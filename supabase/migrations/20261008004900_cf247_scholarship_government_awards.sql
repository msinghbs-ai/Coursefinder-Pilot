-- CF-247 Scholarships: government awards from a record register reach courses through approved institutions.
-- Platform Admin decisions 9 Oct 2026 (multiple choice): "Publish the government records" and
-- "Link to approved institutions": Manaaki links to its named institutions (matched by official website,
-- following redirects); Australia Awards waits for a person to pick participating institutions.
--
-- 1. Nationality terms: 11 countries the government registers list that the terms did not cover, and the
--    register spellings for two that were covered (Federated States of Micronesia, Naoero for Nauru).
-- 2. scholarship.registers.provider_ids: institutions a Platform Admin picked (Australia Awards).
-- 3. security.scholarship_from_record_register(id): true for a scholarship read from a record register.
-- 4. public.svc_scholarship_register_record_profile(register): after each register read, sets the record's
--    nationalities from the register's country lists (stops if a country is not recognised), audience
--    international, and links courses at the approved institutions (bachelor, master's, doctorate, and
--    diplomas/certificates titled postgraduate) as course scopes and course links. Insert only.
-- 5. public.admin_scholarship_register_institutions(register, provider_ids, reason): Platform Admin picks
--    institutions for a register; logged; then the profile runs.
-- 6. The audience and nationality wording jobs no longer overwrite a register record (md5-guarded patch).
-- 7. Publishing rules: for a register record, a stated full tuition coverage counts as a stated value, and the
--    two provider-page wording checks do not apply (the page is a government page) (md5-guarded patch).
-- Nothing is published by this migration.

insert into ref.nationality_terms(code, names, demonyms, region) values
 ('AO','Angola','Angolan',false),
 ('CI','Côte d''Ivoire|Cote d''Ivoire|Ivory Coast','Ivorian',false),
 ('CD','Democratic Republic of the Congo|DR Congo|DRC','Congolese',false),
 ('PF','French Polynesia','French Polynesian',false),
 ('GN','(?<!New )(?<!Equatorial )(?<!Papua New )Guinea(?!-Bissau)','Guinean',false),
 ('MG','Madagascar','Malagasy',false),
 ('NA','Namibia','Namibian',false),
 ('NC','New Caledonia','New Caledonian',false),
 ('SL','Sierra Leone','Sierra Leonean',false),
 ('GM','The Gambia|Gambia','Gambian',false),
 ('WF','Wallis and Futuna','Wallisian|Futunan',false)
on conflict do nothing;
update ref.nationality_terms set names = 'Federated States of Micronesia|Micronesia' where code = 'FM' and names = 'Micronesia';
update ref.nationality_terms set names = 'Nauru|Naoero' where code = 'NR' and names = 'Nauru';

alter table scholarship.registers add column if not exists provider_ids uuid[] not null default '{}';
alter table scholarship.registers add column if not exists profile jsonb;

create or replace function security.scholarship_from_record_register(p_scholarship_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from scholarship.scholarships s join scholarship.registers r on r.source_id = s.source_id and r.role = 'record'
                  where s.id = p_scholarship_id)
$$;
revoke all on function security.scholarship_from_record_register(uuid) from public, anon, authenticated;

