-- CF-247 AER missing-university strategy (Platform Admin 3 Nov 2026 16:24; admin docs/platform/aer/2026-11-03-missing-universities-source-and-reader-strategy.md
-- at 9fc8cbf6), workstream C: attach the official entry-requirement sources that free, read-only discovery verified on 3 Nov 2026 (inventory
-- pipeline.aer_source_inventory, migration 20261104090000), through the existing attachment path (pipeline.entry_matrix_sources, found_via 'manual',
-- as Wave H did, migration 20261028006000).
--   Charles Darwin University  https://www.cdu.edu.au/international/how-apply/entry-requirements          (country table; IB and A Level rules)
--   University of Southern Qld https://www.unisq.edu.au/international/apply/entry-requirements            (static IB and A Level rules; the per-country
--                                                                                                            selector needs the rendered route: not asked)
--   University of New England  https://www.une.edu.au/international/apply/eligibility/academic-requirements (general rule only: an evidenced "no table")
--   Torrens University         https://www.torrens.edu.au/apply-online/admissions-criteria                (general rule only: an evidenced "no table")
-- Not attached (no verified URL): Deakin (site refused the free read), ACU (minimum academic entry PDF: href not verifiable), CQU (country document:
-- href not verifiable), JCU (selector: rendered route only).
-- Effect after applying: with job aer-scheduled-read on (Release C, v2.15.427), security.entry_matrix_enabled_v1 admits each provider (an entry page is
-- recorded); the existing entry-matrix-read job reads each page directly (robots.txt respected by the worker; no Firecrawl: none of the hosts is in
-- entry.render_hosts), within guard_entry_matrix and the OpenRouter floor; every first read goes to Layer 4 (entry.matrix_first_run_review 1). Nothing is
-- admitted or published by this file. Expected AI cost: about US$0.02-0.10 a page (UWA's 6-slice read cost US$0.104).
-- PASTE FILE. Not applied by any migration. Run after migration 20261104090000 is deployed. Inserts exactly 4 rows. Nothing is deleted.
-- Rollback: PASTE-20261104-aer-missing-university-sources-rollback.sql (refused once a source has been read).
begin;
do $$
declare v_n int; v_before int := (select count(*) from pipeline.entry_matrix_sources);
begin
  if to_regclass('pipeline.aer_source_inventory') is null then raise exception 'migration 20261104090000 is not deployed; nothing changed'; end if;
  create temporary table att(provider_id uuid, url text, title text) on commit drop;
  insert into att values
    ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2', 'https://www.cdu.edu.au/international/how-apply/entry-requirements', 'CDU: international entry requirements (country table)'),
    ('551383f9-7732-4588-a843-dd2b97c13f6f', 'https://www.unisq.edu.au/international/apply/entry-requirements', 'UniSQ: international undergraduate entry requirements'),
    ('fa0e0d13-838a-42ff-b6a3-9cea84bd80b2', 'https://www.une.edu.au/international/apply/eligibility/academic-requirements', 'UNE: international academic requirements (general)'),
    ('fec52f92-a8a3-4de8-a862-06f355e4e2f7', 'https://www.torrens.edu.au/apply-online/admissions-criteria', 'Torrens: admissions criteria (general admission information)');
  select count(*) into v_n from att a join pipeline.aer_source_inventory i on i.provider_id = a.provider_id and i.url = a.url and i.attach;
  if v_n <> 4 then raise exception 'guard: % of 4 sources are in the inventory marked for attachment; nothing changed', v_n; end if;
  select count(*) into v_n from att a join security.aer_eligible_v1() e on e.provider_id = a.provider_id;
  if v_n <> 4 then raise exception 'guard: % of 4 providers are AER-eligible; nothing changed', v_n; end if;
  select count(*) into v_n from att a join pipeline.entry_matrix_sources s on s.provider_id = a.provider_id;
  if v_n <> 0 then raise exception 'guard: % of the providers already have a source; nothing changed', v_n; end if;
  insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)
  select a.provider_id, a.url, a.title, 1, 'manual' from att a on conflict (provider_id, url) do nothing;
  get diagnostics v_n = row_count;
  if v_n <> 4 or (select count(*) from pipeline.entry_matrix_sources) <> v_before + 4 then raise exception 'guard: inserted %, expected 4; rolled back', v_n; end if;
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('entry_requirements', 'aer_missing_university_sources', 'pipeline.entry_matrix_sources',
          jsonb_build_object('count', 4, 'urls', (select jsonb_agg(url order by url) from att), 'inventory_migration', '20261104090000',
                             'authority', 'Platform Admin 3 Nov 2026 16:24 (AER missing-university strategy); D6 scheduled reading 15:52'));
end $$;
commit;
