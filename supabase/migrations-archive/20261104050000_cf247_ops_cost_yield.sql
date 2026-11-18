-- CF-247 workstream F (P0 Autonomous AI Operations, 3 Nov 2026): the AI cost and yield controller and efficiency reporting.
-- Mandate: admin docs/platform/nz-enrichment-brief/2026-11-03-p0-autonomous-ai-operations-mandate-1537.md §11 (budget-aware execution) and
-- §16 (Efficiency); ownership and shared contract: 2026-11-03-ai-operations-workstreams-1540.md §3 (F owns new ops_cost_* objects and read-only
-- reporting; F exposes security.ops_step_value_v1 for workstream D to call; F does not edit D's plan functions).
-- Why (production, read-only, 3 Nov 2026 15:46-15:48 and 15:56-15:58 AEDT, 7 days ending 3 Nov 15:46):
--   * Repeated searches with no new input: 10,312 of 14,766 paid searches (20,624 of 29,532 credits) repeated a query string already paid for
--     within 30 days (course_link_search 6,374 repeats, 12,748 credits; the integrator's fc_search run 3,937, 7,874 credits). In the last 24 h
--     850 of 1,040 course-page searches repeated an earlier query; the same query was sent up to 4 times within 2 minutes (one per course
--     row with the same title). Yield of those 899 search rows: 229 found, 17 verified (27%).
--   * Expensive low-confidence loops: 2,526 course fields were read by AI 3 or more times in 37 days with no value found (7,884 reads,
--     US$6.03 of US$23.70 enrich_fields spend in 7 days, 25%). The existing "page did not state it" hold (security.enrich_item_held_v1, flag
--     enrich_no_value) is raised only for five skip wordings, so these keys are read again.
--   * Repeated AI reads of identical evidence: 509 enrich_fields reads (US$0.61) of the same course, field and page content already answered;
--     6 scholarship reads (US$0.0015). One provider-level campus list read 62 times from one unchanged page.
--   * Paid acquisition for stored pages: 14,225 of 20,268 paid page reads (14,264 credits) were of an address with a stored copy under 30 days
--     old (12,232 of them in the integrator's re-read run fd98d679); 13 brought back byte-identical content.
--   * Unlimited retries: AI course-page matching made 8,919 attempts above waste.retry_max_attempts (3) in 7 days (up to attempt 11;
--     US$1.23; 1,449 found a page, 16%). Firecrawl failures are not billed (0 credits on 17 extra failed calls).
--   * Ineligible providers: 8,668 credits on 372 providers now search-stopped (5,972), scholarship-ineligible (1,380) or on
--     search.skip_providers (614).
-- What:
--   1. Settings (G2), section "Cost and yield": windows, thresholds, a Firecrawl price per credit (0 = not priced), and one enforcement
--      switch per breaker. Every enforcement switch ships OFF (it holds work or refuses spend, so it removes work).
--   2. pipeline.ops_cost_waste_measures (hourly measures, kept ops_cost.measure_keep_days) and pipeline.ops_cost_breakers (breaker state).
--   3. security.ops_cost_waste_v1(window): the six waste checks, live, with counts, spend and samples (read-only).
--   4. security.ops_cost_guard_v1(): run by the existing waste-guard job (security.waste_guard_v1, md5-guarded edit adds one key). It records
--      the measures, trips or clears each breaker against the settings, opens or clears one integration issue per check by fingerprint
--      (cost:<check>), and, only when its switch is on, holds looping course fields through the existing enrich_no_value hold. A breaker
--      only pauses or skips: nothing here raises a budget, a share, a ceiling or a cap.
--   5. security.ops_cost_fc_refusal_v1: public.svc_fc_spend (md5-guarded edit adds one refusal branch after the on-demand branch) refuses a
--      repeated search, a stored page or an ineligible provider while that breaker is tripped and its switch is on; the refusal is recorded
--      with the other refusals (pipeline.firecrawl_budget_refusals, firecrawl_refusals_by_provider). On-demand runs a person started are not
--      held. Off: no refusal is added.
--   6. Workstream A's contract: eight root causes and three remedies registered (cost_breaker auto; cost_result_reuse release;
--      cost_budget_decision admin), with the breaker remedy's action and verify functions.
--   7. security.ops_step_value_v1(provider, step, scope): the value estimate of a candidate plan step for workstream D (eligible records,
--      expected recovery from measured yield, evidence held, incremental AI and Firecrawl cost, likelihood, work in progress, retry spend and
--      last failure, value per dollar). Reads existing tables only.
--   8. security.ops_cost_report_v1(window_hours): the §16 efficiency section for workstream A's ops_report_v1 (paid operations and cost,
--      evidence reuse, avoided duplicate reads, useful yield per execution, AI and Firecrawl consumption, cost per verified improvement by lane).
-- Live definitions edited (md5 read live 3 Nov 2026 15:43 and 15:56 AEDT):
--   public.svc_fc_spend(numeric,text,uuid,text)      d418c451d681ffd95134f5f4dcf7c504 -> a9217c5af8e0da8ee18b03bcab9eaeef
--   security.waste_guard_v1()                        101d6fbf97e3c7d3e5830f762c33107b -> 49b86d8c8cac388957761e17b9f2dc28
-- Ships ON: measures, breaker state, integration issues, the registry, ops_step_value_v1 and ops_cost_report_v1 (they only measure, diagnose
-- and report). Ships OFF: ops_cost.enforce_ai_loop_hold, ops_cost.enforce_repeat_search, ops_cost.enforce_stored_page, ops_cost.enforce_ineligible.
-- Replaces: nothing (public.svc_fc_spend and security.waste_guard_v1 keep their names; md5-guarded edits)
-- Retires: nothing
-- Nothing dropped or deleted by this migration; no job added (the existing waste-guard job runs the guard); no budget, share, ceiling or cap
-- changed. Consumer API untouched (G3): catalogue and search tables are only read.

do $guard$ begin
  if to_regclass('pipeline.ops_remedies') is null then
    raise exception 'workstream A''s shared contract (migration 20261104010000) must be applied first: pipeline.ops_remedies is missing';
  end if;
end $guard$;

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 1. settings (G2) -------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'ops_cost.measure_on', 'Cost and yield: measure waste every hour',
  'The waste-guard job measures the six kinds of waste (repeated AI reads, repeated searches, paid reads of stored pages, retries, low-confidence loops, ineligible providers), records them, trips or clears the breakers and opens or clears one integration issue per kind. It never spends.',
  'number', '1'::jsonb, 0, 1, 'on (1) or off (0)', 1100, 'Cost and yield', 'security.ops_cost_guard_v1 (job waste-guard)', 'P0 AI operations mandate 3 Nov 2026 §11 (workstream F)'),
 ('pipeline', 'ops_cost.guard_window_hours', 'Cost and yield: the hourly check looks at the last',
  'The window the waste-guard job measures each hour. The report and the Platform Admin can ask for any window.',
  'number', '24'::jsonb, 1, 168, 'hours', 1101, 'Cost and yield', 'security.ops_cost_guard_v1', 'P0 AI operations mandate §11'),
 ('pipeline', 'ops_cost.lookback_days', 'Cost and yield: an earlier identical read or search counts within',
  'A read or search counts as a repeat when the same page content, field or query was already paid for within this many days.',
  'number', '30'::jsonb, 1, 90, 'days', 1102, 'Cost and yield', 'security.ops_cost_waste_v1', 'P0 AI operations mandate §11'),
 ('pipeline', 'ops_cost.history_days', 'Cost and yield: yield and unit costs measured over the last',
  'Plan step estimates use the measured yield (values filled, pages found and verified, scholarships admitted) and the measured AI and Firecrawl cost of this many days.',
  'number', '30'::jsonb, 7, 90, 'days', 1103, 'Cost and yield', 'security.ops_step_value_v1', 'P0 AI operations mandate §11'),
 ('pipeline', 'ops_cost.min_sample', 'Cost and yield: least settled items before a provider''s own yield is used',
  'Below this many settled items the platform-wide yield for the step and field is used instead of the provider''s own.',
  'number', '20'::jsonb, 1, 1000, 'items', 1104, 'Cost and yield', 'security.ops_step_value_v1', 'P0 AI operations mandate §11'),
 ('pipeline', 'ops_cost.loop_min_reads', 'Cost and yield: AI reads of one course field with no value before it is a loop',
  'A course field read by AI this many times within the look-back with no value found is a low-confidence loop.',
  'number', '3'::jsonb, 2, 20, 'reads', 1105, 'Cost and yield', 'security.ops_cost_waste_v1, security.ops_cost_guard_v1', 'P0 AI operations mandate §11: expensive low-confidence loops'),
 ('pipeline', 'ops_cost.stored_page_fresh_hours', 'Cost and yield: a stored page this fresh is not bought again',
  'A paid page read of an address with a stored copy younger than this counts as waste; with its breaker switched on it is refused.',
  'number', '24'::jsonb, 1, 720, 'hours', 1106, 'Cost and yield', 'security.ops_cost_waste_v1, security.ops_cost_fc_refusal_v1', 'P0 AI operations mandate §11: paid acquisition for stored pages'),
 ('pipeline', 'ops_cost.repeat_search_hours', 'Cost and yield: the same search is not paid for again within',
  'A paid search whose exact query was already paid for within this many hours counts as a repeat; with its breaker switched on it is refused.',
  'number', '24'::jsonb, 1, 720, 'hours', 1107, 'Cost and yield', 'security.ops_cost_waste_v1, security.ops_cost_fc_refusal_v1', 'P0 AI operations mandate §11: repeated searches with no new information'),
 ('pipeline', 'ops_cost.ineligible_min_credits', 'Cost and yield: credits on one ineligible provider before its breaker trips',
  'A provider that is search-stopped, scholarship-ineligible or on the search skip list and used this many credits for that purpose in the window trips its own breaker.',
  'number', '50'::jsonb, 1, 10000, 'credits', 1108, 'Cost and yield', 'security.ops_cost_guard_v1', 'P0 AI operations mandate §11: high-volume scans of ineligible providers'),
 ('pipeline', 'ops_cost.trip_min_events', 'Cost and yield: wasted operations in the window before a breaker trips',
  'A breaker trips when its kind of waste reaches this many operations in the window and the share below.',
  'number', '20'::jsonb, 1, 100000, 'operations', 1109, 'Cost and yield', 'security.ops_cost_guard_v1, security.ops_cost_remedy_verify_v1', 'P0 AI operations mandate §11: circuit breakers'),
 ('pipeline', 'ops_cost.trip_min_share', 'Cost and yield: and at least this share of the lane''s paid operations',
  'The share of the lane''s paid operations in the window that must be waste for the breaker to trip.',
  'number', '10'::jsonb, 1, 100, '%', 1110, 'Cost and yield', 'security.ops_cost_guard_v1', 'P0 AI operations mandate §11: circuit breakers'),
 ('pipeline', 'ops_cost.hold_per_run', 'Cost and yield: most looping course fields held per run',
  'With the loop hold switched on, at most this many course fields are held each hour.',
  'number', '500'::jsonb, 0, 5000, 'fields', 1111, 'Cost and yield', 'security.ops_cost_guard_v1', 'P0 AI operations mandate §11'),
 ('pipeline', 'ops_cost.samples', 'Cost and yield: samples kept per measure',
  'How many example rows each measure keeps as evidence.',
  'number', '5'::jsonb, 1, 50, 'rows', 1112, 'Cost and yield', 'security.ops_cost_waste_v1', 'P0 AI operations mandate §11'),
 ('pipeline', 'ops_cost.measure_keep_days', 'Cost and yield: keep hourly measures for',
  'Hourly waste measures older than this are removed by the waste-guard job.',
  'number', '90'::jsonb, 7, 400, 'days', 1113, 'Cost and yield', 'security.ops_cost_guard_v1', 'P0 AI operations mandate §11'),
 ('pipeline', 'ops_cost.fc_usd_per_credit', 'Cost and yield: Firecrawl price per credit',
  'Used to put Firecrawl credits and AI dollars on one scale (value per dollar, cost per verified improvement). 0 = not priced: credits are reported on their own and value per dollar counts AI only.',
  'number', '0'::jsonb, 0, 1, 'US$ per credit', 1114, 'Cost and yield', 'security.ops_step_value_v1, security.ops_cost_report_v1', 'P0 AI operations mandate §11 (the vendor price is not held in the platform; Platform Admin to set)'),
 ('pipeline', 'ops_cost.remedy_max_attempts', 'Cost and yield: breaker remedy attempts per issue',
  'The AI Operations Controller tries the breaker remedy at most this many times on one issue.',
  'number', '3'::jsonb, 1, 10, 'attempts', 1115, 'Cost and yield', 'pipeline.ops_remedies cost_breaker (max_attempts_key)', 'Workstream A contract'),
 ('pipeline', 'ops_cost.remedy_cooldown_hours', 'Cost and yield: wait between breaker remedy attempts',
  'The AI Operations Controller waits this long between attempts of the breaker remedy on one issue.',
  'number', '6'::jsonb, 1, 168, 'hours', 1116, 'Cost and yield', 'pipeline.ops_remedies cost_breaker (cooldown_key)', 'Workstream A contract'),
 ('pipeline', 'ops_cost.likely_high_pct', 'Cost and yield: a step is "high" likelihood from a success rate of',
  'A plan step whose measured success rate is at least this is high likelihood; at least waste.retry_min_yield_pct is medium; below that low.',
  'number', '50'::jsonb, 1, 100, '%', 1121, 'Cost and yield', 'security.ops_step_value_v1', 'P0 AI operations mandate §11'),
 ('pipeline', 'ops_cost.enforce_ai_loop_hold', 'Cost and yield breaker: hold looping course fields',
  'On: while the loop or repeated-read breaker is tripped, course fields read by AI without a value (or read again from unchanged content) are held through the existing "page did not state it" hold; the hold lifts when a new page is read or after gaps.recheck_days. Off: measured only.',
  'number', '0'::jsonb, 0, 1, 'on (1) or off (0)', 1117, 'Cost and yield', 'security.ops_cost_guard_v1 (security.enrich_item_held_v1)', 'Ships off: holding items removes work (ops brief 3 Nov 2026 15:45)'),
 ('pipeline', 'ops_cost.enforce_repeat_search', 'Cost and yield breaker: refuse a repeated search',
  'On: while the repeated-search breaker is tripped, a paid search whose exact query was paid for within ops_cost.repeat_search_hours is refused (reason repeat_search). Off: measured only.',
  'number', '0'::jsonb, 0, 1, 'on (1) or off (0)', 1118, 'Cost and yield', 'security.ops_cost_fc_refusal_v1 (public.svc_fc_spend)', 'Ships off: refusing spend removes work'),
 ('pipeline', 'ops_cost.enforce_stored_page', 'Cost and yield breaker: refuse buying a page already stored',
  'On: while the stored-page breaker is tripped, a paid read of an address with a stored copy younger than ops_cost.stored_page_fresh_hours is refused (reason stored_page), unless a person asked for the page again. Off: measured only.',
  'number', '0'::jsonb, 0, 1, 'on (1) or off (0)', 1119, 'Cost and yield', 'security.ops_cost_fc_refusal_v1 (public.svc_fc_spend)', 'Ships off: refusing spend removes work'),
 ('pipeline', 'ops_cost.enforce_ineligible', 'Cost and yield breaker: refuse spend on an ineligible provider',
  'On: a provider whose own breaker is tripped (search-stopped, scholarship-ineligible or skip-listed, with heavy spend) is refused (reason ineligible_provider). Off: measured only.',
  'number', '0'::jsonb, 0, 1, 'on (1) or off (0)', 1120, 'Cost and yield', 'security.ops_cost_fc_refusal_v1 (public.svc_fc_spend)', 'Ships off: refusing spend removes work')
