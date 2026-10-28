-- CF-247 AER programme, Step B: PDF matrices, and Step C: JavaScript-only pages (Platform Admin consolidated mandate, 28 Oct 2026 23:22;
-- admin docs/platform/ENTRY-REQUIREMENTS-PROGRAMME-DECISION-2026-10-28.md P4, P5 and sections 3-4; ENTRY-REQUIREMENTS-IMPLEMENTATION.md
-- 2.5 steps B and C).
-- The PDF route through the existing entry-matrix reader: the same sources, runs, evidence, identity, Layer 4 first-run review and
-- unchanged-page hash skip. No new table, job or status. Worker v0.50.0 reads a stored PDF's tables from the PDF's own drawn rules and
-- holds anything it cannot prove (held_unparsed, before any AI read).
-- 1. Settings (G2): entry.pdf_enabled (0 here: PDF sources stay parked as pdf_step_b; switched on by its own change after worker v0.50.0
--    is verified live, so no PDF is read by an earlier worker), entry.pdf_max_bytes, entry.pdf_max_pages.
-- 2. security.entry_matrix_fire_v1: while entry.pdf_enabled is 1, parked PDF sources of providers in scope return to found (tries reset)
--    and are fetched like any page.
-- 3. public.svc_entry_matrix_fetch_next: parks PDFs only while entry.pdf_enabled is 0, and tells the worker which items are PDFs and their
--    size cap.
-- 4. security.entry_matrix_use_stored_v1: a PDF source takes a stored copy only when that copy is a PDF (a page text or markdown copy of a
--    PDF has no positions to prove its columns from).
-- 5. public.svc_entry_matrix_next: passes entry.pdf_max_pages.
-- 6. Step C: entry.render_hosts (empty here) names the sites whose requirements the browser draws; svc_entry_matrix_fetch_next marks
--    their sources render, and worker v0.50.0 reads them once rendered through Firecrawl (rawHtml, waiting entry.render_wait_ms),
--    robots.txt respected, within the Firecrawl budget check. Sources and hosts are added by their own change after v0.50.0 is live.
-- Replaces: security.entry_matrix_fire_v1, public.svc_entry_matrix_fetch_next, security.entry_matrix_use_stored_v1, public.svc_entry_matrix_next
--   (same names, md5-guarded edits); the pdf_step_b parking rule (kept while entry.pdf_enabled is 0)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table or status.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'entry.pdf_enabled', 'Entry matrices: read PDF tables', 'On: PDF entry tables are fetched and read once their columns and rows are proven from the PDF''s own drawn cells. Off: PDF sources wait (pdf_step_b).', 'number',
  to_jsonb(0), 0, 1, 'on/off', 920, 'Entry requirements', 'security.entry_matrix_fire_v1, public.svc_entry_matrix_fetch_next',
  'CF-247 AER programme Step B (29 Oct 2026): off until worker v0.50.0 is verified live'),
 ('pipeline', 'entry.pdf_max_bytes', 'Entry matrices: largest PDF', 'A PDF larger than this is not fetched (recorded as pdf_too_large).', 'number',
  to_jsonb(20000000), 1000000, 50000000, 'bytes', 921, 'Entry requirements', 'public.svc_entry_matrix_fetch_next, worker entry_ai',
  'CF-247 AER programme Step B (29 Oct 2026): the planned PDFs are 0.1 to 0.8 MB'),
 ('pipeline', 'entry.pdf_max_pages', 'Entry matrices: PDF pages read', 'At most this many pages of a PDF are read; a table continuing beyond them is not read.', 'number',
  to_jsonb(40), 1, 200, 'pages', 922, 'Entry requirements', 'public.svc_entry_matrix_next, worker entry_ai',
  'CF-247 AER programme Step B (29 Oct 2026): the planned PDFs have 1 to 10 pages'),
 ('pipeline', 'entry.render_hosts', 'Entry matrices: sites read rendered', 'Sites (host names, without www.) whose entry requirements the browser draws: their pages are read once rendered through Firecrawl, robots.txt respected.', 'list',
  '[]'::jsonb, null, null, 'hosts', 923, 'Entry requirements', 'public.svc_entry_matrix_fetch_next, worker entry_ai',
  'CF-247 AER programme Step C (29 Oct 2026): empty until worker v0.50.0 is verified live'),
 ('pipeline', 'entry.render_wait_ms', 'Entry matrices: rendered page wait', 'How long Firecrawl waits for a rendered page to draw its requirements before reading it.', 'number',
  to_jsonb(5000), 1000, 30000, 'milliseconds', 924, 'Entry requirements', 'public.svc_entry_matrix_fetch_next, worker entry_ai',
  'CF-247 AER programme Step C (29 Oct 2026)')
