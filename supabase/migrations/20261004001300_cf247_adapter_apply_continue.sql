-- CF-247 Decision 253 (4 Oct 2026). Applying an adapter read up to 120 stored pages in one edge call. A large course
-- page takes about 75 ms of processor time to read, and an edge call may use only about two seconds, so Apply on
-- Flinders (study pages of about 300 KB) stopped with "CPU Time exceeded" before recording anything. The worker
-- (v0.16.1) now reads pages one after another, stops after about a second of reading and asks for a fresh call that
-- carries on after the last page read. The page order only moves forward, so the chain ends at the last page.
-- No text value in this file contains a semicolon.

create or replace function public.svc_adapter_apply_continue(p_provider_id uuid, p_after uuid) returns bigint
language plpgsql security definer set search_path = '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_after is null or not exists (select 1 from pipeline.uni_adapters a where a.provider_id = p_provider_id and a.enabled) then return null; end if;
  return pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_apply', 'provider_id', p_provider_id, 'after', p_after));
end $f$;
revoke all on function public.svc_adapter_apply_continue(uuid, uuid) from public, anon, authenticated;
grant execute on function public.svc_adapter_apply_continue(uuid, uuid) to service_role;
