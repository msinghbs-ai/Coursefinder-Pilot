-- CF-247 AER D3: governed recovery of the R1 leftovers (Platform Admin mandate 30 Oct 2026 08:45, D3: "GOVERNED RECOVERY APPROVED, NO
-- IDENTITY WEAKENING ... Ceiling: 35 Firecrawl credits, no AI. Preserve history"). Decision: admin decision §11 (recorded before code).
-- The 35 pages left by R1 (migration 20261030060000), reconciled live at 09:30 AEDT:
--   7 "still waiting": each had its single R1 attempt (read, CRICOS not found on the page; next read 5 Nov). Not read again here.
--   6 needs render (Federation 5, UNSW handbook 1): one rendered recovery attempt now (the reader renders needs_render pages in render
--     countries; AU is one). The read binds only on a fresh CRICOS proof, as before.
--   4 fetch failed (Federation 1, Sydney 1 PDF, UWA 2): one bounded retry now (read_attempts 3 -> 2); none is leased.
--   13 adapter-code proofs (Flinders handbook): not restored. The reader promotes ambiguous pages only on a CRICOS proof and no approved,
--     documented rule promotes on an adapter code; 5 of the 13 pages name a different course or variant. Listed as an evidence gap.
--   2 blocked (QUT): left blocked (read_attempts 3; no read).   3 identity mismatches: left unbound; investigated read-only.
-- Nothing is bound, deleted or rewritten by this migration; it only brings forward one read of 10 pages. The values before are kept in the
-- audit event. Firecrawl: at most one scrape a page (10 credits) within the 35-credit ceiling. No AI is called by a page read.
-- Actor: the Platform Admin.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, setting or status.

do $$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';
        v_render constant uuid[] := array['548cd554-2198-4106-9a13-9b4f30c53ac9', '042b5dd8-f6b9-4c56-88c7-955e837f81d0', '30b03bb2-965a-496c-9b7d-134253db36c3',
                                          '61fc81d2-231a-4a17-8995-87c6b6fa3f4a', '9be91850-84d3-48de-a06a-9591d86de118', '3ae13d92-9a51-47f5-97bb-d5ec6fb8731e']::uuid[];
        v_fetch constant uuid[] := array['ac8a883e-23e4-4b49-bf53-f27ab4de909f', 'f5503aa1-e75d-404a-ade1-bbe5ca17806c', '02ae763b-859a-41f8-ab9c-7319fffbc5dc',
                                         '88213ecb-e709-43b3-8b36-57e014409535']::uuid[];
        v_before jsonb; v_n int;
begin
  if exists (select 1 from pipeline.admin_control_events where area = 'coverage' and action = 'd3_recovery') then raise exception 'D3: the recovery has already been queued'; end if;
  select count(*) into v_n from pipeline.coverage_course_pages where course_id = any (v_render) and status = 'ambiguous' and read_status = 'needs_render'
     and coalesce(leased_until, '-infinity') < now() and security.render_country_v1(provider_id);
  if v_n <> 6 then raise exception 'D3 precondition: % of 6 needs-render pages as reconciled', v_n; end if;
  select count(*) into v_n from pipeline.coverage_course_pages where course_id = any (v_fetch) and status = 'ambiguous' and read_status = 'fetch_failed'
     and read_attempts = 3 and coalesce(leased_until, '-infinity') < now();
  if v_n <> 4 then raise exception 'D3 precondition: % of 4 fetch-failed pages as reconciled (or a read is running)', v_n; end if;
  select jsonb_agg(jsonb_build_object('course_id', course_id, 'url', url, 'status', status, 'read_status', read_status, 'read_attempts', read_attempts,
                                      'next_read_at', next_read_at)) into v_before
    from pipeline.coverage_course_pages where course_id = any (v_render || v_fetch);

  update pipeline.coverage_course_pages set next_read_at = now(), leased_until = null where course_id = any (v_render) and read_status = 'needs_render';
  get diagnostics v_n = row_count; if v_n <> 6 then raise exception 'D3: % needs-render pages updated, expected 6', v_n; end if;
  update pipeline.coverage_course_pages set next_read_at = now(), read_attempts = 2, leased_until = null where course_id = any (v_fetch) and read_status = 'fetch_failed' and read_attempts = 3;
  get diagnostics v_n = row_count; if v_n <> 4 then raise exception 'D3: % fetch-failed pages updated, expected 4', v_n; end if;

  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('coverage', 'd3_recovery', 'migration 20261030230000',
          jsonb_build_object('reason', 'CF-247 D3 governed recovery of R1 leftovers (Platform Admin mandate 30 Oct 2026 08:45)', 'ceiling_firecrawl_credits', 35, 'ai_spend', 0,
                             'queued_at', now(), 'render', to_jsonb(v_render), 'fetch_retry', to_jsonb(v_fetch), 'before', v_before,
                             'not_restored_adapter_code', 13, 'left_blocked', 2, 'left_mismatch', 3, 'attempt_complete', 7), v_pa);
end $$;
