-- CF-247 AER programme (Platform Admin consolidated mandate, 28 Oct 2026 23:22; admin docs/platform/ENTRY-REQUIREMENTS-PROGRAMME-DECISION-2026-10-28.md
-- P1, P4, P5): switches on Steps B and C now that worker v0.50.0 answers live (merged separately from the worker: the 28 Oct deploy-order
-- lesson), and adds Wave J, the planned JavaScript-only sources.
-- 1. entry.pdf_enabled 1: the 13 parked PDF sources return to found at the next fire and are fetched, proven and read (or held).
-- 2. entry.render_hosts: Victoria University of Wellington, Whitireia and WelTec, Newcastle and Griffith; their seeded pages are read
--    once rendered. Canterbury publishes a checker app with no page to read: not seeded (contact provider, reported).
-- 3. Wave J sources seeded (found_via 'manual', count-guarded) and their providers added to entry.providers (guarded on the Wave H list;
--    RMIT stays out).
-- 4. Reads stopped by faults fixed in #722 are given their tries back, bounded: sources refused for Firecrawl budget (credits_refused)
--    before the fix, and runs whose answer was cut off at the old fixed length (MIT, Wollongong). Their outcome goes to Layer 4 as
--    any first read.
-- Replaces: nothing
-- Retires: the pdf_step_b wait for providers in scope (kept for any provider outside entry.providers)
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table or status.

do $$
declare v_scope jsonb := (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.providers');
begin
  if jsonb_array_length(v_scope) <> 29 or v_scope ? '8e1adb6c-e069-43db-9584-bd054255e702' then raise exception 'entry.providers is not the Wave H list (live: %)', v_scope; end if;
  if security.pipeline_num_v1('entry.pdf_enabled', 0) <> 0 then raise exception 'entry.pdf_enabled is already on'; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.render_hosts') then raise exception 'entry.render_hosts is missing (#723 first)'; end if;
end $$;

update pipeline.platform_toolset_settings set value = to_jsonb(1), updated_at = now(),
       reason = 'CF-247 AER programme Step B: worker v0.50.0 verified live; Platform Admin consolidated mandate 28 Oct 2026 23:22'
 where toolset_key = 'pipeline' and key = 'entry.pdf_enabled';
update pipeline.platform_toolset_settings set value = '["wgtn.ac.nz", "whitireiaweltec.ac.nz", "newcastle.edu.au", "griffith.edu.au"]'::jsonb, updated_at = now(),
       reason = 'CF-247 AER programme Step C (Wave J): the planned JavaScript-only entry pages; Platform Admin consolidated mandate 28 Oct 2026 23:22'
 where toolset_key = 'pipeline' and key = 'entry.render_hosts';

do $$ declare v_n int; begin
  insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via) values
   ('34616965-b2b7-42a7-8da7-50ffbf120958', 'https://www.wgtn.ac.nz/international/applying/entry-requirements', 'Victoria University of Wellington: international entry requirements (rendered)', 1, 'manual'),
   ('40f9891f-c8da-45cc-aced-154e63d41cff', 'https://www.whitireiaweltec.ac.nz/enrolment-information/international-enrolments/academic-entry-requirements', 'Whitireia and WelTec: academic entry requirements (rendered)', 1, 'manual'),
   ('1822b40a-8b13-44dc-8c37-106ae31bb447', 'https://www.newcastle.edu.au/study/international/the-university-in-your-country/uon-agents/entry-requirements', 'Newcastle: entry requirements by country (rendered)', 1, 'manual'),
   ('36086f5e-9fe0-4878-aa40-1897a7d8cb24', 'https://www.griffith.edu.au/apply/international/understanding-entry-requirements', 'Griffith: understanding entry requirements (rendered)', 1, 'manual')
  on conflict (provider_id, url) do nothing;
  get diagnostics v_n = row_count;
  if v_n <> 4 then raise exception 'Wave J: expected 4 new sources, inserted %', v_n; end if;
end $$;

update pipeline.platform_toolset_settings
   set value = value || '["34616965-b2b7-42a7-8da7-50ffbf120958", "40f9891f-c8da-45cc-aced-154e63d41cff", "1822b40a-8b13-44dc-8c37-106ae31bb447", "36086f5e-9fe0-4878-aa40-1897a7d8cb24"]'::jsonb,
       updated_at = now(),
       reason = 'CF-247 AER programme Wave J: the planned JavaScript-only providers with a seeded official source; Platform Admin consolidated mandate 28 Oct 2026 23:22'
 where toolset_key = 'pipeline' and key = 'entry.providers';

do $$ declare v_s int; v_r int; begin
  update pipeline.entry_matrix_sources set status = 'found', attempts = 0, updated_at = now()
   where found_via = 'manual' and status = 'failed' and error in ('credits_refused', 'credits_reserve') and read_at is null;
  get diagnostics v_s = row_count;
  if v_s > 10 then raise exception 'expected at most 10 budget-refused sources, found %', v_s; end if;
  update pipeline.entry_matrix_runs set state = 'queued', attempts = 0, leased_until = null, updated_at = now()
   where state = 'failed' and error like 'Unterminated string in JSON%' and review_item_id is null;
  get diagnostics v_r = row_count;
  if v_r > 5 then raise exception 'expected at most 5 cut-off runs, found %', v_r; end if;
  if jsonb_array_length((select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.providers')) <> 33 then raise exception 'entry.providers widening did not apply'; end if;
  if security.entry_matrix_enabled_v1('8e1adb6c-e069-43db-9584-bd054255e702') then raise exception 'RMIT must stay out of matrix reading scope'; end if;
end $$;
