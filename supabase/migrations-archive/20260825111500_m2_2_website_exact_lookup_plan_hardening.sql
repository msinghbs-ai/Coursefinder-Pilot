create or replace function api.website_course_lookup_preview_v1(p_identifier text)
returns jsonb
language sql
stable
security definer
set search_path to 'api','search','pg_catalog'
as $function$
with hit as (
  select d.*, 'exact_course_code'::text as match_type, 0 as match_priority
  from search.course_documents d
  where nullif(trim(p_identifier),'') is not null
    and lower(d.course_code)=lower(trim(p_identifier))
  union all
  select d.*, 'exact_course_id'::text as match_type, 1 as match_priority
  from search.course_documents d
  where nullif(trim(p_identifier),'') is not null
    and lower(d.course_stable_key)=lower(trim(p_identifier))
), chosen as (
  select * from hit order by match_priority,course_stable_key limit 1
), state as (
  select generation,content_hash from search.projection_state where projection_code='courses'
)
select jsonb_build_object(
 'contract_version','website-course-lookup-preview-v1','boundary','server-side-showcase-only',
 'meta',jsonb_build_object('mode','exact','projection_version','course-v3','projection_generation',(select generation from state),'projection_hash',(select content_hash from state),'publication_authority','not_granted'),
 'item',(select jsonb_build_object(
   'course_id',course_stable_key,'title',course_title,'course_code',course_code,
   'provider',jsonb_build_object('provider_id',provider_stable_key,'name',provider_name),
   'country',country_code,'study_level',study_level_code,
   'field',case when primary_field_code is null then null else jsonb_build_object('code',primary_field_code,'name',primary_field_name) end,
   'locations',to_jsonb(subdivision_codes),'delivery_modes',to_jsonb(delivery_modes),
   'regulatory_tuition',jsonb_build_object('state',regulatory_tuition_state,'amount',regulatory_tuition_amount,'currency',trim(regulatory_tuition_currency),'basis',regulatory_tuition_basis),
   'provider_current_tuition',jsonb_build_object('has_value',has_provider_current_tuition,'annual_amount',provider_annual_tuition_amount,'annual_currency',trim(provider_annual_tuition_currency),'options',provider_tuition_options),
   'official_course_url',official_course_url,'intakes',intake_options,'english_requirements',english_requirement_options,'scholarships',scholarship_options,
   'visibility',jsonb_build_object('publication_status',publication_status),
   'freshness',jsonb_build_object('source_updated_at',source_updated_at,'generated_at',generated_at),
   'match',jsonb_build_object('mode',match_type,'keyword_score',1000)
 ) from chosen)
);
$function$;

revoke all on function api.website_course_lookup_preview_v1(text) from public,anon,authenticated;
grant execute on function api.website_course_lookup_preview_v1(text) to service_role;
