-- CF-247 StudySearch: budget enforcement (AI and Firecrawl) and an external alert watchdog. Platform Admin consolidated decision pack,
-- 2 Nov 2026 10:56, Decision 5: E-7 (AI budget enforcement), E-8 (Firecrawl F2), E-9 (W1 watchdog); E-6 U1 is a screen label only.
-- Admin docs/platform/nz-enrichment-brief/2026-11-02-consolidated-decision-pack-1056.md; RECOVERY-RUNBOOK.md appendices C and D.
-- Why (verified live, read-only, 2 Nov 2026 11:05-11:27 AEDT):
--   E-7. security.ai_use_allowed_v1 (stop mode only; live mode 'observe') checks the credit floor and one lane's guard. It never reads the
--        aggregate ceiling (budgets.ai_daily_ceiling_usd, US$14); the lane guards add up to US$67. Two paid lanes ask no one: AI course-page
--        matching (job coverage-ai-match, every minute, straight to the worker; claim public.svc_coverage_ai_match_next) and adapter proposals
--        (public.admin_adapter_builder 'propose'). The floor refuses only below it, not at it. Spend accounting (security.ai_spend_today_v1)
--        dates each row's lifetime cost by its last change (enrichment items and entry-matrix runs by updated_at), so a cost spent on an
--        earlier day is counted again on the day the row is touched; a re-decided course match overwrites its earlier cost; and the
--        scholarship re-check's cost (pipeline.scholarship_ai_reviews.recheck.cost_usd) is not counted at all.
--   E-8. The monthly Firecrawl limit (security.layer2_provider_budget_status) is read by the Layer 2 runner and, as a snapshot taken at the
--        start of each worker call, by the worker. The database checks every spend against the day only: security.fc_budget_left_v1 and
--        public.svc_fc_spend (including its on-demand branch) never read the month, and adapter page captures (admin_adapter_builder
--        'start' and 'add_sample', mode adapter_capture) check nothing before spending.
--        Month boundary: layer2_provider_budget_status counts from date_trunc('month', now()) in the session time zone (UTC; the function
--        does not pin it), so the counted month is the UTC calendar month. The vendor period runs from the 2nd (billing_config.plan_note
--        "period 2 Oct to 2 Nov 2026"). The vendor's own balance, read every 15 minutes, overrides the count whenever it is under 2 hours
--        old, so the vendor period governs while the balance reader works; the UTC month count is only the fall-back.
--   E-9. Nothing outside the platform notices when pg_cron, platform-health, platform-alerts or the alert-collecting task stop.
-- What:
--   * pipeline.ai_spend_ledger: one row per recorded AI cost, written by triggers on the eight tables the lanes record cost in (the
--     increase of an accumulated cost; for a course match, the cost of each decision of a leased item). Spend today is the ledger's UTC
--     day, so a cost is counted once, on the day it was recorded, whatever happens to its row later. An opening row per lane carries
--     today's spend as counted before this change (first application only).
--   * security.ai_spend_today_v1 (guarded replacement, same columns): reads the ledger.
--   * security.ai_use_refusal_v1 (new): in stop mode the reason an AI use is refused, or null: the credit balance less the spend recorded
--     since it was read is at or below openrouter.credit_floor_usd; or today's spend across all lanes has reached
--     budgets.ai_daily_ceiling_usd; or the lane's own guard is reached. Observe mode never refuses.
--     security.ai_use_allowed_v1 (guarded replacement, same signature) answers "no reason". security.ai_use_refuse_v1 raises it for a person.
--   * The two unguarded lanes now ask: public.svc_coverage_ai_match_next claims nothing when course_match is refused;
--     public.admin_adapter_builder 'propose' raises the refusal. A claim already made finishes and records its cost; only new claims stop.
--   * security.fc_month_refusal_v1 (new): the monthly plan limit for Firecrawl (provider found by key), as layer2_provider_budget_status
--     decides it: the vendor balance under 2 hours old less use since, otherwise the counted month. security.fc_budget_left_v1 returns 0
--     and public.svc_fc_spend refuses ('month_limit', recorded with the other refusals) before any daily or on-demand rule;
--     admin_adapter_builder refuses a page capture (security.fc_month_refuse_v1). The daily allowance and its shares are unchanged.
--   * security.platform_watchdog_v1 (new, read-only): platform-health and platform-alerts are active and ran in the last
--     alerts.watchdog_stale_minutes, their last runs did not fail, and no alert has waited longer than alerts.collect_within_minutes.
--     Executable by the read-only role, for the hourly GitHub workflow .github/workflows/platform-watchdog.yml.
-- Replaces: security.ai_use_allowed_v1, security.ai_spend_today_v1, public.svc_coverage_ai_match_next, public.admin_adapter_builder, security.fc_budget_left_v1, public.svc_fc_spend (same names; md5-guarded edits)
-- Retires: nothing
-- No setting value is changed: openrouter stays in 'observe'; credit_floor_usd stays US$5 (US$10 is proposed to the Platform Admin); the
-- ceiling, the guards, the Firecrawl plan and the daily allowance keep their values. Help and used_by lines are corrected only.
-- Nothing dropped, deleted or renamed. No job or schedule change. Consumer API untouched (G3).

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

