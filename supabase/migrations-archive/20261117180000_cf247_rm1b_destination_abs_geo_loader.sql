-- CF-247 RM1B: ABS population and ASGS postcode loader for Australian destination localities (S2-Build mandate, Platform Admin 17 Nov 2026 13:12;
-- handoff from S1-RM-Design 14:11 and 14:30; Admin destination data design v1.9, approvals A-1 to A-4 of 17 Nov 2026 07:29 and 07:35).
--
-- What it builds
--   * destination.abs_postcode_sua_shares: for each Postal Area (ASGS Edition 3, 2021) the share of its area inside each Significant Urban
--     Area, derived from the ASGS Edition 3 Mesh Block allocation files (A-4: the allocation zip has no direct Postal Area to SUA file). Loaded
--     once per boundary vintage by workflow destination-abs-shares-load (the 277 MB zip is too large for an edge function).
--   * security.destination_abs_population_load_v1: one SUA locality per row of ABS Regional population 2024-25, Table 2 (A-1, A-2), with its
--     estimated resident population at 30 June 2025 as a draft figure, attribution on every locality and figure, the source file as evidence
--     (evidence_id on localities and figures, design spec step 1), the edition on destination.editions, then the postcode rows.
--   * security.destination_abs_postcodes_rebuild_v1: destination.locality_postcodes from the shares, flagged by
--     security.destination_postcode_flags_v1 (A-3 and G-3: at least 90% is the primary match; anything less waits for Layer 4 kind
--     Campus locality). A postcode with a Layer 4 decision is left as decided.
--   * job destination-abs-load (1st of the month, 05:30 Sydney) calling edge function layer1-destination-geo-loader with a one-time nonce;
--     catalogued with the destination- prefix so it shows on Platform health › Data delivery › Destination loads, with Run now.
--   * Run now for destination- jobs: security.job_run_now_v1 hands them to security.destination_job_run_now_v1, which starts the same edge
--     function with the same body the schedule sends; the edge function records the result on the Run now task.
-- Everything loads as draft. Nothing is approved or published by this change (a passing load never switches anything on by itself).
--
-- Replaces: nothing (destination localities had no loader).
-- Retires: nothing.

-- 1. evidence on localities and figures (design spec section 3, step 1)
alter table destination.localities add column if not exists evidence_id uuid references pipeline.evidence_artifacts(id);
alter table destination.locality_metrics add column if not exists evidence_id uuid references pipeline.evidence_artifacts(id);
comment on column destination.localities.evidence_id is 'The stored source file the locality was loaded from (RM1B).';
comment on column destination.locality_metrics.evidence_id is 'The stored source file the figure was loaded from (RM1B).';

-- 2. postcode to SUA shares
create table if not exists destination.abs_postcode_sua_shares (
  boundary_vintage text not null,
  postcode text not null,
  sua_code text not null,
  sua_name text not null,
  overlap_sqkm numeric not null check (overlap_sqkm >= 0),
  postcode_sqkm numeric not null check (postcode_sqkm > 0),
  share numeric(6,5) not null check (share >= 0 and share <= 1),
  mesh_blocks integer not null check (mesh_blocks > 0),
  evidence_id uuid references pipeline.evidence_artifacts(id),
  loaded_at timestamptz not null default now(),
  primary key (boundary_vintage, postcode, sua_code)
);
comment on table destination.abs_postcode_sua_shares is 'RM1B (A-3, A-4): share of each ASGS Edition 3 Postal Area''s area inside each Significant Urban Area, summed from the Mesh Block allocation files; the input to destination.locality_postcodes.';
alter table destination.abs_postcode_sua_shares enable row level security;
revoke all on table destination.abs_postcode_sua_shares from public, anon, authenticated;
grant select on table destination.abs_postcode_sua_shares to service_role;

