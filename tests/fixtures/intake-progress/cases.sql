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

-- repeated deterministic failures (Platform Admin 5 Nov 2026 22:46): only a repeat with demonstrably unchanged evidence, reader and settings is raised
create or replace function fx.repeat_pair(p_n int, p_at1 timestamptz, p_at2 timestamptz) returns void language plpgsql as $$
begin
  perform fx.decide('swinburne', p_n, 'February', 'skipped', 'the course page names no study period of the calendar (month only)', p_at1);
  perform fx.decide('swinburne', p_n, 'February', 'skipped', 'the course page names no study period of the calendar (month only)', p_at2);
end $$;
-- the 167 UNSW rechecks of 5 Nov 2026, at production scale: 151 academic_year_unproven and 16 no_matching_commencement_period rows, null reader, decided
-- at 14:26 and again at 16:26 (Sydney; the most recent 16:26 within a day) under the same rule and calendar set
create or replace function fx.unsw167() returns void language plpgsql as $$
declare t2 timestamptz := ((date_trunc('day', now() at time zone 'Australia/Sydney') + interval '16 hours 26 minutes') at time zone 'Australia/Sydney');
        t1 timestamptz; k int; n int := 0; c int; m text;
begin
  if t2 > now() then t2 := t2 - interval '1 day'; end if;
  t1 := t2 - interval '2 hours';
  -- the seeded intake settings were written when the fixture was built; date them before both decisions so only the case's own change is seen
  update pipeline.platform_toolset_settings set updated_at = least(updated_at, t1 - interval '1 hour') where toolset_key = 'pipeline' and key ~ '^(intake_dates|run_now)\.';
  insert into pim.entity_registry(id) select fx.id('c:unsw:' || g) from generate_series(31, 100) g on conflict do nothing;
  insert into catalogue.courses(id, provider_id, canonical_title, course_url)
  select fx.id('c:unsw:' || g), fx.id('p:unsw'), 'Course ' || g || ' of unsw', 'https://example.edu.au/unsw/course-' || g from generate_series(31, 100) g on conflict do nothing;
  insert into catalogue.course_intakes(id, course_id, intake_year, intake_label)
  select fx.id('i:unsw:' || g || ':' || mm), fx.id('c:unsw:' || g), 2027, mm from generate_series(31, 100) g, unnest(array['February', 'July']) mm on conflict do nothing;
  for c in 16 .. 100 loop foreach m in array array['February', 'July'] loop
    exit when n >= 167;
    -- courses 1 to 15 are already decided in the base run history
    n := n + 1;
    perform fx.decide('unsw', c, m, 'skipped', case when n <= 151 then 'the calendar does not print the year of its start in this month (month only)'
                                                     else 'the course page names no study period of the calendar (month only)' end, t1);
    perform fx.decide('unsw', c, m, 'skipped', case when n <= 151 then 'the calendar does not print the year of its start in this month (month only)'
                                                     else 'the course page names no study period of the calendar (month only)' end, t2);
  end loop; end loop;
  create temp table if not exists rep_t(k text primary key, at timestamptz);
  delete from rep_t; insert into rep_t values ('t1', t1), ('t2', t2), ('t_1556', t2 - interval '30 minutes');
end $$;
-- (a) with the governed 15:56 change of intake_dates.month_unique_match 1 -> 0 between them (as admin control event 28963): 167 excluded, none confirmed, no issue
begin;
select fx.unsw167();
insert into pipeline.admin_control_events(area, action, target, detail, actor, created_at)
select 'toolsets', 'setting', 'pipeline.intake_dates.month_unique_match', '{"after": 0, "before": 1, "reason": "P0 IQ-00313 containment"}', fx.id('user:6'), at from rep_t where k = 't_1556';
insert into obs select 10, security.progress_read_v1();
select fx.ok((x->>'excluded_setting_change')::int = 167 and (x->>'confirmed')::int = 0
   and (select count(*) from pipeline.course_intake_date_events e where e.provider_id = fx.id('p:unsw') and e.run_at = (select at from rep_t where k = 't2') and e.failure_class = 'academic_year_unproven' and e.reader is null) = 151
   and (select count(*) from pipeline.course_intake_date_events e where e.provider_id = fx.id('p:unsw') and e.run_at = (select at from rep_t where k = 't2') and e.failure_class = 'no_matching_commencement_period') = 16
   and not exists (select 1 from pipeline.integration_issues where fingerprint = 'intake-progress:repeated-deterministic'),
  'repeats: the 167 UNSW rechecks (151 academic_year_unproven, 16 no_matching_commencement_period, null reader, 14:26 and 16:26, the 15:56 setting audit between) are 167 excluded_setting_change, 0 confirmed, no issue')
  from (select security.intake_progress_repeats_v1() x) y;
