# 🛡️ IHS — Intelligent Home Surveillance System

> **Final Year Project** — Real-time fall detection, hazard recognition, child safety monitoring, background device surveillance, and AI-powered emergency guidance.

[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white)](https://python.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.2+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.100+-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Supabase](https://img.shields.io/badge/Supabase-Auth%20%2B%20DB-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)

---

## 📋 Overview

Intelligent Home Surveillance (IHS) is an end-to-end home safety surveillance platform that combines deep learning–based video analytics with a mobile companion app and a desktop control panel. It is designed to protect elderly individuals and children within a home environment by continuously monitoring camera feeds for:

| Capability | Description |
|---|---|
| **Fall Detection** | Hybrid TCN + heuristic classifier blending temporal pose sequences with rule-based biomechanics |
| **Inactivity Alerts** | Timer-based alarm when a person remains on the floor beyond a configurable threshold |
| **Hazard Detection** | Custom-trained YOLOv8 object detector for knives, fire, stairs, ovens, and stoves |
| **Child Safety** | Skeleton-ratio age classification with proximity alerts when children approach hazards |
| **Background Monitoring** | Server-side `DeviceMonitorManager` processes RTSP/HTTP streams independently of client connections |
| **First Aid Chatbot** | RAG-powered Q&A over official first aid manuals (FAISS + BM25 hybrid retrieval, Groq LLM) |
| **AI Incident Reports** | LLM-generated caregiver summaries from aggregated detection history |
| **Push Notifications** | Firebase Cloud Messaging (FCM) alerts delivered even when the app is closed |
| **Device Management** | Register, configure, start/stop monitoring for cameras and RTSP streams |
| **Notifications Inbox** | In-app notification centre with unread badges |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Mobile App (Flutter)                             │
│  Auth · History · Devices · Notifications · AI Summary · Chatbot       │
│  Supabase Auth · FCM Push · Dark/Light Theme                           │
└──────────────────────────┬──────────────────────────────────────────────┘
                           │ REST (history, devices, chat, summaries)
                           ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Engine Flutter App (Desktop/Web)                      │
│  Live Camera · File Upload · RTSP Streams · Device Control · Dashboard │
└──────────────────────────┬──────────────────────────────────────────────┘
                           │ WebSocket (frames) + REST
                           ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Inference Engine (FastAPI)                            │
│  YOLOv8-Pose · TCN · Hazard YOLO · Heuristic FSM                      │
│  DeviceMonitorManager · RAG Service · Groq LLM · FCM Sender           │
└──────────────────┬──────────────────────────────┬───────────────────────┘
                   │                              │
                   ▼                              ▼
           ┌─────────────┐               ┌──────────────┐
           │   Supabase   │               │   Firebase   │
           │  Auth + DB   │               │     FCM      │
           └─────────────┘               └──────────────┘
```

---

## 📁 Repository Structure

```
.
├── Engine/                       # Python inference engine + FastAPI backend
│   ├── main.py                     # FastAPI server — WebSocket + REST + DeviceMonitorManager
│   ├── falldetection_v1.py         # Core detection: TCN, heuristic, hazard, child safety
│   ├── rag_service.py              # RAG pipeline (FAISS + BM25 + Groq)
│   ├── generate_embeddings.py      # Offline FAISS index builder for first aid books
│   ├── requirements.txt            # Python dependencies
│   ├── .env                        # Environment config (Supabase, Groq keys)
│   ├── firebase-service-account.json  # FCM service account credentials
│   ├── embeddings/                 # Pre-built FAISS index + BM25 corpus
│   ├── tests/                      # Python test suite (pytest)
│   ├── flutter_app/                # Desktop/web Flutter control panel
│   └── testing/                    # Test video files
│
├── mobile_app/                   # Flutter mobile companion app
│   ├── lib/
│   │   ├── main.dart                 # App entry point, Firebase + Supabase init
│   │   ├── core/                     # Theme, colours, constants
│   │   ├── data/                     # API service, models, Supabase, notifications
│   │   ├── features/                 # Feature screens (auth, devices, notifications, AI, profile)
│   │   └── theme/                    # Theme provider
│   ├── test/                         # Dart unit tests (flutter test)
│   ├── pubspec.yaml                  # Flutter dependencies
│   └── .env                          # Mobile environment config
│
├── supabase/migrations/          # Database schema & RLS policies
│   └── 20260505000001_add_devices_notifications_summaries_chat.sql
│
├── weights/                      # Pre-trained model weights (git-ignored)
│   ├── yolov8s-pose.pt             # YOLOv8-small pose estimation
│   ├── tcn_fall_best.pt            # Trained TCN fall classifier
│   ├── best.pt                     # Trained hazard detector (YOLOv8)
│   ├── sticky_tracker.yaml         # ByteTrack tracker config
│   ├── norm_mean.npy               # Feature normalisation statistics
│   └── norm_std.npy
│
├── books/                        # First aid reference PDFs (RAG knowledge base)
├── docs/                         # Project documentation & training notebooks
└── README.md                     # ← You are here
```

---

## 🚀 Quick Start

### Prerequisites

- **Python 3.10+** with `pip`
- **Flutter SDK ≥ 3.2.0**
- **Supabase** project (free tier works)
- **Groq** API key ([free at console.groq.com](https://console.groq.com))
- **Firebase** project (for FCM push notifications)

### 1. Clone & Setup Environment

```bash
git clone <repo-url> && cd <repo-dir>
```

### 2. Start the Inference Engine

```bash
cd Engine
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# Build the First Aid FAISS index (one-time)
python generate_embeddings.py

# Start the backend server
python main.py
# → Server runs on http://localhost:8000
# → Active devices auto-start background monitoring on startup
```

### 3. Run the Engine Flutter App (Desktop/Web Control Panel)

```bash
cd Engine/flutter_app
flutter pub get
flutter run -d chrome     # or: flutter run -d macos / flutter run -d linux
```

### 4. Run the Mobile Companion App

```bash
cd mobile_app
flutter pub get
flutter run               # Physical device or emulator
```

> **Tip for APK testing:** Use [ngrok](https://ngrok.com) to expose `localhost:8000` and set the server URL in the mobile app's Profile → Server Connection.

### 5. Database Setup

Run the SQL migration against your Supabase project:

```sql
-- Execute in Supabase SQL Editor:
-- supabase/migrations/20260505000001_add_devices_notifications_summaries_chat.sql
```

---

## 🔧 Configuration

### Engine `.env`

| Variable | Description |
|---|---|
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase service role key (bypasses RLS) |
| `GROQ_API_KEY` | Groq API key for LLM generation |
| `GROQ_MODEL` | LLM model (default: `llama-3.1-8b-instant`) |

### Mobile App `.env`

| Variable | Description |
|---|---|
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_ANON_KEY` | Supabase anonymous key (fallback) |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase service role key (used for DB operations) |

> The mobile app configures the Engine server URL through the **Profile → Server Connection** screen (persisted via `SharedPreferences`).

---

## 🧠 Detection Pipeline

### Fall Detection (Hybrid TCN + Heuristic)

1. **Pose Estimation** — YOLOv8s-Pose extracts 17 COCO keypoints per person
2. **Feature Engineering** — Hip-centred normalisation, joint angles, velocities, trunk tilt (61-dim vector)
3. **TCN Classifier** — 3-layer Residual TCN over 30-frame sliding windows (runs every 10 frames)
4. **Heuristic Classifier** — Rule-based FSM using trunk angle, hip height, CoG velocity, and inversion detection
5. **Score Blending** — 70% TCN + 30% heuristic with gating for confirmed falls
6. **Sticky Lock** — Hysteresis prevents rapid state oscillation

### Hazard Detection

- Custom-trained YOLOv8 (`best.pt`) detecting: **knife, fire, stairs, oven, stove**
- Temporal confidence smoothing over 5-frame sliding window
- Child-hazard proximity alerts with object-specific distance thresholds

### Background Device Monitoring

- Server-side `DeviceMonitorManager` processes RTSP/HTTP streams at ~2 FPS
- Shared YOLO models with per-device state isolation (`save_state`/`load_state`)
- Auto-resumes active devices on server restart
- Auto-reconnects on stream failure (3 retries)
- Logs detections to history and sends FCM push notifications automatically

### First Aid RAG Chatbot

- Offline PDF extraction → chunking → local embedding (`all-MiniLM-L6-v2`)
- Hybrid retrieval: FAISS dense search + BM25 sparse search + Reciprocal Rank Fusion
- Answer generation via Groq API (free tier)

---

## 📱 App Features

### Engine Flutter App (Desktop/Web Control Panel)

| Screen | Description |
|---|---|
| **Auth** | Email/password login & signup via Supabase Auth |
| **Dashboard** | Live camera feed, file upload, and RTSP stream processing with real-time detection overlays |
| **Devices** | Device manager — add, edit, delete cameras with start/stop background monitoring toggle |
| **Notifications** | In-app notification inbox with unread badge |
| **History** | Chronological event log with event type and confidence |
| **AI Summary** | LLM-generated caregiver incident reports |
| **Chatbot** | RAG-powered first aid Q&A assistant with chat sessions |
| **Profile** | Module toggles (child/elderly), theme settings |

### Mobile Companion App

| Screen | Description |
|---|---|
| **Auth** | Email/password login & signup via Supabase Auth |
| **Home** | Navigation hub with bottom bar |
| **Devices** | Device manager with start/stop background monitoring toggle |
| **Notifications** | In-app notification inbox with unread badge |
| **History** | Chronological event log with event type and confidence |
| **AI Summary** | LLM-generated caregiver incident reports + summary history |
| **Chatbot** | RAG-powered first aid Q&A assistant |
| **Profile** | Module toggles (child/elderly), theme, server URL config |

---

## 🗄️ Database Schema

| Table | Purpose |
|---|---|
| `profiles` | User preferences (theme, module toggles). PK = `auth.users.id`. |
| `history` | Detection events (type, confidence, frame count, timestamp). Indexed by user + time. |
| `fcm_tokens` | Firebase device tokens for push notifications. |
| `devices` | Registered cameras/streams with name, type, stream URL, location, status. |
| `notifications` | In-app notification inbox with read/unread status. |
| `incident_summaries` | Cached AI-generated incident reports. |
| `chat_sessions` | RAG chatbot conversation sessions. |
| `chat_messages` | Individual chat messages within sessions. |

All new tables enforce **Row-Level Security (RLS)** for user-scoped access. The backend uses the `service_role` key to bypass RLS for server-side operations.

---

## 📡 API Endpoints

### WebSocket

| Endpoint | Description |
|---|---|
| `WS /ws/inference/{user_id}` | Real-time camera frame inference |
| `WS /ws/process-video/{user_id}` | Server-side video file processing |
| `WS /ws/stream/{user_id}` | RTSP/HTTP stream processing |

### REST — Core

| Endpoint | Method | Description |
|---|---|---|
| `/health` | GET | Health check |
| `/api/history` | GET | User's detection event history |
| `/api/profile` | GET | User profile and module toggles |
| `/api/gemini-report` | GET | AI-generated incident summary |
| `/api/chat` | POST | RAG first aid chatbot |

### REST — Devices & Monitoring

| Endpoint | Method | Description |
|---|---|---|
| `/api/devices` | GET | List user's devices |
| `/api/devices` | POST | Register a new device |
| `/api/devices/{id}` | PATCH | Update device settings |
| `/api/devices/{id}` | DELETE | Delete a device |
| `/api/devices/{id}/start` | POST | Start background monitoring |
| `/api/devices/{id}/stop` | POST | Stop background monitoring |
| `/api/devices/{id}/status` | GET | Get monitor status (monitoring/stopped/error) |

### REST — Notifications, Summaries, Chat Sessions

| Endpoint | Method | Description |
|---|---|---|
| `/api/notifications` | GET | List user's notifications |
| `/api/notifications/{id}` | PATCH | Mark notification as read |
| `/api/summaries` | GET | List cached incident summaries |
| `/api/chat/sessions` | GET | List chat sessions |
| `/api/chat/sessions/{id}/messages` | GET | Get messages for a session |

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **Inference** | PyTorch, YOLOv8 (Ultralytics), OpenCV, SciPy |
| **Backend** | FastAPI, Uvicorn, WebSockets, asyncio |
| **Background Monitoring** | DeviceMonitorManager (asyncio tasks, shared YOLO + state isolation) |
| **RAG** | FAISS, BM25, sentence-transformers, Groq API |
| **Database** | Supabase (PostgreSQL + Auth + RLS) |
| **Push** | Firebase Cloud Messaging (FCM HTTP v1 API) |
| **Desktop App** | Flutter (Web/macOS/Linux), Provider |
| **Mobile App** | Flutter, Provider, Supabase Flutter SDK |
| **Auth** | Supabase Auth (email/password) |

---

## 🧪 Testing

### Python (Engine)

```bash
cd Engine
pip install pytest pytest-asyncio httpx
pytest
```

### Flutter (mobile_app)

```bash
cd mobile_app
flutter test
```

See [`Engine/tests/README.md`](Engine/tests/README.md) for test suite details.

---

## 📄 License

This project was developed as a Final Year Project. All rights reserved.
