-- CF-247 operating model: on-demand work is not held by toolset limits; only scheduled work is (Platform Admin 12 Nov 2026 21:07: "toolset limit should be
-- waved when doing on demand, only scheduled tasks should obey toolset limits. especially when requested to execute from claude session it should display
-- estimated toolset value and then after finish display actual used or credit left on toolset"). Operating model 1.5 section 3.3.2.
-- Guards: G1 (no job), G2 (the window is a setting; the account limits stay settings), G3 (no consumer API object: coverage_vendor_usage, svc_fc_spend and
--   admin_enrich_plan are not consumer API), Decision 260, nothing admitted or published by this change.
-- What:
--   1. pipeline.on_demand_requests: one row per on-demand request (from a person's screen or a Claude session): scope (providers), reason, estimate, the
--      account credit left when it opened, a window (setting ondemand.window_hours), and on close the actual use and credit left.
--      security.on_demand_open_v1 / on_demand_report_v1 / on_demand_close_v1 open it, report estimate against actual, and close it.
--   2. svc_fc_spend (md5-guarded): a Firecrawl spend for a provider in an open request is not held by the daily total, the daily shares, per-university caps,
--      the refresh interval, the cost breakers or the discovery campaign ceiling; a manual Run now plan is no longer held by the on-demand allowance.
--      Still applied to every spend: directory sites (a policy, not a limit) and the account's monthly plan limit. The spend records its request.
--   3. fc_budget_left_v1 and fc_on_demand_today_v1 (md5-guarded): spends of a request are on-demand use, outside the scheduled shares.
--   4. admin_enrich_plan (md5-guarded): Run now is checked against the account (Firecrawl credit left on the plan; OpenRouter balance above its floor),
--      not the daily on-demand allowance. The estimate is still shown before the run, and the actual after (unchanged).
--   5. The two on-demand allowance settings stay on screen as reference, with help saying they no longer hold a run.
-- Not in this change (operating model 3.3.2, phase 2): the OpenRouter daily ceiling and lane guards for on-demand AI (security.ai_use_refusal_v1 has no
--   request context yet). The credit floor stays for every AI call.
-- Live definitions this change edits (md5 of pg_get_functiondef, read 12 Nov 2026 21:20 AEDT): public.svc_fc_spend 41fb1ac8c71c74df25b913b85dcf3baa;
--   security.fc_budget_left_v1 a337da7a9e56cbb5eb7fa051eb92467d; security.fc_on_demand_today_v1 782b58492f258102047038e12f5512e4;
--   public.admin_enrich_plan dab650c5adefd9b0b9c006b0c5db4d5d.
-- Replaces: the on-demand allowance check in svc_fc_spend and admin_enrich_plan (same functions; md5-guarded text edits). Retires: nothing.

create table if not exists pipeline.on_demand_requests (
  id uuid primary key default gen_random_uuid(),
  requested_via text not null check (requested_via in ('claude_session', 'admin_screen')),
  requested_by uuid,
  reason text not null check (length(btrim(reason)) >= 5),
  provider_ids uuid[] not null default '{}',
  toolsets text[] not null default '{firecrawl,openrouter}',
  estimate jsonb not null default '{}'::jsonb,
  before jsonb not null default '{}'::jsonb,
  actual jsonb,
  state text not null default 'open' check (state in ('open', 'closed')),
  opened_at timestamptz not null default now(),
  expires_at timestamptz not null,
  closed_at timestamptz
);
comment on table pipeline.on_demand_requests is 'CF-247 operating model 3.3.2 (Platform Admin 12 Nov 2026 21:07): one on-demand request (a person''s screen or a Claude session). While open (until expires_at), Firecrawl spends for its providers are not held by toolset limits, only by the account''s monthly plan; it records the estimate and the credit left before, and the actual use and credit left after.';
create index if not exists on_demand_requests_open_ix on pipeline.on_demand_requests (expires_at) where state = 'open';
alter table pipeline.coverage_vendor_usage add column if not exists on_demand_request uuid references pipeline.on_demand_requests(id);
comment on column pipeline.coverage_vendor_usage.on_demand_request is 'The on-demand request (pipeline.on_demand_requests) this spend belongs to; such spends are outside the scheduled shares.';

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'ondemand.window_hours', 'On demand: how long a request stays open',
  'An on-demand request (a person''s screen or a Claude session) is not held by toolset limits for this many hours from when it opens, or until it is closed. Scheduled work keeps every limit.',
  'number', to_jsonb(6), 1, 48, 'hours', 1150, 'On demand', 'security.on_demand_open_v1; svc_fc_spend', 'Platform Admin 12 Nov 2026 21:07: toolset limits are waived on demand; only scheduled tasks obey them')
on conflict (toolset_key, key) do nothing;

update pipeline.platform_toolset_settings
   set help = 'Reference only since 12 Nov 2026 (Platform Admin 21:07): on-demand runs are not held by toolset limits, only by the account (Firecrawl monthly plan, OpenRouter credit floor). Run now still shows its estimate before and its actual use after.',
       used_by = 'Layer 2/3 › Enrichment plan (shown); not a limit', reason = 'Platform Admin 12 Nov 2026 21:07: toolset limits are waived on demand; only scheduled tasks obey them', updated_at = now()
 where (toolset_key, key) in (('firecrawl', 'ondemand_credits_per_day'), ('openrouter', 'ondemand_usd_per_day'));

-- the account's credit left, both toolsets
create or replace function security.on_demand_credit_left_v1() returns jsonb language sql stable security definer set search_path to '' as $f$
  select jsonb_build_object(
    'firecrawl_left_on_plan', security.fc_vendor_estimate_v1(),
    'firecrawl_month_refusal', security.fc_month_refusal_v1(1),
    'openrouter_balance_usd', (select round(o.remaining_usd - coalesce((select sum(l.cost_usd) from pipeline.ai_spend_ledger l where l.at > o.observed_at and l.source <> 'opening'), 0), 2)
                                 from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1),
    'openrouter_floor_usd', coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0),
    'at', now())
