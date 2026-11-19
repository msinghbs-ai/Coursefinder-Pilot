-- CF-247 / Decision 155 step 2 (R19): change-based register apply.
-- Each register record has a fingerprint (its source rows). A run first plans: it compares the
-- current register with the last applied fingerprints and lists only new and changed records
-- (departed records are listed for step 6). Batches then apply only the planned records and
-- record their fingerprints. Unchanged records are counted, not re-applied.
-- Consumer API: not touched.

create table if not exists pipeline.layer1_register_row_state(
  source_id uuid not null references pipeline.sources(id) on delete cascade,
  record_key text not null,
  fingerprint text not null,
  applied_run_id uuid,
  applied_at timestamptz not null default now(),
  seen_at timestamptz not null default now(),
  primary key (source_id, record_key));
alter table pipeline.layer1_register_row_state enable row level security;
revoke all on pipeline.layer1_register_row_state from public, anon, authenticated;

create table if not exists pipeline.layer1_run_plans(
  run_id uuid primary key references pipeline.layer1_run_queue(id) on delete cascade,
  source_id uuid not null references pipeline.sources(id) on delete cascade,
  register_total integer not null,
  new_count integer not null,
  changed_count integer not null,
  unchanged_count integer not null,
  departed_count integer not null,
  items jsonb not null,            -- ordered [[record_key, fingerprint, 'new'|'changed'], ...]
  departed_keys text[] not null default '{}',
  zip_evidence_id uuid references pipeline.evidence_artifacts(id),
  course_evidence_id uuid references pipeline.evidence_artifacts(id),
  course_hash text,
  created_at timestamptz not null default now());
alter table pipeline.layer1_run_plans enable row level security;
revoke all on pipeline.layer1_run_plans from public, anon, authenticated;

-- Plan a run (or, with p_bootstrap, record the current register as already applied: allowed only
-- when the register file is the one last accepted, so the catalogue already reflects it).
create or replace function public.svc_layer1_plan_changes(p_run_id uuid, p_source_id uuid, p_rows jsonb,
  p_zip_evidence_id uuid, p_course_evidence_id uuid, p_course_hash text, p_bootstrap boolean default false)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare v_total int; v_new int; v_changed int; v_unchanged int; v_departed text[]; v_items jsonb; v_accepted text;
begin
  if jsonb_typeof(p_rows)<>'array' then raise exception 'rows must be an array'; end if;
  create temp table if not exists t_l1_rows(k text primary key, f text not null) on commit drop;
  truncate t_l1_rows;
  insert into t_l1_rows(k,f) select r->>0, r->>1 from jsonb_array_elements(p_rows) r
    where coalesce(r->>0,'')<>'' and coalesce(r->>1,'')<>'' on conflict (k) do nothing;
  select count(*) into v_total from t_l1_rows;
  if v_total<1 then raise exception 'empty register plan'; end if;

  if p_bootstrap then
    select previous_accepted_hash into v_accepted from pipeline.layer1_source_operations where source_id=p_source_id;
    if v_accepted is null or v_accepted<>p_course_hash then
      raise exception 'bootstrap refused: register file % is not the last accepted file %', left(p_course_hash,12), left(coalesce(v_accepted,'none'),12);
    end if;
    insert into pipeline.layer1_register_row_state(source_id,record_key,fingerprint,applied_run_id,applied_at,seen_at)
    select p_source_id,k,f,null,now(),now() from t_l1_rows
    on conflict (source_id,record_key) do update set fingerprint=excluded.fingerprint, seen_at=now()
      where layer1_register_row_state.fingerprint is distinct from excluded.fingerprint;
    return jsonb_build_object('bootstrap',true,'register_total',v_total,'course_hash',p_course_hash);
  end if;

  select count(*) filter (where s.record_key is null), count(*) filter (where s.record_key is not null and s.fingerprint<>t.f),
         count(*) filter (where s.fingerprint=t.f)
    into v_new, v_changed, v_unchanged
    from t_l1_rows t left join pipeline.layer1_register_row_state s on s.source_id=p_source_id and s.record_key=t.k;
  select coalesce(jsonb_agg(jsonb_build_array(t.k,t.f,case when s.record_key is null then 'new' else 'changed' end) order by t.k),'[]'::jsonb)
    into v_items
    from t_l1_rows t left join pipeline.layer1_register_row_state s on s.source_id=p_source_id and s.record_key=t.k
   where s.record_key is null or s.fingerprint<>t.f;
  select coalesce(array_agg(s.record_key order by s.record_key),'{}') into v_departed
    from pipeline.layer1_register_row_state s where s.source_id=p_source_id and not exists (select 1 from t_l1_rows t where t.k=s.record_key);
  update pipeline.layer1_register_row_state s set seen_at=now() from t_l1_rows t where s.source_id=p_source_id and s.record_key=t.k and s.fingerprint=t.f;

  insert into pipeline.layer1_run_plans(run_id,source_id,register_total,new_count,changed_count,unchanged_count,departed_count,items,departed_keys,zip_evidence_id,course_evidence_id,course_hash)
  values (p_run_id,p_source_id,v_total,v_new,v_changed,v_unchanged,cardinality(v_departed),v_items,v_departed,p_zip_evidence_id,p_course_evidence_id,p_course_hash)
  on conflict (run_id) do update set register_total=excluded.register_total,new_count=excluded.new_count,changed_count=excluded.changed_count,
    unchanged_count=excluded.unchanged_count,departed_count=excluded.departed_count,items=excluded.items,departed_keys=excluded.departed_keys,
    zip_evidence_id=excluded.zip_evidence_id,course_evidence_id=excluded.course_evidence_id,course_hash=excluded.course_hash,created_at=now();
  return jsonb_build_object('register_total',v_total,'new',v_new,'changed',v_changed,'unchanged',v_unchanged,'departed',cardinality(v_departed),'to_apply',v_new+v_changed);
