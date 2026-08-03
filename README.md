# 🛡️ IHS — Intelligent Home Surveillance

> **Final Year Project** — real-time fall detection, hazard recognition, child-safety monitoring, background RTSP surveillance, and AI-powered first-aid guidance.

[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white)](https://python.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.2+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Supabase](https://img.shields.io/badge/Supabase-Auth%20%2B%20Postgres-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)

---

## What this is

IHS watches a home's camera feeds and raises an alarm when something goes wrong — someone falls and doesn't get up, a child wanders near a stove or a knife, a fire starts. It is three deployable pieces plus a hosted database:

| Piece | Directory | What it does |
|---|---|---|
| **Engine** | [`Engine/`](Engine/) | Python + FastAPI. Runs all the models, exposes WebSocket inference and a REST API, monitors RTSP streams in the background, sends push notifications. |
| **Chrome app** | [`chrome_app/`](chrome_app/) | Flutter control panel, run in Chrome (`flutter run -d chrome`) or as a Linux/macOS/Windows desktop build. Live camera, file upload, stream processing, device management. |
| **Mobile app** | [`mobile_app/`](mobile_app/) | Flutter companion for Android/iOS. No live inference — alerts, history, device control, AI summaries, first-aid chat. |
| **Database** | [`supabase/`](supabase/) | Supabase (Postgres + Auth + RLS). Schema lives in `supabase/migrations/`. |

### Detection capabilities

| Capability | How |
|---|---|
| **Fall detection** | Hybrid classifier — a 3-layer residual TCN over 30-frame pose windows blended 70/30 with a rule-based biomechanics FSM |
| **Inactivity alert** | Timer fires when a person stays down past a configurable threshold |
| **Hazard detection** | Custom-trained YOLOv8 (`best.pt`) for knife, fire, stairs, oven, stove |
| **Child safety** | Skeleton-ratio age classification + per-hazard proximity thresholds |
| **Background monitoring** | `DeviceMonitorManager` pulls RTSP/HTTP streams server-side at ~2 FPS, independent of any connected client |
| **First-aid chatbot** | RAG over first-aid manuals — FAISS dense + BM25 sparse, fused by RRF, generated with Groq |
| **AI incident reports** | LLM-written caregiver summaries built from the detection history |
| **Push notifications** | Firebase Cloud Messaging (HTTP v1), delivered with the app closed |

---

## Architecture

```
┌──────────────────────────┐        ┌──────────────────────────────────┐
│   mobile_app (Flutter)   │        │   chrome_app (Flutter, Chrome/   │
│   Android · iOS          │        │   Linux · macOS · Windows)       │
│   alerts · history       │        │   live camera · file · RTSP      │
│   devices · AI · chat    │        │   devices · history · AI · chat  │
└────────────┬─────────────┘        └────────────┬─────────────────────┘
             │ REST                              │ REST + WebSocket (frames)
             └──────────────┬────────────────────┘
                            ▼
        ┌───────────────────────────────────────────────┐
        │        Engine — FastAPI  :8000                │
        │  YOLOv8-Pose → features → TCN + heuristic FSM │
        │  hazard YOLO · DeviceMonitorManager           │
        │  RAG service (FAISS + BM25 + Groq) · FCM      │
        └───────────┬───────────────────────┬───────────┘
                    ▼                       ▼
            ┌───────────────┐      ┌────────────────┐
            │   Supabase    │      │    Firebase    │
            │ Auth+Postgres │      │      FCM       │
            └───────────────┘      └────────────────┘
```

Both Flutter clients authenticate directly against Supabase Auth and read tables through PostgREST; everything model-related goes through the Engine.

---

## Repository layout

```
.
├── Engine/                     # Python inference engine + FastAPI backend
│   ├── main.py                   # FastAPI app: WebSockets, REST, DeviceMonitorManager, FCM
│   ├── falldetection_v1.py       # HomeSafetyInference — TCN, heuristic FSM, hazard, child safety
│   ├── rag_service.py            # Hybrid retrieval + Groq generation
│   ├── generate_embeddings.py    # Offline: books/*.pdf → chunks → FAISS index
│   ├── requirements.txt
│   ├── .env                      # Shared config (chrome_app/.env symlinks to this)
│   ├── embeddings/               # Pre-built faiss.index, chunks.json, bm25_corpus.json
│   ├── tests/                    # pytest suite
│   └── testing/                  # Sample videos for manual testing
│
├── chrome_app/                 # Flutter control panel (Chrome / desktop)
│   ├── lib/{core,data,features}/
│   └── .env -> ../Engine/.env
│
├── mobile_app/                 # Flutter mobile companion
│   ├── lib/{core,data,features,theme}/
│   └── .env                      # Its own config (server URL is also settable in-app)
│
├── supabase/migrations/        # Database schema + RLS — run in order
│   ├── 20260505000000_core_schema.sql
│   └── 20260505000001_add_devices_notifications_summaries_chat.sql
│
├── weights/                    # Model weights (git-ignored, not in the repo)
├── books/                      # First-aid PDFs — the RAG knowledge base (git-ignored)
└── docs/                       # Thesis, poster, presentation, training notebook
```

---

## Running it

### Prerequisites

- Python 3.10+
- Flutter SDK ≥ 3.2.0
- A Supabase project (free tier is fine)
- A Groq API key — free at [console.groq.com](https://console.groq.com)
- A Firebase project with FCM enabled (only needed for push notifications)

### 0. Model weights

`weights/` is git-ignored, so a fresh clone will not have it. The Engine expects:

| File | Purpose |
|---|---|
| `weights/tcn_fall_best.pt` | Trained TCN fall classifier |
| `weights/best.pt` | Trained YOLOv8 hazard detector |
| `weights/norm_mean.npy`, `weights/norm_std.npy` | Feature normalisation statistics |
| `weights/sticky_tracker.yaml` | ByteTrack tracker config |
| `weights/yolov8s-pose.pt` | YOLOv8s pose model (Ultralytics downloads this on first run if absent) |

### 1. Database

Run both files, **in filename order**, in the Supabase SQL editor (or `supabase db push`):

```
supabase/migrations/20260505000000_core_schema.sql   # profiles, history, fcm_tokens
supabase/migrations/20260505000001_add_devices_notifications_summaries_chat.sql
```

The first migration installs an `on_auth_user_created` trigger, so every new signup gets a `profiles` row automatically.

### 2. Engine

```bash
cd Engine
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt

cp .env.example .env   # if starting fresh — then fill in the values below

# One-time: build the first-aid FAISS index from books/*.pdf
python generate_embeddings.py

python main.py
```

Serves on `http://0.0.0.0:8000` with autoreload. On startup it re-attaches background monitors to every device whose `status` is `active`. Sanity check: `curl localhost:8000/health`.

Also drop your Firebase service-account JSON at `Engine/firebase-service-account.json` if you want push notifications.

### 3. Chrome app

```bash
cd chrome_app
flutter pub get
flutter run -d chrome
# or: flutter run -d linux | -d macos | -d windows
```

Config is read from `chrome_app/.env`, which is a **symlink to `Engine/.env`** — one file for both. Point `INFERENCE_API_URL` at the Engine (`http://localhost:8000` when both run on the same machine).

### 4. Mobile app

```bash
cd mobile_app
flutter pub get
flutter run          # physical device or emulator
```

The mobile app needs to reach the Engine over the network, so `localhost` will not work from a phone. Either put both on the same LAN and use the machine's IP, or tunnel:

```bash
ngrok http 8000
```

Then set the URL under **Profile → Server Connection** in the app (persisted via `SharedPreferences`), or edit `INFERENCE_API_URL` in `mobile_app/.env` — keep `https://` for REST and `wss://` for WebSocket.

---

## Configuration

`Engine/.env` is the single source of truth for the Engine and the Chrome app:

| Variable | Read by | Description |
|---|---|---|
| `SUPABASE_URL` | both | Supabase project URL |
| `SUPABASE_ANON_KEY` | chrome_app | Public anon key — RLS applies |
| `SUPABASE_SERVICE_ROLE_KEY` | Engine | Service role key — **bypasses RLS**, server-side only |
| `INFERENCE_API_URL` | chrome_app | Engine base URL |
| `CHATBOT_API_URL` | chrome_app | Chat endpoint base URL |
| `GROQ_API_KEY` | Engine | Groq API key |
| `GROQ_MODEL` | Engine | Default `llama-3.1-8b-instant` |

`mobile_app/.env` carries its own `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `INFERENCE_API_URL` and `CHATBOT_API_URL`.

> ⚠️ **Known issue — do not ship as is.** `mobile_app/lib/main.dart` initialises Supabase with `SUPABASE_SERVICE_ROLE_KEY` (falling back to the anon key), and Flutter bundles `.env` as a readable asset. A service-role key inside an APK or a web build is extractable by anyone who has the build, and it bypasses every RLS policy. Both clients should use the anon key only.

---

## How detection works

**Fall detection.** YOLOv8s-Pose extracts 17 COCO keypoints per tracked person. Those become a 61-dim feature vector — hip-centred normalised coordinates, joint angles, velocities, trunk tilt. A 3-layer residual TCN scores a 30-frame sliding window (re-evaluated every 10 frames), in parallel with a rule-based FSM reading trunk angle, hip height, centre-of-gravity velocity and inversion. The two scores blend 70/30, gated so a confirmed heuristic fall cannot be argued away, and a sticky lock adds hysteresis so the state does not oscillate.

**Hazard and child safety.** A separately trained YOLOv8 detects knife, fire, stairs, oven and stove, smoothed over a 5-frame confidence window. Each person is classified child vs. adult by skeleton proportions; a child inside a hazard's distance threshold raises `CHILD_HAZARD`.

**Background monitoring.** `DeviceMonitorManager` runs one asyncio task per active device, sharing the loaded YOLO models while keeping per-device detector state isolated via `save_state()` / `load_state()`. It retries a failed stream 3 times, marks the device `offline` if it cannot recover, and writes detections to history + notifications + FCM exactly as the live path does.

**First-aid RAG.** `generate_embeddings.py` extracts the PDFs in `books/`, chunks them, embeds with `all-MiniLM-L6-v2`, and writes `faiss.index` + `bm25_corpus.json`. At query time dense and sparse hits are fused by Reciprocal Rank Fusion and handed to Groq with the retrieved passages as context.

---

## API

Base URL `http://localhost:8000`.

### WebSocket

| Endpoint | Description |
|---|---|
| `WS /ws/inference/{user_id}` | Live camera frames from a client, annotated frames back |
| `WS /ws/process-video/{user_id}` | Server-side processing of an uploaded video file |
| `WS /ws/stream/{user_id}` | Client-initiated RTSP/HTTP stream processing |

### REST

| Endpoint | Method | Description |
|---|---|---|
| `/health` | GET | Health check |
| `/api/profile` | GET | Profile + module toggles |
| `/api/history` | GET | Detection event history |
| `/api/gemini-report` | GET | AI incident summary (legacy path name — it calls Groq, not Gemini) |
| `/api/summaries` | GET | Previously generated summaries |
| `/api/chat` | POST | First-aid RAG chatbot |
| `/api/chat/sessions` | GET | Chat sessions |
| `/api/chat/sessions/{id}/messages` | GET | Messages in a session |
| `/api/devices` | GET / POST | List / register devices |
| `/api/devices/{id}` | PATCH / DELETE | Update / delete a device |
| `/api/devices/{id}/start` | POST | Start background monitoring |
| `/api/devices/{id}/stop` | POST | Stop background monitoring |
| `/api/devices/{id}/status` | GET | `monitoring` / `stopped` / `error` |
| `/api/notifications` | GET | Notification inbox |
| `/api/notifications/{id}` | PATCH | Mark as read |

Interactive docs at `http://localhost:8000/docs`.

---

## Database schema

| Table | Purpose |
|---|---|
| `profiles` | Per-user theme + child/elderly module toggles. PK = `auth.users.id`, auto-created on signup. |
| `history` | Detection events — `event_type` (`FALL`, `INACTIVITY`, `CHILD_HAZARD`), confidence, frame count. |
| `fcm_tokens` | One Firebase device token per user (unique on `user_id`, upserted by the mobile app). |
| `devices` | Registered cameras/streams — name, type, stream URL, location, status. |
| `notifications` | In-app inbox, one row per alert, with read/unread state. |
| `incident_summaries` | Cached AI incident reports so the UI can replay without re-billing Groq. |
| `chat_sessions` / `chat_messages` | Chatbot conversation history, with retrieved sources stored as JSONB. |

Every table has RLS enabled with owner-scoped policies. The Engine uses the `service_role` key, which bypasses RLS by design.

---

## Tech stack

| Layer | Technology |
|---|---|
| Inference | PyTorch, Ultralytics YOLOv8, OpenCV, SciPy, NumPy |
| Backend | FastAPI, Uvicorn, WebSockets, asyncio |
| RAG | FAISS, rank-bm25, sentence-transformers, Groq API |
| Database | Supabase — Postgres, Auth, RLS |
| Push | Firebase Cloud Messaging HTTP v1 (PyJWT-signed service-account JWT) |
| Clients | Flutter + Provider (`chrome_app` desktop/web, `mobile_app` Android/iOS) |

---

## Tests

```bash
cd Engine
pip install pytest pytest-asyncio httpx
pytest
```

42 tests across three files — Supabase, the inference engine, the RAG service and the device monitor are all mocked, so no weights or network are needed. See [`Engine/tests/README.md`](Engine/tests/README.md).

```bash
cd mobile_app && flutter test
cd chrome_app && flutter analyze
```

---

## License

Developed as a Final Year Project. All rights reserved.