$f$;

-- the open request covering a provider, if any
create or replace function security.on_demand_request_for_v1(p_provider uuid) returns uuid language sql stable security definer set search_path to '' as $f$
  select r.id from pipeline.on_demand_requests r
   where r.state = 'open' and r.expires_at > now() and p_provider = any (r.provider_ids) and 'firecrawl' = any (r.toolsets)
   order by r.opened_at desc limit 1
$f$;

create or replace function security.on_demand_open_v1(p_via text, p_reason text, p_provider_ids uuid[], p_estimate jsonb, p_requested_by uuid default null,
                                                        p_toolsets text[] default '{firecrawl,openrouter}') returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare v_id uuid; v_before jsonb := security.on_demand_credit_left_v1();
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' and coalesce(security.current_role_rank(), 0) < 3 then
    raise exception 'Curator role or above, or the service, required' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_provider_ids), 0) = 0 then raise exception 'an on-demand request names its providers'; end if;
  insert into pipeline.on_demand_requests(requested_via, requested_by, reason, provider_ids, toolsets, estimate, before, expires_at)
  values (p_via, coalesce(p_requested_by, auth.uid()), btrim(p_reason), p_provider_ids, coalesce(p_toolsets, '{firecrawl,openrouter}'), coalesce(p_estimate, '{}'::jsonb), v_before,
          now() + make_interval(hours => security.pipeline_num_v1('ondemand.window_hours', 6)::int))
  returning id into v_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('on_demand', 'open', 'pipeline.on_demand_requests', jsonb_build_object('id', v_id, 'via', p_via, 'reason', btrim(p_reason), 'providers', cardinality(p_provider_ids), 'estimate', p_estimate, 'before', v_before), auth.uid());
  return jsonb_build_object('id', v_id, 'estimate', coalesce(p_estimate, '{}'::jsonb), 'credit_left_before', v_before,
                            'expires_at', now() + make_interval(hours => security.pipeline_num_v1('ondemand.window_hours', 6)::int));
end $f$;

-- estimate against actual: Firecrawl units spent under the request; AI spend recorded in its window (all lanes: the AI ledger has no provider); credit left now
create or replace function security.on_demand_report_v1(p_id uuid) returns jsonb language sql stable security definer set search_path to '' as $f$
  select jsonb_build_object('id', r.id, 'state', r.state, 'via', r.requested_via, 'reason', r.reason, 'providers', cardinality(r.provider_ids),
           'opened_at', r.opened_at, 'expires_at', r.expires_at, 'closed_at', r.closed_at, 'estimate', r.estimate, 'credit_left_before', r.before,
           'actual', coalesce(r.actual, jsonb_build_object(
              'firecrawl_units', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.on_demand_request = r.id),
              'firecrawl_by_purpose', (select coalesce(jsonb_object_agg(x.purpose, x.n), '{}'::jsonb) from (select u.purpose, sum(u.units) n from pipeline.coverage_vendor_usage u where u.on_demand_request = r.id group by 1) x),
              'openrouter_usd_in_window_all_lanes', (select round(coalesce(sum(l.cost_usd), 0), 4) from pipeline.ai_spend_ledger l where l.at between r.opened_at and least(now(), r.expires_at) and l.source <> 'opening'))),
           'credit_left_now', security.on_demand_credit_left_v1())
    from pipeline.on_demand_requests r where r.id = p_id
$f$;

