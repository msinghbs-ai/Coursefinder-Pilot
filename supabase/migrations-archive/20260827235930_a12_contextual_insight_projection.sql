-- A12 contextual insight projection: QILT/PRISMS/country counterparts + Scholarships on Provider/Course detail.
-- Read-only derived context. Does not alter Layer 1 identity or authorize Search/Publication mutation.
begin;

CREATE OR REPLACE FUNCTION security.admin_contextual_insights(p_entity_type text, p_entity_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'scholarship', 'ref'
AS $function$
declare
  v_rank smallint;
  v_provider uuid;
  v_course uuid;
  v_country uuid;
  v_country_code text;
  v_subdivision uuid;
  v_level uuid;
  v_field uuid;
  v_outcomes jsonb:='[]'::jsonb;
  v_flow jsonb:='[]'::jsonb;
  v_scholarships jsonb:='[]'::jsonb;
  v_outcome_count int:=0;
  v_flow_direct_count int:=0;
  v_flow_context_count int:=0;
  v_scholarship_count int:=0;
  v_flow_state text:='not_available';
  v_flow_granularity text:='none';
begin
  v_rank:=security.current_role_rank();
  if coalesce(v_rank,0)<1 then
    raise exception 'catalogue reader role required' using errcode='42501';
  end if;

  if p_entity_type='provider' then
    select p.id,p.country_id,p.subdivision_id,c.iso_alpha2
      into v_provider,v_country,v_subdivision,v_country_code
    from catalogue.providers p
    left join ref.countries c on c.id=p.country_id
    where p.id=p_entity_id;
    if v_provider is null then return '{}'::jsonb; end if;

    select count(*) into v_outcome_count
    from catalogue.provider_outcomes po
    where po.provider_id=v_provider and coalesce(po.status,'current') in ('active','current');

    select coalesce(jsonb_agg(to_jsonb(x) order by x.collection_year_to desc nulls last,x.metric_name),'[]'::jsonb)
    into v_outcomes
    from (
      select
        po.id,
        coalesce(os.source_family,case when v_country_code='AU' then 'QILT' else 'outcomes' end) source_family,
        coalesce(os.name,os.code,'Student outcomes') source_label,
        om.name metric_name,
        om.code metric_code,
        om.unit,
        po.metric_value,
        po.national_benchmark,
        po.response_count,
        po.audience,
        po.collection_year_from,
        po.collection_year_to,
        esa.name study_area,
        sl.name study_level,
        po.status,
        po.observed_at,
        po.evidence_id,
        'provider'::text granularity
      from catalogue.provider_outcomes po
      left join ref.outcome_surveys os on os.id=po.survey_id
      left join ref.outcome_metrics om on om.id=po.metric_id
      left join ref.external_study_areas esa on esa.id=po.external_study_area_id
      left join ref.study_levels sl on sl.id=po.study_level_id
      where po.provider_id=v_provider and coalesce(po.status,'current') in ('active','current')
      order by po.collection_year_to desc nulls last,po.observed_at desc nulls last,om.name
      limit 12
    ) x;

    select count(*) into v_flow_direct_count
    from catalogue.student_flow_observations sf
    where sf.provider_id=v_provider and coalesce(sf.status,'current') in ('active','current');

    if v_flow_direct_count>0 then
      v_flow_state:='direct_provider';
      v_flow_granularity:='provider';
      select coalesce(jsonb_agg(to_jsonb(x) order by x.period_end desc nulls last,x.metric_value desc nulls last),'[]'::jsonb)
      into v_flow
      from (
        select sf.id,coalesce(os.source_family,case when v_country_code='AU' then 'PRISMS' else 'student_flow' end) source_family,
               coalesce(os.name,os.code,'International student flow') source_label,
               om.name metric_name,om.code metric_code,sf.metric_value,sf.period_start,sf.period_end,sf.period_type,
               sd.name subdivision,esa.name study_area,sf.source_nationality_name nationality,
               sf.is_suppressed,sf.suppression_code,sf.status,sf.observed_at,sf.evidence_id,
               'provider'::text granularity
        from catalogue.student_flow_observations sf
        left join ref.outcome_surveys os on os.id=sf.survey_id
        left join ref.outcome_metrics om on om.id=sf.metric_id
        left join ref.subdivisions sd on sd.id=sf.subdivision_id
        left join ref.external_study_areas esa on esa.id=sf.external_study_area_id
        where sf.provider_id=v_provider and coalesce(sf.status,'current') in ('active','current')
        order by sf.period_end desc nulls last,sf.metric_value desc nulls last
        limit 10
      ) x;
    else
      select count(*) into v_flow_context_count
      from catalogue.student_flow_observations sf
      where coalesce(sf.status,'current') in ('active','current')
        and sf.subdivision_id in (
          select v_subdivision where v_subdivision is not null
          union
          select cp.subdivision_id from catalogue.campuses cp where cp.provider_id=v_provider and cp.subdivision_id is not null
        );

      if v_flow_context_count>0 then
        v_flow_state:='regional_context';
        v_flow_granularity:='regional';
        select coalesce(jsonb_agg(to_jsonb(x) order by x.period_end desc nulls last,x.metric_value desc nulls last),'[]'::jsonb)
        into v_flow
        from (
          select sf.id,coalesce(os.source_family,case when v_country_code='AU' then 'PRISMS' else 'student_flow' end) source_family,
                 coalesce(os.name,os.code,'International student flow') source_label,
                 om.name metric_name,om.code metric_code,sf.metric_value,sf.period_start,sf.period_end,sf.period_type,
                 sd.name subdivision,esa.name study_area,sf.source_nationality_name nationality,
                 sf.is_suppressed,sf.suppression_code,sf.status,sf.observed_at,sf.evidence_id,
                 'regional_context'::text granularity
          from catalogue.student_flow_observations sf
          left join ref.outcome_surveys os on os.id=sf.survey_id
          left join ref.outcome_metrics om on om.id=sf.metric_id
          left join ref.subdivisions sd on sd.id=sf.subdivision_id
          left join ref.external_study_areas esa on esa.id=sf.external_study_area_id
          where coalesce(sf.status,'current') in ('active','current')
            and sf.subdivision_id in (
              select v_subdivision where v_subdivision is not null
              union
              select cp.subdivision_id from catalogue.campuses cp where cp.provider_id=v_provider and cp.subdivision_id is not null
            )
          order by sf.period_end desc nulls last,sf.metric_value desc nulls last
          limit 10
        ) x;
      else
        v_flow_state:=case when v_country_code='AU' then 'not_mapped' else 'country_counterpart_not_available' end;
      end if;
    end if;

    select count(distinct s.id) into v_scholarship_count
    from scholarship.scholarships s
    left join scholarship.scopes sc on sc.scholarship_id=s.id and coalesce(sc.include_exclude,'include')='include'
    where coalesce(s.lifecycle_status,'active')='active'
      and (s.provider_id=v_provider or sc.provider_id=v_provider);

    select coalesce(jsonb_agg(to_jsonb(x) order by x.application_close_date nulls last,x.name),'[]'::jsonb)
    into v_scholarships
    from (
      select distinct on(s.id)
        s.id,s.name,s.scholarship_type,s.audience,s.award_value_text,s.academic_year,
        s.application_required,s.application_open_date,s.application_close_date,
        s.lifecycle_status,s.publication_status,s.source_url,s.evidence_id,
        case when exists(select 1 from scholarship.scopes sc where sc.scholarship_id=s.id and sc.provider_id=v_provider and coalesce(sc.include_exclude,'include')='include')
             then 'provider_scope' else 'provider_owner' end relationship,
        'provider'::text granularity
      from scholarship.scholarships s
      left join scholarship.scopes sc on sc.scholarship_id=s.id
      where coalesce(s.lifecycle_status,'active')='active'
        and (s.provider_id=v_provider or (sc.provider_id=v_provider and coalesce(sc.include_exclude,'include')='include'))
      order by s.id,s.application_close_date nulls last
      limit 10
    ) x;

  elsif p_entity_type='course' then
    select c.id,c.provider_id,p.country_id,coalesce(camp.subdivision_id,p.subdivision_id),pco.iso_alpha2,c.study_level_id,c.primary_field_id
      into v_course,v_provider,v_country,v_subdivision,v_country_code,v_level,v_field
    from catalogue.courses c
    join catalogue.providers p on p.id=c.provider_id
    left join ref.countries pco on pco.id=p.country_id
    left join lateral (
      select cp.subdivision_id
      from catalogue.course_campuses cc
      join catalogue.campuses cp on cp.id=cc.campus_id
      where cc.course_id=c.id and cp.subdivision_id is not null
      order by coalesce(cc.is_primary,false) desc
      limit 1
    ) camp on true
    where c.id=p_entity_id;
    if v_course is null then return '{}'::jsonb; end if;

    select count(*) into v_outcome_count
    from catalogue.provider_outcomes po
    where po.provider_id=v_provider and coalesce(po.status,'current') in ('active','current')
      and (po.study_level_id is null or v_level is null or po.study_level_id=v_level);

    select coalesce(jsonb_agg(to_jsonb(x) order by x.level_match desc,x.collection_year_to desc nulls last,x.metric_name),'[]'::jsonb)
    into v_outcomes
    from (
      select
        po.id,
        coalesce(os.source_family,case when v_country_code='AU' then 'QILT' else 'outcomes' end) source_family,
        coalesce(os.name,os.code,'Student outcomes') source_label,
        om.name metric_name,om.code metric_code,om.unit,po.metric_value,po.national_benchmark,po.response_count,
        po.audience,po.collection_year_from,po.collection_year_to,esa.name study_area,sl.name study_level,
        po.status,po.observed_at,po.evidence_id,
        case when po.study_level_id=v_level then true else false end level_match,
        'provider_context'::text granularity
      from catalogue.provider_outcomes po
      left join ref.outcome_surveys os on os.id=po.survey_id
      left join ref.outcome_metrics om on om.id=po.metric_id
      left join ref.external_study_areas esa on esa.id=po.external_study_area_id
      left join ref.study_levels sl on sl.id=po.study_level_id
      where po.provider_id=v_provider and coalesce(po.status,'current') in ('active','current')
        and (po.study_level_id is null or v_level is null or po.study_level_id=v_level)
      order by (po.study_level_id=v_level) desc,po.collection_year_to desc nulls last,po.observed_at desc nulls last,om.name
      limit 10
    ) x;

    select count(*) into v_flow_direct_count
    from catalogue.student_flow_observations sf
    where sf.course_id=v_course and coalesce(sf.status,'current') in ('active','current');

    if v_flow_direct_count>0 then
      v_flow_state:='direct_course';
      v_flow_granularity:='course';
      select coalesce(jsonb_agg(to_jsonb(x) order by x.period_end desc nulls last,x.metric_value desc nulls last),'[]'::jsonb)
      into v_flow
      from (
        select sf.id,coalesce(os.source_family,case when v_country_code='AU' then 'PRISMS' else 'student_flow' end) source_family,
               coalesce(os.name,os.code,'International student flow') source_label,om.name metric_name,om.code metric_code,
               sf.metric_value,sf.period_start,sf.period_end,sf.period_type,sd.name subdivision,esa.name study_area,
               sf.source_nationality_name nationality,sf.is_suppressed,sf.suppression_code,sf.status,sf.observed_at,sf.evidence_id,
               'course'::text granularity
        from catalogue.student_flow_observations sf
        left join ref.outcome_surveys os on os.id=sf.survey_id
        left join ref.outcome_metrics om on om.id=sf.metric_id
        left join ref.subdivisions sd on sd.id=sf.subdivision_id
        left join ref.external_study_areas esa on esa.id=sf.external_study_area_id
        where sf.course_id=v_course and coalesce(sf.status,'current') in ('active','current')
        order by sf.period_end desc nulls last,sf.metric_value desc nulls last
        limit 10
      ) x;
    else
      select count(*) into v_flow_context_count
      from catalogue.student_flow_observations sf
      where coalesce(sf.status,'current') in ('active','current')
        and sf.field_of_study_id=v_field
        and sf.subdivision_id in (
          select v_subdivision where v_subdivision is not null
          union
          select cp.subdivision_id from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id where cc.course_id=v_course and cp.subdivision_id is not null
        );
      if v_flow_context_count>0 then
        v_flow_state:='regional_field_context';
        v_flow_granularity:='regional_field';
        select coalesce(jsonb_agg(to_jsonb(x) order by x.period_end desc nulls last,x.metric_value desc nulls last),'[]'::jsonb)
        into v_flow
        from (
          select sf.id,coalesce(os.source_family,case when v_country_code='AU' then 'PRISMS' else 'student_flow' end) source_family,
                 coalesce(os.name,os.code,'International student flow') source_label,om.name metric_name,om.code metric_code,
                 sf.metric_value,sf.period_start,sf.period_end,sf.period_type,sd.name subdivision,esa.name study_area,
                 sf.source_nationality_name nationality,sf.is_suppressed,sf.suppression_code,sf.status,sf.observed_at,sf.evidence_id,
                 'regional_field_context'::text granularity
          from catalogue.student_flow_observations sf
          left join ref.outcome_surveys os on os.id=sf.survey_id
          left join ref.outcome_metrics om on om.id=sf.metric_id
          left join ref.subdivisions sd on sd.id=sf.subdivision_id
          left join ref.external_study_areas esa on esa.id=sf.external_study_area_id
          where coalesce(sf.status,'current') in ('active','current')
            and sf.field_of_study_id=v_field
            and sf.subdivision_id in (
              select v_subdivision where v_subdivision is not null
              union
              select cp.subdivision_id from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id where cc.course_id=v_course and cp.subdivision_id is not null
            )
          order by sf.period_end desc nulls last,sf.metric_value desc nulls last
          limit 10
        ) x;
      else
        v_flow_state:=case when v_country_code='AU' then 'not_mapped' else 'country_counterpart_not_available' end;
      end if;
    end if;

    select count(distinct s.id) into v_scholarship_count
    from scholarship.scholarships s
    where coalesce(s.lifecycle_status,'active')='active'
      and exists (
        select 1 from scholarship.scopes inc
        where inc.scholarship_id=s.id and coalesce(inc.include_exclude,'include')='include'
          and (
            inc.course_id=v_course
            or inc.provider_id=v_provider
            or (inc.study_level_id is not null and inc.study_level_id=v_level)
            or (inc.field_id is not null and inc.field_id=v_field)
            or (inc.country_id is not null and inc.country_id=v_country)
            or (inc.campus_id is not null and inc.campus_id in (select cc.campus_id from catalogue.course_campuses cc where cc.course_id=v_course))
          )
      )
      and not exists (
        select 1 from scholarship.scopes exc
        where exc.scholarship_id=s.id and exc.include_exclude='exclude'
          and (
            exc.course_id=v_course
            or exc.provider_id=v_provider
            or (exc.study_level_id is not null and exc.study_level_id=v_level)
            or (exc.field_id is not null and exc.field_id=v_field)
            or (exc.country_id is not null and exc.country_id=v_country)
            or (exc.campus_id is not null and exc.campus_id in (select cc.campus_id from catalogue.course_campuses cc where cc.course_id=v_course))
          )
      );

    select coalesce(jsonb_agg(to_jsonb(x) order by x.application_close_date nulls last,x.name),'[]'::jsonb)
    into v_scholarships
    from (
      select distinct on(s.id)
        s.id,s.name,s.scholarship_type,s.audience,s.award_value_text,s.academic_year,
        s.application_required,s.application_open_date,s.application_close_date,
        s.lifecycle_status,s.publication_status,s.source_url,s.evidence_id,
        case
          when exists(select 1 from scholarship.scopes z where z.scholarship_id=s.id and z.course_id=v_course and coalesce(z.include_exclude,'include')='include') then 'course_scope'
          when exists(select 1 from scholarship.scopes z where z.scholarship_id=s.id and z.provider_id=v_provider and coalesce(z.include_exclude,'include')='include') then 'provider_scope'
          when exists(select 1 from scholarship.scopes z where z.scholarship_id=s.id and z.study_level_id=v_level and coalesce(z.include_exclude,'include')='include') then 'study_level_scope'
          when exists(select 1 from scholarship.scopes z where z.scholarship_id=s.id and z.field_id=v_field and coalesce(z.include_exclude,'include')='include') then 'field_scope'
          else 'broader_scope'
        end relationship,
        case
          when exists(select 1 from scholarship.scopes z where z.scholarship_id=s.id and z.course_id=v_course and coalesce(z.include_exclude,'include')='include') then 'course'
          else 'contextual_eligibility'
        end granularity
      from scholarship.scholarships s
      where coalesce(s.lifecycle_status,'active')='active'
        and exists (
          select 1 from scholarship.scopes inc
          where inc.scholarship_id=s.id and coalesce(inc.include_exclude,'include')='include'
            and (
              inc.course_id=v_course or inc.provider_id=v_provider
              or (inc.study_level_id is not null and inc.study_level_id=v_level)
              or (inc.field_id is not null and inc.field_id=v_field)
              or (inc.country_id is not null and inc.country_id=v_country)
              or (inc.campus_id is not null and inc.campus_id in (select cc.campus_id from catalogue.course_campuses cc where cc.course_id=v_course))
            )
        )
        and not exists (
          select 1 from scholarship.scopes exc
          where exc.scholarship_id=s.id and exc.include_exclude='exclude'
            and (
              exc.course_id=v_course or exc.provider_id=v_provider
              or (exc.study_level_id is not null and exc.study_level_id=v_level)
              or (exc.field_id is not null and exc.field_id=v_field)
              or (exc.country_id is not null and exc.country_id=v_country)
              or (exc.campus_id is not null and exc.campus_id in (select cc.campus_id from catalogue.course_campuses cc where cc.course_id=v_course))
            )
        )
      order by s.id,s.application_close_date nulls last
      limit 10
    ) x;
  else
    raise exception 'unsupported contextual entity type' using errcode='22023';
  end if;

  return jsonb_build_object(
    'country_code',v_country_code,
    'student_outcomes',jsonb_build_object(
      'semantic_group','student_outcomes',
      'source_label',case when v_country_code='AU' then 'QILT' else 'Country outcomes / benchmark source' end,
      'relationship_state',case when v_outcome_count>0 then 'available' else case when v_country_code='AU' then 'not_mapped' else 'country_counterpart_not_available' end end,
      'granularity',case when p_entity_type='provider' then 'provider' else 'provider_context' end,
      'total',v_outcome_count,
      'items',v_outcomes
    ),
    'student_flow',jsonb_build_object(
      'semantic_group','international_student_flow',
      'source_label',case when v_country_code='AU' then 'PRISMS' else 'Country student-flow source' end,
      'relationship_state',v_flow_state,
      'granularity',v_flow_granularity,
      'direct_total',v_flow_direct_count,
      'context_total',v_flow_context_count,
      'items',v_flow
    ),
    'scholarships',jsonb_build_object(
      'semantic_group','scholarships_funding',
      'source_label','Scholarships',
      'relationship_state',case when v_scholarship_count>0 then 'available' else 'none_related' end,
      'granularity',case when p_entity_type='provider' then 'provider' else 'governed_scope' end,
      'total',v_scholarship_count,
      'items',v_scholarships
    ),
    'authority_note','Context only. Provider/regional statistics are not Course facts and do not authorise Search or Publication mutation.'
  );
end $function$
;

revoke all on function security.admin_contextual_insights(text,uuid) from public,anon;
grant execute on function security.admin_contextual_insights(text,uuid) to authenticated,service_role;

CREATE OR REPLACE FUNCTION public.admin_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'security'
AS $function$
declare v_result jsonb;v_id uuid;begin
 if p_operation='admin_filter_option_page' then return security.admin_filter_option_page(p_args); end if;
 if p_operation='dashboard' then return security.admin_dashboard_maturity(); end if;
 if p_operation='catalogue_filter_page' then return security.admin_catalogue_filter_page(p_args); end if;
 if p_operation in ('provider_filters','course_filters') then return security.admin_catalogue_filter_options(p_operation,p_args); end if;
 if p_operation in ('evidence_page','evidence_filters','evidence_detail','evidence_observations','evidence_entities') then return security.admin_evidence_read(p_operation,p_args); end if;
 if p_operation='courses_page' then return security.admin_course_page_fast(p_args); end if;
 if p_operation in ('providers_page','campuses_page','scholarships_page') then return security.admin_catalogue_page(p_operation,p_args); end if;
 if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then return security.admin_insights_read(p_operation,p_args); end if;
 if p_operation='reviews_page' then return security.admin_operational_page(p_operation,p_args); end if;
 if p_operation in ('reviews','jobs','sources') then return security.admin_operations_read(p_operation,p_args); end if;
 if p_operation='layer1_operations' then return security.admin_layer1_operations_read(p_args); end if;
 if p_operation='layer2_ops_alerts' then return security.layer2_operational_alerts_read(); end if;
 if p_operation in ('layer2_ops_overview','layer2_ops_run_detail') then return security.admin_layer2_ops_read(p_operation,p_args); end if;
 if p_operation in ('layer2_profiles','layer2_profile_detail') then return security.admin_layer2_config_read(p_operation,p_args); end if;
 if p_operation in ('layer2_acquisition_providers','layer2_provider_routes','layer2_provider_attempts') then return security.admin_layer2_provider_read(p_operation,p_args); end if;
 if p_operation='attributes' then return security.admin_pim_governance_read(p_args); end if;
 if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then v_result:=security.admin_pipeline_ops_read(p_operation,p_args);return security.admin_pipeline_ops_sanitise_result(p_operation,v_result);end if;
 if p_operation in ('data_quality_overview','data_quality_exceptions') then return security.admin_data_quality_read(p_operation,p_args); end if;
 if p_operation='publication_overview' then return security.admin_publication_overview(); end if;
 if p_operation='provider_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_provider_detail(v_id)||jsonb_build_object('contextual_insights',security.admin_contextual_insights('provider',v_id));end if;
 if p_operation='campus_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_campus_detail(v_id);end if;
 v_result:=security.admin_read_impl(p_operation,p_args);
 if p_operation='course_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))||jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))||jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id))||jsonb_build_object('state_summary',security.admin_course_state_summary(v_id))||jsonb_build_object('contextual_insights',security.admin_contextual_insights('course',v_id));end if;
 if p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));end if;
 return v_result;
end$function$
;

revoke all on function public.admin_read(text,jsonb) from public,anon;
grant execute on function public.admin_read(text,jsonb) to authenticated,service_role;

commit;
