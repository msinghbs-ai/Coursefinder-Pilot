CREATE OR REPLACE FUNCTION api.zoho_course_lookup_v1(p_identifier text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'api'
AS $function$
  with x as (
    select d.* from search.course_documents d
    where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
      and (lower(d.course_stable_key)=lower(btrim(p_identifier))
       or lower(d.course_code)=lower(btrim(p_identifier)))
    order by case when lower(d.course_stable_key)=lower(btrim(p_identifier)) then 0 else 1 end
             ,d.course_stable_key
    limit 1
  )
  select case when exists(select 1 from x) then jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','course',
    'item',(select jsonb_build_object(
      'course_id',course_stable_key,'course_code',course_code,'title',course_title,
      'provider',jsonb_build_object('provider_id',provider_stable_key,'name',provider_name),
      'country_code',country_code,
      'study_level',jsonb_build_object('code',study_level_code),
      'field',jsonb_build_object('code',primary_field_code,'name',primary_field_name),
      'subdivision_codes',coalesce(to_jsonb(subdivision_codes),'[]'::jsonb),
      'delivery_modes',coalesce(to_jsonb(delivery_modes),'[]'::jsonb),
      'regulatory_tuition',jsonb_build_object(
        'state',regulatory_tuition_state,'amount',regulatory_tuition_amount,
        'currency',regulatory_tuition_currency,'basis',regulatory_tuition_basis
      ),
      'provider_current_tuition',jsonb_build_object(
        'has_value',has_provider_current_tuition,'annual_amount',provider_annual_tuition_amount,
        'annual_currency',provider_annual_tuition_currency,'options',coalesce(provider_tuition_options,'[]'::jsonb)
      ),
      'fee_used',security.course_fee_used_v1(course_id),
      'official_course_url',official_course_url,
      'intakes',coalesce(intake_options,'[]'::jsonb),
      'english_requirements',coalesce(english_requirement_options,'[]'::jsonb),
      'scholarships',coalesce(scholarship_options,'[]'::jsonb),
      'publication_status',publication_status,
      'context',jsonb_build_object(
        'qilt',jsonb_build_object('state','not_admitted','grain','provider_or_study_area','message','QILT remains contextual and is not yet admitted in this v1 Pilot read function'),
        'prisms',jsonb_build_object('state','not_admitted','grain','provider_state_or_sector','message','PRISMS remains contextual and is not yet admitted in this v1 Pilot read function')
      ),
      'freshness',jsonb_build_object(
        'source_updated_at',source_updated_at,'projection_updated_at',updated_at,'generated_at',generated_at
      )
    ) from x),
    'generated_at',now()
  ) else jsonb_build_object(
    'contract_version','zoho-integration-v1','resource','course','error',
    jsonb_build_object('code','NOT_FOUND','message','Course identifier not found')
  ) end;
$function$
