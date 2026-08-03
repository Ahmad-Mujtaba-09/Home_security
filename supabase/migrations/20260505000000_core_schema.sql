-- ============================================================================
-- Migration 20260505000000 — Core schema
-- Tables: profiles, history, fcm_tokens
--
-- Run this FIRST, then 20260505000001_add_devices_notifications_summaries_chat.
-- Run in the Supabase SQL editor, or via `supabase db push`.
-- ============================================================================


-- ─── Shared trigger function ────────────────────────────────────────────────
-- Used by profiles, fcm_tokens and (in migration 001) devices.
create or replace function public.handle_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;


-- ─── 1. profiles ────────────────────────────────────────────────────────────
-- User preferences. 1:1 with auth.users. Read by the Engine
-- (`_get_user_profile`) to decide which detection modules to run, and by both
-- Flutter clients for the theme + module toggles.
create table if not exists public.profiles (
  id                     uuid primary key references auth.users(id) on delete cascade,
  light_mode             boolean     not null default false,
  child_module_enabled   boolean     not null default true,
  elderly_module_enabled boolean     not null default true,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.handle_updated_at();

-- Auto-create a profile row on signup so the clients never race an empty read.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ─── 2. history ─────────────────────────────────────────────────────────────
-- Detection events written by the Engine (`_log_event`) and read by
-- GET /api/history, the AI summary generator, and both Flutter clients.
-- event_type values in use: FALL, INACTIVITY, CHILD_HAZARD.
create table if not exists public.history (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  event_type  text not null,
  confidence  double precision,          -- 0.0–1.0
  frame_count integer,                   -- frame index of the triggering window
  "timestamp" timestamptz not null default now()
);

-- The main client query: user-scoped, newest first.
create index if not exists idx_history_user_timestamp
  on public.history (user_id, "timestamp" desc);


-- ─── 3. fcm_tokens ──────────────────────────────────────────────────────────
-- Firebase device tokens. Upserted by the mobile app
-- (`PushNotificationService._saveToken`, on_conflict = user_id) and read by
-- the Engine (`_send_fcm_push`). One token per user — the unique constraint on
-- user_id is what makes that upsert work.
create table if not exists public.fcm_tokens (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null unique references auth.users(id) on delete cascade,
  token      text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_fcm_tokens_user on public.fcm_tokens (user_id);

drop trigger if exists fcm_tokens_updated_at on public.fcm_tokens;
create trigger fcm_tokens_updated_at
  before update on public.fcm_tokens
  for each row execute function public.handle_updated_at();


-- ============================================================================
-- Row Level Security
--
-- The Engine talks to Supabase with the service_role key, which bypasses RLS
-- entirely. These policies exist for the Flutter clients using the anon key.
-- ============================================================================

alter table public.profiles    enable row level security;
alter table public.history     enable row level security;
alter table public.fcm_tokens  enable row level security;

-- profiles: owner-scoped select/insert/update
drop policy if exists "profiles_owner_select" on public.profiles;
drop policy if exists "profiles_owner_insert" on public.profiles;
drop policy if exists "profiles_owner_update" on public.profiles;
create policy "profiles_owner_select"
  on public.profiles for select
  using (auth.uid() = id);
create policy "profiles_owner_insert"
  on public.profiles for insert
  with check (auth.uid() = id);
create policy "profiles_owner_update"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- history: owner-scoped read + insert
drop policy if exists "history_owner_select" on public.history;
drop policy if exists "history_owner_insert" on public.history;
create policy "history_owner_select"
  on public.history for select
  using (auth.uid() = user_id);
create policy "history_owner_insert"
  on public.history for insert
  with check (auth.uid() = user_id);

-- fcm_tokens: owner-scoped CRUD (the mobile app upserts its own token)
drop policy if exists "fcm_tokens_owner_all" on public.fcm_tokens;
create policy "fcm_tokens_owner_all"
  on public.fcm_tokens for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
