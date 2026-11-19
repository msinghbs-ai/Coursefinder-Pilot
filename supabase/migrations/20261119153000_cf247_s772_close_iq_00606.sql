-- CF-247 s772 follow-up (S2-Build; Platform Admin 19 Nov 2026 14:24): close IQ-00606 after its original failing condition was verified as
-- cleared (CF-247 mandate step 13: security.integration_issue_close_v1 with passed verification, evidence and a time).
--
-- Verified (read back 19 Nov 2026 15:17-15:30 AEDT through the rolled-back dry-run workflow): every coverage-sweep page_text run since
-- 20261119150000 went live at 15:07 AEDT succeeded with 40 items (pipeline.mode_outcome_ledger), and none failed on the statement limit in
-- svc_page_text_next_v1; before it, 14 of 55 runs since 20261119104500 had failed on it, and 92 of 92 before that.
-- Replaces: nothing. Retires: nothing. Data only: no table, function or job; the consumer API is not touched (G3 75/48).

do $c$
declare v_id bigint;
begin
  select id into v_id from pipeline.integration_issues where issue_ref = 'IQ-00606' and status not in ('resolved', 'closed');
  if v_id is null then raise notice 'IQ-00606 already closed'; return; end if;
  if exists (select 1 from pipeline.mode_outcome_ledger where mode = 'page_text' and run_at > '2026-11-19 04:08:00+00' and outcome = 'failed') then
    raise exception 'a page_text run failed after 20261119150000; IQ-00606 stays open';
  end if;
  perform security.integration_issue_close_v1(v_id, 'S2-Build (Claude, Platform Admin directive 19 Nov 2026 14:24)',
    jsonb_build_object('outcome', 'passed',
      'evidence', 'coverage-sweep page_text: every run since 20261119150000 (15:07 AEDT) succeeded with 40 items and none hit the statement limit in svc_page_text_next_v1 (pipeline.mode_outcome_ledger); 14 of 55 had failed on it before.',
      'checked_at', '2026-11-19T15:30:00+11:00', 'reference', 'Pilot #1377; s772'));
end $c$;
