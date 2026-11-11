-- CF-247 F-AER.10 reader fixes (Platform Admin mandate 12 Nov 2026 09:23: "Fix UWA's 8 missing quotation values, 41 incorrect band values and 2 identity conflicts at
-- the reader level ... Continue repairing UTS, CSU, Curtin, Wollongong and VU using reusable reader improvements").
-- Guards: G1 (no job), G2 (every fix is a setting), G3 (no consumer API object), Decision 260, Layer 4 authority unchanged (rows are proposed on the same item and admitted
--   only by a person's decision or rule D1).
-- Evidence (production, read only, 12 Nov 2026 09:25-09:50 AEDT; the waiting reads of v0.72.1, their dropped rows and D-R3 flags):
--   UWA (run 4edb1e9f): 8 China rows dropped value_not_in_quote: the grade is a printed range ("488 to 491") and the model gave its midpoint (489.5); 41 rows flagged
--     "the band holds label text": the band is given with its label ("ATAR equivalent: 98", "ATAR 80"); 2 groups of one identity: AP and HKDSE subject rows
--     (one row per subject), which reading.entry_subject_rows_on joins into one subject-prerequisite row.
--   Heading + cell quotes not found on the page (quote_not_on_page): Charles Sturt 16 ("China Entry Requirements Completion of ..."), Charles Darwin 8
--     ("China | Year 12: 80% minimum ..."), UTS 2, Curtin 1, Federation ("COUNTRY: Uganda | Undergraduate Entry: ...").
--   A count with no scale (value_without_scale): Federation Uganda 2 ("minimum 2 passes"), Curtin College 2; the grade text is printed, only the number has no basis.
--   No country: Wollongong 7 rows of Australian AQF qualifications ("AQF bachelor's degree | 50% | ...").
--   Unknown qualification: Victoria University "General Certificate of Education (GCE O Levels)"; Victoria University of Wellington "BTEC ... National Extended Diploma".
-- What:
--   1. Worker v0.74.0 settings: reading.entry_quote_parts_on (1), reading.entry_quote_window_chars (600), reading.entry_band_label_words, reading.entry_qualification_countries.
--   2. Switches built for these cases and shipped off, now on (each keeps the row's grade as printed; a number is kept only where printed):
--      reading.entry_range_lower_bound_on (UWA China ranges: the range's printed lower bound), reading.entry_subject_rows_on (UWA AP and HKDSE subjects),
--      reading.entry_value_null_on (a number with no printed basis is left out, the row kept when its grade text is printed).
--   3. ref.aer_qualifications: GCE O Level (GCE_O) and Pearson BTEC Level 3 National Extended Diploma (BTEC_NED), international.
-- Not here: reading the held tables again is a separate migration, merged after worker v0.74.0 is deployed and verified.
-- Replaces: nothing (new settings and reference rows; three switch values).
-- Retires: nothing.
-- Reversal without code: each setting back to 0 (or its list emptied); the two qualifications stay as reference rows.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'reading.entry_quote_parts_on', 'Entry requirements: prove a heading + cell quote by its parts',
  '1 accepts a quote the model wrote as a heading and a cell ("China Entry Requirements Completion of ...", "COUNTRY: Uganda | Undergraduate Entry: ...") when every part is printed on the page, in order and close together (reading.entry_quote_window_chars); the row records quote_proof "parts". The grade and value must still be printed in the quote. 0 drops such rows as quote_not_on_page.',
  'number', to_jsonb(1), 0, 1, 'switch', 1146, 'Entry requirements', 'coverage-sweep entry_ai (entry.ts quoteInParts)', 'Platform Admin mandate 12 Nov 2026 09:23: reusable reader fixes (Charles Sturt, Charles Darwin, UTS, Curtin, Federation)'),
 ('pipeline', 'reading.entry_quote_window_chars', 'Entry requirements: how close a quote''s parts must be',
  'A quote proven by its parts needs all of them within this many letters and digits of the page.',
  'number', to_jsonb(600), 100, 3000, 'characters', 1147, 'Entry requirements', 'coverage-sweep entry_ai (entry.ts quoteInParts)', 'CF-247 F-AER.10'),
 ('pipeline', 'reading.entry_band_label_words', 'Entry requirements: column labels a band may carry',
  'A band given with its column label ("ATAR equivalent: 98", "Rank / ATAR 80") is the printed number alone when the label contains one of these words. A band name such as "B2" or "Band 3" is never cut.',
  'list', '["ATAR", "rank", "selection rank", "entrance rank"]'::jsonb, null, null, 'words', 1148, 'Entry requirements', 'coverage-sweep entry_ai (entry.ts entryBandNumber)', 'CF-247 F-AER.10: UWA 41 band rows'),
 ('pipeline', 'reading.entry_qualification_countries', 'Entry requirements: national qualification frameworks and their country',
  'FRAMEWORK=CC: a row that names no country but whose qualification is that country''s own framework ("AQF bachelor''s degree") is that country''s row; recorded as country_from_qualification. A name naming two frameworks gets no country.',
  'list', '["AQF=AU"]'::jsonb, null, null, 'frameworks', 1149, 'Entry requirements', 'coverage-sweep entry_ai (entry.ts entryQualificationCountry)', 'CF-247 F-AER.10: Wollongong AQF rows')
on conflict (toolset_key, key) do nothing;

update pipeline.platform_toolset_settings set value = to_jsonb(1), updated_at = now(),
       reason = 'Platform Admin mandate 12 Nov 2026 09:23 (fix at the reader level, reusable): UWA China ranges (8 rows), read again with v0.74.0'
 where toolset_key = 'pipeline' and key = 'reading.entry_range_lower_bound_on' and value = to_jsonb(0);
update pipeline.platform_toolset_settings set value = to_jsonb(1), updated_at = now(),
       reason = 'Platform Admin mandate 12 Nov 2026 09:23 (fix at the reader level, reusable): UWA AP and HKDSE subject rows (2 identity conflicts)'
 where toolset_key = 'pipeline' and key = 'reading.entry_subject_rows_on' and value = to_jsonb(0);
update pipeline.platform_toolset_settings set value = to_jsonb(1), updated_at = now(),
       reason = 'Platform Admin mandate 12 Nov 2026 09:23 (fix at the reader level, reusable): a count with no scale (Federation, Curtin College) keeps its printed grade, no number'
 where toolset_key = 'pipeline' and key = 'reading.entry_value_null_on' and value = to_jsonb(0);

insert into ref.aer_qualifications(code, family, name, awarding_body, level, scope, country_code, grading_scheme, aliases, notes) values
 ('GCE_O', 'GCE Ordinary Level', 'GCE O Level', 'UK and Commonwealth awarding bodies (Cambridge, Singapore-Cambridge)', 'subject_level', 'international', null, 'Grades A to E (or 1 to 9)',
  array['gce o level', 'gce o levels', 'o level', 'o levels', 'gce ordinary level', 'general certificate of education o level', 'general certificate of education gce o levels'],
  'CF-247 F-AER.10 (12 Nov 2026): Victoria University prints it'),
 ('BTEC_NED', 'Pearson BTEC', 'Pearson BTEC Level 3 National Extended Diploma', 'Pearson', 'upper_secondary', 'international', null, 'Distinction*, Distinction, Merit, Pass',
  array['btec level 3 national extended diploma', 'btec national extended diploma', 'business and technology education council level 3 national extended diploma', 'btec extended diploma'],
  'CF-247 F-AER.10 (12 Nov 2026): Victoria University of Wellington prints it')
on conflict (code) do nothing;

do $c$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and value = to_jsonb(1)
        and key in ('reading.entry_quote_parts_on', 'reading.entry_range_lower_bound_on', 'reading.entry_subject_rows_on', 'reading.entry_value_null_on')) <> 4 then
    raise exception 'post-check: the four reader switches are not on';
  end if;
  if (select count(*) from ref.aer_qualifications where code in ('GCE_O', 'BTEC_NED')) <> 2 then raise exception 'post-check: qualifications'; end if;
end $c$;
