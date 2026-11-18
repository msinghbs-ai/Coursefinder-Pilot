-- CF-247 Wave 2 PR C (S2-Build; Platform Admin 17 Nov 2026 17:55, 19:08, 19:58, 22:04, 23:02): the generic Layer 1 declarative runner.
-- A source whose parser is AI-built (pipeline.layer1_source_parsers.parser_kind 'ai_built', a strict JSON spec checked by
-- security.layer1_parser_spec_validate_v1; no SQL or code) is read by the edge function layer1-declarative-runner: the file is fetched and kept as
-- evidence, its headers are checked against the spec (a missing header halts the run and flags the parser for re-inference), the spec turns rows
-- into canonical records, and the records are staged in chunks of layer1.declarative_chunk_rows with a row key and a row hash, so a re-run finds
-- what is new, changed, unchanged or gone. Course and provider registers are applied through public.svc_layer1_apply_register_records (the
-- path every Layer 1 register uses); the other five record types are staged for review. Each staged record names the enrichment categories it
-- leaves open (gap routing to the eight categories of ref.enrichment_categories), and an Australian postcode is checked against the ABS
-- postcode-to-SUA shares (security.destination_postcode_flags_v1: primary, Layer 4 review, or outside every SUA).
-- A dry run (Layer 1 › Sources › + Add source, step 5) reads the first layer1.declarative_dry_run_rows rows, writes nothing to staging and records
-- its counts with public.svc_layer1_induction_dry_run_record (a passing dry run switches nothing on). An apply run needs an active, unpaused
-- source with approved terms (REQ-68) and an undrifted AI-built parser. Gone rows are marked departed in staging only: catalogue records are
-- never retired here (that stays with the register plan and the Platform Admin). No job is scheduled by this change.
-- Hardcoded parsers stay on their own workers (parser_kind 'hardcoded'; Platform Admin 19:08).
-- Replaces: nothing.
-- Retires: nothing.

-- settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'layer1.declarative_chunk_rows', 'Layer 1 declarative runner: rows a chunk',
  'How many records the declarative runner stages (and applies, for course and provider registers) in one call.',
  'number', to_jsonb(200), 10, 1000, 'rows', 1215, 'Wave 2 PR C (S2-Build, 17 Nov 2026)', 'Layer 1 register', 'layer1-declarative-runner'),
 ('pipeline', 'layer1.declarative_dry_run_rows', 'Layer 1 declarative runner: dry-run rows',
  'How many rows a dry run reads from the top of the source (wizard step 5). It writes nothing.',
  'number', to_jsonb(100), 10, 1000, 'rows', 1216, 'Wave 2 PR C (S2-Build, 17 Nov 2026)', 'Layer 1 register', 'layer1-declarative-runner (dry run)'),
 ('pipeline', 'layer1.declarative_batch_rows', 'Layer 1 declarative runner: rows a call',
  'How many source rows one call of an apply run reads, stages and applies; a larger source continues in further calls of the same run.',
  'number', to_jsonb(2000), 200, 20000, 'rows', 1218, 'Wave 2 PR C (S2-Build, 17 Nov 2026)', 'Layer 1 register', 'layer1-declarative-runner (apply)'),
 ('pipeline', 'layer1.declarative_max_rows', 'Layer 1 declarative runner: largest source',
  'The most rows one apply run reads. A larger source stops with its size named.',
  'number', to_jsonb(200000), 1000, 2000000, 'rows', 1217, 'Wave 2 PR C (S2-Build, 17 Nov 2026)', 'Layer 1 register', 'layer1-declarative-runner (apply)')
on conflict (toolset_key, key) do nothing;

