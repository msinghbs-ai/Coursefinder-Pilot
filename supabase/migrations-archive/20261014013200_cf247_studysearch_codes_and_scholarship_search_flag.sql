-- CF-247 v2.15.271 (Platform Admin, 14 Oct 2026 08:33 and 08:4x):
--   "For canada, there was no coursecode and hence had to create something to host the code column. Recommend options here." Chosen:
--   "fill the real program code and if missing generate the studysearch code, create something not too long and meaningful with
--   uni/campus/Degree based, it will be applicable to upcoming countries as well".
--   "Bug/fix: skip scholarship search for any provider whose website is a directory site ... I need visible flag in provider for such
--   rows. Which we can toggle to enable." Chosen: "Auto off, operator can enable" and "Close them and stop the loop".
--
--   1 Course codes. ref.course_code_schemes says which identifier types are codes printed by the university or regulator (CRICOS,
--     NZQA, Canadian college program codes) and which are source IDs (portal GUIDs, page and post IDs, address slugs). A course with a
--     printed code keeps it. A course without one gets a StudySearch code, stored as a typed identifier (scheme "studysearch"), never
--     in course_code (course_code stays the source's own value, which the importers match on):
--        <university>-<level>-<number>, e.g. UBC-MA-042
--     university: its own acronym when the name carries one, else the initials of three or more words, else four letters of its
--     distinctive word (unique within the country); level: two letters from the study level (ref.study_levels.short_code) or the
--     title; number: per university and level, in title order. A code never changes once given. The campus is not part of the code:
--     NZ and Canadian courses have no campus records, and a course that adds a campus would otherwise change its code.
--     The hourly job studysearch-codes gives new courses their code (batch: setting batch.studysearch_codes).
--     The course list and course record show the code (display_code, code_kind) and search finds it.
--   2 Scholarship search flag. pipeline.provider_scholarship_search: Off automatically for a provider whose only known website is a
--     directory site; a Pipeline Operator turns it On with a reason and the provider's own website (that starts a fresh search) or
--     Off with a reason. Discovery, page reading and the AI reader skip providers that are Off.
--   3 The AI reader closes queued reads of directory-site pages or of providers that are Off (state failed, skip_reason), and a read
--     refused for credits now counts toward its 3 tries (it was put back without counting, so refused reads looped every 30 minutes).
-- Nothing dropped or deleted.

do $guard$
declare v_expected jsonb := '{"public.svc_scholarship_ai_next(integer)": "e8154195063bc519ecef412d487d958f", "public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)": "b047f8d230f41aedd732901bf4a630a3", "public.svc_scholarship_candidate_next(integer)": "5034833c89c7e64f55b0b54541d52588", "public.svc_scholarship_discover_next(integer)": "e95b75eebb347fe10f52da089b7df113", "security.scholarship_discovery_refill_v1(integer)": "ef694f93915004f2a45500f394226e42", "security.admin_course_page_fast_base(jsonb)": "99bbbc5cd444185935da9e96b173a80e", "security.admin_course_page_unfiltered_fast(jsonb)": "3b39481d15e5c35ab121bf435342fbf0", "public.admin_read(text,jsonb)": "f910ab61f1e84c2bb3b8f1ef5f3eb198"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1 Which identifier types are printed codes
create table if not exists ref.course_code_schemes (
  scheme text primary key,
  printed boolean not null,
  label text not null,
  note text,
  updated_at timestamptz not null default now());
alter table ref.course_code_schemes enable row level security;
insert into ref.course_code_schemes(scheme, printed, label, note) values
 ('cricos', true, 'CRICOS course code', 'Australia, regulator'),
 ('nzqa', true, 'NZQA qualification number', 'New Zealand, regulator'),
 ('qc_mes_program_code', true, 'Quebec program code', 'Quebec ministry'),
 ('conestoga_program_code', true, 'Program code', 'Conestoga'),
 ('georgian_program_code', true, 'Program code', 'Georgian'),
 ('fanshawe_program_code', true, 'Program code', 'Fanshawe'),
 ('seneca_program_code', true, 'Program code', 'Seneca'),
 ('centennial_program_code', true, 'Program code', 'Centennial'),
 ('saskpoly_program_code', true, 'Program code', 'Saskatchewan Polytechnic'),
 ('stclair_program_code', true, 'Program code', 'St. Clair'),
 ('cna_course_code', true, 'Program code', 'College of the North Atlantic'),
 ('mohawk_program_code', true, 'Program code', 'Mohawk'),
 ('algonquin_program_code', true, 'Program code', 'Algonquin'),
 ('sault_program_code', true, 'Program code', 'Sault'),
 ('lambton_program_code', true, 'Program code', 'Lambton'),
 ('stlawrence_program_code', true, 'Program code', 'St. Lawrence'),
 ('bc_epbc_program_guid', false, 'EducationPlannerBC ID', 'British Columbia portal record ID'),
 ('ab_alis_program_guid', false, 'ALIS ID', 'Alberta portal record ID'),
 ('on_aps', false, 'Ontario portal ID', 'Ontario portal record number'),
 ('sheridan_program_item_id', false, 'Sheridan page ID', 'Web page ID'),
 ('durham_program_id', false, 'Durham page ID', 'Web page ID'),
 ('mb_sao_program_id', false, 'Manitoba portal ID', 'Portal record ID'),
 ('nscc_program_plan_code', false, 'NSCC plan code', 'Internal plan code'),
 ('niagara_program_page_id', false, 'Niagara page ID', 'Web page ID'),
 ('cambrian_program_id', false, 'Cambrian page ID', 'Web page ID'),
 ('loyalist_program_id', false, 'Loyalist page ID', 'Web page ID'),
 ('fleming_program_guid', false, 'Fleming page address', 'Web address path'),
 ('boreal_program_slug', false, 'Boréal page address', 'Web address slug'),
 ('confederation_program_id', false, 'Confederation page ID', 'Web page ID'),
 ('yukonu_drupal_node_id', false, 'Yukon page ID', 'Web page ID'),
 ('northern_program_slug', false, 'Northern page address', 'Web address slug'),
 ('aurora_wp_post_id', false, 'Aurora page ID', 'Web page ID'),
 ('studysearch', false, 'StudySearch code', 'Given by StudySearch when no printed code exists')
on conflict (scheme) do nothing;

alter table ref.study_levels add column if not exists short_code text;
update ref.study_levels set short_code = v.s from (values
 ('primary_school_studies','PS'),('junior_secondary_studies','JS'),('foundation','FN'),('senior_secondary_certificate','SS'),
 ('certificate','CT'),('certificate_i','C1'),('certificate_ii','C2'),('certificate_iii','C3'),('certificate_iv','C4'),
 ('vocational_short_course','SC'),('diploma','DP'),('advanced_diploma','AD'),('associate_degree','AS'),('bachelor','BA'),
 ('bachelor_honours','BH'),('graduate_certificate','GC'),('graduate_diploma','GD'),('masters','MA'),('masters_coursework','MC'),
 ('masters_research','MR'),('masters_extended','ME'),('professional_degree','PD'),('doctorate','DR'),('non_aqf_award','NA')) v(c, s)
 where ref.study_levels.code = v.c and ref.study_levels.short_code is null;

create index if not exists idx_course_identifiers_studysearch on catalogue.course_identifiers (upper(identifier)) where scheme = 'studysearch';

CREATE OR REPLACE FUNCTION security.studysearch_acronym_v1(p_name text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v text; w text[]; s text := ''; x text;
begin
  -- the university's own short name when it is in brackets, e.g. "University of British Columbia (UBC)"
  v := (regexp_match(coalesce(p_name, ''), '\(([A-Za-z&]{2,8})\)'))[1];
  if v is not null then v := upper(regexp_replace(v, '[^A-Za-z]', '', 'g')); if length(v) between 2 and 6 then return v; end if; end if;
  w := array(select t from regexp_split_to_table(
         translate(regexp_replace(lower(coalesce(p_name, '')), '\(.*?\)', ' ', 'g'), 'éèêëàâäîïôöûüùçñ', 'eeeeaaaiioouuucn'), '[^a-z0-9]+') t
       where t <> '' and t not in ('of','the','and','for','at','in','de','du','des','la','le','les','et','d','l','pty','ltd','limited','inc','co'));
  if coalesce(array_length(w, 1), 0) >= 3 then
    foreach x in array w loop s := s || left(x, 1); end loop;
    return upper(left(s, 5));
  end if;
  -- one or two words: four letters of the distinctive word ("Humber College" HUMB, "University of Toronto" TORO)
  foreach x in array w loop
    if x not in ('university','universite','college','cegep','institute','institut','polytechnic','school','academy','centre','center',
                 'campus','international','education','technology','tafe') then return upper(left(x, 4)); end if;
  end loop;
  if coalesce(array_length(w, 1), 0) > 0 then return upper(left(w[1], 4)); end if;
  return 'UNI';
end $function$;

-- two letters for the level: the study level's short code, else read from the title
CREATE OR REPLACE FUNCTION security.studysearch_level_v1(p_level uuid, p_title text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce((select sl.short_code from ref.study_levels sl where sl.id = p_level),
    case when p_title ~* '(ph\.?d|doctor)' then 'DR'
         when p_title ~* 'master|ma[iî]trise' then 'MA'
         when p_title ~* '(graduate|post-?graduate|postgrad|post-?baccalaur|post-?dipl).{0,12}(diploma|dipl[oô]me)' then 'GD'
         when p_title ~* '(graduate|post-?graduate|postgrad).{0,12}(certificate|certificat)' then 'GC'
         when p_title ~* 'bachelor|baccalaur' then 'BA'
         when p_title ~* 'advanced diploma' then 'AD'
         when p_title ~* 'diploma|dipl[oô]me|\mdec\M' then 'DP'
         when p_title ~* 'certificate|certificat|attestation|\maec\M' then 'CT'
         when p_title ~* 'degree' then 'DG'
         else 'CO' end)
$function$;

-- Gives a StudySearch code to courses with no printed code (the hourly job studysearch-codes, and once in this migration)
CREATE OR REPLACE FUNCTION security.studysearch_code_assign_v1(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_base text; v_code text; i int; v_prov int := 0; v_courses int := 0;
begin
  create temp table if not exists _ss_need (id uuid, provider_id uuid, country_id uuid, pname text, title text, level_id uuid) on commit drop;
  truncate _ss_need;
  insert into _ss_need
  select c.id, c.provider_id, p.country_id, coalesce(p.display_name, p.canonical_name), c.canonical_title, c.study_level_id
    from catalogue.courses c join catalogue.providers p on p.id = c.provider_id
   where not exists (select 1 from catalogue.course_identifiers i where i.course_id = c.id and i.scheme = 'studysearch')
     -- a printed code: one from a printed identifier type, or a code entered with no identifier behind it
     and not (nullif(btrim(c.course_code), '') is not null
              and (not exists (select 1 from catalogue.course_identifiers i where i.course_id = c.id)
                   or exists (select 1 from catalogue.course_identifiers i join ref.course_code_schemes s on s.scheme = i.scheme and s.printed
                               where i.course_id = c.id)))
   order by c.provider_id, lower(c.canonical_title), c.id
   limit greatest(coalesce(p_limit, 0), 0);
  -- university codes, unique within the country
  for r in select distinct n.provider_id, n.country_id, n.pname from _ss_need n
            where not exists (select 1 from catalogue.provider_identifiers x where x.provider_id = n.provider_id and x.scheme = 'studysearch_provider') loop
    v_base := security.studysearch_acronym_v1(r.pname); v_code := v_base; i := 1;
    while exists (select 1 from catalogue.provider_identifiers x join catalogue.providers p2 on p2.id = x.provider_id
                   where x.scheme = 'studysearch_provider' and x.identifier = v_code and p2.country_id is not distinct from r.country_id) loop
      i := i + 1; v_code := v_base || i;
    end loop;
    insert into catalogue.provider_identifiers(provider_id, scheme, identifier, country_id, issuing_authority, is_primary)
    values (r.provider_id, 'studysearch_provider', v_code, r.country_id, 'StudySearch', false);
    v_prov := v_prov + 1;
  end loop;
  insert into catalogue.course_identifiers(course_id, provider_id, scheme, identifier, country_id, issuing_authority, is_primary)
  select n.id, n.provider_id, 'studysearch',
         pc.identifier || '-' || n.lvl || '-' || lpad((coalesce(mx.m, 0) + row_number() over (partition by n.provider_id, n.lvl order by lower(n.title), n.id))::text, 3, '0'),
         n.country_id, 'StudySearch', false
    from (select x.*, security.studysearch_level_v1(x.level_id, x.title) lvl from _ss_need x) n
    join catalogue.provider_identifiers pc on pc.provider_id = n.provider_id and pc.scheme = 'studysearch_provider'
    left join lateral (select max(substring(i.identifier from '-([0-9]+)$')::int) m from catalogue.course_identifiers i
                        where i.provider_id = n.provider_id and i.scheme = 'studysearch' and i.identifier like pc.identifier || '-' || n.lvl || '-%') mx on true
  on conflict (provider_id, scheme, identifier) do nothing;
  get diagnostics v_courses = row_count;
  return jsonb_build_object('universities', v_prov, 'courses', v_courses);
end $function$;
revoke all on function security.studysearch_code_assign_v1(integer) from public, anon, authenticated;

-- The code a screen shows for a course: its StudySearch code when it has one, else its own code
CREATE OR REPLACE FUNCTION security.course_display_code_v1(p_course uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when ss.identifier is not null then jsonb_build_object('code', ss.identifier, 'kind', 'studysearch', 'label', 'StudySearch code')
              else jsonb_build_object('code', c.course_code, 'kind', 'own',
                     'label', coalesce((select s.label from catalogue.course_identifiers i join ref.course_code_schemes s on s.scheme = i.scheme
                                         where i.course_id = c.id and i.identifier = c.course_code limit 1), 'Course code')) end
    from catalogue.courses c
    left join lateral (select i.identifier from catalogue.course_identifiers i where i.course_id = c.id and i.scheme = 'studysearch' limit 1) ss on true
   where c.id = p_course
$function$;
grant execute on function security.course_display_code_v1(uuid) to authenticated;

-- 2 Scholarship search flag
create table if not exists pipeline.provider_scholarship_search (
  provider_id uuid primary key references catalogue.providers(id) on delete cascade,
  enabled boolean not null,
  auto boolean not null default false,
  reason text,
  set_by uuid,
  set_at timestamptz not null default now());
alter table pipeline.provider_scholarship_search enable row level security;
create table if not exists pipeline.provider_scholarship_search_log (
  id bigserial primary key,
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  enabled boolean not null,
  auto boolean not null default false,
  reason text,
  website text,
  set_by uuid,
  at timestamptz not null default now());
alter table pipeline.provider_scholarship_search_log enable row level security;
alter table pipeline.scholarship_ai_queue add column if not exists skip_reason text;

-- the provider's own website (not a directory site), from its record or the website finder; null when none is known
CREATE OR REPLACE FUNCTION security.provider_own_site_v1(p_provider uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    (select nullif(btrim(p.website), '') from catalogue.providers p where p.id = p_provider and nullif(btrim(p.website), '') is not null and not security.third_party_host_v1(p.website)),
    (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p_provider and d.status = 'mapped'
        and nullif(btrim(d.website), '') is not null and not security.third_party_host_v1(d.website) limit 1),
    (select nullif(btrim(d.website), '') from pipeline.scholarship_discovery_providers d where d.provider_id = p_provider
        and nullif(btrim(d.website), '') is not null and not security.third_party_host_v1(d.website)))
$function$;

-- a directory site is the only website known for the provider
CREATE OR REPLACE FUNCTION security.provider_directory_only_v1(p_provider uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select security.provider_own_site_v1(p_provider) is null
     and (exists (select 1 from catalogue.providers p where p.id = p_provider and security.third_party_host_v1(coalesce(p.website, '')))
          or exists (select 1 from pipeline.coverage_provider_discovery d where d.provider_id = p_provider and security.third_party_host_v1(coalesce(d.website, '')))
          or exists (select 1 from pipeline.scholarship_discovery_providers d where d.provider_id = p_provider and security.third_party_host_v1(coalesce(d.website, ''))))
$function$;

CREATE OR REPLACE FUNCTION security.provider_sch_search_off_v1(p_provider uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (select 1 from pipeline.provider_scholarship_search f where f.provider_id = p_provider and not f.enabled)
$function$;

-- Providers list and provider panel: read the flag for some providers, or switch it with a reason (Pipeline Operator and above)
CREATE OR REPLACE FUNCTION public.admin_provider_sch_search(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_pid uuid; v_on boolean; v_reason text; v_site text; v_own text;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  if p_action = 'states' then
    return coalesce((select jsonb_object_agg(p.id::text, jsonb_build_object(
             'on', coalesce(f.enabled, true), 'auto', coalesce(f.auto, false), 'reason', f.reason, 'set_at', f.set_at,
             'directory_only', security.provider_directory_only_v1(p.id), 'own_site', security.provider_own_site_v1(p.id),
             'can_manage', v_rank >= 4))
      from catalogue.providers p left join pipeline.provider_scholarship_search f on f.provider_id = p.id
     where p.id in (select (jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)))::uuid)), '{}'::jsonb);
  elsif p_action = 'off_count' then
    return jsonb_build_object('off', (select count(*) from pipeline.provider_scholarship_search where not enabled),
                              'auto', (select count(*) from pipeline.provider_scholarship_search where not enabled and auto));
  elsif p_action = 'set' then
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    v_pid := nullif(p_args->>'provider_id', '')::uuid; v_on := (p_args->>'on')::boolean; v_reason := btrim(coalesce(p_args->>'reason', ''));
    v_site := nullif(btrim(coalesce(p_args->>'website', '')), '');
    if v_pid is null or v_on is null then raise exception 'provider and on/off are required'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (it is kept in the log)'; end if;
    if v_on then
      if v_site is not null and security.third_party_host_v1(v_site) then raise exception 'that address is a directory site; enter the provider''s own website'; end if;
      v_own := security.provider_own_site_v1(v_pid);
      if v_site is not null and v_site is distinct from v_own then
        perform public.admin_provider_website_set(v_pid, v_site);  -- saved as entered by a person (Curator and above), logged
        v_own := v_site;
      end if;
      if v_own is null then raise exception 'enter the provider''s own website to switch scholarship search on'; end if;
      -- a fresh search from the provider's own website (the 30-course rule and the credit caps still apply)
      insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status)
      values (v_pid, v_own, 4, 'enabled_by_person', 'pending')
      on conflict (provider_id) do update set website = excluded.website, site_origin = null, status = 'pending', attempts = 0,
             leased_until = null, last_error = null, reason = 'enabled_by_person', updated_at = now();
    end if;
    insert into pipeline.provider_scholarship_search(provider_id, enabled, auto, reason, set_by, set_at)
    values (v_pid, v_on, false, v_reason, auth.uid(), now())
    on conflict (provider_id) do update set enabled = excluded.enabled, auto = false, reason = excluded.reason, set_by = excluded.set_by, set_at = now();
    insert into pipeline.provider_scholarship_search_log(provider_id, enabled, auto, reason, website, set_by) values (v_pid, v_on, false, v_reason, v_own, auth.uid());
    return public.admin_provider_sch_search('states', jsonb_build_object('provider_ids', jsonb_build_array(v_pid)));
  end if;
  raise exception 'unknown action %', p_action using errcode = '22023';
end $function$;
revoke all on function public.admin_provider_sch_search(text, jsonb) from public, anon;
grant execute on function public.admin_provider_sch_search(text, jsonb) to authenticated;

-- switched Off automatically for providers whose only website is a directory site (no row yet; a person's choice is never changed)
CREATE OR REPLACE FUNCTION security.provider_sch_search_auto_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v int;
begin
  with ins as (
    insert into pipeline.provider_scholarship_search(provider_id, enabled, auto, reason)
    select x.provider_id, false, true, 'Only website known is a directory site'
      from (select provider_id from pipeline.scholarship_discovery_providers where security.third_party_host_v1(coalesce(website, ''))
            union select provider_id from pipeline.coverage_provider_discovery where security.third_party_host_v1(coalesce(website, ''))
            union select id from catalogue.providers where security.third_party_host_v1(coalesce(website, ''))) x
     where not exists (select 1 from pipeline.provider_scholarship_search f where f.provider_id = x.provider_id)
       and security.provider_directory_only_v1(x.provider_id)
    on conflict (provider_id) do nothing
    returning provider_id, reason)
  insert into pipeline.provider_scholarship_search_log(provider_id, enabled, auto, reason)
  select provider_id, false, true, reason from ins;
  get diagnostics v = row_count;
  return v;
end $function$;

-- the setting, the hourly job and its catalogue entry
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values ('pipeline', 'batch.studysearch_codes', 'StudySearch codes', 'Courses given a StudySearch code in each run (courses with no printed code).',
        'number', to_jsonb(2000), 100, 20000, 'courses a run', 100, 'CF-247 v2.15.271: new job', 'Job sizes', 'studysearch-codes (hourly)')
on conflict do nothing;
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('studysearch-codes', 'Platform upkeep', 90, 'Give StudySearch codes',
        'Courses with no code printed by the university or regulator get a short StudySearch code (university, level, number). A code never changes.', 6, false)
on conflict do nothing;
select cron.schedule('studysearch-codes', '41 * * * *', 'select security.studysearch_code_assign_v1(security.pipeline_num_v1(''batch.studysearch_codes'', 2000)::int)');

CREATE OR REPLACE FUNCTION public.svc_scholarship_ai_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- v2.15.271 (Platform Admin, 14 Oct 2026): pages on a directory site, and providers whose scholarship search is Off, are closed, not read
  update pipeline.scholarship_ai_queue q
     set state = 'failed', done_at = now(), leased_until = null,
         skip_reason = case when security.third_party_host_v1(q.url) then 'directory site' else 'scholarship search off for this provider' end
   where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now()))
     and (security.third_party_host_v1(q.url) or (q.provider_id is not null and security.provider_sch_search_off_v1(q.provider_id)));
  with pick as (
    select q.id from pipeline.scholarship_ai_queue q
     where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
     order by (q.run_kind = 'test') desc, (q.run_kind = 'qualify') desc, q.step desc, q.id
     limit greatest(1, least(coalesce(p_limit, 8), 20)) for update skip locked),
  upd as (update pipeline.scholarship_ai_queue q set state = 'leased', leased_until = now() + interval '4 minutes', attempts = q.attempts + 1 from pick where q.id = pick.id returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('queue_id', u.id, 'model_code', u.model_code, 'model', m.model_identifier, 'prompt_version', u.prompt_version,
           'prompt', (select p.text from pipeline.scholarship_ai_prompts p where p.version = u.prompt_version), 'run_kind', u.run_kind, 'url', u.url,
           'candidate_id', u.candidate_id, 'scholarship_id', u.scholarship_id, 'provider_id', u.provider_id, 'country', case when u.provider_id is not null then security.coverage_country(u.provider_id) end,  -- v2.15.256
           'provider', (select coalesce(pr.display_name, pr.canonical_name) from catalogue.providers pr where pr.id = u.provider_id),
           'currency', case when u.provider_id is not null then scholarship.provider_currency(u.provider_id) else 'AUD' end,
           'storage_path', coalesce(u.storage_path, (select c.storage_path from pipeline.scholarship_page_candidates c where c.id = u.candidate_id),
                                    (select e.storage_path from pipeline.scholarship_pages sp join pipeline.evidence_artifacts e on e.id = sp.evidence_id where sp.scholarship_id = u.scholarship_id),
                                    (select e.storage_path from scholarship.scholarships s join pipeline.evidence_artifacts e on e.id = s.evidence_id where s.id = u.scholarship_id)))), '[]'::jsonb)
    into v from upd u join pipeline.scholarship_ai_models m on m.code = u.model_code;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_ai_record(p_queue_id bigint, p_answer jsonb, p_checks jsonb, p_verdict text, p_cost numeric, p_tokens_in integer, p_tokens_out integer, p_seconds numeric, p_error text, p_storage_path text, p_sha256 text, p_final_url text, p_rule_facts jsonb, p_retry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare q pipeline.scholarship_ai_queue%rowtype; v_id bigint; v_ev uuid; v_on boolean; r jsonb; v_why text; v_next text; v_prev record;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into q from pipeline.scholarship_ai_queue where id = p_queue_id for update;
  if q.id is null then return jsonb_build_object('ok', false, 'reason', 'no queue item'); end if;
  if p_retry then
    -- v2.15.271: a read refused for credits counts toward the 3 tries (it was put back uncounted and looped); after the third it is closed
    update pipeline.scholarship_ai_queue set state = case when attempts >= 3 then 'failed' else 'queued' end, leased_until = null,
           done_at = case when attempts >= 3 then now() end, skip_reason = case when attempts >= 3 then 'no scraper credit after 3 tries' end,
           next_try_at = now() + interval '30 minutes' where id = q.id;
    return jsonb_build_object('ok', true, 'retry', true);
  end if;
  -- v2.15.256: a value an earlier model in this chain proved stands when this model's value is not proven (its own proven value wins)
  if p_error is null and p_verdict = 'scholarship' and not coalesce((p_checks->>'value')::boolean, false)
     and coalesce(p_answer->'value'->>'kind', 'not_stated') not in ('not_stated', 'non_monetary') then
    select e.answer->'value' val, e.model_code into v_prev from pipeline.scholarship_ai_extractions e join pipeline.scholarship_ai_queue x on x.id = e.queue_id
     where coalesce(x.root_id, x.id) = coalesce(q.root_id, q.id) and x.id <> q.id and e.verdict = 'scholarship' and e.error is null
       and coalesce((e.checks->>'value')::boolean, false) order by e.id desc limit 1;
    if v_prev.val is not null then
      p_answer := jsonb_set(p_answer, '{value}', v_prev.val) || jsonb_build_object('value_from', v_prev.model_code);
      p_checks := p_checks || jsonb_build_object('value', true);
    end if;
  end if;
  -- a candidate page read live for the first time: its copy and read are recorded on the candidate, as the scheduled reader does
  if q.candidate_id is not null and p_storage_path is not null then
    update pipeline.scholarship_page_candidates set storage_path = p_storage_path, content_hash = p_sha256, final_url = coalesce(p_final_url, final_url), read_at = now(),
           read_status = coalesce(nullif(p_rule_facts->>'read_status', ''), 'read'), next_read_at = now() + make_interval(days => security.pipeline_num_v1('reread.scholarship_ai_days', 90)::int), leased_until = null,
           facts = case when p_rule_facts ? 'facts' then p_rule_facts->'facts' else facts end
     where id = q.candidate_id;
  end if;
  if p_storage_path is not null then
    insert into pipeline.evidence_artifacts(source_id, evidence_type, source_url, storage_path, content_hash, mime_type, metadata, capture_version, evidence_group_key)
    values (security.coverage_sweep_source(q.provider_id), 'scholarship_ai_page', coalesce(p_final_url, q.url), p_storage_path, p_sha256, 'application/gzip',
            jsonb_build_object('queue_id', q.id, 'candidate_id', q.candidate_id, 'scholarship_id', q.scholarship_id, 'model', q.model_code, 'worker', 'coverage-sweep scholarship_ai'), 1, 'scholarship_ai:' || q.id)
    returning id into v_ev;
    if q.candidate_id is not null then update pipeline.scholarship_page_candidates set evidence_id = coalesce(evidence_id, v_ev) where id = q.candidate_id; end if;
  end if;
  insert into pipeline.scholarship_ai_extractions(queue_id, model_code, model_identifier, prompt_version, run_kind, job_id, sample_id, candidate_id, scholarship_id, provider_id, url,
         storage_path, content_hash, evidence_id, answer, checks, verdict, cost_usd, tokens_in, tokens_out, seconds, error)
  values (q.id, q.model_code, (select m.model_identifier from pipeline.scholarship_ai_models m where m.code = q.model_code), q.prompt_version, q.run_kind, q.job_id, q.sample_id, q.candidate_id, q.scholarship_id, q.provider_id,
          coalesce(p_final_url, q.url), coalesce(p_storage_path, (select c.storage_path from pipeline.scholarship_page_candidates c where c.id = q.candidate_id)), p_sha256,
          coalesce(v_ev, (select c.evidence_id from pipeline.scholarship_page_candidates c where c.id = q.candidate_id), (select sp.evidence_id from pipeline.scholarship_pages sp where sp.scholarship_id = q.scholarship_id)),
          p_answer, p_checks, p_verdict, p_cost, p_tokens_in, p_tokens_out, p_seconds, p_error)
  returning id into v_id;
  -- v2.15.250 (bugs 11/10-6 follow-up): an unsettled answer (failed reply, name not proven, or a stated fact not proven by its quote)
  -- goes to the next model in the chain, on the same stored copy; after the last model it goes to Layer 4 while AI admission is on
  v_why := case when q.run_kind in ('admit', 'reread') then security.scholarship_ai_unsettled_v1(p_answer, p_checks, p_verdict, p_error) end;
  -- v2.15.250 (23:50): an answer that would admit is confirmed by the next model while confirm_admissions is on
  if v_why is null and q.run_kind in ('admit', 'reread') and p_error is null and p_verdict = 'scholarship' and p_answer->>'audience' in ('international', 'both')
     and coalesce((p_checks->>'audience')::boolean, false) and coalesce(p_answer->>'offered', '') <> 'no'
     and coalesce((select s.confirm_admissions from pipeline.scholarship_ai_extract_settings s where s.id = 1), true)
     and security.scholarship_ai_next_model_v1(q.model_code) is not null then
    v_why := 'a second model confirms each admission';
  end if;
  v_next := case when v_why is not null then security.scholarship_ai_next_model_v1(q.model_code) end;
  if v_next is not null then
    update pipeline.scholarship_ai_queue set state = 'done', done_at = now(), leased_until = null, extraction_id = v_id where id = q.id;
    insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, sample_id, candidate_id, scholarship_id, provider_id, url, step, storage_path, root_id)
    values (v_next, q.prompt_version, q.run_kind, q.job_id, q.sample_id, q.candidate_id, q.scholarship_id, q.provider_id, coalesce(p_final_url, q.url), q.step + 1,
            coalesce(p_storage_path, q.storage_path), coalesce(q.root_id, q.id));
    return jsonb_build_object('ok', true, 'extraction', v_id, 'escalated_to', v_next, 'why', v_why);
  end if;
  update pipeline.scholarship_ai_queue set state = case when p_error is null or attempts >= 3 then 'done' else 'queued' end, done_at = case when p_error is null or attempts >= 3 then now() end,
         leased_until = null, next_try_at = now() + interval '10 minutes', extraction_id = v_id where id = q.id;
  select ai_admission into v_on from pipeline.scholarship_ai_extract_settings where id = 1;
  if v_on and v_why is not null and (p_error is null or q.attempts >= 3) then r := security.scholarship_ai_review_open_v1(v_id, v_why);
  elsif p_error is null and v_on and q.run_kind in ('admit', 'reread') then r := security.scholarship_ai_apply_v1(v_id); end if;
  return jsonb_build_object('ok', true, 'extraction', v_id, 'applied', r);
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  -- v2.15.248 (Platform Admin bugs 11/10-5, Fix 3): pages that are never scholarships are skipped before they are read, by the address
  -- rules in Scholarships › Coverage › Settings and jobs (never an address that mentions a scholarship, bursary, stipend or grant)
  update pipeline.scholarship_page_candidates c set admit_status='skipped', admit_reasons=array['skipped: '||r.label], read_status=coalesce(c.read_status,'skipped'), read_at=now(), leased_until=null
    from pipeline.scholarship_skip_rules r
   where r.active and c.admit_status is null and c.matched_scholarship_id is null and c.source<>'register' and c.url ~* r.pattern and c.url !~* r.unless_pattern;
  with ranked as (
    select c.id, d.priority, row_number() over (partition by c.provider_id order by (c.url ~* 'international') desc, c.found_at, c.id) rn
      from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
     where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)
       -- v2.15.265: not for providers that do not qualify or are past their cap, nor pages on a directory site
       and not security.fc_sch_held_v1(c.provider_id, true) and not security.third_party_host_v1(c.url)
       and not security.provider_sch_search_off_v1(c.provider_id)),  -- v2.15.271: scholarship search Off
        -- v2.15.237: paused while the provider is unpublished or archived
  pick as (
    select c.id from pipeline.scholarship_page_candidates c join ranked r on r.id=c.id
     -- re-checked on the locked row, so concurrent readers never take the same page
     where coalesce(c.leased_until,'-infinity')<now() and c.admit_status is null and c.matched_scholarship_id is null and c.next_read_at<=now()
     order by (c.requested_at is not null) desc, security.fc_provider_tier_v1(c.provider_id), r.rn, (r.priority not in (0,3)), c.id -- 11 Oct 2026: on-demand candidates first
     limit greatest(1,least(coalesce(p_limit,30),60)) for update of c skip locked),
  upd as (update pipeline.scholarship_page_candidates c set leased_until=now()+interval '5 minutes', attempts=c.attempts+1 from pick where c.id=pick.id
          returning c.id, c.url, c.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('candidate_id',u.id,'url',u.url,'provider_id',u.provider_id,'currency',scholarship.provider_currency(u.provider_id),
           'site',(select coalesce(site_origin,website) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id),
           'hosts',(select to_jsonb(allowed_hosts) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id))),'[]'::jsonb)
    into v from upd u;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_discover_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select d.provider_id from pipeline.scholarship_discovery_providers d
     where d.status='pending' and coalesce(d.leased_until,'-infinity')<now() and d.attempts<3
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
       and not security.fc_sch_held_v1(d.provider_id, true) and not security.third_party_host_v1(coalesce(d.website, ''))
       and not security.provider_sch_search_off_v1(d.provider_id)  -- v2.15.271
        -- v2.15.265
     order by security.fc_provider_tier_v1(d.provider_id), d.priority, d.provider_id limit greatest(1,least(coalesce(p_limit,3),6)) for update skip locked),
  upd as (update pipeline.scholarship_discovery_providers d set leased_until=now()+interval '5 minutes', attempts=d.attempts+1, updated_at=now()
            from pick where d.provider_id=pick.provider_id returning d.provider_id, d.website, d.reason, d.allowed_hosts)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'website',u.website,'reason',u.reason,'hosts',to_jsonb(u.allowed_hosts),
           'names',security.provider_name_list(u.provider_id),'held',security.scholarship_held_without_page(u.provider_id))),'[]'::jsonb) into v from upd u;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.scholarship_discovery_refill_v1(p_keep integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_pending int; v_added int := 0;
begin
  perform security.provider_sch_search_auto_v1();  -- v2.15.271: directory-only providers switched Off
  select count(*) into v_pending from pipeline.scholarship_discovery_providers where status = 'pending';
  if v_pending < p_keep then
    insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status)
    select q.provider_id, q.website, case when q.cc = 'AU' then 4 else 1 end, case when q.cc = 'AU' then 'largest_unsearched' else 'university_' || lower(q.cc) end, 'pending'
      from (select p.id provider_id, k.iso_alpha2 cc,
                   coalesce(nullif(btrim(p.website), ''), (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p.id and d.status = 'mapped')) website,
                   count(*) n
              from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
             where co.lifecycle_status = 'active' and k.scholarship_ingestion_enabled
               and (k.iso_alpha2 = 'AU' or security.scholarship_university(p.id))
               and not exists (select 1 from pipeline.scholarship_discovery_providers d where d.provider_id = p.id)
             group by p.id, p.website, k.iso_alpha2) q
     where q.website is not null
       -- v2.15.265: qualifying providers only, never a directory site; top-50, Australian 30+, overseas
       and security.fc_sch_eligible_v1(q.provider_id) and not security.third_party_host_v1(q.website)
       and not security.provider_sch_search_off_v1(q.provider_id)  -- v2.15.271
     order by security.fc_provider_tier_v1(q.provider_id), q.n desc, q.provider_id limit greatest(0, p_keep - v_pending)
    on conflict do nothing;
    get diagnostics v_added = row_count;
  end if;
  return jsonb_build_object('pending_before', v_pending, 'added', v_added);
