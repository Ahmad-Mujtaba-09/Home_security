-- ============================================================================
-- Migration 20260505000001 — devices, notifications, incident_summaries,
--                            chat_sessions, chat_messages
--
-- Requires 20260505000000_core_schema.sql (profiles, history, fcm_tokens and
-- the handle_updated_at function). Core tables are NOT modified here.
-- Run in the Supabase SQL editor, or via `supabase db push`.
-- ============================================================================


-- ─── 1. devices ─────────────────────────────────────────────────────────────
create table if not exists public.devices (
  device_id    uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  device_name  text not null,
  device_type  text not null default 'camera'
                check (device_type in ('camera', 'mobile', 'rtsp', 'other')),
  stream_url   text,
  location     text,
  status       text not null default 'inactive'
                check (status in ('active', 'inactive', 'offline')),
  last_seen    timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists idx_devices_user        on public.devices (user_id);
create index if not exists idx_devices_user_status on public.devices (user_id, status);

drop trigger if exists devices_updated_at on public.devices;
create trigger devices_updated_at
  before update on public.devices
  for each row execute function public.handle_updated_at();


-- ─── 2. notifications ───────────────────────────────────────────────────────
create table if not exists public.notifications (
  notification_id   uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  event_id          uuid references public.history(id) on delete set null,
  title             text not null,
  message           text not null,
  notification_type text not null default 'alert',
  sent_at           timestamptz not null default now(),
  read_status       boolean not null default false
);

create index if not exists idx_notifications_user_sent
  on public.notifications (user_id, sent_at desc);
create index if not exists idx_notifications_unread
  on public.notifications (user_id) where read_status = false;


-- ─── 3. incident_summaries ──────────────────────────────────────────────────
create table if not exists public.incident_summaries (
  summary_id      uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  start_time      timestamptz not null,
  end_time        timestamptz not null,
  summary_text    text not null,
  incident_count  integer not null default 0,
  generated_at    timestamptz not null default now()
);

create index if not exists idx_summaries_user_generated
  on public.incident_summaries (user_id, generated_at desc);


-- ─── 4. chat_sessions ───────────────────────────────────────────────────────
create table if not exists public.chat_sessions (
  session_id  uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  title       text,
  started_at  timestamptz not null default now(),
  ended_at    timestamptz
);

create index if not exists idx_sessions_user_started
  on public.chat_sessions (user_id, started_at desc);


-- ─── 5. chat_messages ───────────────────────────────────────────────────────
create table if not exists public.chat_messages (
  message_id    uuid primary key default gen_random_uuid(),
  session_id    uuid not null references public.chat_sessions(session_id) on delete cascade,
  sender        text not null check (sender in ('user', 'bot')),
  message_text  text not null,
  sources       jsonb,
  "timestamp"   timestamptz not null default now()
);

create index if not exists idx_messages_session_ts
  on public.chat_messages (session_id, "timestamp");


-- ============================================================================
-- Row Level Security
-- ============================================================================
alter table public.devices            enable row level security;
alter table public.notifications      enable row level security;
alter table public.incident_summaries enable row level security;
alter table public.chat_sessions      enable row level security;
alter table public.chat_messages      enable row level security;

-- devices: owner-scoped CRUD
drop policy if exists "devices_owner_select" on public.devices;
drop policy if exists "devices_owner_modify" on public.devices;
create policy "devices_owner_select"
  on public.devices for select
  using (auth.uid() = user_id);
create policy "devices_owner_modify"
  on public.devices for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- notifications: read + update (mark as read) only
drop policy if exists "notifications_owner_select" on public.notifications;
drop policy if exists "notifications_owner_update" on public.notifications;
create policy "notifications_owner_select"
  on public.notifications for select
  using (auth.uid() = user_id);
create policy "notifications_owner_update"
  on public.notifications for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- incident_summaries: read-only for owner (server inserts via service role)
drop policy if exists "summaries_owner_select" on public.incident_summaries;
create policy "summaries_owner_select"
  on public.incident_summaries for select
  using (auth.uid() = user_id);

-- chat_sessions / chat_messages: owner-scoped
drop policy if exists "chat_sessions_owner_all" on public.chat_sessions;
create policy "chat_sessions_owner_all"
  on public.chat_sessions for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "chat_messages_owner_all" on public.chat_messages;
create policy "chat_messages_owner_all"
  on public.chat_messages for all
  using (
    exists (
      select 1 from public.chat_sessions s
      where s.session_id = chat_messages.session_id
        and s.user_id    = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.chat_sessions s
      where s.session_id = chat_messages.session_id
        and s.user_id    = auth.uid()
    )
  );
