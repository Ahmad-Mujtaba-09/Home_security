"""
FastAPI Backend for Surveillance App
=====================================
WebSocket-based inference server wrapping HomeSafetyInference.
Streams frames from the Flutter client, runs detection, and pushes alerts back.
"""

import os
import sys
import json
import base64
import logging
import asyncio
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, Optional, Tuple

import cv2
import numpy as np
from dotenv import load_dotenv
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from supabase import create_client, Client

# ─── Ensure our own directory is importable ───────────────────────────────────
sys.path.insert(0, str(Path(__file__).resolve().parent))

from falldetection_v1 import HomeSafetyInference
from rag_service import RAGService

# ─── Environment ──────────────────────────────────────────────────────────────
load_dotenv(Path(__file__).resolve().parent / ".env")

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")

logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
logger = logging.getLogger("surveillance-api")

# ─── FastAPI App ──────────────────────────────────────────────────────────────
app = FastAPI(title="Surveillance Inference API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── Globals initialised at startup ──────────────────────────────────────────
supabase: Optional[Client] = None
inference_system: Optional[HomeSafetyInference] = None
rag_service: Optional[RAGService] = None

WEIGHTS_DIR = Path(__file__).resolve().parent.parent / "weights"


@app.on_event("startup")
async def startup():
    global supabase, inference_system, rag_service

    # Supabase client (service role for server-side inserts)
    if SUPABASE_URL and SUPABASE_SERVICE_KEY:
        supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
        logger.info("Supabase client initialised.")
    else:
        logger.warning("Supabase credentials missing — DB logging disabled.")

    # Inference engine
    logger.info(f"Loading weights from {WEIGHTS_DIR} ...")
    inference_system = HomeSafetyInference(
        tcn_weights=str(WEIGHTS_DIR / "tcn_fall_best.pt"),
        norm_mean=str(WEIGHTS_DIR / "norm_mean.npy"),
        norm_std=str(WEIGHTS_DIR / "norm_std.npy"),
        hazard_weights=str(WEIGHTS_DIR / "best.pt"),
        mode="hybrid",
        fall_threshold=0.65,
    )
    logger.info("Inference engine ready.")

    # RAG service (loads pre-built FAISS index — embedding model lazy-loaded on first query)
    rag_service = RAGService()
    if rag_service.load():
        logger.info("RAG service loaded successfully.")
    else:
        logger.warning("RAG service not available — run `python generate_embeddings.py` first.")

    # Auto-start active devices with stream URLs
    if supabase:
        try:
            resp = supabase.table("devices").select("*").eq("status", "active").execute()
            for d in (resp.data or []):
                url = d.get("stream_url", "")
                if url:
                    await device_monitor.start_device(d["device_id"], url, d["user_id"])
            if resp.data:
                logger.info(f"Auto-started {len(device_monitor.active_device_ids)} device monitor(s).")
        except Exception as e:
            logger.warning(f"Auto-start devices failed: {e}")


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _get_user_profile(user_id: str) -> Dict:
    """Fetch user profile from Supabase. Returns defaults if unavailable."""
    defaults = {"child_module_enabled": True, "elderly_module_enabled": True}
    if supabase is None:
        logger.warning("Supabase not configured — using default profile (both modules ON)")
        return defaults
    try:
        resp = supabase.table("profiles").select("*").eq("id", user_id).single().execute()
        if resp.data:
            logger.info(f"Profile for {user_id}: child={resp.data.get('child_module_enabled')}, elderly={resp.data.get('elderly_module_enabled')}")
            return resp.data
    except Exception as e:
        logger.warning(f"Profile fetch failed for {user_id}: {e}")
    return defaults


def _alert_title_body(alert: Dict) -> Tuple[str, str]:
    event_type = alert.get("type", "UNKNOWN")
    confidence = alert.get("prob", 0) or 0
    title = f"⚠️ {event_type.replace('_', ' ').title()} Detected"
    body = f"Confidence: {confidence:.0%}. Check the app for details."
    return title, body


def _log_event(user_id: str, alert: Dict):
    """Write a detection event to history, persist a notification row, push FCM."""
    if supabase is None:
        return
    try:
        row = {
            "user_id": user_id,
            "event_type": alert.get("type", "UNKNOWN"),
            "confidence": alert.get("prob"),
            "frame_count": alert.get("frame"),
        }
        resp = supabase.table("history").insert(row).execute()
        event_id = (resp.data or [{}])[0].get("id") if getattr(resp, "data", None) else None

        # Persist notification record (decoupled from FCM throttling — every
        # alert produces a notification row so the in-app history is complete).
        try:
            title, body = _alert_title_body(alert)
            supabase.table("notifications").insert({
                "user_id": user_id,
                "event_id": event_id,
                "title": title,
                "message": body,
                "notification_type": alert.get("type", "alert"),
            }).execute()
        except Exception as e:
            logger.warning(f"Failed to insert notification: {e}")

        # Send FCM push notification (throttled)
        _send_fcm_push(user_id, alert)
    except Exception as e:
        logger.error(f"Failed to log event: {e}")


# ── FCM Push Notification Sender (HTTP v1 API) ────────────────────────────────
_fcm_last_sent: Dict[str, float] = {}   # "user_id:event_type" → timestamp
FCM_THROTTLE_SECS = 60                    # Same as mobile app throttle
_fcm_access_token: Optional[str] = None
_fcm_token_expiry: float = 0

def _get_fcm_access_token() -> Optional[str]:
    """Get a valid OAuth2 access token for FCM using the service account."""
    global _fcm_access_token, _fcm_token_expiry
    import time

    # Return cached token if still valid (with 60s buffer)
    if _fcm_access_token and time.time() < _fcm_token_expiry - 60:
        return _fcm_access_token

    sa_path = Path(__file__).resolve().parent / "firebase-service-account.json"
    if not sa_path.exists():
        return None

    try:
        import json
        import jwt  # PyJWT
        import httpx

        with open(sa_path) as f:
            sa = json.load(f)

        # Create JWT assertion
        now = int(time.time())
        payload = {
            "iss": sa["client_email"],
            "sub": sa["client_email"],
            "aud": "https://oauth2.googleapis.com/token",
            "iat": now,
            "exp": now + 3600,
            "scope": "https://www.googleapis.com/auth/firebase.messaging",
        }
        assertion = jwt.encode(payload, sa["private_key"], algorithm="RS256")

        # Exchange JWT for access token
        with httpx.Client(timeout=10) as client:
            resp = client.post(
                "https://oauth2.googleapis.com/token",
                data={
                    "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                    "assertion": assertion,
                },
            )
            token_data = resp.json()
            _fcm_access_token = token_data["access_token"]
            _fcm_token_expiry = now + token_data.get("expires_in", 3600)
            return _fcm_access_token
    except Exception as e:
        logger.warning(f"FCM token fetch failed: {e}")
        return None


def _send_fcm_push(user_id: str, alert: Dict):
    """Send an FCM push notification via HTTP v1 API."""
    import time
    import httpx

    event_type = alert.get("type", "UNKNOWN")
    throttle_key = f"{user_id}:{event_type}"
    now = time.time()

    # Throttle: same event type per user only once per 60s
    if throttle_key in _fcm_last_sent:
        elapsed = now - _fcm_last_sent[throttle_key]
        if elapsed < FCM_THROTTLE_SECS:
            logger.debug(f"FCM throttled: {event_type} ({elapsed:.0f}s < {FCM_THROTTLE_SECS}s)")
            return
    _fcm_last_sent[throttle_key] = now

    if supabase is None:
        logger.warning("FCM push skipped — supabase is None")
        return

    access_token = _get_fcm_access_token()
    if not access_token:
        logger.warning("FCM push skipped — could not get access token")
        return

    try:
        # Get user's FCM token from Supabase
        resp = supabase.table("fcm_tokens").select("token").eq("user_id", user_id).execute()
        if not resp.data:
            logger.warning(f"FCM push skipped — no FCM token found for user {user_id}")
            return
        token = resp.data[0].get("token")
        if not token:
            logger.warning(f"FCM push skipped — empty token for user {user_id}")
            return

        logger.info(f"FCM: sending push to user {user_id[:8]}... for {event_type}")

        # Build notification
        confidence = alert.get("prob", 0)
        title = f"⚠️ {event_type.replace('_', ' ').title()} Detected"
        body = f"Confidence: {confidence:.0%}. Check the app for details."

        # FCM project ID from service account
        sa_path = Path(__file__).resolve().parent / "firebase-service-account.json"
        with open(sa_path) as f:
            project_id = __import__("json").load(f)["project_id"]

        # Send via FCM HTTP v1 API
        with httpx.Client(timeout=10) as client:
            fcm_resp = client.post(
                f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send",
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Content-Type": "application/json",
                },
                json={
                    "message": {
                        "token": token,
                        "notification": {
                            "title": title,
                            "body": body,
                        },
                        "android": {
                            "priority": "high",
                            "notification": {
                                "sound": "default",
                                "channel_id": "safeguard_alerts",
                            },
                        },
                        "data": {
                            "event_type": event_type,
                            "confidence": str(confidence),
                            "user_id": user_id,
                        },
                    }
                },
            )
            logger.info(f"FCM response: {fcm_resp.status_code} — {fcm_resp.text[:200]}")
    except Exception as e:
        logger.warning(f"FCM push failed: {e}")