-- a whole definition replaced, only from the definition it was written against
create or replace function pg_temp.replace_once(p_sig text, p_before text, p_after text, p_def text) returns text language plpgsql as $f$
begin
  if md5(pg_get_functiondef(p_sig::regprocedure)) = p_after then return p_sig || ': already applied'; end if;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_before then
    raise exception 'live % differs from the definition this change replaces (md5 %)', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)); end if;
  execute p_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the replacement has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after; end if;
  return p_sig || ': applied';
end $f$;

-- 0. the definitions read by the new functions are the ones they were written from (not changed here)
do $g$
begin
  if md5(pg_get_functiondef('security.layer2_provider_budget_status(uuid,numeric)'::regprocedure)) <> '30267f08ebf396738f2a83d72b853c78' then
    raise exception 'live security.layer2_provider_budget_status differs from the rule security.fc_month_refusal_v1 mirrors'; end if;
  if md5(pg_get_functiondef('public.svc_coverage_ai_match_record(bigint,text,jsonb,text,numeric,text)'::regprocedure)) <> 'b468dcaaaf6cb9494eb1e5e906464c94' then
    raise exception 'live public.svc_coverage_ai_match_record differs from the recorder the course_match ledger trigger was written for'; end if;
end $g$;

-- 1. settings (G2): two new; help and used_by corrected on four (values untouched) -----------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'alerts.watchdog_stale_minutes', 'Watchdog: alert jobs must have run within',
  'The hourly GitHub watchdog fails (and GitHub e-mails the repository owner) when platform-health or platform-alerts has not started within this many minutes, is switched off, or its last run failed. Both run every 10 minutes.',
  'number', to_jsonb(30), 10, 180, 'minutes', 975, 'Alerts', 'security.platform_watchdog_v1; .github/workflows/platform-watchdog.yml',
  'Decision 5 E-9 W1 (Platform Admin 2 Nov 2026 10:56): external hourly watchdog'),
 ('pipeline', 'alerts.watchdog_scan_runs', 'Watchdog: scheduler runs looked through',
  'The watchdog finds each alert job''s last run among this many of the newest scheduler runs (all jobs), so its read stays small. Keep it above the runs of all jobs in the stale window (about 1,200 in 30 minutes).',
  'number', to_jsonb(20000), 1000, 200000, 'runs', 976, 'Alerts', 'security.platform_watchdog_v1',
  'Decision 5 E-9 W1 (Platform Admin 2 Nov 2026 10:56): a bounded read of cron.job_run_details')
on conflict (toolset_key, key) do nothing;

update pipeline.platform_toolset_settings set
  help = 'In Stop at limits, every AI use is refused while the OpenRouter balance, less the spend recorded since it was read, is at or below this amount. Observe only never refuses. Proposed: US$10 (equal to target T2).',
  used_by = 'security.ai_use_refusal_v1 (every AI lane)'
 where toolset_key = 'openrouter' and key = 'credit_floor_usd';
update pipeline.platform_toolset_settings set
  help = 'Spend in a UTC day by AI course-page matching (job coverage-ai-match). In Stop at limits, no new matches are claimed once reached; matches already claimed finish.',
  used_by = 'security.ai_use_refusal_v1 via public.svc_coverage_ai_match_next'
 where toolset_key = 'openrouter' and key = 'guard_course_match';
