-- CF-247 F-AER.08 recovery: read the held UNSW, Sydney and UQ entry PDFs again with the aligned grid reader (Platform Admin mandate 12 Nov 2026 09:23 §4: "Reprocess
-- stored evidence for UNSW, Sydney, UQ and Auckland ... Avoid duplicate records, invented equivalencies and unnecessary paid extraction").
-- Guards: G1 (no job), G2 (no new value), G3 (no consumer API object), Decision 260, Layer 4 authority unchanged (each read is proposed on a new item; rule D1 keeps grid
--   reads with a person while aer.grid_machine_admission_on is 0; course links per decision 2).
-- Evidence: worker v0.73.0 deployed with #1050 (verified live 12 Nov 2026 10:20 AEDT: coverage-sweep answers coverage-sweep-worker-v0.73.0; migration 20261112213100
--   applied; reading.entry_grid_reader_on 1). The three sources failed held_unparsed (no drawn rules); their stored copies are the fixtures the grid reader proves
--   (sha256 equal): UNSW 65 courses x 35 columns, Sydney 89 courses, UQ 54 courses; 5,734 minimums, none dropped by the parser. The stored copy is read: no Firecrawl,
--   no model.
-- Not here: Auckland (A-I and J-Z): its later pages print prose rows and a free-text column, which the grid proof holds (fail closed); a reader for them comes next.
-- Replaces: nothing. Retires: nothing.

do $r$
declare v jsonb; ids uuid[] := array['b1222e5d-04c2-4964-a574-3630258da766', '1f22a28d-0543-4e59-8d17-f696801a396e', '291cd06c-0232-40ae-9950-15fc1c5d19e4']::uuid[];
begin
  if security.pipeline_num_v1('reading.entry_grid_reader_on', 0) < 1 then raise notice 'reading.entry_grid_reader_on is 0: nothing read again'; return; end if;
  -- each source's stored copy is the one the grid reader was proven on
  if (select count(*) from pipeline.entry_matrix_sources s where (s.id, s.content_hash) in (
        ('b1222e5d-04c2-4964-a574-3630258da766'::uuid, 'be64345329d911fcaa1fab3b261f4529f39b32cd73832f4962f657f84112b0a9'),
        ('1f22a28d-0543-4e59-8d17-f696801a396e'::uuid, 'bb850ce1acc52800c2ee250233eb48ec58c8e1719c85c2d7373824c8eec198d1'),
        ('291cd06c-0232-40ae-9950-15fc1c5d19e4'::uuid, 'b0f7b80368299d165fd90c501ce647cbb7a885661a8dfcf10e2b10acfc9cf62d'))) <> 3 then
    raise exception 'pre-check: a stored copy changed since the grid reader was proven on it';
  end if;
  -- a source whose waiting item a person has taken is left to that person
  ids := array(select u from unnest(ids) u where not exists (
           select 1 from pipeline.entry_matrix_runs r join pipeline.layer4_review_items li on li.id = r.review_item_id
            where r.source_id = u and li.status = 'pending' and (li.claimed_at is not null or li.assigned_to is not null)));
  if cardinality(ids) = 0 then raise notice 'every item is taken by a person: nothing read again'; return; end if;
  v := public.admin_entry_matrix_reread(ids, 'F-AER.08: held PDF (no drawn rules) read again with the aligned grid reader, worker v0.73.0 (Platform Admin mandate 12 Nov 2026 09:23 §4)');
  raise notice 'reread: %', v;
  if coalesce((v->>'runs')::int, 0) <> cardinality(ids) then raise exception 'post-check: % of % sources queued (%)', v->>'runs', cardinality(ids), v; end if;
end $r$;
