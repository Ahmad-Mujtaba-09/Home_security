"""
HomeSafetyInference.py
======================
Combined inference: TCN fall detection + heuristic + hazard + child safety.

"""

import os
import gc
import tempfile
import subprocess
import logging
import time
from collections import deque, Counter
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Any

import numpy as np
import cv2
import torch
import torch.nn as nn
from scipy.signal import savgol_filter
from ultralytics import YOLO

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger(__name__)

# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────

KP_NOSE = 0
KP_L_SHOULDER = 5
KP_R_SHOULDER = 6
KP_L_ELBOW = 7
KP_R_ELBOW = 8
KP_L_WRIST = 9
KP_R_WRIST = 10
KP_L_HIP = 11
KP_R_HIP = 12
KP_L_KNEE = 13
KP_R_KNEE = 14
KP_L_ANKLE = 15
KP_R_ANKLE = 16
N_KP = 17

WINDOW = 30
FEATURE_DIM = 61
KP_CONF = 0.10
TCN_STRIDE = 5  # run TCN every N frames; return cached value between runs

ANGLE_TRIPLETS = [
    (KP_L_SHOULDER, KP_L_ELBOW, KP_L_WRIST),
    (KP_R_SHOULDER, KP_R_ELBOW, KP_R_WRIST),
    (KP_L_ELBOW, KP_L_SHOULDER, KP_L_HIP),
    (KP_R_ELBOW, KP_R_SHOULDER, KP_R_HIP),
    (KP_L_SHOULDER, KP_L_HIP, KP_L_KNEE),
    (KP_R_SHOULDER, KP_R_HIP, KP_R_KNEE),
    (KP_L_HIP, KP_L_KNEE, KP_L_ANKLE),
    (KP_R_HIP, KP_R_KNEE, KP_R_ANKLE),
]

COG_WEIGHTS = {
    KP_NOSE: 0.08,
    KP_L_SHOULDER: 0.10,
    KP_R_SHOULDER: 0.10,
    KP_L_HIP: 0.15,
    KP_R_HIP: 0.15,
    KP_L_KNEE: 0.10,
    KP_R_KNEE: 0.10,
    KP_L_ANKLE: 0.11,
    KP_R_ANKLE: 0.11,
}

HAZARD_NAMES = {0: "knife", 1: "fire", 2: "stairs", 3: "oven", 4: "stove"}
HAZARD_CONF = {"knife": 0.60, "fire": 0.50, "stairs": 0.30, "oven": 0.25, "stove": 0.25}
HAZARD_PROXIMITY = {
    "knife": 0.18,
    "fire": 0.30,
    "oven": 0.22,
    "stove": 0.22,
    "stairs": 0.28,
}

COLOR = {
    "FALL": (0, 0, 255),
    "FALLING": (0, 60, 255),
    "PRE_FALL": (0, 30, 255),
    "STANDING": (0, 255, 0),
    "CHILD": (255, 105, 180),
    "HAZARD": (0, 165, 255),
    "ALERT": (0, 0, 255),
}

# FIX 7: derive HEURISTIC_WEIGHT so it is always consistent with TCN_WEIGHT
TCN_WEIGHT = 0.70
HEURISTIC_WEIGHT = 1.0 - TCN_WEIGHT  # 0.40 — never manually sync two constants

# States that indicate a person is still on the floor after a fall.
# Used by the inactivity timer to persist through LYING transitions.
_FLOOR_STATES = frozenset({"FALL", "LYING"})


def _calibrated_heuristic_score(state: str) -> float:
    """
    Convert heuristic state to a fall confidence score in [0, 1].

    Values are tuned so:
      - FALL / FALLING:  can raise the blended score above the 0.65 threshold
        even when the TCN is uncertain. This is intentional for confirmed events.
      - PRE_FALL (0.60): stays below the default 0.65 threshold on its own so
        the TCN must corroborate it (see FIX 4 in _process_person).
      - Non-fall states: stay well below threshold; cannot trigger alone.

    Note: true statistical calibration requires Platt scaling on a held-out
    validation set. These values are heuristically reasonable but not
    empirically measured.
    """
    return {
        "FALL": 0.95,
        "FALLING": 0.82,
        "PRE_FALL": 0.60,  # FIX 4: lowered from 0.68 → below default threshold
        "LYING": 0.35,
        "SITTING": 0.12,
        "UNSTABLE": 0.22,
        "WALKING": 0.05,
        "STANDING": 0.03,
        "UNKNOWN": 0.00,
    }.get(state, 0.0)


# ─────────────────────────────────────────────────────────────────────────────
# TCN model  — architecture must match training exactly
# ─────────────────────────────────────────────────────────────────────────────


class ResBlock(nn.Module):
    # FIX 1: Dropout 0.5 → 0.2 to match training notebook (Cell 28)
    def __init__(self, channels: int, dilation: int):
        super().__init__()
        self.net = nn.Sequential(
            nn.Conv1d(
                channels, channels, 3, padding=dilation, dilation=dilation, bias=False
            ),
            nn.BatchNorm1d(channels),
            nn.ReLU(inplace=True),
            nn.Dropout(0.2),
            nn.Conv1d(
                channels, channels, 3, padding=dilation, dilation=dilation, bias=False
            ),
            nn.BatchNorm1d(channels),
        )
        self.act = nn.ReLU(inplace=True)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.act(x + self.net(x))


