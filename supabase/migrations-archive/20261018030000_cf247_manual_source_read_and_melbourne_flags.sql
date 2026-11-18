-- CF-247 Decision 265 follow-up (18 Oct 2026, after the first runs):
-- 1 The UAC page for ACU (added by the Platform Admin's choice "Yes, UAC for ACU") was refused by the Firecrawl spend check: ACU's central pages
--   were read within the last 30 days (central_refresh_days), so a new central read is "not due". A source a person added (found_via manual,
--   still waiting to be read) is now read when found; the daily budget and every other check still apply.
-- 2 Melbourne: 32 courses moved from an older handbook year to the 2026 handbook page of the same code (20261018010000) have no 2026 page
--   ("Page not found"). As with Wollongong and Torrens (Platform Admin: "Check CRICOS first"), CRICOS still lists them, so they stay active with a
--   soft not_on_provider_site flag for a person.
-- Replaces: public.svc_fc_spend (md5-guarded)
-- Retires: nothing
-- Nothing dropped or deleted.

do $guard$
begin
  if md5(pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure)) <> 'd43113b1a6ec99ea3e44c61a562d9cb0' then
    raise exception 'live public.svc_fc_spend differs from the definition this change replaces';
  end if;
end $guard$;

CREATE OR REPLACE FUNCTION public.svc_fc_spend(p_units numeric, p_purpose text, p_provider_id uuid, p_url text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_grp text := security.fc_purpose_group_v1(p_purpose); v_why text; v_host text := security.fc_spend_host_v1(p_url);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- v2.15.265 (Platform Admin, 13 Oct 2026): never a credit on a directory site (a page on it, or a search limited to it), whatever the purpose
  if v_host is not null and security.third_party_host_v1('https://' || v_host) then
    v_why := 'directory_site';
  -- v2.15.265: scholarship site maps and searches only for providers that qualify (Australian with enough courses; overseas as before)
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
                             and fs.found_via = 'manual' and fs.status in ('found', 'reading')) then
      v_why := 'not_due';
    elsif p_provider_id is not null and v_grp = 'course_search' and exists (select 1 from security.fc_search_stopped_v1() s where s.provider_id = p_provider_id) then
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
  insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, provider_id, url)
  select id, p_units, p_purpose, p_provider_id, left(p_url, 500) from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';
  return true;
end $function$;

-- the UAC source failed once on the refusal: back to found with its attempt returned
update pipeline.provider_fact_sources set attempts = 0, status = 'found', updated_at = now()
 where url = 'https://uac.edu.au/institutions/australian-catholic-university/english-language-proficiency' and status in ('found', 'failed');

insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source, kind, state, raised_by_kind)
select 'course', c.id::text, c.provider_id, 'official_url', 'not_on_provider_site',
       format('The CRICOS register (loaded 26 Sep 2026) still lists %s (%s), but the 2026 Melbourne handbook has no page for its code (%s gives "Page not found", 18 Oct 2026), so there is no current page to read English from. Check whether it is still offered (Decision 265).',
              c.canonical_title, c.course_code, g.url),
       'decision-265', 'soft', 'raised', 'auto'
  from catalogue.courses c join pipeline.coverage_course_pages g on g.course_id = c.id
 where c.provider_id = 'de6d32b0-f91b-4dd0-a3da-a542f1aba5f2' and c.lifecycle_status = 'active'
   and g.url like 'https://handbook.unimelb.edu.au/2026/courses/%' and g.read_status = 'identity_mismatch'
   and g.candidates->>'page_title' like 'Page not found%'
on conflict (entity, entity_key, field, reason_code) do nothing;

do $post$
begin
  if pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure) not like '%fs.found_via = ''manual''%' then raise exception 'post-check: spend'; end if;
end $post$;
