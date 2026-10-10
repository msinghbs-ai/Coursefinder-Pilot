CREATE OR REPLACE FUNCTION security.admin_campus_detail(p_campus_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'pipeline', 'ref', 'scholarship', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  select jsonb_build_object(
    'id',ca.id,'stable_key',ca.stable_key,'name',ca.name,'campus_code',ca.campus_code,
    'provider_id',ca.provider_id,'provider_name',coalesce(p.display_name,p.canonical_name),
    'country_code',co.iso_alpha2,'country_name',co.name,'subdivision_code',sd.code,'subdivision_name',sd.name,
    'city',ca.city,'address_line1',ca.address_line1,'address_line2',ca.address_line2,'postcode',ca.postcode,
    'latitude',ca.latitude,'longitude',ca.longitude,'phone',ca.phone,'website',ca.website,
    'status',ca.status,'publication_status',ca.publication_status,'valid_from',ca.valid_from,'valid_to',ca.valid_to,
    'last_verified_at',ca.last_verified_at,'created_at',ca.created_at,'updated_at',ca.updated_at,
    'source',jsonb_build_object('source_id',ca.source_id,'source_label',s.label,'source_type',s.source_type,'source_url',s.url),
    'evidence',case when e.id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('id',e.id,'type',e.evidence_type,'source_url',e.source_url,'storage_path',e.storage_path,'content_hash',e.content_hash,'captured_at',e.captured_at)) end,
    'courses_page',coalesce((
      with base as (
        select c.id,c.stable_key,c.canonical_title,c.course_code,c.lifecycle_status,c.publication_status,cc.delivery_mode,cc.is_primary
        from catalogue.course_campuses cc join catalogue.courses c on c.id=cc.course_id
        where cc.campus_id=ca.id
      ), numbered as (select *,count(*) over() total_count from base), ordered as (
        select * from numbered order by lower(canonical_title),id limit 25
      )
      select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',25,'offset',0) from ordered o
    ),jsonb_build_object('items','[]'::jsonb,'total',0,'limit',25,'offset',0)),
    'scholarship_count',(select count(distinct ss.scholarship_id) from scholarship.scopes ss where ss.campus_id=ca.id and coalesce(ss.include_exclude,'include')='include')
  ) into v_result
  from catalogue.campuses ca
  join catalogue.providers p on p.id=ca.provider_id
  join ref.countries co on co.id=ca.country_id
  left join ref.subdivisions sd on sd.id=ca.subdivision_id
  left join pipeline.sources s on s.id=ca.source_id
  left join pipeline.evidence_artifacts e on e.id=ca.evidence_id
  where ca.id=p_campus_id;

  return coalesce(v_result,'{}'::jsonb);
end
$function$
