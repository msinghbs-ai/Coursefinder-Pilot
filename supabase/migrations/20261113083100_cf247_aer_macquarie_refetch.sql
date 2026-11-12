-- CF-247 Decision 276 workstream B (source discovery and recovery, Platform Admin 12 Nov 2026: "Continue discovering entry-requirement sources for missing providers.
-- Prioritise official provider sources and reuse stored documents ... Maintain automatic retry and recovery").
-- Guards: G1 (no job), G2 (no new value), G3 (no consumer API object), Decision 260, Layer 4 authority unchanged (a fetched PDF is read and proposed as any other).
-- Evidence: Macquarie University (380 active courses, no entry table) has three official "Academic Entry for International Students" PDFs (undergraduate,
--   postgraduate, foundation; July 2026 editions, still the editions linked from mq.edu.au academic-requirements on 12 Nov 2026). Each was refused once on
--   28 Oct 2026 (HTTP 403, blocked_pdf) and has had no try since: three tries in two hours, then failed. A direct PDF fetch costs nothing (no Firecrawl, no model
--   until the PDF is stored and proven).
-- What: the three sources go back to 'found' with their tries reset, as the Platform Admin's "attach" action on Entry requirements › Sources does
--   (public.admin_aer_source), with the same control event. entry-matrix-read fetches them on its next run.
-- Replaces: nothing. Retires: nothing.

do $r$
declare v_n int;
begin
  update pipeline.entry_matrix_sources s set status = 'found', attempts = 0, error = null, updated_at = now()
   where s.provider_id = '188103a5-1aba-4f99-bd3e-0416659086d3' and s.status = 'failed' and s.error = 'blocked_pdf' and s.url ~* '^https://www\.mq\.edu\.au/__data/assets/pdf_file/.*Academic-Entry.*\.pdf$';
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'source_attach_again', 'pipeline.entry_matrix_sources',
          jsonb_build_object('provider', '188103a5-1aba-4f99-bd3e-0416659086d3', 'sources', v_n,
                             'reason', 'Decision 276 workstream B: official Macquarie Academic Entry PDFs refused once (403) on 28 Oct 2026; fetched again directly'), null);
  raise notice 'Macquarie sources attached again: %', v_n;
end $r$;
