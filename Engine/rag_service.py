"""
RAG Service — Retrieval-Augmented Generation
==============================================
Hybrid retrieval (FAISS dense + BM25 sparse) with Reciprocal Rank Fusion.
Answer generation via Groq API (free tier, generous rate limits).

Uses:
  - Local sentence-transformers for query embedding (lazy-loaded)
  - Groq API for answer generation (llama-3.1-8b-instant)
  - FAISS + BM25 for hybrid retrieval

Loaded at FastAPI startup from pre-built embeddings.
"""

import re
import json
import logging
from pathlib import Path
from typing import List, Dict, Optional, Tuple
import os

import numpy as np
import httpx

logger = logging.getLogger("rag-service")

ENGINE_DIR = Path(__file__).resolve().parent
EMBEDDINGS_DIR = ENGINE_DIR / "embeddings"

# Local embedding model (same as used during index building)
EMBED_MODEL_NAME = "all-MiniLM-L6-v2"

# Minimum dense cosine similarity for the corpus to be considered relevant to a
# query at all. Retrieval always returns top_k by rank, so without a floor an
# off-topic question still drags back its six least-bad chunks. Measured against
# this index, off-topic queries peak at ~0.18 and on-topic ones bottom out at
# ~0.52, so 0.35 sits in empty space between the two. Re-measure if the
# embedding model or corpus changes — the number is calibrated, not universal.
MIN_RELEVANCE_SCORE = 0.35