create or replace function public.svc_scholarship_register_record_profile(p_register text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r scholarship.registers; v_sid uuid; v_ev uuid; v_payload jsonb; v_names text[]; v_codes text[]; v_unmapped text[];
        v_inst jsonb; v_resolved jsonb := '[]'; v_unresolved jsonb := '[]'; v_providers uuid[]; v_country uuid;
        v_scopes int := 0; v_maps int := 0; v_courses int := 0; i jsonb; v_pid uuid; v_n int; v_out jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into r from scholarship.registers where code = p_register and role = 'record';
  if r.code is null then raise exception 'not a record register: %', p_register; end if;
  select count(*) into v_n from scholarship.scholarships where source_id = r.source_id and lifecycle_status = 'active';
  if v_n <> 1 then raise exception 'register % has % active records; expected 1', p_register, v_n; end if;
  select id, evidence_id into v_sid, v_ev from scholarship.scholarships where source_id = r.source_id and lifecycle_status = 'active';
  select payload into v_payload from pipeline.scholarship_source_records
   where source_id = r.source_id and status = 'applied' order by observed_at desc nulls last, created_at desc limit 1;
  if v_payload is null then raise exception 'register % has no applied source record', p_register; end if;
  select id into v_country from ref.countries where iso_alpha2 = r.country_code;

  -- nationalities: every country the register lists (objects carry "country"; plain lists are text)
  select array_agg(distinct btrim(n)) into v_names from (
    select case when jsonb_typeof(c) = 'object' then c->>'country' else c #>> '{}' end n
      from jsonb_array_elements(v_payload->'cycles'->0->'criteria') cr, jsonb_array_elements(coalesce(cr->'value_json'->'countries','[]')) c
     where cr->>'criterion_type' = 'citizenship_and_residency'
    union all
    select cr->>'value_text' from jsonb_array_elements(v_payload->'cycles'->0->'criteria') cr
     where cr->>'criterion_type' = 'citizenship_and_residency' and cr->>'operator' = 'equals_source_country') q where coalesce(btrim(n),'') <> '';
  select array_agg(distinct x.code order by x.code) into v_codes
    from unnest(coalesce(v_names,'{}')) n join ref.nationality_terms x on not x.region and n ~* ('^(?:the )?(?:' || x.names || ')$');
  select array_agg(n order by n) into v_unmapped from unnest(coalesce(v_names,'{}')) n
   where not exists (select 1 from ref.nationality_terms x where not x.region and n ~* ('^(?:the )?(?:' || x.names || ')$'));
  if coalesce(cardinality(v_names),0) = 0 then raise exception 'register % lists no countries', p_register; end if;
  if coalesce(cardinality(v_unmapped),0) > 0 then raise exception 'register % lists countries without a nationality code: %', p_register, array_to_string(v_unmapped, ', '); end if;
  update scholarship.scholarships set nationalities = v_codes, audience = 'international', updated_at = now()
   where id = v_sid and (nationalities is distinct from v_codes or audience is distinct from 'international');
  insert into scholarship.nationality_readings(scholarship_id, codes, phrases, reader_version, read_at)
  values (v_sid, v_codes, jsonb_build_object('register', p_register, 'countries', to_jsonb(v_names)), 'register:' || p_register, now())
  on conflict (scholarship_id) do update set codes = excluded.codes, phrases = excluded.phrases, reader_version = excluded.reader_version, read_at = now();

  -- institutions named on the register (matched by official website or the site it redirects to), plus any a person picked
  select cr->'value_json' into v_inst from jsonb_array_elements(v_payload->'cycles'->0->'criteria') cr where cr->>'criterion_key' = 'approved_institution' limit 1;
  for i in select x from jsonb_array_elements(coalesce(v_inst->'universities','[]') || coalesce(v_inst->'institutes_of_technology','[]')) x loop
    select array_agg(distinct p.id) into v_providers from catalogue.providers p
     where p.country_id = v_country and p.lifecycle_status = 'active' and p.website is not null
       and security.url_base_host(p.website) in (security.url_base_host(i->>'website'), security.url_base_host(i->>'final_website'));
    if coalesce(cardinality(v_providers),0) = 1 then v_resolved := v_resolved || jsonb_build_object('name', i->>'name', 'provider_id', v_providers[1], 'basis', 'official website');
    else v_unresolved := v_unresolved || jsonb_build_object('name', i->>'name', 'website', i->>'website', 'final_website', i->>'final_website', 'matches', coalesce(cardinality(v_providers),0)); end if;
  end loop;
  select array_agg(distinct pid) into v_providers from (
    select (x->>'provider_id')::uuid pid from jsonb_array_elements(v_resolved) x union select unnest(r.provider_ids)) q;

  with eligible as (
    select c.id course_id from catalogue.courses c left join ref.study_levels sl on sl.id = c.study_level_id
     where c.provider_id = any(coalesce(v_providers,'{}')) and c.lifecycle_status = 'active'
       and (sl.code in ('bachelor','masters','doctorate') or (sl.code in ('diploma','certificate') and c.canonical_title ~* '\mpost ?graduate\M'))),
  sc as (
    insert into scholarship.scopes(scholarship_id, scope_type, course_id, include_exclude, source_id, evidence_id)
    select v_sid, 'course', e.course_id, 'include', r.source_id, v_ev from eligible e
     where not exists (select 1 from scholarship.scopes x where x.scholarship_id = v_sid and x.scope_type = 'course' and x.course_id = e.course_id)
    returning 1),
  mp as (
    insert into scholarship.course_mappings(scholarship_id, course_id, mapping_state, mapping_basis, evidence_id)
    select v_sid, e.course_id, 'mapped', 'explicit_course_scope', v_ev from eligible e
    on conflict (scholarship_id, course_id) do nothing
    returning 1)
  select (select count(*) from eligible), (select count(*) from sc), (select count(*) from mp) into v_courses, v_scopes, v_maps;

  v_out := jsonb_build_object('register', p_register, 'scholarship_id', v_sid, 'nationalities', to_jsonb(v_codes), 'countries', cardinality(v_names),
                              'institutions_resolved', v_resolved, 'institutions_unresolved', v_unresolved, 'picked_providers', to_jsonb(r.provider_ids),
                              'eligible_courses', v_courses, 'course_scopes_added', v_scopes, 'course_links_added', v_maps, 'at', now());
  update scholarship.registers set profile = v_out, updated_at = now() where code = p_register;
  return v_out;
end $$;
revoke all on function public.svc_scholarship_register_record_profile(text) from public, anon, authenticated;
grant execute on function public.svc_scholarship_register_record_profile(text) to service_role;

create or replace function public.admin_scholarship_register_institutions(p_register text, p_provider_ids uuid[], p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r scholarship.registers; v_bad int; v_out jsonb;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  select * into r from scholarship.registers where code = p_register and role = 'record';
  if r.code is null then raise exception 'not a record register: %', p_register; end if;
  select count(*) into v_bad from unnest(coalesce(p_provider_ids,'{}')) x
   where not exists (select 1 from catalogue.providers p join ref.countries c on c.id = p.country_id where p.id = x and c.iso_alpha2 = r.country_code and p.lifecycle_status = 'active');
  if v_bad > 0 then raise exception '% provider(s) are not active providers in %', v_bad, r.country_code; end if;
  update scholarship.registers set provider_ids = (select array_agg(distinct x) from unnest(r.provider_ids || coalesce(p_provider_ids,'{}')) x), updated_at = now()
   where code = p_register;
  v_out := public.svc_scholarship_register_record_profile(p_register);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('scholarships', 'register_institutions_set', p_register, jsonb_build_object('added', to_jsonb(p_provider_ids), 'reason', left(p_reason, 500), 'profile', v_out), auth.uid());
  return v_out;
end $$;
revoke all on function public.admin_scholarship_register_institutions(text, uuid[], text) from public, anon;
grant execute on function public.admin_scholarship_register_institutions(text, uuid[], text) to authenticated;

-- 6 and 7: patch the live wording jobs and the publishing rules, each only if it is exactly the version expected.
do $patch$
declare d text; n int;
begin
  d := pg_get_functiondef('security.scholarship_audience_read_v1'::regproc);
  if md5(d) <> 'c855a8ed523e39470529f1def62db833' then raise exception 'scholarship_audience_read_v1 changed; refusing to patch'; end if;
  n := (length(d) - length(replace(d, $a$s.audience is distinct from a.audience and not exists$a$, ''))) / length($a$s.audience is distinct from a.audience and not exists$a$);
  if n <> 1 then raise exception 'audience anchor found % times', n; end if;
  execute replace(d, $a$s.audience is distinct from a.audience and not exists$a$,
                     $a$s.audience is distinct from a.audience and not security.scholarship_from_record_register(s.id) and not exists$a$);

  d := pg_get_functiondef('security.scholarship_nationality_read_v1'::regproc);
  if md5(d) <> 'aa0d0f35d70d99a20ff7522bf4edb4aa' then raise exception 'scholarship_nationality_read_v1 changed; refusing to patch'; end if;
  n := (length(d) - length(replace(d, $a$s.nationalities is distinct from a.codes and not exists$a$, ''))) / length($a$s.nationalities is distinct from a.codes and not exists$a$);
  if n <> 1 then raise exception 'nationality anchor found % times', n; end if;
  execute replace(d, $a$s.nationalities is distinct from a.codes and not exists$a$,
                     $a$s.nationalities is distinct from a.codes and not security.scholarship_from_record_register(s.id) and not exists$a$);

  d := pg_get_functiondef('security.scholarship_publishability_v1'::regproc);
  if md5(d) <> '5fa8ee54af103bf126e96ccfcf416a5c' then raise exception 'scholarship_publishability_v1 changed; refusing to patch'; end if;
  if (length(d) - length(replace(d, $a$case when sp.facts is not null and coalesce(sp.facts->>'eligibility_excerpt','')$a$, ''))) / length($a$case when sp.facts is not null and coalesce(sp.facts->>'eligibility_excerpt','')$a$) <> 1
     or (length(d) - length(replace(d, $a$case when sp.facts is not null and sp.facts->>'international'='false' then$a$, ''))) / length($a$case when sp.facts is not null and sp.facts->>'international'='false' then$a$) <> 1
     or (length(d) - length(replace(d, $a$and t.tier_code like 'page_tier_%')) then 'no stated award value' end$a$, ''))) / length($a$and t.tier_code like 'page_tier_%')) then 'no stated award value' end$a$) <> 1
  then raise exception 'publishing rule anchors not found exactly once'; end if;
  d := replace(d, $a$case when sp.facts is not null and coalesce(sp.facts->>'eligibility_excerpt','')$a$,
                  $a$case when sp.facts is not null and not security.scholarship_from_record_register(s.id) and coalesce(sp.facts->>'eligibility_excerpt','')$a$);
  d := replace(d, $a$case when sp.facts is not null and sp.facts->>'international'='false' then$a$,
                  $a$case when sp.facts is not null and sp.facts->>'international'='false' and not security.scholarship_from_record_register(s.id) then$a$);
  d := replace(d, $a$and t.tier_code like 'page_tier_%')) then 'no stated award value' end$a$,
                  $a$and t.tier_code like 'page_tier_%') or (security.scholarship_from_record_register(s.id) and exists (select 1 from scholarship.coverage cv where cv.scholarship_id=s.id and cv.coverage_type='tuition_fees' and cv.percentage=100))) then 'no stated award value' end$a$);
  execute d;
end $patch$;
