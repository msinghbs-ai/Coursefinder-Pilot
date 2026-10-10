create table if not exists pipeline.pilot_automation_keys (
  name text primary key,
  key_hash text not null,
  enabled boolean not null default true,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table pipeline.pilot_automation_keys enable row level security;
revoke all on pipeline.pilot_automation_keys from public, anon, authenticated;
revoke all on pipeline.pilot_automation_keys from service_role;

insert into pipeline.pilot_automation_keys(name,key_hash,enabled,expires_at)
values ('coursefinder_pilot_automation','93b3e9b8ae6b5fa13b9f212c92fb36ab3a3ea83f0d3aa2773b0549d1b380642c',true,'2026-09-30 23:59:59+10')
on conflict (name) do update set key_hash=excluded.key_hash, enabled=true, expires_at=excluded.expires_at, updated_at=now();

create or replace function public.svc_pilot_automation_authorize(p_key text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pipeline, extensions
as $$
  select coalesce((
    select k.enabled
      and (k.expires_at is null or k.expires_at > now())
      and k.key_hash = encode(extensions.digest(convert_to(coalesce(p_key,''),'UTF8'),'sha256'),'hex')
    from pipeline.pilot_automation_keys k
    where k.name='coursefinder_pilot_automation'
  ), false);
$$;

revoke all on function public.svc_pilot_automation_authorize(text) from public, anon, authenticated;
grant execute on function public.svc_pilot_automation_authorize(text) to service_role;
comment on function public.svc_pilot_automation_authorize(text) is 'Temporary Pilot-only server automation secret validator. Remove/disable before production hardening.';