on conflict do nothing;

-- 2. records -------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.ops_cost_waste_measures (
  id bigserial primary key,
  measured_at timestamptz not null default now(),
  window_hours int not null,
  check_code text not null,
  events bigint not null default 0,
  ai_usd numeric not null default 0,
  credits numeric not null default 0,
  base_events bigint not null default 0,
  base_ai_usd numeric not null default 0,
  base_credits numeric not null default 0,
  share_pct numeric,
  samples jsonb not null default '[]'::jsonb,
  detail jsonb not null default '{}'::jsonb);
create index if not exists ops_cost_waste_measures_code_at_idx on pipeline.ops_cost_waste_measures (check_code, measured_at desc);
comment on table pipeline.ops_cost_waste_measures is 'CF-247 workstream F (P0 AI operations mandate 3 Nov 2026 §11): hourly measure of each kind of waste (operations, AI US$, Firecrawl credits, against the lane''s paid operations, with samples), written by security.ops_cost_guard_v1 from the waste-guard job; kept ops_cost.measure_keep_days.';
create table if not exists pipeline.ops_cost_breakers (
  code text not null,
  scope_kind text not null check (scope_kind in ('global', 'provider')),
  scope_key text not null,
  state text not null check (state in ('tripped', 'clear')),
  tripped_at timestamptz,
  cleared_at timestamptz,
  checked_at timestamptz not null default now(),
  measure jsonb not null default '{}'::jsonb,
  primary key (code, scope_kind, scope_key));
comment on table pipeline.ops_cost_breakers is 'CF-247 workstream F (P0 AI operations mandate §11): circuit breaker state per waste check (global) or per provider (ineligible scans). Tripped and cleared by security.ops_cost_guard_v1 against the settings; a tripped breaker refuses or holds only when its ops_cost.enforce_* switch is on. A breaker only pauses or skips.';

