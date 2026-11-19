CREATE OR REPLACE FUNCTION security.coverage_sweep_source(p_provider_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline'
AS $function$
declare v uuid;
begin
  select id into v from pipeline.sources where source_type='provider_course_page_sweep' and provider_id=p_provider_id limit 1;
  if v is null then
    insert into pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
    select 'provider_course_page_sweep', s.system_id, p.id, p.country_id, p.website,
           coalesce(p.display_name,p.canonical_name)||' course pages (coverage sweep)', 80, 'active',
           jsonb_build_object('facts',jsonb_build_array('official_course_url','international_fee','english_requirement','intake'),'decision','CF-247 complete coverage','admission','not admitted: candidates only')
      from catalogue.providers p cross join lateral (select system_id from pipeline.sources where source_type='provider_course_page' limit 1) s
     where p.id=p_provider_id returning id into v;
  end if;
  return v;
end $function$
