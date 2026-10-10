CREATE OR REPLACE FUNCTION api.zoho_scholarship_search_v1(p_query text DEFAULT NULL::text, p_provider_ids text[] DEFAULT NULL::text[], p_changed_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'api'
AS $function$
  with base as (
    select s.*, p.stable_key provider_stable_key, p.canonical_name provider_name
    from scholarship.scholarships s
    left join catalogue.providers p on p.id=s.provider_id
    where not exists (select 1 from security.layer4_search_blocked_scholarships cf_block where cf_block.scholarship_id=s.id)
      and (p_query is null or btrim(p_query)='' or s.name ilike '%'||btrim(p_query)||'%' or s.stable_key ilike '%'||btrim(p_query)||'%')
      and (p_provider_ids is null or p.stable_key = any(p_provider_ids))
      and (p_changed_since is null or s.updated_at > p_changed_since)
  ),
  page as (
    select * from base
    order by lower(name), stable_key
    limit greatest(1, least(coalesce(p_limit,20),50))
    offset greatest(coalesce(p_offset,0),0)
  )
  select jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','scholarships',
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'scholarship_id',stable_key,'name',name,
      'provider',case when provider_stable_key is null then null else jsonb_build_object('provider_id',provider_stable_key,'name',provider_name) end,
      'scholarship_type',scholarship_type,'audience',audience,'award_value_text',award_value_text,
      'application_required',application_required,'application_open_date',application_open_date,
      'application_close_date',application_close_date,'academic_year',academic_year,
      'source_url',source_url,'lifecycle_status',lifecycle_status,'publication_status',publication_status,
      'freshness',jsonb_build_object('updated_at',updated_at)
    ) order by lower(name), stable_key),'[]'::jsonb),
    'page',jsonb_build_object(
      'limit',greatest(1, least(coalesce(p_limit,20),50)),
      'offset',greatest(coalesce(p_offset,0),0),
      'total',(select count(*) from base)
    ),
    'ordering','name_asc,scholarship_id_asc',
    'generated_at',now()
  ) from page;
$function$
