-- CF-247 F-OPS.01/.06 (Platform Admin 10 Nov 2026 19:47, "Restore autonomous operation", IQ-00355): the hourly automatic enrichment planner (job enrich-plan-auto, security.enrich_plan_auto_v1) fails by statement time-out (120 s) and creates no new plans.
--
-- Evidence (project fxcwkweaxjtknorudmwp, SELECT only, 10 Nov 2026 ~20:00 AEDT). The job failed at 18:41 and 19:41 AEDT with "canceling statement due to statement timeout" inside security.enrich_unit_costs_v1 (called by security.enrich_plan_v1); its last successful run was 12:41 AEDT (run 164: considered 51, created 1). The
-- planner looks at up to plans.auto_per_run x 3 universities a run and security.enrich_plan_v1 calls enrich_unit_costs_v1 once for each. That function applied security.fc_purpose_group_v1 to every one of the ~112,000 pipeline.coverage_vendor_usage rows of the 30-day window (10.7 s for the scan alone on a warm cache, 7.6 s for
-- the whole function); aggregated by purpose and provider first it reads the same rows in 0.35 s. The usage table grew with the Firecrawl reads of the last week, so the sum over a run of 51 universities passed 120 s. Executors (enrich-plan-run, every five minutes) kept succeeding because they only consume plans that already exist.
--
-- What this changes: security.enrich_unit_costs_v1 only. The usage rows are summed per purpose and provider first; the purpose group is then worked out on those few rows. The same seven figures are returned (compared to the live function on the same data before this change: identical text). No setting, threshold, window or
-- plan rule changes; the 30-day window stays as marked "-- fixed: estimate window". The other callers (admin_enrich_plan, enrich_fields_estimate_v1, cdesc_on_demand_v1, ops_step_value_v1) get the same figures faster.
-- Live definition this change edits (pg_proc.prosrc md5, read 10 Nov 2026), before -> after (the migration stops, and applies nothing, if the live body is neither):
--   security.enrich_unit_costs_v1()   f10198f02de958119baefd490931c258 -> 00d1b42bc96af737982c3ba77a384036
-- Replaces: the body of security.enrich_unit_costs_v1 is replaced in place (md5-guarded); the per-row purpose-group scan of the 30-day usage window is replaced by one aggregation
-- Retires: nothing
-- Nothing is dropped or deleted by this migration. No plan, setting or row is changed by applying it. Forward recovery (restores the previous body byte for byte): supabase/held/planner_unit_costs_forward_recovery.sql

do $g$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.enrich_unit_costs_v1()'::regprocedure);
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = '00d1b42bc96af737982c3ba77a384036' then raise notice 'security.enrich_unit_costs_v1(): already applied'; return; end if;
  if md5(v_src) <> 'f10198f02de958119baefd490931c258' then raise exception 'live security.enrich_unit_costs_v1() differs from the definition this change replaces (body md5 %)', md5(v_src); end if;
  execute $ddl$
create or replace function security.enrich_unit_costs_v1()
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- what each kind of step actually used, last 30 days (estimates follow the platform, nothing is typed in)
  -- 10 Nov 2026 (IQ-00355): the usage rows are summed per purpose and provider FIRST and the purpose group is worked out on those few rows, not on every one of
  -- the ~110,000 rows of the window (the same figures, about thirty times faster); the automatic planner calls this once for every university it looks at
  with a as (select x.purpose, x.provider_id, sum(x.units) units, count(*) n from pipeline.coverage_vendor_usage x where x.at > now() - interval '30 days' group by x.purpose, x.provider_id),  -- fixed: estimate window
       u as (select security.fc_purpose_group_v1(a.purpose) g, a.purpose, a.units, a.n, a.provider_id from a)
  select jsonb_build_object(
    'site_credits', round(coalesce((select sum(units) / nullif(count(distinct provider_id), 0) from u where g in ('other', 'central')), 0), 1),
    'search_credits_per_course', round(coalesce((select sum(units) / nullif(sum(n), 0) from u where purpose = 'course_link_search'), 0), 2),
    'adapter_credits', round(coalesce((select sum(units) / nullif(count(distinct provider_id), 0) from u where g = 'reads'), 0), 1),
    'scholarship_credits', round(coalesce((select sum(units) / nullif(count(distinct provider_id), 0) from u where g = 'scholarships'), 0), 1),
    'enrich_usd_per_item', coalesce((select round(avg(coalesce(e.cost_usd, 0)), 5) from pipeline.field_enrich_items e where e.updated_at > now() - interval '30 days' and e.state in ('filled', 'skipped', 'review', 'failed')), 0),
    'adapter_usd', coalesce((select round(sum(d.cost_usd) / nullif(count(distinct d.provider_id), 0), 4) from pipeline.uni_adapter_drafts d where d.created_at > now() - interval '30 days'), 0),
    'scholarship_usd', coalesce((select round(sum(s.cost_usd) / nullif(count(distinct s.provider_id), 0), 4) from pipeline.scholarship_ai_extractions s where s.at > now() - interval '30 days'), 0))
$function$
$ddl$;
  v_src := (select p.prosrc from pg_proc p where p.oid = 'security.enrich_unit_costs_v1()'::regprocedure);
  if md5(v_src) <> '00d1b42bc96af737982c3ba77a384036' then raise exception 'security.enrich_unit_costs_v1() after the replacement has body md5 %, expected 00d1b42bc96af737982c3ba77a384036', md5(v_src); end if;
end $g$;
