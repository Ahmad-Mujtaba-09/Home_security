# 🖥️ IHS — Chrome App (Control Panel)

> The Flutter control panel for the IHS surveillance system. Runs in Chrome or as a native desktop build. Live camera inference, video file processing, RTSP stream monitoring, and device management.

This is the operator-facing app that runs on the same machine as the [Engine](../Engine/). It is the only client that does **live inference** — it streams camera frames to the Engine over WebSocket and renders the annotated result. For the phone companion see [`mobile_app/`](../mobile_app/).

---

## Screens

| Screen | Description |
|---|---|
| **Auth** | Email/password login and signup via Supabase Auth |
| **Dashboard** | Live camera feed, video file upload, and RTSP/HTTP stream processing, with real-time detection overlays |
| **Devices** | Add, edit and delete cameras; start/stop background monitoring per device |
| **Notifications** | In-app inbox with unread badge |
| **History** | Chronological event log with event type and confidence |
| **Summaries** | Previously generated AI incident reports |
| **Chatbot** | RAG first-aid Q&A with source citations and session persistence |
| **Profile** | Child/elderly module toggles, dark/light theme, sign out |

---

## Layout

```
chrome_app/
├── lib/
│   ├── main.dart                  # Entry point — dotenv load, Supabase init
│   ├── core/
│   │   ├── app_theme.dart           # AppColors palette + light/dark themes
│   │   └── constants.dart           # Table names, defaults
│   ├── data/
│   │   ├── api_service.dart         # REST client (history, devices, chat, summaries)
│   │   ├── inference_service.dart   # WebSocket client for the three inference channels
│   │   ├── models.dart              # UserProfile, HistoryEvent, Device, NotificationItem,
│   │   │                              IncidentSummary, ChatSession, ChatMessage
│   │   └── supabase_service.dart    # Supabase auth + profile CRUD
│   └── features/
│       ├── auth/  dashboard/  devices/  notifications/
│       └── history/  summaries/  chatbot/  profile/
├── test/widget_test.dart          # Smoke test
├── pubspec.yaml
└── .env -> ../Engine/.env         # Symlink — see Configuration
```

---

## Running

**Prerequisites:** Flutter SDK ≥ 3.2.0, and the Engine running on port 8000 (see [`Engine/README.md`](../Engine/README.md)).

```bash
cd chrome_app
flutter pub get
flutter run -d chrome     # web (the usual target)
flutter run -d linux      # Linux desktop
flutter run -d macos      # macOS desktop
flutter run -d windows    # Windows desktop
```

Live camera capture needs camera permission — in Chrome that means a secure context, so `localhost` works but a plain-HTTP LAN address will not.

---

## Configuration

`chrome_app/.env` is a **symlink to `../Engine/.env`**, so the Engine and this app share one config file. Editing either path edits the same file.

| Variable | Description |
|---|---|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_ANON_KEY` | Public anon key — RLS applies |
| `INFERENCE_API_URL` | Engine base URL, e.g. `http://localhost:8000` |
| `CHATBOT_API_URL` | Chat endpoint base URL |

If the symlink is missing after a fresh clone (git does not carry `.env`), recreate it:

```bash
cd chrome_app && ln -s ../Engine/.env .env
```

`pubspec.yaml` declares `.env` as a Flutter asset, which means it is bundled into the build output and readable by anyone with the build. Keep the service-role key out of anything you distribute.

---

## Backend connection

### WebSocket — used by the Dashboard

| URL | Purpose |
|---|---|
| `ws://<engine>/ws/inference/{user_id}` | Live camera frames |
| `ws://<engine>/ws/process-video/{user_id}` | Uploaded video file processing |
| `ws://<engine>/ws/stream/{user_id}` | RTSP/HTTP stream processing |

### REST — everything else

| Endpoint | Purpose |
|---|---|
| `/api/profile` | Profile and module toggles |
| `/api/history` | Detection event history |
| `/api/devices` (+ `/start` `/stop` `/status`) | Device CRUD and monitor control |
| `/api/notifications` | Inbox and mark-as-read |
| `/api/summaries` | Cached AI incident reports |
| `/api/gemini-report` | Generate an AI incident report (legacy name — calls Groq) |
| `/api/chat`, `/api/chat/sessions` | RAG chatbot and session history |

---

## Dependencies actually in use

| Package | Purpose |
|---|---|
| `supabase_flutter` | Auth + PostgREST access |
| `provider` | State management |
| `web_socket_channel` | Inference WebSocket |
| `http` | REST client |
| `camera` | Camera capture on the Dashboard |
| `file_picker` | Video file selection |
| `flutter_dotenv` | `.env` loading |
| `google_fonts` | Typography |
| `intl` | Date/time formatting |

`shimmer`, `flutter_markdown` and `cupertino_icons` are declared in `pubspec.yaml` but not imported anywhere in `lib/`.

---

## Checks

```bash
flutter analyze
flutter test
```
