-- CF-247 AER source recovery, follow-up to 20261113123100 (Platform Admin 12 Nov 2026 20:23: "use firecrawl for http is refused and store the artifact as
-- evidence in storage"; an explicit Platform Admin instruction, so an exception to the AER v1 freeze of Decision 276).
-- Guards: G1 (no job), G2 (no new value; the shares and the switch are unchanged settings), G3 (no consumer API object), Decision 260.
-- Evidence: worker v0.80.0 spent the refused-PDF fetch as provider_facts_scrape, which svc_fc_spend counts in the central share (discovery: central_map,
--   central_entry_search). The AER discovery campaign uses that share up each day, so Macquarie's three PDFs and CIT's one were refused (reason 'share',
--   recorded on the source as "blocked_pdf; firecrawl: credits_refused") with 1,030 units of the reads share unused. A rolled-back call on 12 Nov 2026 21:00 AEDT:
--   svc_fc_spend(1, 'fc_read', Macquarie, PDF) = true; (1, 'provider_facts_scrape', ...) = false.
-- What:
--   1. Worker v0.80.1 spends the refused-PDF fetch as fc_read (the reads share, one page read). The daily total, the monthly limit and the cost breakers still apply.
--   2. The four sources refused this way go back to 'found' with their tries reset (as the attach action does), with the control event.
-- Replaces: nothing. Retires: nothing.

do $r$
declare v_n int;
begin
  update pipeline.entry_matrix_sources s set status = 'found', attempts = 0, error = null, updated_at = now()
   where s.error like 'blocked_pdf; firecrawl: credits_refused%' and s.status in ('failed', 'found');
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'source_attach_again', 'pipeline.entry_matrix_sources',
          jsonb_build_object('sources', v_n, 'reason', 'Refused PDFs fetched through Firecrawl from the reads share (worker v0.80.1); the central share was used up'), null);
  raise notice 'refused PDF sources attached again: %', v_n;
end $r$;
