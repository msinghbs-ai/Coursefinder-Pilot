-- Reusable portion of live Pilot migration 20260813225136.
-- The live project also has a temporary environment-local submit helper that posts
-- to its own Edge URL. That helper is intentionally not committed because it is
-- project-specific Pilot control-plane plumbing and must be removed before production.

create table if not exists pipeline.pilot_edge_nonces(
  id uuid primary key default extensions.gen_random_uuid(),
  function_name text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz
);
alter table pipeline.pilot_edge_nonces enable row level security;
revoke all on pipeline.pilot_edge_nonces from public, anon, authenticated;
grant select,update on pipeline.pilot_edge_nonces to service_role;

create or replace function public.svc_pilot_consume_nonce(p_function text,p_nonce uuid)
returns boolean language sql security invoker set search_path to 'pipeline','public'
as $function$
 with consumed as (
   update pipeline.pilot_edge_nonces set used_at=now()
   where id=p_nonce and function_name=p_function and used_at is null and expires_at>now()
   returning id
 ) select exists(select 1 from consumed);
$function$;
revoke all on function public.svc_pilot_consume_nonce(text,uuid) from public,anon,authenticated;
grant execute on function public.svc_pilot_consume_nonce(text,uuid) to service_role;
