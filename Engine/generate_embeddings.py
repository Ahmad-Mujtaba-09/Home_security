"""
First Aid Books — Embedding Generator
=======================================
Standalone script to extract text from PDF books, chunk it, embed using a
LOCAL sentence-transformers model (no API calls), and store to FAISS index.

    python generate_embeddings.py

Outputs:
    Engine/embeddings/faiss.index       — FAISS vector index
    Engine/embeddings/chunks.json       — Chunk metadata (text, source, page)
    Engine/embeddings/bm25_corpus.json  — Tokenized corpus for BM25
"""

import sys
import json
import logging
import re
from pathlib import Path
from typing import List, Dict

import numpy as np

# ─── Setup ────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s"
)
logger = logging.getLogger("embedding-generator")

ENGINE_DIR = Path(__file__).resolve().parent
BOOKS_DIR = ENGINE_DIR.parent / "books"
EMBEDDINGS_DIR = ENGINE_DIR / "embeddings"

# Local embedding model — runs on CPU, no API key needed
# all-MiniLM-L6-v2: 384 dims, ~80MB, fast, good accuracy
EMBED_MODEL_NAME = "all-MiniLM-L6-v2"


# ─── 1. PDF Text Extraction ──────────────────────────────────────────────────

def extract_text_from_pdfs(books_dir: Path) -> List[Dict]:
    """Extract text from all PDFs with page-level granularity."""
    import fitz  # PyMuPDF

    documents = []
    pdf_files = sorted(books_dir.glob("*.pdf"))

    if not pdf_files:
        logger.error(f"No PDF files found in {books_dir}")
        sys.exit(1)

    for pdf_path in pdf_files:
        logger.info(f"Extracting: {pdf_path.name}")
        try:
            doc = fitz.open(str(pdf_path))
            page_count = len(doc)
            for page_num in range(page_count):
                page = doc[page_num]
                text = page.get_text("text")
                text = _clean_text(text)
                if len(text.strip()) > 50:
                    documents.append({
                        "text": text,
                        "source": pdf_path.name,
                        "page": page_num + 1,
                    })
            doc.close()
            logger.info(f"  → {pdf_path.name}: extracted {page_count} pages")
        except Exception as e:
            logger.error(f"  ✗ Failed to extract {pdf_path.name}: {e}")

    logger.info(f"Total document pages extracted: {len(documents)}")
    return documents


def _clean_text(text: str) -> str:
    """Clean extracted PDF text."""
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', text)
    return text.strip()


# ─── 2. Intelligent Chunking ─────────────────────────────────────────────────

def chunk_documents(documents: List[Dict],
                    chunk_size: int = 800,
                    chunk_overlap: int = 200) -> List[Dict]:
    """
    Recursive character-level chunking with overlap.
    Preserves source/page metadata per chunk.
    """
    chunks = []
    separators = ["\n\n", "\n", ". ", "! ", "? ", "; ", ", ", " "]

    for doc in documents:
        text = doc["text"]
        doc_chunks = _recursive_split(text, chunk_size, chunk_overlap, separators)

        for i, chunk_text in enumerate(doc_chunks):
            if len(chunk_text.strip()) < 30:
                continue
            chunks.append({
                "text": chunk_text.strip(),
                "source": doc["source"],
                "page": doc["page"],
                "chunk_index": i,
            })

    logger.info(f"Total chunks created: {len(chunks)}")
    return chunks


