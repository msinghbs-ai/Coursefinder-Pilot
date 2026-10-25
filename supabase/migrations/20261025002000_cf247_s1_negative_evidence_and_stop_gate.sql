-- CF-247 S1 part 1 (25 Oct 2026, v2.15.352). Track A: S1 negative evidence and gate consolidation (throughput plan item 8; Platform Admin
-- 25 Oct 18:05: "S1's gate consolidation ... holds its schedule"). Record: admin repo docs/platform/ui-audit/2026-10-25-overnight-outcomes.md
-- and docs/platform/PIPELINE-LINEAGE.md sections 2-4 (updated in the same change, doc-as-code).
-- Found (live): two negative-evidence lists with different readers - pipeline.page_rejections (read by the AI page match and reidentify)
-- and pipeline.course_page_blocks (read only by the search binder) - and two binding paths that read neither: the search result
-- (svc_course_link_search_record binds its first candidate) and the site-map binder (security.coverage_bind_v2). The search stop was
-- written three times (picker, credit check svc_fc_spend, stall-cause walk link_search_block_v1), which is how hotfixes 1 and 2 missed one.
-- 1 One predicate, security.page_refused_v1(course, url): a page rejected for the course (page_rejections) or blocked for it
--   (course_page_blocks). Every automatic binding path and the two candidate readers ask it. A person's manual binding
--   (admin_course_edit) is not affected.
-- 2 One stop gate, security.search_stop_gate_v1(provider, course, stopped, person): 'search_stopped' when the university's automatic
--   search stopped and no person's task covers it; 'course_stopped' when the course has search.stop_per_course_after distinct rejected
--   pages; else null. The picker, the credit check and the stall-cause walk all call it (the picker passes its set-based stop list, so
--   speed is unchanged). Behaviour is unchanged; the rule now lives in one place.
-- Not in this part (S1 part 2, own release): Layer 4 needs_person after the course stop; seeding attempts-exhausted pages (the F8 seed
-- file awaits the Platform Admin); next_attempt_at. The spec's pages.max_distinct_wrong is not added: search.stop_per_course_after (R2)
-- is the one number for "too many wrong pages for this course" (consolidation, not a second threshold).
-- Replaces: the inline stop checks in svc_course_link_search_next, svc_fc_spend, link_search_block_v1; the inline negative-evidence checks
--   in coverage_ai_match_prepare_v1, svc_coverage_reidentify_next, course_link_bind_v1 (all md5-guarded edits)
-- Retires: nothing

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

create or replace function security.page_refused_v1(p_course uuid, p_url text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from pipeline.page_rejections r where r.course_id = p_course and r.url = p_url)
      or exists (select 1 from pipeline.course_page_blocks b where b.course_id = p_course and b.url = p_url)
$$;
comment on function security.page_refused_v1(uuid, text) is 'CF-247 S1 (v2.15.352): the one negative-evidence predicate - true when the page was rejected (page_rejections) or blocked (course_page_blocks) for the course; every automatic binding path asks it';

create or replace function security.search_stop_gate_v1(p_provider uuid, p_course uuid default null, p_stopped boolean default null, p_person boolean default null)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_stopped boolean; v_person boolean;
begin
  -- the university stop, unless a person's task covers it (search.person_task_bypass)
  v_stopped := coalesce(p_stopped, security.fc_search_stopped_for_v1(p_provider));
  if v_stopped then
    v_person := security.pipeline_num_v1('search.person_task_bypass', 1) >= 1 and coalesce(p_person,
      case when p_course is not null then security.link_search_person_task_v1(p_provider, p_course)
           else exists (select 1 from pipeline.admin_jobs j where j.kind = 'course_page_find' and j.state in ('queued', 'running') and j.args->>'provider_id' = p_provider::text) end);
    if not v_person then return 'search_stopped'; end if;
  end if;
  -- the course stop (R2): too many different pages rejected for this course
  if p_course is not null and (select count(distinct r.url) from pipeline.page_rejections r where r.course_id = p_course)
                              >= security.pipeline_num_v1('search.stop_per_course_after', 6) then
    return 'course_stopped';
  end if;
  return null;
end $$;
comment on function security.search_stop_gate_v1(uuid, uuid, boolean, boolean) is 'CF-247 S1 (v2.15.352): the one course-search stop gate (university stop with the person-task bypass, then the per-course stop) used by the picker, the credit check and the stall-cause walk';

-- 2 the stop gate in its three callers -----------------------------------------------------------------------------------------------
select pg_temp.edit_n('public.svc_course_link_search_next(integer)', 'd928af887ba01cf49c4c4ff141065b42', array[
  array[$o$       and (not pv.stopped or (v_person and security.link_search_person_task_v1(s.provider_id, s.course_id)))  -- hotfix D2: a person's task passes the stop
$o$, $n$       and security.search_stop_gate_v1(s.provider_id, s.course_id, pv.stopped) is null  -- S1: the one stop gate (university stop with the person bypass, per-course stop)
$n$],
  array[$o$       and (select count(distinct r.url) from pipeline.page_rejections r where r.course_id = s.course_id) < v_course_stop  -- R2: per-course stop
$o$, $n$$n$]],
  array[1, 1]);

