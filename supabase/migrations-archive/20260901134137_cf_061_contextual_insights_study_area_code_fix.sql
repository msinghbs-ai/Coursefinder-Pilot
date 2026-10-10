-- CF-CHG-20260901-061
-- Correct external study-area code projection.
-- ref.external_study_areas stores external_code, not code.

begin;

create or replace function security.admin_contextual_insights_v2(
  p_entity_type text,
  p_entity_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','catalogue','scholarship','ref','auth'
as $$
declare
  v_rank integer:=0;
  v_provider uuid;
  v_level uuid;
  v_country_code text;
  v_items jsonb:='[]'::jsonb;
  v_total integer:=0;
  v_base jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'catalogue reader role required' using errcode='42501'; end if;

  v_base:=security.admin_contextual_insights(p_entity_type,p_entity_id);

  if p_entity_type='provider' then
    select p.id,co.iso_alpha2 into v_provider,v_country_code
    from catalogue.providers p left join ref.countries co on co.id=p.country_id
    where p.id=p_entity_id;
  elsif p_entity_type='course' then
    select c.provider_id,c.study_level_id,co.iso_alpha2 into v_provider,v_level,v_country_code
    from catalogue.courses c
    join catalogue.providers p on p.id=c.provider_id
    left join ref.countries co on co.id=p.country_id
    where c.id=p_entity_id;
  else
    raise exception 'unsupported contextual entity type' using errcode='22023';
  end if;

  if v_provider is null then return v_base; end if;

  select count(*) into v_total
  from catalogue.provider_outcomes po
  where po.provider_id=v_provider
    and coalesce(po.status,'current') in ('active','current')
    and (p_entity_type='provider' or po.study_level_id is null or v_level is null or po.study_level_id=v_level);

  select coalesce(jsonb_agg(to_jsonb(x) order by x.level_match desc,x.collection_year_to desc nulls last,x.metric_name),'[]'::jsonb)
  into v_items
  from (
    select
      po.id,
      coalesce(os.source_family,case when v_country_code='AU' then 'QILT' else 'outcomes' end) source_family,
      coalesce(os.name,os.code,'Student outcomes') source_label,
      os.code survey_code,
      om.name metric_name,
      om.code metric_code,
      om.unit,
      po.metric_value,
      po.national_benchmark,
      po.response_count,
      po.confidence_low,
      po.confidence_high,
      po.audience,
      po.collection_year_from,
      po.collection_year_to,
      po.source_cohort_code,
      esa.name study_area,
      esa.external_code study_area_code,
      sl.name study_level,
      sl.code study_level_code,
      po.status,
      po.observed_at,
      po.evidence_id,
      case when p_entity_type='course' and po.study_level_id=v_level then true else false end level_match,
      case when p_entity_type='provider' then 'provider' else 'provider_context' end granularity
    from catalogue.provider_outcomes po
    left join ref.outcome_surveys os on os.id=po.survey_id
    left join ref.outcome_metrics om on om.id=po.metric_id
    left join ref.external_study_areas esa on esa.id=po.external_study_area_id
    left join ref.study_levels sl on sl.id=po.study_level_id
    where po.provider_id=v_provider
      and coalesce(po.status,'current') in ('active','current')
      and (p_entity_type='provider' or po.study_level_id is null or v_level is null or po.study_level_id=v_level)
    order by
      case when p_entity_type='course' and po.study_level_id=v_level then 1 else 0 end desc,
      po.collection_year_to desc nulls last,
      po.observed_at desc nulls last,
      om.name
    limit 30
  ) x;

  v_base:=jsonb_set(v_base,'{student_outcomes,items}',v_items,true);
  v_base:=jsonb_set(v_base,'{student_outcomes,total}',to_jsonb(v_total),true);
  v_base:=jsonb_set(v_base,'{student_outcomes,granularity}',to_jsonb(case when p_entity_type='provider' then 'provider' else 'provider_context' end),true);
  return v_base;
end
$$;

revoke all on function security.admin_contextual_insights_v2(text,uuid) from public,anon,authenticated;
grant execute on function security.admin_contextual_insights_v2(text,uuid) to service_role;

commit;
