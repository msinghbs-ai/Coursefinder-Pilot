-- CF-247, 7 Oct 2026 (Platform Admin: fix the two failing jobs). Both timed out at 120 s.
-- 1. scholarship-nationality (24 of 24 runs failed): it re-read all 1,354 active scholarships against 114 nationality terms every hour. It now reads
--    at most 150 scholarships a run, those never read or changed since their last reading (oldest first), and runs every 10 minutes.
-- 2. platform-resource-observe (13 of 24 failed): the peak-concurrency measure compared every cron run with every other (about 1,300 runs an hour).
--    It is now one running sum over start and end events; the result is the same measure.
do $p$
declare d text;
begin
  d := pg_get_functiondef('security.scholarship_nationality_read_v1()'::regprocedure);
  if md5(d) <> 'e78ee764d1ef9812664ef99d638a6a87' then raise exception 'scholarship_nationality_read_v1 is not the version this migration expects'; end if;
  if strpos(d, E'     where s.lifecycle_status = ''active''),\n  m as (') = 0 then raise exception 'anchor 1 not found'; end if;
  d := replace(d, E'     where s.lifecycle_status = ''active''),\n  m as (',
    E'     where s.lifecycle_status = ''active''\n'
    || E'       and not exists (select 1 from scholarship.nationality_readings a where a.scholarship_id = s.id and a.reader_version = ''scholarship-nationality-v1'' and a.read_at >= s.updated_at\n'
    || E'                         and a.read_at >= coalesce((select max(c.created_at) from scholarship.criteria c where c.scholarship_id = s.id), ''-infinity''::timestamptz))\n'
    || E'     order by (select a.read_at from scholarship.nationality_readings a where a.scholarship_id = s.id) nulls first, s.id\n'
    || E'     limit 150),\n  m as (');
  execute d;

  d := pg_get_functiondef('security.platform_resource_observe_v1()'::regprocedure);
  if md5(d) <> 'b4810bd37552c901332892210caf612b' then raise exception 'platform_resource_observe_v1 is not the version this migration expects'; end if;
  if strpos(d, $a$  select coalesce(max(c),0) into r.cron_max_concurrent from (
    select (select count(*) from cron.job_run_details b where b.start_time >= h0 - interval '1 hour' and b.start_time <= a.start_time and coalesce(b.end_time, case when b.status in ('running','starting','sending','connecting') then now() else b.start_time end) > a.start_time) c
    from cron.job_run_details a where a.start_time >= h0 and a.start_time < h) z;$a$) = 0 then raise exception 'anchor 2 not found'; end if;
  d := replace(d, $a$  select coalesce(max(c),0) into r.cron_max_concurrent from (
    select (select count(*) from cron.job_run_details b where b.start_time >= h0 - interval '1 hour' and b.start_time <= a.start_time and coalesce(b.end_time, case when b.status in ('running','starting','sending','connecting') then now() else b.start_time end) > a.start_time) c
    from cron.job_run_details a where a.start_time >= h0 and a.start_time < h) z;$a$,
  $b$  select coalesce(max(c) filter (where t >= h0 and t < h and d = 1),0) into r.cron_max_concurrent from (
    select e.t, e.d, sum(e.d) over (order by e.t, e.d desc) c from (
      select b.start_time t, 1 d from cron.job_run_details b where b.start_time >= h0 - interval '1 hour' and b.start_time < h
      union all
      select coalesce(b.end_time, case when b.status in ('running','starting','sending','connecting') then now() else b.start_time end), -1
        from cron.job_run_details b where b.start_time >= h0 - interval '1 hour' and b.start_time < h) e) z;$b$);
  execute d;

  perform cron.alter_job(job_id := (select jobid from cron.job where jobname = 'scholarship-nationality'), schedule := '3-59/10 * * * *');
end $p$;
