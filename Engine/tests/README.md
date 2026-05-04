# Engine tests

```bash
cd Engine
pip install pytest pytest-asyncio httpx
pytest
```

- `test_falldetection_v1.py` — unit tests for pure helpers (geometry, feature
  engineering, heuristic state, person classification). No model weights
  required.
- `test_main.py` — FastAPI integration tests via `TestClient`. Supabase, the
  inference engine, and the RAG service are mocked.
- `test_rag_service.py` — RAG pipeline tests with FAISS / sentence-transformers
  / Groq HTTP all mocked.

## Mobile app

```bash
cd mobile_app
flutter test
```

- `test/models_test.dart` — `UserProfile` / `HistoryEvent` JSON round-trip and
  display helpers.
- `test/api_service_test.dart` — `ApiService` server-URL persistence using the
  in-memory `SharedPreferences` mock.
