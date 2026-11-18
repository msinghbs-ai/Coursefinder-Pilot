-- CF-247 (21 Oct 2026). Platform Admin 19:18: "Go on with task 3" (the three adapter fixes: A, course-page filter; shared pages for
-- Otago, SFU and Calgary; the NZIST names).
-- Found while looking into why seven automatic plans stopped at the adapter:
--   - pages that are not course pages were bound as course pages (library guides, thesis and journal repositories, research guides,
--     archived handbooks): 174 bound pages at 18 providers (Georgian College 49, University of Sydney 33, University of Manitoba 28,
--     George Brown College 19, ...), 103 of them published as the course's official link;
--   - universities' term dates did not become intakes outside Australia: security.calendar_default_intakes_apply_v1 had the country
--     written in as 'AU' (a G2 gap), and the parsed calendars of Otago, Calgary and SFU give no single start month per period;
--   - SFU's English central page was a Computing Science FAQ, not the admission requirement;
--   - six New Zealand records shared the name "New Zealand Institute of Skills and Technology" (NZQA 6012, 6014, 6017, 6024, 6044, 6683).
-- Changes:
--   1 Setting pages.not_course_patterns (list of patterns) and security.not_course_page_v1(url). The existing guard trigger on
--     pipeline.coverage_course_pages (security.coverage_page_refused_host_guard) now also turns a page matching a pattern into
--     'mismatch' / 'not_course_page' whichever job binds it, unless a person entered the course's official link. The 174 pages bound now
--     are marked the same way and blocked for their course (pipeline.course_page_blocks), and their 103 active official links are set
--     inactive (not removed); the course-page jobs then look for the right page as for any mismatch.
--   2 Setting calendar.countries (["AU", "NZ", "CA"]) replaces the 'AU' written into security.calendar_default_intakes_apply_v1.
--   3 Start months set by hand (the existing by-hand calendar, as for the Australian universities on 7 Oct 2026) from each university's
--     dates page: Otago semester 1 March, semester 2 July; Calgary fall September, winter January; SFU fall September, spring January,
--     summer May. University courses take these at the levels in calendar.university_levels (undergraduate).
--   4 SFU English: the undergraduate English language requirement page added as SFU's English central page (read by job provider-facts).
--   5 NZIST names from NZQA: NorthTec (6012), Whitireia and WelTec (6014), Western Institute of Technology at Taranaki (6017),
--     Tai Poutini Polytechnic (6024), NZIST Work-Based Learning (6044: Competenz, Connexis, Careerforce, ServiceIQ, Primary ITO, EarnLearn),
--     New Zealand Institute of Skills and Technology (NZIST) (6683, national programmes). Not duplicates: each has its own NZQA number
--     and courses. Names locked against overwrite as with the NZ names on 21 Oct (20261021090000).
-- Replaces: security.coverage_page_refused_host_guard (not-course patterns); security.calendar_default_intakes_apply_v1 (countries from a
--   setting). Both md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted (links set inactive, pages marked mismatch). Consumer API not touched (Decision 266): no function, table or
-- column of it changes; provider names and official links change as data.

do $guard$
declare v_expected jsonb := '{"security.coverage_page_refused_host_guard()": "eb1ede4888edc10c9be0a9df7aae25e6",
                              "security.calendar_default_intakes_apply_v1()": "e599beeaab073a91d534a4208adc0fc6"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(pg_get_functiondef(v_sig::regprocedure)) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
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