-- 3. settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'destination.postcode_candidate_min_share', 'Destination: smallest postcode share kept as a candidate',
  'A postcode''s overlap with a locality smaller than this share is not stored, so boundary slivers do not show as review candidates. The primary match rule is the separate setting destination.postcode_primary_min_share.',
  'number', to_jsonb(0.01), 0, 0.5, 'share (0 to 1)', 1863, 'RM1B loader (S2-Build, Platform Admin 17 Nov 2026 13:12)', 'Destination data',
  'security.destination_abs_postcodes_rebuild_v1 (job destination-abs-load)')
on conflict (toolset_key, key) do nothing;

-- 4. evidence for a source file (one row per file and hash)
create or replace function security.destination_source_evidence_v1(p_url text, p_hash text, p_mime text, p_storage_path text, p_metadata jsonb)
 returns uuid
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_id uuid;
begin
  if coalesce(btrim(p_url), '') = '' or coalesce(btrim(p_hash), '') = '' then raise exception 'source link and file hash are required'; end if;
  select e.id into v_id from pipeline.evidence_artifacts e where e.source_url = p_url and e.content_hash = p_hash order by e.captured_at desc limit 1;
  if v_id is null then
    insert into pipeline.evidence_artifacts(evidence_type, source_url, storage_path, content_hash, mime_type, metadata, review_state)
    values ('dataset_file', p_url, nullif(btrim(p_storage_path), ''), p_hash, p_mime, coalesce(p_metadata, '{}'::jsonb), 'captured')
    returning id into v_id;
  elsif nullif(btrim(p_storage_path), '') is not null then
    update pipeline.evidence_artifacts set storage_path = coalesce(storage_path, p_storage_path) where id = v_id;
  end if;
  return v_id;
end $function$;
comment on function security.destination_source_evidence_v1(text, text, text, text, jsonb) is 'RM1B: the evidence row of a destination source file, one per link and SHA-256 hash.';