end $function$;

CREATE OR REPLACE FUNCTION security.admin_course_page_fast_base(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'scholarship', 'search', 'public', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'course'));
  v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end;
  v_provider_id uuid:=nullif(p_args->>'provider_id','')::uuid;
  v_has_fee boolean:=case when nullif(p_args->>'has_fee','') is null then null else (p_args->>'has_fee')::boolean end;
  v_has_intake boolean:=case when nullif(p_args->>'has_intake','') is null then null else (p_args->>'has_intake')::boolean end;
  v_has_english boolean:=case when nullif(p_args->>'has_english','') is null then null else (p_args->>'has_english')::boolean end;
  v_has_scholarship boolean:=case when nullif(p_args->>'has_scholarship','') is null then null else (p_args->>'has_scholarship')::boolean end;
  v_has_state boolean:=case when nullif(p_args->>'has_state','') is null then null else (p_args->>'has_state')::boolean end;
  v_has_link boolean:=case when nullif(p_args->>'has_link','') is null then null else (p_args->>'has_link')::boolean end;
  v_min_completeness numeric:=nullif(p_args->>'min_completeness','')::numeric;
  v_group text:=nullif(trim(coalesce(p_args->>'university_group','')),'');
  v_result jsonb;
  v_sub_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  if nullif(trim(coalesce(p_args->>'subdivision_code','')),'') is not null then
    select sd.id into v_sub_id from ref.subdivisions sd where sd.code=upper(trim(p_args->>'subdivision_code'));
  end if;

  -- Fee/readiness ordering is still intentionally not promoted by the v2.10 UI.
  -- Preserve the accepted legacy implementation only for explicit direct callers of
  -- those derived sorts. All normal derived filters remain in the bounded fast path.
  if v_sort in ('fee','completeness') then
    return security.admin_course_page_search_state(public.ui_courses_decision_page(
      v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'subdivision_code',''),v_provider_id,
      nullif(p_args->>'level_code',''),nullif(p_args->>'field_code',''),nullif(p_args->>'delivery_mode',''),nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),
      v_has_fee,v_has_intake,v_has_english,v_has_scholarship,v_min_completeness,nullif(p_args->>'freshness',''),
      v_sort,v_dir,v_has_state,v_has_link,v_group
    ));
  end if;

  with base as (
    select
      c.id,c.stable_key,c.canonical_title,c.display_title,c.course_code,c.course_url,
      c.lifecycle_status,c.publication_status,c.last_verified_at,c.created_at,c.updated_at,c.provider_id,
      c.duration_value,c.description,c.delivery_mode canonical_delivery_mode,c.open_to_international,c.open_to_domestic,
      coalesce(p.display_name,p.canonical_name) provider_name,
      co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
      sl.code level_code,sl.name level_name,fos.code field_code,fos.name field_of_study
    from catalogue.courses c
    join catalogue.providers p on p.id=c.provider_id
    join ref.countries co on co.id=p.country_id
    left join ref.study_levels sl on sl.id=c.study_level_id
    left join ref.fields_of_study fos on fos.id=c.primary_field_id
    where (nullif(trim(coalesce(p_args->>'query','')),'') is null
      or c.canonical_title ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(c.display_title,'') ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(c.course_code,'') ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(c.stable_key,'') ilike '%'||trim(p_args->>'query')||'%'
      or exists(select 1 from catalogue.course_identifiers ci where ci.course_id=c.id and ci.scheme='studysearch' and upper(ci.identifier) like upper(trim(p_args->>'query'))||'%'))
      and (nullif(trim(coalesce(p_args->>'country_code','')),'') is null or co.iso_alpha2::text=upper(trim(p_args->>'country_code')))
      and (v_provider_id is null or c.provider_id=v_provider_id)
      and (v_group is null or c.provider_id in (select security.university_group_provider_ids(v_group)))
      and (nullif(trim(coalesce(p_args->>'level_code','')),'') is null or sl.code=trim(p_args->>'level_code'))
      and (nullif(trim(coalesce(p_args->>'field_code','')),'') is null or fos.code=trim(p_args->>'field_code'))
      and (nullif(trim(coalesce(p_args->>'lifecycle_status','')),'') is null or c.lifecycle_status=trim(p_args->>'lifecycle_status'))
      and (nullif(trim(coalesce(p_args->>'publication_status','')),'') is null or c.publication_status=trim(p_args->>'publication_status'))
      and (nullif(trim(coalesce(p_args->>'subdivision_code','')),'') is null or exists(
        select 1 from catalogue.course_campuses cc
        join catalogue.campuses ca on ca.id=cc.campus_id
        join ref.subdivisions sd on sd.id=ca.subdivision_id
        where cc.course_id=c.id and sd.code=upper(trim(p_args->>'subdivision_code')))
        or (p.subdivision_id=v_sub_id and not exists(
          select 1 from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id
          where cc.course_id=c.id and ca.subdivision_id is not null)))
      and (nullif(trim(coalesce(p_args->>'delivery_mode','')),'') is null
        or nullif(btrim(c.delivery_mode),'')=trim(p_args->>'delivery_mode')
        or (nullif(btrim(c.delivery_mode),'') is null
            and exists(select 1 from catalogue.course_campuses cc where cc.course_id=c.id and cc.delivery_mode=trim(p_args->>'delivery_mode'))))
      and (nullif(trim(coalesce(p_args->>'freshness','')),'') is null
        or (p_args->>'freshness'='never_verified' and c.last_verified_at is null)
        or (p_args->>'freshness'='modified_7d' and c.updated_at>=now()-interval '7 days')
        or (p_args->>'freshness'='modified_30d' and c.updated_at>=now()-interval '30 days')
        or (p_args->>'freshness'='stale_180d' and (c.last_verified_at is null or c.last_verified_at<now()-interval '180 days')))
      and (v_has_fee is null or exists(
        select 1 from catalogue.course_fees cf
        where cf.course_id=c.id and coalesce(cf.status,'active')='active')=v_has_fee)
      and (v_has_intake is null or exists(
        select 1 from catalogue.course_intakes ci
        where ci.course_id=c.id and coalesce(ci.status,'active')='active')=v_has_intake)
      and (v_has_english is null or exists(
        select 1 from catalogue.course_english_requirements er
        where er.course_id=c.id and coalesce(er.status,'active')='active')=v_has_english)
      and (v_has_scholarship is null or exists(
        select 1 from scholarship.scopes ss
        where coalesce(ss.include_exclude,'include')='include'
          and (ss.course_id=c.id or (ss.scope_type='provider' and ss.provider_id=c.provider_id)))=v_has_scholarship)
      and (v_has_state is null or (p.subdivision_id is not null or exists(
        select 1 from catalogue.course_campuses cc
        join catalogue.campuses ca on ca.id=cc.campus_id
        where cc.course_id=c.id and ca.subdivision_id is not null))=v_has_state)
      and (v_has_link is null or exists(
        select 1 from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=c.id and l.status='active')=v_has_link)
      and (nullif(p_args->>'applicant','') is null
        or (p_args->>'applicant'='international' and c.open_to_international is true)
        or (p_args->>'applicant'='domestic_only' and c.open_to_international is false)
        or (p_args->>'applicant'='both' and c.open_to_international is true and c.open_to_domestic is true)
        or (p_args->>'applicant'='unknown' and c.open_to_international is null))
      and (v_min_completeness is null or (
        (exists(select 1 from catalogue.course_registrations r where r.course_id=c.id))::int
        +(c.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=c.id))::int
        +(exists(select 1 from catalogue.course_fees cf where cf.course_id=c.id and coalesce(cf.status,'active')='active'))::int
        +(exists(select 1 from catalogue.course_intakes ci where ci.course_id=c.id and coalesce(ci.status,'active')='active'))::int
        +(exists(select 1 from catalogue.course_english_requirements er where er.course_id=c.id and coalesce(er.status,'active')='active'))::int
        +(c.description is not null and length(trim(c.description))>0)::int
      )*100.0/6.0 >= v_min_completeness)
  ), numbered as (
    select *,count(*) over() total_count from base
  ), paged as (
    select * from numbered order by
      case when v_sort='course' and v_dir='asc' then lower(canonical_title) end asc,
      case when v_sort='course' and v_dir='desc' then lower(canonical_title) end desc,
      case when v_sort='provider' and v_dir='asc' then lower(provider_name) end asc,
      case when v_sort='provider' and v_dir='desc' then lower(provider_name) end desc,
      case when v_sort='field' and v_dir='asc' then lower(coalesce(field_of_study,'')) end asc,
      case when v_sort='field' and v_dir='desc' then lower(coalesce(field_of_study,'')) end desc,
      case when v_sort='modified' and v_dir='asc' then updated_at end asc,
      case when v_sort='modified' and v_dir='desc' then updated_at end desc,
      case when v_sort='verified' and v_dir='asc' then last_verified_at end asc nulls first,
      case when v_sort='verified' and v_dir='desc' then last_verified_at end desc nulls last,
      lower(canonical_title),id
    limit v_limit offset v_offset
  ), enriched as (
    select
      pg.id,pg.stable_key,pg.canonical_title,pg.display_title,pg.course_code,pg.course_url,
      pg.lifecycle_status,pg.publication_status,pg.last_verified_at,pg.created_at,pg.updated_at,pg.provider_id,
      pg.open_to_international,pg.open_to_domestic,coalesce(ssc.identifier,pg.course_code) display_code,case when ssc.identifier is not null then 'studysearch' else 'own' end code_kind,
      pg.provider_name,pg.country_code,pg.country_name,pg.currency_code,pg.level_code,pg.level_name,pg.field_code,pg.field_of_study,
      coalesce(nullif(btrim(pg.canonical_delivery_mode),''),case when dm.mode_count=1 then dm.single_mode when dm.mode_count>1 then dm.mode_count::text||' modes' end) delivery_mode,
      fee.amount fee_amount,fee.currency_code::text fee_currency,
      sig.has_registration,sig.has_structure,sig.has_fee,sig.has_intake,sig.has_english,sig.has_description,
      round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score_v2,
      round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score,
      sch.has_scholarship,lnk.has_link,(coalesce(geo.region_count,0)>0 or psd.id is not null) has_state,
      coalesce(geo.campus_count,0) campus_count,
      case when geo.region_count=1 then geo.single_code when coalesce(geo.region_count,0)=0 then psd.code else null end subdivision_code,
      case when geo.region_count=1 then geo.single_name when geo.region_count>1 then geo.region_count::text||' regions' else psd.name end subdivision_name,
      case when coalesce(geo.region_count,0)>0 then geo.region_count when psd.id is not null then 1 else 0 end region_count,
      case when coalesce(geo.region_count,0)>0 then 'campus' when psd.id is not null then 'provider' else null end region_source,
      (d.course_id is not null) search_projected,d.publication_status search_projection_status,d.completeness_score search_projection_completeness,
      d.projection_version search_projection_version,d.catalogue_generation search_catalogue_generation,d.updated_at search_projection_updated_at,
      d.generated_at search_projection_generated_at,d.has_fee search_has_fee,d.has_intake search_has_intake,d.has_english search_has_english,d.has_scholarship search_has_scholarship,
      security.provider_university_groups(pg.provider_id) university_groups,
      pg.total_count
    from paged pg
    left join search.course_documents d on d.course_id=pg.id
    left join lateral (
      select cf.amount,cf.currency_code from catalogue.course_fees cf
      where cf.course_id=pg.id and cf.fee_type='tuition' and cf.basis='registered_total_course' and coalesce(cf.status,'active')='active'
      order by cf.source_snapshot_at desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc limit 1
    ) fee on true
    cross join lateral (
      select
        exists(select 1 from catalogue.course_registrations r where r.course_id=pg.id) has_registration,
        (pg.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=pg.id)) has_structure,
        exists(select 1 from catalogue.course_fees cf where cf.course_id=pg.id and coalesce(cf.status,'active')='active') has_fee,
        exists(select 1 from catalogue.course_intakes ci where ci.course_id=pg.id and coalesce(ci.status,'active')='active') has_intake,
        exists(select 1 from catalogue.course_english_requirements er where er.course_id=pg.id and coalesce(er.status,'active')='active') has_english,
        (pg.description is not null and length(trim(pg.description))>0) has_description
    ) sig
    cross join lateral (select exists(select 1 from scholarship.scopes ss where coalesce(ss.include_exclude,'include')='include' and (ss.course_id=pg.id or (ss.scope_type='provider' and ss.provider_id=pg.provider_id))) has_scholarship) sch
    cross join lateral (select exists(select 1 from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=pg.id and l.status='active') has_link) lnk
    left join lateral (
      select count(distinct cc.campus_id)::int campus_count,count(distinct sd.id)::int region_count,min(sd.code) single_code,min(sd.name) single_name
      from catalogue.course_campuses cc join catalogue.campuses ca on ca.id=cc.campus_id left join ref.subdivisions sd on sd.id=ca.subdivision_id where cc.course_id=pg.id
    ) geo on true
    left join ref.subdivisions psd on psd.id=(select p2.subdivision_id from catalogue.providers p2 where p2.id=pg.provider_id)
    left join lateral (select i.identifier from catalogue.course_identifiers i where i.course_id=pg.id and i.scheme='studysearch' limit 1) ssc on true
    left join lateral (
      select count(distinct cc.delivery_mode)::int mode_count,min(cc.delivery_mode) single_mode
      from catalogue.course_campuses cc where cc.course_id=pg.id and cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
    ) dm on true
  )
  select jsonb_build_object(
    'items',coalesce(jsonb_agg(to_jsonb(e)-'total_count'),'[]'::jsonb),
    'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir,
    'execution_profile','paged_enrichment_v3'
  ) into v_result from enriched e;
  return v_result;
