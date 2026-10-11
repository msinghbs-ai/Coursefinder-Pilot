CREATE OR REPLACE FUNCTION api.zoho_scholarship_lookup_v1(p_identifier text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'api'
AS $function$
  with x as (
    select s.*, p.stable_key provider_stable_key, p.canonical_name provider_name
    from scholarship.scholarships s
    left join catalogue.providers p on p.id=s.provider_id
    where not exists (select 1 from security.layer4_search_blocked_scholarships cf_block where cf_block.scholarship_id=s.id)
      and lower(s.stable_key)=lower(btrim(p_identifier))
      and s.lifecycle_status='active' and s.publication_status='published'  -- v2.15.239 (S1): published scholarships only, always
    limit 1
  )
  select case when exists(select 1 from x) then jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','scholarship',
    'item',(select jsonb_build_object(
      'scholarship_id',stable_key,'name',name,
      'provider',case when provider_stable_key is null then null else jsonb_build_object('provider_id',provider_stable_key,'name',provider_name) end,
      'scholarship_type',scholarship_type,'description',description,'audience',audience,
      'award_value_text',award_value_text,'application_required',application_required,
      'application_open_date',application_open_date,'application_close_date',application_close_date,
      'academic_year',academic_year,'source_url',source_url,
      'lifecycle_status',lifecycle_status,'publication_status',publication_status,
      'freshness',jsonb_build_object('updated_at',updated_at)
    ) from x),
    'generated_at',now()
  ) else jsonb_build_object(
    'contract_version','zoho-integration-v1','resource','scholarship','error',
    jsonb_build_object('code','NOT_FOUND','message','Scholarship identifier not found')
  ) end;
$function$
