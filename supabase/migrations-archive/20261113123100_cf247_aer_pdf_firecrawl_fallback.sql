-- CF-247 AER source recovery: a refused PDF is fetched through Firecrawl and stored as evidence (Platform Admin 12 Nov 2026 20:23: "use firecrawl for http is refused
-- and store the artifact as evidence in storage"; an explicit Platform Admin instruction, so an exception to the AER v1 freeze of Decision 276).
-- Guards: G1 (no job), G2 (the fallback is a switch), G3 (no consumer API object), Decision 260, Layer 4 authority unchanged (the stored copy is read and proposed as
--   any page; nothing is admitted here).
-- Evidence: Macquarie's three official Academic Entry PDFs (380 courses, no entry table) were refused by mq.edu.au with HTTP 403 on 28 Oct and again on 12 Nov after
--   #1067 (bot protection); Canberra Institute of Technology has one PDF refused the same way. PDFs were fetched directly only, never through Firecrawl.
-- What:
--   1. Setting reading.entry_pdf_firecrawl_on (1): worker v0.80.0 fetches a PDF the provider's server refuses (401, 403, 406, 429) once through Firecrawl, within the
--      Firecrawl budget check (purpose provider_facts_scrape), stores Firecrawl's text of the PDF (markdown) in the evidence bucket (.md.gz, read_via firecrawl) and
--      reads it as text. The PDF cell and grid readers do not apply (no column positions); every quote is still checked against the stored copy.
--   2. The four refused PDF sources go back to 'found' with their tries reset (as the Platform Admin's attach action does), with the control event.
-- Replaces: nothing. Retires: nothing.
-- Reversal without code: reading.entry_pdf_firecrawl_on 0 (refused PDFs are failed again, as before).

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'reading.entry_pdf_firecrawl_on', 'Entry requirements: fetch a refused PDF through Firecrawl',
  '1 fetches an entry-requirements PDF that the provider''s server refuses (401, 403, 406, 429) once through Firecrawl, within the Firecrawl budget check, and stores Firecrawl''s text of the PDF as evidence; it is read as text (the PDF column proof needs the PDF itself, so it does not apply). 0 leaves a refused PDF failed.',
  'number', to_jsonb(1), 0, 1, 'switch', 1145, 'Entry requirements', 'coverage-sweep entry_ai fetch (worker v0.80.0)', 'Platform Admin 12 Nov 2026 20:23: use Firecrawl when HTTP is refused and store the artifact as evidence')
on conflict (toolset_key, key) do nothing;

do $r$
declare v_n int;
begin
  update pipeline.entry_matrix_sources s set status = 'found', attempts = 0, error = null, updated_at = now()
   where s.error = 'blocked_pdf' and s.status in ('failed', 'found');
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'source_attach_again', 'pipeline.entry_matrix_sources',
          jsonb_build_object('sources', v_n, 'reason', 'Platform Admin 12 Nov 2026 20:23: refused PDFs fetched again, through Firecrawl when refused'), null);
  raise notice 'refused PDF sources attached again: %', v_n;
end $r$;
