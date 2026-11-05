-- Guards: Platform Admin decision 5 Nov 2026 16:36 §8 (database-backed acceptance of the Automation Progress layer, isolated PostgreSQL only): counts
-- reconcile with the decision records, "Not processed" is distinct from "zero eligible", the four history windows, the failure list, role
-- restrictions, Pause/Resume through the existing job toggle and its audit, a running and a stalled job, and the observer's zero-yield routing
-- through the generic progress observer (decision 20:03: one condition, one fingerprint; nothing for expected absence of evidence). Each case prints PASS or raises.
\set ON_ERROR_STOP on
set client_min_messages = warning;
-- callers act as the authenticated role with a seeded identity of the given rank (as Supabase sets auth.uid())
create or replace function fx.v(p_rank int, p_view text, p_args jsonb default '{}') returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', fx.id('user:' || p_rank)::text, true);
  perform set_config('role', 'authenticated', true);
  begin r := public.admin_intake_progress_v1(p_view, p_args);
  exception when others then perform set_config('role', 'postgres', true); raise; end;
  perform set_config('role', 'postgres', true);
  return r;
end $$;
create or replace function fx.ctl(p_rank int, p_job text, p_action text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', fx.id('user:' || p_rank)::text, true);
  perform set_config('role', 'authenticated', true);
  begin r := public.admin_automation_control(p_job, p_action, jsonb_build_object('reason', 'Process results › Automation progress (fixture)'));
  exception when others then perform set_config('role', 'postgres', true); raise; end;
  perform set_config('role', 'postgres', true);
  return r;
end $$;
create or replace function fx.ok(p_cond boolean, p_msg text) returns text language plpgsql as $$
begin if p_cond is not true then raise exception 'FAIL %', p_msg; end if; return 'PASS ' || p_msg; end $$;

-- 1 the latest run's funnel reconciles with its decision rows
select fx.ok(f->>'selected' = (select count(*)::text from pipeline.course_intake_date_events where run_at = fx.at('C'))
   and (f->>'admitted')::int = (select count(*) from pipeline.course_intake_date_events where run_at = fx.at('C') and outcome = 'filled')
   and (f->>'published')::int = (select count(*) from pipeline.course_intake_date_events where run_at = fx.at('C') and publication_state = 'published')
   and (f->>'selected')::int = (f->>'admitted')::int + (f->>'nothing_new')::int + (f->>'refused_or_held')::int
   and (f->>'dates_validated')::int = 3 and (f->>'evidence_found')::int = (select count(*) from pipeline.course_intake_date_events where run_at = fx.at('C') and page_quote is not null),
   'latest run funnel: selected 12 = admitted + nothing new + refused or held; validated, published and evidence found equal the decision records')
from (select fx.v(3, 'window', '{"window":"latest"}')->'funnel' f) x;

-- 2 Not processed versus zero eligible (latest run): Newcastle was not selected; UNSW was selected and evaluated with nothing eligible
select fx.ok((select u->>'state' from jsonb_array_elements(w->'universities') u where u->>'university' = 'The University of Newcastle') = 'not_processed'
   and (select (u->>'selected')::int from jsonb_array_elements(w->'universities') u where u->>'university' = 'The University of Newcastle') = 0
   and (select (u->>'pending')::int from jsonb_array_elements(w->'universities') u where u->>'university' = 'The University of Newcastle') > 0
   and (select u->>'state' from jsonb_array_elements(w->'universities') u where u->>'university' = 'UNSW Sydney') = 'zero_eligible'
   and (select (u->>'selected')::int from jsonb_array_elements(w->'universities') u where u->>'university' = 'UNSW Sydney') = 6
   and (select u->>'state' from jsonb_array_elements(w->'universities') u where u->>'university' = 'The University of Sydney') = 'eligible_not_admitted'
   and (select u->>'state' from jsonb_array_elements(w->'universities') u where u->>'university' = 'The University of Melbourne') = 'admitted'
   and (select count(*) from jsonb_array_elements(w->'universities') u where (u->>'pilot')::boolean) = 10
   and exists (select 1 from jsonb_array_elements(w->'universities') u where u->>'university' = 'Torrens University Australia' and not (u->>'pilot')::boolean),
   'latest run: Newcastle not processed (0 selected, work pending), UNSW zero eligible (6 selected, 0 validated), Sydney eligible not admitted, Melbourne admitted; 10 pilot rows and the other processed provider')
from (select fx.v(3, 'window', '{"window":"latest"}') w) x;
-- the same university processed by a governed Run Now inside 24 hours is processed in that window
select fx.ok((select u->>'state' from jsonb_array_elements(fx.v(3, 'window', '{"window":"24h"}')->'universities') u where u->>'university' = 'The University of Newcastle') = 'admitted',
  '24 hours: Newcastle processed and admitted by the governed Run Now');

-- 3 history windows: each equals the decision records in its interval; net gain counts withdrawals; 30 days reaches the old run
select fx.ok((d->>'selected')::int = (select count(*) from pipeline.course_intake_date_events where run_at >= now() - interval '1 day' and outcome <> 'withdrawn')
   and (d->>'withdrawn')::int = 1 and (d->>'admitted')::int = 4 and (d->>'net_gain')::int = 3 and (d->>'runs')::int = 4 and (d->>'run_now_runs')::int = 1 and (d->>'withdrawal_actions')::int = 1,
   '24 hours: 4 runs (1 Run Now), 4 admitted, 1 withdrawn, net gain 3; selected equals the records')
from (select fx.v(3, 'window', '{"window":"24h"}')->'funnel' d) x;
select fx.ok((w->>'admitted')::int = 5 and (w->>'net_gain')::int = 4 and (m->>'admitted')::int = 6 and (m->>'net_gain')::int = 5
   and (m->>'selected')::int = (select count(*) from pipeline.course_intake_date_events where run_at >= now() - interval '30 days' and outcome <> 'withdrawn'),
   '7 days: 5 admitted, net 4 (the UNSW value admitted 3 days ago and withdrawn); 30 days: 6 admitted, net 5, including the run 10 days ago')
from (select fx.v(3, 'window', '{"window":"7d"}')->'funnel' w, fx.v(3, 'window', '{"window":"30d"}')->'funnel' m) x;
select fx.ok(jsonb_array_length(r) = 7 and r->0->>'kind' = 'scheduled' and (r->0->'cron_run'->>'runid') is not null
   and exists (select 1 from jsonb_array_elements(r) x where x->>'kind' = 'run_now') and exists (select 1 from jsonb_array_elements(r) x where x->>'kind' = 'withdrawal'),
   '30 days: seven runs listed newest first, scheduled ones with their pg_cron run id, a Run Now and a withdrawal')
from (select fx.v(3, 'runs', '{"window":"30d"}') r) x;

-- 4 failures: every held or failed row, its class, reason, evidence version, next action, issue and who acts
select fx.ok((f->>'total')::int = (select count(*) from pipeline.course_intake_dates where outcome <> 'filled' or failure_class is not null or publication_state = 'consumer_publication_failed')
   and (select r->'issue'->>'ref' from jsonb_array_elements(f->'rows') r where r->>'class' = 'consumer_publication_failed') = (select issue_ref from pipeline.integration_issues where fingerprint = 'intake-dates:fixture-publication')
   and (select bool_and(r ? 'evidence_version' and r ? 'last_attempt' and r ? 'next_action' and r ? 'auto_recover' and r ? 'person_required' and r->>'reason' is not null) from jsonb_array_elements(f->'rows') r)
   and (select (r->>'person_required')::boolean from jsonb_array_elements(f->'rows') r where r->>'class' = 'admission_held') is true
   and (select (r->>'auto_recover')::boolean from jsonb_array_elements(f->'rows') r where r->>'class' = 'course_identity_unresolved' limit 1) is true,
   'failures: total equals the held and failed rows; the unpublished value shows its open issue; a lock needs a person; identity rows recover on their revisit')
from (select fx.v(3, 'failures') f) x;
select fx.ok((select bool_and(r->>'class' = 'no_matching_commencement_period' and r->>'university' = 'UNSW Sydney') from jsonb_array_elements(f->'rows') r)
   and jsonb_array_length(f->'rows') = 7, 'failures filtered by class and university')
from (select fx.v(3, 'failures', jsonb_build_object('class', 'no_matching_commencement_period', 'provider_id', fx.id('p:unsw'))) f) x;

-- 5 role restrictions: below Operations read refused; Operations read sees no controls; the job's control rank decides Pause/Resume
do $$ begin perform fx.v(2, 'status'); raise exception 'FAIL rank 2 read'; exception when insufficient_privilege then null; end $$;
do $$ begin set local role authenticated; perform count(*) from pipeline.course_intake_date_events; raise exception 'FAIL direct table read'; exception when insufficient_privilege then reset role; end $$;
select fx.ok((fx.v(3, 'status')->'controls'->>'can_pause_resume')::boolean = false and (fx.v(4, 'status')->'controls'->>'can_pause_resume')::boolean = false
   and (fx.v(5, 'status')->'controls'->>'can_pause_resume')::boolean = true and (fx.v(3, 'status')->'controls'->>'can_run_now')::boolean = false,
   'roles: rank 2 refused, no direct table read; Curator and Pipeline Operator see no Pause/Resume; PIM Admin may (control rank 5)');

-- 6 Pause/Resume through the existing toggle and its audit
do $$ begin perform fx.ctl(4, 'intake-dates-apply', 'pause'); raise exception 'FAIL rank 4 pause'; exception when insufficient_privilege then null; end $$;
select fx.ok(fx.ctl(6, 'intake-dates-apply', 'pause') is not null, 'pause called through public.admin_automation_control as a Platform Admin');
select fx.ok(not (select active from cron.job where jobname = 'intake-dates-apply')
   and fx.v(3, 'status')->>'state' = 'paused'
   and exists (select 1 from pipeline.admin_control_events where area = 'automations' and action = 'pause' and target = 'intake-dates-apply' and actor = fx.id('user:6')),
   'pause: the existing admin_automation_control switches the job off, records the audit row with the actor, status shows paused');
select fx.ok(fx.ctl(6, 'intake-dates-apply', 'resume') is not null, 'resume called through public.admin_automation_control');
select fx.ok((select active from cron.job where jobname = 'intake-dates-apply')
   and fx.v(3, 'status')->>'state' = 'waiting'
   and (select count(*) from pipeline.admin_control_events where target = 'intake-dates-apply') = 2, 'resume: switched on again, audited, status waiting');

-- 7 running and stalled are distinct from a healthy idle job
begin;
insert into cron.job_run_details(jobid, status, start_time) values ((select jobid from cron.job where jobname = 'intake-dates-apply'), 'running', now() - interval '20 seconds');
select fx.ok(s->>'state' = 'running' and (s->>'running_run')::bigint = (select max(runid) from cron.job_run_details) and s->>'current_university' is not null,
  'running: the job shows its run id while the run is open') from (select fx.v(3, 'status') s) x;
rollback;
begin;
update cron.job_run_details set start_time = start_time - interval '3 hours', end_time = end_time - interval '3 hours';
select fx.ok(s->>'state' = 'stalled' and (select (a->>'tripped')::boolean from jsonb_array_elements(s->'alerts') a where a->>'code' = 'job_overdue'),
  'stalled: an active job whose last run is older than intake_progress.stall_minutes is shown stalled in the job alert') from (select fx.v(3, 'status') s) x;
rollback;

-- 8 the generic progress observer (job first-run-verify, security.progress_read_v1) now reads the intake chain; one condition raises one fingerprint
create temp table obs(n int, r jsonb);
insert into obs select 1, security.progress_read_v1();
select fx.ok((r->>'errors')::int = 0 and (select count(*) from pipeline.progress_observations where transition_key like 'intake%') = 3
   and (select output_admitted from pipeline.progress_transitions where key = 'intake_admission') = (select count(*) from pipeline.course_intake_date_events where outcome = 'filled' and run_at >= now() - interval '24 hours')
   and (select output_created from pipeline.progress_transitions where key = 'intake_selection') = (select count(*) from pipeline.course_intake_date_events where outcome <> 'withdrawn' and run_at >= now() - interval '24 hours')
   and not exists (select 1 from pipeline.progress_transitions where chain = 'intake' and stalled)
   and r->'intake'->>'publication_mismatch' is not null
   and (select count(*) from pipeline.integration_issues where fingerprint like 'intake-progress:%' or fingerprint like 'stall:intake%') = 1,
   'observer: the three intake transitions read with the decision records'' counts; nothing stalled; the partial publication mismatch raises intake-progress:publication-mismatch only')
  from obs where n = 1;
select fx.ok((select count(*) from jsonb_array_elements(fx.v(3, 'status')->'observer'->'transitions')) = 3
   and jsonb_array_length(fx.v(3, 'observations')) = 3, 'status and observations views show the observer''s intake readings');
-- zero yield: earlier work moved out of the window, then three scheduled runs admit nothing although a validated row is held and a reader failed
begin;
update pipeline.course_intake_date_events set run_at = run_at - interval '2 days';
update pipeline.course_intake_dates set applied_at = applied_at - interval '2 days', publication_checked_at = publication_checked_at - interval '2 days';
update pipeline.progress_transitions set last_advanced_at = last_advanced_at - interval '2 days' where chain = 'intake';  -- the same two days pass for the observer
do $$ declare k int; begin
  for k in 1 .. 3 loop
    perform fx.decide('flinders', k, 'February', 'skipped', 'intakes locked by hand', now() - make_interval(mins => 20 - k));
    perform fx.decide('flinders', k + 10, 'February', 'skipped', 'no stored reading of the page''s intake wording (month only)', now() - make_interval(mins => 20 - k));
  end loop; end $$;
insert into obs select 2, security.progress_read_v1();
select fx.ok((select stalled and zero_reason = 'technical_failure' from pipeline.progress_transitions where key = 'intake_admission')
   and (select count(*) from pipeline.integration_issues where fingerprint = 'stall:intake_admission' and layer = 'Layer 2' and workstream = 'A8') = 1
   and not exists (select 1 from pipeline.integration_issues where fingerprint in ('intake-progress:zero-yield', 'stall:intake_selection', 'stall:intake_publication')),
   'zero yield: raised once by the generic observer as stall:intake_admission (Layer 2, A8), with no second intake fingerprint for it');
insert into obs select 3, security.progress_read_v1();
select fx.ok((select count(*) from pipeline.integration_issues where fingerprint = 'stall:intake_admission') = 1
   and (select retry_count from pipeline.integration_issues where fingerprint = 'stall:intake_admission') = 1
   and (select count(*) from pipeline.integration_issues where fingerprint = 'intake-progress:monopoly') = 1
   and (select retry_count from pipeline.integration_issues where fingerprint = 'intake-progress:monopoly') = 1,
   're-run idempotent: the next reading updates the same issues (stall:intake_admission, intake-progress:monopoly), no duplicate');
select fx.ok((select a->'issue'->>'ref' from jsonb_array_elements(fx.v(3, 'status')->'alerts') a where a->>'code' = 'zero_yield') is not null,
   'the screen shows the zero-yield alert with the observer''s issue');
rollback;
begin;
update pipeline.course_intake_date_events set run_at = run_at - interval '2 days';
update pipeline.course_intake_dates set applied_at = applied_at - interval '2 days', publication_checked_at = publication_checked_at - interval '2 days';
update pipeline.progress_transitions set last_advanced_at = last_advanced_at - interval '2 days' where chain = 'intake';  -- the same two days pass for the observer
do $$ declare k int; begin
  for k in 1 .. 3 loop perform fx.decide('flinders', k, 'February', 'skipped', 'the course page names no study period of the calendar (month only)', now() - make_interval(mins => 20 - k)); end loop; end $$;
insert into obs select 4, security.progress_read_v1();
select fx.ok((select zero_reason = 'correctly_excluded' and not stalled from pipeline.progress_transitions where key = 'intake_admission')
   and not exists (select 1 from pipeline.integration_issues where fingerprint = 'stall:intake_admission'),
   'expected absence: runs whose rows only lack evidence are correctly_excluded and raise no issue');
rollback;
-- publication: when nothing admitted reaches the consumer source the observer raises stall:intake_publication, and the partial-mismatch check stays quiet
begin;
update pipeline.course_intake_dates set publication_state = 'consumer_publication_failed' where outcome = 'filled' and applied_at >= now() - interval '24 hours';
update pipeline.progress_transitions set last_advanced_at = last_advanced_at - interval '2 days' where chain = 'intake';
insert into obs select 5, security.progress_read_v1();
select fx.ok((select count(*) from pipeline.integration_issues where fingerprint = 'stall:intake_publication') = 1
   and (select condition_cleared_at is not null from pipeline.integration_issues where fingerprint = 'intake-progress:publication-mismatch'),
   'publication stalled: one fingerprint (stall:intake_publication); the partial-mismatch issue is marked cleared for the same condition');
rollback;
begin;
update pipeline.course_intake_dates set publication_state = 'published', failure_class = null where publication_state = 'consumer_publication_failed';
insert into obs select 6, security.progress_read_v1();
select fx.ok((select condition_cleared_at is not null from pipeline.integration_issues where fingerprint = 'intake-progress:publication-mismatch'),
  'a cleared condition marks its issue condition_cleared_at (the controller closes it)');
rollback;

-- forward recovery: the narrow off switch stops the intake readings and checks; the scholarship and AER chains are still read
begin;
update pipeline.platform_toolset_settings set value = '0' where toolset_key = 'pipeline' and key = 'progress.intake_chain_on';
update pipeline.course_intake_dates set publication_state = 'consumer_publication_failed' where outcome = 'filled';
insert into obs select 7, security.progress_read_v1();
select fx.ok((select bool_and(measured_at < now()) from pipeline.progress_transitions where chain = 'intake')
   and (select bool_and(measured_at = now()) from pipeline.progress_transitions where chain in ('scholarship', 'aer'))
   and not (r ? 'intake') and (r->>'read')::int = 16,
   'off switch: with progress.intake_chain_on 0 the observer reads the 16 scholarship and AER transitions only and runs no intake check') from obs where n = 7;
rollback;

-- 9 no job added or changed; the intake scheduler and processing untouched
select fx.ok((select command from cron.job where jobname = 'process-results') = 'select security.intake_publication_check_v1(); select security.process_results_record_v1(); select security.process_results_recovery_record_v1()'
   and (select command from cron.job where jobname = 'intake-dates-apply') = 'select security.intake_dates_apply_v1(security.pipeline_num_v1(''batch.intake_dates_apply'', 200)::int); select security.intake_publication_check_v1()'
   and (select count(*) from cron.job) = 3, 'jobs: process-results, intake-dates-apply and first-run-verify unchanged; no new job');
