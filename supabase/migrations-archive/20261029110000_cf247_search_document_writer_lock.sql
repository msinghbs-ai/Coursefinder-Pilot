-- CF-247 decision W27 (Platform Admin mandate 29 Oct 2026 16:59, Workstream 0; admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md §7,
-- root cause in docs/platform/ui-audit/2026-10-29-scholarship-deadlock-reconciliation.md).
-- The scholarship paste (214 calls of security.scholarship_sweep_apply_v1 in one transaction, each refreshing its courses' search documents
-- through search.refresh_course_enrichment_scoped_v1) deadlocked at 16:26 with the scheduled full rebuild (job 39 search-refresh-requested
-- -> search.refresh_course_documents_v3): no writer of search.course_documents coordinated with another, and each locked rows in its own
-- plan order. One transaction-scoped advisory lock now serialises every writer:
--   * search.refresh_course_enrichment_scoped_v1 (the shared choke point for every scoped writer) and search.refresh_course_documents_v3
--     (every full rebuild) wait for it when they apply; a long transaction keeps it until it commits;
--   * the scheduled security.search_refresh_requested_v1 only tries it; when another writer holds it, it returns 'held' and leaves the
--     requests unprocessed for its next run (nothing lost, nothing waits behind a long paste);
--   * the scoped refresh also locks its documents in ascending course_id before updating (a defined row order within a call).
-- Unchanged: every document value written, generated_at behaviour, the consumer API shape (G3), scholarship relationship rules, admission
-- gates and Layer 4. A writer that previously waited on the rebuild's row locks now waits on the writer lock instead, for the same time.
-- Replaces: search.refresh_course_enrichment_scoped_v1, search.refresh_course_documents_v3, security.search_refresh_requested_v1 (same names, md5-guarded edits)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No new job, table, setting or status.

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

-- 1. The shared scoped refresh: wait for the writer lock, then lock the requested documents in ascending course_id.
select pg_temp.edit_n('search.refresh_course_enrichment_scoped_v1(uuid[],boolean)', '52bff5be91bdbab2ce6d63031c5652c7', array[
  array[$o$  v_result := search.refresh_course_enrichment_core_scoped_v1(p_course_ids, p_apply);$o$,
        $n$  if p_apply then
    perform pg_advisory_xact_lock(hashtext('cf247:search_course_documents_writer'));  -- fixed: the one writer lock for search.course_documents (W27)
    perform 1 from search.course_documents d where d.course_id = any(p_course_ids) order by d.course_id for update;
  end if;
  v_result := search.refresh_course_enrichment_core_scoped_v1(p_course_ids, p_apply);$n$]], array[1]);

-- 2. Every full rebuild: wait for the writer lock when applying.
select pg_temp.edit_n('search.refresh_course_documents_v3(boolean)', '40dc6d9707ad5a1cb019e525e3b887cb', array[
  array[$o$begin
  v_base:=search.refresh_course_base_v3(p_apply);$o$,
        $n$begin
  if p_apply then
    perform pg_advisory_xact_lock(hashtext('cf247:search_course_documents_writer'));  -- fixed: the one writer lock for search.course_documents (W27)
  end if;
  v_base:=search.refresh_course_base_v3(p_apply);$n$]], array[1]);

-- 3. The scheduled run never waits: when another writer holds the lock, its requests wait for the next run.
select pg_temp.edit_n('security.search_refresh_requested_v1()', 'bb78c8546a649ffb17ff0e676c7031e5', array[
  array[$o$  r := search.refresh_course_documents_v3(true);$o$,
        $n$  if not pg_try_advisory_xact_lock(hashtext('cf247:search_course_documents_writer')) then  -- fixed: the one writer lock (W27)
    return jsonb_build_object('pending', cardinality(v_ids), 'held', 'another search-document writer is running; the requests wait for the next run');
  end if;
  r := search.refresh_course_documents_v3(true);$n$]], array[1]);
