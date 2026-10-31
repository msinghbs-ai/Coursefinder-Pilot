-- CF-247 StudySearch SS-007 integrity repair (Platform Admin mandate 1 Nov 2026 08:57, scheduled verification "SS-007 Batch A integrity";
-- admin docs/platform/nz-enrichment-brief/2026-10-31-studysearch-transformation.md §34).
-- Why (verified live 1 Nov 2026 10:40): decision D1 (Platform Admin 31 Oct 2026 13:30) held 177 courses and set their 167 published official
--   links 'unverified' (13:31 to 13:36; website official_url 167 -> 0, verified 13:39). At 14:30:00 the scheduled job coverage-admit set
--   all 167 back to 'active' (catalogue.course_links updated_at 2026-10-31 03:30:00.566382 UTC = that run's transaction time), and the
--   search refreshes of 31 Oct 14:xx and 1 Nov 07:xx published them again: 167 of 173 website items show a fee, application or general page
--   as official_url. Cause: security.coverage_admission_plan_v1 does not consult the SS-007 hold (security.course_held_v1); the held pages
--   keep their read result, so with no active link the plan proposed 'write'. Nothing else changed on held courses (no English, intake or
--   course rows; no Layer 4 items). No other scheduled writer re-activates official links (checked).
-- What:
--   1. coverage_admission_plan_v1 (md5-guarded edit): a course under an open binding remediation hold is never planned for admission.
--      Without this, the repair below would be undone by the next coverage-admit run (the plan shows 167 'same' now, 'write' after repair).
--   2. Restore the approved D1 state: exactly those 167 links (active, official_course, on an open hold, updated by that 14:30 run) are set
--      'unverified' again, as security.binding_remediation_apply_v1 did; count-guarded (167, ids md5 c0aff804); then a search refresh is requested.
--   No new correction: the same courses, links and status D1 approved; the 154 releases and 1,012 verification reads stay held (D11).
-- Rollback: re-apply the plan definition (md5 7390a600); set the 167 links (admin ss007-integrity-repair-links.csv) back to 'active'.
-- Replaces: security.coverage_admission_plan_v1 (same name; md5-guarded edit)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API shape untouched (G3): data only, restoring the consumer state D1 approved.

do $$
declare v text := pg_get_functiondef('security.coverage_admission_plan_v1(text)'::regprocedure);
  o text := $o$       and not security.layer4_entity_or_parent_blocked('course',p.course_id,'operational')),$o$;
  n text := $n$       and not security.layer4_entity_or_parent_blocked('course',p.course_id,'operational')
       and not security.course_held_v1(p.course_id)),  -- SS-007 (1 Nov 2026): a course under an open binding remediation hold is never admitted from its page$n$;
begin
  if md5(v) = 'f9dceaf2ff05e2b410d06ed968cfcac0' then raise notice 'plan: already applied'; return; end if;
  if md5(v) <> '7390a600044900f5d11d2be436e94ff6' then raise exception 'live coverage_admission_plan_v1 differs from the definition this change edits (md5 %)', md5(v); end if;
  if (length(v) - length(replace(v, o, ''))) / length(o) <> 1 then raise exception 'plan edit must apply exactly once'; end if;
  execute replace(v, o, n);
  if md5(pg_get_functiondef('security.coverage_admission_plan_v1(text)'::regprocedure)) <> 'f9dceaf2ff05e2b410d06ed968cfcac0' then
    raise exception 'plan after the edit has md5 %', md5(pg_get_functiondef('security.coverage_admission_plan_v1(text)'::regprocedure)); end if;
end $$;

do $$
declare v_n int; v_md5 text;
begin
  select count(*), md5(string_agg(l.id::text, ',' order by l.id)) into v_n, v_md5
    from catalogue.course_links l
   where l.link_type = 'official_course' and l.status = 'active' and l.updated_at = '2026-10-31 03:30:00.566382+00'  -- fixed: the coverage-admit run that re-activated them
     and exists (select 1 from pipeline.course_remediation_holds h where h.course_id = l.course_id and h.lifted_at is null);
  if v_n = 0 then raise notice 'SS-007 repair: already applied'; return; end if;
  if v_n <> 167 or v_md5 <> 'c0aff804f9a0465da788a65efd7987d7' then raise exception 'SS-007 repair: expected the 167 measured links (found %, md5 %)', v_n, v_md5; end if;
  update catalogue.course_links l set status = 'unverified', is_primary = false, updated_at = now()
   where l.link_type = 'official_course' and l.status = 'active' and l.updated_at = '2026-10-31 03:30:00.566382+00'  -- fixed: as above
     and exists (select 1 from pipeline.course_remediation_holds h where h.course_id = l.course_id and h.lifted_at is null);
  get diagnostics v_n = row_count;
  if v_n <> 167 then raise exception 'SS-007 repair: % rows', v_n; end if;
  insert into search.refresh_requests(requested_by) values ('SS-007 integrity repair (1 Nov 2026): 167 official links on held courses set unverified again (D1)');
end $$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.coverage_admission_plan_v1', 'Platform', 'Admission', 'SS-007: admission skips courses under an open binding remediation hold', 'active', '{}', '20261101030000')
on conflict do nothing;

-- post-check
do $$
begin
  if exists (select 1 from catalogue.course_links l join pipeline.course_remediation_holds h on h.course_id = l.course_id and h.lifted_at is null
              where l.link_type = 'official_course' and l.status = 'active' and l.updated_at = '2026-10-31 03:30:00.566382+00') then  -- fixed: as above
    raise exception 'SS-007 post-check: a re-activated link is still active'; end if;
  if exists (select 1 from security.coverage_admission_plan_v1('coverage-sweep-v0.5.6') a where security.course_held_v1(a.course_id)) then  -- fixed: the live extractor
    raise exception 'SS-007 post-check: the admission plan still includes a held course'; end if;
end $$;
