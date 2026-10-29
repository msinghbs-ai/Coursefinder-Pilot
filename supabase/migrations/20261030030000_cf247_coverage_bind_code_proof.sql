-- CF-247 decision W31 (30 Oct 2026, AER programme Workstream 4, course-page identity and eligibility; lane H investigation, read-only).
-- Finding: on 29 Oct 2026 the routine 30-day site re-map (remap.site_days) re-mapped 20 of the 21 AU reading-scope universities between
-- 14:10 and 14:43 AEDT, and job 47 coverage-bind (security.coverage_bind_tick_v1 -> security.coverage_bind_v2) re-bound them at 14:15,
-- 14:25 and 14:35. 789 AU courses lost a page whose stored copy the reader had proved with the course's CRICOS code (eligible AU courses
-- 4,977 -> 4,156): 509 kept the same page but were set to ambiguous, 280 had the page replaced by another title-matched page (UWA 162 now on
-- robots-blocked CMS paths, wrong degrees, a prize page). No weak page became eligible (every replacement failed the identity gate), so the
-- gates held; the binder itself was wrong. Two defects in security.coverage_bind_v2 (live md5 bc1872ed7df7d2837821600a8a18d55e):
--   1. the upsert protected a row only by its page basis (cricos_search, title_search, manual, ai_match) and never by the reader's proof,
--      so a page already read with a code proof was re-scored on title tokens alone and demoted or replaced;
--   2. the release step demoted pages the site-map binder never bound (firecrawl_search, serper_search, year_page_current, url_list, ...)
--      whenever they were not in the new map, and left no timestamp.
-- Correction (the smallest): the binder never overwrites, demotes or releases a page the reader has read with a code or manual proof
-- (identity_basis cricos_code, nzqa_code, adapter_code, manual) unless that page has been refused; and the release step only releases
-- rows the binder itself owns (basis title_match or a code basis it set). Identity, completeness and admission gates are unchanged; nothing
-- is re-bound, re-read or promoted by this migration (remediation of the 714 displaced courses is a separate manifest, BLOCKED on spend).
-- Must land before the next re-map (coverage_provider_discovery next_due_at 28 Nov 2026).
-- Replaces: security.coverage_bind_v2 (same name, md5-guarded edit)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No new job, table, setting or status value. Consumer API untouched (G3).

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

select pg_temp.edit_n('security.coverage_bind_v2(uuid)', 'bc1872ed7df7d2837821600a8a18d55e', array[
  -- 1. the upsert leaves a code-proved page alone
  array[$o$     and coalesce(pipeline.coverage_course_pages.basis,'') not in ('cricos_search','title_search','manual','ai_match');$o$,
        $n$     and coalesce(pipeline.coverage_course_pages.basis,'') not in ('cricos_search','title_search','manual','ai_match')
     -- W31 (30 Oct 2026): a page the reader has proved with a code or manual proof is never re-scored on title tokens (unless refused)
     and not (pipeline.coverage_course_pages.read_status = 'read'
              and pipeline.coverage_course_pages.identity_basis in ('cricos_code','nzqa_code','adapter_code','manual')
              and not security.page_refused_v1(pipeline.coverage_course_pages.course_id, pipeline.coverage_course_pages.url));$n$],
  -- 2. the release step releases only rows the binder owns, and never a code-proved page
  array[$o$   where p.provider_id=p_provider_id and p.status='bound' and coalesce(p.basis,'') not in ('cricos_search','title_search','manual','ai_match')$o$,
        $n$   where p.provider_id=p_provider_id and p.status='bound' and coalesce(p.basis,'') in ('title_match','cricos_code','nzqa_code','adapter_code')  -- W31: rows this binder bound
     and not (p.read_status = 'read' and p.identity_basis in ('cricos_code','nzqa_code','adapter_code','manual') and not security.page_refused_v1(p.course_id, p.url))$n$]
], array[1, 1]);

comment on function security.coverage_bind_v2(uuid) is 'CF-247 site-map binder: binds a provider''s active courses to pages of its mapped site by course code or title tokens. W31 (30 Oct 2026): a page the reader has proved with a code or manual proof (identity_basis cricos_code, nzqa_code, adapter_code, manual) is never re-scored, demoted or released by a re-map unless refused; the release step only releases rows this binder bound.';

-- post-check
do $g$ declare d text := pg_get_functiondef('security.coverage_bind_v2(uuid)'::regprocedure); begin
  if position('W31 (30 Oct 2026): a page the reader has proved' in d) = 0 then raise exception 'W31 post-check: upsert guard missing'; end if;
  if position($q$in ('title_match','cricos_code','nzqa_code','adapter_code')  -- W31: rows this binder bound$q$ in d) = 0 then raise exception 'W31 post-check: release step not limited'; end if;
end $g$;
