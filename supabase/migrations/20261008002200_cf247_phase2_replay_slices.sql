-- CF-247 Phase 2, 8 Oct 2026: the first replay call failed with the edge resource limit (a whole register archive, about 25,500 courses,
-- in one call). The worker (v0.17.20) now reads 4,000 records a call; the run remembers how far each engine has got. The earlier
-- svc_register_replay_next/save stay in place, unused. Read only for the catalogue, as before.
alter table pipeline.register_replay_runs add column if not exists reference_pos int not null default 0, add column if not exists adapter_pos int not null default 0;

create or replace function public.svc_register_replay_next_v2()
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare r pipeline.register_replay_runs%rowtype;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into r from pipeline.register_replay_runs where done_at is null and error is null and not (reference_done and adapter_done) order by created_at limit 1;
  if r.id is null then return null; end if;
  return jsonb_build_object('run_id', r.id, 'engine', case when not r.reference_done then 'reference' else 'adapter' end,
                            'pos', case when not r.reference_done then r.reference_pos else r.adapter_pos end, 'storage_path', r.storage_path,
                            'zip_hash', r.zip_hash, 'keep_fields', r.keep_fields, 'spec', (select a.spec from pipeline.register_adapters a where a.source_id = r.source_id));
end $f$;

create or replace function public.svc_register_replay_save_v2(p_run_id uuid, p_engine text, p_rows jsonb, p_pos int, p_final boolean, p_error text default null)
returns int language plpgsql security definer set search_path = '' as $f$
declare n int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_error is not null then
    update pipeline.register_replay_runs set error = p_engine || ': ' || left(p_error, 300), done_at = now() where id = p_run_id;
    return 0;
  end if;
  insert into pipeline.register_replay_keys(run_id, engine, record_key, fingerprint, fields_hash, fields)
  select p_run_id, p_engine, x->>'k', x->>'f', x->>'h', x->'x' from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) x
  on conflict (run_id, engine, record_key) do update set fingerprint = excluded.fingerprint, fields_hash = excluded.fields_hash, fields = excluded.fields,
         dup = pipeline.register_replay_keys.dup + 1;
  get diagnostics n = row_count;
  update pipeline.register_replay_runs
     set reference_pos = case when p_engine = 'reference' and p_pos is not null then p_pos else reference_pos end,
         adapter_pos = case when p_engine = 'adapter' and p_pos is not null then p_pos else adapter_pos end
   where id = p_run_id;
  if p_final then
    update pipeline.register_replay_runs
       set reference_done = reference_done or p_engine = 'reference', adapter_done = adapter_done or p_engine = 'adapter',
           reference_records = case when p_engine = 'reference' then (select count(*) from pipeline.register_replay_keys k where k.run_id = p_run_id and k.engine = 'reference') else reference_records end,
           adapter_records = case when p_engine = 'adapter' then (select count(*) from pipeline.register_replay_keys k where k.run_id = p_run_id and k.engine = 'adapter') else adapter_records end
     where id = p_run_id;
    perform security.register_replay_compare_v1(p_run_id);
  end if;
  return n;
end $f$;
revoke all on function public.svc_register_replay_next_v2(), public.svc_register_replay_save_v2(uuid, text, jsonb, int, boolean, text) from public, anon, authenticated;
grant execute on function public.svc_register_replay_next_v2(), public.svc_register_replay_save_v2(uuid, text, jsonb, int, boolean, text) to service_role;
