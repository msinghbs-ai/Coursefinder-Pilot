CREATE OR REPLACE FUNCTION security.admin_catalogue_filter_options(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'auth'
AS $function$
declare
  v_rank integer := 0;
  v_country text := upper(nullif(trim(coalesce(p_args->>'country_code','')),''));
  v_subdivision text := upper(nullif(trim(coalesce(p_args->>'subdivision_code','')),''));
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 1 then
    raise exception 'assigned CourseFinder role required' using errcode='42501';
  end if;

  if p_operation='provider_filters' then
    return jsonb_build_object(
      'countries',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name)
        from (
          select distinct c.iso_alpha2::text code,c.name
          from ref.countries c
          where exists(select 1 from catalogue.providers p where p.country_id=c.id)
        ) x
      ),'[]'::jsonb),
      'subdivisions',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'type',x.subdivision_type) order by x.name)
        from (
          select distinct s.code,s.name,s.subdivision_type
          from ref.subdivisions s
          join ref.countries c on c.id=s.country_id
          where (v_country is null or c.iso_alpha2::text=v_country)
            and (
              exists(select 1 from catalogue.providers p where p.subdivision_id=s.id)
              or exists(select 1 from catalogue.campuses cp where cp.subdivision_id=s.id)
            )
        ) x
      ),'[]'::jsonb)
    );
  elsif p_operation='course_filters' then
    return jsonb_build_object(
      'countries',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name)
        from (
          select distinct co.iso_alpha2::text code,co.name
          from catalogue.courses c
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
        ) x
      ),'[]'::jsonb),
      'subdivisions',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'type',x.subdivision_type) order by x.name)
        from (
          select distinct s.code,s.name,s.subdivision_type
          from catalogue.courses c
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
          join catalogue.course_campuses cc on cc.course_id=c.id
          join catalogue.campuses cp on cp.id=cc.campus_id
          join ref.subdivisions s on s.id=cp.subdivision_id
          where (v_country is null or co.iso_alpha2::text=v_country)
        ) x
      ),'[]'::jsonb),
      'providers',coalesce((
        select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'stable_key',x.stable_key) order by x.name)
        from (
          select distinct p.id,coalesce(p.display_name,p.canonical_name) name,p.stable_key
          from catalogue.courses c
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
          where (v_country is null or co.iso_alpha2::text=v_country)
            and (v_subdivision is null or exists(
              select 1
              from catalogue.course_campuses cc
              join catalogue.campuses cp on cp.id=cc.campus_id
              join ref.subdivisions s on s.id=cp.subdivision_id
              where cc.course_id=c.id and s.code=v_subdivision
            ))
        ) x
      ),'[]'::jsonb),
      'levels',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.sort_order,x.name)
        from (
          select distinct sl.code,sl.name,sl.sort_order
          from catalogue.courses c
          join ref.study_levels sl on sl.id=c.study_level_id
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
          where (v_country is null or co.iso_alpha2::text=v_country)
            and (v_subdivision is null or exists(
              select 1 from catalogue.course_campuses cc
              join catalogue.campuses cp on cp.id=cc.campus_id
              join ref.subdivisions s on s.id=cp.subdivision_id
              where cc.course_id=c.id and s.code=v_subdivision
            ))
        ) x
      ),'[]'::jsonb),
      'fields',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.name) order by x.name)
        from (
          select distinct fos.code,fos.name
          from catalogue.courses c
          join ref.fields_of_study fos on fos.id=c.primary_field_id
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
          where (v_country is null or co.iso_alpha2::text=v_country)
            and (v_subdivision is null or exists(
              select 1 from catalogue.course_campuses cc
              join catalogue.campuses cp on cp.id=cc.campus_id
              join ref.subdivisions s on s.id=cp.subdivision_id
              where cc.course_id=c.id and s.code=v_subdivision
            ))
        ) x
      ),'[]'::jsonb),
      'delivery_modes',coalesce((
        select jsonb_agg(jsonb_build_object('code',x.code,'name',x.code) order by x.code)
        from (
          select distinct cc.delivery_mode code
          from catalogue.course_campuses cc
          join catalogue.courses c on c.id=cc.course_id
          join catalogue.providers p on p.id=c.provider_id
          join ref.countries co on co.id=p.country_id
          where cc.delivery_mode is not null and btrim(cc.delivery_mode)<>''
            and (v_country is null or co.iso_alpha2::text=v_country)
            and (v_subdivision is null or exists(
              select 1 from catalogue.course_campuses cc2
              join catalogue.campuses cp2 on cp2.id=cc2.campus_id
              join ref.subdivisions s2 on s2.id=cp2.subdivision_id
              where cc2.course_id=c.id and s2.code=v_subdivision
            ))
        ) x
      ),'[]'::jsonb)
    );
  end if;

  raise exception 'unsupported catalogue filter operation: %',p_operation using errcode='22023';
end
$function$