on conflict (toolset_key, key) do nothing;

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('security.entry_matrix_fire_v1()', 'dd985f9ab6b51bddbf5e97d1f7d83143', array[
  array[$o$  v_att := security.entry_matrix_attach_v1();$o$,
        $n$  v_att := security.entry_matrix_attach_v1();
  -- AER Step B (29 Oct 2026): while PDF tables are read, a parked PDF source of a provider in scope is fetched like any page
  if security.pipeline_num_v1('entry.pdf_enabled', 0) >= 1 then
    update pipeline.entry_matrix_sources f set status = 'found', attempts = 0, error = null, updated_at = now()
     where f.status = 'pdf_step_b' and security.entry_matrix_enabled_v1(f.provider_id);
  end if;$n$]], array[1]);

select pg_temp.edit_n('public.svc_entry_matrix_fetch_next(integer)', '8fa16c874184ce085011b0c354b310e4', array[
  array[$o$  update pipeline.entry_matrix_sources s set status = 'pdf_step_b', updated_at = now()
   where s.status = 'found' and s.url ~* '\.pdf($|[?#])';$o$,
        $n$  -- AER Step B (29 Oct 2026): PDFs wait only while entry.pdf_enabled is 0
  if security.pipeline_num_v1('entry.pdf_enabled', 0) < 1 then
    update pipeline.entry_matrix_sources s set status = 'pdf_step_b', updated_at = now()
     where s.status = 'found' and s.url ~* '\.pdf($|[?#])';
  end if;$n$],
  array[$o$'country', (select k.iso_alpha2 from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = u.provider_id))), '[]'::jsonb)$o$,
        $n$'country', (select k.iso_alpha2 from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = u.provider_id),
           'pdf', u.url ~* '\.pdf($|[?#])', 'pdf_max_bytes', security.pipeline_num_v1('entry.pdf_max_bytes', 20000000)::bigint,
           'render', coalesce(security.toolset_setting('pipeline', 'entry.render_hosts'), '[]'::jsonb) ? lower(substring(u.url from '^https?://(?:www\.)?([^/:?#]+)')),
           'render_wait_ms', security.pipeline_num_v1('entry.render_wait_ms', 5000)::int)), '[]'::jsonb)$n$]], array[1, 1]);

select pg_temp.edit_n('security.entry_matrix_use_stored_v1()', '9e411390c46ed41bc2546ecd66deef49', array[
  array[$o$                            where a.source_url = s.url and a.storage_path is not null$o$,
        $n$                            where a.source_url = s.url and a.storage_path is not null
                              -- AER Step B (29 Oct 2026): a PDF source takes only a stored PDF
                              and (s.url !~* '\.pdf($|[?#])' or a.mime_type = 'application/pdf')$n$]], array[1]);

select pg_temp.edit_n('public.svc_entry_matrix_next(integer)', 'c2ac766d85fa71d0b4a1966f07a04d87', array[
  array[$o$           'slice_chars', security.pipeline_num_v1('entry.matrix_slice_chars', 24000)::int,$o$,
        $n$           'slice_chars', security.pipeline_num_v1('entry.matrix_slice_chars', 24000)::int,
           'pdf_max_pages', security.pipeline_num_v1('entry.pdf_max_pages', 40)::int,$n$]], array[1]);

do $$ begin
  if security.pipeline_num_v1('entry.pdf_enabled', 0) <> 0 then raise exception 'entry.pdf_enabled must stay 0 in this change'; end if;
  if jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'entry.render_hosts'), '[]'::jsonb)) <> 0 then raise exception 'entry.render_hosts must stay empty in this change'; end if;
end $$;