-- 1. runs and staged rows
create table if not exists pipeline.layer1_declarative_runs (
  id uuid primary key default gen_random_uuid(),
  source_id uuid references pipeline.sources(id),
  induction_id uuid references pipeline.layer1_source_inductions(id),
  mode text not null check (mode in ('dry_run', 'apply')),
  record_type text not null,
  status text not null default 'running' check (status in ('running', 'completed', 'failed', 'halted_drift')),
  reader text,
  job_id uuid,
  evidence_id uuid,
  counts jsonb not null default '{}'::jsonb,
  message text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  check (source_id is not null or induction_id is not null)
);
comment on table pipeline.layer1_declarative_runs is 'CF-247 Wave 2 PR C (17 Nov 2026): one row per Layer 1 declarative runner run (dry run for a wizard draft, or apply for an active source with an AI-built parser): record type, outcome (completed, failed, or halted on header drift), the evidence kept, and the counts (rows read, records, inserts, updates, unchanged, departures, applied, staged for review, postcode escalations, gaps by enrichment category).';
create index if not exists layer1_declarative_runs_source_idx on pipeline.layer1_declarative_runs(source_id, started_at desc);
alter table pipeline.layer1_declarative_runs enable row level security;
revoke all on pipeline.layer1_declarative_runs from anon, authenticated;

create table if not exists pipeline.layer1_declarative_rows (
  source_id uuid not null references pipeline.sources(id),
  row_key text not null,
  record_type text not null,
  row_hash text not null,
  record jsonb not null,
  evidence_id uuid,
  apply_state text not null check (apply_state in ('applied', 'staged_review')),
  gap_categories text[] not null default '{}',
  postcode_flag text check (postcode_flag in ('primary', 'layer4_review', 'outside_sua')),
  state text not null default 'current' check (state in ('current', 'departed')),
  first_seen_run uuid references pipeline.layer1_declarative_runs(id),
  last_seen_run uuid references pipeline.layer1_declarative_runs(id),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  last_changed_at timestamptz not null default now(),
  departed_at timestamptz,
  primary key (source_id, row_key)
);
comment on table pipeline.layer1_declarative_rows is 'CF-247 Wave 2 PR C (17 Nov 2026): Layer 1 declarative staging, one row per source record key: the canonical record the AI-built parser spec produced, its row hash (deterministic diffing between runs), whether it was applied (course and provider registers) or is staged for review (the other record types), the enrichment categories it leaves open, the ABS postcode flag, and current or departed. Departed marks staging only; no catalogue record is retired here.';
create index if not exists layer1_declarative_rows_run_idx on pipeline.layer1_declarative_rows(source_id, last_seen_run);
alter table pipeline.layer1_declarative_rows enable row level security;
revoke all on pipeline.layer1_declarative_rows from anon, authenticated;

-- 2. gap routes: for each record type, the fields whose absence leaves an enrichment category open (data, not code)
create or replace function security.layer1_gap_routes_v1()
 returns jsonb
 language sql
 immutable
 set search_path to ''
as $function$
  select jsonb_build_object(
    'course_register', jsonb_build_object('course_basics', jsonb_build_array('course_level', 'duration_weeks', 'field_code'),
                                          'campus_location', jsonb_build_array('city', 'state', 'postcode'), 'provider_profile', jsonb_build_array('website')),
    'provider_register', jsonb_build_object('provider_profile', jsonb_build_array('provider_classification', 'website'),
                                            'campus_location', jsonb_build_array('city', 'state', 'postcode', 'address_line1')),
    'tuition_fees', jsonb_build_object('fees', jsonb_build_array('currency_code', 'fee_year', 'audience', 'basis'), 'campus_location', jsonb_build_array('campus_name')),
    'study_rules', jsonb_build_object('recognition_registration', jsonb_build_array('visa_subclass', 'effective_from')),
    'destination_metrics', jsonb_build_object('campus_location', jsonb_build_array('locality_name', 'geography_type')),
    'career_outcomes', jsonb_build_object('course_basics', jsonb_build_array('median_salary', 'employment_rate_pct', 'job_outlook_rating')),
    'scholarships', jsonb_build_object('scholarships', jsonb_build_array('amount', 'close_date', 'eligibility', 'study_level'), 'provider_profile', jsonb_build_array('provider_code')))
$function$;
comment on function security.layer1_gap_routes_v1() is 'CF-247 Wave 2 PR C (17 Nov 2026): gap routing for the Layer 1 declarative runner: per record type, the enrichment category (ref.enrichment_categories) each empty field leaves open.';
revoke all on function security.layer1_gap_routes_v1() from public, anon, authenticated;