create or replace function security.on_demand_close_v1(p_id uuid) returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' and coalesce(security.current_role_rank(), 0) < 3 then
    raise exception 'Curator role or above, or the service, required' using errcode = '42501';
  end if;
  v := security.on_demand_report_v1(p_id);
  if v is null then raise exception 'no on-demand request %', p_id; end if;
  update pipeline.on_demand_requests set state = 'closed', closed_at = now(), actual = (v->'actual') || jsonb_build_object('credit_left_after', v->'credit_left_now')
   where id = p_id and state = 'open';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('on_demand', 'close', 'pipeline.on_demand_requests', jsonb_build_object('id', p_id, 'estimate', v->'estimate', 'actual', v->'actual', 'credit_left_after', v->'credit_left_now'), auth.uid());
  return security.on_demand_report_v1(p_id);
end $f$;

revoke all on function security.on_demand_open_v1(text, text, uuid[], jsonb, uuid, text[]) from public, anon;
revoke all on function security.on_demand_close_v1(uuid) from public, anon;

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 2. svc_fc_spend: an open request waives the toolset limits (after the directory-site rule and the monthly plan limit); Run now no longer meets an allowance
select pg_temp.edit_n('public.svc_fc_spend(numeric,text,uuid,text)', '41fb1ac8c71c74df25b913b85dcf3baa', array[
  array[$o$v_spare boolean := false;$o$,
        $n$v_spare boolean := false;
  -- CF-247 operating model 3.3.2 (Platform Admin 12 Nov 2026 21:07): an open on-demand request for this provider (a person's screen or a Claude session)
  v_req uuid := case when p_provider_id is null then null else security.on_demand_request_for_v1(p_provider_id) end;$n$],
  array[$o$    if security.fc_on_demand_today_v1() + p_units > security.fc_setting_num_v1('ondemand_credits_per_day', 2000) then v_why := 'on_demand_allowance'; end if;$o$,
        $n$    null;  -- 12 Nov 2026 (Platform Admin 21:07): on demand is not held by toolset limits; the on-demand allowance is shown only$n$],
  array[$o$  elsif v_od is not null then$o$,
        $n$  elsif v_req is not null then
    v_why := null;  -- 12 Nov 2026 (Platform Admin 21:07): an open on-demand request is held only by the directory-site rule and the monthly plan limit above
  elsif v_od is not null then$n$],
  array[$o$  insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, provider_id, url, on_demand_run)
  select id, p_units, p_purpose, p_provider_id, left(p_url, 500), v_od from$o$,
        $n$  insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, provider_id, url, on_demand_run, on_demand_request)
  select id, p_units, p_purpose, p_provider_id, left(p_url, 500), v_od, v_req from$n$]
], array[1, 1, 1, 1]);

-- 3. a request's spends are on-demand use, outside the scheduled shares
select pg_temp.edit_n('security.fc_budget_left_v1(text)', 'a337da7a9e56cbb5eb7fa051eb92467d', array[
  array[$o$and x.on_demand_run is null;$o$, $n$and x.on_demand_run is null and x.on_demand_request is null;$n$]
], array[1]);
select pg_temp.edit_n('security.fc_on_demand_today_v1()', '782b58492f258102047038e12f5512e4', array[
  array[$o$where x.on_demand_run is not null and$o$, $n$where (x.on_demand_run is not null or x.on_demand_request is not null) and$n$]
], array[1]);

-- 4. Run now: checked against the account, not the daily on-demand allowance (the estimate is still shown before, the actual after)
select pg_temp.edit_n('public.admin_enrich_plan(text,jsonb)', 'dab650c5adefd9b0b9c006b0c5db4d5d', array[
  array[$o$    if v_est_c > v_left_c then raise exception 'the estimate (% credits) is more than the on-demand allowance left today (% credits); lower the steps, or raise the allowance on Models & services › Toolsets & limits', round(v_est_c), round(v_left_c); end if;$o$,
        $n$    -- 12 Nov 2026 (Platform Admin 21:07): on demand is not held by toolset limits; only the account's own credit stops it
    if v_est_c > coalesce(security.fc_vendor_estimate_v1(), v_est_c) then raise exception 'the estimate (% credits) is more than the Firecrawl credit left on the plan (% credits)', round(v_est_c), round(security.fc_vendor_estimate_v1()); end if;$n$],
  array[$o$    if v_est_u > v_left_u then raise exception 'the estimate (US$%) is more than the on-demand AI allowance left today (US$%)', round(v_est_u, 2), round(v_left_u, 2); end if;$o$,
        $n$    if v_est_u > coalesce((security.on_demand_credit_left_v1()->>'openrouter_balance_usd')::numeric - (security.on_demand_credit_left_v1()->>'openrouter_floor_usd')::numeric, v_est_u) then
      raise exception 'the estimate (US$%) would take the OpenRouter balance below its floor (US$% left above the floor)', round(v_est_u, 2),
        round((security.on_demand_credit_left_v1()->>'openrouter_balance_usd')::numeric - (security.on_demand_credit_left_v1()->>'openrouter_floor_usd')::numeric, 2);
    end if;$n$]
], array[1, 1]);
