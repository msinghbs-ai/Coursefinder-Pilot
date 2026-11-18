-- CF-247 (22 Oct 2026). Platform Admin 13:28: "Implement - program following resolution" (the NZ review's gaps and resolutions) and
-- "Include resolution to be programmed after everyday report with lesson learnt". Most of the table went live in v2.15.310 (search off where
-- the site lists too few course pages, render pass, address guesses off in NZ, quote-miss retry, no re-ask of an unchanged page, fee reader
-- fixes, AI match gate, one provider flag, daily toolset use). This change finishes what was left:
--   1 Site check before any search: a provider in search.site_check_countries without a site map is mapped first (a pending site-map row,
--     about 1 credit) and is not searched until the map says how many course pages its site lists (security.site_not_checked_v1).
--     117 NZ providers had no site map.
--   3 Robots: pages whose site refuses automated reading (robots.txt) are never fetched; one provider flag, pages_refuse_reading, lists how
--     many so a person adds them by hand.
--   4 Provider-level facts when the course page is silent (security.enrich_fallback_v1), used by the AI reader's record and by Enrich fields
--     when no source had a value: campus = the provider's only active campus; international = yes when the course has an international
--     fee on record or a CRICOS registration, no when the provider does not enrol international students. Each value says where it came
--     from (source provider_facts). Delivery has no provider-level fact and is left as before.
--   Daily measures: security.nz_resolution_measures_v1(country) gives one figure a day per resolution for the daily report's
--   "Resolutions & lessons" sheet.
-- Replaces: public.svc_course_link_search_next (site not checked); public.svc_enrich_ai_record (fallback); security.enrich_fields_slice_v1 (fallback); security.enrichment_flags_refresh_v1 (site map rows, robots flag). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
declare v_expected jsonb := '{"public.svc_course_link_search_next(integer)": "560b3e98fddef841003d92356b8e43af",
                              "public.svc_enrich_ai_record(jsonb)": "7f28803f79f35054f7b4d92fb61a31af",
                              "security.enrich_fields_slice_v1(uuid,integer)": "7c8420634f20589f57d5d8a3f322a08c",
                              "security.enrichment_flags_refresh_v1()": "8ce9cb59a2f29222005b0013786e9b72"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(pg_get_functiondef(v_sig::regprocedure)) <> v_expected->>v_sig then raise exception 'live % differs from the definition this change replaces', v_sig; end if;
  end loop;
end $guard$;

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 1 ---------------------------------------------------------------------------------------------------------------------------------
create or replace function security.site_not_checked_v1(p_provider uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  -- CF-247 22 Oct 2026 (NZ review fix 1): in the check-first countries a provider is searched only after its site map has run
  select coalesce(security.coverage_country(p_provider) in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s
                                                            where s.toolset_key = 'pipeline' and s.key = 'search.site_check_countries'), false)
     and not exists (select 1 from pipeline.coverage_provider_discovery d where d.provider_id = p_provider and d.status in ('mapped', 'failed', 'no_website'))
$$;
comment on function security.site_not_checked_v1(uuid) is 'CF-247 22 Oct 2026: true while a provider in search.site_check_countries has no finished site map; course search waits for it.';
revoke all on function security.site_not_checked_v1(uuid) from public;

select pg_temp.edit_once('public.svc_course_link_search_next(integer)', '560b3e98fddef841003d92356b8e43af', array[
  [$o$       and (s.requested_at is not null or security.site_list_match_done_v1(s.course_id, s.provider_id))$o$,
   $n$       and (s.requested_at is not null or security.site_list_match_done_v1(s.course_id, s.provider_id))
       -- 22 Oct 2026 (Platform Admin 13:28, fix 1): the site is checked (one site map) before any search
       and (s.requested_at is not null or not security.site_not_checked_v1(s.provider_id))$n$]]);

-- 4 ---------------------------------------------------------------------------------------------------------------------------------
create or replace function security.enrich_fallback_v1(p_item bigint) returns boolean
language plpgsql security definer set search_path = '' as $$
-- CF-247 22 Oct 2026 (Platform Admin 13:28, fix 4): a provider-level or registered fact when the course page is silent
declare i pipeline.field_enrich_items%rowtype; v jsonb; q text; c record;
begin
  select * into i from pipeline.field_enrich_items where id = p_item;
  if i.id is null or i.course_id is null then return false; end if;
  if i.field = 'campus' then
    select k.id, k.name into c from catalogue.campuses k
     where k.provider_id = i.provider_id and coalesce(k.status, 'active') = 'active'
       and (select count(*) from catalogue.campuses k2 where k2.provider_id = i.provider_id and coalesce(k2.status, 'active') = 'active') = 1;
    if c.id is not null then
      v := jsonb_build_object('campuses', jsonb_build_array(jsonb_build_object('campus_id', c.id, 'name', c.name)));
      q := 'The provider has one campus: ' || c.name;
    end if;
  elsif i.field = 'international' then
    if exists (select 1 from catalogue.course_fees f where f.course_id = i.course_id and f.audience = 'international' and coalesce(f.status, 'active') = 'active') then
      v := jsonb_build_object('open', true); q := 'An international fee is on record for this course';
    elsif exists (select 1 from catalogue.course_registrations r where r.course_id = i.course_id and lower(r.scheme) = 'cricos' and coalesce(r.status, 'active') = 'active') then
      v := jsonb_build_object('open', true); q := 'Registered on CRICOS (courses for overseas students)';
    elsif exists (select 1 from catalogue.providers p where p.id = i.provider_id and p.enrols_international = false) then
      v := jsonb_build_object('open', false); q := 'The provider does not enrol international students';
    end if;
  end if;
  if v is null then return false; end if;
  update pipeline.field_enrich_items set value = v, quote = left(q, 300), source = 'provider_facts', reason = 'provider-level fact (the course page did not state it)', updated_at = now()
   where id = i.id;
  perform security.enrich_apply_v1(i.id);
  return true;
end $$;
comment on function security.enrich_fallback_v1(bigint) is 'CF-247 22 Oct 2026: fills campus (the provider''s only campus) or international (international fee or CRICOS registration; provider not enrolling) when the course page is silent; source provider_facts.';
revoke all on function security.enrich_fallback_v1(bigint) from public;

select pg_temp.edit_once('public.svc_enrich_ai_record(jsonb)', '7f28803f79f35054f7b4d92fb61a31af', array[
  [$o$        update pipeline.field_enrich_items set state = 'skipped', reason = 'the page names no campus' where id = i.id; v_k := 'not_stated';$o$,
   $n$        if security.enrich_fallback_v1(i.id) then v_k := 'provider_fact';  -- 22 Oct 2026 (fix 4): the provider's only campus
        else update pipeline.field_enrich_items set state = 'skipped', reason = 'the page names no campus' where id = i.id; v_k := 'not_stated'; end if;$n$],
  [$o$        update pipeline.field_enrich_items set state = 'skipped', reason = coalesce(nullif(r->>'reason', ''), 'the page does not state it') where id = i.id;
        v_k := 'not_stated';$o$,
   $n$        if security.enrich_fallback_v1(i.id) then v_k := 'provider_fact';  -- 22 Oct 2026 (fix 4): a provider-level or registered fact
        else
        update pipeline.field_enrich_items set state = 'skipped', reason = coalesce(nullif(r->>'reason', ''), 'the page does not state it') where id = i.id;
        v_k := 'not_stated';
        end if;$n$]]);

select pg_temp.edit_once('security.enrich_fields_slice_v1(uuid,integer)', '7c8420634f20589f57d5d8a3f322a08c', array[
  [$o$    if not v_settled then
      update pipeline.field_enrich_items set state = 'skipped', reason = coalesce(reason, 'no allowed source had a value'), updated_at = now() where id = it.id and state = 'queued';$o$,
   $n$    -- 22 Oct 2026 (fix 4): a provider-level or registered fact before skipping
    if not v_settled and not security.enrich_fallback_v1(it.id) then
      update pipeline.field_enrich_items set state = 'skipped', reason = coalesce(reason, 'no allowed source had a value'), updated_at = now() where id = it.id and state = 'queued';$n$]]);

-- 1 and 3 -----------------------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.enrichment_flags_refresh_v1()', '8ce9cb59a2f29222005b0013786e9b72', array[
  [$o$  return jsonb_build_object('outside_focus', v_tail, 'page_not_found', v_nf, 'course_pages_not_listed', v_off);$o$,
   $n$  -- 22 Oct 2026 (Platform Admin 13:28, fix 1): providers in the check-first countries without a site map get one (pending) before any search
  insert into pipeline.coverage_provider_discovery(provider_id, website, status)
  select p.id, p.website, 'pending' from catalogue.providers p
   where p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.website), '') is not null
     and not security.third_party_host_v1(p.website) and security.site_not_checked_v1(p.id)
     and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
  on conflict (provider_id) do nothing;
  -- fix 3: pages whose site refuses automated reading (robots.txt) are listed for a person, one flag per provider
  insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
  select 'provider', g.provider_id::text, g.provider_id, 'course_page', 'pages_refuse_reading',
         format('%s course page(s) on this site refuse automated reading (robots.txt); add them by hand on each course', count(*)), 'waste-guard'
    from pipeline.coverage_course_pages g where g.status = 'bound' and g.read_status = 'robots_disallowed' group by g.provider_id
  on conflict (entity, entity_key, field, reason_code) do update set cleared_at = null, reason = excluded.reason
   where pipeline.enrichment_flags.cleared_at is not null or pipeline.enrichment_flags.reason is distinct from excluded.reason;
  update pipeline.enrichment_flags f set cleared_at = now()
   where f.reason_code = 'pages_refuse_reading' and f.cleared_at is null
     and not exists (select 1 from pipeline.coverage_course_pages g where g.provider_id = f.provider_id and g.status = 'bound' and g.read_status = 'robots_disallowed');
  return jsonb_build_object('outside_focus', v_tail, 'page_not_found', v_nf, 'course_pages_not_listed', v_off);$n$]]);

