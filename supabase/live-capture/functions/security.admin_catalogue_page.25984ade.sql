CREATE OR REPLACE FUNCTION security.admin_catalogue_page(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'catalogue', 'ref', 'scholarship', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'name'));
  v_dir text:=case when lower(coalesce(nullif(p_args->>'direction',''),'asc'))='desc' then 'desc' else 'asc' end;
  v_result jsonb;
  v_provider_id uuid:=nullif(p_args->>'provider_id','')::uuid;
  v_has_fee boolean:=case when nullif(p_args->>'has_fee','') is null then null else (p_args->>'has_fee')::boolean end;
  v_has_intake boolean:=case when nullif(p_args->>'has_intake','') is null then null else (p_args->>'has_intake')::boolean end;
  v_has_english boolean:=case when nullif(p_args->>'has_english','') is null then null else (p_args->>'has_english')::boolean end;
  v_has_scholarship boolean:=case when nullif(p_args->>'has_scholarship','') is null then null else (p_args->>'has_scholarship')::boolean end;
  v_has_state boolean:=case when nullif(p_args->>'has_state','') is null then null else (p_args->>'has_state')::boolean end;
  v_has_link boolean:=case when nullif(p_args->>'has_link','') is null then null else (p_args->>'has_link')::boolean end;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  if p_operation='providers_page' then
    return security.admin_providers_page(v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'subdivision_code',''),nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),coalesce(nullif(p_args->>'sort',''),'provider'),v_dir,nullif(p_args->>'university_group',''));
  elsif p_operation='courses_page' then
    return public.ui_courses_decision_page(v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'subdivision_code',''),v_provider_id,nullif(p_args->>'level_code',''),nullif(p_args->>'field_code',''),nullif(p_args->>'delivery_mode',''),nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),v_has_fee,v_has_intake,v_has_english,v_has_scholarship,nullif(p_args->>'min_completeness','')::numeric,nullif(p_args->>'freshness',''),coalesce(nullif(p_args->>'sort',''),'course'),v_dir,v_has_state,v_has_link,nullif(p_args->>'university_group',''));
  elsif p_operation='scholarships_page' then
    return security.admin_scholarships_page(p_args);
  elsif p_operation='campuses_page' then
    with base as (
      select ca.id,ca.stable_key,ca.name,ca.campus_code,ca.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,co.iso_alpha2::text country_code,co.name country_name,sd.code subdivision_code,sd.name subdivision_name,ca.city,ca.status,ca.publication_status,ca.last_verified_at,ca.created_at,ca.updated_at,(select count(*)::int from catalogue.course_campuses cc where cc.campus_id=ca.id) course_count
      from catalogue.campuses ca join catalogue.providers p on p.id=ca.provider_id join ref.countries co on co.id=p.country_id left join ref.subdivisions sd on sd.id=ca.subdivision_id
      where (nullif(trim(coalesce(p_args->>'query','')),'') is null or ca.name ilike '%'||trim(p_args->>'query')||'%' or coalesce(ca.campus_code,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(ca.stable_key,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(ca.city,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_args->>'query')||'%')
        and (nullif(p_args->>'country_code','') is null or co.iso_alpha2::text=upper(p_args->>'country_code'))
        and (nullif(p_args->>'subdivision_code','') is null or sd.code=upper(p_args->>'subdivision_code'))
        and (v_provider_id is null or ca.provider_id=v_provider_id)
        and (nullif(p_args->>'status','') is null or ca.status=p_args->>'status')
        and (nullif(p_args->>'publication_status','') is null or ca.publication_status=p_args->>'publication_status')
    ), numbered as (select *,count(*) over() total_count from base), ordered as (
      select * from numbered order by
        case when v_sort in ('name','campus') and v_dir='asc' then lower(name) end asc,
        case when v_sort in ('name','campus') and v_dir='desc' then lower(name) end desc,
        case when v_sort='provider' and v_dir='asc' then lower(provider_name) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(provider_name) end desc,
        case when v_sort='city' and v_dir='asc' then lower(coalesce(city,'')) end asc,
        case when v_sort='city' and v_dir='desc' then lower(coalesce(city,'')) end desc,
        case when v_sort='courses' and v_dir='asc' then course_count end asc,
        case when v_sort='courses' and v_dir='desc' then course_count end desc,
        case when v_sort='modified' and v_dir='asc' then updated_at end asc,
        case when v_sort='modified' and v_dir='desc' then updated_at end desc,
        lower(name),id
      limit v_limit offset v_offset
    )
    select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) into v_result from ordered o;
    return v_result;
  else
    raise exception 'unsupported catalogue page operation: %',p_operation using errcode='22023';
  end if;
end
$function$