class RAGService:
    """RAG pipeline: local retrieval + Groq API generation."""

    def __init__(self):
        self._index = None       # FAISS index
        self._chunks = []        # Chunk metadata
        self._bm25 = None        # BM25 model
        self._tokenized_corpus = []
        self._embed_model = None  # Local sentence-transformers (lazy)
        self._ready = False
        # Groq config
        self.groq_key = os.getenv("GROQ_API_KEY", "")
        self.groq_model = os.getenv("GROQ_MODEL", "llama-3.1-8b-instant")

    def load(self) -> bool:
        """Load pre-built FAISS index and BM25 corpus."""
        index_path = EMBEDDINGS_DIR / "faiss.index"
        chunks_path = EMBEDDINGS_DIR / "chunks.json"
        bm25_path = EMBEDDINGS_DIR / "bm25_corpus.json"

        if not index_path.exists():
            logger.warning(f"FAISS index not found at {index_path}. "
                          f"Run `python generate_embeddings.py` first.")
            return False

        try:
            import faiss
            from rank_bm25 import BM25Okapi

            # Load FAISS
            self._index = faiss.read_index(str(index_path))
            logger.info(f"FAISS index loaded: {self._index.ntotal} vectors")

            # Load chunk metadata
            with open(chunks_path, "r", encoding="utf-8") as f:
                self._chunks = json.load(f)
            logger.info(f"Loaded {len(self._chunks)} chunks")

            # Load BM25 corpus
            with open(bm25_path, "r", encoding="utf-8") as f:
                self._tokenized_corpus = json.load(f)
            self._bm25 = BM25Okapi(self._tokenized_corpus)
            logger.info("BM25 index built from saved corpus")

            # NOTE: sentence-transformers model is lazy-loaded on first query
            self._ready = True
            logger.info("✅ RAG Service ready (embedding model lazy-loaded)")
            return True

        except Exception as e:
            logger.error(f"Failed to load RAG service: {e}")
            return False

    @property
    def ready(self) -> bool:
        return self._ready

    # ─── Main Query Pipeline ─────────────────────────────────────────────────

    async def query(self, user_message: str,
                    chat_history: Optional[List[Dict]] = None,
                    top_k: int = 6) -> Dict:
        """
        Full RAG pipeline:
        1. Hybrid retrieval (FAISS + BM25) — fully local
        2. Reciprocal Rank Fusion
        3. Relevance gate — bail out if nothing in the corpus is close enough
        4. Answer generation via Groq API
        """
        if not self._ready:
            return {
                "reply": "The First Aid knowledge base is not loaded. "
                         "Please run `python generate_embeddings.py` first.",
                "sources": []
            }

        if not self.groq_key:
            return {
                "reply": "⚠️ GROQ_API_KEY not set. Get a free key at https://console.groq.com",
                "sources": []
            }

        try:
            # Step 1: Hybrid retrieval (local)
            candidates, best_score = self._hybrid_retrieve(
                user_message, top_k=top_k * 3
            )
            top_candidates = candidates[:top_k]

            # Step 2: Relevance gate. Answering off-topic questions is not this
            # bot's job, and passing junk context to the model just invites it
            # to improvise a referral elsewhere.
            if not top_candidates or best_score < MIN_RELEVANCE_SCORE:
                logger.info(
                    f"Query below relevance floor (best={best_score:.3f}): {user_message[:60]!r}"
                )
                return {
                    "reply": "I couldn't find anything about that in the first aid "
                             "references. Try asking about an injury, emergency, or "
                             "health concern.",
                    "sources": []
                }

            # Step 3: Generate answer via Groq
            reply, sources = await self._generate_answer(
                user_message, top_candidates, chat_history
            )
            return {"reply": reply, "sources": sources}

        except Exception as e:
            logger.error(f"RAG query error: {e}")
            return {
                "reply": f"I encountered an error: {str(e)}. Please try again.",
                "sources": []
            }

    # ─── Hybrid Retrieval (fully local) ──────────────────────────────────────

    def _hybrid_retrieve(self, query: str,
                         top_k: int = 18) -> Tuple[List[Dict], float]:
        """FAISS + BM25 with Reciprocal Rank Fusion.

        Also returns the best dense cosine similarity, which is the only honest
        relevance signal available here: RRF scores are rank-derived
        (1/(60+rank)), so the top chunk scores the same whether it is a perfect
        match or the least-bad of a bad lot.
        """
        half_k = max(top_k, 10)
        dense_results = self._dense_search(query, top_k=half_k)
        sparse_results = self._bm25_search(query, top_k=half_k)
        fused = self._reciprocal_rank_fusion(dense_results, sparse_results, k=60)
        best_score = max((s for _, s in dense_results), default=0.0)
        return fused[:top_k], best_score

    def _dense_search(self, query: str, top_k: int = 10) -> List[Tuple[int, float]]:
        """Search FAISS index with local query embedding (lazy-loads model)."""
        try:
            if self._embed_model is None:
                from sentence_transformers import SentenceTransformer
                logger.info(f"Lazy-loading embedding model: {EMBED_MODEL_NAME}")
                self._embed_model = SentenceTransformer(EMBED_MODEL_NAME)
                logger.info("Embedding model loaded")

            query_vec = self._embed_model.encode(
                [query], normalize_embeddings=True
            ).astype(np.float32)

            scores, indices = self._index.search(query_vec, top_k)
            results = []
            for idx, score in zip(indices[0], scores[0]):
                if idx >= 0:
                    results.append((int(idx), float(score)))
            return results
        except Exception as e:
            logger.error(f"Dense search error: {e}")
            return []

    def _bm25_search(self, query: str, top_k: int = 10) -> List[Tuple[int, float]]:
        """Search BM25 index."""
        tokens = self._tokenize(query)
        if not tokens:
            return []
        scores = self._bm25.get_scores(tokens)
        top_indices = np.argsort(scores)[::-1][:top_k]
        return [(int(idx), float(scores[idx])) for idx in top_indices if scores[idx] > 0]

    def _reciprocal_rank_fusion(self,
                                 dense_results: List[Tuple[int, float]],
                                 sparse_results: List[Tuple[int, float]],
                                 k: int = 60) -> List[Dict]:
        """Merge dense and sparse results using RRF."""
        rrf_scores = {}
        for rank, (idx, _) in enumerate(dense_results):
            rrf_scores[idx] = rrf_scores.get(idx, 0.0) + 1.0 / (k + rank + 1)
        for rank, (idx, _) in enumerate(sparse_results):
            rrf_scores[idx] = rrf_scores.get(idx, 0.0) + 1.0 / (k + rank + 1)

        sorted_indices = sorted(rrf_scores.keys(),
                                key=lambda x: rrf_scores[x], reverse=True)
        results = []
        for idx in sorted_indices:
            if idx < len(self._chunks):
                chunk = self._chunks[idx].copy()
                chunk["rrf_score"] = rrf_scores[idx]
                results.append(chunk)
        return results

    # ─── Answer Generation (Groq API) ────────────────────────────────────────

    async def _generate_answer(self, query: str, context_chunks: List[Dict],
                                chat_history: Optional[List[Dict]] = None
                                ) -> Tuple[str, List[Dict]]:
        """Generate a grounded answer using Groq API."""
        context_parts = []
        for i, chunk in enumerate(context_chunks):
            source_ref = f"{chunk['source']}, p.{chunk['page']}"
            context_parts.append(f"[Source {i+1}: {source_ref}]\n{chunk['text']}")

        context_block = "\n\n---\n\n".join(context_parts)

        history_block = ""
        if chat_history:
            history_lines = []
            for msg in chat_history[-6:]:
                role = msg.get("role", "user")
                text = msg.get("text", "")[:200]
                history_lines.append(f"{role.upper()}: {text}")
            history_block = "\n".join(history_lines)

        system_msg = (
            "You are a knowledgeable First Aid assistant powered by official first aid manuals. "
            "RULES: 1) Base answers on the provided references. 2) If info not in references, say so. "
            "3) For serious situations, recommend calling 911/112. 4) Use numbered steps. "
            "5) Cite sources as [Source N]. 6) Never diagnose — only first aid guidance."
        )

        user_msg = f"REFERENCE MATERIAL:\n{context_block}\n\n"
        if history_block:
            user_msg += f"CHAT HISTORY:\n{history_block}\n\n"
        user_msg += f"QUESTION: {query}"

        try:
            async with httpx.AsyncClient(timeout=30) as client:
                resp = await client.post(
                    "https://api.groq.com/openai/v1/chat/completions",
                    headers={"Authorization": f"Bearer {self.groq_key}"},
                    json={
                        "model": self.groq_model,
                        "messages": [
                            {"role": "system", "content": system_msg},
                            {"role": "user", "content": user_msg},
                        ],
                        "temperature": 0.3,
                        "max_tokens": 1024,
                    },
                )
                resp.raise_for_status()
                reply = resp.json()["choices"][0]["message"]["content"]

            # Prefer the passages the model actually cited. It cites
            # inconsistently, so fall back to everything it was shown — safe
            # only because the relevance gate already rejected off-topic
            # queries, so these chunks are known to be on-subject.
            sources = self._cited_sources(reply, context_chunks)
            if not sources:
                sources = self._all_sources(context_chunks)
            return reply, sources

        except Exception as e:
            logger.error(f"Groq generation error: {e}")
            return (f"Error generating response: {str(e)}", [])

    # ─── Citation parsing ────────────────────────────────────────────────────

    @staticmethod
    def _cited_sources(reply: str, context_chunks: List[Dict]) -> List[Dict]:
        """Map [Source N] citations in the reply back to their chunks.

        N is 1-based and matches the numbering handed to the model in the
        prompt. Handles the shapes the model actually emits — [Source 1],
        [Source 1, 2, 3], [Sources 1 and 2], [Source 1][Source 2]. Numbers
        outside the range of what was retrieved are dropped rather than
        trusted, since a hallucinated citation index is not evidence.
        """
        cited = set()
        for span in re.findall(r"\[Sources?\b[^\]]*\]", reply):
            cited.update(int(n) for n in re.findall(r"\d+", span))
        return RAGService._all_sources(
            [context_chunks[i - 1] for i in cited if 1 <= i <= len(context_chunks)]
        )

    @staticmethod
    def _all_sources(chunks: List[Dict]) -> List[Dict]:
        """Deduplicated (book, page) list for the given chunks."""
        source_set = {(c["source"], c["page"]) for c in chunks}
        return [{"book": s[0], "page": s[1]} for s in sorted(source_set)]

    # ─── Tokenizer ────────────────────────────────────────────────────────────

    def _tokenize(self, text: str) -> List[str]:
        """Tokenize text for BM25."""
        text = text.lower()
        text = re.sub(r'[^\w\s]', ' ', text)
        tokens = text.split()
        stopwords = {'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been',
                     'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will',
                     'would', 'could', 'should', 'may', 'might', 'can', 'shall',
                     'to', 'of', 'in', 'for', 'on', 'with', 'at', 'by', 'from',
                     'as', 'into', 'through', 'during', 'before', 'after', 'and',
                     'but', 'or', 'not', 'no', 'if', 'then', 'than', 'that',
                     'this', 'it', 'its', 'he', 'she', 'they', 'we', 'you', 'i',
                     'my', 'your', 'his', 'her', 'their', 'our', 'me', 'him',
                     'them', 'us', 'who', 'which', 'what', 'when', 'where', 'how',
                     'all', 'each', 'every', 'both', 'few', 'more', 'most', 'other',
                     'some', 'such', 'only', 'own', 'same', 'so', 'very', 'just'}
        return [t for t in tokens if len(t) > 1 and t not in stopwords]
