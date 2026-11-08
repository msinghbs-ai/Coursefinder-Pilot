CREATE OR REPLACE FUNCTION public.svc_fc_spend(p_units numeric, p_purpose text, p_provider_id uuid, p_url text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_grp text := security.fc_purpose_group_v1(p_purpose); v_why text; v_host text := security.fc_spend_host_v1(p_url);
  -- CF-247 21 Oct 2026: a university with a manual enrichment plan run spends from the on-demand allowance
  v_od uuid := case when p_provider_id is null then null else (select r.id from pipeline.enrich_plan_runs r where r.provider_id = p_provider_id and r.mode = 'manual' and r.state = 'running' limit 1) end;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- v2.15.265 (Platform Admin, 13 Oct 2026): never a credit on a directory site (a page on it, or a search limited to it), whatever the purpose
  if v_host is not null and security.third_party_host_v1('https://' || v_host) then
    v_why := 'directory_site';
  -- v2.15.265: scholarship site maps and searches only for providers that qualify (Australian with enough courses; overseas as before)
  -- Decision 5 E-8 F2 (2 Nov 2026): the monthly plan limit, before the on-demand allowance and the daily rules (every path)
  elsif security.fc_month_refusal_v1(p_units) is not null then
    v_why := 'month_limit';
  elsif v_od is not null then
    -- on demand: the person saw the estimate and chose to run it; the daily shares and per-university caps do not apply, the allowance does
    perform pg_advisory_xact_lock(hashtext('fc_spend:on_demand'));
    if security.fc_on_demand_today_v1() + p_units > security.fc_setting_num_v1('ondemand_credits_per_day', 2000) then v_why := 'on_demand_allowance'; end if;
  -- CF-247 workstream F (P0 AI operations §11): the cost breakers (repeat search, stored page, ineligible provider); each off by its own
  -- ops_cost.enforce_* switch, and only while its breaker is tripped. On-demand runs a person started are decided above and never held here.
  elsif security.ops_cost_fc_refusal_v1(p_units, p_purpose, p_provider_id, p_url) is not null then
    v_why := security.ops_cost_fc_refusal_v1(p_units, p_purpose, p_provider_id, p_url);
  elsif p_provider_id is not null and p_purpose in ('sch_map', 'sch_search') and not security.fc_sch_eligible_v1(p_provider_id) then
    v_why := 'not_eligible';
  elsif coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false) then
    perform pg_advisory_xact_lock(hashtext('fc_spend:' || v_grp));
    if security.fc_budget_left_v1(p_purpose) < p_units then
      v_why := case when security.fc_billed_today_v1() >= security.fc_setting_num_v1('daily_budget_total', 15000) then 'day_total' else 'share' end;
    elsif p_provider_id is not null and v_grp = 'scholarships'
          and (select coalesce(sum(x.units), 0) from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and x.purpose like 'sch\_%' and x.at > security.fc_sch_cap_since_v1(p_provider_id))
              + p_units > security.fc_setting_num_v1('scholarship_cap_per_uni', 150)
          -- 16 Oct 2026: a scholarship page asked to be read again is not held by the per-university cap
          and not (p_purpose = 'sch_scrape' and exists (select 1 from pipeline.scholarship_pages sp join scholarship.scholarships s on s.id = sp.scholarship_id
                                                         where s.provider_id = p_provider_id and sp.url = p_url and sp.requested_at is not null)) then
      v_why := 'university_cap';
    elsif p_provider_id is not null and v_grp = 'central'
          and exists (select 1 from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and security.fc_purpose_group_v1(x.purpose) = 'central'
                         and x.at > now() - make_interval(days => security.fc_setting_num_v1('central_refresh_days', 30)::int) and x.at < now() - interval '6 hours')  -- fixed: spends within the same central-page run
          -- Decision 265 (18 Oct 2026): a source a person added and not yet read is not held by the refresh interval
          and not exists (select 1 from pipeline.provider_fact_sources fs where fs.provider_id = p_provider_id and fs.url = p_url
                             and fs.status in ('found', 'reading') and fs.read_at is null)  -- 21 Oct 2026: any page never read (fee reader)
          -- 29 Oct 2026 (AER programme): nor is a seeded entry-requirements page never read
          and not exists (select 1 from pipeline.entry_matrix_sources es where es.provider_id = p_provider_id and es.url = p_url
                             and es.status in ('found', 'reading') and es.read_at is null) then
      v_why := 'not_due';
    elsif p_provider_id is not null and v_grp = 'course_search' and security.search_stop_gate_v1(p_provider_id) = 'search_stopped' then  -- S1: the one stop gate
      v_why := 'search_stopped';
    end if;
  end if;
  if v_why is not null then
    insert into pipeline.firecrawl_budget_refusals(day, grp, reason, n, last_at) values ((now() at time zone 'Australia/Melbourne')::date, v_grp, v_why, 1, now())
    on conflict (day, grp, reason) do update set n = pipeline.firecrawl_budget_refusals.n + 1, last_at = now();
    -- v2.15.265: and per university
    if p_provider_id is not null then
      insert into pipeline.firecrawl_refusals_by_provider(day, provider_id, grp, reason, n, last_at) values ((now() at time zone 'Australia/Melbourne')::date, p_provider_id, v_grp, v_why, 1, now())
      on conflict (day, provider_id, grp, reason) do update set n = pipeline.firecrawl_refusals_by_provider.n + 1, last_at = now();
    end if;
    return false;
  end if;
  insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, provider_id, url, on_demand_run)
  select id, p_units, p_purpose, p_provider_id, left(p_url, 500), v_od from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';
  return true;
end $function$
