<![CDATA[# ⚙️ SafeGuard — Inference Engine

> Python-based real-time inference server: fall detection, hazard recognition, child safety, and AI-powered first aid guidance.

---

## 📋 Overview

The Engine is the backend intelligence layer of SafeGuard. It receives camera frames from the Flutter mobile app over WebSocket, runs multi-model detection, and pushes alerts back. It also serves REST endpoints for event history, AI reports, and a RAG-powered first aid chatbot.

### Key Capabilities

- **Fall Detection** — Hybrid TCN deep learning + heuristic biomechanics classifier
- **Hazard Detection** — YOLOv8 object detection (knife, fire, stairs, oven, stove) with OpenVINO INT8 optimization
- **Child Safety** — Skeleton-ratio classification + hazard proximity alerts
- **Inactivity Monitoring** — Timer-based alarm for prolonged immobility after falls
- **First Aid RAG Chatbot** — Hybrid FAISS + BM25 retrieval with Groq LLM generation
- **AI Incident Reports** — LLM-generated caregiver summaries from detection history
- **FCM Push Notifications** — Firebase Cloud Messaging via HTTP v1 API

---

## 📁 File Structure

```
Engine/
├── main.py                     # FastAPI server — WebSocket + REST endpoints
├── falldetection_v1.py         # Core detection engine (1500+ lines)
│                                 TCN model, heuristic classifier, hazard
│                                 detection, child safety, annotation
├── rag_service.py              # RAG pipeline: retrieval + Groq generation
├── generate_embeddings.py      # Offline: PDF → chunks → FAISS index builder
├── requirements.txt            # Python dependencies
├── .env                        # Environment variables (keys, URLs)
├── firebase-service-account.json  # FCM service account (do not commit)
│
├── embeddings/                 # Pre-built search indices
│   ├── faiss.index             # Dense vector index (~1.2MB)
│   ├── chunks.json             # Chunk metadata (text, source, page)
│   └── bm25_corpus.json        # Tokenized corpus for sparse retrieval
│
├── supabase/migrations/        # Database schema
│   ├── 001_create_tables.sql   # profiles, history tables + RLS policies
│   └── 002_seed_dummy_data.sql # Test data seed
│
├── datasets/                   # Training datasets (COCO format)
├── testing/                    # Test video files
├── flutter_app/                # Legacy Flutter app (deprecated, use mobile_app/)
└── .vscode/                    # Editor settings
```

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

Create or edit `.env` in this directory:

```env
# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...

# Groq LLM (free tier)
GROQ_API_KEY=gsk_...
GROQ_MODEL=llama-3.1-8b-instant

# App URLs (used by mobile app, not backend)
INFERENCE_API_URL=ws://localhost:8000
CHATBOT_API_URL=http://localhost:8000/api/chat
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

### REST Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/health` | GET | Health check (`{"status": "ok"}`) |
| `/api/history?user_id=` | GET | User's detection event history (last 200) |
| `/api/profile?user_id=` | GET | User profile and module toggles |
| `/api/gemini-report?user_id=` | GET | AI-generated incident summary (last 1 hour) |
| `/api/chat` | POST | RAG chatbot. Body: `{"message": str, "user_id": str, "history": [...]}` |

---

## 🧠 Detection Pipeline Deep Dive

### 1. Pose Estimation

- **Model:** YOLOv8s-Pose (`yolov8s-pose.pt`)
- **Output:** 17 COCO keypoints per person with confidence scores
- **Tracking:** BoT-SORT tracker for persistent person IDs
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

- **Model:** Custom YOLOv8 INT8 OpenVINO (`best_int8_openvino_model/`)
- **Classes:** knife (0.40), fire (0.50), stairs (0.30), oven (0.25), stove (0.25) — per-class confidence thresholds
- **Temporal smoothing:** 5-frame sliding window with confidence bonus for persistent detections
- **Child proximity:** Normalised distance thresholds per hazard type (e.g., knife: 0.18, fire: 0.30)

### 6. Child/Adult Classification

- **Primary:** Leg-to-torso skeleton ratio (< 0.75 → CHILD)
- **Small person boost:** If bounding box < 35% of frame height, ratio threshold raised to 0.85
- **Sticky lock:** 15-frame hysteresis prevents classification flicker

### 7. RAG First Aid Chatbot

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
| `profiles` | User preferences. Auto-created via `on_auth_user_created` trigger. Fields: `light_mode`, `child_module_enabled`, `elderly_module_enabled`. |
| `history` | Detection events. Fields: `event_type`, `confidence`, `frame_count`, `timestamp`. Indexed: `(user_id, timestamp DESC)`. |
| `fcm_tokens` | Device tokens for push notifications. |

All tables enforce **Row-Level Security (RLS)** — users can only read/write their own rows. The backend uses the `service_role` key to bypass RLS for server-side inserts.

---

## ⚠️ Important Notes

- **Model weights** are stored in `../weights/` and are **not committed to git** (see `.gitignore`).
- **`firebase-service-account.json`** must **never** be committed. Add it to `.gitignore`.
- The backend runs on **CPU by default**. Set `CUDA_VISIBLE_DEVICES` for GPU acceleration.
- The `flutter_app/` directory is a **legacy prototype** — use the top-level `mobile_app/` instead.

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

### RAG Chatbot
- `PyMuPDF` — PDF text extraction
- `faiss-cpu` — Dense vector search
- `rank-bm25` — Sparse keyword search
- `sentence-transformers` — Local text embeddings
]]>
