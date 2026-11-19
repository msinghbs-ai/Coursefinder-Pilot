-- CF-247 s720 follow-up (S2-Build; Platform Admin 19 Nov 2026 08:17 and 11:42): close the four integration issues whose original failing
-- production condition was verified as cleared after 20261119104500 to 20261119115000 went live (CF-247 mandate step 13: an issue closes only
-- through security.integration_issue_close_v1 with passed verification, evidence and a time).
--
-- Verified (read back 19 Nov 2026 12:39-12:55 AEDT through the rolled-back dry-run workflow):
--   IQ-00609 rollup-scheduler: no failed run since the 11:03 AEDT deploy (statement timeouts in the coverage build before it).
--   IQ-00594 admission-rule-runner-b and IQ-00588 admission-rule-runner-c: no failed run since 11:03 AEDT (last failure runner-c 09:55).
--   IQ-00348 evidence-link-index: HTTP 200 at 12:19, 12:29 and 12:39 AEDT (500 statement timeouts at 11:59 and 12:09, before 20261119114500).
-- Not closed: IQ-00606 (page_text): the duplicate-claim error is gone, but 14 of 55 runs since the deploy hit the statement limit in the claim
-- (2.9 s by plan, more under load); it stays open for a bounded candidate walk.
-- Replaces: nothing. Retires: nothing. Data only: no table, function or job; the consumer API is not touched (G3 75/48).

do $c$
declare r record; v_n int := 0;
begin
  for r in
    select i.id, i.issue_ref, x.evidence
      from pipeline.integration_issues i
      join (values
        ('IQ-00609', 'rollup-scheduler: no failed run in cron.job_run_details since the 20261119104500 deploy at 11:03 AEDT; course-coverage-build runs chunked every 2 minutes, 11.7 to 16.0 s at 800 courses, now 400 (20261119115000).'),
        ('IQ-00594', 'admission-rule-runner-b: no failed run in cron.job_run_details since the 20261119104500 deploy at 11:03 AEDT (bounded consumer API snapshot, writer lock tried not waited for).'),
        ('IQ-00588', 'admission-rule-runner-c: no failed run in cron.job_run_details since the 20261119104500 deploy at 11:03 AEDT; last failure 09:55 AEDT, before it.'),
        ('IQ-00348', 'evidence-link-index: net._http_response HTTP 200 for the calls at 12:19, 12:29 and 12:39 AEDT after 20261119114500 (feed 1.6 s live, was 9.5 s; 500 statement timeouts at 11:59 and 12:09, before it).')
      ) x(issue_ref, evidence) on x.issue_ref = i.issue_ref
     where i.status not in ('resolved', 'closed')
  loop
    perform security.integration_issue_close_v1(r.id, 'S2-Build (Claude, Platform Admin directive 19 Nov 2026 08:17 and 11:42)',
      jsonb_build_object('outcome', 'passed', 'evidence', r.evidence, 'checked_at', '2026-11-19T12:55:00+11:00',
                         'reference', 'Pilot #1364, #1366, #1369; s720'));
    v_n := v_n + 1;
  end loop;
  raise notice 'closed % verified issue(s)', v_n;
end $c$;

-- post-check: the four are closed and IQ-00606 is still open
do $p$
begin
  if exists (select 1 from pipeline.integration_issues where issue_ref in ('IQ-00609','IQ-00594','IQ-00588','IQ-00348') and status not in ('resolved', 'closed')) then
    raise exception 'a verified issue is still open';
  end if;
  if exists (select 1 from pipeline.integration_issues where issue_ref = 'IQ-00606' and status in ('resolved', 'closed')) then
    raise exception 'IQ-00606 must stay open';
  end if;
end $p$;