-- Settings ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'pages.not_course_patterns', 'Never a course page',
  'Address patterns (regular expressions, case ignored) that are never a course page: library and research guides, thesis and journal repositories, archived handbooks. A page matching one is not bound to a course by any job, unless a person entered that course''s official link.',
  'list', '["^https?://([a-z0-9-]+\\.)*(library|libguides|lib|researchguides|researchcommons|researchspace|research-repository|repository|eprints|mspace|ojs|journals?|journalhosting|ourarchive|digitalcollections|careers|jobs|alumni|shop|store)\\.", "/(article/(download|view)|bitstreams?|handle/[0-9]|islandora|esploro|view/delivery)/", "/(calendar|handbook|archive)s?/(19|20)[0-1][0-9]/", "/c\\.php\\?g=[0-9]"]'::jsonb,
  null, null, 'patterns', 318, 'CF-247, Platform Admin 21 Oct 2026 19:18 "Go on with task 3" (174 non-course pages bound at 18 providers)', 'Course pages', 'trigger coverage_page_refused_host (security.not_course_page_v1)'),
 ('pipeline', 'calendar.countries', 'Countries whose term dates give intakes',
  'Countries in which a provider''s approved term dates fill intakes for courses that name none (universities: only the levels in University courses filled from the academic calendar).',
  'list', '["AU", "NZ", "CA"]'::jsonb, null, null, 'countries', 321, 'CF-247, Platform Admin 21 Oct 2026 19:18 "Go on with task 3" (was written in as AU)', 'Enrichment', 'security.calendar_default_intakes_apply_v1')
on conflict (toolset_key, key) do nothing;

-- 1 Never a course page --------------------------------------------------------------------------------------------------------------
create or replace function security.not_course_page_v1(p_url text)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select coalesce(p_url, '') <> '' and exists (
    select 1 from pipeline.platform_toolset_settings s, jsonb_array_elements_text(coalesce(s.value, '[]'::jsonb)) x(p)
     where s.toolset_key = 'pipeline' and s.key = 'pages.not_course_patterns' and p_url ~* x.p)
$function$;
revoke execute on function security.not_course_page_v1(text) from public, anon, authenticated;

select pg_temp.edit_once('security.coverage_page_refused_host_guard()', 'eb1ede4888edc10c9be0a9df7aae25e6', array[
  [$o$    new.status := 'mismatch'; new.read_status := 'refused_host'; new.identity_basis := null; new.next_read_at := null;
  end if;$o$,
   $n$    new.status := 'mismatch'; new.read_status := 'refused_host'; new.identity_basis := null; new.next_read_at := null;
  -- 21 Oct 2026 (Platform Admin "Go on with task 3"): never a course page (setting pages.not_course_patterns)
  elsif new.status in ('bound', 'ambiguous') and security.not_course_page_v1(new.url)
     and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = new.course_id and k.field = 'official_url') then
    new.status := 'mismatch'; new.read_status := 'not_course_page'; new.identity_basis := null; new.next_read_at := null;
  end if;$n$]]);

create temp table not_course_now on commit drop as
select cp.course_id, cp.url, cp.provider_id
  from pipeline.coverage_course_pages cp
 where cp.status = 'bound' and security.not_course_page_v1(cp.url)
   and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = cp.course_id and k.field = 'official_url');

insert into pipeline.course_page_blocks(course_id, url, reason)
select course_id, url, 'not a course page (pages.not_course_patterns), CF-247 21 Oct 2026' from not_course_now
on conflict (course_id, url) do nothing;

update catalogue.course_links l set status = 'inactive', updated_at = now()
  from not_course_now n
 where l.course_id = n.course_id and l.url = n.url and l.link_type = 'official_course' and l.status = 'active';

update pipeline.coverage_course_pages cp set status = 'mismatch', read_status = 'not_course_page', identity_basis = null, next_read_at = null
  from not_course_now n where cp.course_id = n.course_id and cp.url = n.url;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'coverage', 'not_course_pages', 'course pages',
       jsonb_build_object('pages', count(*), 'providers', count(distinct provider_id), 'reason', 'CF-247 21 Oct 2026: never a course page (pages.not_course_patterns)'), null
  from not_course_now;

-- 2 Countries from a setting ---------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.calendar_default_intakes_apply_v1()', 'e599beeaab073a91d534a4208adc0fc6', array[
  [$o$k.iso_alpha2 = 'AU')$o$,
   $n$k.iso_alpha2 in (select jsonb_array_elements_text(s3.value) from pipeline.platform_toolset_settings s3 where s3.toolset_key = 'pipeline' and s3.key = 'calendar.countries'))$n$]]);