-- 3. service-role functions the runner calls
create or replace function public.svc_layer1_declarative_source_v1(p_source_id uuid default null, p_induction_id uuid default null)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare v_ind jsonb; v_par pipeline.layer1_source_parsers; v_ops pipeline.layer1_source_operations; v_src pipeline.sources;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  if p_induction_id is not null then
    select security.layer1_induction_item_v1(i) into v_ind from pipeline.layer1_source_inductions i where i.id = p_induction_id;
  elsif p_source_id is not null then
    select security.layer1_induction_item_v1(i) into v_ind from pipeline.layer1_source_inductions i where i.source_id = p_source_id order by i.updated_at desc limit 1;
  end if;
  select * into v_par from pipeline.layer1_source_parsers p where p.source_id = coalesce(p_source_id, (v_ind->>'source_id')::uuid);
  select * into v_ops from pipeline.layer1_source_operations o where o.source_id = coalesce(p_source_id, (v_ind->>'source_id')::uuid);
  select * into v_src from pipeline.sources s where s.id = coalesce(p_source_id, (v_ind->>'source_id')::uuid);
  return jsonb_build_object('induction', v_ind,
    'parser', case when v_par.source_id is null then null else jsonb_build_object('parser_kind', v_par.parser_kind, 'target_record_type', v_par.target_record_type,
      'parser_spec', v_par.parser_spec, 'spec_version', v_par.spec_version, 'drift_flagged_at', v_par.drift_flagged_at) end,
    'source', case when v_src.id is null then null else jsonb_build_object('id', v_src.id, 'url', v_src.url, 'label', v_src.label,
      'country_code', (select c.iso_alpha2::text from ref.countries c where c.id = v_src.country_id)) end,
    'operations', case when v_ops.source_id is null then null else jsonb_build_object('active', v_ops.active, 'paused', v_ops.paused, 'expected_format', v_ops.expected_format) end,
    'targets', security.layer1_parser_targets_v1(), 'gap_routes', security.layer1_gap_routes_v1(),
    'categories', (select coalesce(jsonb_agg(e.category_key order by e.sort_order), '[]'::jsonb) from ref.enrichment_categories e));
end $function$;
comment on function public.svc_layer1_declarative_source_v1(uuid, uuid) is 'CF-247 Wave 2 PR C (17 Nov 2026): what layer1-declarative-runner needs for a source or a wizard draft: the draft, the parser (kind, spec, drift), the source, its Layer 1 controls, the allowed targets and the gap routes. Service role only.';
revoke all on function public.svc_layer1_declarative_source_v1(uuid, uuid) from public, anon, authenticated;
grant execute on function public.svc_layer1_declarative_source_v1(uuid, uuid) to service_role;

create or replace function public.svc_layer1_declarative_run_start_v1(p_source_id uuid, p_induction_id uuid, p_mode text, p_record_type text, p_reader text default null)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_id uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  if p_mode = 'apply' and p_source_id is null then raise exception 'an apply run needs a source' using errcode = '22023'; end if;
  if p_mode = 'apply' and exists (select 1 from pipeline.layer1_declarative_runs r where r.source_id = p_source_id and r.mode = 'apply' and r.status = 'running'
                                    and r.started_at > now() - interval '60 minutes') then  -- fixed: run lease, one apply run per source at a time
    raise exception 'an apply run for this source is already running' using errcode = '55000';
  end if;
  if not (security.layer1_parser_targets_v1() ? p_record_type) then raise exception 'unknown record type %', p_record_type using errcode = '22023'; end if;
  insert into pipeline.layer1_declarative_runs(source_id, induction_id, mode, record_type, reader)
  values (p_source_id, p_induction_id, p_mode, p_record_type, left(coalesce(p_reader, ''), 120)) returning id into v_id;
  return v_id;
