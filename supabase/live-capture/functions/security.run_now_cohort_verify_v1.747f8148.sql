CREATE OR REPLACE FUNCTION security.run_now_cohort_verify_v1(p_cohort uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c pipeline.run_now_cohorts%rowtype; m record; v_rows jsonb := '[]'; v_course jsonb; v_web jsonb; v_zoho jsonb; v_added jsonb; v_after jsonb;
        t_sel int := 0; t_elig int := 0; t_adm int := 0; t_pub int := 0; t_zoho int := 0; t_wrong int := 0; v_n int; v_p int; v_w int;
begin
  select * into c from pipeline.run_now_cohorts where id = p_cohort;
  if c.id is null then raise exception 'unknown cohort'; end if;
  for m in select * from pipeline.run_now_cohort_members where cohort_id = p_cohort order by pick loop
    t_sel := t_sel + 1;
    t_elig := t_elig + jsonb_array_length(m.evidence);
    -- values filled for this course since the cohort was picked, with the evidence the job recorded
    select coalesce(jsonb_agg(jsonb_build_object('intake_id', d.intake_id, 'before', d.before_value, 'after', d.after_value, 'periods', d.periods,
                     'page_quote', d.page_quote, 'start_quote', d.start_quote, 'deadline_quote', d.deadline_quote, 'calendar_url', d.calendar_url, 'applied_at', d.applied_at,
                     'as_planned', d.after_value = coalesce(d.before_value, '{}') || jsonb_strip_nulls((select e->'planned' from jsonb_array_elements(m.evidence) e where (e->>'intake_id')::uuid = d.intake_id)))
                     order by d.intake_id), '[]'), count(*)
      into v_added, v_n
      from pipeline.course_intake_dates d where d.course_id = m.course_id and d.outcome = 'filled' and d.applied_at >= c.created_at;
    select coalesce(jsonb_agg(jsonb_build_object('intake_id', i.id, 'label', i.intake_label, 'year', i.intake_year, 'start_date', i.start_date,
                     'application_deadline', i.application_deadline, 'status', i.status) order by i.id), '[]')
      into v_after from catalogue.course_intakes i where i.id in (select (e->>'intake_id')::uuid from jsonb_array_elements(m.evidence) e);
    begin v_web := api.website_v2_course_item(m.course_id) -> 'intakes'; exception when others then v_web := jsonb_build_object('error', sqlerrm); end;
    begin v_zoho := public.zoho_edge_course_lookup_v1(m.course_id::text); exception when others then v_zoho := jsonb_build_object('error', sqlerrm); end;
    -- a filled value is published when the website returns an intake with the same start date (or the same year where no date was filled)
    select count(*) filter (where exists (select 1 from jsonb_array_elements(case when jsonb_typeof(v_web) = 'array' then v_web else '[]' end) w
                                           where (a->'after'->>'start_date' is not null and w->>'start_date' = a->'after'->>'start_date')
                                              or (a->'after'->>'start_date' is null and w->>'year' = a->'after'->>'year'))),
           count(*) filter (where not coalesce((a->>'as_planned')::boolean, false))
      into v_p, v_w from jsonb_array_elements(v_added) a;
    t_adm := t_adm + v_n; t_pub := t_pub + v_p; t_wrong := t_wrong + v_w;
    if v_zoho ? 'error' is false and v_zoho is not null then t_zoho := t_zoho + 1; end if;
    v_rows := v_rows || jsonb_build_array(jsonb_build_object('pick', m.pick, 'course_id', m.course_id, 'provider_id', m.provider_id, 'pattern', m.pattern, 'fills', m.fills,
      'at_selection', m.evidence, 'now', v_after, 'added', v_added, 'admitted', v_n, 'published', v_p, 'not_as_planned', v_w,
      'website_intakes', v_web, 'zoho_intakes', coalesce(v_zoho->'intakes', v_zoho->'course'->'intakes', case when v_zoho ? 'error' then v_zoho end, to_jsonb('no intake field'::text))));
  end loop;
  return jsonb_build_object('cohort_id', c.id, 'job', c.job, 'label', c.label, 'rule', c.selection_rule, 'picked_at', c.created_at, 'selection', c.selection,
    'totals', jsonb_build_object('selected', t_sel, 'eligible_values', t_elig, 'admitted', t_adm, 'published', t_pub, 'not_as_planned', t_wrong, 'zoho_checked', t_zoho,
      'skipped_or_failed', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select d.outcome || coalesce(': ' || d.reason, '') k, count(*) n
                            from pipeline.course_intake_dates d join pipeline.run_now_cohort_members mm on mm.course_id = d.course_id and mm.cohort_id = c.id
                           where d.outcome <> 'filled' and d.applied_at >= c.created_at group by 1) x),
      'vendor_calls', (select coalesce(sum((j.result->>'vendor_calls')::int), 0) from pipeline.admin_jobs j where j.kind = 'job_run_now' and j.args->>'cohort_id' = c.id::text)),
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('run_id', j.id, 'state', j.state, 'reason', j.reason, 'started_at', j.started_at, 'finished_at', j.finished_at,
                     'processed', j.result->'processed', 'admitted', j.result->'admitted', 'skipped', j.result->'skipped', 'failed', j.result->'failed', 'refused', j.result->'refused')
                     order by j.created_at), '[]') from pipeline.admin_jobs j where j.kind = 'job_run_now' and j.args->>'cohort_id' = c.id::text),
    'courses', v_rows);
end $function$
