-- Guards: Platform Admin decision 5 Nov 2026 16:36 §8: the run history the Automation Progress screen is tested on, written the way production
-- writes it: one decision row per intake row per run in pipeline.course_intake_date_events (the live failure-class trigger classifies each from its
-- reason, as security.intake_dates_apply_v1 leaves it), the current state in pipeline.course_intake_dates (same trigger and checks), the
-- intake-dates-apply cron runs, the hourly process-results measurements and one open integration issue. Times are relative to now().
set client_min_messages = warning;
create or replace function fx.decide(p_k text, p_n int, p_month text, p_outcome text, p_reason text, p_at timestamptz, p_bounded boolean default false,
                                     p_pub text default null, p_revisit timestamptz default null) returns void language plpgsql as $$
declare v_i uuid := fx.id('i:' || p_k || ':' || p_n || ':' || p_month); v_c uuid := fx.id('c:' || p_k || ':' || p_n); v_p uuid := fx.id('p:' || p_k);
        v_filled boolean := p_outcome = 'filled'; v_after jsonb := case when p_outcome = 'filled' then jsonb_build_object('year', 2027, 'start_date', '2027-02-15') end;
        v_next text := case when p_outcome = 'filled' then 'complete' when p_outcome = 'withdrawn' then 'human_decision_required' else 'evidence_ambiguous' end;
begin
  insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, run_at, rule, outcome, reason, next_action, next_revisit_at, calendar_set, before_value, after_value,
                                                 page_quote, start_quote, calendar_url, bounded, publication_state, publication_checked_at)
  values (v_i, v_c, v_p, p_at, 'calendar-v3', p_outcome, p_reason, v_next, p_revisit, 'set:' || p_k || ':v2.1', jsonb_build_object('year', 2027),
          v_after, case when p_reason is null or p_reason not like 'page not proved%' then 'Intakes: ' || p_month end,
          case when v_filled then 'Term 1 2027 | 15 February' end, 'https://example.edu.au/' || p_k || '/key-dates', p_bounded, p_pub, case when p_pub is not null then p_at end);
  insert into pipeline.course_intake_dates(intake_id, course_id, provider_id, outcome, reason, applied_at, rule, calendar_set, inputs_fp, next_action, next_revisit_at,
                                           before_value, after_value, calendar_url, publication_state, publication_checked_at)
  values (v_i, v_c, v_p, case when p_outcome = 'withdrawn' then 'skipped' else p_outcome end, p_reason, p_at, 'calendar-v3', 'set:' || p_k || ':v2.1', md5(p_k || p_n || p_month), v_next,
          p_revisit, jsonb_build_object('year', 2027), v_after, 'https://example.edu.au/' || p_k || '/key-dates', p_pub, case when p_pub is not null then p_at end)
  on conflict (intake_id) do update set outcome = excluded.outcome, reason = excluded.reason, applied_at = excluded.applied_at, next_action = excluded.next_action,
    next_revisit_at = excluded.next_revisit_at, after_value = excluded.after_value, publication_state = excluded.publication_state, publication_checked_at = excluded.publication_checked_at;
  if p_outcome = 'filled' then update catalogue.course_intakes set start_date = '2027-02-15' where id = v_i; end if;
  if p_outcome = 'withdrawn' then update catalogue.course_intakes set start_date = null where id = v_i; end if;
end $$;

create table if not exists fx.t(k text primary key, at timestamptz);
insert into fx.t values ('O', now() - interval '10 days'), ('S', now() - interval '3 days'), ('A', now() - interval '150 minutes'), ('R', now() - interval '120 minutes'),
  ('W', now() - interval '100 minutes'), ('B', now() - interval '90 minutes'), ('C', now() - interval '30 minutes') on conflict (k) do update set at = excluded.at;
create or replace function fx.at(p text) returns timestamptz language sql stable as $$ select at from fx.t where k = p $$;

