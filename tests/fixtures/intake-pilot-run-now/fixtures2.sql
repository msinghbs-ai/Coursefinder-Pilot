-- Run now cases, part 2 (after run.sh has shown a concurrent run is refused): the run, the record, the read-back, the scheduler unchanged.
\set ON_ERROR_STOP 1
do $$
declare c uuid := (select (v #>> '{}')::uuid from public.fixture_run_now where k = 'cohort'); v jsonb; w jsonb; j pipeline.admin_jobs%rowtype; n int;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.u('admin')::text, true);
  v := public.admin_job_run_now_v1('intake-dates-apply', 'fixture: immediate validation', jsonb_build_object('cohort_id', c, 'idempotency_key', 'k1'));
  perform pg_temp.ok(v->>'state' = 'done' and (v->>'admitted')::int = 4 and (v->>'processed')::int = 4 and (v->>'skipped')::int = 0 and (v->>'failed')::int = 0
                     and (v->>'vendor_calls')::int = 0 and (v->>'bounded')::boolean, 'the run: ' || v::text);
  select * into j from pipeline.admin_jobs where id = (v->>'run_id')::uuid;
  perform pg_temp.ok(j.kind = 'job_run_now' and j.requested_by = pg_temp.u('admin') and j.reason = 'fixture: immediate validation' and j.started_at is not null
                     and j.finished_at >= j.started_at and j.scope = 'cohort:' || c and (j.result->>'admitted')::int = 4, 'the record: requester, reason, start, finish, counts');
  perform pg_temp.ok((select count(*) from pipeline.admin_control_events where area = 'run_now' and action = 'ran') = 1, 'audited');
  perform pg_temp.ok((pg_temp.row('rn h1', 'March')).start_date = make_date(pg_temp.y(1), 3, 1) and (pg_temp.row('rn h1', 'March')).intake_year = pg_temp.y(1)
                     and (pg_temp.row('rn h1', 'March')).application_deadline = make_date(pg_temp.y(0), 11, 30), 'harbour: year, start date and deadline from the calendar');
  perform pg_temp.ok((pg_temp.row('rn b1', 'March')).start_date = make_date(pg_temp.y(1), 3, 2), 'bay: start date from the stored quote');
  perform pg_temp.ok((pg_temp.row('rn h3', 'July')).start_date is null and (pg_temp.row('rn lock', 'March')).start_date is null, 'outside the cohort: untouched; the lock held');
  perform pg_temp.ok((select course_ids from public.fixture_refresh_calls order by at desc limit 1) <@ array(select course_id from pipeline.run_now_cohort_members where cohort_id = c),
                     'the job''s own publication refresh, for cohort courses only');
  -- a repeat with the same key returns the same run
  w := public.admin_job_run_now_v1('intake-dates-apply', 'retry', jsonb_build_object('cohort_id', c, 'idempotency_key', 'k1'));
  perform pg_temp.ok(w->>'run_id' = v->>'run_id' and (w->>'repeat')::boolean, 'idempotency key: the earlier run');
  -- the projection the scheduled refresh runs, as the intake-dates fixture does
  perform search.refresh_course_enrichment_core_scoped_v1(array(select course_id from pipeline.run_now_cohort_members where cohort_id = c), false);
  update search.course_documents d set intake_options = s.intake_options, earliest_intake_date = s.earliest_intake_date, has_intake = (jsonb_array_length(s.intake_options) > 0)
    from cf_search_enrichment_stage s where d.course_id = s.course_id;
  w := security.run_now_cohort_verify_v1(c);
  perform pg_temp.ok((w->'totals'->>'selected')::int = 4 and (w->'totals'->>'eligible_values')::int = 4 and (w->'totals'->>'admitted')::int = 4
                     and (w->'totals'->>'published')::int = 4 and (w->'totals'->>'not_as_planned')::int = 0 and (w->'totals'->>'vendor_calls')::int = 0
                     and (w->'totals'->>'zoho_checked')::int = 0, 'verification totals: ' || (w->'totals')::text);
  perform pg_temp.ok((select bool_and(jsonb_array_length(x->'added') = 1 and x->'added'->0->>'start_quote' is not null and x->'added'->0->>'page_quote' <> ''
                        and jsonb_array_length(x->'website_intakes') = 1 and x->>'zoho_intakes' like '%Zoho not connected%') from jsonb_array_elements(w->'courses') x),
                     'per course: the value added, its quotes, the website read-back; Zoho reported when it does not answer');
  perform pg_temp.ok(jsonb_array_length(w->'runs') = 6, 'every Run now of the cohort is listed (five refused for it, one done)');
  raise notice 'PASS run: four courses filled through the job''s own function and publication path; record, idempotency, read-back and totals';
  -- the scheduled job: no selector, as before; it takes the rest, the cohort is not looked at again
  v := security.intake_dates_apply_v1(security.pipeline_num_v1('batch.intake_dates_apply', 200)::int);
  perform pg_temp.ok((v->>'filled')::int = 1 and not (v->>'bounded')::boolean and (pg_temp.row('rn h3', 'July')).start_date = make_date(pg_temp.y(1), 7, 26), 'the scheduled job unchanged: ' || v::text);
  v := security.job_run_now_v1('intake-dates-apply', 'again', jsonb_build_object('cohort_id', c), pg_temp.u('admin'));
  perform pg_temp.ok((v->>'processed')::int = 0 and (v->>'admitted')::int = 0, 'a second Run now finds nothing left: ' || v::text);
  raise notice 'PASS scheduled job unchanged in behaviour; nothing is filled twice';
end $$;
