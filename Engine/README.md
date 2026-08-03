# ⚙️ SafeGuard — Inference Engine

> Python-based real-time inference server: fall detection, hazard recognition, child safety, background device monitoring, and AI-powered first aid guidance.

---

## 📋 Overview

The Engine is the backend intelligence layer of SafeGuard. It runs multi-model inference on video frames received via WebSocket from the Flutter desktop app, processes RTSP/HTTP streams via background monitoring tasks, and serves REST endpoints for event history, device management, AI reports, and a RAG-powered first aid chatbot.

### Key Capabilities

- **Fall Detection** — Hybrid TCN deep learning + heuristic biomechanics classifier
- **Hazard Detection** — YOLOv8 object detection (knife, fire, stairs, oven, stove)
- **Child Safety** — Skeleton-ratio classification + hazard proximity alerts
- **Inactivity Monitoring** — Timer-based alarm for prolonged immobility after falls
- **Background Device Monitoring** — `DeviceMonitorManager` processes RTSP/HTTP streams at ~2 FPS independently of clients
- **First Aid RAG Chatbot** — Hybrid FAISS + BM25 retrieval with Groq LLM generation
- **AI Incident Reports** — LLM-generated caregiver summaries from detection history
- **FCM Push Notifications** — Firebase Cloud Messaging via HTTP v1 API
- **Device Management** — CRUD API for cameras/streams with auto-start/stop monitoring

---

## 📁 File Structure

```
Engine/
├── main.py                        # FastAPI server — WebSocket + REST + DeviceMonitorManager
├── falldetection_v1.py            # Core detection engine (~1000 lines)
│                                    TCN model, heuristic classifier, hazard
│                                    detection, child safety, save/load state
├── rag_service.py                 # RAG pipeline: retrieval + Groq generation
├── generate_embeddings.py         # Offline: PDF → chunks → FAISS index builder
├── requirements.txt               # Python dependencies
├── .env                           # Environment variables (git-ignored)
├── .env.example                   # Template — copy to .env and fill in
├── firebase-service-account.json  # FCM service account (git-ignored)
│
├── embeddings/                    # Pre-built search indices (git-ignored)
│   ├── faiss.index                  # Dense vector index
│   ├── chunks.json                  # Chunk metadata (text, source, page)
│   └── bm25_corpus.json             # Tokenized corpus for sparse retrieval
│
├── tests/                         # Python test suite (pytest)
│   ├── conftest.py                  # Path setup fixtures
│   ├── test_main.py                 # FastAPI integration tests (18 tests)
│   ├── test_falldetection_v1.py     # Detection helpers + state swap tests (15 tests)
│   └── test_rag_service.py          # RAG pipeline tests (9 tests)
│
└── testing/                       # Sample videos for manual testing (git-ignored)
```

Sibling directories the Engine depends on: `../weights/` (model files), `../books/`
(source PDFs for the RAG index), and `../supabase/migrations/` (database schema).
The Flutter clients live in `../chrome_app/` and `../mobile_app/`.

---

## 🚀 Getting Started

### Prerequisites

- Python 3.10+
- 4GB+ RAM (models load ~200MB)
- CUDA GPU (optional — CPU inference works but is slower)

### Installation

```bash
cd Engine
python -m venv venv
source venv/bin/activate       # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### Environment Setup

```bash
cp .env.example .env
```

`Engine/.env` is shared with the Chrome app — `chrome_app/.env` is a symlink to it,
so it holds both sets of keys:

```env
# Read by the Engine
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...      # bypasses RLS — server-side only
GROQ_API_KEY=gsk_...
GROQ_MODEL=llama-3.1-8b-instant

