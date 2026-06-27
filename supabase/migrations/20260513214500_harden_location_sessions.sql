create or replace function public.set_location_sessions_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke execute on function public.set_location_sessions_updated_at() from public;
revoke execute on function public.set_location_sessions_updated_at() from anon;
revoke execute on function public.set_location_sessions_updated_at() from authenticated;

do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public;
    revoke execute on function public.rls_auto_enable() from anon;
    revoke execute on function public.rls_auto_enable() from authenticated;
  end if;
end;
$$;

drop policy if exists "location_sessions_insert_anon" on public.location_sessions;
drop policy if exists "location_sessions_update_anon" on public.location_sessions;

create policy "location_sessions_insert_anon"
on public.location_sessions
for insert
to anon
with check (
  id is not null
  and latitude between -90 and 90
  and longitude between -180 and 180
  and active = true
);

create policy "location_sessions_update_anon"
on public.location_sessions
for update
to anon
using (id is not null)
with check (
  id is not null
  and latitude between -90 and 90
  and longitude between -180 and 180
  and (
    client_latitude is null
    or client_latitude between -90 and 90
  )
  and (
    client_longitude is null
    or client_longitude between -180 and 180
  )
);
