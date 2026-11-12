-- CF-247 F-AER.10: read the eight held country tables again with the reusable reader fixes (Platform Admin mandate 12 Nov 2026 09:23 §1: "Fix UWA's ... at the reader
-- level ... Continue repairing UTS, CSU, Curtin, Wollongong and VU using reusable reader improvements. Reprocess stored evidence without unnecessary new AI or
-- Firecrawl expenditure").
-- Guards: G1 (no job), G2 (no new value), G3 (no consumer API object), Decision 260, Layer 4 authority unchanged (each read is proposed on a new item).
-- Evidence: worker v0.74.0 deployed with #1053 (verified live 12 Nov 2026 11:20 AEDT: coverage-sweep answers v0.74.0; reading.entry_quote_parts_on,
--   entry_range_lower_bound_on, entry_subject_rows_on, entry_value_null_on 1; GCE_O and BTEC_NED served). The waiting reads (all of the source's current stored copy,
--   read directly, none taken by a person): UWA 185 rows / 8 dropped, 41 band flags, 2 identity groups; Federation 77 / 5; Charles Darwin 43 / 12; Charles Sturt 14 / 16;
--   Curtin 34 / 1; UTS 42 / 2; Wollongong 241 / 17; Victoria University 147 / 2. Each is read once more by the model from its stored copy (no Firecrawl).
-- Replaces: nothing. Retires: nothing.

do $r$
declare v jsonb; ids uuid[] := array['74306034-c24a-4ed8-a859-1770edd7ab0b', '58c60102-e549-4482-be03-7b6358059ada', '01139439-b952-4a53-891c-60e593c01cd1',
                                     '7fd6e509-324a-4039-9706-a863e2bcc6d6', '30ceba77-2972-400e-b51c-e6139964a2f5', '7675875e-11f2-4dc5-a89c-b7a87e4c6f6d',
                                     'c9a5c1d5-8334-4fd6-89f7-f194deb5ad53', 'a84c16f4-7ada-4319-b900-b0e07eacabcf']::uuid[];
begin
  if security.pipeline_num_v1('reading.entry_quote_parts_on', 0) < 1 then raise notice 'the reader fixes are not on: nothing read again'; return; end if;
  -- a source whose waiting item a person has taken is left to that person
  ids := array(select u from unnest(ids) u where not exists (
           select 1 from pipeline.entry_matrix_runs r join pipeline.layer4_review_items li on li.id = r.review_item_id
            where r.source_id = u and li.status = 'pending' and (li.claimed_at is not null or li.assigned_to is not null)));
  if cardinality(ids) = 0 then raise notice 'every item is taken by a person: nothing read again'; return; end if;
  v := public.admin_entry_matrix_reread(ids, 'F-AER.10: read again with the reusable reader fixes of worker v0.74.0 (Platform Admin mandate 12 Nov 2026 09:23 §1)');
  raise notice 'reread: %', v;
  if coalesce((v->>'runs')::int, 0) = 0 then raise exception 'post-check: nothing queued (%)', v; end if;
end $r$;
