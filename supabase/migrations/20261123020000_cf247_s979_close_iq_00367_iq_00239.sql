-- CF-247 s979 (S2-Build; Platform Admin consolidated batch 23 Nov 2026 07:16 and 07:45 AEDT, Part 3): close IQ-00367 and IQ-00239 after their
-- failing conditions were verified as cleared (security.integration_issue_close_v1 with passed verification, evidence and a time).
-- Verified (read back 23 Nov 2026 08:25 to 08:31 AEDT through the rolled-back dry-run workflow):
--   IQ-00367 "Academic entry requirements: 5 critical consumer data finding(s)" (31 at the last read): after s978 (migration 20261123010000,
--   Pilot #1483) the 08:27 aer-reconcile run left 0 open P0 findings and resolved the Health check aer:p0. The findings were rows admitted by
--   the partial admission rule aer-partial-v1 (s914) that the check could not see.
--   IQ-00239 "scheduled job scholarship-coverage-classify failed": 0 failed runs in the last 24 hours (hourly at :40, about 10 s each).
-- Not closed: IQ-00555 and IQ-00029 (coverage-sweep HTTP 500 and 546). The listing claim fix is live and no 5xx came back after deploy, but job
-- scholarship-listing was switched off outside this change before it ran again, so the fix has no live run to verify yet.
-- Replaces: nothing. Retires: nothing. Data only: no table, function or job; the consumer API is not touched (G3 75/48).

do $c$
declare v_id bigint;
begin
  select id into v_id from pipeline.integration_issues where issue_ref = 'IQ-00367' and status not in ('resolved', 'closed');
  if v_id is null then raise notice 'IQ-00367 already closed';
  else
    if exists (select 1 from pipeline.aer_gap_findings where state <> 'resolved' and severity = 'P0') then
      raise exception 'an AER P0 finding is open; IQ-00367 stays open';
    end if;
    perform security.integration_issue_close_v1(v_id, 'S2-Build (Claude, Platform Admin batch 23 Nov 2026 07:16 and 07:45)',
      jsonb_build_object('outcome', 'passed',
        'evidence', 'After s978 (migration 20261123010000) the 08:27 AEDT aer-reconcile run left 0 open P0 AER findings and resolved Health check aer:p0; the 31 findings were 1,133 rows admitted by rule aer-partial-v1 (s914) that the check could not see.',
        'checked_at', '2026-11-23T08:28:00+11:00', 'reference', 'Pilot #1483; s978'));
  end if;
  select id into v_id from pipeline.integration_issues where issue_ref = 'IQ-00239' and status not in ('resolved', 'closed');
  if v_id is null then raise notice 'IQ-00239 already closed';
  else
    if exists (select 1 from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                where j.jobname = 'scholarship-coverage-classify' and d.status <> 'succeeded' and d.start_time > now() - interval '24 hours') then  -- fixed: the 24-hour check window of this close
      raise exception 'scholarship-coverage-classify failed in the last 24 hours; IQ-00239 stays open';
    end if;
    perform security.integration_issue_close_v1(v_id, 'S2-Build (Claude, Platform Admin batch 23 Nov 2026 07:16 and 07:45)',
      jsonb_build_object('outcome', 'passed',
        'evidence', 'scholarship-coverage-classify: 0 failed runs in the 24 hours to 23 Nov 2026 08:31 AEDT (hourly at :40, about 10 s each, every run succeeded).',
        'checked_at', '2026-11-23T08:31:00+11:00', 'reference', 's979'));
  end if;
end $c$;
