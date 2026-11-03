-- CF-247 AER missing-university strategy, workstream C: bounded rendered-read pilot for JCU and UniSQ (Platform Admin approval 3 Nov 2026 18:14 §2).
-- Why: both universities publish their per-country (UniSQ) or per-qualification-and-course (JCU) minimums in a JavaScript selector, so a direct read sees
--   only the static text (inventory, migration 20261104090000: outcome verified_rendered_only for JCU; UniSQ verified_attachable with the selector
--   rows needing the rendered route).
-- What: the existing rendered route only (no new spend path): the two hosts are added to entry.render_hosts, so the existing entry-matrix fetch
--   (svc_entry_matrix_fetch_next -> worker) reads their recorded entry pages once through Firecrawl (rawHtml, entry.render_wait_ms), robots.txt
--   respected, within the existing Firecrawl budget check (useFcWhy provider_facts_scrape: daily budget, shares, per-provider caps) and AI guard
--   (guard_entry_matrix); every first read goes to Layer 4.
--   Pages: exactly two, guarded below:
--     https://www.jcu.edu.au/entry-options/entry-requirements/academic-and-english-language-entry-requirements/country-specific-academic-levels (attached here)
--     https://www.unisq.edu.au/international/apply/entry-requirements (attached by PASTE-20261104-aer-missing-university-sources.sql; re-read once if
--       it was already read directly)
-- Cost and cap: one Firecrawl scrape per page (1 credit each, plus any extra the scrape reports, recorded by svc_coverage_usage); at most
--   entry.matrix_attempts (3) tries a page, so at most 6 scrapes (about 6-10 credits) and 2 AI reads (about US$0.02-0.10 each) for the whole pilot.
--   The guard refuses to run unless each host has exactly one recorded entry page, so the host switch cannot reach any other page.
-- Expected: UniSQ's country rows may be in the rendered HTML (the table is filled client side); JCU's marks appear only after two selections, which a
--   rendered read without interaction does not make, so the JCU read is expected to show the options but no marks. The measurement query says which.
-- PASTE FILE. Not applied by any migration. Run after 20261104090000 and PASTE-20261104-aer-missing-university-sources.sql. Rollback:
--   PASTE-20261104-aer-render-pilot-rollback.sql (restores entry.render_hosts exactly; the attached JCU page stays only if it has been read).
begin;
do $$
declare v_before jsonb := (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.render_hosts'); v_n int;
begin
  if v_before is distinct from '["wgtn.ac.nz", "whitireiaweltec.ac.nz", "newcastle.edu.au", "griffith.edu.au"]'::jsonb then
    raise exception 'guard: entry.render_hosts is % (expected the four hosts read live 3 Nov 2026 16:29); nothing changed', v_before; end if;
  if not exists (select 1 from pipeline.aer_source_inventory where provider_id = 'fe6af182-f5ca-4a3c-bfb4-b0773ff1b113' and outcome = 'verified_rendered_only'
                   and url = 'https://www.jcu.edu.au/entry-options/entry-requirements/academic-and-english-language-entry-requirements/country-specific-academic-levels') then
    raise exception 'guard: the JCU inventory row (20261104090000) is missing; nothing changed'; end if;
  if not exists (select 1 from pipeline.entry_matrix_sources where provider_id = '551383f9-7732-4588-a843-dd2b97c13f6f' and url = 'https://www.unisq.edu.au/international/apply/entry-requirements') then
    raise exception 'guard: the UniSQ source is not attached (apply PASTE-20261104-aer-missing-university-sources.sql first); nothing changed'; end if;
  insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
  values ('fe6af182-f5ca-4a3c-bfb4-b0773ff1b113', 'https://www.jcu.edu.au/entry-options/entry-requirements/academic-and-english-language-entry-requirements/country-specific-academic-levels',
          'JCU: country-specific academic levels (selector; rendered pilot)', 1, 'manual') on conflict (provider_id, url) do nothing;
  -- the hard cap: exactly one recorded entry page on each pilot host
  select count(*) into v_n from pipeline.entry_matrix_sources where lower(substring(url from '^https?://(?:www\.)?([^/:?#]+)')) in ('jcu.edu.au', 'unisq.edu.au');
  if v_n <> 2 then raise exception 'guard: % entry pages on the pilot hosts, expected exactly 2; rolled back', v_n; end if;
  -- a UniSQ page already read directly is read once more, rendered (the existing re-read path: status found, attempts 0)
  update pipeline.entry_matrix_sources set status = 'found', attempts = 0, updated_at = now()
   where provider_id = '551383f9-7732-4588-a843-dd2b97c13f6f' and url = 'https://www.unisq.edu.au/international/apply/entry-requirements' and status = 'read' and coalesce(read_via, '') <> 'firecrawl';
  update pipeline.platform_toolset_settings set value = v_before || '["jcu.edu.au", "unisq.edu.au"]'::jsonb, updated_at = now(),
         reason = 'CF-247 AER missing-university rendered pilot (Platform Admin 3 Nov 2026 18:14 §2): two selector pages, at most 6 scrapes; rollback restores the four hosts'
   where toolset_key = 'pipeline' and key = 'entry.render_hosts';
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('entry_requirements', 'aer_render_pilot_start', 'pipeline.platform_toolset_settings:entry.render_hosts',
          jsonb_build_object('before', v_before, 'added', '["jcu.edu.au", "unisq.edu.au"]'::jsonb, 'pages', 2, 'max_scrapes', 6,
                             'authority', 'Platform Admin 3 Nov 2026 18:14 §2'));
end $$;
commit;