class TCN(nn.Module):
    def __init__(
        self, feature_dim: int = FEATURE_DIM, n_classes: int = 2, channels: int = 128
    ):
        super().__init__()
        self.input_proj = nn.Sequential(
            nn.Conv1d(feature_dim, channels, 1, bias=False),
            nn.BatchNorm1d(channels),
            nn.ReLU(inplace=True),
        )
        self.blocks = nn.Sequential(
            ResBlock(channels, 1),
            ResBlock(channels, 2),
            ResBlock(channels, 4),
        )
        # FIX 1: head Dropout 0.3 → 0.5 to match training notebook (Cell 28)
        self.head = nn.Sequential(
            nn.Linear(channels, 64),
            nn.ReLU(inplace=True),
            nn.Dropout(0.5),
            nn.Linear(64, n_classes),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = x.permute(0, 2, 1)
        x = self.input_proj(x)
        x = self.blocks(x)
        x = x.mean(dim=-1)
        return self.head(x)


# ─────────────────────────────────────────────────────────────────────────────
# Feature engineering  (identical to training pipeline — do not modify)
# ─────────────────────────────────────────────────────────────────────────────

# def interpolate_and_smooth(
#     kp_seq: List[Optional[np.ndarray]],
#     window_length: int = 9,
#     polyorder: int = 3,
# ) -> np.ndarray:
#     """
#     FIX 2: Rewritten with pure numpy — removes pandas DataFrame allocation from
#     the hot path.

#     Original code called pd.DataFrame(...).interpolate() every TCN_STRIDE frames
#     per tracked person. At 30fps with 4 persons that was ~40 DataFrame + Series
#     allocations per second, each requiring a Python GC cycle to free.

#     Replacement uses np.interp() for linear gap-filling (same semantics as
#     pandas 'linear' + limit_direction='both') and the same Savitzky-Golay
#     filter.  Output shape and dtype are unchanged: (N, 17, 2) float32.
#     """
#     n   = len(kp_seq)
#     arr = np.full((n, N_KP * 2), np.nan, dtype=np.float32)
#     for i, kp in enumerate(kp_seq):
#         if kp is not None:
#             arr[i] = kp.flatten()

#     x = np.arange(n, dtype=np.float32)
#     for col in range(arr.shape[1]):
#         y     = arr[:, col]
#         valid = np.isfinite(y)
#         n_valid = valid.sum()
#         if n_valid >= 2:
#             arr[:, col] = np.interp(x, x[valid], y[valid])
#         elif n_valid == 1:
#             arr[:, col] = y[valid][0]
#         else:
#             arr[:, col] = 0.0

#     wl = min(window_length, n)
#     if wl % 2 == 0:
#         wl -= 1
#     if wl > polyorder:
#         for col in range(arr.shape[1]):
#             arr[:, col] = savgol_filter(arr[:, col], wl, polyorder)

#     return arr.reshape(-1, N_KP, 2).astype(np.float32)


def interpolate_and_smooth(
    kp_seq: List[Optional[np.ndarray]],
    window_length: int = 15,
    polyorder: int = 3,
) -> np.ndarray:
    n = len(kp_seq)
    # 1. Convert to numpy array (N, 34) because 17 keypoints * 2 (x,y)
    arr = np.full((n, N_KP * 2), np.nan, dtype=np.float32)
    for i, kp in enumerate(kp_seq):
        if kp is not None:
            arr[i] = kp.flatten()

    x = np.arange(n, dtype=np.float32)
    for col in range(arr.shape[1]):
        y = arr[:, col]
        valid = np.isfinite(y)
        n_valid = valid.sum()

        if n_valid >= 2:
            # Linear gap filling
            arr[:, col] = np.interp(x, x[valid], y[valid])
        elif n_valid == 1:
            # Persistent value if only one frame exists
            arr[:, col] = y[valid][0]
        else:
            # Avoid (0,0) jumps which kill TCN features
            # 0.5 is the normalized center of the screen
            arr[:, col] = 0.5

    # 2. Savitzky-Golay Smoothing
    # wl MUST be odd and window_length > polyorder
    wl = min(window_length, n)
    if wl % 2 == 0:
        wl -= 1

    # CRITICAL FIX: Savitzky-Golay requires wl > polyorder
    # If the window is too small (e.g., during the first few frames), skip smoothing
    if wl > polyorder and n >= wl:
        try:
            # Apply filter along each coordinate column
            arr = savgol_filter(arr, wl, polyorder, axis=0)
        except Exception:
            # Fallback if the signal is too short or noisy for the filter
            pass

    return arr.reshape(-1, N_KP, 2).astype(np.float32)


def _jangle(a: np.ndarray, v: np.ndarray, b: np.ndarray) -> float:
    ra = a - v
    rb = b - v
    na = np.linalg.norm(ra)
    nb = np.linalg.norm(rb)
    if na < 1e-8 or nb < 1e-8:
        return 0.0
    return float(np.arccos(np.clip(np.dot(ra, rb) / (na * nb), -1.0, 1.0)))


def extract_features(xy_window: np.ndarray) -> np.ndarray:
    """
    (WINDOW, 17, 2) -> (WINDOW, 61).

    Must be byte-for-byte identical to training Cell 9.
    Input is already interpolated — do NOT add velocity clipping here.
    Teleportation spikes are prevented upstream by interpolate_and_smooth.
    """
    norm_frames = []
    for xy in xy_window:
        hip = (xy[KP_L_HIP] + xy[KP_R_HIP]) / 2.0
        spine = (xy[KP_L_SHOULDER] + xy[KP_R_SHOULDER]) / 2.0 - hip
        slen = np.linalg.norm(spine) + 1e-8
        norm_frames.append((xy - hip) / slen)
    nf = np.stack(norm_frames)

    feats = []
    for t in range(WINDOW):
        xy = nf[t]
        raw = xy.flatten()
        vel = (
            np.zeros(N_KP, dtype=np.float32)
            if t == 0
            else np.linalg.norm(nf[t] - nf[t - 1], axis=1).astype(np.float32)
        )
        ang = np.array(
            [_jangle(xy[a], xy[v], xy[b]) for (a, v, b) in ANGLE_TRIPLETS],
            dtype=np.float32,
        )
        spine = (xy[KP_L_SHOULDER] + xy[KP_R_SHOULDER]) / 2 - (
            xy[KP_L_HIP] + xy[KP_R_HIP]
        ) / 2
        sl = np.linalg.norm(spine)
        ta = float(np.arccos(np.clip(-spine[1] / sl, -1.0, 1.0))) if sl > 1e-8 else 0.0
        ll = float(np.arctan2(spine[0], -spine[1])) if sl > 1e-8 else 0.0
        feats.append(np.concatenate([raw, vel, ang, [ta, ll]]))
    return np.stack(feats).astype(np.float32)


# ─────────────────────────────────────────────────────────────────────────────
# Heuristic classifier
# ─────────────────────────────────────────────────────────────────────────────


def _gkp(kp_list: List, idx: int) -> Optional[np.ndarray]:
    return kp_list[idx] if idx < len(kp_list) else None


class HeuristicClassifier:
    """
    Rich per-person heuristic fall detector.
    Returns (state: str, score: float) where score is calibrated [0,1].
    """

    def __init__(
        self,
        fall_angle: float = 60.0,
        hip_height: float = 0.50,
        velocity: float = 0.04,
        cog_vel: float = 30.0,
        cog_stability: float = 50.0,
        debounce: int = 3,
    ):
        self.FALL_ANGLE = fall_angle
        self.HIP_HEIGHT = hip_height
        self.VELOCITY = velocity
        self.COG_VEL = cog_vel
        self.COG_STABILITY = cog_stability
        self.DEBOUNCE = debounce
        self.prev_kp: Dict[int, Any] = {}
        self.prev_cog: Dict[int, Any] = {}
        self.deb_count: Dict[int, int] = {}
        self.prev_state: Dict[int, str] = {}

    def reset(self) -> None:
        self.prev_kp.clear()
        self.prev_cog.clear()
        self.deb_count.clear()
        self.prev_state.clear()

    def _angle(self, kp: List) -> Optional[float]:
        ls = _gkp(kp, KP_L_SHOULDER)
        rs = _gkp(kp, KP_R_SHOULDER)
        lh = _gkp(kp, KP_L_HIP)
        rh = _gkp(kp, KP_R_HIP)
        if any(v is None for v in [ls, rs, lh, rh]):
            return None
        sc = (ls + rs) / 2
        hc = (lh + rh) / 2
        return float(np.abs(np.degrees(np.arctan2(hc[0] - sc[0], hc[1] - sc[1]))))

    def _hip_h(self, kp: List, fh: int) -> Optional[float]:
        lh = _gkp(kp, KP_L_HIP)
        rh = _gkp(kp, KP_R_HIP)
        if lh is None or rh is None:
            return None
        return 1.0 - ((lh[1] + rh[1]) / 2) / fh

    def _vel(self, kp: List, pkp: Optional[List], fh: int) -> float:
        if pkp is None:
            return 0.0
        a = _gkp(kp, KP_L_HIP)
        b = _gkp(kp, KP_R_HIP)
        c = _gkp(pkp, KP_L_HIP)
        d = _gkp(pkp, KP_R_HIP)
        if any(v is None for v in [a, b, c, d]):
            return 0.0
        return float(np.abs((a[1] + b[1]) / 2 - (c[1] + d[1]) / 2)) / fh

    def _moving(self, kp: List, pkp: Optional[List], thr: int = 5) -> bool:
        if pkp is None:
            return False
        la = _gkp(kp, KP_L_ANKLE)
        ra = _gkp(kp, KP_R_ANKLE)
        lp = _gkp(pkp, KP_L_ANKLE)
        rp = _gkp(pkp, KP_R_ANKLE)
        if any(v is None for v in [la, ra, lp, rp]):
            return False
        return float(np.mean([np.linalg.norm(la - lp), np.linalg.norm(ra - rp)])) > thr

    def _cog(self, kp: List) -> Optional[np.ndarray]:
        wx = wy = tw = 0.0
        for idx, w in COG_WEIGHTS.items():
            pt = _gkp(kp, idx)
            if pt is not None:
                wx += pt[0] * w
                wy += pt[1] * w
                tw += w
        return np.array([wx / tw, wy / tw]) if tw >= 0.5 else None

    def _cog_stable(self, cog: Optional[np.ndarray], kp: List) -> bool:
        if cog is None:
            return True
        la = _gkp(kp, KP_L_ANKLE)
        ra = _gkp(kp, KP_R_ANKLE)
        if la is None or ra is None:
            return True
        return abs(cog[0] - (la[0] + ra[0]) / 2) < self.COG_STABILITY

    def _inverted(self, kp: List, fh: int) -> bool:
        """
        Head below hips in image coords (Y increases downward).
        Margin is 2% of frame height — resolution-relative.
        """
        nose = _gkp(kp, KP_NOSE)
        lh = _gkp(kp, KP_L_HIP)
        rh = _gkp(kp, KP_R_HIP)
        if nose is None or (lh is None and rh is None):
            return False
        hip_y = float(np.mean([h[1] for h in [lh, rh] if h is not None]))
        margin = 0.02 * fh
        return float(nose[1]) > hip_y + margin

    def classify(self, kp: List, frame_h: int, pid: int) -> Tuple[str, float]:
        pkp = self.prev_kp.get(pid)
        prev_state = self.prev_state.get(pid, "STANDING")

        angle = self._angle(kp)
        hip_h = self._hip_h(kp, frame_h)
        vel = self._vel(kp, pkp, frame_h)
        moving = self._moving(kp, pkp)
        cog_c = self._cog(kp)
        cog_p = self.prev_cog.get(pid)
        cog_v = (
            float(np.linalg.norm(cog_c - cog_p))
            if cog_c is not None and cog_p is not None
            else 0.0
        )
        stable = self._cog_stable(cog_c, kp)

        if cog_c is not None:
            self.prev_cog[pid] = cog_c

        def _done(state: str) -> Tuple[str, float]:
            self.prev_kp[pid] = kp
            self.prev_state[pid] = state
            return state, _calibrated_heuristic_score(state)

        if self._inverted(kp, frame_h):
            if prev_state in ("STANDING", "WALKING", "UNSTABLE", "FALLING", "PRE_FALL"):
                self.deb_count[pid] = self.DEBOUNCE
                return _done("FALL")
            self.deb_count[pid] = 0
            return _done("LYING")

        if angle is None or hip_h is None:
            self.deb_count[pid] = 0
            return _done("UNKNOWN")

        horiz = angle > self.FALL_ANGLE
        low = hip_h < self.HIP_HEIGHT
        sudden = vel > self.VELOCITY
        cog_rap = cog_v > self.COG_VEL

        if horiz and low:
            fc = (sudden or cog_rap or not stable) and prev_state in (
                "STANDING",
                "WALKING",
                "UNSTABLE",
                "FALLING",
                "PRE_FALL",
            )
            if fc:
                cnt = self.deb_count.get(pid, 0) + 1
                self.deb_count[pid] = cnt
                return _done("FALL" if cnt >= self.DEBOUNCE else "FALLING")
            self.deb_count[pid] = 0
            return _done("LYING")

        if (cog_rap or sudden) and prev_state in ("STANDING", "WALKING", "UNSTABLE"):
            if hip_h > self.HIP_HEIGHT:
                self.deb_count[pid] = self.deb_count.get(pid, 0) + 1
                return _done("PRE_FALL")

        self.deb_count[pid] = 0
        if hip_h < 0.35:
            return _done("SITTING")
        if moving and hip_h > 0.40:
            return _done("UNSTABLE" if not stable else "WALKING")
        return _done("STANDING")


# ─────────────────────────────────────────────────────────────────────────────
# Child classification + geometry helpers
# ─────────────────────────────────────────────────────────────────────────────


def classify_person_type(
    kp: List,
    p_bbox: Optional[Tuple] = None,
    frame_h: Optional[int] = None,
    ratio_thr: float = 0.68,
    infant_thr: float = 0.85,
    small_frac: float = 0.35,
) -> Tuple[str, Optional[float]]:
    """ADULT / CHILD / UNKNOWN via leg-to-torso ratio (scale-invariant)."""
    ls = _gkp(kp, KP_L_SHOULDER)
    rs = _gkp(kp, KP_R_SHOULDER)
    lh = _gkp(kp, KP_L_HIP)
    rh = _gkp(kp, KP_R_HIP)
    la = _gkp(kp, KP_L_ANKLE)
    ra = _gkp(kp, KP_R_ANKLE)

    thr = ratio_thr
    if p_bbox is not None and frame_h is not None:
        # FIX 9: guard against zero-height bboxes setting thr=infant_thr
        # (happens when all keypoints land at the same y-coordinate).
        # Require bbox to have at least 1% of frame height before comparing.
        bbox_h_frac = (p_bbox[3] - p_bbox[1]) / frame_h
        if 0.01 < bbox_h_frac < small_frac:
            thr = infant_thr

    # Primary: leg / torso ratio
    if all(v is not None for v in [ls, rs, lh, rh, la, ra]):
        hip = (lh + rh) / 2
        sh = (ls + rs) / 2
        ank = (la + ra) / 2
        torso = float(np.linalg.norm(hip - sh))
        leg = float(np.linalg.norm(ank - hip))
        if torso > 5.0:
            return ("CHILD" if leg / torso < thr else "ADULT"), round(leg / torso, 3)

    # Fallback: shoulder-width / torso ratio
    if all(v is not None for v in [ls, rs, lh, rh]):
        sh = (ls + rs) / 2
        hip = (lh + rh) / 2
        sw = float(np.linalg.norm(ls - rs))
        torso = float(np.linalg.norm(hip - sh))
        if torso > 5.0:
            r = sw / torso
            return ("CHILD" if r > 0.90 else "ADULT"), round(r, 3)

    return "UNKNOWN", None


# def kp_to_bbox(kp_list: List, frame_h: int,
#                min_h: float = 0.10, max_ar: float = 3.0) -> Optional[Tuple]:
#     valid = [p for p in kp_list if p is not None]
#     if len(valid) < 3:
#         return None
#     xs = [p[0] for p in valid]; ys = [p[1] for p in valid]
#     b = (min(xs), min(ys), max(xs), max(ys))
#     bh = b[3]-b[1]; bw = b[2]-b[0]
#     if bh / frame_h < min_h or bw > bh * max_ar:
#         return None
#     return b


def kp_to_bbox(
    kp_list: List, frame_h: int, min_h: float = 0.05, max_ar: float = 5.0
) -> Optional[Tuple]:
    """
    Optimized for YOLO26: Filters out low-confidence jitter before
    calculating the bounding box.
    """
    # 1. Filter for points that exist AND meet our YOLO26 confidence gate
    # Assuming kp_list contains [x, y, conf] or you are checking against
    # a threshold before passing to this function.
    valid = [p for p in kp_list if p is not None]

    if len(valid) < 5:  # Increased to 5 for YOLO26 stability
        return None

    xs = [p[0] for p in valid]
    ys = [p[1] for p in valid]

    b = (min(xs), min(ys), max(xs), max(ys))
    bh = b[3] - b[1]
    bw = b[2] - b[0]

    # 2. Relaxed thresholds for "Lying Down" detection
    # bh/frame_h < 0.05 allows for people flat on the floor
    # max_ar = 5.0 allows for very wide horizontal boxes
    if bh / frame_h < min_h or bw > (bh * max_ar):
        return None

    return b


def bbox_centre(b: Tuple) -> Tuple[float, float]:
    return ((b[0] + b[2]) / 2, (b[1] + b[3]) / 2)


def proximity(pb: Tuple, hb: Tuple, shape: Tuple) -> float:
    diag = np.sqrt(shape[0] ** 2 + shape[1] ** 2)
    pc = bbox_centre(pb)
    hc = bbox_centre(hb)
    return np.sqrt((pc[0] - hc[0]) ** 2 + (pc[1] - hc[1]) ** 2) / diag


# ─────────────────────────────────────────────────────────────────────────────
# Main system
# ─────────────────────────────────────────────────────────────────────────────


class HomeSafetyInference:
    """
    Combined: TCN + heuristic + hazard + child safety.

    Hybrid blending (TCN_WEIGHT=0.60, HEURISTIC_WEIGHT=0.40):
      Standard blend:  P = TCN_WEIGHT*P_tcn + HEURISTIC_WEIGHT*P_heuristic
      Gating (FALL/FALLING only):
                       P = max(blend, h_score) so heuristic can raise score
                       when it is truly confident. PRE_FALL uses standard
                       blend only — it should not override TCN on its own.
      Inversion (5-frame confirmed): P = max(P_tcn, 0.98)

    TCN runs only every TCN_STRIDE=3 frames. Cached probability used between.
    Inactivity uses time.time() — correct at any frame rate, persists through
    post-fall LYING transitions.

    Live-camera callers must call reset_state() before processing a new stream.
    """

    def __init__(
        self,
        tcn_weights: str,
        norm_mean: str,
        norm_std: str,
        hazard_weights: str,
        yolo_weights: str,
        pose_size: str = "s",
        mode: str = "hybrid",
        fall_threshold: float = 0.65,
        inactivity_seconds: float = 3.0,
        inverted_frames_needed: int = 5,
        heuristic_fall_angle: float = 60.0,
        heuristic_hip_height: float = 0.50,
        heuristic_velocity: float = 0.04,
        heuristic_cog_vel: float = 30.0,
        heuristic_cog_stability: float = 50.0,
        heuristic_debounce: int = 3,
    ):
        # FIX 7: validate weights sum to 1.0 at construction time
        if abs(TCN_WEIGHT + HEURISTIC_WEIGHT - 1.0) > 1e-6:
            raise ValueError(
                f"TCN_WEIGHT ({TCN_WEIGHT}) + HEURISTIC_WEIGHT "
                f"({HEURISTIC_WEIGHT}) must equal 1.0"
            )

        self.mode = mode
        self.fall_threshold = fall_threshold
        self.inactivity_seconds = inactivity_seconds
        self.inverted_frames_needed = inverted_frames_needed
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

        logger.info(f"Device    : {self.device}")
        logger.info(f"Mode      : {mode}")
        if mode == "hybrid":
            logger.info(
                f"Weights   : TCN={TCN_WEIGHT:.0%}  Heuristic={HEURISTIC_WEIGHT:.0%}"
            )
        logger.info(f"Threshold : {fall_threshold}")
        logger.info(f"Inverted  : {inverted_frames_needed} consecutive frames")
        logger.info(f"TCN runs  : every {TCN_STRIDE} frames (cached between)")

        self.pose_model = YOLO(yolo_weights, task="pose")
        self.hazard_model = YOLO(hazard_weights, task="detect")

        if mode in ("tcn", "hybrid"):
            self.tcn = TCN(channels=128).to(self.device)
            self.tcn.load_state_dict(torch.load(tcn_weights, map_location=self.device))
            self.tcn.eval()
            self.norm_mean = np.load(norm_mean)
            self.norm_std = np.load(norm_std)

        self.heuristic = HeuristicClassifier(
            fall_angle=heuristic_fall_angle,
            hip_height=heuristic_hip_height,
            velocity=heuristic_velocity,
            cog_vel=heuristic_cog_vel,
            cog_stability=heuristic_cog_stability,
            debounce=heuristic_debounce,
        )

        # Initialise per-stream state so the object is usable before run()
        self._init_state_dicts()

        self.cached_hazards = []
        logger.info("HomeSafetyInference ready.\n")

    # ── State management ──────────────────────────────────────────────────────

    def _init_state_dicts(self) -> None:
        """Allocate (or reset) all per-person tracking dictionaries."""
        self.kp_buffers: Dict[int, deque] = {}
        self.person_status: Dict[int, Dict] = {}
        self.person_type_hist: Dict[int, List] = {}
        self.lost_patience: Dict[int, int] = {}
        self.fall_start_time: Dict[int, float] = {}
        self.alarm_fired: Dict[int, bool] = {}
        self.inverted_count: Dict[int, int] = {}
        self.cached_tcn: Dict[int, float] = {}
        self.heuristic.reset()

    def reset_state(self) -> None:
        """
        FIX 11: Public reset method for live-camera callers.

        Must be called before processing a new video stream or camera session.
        run() calls this automatically; process_frame() callers must call it
        manually when starting a new session, e.g.:

            system = HomeSafetyInference(...)
            system.reset_state()
            for frame in camera_loop():
                annotated, alerts = system.process_frame(frame, frame_idx)
        """
        self._init_state_dicts()

    # ── Per-person helpers ────────────────────────────────────────────────────

    def _smooth_type(self, tid: int, raw_type: str, n: int = 5) -> str:
        hist = self.person_type_hist.setdefault(tid, [])
        hist.append(raw_type)
        if len(hist) > n:
            hist.pop(0)
        known = [t for t in hist if t != "UNKNOWN"]
        return Counter(known).most_common(1)[0][0] if known else "UNKNOWN"

    def _get_tcn_prob(self, tid: int, frame_count: int) -> float:
        """
        Run TCN only every TCN_STRIDE frames; return cached value between runs.
        """
        if len(self.kp_buffers[tid]) < WINDOW:
            return 0.0
        if frame_count % TCN_STRIDE == 0 or tid not in self.cached_tcn:
            buf = self.kp_buffers[tid]
            clean = interpolate_and_smooth(list(buf))
            feat = extract_features(clean)
            feat = (feat - self.norm_mean) / self.norm_std
            t = torch.tensor(feat, dtype=torch.float32).unsqueeze(0).to(self.device)
            with torch.no_grad():
                prob = float(torch.softmax(self.tcn(t), dim=1)[0, 1].item())
            self.cached_tcn[tid] = prob
        return self.cached_tcn[tid]

    # def _detect_and_draw_hazards(self, frame: np.ndarray) -> List[Dict]:
    #     results = self.hazard_model(frame, iou=0.45, verbose=False, imgsz=480)
    #     hazards = []
    #     if results[0].boxes is not None:
    #         for box in results[0].boxes:
    #             conf   = float(box.conf[0])
    #             cls_id = int(box.cls[0])
    #             name   = HAZARD_NAMES.get(cls_id, str(cls_id))
    #             if conf < HAZARD_CONF.get(name, 0.30):
    #                 continue
    #             x1, y1, x2, y2 = map(int, box.xyxy[0])
    #             hazards.append({'name': name, 'bbox': (x1,y1,x2,y2), 'conf': conf})
    #             cv2.rectangle(frame, (x1,y1), (x2,y2), COLOR['HAZARD'], 2)
    #             cv2.putText(frame, f"{name} {conf:.2f}",
    #                         (x1, max(0,y1-8)),
    #                         cv2.FONT_HERSHEY_SIMPLEX, 0.5, COLOR['HAZARD'], 2)
    #     return hazards

    def _detect_and_draw_hazards(
        self, frame: np.ndarray, frame_count: int
    ) -> List[Dict]:
        # Only run the heavy YOLO model every 15 frames
        if frame_count % 15 == 0 or not getattr(self, "cached_hazards", None):
            results = self.hazard_model(frame, iou=0.45, verbose=False)
            hazards = []
            if results[0].boxes is not None:
                for box in results[0].boxes:
                    conf = float(box.conf[0])
                    cls_id = int(box.cls[0])
                    name = HAZARD_NAMES.get(cls_id, str(cls_id))

                    if conf < HAZARD_CONF.get(name, 0.30):
                        continue

                    x1, y1, x2, y2 = map(int, box.xyxy[0])

                    # FIXED: This must be indented inside the 'for' loop!
                    hazards.append(
                        {"name": name, "bbox": (x1, y1, x2, y2), "conf": conf}
                    )

            self.cached_hazards = hazards

        # Draw the cached boxes every frame so the video still looks smooth
        for hazard in self.cached_hazards:
            x1, y1, x2, y2 = hazard["bbox"]
            cv2.rectangle(frame, (x1, y1), (x2, y2), COLOR["HAZARD"], 2)
            cv2.putText(
                frame,
                f"{hazard['name']} {hazard['conf']:.2f}",
                (x1, max(0, y1 - 8)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                COLOR["HAZARD"],
                2,
            )

        return self.cached_hazards

    def _process_person(
        self,
        tid: int,
        raw_kp: np.ndarray,
        frame: np.ndarray,
        fh: int,
        fw: int,
        frame_count: int,
        hazards: List[Dict],
    ) -> Tuple[np.ndarray, List[Dict]]:

        alerts: List[Dict] = []

        if tid not in self.kp_buffers:
            self.kp_buffers[tid] = deque(maxlen=WINDOW)
            self.person_status[tid] = {"label": "Tracking..."}

        # kp_pixel: pixel coords, conf-filtered (used by heuristic + child)
        # kp_norm:  [0,1] normalised coords (stored in TCN buffer)
        # Both match their training-time counterparts exactly.
        kp_pixel: List[Optional[np.ndarray]] = []
        kp_norm = np.zeros((N_KP, 2), dtype=np.float32)
        valid = 0
        for i, pt in enumerate(raw_kp):
            px, py, conf = float(pt[0]), float(pt[1]), float(pt[2])
            # DEBUG: See if scores are dropping
            if frame_count % 100 == 0:
                print(f"Keypoint {i} Conf: {conf}")
            if conf >= KP_CONF and not (px == 0 and py == 0):
                kp_pixel.append(np.array([px, py]))
                kp_norm[i] = [px / fw, py / fh]
                valid += 1
            else:
                kp_pixel.append(None)

        self.kp_buffers[tid].append(kp_norm if valid >= 3 else None)

        p_bbox = kp_to_bbox(kp_pixel, fh)
        raw_type, ratio = classify_person_type(kp_pixel, p_bbox, fh)
        person_type = self._smooth_type(tid, raw_type)
        h_state, h_score = self.heuristic.classify(kp_pixel, fh, tid)

        # Initialize t_prob here so it is available for all modes
        t_prob = 0.0

        # ── Fall probability ──────────────────────────────────────────────
        if self.mode == "heuristic":
            fall_prob = h_score
            fall_state = h_state

        elif self.mode == "tcn":
            t_prob = self._get_tcn_prob(tid, frame_count)
            fall_prob = t_prob
            fall_state = "FALL" if fall_prob > self.fall_threshold else "STANDING"

        else:  # hybrid
            t_prob = self._get_tcn_prob(tid, frame_count)

            # Inversion confirmation: FIX 8 — 5 frames (was 2) to reduce false
            # positives from forward bends, kicks, and infant detections.
            if self.heuristic._inverted(kp_pixel, fh):
                self.inverted_count[tid] = self.inverted_count.get(tid, 0) + 1
            else:
                self.inverted_count[tid] = 0

            if self.inverted_count.get(tid, 0) >= self.inverted_frames_needed:
                # Confirmed inversion: TCN can only raise, not lower the score
                fall_prob = max(t_prob, 0.98)

            elif h_state in ("FALL", "FALLING"):
                # FIX 4: gating applies only to FALL/FALLING, not PRE_FALL.
                # PRE_FALL score (0.60) is now below the default threshold
                # (0.65), so it requires corroboration from the TCN rather than
                # being able to fire an alert on its own via the max-gate.
                blended = TCN_WEIGHT * t_prob + HEURISTIC_WEIGHT * h_score
                fall_prob = max(blended, h_score)

            else:
                # Standard weighted blend for all other states, including PRE_FALL
                fall_prob = TCN_WEIGHT * t_prob + HEURISTIC_WEIGHT * h_score

            fall_state = "FALL" if fall_prob > self.fall_threshold else h_state

        # ── Fall alert ────────────────────────────────────────────────────
        if fall_state == "FALL" and person_type != "CHILD":
            alerts.append(
                {
                    "type": "FALL",
                    "pid": tid,
                    "prob": round(fall_prob, 3),
                    "t_prob": round(t_prob, 3),
                    "h_score": round(h_score, 3),
                    "frame": frame_count,
                }
            )

        # ── Inactivity alarm (time-based) ─────────────────────────────────
        # FIX 3: Timer starts on the first FALL detection and persists through
        # LYING (post-fall immobility). It resets only when the person
        # transitions back to non-floor states (STANDING, WALKING, etc.).
        #
        # Previous code cleared the timer the moment fall_state became LYING,
        # meaning a person who fell and lay still would never trigger INACTIVITY.
        inactivity = False

        if fall_state == "FALL":
            # Confirmed fall — start timer if not already running
            if tid not in self.fall_start_time:
                self.fall_start_time[tid] = time.time()
        elif h_state == "LYING" and tid in self.fall_start_time:
            # Person transitioned FALL → LYING — keep the timer ticking.
            # Do not reset fall_start_time or alarm_fired here.
            pass
        else:
            # Person is upright or state is ambiguous — clear timer and reset
            self.fall_start_time.pop(tid, None)
            self.alarm_fired.pop(tid, None)

        if (
            tid in self.fall_start_time
            and not self.alarm_fired.get(tid, False)
            and time.time() - self.fall_start_time[tid] > self.inactivity_seconds
        ):
            alerts.append({"type": "INACTIVITY", "pid": tid, "frame": frame_count})
            self.alarm_fired[tid] = True
            inactivity = True

        # ── Child + hazard proximity ──────────────────────────────────────
        if person_type == "CHILD" and p_bbox is not None:
            for hazard in hazards:
                thr = HAZARD_PROXIMITY.get(hazard["name"], 0.20)
                dist = proximity(p_bbox, hazard["bbox"], frame.shape)
                if dist < thr:
                    alerts.append(
                        {
                            "type": "CHILD_HAZARD",
                            "pid": tid,
                            "hazard": hazard["name"],
                            "dist": round(dist, 3),
                            "frame": frame_count,
                        }
                    )
                    pc = tuple(map(int, bbox_centre(p_bbox)))
                    hc = tuple(map(int, bbox_centre(hazard["bbox"])))
                    cv2.line(frame, pc, hc, COLOR["ALERT"], 2)
                    hx1, hy1 = hazard["bbox"][0], hazard["bbox"][1]
                    cv2.putText(
                        frame,
                        f"CHILD NEAR {hazard['name'].upper()}",
                        (hx1, max(0, hy1 - 24)),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.55,
                        COLOR["ALERT"],
                        2,
                    )

        # ── Annotation ────────────────────────────────────────────────────
        if inactivity or fall_state == "FALL":
            color = COLOR["FALL"]
        elif fall_state in ("FALLING", "PRE_FALL"):
            color = COLOR.get(fall_state, (0, 60, 255))
        elif person_type == "CHILD":
            color = COLOR["CHILD"]
        else:
            color = COLOR["STANDING"]

        parts = [f"ID:{tid} [{person_type}] {fall_state}"]
        if self.mode == "hybrid" and len(self.kp_buffers[tid]) == WINDOW:
            parts.append(f"p={fall_prob:.2f}(T:{t_prob:.2f},H:{h_score:.2f})")
        elif self.mode == "tcn" and len(self.kp_buffers[tid]) == WINDOW:
            parts.append(f"p={fall_prob:.2f}(T:{t_prob:.2f})")
        elif self.mode == "heuristic":
            parts.append(f"p={fall_prob:.2f}(H:{h_score:.2f})")

        if ratio is not None:
            parts.append(f"r={ratio:.2f}")
        if inactivity:
            parts.append("!INACTIVE")

        if p_bbox is not None:
            x1, y1, x2, y2 = map(int, p_bbox)
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
            cv2.putText(
                frame,
                " ".join(parts),
                (x1, max(0, y1 - 10)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                color,
                2,
            )

        self.person_status[tid] = {"label": fall_state}
        return frame, alerts

    def process_frame(
        self, frame: np.ndarray, frame_count: int
    ) -> Tuple[np.ndarray, List[Dict]]:
        fh, fw = frame.shape[:2]
        alerts: List[Dict] = []

        hazards = self._detect_and_draw_hazards(frame, frame_count)
        results = self.pose_model.track(
            frame,
            persist=True,
            verbose=False,
            conf=0.25,
            tracker="/content/sticky_tracker.yaml",
        )
        active_ids: List[int] = []

        if (
            len(results) > 0
            and results[0].keypoints is not None
            and results[0].boxes is not None
            and results[0].boxes.id is not None
        ):
            kp_data = results[0].keypoints.data.cpu().numpy()
            track_ids = results[0].boxes.id.int().cpu().tolist()

            for idx, tid in enumerate(track_ids):
                # FIX 6: guard against Ultralytics edge case where track_ids
                # and kp_data have different lengths (detection dropped mid-batch)
                if idx >= len(kp_data):
                    logger.warning(
                        f"kp_data shorter than track_ids at frame "
                        f"{frame_count} (idx={idx}, "
                        f"len(kp_data)={len(kp_data)})"
                    )
                    continue
                active_ids.append(tid)
                frame, new_alerts = self._process_person(
                    tid, kp_data[idx], frame, fh, fw, frame_count, hazards
                )
                alerts.extend(new_alerts)

        self._gc(active_ids)
        return frame, alerts

    def _gc(self, active_ids: List[int]) -> None:
        lost_ids = [tid for tid in self.kp_buffers if tid not in active_ids]
        for tid in lost_ids:
            self.lost_patience[tid] = self.lost_patience.get(tid, 0) + 1
            if self.lost_patience[tid] > WINDOW:
                for d in [
                    self.kp_buffers,
                    self.person_status,
                    self.person_type_hist,
                    self.fall_start_time,
                    self.alarm_fired,
                    self.inverted_count,
                    self.cached_tcn,
                    self.heuristic.prev_kp,
                    self.heuristic.prev_cog,
                    self.heuristic.deb_count,
                    self.heuristic.prev_state,
                ]:
                    d.pop(tid, None)
                self.lost_patience.pop(tid, None)
        for tid in active_ids:
            self.lost_patience.pop(tid, None)

    def run(
        self,
        video_path: str,
        output_path: str,
        max_frames: int = 0,
        show_every: int = 60,
    ) -> List[Dict]:
        tmp_converted = None
        read_path = video_path
        if Path(video_path).suffix.lower() in (".webm", ".avi"):
            logger.info(f"Converting {Path(video_path).suffix} to mp4 ...")
            tmp_fd, tmp_converted = tempfile.mkstemp(suffix=".mp4")
            os.close(tmp_fd)
            r = subprocess.run(
                [
                    "ffmpeg",
                    "-y",
                    "-i",
                    video_path,
                    "-map",
                    "0:v:0",
                    "-an",
                    "-vcodec",
                    "libx264",
                    "-crf",
                    "23",
                    "-preset",
                    "ultrafast",
                    "-loglevel",
                    "error",
                    tmp_converted,
                ],
                capture_output=True,
                timeout=300,
            )
            if r.returncode != 0:
                os.unlink(tmp_converted)
                raise RuntimeError(f"ffmpeg: {r.stderr.decode()[:300]}")
            read_path = tmp_converted

        cap = cv2.VideoCapture(read_path)
        if not cap.isOpened():
            raise FileNotFoundError(f"Cannot open: {video_path}")

        fps = int(cap.get(cv2.CAP_PROP_FPS)) or 25
        w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        limit = max_frames if max_frames > 0 else total
        logger.info(f"Input  : {video_path}  [{w}x{h} @ {fps}fps  {total} frames]")
        logger.info(f"Output : {output_path}\n")

        # Set up FFmpeg streaming subprocess instead of cv2.VideoWriter
        ffmpeg_cmd = [
            "ffmpeg",
            "-y",
            "-f",
            "rawvideo",
            "-vcodec",
            "rawvideo",
            "-s",
            f"{w}x{h}",
            "-pix_fmt",
            "bgr24",
            "-r",
            str(fps),
            "-i",
            "-",
            "-vcodec",
            "libx264",
            "-crf",
            "28",
            "-preset",
            "ultrafast",  # Highly recommended for simultaneous CPU inference
            "-pix_fmt",
            "yuv420p",
            "-loglevel",
            "error",  # Suppress FFmpeg terminal spam
            output_path,
        ]

        logger.info("Initializing FFmpeg compression pipeline...")
        ffmpeg_process = subprocess.Popen(ffmpeg_cmd, stdin=subprocess.PIPE)

        self.reset_state()
        all_alerts: List[Dict] = []
        frame_count = 0

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret or frame_count >= limit:
                break

            annotated, alerts = self.process_frame(frame, frame_count)
            all_alerts.extend(alerts)

            for a in alerts:
                if a["type"] == "FALL":
                    logger.info(
                        f"FALL       — ID:{a['pid']}  "
                        f"p={a.get('prob', '?')} (TCN:{a.get('t_prob', '?')} Heur:{a.get('h_score', '?')})  (frame {a['frame']})"
                    )
                elif a["type"] == "INACTIVITY":
                    logger.info(f"INACTIVITY — ID:{a['pid']} (frame {a['frame']})")
                elif a["type"] == "CHILD_HAZARD":
                    logger.info(
                        f"CHILD NEAR {a['hazard'].upper()}  "
                        f"dist={a['dist']:.2f} (frame {a['frame']})"
                    )

            if frame_count % show_every == 0:
                logger.info(f"Frame {frame_count}/{limit} | alerts: {len(all_alerts)}")

            # Pipe the raw bytes directly to FFmpeg
            if ffmpeg_process.stdin:
                ffmpeg_process.stdin.write(annotated.tobytes())

            del frame, annotated
            frame_count += 1

        gc.collect()

        cap.release()

        # Close the stdin pipe and wait for FFmpeg to finish writing the file
        if ffmpeg_process.stdin:
            ffmpeg_process.stdin.close()
        logger.info("Waiting for FFmpeg to finalize compression...")
        ffmpeg_process.wait()

        if tmp_converted and os.path.exists(tmp_converted):
            os.unlink(tmp_converted)

        logger.info(
            f"\nDone — {frame_count} frames safely compressed to {output_path}."
        )

        counts = Counter(a["type"] for a in all_alerts)
        if counts:
            logger.info("\n── Alert summary ───────────────────────────")
            for t, n in counts.most_common():
                logger.info(f"   {t:<16} : {n}")
            logger.info("────────────────────────────────────────────")

        return all_alerts
