-- CF-247 Phase 2 (8 Oct 2026): a replay call that ran out of worker resources ended without saving or releasing its lease, so the same run
-- was picked again after every lease and the runs behind it waited (CRICOS version 2 adapter slices). A run now counts the calls made at
-- the same engine and position: after three without progress it stops with an error, and a leased run no longer holds up the others.
do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'public.svc_register_replay_next_v3()'::regprocedure) is distinct from '6734bb9841dd3b9344b9c494a8685c05' then
    raise exception 'svc_register_replay_next_v3 is not the migration 3500 definition; refusing to replace it';
  end if;
end $g$;
alter table pipeline.register_replay_runs add column if not exists attempts int not null default 0, add column if not exists attempt_at text;

create or replace function public.svc_register_replay_next_v3()
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare r pipeline.register_replay_runs%rowtype; v_pos int; v_engine text; v_at text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into r from pipeline.register_replay_runs
   where done_at is null and error is null and not (reference_done and adapter_done) and (lease_until is null or lease_until <= now())
   order by created_at limit 1 for update skip locked;
  if r.id is null then return null; end if;
  v_engine := case when not r.reference_done then 'reference' else 'adapter' end;
  v_pos := case when not r.reference_done then r.reference_pos else r.adapter_pos end;
  v_at := v_engine || ':' || v_pos;
  if r.attempt_at is not distinct from v_at and r.attempts >= 3 then
    update pipeline.register_replay_runs
       set error = v_engine || ': stopped after three calls ended without saving at position ' || v_pos || ' (probably the worker resource limit)', done_at = now(), lease_until = null
     where id = r.id;
    return null;
  end if;
  update pipeline.register_replay_runs
     set lease_until = now() + interval '150 seconds', attempts = case when attempt_at is not distinct from v_at then attempts + 1 else 1 end, attempt_at = v_at
   where id = r.id;
  return jsonb_build_object('run_id', r.id, 'engine', v_engine, 'pos', v_pos,
                            'storage_path', r.storage_path, 'paths', to_jsonb(r.paths), 'zip_hash', r.zip_hash, 'keep_fields', r.keep_fields,
                            'code', (select a.code from pipeline.register_adapters a where a.source_id = r.source_id),
                            'spec', (select a.spec from pipeline.register_adapters a where a.source_id = r.source_id));
end $f$;
revoke all on function public.svc_register_replay_next_v3() from public, anon, authenticated;
grant execute on function public.svc_register_replay_next_v3() to service_role;