update pipeline.platform_toolset_settings set
  help = 'Spend in a UTC day by AI adapter proposals. In Stop at limits, a new proposal is refused once reached. Proposals also stop at the Adapter builder''s own daily allowance.',
  used_by = 'security.ai_use_refusal_v1 via public.admin_adapter_builder (propose)'
 where toolset_key = 'openrouter' and key = 'guard_adapter_builder';
update pipeline.platform_toolset_settings set
  help = 'All AI spend recorded in a UTC day, every lane together. In Stop at limits (OpenRouter), every AI use is refused once reached; work already claimed finishes. The health check also warns at 80% and is critical at the ceiling (measured from the credit balance over 24 hours).',
  used_by = 'security.ai_use_refusal_v1 (every AI lane, stop mode); security.platform_health_check_v1 (budgets check); security.ops_scorecard_v1'
 where toolset_key = 'pipeline' and key = 'budgets.ai_daily_ceiling_usd';

-- 2. the AI spend ledger ---------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.ai_spend_ledger(
  id bigserial primary key,
  at timestamptz not null default now(),
  lane text not null,
  source text not null,
  source_id text,
  cost_usd numeric not null check (cost_usd > 0),
  calls int not null default 1);
create index if not exists ai_spend_ledger_at_idx on pipeline.ai_spend_ledger (at);
comment on table pipeline.ai_spend_ledger is 'Decision 5 E-7 (2 Nov 2026): one row per recorded AI cost (OpenRouter), by lane, written by triggers on the tables the lanes record cost in (security.ai_spend_capture_v1). Spend today, the daily ceiling, the lane guards and the credit-floor estimate read it. Rows with source ''opening'' carry the spend counted before the ledger existed on the day it was added.';
revoke all on pipeline.ai_spend_ledger from public, anon, authenticated;

-- opening rows: today's spend as counted before this change, on the first application only (while the old definition is live)
insert into pipeline.ai_spend_ledger(lane, source, cost_usd, calls)
select s.use, 'opening', s.spent, s.calls::int from security.ai_spend_today_v1() s
 where s.spent > 0 and md5(pg_get_functiondef('security.ai_spend_today_v1()'::regprocedure)) = 'f18af72fe3d406341931a5daaa93f987';

create or replace function security.ai_spend_capture_v1() returns trigger
language plpgsql security definer set search_path to '' as $$
-- Decision 5 E-7 (2 Nov 2026): records the AI cost a row gains. tg_argv: lane, how ('delta' = the increase of an accumulated cost;
-- 'decision' = the cost of each decision of a leased item, as svc_coverage_ai_match_record overwrites it), the path of the cost in the row.
declare v_new jsonb := to_jsonb(new); v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end; v_path text[] := tg_argv[2]::text[];
        v_add numeric;
