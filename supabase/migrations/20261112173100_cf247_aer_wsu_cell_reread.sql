-- CF-247 F-AER.07: read WSU's stored Entry Qualifications PDF again with the PDF cell reader (Platform Admin 11 Nov 2026 16:20 "build a reader for WSU based on the PDF
-- and make the button available in Layer 4"; 22:22 "decide to merge PR 1034"). Applied after worker coverage-sweep v0.71.0 and migration 20261112163100 (#1034) are live
-- and verified.
-- Guards: G1 (no job), G2 (nothing in code), G3 (no consumer API object), Decision 260, Layer 4 authority unchanged: the new read goes to a person on a new entry-matrix
--   item (rule aer-matrix-machine-v1 keeps it with a person: its GAC and IB rows have unresolved applicability and some cells print no minimum); nothing is admitted here.
-- Evidence (production, read only, 11 Nov 2026 22:25 AEDT): source 926b1925-d209-4548-85d8-4cfdd4d6b125 (WSU, PDF, stored copy 92aadee2...) was read again by the model
--   (v0.70.0) at 22:07 under 20261112153700: 368 country rows and 7 qualification rows, 21 rows dropped (cells with two education boards; Taiwan), item 4e5619d3 held by
--   D-R3 with only Reject the read open. The cell reader reads the same stored copy (no fetch, no Firecrawl, no AI) into 461 country rows and 8 qualification rows with
--   nothing dropped and no two rows of one identity (fixture test cf-247-f-aer-07).
-- Dry run (rolled back, 11 Nov 2026 23:25 AEDT, after v0.71.0 was verified live byte-identical and 20261112163100 matched its file): 1 run queued, item 4e5619d3
--   and its 368 proposed rows superseded, nothing else touched.
-- What: public.admin_entry_matrix_reread for that one source, unless a person has taken its waiting item: the run's earlier result is kept in previous_results, its
--   proposed rows and waiting item are superseded, and the run is queued again; the next entry reading reads it with the cell reader.
-- Replaces: nothing. Retires: nothing.

do $r$
declare v jsonb;
begin
  if coalesce(security.pipeline_num_v1('reading.entry_cell_reader_on', 0), 0) < 1 then raise exception 'pre-check: the cell reader is not switched on'; end if;
  if not exists (select 1 from pipeline.entry_matrix_sources where id = '926b1925-d209-4548-85d8-4cfdd4d6b125'
                   and provider_id = '1719c3ba-1ddf-483e-935e-c750124ba99c' and content_hash = '92aadee2605f275c1502381c693b368a8f29b302905eaa2c0e7aed4b7fd37af6') then
    raise exception 'pre-check: WSU''s source or stored copy is not the one read in the test'; end if;
  if exists (select 1 from pipeline.entry_matrix_runs r join pipeline.layer4_review_items li on li.id = r.review_item_id
              where r.source_id = '926b1925-d209-4548-85d8-4cfdd4d6b125' and li.status = 'pending' and (li.claimed_at is not null or li.assigned_to is not null)) then
    raise notice 'WSU''s waiting item is taken by a person: left to that person, not read again'; return;
  end if;
  v := public.admin_entry_matrix_reread(array['926b1925-d209-4548-85d8-4cfdd4d6b125']::uuid[],
        'F-AER.07 PDF cell reader (worker v0.71.0): the model reads dropped rows on cells with two education boards (25 on 29 Oct, 21 on 11 Nov); Platform Admin 11 Nov 2026 16:20');
  raise notice 'reread: %', v;
  if coalesce((v->>'runs')::int, 0) <> 1 then raise exception 'post-check: WSU''s run was not queued again (%)', v; end if;
end $r$;