-- daily measures for the report -----------------------------------------------------------------------------------------------------
create or replace function security.nz_resolution_measures_v1(p_country text default 'NZ')
 returns jsonb language sql stable security definer set search_path to ''
as $function$
  with d as (select ((now() at time zone 'Australia/Melbourne')::date - 1)::timestamp at time zone 'Australia/Melbourne' f,
                    ((now() at time zone 'Australia/Melbourne')::date)::timestamp at time zone 'Australia/Melbourne' t),
  pv as (select p.id from catalogue.providers p join ref.countries k on k.id = p.country_id where k.iso_alpha2 = upper(p_country))
  select jsonb_build_object(
    'day', (select (f at time zone 'Australia/Melbourne')::date from d),
    '1_search_off_providers', (select count(*) from pv where security.course_search_off_v1(pv.id)),
    '1_search_credits_on_search_off', (select coalesce(sum(v.units), 0) from pipeline.coverage_vendor_usage v, d
                                        where v.purpose = 'course_link_search' and v.at >= d.f and v.at < d.t and v.provider_id in (select id from pv) and security.course_search_off_v1(v.provider_id)),
    '1_waiting_for_site_map', (select count(*) from pv where security.site_not_checked_v1(pv.id)),
    '2_title_search_pages_right', (select count(*) from pipeline.coverage_course_pages g, d where g.provider_id in (select id from pv) and g.basis = 'title_search' and g.bound_at >= d.f and g.bound_at < d.t and g.status = 'bound' and g.read_status = 'read'),
    '2_title_search_pages_wrong', (select count(*) from pipeline.coverage_course_pages g, d where g.provider_id in (select id from pv) and g.basis = 'title_search' and g.bound_at >= d.f and g.bound_at < d.t and g.status = 'mismatch'),
    '2_university_courses_with_right_page', (select count(*) from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.provider_types t on t.id = p.provider_type_id
                                             where p.id in (select id from pv) and t.code = 'university' and c.lifecycle_status = 'active'
                                               and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.status = 'bound' and g.read_status = 'read')),
    '2_university_courses', (select count(*) from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.provider_types t on t.id = p.provider_type_id
                             where p.id in (select id from pv) and t.code = 'university' and c.lifecycle_status = 'active'),
    '3_rendered_reads', (select count(*) from pipeline.coverage_course_pages g, d where g.provider_id in (select id from pv) and g.fetched_via = 'firecrawl' and g.read_at >= d.f and g.read_at < d.t and g.read_status = 'read'),
    '3_need_browser_or_blocked', (select count(*) from pipeline.coverage_course_pages g where g.provider_id in (select id from pv) and g.status = 'bound' and g.read_status in ('needs_render', 'blocked')),
    '3_providers_listed_for_robots', (select count(*) from pipeline.enrichment_flags f where f.reason_code = 'pages_refuse_reading' and f.cleared_at is null and f.provider_id in (select id from pv)),
    '4_fields_filled', (select count(*) from pipeline.field_enrich_items e, d where e.provider_id in (select id from pv) and e.state = 'filled' and e.updated_at >= d.f and e.updated_at < d.t),
    '4_fields_skipped', (select count(*) from pipeline.field_enrich_items e, d where e.provider_id in (select id from pv) and e.state in ('skipped', 'failed') and e.updated_at >= d.f and e.updated_at < d.t),
    '4_filled_from_provider_facts', (select count(*) from pipeline.field_enrich_items e, d where e.provider_id in (select id from pv) and e.source = 'provider_facts' and e.state = 'filled' and e.updated_at >= d.f and e.updated_at < d.t),
    '4_not_asked_again_same_page', (select count(*) from pipeline.field_enrich_items e, d where e.provider_id in (select id from pv) and e.reason = 'the same page copy was read for this before and did not state it' and e.updated_at >= d.f and e.updated_at < d.t),
    '5_campus_waiting_for_person', (select count(*) from pipeline.field_enrich_items e where e.provider_id in (select id from pv) and e.state = 'review' and e.field in ('campus', 'campus_list')),
    '6_fee_reads_with_rows', (select count(*) from pipeline.fee_reader_queue q, d where q.provider_id in (select id from pv) and q.finished_at >= d.f and q.finished_at < d.t and q.state = 'done' and coalesce(q.rows_found, 0) > 0),
    '6_fee_reads_without_rows', (select count(*) from pipeline.fee_reader_queue q, d where q.provider_id in (select id from pv) and q.finished_at >= d.f and q.finished_at < d.t and not (q.state = 'done' and coalesce(q.rows_found, 0) > 0)),
    '7_ai_match_calls', (select count(*) from pipeline.coverage_ai_match q, d where q.provider_id in (select id from pv) and q.decided_at >= d.f and q.decided_at < d.t and q.state in ('chosen', 'none', 'error')),
    '7_ai_match_no_candidates', (select count(*) from pipeline.coverage_ai_match q, d where q.provider_id in (select id from pv) and q.created_at >= d.f and q.created_at < d.t and q.state = 'no_candidates'),
    '8_course_page_not_found_flags', (select count(*) from pipeline.enrichment_flags f where f.reason_code = 'page_not_found' and f.cleared_at is null and f.provider_id in (select id from pv)),
    '8_provider_search_off_flags', (select count(*) from pipeline.enrichment_flags f where f.reason_code = 'course_pages_not_listed' and f.cleared_at is null and f.provider_id in (select id from pv)),
    '9_toolset_rows_recorded', (select count(*) from pipeline.toolset_use_daily u, d where u.country_code = upper(p_country) and u.snapshot_date = (d.f at time zone 'Australia/Melbourne')::date))
$function$;
comment on function security.nz_resolution_measures_v1(text) is 'CF-247 22 Oct 2026: one figure a day per resolution of the NZ enrichment review (fixes 1-9), for the daily report''s Resolutions & lessons sheet.';
revoke all on function security.nz_resolution_measures_v1(text) from public;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.site_not_checked_v1', 'Course pages', 'Search waits for the site map in the check-first countries', 'active', '{}', '20261022019000'),
 ('function', 'security.enrich_fallback_v1', 'Enrichment', 'Provider-level or registered fact when the course page is silent', 'active', '{}', '20261022019000'),
 ('function', 'security.nz_resolution_measures_v1', 'Reporting', 'Daily measure per NZ review resolution', 'active', '{}', '20261022019000')
on conflict (kind, name) do nothing;

select security.enrichment_flags_refresh_v1();
