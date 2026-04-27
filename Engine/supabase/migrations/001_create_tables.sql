-- ============================================================================
-- Migration 001: Create tables required by the Flutter frontend
-- Tables: profiles, history
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1. PROFILES TABLE
--    Stores user preferences (theme, module toggles).
--    Maps 1:1 to auth.users via id (UUID FK).
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
    id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    light_mode      BOOLEAN NOT NULL DEFAULT false,
    child_module_enabled   BOOLEAN NOT NULL DEFAULT true,
    elderly_module_enabled BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Auto-update the updated_at column on every UPDATE
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

-- Auto-create a profile row when a new user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id)
    VALUES (NEW.id)
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- ────────────────────────────────────────────────────────────────────────────
-- 2. HISTORY TABLE
--    Stores detection events (falls, inactivity, child hazard alerts).
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.history (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    event_type      TEXT NOT NULL,          -- 'FALL', 'INACTIVITY', 'CHILD_HAZARD'
    confidence      DOUBLE PRECISION,       -- detection confidence 0.0–1.0
    frame_count     INTEGER,                -- number of frames in the detection window
    timestamp       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for fast user-scoped queries ordered by time (the main frontend query)
CREATE INDEX IF NOT EXISTS idx_history_user_timestamp
    ON public.history (user_id, timestamp DESC);

-- ────────────────────────────────────────────────────────────────────────────
-- 3. ROW-LEVEL SECURITY (RLS)
--    Each user can only read/write their own rows.
-- ────────────────────────────────────────────────────────────────────────────

-- Profiles RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

CREATE POLICY "Users can insert their own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

-- History RLS
ALTER TABLE public.history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own history"
    ON public.history FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own history"
    ON public.history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Allow the backend (service_role) to insert history on behalf of users.
-- The service_role key bypasses RLS by default, so no extra policy needed.
