-- With the switches off, the edited definitions behave as before (then the switches go back to their shipped values).
do $$
declare v_p uuid; v_j uuid; v_r uuid; v jsonb;
begin
  update pipeline.platform_toolset_settings set value = '0' where toolset_key = 'pipeline'
     and key in ('ops.outcome_on', 'plans.lane_backlog_wait_on', 'plans.retry_ignores_min_days', 'plans.empty_cycles_max');
  perform fx.reset3();
  v_j := fx.task3('enrich_fields', 'done', '{"cost_usd": 0}');
  perform fx.items(v_j, 2, 0);
  perform security.admin_job_close_v1(v_j);
  perform fx.ok(fx.outcome(v_j) is null, 'off: an ended task records no outcome, as before');

  v_p := fx.provider(false, null);
  v_j := fx.task3('scholarship_provider_scan', 'done', '{"done": 0, "total": 0}', v_p);
  v_r := fx.plan(v_p, 'running', jsonb_build_array(jsonb_build_object('step', 'scholarships', 'status', 'running', 'ref', jsonb_build_object('kind', 'job', 'id', v_j))));
  perform security.enrich_plan_tick_v1(v_r); perform security.enrich_plan_tick_v1(v_r);
  perform fx.ok((select actual->>'outcome' from pipeline.enrich_plan_runs where id = v_r) = 'moved' and fx.plan_outcome(v_r) is null,
                'off: a finished plan''s actual.outcome comes from step status, as before (moved), no outcome column');

  perform fx.reset3();
  v_p := fx.provider(false, null);
  insert into pipeline.course_link_search(course_id, provider_id, state, requested_at) select gen_random_uuid(), v_p, 'queued', now() from generate_series(1, 3);
  v_r := fx.plan(v_p, 'running', '[{"step": "pages", "group": "none", "status": "pending"}]');
  perform security.enrich_plan_tick_v1(v_r);
  perform fx.ok(exists (select 1 from fx.started where run = v_r and step = 'pages'), 'off: Find course pages starts with searches queued, as before');

  perform fx.reset3();
  v_p := fx.iq64();
  v := security.enrich_plan_auto_v1();
  perform fx.ok((v->>'started')::int = 0, 'off: the retry re-plan waits plans.replan_min_days, as before');
  perform fx.ok((select count(*) from pipeline.enrich_plan_auto_runs) = 1, 'off: the run is still recorded (it only records)');

  update pipeline.platform_toolset_settings set value = '1' where toolset_key = 'pipeline' and key in ('ops.outcome_on', 'plans.lane_backlog_wait_on', 'plans.retry_ignores_min_days');
  update pipeline.platform_toolset_settings set value = '3' where toolset_key = 'pipeline' and key = 'plans.empty_cycles_max';
end $$;
