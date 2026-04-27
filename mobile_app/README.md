# 📱 SafeGuard Mobile — IHS Surveillance App

> Flutter companion app for the SafeGuard home safety surveillance system. Monitoring, alerts, AI summaries, and first aid guidance — all in your pocket.

---

## 📋 Overview

SafeGuard Mobile connects to the inference engine backend via WebSocket and REST APIs to provide real-time monitoring, incident history, AI-generated reports, and an interactive first aid chatbot. The app uses Supabase for authentication, Firebase Cloud Messaging for push notifications, and supports both light and dark themes.

---

## 🖥️ Screens

| Screen | Description |
|---|---|
| **Login / Signup** | Email + password authentication via Supabase Auth |
| **Home Shell** | Navigation hub with bottom bar for all features |
| **Live Feed** | Camera-to-WebSocket stream with real-time detection overlays |
| **History** | Chronological list of detection events (falls, hazards, child alerts) with confidence scores |
| **AI Summary** | LLM-generated caregiver incident report from the last hour of events |
| **Chatbot** | RAG-powered first aid Q&A assistant with source citations |
| **Profile** | Module toggles (child/elderly), dark/light theme switch, sign out |

---

## 📁 Project Structure

```
mobile_app/
├── lib/
│   ├── main.dart                 # App entry point
│   │                               Firebase + Supabase init, providers
│   │
│   ├── core/                     # App-wide configuration
│   │   ├── app_theme.dart          # Light & dark MaterialApp themes
│   │   ├── app_colors.dart         # Colour palette constants
│   │   └── constants.dart          # Global constants
│   │
│   ├── data/                     # Data layer
│   │   ├── api_service.dart        # HTTP + WebSocket client for backend
│   │   ├── models.dart             # Data models (HistoryEvent, Profile, etc.)
│   │   ├── supabase_service.dart   # Supabase auth + DB operations
│   │   ├── notification_manager.dart     # Local notification scheduling
│   │   └── push_notification_service.dart  # FCM push notification handler
│   │
│   ├── features/                 # Feature modules
│   │   ├── auth/
│   │   │   ├── auth_gate.dart        # Auth state router
│   │   │   ├── login_screen.dart     # Login UI
│   │   │   └── signup_screen.dart    # Registration UI
│   │   ├── home/
│   │   │   └── home_shell.dart       # Bottom nav + scaffold
│   │   ├── history/
│   │   │   └── history_screen.dart   # Event history list
│   │   ├── ai/
│   │   │   ├── summary_screen.dart   # AI incident report
│   │   │   └── chatbot_screen.dart   # First aid RAG chat
│   │   └── profile/
│   │       └── profile_screen.dart   # Settings & module toggles
│   │
│   └── theme/
│       └── theme_provider.dart     # Dark/light mode state manager
│
├── pubspec.yaml                  # Dependencies
├── .env                          # Runtime config (Supabase URL, API URLs)
├── android/                      # Android platform config + google-services.json
├── ios/                          # iOS platform config
├── analysis_options.yaml         # Dart linter rules
└── test/                         # Unit/widget tests
```

---

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK** ≥ 3.2.0
- **Android Studio** or **VS Code** with Flutter extension
- **Supabase** project (URL + anon key)
- **Firebase** project (for push notifications)

### Setup

1. **Install dependencies:**

   ```bash
   cd mobile_app
   flutter pub get
   ```

2. **Configure environment:**

   Edit `.env` with your credentials:

   ```env
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=eyJ...

   # For local development (Engine running on same machine)
   INFERENCE_API_URL=ws://localhost:8000
   CHATBOT_API_URL=http://localhost:8000/api/chat

   # For APK testing on physical device (use ngrok)
   # INFERENCE_API_URL=wss://your-ngrok-url.ngrok-free.app
   # CHATBOT_API_URL=https://your-ngrok-url.ngrok-free.app/api/chat
   ```

3. **Firebase setup:**

   - Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
   - Download `google-services.json` → place in `android/app/`
   - Download `GoogleService-Info.plist` → place in `ios/Runner/`
   - Enable Cloud Messaging in your Firebase project

4. **Run the app:**

   ```bash
   flutter run
   ```

---

## 🔗 Backend Connection

The app communicates with the Engine backend via two channels:

### WebSocket (Real-Time Inference)

```
ws://[INFERENCE_API_URL]/ws/inference/{user_id}
```

- App captures camera frames → sends as binary JPEG → receives detection results
- Profile-aware: backend reads module toggles from Supabase and skips disabled pipelines

### REST API

| Endpoint | Purpose |
|---|---|
| `GET /api/history?user_id=` | Fetch detection event history |
| `GET /api/gemini-report?user_id=` | AI-generated incident summary |
| `POST /api/chat` | First aid RAG chatbot |

> **Tip:** For physical device testing, use [ngrok](https://ngrok.com) to tunnel `localhost:8000`:
>
> ```bash
> ngrok http 8000
> ```
>
> Then update `INFERENCE_API_URL` and `CHATBOT_API_URL` in `.env` with the ngrok URL.

---

## 🔔 Push Notifications

The app receives FCM push notifications for detection events even when closed or in the background.

### How It Works

1. **On login:** FCM token is registered to `fcm_tokens` table in Supabase
2. **Backend detection event:** Engine sends FCM push via HTTP v1 API
3. **App receives:** Notification displayed via `flutter_local_notifications`
4. **Throttling:** Same event type per user limited to 1 push per 60 seconds

### Configuration

- Background handler registered in `main.dart` via `FirebaseMessaging.onBackgroundMessage`
- Notification channel: `safeguard_alerts` (Android high-priority)
- Token lifecycle: split into pre-login (permissions + listeners) and post-login (registration)

---

## 🛡️ Authentication

Supabase Auth with email/password:

- **AuthGate** widget routes users to Login or Home based on session state
- Profile auto-created on signup via database trigger
- Session persisted across app restarts via Supabase Flutter SDK

---

## 📦 Key Dependencies

| Package | Purpose |
|---|---|
| `supabase_flutter` | Supabase Auth + Realtime + DB |
| `firebase_core` + `firebase_messaging` | FCM push notifications |
| `flutter_local_notifications` | Local notification display |
| `flutter_dotenv` | Environment variable loading |
| `provider` | State management |
| `google_fonts` | Typography (custom fonts) |
| `intl` | Date/time formatting |
| `http` | REST API client |
| `shimmer` | Loading placeholder animations |
| `shared_preferences` | Local key-value storage |

---

## 🎨 Theming

- **Light and Dark** themes with `ThemeProvider` (persisted via `shared_preferences`)
- Custom colour palette defined in `core/app_colors.dart`
- Material Design 3 with curated typography via Google Fonts
- Profile screen toggle to switch between modes
]]>
