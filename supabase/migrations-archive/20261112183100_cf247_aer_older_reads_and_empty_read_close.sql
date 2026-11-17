-- CF-247 F-AER.09: read again the four held country tables that older readers read, and close a stale "empty read" request once the provider's table is live
-- (Platform Admin 11 Nov 2026 23:32 "Proceed" on the review pack of the 11 waiting tables, workstream A).
-- Guards: G1 (no job), G2 (nothing in code), G3 (no consumer API object), Decision 260, Layer 4 authority unchanged: each new read goes to a person on its own
--   entry-matrix item (or to rule aer-matrix-machine-v1 under decision D1); nothing is admitted here.
-- Evidence (production, read only, 11 Nov 2026 23:35 AEDT): the review pack found the waiting reads of UWA (worker v0.52.0, 8 rows dropped value_not_in_quote),
--   Federation (v0.52.0, 7 dropped), Adelaide (v0.50.1, 1 dropped) and Charles Darwin (v0.59.4, 8 dropped) held by D-R3 with only Reject the read open; each was
--   read before the PDF column fidelity, per-cell lines, quote proof and qualification-first readers (v0.51.0 to v0.71.0). Their stored copies are current (the
--   read's content hash equals the source's). None of the four items is taken by a person. The five tables read today by v0.70.0 (UTS, CSU, Curtin, Wollongong,
--   VU) are NOT read again here: the same reader would repeat their drops; they need reader fixes.
--   WSU's "Human input needed" item 395 (aer_empty_read, 09:14 UTC) stayed open after its country table was approved at 23:31 AEDT, because the recheck for
--   aer_empty_read only counts course-level requirements. 11 aer_empty_read items are open; 4 would clear with the corrected recheck.
-- Dry run (rolled back, 23:37 AEDT): the re-read queued 4 runs, superseded 4 items and 314 proposed rows, skipped none.
-- Live definition this change edits (md5 of pg_get_functiondef, read 11 Nov 2026 23:38 AEDT):
--   security.har_aer_recheck_v1(bigint) e0c47bda3839960013077b57328c1d55
-- What:
--   1. security.har_aer_recheck_v1: aer_empty_read is also cleared when the provider has an active country-table row (a read that was empty for courses is no
--      longer needed once the provider's own table is live); the job layer4-interventions (14 and 44 past the hour) closes those items with its usual record.
--   2. public.admin_entry_matrix_reread for the four sources (earlier result kept; one model read each by the pinned entry model; no Firecrawl).
-- Replaces: security.har_aer_recheck_v1 (same name and signature; md5-guarded text edit).
-- Retires: nothing.

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

select pg_temp.edit_n('security.har_aer_recheck_v1(bigint)', 'e0c47bda3839960013077b57328c1d55', array[
  array[$o$               where c.provider_id = i.provider_id and x.status in ('proposed', 'active') and x.created_at >= i.created_at)$o$,
        $n$               where c.provider_id = i.provider_id and x.status in ('proposed', 'active') and x.created_at >= i.created_at)
      -- F-AER.09 (11 Nov 2026): or the provider's own country table is live
      or exists (select 1 from catalogue.provider_entry_matrix m where m.provider_id = i.provider_id and m.status = 'active')$n$]
], array[1]);

do $r$
declare v jsonb; ids uuid[] := array['74306034-c24a-4ed8-a859-1770edd7ab0b', '58c60102-e549-4482-be03-7b6358059ada', '18e64f94-d2a5-479f-846b-1c5db07cc65b',
                                     '01139439-b952-4a53-891c-60e593c01cd1']::uuid[];
begin
  -- a source whose waiting item a person has taken is left to that person
  ids := array(select u from unnest(ids) u where not exists (
           select 1 from pipeline.entry_matrix_runs r join pipeline.layer4_review_items li on li.id = r.review_item_id
            where r.source_id = u and li.status = 'pending' and (li.claimed_at is not null or li.assigned_to is not null)));
  if cardinality(ids) = 0 then raise notice 'every item is taken by a person: nothing read again'; return; end if;
  v := public.admin_entry_matrix_reread(ids,
        'F-AER.09: read by an older reader (v0.50 to v0.59) and held by D-R3; read again with the current reader (review pack, Platform Admin 11 Nov 2026 23:32)');
  raise notice 'reread: % of 4 sources: %', cardinality(ids), v;
  if coalesce((v->>'runs')::int, 0) = 0 then raise exception 'post-check: no source was queued again (%)', v; end if;
  -- post-check: WSU's empty-read request now clears on its recheck
  if not coalesce((security.har_aer_recheck_v1(395)->>'cleared')::boolean, false) then raise exception 'post-check: item 395 does not clear'; end if;
end $r$;
