CREATE OR REPLACE FUNCTION api.zoho_filter_options_v1(p_kind text, p_country_code text DEFAULT NULL::text, p_query text DEFAULT NULL::text, p_limit integer DEFAULT 10, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'api', 'ref', 'search'
AS $function$
declare
  v_kind text := lower(trim(coalesce(p_kind,'')));
  v_country text := upper(nullif(trim(coalesce(p_country_code,'')), ''));
  v_query text := nullif(trim(coalesce(p_query,'')), '');
  v_limit integer := least(greatest(coalesce(p_limit,10),1),50);
  v_offset integer := greatest(coalesce(p_offset,0),0);
  v_total bigint := 0;
  v_items jsonb := '[]'::jsonb;
begin
  if v_kind = 'country' then
    select count(*)
      into v_total
      from ref.countries c
     where exists (
             select 1 from search.course_documents d
             where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
               and d.country_id = c.id
           )
       and (
         v_query is null
         or c.name ilike '%'||v_query||'%'
         or c.iso_alpha2::text ilike '%'||v_query||'%'
       );

    select coalesce(jsonb_agg(jsonb_build_object(
             'code', x.iso_alpha2,
             'name', x.name
           ) order by x.name, x.iso_alpha2), '[]'::jsonb)
      into v_items
      from (
        select trim(c.iso_alpha2::text) as iso_alpha2, c.name
          from ref.countries c
         where exists (
                 select 1 from search.course_documents d
                 where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
               and d.country_id = c.id
               )
           and (
             v_query is null
             or c.name ilike '%'||v_query||'%'
             or c.iso_alpha2::text ilike '%'||v_query||'%'
           )
         order by c.name, c.iso_alpha2
         limit v_limit offset v_offset
      ) x;

  elsif v_kind = 'subdivision' then
    if v_country is null then
      raise exception using errcode='22023', message='country_code_required';
    end if;

    select count(*)
      into v_total
      from ref.subdivisions s
      join ref.countries c on c.id = s.country_id
     where trim(c.iso_alpha2::text) = v_country
       and exists (
             select 1
             from search.course_documents d
             where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
               and d.country_id = c.id
               and s.code = any(coalesce(d.subdivision_codes, '{}'::text[]))
           )
       and (
         v_query is null
         or s.name ilike '%'||v_query||'%'
         or s.code ilike '%'||v_query||'%'
       );

    select coalesce(jsonb_agg(jsonb_build_object(
             'code', x.code,
             'name', x.name,
             'country_code', v_country
           ) order by x.name, x.code), '[]'::jsonb)
      into v_items
      from (
        select s.code, s.name
          from ref.subdivisions s
          join ref.countries c on c.id = s.country_id
         where trim(c.iso_alpha2::text) = v_country
           and exists (
                 select 1
                 from search.course_documents d
                 where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
               and d.country_id = c.id
                   and s.code = any(coalesce(d.subdivision_codes, '{}'::text[]))
               )
           and (
             v_query is null
             or s.name ilike '%'||v_query||'%'
             or s.code ilike '%'||v_query||'%'
           )
         order by s.name, s.code
         limit v_limit offset v_offset
      ) x;
  else
    raise exception using errcode='22023', message='invalid_filter_kind';
  end if;

  return jsonb_build_object(
    'contract','zoho-integration-v1',
    'kind',v_kind,
    'items',v_items,
    'total',v_total,
    'limit',v_limit,
    'offset',v_offset,
    'has_more',(v_offset + v_limit) < v_total
  );
end;
$function$
