CREATE OR REPLACE FUNCTION api.zoho_sync_manifest_v1(p_changed_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'scholarship', 'search', 'api'
AS $function$
  select jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'boundary','server-side-pilot-only',
    'changed_since',p_changed_since,
    'providers',jsonb_build_object(
      'count',(select count(*) from catalogue.providers p where not exists (select 1 from security.layer4_search_blocked_providers cf_block where cf_block.provider_id=p.id) and (p_changed_since is null or p.updated_at > p_changed_since)),
      'max_updated_at',(select max(p.updated_at) from catalogue.providers p where not exists (select 1 from security.layer4_search_blocked_providers cf_block where cf_block.provider_id=p.id))
    ),
    'courses',jsonb_build_object(
      'count',(select count(*) from search.course_documents d where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id) and (p_changed_since is null or greatest(d.updated_at,d.source_updated_at,d.generated_at) > p_changed_since)),
      'max_updated_at',(select max(greatest(d.updated_at,d.source_updated_at,d.generated_at)) from search.course_documents d where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id))
    ),
    'scholarships',jsonb_build_object(
      'count',(select count(*) from scholarship.scholarships s where not exists (select 1 from security.layer4_search_blocked_scholarships cf_block where cf_block.scholarship_id=s.id) and (p_changed_since is null or s.updated_at > p_changed_since)),
      'max_updated_at',(select max(s.updated_at) from scholarship.scholarships s where not exists (select 1 from security.layer4_search_blocked_scholarships cf_block where cf_block.scholarship_id=s.id))
    ),
    'ordering',jsonb_build_object(
      'providers','name_asc,provider_id_asc',
      'courses','title_asc,course_id_asc',
      'scholarships','name_asc,scholarship_id_asc'
    ),
    'generated_at',now()
  );
$function$