end
$function$;

CREATE OR REPLACE FUNCTION security.admin_course_page_unfiltered_fast(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'scholarship', 'search', 'public', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_total bigint:=0;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  select count(*) into v_total from catalogue.courses;

  with paged as (
    select
      c.id,c.stable_key,c.canonical_title,c.display_title,c.course_code,c.course_url,
      c.lifecycle_status,c.publication_status,c.last_verified_at,c.created_at,c.updated_at,c.provider_id,
      c.duration_value,c.description,c.delivery_mode canonical_delivery_mode,
      coalesce(p.display_name,p.canonical_name) provider_name,
      co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
      sl.code level_code,sl.name level_name,fos.code field_code,fos.name field_of_study
    from catalogue.courses c
    join catalogue.providers p on p.id=c.provider_id
    join ref.countries co on co.id=p.country_id
    left join ref.study_levels sl on sl.id=c.study_level_id
    left join ref.fields_of_study fos on fos.id=c.primary_field_id
    order by lower(c.canonical_title),c.id
    limit v_limit offset v_offset
  ), enriched as (
    select
      pg.id,pg.stable_key,pg.canonical_title,pg.display_title,pg.course_code,pg.course_url,
      pg.lifecycle_status,pg.publication_status,pg.last_verified_at,pg.created_at,pg.updated_at,pg.provider_id,
      coalesce(ssc.identifier,pg.course_code) display_code,case when ssc.identifier is not null then 'studysearch' else 'own' end code_kind,
      pg.provider_name,pg.country_code,pg.country_name,pg.currency_code,pg.level_code,pg.level_name,pg.field_code,pg.field_of_study,
      coalesce(nullif(btrim(pg.canonical_delivery_mode),''),case when dm.mode_count=1 then dm.single_mode when dm.mode_count>1 then dm.mode_count::text||' modes' end) delivery_mode,
      fee.amount fee_amount,fee.currency_code::text fee_currency,
      sig.has_registration,sig.has_structure,sig.has_fee,sig.has_intake,sig.has_english,sig.has_description,
      round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score_v2,
      round(((sig.has_registration::int+sig.has_structure::int+sig.has_fee::int+sig.has_intake::int+sig.has_english::int+sig.has_description::int)*100.0/6.0)::numeric,2) completeness_score,
      sch.has_scholarship,lnk.has_link,(coalesce(geo.region_count,0)>0 or psd.id is not null) has_state,
      coalesce(geo.campus_count,0) campus_count,
      case when geo.region_count=1 then geo.single_code when coalesce(geo.region_count,0)=0 then psd.code else null end subdivision_code,
      case when geo.region_count=1 then geo.single_name when geo.region_count>1 then geo.region_count::text||' regions' else psd.name end subdivision_name,
      case when coalesce(geo.region_count,0)>0 then geo.region_count when psd.id is not null then 1 else 0 end region_count,
      case when coalesce(geo.region_count,0)>0 then 'campus' when psd.id is not null then 'provider' else null end region_source,
      (d.course_id is not null) search_projected,d.publication_status search_projection_status,d.completeness_score search_projection_completeness,
      d.projection_version search_projection_version,d.catalogue_generation search_catalogue_generation,d.updated_at search_projection_updated_at,
      d.generated_at search_projection_generated_at,d.has_fee search_has_fee,d.has_intake search_has_intake,d.has_english search_has_english,d.has_scholarship search_has_scholarship,
      security.provider_university_groups(pg.provider_id) university_groups
    from paged pg
    left join search.course_documents d on d.course_id=pg.id
    left join lateral (
      select cf.amount,cf.currency_code
      from catalogue.course_fees cf
      where cf.course_id=pg.id
        and cf.fee_type='tuition'
        and cf.basis='registered_total_course'
        and coalesce(cf.status,'active')='active'
      order by cf.source_snapshot_at desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc
      limit 1
    ) fee on true
    cross join lateral (
      select
        exists(select 1 from catalogue.course_registrations r where r.course_id=pg.id) has_registration,
        (pg.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=pg.id)) has_structure,
        exists(select 1 from catalogue.course_fees cf where cf.course_id=pg.id and coalesce(cf.status,'active')='active') has_fee,
        exists(select 1 from catalogue.course_intakes ci where ci.course_id=pg.id and coalesce(ci.status,'active')='active') has_intake,
        exists(select 1 from catalogue.course_english_requirements er where er.course_id=pg.id and coalesce(er.status,'active')='active') has_english,
        (pg.description is not null and length(trim(pg.description))>0) has_description
    ) sig
    cross join lateral (
      select exists(
        select 1 from scholarship.scopes ss
        where coalesce(ss.include_exclude,'include')='include'
          and (ss.course_id=pg.id or (ss.scope_type='provider' and ss.provider_id=pg.provider_id))
      ) has_scholarship
    ) sch
    cross join lateral (
      select exists(select 1 from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=pg.id and l.status='active') has_link
    ) lnk
    left join lateral (
      select count(distinct cc.campus_id)::int campus_count,
             count(distinct sd.id)::int region_count,
             min(sd.code) single_code,min(sd.name) single_name
      from catalogue.course_campuses cc
      join catalogue.campuses ca on ca.id=cc.campus_id
      left join ref.subdivisions sd on sd.id=ca.subdivision_id
      where cc.course_id=pg.id
    ) geo on true
    left join ref.subdivisions psd on psd.id=(select p2.subdivision_id from catalogue.providers p2 where p2.id=pg.provider_id)
    left join lateral (select i.identifier from catalogue.course_identifiers i where i.course_id=pg.id and i.scheme='studysearch' limit 1) ssc on true
    left join lateral (
      select count(distinct cc.delivery_mode)::int mode_count,min(cc.delivery_mode) single_mode
      from catalogue.course_campuses cc
      where cc.course_id=pg.id and cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
    ) dm on true
  )
  select jsonb_build_object(
    'items',coalesce(jsonb_agg(to_jsonb(e)),'[]'::jsonb),
    'total',v_total,'limit',v_limit,'offset',v_offset,
    'sort','course','direction','asc',
    'execution_profile','page_first_unfiltered_v1'
  ) into v_result
  from enriched e;

  return v_result;
