-- CF-247 s1199 (S1-Build / Release Controller; SS-Programme-Control 26 Nov 2026 17:01 AEDT, item 1, DR-15: "separate free Scholarship acquisition
-- eligibility from paid Firecrawl caps. Preserve all other holds, UTAS restrictions and spending controls").
-- Found live (26 Nov 2026, rolled back): the candidate picker (public.svc_scholarship_candidate_next) skipped every candidate of a provider held by its
-- paid Firecrawl limits (security.fc_sch_held_v1: the per-university scholarship cap, or the scholarship spend rule), so the free direct read the
-- reader makes first (Platform Admin 12 Nov 2026 16:12: official page read directly first, no credit) never ran either. Measured: 1,526 due candidates
-- at 20 providers held this way (CA 663, AU 496, NZ 367; 17 providers over the cap, 3 outside the spend rule).
-- What this does:
--   1. The picker no longer holds a provider on its paid Firecrawl limits. Unpublished providers, search switched off (security.provider_sch_search_off_v1,
--      which carries the UTAS and directory restrictions), directory hosts and every skip rule still hold.
--   2. Paid reads stay where they are decided: public.svc_fc_spend keeps the per-university cap, daily shares and month limits, and now also refuses a
--      scrape of a new candidate page for a provider outside the scholarship spend rule (its already admitted pages keep their path, as before).
--   3. A candidate whose read waits because its provider's Firecrawl hold refuses the paid read is tried again after the existing interval
--      retry.scholarship_waiting_scraper_hours (1 hour), so it does not re-enter every run.
-- No new value, setting, job, model, cap or spending authority. AI extraction stays on its own route and cap.
-- G1: no job. G2: the existing setting, its used_by extended. G3: no consumer object changed (checked). Locks and cron checked unchanged.
-- Replaces: public.svc_scholarship_candidate_next, public.svc_scholarship_candidate_record, public.svc_fc_spend (same functions, DR-15).
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: the consumer API check and three function replacements

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('public.svc_scholarship_candidate_next(integer)'::regprocedure)) <> '2f3129679369d97bafaa27d8a468f30b' then raise exception 'guard: public.svc_scholarship_candidate_next is not the definition read on 26 Nov 2026'; end if;
  if md5(pg_get_functiondef('public.svc_scholarship_candidate_record(bigint,text,integer,text,text,text,text,jsonb)'::regprocedure)) <> '44c06460d022b98dfa5404c28ccaa368' then raise exception 'guard: public.svc_scholarship_candidate_record is not the definition read on 26 Nov 2026'; end if;
  if md5(pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure)) <> '545680b0455d28d121fff0b3cd17c167' then raise exception 'guard: public.svc_fc_spend is not the definition read on 26 Nov 2026'; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'retry.scholarship_waiting_scraper_hours') then raise exception 'guard: retry.scholarship_waiting_scraper_hours is not a setting'; end if;
end $g$;
create temp table s1199_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1199_cron on commit drop as select jobname from cron.job;  -- the job names: this change creates none
create temp table s1199_settings on commit drop as select toolset_key, key, value, min_value, max_value from pipeline.platform_toolset_settings;

CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb; v_ok uuid[] := '{}'; v_p record; v_task uuid[];
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  -- CF-247 s1054: only a queued or running "Find scholarships" task puts its providers' candidates first (a request left from earlier no longer does)
  v_task := array(select distinct x::uuid from pipeline.admin_jobs j, jsonb_array_elements_text(coalesce(j.args->'providers', '[]'::jsonb)) x
                   where j.kind = 'scholarship_provider_scan' and j.state in ('queued', 'running'));
  -- CF-247 scholarship recovery F1: the skip rules run when candidates are recorded and hourly (security.scholarship_candidate_skip_v1).
  -- CF-247 s1054: the holds are checked once per provider that has a due candidate, before the window, so held providers never fill it
  for v_p in select distinct c.provider_id from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
              where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3 loop
    -- v2.15.237 unpublished; v2.15.271 search off. DR-15 (s1199, 26 Nov 2026): a paid Firecrawl hold (cap or eligibility) no longer holds the free read:
    -- the page is read directly first at no cost, and any paid scrape is still decided by public.svc_fc_spend (per-university cap, eligibility, shares)
    if not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = v_p.provider_id)
       and not security.provider_sch_search_off_v1(v_p.provider_id) then v_ok := v_ok || v_p.provider_id; end if;
  end loop;
  create temp table if not exists sch_cand_win_v2(id bigint, provider_id uuid, url text, requested boolean, tier int, priority int, found_at timestamptz, cc text) on commit drop;
  truncate sch_cand_win_v2;
  insert into sch_cand_win_v2
  select z.id, z.provider_id, z.url, z.requested, z.tier, z.priority, z.found_at, z.cc from (
    select c.id, c.provider_id, c.url, c.provider_id = any (v_task) requested, coalesce(d.tier, 9) tier, d.priority, c.found_at, coalesce(co.iso_alpha2::text, '--') cc,
           -- CF-247 s1054: the window takes each country in turn, so one country's older backlog never fills it
           row_number() over (partition by coalesce(co.iso_alpha2::text, '--') order by (c.provider_id = any (v_task)) desc, coalesce(d.tier, 9), (d.priority not in (0,3)), c.found_at, c.id) crk
      from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
      join catalogue.providers p on p.id = c.provider_id left join ref.countries co on co.id = p.country_id
     where c.provider_id = any (v_ok) and c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3) z
   order by z.requested desc, z.crk, z.cc
   limit greatest(1, security.pipeline_num_v1('scholarship.candidate_pick_window', 600)::int);
  with ranked0 as (
    select w.id, w.requested, w.tier, w.priority, w.cc, row_number() over (partition by w.provider_id order by (w.url ~* 'international') desc, w.found_at, w.id) rn
      from sch_cand_win_v2 w where not security.third_party_host_v1(w.url)),
  ranked as (
    -- CF-247 s1054: within a country the providers take turns (rn), and the countries take turns (crk)
    select r0.*, row_number() over (partition by r0.requested, r0.cc order by r0.rn, r0.tier, (r0.priority not in (0,3)), r0.id) crk from ranked0 r0),
  pick as (
    select c.id from pipeline.scholarship_page_candidates c join ranked r on r.id=c.id
     -- re-checked on the locked row, so concurrent readers never take the same page
     where coalesce(c.leased_until,'-infinity')<now() and c.admit_status is null and c.matched_scholarship_id is null and c.next_read_at<=now()
     order by r.requested desc, r.crk, r.cc, c.id
     limit greatest(1,least(coalesce(p_limit,30), security.pipeline_num_v1('scholarship.candidates_max', 60)::int)) for update of c skip locked),
  upd as (update pipeline.scholarship_page_candidates c set leased_until=now()+interval '5 minutes', attempts=c.attempts+1 from pick where c.id=pick.id  -- fixed: claim lease
          returning c.id, c.url, c.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('candidate_id',u.id,'url',u.url,'provider_id',u.provider_id,'currency',scholarship.provider_currency(u.provider_id),
           'site',(select coalesce(site_origin,website) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id),
           'hosts',(select to_jsonb(allowed_hosts) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id))),'[]'::jsonb)
    into v from upd u;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_record(p_candidate_id bigint, p_read_status text, p_http_status integer, p_fetched_via text, p_final_url text, p_storage_path text, p_sha256 text, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare r jsonb; c pipeline.scholarship_page_candidates%rowtype; v_ev uuid; v_ai boolean := coalesce((select s.ai_admission from pipeline.scholarship_ai_extract_settings s where s.id=1),false) and exists (select 1 from pipeline.scholarship_ai_models m where m.status='active');
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if p_read_status='deferred' then -- out of time in this run: back to the queue unchanged
    update pipeline.scholarship_page_candidates set leased_until=null, attempts=greatest(0,attempts-1),
           -- DR-15 (s1199): a page that waits for a paid read the provider's Firecrawl hold refuses is tried again after the waiting-for-scraper interval
           next_read_at = case when security.fc_sch_held_v1(provider_id, true)
                               then now() + make_interval(mins => (60 * security.pipeline_num_v1('retry.scholarship_waiting_scraper_hours', 1))::int) else next_read_at end
     where id=p_candidate_id;
    return jsonb_build_object('admitted',false,'deferred',true);
  end if;
  update pipeline.scholarship_page_candidates set read_status=p_read_status, http_status=p_http_status, fetched_via=p_fetched_via, final_url=p_final_url,
         read_at=now(), leased_until=null, storage_path=coalesce(p_storage_path,storage_path), content_hash=coalesce(p_sha256,content_hash), facts=coalesce(p_facts,facts),
         next_read_at=case when p_read_status in ('read','robots_disallowed','gone','redirected_away','section_missing') then now()+make_interval(days => security.pipeline_num_v1('reread.scholarship_candidate_days', 90)::int) else now()+make_interval(hours => security.pipeline_num_v1('retry.scholarship_candidate_failed_hours', 6)::int) end,
         admit_status=case when p_read_status in ('redirected_away','section_missing') then 'rejected'  -- CF-247 scholarship recovery F7, F5
                           when not v_ai and p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) is not true then 'rejected' else admit_status end,
         admit_reasons=case when p_read_status in ('redirected_away','section_missing') then array[p_read_status]
                            when not v_ai and p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) is not true
                            then array(select jsonb_array_elements_text(coalesce(p_facts->'admission'->'reasons','[]'))) else admit_reasons end
   where id=p_candidate_id;
  if not v_ai and p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) then r:=security.scholarship_admit_from_provider_page_v1(p_candidate_id); end if;
  -- v2.15.249 (bugs 11/10-6): with AI admission on, the AI decides every page read (its copy is kept), not the rules
  if v_ai and p_read_status in ('read','too_thin') and p_storage_path is not null then
    insert into pipeline.scholarship_ai_queue(model_code,prompt_version,run_kind,candidate_id,provider_id,url)
    select a.model_code,a.prompt_version,'admit',p_candidate_id,(select x.provider_id from pipeline.scholarship_page_candidates x where x.id=p_candidate_id),coalesce(p_final_url,(select x.url from pipeline.scholarship_page_candidates x where x.id=p_candidate_id))
      from security.scholarship_ai_active_v1() a where not exists (select 1 from pipeline.scholarship_ai_queue q where q.candidate_id=p_candidate_id and q.state in ('queued','leased'));
    r:=jsonb_build_object('admitted',false,'ai','queued');
  end if;
  select * into c from pipeline.scholarship_page_candidates where id=p_candidate_id;
  -- v2.15.248 (Platform Admin bugs 11/10-5, Fix 2): a stored page that did not become a scholarship is kept as evidence of the decision
  if c.storage_path is not null and c.evidence_id is null and coalesce(c.admit_status,'')<>'admitted' then
    insert into pipeline.evidence_artifacts(source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key)
    values (security.coverage_sweep_source(c.provider_id),'scholarship_candidate_page',coalesce(c.final_url,c.url),c.storage_path,c.content_hash,'application/gzip',
            jsonb_build_object('candidate_id',c.id,'provider_id',c.provider_id,'read_status',c.read_status,'decision',coalesce(c.admit_status,c.read_status),'reasons',to_jsonb(coalesce(c.admit_reasons,'{}'::text[])),'worker','coverage-sweep scholarship candidates'),1,'scholarship_candidate:'||c.id)
    returning id into v_ev;
    update pipeline.scholarship_page_candidates set evidence_id=v_ev where id=c.id;
  end if;
  -- (Fix 4) a page that lists scholarships is suggested as the provider's listing page, for a person to confirm
  if coalesce(c.admit_status,'')<>'admitted' and c.read_status in ('read','too_thin')
     and (coalesce(c.facts->>'h1','')||' '||coalesce(c.title,'')||' '||coalesce(c.facts->>'page_title','') ~* '(scholarships? (finder|search|list|directory)|grants and scholarships|find (a|your) scholarship|^\s*scholarships\s*$)'
          or coalesce(c.admit_reasons,'{}') && array['listing_page'] or c.url ~* '(scholarship-finder|/scholarships?/?$|/grants-scholarships/?$)') then
    insert into pipeline.scholarship_listing_pages(provider_id,url,url_norm,source,active,status)
    values (c.provider_id,coalesce(c.final_url,c.url),security.scholarship_url_norm(coalesce(c.final_url,c.url)),'suggested',false,'suggested')
    on conflict (provider_id,url_norm) do nothing;
  end if;
  return coalesce(r, jsonb_build_object('admitted',false));
