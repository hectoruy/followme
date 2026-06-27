create extension if not exists pgcrypto;

create table if not exists public.location_sessions (
  id uuid primary key default gen_random_uuid(),
  latitude double precision not null,
  longitude double precision not null,
  active boolean not null default true,
  driver_name text not null default '',
  driver_phone text not null default '',
  client_latitude double precision,
  client_longitude double precision,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists location_sessions_active_updated_at_idx
  on public.location_sessions (active, updated_at desc);

create or replace function public.set_location_sessions_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_location_sessions_updated_at on public.location_sessions;
create trigger set_location_sessions_updated_at
before update on public.location_sessions
for each row
execute function public.set_location_sessions_updated_at();

alter table public.location_sessions enable row level security;

drop policy if exists "location_sessions_select_anon" on public.location_sessions;
drop policy if exists "location_sessions_insert_anon" on public.location_sessions;
drop policy if exists "location_sessions_update_anon" on public.location_sessions;

create policy "location_sessions_select_anon"
on public.location_sessions
for select
to anon
using (true);

create policy "location_sessions_insert_anon"
on public.location_sessions
for insert
to anon
with check (true);

create policy "location_sessions_update_anon"
on public.location_sessions
for update
to anon
using (true)
with check (true);

grant usage on schema public to anon, authenticated;
grant select, insert, update on public.location_sessions to anon, authenticated;

alter table public.location_sessions replica identity full;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'location_sessions'
  ) then
    alter publication supabase_realtime add table public.location_sessions;
  end if;
end;
$$;
