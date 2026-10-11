CREATE OR REPLACE FUNCTION security.scholarship_held_without_page(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('scholarship_id',s.id,'name',s.name) order by s.name),'[]'::jsonb)
    from scholarship.scholarships s
   where s.provider_id=p_provider_id and s.lifecycle_status='active' and security.reference_url_has_use(s.source_url, 'scholarship_placeholder')
     and not exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id=s.id and not (sp.url_source='discovered' and sp.read_status in ('name_mismatch','robots_disallowed','gone')))
     and not exists (select 1 from scholarship.identifiers i where i.scholarship_id=s.id and i.scheme='first_party_detail_url')
$function$