end $f$;

-- Read a slice of a run's plan, with the stored register files to read it from.
create or replace function public.svc_layer1_plan_slice(p_run_id uuid, p_offset integer, p_limit integer)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','pipeline' as $f$
  select jsonb_build_object(
    'exists', p.run_id is not null,
    'to_apply', jsonb_array_length(p.items),
    'register_total', p.register_total,
    'keys', coalesce((select jsonb_agg(i->0 order by o) from jsonb_array_elements(p.items) with ordinality x(i,o)
                       where o>greatest(p_offset,0) and o<=greatest(p_offset,0)+greatest(least(p_limit,500),1)),'[]'::jsonb),
    'zip_evidence_id', p.zip_evidence_id, 'zip_path', z.storage_path, 'zip_hash', z.content_hash,
    'course_evidence_id', p.course_evidence_id, 'course_path', c.storage_path, 'course_hash', p.course_hash)
  from pipeline.layer1_run_plans p
  left join pipeline.evidence_artifacts z on z.id=p.zip_evidence_id
  left join pipeline.evidence_artifacts c on c.id=p.course_evidence_id
  where p.run_id=p_run_id
$f$;

-- Record that planned records were applied (their fingerprints become the new baseline).
create or replace function public.svc_layer1_plan_mark_applied(p_run_id uuid, p_keys text[])
returns integer language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare v_n int;
begin
  insert into pipeline.layer1_register_row_state(source_id,record_key,fingerprint,applied_run_id,applied_at,seen_at)
  select p.source_id, i->>0, i->>1, p_run_id, now(), now()
    from pipeline.layer1_run_plans p, jsonb_array_elements(p.items) i
   where p.run_id=p_run_id and (i->>0)=any(p_keys)
  on conflict (source_id,record_key) do update set fingerprint=excluded.fingerprint, applied_run_id=excluded.applied_run_id, applied_at=now(), seen_at=now();
  get diagnostics v_n = row_count;
  return v_n;
end $f$;

revoke all on function public.svc_layer1_plan_changes(uuid,uuid,jsonb,uuid,uuid,text,boolean) from public, anon, authenticated;
revoke all on function public.svc_layer1_plan_slice(uuid,integer,integer) from public, anon, authenticated;
revoke all on function public.svc_layer1_plan_mark_applied(uuid,text[]) from public, anon, authenticated;
grant execute on function public.svc_layer1_plan_changes(uuid,uuid,jsonb,uuid,uuid,text,boolean) to service_role;
grant execute on function public.svc_layer1_plan_slice(uuid,integer,integer) to service_role;
grant execute on function public.svc_layer1_plan_mark_applied(uuid,text[]) to service_role;