end $function$;

CREATE OR REPLACE FUNCTION public.svc_fc_spend(p_units numeric, p_purpose text, p_provider_id uuid, p_url text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_grp text := security.fc_purpose_group_v1(p_purpose); v_why text; v_host text := security.fc_spend_host_v1(p_url); v_spare boolean := false;
  -- CF-247 operating model 3.3.2 (Platform Admin 12 Nov 2026 21:07): an open on-demand request for this provider (a person's screen or a Claude session)
  v_req uuid := case when p_provider_id is null then null else security.on_demand_request_for_v2(p_provider_id, p_purpose) end;
  -- CF-247 21 Oct 2026: a university with a manual enrichment plan run spends from the on-demand allowance
  v_od uuid := case when p_provider_id is null then null else (select r.id from pipeline.enrich_plan_runs r where r.provider_id = p_provider_id and r.mode = 'manual' and r.state = 'running' limit 1) end;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- v2.15.265 (Platform Admin, 13 Oct 2026): never a credit on a directory site (a page on it, or a search limited to it), whatever the purpose
  if security.fc_setting_num_v1('daily_budget_total', 15000) = 0 then
    v_why := 'budget_zero';
  elsif v_host is not null and security.third_party_host_v1('https://' || v_host) then
    v_why := 'directory_site';
  -- v2.15.265: scholarship site maps and searches only for providers that qualify (Australian with enough courses; overseas as before)
  -- Decision 5 E-8 F2 (2 Nov 2026): the monthly plan limit, before the on-demand allowance and the daily rules (every path)
  elsif security.fc_month_refusal_v1(p_units) is not null then
    v_why := 'month_limit';
  elsif p_purpose = 'provider_description_on_demand' then
    v_why := null;  -- 20261112010000: an operator asked for this provider's description (Fill description); the daily shares do not apply
  elsif v_req is not null then
    v_why := null;  -- 12 Nov 2026 (Platform Admin 21:07): an open on-demand request is held only by the directory-site rule and the monthly plan limit above
  elsif v_od is not null then
    -- on demand: the person saw the estimate and chose to run it; the daily shares and per-university caps do not apply, the allowance does
    perform pg_advisory_xact_lock(hashtext('fc_spend:on_demand'));
    null;  -- 12 Nov 2026 (Platform Admin 21:07): on demand is not held by toolset limits; the on-demand allowance is shown only
  -- CF-247 workstream F (P0 AI operations §11): the cost breakers (repeat search, stored page, ineligible provider); each off by its own
  -- ops_cost.enforce_* switch, and only while its breaker is tripped. On-demand runs a person started are decided above and never held here.
  elsif security.ops_cost_fc_refusal_v1(p_units, p_purpose, p_provider_id, p_url) is not null then
    v_why := security.ops_cost_fc_refusal_v1(p_units, p_purpose, p_provider_id, p_url);
  -- DR-15 (s1199): a provider outside the scholarship spend rule may not spend a scrape on a new candidate page either (its pages already admitted keep their path)
  elsif p_provider_id is not null and (p_purpose in ('sch_map', 'sch_search')
          or (p_purpose = 'sch_scrape' and not exists (select 1 from pipeline.scholarship_pages sp join scholarship.scholarships s on s.id = sp.scholarship_id
                                                       where s.provider_id = p_provider_id and sp.url = p_url)))
        and not security.fc_sch_eligible_v1(p_provider_id) then
    v_why := 'not_eligible';
  elsif coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false) then
    perform pg_advisory_xact_lock(hashtext('fc_spend:' || v_grp));
    -- 12 Nov 2026 (Platform Admin decision D2): a central spend for a provider with an open discovery campaign request that the central share would refuse may use
    -- verified unused capacity (security.aer_discovery_spare_room_v1: inside the daily total, after every other group's projected need, above the vendor floor, at most
    -- aer.discovery_spare_daily_max a day); the campaign ceiling and not_due below still apply
    v_spare := v_grp = 'central' and p_provider_id is not null and security.fc_budget_left_v1(p_purpose) < p_units
               and security.aer_discovery_spare_ok_v1(p_provider_id, p_units);
    if security.fc_budget_left_v1(p_purpose) < p_units and not v_spare then
      -- CF-247 priority floor (8 Nov 2026): course page search held to keep the last credits for higher-priority work is 'priority_floor', not 'share'
      v_why := case when security.fc_billed_today_v1() >= security.fc_setting_num_v1('daily_budget_total', 15000) then 'day_total'
                    when v_grp = 'course_search' and coalesce(security.fc_priority_room_v1(), p_units) < p_units then 'priority_floor'
                    else 'share' end;
    elsif p_provider_id is not null and v_grp = 'scholarships'
          and (select coalesce(sum(x.units), 0) from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and x.purpose like 'sch\_%' and x.at > security.fc_sch_cap_since_v1(p_provider_id))
              + p_units > security.fc_setting_num_v1('scholarship_cap_per_uni', 150)
          -- 16 Oct 2026: a scholarship page asked to be read again is not held by the per-university cap
          and not (p_purpose = 'sch_scrape' and exists (select 1 from pipeline.scholarship_pages sp join scholarship.scholarships s on s.id = sp.scholarship_id
                                                         where s.provider_id = p_provider_id and sp.url = p_url and sp.requested_at is not null)) then
      v_why := 'university_cap';
    -- CF-247 F-AER.01 (entry search): a targeted entry-requirements search for a provider that AER source discovery asked about is not held by the
    -- central refresh interval (that interval belongs to the whole-site map, which for 357 of these providers ran before the entry page kind existed).
    -- It is held only by its own interval, aer.source_discover_recheck_days, and still by every rule above (month limit, cost breakers, the central share).
    -- 12 Nov 2026 (F-AER.04 discovery campaign): a central spend for a provider the running campaign asked about stops at the campaign ceiling
    -- (aer.discovery_campaign_credit_cap); it is checked after the monthly limit, the cost breakers, the daily total and the central share above
    elsif p_provider_id is not null and v_grp = 'central' and security.aer_discovery_campaign_over_v1(p_provider_id, p_units) then
      v_why := 'campaign_cap';
    elsif p_provider_id is not null and p_purpose = 'central_entry_search' then
      if exists (select 1 from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and x.purpose = 'central_entry_search'
                  and x.at > now() - make_interval(days => security.pipeline_num_v1('aer.source_discover_recheck_days', 30)::int)
                  and x.at < now() - interval '6 hours') then  -- fixed: spends within the same search run
        v_why := 'not_due';
      end if;
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
  insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, provider_id, url, on_demand_run, on_demand_request)
  select id, p_units, p_purpose, p_provider_id, left(p_url, 500), v_od, v_req from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';
  if v_spare then
    insert into pipeline.aer_discovery_spare_spends(campaign_id, provider_id, purpose, units, room)
    select c.id, p_provider_id, p_purpose, p_units, coalesce((security.aer_discovery_spare_room_v1()->>'room')::numeric, 0) + p_units
      from pipeline.aer_discovery_campaigns c where c.state = 'running' order by c.id desc limit 1;
  end if;
  return true;
