# 📱 SafeGuard Mobile — IHS Companion App

> Flutter companion app for the SafeGuard home safety surveillance system. Device management, alerts, AI summaries, and first aid guidance — all in your pocket.

---

## 📋 Overview

SafeGuard Mobile is the **companion app** for the SafeGuard surveillance system. It connects to the inference engine backend via REST APIs to provide device management, background monitoring control, in-app notifications, detection history, AI-generated reports, and an interactive first aid chatbot.

The mobile app does **not** run live camera inference — that is handled by the [Engine Flutter App](../Engine/flutter_app/) (desktop/web) or by the backend's **DeviceMonitorManager** (background RTSP/HTTP stream processing). The mobile app is designed for:

- 📷 **Managing devices** — Register cameras, start/stop background monitoring
- 🔔 **Receiving alerts** — FCM push notifications + in-app notification inbox
- 📊 **Reviewing history** — Browse detection events with confidence scores
- 🤖 **AI summaries** — Read and browse LLM-generated incident reports
- 💬 **First aid chat** — Get RAG-powered emergency guidance
- ⚙️ **Configuration** — Toggle child/elderly modules, set server URL

---

## 🖥️ Screens

| Screen | Description |
|---|---|
| **Login / Signup** | Email + password authentication via Supabase Auth |
| **Home Shell** | Navigation hub with bottom bar for all features |
| **Devices** | Device manager — add, edit, delete cameras. Start/stop background monitoring toggle per device |
| **Notifications** | In-app notification inbox with unread badge and mark-as-read |
| **History** | Chronological list of detection events (falls, hazards, child alerts) with confidence scores |
| **AI Summary** | Generate LLM-powered caregiver incident report from the last hour of events |
| **Summary History** | Browse previously generated AI incident summaries |
| **Chatbot** | RAG-powered first aid Q&A assistant with source citations |
| **Profile** | Module toggles (child/elderly), dark/light theme switch, server URL config, sign out |

---

## 📁 Project Structure

```
mobile_app/
├── lib/
│   ├── main.dart                     # App entry point
│   │                                   Firebase + Supabase init, providers
│   │
│   ├── core/                         # App-wide configuration
│   │   ├── app_theme.dart              # Light & dark MaterialApp themes
│   │   ├── app_colors.dart             # Colour palette constants
│   │   └── constants.dart              # Table names, defaults
│   │
│   ├── data/                         # Data layer
│   │   ├── api_service.dart            # HTTP client for backend (REST + monitor control)
│   │   ├── models.dart                 # Data models:
│   │   │                                 UserProfile, HistoryEvent, Device,
│   │   │                                 NotificationItem, IncidentSummary,
│   │   │                                 ChatSession, ChatMessage
│   │   ├── supabase_service.dart       # Supabase auth + profile/history CRUD
│   │   ├── notification_manager.dart   # Local notification scheduling
│   │   └── push_notification_service.dart  # FCM push notification handler
│   │
│   ├── features/                     # Feature modules
│   │   ├── auth/
│   │   │   ├── auth_gate.dart            # Auth state router
│   │   │   ├── login_screen.dart         # Login UI
│   │   │   └── signup_screen.dart        # Registration UI
│   │   ├── home/
│   │   │   └── home_shell.dart           # Bottom nav + scaffold
│   │   ├── devices/
│   │   │   └── devices_screen.dart       # Device CRUD + monitoring toggle
│   │   ├── notifications/
│   │   │   └── notifications_screen.dart # Notification inbox
│   │   ├── history/
│   │   │   └── history_screen.dart       # Event history list
│   │   ├── ai/
│   │   │   ├── summary_screen.dart       # AI incident report generator
│   │   │   ├── summaries_history_screen.dart  # Browse past summaries
│   │   │   └── chatbot_screen.dart       # First aid RAG chat
│   │   └── profile/
│   │       └── profile_screen.dart       # Settings & module toggles
│   │
│   └── theme/
│       └── theme_provider.dart         # Dark/light mode state manager
│
├── test/                             # Unit tests
│   ├── models_test.dart                # All 7 models: fromJson, toJson, copyWith (26 tests)
│   ├── api_service_test.dart           # Server URL persistence (4 tests)
│   └── widget_test.dart                # Smoke test
│
├── pubspec.yaml                      # Dependencies
├── .env                              # Runtime config (Supabase URL + keys)
├── android/                          # Android platform config + google-services.json
├── ios/                              # iOS platform config
└── analysis_options.yaml             # Dart linter rules
```

---

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK** ≥ 3.2.0
- **Android Studio** or **VS Code** with Flutter extension
- **Supabase** project (URL + service role key)
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
   SUPABASE_SERVICE_ROLE_KEY=eyJ...
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

5. **Set server URL:**

   After logging in, go to **Profile → Server Connection** and enter your Engine backend URL (e.g., `https://abc123.ngrok-free.app` for remote access, or leave empty for localhost).

---

## 🔗 Backend Connection

The app communicates with the Engine backend via REST APIs. The server URL is configured in-app via **Profile → Server Connection** (persisted via `SharedPreferences`).

### REST API

| Endpoint | Purpose |
|---|---|
| `GET /api/history?user_id=` | Fetch detection event history |
| `GET /api/gemini-report?user_id=` | AI-generated incident summary |
| `POST /api/chat` | First aid RAG chatbot |
| `GET /api/devices?user_id=` | List registered devices |
| `POST /api/devices` | Register new device |
| `PATCH /api/devices/{id}` | Update device |
| `DELETE /api/devices/{id}` | Delete device |
| `POST /api/devices/{id}/start` | Start background monitoring |
| `POST /api/devices/{id}/stop` | Stop background monitoring |
| `GET /api/devices/{id}/status` | Monitor status (monitoring/stopped/error) |
| `GET /api/notifications?user_id=` | List notifications |
| `PATCH /api/notifications/{id}` | Mark as read |
| `GET /api/summaries?user_id=` | List AI incident summaries |
| `GET /api/chat/sessions?user_id=` | Chat session list |

> **Tip:** For physical device testing, use [ngrok](https://ngrok.com) to tunnel `localhost:8000`:
>
> ```bash
> ngrok http 8000
> ```
>
> Then set the ngrok URL in the app's Profile → Server Connection.

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
- Uses **service role key** for DB operations (bypasses RLS)

---

## 🧪 Testing

```bash
cd mobile_app
flutter test
```

**28 tests** across 3 test files:

- `models_test.dart` — All 7 data models: `fromJson`, `toJson`, `copyWith`, default values, edge cases (26 tests)
- `api_service_test.dart` — Server URL persistence with `SharedPreferences` mock (4 tests)
- `widget_test.dart` — Smoke test

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
