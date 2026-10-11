CREATE OR REPLACE FUNCTION security.scholarship_selection_for_provider_impl(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'scholarship', 'ref'
AS $function$
with provider_base as (
  select p.id provider_id,p.canonical_name provider_name,p.country_id
  from catalogue.providers p where p.id=p_provider_id
), scholarship_base as (
  select s.*,
         (select count(*) from scholarship.scopes sc where sc.scholarship_id=s.id) scope_count,
         (select count(*) from scholarship.scopes sc where sc.scholarship_id=s.id
           and coalesce(sc.include_exclude,'include')='include' and sc.provider_id=p_provider_id) provider_scope_match_count,
         (select count(*) from scholarship.scopes sc join catalogue.courses c on c.id=sc.course_id
           where sc.scholarship_id=s.id and coalesce(sc.include_exclude,'include')='include' and c.provider_id=p_provider_id) course_scope_match_count
  from scholarship.scholarships s
  where s.lifecycle_status='active'
    and lower(coalesce(s.audience,'')) in ('international','international_and_domestic')
    and (
      s.provider_id=p_provider_id
      or (s.provider_id is null and exists(
        select 1 from scholarship.scopes sc
        where sc.scholarship_id=s.id and coalesce(sc.include_exclude,'include')='include' and sc.provider_id=p_provider_id
      ))
    )
), rendered as (
  select jsonb_build_object(
    'scholarship_id',s.id,
    'name',s.name,
    'selection_state',case when s.provider_id=p_provider_id then 'PROVIDER_CATALOGUE' else 'PROVIDER_SCOPE_CANDIDATE' end,
    'eligibility_state','UNRESOLVED',
    'source_fact',jsonb_build_object(
      'label','SOURCE FACT','audience',s.audience,'nationalities',s.nationalities,'award_value_is_maximum',s.award_value_is_maximum,'award_value_text',s.award_value_text,
      'application_required',s.application_required,'application_open_date',s.application_open_date,
      'application_close_date',s.application_close_date,'academic_year',s.academic_year,
      'source_url',s.source_url,'source_id',s.source_id,'evidence_id',s.evidence_id,
      'publication_status',s.publication_status,'scope_count',s.scope_count,
      'matched_scope_count',s.provider_scope_match_count+s.course_scope_match_count,
      'scholarship_provider_id',s.provider_id
    ),
    'derived_score',jsonb_build_object(
      'label','PROVIDER INVENTORY','scope_fit_score',case
        when s.provider_scope_match_count>0 then 100
        when s.course_scope_match_count>0 then 90
        when s.provider_id=p_provider_id then 80 else 70 end,
      'meaning','International Scholarship inventory relevance for this university; exact Course/student eligibility remains separate.'
    ),
    'missing_unresolved',jsonb_build_object(
      'label','MISSING / UNRESOLVED',
      'reason','University inventory match only; exact Course and student eligibility have not been evaluated.',
      'mandatory_criteria',coalesce((select jsonb_agg(jsonb_build_object(
          'criterion_type',c.criterion_type,'human_text',c.human_text,'machine_evaluable',c.machine_evaluable,
          'source_id',c.source_id,'evidence_id',c.evidence_id,'confidence',c.confidence
        ) order by c.criterion_type,c.created_at)
        from scholarship.criteria c where c.scholarship_id=s.id and c.status='active' and c.is_mandatory),'[]'::jsonb),
      'non_machine_evaluable_count',(select count(*) from scholarship.criteria c where c.scholarship_id=s.id and c.status='active' and c.is_mandatory and not c.machine_evaluable)
    )
  ) item
  from scholarship_base s
)
select jsonb_build_object(
  'mode','provider','audience_filter','international','provider_id',b.provider_id,'provider_name',b.provider_name,
  'contract','scholarship_selection_decision_support_v2','eligibility_inference_permitted',false,
  'candidate_count',(select count(*) from scholarship_base),
  'candidates',coalesce((select jsonb_agg(item order by item->>'name') from rendered),'[]'::jsonb)
) from provider_base b
$function$
