-- CF-247 v2.15.233 (R2): Platform Admin bug list of 10 Oct 2026 — Fix 1, Feature 1, Feature 3 (decision: Hotcourses kept for logos only).
-- Only the provider's own website, the regulator, or a value entered by hand may be a provider's website, course finder or course page.
--  1. Twelve course directories found as "course finders" join the governed third-party list (Reference sources).
--  2. Helpers: security.site_host_v1, security.third_party_host_v1, security.provider_site_verdict_v1 (third_party / regulator / own / unconfirmed).
--  3. The website search never records a third-party site; refused_host also refuses third-party course pages; directory site hints are
--     no longer used; a website, course finder or official page entered by hand on a third-party site is refused; the provider panel
--     shows whose each address is.
--  4. Existing data: third-party course finders cleared (back to the website search); third-party course pages refused; intakes, English
--     requirements and official links read from them withdrawn (locked values skipped); those courses re-queued for their own page;
--     an own site found by the search becomes the provider's website when none is recorded; search documents rebuilt.
-- Live definitions are md5-checked before and after. Nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := jsonb_build_object('security.refused_host(text)', 'aa5234b75a902340aeac72c1f041f175', 'public.svc_coverage_site_record(uuid,text,jsonb)', '153b3bd42d3c751deb5d37231feec9b8', 'public.svc_site_hint_next(integer)', 'b1cae71d7fa98cf35c42b73ec2846730', 'public.admin_provider_edit(uuid,text,jsonb)', '21b1ff3858ad64d52e4ff36bcce85e23', 'public.admin_course_edit(uuid,text,jsonb)', '14a90dea54f2e42c7a3f3341b070871d', 'public.admin_provider_edit_read(uuid)', 'b616552481613710ccb923e84880cf16');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1. The governed list of third-party sites (Reference data › Reference sources). Course directories found as "course finders" on
--    10 Oct 2026 are added; like Hotcourses they are never a provider's website or course page.
insert into pipeline.important_links(country_code, authority_category, authority_name, owner_label, url, purpose, uses, domain, change_control_ref)
select c, 'third_party_directory', n, 'CourseFinder Data Ops', u, 'Course directory or comparison site. Never a provider''s website, course finder or course page (Platform Admin, 10 Oct 2026).',
       array['not_provider_site', 'not_course_page'], d, 'CF-CHG-20260915-247'
  from (values ('AU', 'ACIR course search', 'https://search.acir.com.au/', 'search.acir.com.au'),
               ('AU', 'HigherStudy', 'https://higherstudy.com/', 'higherstudy.com'),
               ('AU', 'OneUEdu', 'https://oneuedu.com/', 'oneuedu.com'),
               ('AU', 'Study Melbourne course search', 'https://coursesearch.studymelbourne.vic.gov.au/', 'coursesearch.studymelbourne.vic.gov.au'),
               ('AU', 'Australian Courses', 'https://australiancourses.com.au/', 'australiancourses.com.au'),
               ('AU', 'Courses.com.au', 'https://www.courses.com.au/', 'courses.com.au'),
               ('AU', 'Find the Courses', 'https://findthecourses.com.au/', 'findthecourses.com.au'),
               ('AU', 'Overseas Students Australia', 'https://overseasstudentsaustralia.com/', 'overseasstudentsaustralia.com'),
               ('AU', 'Good Universities Guide', 'https://www.gooduniversitiesguide.com.au/', 'gooduniversitiesguide.com.au'),
               ('AU', 'Study Queensland course search', 'https://search.studyqueensland.qld.gov.au/', 'search.studyqueensland.qld.gov.au'),
               ('NZ', 'StudySpy', 'https://www.studyspy.ac.nz/', 'studyspy.ac.nz'),
               ('AU', 'Top Australia Universities', 'https://topaustraliauniversities.com/', 'topaustraliauniversities.com')) v(c, n, u, d)
on conflict (country_code, url) do nothing;

