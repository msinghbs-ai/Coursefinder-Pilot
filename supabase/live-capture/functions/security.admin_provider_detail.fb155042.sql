CREATE OR REPLACE FUNCTION security.admin_provider_detail(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'public', 'catalogue', 'pipeline', 'ref', 'search', 'scholarship', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_base jsonb;
  v_courses jsonb;
  v_evidence jsonb;
  v_campuses jsonb;
  v_contacts jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  v_base:=public.ui_provider_detail(p_provider_id);
  if v_base is null then return '{}'::jsonb; end if;
  v_courses:=public.ui_provider_related_courses(p_provider_id,25,0,null,null,null);
  v_evidence:=public.ui_provider_related_evidence(p_provider_id,25,0,null,null);
  v_contacts:=security.admin_provider_contacts(p_provider_id);

  with base as (
    select ca.id,ca.stable_key,ca.name,ca.campus_code,ca.city,ca.postcode,ca.status,ca.publication_status,
           sd.code subdivision_code,sd.name subdivision_name,
           (select count(*)::int from catalogue.course_campuses cc where cc.campus_id=ca.id) course_count
    from catalogue.campuses ca left join ref.subdivisions sd on sd.id=ca.subdivision_id
    where ca.provider_id=p_provider_id
  ), numbered as (select *,count(*) over() total_count from base), ordered as (
    select * from numbered order by lower(name),id limit 25
  )
  select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',25,'offset',0)
    into v_campuses from ordered o;

  return v_base || jsonb_build_object(
    'courses_page',coalesce(v_courses,jsonb_build_object('items','[]'::jsonb,'total',0,'limit',25,'offset',0)),
    'evidence_page',coalesce(v_evidence,jsonb_build_object('items','[]'::jsonb,'total',0,'limit',25,'offset',0)),
    'campuses_page',coalesce(v_campuses,jsonb_build_object('items','[]'::jsonb,'total',0,'limit',25,'offset',0)),
    'courses',coalesce(v_courses->'items','[]'::jsonb),
    'evidence',coalesce(v_evidence->'items','[]'::jsonb),
    'international_contacts',coalesce(v_contacts,jsonb_build_object('items','[]'::jsonb,'events','[]'::jsonb,'summary','{}'::jsonb)),
    'scholarship_count',(select count(*) from scholarship.scholarships s where s.provider_id=p_provider_id),
    'university_groups',security.provider_university_groups(p_provider_id),
    'history',jsonb_build_object('created_at',v_base->'created_at','updated_at',v_base->'updated_at','last_verified_at',v_base->'last_verified_at')
  );
end $function$