-- 3. the six waste checks (read-only) -------------------------------------------------------------------------------------------------------
create or replace function security.ops_cost_waste_v1(p_window_hours int default null, p_since timestamptz default null) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 workstream F: repeated AI reads of identical evidence, repeated searches with no new input, paid reads of stored pages, retries above
-- the cap, low-confidence AI loops, Firecrawl spend on ineligible providers. Each: events, AI US$, credits, the lane's paid base, samples.
declare v_w int := greatest(1, least(coalesce(p_window_hours, security.pipeline_num_v1('ops_cost.guard_window_hours', 24)::int), 24 * 90));  -- fixed: a window is at most 90 days (the look-back tables are kept about that long)
        -- p_since (a remedy's verify): measure from that moment instead of a whole window
        v_since timestamptz := greatest(coalesce(p_since, now() - make_interval(hours => v_w)), now() - make_interval(hours => v_w));
        v_back timestamptz := now() - make_interval(hours => v_w) - make_interval(days => security.pipeline_num_v1('ops_cost.lookback_days', 30)::int);
        v_n int := security.pipeline_num_v1('ops_cost.samples', 5)::int;
        v_loop int := security.pipeline_num_v1('ops_cost.loop_min_reads', 3)::int;
        v_fresh interval := make_interval(hours => security.pipeline_num_v1('ops_cost.stored_page_fresh_hours', 24)::int);
        v_rs interval := make_interval(hours => security.pipeline_num_v1('ops_cost.repeat_search_hours', 24)::int);
        v_cap int := security.pipeline_num_v1('waste.retry_max_attempts', 3)::int;
        v_inel numeric := security.pipeline_num_v1('ops_cost.ineligible_min_credits', 50);
        c1 jsonb; c2 jsonb; c3 jsonb; c4 jsonb; c5 jsonb; c6 jsonb;
begin
  -- 1. repeated AI reads of identical evidence: an AI read of a course field (or provider list) whose same page content was already answered
  with fi as (select i.id, i.course_id, i.provider_id, i.field, i.state, i.cost_usd, i.updated_at, e.content_hash
                from pipeline.field_enrich_items i join pipeline.evidence_artifacts e on e.id = i.evidence_id
               where i.cost_usd > 0 and e.content_hash is not null and i.updated_at > v_back),
       fr as (select fi.*, row_number() over w rn,
                     bool_or(state in ('filled', 'skipped', 'review')) over (w rows between unbounded preceding and 1 preceding) prior_answered
                from fi window w as (partition by provider_id, course_id, field, content_hash order by updated_at, id)),
       sx as (select x.id, x.url, x.content_hash, x.cost_usd, x.at, x.run_kind, coalesce(q.step, 0) step,
                     row_number() over (partition by x.content_hash, x.model_code, x.prompt_version, x.run_kind, coalesce(q.step, 0) order by x.at, x.id) rn
                from pipeline.scholarship_ai_extractions x left join pipeline.scholarship_ai_queue q on q.id = x.queue_id
               where x.content_hash is not null and x.error is null and x.at > v_back)
  select jsonb_build_object(
    'events', (select count(*) from fr where rn > 1 and prior_answered and updated_at > v_since) + (select count(*) from sx where rn > 1 and at > v_since),
    'ai_usd', coalesce((select sum(cost_usd) from fr where rn > 1 and prior_answered and updated_at > v_since), 0) + coalesce((select sum(cost_usd) from sx where rn > 1 and at > v_since), 0),
    'credits', 0,
    'base_events', (select count(*) from fi where updated_at > v_since) + (select count(*) from sx where at > v_since),
    'base_ai_usd', coalesce((select sum(cost_usd) from fi where updated_at > v_since), 0) + coalesce((select sum(cost_usd) from sx where at > v_since), 0),
    'base_credits', 0,
    'detail', jsonb_build_object('enrich_fields', (select count(*) from fr where rn > 1 and prior_answered and updated_at > v_since),
                                 'enrich_fields_provider_level', (select count(*) from fr where rn > 1 and prior_answered and updated_at > v_since and course_id is null),
                                 'scholarship_ai', (select count(*) from sx where rn > 1 and at > v_since)),
    'samples', coalesce((select jsonb_agg(s) from (select 'enrich_fields' lane, course_id, provider_id, field, left(content_hash, 12) content, rn reads, state, cost_usd
                                                    from fr where rn > 1 and prior_answered and updated_at > v_since order by rn desc, updated_at desc limit v_n) s), '[]'::jsonb))
    into c1;

  -- 2. repeated searches: a paid search whose exact query was already paid for within ops_cost.repeat_search_hours
  with su as (select u.id, u.purpose, u.url, u.provider_id, u.units, u.at,
                     lag(u.at) over (partition by u.purpose, lower(u.url) order by u.at, u.id) prev_at
                from pipeline.coverage_vendor_usage u
               where u.purpose in ('course_link_search', 'fc_search', 'sch_search', 'search') and u.at > v_since - v_rs)
  select jsonb_build_object(
    'events', count(*) filter (where su.at > v_since and su.prev_at > su.at - v_rs),
    'ai_usd', 0,
    'credits', coalesce(sum(su.units) filter (where su.at > v_since and su.prev_at > su.at - v_rs), 0),
    'base_events', count(*) filter (where su.at > v_since),
    'base_ai_usd', 0,
    'base_credits', coalesce(sum(su.units) filter (where su.at > v_since), 0),
    'detail', jsonb_build_object('by_purpose', (select coalesce(jsonb_object_agg(p, n), '{}'::jsonb) from (select s2.purpose p, count(*) n from su s2 where s2.at > v_since and s2.prev_at > s2.at - v_rs group by 1) z),
                                 'repeat_within_lookback', (select count(*) from su s3 where s3.at > v_since and exists (
                                     select 1 from pipeline.coverage_vendor_usage p where p.purpose = s3.purpose and p.provider_id is not distinct from s3.provider_id and p.at < s3.at and p.at > v_back and lower(p.url) = lower(s3.url)))),
    'samples', coalesce((select jsonb_agg(s) from (select s4.purpose, left(s4.url, 160) query, s4.provider_id, s4.at, s4.prev_at from su s4 where s4.at > v_since and s4.prev_at > s4.at - v_rs order by s4.at desc limit v_n) s), '[]'::jsonb))
    into c2 from su;

  -- 3. paid reads of a page already stored (a stored copy of the same address younger than ops_cost.stored_page_fresh_hours)
  with rd as (select u.id, u.purpose, u.url, u.provider_id, u.units, u.at from pipeline.coverage_vendor_usage u
               where u.at > v_since and u.purpose in ('scrape', 'fc_read', 'sch_scrape', 'list_scrape', 'provider_facts_scrape', 'companion_read', 'provider_description')),
       st as (select rd.*, prev.content_hash prev_hash, prev.captured_at prev_at
                from rd cross join lateral (select e.content_hash, e.captured_at from pipeline.evidence_artifacts e
                                             where lower(e.source_url) = lower(rd.url) and e.captured_at < rd.at - interval '10 minutes'  -- fixed: the read's own copy is not "stored before"
                                               and e.captured_at > rd.at - v_fresh order by e.captured_at desc limit 1) prev)
  select jsonb_build_object(
    'events', (select count(*) from st), 'ai_usd', 0, 'credits', coalesce((select sum(units) from st), 0),
    'base_events', (select count(*) from rd), 'base_ai_usd', 0, 'base_credits', coalesce((select sum(units) from rd), 0),
    'detail', jsonb_build_object('by_purpose', (select coalesce(jsonb_object_agg(p, n), '{}'::jsonb) from (select purpose p, count(*) n from st group by 1) z)),
    'samples', coalesce((select jsonb_agg(s) from (select purpose, left(url, 160) url, provider_id, prev_at stored_at, at read_at from st order by at desc limit v_n) s), '[]'::jsonb))
    into c3;

  -- 4. retries above the cap: AI course-page matching attempts above waste.retry_max_attempts; course pages read more than the cap
  select jsonb_build_object(
    'events', count(*) filter (where m.attempt > v_cap),
    'ai_usd', coalesce(sum(m.cost_usd) filter (where m.attempt > v_cap), 0),
    'credits', 0,
    'base_events', count(*), 'base_ai_usd', coalesce(sum(m.cost_usd), 0), 'base_credits', 0,
    'detail', jsonb_build_object('cap', v_cap, 'max_attempt', max(m.attempt),
                                 'found_above_cap', count(*) filter (where m.attempt > v_cap and m.chosen_url is not null),
                                 'course_pages_read_above_cap', (select count(*) from pipeline.coverage_course_pages p where p.read_attempts > v_cap and p.read_at > v_since),
                                 'enrich_items_above_cap', (select count(*) from pipeline.field_enrich_items i where i.attempts > v_cap and i.updated_at > v_since)),
    'samples', coalesce((select jsonb_agg(s) from (select m2.course_id, m2.provider_id, m2.attempt, m2.state, m2.cost_usd from pipeline.coverage_ai_match m2
                                                    where m2.created_at > v_since and m2.attempt > v_cap order by m2.attempt desc, m2.id desc limit v_n) s), '[]'::jsonb))
    into c4 from pipeline.coverage_ai_match m where m.created_at > v_since;

  -- 5. low-confidence loops: a course field read by AI ops_cost.loop_min_reads times or more in the look-back with no value, read again in the window
  with lc as (select i.course_id, i.provider_id, i.field, count(*) reads, sum(i.cost_usd) usd, sum(i.cost_usd) filter (where i.updated_at > v_since) usd_w,
                     count(*) filter (where i.updated_at > v_since) reads_w
                from pipeline.field_enrich_items i where i.cost_usd > 0 and i.course_id is not null and i.updated_at > v_back
               group by 1, 2, 3 having count(*) >= v_loop and bool_and(i.state <> 'filled'))
  select jsonb_build_object(
    'events', coalesce(sum(reads_w) filter (where reads_w > 0), 0), 'ai_usd', coalesce(sum(usd_w), 0), 'credits', 0,
    'base_events', (select count(*) from pipeline.field_enrich_items i where i.cost_usd > 0 and i.updated_at > v_since),
    'base_ai_usd', coalesce((select sum(i.cost_usd) from pipeline.field_enrich_items i where i.cost_usd > 0 and i.updated_at > v_since), 0), 'base_credits', 0,
    'detail', jsonb_build_object('course_fields', count(*) filter (where reads_w > 0), 'providers', count(distinct provider_id) filter (where reads_w > 0),
                                 'reads_in_lookback', coalesce(sum(reads) filter (where reads_w > 0), 0), 'ai_usd_in_lookback', coalesce(sum(usd) filter (where reads_w > 0), 0)),
    'samples', coalesce((select jsonb_agg(s) from (select l2.course_id, l2.provider_id, l2.field, l2.reads, round(l2.usd, 4) usd from lc l2 where l2.reads_w > 0 order by l2.usd desc limit v_n) s), '[]'::jsonb))
    into c5 from lc;

  -- 6. ineligible providers: Firecrawl credits for a purpose the provider is not eligible for (scholarship reads of a scholarship-ineligible
  -- provider, course searches of a search-stopped provider, any spend on a provider on search.skip_providers). Unpublished providers being
  -- onboarded are not counted.
  with pv as (select u.provider_id, u.purpose, sum(u.units) credits, count(*) calls from pipeline.coverage_vendor_usage u
               where u.at > v_since and u.provider_id is not null and u.on_demand_run is null group by 1, 2),
       stopped as (select x.provider_id from security.fc_search_stopped_v1() x),
       skipk as (select k from jsonb_array_elements_text(coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'search.skip_providers'), '[]'::jsonb)) k),
       ie as (select pv.*, case when p.stable_key in (select k from skipk) then 'skip_listed'
                                when pv.purpose in ('course_link_search', 'fc_search') and pv.provider_id in (select provider_id from stopped) then 'search_stopped'
                                when pv.purpose like 'sch\_%' and not security.fc_sch_eligible_v1(pv.provider_id) then 'scholarship_ineligible' end why
                from pv join catalogue.providers p on p.id = pv.provider_id where p.lifecycle_status = 'active'),
       pp as (select provider_id, sum(credits) credits, sum(calls) calls, jsonb_object_agg(purpose || ':' || why, credits) parts from ie where why is not null group by provider_id)
  select jsonb_build_object(
    'events', coalesce((select sum(calls) from pp), 0), 'ai_usd', 0, 'credits', coalesce((select sum(credits) from pp), 0),
    'base_events', coalesce((select sum(calls) from pv), 0), 'base_ai_usd', 0, 'base_credits', coalesce((select sum(credits) from pv), 0),
    'detail', jsonb_build_object('providers', (select count(*) from pp),
                                 'by_reason', (select coalesce(jsonb_object_agg(why, c), '{}'::jsonb) from (select why, sum(credits) c from ie where why is not null group by 1) z),
                                 'heavy_providers', (select coalesce(jsonb_agg(provider_id order by credits desc), '[]'::jsonb) from pp where credits >= v_inel)),
    'samples', coalesce((select jsonb_agg(s) from (select provider_id, credits, calls, parts from pp order by credits desc limit v_n) s), '[]'::jsonb))
    into c6;

  return jsonb_build_object('window_hours', v_w, 'measured_at', now(), 'checks', jsonb_build_object(
    'cost_repeat_ai_read', c1, 'cost_repeat_search', c2, 'cost_paid_stored_page', c3, 'cost_unbounded_retry', c4, 'cost_low_conf_loop', c5, 'cost_ineligible_scan', c6));
end $function$;
revoke all on function security.ops_cost_waste_v1(int, timestamptz) from public, anon, authenticated;
comment on function security.ops_cost_waste_v1(int, timestamptz) is 'CF-247 workstream F (mandate §11): the six waste checks over a window, with counts, AI US$, credits, the lane base and samples; read-only';