end $function$;

do $s$
declare s record; v_reason constant text := 'DR-15 (SS-Programme-Control 26 Nov 2026 17:01 AEDT): a scholarship candidate refused a paid read by its provider''s Firecrawl hold waits this long (CF-247 s1199)';
begin
  select * into s from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'retry.scholarship_waiting_scraper_hours' for update;
  update pipeline.platform_toolset_settings
     set used_by = case when coalesce(used_by, '') like '%svc_scholarship_candidate_record%' then used_by else concat_ws(', ', nullif(used_by, ''), 'public.svc_scholarship_candidate_record (DR-15)') end,
         reason = v_reason, updated_at = now()
   where toolset_key = 'pipeline' and key = 'retry.scholarship_waiting_scraper_hours';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('scholarships', 'free_read_hold_split', 'public.svc_scholarship_candidate_next', jsonb_build_object('reason', 'DR-15: paid Firecrawl holds no longer hold the free direct read of scholarship candidates', 'by', 'migration CF-247 s1199',
          'setting_used_by_before', s.used_by, 'retry_hours', s.value), null);
end $s$;

do $c$
declare v_api jsonb;
begin
  if exists (select 1 from cron.job j where not exists (select 1 from s1199_cron b where b.jobname = j.jobname)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;  -- fixed: the standing cron limit
  if (select count(*) from pipeline.manual_locks) <> (select n from s1199_locks) then raise exception 'post-check: manual locks changed'; end if;
  if exists (select toolset_key, key, value, min_value, max_value from pipeline.platform_toolset_settings except select * from s1199_settings) then raise exception 'post-check: a setting value or range changed'; end if;
  if position('fc_sch_held_v1' in pg_get_functiondef('public.svc_scholarship_candidate_next(integer)'::regprocedure)) > 0 then raise exception 'post-check: the picker still holds on a paid Firecrawl limit'; end if;
  if position('scholarship_cap_per_uni' in pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure)) = 0 then raise exception 'post-check: the per-university cap left the spend function'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
