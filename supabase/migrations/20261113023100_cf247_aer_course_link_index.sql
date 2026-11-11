-- CF-247 F-AER.08 production verification: UNSW's grid read is recorded within the statement time (Platform Admin mandate 12 Nov 2026 09:23: "If production
-- verification fails ... correct the root cause and continue autonomously").
-- Guards: G1 (no job), G2 (no new value), G3 (catalogue.courses is read by the consumer API: two indexes are added beside it; no column, function or row of it is
--   altered, dropped, renamed or retyped), Decision 260, Layer 4 authority unchanged.
-- Evidence (production, 12 Nov 2026 10:24-10:45 AEDT): UNSW's grid read (2,257 rows) failed three times, the last as "svc_entry_matrix_record: canceling statement due to
--   statement timeout" (the first try was also stopped by the worker call's CPU limit, fixed in v0.74.1). Sydney (2,047 rows, linked by CRICOS code) and UQ (1,430
--   rows, 383 courses) were recorded. UNSW links by title: each new printed course compares its key with every one of its 667 courses' canonical and display
--   titles, computing the key each time (65 labels x 1,334 keys), inside the one statement that records the read.
-- What:
--   1. Expression indexes on catalogue.courses (provider_id, security.entry_course_title_key_v1(canonical_title | display_title)): the title rule of
--      security.entry_course_link_v1 becomes an index lookup (the function is immutable; the query is unchanged).
--   2. UNSW's stored PDF is read again (no model, no Firecrawl), unless a person has taken its item.
-- Replaces: nothing. Retires: nothing.

create index if not exists courses_title_key_ix on catalogue.courses (provider_id, security.entry_course_title_key_v1(canonical_title));
create index if not exists courses_display_title_key_ix on catalogue.courses (provider_id, security.entry_course_title_key_v1(display_title));

do $r$
declare v jsonb; ids uuid[] := array['b1222e5d-04c2-4964-a574-3630258da766']::uuid[];
begin
  ids := array(select u from unnest(ids) u where not exists (
           select 1 from pipeline.entry_matrix_runs r join pipeline.layer4_review_items li on li.id = r.review_item_id
            where r.source_id = u and li.status = 'pending' and (li.claimed_at is not null or li.assigned_to is not null)));
  if cardinality(ids) = 0 then raise notice 'the item is taken by a person: nothing read again'; return; end if;
  v := public.admin_entry_matrix_reread(ids, 'F-AER.08 production verification: UNSW grid read again after the course-title index (statement timeout)');
  raise notice 'reread: %', v;
end $r$;
