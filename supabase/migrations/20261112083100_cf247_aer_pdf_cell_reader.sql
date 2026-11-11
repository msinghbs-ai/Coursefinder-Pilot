-- CF-247 F-AER.07 PDF cell reader (Platform Admin 11 Nov 2026 16:20: "build a reader for WSU based on the PDF and make the button available in Layer 4 ... reader need
-- to recognise Country, qualification and minimum requirement in accordance with Country and their Education Boards"; qualification-first decision 11 Nov 2026 item 5:
-- "Update the PDF table reader to identify country, education board, qualification, academic level, grading scale and minimum requirement for every applicable row or cell").
-- Guards: G1 (no job), G2 (the switch and the shape limits are settings), G3 (no consumer API object), Decision 260, Layer 4 authority unchanged (the reader's rows are
--   proposed on the same entry-matrix item and admitted only by a person's decision).
-- Evidence (production, read only, 11 Nov 2026 16:10-19:40 AEDT): WSU's Entry Qualifications PDF (source 926b1925, stored copy 92aadee2...) was read by the model on
--   29 Oct: 367 rows kept and 25 dropped (grade_not_in_quote 16, quote_not_on_page 2, unknown_country 7), so the read is held by D-R3 and its Layer 4 item 763ece39
--   offers only Reject the read. The dropped rows are cells that name two education boards with a minimum each (Nepal HSC pre-2018 or NEB GPA; China Gao Er or
--   specialised school) and the GAC and IB rows. pdfTables already proves the table (11 tables, 7 columns, one line per cell). Read cell by cell (worker v0.71.0,
--   entry-cells.ts) against that stored copy: 456 cells, 468 country rows across 72 countries (35 board rows, every cell's minimum and scale printed in its quote),
--   8 qualification rows (GAC 3, IB Certificate 5), 4 "Not applicable" cells kept as no_minimum_published, 0 rows dropped by the parser.
-- What:
--   1. Settings: reading.entry_cell_reader_on (1), reading.entry_cell_min_levels (4), reading.entry_cell_min_lines (20).
--   2. security.layer4_aer_recovery_state_v1 (md5-guarded edit): a provider-table item no longer fails with "record v_sup is not assigned yet" (the record is set
--      empty before either branch reads it), so Layer 4 shows the recovery panel of every provider-table item again.
-- Not here: reading WSU's stored copy again is a separate migration, merged after worker v0.71.0 is deployed and verified (a migration is applied before the
--   functions deploy on merge, so a re-read in this change could be picked up by the old worker).
-- Live definition this change edits (md5 of pg_get_functiondef, read 11 Nov 2026 19:50 AEDT):
--   security.layer4_aer_recovery_state_v1(uuid) caf0e61bfcf983fb421638afd3aea795
-- Replaces: security.layer4_aer_recovery_state_v1 (same name and signature; md5-guarded text edit)
-- Retires: nothing.
-- Reversal without code: reading.entry_cell_reader_on 0 (every page goes to the model as before).

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'reading.entry_cell_reader_on', 'Entry requirements: read PDF country tables cell by cell',
  '1 reads a proven PDF entry table that has one line per cell (a country, an education board or an international qualification, by study-level columns) without the model: each cell gives one row per education board that prints its own minimum, with the minimum, its scale and the qualification as printed. The rows go through the same checks as a model''s answer and to the same Layer 4 item. 0 sends every page to the model as before.',
  'number', to_jsonb(1), 0, 1, 'switch', 1520, 'Entry requirements', 'coverage-sweep entry_ai (entry-cells.ts)',
  'Platform Admin 11 Nov 2026 16:20 (build a reader for WSU from the PDF) and qualification-first decision item 5'),
 ('pipeline', 'reading.entry_cell_min_levels', 'Entry requirements: fewest study-level columns for the cell reader',
  'A PDF table is read cell by cell only when it has at least this many study-level columns (otherwise the model reads it).',
  'number', to_jsonb(4), 2, 20, 'columns', 1521, 'Entry requirements', 'coverage-sweep entry_ai (entry-cells.ts)', 'CF-247 F-AER.07: WSU has 6'),
 ('pipeline', 'reading.entry_cell_min_lines', 'Entry requirements: fewest cell lines for the cell reader',
  'A PDF table is read cell by cell only when it gives at least this many cell lines (otherwise the model reads it).',
  'number', to_jsonb(20), 5, 5000, 'lines', 1522, 'Entry requirements', 'coverage-sweep entry_ai (entry-cells.ts)', 'CF-247 F-AER.07: WSU has 456')
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

select pg_temp.edit_n('security.layer4_aer_recovery_state_v1(uuid)', 'caf0e61bfcf983fb421638afd3aea795', array[
  array[$o$  select * into r from pipeline.layer4_review_items where id = p_item;
  if r.id is null$o$,
        $n$  select * into r from pipeline.layer4_review_items where id = p_item;
  -- F-AER.07 (11 Nov 2026): the corrected-read record exists before either branch reads it (a provider-table item never sets it)
  select null::text state, null::text outcome, null::timestamptz requested_at, null::uuid new_item_id into v_sup;
  if r.id is null$n$]
], array[1]);

do $p$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('reading.entry_cell_reader_on', 'reading.entry_cell_min_levels', 'reading.entry_cell_min_lines')) <> 3 then
    raise exception 'post-check: cell reader settings missing'; end if;
  -- the recovery panel of the waiting WSU provider-table item reads without an error
  perform security.layer4_aer_recovery_state_v1(id) from pipeline.layer4_review_items where field_code in ('entry_matrix_first_run', 'entry_matrix_change') and status = 'pending';
end $p$;
