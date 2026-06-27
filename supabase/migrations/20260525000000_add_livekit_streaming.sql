alter table public.location_sessions
add column if not exists video_enabled boolean not null default false;

create table if not exists public.live_stream_sessions (
  session_id uuid primary key references public.location_sessions(id) on delete cascade,
  room_name text not null unique,
  driver_secret_hash text not null,
  created_at timestamptz not null default now()
);

create index if not exists live_stream_sessions_created_at_idx
  on public.live_stream_sessions (created_at desc);

alter table public.live_stream_sessions enable row level security;

revoke all on public.live_stream_sessions from anon;
revoke all on public.live_stream_sessions from authenticated;

