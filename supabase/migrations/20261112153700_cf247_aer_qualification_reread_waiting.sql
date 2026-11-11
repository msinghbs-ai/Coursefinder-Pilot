-- CF-247 F-AER.03 (country and qualification variants): read again the stored entry pages left out of 20261112070000 because their provider had an entry-matrix item
-- waiting, without a second Layer 4 item (Platform Admin decision delivery item 4, 11 Nov 2026, SS-017 / Operating Model v1.12: "Recover the 15 pending re-reads without
-- duplicate Layer 4 items").
-- Guards: G1 (no job), G2 (nothing in code), G3 (no consumer API object), Decision 260, Layer 4 authority unchanged: each new read goes to a person on its entry-matrix item
--   (or to rule aer-matrix-machine-v1 under decision D1); active rows stay active until the new read is approved.
-- Evidence (production, read only, 11 Nov 2026 22:00 AEDT): 20261112070000 left 15 sources for after the waiting decision. One has since been settled; 14 remain: their newest
--   done read on the current stored copy dropped rows as unknown_country whose heading is an every-country word (reading.entry_global_scope_tokens) or a recognised
--   international qualification (ref.aer_qualifications), which reader v0.70.0 keeps. For 13 of them the only waiting item is that source's own first read; for the ANU page
--   none of its own waits (its 22 other pages' items are other sources). None is taken by a person.
-- No duplicate: the governed re-read supersedes the source's own waiting item and its proposed rows before the run is queued again, so each source keeps exactly one
--   item when the new read records. Dry run (rolled back): 14 runs queued, 13 items superseded, 0 skipped, 0 claimed; pending entry-matrix items 66 -> 53 before the reads.
-- What: public.admin_entry_matrix_reread for those 14 sources (earlier result kept; no Firecrawl; one AI read each by the pinned entry model). Nothing else changes.
-- Replaces: nothing.
-- Retires: nothing.

do $r$
declare v jsonb; ids uuid[] := array['bd114da0-5a3d-46aa-bb69-5397bc4dc78e', '30ceba77-2972-400e-b51c-e6139964a2f5', '3a111cd8-14d4-4243-afed-cc5e46a3d224',
                                     'd74fcba4-a492-4cde-a1f0-70a398e6bfda', 'f40fe151-8a4d-4adf-9bbc-f87fcc7f540c', '8d669740-bfac-4c36-a1b0-c386cfd5042f',
                                     '7fc5311c-7911-4a99-91a8-439fd46cea55', '7675875e-11f2-4dc5-a89c-b7a87e4c6f6d', 'c9a5c1d5-8334-4fd6-89f7-f194deb5ad53',
                                     'a40e5a0b-d08d-49df-b630-05b73fd858a4', 'a84c16f4-7ada-4319-b900-b0e07eacabcf', '8b020b17-cb26-4d91-90c1-498062465a4a',
                                     'f06a01dd-d77e-48bc-b646-e669e22daffd', '926b1925-d209-4548-85d8-4cfdd4d6b125']::uuid[];
begin
  -- a source whose waiting item a person has taken is left to that person
  ids := array(select u from unnest(ids) u where not exists (
           select 1 from pipeline.entry_matrix_runs r join pipeline.layer4_review_items li on li.id = r.review_item_id
            where r.source_id = u and li.status = 'pending' and (li.claimed_at is not null or li.assigned_to is not null)));
  v := public.admin_entry_matrix_reread(ids,
        'F-AER.03 qualification-first (worker v0.70.0): earlier read dropped international-qualification rows as unknown_country; read again in place of its waiting item (decision delivery item 4, 11 Nov 2026)');
  raise notice 'reread: % of 14 sources: %', cardinality(ids), v;
  if coalesce((v->>'runs')::int, 0) = 0 then raise exception 'post-check: no source was queued again (%)', v; end if;
end $r$;