rollback;
-- (a2) the same change written without an audit row (seen through platform_toolset_settings.updated_at): still excluded
begin;
select fx.unsw167();
update pipeline.platform_toolset_settings set value = '0', updated_at = (select at from rep_t where k = 't_1556') where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, section, used_by, updated_at)
select 'pipeline', 'intake_dates.month_unique_match', 'Intake dates: unique month', 'number', '0', 'Intake dates', 'security.intake_dates_plan_v3', at from rep_t where k = 't_1556'
on conflict (toolset_key, key) do nothing;
select fx.ok((x->>'excluded_setting_change')::int = 167 and (x->>'confirmed')::int = 0,
  'repeats: an unaudited change of an intake_dates.* setting between the decisions (its updated_at) also excludes the 167 rechecks') from (select security.intake_progress_repeats_v1() x) y;
rollback;
-- (b) the same 167 with no change at all: confirmed, one issue; a re-run updates it; it clears when the repeats leave the window
begin;
select fx.unsw167();
insert into obs select 11, security.progress_read_v1();
select fx.ok((select (x->>'confirmed')::int from (select security.intake_progress_repeats_v1() x) y) = 167
   and (select count(*) from pipeline.integration_issues where fingerprint = 'intake-progress:repeated-deterministic') = 1
   and r->'intake'->>'repeated_deterministic' is not null, 'repeats: the same 167 with nothing changed are 167 confirmed and one issue intake-progress:repeated-deterministic')
  from obs where n = 11;
insert into obs select 12, security.progress_read_v1();
select fx.ok((select count(*) from pipeline.integration_issues where fingerprint = 'intake-progress:repeated-deterministic') = 1
   and (select retry_count from pipeline.integration_issues where fingerprint = 'intake-progress:repeated-deterministic') = 1,
   'repeats: a re-run updates the same issue (stable fingerprint, no duplicate)');
update pipeline.course_intake_date_events set run_at = run_at - interval '2 days' where run_at in (select at from rep_t where k in ('t1', 't2'));
insert into obs select 13, security.progress_read_v1();
select fx.ok((select condition_cleared_at is not null from pipeline.integration_issues where fingerprint = 'intake-progress:repeated-deterministic'),
  'repeats: when the condition clears, the issue is marked cleared');
rollback;
-- (b2) an unrelated setting changed between them (audited and unaudited): the 167 stay confirmed
begin;
select fx.unsw167();
insert into pipeline.admin_control_events(area, action, target, detail, actor, created_at)
select 'toolsets', 'setting', 'pipeline.process_results.window_days', '{"after": 14, "before": 7}', fx.id('user:6'), at from rep_t where k = 't_1556';
update pipeline.platform_toolset_settings set updated_at = (select at from rep_t where k = 't_1556') where toolset_key = 'pipeline' and key = 'process_results.window_days';
select fx.ok((x->>'confirmed')::int = 167 and (x->>'excluded_setting_change')::int = 0,
  'repeats: a change of an unrelated setting between the decisions does not excuse them: 167 confirmed') from (select security.intake_progress_repeats_v1() x) y;
rollback;
-- (c) inputs that cannot be established (no stored page wording on the later decision, nor on the earlier one): unverified_repeat, shown, no issue
begin;
do $$ declare k int; begin for k in 1 .. 3 loop perform fx.repeat_pair(k, now() - interval '150 minutes', now() - interval '30 minutes'); end loop; end $$;
update pipeline.course_intake_date_events set page_quote = null where provider_id = fx.id('p:swinburne');
insert into obs select 14, security.progress_read_v1();
select fx.ok((x->>'unverified_repeat')::int = 3 and (x->>'confirmed')::int = 0 and not exists (select 1 from pipeline.integration_issues where fingerprint = 'intake-progress:repeated-deterministic')
   and (select (a->'evidence'->>'unverified_repeat')::int from jsonb_array_elements(fx.v(3, 'status')->'alerts') a where a->>'code' = 'repeated_deterministic') = 3,
  'repeats: inputs that cannot be established are unverified_repeat, shown on the screen, no issue') from (select security.intake_progress_repeats_v1() x) y;
rollback;
-- (d) a reader revision (a release that changed an intake function between the decisions) and (e) a source update (another calendar set) are excluded
begin;
do $$ declare k int; begin for k in 1 .. 2 loop perform fx.repeat_pair(k, now() - interval '150 minutes', now() - interval '30 minutes'); end loop; end $$;
insert into pipeline.integration_deploy_checks(release, since, ok, result)
values ('v2.15.482', now() - interval '60 minutes', true, '{"functions": [{"ok": true, "function": "security.intake_dates_plan_v3(uuid[],integer)"}]}');
update pipeline.course_intake_date_events set calendar_set = 'set:swinburne:v2.2' where provider_id = fx.id('p:swinburne') and course_id = fx.id('c:swinburne:2') and run_at > now() - interval '60 minutes';
select fx.ok((x->>'excluded_reader_revision')::int = 1 and (x->>'excluded_source_update')::int = 1 and (x->>'confirmed')::int = 0,
  'repeats: a release changing an intake function is a reader revision; a changed calendar set is a source update; neither is confirmed') from (select security.intake_progress_repeats_v1() x) y;
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