# Read by chrome_app
SUPABASE_ANON_KEY=eyJ...
INFERENCE_API_URL=http://localhost:8000
CHATBOT_API_URL=http://localhost:8000
```

### Database Setup (One-Time)

Run both migrations, in filename order, in the Supabase SQL editor:

```
../supabase/migrations/20260505000000_core_schema.sql
../supabase/migrations/20260505000001_add_devices_notifications_summaries_chat.sql
```

### Build the RAG Index (One-Time)

```bash
python generate_embeddings.py
```

This reads PDFs from `../books/`, chunks them, embeds locally with `all-MiniLM-L6-v2`, and saves the FAISS index + BM25 corpus to `embeddings/`.

### Start the Server

```bash
python main.py
# → Uvicorn starts on http://0.0.0.0:8000
# → Active devices auto-start background monitoring
```

---

## 🔌 API Reference

### WebSocket Endpoints

#### `WS /ws/inference/{user_id}`

Real-time camera frame inference.

- **Client sends:** Binary JPEG frame **or** JSON `{"image": "<base64>"}`
- **Server sends:** `{"alerts": [...], "detections": [...], "frame": N}`
- Profile-aware: respects `child_module_enabled` / `elderly_module_enabled` toggles
- Auto-refreshes profile every 60 frames

#### `WS /ws/process-video/{user_id}`

Server-side video file processing with annotated frame streaming.

- **Client sends:** JSON `{"video": "<base64>", "filename": "..."}`
- **Server sends:** `{"alerts": [...], "frame": N, "total_frames": N, "annotated_frame": "<base64>", "status": "processing"}`
- Final message: `{"status": "done", "total_frames": N, "total_alerts": N}`

#### `WS /ws/stream/{user_id}`

RTSP/HTTP stream processing.

- **Client sends:** JSON `{"url": "rtsp://..."}`
- **Server sends:** Annotated frames + alerts per frame

### REST Endpoints — Core

| Endpoint | Method | Description |
|---|---|---|
| `/health` | GET | Health check (`{"status": "ok"}`) |
| `/api/history?user_id=` | GET | User's detection event history (last 200) |
| `/api/profile?user_id=` | GET | User profile and module toggles |
| `/api/gemini-report?user_id=` | GET | AI-generated incident summary (last 1 hour) |
| `/api/chat` | POST | RAG chatbot. Body: `{"message": str, "user_id": str, "history": [...]}` |

### REST Endpoints — Device Management

| Endpoint | Method | Description |
|---|---|---|
| `/api/devices?user_id=` | GET | List user's registered devices |
| `/api/devices` | POST | Register a new device (auto-starts if status = "active") |
| `/api/devices/{id}` | PATCH | Update device settings (auto-starts/stops on status change) |
| `/api/devices/{id}` | DELETE | Delete device (auto-stops monitoring) |
| `/api/devices/{id}/start` | POST | Start background monitoring for a device |
| `/api/devices/{id}/stop` | POST | Stop background monitoring |
| `/api/devices/{id}/status` | GET | Get monitor status: `monitoring`, `stopped`, `connecting`, `error` |

### REST Endpoints — Notifications, Summaries, Chat

| Endpoint | Method | Description |
|---|---|---|
| `/api/notifications?user_id=` | GET | List notifications (`&unread_only=true` supported) |
| `/api/notifications/{id}` | PATCH | Mark notification as read |
| `/api/summaries?user_id=` | GET | List cached AI incident summaries |
| `/api/chat/sessions?user_id=` | GET | List user's chat sessions |
| `/api/chat/sessions/{id}/messages` | GET | Get messages for a chat session |

---

## 🧠 Detection Pipeline Deep Dive

### 1. Pose Estimation

- **Model:** YOLOv8s-Pose, loaded by bare name (`yolov8s-pose.pt`) — Ultralytics resolves it
  from the working directory and downloads it there on first run if missing. A copy is also
  kept in `../weights/`.
- **Output:** 17 COCO keypoints per person with confidence scores
- **Tracking:** ByteTrack for persistent person IDs, tuned in `../weights/sticky_tracker.yaml`
  (`track_buffer: 150`, `match_thresh: 0.95`) so IDs survive a person lying still
- **Optimisation:** Frame decimation (2× skip) + motion gating (~500px threshold)

### 2. Fall Detection — TCN

- **Architecture:** 3-layer Residual TCN (128 channels) with 1D dilated convolutions
- **Input:** 30-frame sliding window → 61-dimensional feature vectors per frame
- **Features:** Hip-centred normalisation, 8 joint angles, 17 keypoint velocities, trunk tilt + lean
- **Preprocessing:** Savitzky-Golay smoothing, linear interpolation for missing keypoints
- **Stride:** Runs every 10 frames; cached probability used between runs

### 3. Fall Detection — Heuristic Classifier

Rule-based finite state machine using:
- Trunk angle (shoulder→hip vector)
- Hip height relative to frame
- Hip descent velocity
- Centre-of-gravity velocity and stability
- Head-below-hips inversion detection
- Debounce counter for state transitions

**States:** `STANDING` → `WALKING` → `UNSTABLE` → `PRE_FALL` → `FALLING` → `FALL` → `LYING`

### 4. Score Blending (Hybrid Mode)

```
P_final = 0.70 × P_tcn + 0.30 × P_heuristic
```

- **Gating:** For `FALL`/`FALLING`, final score is `max(blend, heuristic_score)` — heuristic can independently trigger
- **Inversion boost:** 5 consecutive head-below-hips frames → score forced to ≥0.98
- **Threshold:** Default 0.65 (configurable)

### 5. Hazard Detection

- **Model:** Custom-trained YOLOv8 (`../weights/best.pt`). An OpenVINO GPU compile path
  exists (`_compile_openvino_for_gpu`) but is currently commented out.
- **Classes:** knife (0.40), fire (0.50), stairs (0.30), oven (0.25), stove (0.25) — per-class confidence thresholds
- **Temporal smoothing:** 5-frame sliding window with confidence bonus for persistent detections
- **Child proximity:** Normalised distance thresholds per hazard type (e.g., knife: 0.18, fire: 0.30)

### 6. Child/Adult Classification

- **Primary:** Leg-to-torso skeleton ratio (< 0.75 → CHILD)
- **Small person boost:** If bounding box < 35% of frame height, ratio threshold raised to 0.85
- **Sticky lock:** 15-frame hysteresis prevents classification flicker

### 7. Background Device Monitoring

- **`DeviceMonitorManager`** creates one `asyncio.Task` per device
- **Shared models:** All devices share the same YOLO weights via `asyncio.Lock`
- **State isolation:** `save_state()` / `load_state()` on `HomeSafetyInference` swaps per-device tracking state
- **Processing rate:** ~2 FPS per device (configurable)
- **Auto-resume:** All devices with `status='active'` auto-start on server boot
- **Auto-reconnect:** 3 retries on stream failure, updates device status to `offline` on exhaustion
- **Logging:** Detections auto-logged to `history` table + FCM push sent to user

### 8. RAG First Aid Chatbot

```
PDF Books → PyMuPDF extraction → Recursive chunking (800 chars, 200 overlap)
         → all-MiniLM-L6-v2 embedding → FAISS IndexFlatIP