-- 2. Helpers. A host is third-party when it is on that list (directories, general web, ranking publishers). The verdict says
--    whose a site is: third_party, regulator, own (the regulator's register address or a domain that fits the name), unconfirmed.
create or replace function security.site_host_v1(p_url text) returns text language sql immutable set search_path to '' as $f$
  select nullif(lower(regexp_replace(substring(btrim(coalesce(p_url, '')) from '^(?:https?://)?([^/:?#\s]+)'), '^www\.', '')), '')
$f$;

create or replace function security.third_party_host_v1(p_url text) returns boolean language sql stable security definer set search_path to '' as $f$
  select coalesce((select bool_or(case when l.domain like '%.%' then h = l.domain or h like '%.' || l.domain else h ~ ('(^|\.)' || l.domain) end)
                     from pipeline.important_links l, (select security.site_host_v1(p_url) h) x
                    where x.h is not null and l.enabled and l.retired_at is null and l.domain is not null and 'not_provider_site' = any(l.uses)
                      and l.authority_category in ('third_party_directory', 'general_web', 'ranking_publisher')), false)
$f$;

create or replace function security.provider_site_verdict_v1(p_provider_id uuid, p_url text) returns text language plpgsql stable security definer set search_path to '' as $f$
declare v_host text := security.site_host_v1(p_url); v_reg text; v_label text; v_words text[]; v_init text; v_name text;
begin
  if v_host is null then return 'none'; end if;
  if security.third_party_host_v1(p_url) then return 'third_party'; end if;
  if exists (select 1 from pipeline.important_links l where l.enabled and l.retired_at is null and l.domain like '%.%'
               and l.authority_category in ('regulatory_authority', 'qualification_framework') and (v_host = l.domain or v_host like '%.' || l.domain)) then return 'regulator'; end if;
  select security.site_host_v1(p.website), regexp_replace(split_part(v_host, '.', 1), '[^a-z0-9]', '', 'g'), lower(coalesce(p.display_name, p.canonical_name, '')),
         array_remove(regexp_split_to_array(btrim(regexp_replace(lower(coalesce(p.display_name, '') || ' ' || coalesce(p.canonical_name, '') || ' ' || coalesce(p.short_name, '')), '[^a-z0-9]+', ' ', 'g')), ' '), '')
    into v_reg, v_label, v_name, v_words from catalogue.providers p where p.id = p_provider_id;
  if v_reg is not null and (v_host = v_reg or v_host like '%.' || v_reg or v_reg like '%.' || v_host) then return 'own'; end if;
  if length(coalesce(v_label, '')) >= 3 then
    if exists (select 1 from unnest(v_words) w where length(w) >= 4 and v_label like '%' || w || '%'
                 and w not in ('university','college','institute','technology','school','polytechnic','community','arts','design','australia','australian',
                               'education','training','international','group','academy','business','management','limited','trading','services','national',
                               'learning','studies','english','language','centre','center','holdings','trust','incorporated')) then return 'own'; end if;
    select string_agg(left(w, 1), '') into v_init from unnest(regexp_split_to_array(btrim(regexp_replace(v_name, '[^a-z0-9]+', ' ', 'g')), ' ')) w where w <> '' and w not in ('of','and','the','at','for','in','pty','ltd');
    if v_label = v_init then return 'own'; end if;
  end if;
  return 'unconfirmed';
end $f$;
revoke all on function security.third_party_host_v1(text) from public, anon, authenticated;
revoke all on function security.provider_site_verdict_v1(uuid, text) from public, anon, authenticated;

-- 3. Changed functions

CREATE OR REPLACE FUNCTION security.refused_host(p_url text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(substring(coalesce(p_url, '') from '^https?://([^/?#]+)') ~* nullif(btrim(coalesce(security.firecrawl_setting('refused_host_pattern') #>> '{}', '')), ''), false)
         or security.third_party_host_v1(p_url)  -- v2.15.233 (Feature 3): never a third-party course directory
$function$;

CREATE OR REPLACE FUNCTION public.svc_coverage_site_record(p_provider_id uuid, p_website text, p_evidence jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare v_dom text;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  -- v2.15.232 (Fix 3): a course finder address entered by hand is kept; the search result is stored as evidence only
  if exists (select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=p_provider_id and l.field='course_finder')
     or exists (select 1 from pipeline.coverage_provider_discovery d where d.provider_id=p_provider_id and d.site_source='manual') then
    update pipeline.coverage_provider_discovery set site_searched_at=now(), leased_until=null, site_evidence=p_evidence, updated_at=now() where provider_id=p_provider_id;
    return;
  end if;
  -- v2.15.233 (Feature 1): a course directory or other third-party site is never recorded as the provider's site
  if nullif(p_website,'') is not null and security.third_party_host_v1(p_website) then
    update pipeline.coverage_provider_discovery set site_searched_at=now(), leased_until=null, updated_at=now(),
           site_evidence=coalesce(p_evidence,'{}'::jsonb)||jsonb_build_object('refused', p_website, 'refused_why', 'third-party site, not the provider''s own')
     where provider_id=p_provider_id;
    return;
  end if;
  update pipeline.coverage_provider_discovery set site_searched_at=now(), leased_until=null, site_evidence=p_evidence,
         website=coalesce(nullif(p_website,''),website), site_source=case when nullif(p_website,'') is not null then coalesce('search_verified_'||nullif(p_evidence->>'basis',''),'search_verified_cricos_code') else site_source end,
         status=case when nullif(p_website,'') is not null then 'pending' else status end, attempts=case when nullif(p_website,'') is not null then 0 else attempts end,
         updated_at=now()
   where provider_id=p_provider_id;
  -- Decision 220: a Canadian site gets the generic recipe for its own .ca domain, and its active courses with no
  -- candidate page are queued for the course-page search by title.
  if nullif(p_website,'') is not null and security.coverage_country(p_provider_id) = 'CA' then
    v_dom := lower(regexp_replace(substring(btrim(p_website) from '^(?:https?://)?([^/:?#]+)'), '^www\.', ''));
    if v_dom ~ '^[a-z0-9.-]+\.ca$' then
      insert into pipeline.course_link_recipes(provider_id, search_domain, patterns, active, notes, updated_at)
      select p_provider_id, v_dom,
             jsonb_build_array(jsonb_build_object(
               're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(v_dom, '\.', '\\.', 'g')
                     || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
               'rep', '\&')),
             true, 'Generic recipe: any page on the provider''s own site; used only when the reader proves the page is the course''s (CA, Decision 220, 2 Oct 2026)', now()
       where not exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id);
      insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
      select c.id, c.provider_id, 'title', 'queued', now()
        from catalogue.courses c
       where c.provider_id = p_provider_id and c.lifecycle_status = 'active'
         and exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id and x.active)
         and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id)
      on conflict (course_id) do nothing;
    end if;
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_site_hint_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with hints as (
    -- v2.15.233 (Feature 3): hints from third-party directories (Hotcourses, univ.cc) are no longer used; Hotcourses stays for logos only
    select r.provider_id, u url, 'hipo' via from pipeline.reference_institutions r, unnest(r.web_pages) u where r.provider_id is not null),
  todo as (
    select h.provider_id, jsonb_agg(distinct jsonb_build_object('url', h.url, 'via', h.via)) urls
      from hints h
      left join pipeline.coverage_provider_discovery d on d.provider_id = h.provider_id
     where (d.provider_id is null or d.status in ('no_website', 'failed') or d.website is null)
       and exists (select 1 from catalogue.courses co where co.provider_id = h.provider_id and co.lifecycle_status = 'active')
       and not exists (select 1 from pipeline.site_hint_checks c where c.provider_id = h.provider_id and c.url = h.url
                         and (c.accepted or coalesce(c.evidence->>'worker', '') not in ('coverage-sweep-worker-v0.10.0', 'coverage-sweep-worker-v0.10.1', 'coverage-sweep-worker-v0.10.2', 'coverage-sweep-worker-v0.10.3')))
     group by 1 limit greatest(1, least(coalesce(p_limit, 20), 60)))
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', t.provider_id, 'name', coalesce(pr.display_name, pr.canonical_name), 'country', security.coverage_country(t.provider_id),
           'cricos', (select i.identifier from catalogue.provider_identifiers i where i.provider_id = t.provider_id and i.scheme = 'cricos' limit 1),
           'dli', (select i.identifier from catalogue.provider_identifiers i where i.provider_id = t.provider_id and i.scheme = 'ircc_dli' limit 1),
           'urls', t.urls)), '[]'::jsonb)
    into v from todo t join catalogue.providers pr on pr.id = t.provider_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.admin_provider_edit(p_provider_id uuid, p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_p catalogue.providers%rowtype; v_field text; v_before jsonb; v_after jsonb; v_val jsonb; v_url text;
        v_reason text := nullif(btrim(coalesce(p_args->>'reason', '')), '');
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into v_p from catalogue.providers where id = p_provider_id;
  if v_p.id is null then raise exception 'provider not found'; end if;
  if p_action in ('archive','restore') and v_rank < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  perform set_config('cf.manual_edit', 'on', true);

  if p_action = 'set_core' then
    v_field := p_args->>'field';
    if v_field is null or v_field not in ('display_name','short_name','website','phone','email','description','primary_city','address_line1','postcode') then raise exception 'this field cannot be edited here'; end if;
    v_val := p_args->'value';
    if jsonb_typeof(v_val) = 'string' then v_val := to_jsonb(nullif(btrim(v_val #>> '{}'), '')); end if;
    if v_field = 'website' and v_val is not null and v_val <> 'null'::jsonb and (v_val #>> '{}') !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    if v_field = 'website' and v_val is not null and v_val <> 'null'::jsonb and security.third_party_host_v1(v_val #>> '{}') then raise exception 'that is a third-party site (a course directory or similar), not the provider''s own website'; end if;
    if v_field = 'email' and v_val is not null and v_val <> 'null'::jsonb and (v_val #>> '{}') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'enter a valid email address'; end if;
    v_before := to_jsonb(v_p)->v_field;
    update catalogue.providers p set display_name = r.display_name, short_name = r.short_name, website = r.website, phone = r.phone, email = r.email,
           description = r.description, primary_city = r.primary_city, address_line1 = r.address_line1, postcode = r.postcode, updated_at = now()
      from (select (jsonb_populate_record(x0, jsonb_build_object(v_field, v_val))).* from catalogue.providers x0 where x0.id = p_provider_id) r
     where p.id = p_provider_id;
    perform security.manual_lock_set('provider', p_provider_id, v_field, 'value');
    v_after := v_val;

  elsif p_action = 'set_course_finder' then
    v_field := 'course_finder'; v_url := btrim(coalesce(p_args->>'url', ''));
    if v_url !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    if security.third_party_host_v1(v_url) then raise exception 'that is a third-party course directory: use the provider''s own website or the regulator''s page'; end if;
    select to_jsonb(d.website) into v_before from pipeline.coverage_provider_discovery d where d.provider_id = p_provider_id;
    insert into pipeline.coverage_provider_discovery(provider_id, website, status, attempts, next_due_at, updated_at)
    values (p_provider_id, v_url, 'pending', 0, now(), now())
    on conflict (provider_id) do update set website = excluded.website, status = 'pending', attempts = 0, next_due_at = now(), leased_until = null,
           last_error = null, updated_at = now();
    -- v2.15.232 (Fix 3): an address entered by hand is marked manual and locked, so automation never replaces it
    update pipeline.coverage_provider_discovery set site_source = 'manual', site_searched_at = now() where provider_id = p_provider_id;
    perform security.manual_lock_set('provider', p_provider_id, 'course_finder', 'value');
    v_after := to_jsonb(v_url);

  elsif p_action = 'release' then
    v_field := p_args->>'field';
    select to_jsonb(l) into v_before from pipeline.manual_locks l where entity = 'provider' and entity_id = p_provider_id and field = v_field;
    if v_before is null then raise exception 'nothing to release'; end if;
    delete from pipeline.manual_locks where entity = 'provider' and entity_id = p_provider_id and field = v_field;
    -- v2.15.232: handing the course finder address back to automation lets the site search replace it again
    if v_field = 'course_finder' then update pipeline.coverage_provider_discovery set site_source = null where provider_id = p_provider_id and site_source = 'manual'; end if;

  elsif p_action in ('archive','restore') then
    v_field := 'lifecycle_status'; v_before := to_jsonb(v_p.lifecycle_status);
    update catalogue.providers set lifecycle_status = case p_action when 'archive' then 'inactive' else 'active' end, updated_at = now() where id = p_provider_id;
    perform security.manual_lock_set('provider', p_provider_id, 'lifecycle_status', 'value');
    v_after := to_jsonb(case p_action when 'archive' then 'inactive' else 'active' end);

  else
    raise exception 'unknown action %', p_action;
  end if;

  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('provider', p_provider_id, v_field, p_action, v_before, v_after, v_reason, auth.uid());
  return public.admin_provider_edit_read(p_provider_id);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_course_edit(p_course_id uuid, p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_src uuid; v_c catalogue.courses%rowtype; v_field text; v_before jsonb; v_after jsonb;
        v_reason text := nullif(btrim(coalesce(p_args->>'reason', '')), ''); v_url text; x jsonb; v_test uuid; v_amount numeric; v_val jsonb;
        v_keep uuid[] := '{}'; v_n int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into v_c from catalogue.courses where id = p_course_id;
  if v_c.id is null then raise exception 'course not found'; end if;
  if p_action in ('archive','restore') and v_rank < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  perform set_config('cf.manual_edit', 'on', true);
  select id into v_src from pipeline.sources where source_type = 'manual_entry' limit 1;

  if p_action = 'set_core' then
    v_field := p_args->>'field';
    if v_field is null or v_field not in ('display_title','description','duration_value','duration_unit','delivery_mode') then raise exception 'this field cannot be edited here'; end if;
    v_val := p_args->'value';
    if jsonb_typeof(v_val) = 'string' then v_val := to_jsonb(nullif(btrim(v_val #>> '{}'), '')); end if;
    if v_field = 'duration_value' and v_val is not null and v_val <> 'null'::jsonb and not ((v_val #>> '{}') ~ '^[0-9]+(\.[0-9]+)?$') then raise exception 'duration must be a number'; end if;
    v_before := to_jsonb(v_c)->v_field;
    update catalogue.courses c set display_title = r.display_title, description = r.description, duration_value = r.duration_value,
           duration_unit = r.duration_unit, delivery_mode = r.delivery_mode, updated_at = now()
      from (select (jsonb_populate_record(x0, jsonb_build_object(v_field, v_val))).* from catalogue.courses x0 where x0.id = p_course_id) r
     where c.id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, v_field, 'value');
    v_after := v_val;

  elsif p_action = 'set_official_url' then
    v_field := 'official_url'; v_url := btrim(coalesce(p_args->>'url', ''));
    if v_url !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    if security.third_party_host_v1(v_url) then raise exception 'that is a third-party course directory: the official page must be on the provider''s own website'; end if;
    select jsonb_agg(url) into v_before from catalogue.course_links where course_id = p_course_id and link_type = 'official_course' and status = 'active';
    update catalogue.course_links set status = 'inactive', is_primary = false, updated_at = now()
     where course_id = p_course_id and link_type = 'official_course' and status = 'active' and url <> v_url;
    insert into catalogue.course_links(course_id, link_type, url, label, is_primary, status, source_id, confidence, last_verified_at)
    values (p_course_id, 'official_course', v_url, 'Official course page', true, 'active', v_src, 1, now())
    on conflict (course_id, link_type, url) do update set status = 'active', is_primary = true, source_id = v_src, confidence = 1,
           last_verified_at = now(), updated_at = now(), evidence_id = null;
    update catalogue.courses set course_url = v_url, updated_at = now() where id = p_course_id;
    insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, bound_at, next_read_at, read_attempts)
    values (p_course_id, v_c.provider_id, v_url, 'manual', 'bound', now(), now(), 0)
    on conflict (course_id) do update set url = excluded.url, basis = 'manual', status = 'bound', bound_at = now(), score = null, runner_up = null,
           read_status = null, read_at = null, http_status = null, fetched_via = null, identity_basis = null, evidence_id = null, candidates = null,
           leased_until = null, read_attempts = 0, next_read_at = now();
    update pipeline.course_link_search set state = 'verified', bound_url = v_url, done_at = now() where course_id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, 'official_url', 'value');
    perform security.manual_lock_set('course', p_course_id, 'course_url', 'value');
    v_after := to_jsonb(v_url);

  elsif p_action = 'remove_official_url' then
    v_field := 'official_url';
    select jsonb_agg(url) into v_before from catalogue.course_links where course_id = p_course_id and link_type = 'official_course' and status = 'active';
    update catalogue.course_links set status = 'inactive', is_primary = false, updated_at = now()
     where course_id = p_course_id and link_type = 'official_course' and status = 'active';
    update catalogue.courses set course_url = null, updated_at = now() where id = p_course_id;
    update pipeline.coverage_course_pages set status = 'mismatch', basis = 'manual', leased_until = null where course_id = p_course_id;
    delete from pipeline.course_link_search where course_id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, 'official_url', 'removed');
    perform security.manual_lock_set('course', p_course_id, 'course_url', 'removed');

  elsif p_action = 'set_intakes' then
    v_field := 'intakes';
    if jsonb_typeof(p_args->'intakes') <> 'array' or jsonb_array_length(p_args->'intakes') = 0 then raise exception 'add at least one intake'; end if;
    select jsonb_agg(jsonb_build_object('label', intake_label, 'year', intake_year, 'start_date', start_date)) into v_before
      from catalogue.course_intakes where course_id = p_course_id and status = 'active';
    update catalogue.course_intakes set status = 'inactive' where course_id = p_course_id and status = 'active';
    for x in select * from jsonb_array_elements(p_args->'intakes') loop
      if nullif(btrim(coalesce(x->>'label', '')), '') is null then raise exception 'each intake needs a name, for example February'; end if;
      insert into catalogue.course_intakes(course_id, intake_year, intake_label, start_date, status, source_id, confidence, source_intake_key)
      values (p_course_id, nullif(x->>'year', '')::int, btrim(x->>'label'), nullif(x->>'start_date', '')::date, 'active', v_src, 1,
              'manual:' || lower(btrim(x->>'label')) || ':' || coalesce(nullif(x->>'year', ''), '') || ':' || coalesce(nullif(x->>'start_date', ''), ''))
      on conflict (course_id, source_id, source_intake_key) where source_id is not null and source_intake_key is not null
      do update set status = 'active', intake_year = excluded.intake_year, start_date = excluded.start_date, confidence = 1;
    end loop;
    perform security.manual_lock_set('course', p_course_id, 'intakes', 'value');
    v_after := p_args->'intakes';

  elsif p_action = 'remove_intakes' then
    v_field := 'intakes';
    select jsonb_agg(jsonb_build_object('label', intake_label, 'year', intake_year)) into v_before from catalogue.course_intakes where course_id = p_course_id and status = 'active';
    update catalogue.course_intakes set status = 'inactive' where course_id = p_course_id and status = 'active';
    perform security.manual_lock_set('course', p_course_id, 'intakes', 'removed');

  elsif p_action = 'set_english' then
    v_field := 'english';
    if jsonb_typeof(p_args->'tests') <> 'array' or jsonb_array_length(p_args->'tests') = 0 then raise exception 'add at least one English test score'; end if;
    select jsonb_agg(jsonb_build_object('test', t.code, 'overall', e.overall_score, 'components', e.component_scores)) into v_before
      from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id where e.course_id = p_course_id and e.status = 'active';
    for x in select * from jsonb_array_elements(p_args->'tests') loop
      select id into v_test from ref.english_tests where code = x->>'test';
      if v_test is null then raise exception 'unknown English test %', x->>'test'; end if;
      if (x->>'overall') is null or (x->>'overall') !~ '^[0-9]+(\.[0-9]+)?$' then raise exception 'enter an overall score for %', x->>'test'; end if;
      insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, notes, source_id, evidence_id, confidence, source_requirement_key, status, last_verified_at)
      values (p_course_id, v_test, (x->>'overall')::numeric, coalesce(x->'components', '{}'::jsonb), 'Manual entry', v_src, null, 1, 'manual:' || lower(x->>'test'), 'active', now())
      on conflict (course_id, english_test_id) do update set overall_score = excluded.overall_score, component_scores = excluded.component_scores,
             notes = 'Manual entry', source_id = v_src, evidence_id = null, confidence = 1, source_requirement_key = excluded.source_requirement_key,
             status = 'active', last_verified_at = now();
      v_keep := v_keep || v_test;
    end loop;
    update catalogue.course_english_requirements set status = 'inactive' where course_id = p_course_id and status = 'active' and not (english_test_id = any(v_keep));
    perform security.manual_lock_set('course', p_course_id, 'english', 'value');
    v_after := p_args->'tests';

  elsif p_action = 'remove_english' then
    v_field := 'english';
    select jsonb_agg(jsonb_build_object('test', t.code, 'overall', e.overall_score)) into v_before
      from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id where e.course_id = p_course_id and e.status = 'active';
    update catalogue.course_english_requirements set status = 'inactive' where course_id = p_course_id and status = 'active';
    perform security.manual_lock_set('course', p_course_id, 'english', 'removed');

  elsif p_action = 'set_tuition' then
    v_field := 'tuition';
    if coalesce(p_args->>'amount', '') !~ '^[0-9]+(\.[0-9]+)?$' or (p_args->>'amount')::numeric < 100 then raise exception 'enter the fee as a number, for example 45000'; end if;
    if coalesce(p_args->>'basis', 'annual') not in ('annual','total_indicative','per_semester','per_trimester') then raise exception 'choose per year, per semester, per trimester or whole course'; end if;
    v_amount := (p_args->>'amount')::numeric;
    select jsonb_agg(jsonb_build_object('amount', amount, 'year', fee_year, 'basis', basis)) into v_before
      from catalogue.course_fees where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    update catalogue.course_fees set status = 'superseded', updated_at = now(),
           notes = coalesce(notes, '') || ' | superseded by a manual entry ' || to_char(now(), 'YYYY-MM-DD')
     where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    insert into catalogue.course_fees(course_id, fee_year, audience, fee_type, amount, currency_code, basis, notes, source_id, confidence, source_fee_key, status, last_verified_at)
    values (p_course_id, nullif(p_args->>'fee_year', '')::int, 'international', 'provider_current_tuition', v_amount, coalesce(nullif(p_args->>'currency', ''), (select k.default_currency_code::text from catalogue.providers pv join ref.countries k on k.id = pv.country_id where pv.id = v_c.provider_id), 'AUD'),
            coalesce(p_args->>'basis', 'annual'), 'Manual entry', v_src, 1, 'manual:' || extract(epoch from clock_timestamp())::bigint, 'active', now());
    perform security.manual_lock_set('course', p_course_id, 'tuition', 'value');
    v_after := jsonb_build_object('amount', v_amount, 'year', nullif(p_args->>'fee_year', ''), 'basis', coalesce(p_args->>'basis', 'annual'), 'currency', coalesce(nullif(p_args->>'currency', ''), (select k.default_currency_code::text from catalogue.providers pv join ref.countries k on k.id = pv.country_id where pv.id = v_c.provider_id), 'AUD'));

  elsif p_action = 'remove_tuition' then
    v_field := 'tuition';
    select jsonb_agg(jsonb_build_object('amount', amount, 'year', fee_year, 'basis', basis)) into v_before
      from catalogue.course_fees where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    update catalogue.course_fees set status = 'inactive', updated_at = now(), notes = coalesce(notes, '') || ' | removed by hand ' || to_char(now(), 'YYYY-MM-DD')
     where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    perform security.manual_lock_set('course', p_course_id, 'tuition', 'removed');

  elsif p_action = 'release' then
    v_field := p_args->>'field';
    select to_jsonb(l) into v_before from pipeline.manual_locks l where entity = 'course' and entity_id = p_course_id and field = v_field;
    if v_before is null then raise exception 'nothing to release'; end if;
    delete from pipeline.manual_locks where entity = 'course' and entity_id = p_course_id and (field = v_field or (v_field = 'official_url' and field = 'course_url'));
    if v_field = 'official_url' then
      update pipeline.coverage_course_pages set basis = 'released' where course_id = p_course_id and basis = 'manual';
    end if;

  elsif p_action in ('archive','restore') then
    v_field := 'lifecycle_status'; v_before := to_jsonb(v_c.lifecycle_status);
    update catalogue.courses set lifecycle_status = case p_action when 'archive' then 'inactive' else 'active' end, updated_at = now() where id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, 'lifecycle_status', 'value');
    v_after := to_jsonb(case p_action when 'archive' then 'inactive' else 'active' end);

  else
    raise exception 'unknown action %', p_action;
  end if;

  if v_field in ('official_url','intakes','english','tuition') and p_action <> 'release' then
    perform security.manual_close_layer4(p_course_id, v_field);
  end if;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('course', p_course_id, v_field, p_action, v_before, v_after, v_reason, auth.uid());
  perform search.refresh_course_enrichment_scoped_v1(array[p_course_id], true);
  return public.admin_course_edit_read(p_course_id);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_provider_edit_read(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  if not exists (select 1 from catalogue.providers where id = p_provider_id) then raise exception 'provider not found'; end if;
  return (select jsonb_build_object(
    'provider', jsonb_build_object('id', p.id, 'canonical_name', p.canonical_name, 'display_name', p.display_name, 'short_name', p.short_name,
               'website', p.website, 'phone', p.phone, 'email', p.email, 'description', p.description, 'primary_city', p.primary_city,
               'address_line1', p.address_line1, 'postcode', p.postcode, 'lifecycle_status', p.lifecycle_status, 'country', k.name, 'state', s.name,
               'manual_provider', p.stable_key like 'manual:%', 'website_verdict', security.provider_site_verdict_v1(p.id, p.website),
               'active_courses', (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')),
    'course_finder', (select jsonb_build_object('address', d.website, 'status', d.status, 'pages_found', d.kept_count, 'mapped_at', d.mapped_at,
                               'verdict', security.provider_site_verdict_v1(p.id, d.website), 'source', d.site_source)
                        from pipeline.coverage_provider_discovery d where d.provider_id = p.id),
    'link_recipe', (select jsonb_build_object('search_domain', r.search_domain, 'patterns', r.patterns, 'active', r.active)
                      from pipeline.course_link_recipes r where r.provider_id = p.id),
    'locks', (select coalesce(jsonb_object_agg(l.field, jsonb_build_object('mode', l.mode, 'at', l.set_at)), '{}'::jsonb)
               from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('at', h.at, 'field', h.field, 'action', h.action, 'before', h.before, 'after', h.after,
               'reason', h.reason, 'by', u.email) order by h.at desc), '[]'::jsonb)
               from (select * from pipeline.manual_edit_log where entity = 'provider' and entity_id = p.id order by at desc limit 20) h left join auth.users u on u.id = h.actor),
    'can_edit', v_rank >= 3, 'can_manage', v_rank >= 5)
   from catalogue.providers p left join ref.countries k on k.id = p.country_id left join ref.subdivisions s on s.id = p.subdivision_id where p.id = p_provider_id);
end $function$;

-- 4. Existing data (Feature 1, Feature 3, Fix 1). Nothing is deleted; values entered by hand (manual locks) are never touched.
-- 4a. Course finder addresses on a third-party site are cleared and go back to the website search (status no_website, searched never).
update pipeline.coverage_provider_discovery d
   set website = null, status = 'no_website', site_source = null, site_searched_at = null, leased_until = null,
       last_error = 'third-party course finder removed (v2.15.233)', updated_at = now()
 where security.third_party_host_v1(d.website) and coalesce(d.site_source, '') <> 'manual'
   and not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = d.provider_id and l.field = 'course_finder');

-- 4b. Course pages on a third-party site are refused (the refused-host guard sets them to mismatch / refused_host).
update pipeline.coverage_course_pages g set status = g.status where g.status in ('bound', 'ambiguous') and security.third_party_host_v1(g.url);

-- 4c. Facts read from third-party pages are withdrawn and their official-page links made inactive. Locked values are skipped by the guard.
create temp table _r2_ev on commit drop as select a.id from pipeline.evidence_artifacts a where security.third_party_host_v1(a.source_url);
update catalogue.course_intakes x set status = 'withdrawn' where x.status = 'active' and x.evidence_id in (select id from _r2_ev);
update catalogue.course_english_requirements x set status = 'withdrawn' where x.status = 'active' and x.evidence_id in (select id from _r2_ev);
update catalogue.course_links x set status = 'inactive', is_primary = false, updated_at = now()
 where x.status = 'active' and (x.evidence_id in (select id from _r2_ev) or (x.link_type = 'official_course' and security.third_party_host_v1(x.url)));

-- 4d. Those courses look for their page again on the provider's own site, where the provider has one.
insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
select g.course_id, g.provider_id, 'title', 'queued', now()
  from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id and c.lifecycle_status = 'active'
 where g.read_status = 'refused_host' and security.third_party_host_v1(g.url)
   and exists (select 1 from pipeline.course_link_recipes r where r.provider_id = g.provider_id and r.active)
on conflict (course_id) do update set state = 'queued', queued_at = now(), bound_url = null, done_at = null
 where pipeline.course_link_search.state <> 'queued';

-- 4e. Fix 1: a site the search found that is the provider's own (its address fits the provider's name) becomes the provider's
--     website when none is recorded. Automated (not locked); a website entered by hand is never replaced.
update catalogue.providers p set website = substring(btrim(d.website) from '^(https?://[^/?#]+)'), updated_at = now()
  from pipeline.coverage_provider_discovery d
 where d.provider_id = p.id and p.website is null and d.website is not null
   and d.website ~* '^https?://' and security.provider_site_verdict_v1(p.id, d.website) = 'own'
   and not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field = 'website');

-- 4f. Search documents are rebuilt so withdrawn facts leave the consumer APIs.
insert into search.refresh_requests(requested_by) values ('v2.15.233: third-party course directories removed; facts read from them withdrawn');

do $post$
declare v_expected jsonb := jsonb_build_object('security.refused_host(text)', '348b59aa5483cee2e71c29b76bd80eef', 'public.svc_coverage_site_record(uuid,text,jsonb)', 'db8dd06546847801b76434e02a483cc4', 'public.svc_site_hint_next(integer)', 'a15edf558246bd8cea4f8166bcf44fb1', 'public.admin_provider_edit(uuid,text,jsonb)', '88d604e0b4dcb6a012550d2384a63bdb', 'public.admin_course_edit(uuid,text,jsonb)', 'a8acab9d6f56a5ccca9dafa435318f05', 'public.admin_provider_edit_read(uuid)', 'fd6fec4d444de5eb920b8a618e1a7d09');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 v2.15.233 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