def _decode_frame(data: bytes) -> np.ndarray:
    """Decode a JPEG/PNG byte buffer into an OpenCV BGR frame."""
    arr = np.frombuffer(data, dtype=np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        raise ValueError("Could not decode frame")
    return frame


# ─── Background Device Monitor ──────────────────────────────────────────────

class DeviceMonitorManager:
    """Manages background asyncio tasks that process streams from registered devices.

    Each "active" device with a stream_url gets a dedicated task that:
      - Opens cv2.VideoCapture on the stream URL
      - Processes frames at ~2 FPS through the shared inference_system
      - Swaps per-device tracking state in/out via save_state/load_state
      - Logs alerts to history + notifications + FCM
      - Updates device.last_seen periodically
      - Reconnects on stream failure (up to 3 retries)
    """

    PROCESS_FPS = 2        # Target frames per second per device
    LAST_SEEN_INTERVAL = 30  # Seconds between last_seen updates
    MAX_RETRIES = 3
    RETRY_BACKOFF = 5      # Seconds between reconnection attempts

    def __init__(self):
        self._tasks: Dict[str, asyncio.Task] = {}          # device_id → task
        self._states: Dict[str, dict] = {}                 # device_id → saved tracking state
        self._statuses: Dict[str, str] = {}                # device_id → "monitoring" | "error" | "connecting"
        self._lock = asyncio.Lock()                        # Serialize model access
        self._frame_counts: Dict[str, int] = {}

    @property
    def active_device_ids(self) -> list:
        return list(self._tasks.keys())

    def get_status(self, device_id: str) -> str:
        if device_id in self._tasks and not self._tasks[device_id].done():
            return self._statuses.get(device_id, "monitoring")
        return "stopped"

    async def start_device(self, device_id: str, stream_url: str, user_id: str):
        """Start background monitoring for a device."""
        if device_id in self._tasks and not self._tasks[device_id].done():
            logger.info(f"Monitor already running for device {device_id}")
            return

        # Initialize per-device state
        if device_id not in self._states:
            if inference_system is not None:
                inference_system.reset_state()
                self._states[device_id] = inference_system.save_state()

        self._frame_counts[device_id] = 0
        self._statuses[device_id] = "connecting"
        task = asyncio.create_task(
            self._monitor_loop(device_id, stream_url, user_id)
        )
        self._tasks[device_id] = task
        logger.info(f"Started monitor for device {device_id} → {stream_url}")

    async def stop_device(self, device_id: str):
        """Stop background monitoring for a device."""
        task = self._tasks.pop(device_id, None)
        if task and not task.done():
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
        self._statuses.pop(device_id, None)
        self._frame_counts.pop(device_id, None)
        # Keep the saved state so it can resume later
        logger.info(f"Stopped monitor for device {device_id}")

    async def _monitor_loop(self, device_id: str, stream_url: str, user_id: str):
        """Main loop for a single device monitor."""
        retries = 0
        frame_interval = 1.0 / self.PROCESS_FPS

        while retries < self.MAX_RETRIES:
            cap = None
            try:
                self._statuses[device_id] = "connecting"
                logger.info(f"Device {device_id}: opening stream (attempt {retries + 1})")
                cap = cv2.VideoCapture(stream_url)

                if not cap.isOpened():
                    raise ConnectionError(f"Cannot open stream: {stream_url}")

                self._statuses[device_id] = "monitoring"
                retries = 0  # Reset on successful connect

                # Fetch user profile for module toggles
                profile = _get_user_profile(user_id)
                child_enabled = profile.get("child_module_enabled", True)
                elderly_enabled = profile.get("elderly_module_enabled", True)

                fps = int(cap.get(cv2.CAP_PROP_FPS)) or 25
                last_seen_time = 0
                import time

                while True:
                    loop_start = time.monotonic()

                    ret, frame = cap.read()
                    if not ret:
                        logger.warning(f"Device {device_id}: frame read failed")
                        break

                    if inference_system is None:
                        await asyncio.sleep(1)
                        continue

                    frame_idx = self._frame_counts.get(device_id, 0)

                    # Swap in per-device state, process, swap out
                    async with self._lock:
                        saved = self._states.get(device_id)
                        if saved:
                            inference_system.load_state(saved)
                        inference_system.child_enabled = child_enabled
                        inference_system.elderly_enabled = elderly_enabled
                        inference_system.camera_mode = "cctv"  # Background devices are typically fixed cameras
                        inference_system.fps = fps

                        _, alerts, _ = inference_system.process_frame(frame, frame_idx)
                        self._states[device_id] = inference_system.save_state()

                    # Log alerts
                    for a in alerts:
                        _log_event(user_id, a)

                    self._frame_counts[device_id] = frame_idx + 1

                    # Update last_seen periodically
                    now = time.monotonic()
                    if now - last_seen_time > self.LAST_SEEN_INTERVAL:
                        last_seen_time = now
                        try:
                            if supabase:
                                supabase.table("devices").update({
                                    "last_seen": datetime.now(timezone.utc).isoformat(),
                                    "status": "active",
                                }).eq("device_id", device_id).execute()
                        except Exception as e:
                            logger.warning(f"Device {device_id}: last_seen update failed: {e}")

                    # Refresh profile every 300 frames
                    if frame_idx % 300 == 0 and frame_idx > 0:
                        profile = _get_user_profile(user_id)
                        child_enabled = profile.get("child_module_enabled", True)
                        elderly_enabled = profile.get("elderly_module_enabled", True)

                    # Throttle to target FPS
                    elapsed = time.monotonic() - loop_start
                    sleep_time = frame_interval - elapsed
                    if sleep_time > 0:
                        await asyncio.sleep(sleep_time)
                    else:
                        await asyncio.sleep(0)  # Yield to event loop

            except asyncio.CancelledError:
                logger.info(f"Device {device_id}: monitor cancelled")
                break
            except Exception as e:
                retries += 1
                logger.error(f"Device {device_id}: error ({retries}/{self.MAX_RETRIES}): {e}")
                self._statuses[device_id] = "error"
                if retries < self.MAX_RETRIES:
                    await asyncio.sleep(self.RETRY_BACKOFF * retries)
            finally:
                if cap is not None:
                    cap.release()

        # Permanent failure — mark offline
        self._statuses[device_id] = "stopped"
        self._tasks.pop(device_id, None)
        try:
            if supabase:
                supabase.table("devices").update({"status": "offline"}).eq("device_id", device_id).execute()
        except Exception:
            pass
        logger.warning(f"Device {device_id}: monitor stopped permanently")


device_monitor = DeviceMonitorManager()


# ─── REST endpoints ──────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok", "engine_loaded": inference_system is not None}


@app.get("/api/history")
async def get_history(user_id: str = Query(...)):
    """Fetch full history for a user (Flutter calls this directly)."""
    if supabase is None:
        raise HTTPException(503, "Database not configured")
    try:
        resp = (
            supabase.table("history")
            .select("*")
            .eq("user_id", user_id)
            .order("timestamp", desc=True)
            .limit(200)
            .execute()
        )
        return {"data": resp.data}
    except Exception as e:
        raise HTTPException(500, str(e))


@app.get("/api/profile")
async def get_profile(user_id: str = Query(...)):
    """Fetch the profile for a user."""
    profile = _get_user_profile(user_id)
    return {"data": profile}


# ─── WebSocket inference ─────────────────────────────────────────────────────

@app.websocket("/ws/inference/{user_id}")
async def websocket_inference(websocket: WebSocket, user_id: str):
    """
    Main real-time inference channel.

    Protocol
    --------
    Client sends:  binary JPEG frame  OR  JSON {"image": "<base64>"}.
    Server sends:  JSON {"alerts": [...], "frame": <int>}  after every frame.

    The engine checks the user's profile (child vs elderly modules) and runs
    only relevant detection logic.

    Query parameter ``camera_mode`` selects calibration profile ('mobile' | 'cctv').
    """
    await websocket.accept()
    logger.info(f"WebSocket connected — user {user_id}")

    if inference_system is None:
        await websocket.send_json({"error": "Engine not loaded"})
        await websocket.close()
        return

    # Camera mode from query parameter (default 'mobile')
    camera_mode = websocket.query_params.get("camera_mode", "mobile")

    # Fetch user preferences
    profile = _get_user_profile(user_id)
    child_enabled = profile.get("child_module_enabled", True)
    elderly_enabled = profile.get("elderly_module_enabled", True)

    logger.info(f"User {user_id} — child={child_enabled}, elderly={elderly_enabled}, camera_mode={camera_mode}")

    # Reset engine state and set module toggles for this session
    inference_system.reset_state()
    inference_system.child_enabled = child_enabled
    inference_system.elderly_enabled = elderly_enabled
    inference_system.camera_mode = camera_mode
    frame_count = 0

    try:
        while True:
            raw = await websocket.receive()

            # Handle binary or text messages
            if "bytes" in raw and raw["bytes"]:
                frame_bytes = raw["bytes"]
            elif "text" in raw and raw["text"]:
                payload = json.loads(raw["text"])
                if "image" in payload:
                    frame_bytes = base64.b64decode(payload["image"])
                else:
                    # Control message — skip
                    continue
            else:
                continue

            try:
                frame = _decode_frame(frame_bytes)
            except ValueError:
                await websocket.send_json({"error": "Bad frame", "frame": frame_count})
                continue

            # Live profile refresh every 60 frames (~2s) so toggle changes take effect
            if frame_count % 60 == 0 and frame_count > 0:
                profile = _get_user_profile(user_id)
                inference_system.child_enabled = profile.get("child_module_enabled", True)
                inference_system.elderly_enabled = profile.get("elderly_module_enabled", True)

            # Run inference (engine skips disabled modules internally)
            _, alerts, detections = inference_system.process_frame(frame, frame_count)

            # Log to Supabase
            for a in alerts:
                _log_event(user_id, a)

            # Send lightweight detection metadata (Flutter draws overlays on camera preview)
            await websocket.send_json({
                "alerts": alerts,
                "detections": detections,
                "frame": frame_count,
            })

            frame_count += 1

    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected — user {user_id}, {frame_count} frames processed.")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        try:
            await websocket.send_json({"error": str(e)})
        except Exception:
            pass

# ─── WebSocket video file processing ─────────────────────────────────────────

@app.websocket("/ws/process-video/{user_id}")
async def websocket_process_video(websocket: WebSocket, user_id: str):
    """
    Server-side video processing channel.

    Protocol
    --------
    Client sends:  JSON {"video": "<base64>", "filename": "..."} as the first message.
    Server sends:  JSON {"alerts": [...], "frame": <int>, "annotated_frame": "<base64>", "status": "processing"}
                   for each frame, then {"status": "done", "total_frames": N, "total_alerts": N}.
    """
    await websocket.accept()
    logger.info(f"Video processing WS connected — user {user_id}")

    if inference_system is None:
        await websocket.send_json({"error": "Engine not loaded"})
        await websocket.close()
        return

    try:
        # Receive the video file
        raw = await websocket.receive()
        if "text" in raw and raw["text"]:
            payload = json.loads(raw["text"])
            video_bytes = base64.b64decode(payload.get("video", ""))
            filename = payload.get("filename", "upload.mp4")
        elif "bytes" in raw and raw["bytes"]:
            video_bytes = raw["bytes"]
            filename = "upload.mp4"
        else:
            await websocket.send_json({"error": "No video data received"})
            await websocket.close()
            return

        # Write to temp file for OpenCV
        import tempfile
        tmp_fd, tmp_path = tempfile.mkstemp(suffix=f".{filename.rsplit('.', 1)[-1]}")
        os.close(tmp_fd)
        with open(tmp_path, "wb") as f:
            f.write(video_bytes)

        cap = cv2.VideoCapture(tmp_path)
        if not cap.isOpened():
            await websocket.send_json({"error": f"Cannot open video: {filename}"})
            os.unlink(tmp_path)
            await websocket.close()
            return

        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        logger.info(f"Processing video: {filename} ({total} frames)")

        # Fetch user preferences and set module toggles
        camera_mode = payload.get("camera_mode", "mobile")
        profile = _get_user_profile(user_id)
        inference_system.reset_state()
        inference_system.child_enabled = profile.get("child_module_enabled", True)
        inference_system.elderly_enabled = profile.get("elderly_module_enabled", True)
        inference_system.camera_mode = camera_mode
        logger.info(f"Video camera_mode={camera_mode}")
        fps = int(cap.get(cv2.CAP_PROP_FPS)) or 25
        inference_system.fps = fps
        frame_count = 0
        all_alerts = []
        MAX_DISPLAY_W = 640     # Resize before encode for bandwidth

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            annotated, alerts, _ = inference_system.process_frame(frame, frame_count)
            all_alerts.extend(alerts)

            # Resize for bandwidth if needed
            h, w = annotated.shape[:2]
            if w > MAX_DISPLAY_W:
                scale = MAX_DISPLAY_W / w
                annotated = cv2.resize(annotated, (MAX_DISPLAY_W, int(h * scale)))

            _, jpeg_buf = cv2.imencode(
                ".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, 50]
            )
            frame_b64 = base64.b64encode(jpeg_buf.tobytes()).decode("ascii")

            # Stream back to Flutter
            await websocket.send_json({
                "alerts": alerts,
                "frame": frame_count,
                "total_frames": total,
                "annotated_frame": frame_b64,
                "status": "processing",
            })

            for a in alerts:
                _log_event(user_id, a)

            frame_count += 1
            await asyncio.sleep(0)

        cap.release()
        os.unlink(tmp_path)

        await websocket.send_json({
            "status": "done",
            "total_frames": frame_count,
            "total_alerts": len(all_alerts),
        })
        logger.info(f"Video processing done: {frame_count} frames, {len(all_alerts)} alerts")

    except WebSocketDisconnect:
        logger.info(f"Video processing WS disconnected — user {user_id}")
    except Exception as e:
        logger.error(f"Video processing error: {e}")
        try:
            await websocket.send_json({"error": str(e)})
        except Exception:
            pass


# ─── WebSocket RTSP/stream processing ────────────────────────────────────────

@app.websocket("/ws/stream/{user_id}")
async def websocket_stream(websocket: WebSocket, user_id: str):
    """
    Server-side RTSP/HTTP stream processing.

    Protocol
    --------
    Client sends:  JSON {"url": "<rtsp://...>"} as the first message.
    Server sends:  JSON {"alerts": [...], "frame": <int>, "annotated_frame": "<base64>", "status": "streaming"}
                   for each frame, then {"status": "done"} when stream ends or client disconnects.
    """
    await websocket.accept()
    logger.info(f"Stream WS connected — user {user_id}")

    if inference_system is None:
        await websocket.send_json({"error": "Engine not loaded"})
        await websocket.close()
        return

    try:
        # Receive the stream URL
        raw = await websocket.receive()
        if "text" in raw and raw["text"]:
            payload = json.loads(raw["text"])
            stream_url = payload.get("url", "")
        else:
            await websocket.send_json({"error": "No stream URL received"})
            await websocket.close()
            return

        if not stream_url:
            await websocket.send_json({"error": "Empty stream URL"})
            await websocket.close()
            return

        logger.info(f"Opening stream: {stream_url}")
        cap = cv2.VideoCapture(stream_url)
        if not cap.isOpened():
            await websocket.send_json({"error": f"Cannot open stream: {stream_url}"})
            await websocket.close()
            return

        # Fetch user preferences and set module toggles
        camera_mode = payload.get("camera_mode", "mobile")
        profile = _get_user_profile(user_id)
        inference_system.reset_state()
        inference_system.child_enabled = profile.get("child_module_enabled", True)
        inference_system.elderly_enabled = profile.get("elderly_module_enabled", True)
        inference_system.camera_mode = camera_mode
        logger.info(f"Stream camera_mode={camera_mode}")
        fps = int(cap.get(cv2.CAP_PROP_FPS)) or 25
        inference_system.fps = fps
        frame_count = 0
        all_alerts = []

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                # Stream ended or lost connection — wait a bit and retry
                await asyncio.sleep(0.5)
                ret, frame = cap.read()
                if not ret:
                    break

            annotated, alerts, _ = inference_system.process_frame(frame, frame_count)
            all_alerts.extend(alerts)

            # Encode annotated frame
            _, jpeg_buf = cv2.imencode(
                ".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, 60]
            )
            frame_b64 = base64.b64encode(jpeg_buf.tobytes()).decode("ascii")

            # Stream back to Flutter
            try:
                await websocket.send_json({
                    "alerts": alerts,
                    "frame": frame_count,
                    "annotated_frame": frame_b64,
                    "status": "streaming",
                })
            except Exception:
                break  # Client disconnected

            for a in alerts:
                _log_event(user_id, a)

            frame_count += 1
            await asyncio.sleep(0)  # Yield to event loop

        cap.release()
        try:
            await websocket.send_json({
                "status": "done",
                "total_frames": frame_count,
                "total_alerts": len(all_alerts),
            })
        except Exception:
            pass
        logger.info(f"Stream done: {frame_count} frames, {len(all_alerts)} alerts")

    except WebSocketDisconnect:
        logger.info(f"Stream WS disconnected — user {user_id}")
    except Exception as e:
        logger.error(f"Stream error: {e}")
        try:
            await websocket.send_json({"error": str(e)})
        except Exception:
            pass


# ─── Gemini report (called by Flutter) ────────────────────────────────────────

@app.get("/api/gemini-report")
async def gemini_report(user_id: str = Query(...)):
    """
    Aggregates the last 1 hour of history and generates an AI summary via Gemini.
    Returns a graceful message when DB or API keys are unavailable.
    """
    groq_check = os.getenv("GROQ_API_KEY", "")
    if not groq_check:
        return {"report": "⚠️ GROQ_API_KEY not set in .env. Get a free key at https://console.groq.com"}

    if supabase is None:
        return {"report": "⚠️ Database is not configured. Unable to retrieve event history. Please check your SUPABASE_SERVICE_ROLE_KEY in the .env file."}

    try:
        from datetime import timedelta
        cutoff = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
        resp = (
            supabase.table("history")
            .select("*")
            .eq("user_id", user_id)
            .gte("timestamp", cutoff)
            .order("timestamp", desc=False)
            .execute()
        )
        events = resp.data or []
    except Exception as e:
        logger.error(f"Gemini report DB query failed: {e}")
        return {"report": f"⚠️ Could not retrieve event history: {e}"}

    if not events:
        return {"report": "✅ No events were detected for this user in the last hour. Everything appears to be normal."}

    # ── Cluster raw events into distinct incidents (60s gap = new incident) ──
    from datetime import timedelta
    from dateutil import parser as dtparser

    GAP_THRESHOLD = timedelta(seconds=60)  # gap > 60s between same type = new incident

    incidents = []  # list of {type, start, end, count, avg_confidence}
    for e in events:
        etype = e.get("event_type", "unknown")
        try:
            ts = dtparser.parse(e.get("timestamp", ""))
        except Exception:
            continue
        conf = float(e.get("confidence", 0) or 0)

        # Check if this extends the last incident of same type
        merged = False
        if incidents and incidents[-1]["type"] == etype:
            last = incidents[-1]
            if (ts - last["end"]) <= GAP_THRESHOLD:
                last["end"] = ts
                last["count"] += 1
                last["total_conf"] += conf
                merged = True

        if not merged:
            incidents.append({
                "type": etype,
                "start": ts,
                "end": ts,
                "count": 1,
                "total_conf": conf,
            })

    # Build human-readable incident summary
    incident_lines = []
    for i, inc in enumerate(incidents, 1):
        avg_conf = inc["total_conf"] / inc["count"] if inc["count"] else 0
        start_str = inc["start"].strftime("%I:%M:%S %p")
        duration = (inc["end"] - inc["start"]).total_seconds()
        if duration < 2:
            time_desc = f"at {start_str}"
        else:
            time_desc = f"from {start_str} lasting ~{int(duration)}s"
        incident_lines.append(
            f"  {i}. {inc['type']} — {time_desc} "
            f"(avg confidence: {avg_conf:.0%}, {inc['count']} raw detections)"
        )

    incident_summary = "\n".join(incident_lines)

    prompt = (
        "You are an AI caregiver assistant for a home safety surveillance system.\n"
        "Below is a summary of DISTINCT INCIDENTS detected in the LAST 1 HOUR.\n"
        "These have already been clustered from raw frame-level detections.\n"
        "Events within 60 seconds of each other are grouped as one incident.\n"
        "If the same event type appears again after a 60+ second gap, it is a SEPARATE incident — "
        "this is important and should be highlighted.\n\n"
        "Generate a CONCISE report (max 200 words) for a family caregiver that:\n"
        "1. States the number of distinct incidents and their times\n"
        "2. Highlights if multiple separate incidents occurred (e.g. fell, recovered, then fell again)\n"
        "3. Suggests concrete next steps if warranted\n"
        "4. Uses a compassionate but professional tone\n\n"
        "DO NOT include any sign-offs, salutations, greetings, 'Best regards', '[Your Name]', or letter formatting. "
        "Just output the report content directly.\n\n"
        f"Total distinct incidents: {len(incidents)}\n"
        f"Incidents:\n{incident_summary}"
    )

    # Call Groq API (free tier, generous limits)
    import httpx
    groq_key = os.getenv("GROQ_API_KEY", "")
    groq_model = os.getenv("GROQ_MODEL", "llama-3.1-8b-instant")
    if not groq_key:
        return {"report": "⚠️ GROQ_API_KEY not set in .env. Get a free key at https://console.groq.com"}
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(
                "https://api.groq.com/openai/v1/chat/completions",
                headers={"Authorization": f"Bearer {groq_key}"},
                json={
                    "model": groq_model,
                    "messages": [{"role": "user", "content": prompt}],
                    "temperature": 0.3,
                    "max_tokens": 512,
                },
            )
            resp.raise_for_status()
            body = resp.json()
            report_text = body["choices"][0]["message"]["content"]

            # Cache the generated summary so the UI can replay history without
            # re-billing Groq. Best-effort — never fail the request on this.
            try:
                start_iso = incidents[0]["start"].isoformat() if incidents else cutoff
                end_iso = incidents[-1]["end"].isoformat() if incidents else datetime.now(timezone.utc).isoformat()
                supabase.table("incident_summaries").insert({
                    "user_id": user_id,
                    "start_time": start_iso,
                    "end_time": end_iso,
                    "summary_text": report_text,
                    "incident_count": len(incidents),
                }).execute()
            except Exception as e:
                logger.warning(f"Failed to cache incident summary: {e}")

            return {"report": report_text}
    except Exception as e:
        logger.error(f"Groq API error: {e}")
        return {"report": f"⚠️ Could not generate report: {e}"}


# ─── First Aid RAG Chat (called by Flutter) ──────────────────────────────────

@app.post("/api/chat")
async def chat(request: Request):
    """
    RAG-powered First Aid chatbot endpoint.
    Expects JSON:
        {
            "message": str,
            "user_id": str,
            "session_id": str | null,   # optional — server creates one if absent
            "history": [{"role": str, "text": str}, ...]
        }
    Returns JSON:
        {"reply": str, "sources": [...], "session_id": str}
    """
    body = await request.json()
    user_message = body.get("message", "").strip()
    chat_history = body.get("history", [])
    user_id = body.get("user_id", "")
    session_id = body.get("session_id")

    if not user_message:
        return {"reply": "Please enter a message.", "sources": [], "session_id": session_id}

    if rag_service is None or not rag_service.ready:
        return {
            "reply": "⚠️ The First Aid knowledge base is not loaded. "
                     "Please run `python generate_embeddings.py` to build the index.",
            "sources": [],
            "session_id": session_id,
        }

    # Ensure a chat session exists for this exchange.
    if supabase is not None and user_id:
        try:
            if not session_id:
                resp = supabase.table("chat_sessions").insert({
                    "user_id": user_id,
                    "title": user_message[:60],
                }).execute()
                session_id = (resp.data or [{}])[0].get("session_id")

            if session_id:
                supabase.table("chat_messages").insert({
                    "session_id": session_id,
                    "sender": "user",
                    "message_text": user_message,
                }).execute()
        except Exception as e:
            logger.warning(f"Chat session persistence failed: {e}")

    result = await rag_service.query(user_message, chat_history)

    if supabase is not None and session_id:
        try:
            supabase.table("chat_messages").insert({
                "session_id": session_id,
                "sender": "bot",
                "message_text": result.get("reply", ""),
                "sources": result.get("sources", []),
            }).execute()
        except Exception as e:
            logger.warning(f"Bot message persistence failed: {e}")

    result["session_id"] = session_id
    return result


# ─── Devices CRUD ────────────────────────────────────────────────────────────

@app.get("/api/devices")
async def list_devices(user_id: str = Query(...)):
    if supabase is None:
        raise HTTPException(503, "Database not configured")
    resp = (
        supabase.table("devices")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .execute()
    )
    return {"data": resp.data or []}


@app.post("/api/devices")
async def create_device(request: Request):
    if supabase is None:
        raise HTTPException(503, "Database not configured")
    body = await request.json()
    if not body.get("user_id") or not body.get("device_name"):
        raise HTTPException(400, "user_id and device_name are required")
    row = {
        "user_id":     body["user_id"],
        "device_name": body["device_name"],
        "device_type": body.get("device_type", "camera"),
        "stream_url":  body.get("stream_url"),
        "location":    body.get("location"),
        "status":      body.get("status", "inactive"),
    }
    resp = supabase.table("devices").insert(row).execute()
    created = (resp.data or [None])[0]
    # Auto-start if active with a stream URL
    if created and created.get("status") == "active" and created.get("stream_url"):
        await device_monitor.start_device(created["device_id"], created["stream_url"], created["user_id"])
    return {"data": created}


@app.patch("/api/devices/{device_id}")
async def update_device(device_id: str, request: Request):
    if supabase is None:
        raise HTTPException(503, "Database not configured")
    body = await request.json()
    allowed = {"device_name", "device_type", "stream_url", "location", "status", "last_seen"}
    patch = {k: v for k, v in body.items() if k in allowed}
    if not patch:
        raise HTTPException(400, "No updatable fields provided")
    resp = supabase.table("devices").update(patch).eq("device_id", device_id).execute()
    updated = (resp.data or [None])[0]
    # Start/stop monitor based on status change
    if updated and "status" in patch:
        if patch["status"] == "active" and updated.get("stream_url"):
            await device_monitor.start_device(device_id, updated["stream_url"], updated["user_id"])
        elif patch["status"] in ("inactive", "offline"):
            await device_monitor.stop_device(device_id)
    return {"data": updated}


@app.delete("/api/devices/{device_id}")
async def delete_device(device_id: str):
    if supabase is None:
        raise HTTPException(503, "Database not configured")
    await device_monitor.stop_device(device_id)
    supabase.table("devices").delete().eq("device_id", device_id).execute()
    return {"status": "deleted"}


@app.post("/api/devices/{device_id}/start")
async def start_device_monitor(device_id: str):
    """Start background monitoring for a device."""
    if supabase is None:
        raise HTTPException(503, "Database not configured")
    resp = supabase.table("devices").select("*").eq("device_id", device_id).execute()
    if not resp.data:
        raise HTTPException(404, "Device not found")
    d = resp.data[0]
    if not d.get("stream_url"):
        raise HTTPException(400, "Device has no stream_url configured")
    await device_monitor.start_device(device_id, d["stream_url"], d["user_id"])
    supabase.table("devices").update({"status": "active"}).eq("device_id", device_id).execute()
    return {"status": "started", "device_id": device_id}


@app.post("/api/devices/{device_id}/stop")
async def stop_device_monitor(device_id: str):
    """Stop background monitoring for a device."""
    await device_monitor.stop_device(device_id)
    if supabase:
        supabase.table("devices").update({"status": "inactive"}).eq("device_id", device_id).execute()
    return {"status": "stopped", "device_id": device_id}


@app.get("/api/devices/{device_id}/status")
async def get_device_monitor_status(device_id: str):
    """Get the monitoring status of a device."""
    return {
        "device_id": device_id,
        "monitor_status": device_monitor.get_status(device_id),
    }


# ─── Notifications ───────────────────────────────────────────────────────────

@app.get("/api/notifications")
async def list_notifications(
    user_id: str = Query(...),
    unread_only: bool = Query(False),
    limit: int = Query(100),
):
    if supabase is None:
        raise HTTPException(503, "Database not configured")
    q = supabase.table("notifications").select("*").eq("user_id", user_id)
    if unread_only:
        q = q.eq("read_status", False)
    resp = q.order("sent_at", desc=True).limit(limit).execute()
    return {"data": resp.data or []}


@app.patch("/api/notifications/{notification_id}")
async def mark_notification_read(notification_id: str, request: Request):
    if supabase is None:
        raise HTTPException(503, "Database not configured")
    body = await request.json()
    read = bool(body.get("read_status", True))
    resp = (
        supabase.table("notifications")
        .update({"read_status": read})
        .eq("notification_id", notification_id)
        .execute()
    )
    return {"data": (resp.data or [None])[0]}


# ─── Incident summaries (cached Gemini reports) ──────────────────────────────

@app.get("/api/summaries")
async def list_summaries(user_id: str = Query(...), limit: int = Query(50)):
    if supabase is None:
        raise HTTPException(503, "Database not configured")
    resp = (
        supabase.table("incident_summaries")
        .select("*")
        .eq("user_id", user_id)
        .order("generated_at", desc=True)
        .limit(limit)
        .execute()
    )
    return {"data": resp.data or []}


# ─── Chat history ────────────────────────────────────────────────────────────

@app.get("/api/chat/sessions")
async def list_chat_sessions(user_id: str = Query(...)):
    if supabase is None:
        raise HTTPException(503, "Database not configured")
    resp = (
        supabase.table("chat_sessions")
        .select("*")
        .eq("user_id", user_id)
        .order("started_at", desc=True)
        .execute()
    )
    return {"data": resp.data or []}


@app.get("/api/chat/sessions/{session_id}/messages")
async def list_chat_messages(session_id: str):
    if supabase is None:
        raise HTTPException(503, "Database not configured")
    resp = (
        supabase.table("chat_messages")
        .select("*")
        .eq("session_id", session_id)
        .order("timestamp", desc=False)
        .execute()
    )
    return {"data": resp.data or []}


# ─── Entry point ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
