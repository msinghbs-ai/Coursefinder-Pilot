-- CF-247 s1291 (S1-Build; Platform Admin decision D11, 27 Nov 2026: "Retain pauses and reconcile", record coursefinder-admin #1207 comment 7203709925).
-- Jobs 87 scholarship-discover-refill, 378 calendar-reread and 108 firecrawl-runs are switched off (cron row inactive) by earlier decisions, while
-- pipeline.component_register lists them as active with no hold recorded, so the job read (security.data_delivery_jobs_v1) reports them as
-- "switched off while its component is registered active" and the 26 Nov effectiveness assessment suggested retiring them. D11 keeps them off and
-- asks for the register to show the hold. The register's lifecycle status stays 'active' (its vocabulary is active, retiring, retired; these jobs are kept,
-- not retiring); the hold, its decision, owner, replacement, dependency and spend are recorded in the register note, with a control event for each job.
-- Read live 27 Nov 2026 09:10 AEDT:
--   87 scholarship-discover-refill (23 * * * *, Scholarships; owner S1-Build, Master Plan Scholarships lane): paused 17 Nov 2026 13:35 by migration
--      20261117051700 ("Temporarily paused for bulk REQ and Roadmap ingestion", Platform Admin 17 Nov 13:11); s1054 (24 Nov) resumed scholarship-discover
--      and scholarship-read and left it off. Replacement: the s1054 picker takes requested providers ("Find scholarships", scholarship_provider_scan) first,
--      then the candidates already lined up. Spend if resumed: none itself (it lines up providers); scholarship-discover then searches them under the
--      scheduled Firecrawl limits.
--   378 calendar-reread (13 * * * *, Admission; owner S1-RM-Design, intake dates): paused with 87 on 17 Nov 13:35, left off by s1054. Replacement: none
--      scheduled; stored calendar documents are read again on demand (Run Now). Spend if resumed: coverage-sweep calendar_reread on stored documents, no
--      Firecrawl fetch.
--   108 firecrawl-runs (* * * * *, Platform upkeep; owner S3-Backend-Pipeline, Firecrawl containment): paused 22 Nov 2026 by S3 after zero running runs and
--      zero leased items were verified (Master Plan, S3 post-containment verification); s1010 kept it paused. Now: 0 running runs (latest run 2 Nov), 0 leased
--      items, run_auto_continue true. Dependency: a Firecrawl run started from the Firecrawl panel would not advance while the job is off. Spend if resumed:
--      each running run's steps spend Firecrawl credits under the daily budget guard.
-- Runtime is not changed: no cron row is switched, resumed, retired, unscheduled or deleted (D11). G1: no job. G2: no value. G3: 75/48 checked. Locks checked.
-- Replaces: the register notes of the three jobs. Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the register update

create temp table s1291_guard on commit drop as select (select count(*) from pipeline.manual_locks) locks_before;
create temp table s1291_cron on commit drop as select jobid, jobname, active, schedule, md5(command) cmd from cron.job;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v; end if;
  if (select count(*) from cron.job where (jobid, jobname) in ((87, 'scholarship-discover-refill'), (378, 'calendar-reread'), (108, 'firecrawl-runs')) and not active) <> 3 then
    raise exception 'guard: the three jobs are not the inactive cron rows read on 27 Nov 2026';
  end if;
  if (select count(*) from pipeline.component_register where kind = 'job' and name in ('scholarship-discover-refill', 'calendar-reread', 'firecrawl-runs') and status = 'active') <> 3 then
    raise exception 'guard: the three jobs are not registered active';
  end if;
end $g$;

with h(name, note) as (values
  ('scholarship-discover-refill', 'HELD (paused, kept; Platform Admin D11 27 Nov 2026: retain, resume or retire only by a separate decision). Paused 17 Nov 2026 13:35 (migration 20261117051700: temporary pause for bulk REQ and Roadmap ingestion, Platform Admin 17 Nov 13:11); left off by s1054 (24 Nov). Owner: S1-Build (Scholarships lane). Replacement: the s1054 picker (requested providers first, then candidates already lined up). Spend if resumed: none itself; scholarship-discover searches the added providers under the scheduled Firecrawl limits.'),
  ('calendar-reread', 'HELD (paused, kept; Platform Admin D11 27 Nov 2026: retain, resume or retire only by a separate decision). Paused 17 Nov 2026 13:35 (migration 20261117051700: temporary pause for bulk REQ and Roadmap ingestion, Platform Admin 17 Nov 13:11); left off by s1054 (24 Nov). Owner: S1-RM-Design (intake dates). Replacement: none scheduled; stored calendar documents are read again on demand (Run Now). Spend if resumed: coverage-sweep calendar_reread on stored documents, no Firecrawl fetch.'),
  ('firecrawl-runs', 'HELD (paused, kept; Platform Admin D11 27 Nov 2026: retain, resume or retire only by a separate decision). Paused 22 Nov 2026 by S3-Backend-Pipeline after zero running Firecrawl runs and zero leased items were verified (Firecrawl containment); kept paused by s1010. Owner: S3-Backend-Pipeline. Dependency: a Firecrawl run started from the Firecrawl panel does not advance while this job is off (27 Nov: none running, latest run 2 Nov). Spend if resumed: each running run''s steps spend Firecrawl credits under the daily budget guard.'))
update pipeline.component_register c set note = h.note, updated_at = now()
  from h where c.kind = 'job' and c.name = h.name and c.status = 'active';

insert into pipeline.admin_control_events (area, action, target, detail, actor)
select 'scheduler', 'hold_recorded', j.jobname,
       jsonb_build_object('jobid', j.jobid, 'active', j.active, 'decision', 'Platform Admin D11, 27 Nov 2026: retain pauses and reconcile (coursefinder-admin #1207 comment 7203709925)',
                          'runtime_changed', false, 'by', 'migration 20261130091500 (CF-247 s1291)'), null
  from cron.job j where j.jobid in (87, 378, 108);

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
  if exists (select 1 from cron.job j full join s1291_cron b on b.jobid = j.jobid
              where b.jobid is null or j.jobid is null or j.active is distinct from b.active or j.schedule is distinct from b.schedule or md5(j.command) is distinct from b.cmd) then
    raise exception 'post-check: a cron row changed';
  end if;
  if (select count(*) from pipeline.component_register where kind = 'job' and name in ('scholarship-discover-refill', 'calendar-reread', 'firecrawl-runs') and note like 'HELD (paused, kept;%') <> 3 then raise exception 'post-check: a hold is not recorded'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1291_guard) then raise exception 'post-check: manual locks changed'; end if;
end $c$;
