CREATE OR REPLACE FUNCTION security.data_delivery_aer_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- data-delivery-aer-v1
declare v_max int := security.pipeline_num_v1('aer.schedule_layer4_max', 600)::int; -- derived: the limit the scheduled reading tests (same setting and default)
begin
  return (
  with pc as (select * from pipeline.aer_provider_coverage where eligible),
  cov as (select jsonb_build_object(
            'eligible', count(*), 'with_source', count(*) filter (where sources > 0), 'source_read', count(*) filter (where sources_read > 0),
            'with_active_rows', count(*) filter (where matrix_active > 0 or course_req_active > 0),
            'waiting_for_layer4', count(*) filter (where course_req_proposed > 0 or coalesce((layer4->>'matrix_pending')::int, 0) > 0 or coalesce((layer4->>'course_awaiting_review')::int, 0) > 0),
            'active_course_rows', coalesce(sum(course_req_active), 0), 'active_matrix_rows', coalesce(sum(matrix_active), 0),
            'proposed_course_rows', coalesce(sum(course_req_proposed), 0), 'counted_at', max(updated_at)) j from pc),
  bycc as (select coalesce(jsonb_agg(jsonb_build_object('cc', x.country, 'eligible', x.n, 'with_active_rows', x.a, 'with_source', x.s) order by x.country), '[]'::jsonb) j
             from (select country, count(*) n, count(*) filter (where matrix_active > 0 or course_req_active > 0) a, count(*) filter (where sources > 0) s from pc group by 1) x),
  disp as (select coalesce(jsonb_object_agg(x.disposition, x.n), '{}'::jsonb) j from (select disposition, count(*) n from pc group by 1) x),
  gaps as (select coalesce(jsonb_agg(jsonb_build_object('route', x.route, 'providers', x.n, 'courses_waiting', x.c, 'parked', x.p, 'example_reason', x.r, 'next_action', x.a) order by x.n desc), '[]'::jsonb) j
             from (select coalesce(f.evidence->>'route', 'not_classified') route, count(*) n, sum(coalesce((f.evidence->>'courses_waiting')::int, 0)) c,
                          bool_or(coalesce((f.evidence->>'parked')::boolean, false)) p, min(f.evidence->>'reason') r, min(f.evidence->>'next_action') a
                     from pipeline.aer_gap_findings f where f.root_cause = 'no_source' and f.state <> 'resolved' group by 1) x),
  other as (select coalesce(jsonb_agg(jsonb_build_object('cause', x.root_cause, 'findings', x.n) order by x.n desc), '[]'::jsonb) j
              from (select root_cause, count(*) n from pipeline.aer_gap_findings where state <> 'resolved' and root_cause <> 'no_source' group by 1) x),
  prk as (select coalesce(jsonb_agg(jsonb_build_object('class', x.failure_class, 'items', x.n, 'providers', x.pv, 'reason', x.r, 'next_action', x.a) order by x.n desc), '[]'::jsonb) j, coalesce(sum(x.n), 0) total
            from (select failure_class, count(*) n, count(distinct provider_id) pv, min(reason) r, min(next_action) a from security.aer_parked_items_v1() group by 1) x),
  lastrun as (select coalesce((select to_jsonb(x) from (select ran_at, course_reads, corrections, matrix_pages, layer4_waiting, in_progress, back_pressure, room, refusal, detail->'parked_not_counted' parked_not_counted
                                           from pipeline.aer_schedule_runs order by ran_at desc limit 1) x), '{}'::jsonb) j),
  jobs as (select coalesce(jsonb_agg(jsonb_build_object('job', c.jobname, 'active', c.active, 'schedule', c.schedule, 'next_run', case when c.active then security.cron_next_run_v1(c.schedule, now()) end) order by c.jobname), '[]'::jsonb) j
             from cron.job c where c.jobname in ('aer-scheduled-read', 'aer-source-stored-find', 'entry-matrix-read', 'aer-replay')),
  sf as (select jsonb_build_object('switch_on', security.pipeline_num_v1('aer.source_stored_find_on', 0) >= 1, 'providers_checked', count(*), 'sources_attached', coalesce(sum(attached), 0), 'last_checked_at', max(checked_at)) j,
                coalesce(security.pipeline_num_v1('aer.source_stored_find_on', 0) >= 1, false) on_ from pipeline.aer_source_stored_find),
  srcs as (select coalesce(jsonb_object_agg(x.status, x.n), '{}'::jsonb) j, coalesce(sum(x.n), 0) total from (select status, count(*) n from pipeline.entry_matrix_sources group by 1) x),
  rv as (select coalesce(jsonb_object_agg(x.readiness, x.n), '{}'::jsonb) j from (select readiness, count(*) n from pipeline.aer_review_readiness where settled_at is null group by 1) x),
  stored_waiting as (select coalesce(sum((g->>'providers')::int), 0) n from gaps, jsonb_array_elements(gaps.j) g where g->>'route' = 'source_page_stored'),
  blk as (select coalesce(jsonb_agg(v.t), '[]'::jsonb) j
            from lastrun, sf, stored_waiting, lateral (values
              (case when lastrun.j->>'refusal' is not null then 'Scheduled entry reading is refused: ' || (lastrun.j->>'refusal') end),
              (case when coalesce((lastrun.j->>'back_pressure')::boolean, false)
                    then 'Layer 4 is full for entry requirements: ' || (lastrun.j->>'layer4_waiting') || ' items waiting against the limit of ' || v_max || ' (parked holds not counted: ' || coalesce(lastrun.j->>'parked_not_counted', 'not counted by this run') || '); no new course read starts until decisions are made' end),
              (case when not sf.on_ and stored_waiting.n > 0 then stored_waiting.n || ' providers have a stored entry page that waits for the switch Entry pages from stored links' end)) v(t)
           where v.t is not null)
  select jsonb_build_object('known', true, 'counted_at', now(), 'unit', 'providers', 'coverage', cov.j, 'by_country', bycc.j, 'dispositions', disp.j,
           'sources', jsonb_build_object('total', srcs.total, 'by_status', srcs.j, 'stored_find', sf.j),
           'gaps', gaps.j, 'other_findings', other.j, 'parked', jsonb_build_object('items', prk.total, 'by_rule', prk.j),
           'layer4_readiness', rv.j, 'last_run', lastrun.j, 'jobs', jobs.j, 'blockers', blk.j)
    from cov, bycc, disp, gaps, other, prk, lastrun, jobs, sf, srcs, rv, blk);
exception when others then
  return jsonb_build_object('known', false, 'reason', left(sqlerrm, 200));
end $function$

