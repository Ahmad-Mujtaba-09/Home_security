# Engine Tests

## Python (Backend)

```bash
cd Engine
pip install pytest pytest-asyncio httpx
pytest
```

**42 tests** across 3 files:

### `test_falldetection_v1.py` (15 tests)

Unit tests for pure functions — no model weights required:

- **Calibrated heuristic score** — unit interval, ordering invariants, threshold checks
- **Geometry helpers** — `bbox_centre`, `proximity`, `kp_to_bbox` with edge cases
- **Feature engineering** — `_jangle`, `interpolate_and_smooth`, `extract_features` shape validation
- **Heuristic classifier** — state reset, unknown keypoint handling
- **Person classification** — `classify_person_type` label/score, missing keypoints, short torso
- **State swap** — `save_state()` / `load_state()` round-trip, key structure, multi-device independence

### `test_main.py` (18 tests)

FastAPI integration tests via `TestClient`. Supabase, inference engine, RAG service, and device monitor are all mocked:

- **Health** — endpoint returns OK
- **Profile** — DB failure fallback, successful fetch
- **History** — no-DB 503, data retrieval
- **Chat** — empty message, RAG not ready, full pipeline call
- **Gemini report** — missing key, no events
- **`_decode_frame`** — invalid bytes, valid JPEG
- **Device monitor** — start success, no stream URL (400), not found (404), stop, status polling
- **Auto-start/stop** — create device auto-starts if active, no autostart if inactive, delete stops monitor

### `test_rag_service.py` (9 tests)

RAG pipeline tests with FAISS, sentence-transformers, and Groq HTTP all mocked:

- **Tokenizer** — lowercasing, punctuation, stopwords, single-char drops
- **BM25 search** — ranked results, empty query
- **Dense search** — index-score tuples, negative index filtering
- **RRF fusion** — dense+sparse merge, out-of-range skipping
- **Hybrid retrieval** — top-k results
- **Async query** — not ready, missing key, full pipeline, Groq error handling

---

## Flutter (mobile_app)

```bash
cd mobile_app
flutter test
```

**28 tests** across 3 files:

### `test/models_test.dart` (26 tests)

All 7 data models:

- **UserProfile** — `fromJson`, defaults, `toJson` round-trip, `copyWith`
- **HistoryEvent** — `fromJson`, `displayLabel`, `notificationBody`, null handling
- **Device** — `fromJson`, defaults, `toCreateJson` (empty field omission)
- **NotificationItem** — `fromJson`, defaults, `copyWith`
- **IncidentSummary** — `fromJson`, default `incident_count`
- **ChatSession** — `fromJson`, null optionals
- **ChatMessage** — `fromJson`, null sources

### `test/api_service_test.dart` (4 tests)

Server URL persistence using in-memory `SharedPreferences` mock:
- Default empty, trimming, trailing slash removal, clearing

### `test/widget_test.dart`

Smoke test (placeholder — Supabase requires `.env` at runtime).

---

## Flutter (chrome_app)

```bash
cd chrome_app
flutter test
flutter analyze
```

Smoke test only — the Chrome app's integration behaviour is covered through the Python backend tests.
