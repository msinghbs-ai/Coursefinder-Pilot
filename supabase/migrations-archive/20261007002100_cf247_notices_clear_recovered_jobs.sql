-- CF-247, 7 Oct 2026 (Platform Admin: fix the scholarship notice). The scheduled-job notice counted every timeout in the last 24 hours, so a job
-- that was fixed (scholarship-nationality, 18:53; every run since succeeds) kept showing as failing for a day. A job whose last 3 runs all
-- succeeded is now left out; a job that still fails now and then stays listed.
do $p$
declare d text;
begin
  d := pg_get_functiondef('security.platform_notices_v1()'::regprocedure);
  if md5(d) <> '1d0e96adc060160342e8d0d71eba4d3d' then raise exception 'platform_notices_v1 is not the version this migration expects'; end if;
  if strpos(d, $a$          where d.status = 'failed' and d.end_time > now() - make_interval(hours => w_job)
          group by j.jobid, j.jobname, l.layer, 3$a$) = 0 then raise exception 'anchor not found'; end if;
  d := replace(d, $a$          where d.status = 'failed' and d.end_time > now() - make_interval(hours => w_job)
          group by j.jobid, j.jobname, l.layer, 3$a$, $b$          where d.status = 'failed' and d.end_time > now() - make_interval(hours => w_job)
            and not (select coalesce(bool_and(r.status = 'succeeded'), false) and count(*) = 3
                       from (select d3.status from cron.job_run_details d3 where d3.jobid = j.jobid and d3.status in ('succeeded', 'failed')
                             order by d3.start_time desc limit 3) r)
          group by j.jobid, j.jobname, l.layer, 3$b$);
  execute d;
end $p$;
