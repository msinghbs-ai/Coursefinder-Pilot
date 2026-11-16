-- CF-247 AER v2 long pages (Platform Admin 16 Nov 2026 16:52, decision "Stop Qwen, shadow Mistral", step 2): the switch for worker
-- coverage-sweep v1.0.6, which reads the entry requirement sections of a page longer than reading.aer_v2_page_chars instead of skipping it.
-- Replaces: nothing (the worker change adds a path; page_too_long stays for a page whose sections do not fit or cannot be found).
-- Retires: nothing.
--
-- Why: benchmark round 2 (coursefinder-admin docs/platform/layer4-clearance-and-model-benchmark-2026-11-16.md §4 and lesson 1) lost the same
-- 10 of 50 cases on every model as page_too_long at 60,000 characters; "long pages need splitting into sections in the reader, not a larger
-- limit". The worker uses the platform's existing section selector (lean-sections-v3, field entry_requirements); the page's own block numbers are
-- kept and the answer is verified against the whole page, so a quote must still be on the page. A page is never cut.
-- The switch starts off (0): nothing changes until the Platform Admin switches it on with a reason (Settings › Pipeline settings). It is read by
-- the benchmark mode (aer_v3_eval) and the AER v2 shadow only, and both of those are switched off today.
-- No consumer API object is read or changed (G3). No job, table or function.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'reading.aer_v2_long_page_sections_on', 'Entry requirements v2: read the entry sections of long pages',
  'When on (1), a course page longer than "Entry requirements v2: longest course page read" sends the model only its entry requirement sections, with the page''s own block numbers, if those fit the limit; the answer is still checked against the whole page. When off (0), such a page is recorded as page_too_long and not read. A page is never cut.',
  'number', to_jsonb(0), 0, 1, 'switch', 1547,
  'AER long pages (Platform Admin 16 Nov 2026 16:52): round 2 lost 10 of 50 cases as page_too_long on every model; off until switched on with a reason',
  'Entry requirements', 'worker coverage-sweep v1.0.6 modes aer_v3_eval and aer_v2_shadow (svc_worker_settings_v1; lean-sections.ts longPageWindow)')
on conflict do nothing;

do $post$
begin
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'reading.aer_v2_long_page_sections_on' and value = to_jsonb(0)) then
    raise exception 'post-check: reading.aer_v2_long_page_sections_on is missing or not off';
  end if;
end $post$;
