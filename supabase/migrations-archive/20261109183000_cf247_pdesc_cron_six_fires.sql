-- CF-247 provider-description job fires six times an hour (Platform Admin 9 Nov 2026: "Continue fixing the provider-description declines ... autonomously."; coordinator brief A and QA of PR #959).
--
-- Why (live, read only, 9 Nov 2026, project fxcwkweaxjtknorudmwp):
--   * cron job 352 'provider-description-read' (command: select security.provider_description_fire_v1()) runs at minutes 6,16,26,56: four fires an hour, with no fire
--     at :36 or :46. The fire guard pdesc.every_minutes is 10 (floor) with a 30-second jitter allowance, so ten-minute spacing is already what the guard permits;
--     nothing in the function is changed here.
--   * Each fire dispatches one page-read run of batch.provider_description (10) providers, so the page-read capacity is 40 an hour now and 60 an hour with this change.
-- What:
--   1 cron.alter_job(352, schedule := '6,16,26,36,46,56 * * * *'). Only the schedule; command, active flag and name are not touched.
--     Guard: refuses unless the live schedule is the old value (md5 40439a43fa0f94e46d50c449afb9f46c, '6,16,26,56 * * * *') or the new one (then the schedule step is a no-op),
--     so a schedule someone changed by hand since is not overwritten. It also refuses when the job is missing. If the job is inactive it stays inactive.
--   2 G1 record: the catalogue row pipeline.automation_catalogue 'provider-description-read' describes the schedule; its first words are replaced (guarded: the old words must be
--     there, or the new ones already). The help text of the setting pdesc.every_minutes names the same minutes; the same guarded replace. No setting value, label, range or unit changes.
-- Which minutes (QA judgement, 9 Nov 2026, read from cron.job and cron.job_run_details of the last 2 days):
--   Six fires an hour at least ten minutes apart can only be ten minutes apart, so the choice is one minute digit. The digit 6 keeps the four existing fires and adds :36 and :46.
--   * :36 and :46 already host other jobs: credential-read and search-refresh-requested (6-59/10) run there; :46 also hosts layer4-groups (6,16,26,46,56, which already shares
--     :06, :16, :26 and :56 with this job); :36 hosts coursefinder-m2-3-refresh-intelligence-tick (1.7 s). So no new minute is contended by this change beyond one 1.7 s job.
--   * The heavy groups start one minute later: :37 (exit-awards-apply 32 s avg / 74 s max, no-page-propose 43 / 58, ranking-link 33 / 44) and :47 (course-coverage-build 32 / 55,
--     layer4-auto-admit 16 / 25, coverage snapshot 6). The fire's own database work averaged 15.5 s (192 runs, none failed; the 107 s maximum is the lease time-out that
--     20261109182000 fixes). The lease is called by the worker after the fire, so it can meet the :37 or :47 groups; the lease no longer takes more than a few seconds
--     (20261109182000), and it holds no lock that those jobs take (only an advisory capacity lock named for this job).
--   * Another digit does not clear the groups either: 4 (:14 and :44 layer4-interventions and source-proof-feed, :24 and :54 ops-controller, :34 layer1-auto-ingest, :44 programme-create),
--     8 (:38 country-scope-gate, :48 central-attach), 5 and 3 (the admission minutes :x3 and :x5), 1, 2, 7 and 9 (the :41 / :42 / :37 groups, :x9 admission). Moving all fires would also make
--     the guard refuse the first fire after the change (eight minutes after the last dispatch). So the digit stays 6. If :36 or :46 ever shows contention (a failed or slow run), one forward
--     migration with the same guard returns the schedule to the four fires.
-- Order: apply after the lease one-pass change (20261109182000, PR #957), which brings the lease RPC under the 8-second PostgREST limit that the 08:16 UTC call exceeded (71 s run);
--   two more fires an hour add load, so the lease must be fixed first. The migration does not check this (the lease fix is not a precondition of a schedule); the release order is stated in the PR.
--   The 8-second limit is not guaranteed under load (live per-call cost varied 5 to 30 times in measurements); #957 lowers the cost, it cannot promise the limit.
-- Not changed: the fire function, batch size, concurrency, queue cap, AI and Firecrawl ceilings, any setting value, any other job, the consumer API (G3). Nothing dropped.
--   A passing test switches nothing on: the job keeps its current active flag.
-- Replaces: the schedule '6,16,26,56 * * * *' of cron job 352 (provider-description-read); the schedule wording in the automation_catalogue description of provider-description-read and in the help text of pdesc.every_minutes
-- Retires: nothing
do $cron6$
declare
  v_id bigint; v_sched text; v_n int; v_txt text;
  c_old constant text := '6,16,26,56 * * * *'; -- fixed: the schedule this change replaces, kept only to refuse if it is no longer the live value
  c_new constant text := '6,16,26,36,46,56 * * * *'; -- fixed: cron schedules are not operational settings; the fire guard pdesc.every_minutes and the jitter allowance decide whether a fire runs
  c_desc_old constant text := 'At :06, :16, :26 and :56 (clear of the admission minutes :x3, :x5, :x9, the :35-:42 jobs and the :47 coverage build) while'; -- fixed: the catalogue words this change replaces
  c_desc_new constant text := 'Every ten minutes, at :06, :16, :26, :36, :46 and :56 (six fires an hour; ten minutes is the closest spacing the fire guard allows; :36 and :46 share their minute with other ten-minute jobs and start one minute before the :37 and :47 job groups) while'; -- fixed: the catalogue words
  c_help_old constant text := 'The job wakes at :06, :16, :26 and :56 and sends'; -- fixed: the setting help words this change replaces
  c_help_new constant text := 'The job wakes every ten minutes, at :06, :16, :26, :36, :46 and :56, and sends'; -- fixed: the setting help words
begin
  -- 1 the schedule
  select jobid, schedule into v_id, v_sched from cron.job where jobname = 'provider-description-read';
  if v_id is null then raise exception 'cron job provider-description-read does not exist'; end if;
  if v_sched = c_new then
    raise notice 'provider-description-read already fires at %', c_new;
  else
    if md5(v_sched) <> '40439a43fa0f94e46d50c449afb9f46c' or v_sched <> c_old then
      raise exception 'provider-description-read schedule is %, not the % this change replaces; not overwritten', v_sched, c_old;
    end if;
    perform cron.alter_job(v_id, schedule := c_new);
    select schedule into v_sched from cron.job where jobid = v_id;
    if v_sched <> c_new then raise exception 'schedule not applied (is %)', v_sched; end if;
  end if;
  -- 2 the catalogue row (G1)
  select description into v_txt from pipeline.automation_catalogue where jobname = 'provider-description-read';
  if v_txt is null then raise exception 'the automation catalogue has no row for provider-description-read'; end if;
  if position(c_desc_old in v_txt) = 1 then
    update pipeline.automation_catalogue set description = replace(description, c_desc_old, c_desc_new) where jobname = 'provider-description-read';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'catalogue row not updated'; end if;
  elsif position(c_desc_new in v_txt) <> 1 then
    raise exception 'the catalogue description of provider-description-read is neither the old nor the new wording; not overwritten';
  end if;
  -- 3 the help text of the setting that names the same minutes
  select help into v_txt from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.every_minutes';
  if v_txt is null then raise exception 'setting pdesc.every_minutes does not exist'; end if;
  if position(c_help_old in v_txt) = 1 then
    update pipeline.platform_toolset_settings set help = replace(help, c_help_old, c_help_new) where toolset_key = 'pipeline' and key = 'pdesc.every_minutes';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'setting help not updated'; end if;
  elsif position(c_help_new in v_txt) <> 1 then
    raise exception 'the help of pdesc.every_minutes is neither the old nor the new wording; not overwritten';
  end if;
end
$cron6$;
