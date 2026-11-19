-- CF-247 Compare: in course mode PRISMS showed nothing for most courses. The course branch of
-- security.admin_contextual_insights looked only for course-level rows, then rows matching the course's field
-- AND state, and otherwise returned not_mapped, while the provider branch falls back to the provider's state.
-- Course mode now falls back to the state of the course's campuses (or its provider's campuses), labelled
-- regional_context, the same grain the provider view shows. Course-level and field-and-state rows still come
-- first. Admin read only; not part of the consumer API. Checksum-guarded; the provider branch is untouched.
do $patch$
declare v_def text; v_anchor text; v_new text; v_mark text; v_pos int; v_head text; v_tail text;
begin
  v_def:=pg_get_functiondef('security.admin_contextual_insights(text,uuid)'::regprocedure);
  if md5(v_def)<>'4ddb5b136f74fdd746809b675b8b93d8' then
    raise exception 'security.admin_contextual_insights changed since review; not replaced'; end if;
  v_mark:='''regional_field_context''::text granularity';
  v_pos:=strpos(v_def,v_mark);
  if v_pos=0 then raise exception 'course branch marker not found'; end if;
  v_head:=substr(v_def,1,v_pos-1); v_tail:=substr(v_def,v_pos);
  v_anchor:=E'      else\n        v_flow_state:=case when v_country_code=''AU'' then ''not_mapped'' else ''country_counterpart_not_available'' end;\n      end if;';
  if (length(v_tail)-length(replace(v_tail,v_anchor,'')))/length(v_anchor)<>1 then
    raise exception 'course fallback anchor not found exactly once'; end if;
  v_new:=E'      else
        select count(*) into v_flow_context_count
        from catalogue.student_flow_observations sf
        where coalesce(sf.status,''current'') in (''active'',''current'')
            and sf.subdivision_id in (
              select v_subdivision where v_subdivision is not null
              union
              select cp.subdivision_id from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id where cc.course_id=v_course and cp.subdivision_id is not null
              union
              select cp.subdivision_id from catalogue.campuses cp where cp.provider_id=v_provider and cp.subdivision_id is not null
            );
        select coalesce(jsonb_agg(to_jsonb(x) order by x.period_end desc nulls last,x.metric_value desc nulls last),''[]''::jsonb)
        into v_flow
        from (
          select sf.id,coalesce(os.source_family,case when v_country_code=''AU'' then ''PRISMS'' else ''student_flow'' end) source_family,
                 coalesce(os.name,os.code,''International student flow'') source_label,om.name metric_name,om.code metric_code,
                 sf.metric_value,sf.period_start,sf.period_end,sf.period_type,sd.name subdivision,esa.name study_area,
                 sf.source_nationality_name nationality,sf.is_suppressed,sf.suppression_code,sf.status,sf.observed_at,sf.evidence_id,
                 ''regional_context''::text granularity
          from catalogue.student_flow_observations sf
          left join ref.outcome_surveys os on os.id=sf.survey_id
          left join ref.outcome_metrics om on om.id=sf.metric_id
          left join ref.subdivisions sd on sd.id=sf.subdivision_id
          left join ref.external_study_areas esa on esa.id=sf.external_study_area_id
          where coalesce(sf.status,''current'') in (''active'',''current'')
            and sf.subdivision_id in (
              select v_subdivision where v_subdivision is not null
              union
              select cp.subdivision_id from catalogue.course_campuses cc join catalogue.campuses cp on cp.id=cc.campus_id where cc.course_id=v_course and cp.subdivision_id is not null
              union
              select cp.subdivision_id from catalogue.campuses cp where cp.provider_id=v_provider and cp.subdivision_id is not null
            )
          order by sf.period_end desc nulls last,sf.metric_value desc nulls last
          limit 10
        ) x;
        if v_flow_context_count>0 then
          v_flow_state:=''regional_context'';
          v_flow_granularity:=''regional'';
        else
          v_flow_state:=case when v_country_code=''AU'' then ''not_mapped'' else ''country_counterpart_not_available'' end;
        end if;
      end if;';
  execute v_head||replace(v_tail,v_anchor,v_new);
end $patch$;
