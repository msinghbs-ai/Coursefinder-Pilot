-- CF-247 AER reader quality: settings for the corrected reader behaviours (Platform Admin directive 8 Nov 2026: "Correct verified reader behaviour ...
-- Repair quote truncation, qualification-country aliases and dropped minimums under existing evidence rules ... No blanket approvals, nothing
-- auto-admitted; human Layer 4 decisions remain mandatory"). Development agent, branch cf247-aer-reader-quality. Settings only: no function is edited,
-- no table is created, nothing is read, fetched, spent, approved or admitted, and layer4.reader_revision is NOT changed (the Integration Controller
-- changes it after the worker release is deployed and verified).
--
-- Live evidence (project fxcwkweaxjtknorudmwp, read only, 8 Nov 2026):
--   * 564 waiting course reads (363 technical, 201 judgement-ready) and 41 waiting matrix runs (31 technical, 10 judgement-ready).
--   * Course reads: 614 quote_not_on_page drops sit in the waiting reads; 113 of them (81 reads) are quotes the model joined from separate passages with
--     an ellipsis, and the worker proved only the whole joined text on the page. 51 dropped quotes (and 171 kept ones) are stored at exactly 300 characters.
--   * Matrix runs: unknown_country is 122 drops in 31 runs; only UK (1) and GB-SCT (1) are a country the page unambiguously names. The rest are not a country
--     (INT 26, International Baccalaureate 39, Worldwide 15, GLOBAL 5, Pacific Islands 6+2+1, GAC 2, ANY, ALL, General, empty 11): they stay held.
--   * Matrix runs: value_without_scale 22 and value_not_in_quote 12 drops lose a row whose grade text is printed only because its number has no basis.
-- What this adds (all in the worker, coverage-sweep v0.59.11; the settings are the only database change):
--   1. enrich.course_entry_quote_chars (100 to 300, default 300 = today): the longest quote kept for a course requirement. 300 is the width of
--      catalogue.course_entry_requirements.quote (a table check), so the setting can lower the limit but not raise it. A quote kept short of what the model
--      gave is recorded on its row (quote_cut) and counted in the read's coverage (quotes_cut): never cut silently.
--   2. reading.course_quote_fragments_on (ships 0) with reading.course_entry_fragment_min_chars (default 6): a course quote joined from passages with an
--      ellipsis is proven fragment by fragment (each on the page, in the page's order). A quote whole on the page is accepted as before.
--   3. reading.entry_country_aliases_on (ships 0) with reading.entry_country_aliases: governed aliases from a country token that is not an ISO code to the
--      ISO code it unambiguously means (UK and the ISO 3166-2 codes of Great Britain's nations). The row records the token it was given. A change to the list
--      is a Settings change with a reason (public.admin_toolsets_write writes before, after and reason to pipeline.admin_control_events).
--   4. reading.entry_value_null_on (ships 0): a matrix row whose grade text is printed in its quote is kept, with the number left out, when only the number has
--      no printed scale or is not printed (the same rule as a course score since 7 Nov). The row records what was left out (conditions.value_removed).
--   Not changed: global qualifications and "all countries" tokens (Global, International Baccalaureate, INT, WW, GAC, ANY, ALL) have no country and the matrix
--   needs one (provider_entry_matrix.country_id is not null); they stay held. Bands, grades not printed in the quote and confidence are still checked as before.
-- Activation is a recorded setting change after the worker is deployed and checked (reading.course_quote_fragments_on, reading.entry_country_aliases_on,
-- reading.entry_value_null_on to 1); a passing check switches nothing on by itself.
-- Consumer API (G3): untouched (no object of the frozen list is read or written). Rows already read, superseded or reviewed are not touched.
-- Replaces: nothing (worker behaviours are added behind switches; the unchanged defaults keep today's reading)
-- Retires: nothing
-- Nothing is dropped or deleted.

do $g$
begin
  if to_regclass('pipeline.platform_toolset_settings') is null or to_regprocedure('public.svc_worker_settings_v1()') is null then
    raise exception 'AER reader quality: needs pipeline.platform_toolset_settings and public.svc_worker_settings_v1';
  end if;
  -- the worker reads these keys through svc_worker_settings_v1, which returns every pipeline key starting enrich. or reading.
  if pg_get_functiondef('public.svc_worker_settings_v1()'::regprocedure) not like '%s.key like ''enrich.%''%'
     or pg_get_functiondef('public.svc_worker_settings_v1()'::regprocedure) not like '%s.key like ''reading.%''%' then
    raise exception 'AER reader quality: svc_worker_settings_v1 no longer returns enrich.* and reading.* settings';
  end if;
end $g$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'enrich.course_entry_quote_chars', 'Course entry requirements: longest quote kept',
  'The most characters of the page''s own words kept as the quote of one course requirement. The column holds 300 at most, so this can be lowered, not raised. A quote kept short of what the model gave is marked on its row (quote_cut) and counted in the read (quotes_cut), never cut silently.',
  'number', to_jsonb(300), 100, 300, 'characters', 1140, 'Entry requirements', 'worker coverage-sweep enrich_ai (course-entry.ts storeQuote)', 'CF-247 AER reader quality (8 Nov 2026)'),
 ('pipeline', 'reading.course_quote_fragments_on', 'Course entry reader: prove a joined quote fragment by fragment',
  'On (1): a course quote the model joined from separate passages with an ellipsis is kept when every fragment is on the page, in the page''s order. A fragment missing, too short or out of order drops the requirement as quote_not_on_page and says which. Off (0): the joined text must be on the page whole, as before.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1141, 'Entry requirements', 'worker coverage-sweep enrich_ai (course-entry.ts proveQuote)', 'CF-247 AER reader quality (8 Nov 2026); ships off'),
 ('pipeline', 'reading.course_entry_fragment_min_chars', 'Course entry reader: shortest fragment of a joined quote',
  'Letters and digits a fragment of a joined quote must have, so that a few common words cannot prove a passage.',
  'number', to_jsonb(6), 4, 40, 'characters', 1142, 'Entry requirements', 'worker coverage-sweep enrich_ai (course-entry.ts proveQuote)', 'CF-247 AER reader quality (8 Nov 2026)'),
 ('pipeline', 'reading.entry_country_aliases_on', 'Entry reader: use the country aliases',
  'On (1): a country token the entry reader returns that is not an ISO code is read as the ISO code listed in the aliases (reading.entry_country_aliases). Off (0): held as unknown_country, as before.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1143, 'Entry requirements', 'worker coverage-sweep mode entry_ai (entry.ts entryCountryAliases)', 'CF-247 AER reader quality (8 Nov 2026); ships off'),
 ('pipeline', 'reading.entry_country_aliases', 'Entry reader: country aliases',
  'TOKEN=ISO pairs: a token that is not an ISO 3166-1 code and the ISO code it unambiguously means, for example UK=GB. Add a token only when it can mean one country; Global, International, IB, WW and the like are not countries and stay held. Each change is recorded with its reason.',
  'list', '["UK=GB", "GB-SCT=GB", "GB-ENG=GB", "GB-WLS=GB", "GB-NIR=GB"]'::jsonb, null, null, 'aliases', 1144, 'Entry requirements',
  'worker coverage-sweep mode entry_ai (entry.ts entryCountryAliases)', 'CF-247 AER reader quality (8 Nov 2026)'),
 ('pipeline', 'reading.entry_value_null_on', 'Entry reader: keep a minimum when only its number has no printed basis',
  'On (1): an entry-matrix row whose grade text is printed in its quote is kept, with the number left out and noted on the row, when the number has no printed scale or is not printed in the quote. Off (0): the row is dropped (value_without_scale, value_not_in_quote), as before.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1145, 'Entry requirements', 'worker coverage-sweep mode entry_ai (entry.ts entryMatrixParsed)', 'CF-247 AER reader quality (8 Nov 2026); ships off')
on conflict (toolset_key, key) do nothing;

-- post-check: all six exist and every number is inside its range. (Whether a behaviour is on is a recorded Settings change, so a re-run never judges it.)
do $c$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in
        ('enrich.course_entry_quote_chars', 'reading.course_quote_fragments_on', 'reading.course_entry_fragment_min_chars',
         'reading.entry_country_aliases_on', 'reading.entry_country_aliases', 'reading.entry_value_null_on')) <> 6 then
    raise exception 'AER reader quality post-check: a setting is missing';
  end if;
  if exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and kind = 'number' and key in
        ('enrich.course_entry_quote_chars', 'reading.course_quote_fragments_on', 'reading.course_entry_fragment_min_chars',
         'reading.entry_country_aliases_on', 'reading.entry_value_null_on')
        and (min_value is null or max_value is null or (value #>> '{}')::numeric not between min_value and max_value)) then
    raise exception 'AER reader quality post-check: a number has no range or sits outside it';
  end if;
end $c$;
