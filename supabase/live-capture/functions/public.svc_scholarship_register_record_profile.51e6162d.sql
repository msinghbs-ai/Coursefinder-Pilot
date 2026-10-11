CREATE OR REPLACE FUNCTION public.svc_scholarship_register_record_profile(p_register text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$