-- 5. shares load (workflow destination-abs-shares-load, through the Management API)
create or replace function security.destination_abs_shares_load_v1(p_payload jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_vintage text := btrim(p_payload->>'boundary_vintage'); v_url text := btrim(p_payload->>'source_url'); v_ev uuid; v_n int; v_rows int;
begin
  if coalesce(v_vintage, '') = '' then raise exception 'boundary vintage is required'; end if;
  if v_url !~ '^https://(data\.gov\.au|www\.abs\.gov\.au)/' then raise exception 'shares must come from the ABS allocation files (approval A-4): %', v_url; end if;
  v_rows := jsonb_array_length(coalesce(p_payload->'rows', '[]'::jsonb));
  if v_rows = 0 then raise exception 'no share rows'; end if;
  v_ev := security.destination_source_evidence_v1(v_url, p_payload->>'sha256', 'application/zip', null,
            jsonb_build_object('dataset', 'ASGS Edition 3 (2021) allocation files', 'licence', 'CC BY 4.0', 'approval', 'A-4 (Platform Admin 17 Nov 2026 07:35)',
                               'bytes', p_payload->'bytes', 'files', p_payload->'files', 'method', 'Mesh Block area summed per Postal Area and SUA'));
  with src as (
    select btrim(r->>'postcode') postcode, btrim(r->>'sua_code') sua_code, btrim(r->>'sua_name') sua_name,
           (r->>'overlap_sqkm')::numeric overlap, (r->>'postcode_sqkm')::numeric total, (r->>'mesh_blocks')::int mbs
      from jsonb_array_elements(p_payload->'rows') r),
  up as (
    insert into destination.abs_postcode_sua_shares as t(boundary_vintage, postcode, sua_code, sua_name, overlap_sqkm, postcode_sqkm, share, mesh_blocks, evidence_id)
    select v_vintage, postcode, sua_code, sua_name, overlap, total, round(least(1, overlap / total), 5), mbs, v_ev
      from src where postcode ~ '^[0-9]{4}$' and sua_code ~ '^[0-9]{4}$' and total > 0 and overlap >= 0 and mbs > 0
    on conflict (boundary_vintage, postcode, sua_code) do update
      set sua_name = excluded.sua_name, overlap_sqkm = excluded.overlap_sqkm, postcode_sqkm = excluded.postcode_sqkm, share = excluded.share,
          mesh_blocks = excluded.mesh_blocks, evidence_id = excluded.evidence_id, loaded_at = now()
    returning 1)
  select count(*) into v_n from up;
  return jsonb_build_object('boundary_vintage', v_vintage, 'rows_sent', v_rows, 'rows_written', v_n, 'evidence_id', v_ev,
    'postcodes', (select count(distinct postcode) from destination.abs_postcode_sua_shares where boundary_vintage = v_vintage));
end $function$;
comment on function security.destination_abs_shares_load_v1(jsonb) is 'RM1B: loads Postal Area to SUA area shares for one ASGS boundary vintage (workflow destination-abs-shares-load).';

-- 6. postcode rows from the shares, flagged by security.destination_postcode_flags_v1
create or replace function security.destination_abs_postcodes_rebuild_v1(p_vintage text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_min numeric := security.pipeline_num_v1('destination.postcode_candidate_min_share', 0.01); v_n int;
begin
  with cand as (
    select l.id locality_id, s.postcode, s.share, f.is_primary_match, f.needs_layer4_review
      from destination.abs_postcode_sua_shares s
      join destination.localities l on l.country_code = 'AU' and l.geography_type = 'SUA' and l.boundary_vintage = s.boundary_vintage and l.geography_code = s.sua_code
      cross join lateral security.destination_postcode_flags_v1(s.share) f
     where s.boundary_vintage = p_vintage and s.share >= v_min
       -- a postcode with a Layer 4 decision stays as decided
       and not exists (select 1 from destination.locality_postcodes d where d.country_code = 'AU' and d.postcode = s.postcode
                          and d.boundary_vintage = p_vintage and d.resolved_at is not null)),
  up as (
    insert into destination.locality_postcodes as t(locality_id, country_code, postcode, containment_share, is_primary_match, needs_layer4_review, boundary_vintage)
    select locality_id, 'AU', postcode, share, is_primary_match, needs_layer4_review, p_vintage from cand
    on conflict (locality_id, postcode, boundary_vintage) do update
      set containment_share = excluded.containment_share, is_primary_match = excluded.is_primary_match, needs_layer4_review = excluded.needs_layer4_review
      where t.resolved_at is null
        and (t.containment_share, t.is_primary_match, t.needs_layer4_review) is distinct from (excluded.containment_share, excluded.is_primary_match, excluded.needs_layer4_review)
    returning 1)
  select count(*) into v_n from up;
  return (
    with pc as (
      select p.postcode, bool_or(p.is_primary_match) prim, bool_or(p.needs_layer4_review) rev
        from destination.locality_postcodes p where p.country_code = 'AU' and p.boundary_vintage = p_vintage group by p.postcode),
    camp as (
      select distinct btrim(k.postcode) postcode
        from catalogue.campuses k join catalogue.providers pr on pr.id = k.provider_id
        join ref.countries c on c.id = coalesce(k.country_id, pr.country_id)
       where c.iso_alpha2 = 'AU' and nullif(btrim(k.postcode), '') is not null and coalesce(k.status, 'active') <> 'inactive')
    select jsonb_build_object('rows_written', v_n,
      'postcodes_primary', (select count(*) from pc where prim), 'postcodes_review', (select count(*) from pc where not prim and rev),
      'campus_postcodes', (select count(*) from camp),
      'campus_postcodes_primary', (select count(*) from camp join pc using (postcode) where pc.prim),
      'campus_postcodes_review', (select count(*) from camp join pc using (postcode) where not pc.prim and pc.rev),
      'campus_postcodes_outside_any_sua', (select count(*) from camp where not exists (select 1 from pc where pc.postcode = camp.postcode))));
end $function$;
comment on function security.destination_abs_postcodes_rebuild_v1(text) is 'RM1B: writes destination.locality_postcodes for AU from the SUA area shares, flags from security.destination_postcode_flags_v1; leaves Layer 4 decisions alone.';

-- 7. finishing a Run now task started for a destination job
create or replace function security.destination_run_finish_v1(p_run uuid, p_result jsonb, p_error text)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if p_run is null then return; end if;
  update pipeline.admin_jobs
     set state = case when p_error is null then 'done' else 'failed' end,
         result = coalesce(p_result, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object('error', p_error)),
         error = p_error, updated_at = clock_timestamp(), finished_at = clock_timestamp(),
         outcome = case when p_error is not null then 'failed_retryable'
                        when coalesce((p_result->>'changed')::int, 0) > 0 then 'succeeded_with_result' else 'succeeded_no_movement' end
   where id = p_run and kind = 'job_run_now' and state = 'running';
end $function$;
comment on function security.destination_run_finish_v1(uuid, jsonb, text) is 'RM1B: records the result of a destination load on the Run now task that started it.';

-- 8. population load (edge function layer1-destination-geo-loader)
create or replace function security.destination_abs_population_load_v1(p_payload jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_vintage text := btrim(p_payload->>'boundary_vintage'); v_edition text := btrim(p_payload->>'dataset_edition');
  v_period text := btrim(p_payload->>'reference_period'); v_url text := btrim(p_payload->>'source_url');
  v_attr text := btrim(p_payload->>'attribution_text'); v_run uuid := nullif(p_payload->>'run_id', '')::uuid;
  v_ev uuid; v_loc int; v_loc_new int; v_met int; v_held int; v_pc jsonb; v_res jsonb;
begin
  if coalesce(v_vintage, '') = '' or coalesce(v_edition, '') = '' or coalesce(v_period, '') = '' or coalesce(v_attr, '') = '' then
    raise exception 'boundary vintage, dataset edition, reference period and attribution are required';
  end if;
  if v_url !~ '^https://www\.abs\.gov\.au/' then raise exception 'population must come from the ABS (approval A-1): %', v_url; end if;
  if jsonb_array_length(coalesce(p_payload->'rows', '[]'::jsonb)) = 0 then raise exception 'no SUA rows in the file'; end if;
  if not exists (select 1 from destination.abs_postcode_sua_shares where boundary_vintage = v_vintage) then
    raise exception 'postcode shares for % are not loaded yet (workflow destination-abs-shares-load)', v_vintage;
  end if;
  v_ev := security.destination_source_evidence_v1(v_url, p_payload->>'sha256', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            p_payload->>'storage_path', jsonb_build_object('dataset', v_edition, 'licence', 'CC BY 4.0', 'approval', 'A-1 (Platform Admin 17 Nov 2026 07:29)',
                                                           'sheet', p_payload->'sheet', 'bytes', p_payload->'bytes', 'reference_period', v_period));
  insert into destination.editions(country_id, domain, edition_label, effective_from, status, source_url, source_owner, attribution_text, terms_status, last_checked_at)
  select c.id, 'city_profiles', v_edition, v_period::date, 'draft', v_url, 'Australian Bureau of Statistics', v_attr, 'approved', now()
    from ref.countries c
   where c.iso_alpha2 = 'AU' and not exists (select 1 from destination.editions e where e.country_id = c.id and e.domain = 'city_profiles' and e.edition_label = v_edition);
  update destination.editions e set last_checked_at = now()
    from ref.countries c where c.id = e.country_id and c.iso_alpha2 = 'AU' and e.domain = 'city_profiles' and e.edition_label = v_edition;

  drop table if exists _abs_src;
  create temp table _abs_src on commit drop as
    select btrim(r->>'code') code, btrim(r->>'name') nm, (r->>'erp')::numeric erp
      from jsonb_array_elements(p_payload->'rows') r
     where btrim(r->>'code') ~ '^[0-9]{4}$' and coalesce(btrim(r->>'name'), '') <> ''
       and btrim(r->>'name') !~* '^(not in any|migratory|no usual address)';

  with up as (
    insert into destination.localities as l(country_code, name, geography_type, geography_code, boundary_vintage, dataset_edition, attribution_text, evidence_id)
    select 'AU', s.nm, 'SUA', s.code, v_vintage, v_edition, v_attr, v_ev from _abs_src s
    on conflict (country_code, geography_type, boundary_vintage, geography_code) do update
      set name = excluded.name, dataset_edition = excluded.dataset_edition, attribution_text = excluded.attribution_text, evidence_id = excluded.evidence_id, updated_at = now()
      where (l.name, l.dataset_edition, l.attribution_text, l.evidence_id) is distinct from (excluded.name, excluded.dataset_edition, excluded.attribution_text, excluded.evidence_id)
    returning (xmax = 0) inserted)
  select count(*) filter (where inserted), count(*) into v_loc_new, v_loc from up;

  -- a figure already approved or published keeps its value; a different value in the same edition is counted, not written
  select count(*) into v_held
    from _abs_src s
    join destination.localities l on l.country_code = 'AU' and l.geography_type = 'SUA' and l.boundary_vintage = v_vintage and l.geography_code = s.code
    join destination.locality_metrics m on m.locality_id = l.id and m.metric_key = 'erp_persons' and m.reference_period = v_period and m.dataset_edition = v_edition
   where m.status not in ('draft', 'in_review') and m.numeric_value is distinct from s.erp;

  with up as (
    insert into destination.locality_metrics as t(locality_id, metric_category, metric_key, numeric_value, unit, reference_period, dataset_edition, source_url, attribution_text, evidence_id)
    select l.id, 'population', 'erp_persons', s.erp, 'persons', v_period, v_edition, v_url, v_attr, v_ev
      from _abs_src s
      join destination.localities l on l.country_code = 'AU' and l.geography_type = 'SUA' and l.boundary_vintage = v_vintage and l.geography_code = s.code
     where s.erp is not null and s.erp >= 0
    on conflict (locality_id, metric_key, reference_period, dataset_edition) do update
      set numeric_value = excluded.numeric_value, source_url = excluded.source_url, attribution_text = excluded.attribution_text, evidence_id = excluded.evidence_id, updated_at = now()
      where t.status in ('draft', 'in_review')
        and (t.numeric_value, t.source_url, t.attribution_text, t.evidence_id) is distinct from (excluded.numeric_value, excluded.source_url, excluded.attribution_text, excluded.evidence_id)
    returning 1)
  select count(*) into v_met from up;

  v_pc := security.destination_abs_postcodes_rebuild_v1(v_vintage);
  v_res := jsonb_build_object('rows_in_file', jsonb_array_length(p_payload->'rows'), 'sua_rows', (select count(*) from _abs_src),
    'localities_written', v_loc, 'localities_new', v_loc_new, 'figures_written', v_met, 'figures_held_approved', v_held,
    'changed', v_loc + v_met + coalesce((v_pc->>'rows_written')::int, 0), 'evidence_id', v_ev, 'postcodes', v_pc,
    'dataset_edition', v_edition, 'boundary_vintage', v_vintage, 'reference_period', v_period);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('destination', 'abs_load', 'destination-abs-load', v_res || jsonb_strip_nulls(jsonb_build_object('run_id', v_run, 'trigger', p_payload->>'trigger')), null);
  perform security.destination_run_finish_v1(v_run, v_res, null);
  return v_res;
end $function$;
comment on function security.destination_abs_population_load_v1(jsonb) is 'RM1B: SUA localities and estimated resident population (draft) from ABS Regional population, with evidence and edition, then the AU postcode rows.';

create or replace function public.svc_destination_abs_load_v1(p_payload jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_run uuid := nullif(p_payload->>'run_id', '')::uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_payload ? 'error' then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('destination', 'abs_load_failed', 'destination-abs-load', jsonb_build_object('error', left(p_payload->>'error', 500), 'run_id', v_run, 'trigger', p_payload->>'trigger'), null);
    perform security.destination_run_finish_v1(v_run, null, left(p_payload->>'error', 500));
    return jsonb_build_object('recorded', true);
  end if;
  return security.destination_abs_population_load_v1(p_payload);
end $function$;
comment on function public.svc_destination_abs_load_v1(jsonb) is 'RM1B: service entry of edge function layer1-destination-geo-loader (a load, or the error of a failed one).';

-- 9. fire guard and Run now runner
create or replace function security.destination_abs_load_due_v1()
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  -- fixed: fire guard. The job is scheduled at 18:30 and 19:30 UTC; exactly one of them is 05:30 in Sydney (AEDT or AEST), and only the 1st of the month there runs (mandate 17 Nov 2026 13:12)
  select extract(day from (now() at time zone 'Australia/Sydney')) = 1 and extract(hour from (now() at time zone 'Australia/Sydney')) = 5 -- fixed: fire guard
$function$;
comment on function security.destination_abs_load_due_v1() is 'RM1B: true only on the 1st of the month at 05:xx Sydney time (fire guard of job destination-abs-load).';

create or replace function security.destination_job_run_now_v1(p_job text, p_reason text, p_args jsonb, p_requester uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_id uuid := gen_random_uuid(); v_key text := nullif(btrim(coalesce(p_args->>'idempotency_key', '')), '');
        v_cat pipeline.automation_catalogue%rowtype; v_rank int; v_why text; v_fn text; v_body jsonb; v_req bigint; v_title text;
begin
  select * into v_cat from pipeline.automation_catalogue where jobname = p_job;
  select coalesce(max(r.rank), 0) into v_rank from security.user_roles ur join security.roles r on r.code = ur.role_code
   where ur.user_id = p_requester and (ur.expires_at is null or ur.expires_at > now()) and r.status = 'active';
  -- the bounded runner of each destination job: the edge function its schedule calls, with the body the schedule sends
  select x.fn, x.body into v_fn, v_body from (values
    ('destination-abs-load', 'layer1-destination-geo-loader', jsonb_build_object('mode', 'load'))
  ) x(job, fn, body) where x.job = p_job;
  v_why := case
    when not (p_job = any (array(select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'run_now.jobs'), '[]'::jsonb))))) then 'job is not on the Run now list'
    when v_cat.jobname is null then 'job is not catalogued'
    when v_rank < greatest(coalesce(v_cat.control_rank, 6), 1) then 'requester rank ' || v_rank || ' is below the job''s rank ' || coalesce(v_cat.control_rank, 6)
    when not exists (select 1 from cron.job j where j.jobname = p_job) then 'job is not scheduled'
    when exists (select 1 from cron.job j where j.jobname = p_job and not j.active) then 'job is paused'
    when v_fn is null then 'no bounded runner for this job'
    when exists (select 1 from pipeline.admin_jobs j where j.kind = 'job_run_now' and j.args->>'job' = p_job and j.state = 'running'
                  and j.started_at > now() - interval '15 minutes') then 'a run of this job is in progress'  -- fixed: lease on a started run (the edge call times out at 2 minutes)
  end;
  v_title := 'Run now: ' || coalesce(v_cat.label, p_job);
  if v_why is not null then
    insert into pipeline.admin_jobs(id, kind, lane, state, title, args, result, requested_by, reason, created_at, started_at, updated_at, finished_at, scope, outcome)
    values (v_id, 'job_run_now', 'run_now', 'cancelled', v_title || ' (refused)', jsonb_strip_nulls(jsonb_build_object('job', p_job, 'idempotency_key', v_key)),
            jsonb_build_object('refused', v_why), p_requester, btrim(p_reason), now(), now(), now(), now(), 'job:' || p_job, 'blocked_policy');
    return jsonb_build_object('run_id', v_id, 'state', 'refused', 'refused', v_why);
  end if;
  v_req := pipeline.svc_pilot_submit_nonce(v_fn, v_body || jsonb_build_object('trigger', 'run_now', 'run_id', v_id));
  insert into pipeline.admin_jobs(id, kind, lane, state, title, args, result, requested_by, reason, created_at, started_at, updated_at, scope)
  values (v_id, 'job_run_now', 'run_now', 'running', v_title, jsonb_strip_nulls(jsonb_build_object('job', p_job, 'idempotency_key', v_key, 'edge_function', v_fn)),
          jsonb_build_object('edge_request_id', v_req), p_requester, btrim(p_reason), now(), now(), now(), 'job:' || p_job);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('run_now', 'started', p_job, jsonb_build_object('task', v_id, 'edge_function', v_fn, 'edge_request_id', v_req), p_requester);
  return jsonb_build_object('run_id', v_id, 'state', 'running', 'edge_function', v_fn, 'edge_request_id', v_req);
end $function$;
comment on function security.destination_job_run_now_v1(text, text, jsonb, uuid) is 'RM1B: Run now for destination- jobs; checks the Run now list, catalogue, rank and schedule, then starts the job''s edge function once.';

do $e$
declare
  v_sig constant regprocedure := 'security.job_run_now_v1(text,text,jsonb,uuid)'::regprocedure;
  v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.job_run_now_v1(text,text,jsonb,uuid)'::regprocedure);
  v_def text; v_c int;
  v_old constant text := $o$  v_why := case
    when not (p_job = any$o$;
  v_new constant text := $n$  -- RM1B (17 Nov 2026): destination jobs have their own bounded runner, the edge function their schedule calls
  if p_job like 'destination-%' then return security.destination_job_run_now_v1(p_job, p_reason, p_args, p_requester); end if;
  v_why := case
    when not (p_job = any$n$;
begin
  if position('security.destination_job_run_now_v1' in v_src) > 0 then raise notice 'security.job_run_now_v1: already applied'; return; end if;
  if md5(v_src) <> 'e11749672a47b640e0da93d0508f8a62' then raise exception 'live security.job_run_now_v1 differs from the definition this change edits (body md5 %)', md5(v_src); end if;
  v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception 'security.job_run_now_v1: the edit must apply exactly once (found %)', v_c; end if;
  execute replace(v_def, v_old, v_new);
  if md5((select p.prosrc from pg_proc p where p.oid = v_sig)) <> md5(replace(v_src, v_old, v_new)) then
    raise exception 'security.job_run_now_v1 after the edit is not the expected body';
  end if;
end $e$;

update pipeline.platform_toolset_settings
   set value = value || '["destination-abs-load"]'::jsonb, updated_at = now(),
       reason = 'RM1B: destination-abs-load added (S2-Build mandate and S1-RM-Design handoff, Platform Admin 17 Nov 2026 13:12 and 14:11); earlier entries kept'
 where toolset_key = 'pipeline' and key = 'run_now.jobs' and not (value ? 'destination-abs-load');

-- grants
revoke all on function security.destination_source_evidence_v1(text, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function security.destination_abs_shares_load_v1(jsonb) from public, anon, authenticated;
revoke all on function security.destination_abs_postcodes_rebuild_v1(text) from public, anon, authenticated;
revoke all on function security.destination_run_finish_v1(uuid, jsonb, text) from public, anon, authenticated;
revoke all on function security.destination_abs_population_load_v1(jsonb) from public, anon, authenticated;
revoke all on function security.destination_abs_load_due_v1() from public, anon, authenticated;
revoke all on function security.destination_job_run_now_v1(text, text, jsonb, uuid) from public, anon, authenticated;
revoke all on function public.svc_destination_abs_load_v1(jsonb) from public, anon, authenticated;
grant execute on function public.svc_destination_abs_load_v1(jsonb) to service_role;

-- 10. the edge function, the job and the register
insert into pipeline.pilot_nonce_functions(function_name, note)
select 'layer1-destination-geo-loader', 'RM1B ABS population and postcode loader (job destination-abs-load and Run now)'
where not exists (select 1 from pipeline.pilot_nonce_functions where function_name = 'layer1-destination-geo-loader');

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('destination-abs-load', 'Layer 1 register', 300, 'Destination: ABS population and postcodes',
  'Loads Australian cities (Significant Urban Areas) and their population at 30 June 2025 from the ABS, with attribution, and maps postcodes to them; rows load as draft for approval. Runs on the 1st of the month at 05:30 Sydney time.',
  6, false)
on conflict (jobname) do nothing;

select cron.schedule('destination-abs-load', '30 18,19 * * *', 'select pipeline.svc_pilot_submit_nonce(''layer1-destination-geo-loader'', jsonb_build_object(''mode'', ''load'', ''trigger'', ''schedule'')) where security.destination_abs_load_due_v1()');

insert into pipeline.component_register(kind, name, layer, area, purpose, status, introduced_in)
select v.kind, v.name, v.layer, 'Destination data', v.purpose, 'active', '20261117180000'
  from (values
    ('job', 'destination-abs-load', 'L1 register', 'ABS population and postcodes for Australian destination localities, monthly (RM1B)'),
    ('edge_function', 'layer1-destination-geo-loader', 'L1 register', 'Reads ABS Regional population 2024-25 Table 2 and loads SUA localities, figures and postcodes (RM1B)'),
    ('table', 'destination.abs_postcode_sua_shares', 'Reference', 'Postal Area to SUA area shares from the ASGS Edition 3 allocation files (RM1B, A-4)'),
    ('function', 'security.destination_abs_population_load_v1', 'Layer 1', 'Loads SUA localities and population figures (RM1B)'),
    ('function', 'security.destination_abs_shares_load_v1', 'Layer 1', 'Loads Postal Area to SUA shares (RM1B)'),
    ('function', 'security.destination_abs_postcodes_rebuild_v1', 'Layer 1', 'Writes AU locality postcodes with flags (RM1B)'),
    ('function', 'security.destination_job_run_now_v1', 'Layer 1', 'Run now for destination- jobs (RM1B)'),
    ('function', 'public.svc_destination_abs_load_v1', 'Layer 1', 'Service entry of layer1-destination-geo-loader (RM1B)')
  ) v(kind, name, layer, purpose)
 where not exists (select 1 from pipeline.component_register r where r.kind = v.kind and r.name = v.name);

-- 11. post-checks
do $$
begin
  if not exists (select 1 from cron.job where jobname = 'destination-abs-load' and active) then raise exception 'post-check: job destination-abs-load'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'destination-abs-load') then raise exception 'post-check: catalogue'; end if;
  if not exists (select 1 from pipeline.pilot_nonce_functions where function_name = 'layer1-destination-geo-loader') then raise exception 'post-check: nonce allowlist'; end if;
  if not (security.toolset_setting('pipeline', 'run_now.jobs') ? 'destination-abs-load') then raise exception 'post-check: run_now.jobs'; end if;
  if not (security.toolset_setting('pipeline', 'run_now.jobs') ? 'intake-dates-apply') then raise exception 'post-check: run_now.jobs lost an entry'; end if;
  if position('security.destination_job_run_now_v1' in (select prosrc from pg_proc where oid = 'security.job_run_now_v1(text,text,jsonb,uuid)'::regprocedure)) = 0 then
    raise exception 'post-check: job_run_now_v1 hand-off';
  end if;
  if (select command from cron.job where jobname = 'destination-abs-load') ~ '\(\s*[0-9]+\s*[,)]' then raise exception 'post-check: a number in the job command'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'destination' and table_name = 'locality_metrics' and column_name = 'evidence_id') then
    raise exception 'post-check: evidence_id';
  end if;
end $$;
