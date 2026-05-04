"""
Integration tests for the FastAPI surveillance app (main.py).

Heavy startup is bypassed: we replace `inference_system`, `supabase`, and
`rag_service` with mocks via FastAPI's TestClient lifespan, so the suite
runs without GPU, weights, or network.
"""
from unittest.mock import MagicMock, AsyncMock, patch

import pytest
from fastapi.testclient import TestClient

import main as app_module


@pytest.fixture
def client(monkeypatch):
    # Skip the real on_startup so we don't try to load weights / open Supabase.
    monkeypatch.setattr(app_module, "startup", AsyncMock())

    # Inject mocks for the module-level globals used by the routes.
    fake_supabase = MagicMock()
    fake_engine = MagicMock()
    fake_rag = MagicMock()
    fake_rag.ready = True
    fake_rag.query = AsyncMock(return_value={"reply": "hi", "sources": []})

    monkeypatch.setattr(app_module, "supabase", fake_supabase)
    monkeypatch.setattr(app_module, "inference_system", fake_engine)
    monkeypatch.setattr(app_module, "rag_service", fake_rag)

    with TestClient(app_module.app) as c:
        c.fake_supabase = fake_supabase
        c.fake_engine = fake_engine
        c.fake_rag = fake_rag
        yield c


# ─── /health ───────────────────────────────────────────────────────────────

def test_health_ok(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["engine_loaded"] is True


# ─── /api/profile ──────────────────────────────────────────────────────────

def test_profile_returns_defaults_when_query_fails(client):
    client.fake_supabase.table.side_effect = Exception("db down")
    resp = client.get("/api/profile", params={"user_id": "u1"})
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["child_module_enabled"] is True
    assert data["elderly_module_enabled"] is True


def test_profile_returns_db_row(client):
    fake_resp = MagicMock()
    fake_resp.data = {"id": "u1", "child_module_enabled": False, "elderly_module_enabled": True}
    (client.fake_supabase.table.return_value
        .select.return_value
        .eq.return_value
        .single.return_value
        .execute.return_value) = fake_resp
    resp = client.get("/api/profile", params={"user_id": "u1"})
    assert resp.status_code == 200
    assert resp.json()["data"]["child_module_enabled"] is False


# ─── /api/history ──────────────────────────────────────────────────────────

def test_history_no_db(client, monkeypatch):
    monkeypatch.setattr(app_module, "supabase", None)
    resp = client.get("/api/history", params={"user_id": "u1"})
    assert resp.status_code == 503


def test_history_returns_data(client):
    fake_resp = MagicMock()
    fake_resp.data = [{"id": "1", "event_type": "FALL"}]
    (client.fake_supabase.table.return_value
        .select.return_value
        .eq.return_value
        .order.return_value
        .limit.return_value
        .execute.return_value) = fake_resp
    resp = client.get("/api/history", params={"user_id": "u1"})
    assert resp.status_code == 200
    assert resp.json()["data"][0]["event_type"] == "FALL"


# ─── /api/chat ─────────────────────────────────────────────────────────────

def test_chat_empty_message(client):
    resp = client.post("/api/chat", json={"message": "  ", "user_id": "u1"})
    assert resp.status_code == 200
    assert "Please enter a message" in resp.json()["reply"]


def test_chat_rag_not_ready(client):
    client.fake_rag.ready = False
    resp = client.post("/api/chat", json={"message": "burns", "user_id": "u1"})
    assert resp.status_code == 200
    assert "knowledge base is not loaded" in resp.json()["reply"]


def test_chat_calls_rag_query(client):
    client.fake_rag.ready = True
    client.fake_rag.query = AsyncMock(
        return_value={"reply": "Apply pressure.", "sources": [{"book": "x", "page": 1}]}
    )
    resp = client.post(
        "/api/chat",
        json={"message": "bleeding?", "user_id": "u1", "history": []},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["reply"] == "Apply pressure."
    assert body["sources"][0]["page"] == 1


# ─── /api/gemini-report ────────────────────────────────────────────────────

def test_gemini_report_no_groq_key(client, monkeypatch):
    monkeypatch.delenv("GROQ_API_KEY", raising=False)
    resp = client.get("/api/gemini-report", params={"user_id": "u1"})
    assert resp.status_code == 200
    assert "GROQ_API_KEY" in resp.json()["report"]


def test_gemini_report_no_events(client, monkeypatch):
    monkeypatch.setenv("GROQ_API_KEY", "test-key")
    fake_resp = MagicMock()
    fake_resp.data = []
    (client.fake_supabase.table.return_value
        .select.return_value
        .eq.return_value
        .gte.return_value
        .order.return_value
        .execute.return_value) = fake_resp
    resp = client.get("/api/gemini-report", params={"user_id": "u1"})
    assert resp.status_code == 200
    assert "No events" in resp.json()["report"]


# ─── _decode_frame helper ──────────────────────────────────────────────────

def test_decode_frame_invalid_bytes_raises():
    with pytest.raises(ValueError):
        app_module._decode_frame(b"not an image")


def test_decode_frame_valid_jpeg():
    import cv2
    import numpy as np
    img = np.zeros((10, 10, 3), dtype=np.uint8)
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    out = app_module._decode_frame(buf.tobytes())
    assert out.shape == (10, 10, 3)
