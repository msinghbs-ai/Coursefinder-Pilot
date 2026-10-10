CREATE OR REPLACE FUNCTION public.website_v2_provider(p_provider_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'catalogue', 'ref', 'security', 'api'
AS $function$
declare v_pid uuid; v jsonb; v_outcomes_ok boolean;
begin
  if nullif(btrim(coalesce(p_provider_id,'')),'') is null then raise exception 'INVALID_INPUT: provider_id required' using errcode='22023'; end if;
  select p.id into v_pid from catalogue.providers p where lower(p.stable_key)=lower(btrim(p_provider_id)) limit 1;
  if v_pid is null then return jsonb_build_object('contract_version','website-search-v2','error',jsonb_build_object('code','NOT_FOUND')); end if;
  v := (public.website_v2_providers(jsonb_build_object('provider_ids', jsonb_build_array(btrim(p_provider_id))),1,1))->'items'->0;
  if v is null then return jsonb_build_object('contract_version','website-search-v2','error',jsonb_build_object('code','NOT_FOUND')); end if;
  select exists (select 1 from search.enrichment_gates g where g.projection_code='courses' and g.domain_code='provider_outcomes' and g.gate_status='approved') into v_outcomes_ok;
  v := v || jsonb_build_object(
    'description', (select p.description from catalogue.providers p where p.id=v_pid),
    'rankings', public.website_v2_provider_rankings(v_pid),
    'outcomes_state', case when v_outcomes_ok then 'admitted' else 'not_admitted' end,
    'outcomes', case when v_outcomes_ok then coalesce((select jsonb_agg(jsonb_build_object('survey', sv.code, 'metric_code', m.code, 'metric_name', m.name,
                   'study_level', o.source_cohort_code, 'value', o.metric_value, 'unit', m.unit, 'ci_low', o.confidence_low, 'ci_high', o.confidence_high,
                   'reference_year', o.collection_year_to, 'responses', o.response_count, 'grain', 'provider'))
                 from catalogue.provider_outcomes o join ref.outcome_metrics m on m.id=o.metric_id join ref.outcome_surveys sv on sv.id=o.survey_id
                 where o.provider_id=v_pid and o.external_study_area_id is null), '[]'::jsonb) else '[]'::jsonb end);
  return jsonb_build_object('contract_version','website-search-v2','item',v);
end $function$
