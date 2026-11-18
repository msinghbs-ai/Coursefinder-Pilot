-- CF-247 AER bounded paid reads, step 3: R1 recovery of course pages wrongly displaced on 29 Oct 2026 (Platform Admin mandate 30 Oct 2026 06:53:
-- "R1 — APPROVED: recovery reads for up to the verified 714 wrongly displaced AU course pages, hard ceiling 714 Firecrawl credits, no AI spend").
-- Cause and manifest: admin docs/platform/ui-audit/2026-10-30-aer-enrichment-handback.md §3.8, decision W31 (20261030030000, live since
-- 30 Oct 00:55 AEDT: the site-map binder no longer touches code-proved pages). The manifest is the lane H query (read-only, re-run on
-- 30 Oct 07:15 AEDT): AU courses of entry.course_read_providers whose last coverage-sweep evidence before 29 Oct 14:15 AEDT proved them by
-- CRICOS or adapter code, that are not eligible now, and whose previous page is neither refused nor a past-year handbook:
--   A (451): same page, demoted to ambiguous on 29 Oct, still read -> read again now; the reader promotes ambiguous to bound ONLY when the
--            fresh read finds the course's CRICOS code (svc_coverage_read_record, unchanged).
--   B (263): page replaced on 29 Oct 14:15-14:47 AEDT -> the previous page is restored as ambiguous (read_status cleared) and read now; it
--            becomes bound ONLY on a fresh CRICOS proof. No page is bound by this migration; no identity rule changes.
-- Held (not touched): 73 past-year handbook pages (currency decision: past-year pages are not admitted as current), 3 refused pages, 32 others.
-- Ceiling: each page gets exactly one more read attempt (read_attempts set to 2 against the reader's limit of 3), so at most 714 page reads,
-- each at most one Firecrawl scrape (a direct fetch costs none). No AI is called by a page read. Preconditions: the manifest counts are
-- exactly 451 and 263, no manifest page is leased, no other recovery is waiting.
-- Actor: the Platform Admin.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, setting or status.

do $$
declare v_pa constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';
        v_reason constant text := 'R1 recovery read of a page displaced by the 29 Oct 2026 re-map (Platform Admin mandate 30 Oct 2026 06:53; W31)';
        v_a uuid[]; v_b jsonb; v_n int; v_leased int;
begin
  perform set_config('statement_timeout', '300s', true);
  with scope as (select (e.v)::uuid pid from jsonb_array_elements_text(security.toolset_setting('pipeline', 'entry.course_read_providers')) e(v)),
  el as (select course_id from security.course_entry_eligible_v1()),
  prev as (select distinct on ((metadata->>'course_id')) (metadata->>'course_id')::uuid course_id, source_url prev_url, metadata->>'identity_basis' prev_identity
             from pipeline.evidence_artifacts
            where created_at < '2026-10-29 03:15:00Z' and metadata->>'worker' = 'coverage-sweep' and metadata ? 'course_id'
            order by (metadata->>'course_id'), created_at desc),
  x as (select g.course_id, g.status, g.read_status, g.bound_at, g.leased_until, prev.prev_url,
               (g.url = prev.prev_url or coalesce(g.candidates->>'final_url', '') = prev.prev_url) same_page,
               prev.prev_url ~* '(archive|pubs/handbooks|pre20[0-9]{2}|/(200[0-9]|201[0-9]|202[0-4])(-20[0-9]{2})?/|rp-handbooks|handbook\.mq\.edu\.au/20)' prev_archived,
               security.page_refused_v1(g.course_id, prev.prev_url) prev_refused
          from pipeline.coverage_course_pages g
          join scope on scope.pid = g.provider_id
          join catalogue.courses c on c.id = g.course_id and c.lifecycle_status = 'active'
          join prev on prev.course_id = g.course_id
         where security.coverage_country(g.provider_id) = 'AU' and prev.prev_identity in ('cricos_code', 'adapter_code')
           and g.course_id not in (select course_id from el)),
  y as (select x.*, case when prev_refused or prev_archived then 'hold'
                         when same_page and status = 'ambiguous' and read_status = 'read' then 'A'
                         when not same_page and bound_at between '2026-10-29 03:15Z' and '2026-10-29 03:47Z' then 'B' else 'none' end cat from x)
  select array_agg(course_id) filter (where cat = 'A'),
         jsonb_agg(jsonb_build_object('course_id', course_id, 'prev_url', prev_url)) filter (where cat = 'B'),
         count(*) filter (where cat in ('A', 'B') and leased_until > now())
    into v_a, v_b, v_leased from y;

  if coalesce(array_length(v_a, 1), 0) <> 451 then raise exception 'R1 precondition: manifest A has % pages, expected 451', coalesce(array_length(v_a, 1), 0); end if;
  if coalesce(jsonb_array_length(v_b), 0) <> 263 then raise exception 'R1 precondition: manifest B has % pages, expected 263', coalesce(jsonb_array_length(v_b), 0); end if;
  if v_leased <> 0 then raise exception 'R1 precondition: % manifest pages are being read now', v_leased; end if;
  if exists (select 1 from pipeline.admin_control_events where area = 'coverage' and action = 'r1_recovery') then raise exception 'R1 precondition: the recovery has already been queued'; end if;

  -- A: the same page, read again once
  update pipeline.coverage_course_pages p set next_read_at = now(), read_attempts = 2, leased_until = null
   where p.course_id = any (v_a) and p.status = 'ambiguous' and p.read_status = 'read';
  get diagnostics v_n = row_count;
  if v_n <> 451 then raise exception 'R1: % A pages updated, expected 451', v_n; end if;

  -- B: the previous page restored as ambiguous and read once; bound only when the fresh read proves the CRICOS code
  update pipeline.coverage_course_pages p set url = b.prev_url, status = 'ambiguous', read_status = null, next_read_at = now(), read_attempts = 2, leased_until = null
    from (select (e->>'course_id')::uuid course_id, e->>'prev_url' prev_url from jsonb_array_elements(v_b) e) b
   where p.course_id = b.course_id;
  get diagnostics v_n = row_count;
  if v_n <> 263 then raise exception 'R1: % B pages updated, expected 263', v_n; end if;

  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('coverage', 'r1_recovery', 'migration 20261030060000',
          jsonb_build_object('reason', v_reason, 'ceiling_firecrawl_credits', 714, 'ai_spend', 0, 'queued_at', now(),
                             'a_same_page', to_jsonb(v_a), 'b_restored', v_b, 'attempts_each', 1), v_pa);
end $$;
