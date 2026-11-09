-- CF-247 provider-description job fires six times an hour (Platform Admin 9 Nov 2026: "Continue fixing the provider-description declines ... autonomously."; coordinator brief A).
--
-- Why (live, read only, 9 Nov 2026, project fxcwkweaxjtknorudmwp):
--   * cron job 352 'provider-description-read' (command: select security.provider_description_fire_v1()) runs at minutes 6,16,26,56: four fires an hour, with no fire
--     at :36 or :46. The fire guard pdesc.every_minutes is 10 (floor) with a 30-second jitter allowance, so ten-minute spacing is already what the guard permits;
--     nothing in the function is changed here.
--   * Each fire dispatches one page-read run of batch.provider_description (10) providers, so the page-read capacity is 40 an hour now and 60 an hour with this change.
-- What: cron.alter_job(352, schedule := '6,16,26,36,46,56 * * * *'). Only the schedule; command, active flag, name and catalogue row are not touched.
--   Guard: refuses unless the live schedule is the old value (md5 40439a43fa0f94e46d50c449afb9f46c, '6,16,26,56 * * * *') or the new one (then it is a no-op:
--   "already applied"), so a schedule someone changed by hand since is not overwritten. It also refuses when the job is missing. If the job is inactive it stays inactive.
-- Order: apply after the lease one-pass change (20261109182000, PR #957). That change brings the lease RPC under the 8-second PostgREST limit that the 08:16 UTC call
--   exceeded (71 s run); two more fires an hour add load, so the lease must be fixed first. The migration does not check this (the lease fix is not a precondition of a
--   schedule); the release order is stated in the PR.
-- Not changed: the fire function, batch size, concurrency, queue cap, AI and Firecrawl ceilings, any setting, any other job, the consumer API (G3). Nothing dropped.
--   A passing test switches nothing on: the job keeps its current active flag.
-- Replaces: the schedule '6,16,26,56 * * * *' of cron job 352 (provider-description-read)
-- Retires: nothing
do $mig$
declare
  v_id bigint; v_sched text; v_active boolean;
  c_old constant text := '6,16,26,56 * * * *'; -- fixed: the schedule this change replaces, kept only to refuse if it is no longer the live value
  c_new constant text := '6,16,26,36,46,56 * * * *'; -- fixed: cron schedules are not operational settings; the fire guard pdesc.every_minutes and the jitter allowance decide whether a fire runs
begin
  select jobid, schedule, active into v_id, v_sched, v_active from cron.job where jobname = 'provider-description-read';
  if v_id is null then raise exception 'cron job provider-description-read does not exist'; end if;
  if v_sched = c_new then raise notice 'provider-description-read already fires at %: nothing to do', c_new; return; end if;
  if md5(v_sched) <> '40439a43fa0f94e46d50c449afb9f46c' or v_sched <> c_old then
    raise exception 'provider-description-read schedule is %, not the % this change replaces; not overwritten', v_sched, c_old;
  end if;
  perform cron.alter_job(v_id, schedule := c_new);
  select schedule into v_sched from cron.job where jobid = v_id;
  if v_sched <> c_new then raise exception 'schedule not applied (is %)', v_sched; end if;
end
$mig$;