do $$
declare n int; v_id text := 'page not proved to be the course''s own (E16 refuse)'; v_np text := 'the course page names no study period of the calendar (month only)';
begin
  -- O: ten days ago (only in the 30-day window)
  perform fx.decide('melbourne', 3, 'February', 'filled', null, fx.at('O'), false, 'published');
  perform fx.decide('auckland', 1, 'February', 'skipped', 'no valid academic calendar', fx.at('O'));
  -- S: three days ago
  perform fx.decide('unsw', 15, 'February', 'filled', null, fx.at('S'), false, 'published');
  perform fx.decide('adelaide', 1, 'February', 'skipped', v_id, fx.at('S'), false, null, fx.at('S') + interval '14 days');
  -- A: scheduled
  for n in 11 .. 14 loop perform fx.decide('unsw', n, 'February', 'skipped', v_np, fx.at('A')); end loop;
  -- R: governed Run Now (bounded) for Newcastle
  perform fx.decide('newcastle', 1, 'February', 'filled', null, fx.at('R'), true, 'published');
  -- W: a governed withdrawal of the earlier UNSW value
  perform fx.decide('unsw', 15, 'February', 'withdrawn', 'withdrawn: fixture course offering not supported by course-specific evidence', fx.at('W'));
  -- B: scheduled
  for n in 7 .. 10 loop perform fx.decide('unsw', n, 'February', 'skipped', v_id, fx.at('B'), false, null, fx.at('B') + interval '14 days'); end loop;
  perform fx.decide('monash', 1, 'February', 'filled', null, fx.at('B'), false, 'published');
  -- C: the latest scheduled run
  for n in 1 .. 3 loop perform fx.decide('unsw', n, 'February', 'skipped', v_id, fx.at('C'), false, null, fx.at('C') + interval '14 days'); end loop;
  for n in 4 .. 6 loop perform fx.decide('unsw', n, 'February', 'skipped', v_np, fx.at('C')); end loop;
  perform fx.decide('melbourne', 1, 'February', 'filled', null, fx.at('C'), false, 'published');
  perform fx.decide('melbourne', 2, 'February', 'skipped', 'the calendar does not print the year of its start in this month (month only)', fx.at('C'));
  perform fx.decide('sydney', 1, 'February', 'skipped', 'intakes locked by hand', fx.at('C'));
  perform fx.decide('sydney', 2, 'February', 'skipped', 'no stored reading of the page''s intake wording (month only)', fx.at('C'));
  perform fx.decide('torrens', 1, 'February', 'filled', null, fx.at('C'), false, 'consumer_publication_failed');
  perform fx.decide('torrens', 2, 'February', 'skipped', 'no valid academic calendar: the approved calendars are set aside (not the main teaching calendar)', fx.at('C'));
end $$;
update pipeline.course_intake_dates set failure_class = 'consumer_publication_failed', deterministic = false where publication_state = 'consumer_publication_failed';

-- the intake-dates-apply runs (pg_cron history) and the observer's last run
insert into cron.job_run_details(jobid, status, start_time, end_time, return_message, command)
select (select jobid from cron.job where jobname = 'intake-dates-apply'), 'succeeded', fx.at(k) - interval '1 second', fx.at(k) + interval '3 seconds', '2 rows', 'intake-dates-apply'
  from unnest(array['A', 'B', 'C']) k;
insert into cron.job_run_details(jobid, status, start_time, end_time, return_message)
values ((select jobid from cron.job where jobname = 'process-results'), 'succeeded', now() - interval '10 minutes', now() - interval '9 minutes', '1 row');

-- the hourly measurements process-results saves (the shape of security.process_results_intake_dates_v1 and _recovery_v1)
insert into pipeline.process_results(process_key, scope_key, measured_at, summary, measured_by)
select 'intake-dates', 'top-au', now() - make_interval(mins => m), jsonb_build_object('process', 'intake-dates', 'measured_at', now() - make_interval(mins => m),
  'universities', (select jsonb_agg(jsonb_build_object('provider_id', fx.id('p:' || k), 'university', k, 'never_examined', courses * 2 - 4,
                     'calendars_valid', case when k = 'sydney' and m = 70 then 1 else 2 end, 'ai_cost_usd_7_days', 0.0125) order by courses desc)
                     from fx.provider_keys where courses >= 21),
  'totals', jsonb_build_object('never_examined', (select sum(courses * 2 - 4) from fx.provider_keys where courses >= 21))), 'job process-results'
from unnest(array[70, 10]) m;
insert into pipeline.process_results(process_key, scope_key, measured_at, summary, measured_by)
values ('intake-recovery', 'top-au', now() - interval '10 minutes', '{"refresh": {"budget": 40, "credits_counted": 5, "credits_used": 5, "requests": []}}', 'job process-results');

-- an open integration issue naming the course whose admitted value is not published (shown beside that failure)
select security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'intake-dates:fixture-publication', 'title', 'Fixture: admitted intake not in the Website API source',
  'layer', 'Layer 2', 'subsystem', 'intake-dates', 'severity', 'P1', 'workstream', 'A8', 'validation_layer', 'V4', 'failure', 'fixture', 'expected', 'fixture',
  'course_ids', jsonb_build_array(fx.id('c:torrens:1')), 'provider_ids', jsonb_build_array(fx.id('p:torrens'))), 'fixture');
