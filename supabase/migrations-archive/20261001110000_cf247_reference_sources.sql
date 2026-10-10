-- CF-247 Reference sources (Platform Admin, 1 Oct 2026: "There should be notable third party links maintained and used for
-- reference like hot courses and govt regulatory website, UI should maintain and control profiles how they are used. Not
-- hard coded in script or functions." Screen review 1 Oct: Key links marked Fix - editable, and read by the platform).
-- Key links (pipeline.important_links) becomes the reference sources list. Each site has a domain, an on/off switch and
-- one or more uses:
--   reference                - a link staff look things up on
--   data_source              - the platform reads data from it
--   not_provider_site        - never accepted as a university's own website (coverage sweep, provider page checks)
--   not_course_page          - never accepted as a course page (Layer 4 course link binding)
--   scholarship_placeholder  - a scholarship sourced only from it needs a university page before it can be published
--   logo_directory           - used only to find university logos
--   ranking_publisher        - default source address on Ranking imports (by ranking key)
-- A domain with a dot matches that host and its subdomains (education.gov.au matches cricos.education.gov.au); a single
-- name with no dot matches any host whose name starts with it (google matches google.com and google.com.au).
-- Seeded with exactly the patterns that were hard-coded, so behaviour does not change on day one. The functions that held
-- those patterns now read this list (each edited in place behind an md5(prosrc) guard).
-- Adding or retiring a site, or changing its domain, uses, category, ranking key or switch: PIM Operator and above, with
-- a reason, logged (admin_control_events area 'reference_sources'). Name, address, purpose and "Check now": Curator and up.
-- A site used as a scholarship placeholder cannot be switched off, retired, re-pointed or lose that use while active
-- scholarships are sourced from it (they would look publishable).

alter table pipeline.important_links
  add column if not exists domain text,
  add column if not exists uses text[] not null default array['reference']::text[],
  add column if not exists enabled boolean not null default true,
  add column if not exists ref_key text,
  add column if not exists retired_at timestamptz,
  add column if not exists last_check_at timestamptz,
  add column if not exists last_check_http integer,
  add column if not exists last_check_request bigint;
alter table pipeline.important_links drop constraint if exists important_links_authority_category_check;
alter table pipeline.important_links add constraint important_links_authority_category_check check (authority_category = any (array[
  'regulatory_authority','international_student_immigration','quality_outcomes','official_scholarship','qualification_framework',
  'statistics_data','accepted_provider_course_source','source_health','official_policy_change',
  'third_party_directory','ranking_publisher','general_web']));
alter table pipeline.important_links add constraint important_links_uses_check
  check (cardinality(uses) > 0 and uses <@ array['reference','data_source','not_provider_site','not_course_page','scholarship_placeholder','logo_directory','ranking_publisher']::text[]);
alter table pipeline.important_links add constraint important_links_domain_check
  check (domain is null or domain ~ '^[a-z0-9-]+(\.[a-z0-9-]+)*$');
create unique index if not exists important_links_ref_key_uq on pipeline.important_links(ref_key) where ref_key is not null and retired_at is null;

update pipeline.important_links l set domain = v.domain, uses = v.uses from (values
  ('4000d328-4ad0-49a4-8c58-517243092fbc'::uuid, 'data.gov.au', array['reference','data_source']::text[]),
  ('75f3bd68-6931-46c5-ae7e-35d77d4448cd'::uuid, 'education.gov.au', array['data_source','not_provider_site']::text[]),
  ('13972d87-f2b3-424d-a711-1b17fe2b8b7a'::uuid, 'dfat.gov.au', array['data_source']::text[]),
  ('56e5da45-47b3-4287-ad07-5734b00fa35f'::uuid, 'qilt.edu.au', array['data_source']::text[]),
  ('9be67908-ae2a-4efe-b28b-0fa686f94a9d'::uuid, 'studyaustralia.gov.au', array['data_source','not_provider_site','not_course_page','scholarship_placeholder']::text[]),
  ('6b0ee721-aa0a-40ed-8337-9dac1af32208'::uuid, 'educationcounts.govt.nz', array['data_source']::text[]),
  ('474f56e8-7b3b-400e-938e-13ee84dda971'::uuid, 'nzqa.govt.nz', array['reference','data_source']::text[])
) v(id, domain, uses) where l.id = v.id and l.domain is null;

insert into pipeline.important_links(country_code, authority_category, authority_name, url, domain, uses, ref_key, purpose, owner_label,
  verification_cadence, next_verification_at, health_status, change_control_ref)
select c, cat, n, u, d, us, k, p, 'CourseFinder Data Ops', interval '90 days', now() + interval '90 days', 'unverified', 'CF-CHG-20260915-247'
from (values
  ('ALL','third_party_directory','Hotcourses Abroad','https://www.hotcoursesabroad.com/','hotcourses',array['logo_directory','not_provider_site','not_course_page']::text[],null,'University logos only (exact university-owned copies). Never a university website or course page.'),
  ('ALL','third_party_directory','IDP Education','https://www.idp.com/','idp',array['not_provider_site','not_course_page']::text[],null,'Student agency directory. Never a university website or course page.'),
  ('ALL','third_party_directory','Study International / Study in Australia guides','https://www.studyinternational.com/','studyin',array['not_provider_site','not_course_page']::text[],null,'Study guides and directories. Never a university website or course page.'),
  ('ALL','third_party_directory','Studies in Australia','https://www.studiesinaustralia.com/','studiesinaustralia.com',array['not_provider_site']::text[],null,'Course directory. Never a university website.'),
  ('ALL','third_party_directory','Educations.com','https://www.educations.com/','educations.com',array['not_provider_site']::text[],null,'Course directory. Never a university website.'),
  ('AU','third_party_directory','CourseSeeker','https://www.courseseeker.edu.au/','courseseeker',array['not_course_page']::text[],null,'National course search. Not a university course page.'),
  ('AU','third_party_directory','MyUni portals','https://myuni.adelaide.edu.au/','myuni',array['not_course_page']::text[],null,'Student portals. Not a public course page.'),
  ('AU','regulatory_authority','CRICOS register (website)','https://cricos.education.gov.au/','cricos.education.gov.au',array['reference','not_provider_site']::text[],null,'Government register of courses for international students. Reference only; never a university website.'),
  ('AU','regulatory_authority','TEQSA National Register','https://www.teqsa.gov.au/national-register','teqsa.gov.au',array['reference','not_provider_site']::text[],null,'Higher education regulator. Reference only; never a university website.'),
  ('AU','regulatory_authority','ASQA','https://www.asqa.gov.au/','asqa.gov.au',array['reference','not_provider_site']::text[],null,'Vocational education regulator. Reference only; never a provider website.'),
  ('AU','regulatory_authority','training.gov.au','https://training.gov.au/','training.gov.au',array['reference','not_provider_site']::text[],null,'National register of vocational training. Reference only; never a provider website.'),
  ('AU','regulatory_authority','My Skills','https://www.myskills.gov.au/','myskills',array['not_provider_site']::text[],null,'Government vocational course directory. Never a provider website.'),
  ('AU','regulatory_authority','ASIC','https://asic.gov.au/','asic.gov.au',array['not_provider_site']::text[],null,'Company register. Never a provider website.'),
  ('AU','regulatory_authority','ABN Lookup','https://abr.business.gov.au/','abr.business.gov.au',array['not_provider_site']::text[],null,'Business register. Never a provider website.'),
  ('ALL','ranking_publisher','QS World University Rankings','https://www.topuniversities.com/world-university-rankings','topuniversities.com',array['ranking_publisher','not_provider_site']::text[],'qs_wur','Ranking publisher. Its address is the default source on Ranking imports.'),
  ('ALL','ranking_publisher','Times Higher Education World University Rankings','https://www.timeshighereducation.com/world-university-rankings/latest/world-ranking','timeshighereducation.com',array['ranking_publisher','not_provider_site']::text[],'the_wur','Ranking publisher. Its address is the default source on Ranking imports.'),
  ('ALL','ranking_publisher','Academic Ranking of World Universities (ShanghaiRanking)','https://www.shanghairanking.com/rankings/arwu','shanghairanking.com',array['ranking_publisher','not_provider_site']::text[],'arwu','Ranking publisher. Its address is the default source on Ranking imports.'),
  ('ALL','general_web','Google','https://www.google.com/','google',array['not_provider_site','not_course_page']::text[],null,'Search, social or business listing site. Never a university website or course page.'),
  ('ALL','general_web','Bing','https://www.bing.com/','bing',array['not_provider_site','not_course_page']::text[],null,'Search, social or business listing site. Never a university website or course page.'),
  ('ALL','general_web','DuckDuckGo','https://duckduckgo.com/','duckduckgo',array['not_provider_site','not_course_page']::text[],null,'Search, social or business listing site. Never a university website or course page.'),
  ('ALL','general_web','Yahoo','https://www.yahoo.com/','yahoo',array['not_provider_site','not_course_page']::text[],null,'Search, social or business listing site. Never a university website or course page.'),
  ('ALL','general_web','Facebook','https://www.facebook.com/','facebook',array['not_provider_site','not_course_page']::text[],null,'Search, social or business listing site. Never a university website or course page.'),
  ('ALL','general_web','LinkedIn','https://www.linkedin.com/','linkedin',array['not_provider_site','not_course_page']::text[],null,'Search, social or business listing site. Never a university website or course page.'),
  ('ALL','general_web','Instagram','https://www.instagram.com/','instagram',array['not_provider_site','not_course_page']::text[],null,'Search, social or business listing site. Never a university website or course page.'),
  ('ALL','general_web','YouTube','https://www.youtube.com/','youtube',array['not_provider_site','not_course_page']::text[],null,'Search, social or business listing site. Never a university website or course page.'),
  ('ALL','general_web','Twitter','https://twitter.com/','twitter',array['not_provider_site']::text[],null,'Search, social or business listing site. Never a university website.'),
  ('ALL','general_web','X','https://x.com/','x.com',array['not_provider_site']::text[],null,'Search, social or business listing site. Never a university website.'),
  ('ALL','general_web','Wikipedia','https://www.wikipedia.org/','wikipedia',array['not_provider_site']::text[],null,'Search, social or business listing site. Never a university website.'),
  ('ALL','general_web','SEEK','https://www.seek.com.au/','seek',array['not_provider_site']::text[],null,'Search, social or business listing site. Never a university website.'),
  ('ALL','general_web','Indeed','https://www.indeed.com/','indeed',array['not_provider_site']::text[],null,'Search, social or business listing site. Never a university website.'),
  ('ALL','general_web','Glassdoor','https://www.glassdoor.com/','glassdoor',array['not_provider_site']::text[],null,'Search, social or business listing site. Never a university website.'),
  ('ALL','general_web','Yellow Pages','https://www.yellowpages.com.au/','yellowpages',array['not_provider_site']::text[],null,'Search, social or business listing site. Never a university website.'),
  ('ALL','general_web','Yelp','https://www.yelp.com/','yelp',array['not_provider_site']::text[],null,'Search, social or business listing site. Never a university website.'),
  ('ALL','general_web','True Local','https://www.truelocal.com.au/','truelocal',array['not_provider_site']::text[],null,'Search, social or business listing site. Never a university website.'),
  ('ALL','general_web','Hotfrog','https://www.hotfrog.com.au/','hotfrog',array['not_provider_site']::text[],null,'Search, social or business listing site. Never a university website.'),
  ('ALL','general_web','StartLocal','https://www.startlocal.com.au/','startlocal',array['not_provider_site']::text[],null,'Search, social or business listing site. Never a university website.'),
  ('ALL','general_web','OpenCorporates','https://opencorporates.com/','opencorporates',array['not_provider_site']::text[],null,'Search, social or business listing site. Never a university website.'),
  ('ALL','general_web','Dun & Bradstreet','https://www.dnb.com/','dnb.com',array['not_provider_site']::text[],null,'Search, social or business listing site. Never a university website.'),
  ('ALL','general_web','ZoomInfo','https://www.zoominfo.com/','zoominfo',array['not_provider_site']::text[],null,'Search, social or business listing site. Never a university website.'),
  ('ALL','general_web','CourseFinder (this platform)','https://coursefinder-pilot.techm.workers.dev/','coursefinder',array['not_provider_site']::text[],null,'Search, social or business listing site. Never a university website.')
) v(c, cat, n, u, d, us, k, p)
on conflict (country_code, url) do nothing;

-- Matching
create or replace function security.reference_host_of(p_url text) returns text language sql immutable set search_path = '' as $f$
  select nullif(lower(case when p_url ~ '^[A-Za-z][A-Za-z0-9+.-]*://'
                           then substring(p_url from '^[A-Za-z][A-Za-z0-9+.-]*://(?:[^/@]*@)?([^/:?#]+)')
                           else split_part(split_part(split_part(btrim(coalesce(p_url, '')), '/', 1), '?', 1), ':', 1) end), '')
$f$;
create or replace function security.reference_domain_matches(p_host text, p_domain text) returns boolean language sql immutable set search_path = '' as $f$
  select p_host is not null and p_domain is not null and case
    when position('.' in p_domain) > 0 then p_host = p_domain or right(p_host, length(p_domain) + 1) = '.' || p_domain
    else p_host ~ ('(^|\.)' || p_domain) end
$f$;
create or replace function security.reference_url_has_use(p_url text, p_use text) returns boolean language sql stable set search_path = '' as $f$
  select exists (select 1 from pipeline.important_links l
    where l.enabled and l.retired_at is null and p_use = any(l.uses)
      and security.reference_domain_matches(security.reference_host_of(p_url), l.domain))
$f$;
revoke all on function security.reference_host_of(text) from public, anon;
revoke all on function security.reference_domain_matches(text, text) from public, anon;
revoke all on function security.reference_url_has_use(text, text) from public, anon;
grant execute on function security.reference_host_of(text) to authenticated, service_role;
grant execute on function security.reference_domain_matches(text, text) to authenticated, service_role;
grant execute on function security.reference_url_has_use(text, text) to authenticated, service_role;

-- Edge functions (coverage sweep) read the list for one use.
create or replace function public.svc_reference_domains(p_use text) returns text[] language sql stable security definer set search_path = '' as $f$
  select coalesce(array_agg(distinct l.domain order by l.domain), '{}'::text[]) from pipeline.important_links l
   where l.enabled and l.retired_at is null and l.domain is not null and p_use = any(l.uses)
$f$;
revoke all on function public.svc_reference_domains(text) from public, anon, authenticated;
grant execute on function public.svc_reference_domains(text) to service_role;

-- Scholarships sourced only from a placeholder site (guard)
create or replace function security.reference_placeholder_in_use(p_domain text) returns bigint language sql stable set search_path = '' as $f$
  select count(*) from scholarship.scholarships s where s.lifecycle_status = 'active'
     and security.reference_domain_matches(security.reference_host_of(s.source_url), p_domain)
$f$;
revoke all on function security.reference_placeholder_in_use(text) from public, anon;

-- Read (also records the result of any "Check now" that has finished)
create or replace function public.admin_reference_sources_read() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 2 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  update pipeline.important_links l set last_check_http = r.status_code, last_check_at = coalesce(r.created, now()), last_check_request = null,
         last_verified_at = now(), next_verification_at = now() + l.verification_cadence,
         health_status = case when l.retired_at is not null then 'retired' when r.status_code between 200 and 399 then 'healthy' else 'degraded' end
    from net._http_response r where l.last_check_request = r.id;
  return jsonb_build_object(
    'can_edit', v_rank >= 3, 'can_manage', v_rank >= 5,
    'uses', jsonb_build_array(
      jsonb_build_object('key','reference','label','Reference link','help','Shown to staff for looking things up.'),
      jsonb_build_object('key','data_source','label','Data source','help','The platform reads data from it.'),
      jsonb_build_object('key','not_provider_site','label','Never a university website','help','Skipped when finding or checking a university''s own website.'),
      jsonb_build_object('key','not_course_page','label','Never a course page','help','Refused when binding a course page.'),
      jsonb_build_object('key','scholarship_placeholder','label','Scholarship placeholder','help','A scholarship sourced only from here needs a university page before it can be published.'),
      jsonb_build_object('key','logo_directory','label','Logo directory','help','Used only to find university logos.'),
      jsonb_build_object('key','ranking_publisher','label','Ranking publisher','help','Default source address on Ranking imports.')),
    'categories', jsonb_build_array(
      jsonb_build_object('key','regulatory_authority','label','Regulator or register'),
      jsonb_build_object('key','official_scholarship','label','Official scholarships'),
      jsonb_build_object('key','statistics_data','label','Statistics'),
      jsonb_build_object('key','quality_outcomes','label','Outcomes'),
      jsonb_build_object('key','ranking_publisher','label','Ranking publisher'),
      jsonb_build_object('key','third_party_directory','label','Third-party directory'),
      jsonb_build_object('key','general_web','label','Search, social or listing site'),
      jsonb_build_object('key','international_student_immigration','label','Student visas'),
      jsonb_build_object('key','qualification_framework','label','Qualification framework'),
      jsonb_build_object('key','official_policy_change','label','Policy changes'),
      jsonb_build_object('key','accepted_provider_course_source','label','Accepted course source'),
      jsonb_build_object('key','source_health','label','Source health')),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'country', l.country_code, 'category', l.authority_category,
                 'name', l.authority_name, 'url', l.url, 'domain', l.domain, 'uses', to_jsonb(l.uses), 'enabled', l.enabled,
                 'ref_key', l.ref_key, 'purpose', l.purpose, 'retired', l.retired_at is not null, 'health', l.health_status,
                 'checked_at', coalesce(l.last_check_at, l.last_verified_at), 'http', l.last_check_http, 'checking', l.last_check_request is not null,
                 'scholarships', case when 'scholarship_placeholder' = any(l.uses) then security.reference_placeholder_in_use(l.domain) end,
                 'updated_at', l.updated_at)
               order by l.retired_at is not null, l.authority_category, l.authority_name), '[]'::jsonb) from pipeline.important_links l),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.created_at, 'action', e.action, 'target', e.target, 'detail', e.detail, 'by', u.email) order by e.created_at desc), '[]'::jsonb)
               from (select * from pipeline.admin_control_events where area = 'reference_sources' order by created_at desc limit 20) e left join auth.users u on u.id = e.actor));
