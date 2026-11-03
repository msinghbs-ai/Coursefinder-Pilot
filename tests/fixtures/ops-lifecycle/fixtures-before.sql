-- Before (the live v2.15.426 definitions): the defects workstream D removes, reproduced as seen live on 3 Nov 2026.
do $$
declare v_p uuid; v_j uuid; v_r uuid; v jsonb;
begin
  -- B1 the 12:41 plans: one "Find and read scholarships" step, its task done with total 0 and nothing found; reported as moving data
  perform fx.reset3();
  v_p := fx.provider(false, null);
  v_j := fx.task3('scholarship_provider_scan', 'done', '{"done": 0, "total": 0, "new_scholarships": 0, "became": 0, "links_changed": 0}', v_p);
  v_r := fx.plan(v_p, 'done', jsonb_build_array(jsonb_build_object('step', 'scholarships', 'status', 'done', 'ref', jsonb_build_object('kind', 'job', 'id', v_j))));
  v := security.plan_outcomes_v1();
  perform fx.ok((v->>'moved')::int = 1 and (v->>'no_movement')::int = 0, 'before: the 12:41 plan (scan of 0 of 0, nothing found) is reported as moved');
  perform fx.ok(security.plan_run_outcome_v1((select steps from pipeline.enrich_plan_runs where id = v_r)) = 'moved', 'before: plan_run_outcome_v1 reads "done" as moved');

  -- B2 a task that ends records no outcome (enrich_fields done, every item skipped)
  v_j := fx.task3('enrich_fields', 'done', '{"by_field": {"international": {"skipped": 10}}, "cost_usd": 0}');
  perform fx.items(v_j, 0, 10);
  perform security.admin_job_close_v1(v_j);
  perform fx.ok(fx.outcome(v_j) is null and (select count(*) from pipeline.jobs where payload->>'admin_job_id' = v_j::text) = 1, 'before: an ended task is mirrored but has no outcome');

  -- B3 IQ-00064: the failed Find course pages step is past its retry wait, but the planner reads retry inputs only after replan_min_days
  perform fx.reset3();
  v_p := fx.iq64();
  v := security.enrich_plan_auto_v1();
  perform fx.ok((v->>'started')::int = 0 and not exists (select 1 from pipeline.enrich_plan_runs where provider_id = v_p and state in ('queued', 'running')),
                'before IQ-00064: the retry re-plan does not fire 6.5 hours after the step failed (plans.replan_min_days 2)');
  perform fx.ok(to_regclass('pipeline.enrich_plan_auto_runs') is null and v = '{"auto": "on", "open": 0, "started": 0, "replanned": 0, "nothing_to_do": 0}'::jsonb,
                'before: an automatic run that creates nothing leaves no reason');

  -- B4 a new Find course pages step starts while the provider's searches are still queued (its task would queue them all again)
  perform fx.reset3();
  v_p := fx.provider(false, null);
  insert into pipeline.course_link_search(course_id, provider_id, state, requested_at) select gen_random_uuid(), v_p, 'queued', now() - interval '4 hours' from generate_series(1, 3);
  v_r := fx.plan(v_p, 'running', '[{"step": "pages", "group": "none", "status": "pending"}]');
  perform security.enrich_plan_tick_v1(v_r);
  perform fx.ok(exists (select 1 from fx.started where run = v_r and step = 'pages'), 'before: Find course pages starts with 3 of the provider''s searches still queued');
end $$;