-- 4. the hourly guard (run by the existing waste-guard job) -----------------------------------------------------------------------------------
create or replace function security.ops_cost_guard_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_m jsonb; k text; c jsonb; v_share numeric; v_trip boolean; v_was text; v_out jsonb := '{}'::jsonb; v_iss jsonb; v_held int := 0; v_err text;
        v_min_ev numeric := security.pipeline_num_v1('ops_cost.trip_min_events', 20);
        v_min_sh numeric := security.pipeline_num_v1('ops_cost.trip_min_share', 10);
        v_inel numeric := security.pipeline_num_v1('ops_cost.ineligible_min_credits', 50);
        v_titles jsonb := jsonb_build_object(
          'cost_repeat_ai_read', 'AI reads the same page content again for a field it already answered',
          'cost_repeat_search', 'Paid searches repeat a query already paid for',
          'cost_paid_stored_page', 'Paid page reads buy pages the platform already stores',
          'cost_unbounded_retry', 'AI course-page matching tries past its attempt cap',
          'cost_low_conf_loop', 'AI reads the same course fields again and again without finding a value',
          'cost_ineligible_scan', 'Firecrawl credits are spent on providers known to be ineligible');
begin
  if security.pipeline_num_v1('ops_cost.measure_on', 1) < 1 then return jsonb_build_object('measured', false, 'why', 'ops_cost.measure_on is off'); end if;
  begin
    v_m := security.ops_cost_waste_v1(null);
    for k, c in select * from jsonb_each(v_m->'checks') loop
      v_share := case when coalesce((c->>'base_events')::numeric, 0) > 0 then round(100.0 * (c->>'events')::numeric / (c->>'base_events')::numeric, 1) end;
      insert into pipeline.ops_cost_waste_measures(window_hours, check_code, events, ai_usd, credits, base_events, base_ai_usd, base_credits, share_pct, samples, detail)
      values ((v_m->>'window_hours')::int, k, (c->>'events')::bigint, (c->>'ai_usd')::numeric, (c->>'credits')::numeric, (c->>'base_events')::bigint,
              (c->>'base_ai_usd')::numeric, (c->>'base_credits')::numeric, v_share, coalesce(c->'samples', '[]'::jsonb), coalesce(c->'detail', '{}'::jsonb));
      v_trip := case when k = 'cost_ineligible_scan' then jsonb_array_length(coalesce(c#>'{detail,heavy_providers}', '[]'::jsonb)) > 0
                     else (c->>'events')::numeric >= v_min_ev and coalesce(v_share, 0) >= v_min_sh end;
      select b.state into v_was from pipeline.ops_cost_breakers b where b.code = k and b.scope_kind = 'global' and b.scope_key = '*';
      insert into pipeline.ops_cost_breakers(code, scope_kind, scope_key, state, tripped_at, cleared_at, checked_at, measure)
      values (k, 'global', '*', case when v_trip then 'tripped' else 'clear' end, case when v_trip then now() end, case when not v_trip then now() end, now(),
              jsonb_build_object('events', c->'events', 'share_pct', v_share, 'ai_usd', c->'ai_usd', 'credits', c->'credits', 'window_hours', v_m->'window_hours'))
      on conflict (code, scope_kind, scope_key) do update set state = excluded.state, checked_at = now(), measure = excluded.measure,
        tripped_at = case when excluded.state = 'tripped' and pipeline.ops_cost_breakers.state <> 'tripped' then now() else pipeline.ops_cost_breakers.tripped_at end,
        cleared_at = case when excluded.state = 'clear' and pipeline.ops_cost_breakers.state <> 'clear' then now() else pipeline.ops_cost_breakers.cleared_at end;
      if v_trip then
        v_iss := security.integration_issue_upsert_v1(jsonb_build_object(
          'fingerprint', 'cost:' || k, 'title', v_titles->>k, 'layer', 'Platform', 'subsystem', 'cost and yield', 'severity', 'P2', 'workstream', 'F',
          'source', 'waste-guard', 'validation_layer', 'V4',
          'failure', format('%s: %s wasted operations of %s in %s hours (%s%%), US$%s AI, %s credits', v_titles->>k, c->>'events', c->>'base_events', v_m->>'window_hours',
                            coalesce(v_share::text, '-'), round((c->>'ai_usd')::numeric, 4), c->>'credits'),
          'expected', 'Waste below ops_cost.trip_min_events or ops_cost.trip_min_share; each paid operation brings new input',
          'evidence', jsonb_build_object('measure', c, 'window_hours', v_m->'window_hours', 'root_cause', k),
          'provider_ids', case when k = 'cost_ineligible_scan' then c#>'{detail,heavy_providers}' else '[]'::jsonb end), 'ops-cost-guard');
        -- workstream A's columns: the deterministic diagnosis and correlation key, only where none is recorded yet
        update pipeline.integration_issues i set correlation_key = coalesce(i.correlation_key, 'cost:' || k),
               -- fixed: a diagnosis measured by rule, not inferred, carries a fixed confidence
               diagnosis = coalesce(i.diagnosis, jsonb_build_object('root_cause', k, 'confidence', 0.9, 'method', 'rule: security.ops_cost_waste_v1',
                                                                    'evidence', jsonb_build_array(jsonb_build_object('measure', c->'detail', 'samples', c->'samples')), 'at', now()))
         where i.id = (v_iss->>'id')::bigint;
      elsif v_was = 'tripped' then
        update pipeline.integration_issues i set condition_cleared_at = now() where i.fingerprint = 'cost:' || k and i.condition_cleared_at is null and i.status <> 'closed';
      end if;
      v_out := v_out || jsonb_build_object(k, jsonb_build_object('events', c->'events', 'share_pct', v_share, 'tripped', v_trip));
    end loop;
    -- per-provider breakers for ineligible scans
    update pipeline.ops_cost_breakers b set state = 'clear', cleared_at = now(), checked_at = now()
     where b.code = 'cost_ineligible_scan' and b.scope_kind = 'provider' and b.state = 'tripped'
       and not (v_m#>'{checks,cost_ineligible_scan,detail,heavy_providers}') ? b.scope_key;
    insert into pipeline.ops_cost_breakers(code, scope_kind, scope_key, state, tripped_at, checked_at, measure)
    select 'cost_ineligible_scan', 'provider', p, 'tripped', now(), now(), jsonb_build_object('min_credits', v_inel, 'window_hours', v_m->'window_hours')
      from jsonb_array_elements_text(coalesce(v_m#>'{checks,cost_ineligible_scan,detail,heavy_providers}', '[]'::jsonb)) p
    on conflict (code, scope_kind, scope_key) do update set state = 'tripped', checked_at = now(),
      tripped_at = case when pipeline.ops_cost_breakers.state <> 'tripped' then now() else pipeline.ops_cost_breakers.tripped_at end;
    -- the loop hold (off by default): the existing "page did not state it" hold, soft, lifted by a new page read or after gaps.recheck_days
    if security.pipeline_num_v1('ops_cost.enforce_ai_loop_hold', 0) >= 1
       and exists (select 1 from pipeline.ops_cost_breakers b where b.code in ('cost_low_conf_loop', 'cost_repeat_ai_read') and b.scope_kind = 'global' and b.state = 'tripped') then
      v_held := security.ops_cost_loop_hold_v1(security.pipeline_num_v1('ops_cost.hold_per_run', 500)::int);
    end if;
    delete from pipeline.ops_cost_waste_measures m where m.measured_at < now() - make_interval(days => security.pipeline_num_v1('ops_cost.measure_keep_days', 90)::int);
  exception when others then
    v_err := left(sqlerrm, 300);  -- the waste guard's other checks never fail because of this one
  end;
  return jsonb_build_object('measured', v_err is null, 'checks', v_out, 'held', v_held, 'error', v_err);
end $function$;
revoke all on function security.ops_cost_guard_v1() from public, anon, authenticated;
comment on function security.ops_cost_guard_v1() is 'CF-247 workstream F (mandate §11): hourly in job waste-guard; records the waste measures, trips or clears the breakers, opens or clears integration issues cost:<check>, holds looping course fields only when ops_cost.enforce_ai_loop_hold is on';

-- the loop hold: course fields read by AI loop_min_reads times or more with no value (or read again from unchanged content), newest first,
-- not already held; raised through the existing flag unit so security.enrich_item_held_v1 skips them and a new page read lifts the hold
create or replace function security.ops_cost_loop_hold_v1(p_limit int) returns int
language plpgsql security definer set search_path to '' as $function$
declare r record; v_n int := 0; v_back timestamptz := now() - make_interval(days => security.pipeline_num_v1('ops_cost.lookback_days', 30)::int);
        v_loop int := security.pipeline_num_v1('ops_cost.loop_min_reads', 3)::int;
begin
  for r in
    select i.course_id, i.provider_id, i.field, count(*) reads, round(sum(i.cost_usd), 4) usd,
           (array_agg(i.evidence_id order by i.updated_at desc))[1] evidence_id
      from pipeline.field_enrich_items i
     where i.cost_usd > 0 and i.course_id is not null and i.updated_at > v_back
     group by 1, 2, 3
    having count(*) >= v_loop and bool_and(i.state <> 'filled')
       and not security.enrich_item_held_v1(i.course_id, i.field)
     order by max(i.updated_at) desc
     limit greatest(0, p_limit)
  loop
    perform security.flag_raise_v1('course', r.course_id::text, r.provider_id, r.field, 'enrich_no_value',
      format('Cost and yield: read by AI %s times without a value (US$%s); held until the page changes', r.reads, r.usd), 'soft', 'ops-cost-guard', 'auto',
      jsonb_build_object('reads', r.reads, 'usd', r.usd, 'evidence_id', r.evidence_id, 'rule', 'ops_cost.loop_min_reads'), r.evidence_id::text, null);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;
revoke all on function security.ops_cost_loop_hold_v1(int) from public, anon, authenticated;
comment on function security.ops_cost_loop_hold_v1(int) is 'CF-247 workstream F: holds looping course fields through the existing enrich_no_value flag (soft; lifted by a new page read); called by ops_cost_guard_v1 only when ops_cost.enforce_ai_loop_hold is on';

-- 5. the Firecrawl breakers in svc_fc_spend ---------------------------------------------------------------------------------------------------
create or replace function security.ops_cost_fc_refusal_v1(p_units numeric, p_purpose text, p_provider uuid, p_url text) returns text
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 workstream F: why a Firecrawl spend is refused by a cost breaker, or null. Each breaker refuses only while it is tripped and its
-- ops_cost.enforce_* switch is on. It never allows a spend another rule refuses (svc_fc_spend checks the month, the day and the shares too).
begin
  if security.pipeline_num_v1('ops_cost.enforce_repeat_search', 0) >= 1 and p_purpose in ('course_link_search', 'fc_search', 'sch_search', 'search')
     and exists (select 1 from pipeline.ops_cost_breakers b where b.code = 'cost_repeat_search' and b.scope_kind = 'global' and b.state = 'tripped')
     and exists (select 1 from pipeline.coverage_vendor_usage x
                  where x.purpose = p_purpose and x.at > now() - make_interval(hours => security.pipeline_num_v1('ops_cost.repeat_search_hours', 24)::int)
                    and x.provider_id is not distinct from p_provider and lower(x.url) = lower(p_url)) then
    return 'repeat_search';
  end if;
  if security.pipeline_num_v1('ops_cost.enforce_stored_page', 0) >= 1
     and p_purpose in ('scrape', 'fc_read', 'sch_scrape', 'list_scrape', 'provider_facts_scrape', 'companion_read', 'provider_description')
     and exists (select 1 from pipeline.ops_cost_breakers b where b.code = 'cost_paid_stored_page' and b.scope_kind = 'global' and b.state = 'tripped')
     and exists (select 1 from pipeline.evidence_artifacts e where lower(e.source_url) = lower(p_url)
                    and e.captured_at > now() - make_interval(hours => security.pipeline_num_v1('ops_cost.stored_page_fresh_hours', 24)::int))
     -- a page a person asked to be read again is never held
     and not exists (select 1 from pipeline.scholarship_pages sp where sp.url = p_url and sp.requested_at is not null) then
    return 'stored_page';
  end if;
  if security.pipeline_num_v1('ops_cost.enforce_ineligible', 0) >= 1 and p_provider is not null
     and exists (select 1 from pipeline.ops_cost_breakers b where b.code = 'cost_ineligible_scan' and b.scope_kind = 'provider' and b.scope_key = p_provider::text and b.state = 'tripped') then
    return 'ineligible_provider';
  end if;
  return null;
end $function$;
revoke all on function security.ops_cost_fc_refusal_v1(numeric, text, uuid, text) from public, anon, authenticated;
comment on function security.ops_cost_fc_refusal_v1(numeric, text, uuid, text) is 'CF-247 workstream F (mandate §11): the cost breakers'' Firecrawl refusal (repeat_search, stored_page, ineligible_provider) read by public.svc_fc_spend; each off by its ops_cost.enforce_* switch';

select pg_temp.edit_once('public.svc_fc_spend(numeric,text,uuid,text)', 'd418c451d681ffd95134f5f4dcf7c504', 'a9217c5af8e0da8ee18b03bcab9eaeef', array[
 array[$o$  elsif p_provider_id is not null and p_purpose in ('sch_map', 'sch_search') and not security.fc_sch_eligible_v1(p_provider_id) then$o$,
       $n$  -- CF-247 workstream F (P0 AI operations §11): the cost breakers (repeat search, stored page, ineligible provider); each off by its own
  -- ops_cost.enforce_* switch, and only while its breaker is tripped. On-demand runs a person started are decided above and never held here.
  elsif security.ops_cost_fc_refusal_v1(p_units, p_purpose, p_provider_id, p_url) is not null then
    v_why := security.ops_cost_fc_refusal_v1(p_units, p_purpose, p_provider_id, p_url);
  elsif p_provider_id is not null and p_purpose in ('sch_map', 'sch_search') and not security.fc_sch_eligible_v1(p_provider_id) then$n$]
]::text[][], array[1]);

select pg_temp.edit_once('security.waste_guard_v1()', '101d6fbf97e3c7d3e5830f762c33107b', '49b86d8c8cac388957761e17b9f2dc28', array[
 array[$o$'flags', security.enrichment_flags_refresh_v1());$o$,
       $n$'flags', security.enrichment_flags_refresh_v1(),
    -- CF-247 workstream F (P0 AI operations §11): the cost and yield waste checks and breakers
    'cost', security.ops_cost_guard_v1());$n$]
]::text[][], array[1]);

-- 6. workstream A's contract: root causes and remedies ----------------------------------------------------------------------------------------
create or replace function security.ops_cost_remedy_breaker_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- action of remedy cost_breaker: re-measures the issue's check and trips its breaker. It refuses or holds only where the check's
-- ops_cost.enforce_* switch is on; with the switch off it reports changed = false, so the controller does not count it as a repair.
declare v_fp text; v_code text; v_m jsonb; v_sw text; v_on boolean; v_was text;
begin
  select i.fingerprint into v_fp from pipeline.integration_issues i where i.id = p_issue;
  v_code := substring(v_fp from '^cost:(cost_[a-z_]+)$');
  if v_code is null then return jsonb_build_object('ok', false, 'changed', false, 'evidence', jsonb_build_object('why', 'not a cost issue', 'fingerprint', v_fp)); end if;
  v_sw := case v_code when 'cost_repeat_search' then 'ops_cost.enforce_repeat_search' when 'cost_paid_stored_page' then 'ops_cost.enforce_stored_page'
                      when 'cost_ineligible_scan' then 'ops_cost.enforce_ineligible' when 'cost_low_conf_loop' then 'ops_cost.enforce_ai_loop_hold'
                      when 'cost_repeat_ai_read' then 'ops_cost.enforce_ai_loop_hold' end;
  v_on := v_sw is not null and security.pipeline_num_v1(v_sw, 0) >= 1;
  v_m := security.ops_cost_waste_v1(null)->'checks'->v_code;
  select b.state into v_was from pipeline.ops_cost_breakers b where b.code = v_code and b.scope_kind = 'global' and b.scope_key = '*';
  insert into pipeline.ops_cost_breakers(code, scope_kind, scope_key, state, tripped_at, checked_at, measure)
  values (v_code, 'global', '*', 'tripped', now(), now(), jsonb_build_object('events', v_m->'events', 'by', 'remedy cost_breaker', 'issue', p_issue))
  on conflict (code, scope_kind, scope_key) do update set state = 'tripped', checked_at = now(),
    tripped_at = case when pipeline.ops_cost_breakers.state <> 'tripped' then now() else pipeline.ops_cost_breakers.tripped_at end;
  return jsonb_build_object('ok', true, 'changed', v_on and coalesce(v_was, 'clear') <> 'tripped',
    'evidence', jsonb_build_object('breaker', v_code, 'switch', v_sw, 'enforced', v_on, 'was', v_was, 'measure', v_m - 'samples',
      'note', case when v_sw is null then 'no breaker refuses this kind of waste; the remedy records it'
                   when not v_on then format('%s is off: the breaker is recorded and nothing is refused or held', v_sw)
                   else 'the breaker refuses or holds this waste from now on' end));
end $function$;
revoke all on function security.ops_cost_remedy_breaker_v1(bigint) from public, anon, authenticated;
comment on function security.ops_cost_remedy_breaker_v1(bigint) is 'CF-247 workstream F: action_fn of remedy cost_breaker (workstream A contract): trips the issue''s cost breaker; changed only when its enforce switch is on';

create or replace function security.ops_cost_remedy_verify_v1(p_issue bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- verify of remedy cost_breaker: the check measured since the latest remedy run started (at least one hour) is below the trip thresholds
declare v_fp text; v_code text; v_since timestamptz; v_h int; v_m jsonb; v_share numeric;
begin
  select i.fingerprint into v_fp from pipeline.integration_issues i where i.id = p_issue;
  v_code := substring(v_fp from '^cost:(cost_[a-z_]+)$');
  if v_code is null then return jsonb_build_object('passed', false, 'measure', '{}'::jsonb, 'evidence', jsonb_build_object('why', 'not a cost issue')); end if;
  select max(r.started_at) into v_since from pipeline.ops_remedy_runs r where r.issue_id = p_issue;
  -- since the latest remedy run started; without one, the hourly guard's window
  v_h := security.pipeline_num_v1('ops_cost.guard_window_hours', 24)::int;
  v_m := security.ops_cost_waste_v1(v_h, v_since)->'checks'->v_code;
  v_share := case when (v_m->>'base_events')::numeric > 0 then 100.0 * (v_m->>'events')::numeric / (v_m->>'base_events')::numeric end;
  return jsonb_build_object('passed', case when v_code = 'cost_ineligible_scan' then jsonb_array_length(coalesce(v_m#>'{detail,heavy_providers}', '[]'::jsonb)) = 0
                                           else (v_m->>'events')::numeric < security.pipeline_num_v1('ops_cost.trip_min_events', 20)
                                                or coalesce(v_share, 0) < security.pipeline_num_v1('ops_cost.trip_min_share', 10) end,
                            'measure', jsonb_build_object('since', coalesce(v_since, now() - make_interval(hours => v_h)), 'events', v_m->'events', 'base_events', v_m->'base_events', 'share_pct', round(v_share, 1),
                                                          'ai_usd', v_m->'ai_usd', 'credits', v_m->'credits'),
                            'evidence', coalesce(v_m->'samples', '[]'::jsonb));
end $function$;
revoke all on function security.ops_cost_remedy_verify_v1(bigint) from public, anon, authenticated;
comment on function security.ops_cost_remedy_verify_v1(bigint) is 'CF-247 workstream F: verify_fn of remedy cost_breaker: the check re-measured since the remedy started is under the trip thresholds';

select security.ops_root_cause_register_v1(c.code, c.spec) from (values
 ('cost_repeat_ai_read', jsonb_build_object('class', 'rule', 'title', 'AI reads identical evidence again',
   'description', 'An AI reader is paid again for a course field (or provider list) whose same stored page content it already answered. The reader picks by missing value, not by "content not yet read".',
   'detect', jsonb_build_object('fn', 'security.ops_cost_waste_v1', 'check', 'cost_repeat_ai_read', 'fingerprint', 'cost:cost_repeat_ai_read'))),
 ('cost_repeat_search', jsonb_build_object('class', 'rule', 'title', 'Paid search repeats a query with no new input',
   'description', 'A paid search sends a query string already paid for: course rows that share a title each send their own search, and a search is sent again after a no-result answer with nothing changed.',
   'detect', jsonb_build_object('fn', 'security.ops_cost_waste_v1', 'check', 'cost_repeat_search', 'fingerprint', 'cost:cost_repeat_search'))),
 ('cost_paid_stored_page', jsonb_build_object('class', 'rule', 'title', 'Paid read of a page already stored',
   'description', 'A paid page read buys an address whose stored copy is younger than ops_cost.stored_page_fresh_hours, instead of using the stored copy.',
   'detect', jsonb_build_object('fn', 'security.ops_cost_waste_v1', 'check', 'cost_paid_stored_page', 'fingerprint', 'cost:cost_paid_stored_page'))),
 ('cost_unbounded_retry', jsonb_build_object('class', 'rule', 'title', 'Retries past the attempt cap',
   'description', 'A lane tries an item more times than its cap (AI course-page matching past waste.retry_max_attempts; course pages read past the cap).',
   'detect', jsonb_build_object('fn', 'security.ops_cost_waste_v1', 'check', 'cost_unbounded_retry', 'fingerprint', 'cost:cost_unbounded_retry'))),
 ('cost_low_conf_loop', jsonb_build_object('class', 'rule', 'title', 'Expensive low-confidence AI loop',
   'description', 'A course field is read by AI ops_cost.loop_min_reads times or more with no value found; the existing "page did not state it" hold covers only five skip wordings.',
   'detect', jsonb_build_object('fn', 'security.ops_cost_waste_v1', 'check', 'cost_low_conf_loop', 'fingerprint', 'cost:cost_low_conf_loop'))),
 ('cost_ineligible_scan', jsonb_build_object('class', 'policy', 'title', 'Spend on a provider known to be ineligible',
   'description', 'Firecrawl credits are spent on a provider for a purpose it is not eligible for (search stopped, scholarship-ineligible, on the search skip list).',
   'detect', jsonb_build_object('fn', 'security.ops_cost_waste_v1', 'check', 'cost_ineligible_scan', 'fingerprint', 'cost:cost_ineligible_scan'))),
 ('cost_ai_ceiling_burst', jsonb_build_object('class', 'capacity', 'title', 'One scheduled bulk run uses most of the AI daily ceiling',
   'description', 'A single scheduled run (the standing gap queue''s enrich_fields work) spends most of budgets.ai_daily_ceiling_usd in one hour, so the rolling 24-hour figure nears the ceiling while other lanes are idle.',
   'detect', jsonb_build_object('fingerprint', 'health:budgets:openrouter_daily', 'fn', 'security.ops_cost_report_v1'))),
 ('cost_fc_plan_below_settings', jsonb_build_object('class', 'policy', 'title', 'Firecrawl plan below the configured daily budget',
   'description', 'The vendor plan (about 5,000 credits a month) is far below firecrawl.daily_budget_total and its shares, so the platform reaches the plan reserve and every page-fetching lane idles. A budget decision, not a fault.',
   'detect', jsonb_build_object('fingerprint', 'health:budgets:firecrawl', 'fn', 'security.ops_cost_report_v1')))
) c(code, spec);

select security.ops_remedy_register_v1('cost_breaker', jsonb_build_object('title', 'Trip the cost breaker for this kind of waste',
  'treats', jsonb_build_array('cost_repeat_ai_read', 'cost_repeat_search', 'cost_paid_stored_page', 'cost_low_conf_loop', 'cost_ineligible_scan'), 'authority', 'auto',
  'action_fn', 'security.ops_cost_remedy_breaker_v1(bigint)', 'verify_fn', 'security.ops_cost_remedy_verify_v1(bigint)',
  'max_attempts_key', 'ops_cost.remedy_max_attempts', 'cooldown_key', 'ops_cost.remedy_cooldown_hours',
  'notes', 'Only pauses or skips: refuses a repeated search, a stored page or an ineligible provider in svc_fc_spend, or holds looping course fields, each only while its ops_cost.enforce_* switch is on. Never raises a budget.'));
select security.ops_remedy_register_v1('cost_result_reuse', jsonb_build_object('title', 'Reuse identical search results and stored answers in the lane (shared fix)',
  'treats', jsonb_build_array('cost_repeat_search', 'cost_repeat_ai_read', 'cost_paid_stored_page', 'cost_unbounded_retry'), 'authority', 'release',
  'notes', 'The lasting fix is in the lanes: course-page search answers every course row with the same query from one paid search; enrich_fields skips content already answered for the field; readers use a stored copy younger than ops_cost.stored_page_fresh_hours; AI page matching honours waste.retry_max_attempts. Engineering release (interface requests from workstream F).'));
select security.ops_remedy_register_v1('cost_budget_decision', jsonb_build_object('title', 'Platform Admin budget decision',
  'treats', jsonb_build_array('cost_ai_ceiling_burst', 'cost_fc_plan_below_settings'), 'authority', 'admin',
  'notes', 'Spending limits are the Platform Admin''s: align firecrawl.daily_budget_total and its shares to the vendor plan, and decide whether the standing gap queue''s AI is spread across the day. The controller never raises a budget.'));

-- 7. the value of a candidate plan step (for workstream D) ------------------------------------------------------------------------------------
create or replace function security.ops_step_value_v1(p_provider uuid, p_step text, p_scope jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 workstream F (mandate §11): what a plan step for one provider is expected to bring and cost, from measured history only.
-- p_step: pages | fields | scholarships | site | adapter. p_scope (optional): {"fields": [...], "course_ids": [...]}.
declare v_days int := security.pipeline_num_v1('ops_cost.history_days', 30)::int; v_since timestamptz;
        v_min int := security.pipeline_num_v1('ops_cost.min_sample', 20)::int;
        v_price numeric := security.pipeline_num_v1('ops_cost.fc_usd_per_credit', 0);
        v_fields text[]; v_courses uuid[];
        v_elig numeric := 0; v_evid numeric := 0; v_rate numeric; v_rate_basis text; v_n bigint; v_ok bigint;
        v_lane text; v_usd_call numeric := 0; v_calls numeric := 0; v_credits numeric := 0; v_ai numeric; v_usd numeric;
        v_prog jsonb; v_retry jsonb; v_exp numeric; v_like text; v_skip text; v_extra jsonb := '{}'::jsonb; v_uc jsonb;
begin
  v_since := now() - make_interval(days => v_days);
  v_fields := array(select jsonb_array_elements_text(coalesce(p_scope->'fields', '[]'::jsonb)));
  v_courses := array(select (jsonb_array_elements_text(coalesce(p_scope->'course_ids', '[]'::jsonb)))::uuid);
  v_uc := security.enrich_unit_costs_v1();  -- the plan builder's own measured credits per unit (30 days)
  if p_step not in ('pages', 'fields', 'scholarships', 'site', 'adapter') then
    raise exception 'ops_step_value_v1: unknown step % (pages, fields, scholarships, site, adapter)', p_step using errcode = '22023';
  end if;

  if p_step = 'pages' then
    v_lane := 'course_match';
    -- eligible: active courses with no bound course page and no search in flight or found
    select count(*) into v_elig from catalogue.courses c
     where c.provider_id = p_provider and c.lifecycle_status = 'active' and (cardinality(v_courses) = 0 or c.id = any (v_courses))
       and not exists (select 1 from pipeline.coverage_course_pages p where p.course_id = c.id and p.status = 'bound')
       and not exists (select 1 from pipeline.course_link_search s where s.course_id = c.id and s.state in ('queued', 'found', 'verified'));
    -- evidence held: a proven page already stored for those courses (no search needed)
    select count(distinct pp.course_id) into v_evid from pipeline.course_page_proofs pp join catalogue.courses c on c.id = pp.course_id
     where c.provider_id = p_provider and pp.proven and c.lifecycle_status = 'active' and (cardinality(v_courses) = 0 or c.id = any (v_courses))
       and not exists (select 1 from pipeline.coverage_course_pages p where p.course_id = c.id and p.status = 'bound');
    -- measured yield: searches settled in the window that found (and verified) a page, the provider's own when it has enough
    select count(*), count(*) filter (where s.state in ('found', 'verified')) into v_n, v_ok from pipeline.course_link_search s
     where s.provider_id = p_provider and s.done_at > v_since and s.state in ('none', 'found', 'verified');
    v_rate_basis := 'provider';
    if v_n < v_min then
      select count(*), count(*) filter (where s.state in ('found', 'verified')) into v_n, v_ok from pipeline.course_link_search s
       where s.done_at > v_since and s.state in ('none', 'found', 'verified');
      v_rate_basis := 'platform';
    end if;
    v_extra := jsonb_build_object('verified_rate', (select round(count(*) filter (where s.state = 'verified')::numeric / nullif(count(*), 0), 4) from pipeline.course_link_search s
                                                     where (v_rate_basis = 'platform' or s.provider_id = p_provider) and s.done_at > v_since and s.state in ('none', 'found', 'verified')));
    v_credits := greatest(v_elig - v_evid, 0) * coalesce((v_uc->>'search_credits_per_course')::numeric, 0);
    v_calls := 0;  -- AI page matching runs only for courses a search leaves unmatched; counted in its own lane
  elsif p_step = 'fields' then
    v_lane := 'enrich_fields';
    -- eligible: missing values a reader can still fill (page_found: a stored page not yet read for it; site_known: a page must be read first)
    select count(*) into v_elig from pipeline.course_attribute_coverage a join catalogue.courses c on c.id = a.course_id
     where a.provider_id = p_provider and c.lifecycle_status = 'active' and a.state in ('page_found', 'site_known')
       and (cardinality(v_fields) = 0 or a.attribute = any (v_fields)) and (cardinality(v_courses) = 0 or a.course_id = any (v_courses))
       and not security.enrich_item_held_v1(a.course_id, a.attribute);
    select count(*) into v_evid from pipeline.course_attribute_coverage a join catalogue.courses c on c.id = a.course_id
     where a.provider_id = p_provider and c.lifecycle_status = 'active' and a.state = 'page_found'
       and (cardinality(v_fields) = 0 or a.attribute = any (v_fields)) and (cardinality(v_courses) = 0 or a.course_id = any (v_courses))
       and not security.enrich_item_held_v1(a.course_id, a.attribute);
    select count(*), count(*) filter (where i.state = 'filled') into v_n, v_ok from pipeline.field_enrich_items i
     where i.provider_id = p_provider and i.updated_at > v_since and i.state in ('filled', 'skipped', 'review', 'failed') and (cardinality(v_fields) = 0 or i.field = any (v_fields));
    v_rate_basis := 'provider';
    if v_n < v_min then
      select count(*), count(*) filter (where i.state = 'filled') into v_n, v_ok from pipeline.field_enrich_items i
       where i.updated_at > v_since and i.state in ('filled', 'skipped', 'review', 'failed') and (cardinality(v_fields) = 0 or i.field = any (v_fields));
      v_rate_basis := 'platform';
    end if;
    v_calls := v_elig;
    -- a value whose page is not stored needs a page read first (one credit a page)
    v_credits := greatest(v_elig - v_evid, 0);
  elsif p_step = 'scholarships' then
    v_lane := 'scholarship_ai';
    select count(*) into v_elig from pipeline.scholarship_page_candidates c
     where c.provider_id = p_provider and c.admitted_at is null and c.admit_status is null and (c.next_read_at is null or c.next_read_at <= now());
    select count(*) into v_evid from pipeline.scholarship_page_candidates c
     where c.provider_id = p_provider and c.admitted_at is null and c.admit_status is null and c.storage_path is not null;
    select count(*), count(*) filter (where c.admitted_at is not null) into v_n, v_ok from pipeline.scholarship_page_candidates c
     where c.provider_id = p_provider and c.read_at > v_since;
    v_rate_basis := 'provider';
    if v_n < v_min then
      select count(*), count(*) filter (where c.admitted_at is not null) into v_n, v_ok from pipeline.scholarship_page_candidates c where c.read_at > v_since;
      v_rate_basis := 'platform';
    end if;
    v_calls := v_elig;
    v_credits := case when exists (select 1 from pipeline.scholarship_discovery_providers d where d.provider_id = p_provider and (d.next_discover_at is null or d.next_discover_at <= now()))
                      then coalesce((v_uc->>'scholarship_credits')::numeric, 0) else greatest(v_elig - v_evid, 0) end;
    v_extra := jsonb_build_object('eligible_for_scholarship_spend', security.fc_sch_eligible_v1(p_provider));
  else
    -- site (map the provider site) and adapter (build a course adapter): one provider-level unit; recovery is the courses still missing a page
    v_lane := case p_step when 'adapter' then 'adapter_builder' else null end;
    select count(*) into v_elig from catalogue.courses c where c.provider_id = p_provider and c.lifecycle_status = 'active'
       and not exists (select 1 from pipeline.coverage_course_pages p where p.course_id = c.id and p.status = 'bound');
    select count(*), count(*) filter (where s->>'status' = 'done') into v_n, v_ok
      from pipeline.enrich_plan_runs r, jsonb_array_elements(r.steps) s
     where r.created_at > v_since and s->>'step' = p_step and s->>'status' in ('done', 'failed', 'stopped')
       and r.provider_id = p_provider;
    v_rate_basis := 'provider';
    if v_n < 1 then
      select count(*), count(*) filter (where s->>'status' = 'done') into v_n, v_ok
        from pipeline.enrich_plan_runs r, jsonb_array_elements(r.steps) s
       where r.created_at > v_since and s->>'step' = p_step and s->>'status' in ('done', 'failed', 'stopped');
      v_rate_basis := 'platform (steps that ended done)';
    end if;
    v_calls := case when p_step = 'adapter' then 1 else 0 end;
    v_credits := coalesce((v_uc->>case p_step when 'adapter' then 'adapter_credits' else 'site_credits' end)::numeric, 0);
    v_evid := (select count(*) from pipeline.coverage_provider_urls u where u.provider_id = p_provider);
  end if;

  v_rate := case when v_n > 0 then round(v_ok::numeric / v_n, 4) else 0 end;
  -- AI US$ per call for the lane, from the ledger (opening rows carry no calls)
  if v_lane is not null then
    select coalesce(sum(l.cost_usd) / nullif(sum(l.calls), 0), 0) into v_usd_call from pipeline.ai_spend_ledger l
     where l.lane = v_lane and l.at > v_since and l.source <> 'opening';
  end if;
  v_ai := round(v_calls * v_usd_call, 4);
  v_usd := v_ai + v_credits * v_price;
  -- expected recovery: eligible records times the measured success rate of the step (for site and adapter, the courses still without a page)
  v_exp := round(v_elig * v_rate, 1);
  -- work already in progress
  select jsonb_build_object(
    'tasks', (select count(*) from pipeline.admin_jobs j where j.state in ('queued', 'running', 'paused') and j.args->>'provider_id' = p_provider::text),
    'plan_step_running', exists (select 1 from pipeline.enrich_plan_runs r, jsonb_array_elements(r.steps) s where r.provider_id = p_provider and r.state in ('queued', 'running')
                                  and s->>'step' = p_step and s->>'status' = 'running'),
    'items_in_flight', case p_step when 'fields' then (select count(*) from pipeline.field_enrich_items i where i.provider_id = p_provider and i.state in ('queued', 'waiting', 'ai', 'leased'))
                                   when 'pages' then (select count(*) from pipeline.course_link_search s where s.provider_id = p_provider and s.state = 'queued')
                                   when 'scholarships' then (select count(*) from pipeline.scholarship_ai_queue q where q.provider_id = p_provider and q.state not in ('done', 'failed'))
                                   else 0 end) into v_prog;
  -- retry spend and the previous failure for this provider and step
  select jsonb_build_object('previous_attempts', count(*), 'failed', count(*) filter (where s->>'status' in ('failed', 'stopped')),
                            'last_failure', (array_agg(coalesce(s->>'note', s#>>'{held,reason}', s#>>'{blocked,reason}', s->>'status') order by r.created_at desc)
                                              filter (where s->>'status' in ('failed', 'stopped')))[1],
                            -- what the runs in which this step failed spent (plan runs record actual spend per run, estimates per step)
                            'spent_usd', coalesce(sum((r.actual->>'usd')::numeric) filter (where s->>'status' in ('failed', 'stopped')), 0),
                            'spent_credits', coalesce(sum((r.actual->>'credits')::numeric) filter (where s->>'status' in ('failed', 'stopped')), 0),
                            'estimated_usd_of_failed_steps', coalesce(sum((s->>'est_usd')::numeric) filter (where s->>'status' in ('failed', 'stopped')), 0))
    into v_retry from pipeline.enrich_plan_runs r, jsonb_array_elements(r.steps) s
   where r.provider_id = p_provider and s->>'step' = p_step and r.created_at > v_since;
  v_like := case when v_elig = 0 then 'none' when v_rate * 100 >= security.pipeline_num_v1('ops_cost.likely_high_pct', 50) then 'high' when v_rate * 100 >= security.pipeline_num_v1('waste.retry_min_yield_pct', 15) then 'medium' else 'low' end;
  v_skip := case when v_elig = 0 then 'no eligible records'
                 when (v_prog->>'plan_step_running')::boolean then 'the same step is already running'
                 when v_exp < 1 then 'expected recovery under one record'
                 when exists (select 1 from pipeline.ops_cost_breakers b where b.code = 'cost_ineligible_scan' and b.scope_kind = 'provider' and b.scope_key = p_provider::text and b.state = 'tripped')
                   then 'the provider''s ineligible-spend breaker is tripped' end;
  return jsonb_build_object(
    'provider_id', p_provider, 'step', p_step, 'scope', p_scope, 'history_days', v_days,
    'expected_eligible', v_elig,
    'expected_recovery', jsonb_build_object('records', v_exp, 'rate', v_rate, 'basis', v_rate_basis, 'sample', v_n, 'succeeded', v_ok) || v_extra,
    'evidence_available', v_evid,
    'estimated_cost', jsonb_build_object('ai_usd', v_ai, 'ai_calls', v_calls, 'ai_usd_per_call', round(v_usd_call, 6), 'ai_lane', v_lane,
                                         'firecrawl_credits', round(v_credits, 1), 'usd_per_credit', v_price, 'usd_total', round(v_usd, 4), 'credits_priced', v_price > 0),
    'likelihood', v_like,
    'in_progress', v_prog,
    'retry', v_retry,
    'value_per_dollar', case when v_usd > 0 then round(v_exp / v_usd, 2) end,
    'value_per_credit', case when v_credits > 0 then round(v_exp / v_credits, 4) end,
    'recommend', case when v_skip is null then 'run' else 'skip' end, 'skip_reason', v_skip);
end $function$;
revoke all on function security.ops_step_value_v1(uuid, text, jsonb) from public, anon, authenticated;
comment on function security.ops_step_value_v1(uuid, text, jsonb) is 'CF-247 workstream F (mandate §11): value estimate of a candidate plan step (eligible, expected recovery from measured yield, evidence held, AI and Firecrawl cost, likelihood, work in progress, retry spend and last failure, value per dollar); read-only; for workstream D''s planner';

-- 8. the efficiency section of the consolidated report (§16) ---------------------------------------------------------------------------------
create or replace function security.ops_cost_report_v1(p_window_hours int default 24) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 workstream F (mandate §16 Efficiency): paid operations and cost, evidence reuse, avoided duplicate reads, useful yield per execution,
-- AI and Firecrawl consumption, cost per verified improvement by lane. Read-only; called by workstream A's ops_report_v1.
declare v_w int := greatest(1, least(coalesce(p_window_hours, 24), 24 * 90));  -- fixed: a window is at most 90 days
        v_since timestamptz; v_price numeric := security.pipeline_num_v1('ops_cost.fc_usd_per_credit', 0);
        v_ai jsonb; v_fc jsonb; v_lanes jsonb; v_reuse jsonb; v_avoid jsonb; v_yield jsonb; v_cons jsonb; v_tot jsonb; v_waste jsonb;
begin
  v_since := now() - make_interval(hours => v_w);
  select coalesce(jsonb_object_agg(lane, jsonb_build_object('usd', round(usd, 4), 'calls', calls)), '{}'::jsonb) into v_ai
    from (select l.lane, sum(l.cost_usd) usd, sum(l.calls) calls from pipeline.ai_spend_ledger l where l.at > v_since and l.source <> 'opening' group by 1) x;
  select coalesce(jsonb_object_agg(purpose, jsonb_build_object('credits', credits, 'calls', calls, 'on_demand_credits', od)), '{}'::jsonb) into v_fc
    from (select u.purpose, sum(u.units) credits, count(*) calls, coalesce(sum(u.units) filter (where u.on_demand_run is not null), 0) od
            from pipeline.coverage_vendor_usage u where u.at > v_since group by 1) x;

  -- verified improvements per lane: values filled (less those withdrawn in the window), pages found and verified, official links filled,
  -- scholarships admitted, fee rows found, matches chosen
  with imp as (
    select 'enrich_fields' lane, (select count(*) from pipeline.field_enrich_items i where i.state = 'filled' and i.updated_at > v_since)
                                 - (select count(*) from pipeline.enrich_value_retractions r where r.retracted_at > v_since) n,
           'values filled by Enrich fields, less values withdrawn' what
    union all select 'course_match', (select count(*) from pipeline.coverage_ai_match m where m.chosen_url is not null and m.decided_at > v_since), 'course pages chosen by AI matching'
    union all select 'course_link_search', (select count(*) from pipeline.course_link_search s where s.state in ('found', 'verified') and s.done_at > v_since), 'course pages found by search'
    union all select 'official_links', (select count(*) from pipeline.course_url_fills f where f.filled_at > v_since and f.retracted_at is null), 'official course links filled and not retracted'
    union all select 'scholarships', (select count(*) from pipeline.scholarship_page_candidates c where c.admitted_at > v_since), 'scholarships admitted'
    union all select 'fee_ai', (select coalesce(sum(q.rows_found), 0) from pipeline.fee_reader_queue q where q.finished_at > v_since), 'fee rows found'
    union all select 'page_reads', (select count(*) from pipeline.coverage_course_pages p where p.read_at > v_since and p.evidence_id is not null), 'course pages read and stored'),
  cost as (
    select 'enrich_fields' lane, coalesce((v_ai#>>'{enrich_fields,usd}')::numeric, 0) usd, 0::numeric credits
    union all select 'course_match', coalesce((v_ai#>>'{course_match,usd}')::numeric, 0), 0
    union all select 'course_link_search', 0, coalesce((v_fc#>>'{course_link_search,credits}')::numeric, 0) + coalesce((v_fc#>>'{fc_search,credits}')::numeric, 0)
    union all select 'official_links', 0, 0
    union all select 'scholarships', coalesce((v_ai#>>'{scholarship_ai,usd}')::numeric, 0),
                     coalesce((v_fc#>>'{sch_map,credits}')::numeric, 0) + coalesce((v_fc#>>'{sch_scrape,credits}')::numeric, 0) + coalesce((v_fc#>>'{sch_search,credits}')::numeric, 0)
    union all select 'fee_ai', coalesce((v_ai#>>'{fee_ai,usd}')::numeric, 0), 0
    union all select 'page_reads', 0, coalesce((v_fc#>>'{scrape,credits}')::numeric, 0) + coalesce((v_fc#>>'{fc_read,credits}')::numeric, 0))
  select jsonb_object_agg(imp.lane, jsonb_build_object('improvements', imp.n, 'what', imp.what, 'ai_usd', round(cost.usd, 4), 'credits', cost.credits,
           'usd_per_improvement', case when imp.n > 0 and cost.usd + cost.credits * v_price > 0 then round((cost.usd + cost.credits * v_price) / imp.n, 4) end,
           'credits_per_improvement', case when imp.n > 0 and cost.credits > 0 then round(cost.credits / imp.n, 2) end,
           'ai_usd_per_improvement', case when imp.n > 0 and cost.usd > 0 then round(cost.usd / imp.n, 5) end))
    into v_lanes from imp join cost using (lane);

  -- evidence reuse: Enrich fields items settled from a stored page or adapter value (no new read) against all settled
  -- sources (live 3 Nov): ai_stored (AI on a stored page), adapter, provider_facts, ai_title, institution_rule reuse held evidence; scraper is a new read
  select jsonb_build_object('settled', count(*), 'with_a_source', count(*) filter (where i.source is not null),
                            'from_stored_evidence', count(*) filter (where i.source is not null and i.source <> 'scraper'),
                            'new_reads', count(*) filter (where i.source = 'scraper'),
                            'share_pct', round(100.0 * count(*) filter (where i.source is not null and i.source <> 'scraper') / nullif(count(*) filter (where i.source is not null), 0), 1))
    into v_reuse from pipeline.field_enrich_items i where i.updated_at > v_since and i.state in ('filled', 'skipped', 'review');
  v_reuse := v_reuse || jsonb_build_object('by_source', (select coalesce(jsonb_object_agg(src, n), '{}'::jsonb) from (select coalesce(i.source, 'none') src, count(*) n
                         from pipeline.field_enrich_items i where i.updated_at > v_since and i.state in ('filled', 'skipped', 'review') group by 1) z));
  -- avoided duplicate reads: spends the platform refused as duplicates or not due, and course fields held as already read without a value
  select jsonb_build_object(
    'refused_spends', coalesce((select jsonb_object_agg(reason, n) from (select r.reason, sum(r.n) n from pipeline.firecrawl_budget_refusals r
                                 where r.last_at > v_since and r.reason in ('repeat_search', 'stored_page', 'ineligible_provider', 'not_due', 'search_stopped', 'not_eligible', 'university_cap')
                                 group by 1) z), '{}'::jsonb),
    'course_fields_held', (select count(*) from pipeline.enrichment_flags f where f.entity = 'course' and f.reason_code = 'enrich_no_value' and f.state in ('raised', 'counting')),
    'course_fields_held_by_cost_guard', (select count(*) from pipeline.enrichment_flags f where f.entity = 'course' and f.reason_code = 'enrich_no_value' and f.state in ('raised', 'counting') and f.source = 'ops-cost-guard'))
    into v_avoid;
  -- useful yield per execution: worker calls and items done per mode
  select coalesce(jsonb_object_agg(mode, jsonb_build_object('calls', calls, 'items_ok', ok, 'failed', failed, 'ok_per_call', round(ok::numeric / nullif(calls, 0), 2))), '{}'::jsonb) into v_yield
    from (select l.mode, count(*) calls, coalesce(sum(l.ok), 0) ok, coalesce(sum(l.failed), 0) failed from pipeline.mode_outcome_ledger l where l.run_at > v_since group by 1) x;
  -- consumption against the limits in force (read, never changed)
  select jsonb_build_object(
    'ai_usd_window', (select round(coalesce(sum(l.cost_usd), 0), 4) from pipeline.ai_spend_ledger l where l.at > v_since and l.source <> 'opening'),
    'ai_usd_today_utc', (select round(coalesce(sum(x.spent), 0), 4) from security.ai_spend_today_v1() x),
    'ai_daily_ceiling_usd', security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14),
    'openrouter_balance_usd', (select o.remaining_usd from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1),
    'firecrawl_credits_window', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.at > v_since),
    'firecrawl_daily_budget_total', security.fc_setting_num_v1('daily_budget_total', 0),
    'firecrawl_month_refusal', security.fc_month_refusal_v1(1)) into v_cons;
  select jsonb_build_object('ai_usd', round(coalesce(sum(l.cost_usd), 0), 4)) into v_tot from pipeline.ai_spend_ledger l where l.at > v_since and l.source <> 'opening';
  v_tot := v_tot || jsonb_build_object('credits', (v_cons->>'firecrawl_credits_window')::numeric,
    'improvements', (select coalesce(sum((v->>'improvements')::numeric), 0) from jsonb_each(v_lanes) e(k, v) where k <> 'official_links' and k <> 'page_reads'));
  v_tot := v_tot || jsonb_build_object('ai_usd_per_improvement', case when (v_tot->>'improvements')::numeric > 0 then round((v_tot->>'ai_usd')::numeric / (v_tot->>'improvements')::numeric, 5) end,
                                       'credits_per_improvement', case when (v_tot->>'improvements')::numeric > 0 then round((v_tot->>'credits')::numeric / (v_tot->>'improvements')::numeric, 2) end);
  -- the latest hourly waste measures
  select coalesce(jsonb_object_agg(m.check_code, jsonb_build_object('at', m.measured_at, 'window_hours', m.window_hours, 'events', m.events, 'share_pct', m.share_pct,
                                   'ai_usd', round(m.ai_usd, 4), 'credits', m.credits)), '{}'::jsonb) into v_waste
    from (select distinct on (check_code) * from pipeline.ops_cost_waste_measures order by check_code, measured_at desc) m;
  return jsonb_build_object('window_hours', v_w, 'at', now(), 'usd_per_credit', v_price,
    'paid_operations', jsonb_build_object('ai_by_lane', v_ai, 'firecrawl_by_purpose', v_fc),
    'evidence_cache_reuse', v_reuse, 'avoided_duplicate_reads', v_avoid, 'useful_yield_per_execution', v_yield, 'consumption', v_cons,
    'cost_per_verified_improvement', jsonb_build_object('by_lane', v_lanes, 'total', v_tot),
    'waste_latest', v_waste,
    'breakers', (select coalesce(jsonb_agg(jsonb_build_object('code', b.code, 'scope', b.scope_kind, 'key', b.scope_key, 'since', b.tripped_at)), '[]'::jsonb)
                   from pipeline.ops_cost_breakers b where b.state = 'tripped'));
end $function$;
revoke all on function security.ops_cost_report_v1(int) from public, anon, authenticated;
comment on function security.ops_cost_report_v1(int) is 'CF-247 workstream F (mandate §16 Efficiency): paid operations and cost, evidence reuse, avoided duplicate reads, yield per execution, consumption, cost per verified improvement by lane; read-only; for workstream A''s ops_report_v1';

-- 9. housekeeping: catalogue line for the existing job, component register ---------------------------------------------------------------------
update pipeline.automation_catalogue set description = description || ' Then the cost and yield checks (security.ops_cost_guard_v1): repeated AI reads, repeated searches, paid reads of stored pages, retries past the cap, low-confidence loops and ineligible providers are measured, their breakers tripped or cleared and integration issues cost:<check> opened or cleared; nothing is refused or held unless its ops_cost.enforce_* switch is on.'
 where jobname = 'waste-guard' and description not like '%ops_cost_guard_v1%';
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.ops_cost_waste_measures', 'Platform', 'Cost and yield: hourly waste measures', 'active', '{}', '20261104050000'),
 ('table', 'pipeline.ops_cost_breakers', 'Platform', 'Cost and yield: circuit breaker state', 'active', '{}', '20261104050000'),
 ('function', 'security.ops_cost_waste_v1', 'Platform', 'Cost and yield: the six waste checks', 'active', '{}', '20261104050000'),
 ('function', 'security.ops_cost_guard_v1', 'Platform', 'Cost and yield: hourly guard in job waste-guard', 'active', '{}', '20261104050000'),
 ('function', 'security.ops_cost_loop_hold_v1', 'Platform', 'Cost and yield: hold looping course fields (switch off)', 'active', '{}', '20261104050000'),
 ('function', 'security.ops_cost_fc_refusal_v1', 'Platform', 'Cost and yield: Firecrawl breakers read by svc_fc_spend (switches off)', 'active', '{}', '20261104050000'),
 ('function', 'security.ops_cost_remedy_breaker_v1', 'Platform', 'Cost and yield: remedy cost_breaker action', 'active', '{}', '20261104050000'),
 ('function', 'security.ops_cost_remedy_verify_v1', 'Platform', 'Cost and yield: remedy cost_breaker verify', 'active', '{}', '20261104050000'),
 ('function', 'security.ops_step_value_v1', 'Platform', 'Cost and yield: value of a candidate plan step (for workstream D)', 'active', '{}', '20261104050000'),
 ('function', 'security.ops_cost_report_v1', 'Platform', 'Cost and yield: §16 efficiency report (for workstream A)', 'active', '{}', '20261104050000')
on conflict do nothing;
