-- CF-247 scheduled job quick wins (Platform Admin 15 Nov 2026 20:38, approving the job governance audit of 20:25, quick wins 1 to 3).
--   1a. search-refresh-requested failed 27 of 139 runs in 24 hours on the database's 120 s statement limit: the full projection rebuild
--       (search.refresh_course_documents_v3) takes up to about two minutes when the database is busy. The job now runs with its own time limit,
--       a setting (search.refresh_time_limit_seconds, 300 s; Settings > Pipeline settings > Website API), set by the first statement of its
--       command for that run only (set_config is local to the run's transaction; each statement of a command gets its own limit). The rebuild,
--       its writer lock (W27), its requests and everything it writes are unchanged: no search function is edited (G3).
--   1b. course-description-stale-retire failed 3 of 23 runs on the same limit. It read its two classes (course no longer active, course
--       already described) through security.course_description_reconcile_v1, which also ran the full course description check (the
--       similarity scan against up to enrich.course_description_duplicate_window descriptions) on every waiting proposal, though this job never
--       uses it. It now reads the two classes directly with the same rules (same items, same order, same batch setting, same switch).
--   2.  The three switched-off jobs still marked active in the component register (course-link-reverse, onboarding-pilot-snapshot,
--       worker-outcome-check) are marked retiring, retire_after = today + hygiene.retire_after_days. The other five switched-off jobs were already
--       retiring and are past retire_after. All eight are dropped by docs/paste/PASTE-20261115-cron-legacy-jobs-drop.sql (the Platform Admin
--       pastes it; a migration drops nothing). A retiring job cannot be resumed, run or rescheduled (UR-07).
--   3.  The four jobs flagged COLLISION_RISK start on quieter minutes, with the same number of runs an hour:
--       coverage-ai-match-prepare */2 -> odd minutes; link-refresh */10 -> :01, :11, :21, :31, :41, :51; consumer-reference-bundle-refresh
--       :50 -> :51; course-description-machine keeps its 24 runs and its windows (not :13, not :35 to :43, not :45 to :49) but moves off
--       :00, :10, :20, :30 and :50.
-- G1: no new job. G2: one new setting (inserted; no existing setting changes); the new command reads it (no number written into a job).
-- G3: no consumer API object, search function or search table is changed; consumer-reference-bundle-refresh keeps its command (its start moves
--   one minute). The live consumer API is compared with its baseline by security.consumer_api_check_v1() before and after (no drift).
-- Replaces: security.course_description_retire_stale_v1() (same name and signature; md5-guarded replacement); the commands or schedules of the
--   jobs search-refresh-requested, coverage-ai-match-prepare, link-refresh, consumer-reference-bundle-refresh and course-description-machine.
-- Retires: the jobs course-link-reverse, onboarding-pilot-snapshot and worker-outcome-check (component register: retiring; dropped by the paste
--   file after the retirement period). Nothing is dropped here.

set local lock_timeout = '5s';

-- 0. What this change expects to find
do $$
declare v_def text := pg_get_functiondef('security.course_description_retire_stale_v1()'::regprocedure);
begin
  if md5(v_def) <> '64d853f9e0ba648fc14109bc2ab7de14' then
    raise exception 'live security.course_description_retire_stale_v1 differs from the definition this change replaces (md5 %)', md5(v_def);
  end if;
  if to_regnamespace('cron') is not null then
    if (select count(*) from cron.job where (jobname, schedule, command) in (
          ('search-refresh-requested', '6-59/10 * * * *', 'select security.search_refresh_requested_v1();'),
          ('coverage-ai-match-prepare', '*/2 * * * *', 'select security.coverage_ai_match_prepare_v1(security.pipeline_num_v1(''batch.ai_match_prepare_universities'', 200)::int, security.pipeline_num_v1(''batch.ai_match_prepare_courses'', 1000)::int)'),
          ('link-refresh', '*/10 * * * *', 'select security.link_refresh_tick_v1(security.pipeline_num_v1(''batch.link_refresh'', 500)::int)'),
          ('consumer-reference-bundle-refresh', '50 * * * *', 'select security.refresh_reference_bundle_cache_v1();'),
          ('course-description-machine', '0-34/2,44,50-58/2 * * * *', 'select security.course_description_machine_run_v1()'))) <> 5 then
      raise exception 'a job this change moves does not have the schedule and command it expects';
    end if;
  end if;
end $$;

-- 1a. The search refresh time limit (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values ('pipeline', 'search.refresh_time_limit_seconds', 'Search refresh: time limit for one run',
        'How long one run of the scheduled search refresh may take before the database stops it. A full rebuild of the search documents takes up to about two minutes when the database is busy; the database''s own limit is two minutes. A stopped run leaves its requests for the next run.',
        'number', to_jsonb(300), 120, 900, 'seconds', 332, 'Job governance quick win 1 (Platform Admin 15 Nov 2026 20:38): the refresh failed 27 of 139 runs on the 120 s database limit', 'Website API',
        'job search-refresh-requested (first statement of its command)')
on conflict do nothing;

do $$
declare v_id bigint;
begin
  if to_regnamespace('cron') is null then return; end if;
  select jobid into v_id from cron.job where jobname = 'search-refresh-requested';
  perform cron.alter_job(v_id, command := 'select set_config(''statement_timeout'', security.pipeline_num_v1(''search.refresh_time_limit_seconds'', 300)::int || ''s'', true); select security.search_refresh_requested_v1();');
end $$;

update pipeline.automation_catalogue
   set description = 'Updates search and the API for courses whose facts changed. Each run may take up to Settings > Pipeline settings > Website API > Search refresh: time limit for one run (the database''s own limit is two minutes).'
 where jobname = 'search-refresh-requested' and description = 'Updates search and the API for courses whose facts changed.';

-- 1b. course-description-stale-retire reads its two classes directly
create or replace function security.course_description_retire_stale_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_on boolean := security.pipeline_num_v1('enrich.course_description_stale_supersede_on', 0) >= 1; r record; v_n int := 0; v_ex int := 0; v_by jsonb := '{}'::jsonb; v_reason text;
        v_max int := security.pipeline_num_v1('layer4.reconcile_batch', 200)::int;
begin
  -- 15 Nov 2026 (job governance quick win 1): the two classes this job retires, read directly with the rules of
  -- security.course_description_reconcile_v1 (a course no longer active first, then a course that already has a description). Reading them
  -- through that function also ran the full course description check on every waiting proposal, which this job never uses.
  for r in select i.id item_id, c.id course_id,
                  case when c.lifecycle_status is distinct from 'active' then 'course_inactive' else 'already_filled' end class,
                  i.field_code, i.entity_type, i.entity_id, i.evidence_id
             from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id
            where i.status = 'pending' and i.entity_type = 'course' and i.field_code = 'course_description_first_read'
              and (c.lifecycle_status is distinct from 'active' or nullif(btrim(c.description), '') is not null)
            order by i.created_at limit v_max loop
    v_ex := v_ex + 1;
    v_reason := case r.class when 'course_inactive' then 'entity_retired' else 'covered_by_active' end;
    v_by := v_by || jsonb_build_object(v_reason, coalesce((v_by ->> v_reason)::int, 0) + 1);
    continue when not v_on;
    update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
           change_control_ref = left(coalesce(change_control_ref, '') || ' | superseded: ' || v_reason || ' (course description proposal can no longer be approved)', 400)
     where id = r.item_id and status = 'pending';
    continue when not found;
    insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)
    values (r.item_id, r.field_code, r.entity_type, r.entity_id, v_reason, null,
            jsonb_build_object('class', r.class, 'evidence_id', r.evidence_id, 'by', 'course-description-stale-retire'), 'reconcile');
    if to_regclass('pipeline.layer4_item_readiness') is not null then
      execute 'update pipeline.layer4_item_readiness set item_status = ''superseded'', readiness = ''closed'', classified_at = now() where item_id = $1' using r.item_id;
    end if;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('on', v_on, 'examined', v_ex, 'superseded', v_n, 'by_reason', v_by);
end $function$;

-- 2. Switched-off jobs: retiring (the drop is a paste file)
update pipeline.component_register r
   set status = 'retiring', replaced_by = x.replaced_by, retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int,
       note = 'switched off; retiring (job governance audit, Platform Admin 15 Nov 2026 20:38); dropped by docs/paste/PASTE-20261115-cron-legacy-jobs-drop.sql',
       updated_at = now()
  from (values
    ('course-link-reverse', 'nothing: switched off and not run; course pages are matched by coverage-ai-match and the CRICOS course link steps'),
    ('onboarding-pilot-snapshot', 'nothing: switched off and not run; the onboarding pilot is reported by Layer 2 > Operations lane funnels'),
    ('worker-outcome-check', 'nothing: switched off and never run; worker failures are reported by Platform health (edge_calls) and the queue watchdog')) x(name, replaced_by)
 where r.kind = 'job' and r.name = x.name and r.status = 'active';

update pipeline.component_register
   set note = 'switched off; dropped by docs/paste/PASTE-20261115-cron-legacy-jobs-drop.sql (job governance audit, Platform Admin 15 Nov 2026 20:38)', updated_at = now()
 where kind = 'job' and status = 'retiring'
   and name in ('cron-history-retention', 'cron-history-trim', 'l4-rule-low-agreement', 'provider-calendar-defaults', 'provider-calendar-intakes');

-- 3. Quieter start minutes (same number of runs an hour)
do $$
begin
  if to_regnamespace('cron') is null then return; end if;
  perform cron.alter_job((select jobid from cron.job where jobname = 'coverage-ai-match-prepare'), schedule := '1-59/2 * * * *');
  perform cron.alter_job((select jobid from cron.job where jobname = 'link-refresh'), schedule := '1-59/10 * * * *');
  perform cron.alter_job((select jobid from cron.job where jobname = 'consumer-reference-bundle-refresh'), schedule := '51 * * * *');
  perform cron.alter_job((select jobid from cron.job where jobname = 'course-description-machine'), schedule := '1,2-8/2,11,12-18/2,21,22-28/2,31,32,34,44,51,52-58/2 * * * *');
end $$;

-- 4. Post-checks
do $$
declare v_def text := pg_get_functiondef('security.course_description_retire_stale_v1()'::regprocedure);
begin
  if v_def like '%course_description_reconcile_v1%' then raise exception 'post-check: stale-retire still reads through the reconcile function'; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'search.refresh_time_limit_seconds' and value = to_jsonb(300)) then
    raise exception 'post-check: the search refresh time limit setting is missing';
  end if;
  if (select count(*) from pipeline.component_register where kind = 'job' and status = 'retiring' and name in ('course-link-reverse', 'cron-history-retention', 'cron-history-trim',
        'l4-rule-low-agreement', 'provider-calendar-defaults', 'provider-calendar-intakes', 'onboarding-pilot-snapshot', 'worker-outcome-check')) <> 8 then
    raise exception 'post-check: not all eight switched-off jobs are retiring';
  end if;
  if to_regnamespace('cron') is not null then
    if (select count(*) from cron.job where (jobname, schedule) in (('coverage-ai-match-prepare', '1-59/2 * * * *'), ('link-refresh', '1-59/10 * * * *'),
          ('consumer-reference-bundle-refresh', '51 * * * *'), ('course-description-machine', '1,2-8/2,11,12-18/2,21,22-28/2,31,32,34,44,51,52-58/2 * * * *'))) <> 4 then
      raise exception 'post-check: schedules';
    end if;
    if not exists (select 1 from cron.job where jobname = 'search-refresh-requested' and schedule = '6-59/10 * * * *'
                    and command like 'select set_config(''statement_timeout'', security.pipeline_num_v1(''search.refresh_time_limit_seconds'', 300)::int || ''s'', true); select security.search_refresh_requested_v1();') then
      raise exception 'post-check: search refresh command';
    end if;
    if exists (select 1 from cron.job where active and jobname in ('course-link-reverse', 'cron-history-retention', 'cron-history-trim', 'l4-rule-low-agreement',
          'provider-calendar-defaults', 'provider-calendar-intakes', 'onboarding-pilot-snapshot', 'worker-outcome-check')) then
      raise exception 'post-check: a retiring job is switched on';
    end if;
  end if;
end $$;