end $f$;
revoke all on function public.admin_reference_sources_read() from public, anon;
grant execute on function public.admin_reference_sources_read() to authenticated;

-- Save: add a site (p_id null) or change its fields
create or replace function public.admin_reference_source_save(p_id uuid, p_fields jsonb, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_old pipeline.important_links%rowtype; v_new pipeline.important_links%rowtype;
        v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_changed text[]; v_inuse bigint;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then raise exception 'nothing to save'; end if;
  if exists (select 1 from jsonb_object_keys(p_fields) k where k not in ('name','url','purpose','country','category','domain','uses','enabled','ref_key')) then
    raise exception 'unknown field'; end if;
  if p_id is null or exists (select 1 from jsonb_object_keys(p_fields) k where k in ('domain','uses','enabled','ref_key','category')) then
    if v_rank < 5 then raise exception 'PIM Operator role or above required to add a site or change how it is used' using errcode = '42501'; end if;
    if v_reason is null or length(v_reason) < 3 then raise exception 'give a short reason'; end if;
  end if;
  if p_id is null then
    insert into pipeline.important_links(country_code, authority_category, authority_name, url, domain, uses, enabled, ref_key, purpose, owner_label,
      verification_cadence, next_verification_at, health_status, change_control_ref, created_by, updated_by)
    values (upper(coalesce(nullif(btrim(p_fields->>'country'), ''), 'ALL')), coalesce(p_fields->>'category', 'third_party_directory'),
      btrim(coalesce(p_fields->>'name', '')), btrim(coalesce(p_fields->>'url', '')), nullif(lower(btrim(coalesce(p_fields->>'domain', ''))), ''),
      coalesce((select array_agg(x) from jsonb_array_elements_text(p_fields->'uses') x), array['reference']::text[]),
      coalesce((p_fields->>'enabled')::boolean, true), nullif(btrim(coalesce(p_fields->>'ref_key', '')), ''), nullif(btrim(coalesce(p_fields->>'purpose', '')), ''),
      'CourseFinder Data Ops', interval '90 days', now() + interval '90 days', 'unverified', 'CF-CHG-20260915-247', auth.uid(), auth.uid())
    returning * into v_new;
    if length(v_new.authority_name) < 2 then raise exception 'give the site a name'; end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('reference_sources', 'add', v_new.authority_name, jsonb_build_object('id', v_new.id, 'domain', v_new.domain, 'uses', to_jsonb(v_new.uses), 'reason', v_reason), auth.uid());
    return public.admin_reference_sources_read() || jsonb_build_object('saved', v_new.id);
  end if;
  select * into v_old from pipeline.important_links where id = p_id for update;
  if not found then raise exception 'site not found'; end if;
  update pipeline.important_links set
    authority_name = case when p_fields ? 'name' then btrim(p_fields->>'name') else authority_name end,
    url = case when p_fields ? 'url' then btrim(p_fields->>'url') else url end,
    purpose = case when p_fields ? 'purpose' then nullif(btrim(coalesce(p_fields->>'purpose', '')), '') else purpose end,
    country_code = case when p_fields ? 'country' then upper(coalesce(nullif(btrim(p_fields->>'country'), ''), 'ALL')) else country_code end,
    authority_category = case when p_fields ? 'category' then p_fields->>'category' else authority_category end,
    domain = case when p_fields ? 'domain' then nullif(lower(btrim(coalesce(p_fields->>'domain', ''))), '') else domain end,
    uses = case when p_fields ? 'uses' then coalesce((select array_agg(x) from jsonb_array_elements_text(p_fields->'uses') x), array[]::text[]) else uses end,
    enabled = case when p_fields ? 'enabled' then (p_fields->>'enabled')::boolean else enabled end,
    ref_key = case when p_fields ? 'ref_key' then nullif(btrim(coalesce(p_fields->>'ref_key', '')), '') else ref_key end,
    updated_by = auth.uid(), updated_at = now()
  where id = p_id returning * into v_new;
  if length(coalesce(v_new.authority_name, '')) < 2 then raise exception 'give the site a name'; end if;
  if 'scholarship_placeholder' = any(v_old.uses) and v_old.enabled and v_old.retired_at is null
     and (not v_new.enabled or not ('scholarship_placeholder' = any(v_new.uses)) or v_new.domain is distinct from v_old.domain) then
    v_inuse := security.reference_placeholder_in_use(v_old.domain);
    if v_inuse > 0 then raise exception '% active scholarships are sourced only from this site; they would look publishable. Give them a university page first.', v_inuse; end if;
  end if;
  select array_agg(k) into v_changed from jsonb_object_keys(p_fields) k;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('reference_sources', 'change', v_new.authority_name, jsonb_build_object('id', p_id, 'fields', to_jsonb(v_changed),
          'before', jsonb_build_object('name', v_old.authority_name, 'url', v_old.url, 'domain', v_old.domain, 'uses', to_jsonb(v_old.uses),
                    'enabled', v_old.enabled, 'category', v_old.authority_category, 'country', v_old.country_code, 'ref_key', v_old.ref_key, 'purpose', v_old.purpose),
          'reason', v_reason), auth.uid());
  return public.admin_reference_sources_read() || jsonb_build_object('saved', p_id);
end $f$;
revoke all on function public.admin_reference_source_save(uuid, jsonb, text) from public, anon;
grant execute on function public.admin_reference_source_save(uuid, jsonb, text) to authenticated;

-- Actions: retire, restore, check (one site), check_all
create or replace function public.admin_reference_source_action(p_id uuid, p_action text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v pipeline.important_links%rowtype; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
        v_inuse bigint; v_n int := 0;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_action = 'check_all' then
    update pipeline.important_links l set last_check_request = net.http_get(l.url, timeout_milliseconds := 15000)
     where l.retired_at is null and l.last_check_request is null;
    get diagnostics v_n = row_count;
    return public.admin_reference_sources_read() || jsonb_build_object('checking', v_n);
  end if;
  select * into v from pipeline.important_links where id = p_id for update;
  if not found then raise exception 'site not found'; end if;
  if p_action = 'check' then
    update pipeline.important_links set last_check_request = net.http_get(v.url, timeout_milliseconds := 15000) where id = p_id;
    return public.admin_reference_sources_read() || jsonb_build_object('checking', 1);
  elsif p_action in ('retire', 'restore') then
    if v_rank < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
    if v_reason is null or length(v_reason) < 3 then raise exception 'give a short reason'; end if;
    if p_action = 'retire' and 'scholarship_placeholder' = any(v.uses) and v.enabled and v.retired_at is null then
      v_inuse := security.reference_placeholder_in_use(v.domain);
      if v_inuse > 0 then raise exception '% active scholarships are sourced only from this site; they would look publishable. Give them a university page first.', v_inuse; end if;
    end if;
    update pipeline.important_links set retired_at = case when p_action = 'retire' then now() end,
           enabled = (p_action = 'restore'), health_status = case when p_action = 'retire' then 'retired' else 'unverified' end,
           updated_by = auth.uid(), updated_at = now() where id = p_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('reference_sources', p_action, v.authority_name, jsonb_build_object('id', p_id, 'reason', v_reason), auth.uid());
    return public.admin_reference_sources_read();
  end if;
  raise exception 'unknown action %', p_action;
end $f$;
revoke all on function public.admin_reference_source_action(uuid, text, text) from public, anon;
grant execute on function public.admin_reference_source_action(uuid, text, text) to authenticated;

-- The functions that held hard-coded site patterns now read the list (md5-guarded in-place edits).
do $do$
declare v_def text; v_new text; r record;
  v_sa_not constant text := $p$([A-Za-z_][A-Za-z0-9_.]*(\([^()]*\))?)\s*!~\*\s*'studyaustralia\\\.gov\\\.au'$p$;
  v_sa_pat constant text := $p$([A-Za-z_][A-Za-z0-9_.]*(\([^()]*\))?)\s*~\*\s*'studyaustralia\\\.gov\\\.au'$p$;
begin
  -- Layer 4 course page binding
  if (select md5(prosrc) from pg_proc where oid = 'security.layer4_course_link_apply_impl(uuid,uuid,jsonb,text)'::regprocedure) <> 'f5fbcf04066596ad0fab6662980350c8' then
    raise exception 'security.layer4_course_link_apply_impl changed since it was checked; not editing'; end if;
  v_def := pg_get_functiondef('security.layer4_course_link_apply_impl(uuid,uuid,jsonb,text)'::regprocedure);
  v_new := replace(v_def, $s$v_host ~ '(^|\.)(google|bing|duckduckgo|yahoo|facebook|linkedin|instagram|youtube|hotcourses|studyinternational|idp|studyaustralia|courseseeker|myuni)\.'$s$,
                   $s$security.reference_url_has_use(v_url, 'not_course_page')$s$);
  if v_new = v_def then raise exception 'expected text not found (layer4 course link)'; end if;
  execute v_new;

  -- Provider catalogue page: the provider's own hosts leave out sites that are never a university website
  if (select md5(prosrc) from pg_proc where oid = 'security.layer2_provider_catalogue_submit_impl(uuid,uuid,text,text,boolean,text)'::regprocedure) <> 'fdfd2c967fafa7fff6731f113543944c' then
    raise exception 'security.layer2_provider_catalogue_submit_impl changed since it was checked; not editing'; end if;
  v_def := pg_get_functiondef('security.layer2_provider_catalogue_submit_impl(uuid,uuid,text,text,boolean,text)'::regprocedure);
  v_new := replace(v_def, $s$s.url !~* '(hotcourses|studyin|idp\.com)'$s$, $s$not security.reference_url_has_use(s.url, 'not_provider_site')$s$);
  if v_new = v_def then raise exception 'expected text not found (catalogue submit)'; end if;
  execute v_new;

  -- Scholarships: a source on a placeholder site is not a university page
  for r in select * from (values
      ('security.scholarship_admit_from_provider_page_v1(bigint)', '922241c33773ea6dad2e3301fa685b02'),
      ('security.scholarship_held_without_page(uuid)', '9d0c004c433e9982d77bc437cb7dffd9'),
      ('security.scholarship_page_match_v1(uuid,text,text,bigint)', 'fef79c3efe85173df093e09c19874f08'),
      ('security.scholarship_publishability_v1()', 'b80870edd30933a6d050a8f109883163'),
      ('security.scholarship_sweep_apply_v1(uuid)', '6277995146a58e49fb3ec1ef8591b08b'),
      ('public.svc_scholarship_search_next(integer)', '2b12b44733ba09aa3bde20847ebe35d1')) t(fn, m) loop
    if (select md5(prosrc) from pg_proc where oid = r.fn::regprocedure) <> r.m then raise exception '% changed since it was checked; not editing', r.fn; end if;
    v_def := pg_get_functiondef(r.fn::regprocedure);
    v_new := regexp_replace(v_def, v_sa_not, $s$not security.reference_url_has_use(\1, 'scholarship_placeholder')$s$, 'g');
    v_new := regexp_replace(v_new, v_sa_pat, $s$security.reference_url_has_use(\1, 'scholarship_placeholder')$s$, 'g');
    if v_new = v_def or position('studyaustralia\.gov' in v_new) > 0 then raise exception 'pattern replacement incomplete in %', r.fn; end if;
    execute v_new;
  end loop;

  -- Source comparison: the Study Australia record is the one on a placeholder site
  if (select md5(prosrc) from pg_proc where oid = 'security.admin_source_comparison_read_v1(text,uuid)'::regprocedure) <> '6d40fbddbc2744d19325705f8379d537' then
    raise exception 'security.admin_source_comparison_read_v1 changed since it was checked; not editing'; end if;
  v_def := pg_get_functiondef('security.admin_source_comparison_read_v1(text,uuid)'::regprocedure);
  v_new := regexp_replace(v_def, $p$(\S+)\s+ilike\s+'%studyaustralia\.gov\.au%'$p$, $s$security.reference_url_has_use(\1, 'scholarship_placeholder')$s$, 'g');
  if v_new = v_def or position('studyaustralia.gov.au%' in v_new) > 0 then raise exception 'pattern replacement incomplete (source comparison)'; end if;
  execute v_new;
end $do$;