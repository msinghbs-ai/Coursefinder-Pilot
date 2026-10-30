-- CF-247 StudySearch transformation, finding F1 (Platform Admin mandate 31 Oct 2026 10:23; decision and evidence lodged first in admin
-- docs/platform/nz-enrichment-brief/2026-10-31-studysearch-transformation.md section 7): the provider-level checks in two scheduled pipeline
-- functions are evaluated once per provider instead of once per row.
-- Why (verified live 31 Oct 2026, rolled-back dry runs only): job waste-guard (security.waste_guard_v1) spent 115 to 120 s of its 120 s statement
-- limit in security.enrichment_flags_refresh_v1, failing 14 of 24 runs on 30-31 Oct; job coverage-ai-match-prepare (security.
-- coverage_ai_match_prepare_v1) ran a median 47.7 s with time-outs. Each called provider-level checks (enrich_focus_v1, course_search_off_v1,
-- course_list_read_v1, bind_match_scope_v1, about 1 ms each) once per course, AI-match row or flag: 9,145 courses, 53,807 AI-match rows (up 8%
-- since the 29 Oct onset), 11,297 and 5,932 open flags.
-- What: each such check is computed once over a materialised list of the distinct providers and joined back (MATERIALIZED, because the
-- planner otherwise pushes the check below the DISTINCT and evaluates it per row again). The rules, the rows written and every setting are
-- unchanged. A flag with no provider keeps the per-row check (none exists today).
-- Proof (rolled back, 31 Oct 2026): identical row sets, old against new: outside focus 9,145 = 9,145; page not found 2,128 = 2,128 on 17,888
-- AI-match rows of 400 providers (the old form cannot finish the whole table inside a test window); flag clearing 11,297 = 11,297 and
-- 5,932 = 5,932 (checks inverted to exercise non-empty sets); AI-match scope 142 = 142 providers on 6,799 courses. Timings: the new
-- enrichment_flags_refresh_v1 15.3 s (was 115 to 120 s); the new coverage_ai_match_prepare_v1 19.4 s (median was 47.7 s).
-- Not changed: the 120 s time-out, the job schedules, the job commands, any consumer API object (Decision 266), any data.
-- Replaces: security.enrichment_flags_refresh_v1, security.coverage_ai_match_prepare_v1 (same names; md5-guarded edits)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No new table, column, job, setting or status.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_once('security.enrichment_flags_refresh_v1()', 'ae5776259a0e5d35478494731cbcc75b', '3bbec96c35136e885e29885d145dd3b7', array[
  -- 1 outside focus: the focus check once per provider (a materialised list), not once per course
  array[$o$    insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
    select 'course', d.course_id::text, d.provider_id, 'course_page', 'outside_focus',$o$,
        $n$    insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
    with pv as materialized (select distinct d0.provider_id pid from search.course_documents d0 where d0.country_code = 'AU'),
    fp as materialized (select pv.pid from pv where not security.enrich_focus_v1(pv.pid))  -- 31 Oct 2026 (StudySearch F1): once per provider, not once per course
    select 'course', d.course_id::text, d.provider_id, 'course_page', 'outside_focus',$n$],
  array[$o$       and not security.enrich_focus_v1(d.provider_id)$o$,
        $n$       and d.provider_id in (select fp.pid from fp)$n$],
  -- 2 clearing outside-focus flags: once per provider among the open flags (a flag with no provider keeps the per-row check)
  array[$o$  update pipeline.enrichment_flags f set cleared_at = now()
   where f.reason_code = 'outside_focus' and f.cleared_at is null and (not v_on or security.enrich_focus_v1(f.provider_id));$o$,
        $n$  with pv as materialized (select distinct f0.provider_id pid from pipeline.enrichment_flags f0
                             where f0.reason_code = 'outside_focus' and f0.cleared_at is null and f0.provider_id is not null),
  fp as materialized (select pv.pid from pv where security.enrich_focus_v1(pv.pid))  -- 31 Oct 2026 (F1): once per provider
  update pipeline.enrichment_flags f set cleared_at = now()
   where f.reason_code = 'outside_focus' and f.cleared_at is null
     and (not v_on or (case when f.provider_id is null then security.enrich_focus_v1(f.provider_id) else f.provider_id in (select fp.pid from fp) end));$n$],
  -- 3 page not found: the course-search-off check once per provider, not once per AI-match row
  array[$o$  insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
  select 'course', q.course_id::text, max(q.provider_id::text)::uuid, 'official_url', 'page_not_found',$o$,
        $n$  insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
  with pv as materialized (select distinct q0.provider_id pid from pipeline.coverage_ai_match q0),
  so as materialized (select pv.pid from pv where not security.course_search_off_v1(pv.pid))  -- 31 Oct 2026 (F1): once per provider, not once per AI-match row
  select 'course', q.course_id::text, max(q.provider_id::text)::uuid, 'official_url', 'page_not_found',$n$],
  array[$o$     and not security.course_search_off_v1(q.provider_id)  -- 22 Oct 2026 (NZ review fix 8): the provider flag covers these$o$,
        $n$     and q.provider_id in (select so.pid from so)  -- 22 Oct 2026 (NZ review fix 8): the provider flag covers these$n$],
  -- 4 clearing page-not-found flags of providers whose course search is off: once per provider
  array[$o$  update pipeline.enrichment_flags f set cleared_at = now()
   where f.reason_code = 'page_not_found' and f.entity = 'course' and f.cleared_at is null and security.course_search_off_v1(f.provider_id);$o$,
        $n$  with pv as materialized (select distinct f0.provider_id pid from pipeline.enrichment_flags f0
                             where f0.reason_code = 'page_not_found' and f0.entity = 'course' and f0.cleared_at is null and f0.provider_id is not null),
  so as materialized (select pv.pid from pv where security.course_search_off_v1(pv.pid))  -- 31 Oct 2026 (F1): once per provider
  update pipeline.enrichment_flags f set cleared_at = now()
   where f.reason_code = 'page_not_found' and f.entity = 'course' and f.cleared_at is null
     and (case when f.provider_id is null then security.course_search_off_v1(f.provider_id) else f.provider_id in (select so.pid from so) end);$n$]],
  array[1, 1, 1, 1, 1, 1]);