begin
  if tg_argv[1] = 'decision' then
    if tg_op = 'UPDATE' and not (v_old->>'state' = 'leased' and v_new->>'state' <> 'leased'
                                 and (v_new->>'decided_at') is distinct from (v_old->>'decided_at')) then return null; end if;
    v_add := coalesce((v_new #>> v_path)::numeric, 0);
  else
    v_add := coalesce((v_new #>> v_path)::numeric, 0) - coalesce((v_old #>> v_path)::numeric, 0);
  end if;
  if v_add > 0 then
    insert into pipeline.ai_spend_ledger(lane, source, source_id, cost_usd) values (tg_argv[0], tg_table_name, v_new->>'id', v_add);
  end if;
  return null;
end $$;
revoke all on function security.ai_spend_capture_v1() from public, anon, authenticated;
comment on function security.ai_spend_capture_v1() is 'Decision 5 E-7 (2 Nov 2026): writes pipeline.ai_spend_ledger from the eight AI cost tables';

create or replace trigger ai_spend_capture after insert or update of cost_usd on pipeline.scholarship_ai_extractions
  for each row execute function security.ai_spend_capture_v1('scholarship_ai', 'delta', '{cost_usd}');
create or replace trigger ai_spend_capture after insert or update of recheck on pipeline.scholarship_ai_reviews
  for each row execute function security.ai_spend_capture_v1('scholarship_ai', 'delta', '{recheck,cost_usd}');
create or replace trigger ai_spend_capture after insert or update of cost_usd on pipeline.uni_adapter_drafts
  for each row execute function security.ai_spend_capture_v1('adapter_builder', 'delta', '{cost_usd}');
create or replace trigger ai_spend_capture after insert or update of cost_usd on pipeline.central_ai_queue
  for each row execute function security.ai_spend_capture_v1('central_ai', 'delta', '{cost_usd}');
create or replace trigger ai_spend_capture after insert or update of decided_at on pipeline.coverage_ai_match
  for each row execute function security.ai_spend_capture_v1('course_match', 'decision', '{cost_usd}');
create or replace trigger ai_spend_capture after insert or update of cost_usd on pipeline.field_enrich_items
  for each row execute function security.ai_spend_capture_v1('enrich_fields', 'delta', '{cost_usd}');
create or replace trigger ai_spend_capture after insert or update of cost_usd on pipeline.fee_reader_queue
  for each row execute function security.ai_spend_capture_v1('fee_ai', 'delta', '{cost_usd}');
create or replace trigger ai_spend_capture after insert or update of cost_usd on pipeline.entry_matrix_runs
  for each row execute function security.ai_spend_capture_v1('entry_matrix', 'delta', '{cost_usd}');

-- 3. spend today from the ledger (same columns) ----------------------------------------------------------------------------------------
select pg_temp.replace_once('security.ai_spend_today_v1()', 'f18af72fe3d406341931a5daaa93f987', '0b79a7f732669ee4c59a260e26188d5a', $def$
create or replace function security.ai_spend_today_v1() returns table(use text, label text, spent numeric, guard numeric, calls bigint)
language sql stable security definer set search_path to '' as $function$
  -- Decision 5 E-7 (2 Nov 2026): the AI cost recorded today, from pipeline.ai_spend_ledger, so each cost counts once, on the day it was
  -- recorded (it was each row's whole cost, dated by the row's last change; the scholarship re-check was not counted)
  with d as (select (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') t),  -- fixed: the UTC day the OpenRouter guards count
  s as (select x.lane u, sum(x.cost_usd) spent, sum(x.calls) calls from pipeline.ai_spend_ledger x, d where x.at >= d.t group by x.lane)
  select l.u, l.label, round(coalesce(s.spent, 0), 4), (security.toolset_setting('openrouter', 'guard_' || l.u))::text::numeric, coalesce(s.calls, 0)::bigint
    from (values ('scholarship_ai', 'Read scholarship pages with AI', 1), ('adapter_builder', 'Adapter proposals', 2), ('central_ai', 'Central pages with AI', 3),
                 ('course_match', 'AI course-page matching', 4), ('enrich_fields', 'Enrich fields with AI', 5), ('fee_ai', 'Fee reader with AI', 6), ('entry_matrix', 'Entry matrices with AI', 7)) l(u, label, sort)
    left join s on s.u = l.u
   order by l.sort
$function$;
$def$);

-- 4. one refusal rule for every AI lane --------------------------------------------------------------------------------------------------
create or replace function security.ai_use_refusal_v1(p_use text) returns text
language plpgsql stable security definer set search_path to '' as $$
-- Decision 5 E-7 (2 Nov 2026): why an AI use is refused now, or null. Only in Stop at limits (pipeline.platform_toolsets 'openrouter');
-- Observe only never refuses. Checked before work is claimed or fired, never during a call: what is claimed finishes and records its cost.
declare v_mode text; v_bal numeric; v_at timestamptz; v_floor numeric; v_ceiling numeric; v_total numeric; g record;
begin
  select t.enforcement into v_mode from pipeline.platform_toolsets t where t.key = 'openrouter';
  if coalesce(v_mode, 'observe') <> 'stop' then return null; end if;
  -- the credit floor: the latest balance (read every 15 minutes) less the spend recorded since; at or below the floor is refused
  select o.remaining_usd, o.observed_at into v_bal, v_at from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  if v_bal is not null then
    v_bal := v_bal - coalesce((select sum(l.cost_usd) from pipeline.ai_spend_ledger l where l.at > v_at and l.source <> 'opening'), 0);
    if v_bal <= v_floor then
      return format('credit floor: balance about US$%s, at or below the floor of US$%s (openrouter.credit_floor_usd)', round(v_bal, 2), v_floor);
    end if;
  end if;
  -- the daily ceiling: every lane together, today (UTC)
  v_ceiling := security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14);
  select coalesce(sum(x.spent), 0) into v_total from security.ai_spend_today_v1() x;
  if v_ceiling > 0 and v_total >= v_ceiling then
    return format('daily ceiling: US$%s spent today (UTC) across all AI lanes, ceiling US$%s (budgets.ai_daily_ceiling_usd)', v_total, v_ceiling);
  end if;
  -- the lane's own guard (0 = no guard)
  select * into g from security.ai_spend_today_v1() x where x.use = p_use;
  if coalesce(g.guard, 0) > 0 and coalesce(g.spent, 0) >= g.guard then
    return format('lane guard: %s spent US$%s today (UTC), guard US$%s (openrouter.guard_%s)', p_use, g.spent, g.guard, p_use);
  end if;
  return null;
end $$;
revoke all on function security.ai_use_refusal_v1(text) from public, anon, authenticated;
comment on function security.ai_use_refusal_v1(text) is 'Decision 5 E-7 (2 Nov 2026): the reason an AI use is refused in stop mode (credit floor, daily ceiling, lane guard), or null';

create or replace function security.ai_use_refuse_v1(p_use text) returns void
language plpgsql stable security definer set search_path to '' as $$
declare v text := security.ai_use_refusal_v1(p_use);
begin
  -- Decision 5 E-7 (2 Nov 2026): for an action a person starts: the refusal, in words
  if v is not null then raise exception 'AI spending is stopped for now (%). Models & services › Toolsets & limits', v; end if;
end $$;
revoke all on function security.ai_use_refuse_v1(text) from public, anon, authenticated;
comment on function security.ai_use_refuse_v1(text) is 'Decision 5 E-7 (2 Nov 2026): raises security.ai_use_refusal_v1 for an action a person starts';

select pg_temp.replace_once('security.ai_use_allowed_v1(text)', '201f93054b167c78462086372d64c369', '07b6387d6a30be8a0f86b90b602b6d08', $def$
create or replace function security.ai_use_allowed_v1(p_use text) returns boolean
language plpgsql stable security definer set search_path to '' as $function$
begin
  -- Decision 5 E-7 (2 Nov 2026): one rule for every lane (credit floor, daily ceiling, lane guard), in security.ai_use_refusal_v1
  return security.ai_use_refusal_v1(p_use) is null;
end $function$;
$def$);

-- 5. the two lanes that asked no one -----------------------------------------------------------------------------------------------------
select pg_temp.edit_once('public.svc_coverage_ai_match_next(integer)', 'e40e9847068ccf4b7e6e1244a31c2cee', '5a8176270c18994ef3564a5f59a9ff60', array[
 array[$o$then raise exception 'service_role required'; end if;$o$,
       $n$then raise exception 'service_role required'; end if; if not security.ai_use_allowed_v1('course_match') then return '[]'::jsonb; end if;  -- Decision 5 E-7 (2 Nov 2026): nothing new is claimed while AI use is refused$n$]],
 array[1]);

-- admin_adapter_builder: a proposal asks the AI rule; a page capture asks the Firecrawl month (both raise, so nothing is recorded or sent)
select pg_temp.edit_once('public.admin_adapter_builder(text,jsonb)', '23c611e79c25ab1663f65fcea709b202', '62e93d40ff0616e87a8960d2d29a2b21', array[
 array[$o$v_m := security.adapter_builder_model_for_v1(v_d.provider_id);$o$,
       $n$perform security.ai_use_refuse_v1('adapter_builder');  -- Decision 5 E-7 (2 Nov 2026)
    v_m := security.adapter_builder_model_for_v1(v_d.provider_id);$n$],
 array[$o$perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_capture', 'draft_id', v_id));$o$,
       $n$perform security.fc_month_refuse_v1(1);  -- Decision 5 E-8 F2 (2 Nov 2026): a capture spends Firecrawl credits
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_capture', 'draft_id', v_id));$n$]],
 array[1, 2]);

-- 6. Firecrawl: one monthly limit on every path ----------------------------------------------------------------------------------------
create or replace function security.fc_month_refusal_v1(p_units numeric) returns text
language plpgsql stable security definer set search_path to '' as $$
-- Decision 5 E-8 F2 (2 Nov 2026): why a Firecrawl spend of p_units is refused by the monthly plan limit, or null. The rule is
-- security.layer2_provider_budget_status's: the vendor's balance read in the last 2 hours less the platform's use since (the vendor's own
-- billing period, from the 2nd), otherwise the counted UTC calendar month; refused when what is left after this spend is under
-- billing_config.stop_at_vendor_units_remaining. With a fresh balance it is computed here without the month count, which that function
-- also works out (a whole month of use on every spend); without one, that function answers.
declare p pipeline.layer2_acquisition_providers%rowtype; v_stop numeric; v_unit numeric; v_rem numeric; v_at timestamptz; st jsonb;
begin
  select * into p from pipeline.layer2_acquisition_providers x where x.provider_key = 'firecrawl';
  if p.id is null or nullif(p.billing_config->>'monthly_vendor_units_limit', '') is null then return null; end if;
  select o.remaining_units, o.observed_at into v_rem, v_at from pipeline.vendor_credit_observations o
   where o.provider_id = p.id and o.observed_at > now() - interval '2 hours'  -- fixed: the freshness layer2_provider_budget_status trusts (Decision 253)
   order by o.observed_at desc limit 1;
  if v_at is null then
    st := security.layer2_provider_budget_status(p.id, p_units);
    if coalesce((st->>'allowed')::boolean, true) then return null; end if;
    return format('Firecrawl monthly limit: %s of %s credits left this month (UTC, counted; no vendor balance in the last 2 hours), %s kept in reserve',
                  st->>'remaining_units', st->>'limit_units', st->>'stop_at_remaining_units');
  end if;
  v_stop := coalesce(nullif(p.billing_config->>'stop_at_vendor_units_remaining', '')::numeric, 0);
  v_unit := coalesce(nullif(p.request_template->>'fixed_credit_units', '')::numeric, 1);
  v_rem := greatest(v_rem
    - coalesce((select sum(u.units) from pipeline.coverage_vendor_usage u where u.acquisition_provider_id = p.id and u.at > v_at), 0)
    - (select count(*)::numeric * v_unit from pipeline.layer2_provider_attempts a where a.acquisition_provider_id = p.id and a.started_at > v_at), 0);
  if v_rem - greatest(coalesce(p_units, v_unit), 0) >= v_stop then return null; end if;
  return format('Firecrawl monthly limit: about %s credits left on the plan (vendor balance read %s less use since), %s kept in reserve',
                v_rem, to_char(v_at at time zone 'Australia/Melbourne', 'DD Mon HH24:MI'), v_stop);
end $$;
revoke all on function security.fc_month_refusal_v1(numeric) from public, anon, authenticated;
comment on function security.fc_month_refusal_v1(numeric) is 'Decision 5 E-8 F2 (2 Nov 2026): the Firecrawl monthly plan limit for one spend (vendor balance, else the counted month); read by fc_budget_left_v1, svc_fc_spend and admin_adapter_builder';

create or replace function security.fc_month_refuse_v1(p_units numeric) returns void
language plpgsql stable security definer set search_path to '' as $$
declare v text := security.fc_month_refusal_v1(p_units);
begin
  -- Decision 5 E-8 F2 (2 Nov 2026): for an action a person starts: the refusal, in words
  if v is not null then raise exception '%. Nothing was spent.', v; end if;
end $$;
revoke all on function security.fc_month_refuse_v1(numeric) from public, anon, authenticated;
comment on function security.fc_month_refuse_v1(numeric) is 'Decision 5 E-8 F2 (2 Nov 2026): raises security.fc_month_refusal_v1 for an action a person starts';

select pg_temp.edit_once('security.fc_budget_left_v1(text)', '187ad8c1c8b085f61ce3fba7cd0fe247', 'e979d2e3d7319d845a5149e40abe6987', array[
 array[$o$  if not coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false) then return 1000000; end if;$o$,
       $n$  -- Decision 5 E-8 F2 (2 Nov 2026): nothing is left on any path once the monthly plan limit is reached
  if security.fc_month_refusal_v1(1) is not null then return 0; end if;
  if not coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false) then return 1000000; end if;$n$]],
 array[1]);

select pg_temp.edit_once('public.svc_fc_spend(numeric,text,uuid,text)', '7a9b0cee72676c18c01d4692a8a56939', 'd418c451d681ffd95134f5f4dcf7c504', array[
 array[$o$  elsif v_od is not null then$o$,
       $n$  -- Decision 5 E-8 F2 (2 Nov 2026): the monthly plan limit, before the on-demand allowance and the daily rules (every path)
  elsif security.fc_month_refusal_v1(p_units) is not null then
    v_why := 'month_limit';
  elsif v_od is not null then$n$]],
 array[1]);

-- 7. the external watchdog's read (E-9 W1) ---------------------------------------------------------------------------------------------
create or replace function security.platform_watchdog_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $$
-- Decision 5 E-9 W1 (2 Nov 2026): read by the hourly GitHub workflow platform-watchdog (read-only role), which fails when ok is false so
-- GitHub e-mails the repository owner. Independent of the Claude scheduler and the alert task; reads only.
declare v_stale int := security.pipeline_num_v1('alerts.watchdog_stale_minutes', 30)::int;
        v_scan int := security.pipeline_num_v1('alerts.watchdog_scan_runs', 20000)::int;
        v_collect int := security.pipeline_num_v1('alerts.collect_within_minutes', 120)::int;
        v_delivery boolean := coalesce((security.toolset_setting('pipeline', 'alerts.delivery_enabled') #>> '{}')::boolean, false);
        v_problems text[] := '{}'; v_jobs jsonb := '{}'::jsonb; j record; r record; v_waiting int; v_since timestamptz;
begin
  for j in select n.name, c.jobid, c.active from unnest(array['platform-health', 'platform-alerts']) n(name) left join cron.job c on c.jobname = n.name loop
    r := null;
    select d.status, d.start_time into r
      from (select x.runid, x.jobid, x.status, x.start_time from cron.job_run_details x order by x.runid desc limit v_scan) d
     where d.jobid = j.jobid order by d.runid desc limit 1;
    v_jobs := v_jobs || jsonb_build_object(j.name, jsonb_build_object('active', j.active, 'last_start', r.start_time, 'last_status', r.status));
    if j.jobid is null then v_problems := v_problems || format('%s: the job is not scheduled', j.name);
    elsif not j.active then v_problems := v_problems || format('%s: the job is switched off', j.name);
    elsif r.start_time is null or r.start_time < now() - make_interval(mins => v_stale) then
      v_problems := v_problems || format('%s: no run started in the last %s minutes (last: %s)', j.name, v_stale,
                                         coalesce(to_char(r.start_time at time zone 'Australia/Melbourne', 'DD Mon HH24:MI'), 'none found'));
    elsif r.status not in ('succeeded', 'running', 'starting') then
      v_problems := v_problems || format('%s: the last run %s', j.name, r.status);
    end if;
  end loop;
  -- the alert-collecting step: an alert left waiting longer than alerts.collect_within_minutes means nothing is taking them
  select count(*), min(a.created_at) into v_waiting, v_since from pipeline.platform_alerts a
   where a.status = 'pending' and a.created_at < now() - make_interval(mins => v_collect);
  if v_delivery and v_waiting > 0 then
    v_problems := v_problems || format('alerts are not being collected: %s waiting since %s (longer than %s minutes)', v_waiting,
                                       to_char(v_since at time zone 'Australia/Melbourne', 'DD Mon HH24:MI'), v_collect);
  end if;
  return jsonb_build_object('ok', cardinality(v_problems) = 0, 'problems', to_jsonb(v_problems), 'checked_at', now(), 'jobs', v_jobs,
                            'alerts_waiting_too_long', v_waiting, 'delivery_enabled', v_delivery, 'stale_minutes', v_stale, 'collect_within_minutes', v_collect);
end $$;
revoke all on function security.platform_watchdog_v1() from public, anon, authenticated;
do $r$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    -- the read-only role runs only this; its body reads as the owner (security definer) and the transaction stays read-only
    grant execute on function security.platform_watchdog_v1() to supabase_read_only_user;
  end if;
end $r$;
comment on function security.platform_watchdog_v1() is 'Decision 5 E-9 W1 (2 Nov 2026): read-only health of the alert path (platform-health and platform-alerts runs, alerts waiting); read hourly by .github/workflows/platform-watchdog.yml';