def _recursive_split(text: str, chunk_size: int, chunk_overlap: int,
                     separators: List[str]) -> List[str]:
    """Split text recursively using a hierarchy of separators."""
    if len(text) <= chunk_size:
        return [text]

    sep = ""
    for s in separators:
        if s in text:
            sep = s
            break

    if not sep:
        chunks = []
        start = 0
        while start < len(text):
            end = min(start + chunk_size, len(text))
            chunks.append(text[start:end])
            start = end - chunk_overlap
        return chunks

    parts = text.split(sep)
    chunks = []
    current = ""

    for part in parts:
        candidate = current + sep + part if current else part
        if len(candidate) <= chunk_size:
            current = candidate
        else:
            if current:
                chunks.append(current)
            if len(part) > chunk_size:
                remaining_seps = separators[separators.index(sep) + 1:] if sep in separators else separators[-1:]
                sub_chunks = _recursive_split(part, chunk_size, chunk_overlap, remaining_seps)
                chunks.extend(sub_chunks)
                current = ""
            else:
                current = part

    if current:
        chunks.append(current)

    if chunk_overlap > 0 and len(chunks) > 1:
        overlapped = [chunks[0]]
        for i in range(1, len(chunks)):
            prev = chunks[i - 1]
            overlap_text = prev[-chunk_overlap:] if len(prev) > chunk_overlap else prev
            overlapped.append(overlap_text + sep + chunks[i])
        chunks = overlapped

    return chunks


# ─── 3. Local Embedding (sentence-transformers) ──────────────────────────────

def embed_chunks(chunks: List[Dict]) -> np.ndarray:
    """
    Embed text chunks using a local sentence-transformers model.
    No API calls — runs entirely on CPU. Fast and free.
    """
    from sentence_transformers import SentenceTransformer

    logger.info(f"Loading local embedding model: {EMBED_MODEL_NAME}")
    model = SentenceTransformer(EMBED_MODEL_NAME)

    texts = [c["text"] for c in chunks]
    logger.info(f"Embedding {len(texts)} chunks locally (this may take a minute)...")

    embeddings = model.encode(
        texts,
        batch_size=64,
        show_progress_bar=True,
        normalize_embeddings=True,  # L2 normalize for cosine similarity
    )

    embeddings = np.array(embeddings, dtype=np.float32)
    logger.info(f"Embedding matrix shape: {embeddings.shape}")
    return embeddings


# ─── 4. Build FAISS Index + BM25 Corpus ──────────────────────────────────────

def build_and_save(chunks: List[Dict], embeddings: np.ndarray):
    """Build FAISS index and BM25 tokenized corpus, save to disk."""
    import faiss

    EMBEDDINGS_DIR.mkdir(parents=True, exist_ok=True)

    # FAISS index (inner product = cosine sim on normalized vectors)
    dim = embeddings.shape[1]
    index = faiss.IndexFlatIP(dim)
    index.add(embeddings)
    faiss.write_index(index, str(EMBEDDINGS_DIR / "faiss.index"))
    logger.info(f"FAISS index saved: {index.ntotal} vectors, dim={dim}")

    # Chunk metadata
    with open(EMBEDDINGS_DIR / "chunks.json", "w", encoding="utf-8") as f:
        json.dump(chunks, f, ensure_ascii=False, indent=1)
    logger.info(f"Chunk metadata saved: {len(chunks)} chunks")

    # BM25 tokenized corpus
    tokenized_corpus = []
    for chunk in chunks:
        tokens = _tokenize_for_bm25(chunk["text"])
        tokenized_corpus.append(tokens)

    with open(EMBEDDINGS_DIR / "bm25_corpus.json", "w", encoding="utf-8") as f:
        json.dump(tokenized_corpus, f)
    logger.info("BM25 corpus saved")


def _tokenize_for_bm25(text: str) -> List[str]:
    """Simple whitespace + punctuation tokenizer for BM25."""
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


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    logger.info("=" * 60)
    logger.info("First Aid Books — Embedding Generator")
    logger.info(f"Using LOCAL model: {EMBED_MODEL_NAME} (no API calls)")
    logger.info("=" * 60)

    documents = extract_text_from_pdfs(BOOKS_DIR)
    chunks = chunk_documents(documents)
    embeddings = embed_chunks(chunks)
    build_and_save(chunks, embeddings)

    logger.info("=" * 60)
    logger.info("✅ Embedding generation complete!")
    logger.info(f"   Index:    {EMBEDDINGS_DIR / 'faiss.index'}")
    logger.info(f"   Chunks:   {EMBEDDINGS_DIR / 'chunks.json'}")
    logger.info(f"   BM25:     {EMBEDDINGS_DIR / 'bm25_corpus.json'}")
    logger.info("=" * 60)


if __name__ == "__main__":
    main()
