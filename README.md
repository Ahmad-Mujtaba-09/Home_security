<![CDATA[# 🛡️ SafeGuard — Intelligent Home Safety Surveillance System

> **Final Year Project** — Real-time fall detection, hazard recognition, child safety monitoring, and AI-powered emergency guidance.

[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?logo=python&logoColor=white)](https://python.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.2+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.100+-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Supabase](https://img.shields.io/badge/Supabase-Auth%20%2B%20DB-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)

---

## 📋 Overview

SafeGuard is an end-to-end home safety surveillance platform that combines deep learning–based video analytics with a mobile companion app. It is designed to protect elderly individuals and children within a home environment by continuously monitoring camera feeds for:

| Capability | Description |
|---|---|
| **Fall Detection** | Hybrid TCN + heuristic classifier blending temporal pose sequences with rule-based biomechanics |
| **Inactivity Alerts** | Timer-based alarm when a person remains on the floor beyond a configurable threshold |
| **Hazard Detection** | YOLOv8-trained object detector for knives, fire, stairs, ovens, and stoves |
| **Child Safety** | Skeleton-ratio age classification with proximity alerts when children approach hazards |
| **First Aid Chatbot** | RAG-powered Q&A over official first aid manuals (FAISS + BM25 hybrid retrieval, Groq LLM) |
| **AI Incident Reports** | LLM-generated caregiver summaries from aggregated detection history |
| **Push Notifications** | Firebase Cloud Messaging (FCM) alerts delivered even when the app is closed |

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────┐
│                   Mobile App (Flutter)                │
│  Auth · Live Feed · History · AI Report · Chatbot    │
│  Supabase Auth · FCM Push · Dark/Light Theme         │
└──────────────┬───────────────────────┬───────────────┘
               │ WebSocket (frames)    │ REST (history,
               │                       │  report, chat)
               ▼                       ▼
┌──────────────────────────────────────────────────────┐
│              Inference Engine (FastAPI)               │
│  YOLOv8-Pose · TCN · Hazard YOLO · Heuristic FSM    │
│  RAG Service · Groq LLM · FCM Sender                │
└──────────────┬───────────────────────┬───────────────┘
               │                       │
               ▼                       ▼
        ┌─────────────┐        ┌──────────────┐
        │   Supabase   │        │   Firebase   │
        │  Auth + DB   │        │     FCM      │
        └─────────────┘        └──────────────┘
```

---

## 📁 Repository Structure

```
.
├── Engine/                  # Python inference engine + FastAPI backend
│   ├── main.py              # FastAPI server (WebSocket + REST endpoints)
│   ├── falldetection_v1.py  # Core detection: TCN, heuristic, hazard, child safety
│   ├── rag_service.py       # RAG pipeline (FAISS + BM25 + Groq)
│   ├── generate_embeddings.py  # Offline FAISS index builder for first aid books
│   ├── requirements.txt     # Python dependencies
│   ├── .env                 # Environment config (Supabase, Groq, inference URLs)
│   ├── firebase-service-account.json  # FCM service account credentials
│   ├── embeddings/          # Pre-built FAISS index + BM25 corpus
│   ├── supabase/migrations/ # SQL schema (profiles, history, RLS policies)
│   └── testing/             # Test video files
│
├── mobile_app/              # Flutter mobile application
│   ├── lib/
│   │   ├── main.dart              # App entry point, Firebase + Supabase init
│   │   ├── core/                  # Theme, colors, constants
│   │   ├── data/                  # API service, models, notifications
│   │   ├── features/              # Feature screens (auth, home, history, AI, profile)
│   │   └── theme/                 # Theme provider
│   ├── pubspec.yaml               # Flutter dependencies
│   ├── android/                   # Android platform config
│   ├── ios/                       # iOS platform config
│   └── .env                       # Mobile environment config
│
├── weights/                 # Pre-trained model weights (git-ignored)
│   ├── yolov8s-pose.pt      # YOLOv8-small pose estimation
│   ├── tcn_fall_best.pt     # Trained TCN fall classifier
│   ├── best_int8_openvino_model/  # Hazard detector (INT8 OpenVINO)
│   ├── norm_mean.npy        # Feature normalisation statistics
│   └── norm_std.npy
│
├── books/                   # First aid reference PDFs (RAG knowledge base)
├── docs/                    # Project documentation & training notebooks
└── README.md                # ← You are here
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
git clone <repo-url> && cd SafeGuard
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
```

### 3. Run the Mobile App

```bash
cd mobile_app

# Configure environment
cp .env.example .env   # Edit with your Supabase + server URLs

flutter pub get
flutter run
```

> **Tip for APK testing:** Use [ngrok](https://ngrok.com) to expose `localhost:8000` and set the `INFERENCE_API_URL` in `mobile_app/.env` to the ngrok URL.

### 4. Database Setup

Run the SQL migrations against your Supabase project:

```sql
-- Execute in Supabase SQL Editor:
-- Engine/supabase/migrations/001_create_tables.sql
-- Engine/supabase/migrations/002_seed_dummy_data.sql
```

---

## 🔧 Configuration

All configuration is managed through `.env` files:

| Variable | Used By | Description |
|---|---|---|
| `SUPABASE_URL` | Engine + App | Your Supabase project URL |
| `SUPABASE_ANON_KEY` | App | Supabase anonymous/public key |
| `SUPABASE_SERVICE_ROLE_KEY` | Engine | Supabase service role key (server-side) |
| `GROQ_API_KEY` | Engine | Groq API key for LLM generation |
| `GROQ_MODEL` | Engine | LLM model (default: `llama-3.1-8b-instant`) |
| `INFERENCE_API_URL` | App | WebSocket URL to the inference server |
| `CHATBOT_API_URL` | App | HTTP URL for the RAG chatbot endpoint |

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

- Custom-trained YOLOv8 (INT8 OpenVINO) detecting: **knife, fire, stairs, oven, stove**
- Temporal confidence smoothing over 5-frame sliding window
- Child-hazard proximity alerts with object-specific distance thresholds

### First Aid RAG Chatbot

- Offline PDF extraction → chunking → local embedding (`all-MiniLM-L6-v2`)
- Hybrid retrieval: FAISS dense search + BM25 sparse search + Reciprocal Rank Fusion
- Answer generation via Groq API (free tier)

---

## 📱 Mobile App Features

| Screen | Description |
|---|---|
| **Auth** | Email/password login & signup via Supabase Auth |
| **Home** | Live camera feed with real-time WebSocket inference overlay |
| **History** | Chronological event log with event type and confidence |
| **AI Summary** | LLM-generated caregiver incident reports |
| **Chatbot** | RAG-powered first aid Q&A assistant |
| **Profile** | Module toggles (child/elderly), theme settings |

---

## 🗄️ Database Schema

| Table | Purpose |
|---|---|
| `profiles` | User preferences (theme, module toggles). Auto-created on signup via trigger. |
| `history` | Detection events (type, confidence, frame count, timestamp). Indexed by user + time. |
| `fcm_tokens` | Firebase device tokens for push notifications. |

All tables use **Row-Level Security (RLS)** — users can only access their own data.

---

## 📡 API Endpoints

| Endpoint | Type | Description |
|---|---|---|
| `/ws/inference/{user_id}` | WebSocket | Real-time camera frame inference |
| `/ws/process-video/{user_id}` | WebSocket | Server-side video file processing |
| `/ws/stream/{user_id}` | WebSocket | RTSP/HTTP stream processing |
| `/api/history?user_id=` | GET | Fetch user detection history |
| `/api/profile?user_id=` | GET | Fetch user profile |
| `/api/gemini-report?user_id=` | GET | Generate AI incident summary |
| `/api/chat` | POST | RAG first aid chatbot |
| `/health` | GET | Health check |

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **Inference** | PyTorch, YOLOv8 (Ultralytics), OpenVINO, OpenCV, SciPy |
| **Backend** | FastAPI, Uvicorn, WebSockets |
| **RAG** | FAISS, BM25, sentence-transformers, Groq API |
| **Database** | Supabase (PostgreSQL + Auth + RLS) |
| **Push** | Firebase Cloud Messaging (FCM HTTP v1 API) |
| **Mobile** | Flutter 3.2+, Provider, Supabase Flutter SDK |
| **Auth** | Supabase Auth (email/password) |

---

## 📄 License

This project was developed as a Final Year Project. All rights reserved.
]]>