select pg_temp.edit_n('public.svc_fc_spend(numeric,text,uuid,text)', 'e607a9bddc558eb55d9d5b89dad00867', array[
  array[$o$    elsif p_provider_id is not null and v_grp = 'course_search' and security.fc_search_stopped_for_v1(p_provider_id)
          -- 24 Oct 2026 (hotfix 2): a person's waiting or running Find course pages task passes the stop here too, as in the picker
          and not (security.pipeline_num_v1('search.person_task_bypass', 1) >= 1
                   and exists (select 1 from pipeline.admin_jobs j where j.kind = 'course_page_find' and j.state in ('queued', 'running')
                                  and j.args->>'provider_id' = p_provider_id::text)) then$o$,
        $n$    elsif p_provider_id is not null and v_grp = 'course_search' and security.search_stop_gate_v1(p_provider_id) = 'search_stopped' then  -- S1: the one stop gate$n$]],
  array[1]);

select pg_temp.edit_n('security.link_search_block_v1(uuid,uuid[])', '96d25d8b0aa22a2681b8695e77fe4afc', array[
  array[$o$  if security.fc_search_stopped_for_v1(p_provider) and not (v_bypass and v_person) then$o$,
        $n$  if security.search_stop_gate_v1(p_provider, null, null, v_person) = 'search_stopped' then  -- S1: the one stop gate$n$]],
  array[1]);

-- 1 the negative-evidence predicate in every automatic binding path and both candidate readers --------------------------------------
select pg_temp.edit_n('public.svc_course_link_search_record(uuid,integer,text[],text)', 'aecdd65721f0db2841642be1e1542ec3', array[
  array[$o$    v_c := security.course_link_pick_v1(r.provider_id, coalesce(p_urls, '{}'));$o$,
        $n$    v_c := security.course_link_pick_v1(r.provider_id, coalesce(p_urls, '{}'));
    -- S1: a page rejected or blocked for this course is never taken from a search result
    v_c := coalesce(array(select t.u from unnest(v_c) with ordinality t(u, o) where not security.page_refused_v1(p_course_id, t.u) order by t.o), '{}');$n$]],
  array[1]);

select pg_temp.edit_n('security.course_link_bind_v1(uuid,uuid,text,text)', '5b86dea43578966d37a3092598d363a3', array[
  array[$o$   where not exists (select 1 from pipeline.course_page_blocks b where b.course_id = p_course_id and b.url = p_url)$o$,
        $n$   where not security.page_refused_v1(p_course_id, p_url)  -- S1: rejections and blocks$n$]],
  array[1]);

select pg_temp.edit_n('security.coverage_bind_v2(uuid)', '72fc0db3d44ca616ee45df90a9a9f2be', array[
  array[$o$    from _cb_best
  on conflict (course_id) do update$o$,
        $n$    from _cb_best where not security.page_refused_v1(course_id, url)  -- S1: the site-map binder skips refused pages
  on conflict (course_id) do update$n$]],
  array[1]);

select pg_temp.edit_n('security.coverage_ai_match_prepare_v1(integer,integer)', '621c9bfccbe7d867352b4015736b5e83', array[
  array[$o$union select x.course_id, x.url from pipeline.page_rejections x join c using (course_id) /* 24 Oct 2026: rejected pages are never candidates */$o$,
        $n$union select x.course_id, x.url from pipeline.page_rejections x join c using (course_id) /* 24 Oct 2026: rejected pages are never candidates */
                union select b.course_id, b.url from pipeline.course_page_blocks b join c using (course_id) /* S1: blocked pages neither */$n$]],
  array[1]);

select pg_temp.edit_n('public.svc_coverage_reidentify_next(integer,text)', 'bbac1bef6f49eddfeca79092b5ed09de', array[
  array[$o$and not exists (select 1 from pipeline.page_rejections x where x.course_id = p.course_id and x.url = p.url) /* 24 Oct 2026: a rejected page is never re-bound */$o$,
        $n$and not security.page_refused_v1(p.course_id, p.url) /* 24 Oct 2026; S1: a rejected or blocked page is never re-bound */$n$]],
  array[1]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.page_refused_v1', 'Layer 2', 'one negative-evidence predicate (rejections and blocks) for every automatic binding path', 'active', '{}', '20261025002000'),
 ('function', 'security.search_stop_gate_v1', 'Layer 2', 'one course-search stop gate for the picker, the credit check and the stall-cause walk', 'active', '{}', '20261025002000')
on conflict (kind, name) do nothing;

select 'S1 part 1: one negative-evidence predicate and one stop gate' ok;