Query → Hybrid retrieval (FAISS + BM25) → RRF fusion → Top-6 chunks
     → Groq API (llama-3.1-8b) → Grounded answer with source citations
```

---

## 🗄️ Database

### Tables

| Table | Description |
|---|---|
| `profiles` | User preferences. PK = `auth.users.id`. Fields: `light_mode`, `child_module_enabled`, `elderly_module_enabled`. |
| `history` | Detection events. Fields: `event_type`, `confidence`, `frame_count`, `timestamp`. Indexed: `(user_id, timestamp DESC)`. |
| `fcm_tokens` | Device tokens for push notifications. |
| `devices` | Registered cameras/streams. Fields: `device_name`, `device_type`, `stream_url`, `location`, `status`, `last_seen`. |
| `notifications` | In-app notification inbox with read/unread status and event references. |
| `incident_summaries` | Cached AI-generated incident reports with start/end time and incident count. |
| `chat_sessions` | RAG chatbot conversation sessions. |
| `chat_messages` | Individual messages within sessions (user/bot sender, sources). |

The backend uses the `service_role` key to bypass RLS for server-side inserts. New tables have RLS policies for user-scoped access via the anon key.

---

## ⚠️ Important Notes

- **Model weights** live in `../weights/` and are **not committed to git** (see `.gitignore`).
  A fresh clone will not have them.
- **`firebase-service-account.json`** must **never** be committed — it is already git-ignored.
  Without it (and without `PyJWT[crypto]` installed) FCM push silently no-ops; everything
  else keeps working.
- The backend runs on **CPU by default**. Set `CUDA_VISIBLE_DEVICES` for GPU acceleration.
- `../chrome_app/` is the **Chrome/desktop control panel** — it runs alongside the Engine on the
  same machine and is the only client that performs live inference.
- `../mobile_app/` is the **mobile companion app** for alerts, history, and device management.
- `/api/gemini-report` is a **legacy endpoint name**. It calls Groq, not Gemini.

---

## 📦 Dependencies

### Core Inference
- `torch` — TCN model, tensor operations
- `ultralytics` — YOLOv8 pose + hazard models
- `opencv-python` — Frame decoding, video I/O, annotation
- `numpy`, `scipy` — Feature engineering, Savitzky-Golay filtering

### Backend Server
- `fastapi`, `uvicorn` — Async HTTP/WebSocket server
- `websockets` — WebSocket protocol
- `python-dotenv` — Environment variable loading
- `supabase` — Database client
- `httpx` — HTTP client (Groq API, FCM)
- `PyJWT[crypto]` — RS256-signs the service-account JWT used to mint FCM access tokens

### RAG Chatbot
- `PyMuPDF` — PDF text extraction
- `faiss-cpu` — Dense vector search
- `rank-bm25` — Sparse keyword search
- `sentence-transformers` — Local text embeddings