end $function$;

CREATE OR REPLACE FUNCTION public.admin_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'security'
AS $function$
declare v_result jsonb;v_id uuid;
begin
 if p_operation='platform_health' then return security.admin_platform_health_v1(p_args); end if;
 if p_operation='live_activity' then return security.admin_live_activity_v1(); end if;
 if p_operation in ('course_coverage','course_coverage_courses','course_coverage_providers') then return security.admin_course_coverage_read(p_operation,p_args); end if;
 if p_operation='scholarship_ai' then return security.scholarship_ai_control_read_impl(coalesce(nullif(p_args->>'country_code',''),'AU')); end if;
 if p_operation='layer3_queue_status' then return security.layer3_queue_status_read_v1(); end if;
 if p_operation='admin_filter_option_page' then return security.admin_filter_option_page(p_args); end if;
 if p_operation='dashboard' then return security.admin_dashboard_maturity(); end if;
 if p_operation='layer_status_summary' then return security.admin_layer_status_summary(); end if;
 if p_operation='catalogue_filter_page' then return security.admin_catalogue_filter_page(p_args); end if;
 if p_operation in ('provider_filters','course_filters') then return security.admin_catalogue_filter_options(p_operation,p_args); end if;
 if p_operation='evidence_page' then return security.admin_evidence_page(p_args); end if;
 if p_operation in ('evidence_filters','evidence_detail','evidence_observations','evidence_entities') then return security.admin_evidence_read(p_operation,p_args); end if;
 if p_operation='courses_page' then return security.admin_course_page_fast(p_args); end if;
 if p_operation='campuses_page' then return security.admin_campus_page_fast(p_args); end if;
 if p_operation in ('providers_page','scholarships_page') then return security.admin_catalogue_page(p_operation,p_args); end if;
 if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then return security.admin_insights_read(p_operation,p_args); end if;
 if p_operation='ranking_imports' then return security.admin_ranking_imports_read(p_args); end if;
 if p_operation in ('ranking_summary','ranking_filters','ranking_observations') then return security.admin_ranking_read(p_operation,p_args); end if;
 if p_operation in ('ranking_filter_options','ranking_link_candidates','ranking_provider_search','provider_ranking_history') then return security.admin_ranking_links_read(p_operation,p_args); end if;
 if p_operation in ('provider_asset_summary','provider_asset_coverage','provider_asset_context') then return security.admin_provider_asset_read(p_operation,p_args); end if;
 if p_operation in ('provider_contacts_page','provider_contact_detail','provider_contact_imports','provider_contact_import_detail') then return security.admin_provider_contact_read(p_operation,p_args); end if;
 if p_operation='contextual_compare' then return security.admin_contextual_compare(p_args); end if;
 if p_operation='reviews_page' then return security.admin_operational_page(p_operation,p_args); end if;
 if p_operation='layer2_dispatcher_tuning' then return security.admin_layer2_dispatcher_tuning_read_v1(p_args); end if;
 if p_operation='enrichment_operations' then return security.admin_enrichment_operations_read(p_args); end if;
 if p_operation='jobs_runtime' then return security.admin_jobs_runtime_read_v1(p_args); end if;
 if p_operation in ('reviews','jobs','sources') then return security.admin_operations_read(p_operation,p_args); end if;
 if p_operation='layer1_operations' then return security.admin_layer1_operations_read(p_args); end if;
 if p_operation='layer2_ops_alerts' then return security.layer2_operational_alerts_read(); end if;
 if p_operation='layer2_parent_runs' then return security.admin_layer2_parent_runs(coalesce(nullif(p_args->>'limit','')::integer,10)); end if;
 if p_operation='layer2_ops_overview' then return security.admin_layer2_ops_read('layer2_ops_overview',p_args); end if;
 if p_operation='layer2_ops_run_detail' then return security.admin_layer2_ops_read(p_operation,p_args); end if;
 if p_operation in ('layer2_acquisition_providers','layer2_provider_attempts') then return security.admin_layer2_provider_read(p_operation,p_args); end if;
 if p_operation='attributes' then return security.admin_pim_governance_read(p_args); end if;
 if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then v_result:=security.admin_pipeline_ops_read(p_operation,p_args);return security.admin_pipeline_ops_sanitise_result(p_operation,v_result);end if;
 if p_operation in ('data_quality_overview','data_quality_exceptions','data_quality_quarantine') then return security.admin_data_quality_read(p_operation,p_args); end if;
 if p_operation in ('platform_readiness','platform_capacity','platform_environment_gates','platform_uat_catalogue','platform_workloads','platform_retention','platform_active_blocks') then return security.admin_platform_maturity_read(p_operation,p_args); end if;
 if p_operation='publication_overview' then return security.admin_publication_overview(); end if;
 if p_operation='provider_insights' then v_id:=nullif(p_args->>'id','')::uuid;return jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('provider',v_id));end if;
 if p_operation='provider_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_provider_detail(v_id)-'courses'-'courses_page'-'evidence'-'evidence_page'-'sources'-'history';end if;
 if p_operation='campus_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_campus_detail(v_id);end if;
 if p_operation='course_insights' then v_id:=nullif(p_args->>'id','')::uuid;return jsonb_build_object('contextual_insights',security.admin_contextual_insights_v2('course',v_id));end if;
 v_result:=security.admin_read_impl(p_operation,p_args);
 if p_operation='course_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))||jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))||jsonb_build_object('display_code',security.course_display_code_v1(v_id));end if;
 if p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));end if;
 return v_result;
