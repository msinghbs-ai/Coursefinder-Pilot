-- CF-247 S1-UX (Platform Admin 20 Nov 2026 10:31, chat S1-UX, s823; rescoped 11:24 with S1-RM-Design #1411): less database read and write pressure from the admin screens and idle workers.
--   s823a Ops pulse snapshot. Every open of Platform Health and every page's top-bar health dot runs security.admin_platform_health_cf221(), which counts
--        pipeline.jobs, and 24 hours of pipeline.evidence_artifacts, pipeline.layer2_provider_attempts and pipeline.layer3_interpretations, plus every
--        scholarship, at read time. Those counts now come from one stored row, pipeline.ops_pulse_snapshot, rebuilt every 5 minutes by the new job
--        ops-pulse-refresh. The same row carries the Platform Health pulse strip and the 4-stage pipeline (Official Registers, Page Capture,
--        AI Extraction & Auto-Clean, Live Catalogue), built from the health checks the scheduled check job already stores, the stored completeness
--        scores and the Layer 4 waiting counts. If the row is older than the setting ops.pulse_max_age_minutes (15), the read falls back to the live
--        counts exactly as before, so a stopped job can never show stale figures as current.
--   s823b Log state transitions only (idle-poll collapse). public.svc_worker_report_v1 writes one pipeline.mode_outcome_ledger row and two updates for every worker call, including
--        calls that found nothing to do. A run of idle calls for the same mode and worker now updates one row (run_at moves to the latest call;
--        detail.idle_polls counts the calls, detail.first_idle_at keeps the first) for up to telemetry.idle_collapse_minutes (15; 0 switches it off).
--        Any call that does work, fails or errors ends the run and is recorded as before. Lane liveness (latest run_at) is unchanged.
-- Objects (no new public function, table or view): tables pipeline.ops_pulse_snapshot, pipeline.ops_pulse_stage_map, pipeline.worker_idle_tally;
-- functions security.ops_pulse_refresh_v1(), security.ops_pulse_fresh_v1(), security.ops_pulse_cf221_v1(int), security.worker_idle_collapse_v1(text,int,int,jsonb,text),
-- security.worker_idle_note_v1(text,text,bigint); two in-place edits: security.admin_platform_health_cf221() (fragment-guarded, signature unchanged) and
-- public.svc_worker_report_v1(text,integer,integer,jsonb,text) (md5-guarded, signature unchanged); one job ops-pulse-refresh (every 5 minutes, in Automations).
-- G1: one job, registered in pipeline.automation_catalogue and the component register. G2: both limits are settings. G3: no consumer API object;
-- security.consumer_api_check_v1() is read before and after (75 functions, 48 relations, no drift). Spend: none (no AI, no Firecrawl).
-- Replaces: the read-time counts of security.admin_platform_health_cf221() (kept as the fallback); one ledger row per idle call.
-- Retires: nothing. Nothing dropped, deleted or renamed.
-- Rollback: unschedule ops-pulse-refresh (the read then falls back to live counts by itself), set telemetry.idle_collapse_minutes to 0 (every call
-- writes its own row again); the two edits are each one inserted line and can be removed with the same helper.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;

-- settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
  ('pipeline', 'ops.pulse_max_age_minutes', 'Ops pulse: oldest snapshot shown as current',
   'Platform Health and the top-bar health dot read the stored ops pulse (rebuilt every 5 minutes). If it is older than this, they count live again, as before.',
   'number', to_jsonb(15), 6, 120, 'minutes', 980, 'Platform health', 'security.admin_platform_health_cf221 (fast path), security.ops_pulse_fresh_v1', 'CF-247 s823 (Platform Admin 20 Nov 2026 10:31 and 11:24)'),
  ('pipeline', 'telemetry.idle_collapse_minutes', 'Worker calls: idle calls folded into one row for',
   'Calls that found nothing to do, one after another for the same mode and worker, update one ledger row for up to this many minutes. 0 records every call as its own row.',
   'number', to_jsonb(15), 0, 120, 'minutes', 981, 'Platform health', 'public.svc_worker_report_v1 (security.worker_idle_collapse_v1)', 'CF-247 s823 (Platform Admin 20 Nov 2026 10:31 and 11:24)')
on conflict (toolset_key, key) do nothing;

-- the stored pulse: one row
create table if not exists pipeline.ops_pulse_snapshot (
  id smallint primary key default 1 check (id = 1),
  payload jsonb not null,
  refreshed_at timestamptz not null default now(),
  run_ms integer not null default 0
);
alter table pipeline.ops_pulse_snapshot enable row level security;
revoke all on table pipeline.ops_pulse_snapshot from public, anon, authenticated;
comment on table pipeline.ops_pulse_snapshot is 'CF-247 s823: the stored ops pulse (Platform Health counts, pulse strip, 4-stage pipeline), one row, rebuilt every 5 minutes by job ops-pulse-refresh. Read only through security.admin_platform_health_cf221().';

-- which health checks belong to which pipeline stage (editable data, not code); a check no pattern matches is shown under System internals
create table if not exists pipeline.ops_pulse_stage_map (
  pattern text primary key,
  stage smallint not null check (stage between 1 and 4),
  note text
);
alter table pipeline.ops_pulse_stage_map enable row level security;
revoke all on table pipeline.ops_pulse_stage_map from public, anon, authenticated;
comment on table pipeline.ops_pulse_stage_map is 'CF-247 s823: a regular expression on a health check key or area, and the pipeline stage it reports under (1 Official Registers, 2 Page Capture, 3 AI Extraction & Auto-Clean, 4 Live Catalogue).';
insert into pipeline.ops_pulse_stage_map(pattern, stage, note) values
  ('^(layer1|register|reference|statistics|ranking)', 1, 'Layer 1 registers and reference sources'),
  ('^(coverage_queues|edge_calls|firecrawl|queue_watch|field_stalled|layer2|fetch)', 2, 'Page capture and the queues that feed it'),
  ('^(admission|aer|scholarship_queues|budgets|models|openrouter|descriptions?)', 3, 'AI extraction, admission and budgets'),
  ('^(search_refresh|layer_queues|scholarship_review|publication|consumer_api|api)', 4, 'Search, Layer 4 backlog and what the APIs serve')
on conflict (pattern) do nothing;

-- a run of idle calls per mode and worker: the ledger row they update
create table if not exists pipeline.worker_idle_tally (
  mode text not null,
  worker text not null,
  ledger_id bigint not null,
  polls integer not null default 1,
  last_at timestamptz not null default now(),
  primary key (mode, worker)
);
alter table pipeline.worker_idle_tally enable row level security;
revoke all on table pipeline.worker_idle_tally from public, anon, authenticated;
comment on table pipeline.worker_idle_tally is 'CF-247 s823: the current run of idle worker calls for each mode and worker, and the pipeline.mode_outcome_ledger row it updates. A call that does work, fails or errors deletes its row.';

create or replace function security.ops_pulse_refresh_v1()
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare
  t0 timestamptz := clock_timestamp();
  v_failed int; v_running int; v_completed int; v_ev24 bigint; v_attempts bigint; v_calls bigint; v_cost numeric; v_sch bigint; v_staged int; v_qualified int;
  v_cf221 jsonb; v_l4 jsonb; v_l4_total int; v_comp jsonb; v_checks jsonb; v_stages jsonb; v_budget jsonb; v_crit int; v_warn int; v_status text;
  v_errors jsonb := '{}'::jsonb; v_payload jsonb; v_ms int;
begin
  -- 1 the same counts security.admin_platform_health_cf221() makes at read time (each part on its own: a missing table never stops the rest)
  begin
    select count(*) filter (where status = 'failed' and created_at >= now() - interval '24 hours'), count(*) filter (where status in ('queued', 'running')),
           count(*) filter (where status in ('completed', 'succeeded') and created_at >= now() - interval '24 hours')
      into v_failed, v_running, v_completed from pipeline.jobs;
  exception when others then v_errors := v_errors || jsonb_build_object('jobs', left(sqlerrm, 200)); end;
  begin select count(*) into v_ev24 from pipeline.evidence_artifacts where created_at >= now() - interval '24 hours';
  exception when others then v_errors := v_errors || jsonb_build_object('evidence', left(sqlerrm, 200)); end;
  begin select count(*) into v_attempts from pipeline.layer2_provider_attempts where created_at >= now() - interval '24 hours';
  exception when others then v_errors := v_errors || jsonb_build_object('layer2_attempts', left(sqlerrm, 200)); end;
  begin select coalesce(sum(external_call_count), 0), coalesce(sum(estimated_cost_usd), 0) into v_calls, v_cost from pipeline.layer3_interpretations where created_at >= now() - interval '24 hours';
  exception when others then v_errors := v_errors || jsonb_build_object('layer3', left(sqlerrm, 200)); end;
  begin select count(*) into v_sch from scholarship.scholarships;
  exception when others then v_errors := v_errors || jsonb_build_object('scholarships', left(sqlerrm, 200)); end;
  begin
    select count(*), count(*) filter (where coalesce((quality_benchmark->>'pass')::boolean, false)) into v_staged, v_qualified
      from pipeline.layer3_model_profiles where code like 'openrouter-scholarship-%';
  exception when others then v_errors := v_errors || jsonb_build_object('profiles', left(sqlerrm, 200)); end;
  v_cf221 := jsonb_build_object(
    'overall_status', case when coalesce(v_failed, 0) > 0 then 'attention' when coalesce(v_running, 0) > 0 then 'active' else 'healthy' end,
    'jobs', jsonb_build_object('running', v_running, 'failed_24h', v_failed, 'completed_24h', v_completed),
    'data', jsonb_build_object('evidence_fetched_24h', v_ev24, 'scholarships', v_sch),
    'edge_runtime', jsonb_build_object('status', case when coalesce(v_failed, 0) > 0 then 'attention' else 'healthy' end, 'active_workloads', v_running, 'completed_24h', v_completed),
    'api_activity', jsonb_build_object('layer2_provider_requests_24h', v_attempts, 'layer3_external_calls_24h', v_calls, 'layer3_cost_24h_usd', v_cost),
    'scholarship_ai', jsonb_build_object('active_runs', 0, 'profiles_staged', v_staged, 'profiles_qualified', v_qualified));

  -- 2 Layer 4: what waits for a person, by kind (counts and keys only, no detail)
  begin
    select coalesce(jsonb_object_agg(k, n), '{}'::jsonb), coalesce(sum(n), 0)::int into v_l4, v_l4_total
      from (select r.kind k, count(*)::int n from security.layer4_inbox_items_v2(null, null, null, false) r group by r.kind) x;
  exception when others then v_l4 := null; v_l4_total := null; v_errors := v_errors || jsonb_build_object('layer4', left(sqlerrm, 200)); end;

  -- 3 stored completeness (pipeline.course_completeness, rebuilt by the coverage build), by country
  begin
    select coalesce(jsonb_object_agg(cc, jsonb_build_object('completeness', pct, 'courses', n)), '{}'::jsonb) into v_comp
      from (select k.iso_alpha2 cc, round(avg(c.completeness), 1) pct, count(*)::int n
              from pipeline.course_completeness c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id
             where k.iso_alpha2 in ('AU', 'NZ', 'CA') group by k.iso_alpha2) x;
  exception when others then v_comp := null; v_errors := v_errors || jsonb_build_object('completeness', left(sqlerrm, 200)); end;

  -- 4 the four stages, from the checks the scheduled health check already stores (no new scan of the work tables)
  begin
    with c as (
      select h.key, h.area, h.label, h.status, h.detail, h.checked_at,
             coalesce((select m.stage from pipeline.ops_pulse_stage_map m where h.key ~* m.pattern or coalesce(h.area, '') ~* m.pattern order by m.stage limit 1), 0) stage,
             (select coalesce(sum((e.value #>> '{}')::numeric), 0) from jsonb_each(case when jsonb_typeof(h.detail) = 'object' then h.detail else '{}'::jsonb end) e
               where e.key in ('waiting', 'queued', 'pending', 'backlog') and jsonb_typeof(e.value) = 'number') queued
        from pipeline.platform_health_checks h)
    select jsonb_agg(jsonb_build_object(
             'stage', s.n, 'name', s.name,
             'status', coalesce((select case min(case c.status when 'critical' then 1 when 'warning' then 2 when 'ok' then 3 else 4 end) when 1 then 'critical' when 2 then 'warning' when 3 then 'ok' else 'unknown' end
                                  from c where c.stage = s.n), 'unknown'),
             'checks', (select count(*) from c where c.stage = s.n),
             'attention', (select coalesce(jsonb_agg(jsonb_build_object('key', c.key, 'label', c.label, 'status', c.status) order by c.status, c.key), '[]'::jsonb)
                             from c where c.stage = s.n and c.status in ('critical', 'warning')),
             'queued', case when s.n = 4 then v_l4_total else (select sum(c.queued) from c where c.stage = s.n) end)
           order by s.n),
           (select jsonb_build_object('total', count(*), 'attention', count(*) filter (where c.status in ('critical', 'warning')),
                                      'healthy', count(*) filter (where c.status = 'ok'), 'skipped', count(*) filter (where c.status = 'skipped'),
                                      'unmapped', count(*) filter (where c.stage = 0)) from c)
      into v_stages, v_checks
      from (values (1, 'Official Registers'), (2, 'Page Capture'), (3, 'AI Extraction & Auto-Clean'), (4, 'Live Catalogue')) s(n, name);
  exception when others then v_stages := null; v_checks := null; v_errors := v_errors || jsonb_build_object('stages', left(sqlerrm, 200)); end;

  -- 5 today's AI spend against the daily limit, as the budgets check last measured it
  begin
    select jsonb_build_object('spend_usd', h.detail->'openrouter_spend_24h_usd', 'cap_usd', h.detail->'openrouter_daily_ceiling_usd',
                              'crawl_credits', h.detail->'scholarship_firecrawl_used', 'checked_at', h.checked_at)
      into v_budget from pipeline.platform_health_checks h where h.key = 'budgets';
  exception when others then v_budget := null; v_errors := v_errors || jsonb_build_object('budget', left(sqlerrm, 200)); end;

  -- 6 overall: the open issues, as the Platform Health page counts them
  begin
    select count(*) filter (where severity = 'critical'), count(*) filter (where severity = 'warning') into v_crit, v_warn
      from pipeline.platform_issues where resolved_at is null;
  exception when others then v_crit := null; v_warn := null; v_errors := v_errors || jsonb_build_object('issues', left(sqlerrm, 200)); end;
  v_status := case when v_crit is null then 'unknown' when v_crit > 0 then 'critical' when v_warn > 0 then 'warning' else 'ok' end;

  v_ms := round(extract(epoch from clock_timestamp() - t0) * 1000)::int;
  v_payload := jsonb_build_object('cf221', v_cf221,
    'pulse', jsonb_build_object('status', v_status, 'critical', v_crit, 'warning', v_warn, 'completeness', v_comp,
                                'layer4_waiting', v_l4_total, 'layer4_by_kind', v_l4, 'blockers', v_crit, 'budget', v_budget,
                                'stages', v_stages, 'checks', v_checks),
    'errors', v_errors, 'run_ms', v_ms);
  insert into pipeline.ops_pulse_snapshot(id, payload, refreshed_at, run_ms) values (1, v_payload, now(), v_ms)
  on conflict (id) do update set payload = excluded.payload, refreshed_at = excluded.refreshed_at, run_ms = excluded.run_ms;
  return jsonb_build_object('ok', true, 'run_ms', v_ms, 'errors', v_errors);
end $f$;
revoke all on function security.ops_pulse_refresh_v1() from public, anon, authenticated;
comment on function security.ops_pulse_refresh_v1() is 'CF-247 s823: rebuilds pipeline.ops_pulse_snapshot (job ops-pulse-refresh, every 5 minutes). Each part is counted on its own; a part that fails is null and named in payload.errors, never 0.';

create or replace function security.ops_pulse_fresh_v1()
returns boolean language sql stable security definer set search_path to '' as $f$
  select exists (select 1 from pipeline.ops_pulse_snapshot s
                  where s.id = 1 and s.payload ? 'cf221'
                    and s.refreshed_at >= now() - make_interval(mins => greatest(6, security.pipeline_num_v1('ops.pulse_max_age_minutes', 15)::int)))
$f$;
revoke all on function security.ops_pulse_fresh_v1() from public, anon, authenticated;

-- the stored row in the shape security.admin_platform_health_cf221() returns, gated by role exactly as it is, plus the pulse for Curator (rank 3) and above
create or replace function security.ops_pulse_cf221_v1(p_rank int)
returns jsonb language sql stable security definer set search_path to '' as $f$
  select jsonb_strip_nulls(jsonb_build_object(
    'overall_status', s.payload->'cf221'->'overall_status',
    'jobs', s.payload->'cf221'->'jobs',
    'data', s.payload->'cf221'->'data',
    'edge_runtime', s.payload->'cf221'->'edge_runtime',
    'api_activity', case when p_rank >= 4 then s.payload->'cf221'->'api_activity' end,
    'scholarship_ai', case when p_rank >= 3 then s.payload->'cf221'->'scholarship_ai' end,
    'security', case when p_rank >= 6 then jsonb_build_object('status', 'reviewed_with_existing_findings', 'note', 'Security Advisor remains the authority; no CF-221 finding is asserted by this runtime snapshot.') end,
    'observed_at', s.refreshed_at,
    'pulse', case when p_rank >= 3 then s.payload->'pulse' || jsonb_build_object('refreshed_at', s.refreshed_at, 'run_ms', s.run_ms) end,
    'pulse_source', 'snapshot'))
  from pipeline.ops_pulse_snapshot s where s.id = 1
$f$;
revoke all on function security.ops_pulse_cf221_v1(int) from public, anon, authenticated;
comment on function security.ops_pulse_cf221_v1(int) is 'CF-247 s823: the stored ops pulse in the security.admin_platform_health_cf221() shape and role gates; pulse (stages, completeness, Layer 4 waiting, budget) for rank 3 and above only.';

-- s823: idle calls
create or replace function security.worker_idle_collapse_v1(p_mode text, p_status int, p_ms int, p_body jsonb, p_worker text)
returns bigint language plpgsql security definer set search_path to '' as $f$
declare
  v_min int := security.pipeline_num_v1('telemetry.idle_collapse_minutes', 15)::int;
  v_mode text := left(coalesce(p_mode, ''), 60); v_worker text := left(coalesce(p_worker, ''), 80);
  v_idle boolean; v_t pipeline.worker_idle_tally%rowtype; v_id bigint;
begin
  if v_min <= 0 then return null; end if;
  v_idle := coalesce(p_status, 200) < 400 and coalesce(p_body->>'ok', 'true') <> 'false' and not coalesce(p_body ? 'error', false)
        and coalesce(security.worker_call_work_v1(p_body::text), 0) = 0
        and coalesce(security.jsonb_int_v1(p_body->'failed'), 0) = 0 and coalesce(security.jsonb_int_v1(p_body->'tally'->'failed'), 0) = 0
        and coalesce(security.jsonb_int_v1(p_body->'tally'->'fetch_failed'), 0) = 0 and coalesce(security.jsonb_int_v1(p_body->'tally'->'scrape_failed'), 0) = 0;
  if not v_idle then
    delete from pipeline.worker_idle_tally where mode = v_mode and worker = v_worker;
    return null;
  end if;
  select * into v_t from pipeline.worker_idle_tally where mode = v_mode and worker = v_worker for update;
  if not found or v_t.last_at < now() - make_interval(mins => v_min) then return null; end if;
  update pipeline.mode_outcome_ledger l
     set run_at = now(), ms = coalesce(p_ms, l.ms),
         detail = coalesce(l.detail, '{}'::jsonb) || jsonb_build_object('idle_polls', v_t.polls + 1, 'first_idle_at', coalesce(l.detail->>'first_idle_at', l.run_at::text))
   where l.id = v_t.ledger_id and l.outcome = 'idle' and l.mode = v_mode
  returning l.id into v_id;
  if v_id is null then
    delete from pipeline.worker_idle_tally where mode = v_mode and worker = v_worker;
    return null;
  end if;
  update pipeline.worker_idle_tally set polls = polls + 1, last_at = now() where mode = v_mode and worker = v_worker;
  return v_id;
end $f$;
revoke all on function security.worker_idle_collapse_v1(text, int, int, jsonb, text) from public, anon, authenticated;
comment on function security.worker_idle_collapse_v1(text, int, int, jsonb, text) is 'CF-247 s823: called first by public.svc_worker_report_v1. An idle call that follows an idle call of the same mode and worker within telemetry.idle_collapse_minutes updates that ledger row and returns its id; anything else returns null and is recorded as before.';

create or replace function security.worker_idle_note_v1(p_mode text, p_worker text, p_id bigint)
returns void language plpgsql security definer set search_path to '' as $f$
begin
  if exists (select 1 from pipeline.mode_outcome_ledger l where l.id = p_id and l.outcome = 'idle') then
    insert into pipeline.worker_idle_tally(mode, worker, ledger_id, polls, last_at)
    values (left(coalesce(p_mode, ''), 60), left(coalesce(p_worker, ''), 80), p_id, 1, now())
    on conflict (mode, worker) do update set ledger_id = excluded.ledger_id, polls = 1, last_at = excluded.last_at;
  end if;
end $f$;
revoke all on function security.worker_idle_note_v1(text, text, bigint) from public, anon, authenticated;
comment on function security.worker_idle_note_v1(text, text, bigint) is 'CF-247 s823: called last by public.svc_worker_report_v1; a newly written idle row starts a run of idle calls.';

-- in-place edits: each old fragment must occur exactly once, so a definition that has drifted stops the change instead of being overwritten
create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if p_md5 is not null and md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

-- s823: security.admin_platform_health_cf221() answers from the stored pulse when it is fresh. No md5 is recorded for this function since its 20 Oct 2026
-- D11 edit, so the guard is two exactly-once fragments: the D11 line (proves the version) and the role check the fast path follows.
select pg_temp.cf_edit_def('security.admin_platform_health_cf221()'::regprocedure, null,
  array[$o$v_active_ai := 0;  -- CF-247 20 Oct 2026 (D11): scholarship AI runs retired$o$,
        $o$ if v_rank<1 then raise exception 'authenticated role required' using errcode='42501'; end if;$o$],
  array[$n$v_active_ai := 0;  -- CF-247 20 Oct 2026 (D11): scholarship AI runs retired$n$,
        $n$ if v_rank<1 then raise exception 'authenticated role required' using errcode='42501'; end if;
 if security.ops_pulse_fresh_v1() then return security.ops_pulse_cf221_v1(v_rank); end if;  -- CF-247 s823: the stored pulse (5 minutes); live counts below only when it is stale$n$]);

-- s823: public.svc_worker_report_v1 (md5 recorded after its 3 Nov 2026 lanes edit, 20261103160000): an idle run updates one row
select pg_temp.cf_edit_def('public.svc_worker_report_v1(text,integer,integer,jsonb,text)'::regprocedure, 'b110a648a8149eede42cbc69cce43a77',
  array[$o$  v_items := coalesce(security.worker_call_work_v1(p_body::text), 0)::int;$o$,
        $o$   where l.id = v_id;
  return v_id;$o$],
  array[$n$  v_id := security.worker_idle_collapse_v1(p_mode, p_status, p_ms, p_body, p_worker);  -- CF-247 s823: a run of idle calls updates one row
  if v_id is not null then return v_id; end if;
  v_items := coalesce(security.worker_call_work_v1(p_body::text), 0)::int;$n$,
        $n$   where l.id = v_id;
  perform security.worker_idle_note_v1(p_mode, p_worker, v_id);  -- CF-247 s823
  return v_id;$n$]);

-- the job (G1): registered in Automations and the component register
insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values
 ('ops-pulse-refresh', 'Platform health', 5, 'Ops pulse: rebuild the stored Platform Health figures',
  'Every 5 minutes: counts jobs, evidence, Layer 2 requests, scholarships, Layer 4 waiting items and completeness once and stores them in one row, so Platform Health and the top-bar health dot read a stored row instead of counting on every open. If this job stops, the screens count live again after ops.pulse_max_age_minutes.',
  6, false)
on conflict (jobname) do nothing;

select cron.schedule('ops-pulse-refresh', '*/5 * * * *', 'select security.ops_pulse_refresh_v1()')
where not exists (select 1 from cron.job where jobname = 'ops-pulse-refresh');

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('job', 'ops-pulse-refresh', 'Platform', 'Platform health', 'Rebuilds the stored ops pulse every 5 minutes', 'active', '{}', '20261120140000'),
  ('table', 'pipeline.ops_pulse_snapshot', 'Platform', 'Platform health', 'The stored ops pulse (one row)', 'active', '{}', '20261120140000'),
  ('table', 'pipeline.ops_pulse_stage_map', 'Platform', 'Platform health', 'Which health check reports under which pipeline stage', 'active', '{}', '20261120140000'),
  ('table', 'pipeline.worker_idle_tally', 'Platform', 'Telemetry', 'The current run of idle worker calls per mode and worker', 'active', '{}', '20261120140000'),
  ('function', 'security.ops_pulse_refresh_v1', 'Platform', 'Platform health', 'One rebuild of the stored ops pulse', 'active', '{}', '20261120140000'),
  ('function', 'security.ops_pulse_cf221_v1', 'Platform', 'Platform health', 'The stored ops pulse in the Platform Health shape, by role', 'active', '{}', '20261120140000'),
  ('function', 'security.worker_idle_collapse_v1', 'Platform', 'Telemetry', 'Folds a run of idle worker calls into one ledger row', 'active', '{}', '20261120140000')
on conflict do nothing;

-- the first rebuild, so the screens read the stored row from the first open
create temp table s820_run on commit drop as select security.ops_pulse_refresh_v1() r;

-- post-checks: reads, plus one idle-collapse test in a sub-block that is always rolled back
do $c$
declare v jsonb := (select r from s820_run); v_admin uuid; v_viewer uuid; h jsonb; t0 timestamptz; v_ms numeric; v_a bigint; v_b bigint; v_c bigint; v_rows int; v_polls int; v_o text := '';
begin
  if not (v->>'ok')::boolean then raise exception 'post-check: the first rebuild failed: %', v; end if;
  if (v->>'run_ms')::int > 20000 then raise exception 'post-check: the rebuild took % ms (limit 20 s for a 5-minute job)', v->>'run_ms'; end if;
  if (select payload->'pulse'->'layer4_waiting' from pipeline.ops_pulse_snapshot) is null then raise exception 'post-check: the Layer 4 waiting count is unknown: %', v->'errors'; end if;
  if jsonb_array_length((select payload->'pulse'->'stages' from pipeline.ops_pulse_snapshot)) <> 4 then raise exception 'post-check: the pulse does not hold four stages'; end if;
  if not exists (select 1 from cron.job where jobname = 'ops-pulse-refresh' and active) then raise exception 'post-check: the job is not scheduled'; end if;
  v_o := format('rebuild %s ms, errors %s', v->>'run_ms', v->'errors');

  -- as a Platform Admin: the read answers from the stored row, quickly, with the pulse; the CF-221 keys the Dashboard panel reads are all there
  select ur.user_id into v_admin from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ro.status = 'active' and ro.rank >= 6 and (ur.expires_at is null or ur.expires_at > now()) order by ur.user_id limit 1;
  if v_admin is null then raise exception 'post-check: no Platform Admin to act as'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  t0 := clock_timestamp();
  h := security.admin_platform_health_cf221();
  v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  if coalesce(h->>'pulse_source', '') <> 'snapshot' then raise exception 'post-check: the read did not use the stored pulse: %', left(h::text, 300); end if;
  if not (h ? 'jobs' and h ? 'data' and h ? 'edge_runtime' and h ? 'api_activity' and h ? 'pulse' and h ? 'observed_at') then raise exception 'post-check: keys missing %', left(h::text, 300); end if;
  if v_ms > 50 then raise exception 'post-check: the stored read took % ms', round(v_ms, 1); end if;
  v_o := v_o || format('; admin read %s ms', round(v_ms, 2));

  -- a rank 1 or 2 user gets no api_activity and no pulse
  select ur.user_id into v_viewer from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ro.status = 'active' and ro.rank between 1 and 2 and (ur.expires_at is null or ur.expires_at > now()) order by ur.user_id limit 1;
  if v_viewer is not null then
    perform set_config('request.jwt.claims', jsonb_build_object('sub', v_viewer::text, 'role', 'authenticated')::text, true);
    h := security.admin_platform_health_cf221();
    if h ? 'pulse' or h ? 'api_activity' then raise exception 'post-check: a rank 1-2 user was given the pulse or API activity'; end if;
    v_o := v_o || '; viewer gated';
  end if;
  perform set_config('request.jwt.claims', '', true);

  -- s823 in a block that is always undone: three idle calls are one row with idle_polls 3; a call with work then writes its own row
  begin
    perform set_config('request.jwt.claims', jsonb_build_object('role', 'service_role')::text, true);
    v_a := public.svc_worker_report_v1('s823_post_check', 200, 10, jsonb_build_object('ok', true, 'mode', 's823_post_check', 'idle', true, 'items', 0), 's823-test');
    v_b := public.svc_worker_report_v1('s823_post_check', 200, 11, jsonb_build_object('ok', true, 'mode', 's823_post_check', 'idle', true, 'items', 0), 's823-test');
    v_b := public.svc_worker_report_v1('s823_post_check', 200, 12, jsonb_build_object('ok', true, 'mode', 's823_post_check', 'idle', true, 'items', 0), 's823-test');
    select count(*), max((detail->>'idle_polls')::int) into v_rows, v_polls from pipeline.mode_outcome_ledger where mode = 's823_post_check';
    if v_a <> v_b or v_rows <> 1 or v_polls <> 3 then raise exception 'post-check: idle calls were not folded (rows %, polls %, ids % %)', v_rows, v_polls, v_a, v_b; end if;
    v_c := public.svc_worker_report_v1('s823_post_check', 200, 13, jsonb_build_object('ok', true, 'mode', 's823_post_check', 'items', 2, 'done', 2), 's823-test');
    if v_c = v_a or (select count(*) from pipeline.mode_outcome_ledger where mode = 's823_post_check') <> 2 then raise exception 'post-check: a call with work did not get its own row'; end if;
    if exists (select 1 from pipeline.worker_idle_tally where mode = 's823_post_check') then raise exception 'post-check: work did not end the idle run'; end if;
    raise exception 'cf-s823-undo';
  exception when others then
    if sqlerrm <> 'cf-s823-undo' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '', true);
  v_o := v_o || '; idle calls folded 3 to 1 and work recorded on its own (rolled back)';
  raise notice 'CF-247 s823 post-checks: %', v_o;
end $c$;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API changed: %', v;
  end if;
end $g$;