-- 3 Start months by hand -------------------------------------------------------------------------------------------------------------
insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, url, style, proposal, status, decided_by, decided_at, decision_note)
select f.provider_id, f.id, 'intake_calendar', 'set by hand', f.url, 'by_hand', v.proposal, 'approved', '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid, now(), v.note
  from (values
    ('340845cf-0ed1-4e1a-8c87-39a7fb997257'::uuid, '{"periods": [{"months": [3], "period": "semester 1"}, {"months": [7], "period": "semester 2"}]}'::jsonb,
     'CF-247 21 Oct 2026: Otago dates page (Semester 1 formal lectures begin 1 March 2027; Semester 2 from July); Platform Admin "Go on with task 3"'),
    ('e02f0326-0b95-4904-84d1-b701b27981b8'::uuid, '{"periods": [{"months": [9], "period": "term 1"}, {"months": [1], "period": "term 2"}]}'::jsonb,
     'CF-247 21 Oct 2026: Calgary registrar dates (Fall classes 1 Sept 2026, Winter classes 11 Jan 2027; spring and summer not mapped); Platform Admin "Go on with task 3"'),
    ('0d9651ad-e9e4-469f-9d81-c497a793d6c4'::uuid, '{"periods": [{"months": [9], "period": "term 1"}, {"months": [1], "period": "term 2"}, {"months": [5], "period": "term 3"}]}'::jsonb,
     'CF-247 21 Oct 2026: SFU terms (Fall September, Spring January, Summer May); Platform Admin "Go on with task 3"')) v(src, proposal, note)
  join pipeline.provider_fact_sources f on f.id = v.src and f.kind = 'intake_calendar'
 where not exists (select 1 from pipeline.provider_policy_proposals x where x.fact_source_id = f.id and x.style = 'by_hand' and x.status = 'approved');

-- 4 SFU English page -----------------------------------------------------------------------------------------------------------------
insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status)
select p.id, 'english_policy', 'https://www.sfu.ca/students/admission/admission-requirements/english-language-requirement.html',
       'English language requirement - Undergraduate Admission - Simon Fraser University', 9, 'manual', 'found'
  from catalogue.providers p where p.display_name = 'Simon Fraser University (SFU)'
on conflict (provider_id, kind, url) do nothing;
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'toolsets', 'central_page_add', p.id::text,
       jsonb_build_object('kind', 'english_policy', 'url', 'https://www.sfu.ca/students/admission/admission-requirements/english-language-requirement.html',
                          'reason', 'CF-247 21 Oct 2026: the English page on record was a Computing Science FAQ'), null
  from catalogue.providers p where p.display_name = 'Simon Fraser University (SFU)';

-- 5 NZIST names ----------------------------------------------------------------------------------------------------------------------
create temp table nzist_names(stable_key text, name text) on commit drop;
insert into nzist_names values
 ('provider:nzqa:6012', 'NorthTec'),
 ('provider:nzqa:6014', 'Whitireia and WelTec'),
 ('provider:nzqa:6017', 'Western Institute of Technology at Taranaki (WITT)'),
 ('provider:nzqa:6024', 'Tai Poutini Polytechnic'),
 ('provider:nzqa:6044', 'NZIST Work-Based Learning (Competenz, Connexis, Careerforce, ServiceIQ, Primary ITO, EarnLearn)'),
 ('provider:nzqa:6683', 'New Zealand Institute of Skills and Technology (NZIST)');
do $names$
begin
  if (select count(*) from catalogue.providers p join nzist_names n on n.stable_key = p.stable_key
       where p.display_name = 'New Zealand Institute of Skills and Technology') <> 6 then
    raise exception 'the six NZIST records are not as expected';
  end if;
end $names$;
select set_config('cf.manual_edit', 'on', true);
update catalogue.providers p set display_name = n.name, canonical_name = n.name, updated_at = now()
  from nzist_names n where p.stable_key = n.stable_key and p.display_name = 'New Zealand Institute of Skills and Technology';
insert into pipeline.manual_locks(entity, entity_id, field, mode)
select 'provider', p.id, f, 'value' from catalogue.providers p join nzist_names n on n.stable_key = p.stable_key cross join unnest(array['display_name', 'canonical_name']) f
on conflict (entity, entity_id, field) do nothing;

insert into search.refresh_requests(requested_by) values ('cf247_page_filter_calendars_nzist');

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'security.not_course_page_v1', 'Layer 2', 'Addresses that are never a course page (setting pages.not_course_patterns)', 'active', '20261021235000')
on conflict (kind, name) do nothing;