select pg_temp.edit_once('security.coverage_ai_match_prepare_v1(integer,integer)', 'b7db293ca3f9ff521976bb074ed3a85e', 'ab2dd5dc2e897b20c9de8bbc84bd26eb', array[
  -- 5 the providers in scope: the three provider checks once per provider (a materialised list), not once per active course
  array[$o$    with missing as ($o$,
        $n$    with pv as materialized (select distinct co0.provider_id pid from catalogue.courses co0 where co0.lifecycle_status = 'active'),
    scope as materialized (  -- 31 Oct 2026 (StudySearch F1): the provider checks once per provider, not once per active course
      select pv.pid from pv
       where security.enrich_focus_v1(pv.pid)  -- CF-247 15 Oct: focus providers only (Waste rules)
          or security.course_list_read_v1(pv.pid)  -- 22 Oct 2026: and any provider with a read course list page
          or security.bind_match_scope_v1(pv.pid)),  -- SP-1: tranche overrides and the top Australian providers by courses without a page
    missing as ($n$],
  array[$o$         and (security.enrich_focus_v1(co.provider_id)  -- CF-247 15 Oct: focus providers only (Waste rules)
              or security.course_list_read_v1(co.provider_id)  -- 22 Oct 2026: and any provider with a read course list page
              or security.bind_match_scope_v1(co.provider_id))  -- SP-1: tranche overrides and the top Australian providers by courses without a page$o$,
        $n$         and co.provider_id in (select s.pid from scope s)  -- focus, read course list, or SP-1 bind scope (scope above)$n$]],
  array[1, 1]);

-- post-check: both functions carry the once-per-provider form and no per-row provider check is left in them
do $$
declare a text := pg_get_functiondef('security.enrichment_flags_refresh_v1()'::regprocedure);
        b text := pg_get_functiondef('security.coverage_ai_match_prepare_v1(integer,integer)'::regprocedure);
begin
  if a ~ 'enrich_focus_v1\((d|f)\.provider_id\)' and a !~ 'when f\.provider_id is null then security\.enrich_focus_v1\(f\.provider_id\)' then
    raise exception 'F1 post-check: a per-row focus check is left in enrichment_flags_refresh_v1'; end if;
  if a ~ 'course_search_off_v1\(q\.provider_id\)' then raise exception 'F1 post-check: a per-row course-search check is left in enrichment_flags_refresh_v1'; end if;
  if b ~ '(enrich_focus_v1|course_list_read_v1|bind_match_scope_v1)\(co\.provider_id\)' then
    raise exception 'F1 post-check: a per-row provider check is left in coverage_ai_match_prepare_v1'; end if;
end $$;
