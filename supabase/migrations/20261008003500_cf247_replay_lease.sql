-- CF-247 Phase 2 (8 Oct 2026): a replay slice could still be running when the next minute's call started on the same run; both saved the
-- same records and one save hit the statement time limit (seen on NZQA and PRISMS). A run is now leased to one call (150 seconds, released
-- by the worker when the call ends, coverage-sweep v0.17.24); a call that finds the only open run leased does nothing.
do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'public.svc_register_replay_next_v3()'::regprocedure) is distinct from 'e3617cc0201ad9810879f568a909a846' then
    raise exception 'svc_register_replay_next_v3 is not the migration 2800 definition; refusing to replace it';
  end if;
end $g$;
alter table pipeline.register_replay_runs add column if not exists lease_until timestamptz;

create or replace function public.svc_register_replay_next_v3()
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare r pipeline.register_replay_runs%rowtype; v_pos int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into r from pipeline.register_replay_runs where done_at is null and error is null and not (reference_done and adapter_done)
   order by created_at limit 1 for update skip locked;
  if r.id is null or coalesce(r.lease_until > now(), false) then return null; end if;
  update pipeline.register_replay_runs set lease_until = now() + interval '150 seconds' where id = r.id;
  v_pos := case when not r.reference_done then r.reference_pos else r.adapter_pos end;
  return jsonb_build_object('run_id', r.id, 'engine', case when not r.reference_done then 'reference' else 'adapter' end, 'pos', v_pos,
                            'storage_path', r.storage_path, 'paths', to_jsonb(r.paths), 'zip_hash', r.zip_hash, 'keep_fields', r.keep_fields,
                            'code', (select a.code from pipeline.register_adapters a where a.source_id = r.source_id),
                            'spec', (select a.spec from pipeline.register_adapters a where a.source_id = r.source_id));
end $f$;
revoke all on function public.svc_register_replay_next_v3() from public, anon, authenticated;
grant execute on function public.svc_register_replay_next_v3() to service_role;

create or replace function public.svc_register_replay_release(p_run_id uuid)
returns void language plpgsql security definer set search_path = '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  update pipeline.register_replay_runs set lease_until = null where id = p_run_id;
end $f$;
revoke all on function public.svc_register_replay_release(uuid) from public, anon, authenticated;
grant execute on function public.svc_register_replay_release(uuid) to service_role;
