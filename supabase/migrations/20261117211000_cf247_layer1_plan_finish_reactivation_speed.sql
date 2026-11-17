-- CF-247 Layer 1 register: the plan finish no longer scans the course registrations once per new course (S2-Build, CRICOS 11 Nov 2026 edition).
-- Cause: run 802d8928 applied its 953 waiting courses, then svc_layer1_plan_finish (security.layer1_plan_finish_v1) timed out. Its first
-- statement, which brings back retired courses that are new in the register again, joined jsonb_array_elements(p.items) (25,199 items) to
-- catalogue.course_registrations on upper(code); the planner expects one item and runs a full scan of the registrations for each of the 317 new
-- items. A direct run outside the API limit was still on that statement after two minutes.
-- Change: the new codes are collected into an array first and matched with = any(...), one scan. Same rows, same result; nothing else in the
-- function changes (md5-guarded edit: before-body cbd1ae13..., after-body checked against the expected replacement).
-- Replaces: the per-item join in the reactivation statement of security.layer1_plan_finish_v1.
-- Retires: nothing.

do $e$
declare
  v_sig constant regprocedure := 'security.layer1_plan_finish_v1(uuid,boolean,uuid)'::regprocedure;
  v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.layer1_plan_finish_v1(uuid,boolean,uuid)'::regprocedure);
  v_def text; v_out text; v_c int; i int;
  v_old text[] := array[
    $o1$v_snapshot text; v_result jsonb; v_country uuid;$o1$,
    $o2$  -- Reactivate planned 'new' records that match a retired course.
  with back as (
    select distinct r.course_id from pipeline.layer1_course_retirements r
    join catalogue.course_registrations cr on cr.course_id=r.course_id and lower(cr.scheme)='cricos'
    join jsonb_array_elements(p.items) i on upper(i->>0)=upper(cr.registration_code) and i->>2='new'
$o2$];
  v_new text[] := array[
    $n1$v_snapshot text; v_result jsonb; v_country uuid; v_new_codes text[];$n1$,
    $n2$  -- Reactivate planned 'new' records that match a retired course.
  -- 17 Nov 2026: the new codes are collected first and matched in one scan (a join on the plan items scanned the registrations once per item)
  v_new_codes := array(select distinct upper(i->>0) from jsonb_array_elements(p.items) i where i->>2='new');
  with back as (
    select distinct r.course_id from pipeline.layer1_course_retirements r
    join catalogue.course_registrations cr on cr.course_id=r.course_id and lower(cr.scheme)='cricos' and upper(cr.registration_code)=any(v_new_codes)
$n2$];
begin
  if position('v_new_codes' in v_src) > 0 then raise notice 'security.layer1_plan_finish_v1: already applied'; return; end if;
  if md5(v_src) <> 'cbd1ae1397a6c45599c23d3597967e51' then raise exception 'live security.layer1_plan_finish_v1 differs from the definition this change edits (body md5 %)', md5(v_src); end if;
  v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
  v_out := v_src;
  for i in 1 .. array_length(v_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, v_old[i], ''))) / length(v_old[i]);
    if v_c <> 1 then raise exception 'security.layer1_plan_finish_v1: edit % must apply exactly once (found %)', i, v_c; end if;
    v_def := replace(v_def, v_old[i], v_new[i]);
    v_out := replace(v_out, v_old[i], v_new[i]);
  end loop;
  execute v_def;
  if md5((select p.prosrc from pg_proc p where p.oid = v_sig)) <> md5(v_out) then raise exception 'security.layer1_plan_finish_v1 after the edit is not the expected body'; end if;
end $e$;

do $$
begin
  if position('upper(cr.registration_code)=any(v_new_codes)' in (select prosrc from pg_proc where oid = 'security.layer1_plan_finish_v1(uuid,boolean,uuid)'::regprocedure)) = 0 then
    raise exception 'post-check: reactivation statement';
  end if;
end $$;
