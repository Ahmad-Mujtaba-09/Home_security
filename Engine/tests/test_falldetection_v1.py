"""
Unit tests for falldetection_v1 pure functions.

Focuses on logic that does not require model weights:
  - Calibrated heuristic score table
  - Geometry helpers (proximity, bbox_centre, kp_to_bbox)
  - Feature engineering (interpolate_and_smooth, extract_features, _jangle)
  - HeuristicClassifier reset/state
  - Person classification (classify_person_type)

Model-loading paths (TCN forward, YOLO inference) are out of scope here —
they belong to a slow integration suite gated on the actual weights.
"""
import numpy as np
import pytest

import falldetection_v1 as fd


# ─── _calibrated_heuristic_score ────────────────────────────────────────────

class TestCalibratedHeuristicScore:
    def test_known_states_in_unit_interval(self):
        for state in ["FALL", "FALLING", "PRE_FALL", "LYING",
                      "SITTING", "UNSTABLE", "WALKING", "STANDING", "UNKNOWN"]:
            v = fd._calibrated_heuristic_score(state)
            assert 0.0 <= v <= 1.0

    def test_fall_above_pre_fall_above_walking(self):
        assert (fd._calibrated_heuristic_score("FALL")
                > fd._calibrated_heuristic_score("PRE_FALL")
                > fd._calibrated_heuristic_score("WALKING"))

    def test_unknown_state_returns_zero(self):
        assert fd._calibrated_heuristic_score("NOPE") == 0.0

    def test_pre_fall_below_default_threshold(self):
        # Documented invariant: PRE_FALL alone must not cross 0.65.
        assert fd._calibrated_heuristic_score("PRE_FALL") < 0.65


# ─── Geometry helpers ──────────────────────────────────────────────────────

class TestBBoxHelpers:
    def test_bbox_centre(self):
        assert fd.bbox_centre((0, 0, 10, 20)) == (5, 10)

    def test_proximity_zero_when_centres_match(self):
        b = (0, 0, 10, 10)
        assert fd.proximity(b, b, (100, 100)) == 0.0

    def test_proximity_normalised_by_diagonal(self):
        # Centres at (5,5) and (15,15) → distance 14.14 in 100x100 frame.
        d = fd.proximity((0, 0, 10, 10), (10, 10, 20, 20), (100, 100))
        assert 0.0 < d < 1.0

    def test_kp_to_bbox_returns_none_for_too_few_points(self):
        kps = [None, None, np.array([10.0, 10.0])]
        assert fd.kp_to_bbox(kps, frame_h=100) is None

    def test_kp_to_bbox_returns_none_for_too_short(self):
        # All very tight, height < 15% of frame.
        kps = [np.array([10.0, 10.0]), np.array([12.0, 12.0]), np.array([14.0, 11.0])]
        assert fd.kp_to_bbox(kps, frame_h=1000) is None

    def test_kp_to_bbox_valid(self):
        kps = [np.array([10.0, 10.0]),
               np.array([20.0, 60.0]),
               np.array([15.0, 30.0])]
        b = fd.kp_to_bbox(kps, frame_h=100)
        assert b == (10.0, 10.0, 20.0, 60.0)


# ─── Feature engineering ───────────────────────────────────────────────────

class TestFeatureEngineering:
    def test_jangle_handles_zero_vectors(self):
        z = np.zeros(2)
        v = np.zeros(2)
        assert fd._jangle(z, v, z) == 0.0

    def test_jangle_right_angle(self):
        a = np.array([1.0, 0.0])
        v = np.array([0.0, 0.0])
        b = np.array([0.0, 1.0])
        ang = fd._jangle(a, v, b)
        assert abs(ang - np.pi / 2) < 1e-5

    def test_interpolate_and_smooth_shape(self):
        kp_seq = [np.random.rand(fd.N_KP, 2).astype(np.float32) for _ in range(fd.WINDOW)]
        out = fd.interpolate_and_smooth(kp_seq)
        assert out.shape == (fd.WINDOW, fd.N_KP, 2)
        assert out.dtype == np.float32

    def test_interpolate_fills_missing_frames(self):
        # First and last present, middle missing — linear interp must fill.
        n = 10
        seq = [None] * n
        seq[0] = np.zeros((fd.N_KP, 2), dtype=np.float32)
        seq[-1] = np.ones((fd.N_KP, 2), dtype=np.float32) * 10
        out = fd.interpolate_and_smooth(seq, window_length=3, polyorder=1)
        assert np.all(np.isfinite(out))

    def test_interpolate_all_missing_zeros(self):
        seq = [None] * fd.WINDOW
        out = fd.interpolate_and_smooth(seq)
        assert out.shape == (fd.WINDOW, fd.N_KP, 2)
        assert np.allclose(out, 0)

    def test_extract_features_shape(self):
        xy = np.random.rand(fd.WINDOW, fd.N_KP, 2).astype(np.float32) * 100
        feats = fd.extract_features(xy)
        assert feats.shape == (fd.WINDOW, fd.FEATURE_DIM)
        assert feats.dtype == np.float32
        assert np.all(np.isfinite(feats))


# ─── HeuristicClassifier ───────────────────────────────────────────────────