end $function$;

-- Once now: codes for every course without a printed code; providers whose only website is a directory site switched Off;
-- discovery for providers that have their own website re-pointed to it; queued reads of directory pages closed
select security.studysearch_code_assign_v1(security.pipeline_num_v1('batch.studysearch_codes', 2000)::int * 10);
select security.provider_sch_search_auto_v1();
update pipeline.scholarship_discovery_providers d
   set website = security.provider_own_site_v1(d.provider_id), site_origin = null, status = 'pending', attempts = 0, leased_until = null,
       last_error = null, reason = 'own_website_found', updated_at = now()
 where security.third_party_host_v1(coalesce(d.website, '')) and security.provider_own_site_v1(d.provider_id) is not null;
update pipeline.scholarship_ai_queue q
   set state = 'failed', done_at = now(), leased_until = null, skip_reason = 'directory site'
 where q.state in ('queued', 'leased') and security.third_party_host_v1(q.url);

do $post$
declare v_expected jsonb := '{"public.svc_scholarship_ai_next(integer)": "3f1c5858629531c66f2537961cebb129", "public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)": "aa337a9fb30a75452a7b54bddbf8d00f", "public.svc_scholarship_candidate_next(integer)": "05a40ab97bec72d3b3ff2aa2c7dddf41", "public.svc_scholarship_discover_next(integer)": "139bc97b784ac031db99d13b656f7c84", "security.scholarship_discovery_refill_v1(integer)": "49e9272a0e688ad1290a54bbdbe69eb5", "security.admin_course_page_fast_base(jsonb)": "9ddef257dbd6b515e1cf586354517fb3", "security.admin_course_page_unfiltered_fast(jsonb)": "3b7ea35f749554d044ffaefc0c2054cd", "public.admin_read(text,jsonb)": "f7f3ebded941a60b391fa8b7c8e91805"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.271 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $chk$
declare v_left int;
begin
  select count(*) into v_left from catalogue.courses c
   where not exists (select 1 from catalogue.course_identifiers i where i.course_id = c.id and i.scheme = 'studysearch')
     and not (nullif(btrim(c.course_code), '') is not null
              and (not exists (select 1 from catalogue.course_identifiers i where i.course_id = c.id)
                   or exists (select 1 from catalogue.course_identifiers i join ref.course_code_schemes s on s.scheme = i.scheme and s.printed where i.course_id = c.id)));
  if v_left > 0 then raise notice 'v2.15.271: % course(s) still without a code; the hourly job gives them one', v_left; end if;
  if exists (select 1 from pipeline.scholarship_ai_queue where state in ('queued', 'leased') and security.third_party_host_v1(url)) then
    raise exception 'v2.15.271 post-check: queued reads of directory pages remain';
  end if;
end $chk$;
