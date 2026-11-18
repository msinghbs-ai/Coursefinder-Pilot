-- CF-247 Firecrawl PRIORITY FLOOR: the lowest-priority spend group (course page search) does not spend the last credits on the plan.
-- Guards: Platform Admin Firecrawl priority order 8 Nov 2026 ((1) AER missing official entry-requirement pages via central_map / central find, (2) English requirements,
--   (3) scholarships, (4) course discovery, (5) other fields), G2 (the floor is a setting with label, range, unit and used_by), G3 (no consumer API object, table or column is
--   touched), Decision 260 (housekeeping), "a passing check never switches anything on" (this keeps credits back; it starts nothing), "nothing is dropped or deleted by an
--   applied migration".
-- Replaces: security.fc_budget_left_v1, public.svc_fc_spend and security.lane_paid_hold_v1 (same names and signatures; md5-guarded, exact-once edits)
-- Retires: nothing
--
-- Live evidence (project fxcwkweaxjtknorudmwp, read only, 8 Nov 2026 UTC): the Firecrawl plan is 5,000 credits (pipeline.vendor_credit_observations). The balance was 8 at
-- 00:30, about 962 at 00:45 after a top-up, and the whole amount was spent within minutes by purpose course_link_search (2 credits a search, up to 120 searches a minute through
-- the worker lane link_search; 2,961 searches were queued). security.fc_budget_left_v1 gives each purpose group a DAILY share sized for a 500,000-credit plan (13,000 course search,
-- 5,000 reads, 2,500 central, 3,500 scholarships, 1,000 other) and security.fc_month_refusal_v1 refuses only at the vendor balance less
-- billing_config.stop_at_vendor_units_remaining (live: 0). With a few hundred credits nothing orders the groups, so course search (priority 4) emptied the plan before the
-- higher-priority work could use it. 630 providers' central find (AER entry pages, priority 1) is held by central_not_due flags that release on 10 and 11 Nov and then needs credits.
--
-- What this changes:
--   1. Setting firecrawl / priority_floor_course_search (default 1,500 credits; 0 switches the floor off).
--   2. security.fc_vendor_estimate_v1(): the estimated credits left on the plan, worked out EXACTLY as security.fc_month_refusal_v1 works it out (the vendor balance read in the last
--      2 hours, less the platform's use since, less provider attempts since), or null when there is no balance read in the last 2 hours. fc_month_refusal_v1 itself is NOT edited (it is
--      the hot path of every spend); the fixture proves the two agree for every balance, spend, use and attempt tried, and the spec fails if either text drifts.
--   3. security.fc_priority_room_v1(): estimate less the floor, or null when the floor is 0 or there is no estimate.
--   4. security.fc_budget_left_v1: for the course_search group only, the credits left are the day's share left or the room above the floor, whichever is less (0 when under one
--      credit of room). Every other group, a floor of 0, no balance read, the daily-budget-off mode and every earlier return are byte-for-byte the same answer. Because the
--      answer is the room (not a bare 0), the picker public.svc_course_link_search_next, which sizes its batch as floor(budget_left / 2), picks only as many searches as fit
--      above the floor, and a spend of n credits is allowed exactly when the estimate is at least floor + n.
--   5. public.svc_fc_spend: the refusal is recorded as the distinct reason 'priority_floor' (pipeline.firecrawl_budget_refusals and firecrawl_refusals_by_provider, like the other
--      reasons) when the floor is what holds the spend; 'day_total' still comes first and 'share' is kept for every other case.
--   6. security.lane_paid_hold_v1: says 'budget_held: Firecrawl balance kept for higher-priority work (priority floor N credits)'. The lanes (worker_lane_call_v1,
--      work_continuity_tick_v1, course_search_paid_cap_v1) read this text, so the link_search lane stops being called while the floor holds and starts again by itself on the first
--      tick after the balance (read every 15 minutes) is back above the floor plus a search.
-- Not changed: the consumer API, billing_config, stop_at_vendor_units_remaining, the daily shares and total, any job or schedule, every other group, the on-demand allowance
--   (a person's Run now spends from its own allowance and is not held by the floor; the monthly limit still applies to it). Nothing is fetched, searched, read by AI, switched on or off.
-- Before -> after (live md5s read 8 Nov 2026; the after values are what the scratch copy of the live definitions gives, and the live run checks them):
--   security.fc_budget_left_v1(text)                              e979d2e3d7319d845a5149e40abe6987 -> a337da7a9e56cbb5eb7fa051eb92467d
--   public.svc_fc_spend(numeric,text,uuid,text)                   a9217c5af8e0da8ee18b03bcab9eaeef -> a0f43e737574f504de4aad17daf792bb
--   security.lane_paid_hold_v1(text)                              99ec517b8b51b0d1305b739e7f1562fb -> 96e7eddea3a3c68c4b13ce5a8a62d559
-- Rollback: set priority_floor_course_search to 0 (the floor is off and every answer is the earlier one), or restore the three definitions from the audit event's before md5s.

-- 0. the rule the estimate copies is the one it was written from (first application only) ----------------------------------------------------------
do $g$
begin
  if to_regprocedure('security.fc_vendor_estimate_v1()') is null
     and md5(pg_get_functiondef('security.fc_month_refusal_v1(numeric)'::regprocedure)) <> '8c1419332ff503abd69539ccbad1121d' then
    raise exception 'live security.fc_month_refusal_v1 differs from the rule security.fc_vendor_estimate_v1 copies (md5 %); nothing changed',
      md5(pg_get_functiondef('security.fc_month_refusal_v1(numeric)'::regprocedure));
  end if;
end $g$;

-- 1. the setting (G2) -------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
('firecrawl', 'priority_floor_course_search', 'Credits kept back from course page search',
 'Firecrawl credits left on the plan for higher-priority work. While the plan''s estimated balance (the balance Firecrawl reported in the last 2 hours, less what the platform has used since) is under this amount plus the cost of a search, course page searches wait. Entry-requirement page finding, English requirements, scholarships, page reading and everything else carry on. Searching starts again by itself when the balance is back above this amount (the balance is read every 15 minutes). 0 = off. It has no effect while no balance has been read in the last 2 hours.',
 'number', '1500'::jsonb, 0, 100000, 'credits', 660, 'Daily budget',
 'security.fc_budget_left_v1 (course search group); public.svc_fc_spend (refusal reason priority_floor); security.lane_paid_hold_v1 (link_search lane); public.svc_course_link_search_next',
 'CF-247, Platform Admin 8 Nov 2026 Firecrawl priority order: AER entry pages first; course page search must not spend the last credits on the plan')
on conflict (toolset_key, key) do nothing;

-- 2. the estimate and the room above the floor -----------------------------------------------------------------------------------------------------
create or replace function security.fc_vendor_estimate_v1() returns numeric
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 priority floor (8 Nov 2026): the estimated credits left on the Firecrawl plan, or null when no vendor balance was read in the last 2 hours. The same estimate, term for term, as
-- security.fc_month_refusal_v1 uses before it refuses a spend: the vendor's balance less the platform's use since (pipeline.coverage_vendor_usage) less provider attempts since
-- (pipeline.layer2_provider_attempts, at the provider's fixed credit units), never below 0.
declare p pipeline.layer2_acquisition_providers%rowtype; v_unit numeric; v_rem numeric; v_at timestamptz;
begin
  select * into p from pipeline.layer2_acquisition_providers x where x.provider_key = 'firecrawl';
  if p.id is null then return null; end if;
  select o.remaining_units, o.observed_at into v_rem, v_at from pipeline.vendor_credit_observations o
   where o.provider_id = p.id and o.observed_at > now() - interval '2 hours'  -- fixed: the freshness layer2_provider_budget_status trusts (Decision 253)
   order by o.observed_at desc limit 1;
  if v_at is null then return null; end if;
  v_unit := coalesce(nullif(p.request_template->>'fixed_credit_units', '')::numeric, 1);
  return greatest(v_rem
    - coalesce((select sum(u.units) from pipeline.coverage_vendor_usage u where u.acquisition_provider_id = p.id and u.at > v_at), 0)
    - (select count(*)::numeric * v_unit from pipeline.layer2_provider_attempts a where a.acquisition_provider_id = p.id and a.started_at > v_at), 0);
end $function$;

create or replace function security.fc_priority_room_v1() returns numeric
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 priority floor (8 Nov 2026): the credits course page search may still spend before the plan's estimated balance (security.fc_vendor_estimate_v1) reaches the floor
-- (firecrawl / priority_floor_course_search), or null when the floor does not apply: the setting is 0 (or missing), or no vendor balance was read in the last 2 hours.
-- Negative when the balance is already under the floor.
declare v_floor numeric := security.fc_setting_num_v1('priority_floor_course_search', 0);  -- fixed: a missing setting means the floor is off
        v_est numeric;
begin
  if v_floor <= 0 then return null; end if;  -- fixed: 0 switches the floor off
  v_est := security.fc_vendor_estimate_v1();
  if v_est is null then return null; end if;
  return v_est - v_floor;
end $function$;

revoke all on function security.fc_vendor_estimate_v1() from public, anon, authenticated;
revoke all on function security.fc_priority_room_v1() from public, anon, authenticated;
comment on function security.fc_vendor_estimate_v1() is 'CF-247 priority floor (8 Nov 2026): estimated Firecrawl credits left on the plan (vendor balance read in the last 2 hours less use and provider attempts since), the same estimate security.fc_month_refusal_v1 uses; null when no balance was read in the last 2 hours.';
comment on function security.fc_priority_room_v1() is 'CF-247 priority floor (8 Nov 2026): estimated plan credits less firecrawl / priority_floor_course_search; null when the floor is off or no balance is fresh. Read by security.fc_budget_left_v1 (course_search group), public.svc_fc_spend and security.lane_paid_hold_v1.';

-- 3. the three edits, each only from the live definition it was written against, each exact-once, a second run reports "already applied" -----------
create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %); nothing changed', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % time(s) (found %); nothing changed', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_once('security.fc_budget_left_v1(text)', 'e979d2e3d7319d845a5149e40abe6987', 'a337da7a9e56cbb5eb7fa051eb92467d', array[
  array[$e$declare v_grp text := security.fc_purpose_group_v1(p_purpose); v_used numeric;$e$,
        $e$declare v_grp text := security.fc_purpose_group_v1(p_purpose); v_used numeric; v_left numeric; v_room numeric;$e$],
  array[$e$  return greatest(0, security.fc_setting_num_v1('daily_share_' || v_grp, 0) - v_used);$e$,
        $e$  v_left := greatest(0, security.fc_setting_num_v1('daily_share_' || v_grp, 0) - v_used);
  -- CF-247 priority floor (Platform Admin 8 Nov 2026, Firecrawl priority order): course page search, the lowest priority, does not spend the last credits on the plan. It may
  -- spend only the room above the floor (security.fc_priority_room_v1: null when the floor is off or no balance is fresh); every other group is unchanged.
  if v_grp = 'course_search' then
    v_room := security.fc_priority_room_v1();
    if v_room is not null then return case when v_room < 1 then 0 else least(v_left, v_room) end; end if;  -- fixed: one credit, the smallest spend
  end if;
  return v_left;$e$]
], array[1, 1]);

select pg_temp.edit_once('public.svc_fc_spend(numeric,text,uuid,text)', 'a9217c5af8e0da8ee18b03bcab9eaeef', 'a0f43e737574f504de4aad17daf792bb', array[
  array[$e$      v_why := case when security.fc_billed_today_v1() >= security.fc_setting_num_v1('daily_budget_total', 15000) then 'day_total' else 'share' end;$e$,
        $e$      -- CF-247 priority floor (8 Nov 2026): course page search held to keep the last credits for higher-priority work is 'priority_floor', not 'share'
      v_why := case when security.fc_billed_today_v1() >= security.fc_setting_num_v1('daily_budget_total', 15000) then 'day_total'
                    when v_grp = 'course_search' and coalesce(security.fc_priority_room_v1(), p_units) < p_units then 'priority_floor'
                    else 'share' end;$e$]
], array[1]);

select pg_temp.edit_once('security.lane_paid_hold_v1(text)', '99ec517b8b51b0d1305b739e7f1562fb', '96e7eddea3a3c68c4b13ce5a8a62d559', array[
  array[$e$    return 'budget_held: no room left in today''s Firecrawl share for ' || security.fc_purpose_group_v1(p_purpose);$e$,
        $e$    -- CF-247 priority floor (8 Nov 2026): course page search waits while the plan's balance is kept for higher-priority work
    if security.fc_purpose_group_v1(p_purpose) = 'course_search' and coalesce(security.fc_priority_room_v1(), 1) < 1 then  -- fixed: one credit, the smallest spend
      return 'budget_held: Firecrawl balance kept for higher-priority work (priority floor ' || security.fc_setting_num_v1('priority_floor_course_search', 0)::bigint || ' credits)';
    end if;
    return 'budget_held: no room left in today''s Firecrawl share for ' || security.fc_purpose_group_v1(p_purpose);$e$]
], array[1]);

-- 4. the audit event (once) ---------------------------------------------------------------------------------------------------------------------
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'firecrawl', 'priority_floor', 'security.fc_budget_left_v1; public.svc_fc_spend; security.lane_paid_hold_v1',
       jsonb_build_object('governance', 'Platform Admin Firecrawl priority order 8 Nov 2026', 'setting', 'firecrawl/priority_floor_course_search', 'default', 1500,
                          'before_md5', jsonb_build_object('security.fc_budget_left_v1', 'e979d2e3d7319d845a5149e40abe6987', 'public.svc_fc_spend', 'a9217c5af8e0da8ee18b03bcab9eaeef',
                                                           'security.lane_paid_hold_v1', '99ec517b8b51b0d1305b739e7f1562fb'),
                          'new_functions', jsonb_build_array('security.fc_vendor_estimate_v1', 'security.fc_priority_room_v1'),
                          'affects', 'course_search group only', 'consumer_api', 'untouched', 'switches_on', false, 'migration', '20261108060000'),
       null
 where not exists (select 1 from pipeline.admin_control_events e where e.area = 'firecrawl' and e.action = 'priority_floor' and e.detail->>'migration' = '20261108060000');