class TestHeuristicClassifier:
    def test_reset_clears_state(self):
        clf = fd.HeuristicClassifier()
        clf.prev_kp[1] = "x"
        clf.prev_cog[1] = "y"
        clf.deb_count[1] = 3
        clf.prev_state[1] = "FALL"
        clf.reset()
        assert clf.prev_kp == {}
        assert clf.prev_cog == {}
        assert clf.deb_count == {}
        assert clf.prev_state == {}

    def test_classify_returns_unknown_on_missing_keypoints(self):
        clf = fd.HeuristicClassifier()
        # Only nose available, no shoulders/hips → upstream returns UNKNOWN.
        kp = [None] * fd.N_KP
        state, score = clf.classify(kp, frame_h=480, pid=1)
        assert isinstance(state, str)
        assert isinstance(score, float)
        assert 0.0 <= score <= 1.0


# ─── classify_person_type ──────────────────────────────────────────────────

class TestClassifyPersonType:
    def _make_kp(self):
        kp = [None] * fd.N_KP
        kp[fd.KP_NOSE] = np.array([100.0, 50.0])
        kp[fd.KP_L_SHOULDER] = np.array([90.0, 100.0])
        kp[fd.KP_R_SHOULDER] = np.array([110.0, 100.0])
        kp[fd.KP_L_HIP] = np.array([90.0, 200.0])
        kp[fd.KP_R_HIP] = np.array([110.0, 200.0])
        kp[fd.KP_L_ANKLE] = np.array([90.0, 350.0])
        kp[fd.KP_R_ANKLE] = np.array([110.0, 350.0])
        return kp

    def test_returns_label_and_score(self):
        label, score = fd.classify_person_type(
            self._make_kp(), frame_h=480, camera_mode="mobile", tid=1
        )
        assert label in {"ADULT", "CHILD", "UNKNOWN"}
        if score is not None:
            assert 0.0 <= score <= 1.0

    def test_missing_required_keypoints_returns_unknown(self):
        kp = [None] * fd.N_KP
        label, score = fd.classify_person_type(kp, frame_h=480)
        assert label == "UNKNOWN"
        assert score is None

    def test_short_torso_returns_unknown(self):
        kp = self._make_kp()
        # Collapse shoulder onto hip → torso < min_torso.
        kp[fd.KP_L_SHOULDER] = np.array([90.0, 199.0])
        kp[fd.KP_R_SHOULDER] = np.array([110.0, 199.0])
        label, _ = fd.classify_person_type(kp, frame_h=480, camera_mode="mobile")
        assert label == "UNKNOWN"


# ─── save_state / load_state ──────────────────────────────────────────────

class TestSaveLoadState:
    """Verify the state swap mechanism used by DeviceMonitorManager."""

    @pytest.fixture
    def system(self, tmp_path):
        """Create a minimal HomeSafetyInference without real weights."""
        # We need to mock model loading since we don't have weight files.
        from unittest.mock import patch, MagicMock
        import torch

        fake_yolo = MagicMock()
        fake_tcn_weights = tmp_path / "tcn.pt"
        fake_mean = tmp_path / "mean.npy"
        fake_std = tmp_path / "std.npy"

        # Create dummy weight files
        torch.save(fd.TCN().state_dict(), str(fake_tcn_weights))
        np.save(str(fake_mean), np.zeros(fd.FEATURE_DIM))
        np.save(str(fake_std), np.ones(fd.FEATURE_DIM))

        with patch.object(fd, "YOLO", return_value=fake_yolo):
            sys = fd.HomeSafetyInference(
                tcn_weights=str(fake_tcn_weights),
                norm_mean=str(fake_mean),
                norm_std=str(fake_std),
                hazard_weights="dummy.pt",
                mode="hybrid",
            )
        return sys

    def test_save_returns_dict_with_expected_keys(self, system):
        state = system.save_state()
        expected_keys = {
            "kp_buffers", "person_status", "person_type_hist",
            "lost_patience", "fall_start_time", "alarm_fired",
            "inverted_count", "cached_tcn", "fps",
            "_hazard_history", "_hazard_miss_count", "child_score_hist",
            "heuristic_prev_kp", "heuristic_prev_cog",
            "heuristic_deb_count", "heuristic_prev_state",
        }
        assert set(state.keys()) == expected_keys

    def test_save_load_roundtrip_preserves_state(self, system):
        # Mutate some tracking state.
        system.kp_buffers[42] = "test_buffer"
        system.cached_tcn[42] = 0.75
        system.heuristic.prev_state[42] = "FALL"
        system.fps = 15

        snapshot = system.save_state()

        # Reset to clean state.
        system.reset_state()
        assert system.kp_buffers == {}
        assert system.cached_tcn == {}

        # Restore from snapshot.
        system.load_state(snapshot)
        assert system.kp_buffers[42] == "test_buffer"
        assert system.cached_tcn[42] == 0.75
        assert system.heuristic.prev_state[42] == "FALL"
        assert system.fps == 15

    def test_multiple_device_states_independent(self, system):
        """Simulate two devices swapping state through the same system."""
        # Device A state
        system.reset_state()
        system.cached_tcn[1] = 0.9
        system.heuristic.prev_state[1] = "FALL"
        state_a = system.save_state()

        # Device B state
        system.reset_state()
        system.cached_tcn[2] = 0.1
        system.heuristic.prev_state[2] = "STANDING"
        state_b = system.save_state()

        # Restore A — should not contain B's data.
        system.load_state(state_a)
        assert 1 in system.cached_tcn
        assert 2 not in system.cached_tcn
        assert system.heuristic.prev_state[1] == "FALL"

        # Restore B — should not contain A's data.
        system.load_state(state_b)
        assert 2 in system.cached_tcn
        assert 1 not in system.cached_tcn
        assert system.heuristic.prev_state[2] == "STANDING"

