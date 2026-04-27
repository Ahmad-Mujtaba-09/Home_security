-- ============================================================================
-- Migration 002: Seed dummy data for user 814b37a6-fa07-4df4-bc32-079872871b44
-- Email: rafayjalal50@gmail.com
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1. PROFILE — default settings for this user
-- ────────────────────────────────────────────────────────────────────────────
INSERT INTO public.profiles (id, light_mode, child_module_enabled, elderly_module_enabled)
VALUES (
    '814b37a6-fa07-4df4-bc32-079872871b44',
    false,   -- dark mode by default
    true,    -- child module on
    true     -- elderly module on
)
ON CONFLICT (id) DO NOTHING;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. HISTORY — realistic detection events over the past 7 days
-- ────────────────────────────────────────────────────────────────────────────
INSERT INTO public.history (user_id, event_type, confidence, frame_count, timestamp)
VALUES
    -- ── Day 1 (7 days ago) ──────────────────────────────────────────────────
    (
        '814b37a6-fa07-4df4-bc32-079872871b44',
        'FALL',
        0.92,
        48,
        now() - INTERVAL '7 days' + INTERVAL '9 hours 15 minutes'
    ),
    (
        '814b37a6-fa07-4df4-bc32-079872871b44',
        'INACTIVITY',
        0.78,
        120,
        now() - INTERVAL '7 days' + INTERVAL '14 hours 30 minutes'
    ),

    -- ── Day 2 (6 days ago) ──────────────────────────────────────────────────
    (
        '814b37a6-fa07-4df4-bc32-079872871b44',
        'CHILD_HAZARD',
        0.85,
        36,
        now() - INTERVAL '6 days' + INTERVAL '10 hours 45 minutes'
    ),

    -- ── Day 3 (5 days ago) ──────────────────────────────────────────────────
    (
        '814b37a6-fa07-4df4-bc32-079872871b44',
        'FALL',
        0.97,
        52,
        now() - INTERVAL '5 days' + INTERVAL '8 hours 20 minutes'
    ),
    (
        '814b37a6-fa07-4df4-bc32-079872871b44',
        'CHILD_HAZARD',
        0.73,
        28,
        now() - INTERVAL '5 days' + INTERVAL '16 hours 10 minutes'
    ),

    -- ── Day 4 (4 days ago) ──────────────────────────────────────────────────
    (
        '814b37a6-fa07-4df4-bc32-079872871b44',
        'INACTIVITY',
        0.88,
        150,
        now() - INTERVAL '4 days' + INTERVAL '11 hours 5 minutes'
    ),

    -- ── Day 5 (3 days ago) ──────────────────────────────────────────────────
    (
        '814b37a6-fa07-4df4-bc32-079872871b44',
        'FALL',
        0.81,
        44,
        now() - INTERVAL '3 days' + INTERVAL '7 hours 50 minutes'
    ),
    (
        '814b37a6-fa07-4df4-bc32-079872871b44',
        'CHILD_HAZARD',
        0.91,
        40,
        now() - INTERVAL '3 days' + INTERVAL '13 hours 25 minutes'
    ),
    (
        '814b37a6-fa07-4df4-bc32-079872871b44',
        'INACTIVITY',
        0.65,
        90,
        now() - INTERVAL '3 days' + INTERVAL '20 hours 0 minutes'
    ),

    -- ── Day 6 (2 days ago) ──────────────────────────────────────────────────
    (
        '814b37a6-fa07-4df4-bc32-079872871b44',
        'FALL',
        0.94,
        56,
        now() - INTERVAL '2 days' + INTERVAL '6 hours 40 minutes'
    ),

    -- ── Day 7 (yesterday) ───────────────────────────────────────────────────
    (
        '814b37a6-fa07-4df4-bc32-079872871b44',
        'CHILD_HAZARD',
        0.87,
        32,
        now() - INTERVAL '1 day' + INTERVAL '9 hours 55 minutes'
    ),
    (
        '814b37a6-fa07-4df4-bc32-079872871b44',
        'INACTIVITY',
        0.72,
        110,
        now() - INTERVAL '1 day' + INTERVAL '17 hours 30 minutes'
    );