end $function$;
comment on function public.svc_layer1_declarative_run_start_v1(uuid, uuid, text, text, text) is 'CF-247 Wave 2 PR C (17 Nov 2026): opens a Layer 1 declarative runner run (one apply run per source at a time). Service role only.';
revoke all on function public.svc_layer1_declarative_run_start_v1(uuid, uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.svc_layer1_declarative_run_start_v1(uuid, uuid, text, text, text) to service_role;

create or replace function public.svc_layer1_declarative_run_note_v1(p_run_id uuid, p_job_id uuid, p_evidence_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  update pipeline.layer1_declarative_runs set job_id = coalesce(p_job_id, job_id), evidence_id = coalesce(p_evidence_id, evidence_id) where id = p_run_id;
end $function$;
comment on function public.svc_layer1_declarative_run_note_v1(uuid, uuid, uuid) is 'CF-247 Wave 2 PR C (17 Nov 2026): records the Layer 1 job and the evidence kept for a declarative runner run. Service role only.';
revoke all on function public.svc_layer1_declarative_run_note_v1(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.svc_layer1_declarative_run_note_v1(uuid, uuid, uuid) to service_role;

-- staged rows: [{key, hash, record, gaps, postcode_flag, apply_state}]; compares with what the source holds and, when p_write, keeps them
create or replace function public.svc_layer1_declarative_stage_v1(p_run_id uuid, p_rows jsonb, p_write boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_run pipeline.layer1_declarative_runs; v_ins int := 0; v_upd int := 0; v_same int := 0; v_keys jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  select * into v_run from pipeline.layer1_declarative_runs where id = p_run_id;
  if v_run.id is null or v_run.status <> 'running' then raise exception 'run not open' using errcode = '22023'; end if;
  if coalesce(p_write, false) and (v_run.mode <> 'apply' or v_run.source_id is null) then raise exception 'only an apply run writes staging' using errcode = '22023'; end if;
  with x as (
    select e->>'key' k, e->>'hash' h, e->'record' rec, coalesce(array(select jsonb_array_elements_text(e->'gaps')), '{}') gaps,
           nullif(e->>'postcode_flag', '') pf, coalesce(nullif(e->>'apply_state', ''), 'staged_review') st
      from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) e where coalesce(e->>'key', '') <> '' and coalesce(e->>'hash', '') <> '')
  select count(*) filter (where d.row_key is null), count(*) filter (where d.row_key is not null and (d.row_hash <> x.h or d.state = 'departed')),
         count(*) filter (where d.row_key is not null and d.row_hash = x.h and d.state = 'current'),
         coalesce(jsonb_agg(x.k) filter (where d.row_key is null or d.row_hash <> x.h or d.state = 'departed'), '[]'::jsonb)
    into v_ins, v_upd, v_same, v_keys
    from x left join pipeline.layer1_declarative_rows d on d.source_id = v_run.source_id and d.row_key = x.k;
  if coalesce(p_write, false) then
    insert into pipeline.layer1_declarative_rows as d (source_id, row_key, record_type, row_hash, record, evidence_id, apply_state, gap_categories, postcode_flag, first_seen_run, last_seen_run)
    select v_run.source_id, e->>'key', v_run.record_type, e->>'hash', e->'record', v_run.evidence_id, coalesce(nullif(e->>'apply_state', ''), 'staged_review'),
           coalesce(array(select jsonb_array_elements_text(e->'gaps')), '{}'), nullif(e->>'postcode_flag', ''), p_run_id, p_run_id
      from jsonb_array_elements(p_rows) e where coalesce(e->>'key', '') <> '' and coalesce(e->>'hash', '') <> ''
    on conflict (source_id, row_key) do update set
      last_seen_run = excluded.last_seen_run, last_seen_at = now(), state = 'current', departed_at = null,
      record = excluded.record, record_type = excluded.record_type, apply_state = excluded.apply_state, gap_categories = excluded.gap_categories,
      postcode_flag = excluded.postcode_flag, evidence_id = excluded.evidence_id,
      last_changed_at = case when d.row_hash <> excluded.row_hash or d.state = 'departed' then now() else d.last_changed_at end,
      row_hash = excluded.row_hash;
  end if;
  return jsonb_build_object('inserts', v_ins, 'updates', v_upd, 'unchanged', v_same, 'changed_keys', v_keys);
end $function$;
comment on function public.svc_layer1_declarative_stage_v1(uuid, jsonb, boolean) is 'CF-247 Wave 2 PR C (17 Nov 2026): compares a chunk of canonical records (row key and row hash) with what the source has staged (new, changed, unchanged; the new and changed keys are returned) and, for an apply run, keeps them in pipeline.layer1_declarative_rows. Service role only.';
revoke all on function public.svc_layer1_declarative_stage_v1(uuid, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.svc_layer1_declarative_stage_v1(uuid, jsonb, boolean) to service_role;

-- postcodes: the ABS postcode-to-SUA flag for each Australian postcode (latest boundary vintage)
create or replace function public.svc_layer1_declarative_postcodes_v1(p_postcodes text[])
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  return (select coalesce(jsonb_object_agg(q.pc, q.flag), '{}'::jsonb) from (
    select pc, case when b.share is null then 'outside_sua' when (security.destination_postcode_flags_v1(b.share)).is_primary_match then 'primary' else 'layer4_review' end flag
      from unnest(coalesce(p_postcodes, '{}')) pc
      left join lateral (select max(s.share) share from destination.abs_postcode_sua_shares s
                          where s.postcode = pc and s.boundary_vintage = (select max(boundary_vintage) from destination.abs_postcode_sua_shares)) b on true
     where pc ~ '^[0-9]{4}$') q);
end $function$;
comment on function public.svc_layer1_declarative_postcodes_v1(text[]) is 'CF-247 Wave 2 PR C (17 Nov 2026): for Australian postcodes, primary (largest SUA share at or above destination.postcode_primary_min_share), layer4_review (split across SUAs) or outside_sua, from destination.abs_postcode_sua_shares. Service role only.';
revoke all on function public.svc_layer1_declarative_postcodes_v1(text[]) from public, anon, authenticated;
grant execute on function public.svc_layer1_declarative_postcodes_v1(text[]) to service_role;

create or replace function public.svc_layer1_declarative_run_finish_v1(p_run_id uuid, p_status text, p_counts jsonb default '{}'::jsonb, p_message text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_run pipeline.layer1_declarative_runs; v_dep int := 0; v_counts jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  if p_status not in ('completed', 'failed', 'halted_drift') then raise exception 'a run ends completed, failed or halted_drift' using errcode = '22023'; end if;
  select * into v_run from pipeline.layer1_declarative_runs where id = p_run_id for update;
  if v_run.id is null or v_run.status <> 'running' then raise exception 'run not open' using errcode = '22023'; end if;
  if v_run.mode = 'apply' and p_status = 'completed' then
    -- departures: staged rows of this source not seen in this full read (staging only; the catalogue is not touched)
    with d as (update pipeline.layer1_declarative_rows r set state = 'departed', departed_at = now()
                where r.source_id = v_run.source_id and r.state = 'current' and r.last_seen_run is distinct from p_run_id returning 1)
    select count(*) into v_dep from d;
  end if;
  v_counts := coalesce(p_counts, '{}'::jsonb) || jsonb_build_object('departures', v_dep);
  update pipeline.layer1_declarative_runs set status = p_status, counts = v_counts, message = left(coalesce(p_message, ''), 1000), finished_at = now() where id = p_run_id;
  return jsonb_build_object('ok', true, 'run_id', p_run_id, 'status', p_status, 'counts', v_counts);
end $function$;
comment on function public.svc_layer1_declarative_run_finish_v1(uuid, text, jsonb, text) is 'CF-247 Wave 2 PR C (17 Nov 2026): closes a Layer 1 declarative runner run with its counts; a completed apply run marks the staged rows it did not see as departed (staging only). Service role only.';
revoke all on function public.svc_layer1_declarative_run_finish_v1(uuid, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.svc_layer1_declarative_run_finish_v1(uuid, text, jsonb, text) to service_role;

do $$
begin
  if exists (select 1 from jsonb_each(security.layer1_gap_routes_v1()) t, jsonb_object_keys(t.value) k where k not in (select category_key from ref.enrichment_categories where active)) then
    raise exception 'post-check: a gap route names a category that is not in ref.enrichment_categories';
  end if;
  if exists (select 1 from jsonb_object_keys(security.layer1_gap_routes_v1()) k where not (security.layer1_parser_targets_v1() ? k)) then
    raise exception 'post-check: a gap route names a record type with no parser target';
  end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('layer1.declarative_chunk_rows', 'layer1.declarative_dry_run_rows', 'layer1.declarative_batch_rows', 'layer1.declarative_max_rows')) <> 4 then
    raise exception 'post-check: settings';
  end if;
end $$;
