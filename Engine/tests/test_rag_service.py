"""
Unit and integration tests for RAGService.

External dependencies (FAISS, sentence-transformers, Groq HTTP) are mocked.
We only exercise the orchestration code: tokenizer, RRF fusion, BM25 search,
and the async query pipeline.
"""
from unittest.mock import MagicMock, AsyncMock, patch

import numpy as np
import pytest

from rag_service import RAGService


@pytest.fixture
def rag():
    svc = RAGService()
    # Pretend the index is loaded.
    svc._chunks = [
        {"source": "FirstAid.pdf", "page": 1, "text": "Apply pressure to bleeding wounds."},
        {"source": "FirstAid.pdf", "page": 2, "text": "For burns, run cool water over the area."},
        {"source": "Manual.pdf", "page": 5, "text": "Call 911 in case of unconsciousness."},
    ]
    svc._tokenized_corpus = [
        ["apply", "pressure", "bleeding", "wounds"],
        ["burns", "cool", "water", "area"],
        ["call", "911", "unconsciousness"],
    ]

    bm25 = MagicMock()
    bm25.get_scores = MagicMock(return_value=np.array([0.5, 1.2, 0.0]))
    svc._bm25 = bm25

    fake_index = MagicMock()
    fake_index.search = MagicMock(
        return_value=(np.array([[0.9, 0.7]]), np.array([[1, 0]]))
    )
    svc._index = fake_index

    embed = MagicMock()
    embed.encode = MagicMock(return_value=np.zeros((1, 384), dtype=np.float32))
    svc._embed_model = embed

    svc._ready = True
    svc.groq_key = "test-key"
    svc.groq_model = "llama-3.1-8b-instant"
    return svc


# ─── Tokenizer ─────────────────────────────────────────────────────────────

class TestTokenize:
    def test_lowercases_and_strips_punctuation(self):
        svc = RAGService()
        out = svc._tokenize("How do I treat a Burn!?")
        assert "burn" in out
        assert "!" not in " ".join(out)

    def test_drops_stopwords(self):
        svc = RAGService()
        out = svc._tokenize("the burn is on my hand")
        assert "the" not in out
        assert "is" not in out
        assert "burn" in out
        assert "hand" in out

    def test_drops_single_character_tokens(self):
        svc = RAGService()
        assert "a" not in svc._tokenize("a burn")


# ─── BM25 search ──────────────────────────────────────────────────────────

class TestBM25Search:
    def test_returns_ranked_indices(self, rag):
        results = rag._bm25_search("burn cool water", top_k=2)
        assert len(results) <= 2
        assert all(score > 0 for _, score in results)

    def test_empty_query(self, rag):
        # All-stopword query → empty token list → empty results.
        assert rag._bm25_search("the a is", top_k=5) == []


# ─── Dense search ─────────────────────────────────────────────────────────

class TestDenseSearch:
    def test_returns_index_score_tuples(self, rag):
        results = rag._dense_search("burn", top_k=2)
        assert results == [(1, pytest.approx(0.9)), (0, pytest.approx(0.7))]

    def test_filters_negative_indices(self, rag):
        rag._index.search = MagicMock(
            return_value=(np.array([[0.5, 0.2]]), np.array([[0, -1]]))
        )
        out = rag._dense_search("q", top_k=2)
        assert out == [(0, pytest.approx(0.5))]


# ─── RRF fusion ───────────────────────────────────────────────────────────

class TestReciprocalRankFusion:
    def test_fuses_dense_and_sparse(self, rag):
        dense = [(0, 0.9), (1, 0.7)]
        sparse = [(1, 1.2), (2, 0.5)]
        fused = rag._reciprocal_rank_fusion(dense, sparse, k=60)
        # idx 1 appears in both lists → highest score.
        assert fused[0]["page"] == rag._chunks[1]["page"]
        assert {c["page"] for c in fused} == {1, 2, 5}

    def test_skips_out_of_range_indices(self, rag):
        fused = rag._reciprocal_rank_fusion([(99, 1.0)], [], k=60)
        assert fused == []


# ─── Hybrid retrieval ─────────────────────────────────────────────────────

def test_hybrid_retrieve_returns_top_k(rag):
    results = rag._hybrid_retrieve("burn", top_k=2)
    assert len(results) <= 2
    assert all("text" in r for r in results)


# ─── Async query pipeline ────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_query_when_not_ready():
    svc = RAGService()
    svc._ready = False
    out = await svc.query("anything")
    assert "not loaded" in out["reply"]
    assert out["sources"] == []


@pytest.mark.asyncio
async def test_query_missing_groq_key(rag):
    rag.groq_key = ""
    out = await rag.query("burn")
    assert "GROQ_API_KEY" in out["reply"]


@pytest.mark.asyncio
async def test_query_full_pipeline(rag):
    fake_response = MagicMock()
    fake_response.raise_for_status = MagicMock()
    fake_response.json = MagicMock(
        return_value={"choices": [{"message": {"content": "Run cool water."}}]}
    )

    fake_client = MagicMock()
    fake_client.post = AsyncMock(return_value=fake_response)
    fake_client.__aenter__ = AsyncMock(return_value=fake_client)
    fake_client.__aexit__ = AsyncMock(return_value=False)

    with patch("rag_service.httpx.AsyncClient", return_value=fake_client):
        out = await rag.query("how to treat a burn?")

    assert out["reply"] == "Run cool water."
    assert isinstance(out["sources"], list)
    fake_client.post.assert_called_once()


@pytest.mark.asyncio
async def test_query_handles_groq_error(rag):
    fake_client = MagicMock()
    fake_client.post = AsyncMock(side_effect=RuntimeError("boom"))
    fake_client.__aenter__ = AsyncMock(return_value=fake_client)
    fake_client.__aexit__ = AsyncMock(return_value=False)

    with patch("rag_service.httpx.AsyncClient", return_value=fake_client):
        out = await rag.query("burn")

    # Errors during answer generation surface as a graceful reply.
    assert "Error" in out["reply"] or "error" in out["reply"]
