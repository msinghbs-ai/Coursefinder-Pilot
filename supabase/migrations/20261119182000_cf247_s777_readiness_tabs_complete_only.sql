-- CF-247 s777 follow-up: the stakeholder readiness tabs are written only from a complete snapshot (Platform Admin 19 Nov 2026 15:36 AEDT, chat
-- S1-Build, s776 and s777).
-- Found (rolled-back live read-back through GitHub Actions, 19 Nov 2026 17:27 AEDT, after 20261119174000 went live): the readiness snapshot is
-- built one part every 4 minutes (readiness.snapshot_parts, 16). With 3 of 16 parts built, security.course_field_readiness_tabs_v1 already
-- returned tabs, so the first hourly telemetry sync would have put part-totals (about 3/16 of the courses) on the stakeholder sheet. The PIM
-- Admin panel says "3 of 16 built so far"; the sheet has no such line.
-- What changes (md5-guarded fragment edit; no table, job or setting): security.course_field_readiness_tabs_v1 returns null until every part of
-- the current part count is built (summary parts_built = parts). The hourly sync already skips the tabs on null (prompt step 8b) and says so.
-- After the first full build every part is refreshed in place, so null is returned again only if readiness.snapshot_parts is changed.
-- Replaces: nothing (narrows when the tabs read returns rows).
-- Retires: nothing.
-- G1: no job. G2: no setting (the part count is readiness.snapshot_parts). G3: untouched (75 functions, 48 tables; schema security).

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.cf_edit_def('security.course_field_readiness_tabs_v1()'::regprocedure, '95bb07bb4afcff89d906b3ffd91dc486',
  array[$o$  if v_s is null then return null; end if;$o$],
  array[$n$  -- complete snapshots only (s777 follow-up): part-totals never reach the stakeholder sheet
  if v_s is null or coalesce((v_s->>'parts_built')::int, 0) < coalesce((v_s->>'parts')::int, 1) then return null; end if;$n$]);

-- post-checks
do $$
declare v_s jsonb := (select s.last_result from pipeline.job_input_marks s where s.job_key = 'course-field-readiness:summary');
        v_t jsonb := security.course_field_readiness_tabs_v1(); v_complete boolean;
begin
  if (select prosecdef from pg_proc where oid = 'security.course_field_readiness_tabs_v1()'::regprocedure) is distinct from
     (select prosecdef from pg_proc where oid = 'security.course_field_readiness_summary_v1()'::regprocedure) then
    raise exception 'post-check: security mode of the tabs read changed';
  end if;
  v_complete := v_s is not null and (v_s->>'parts_built')::int >= (v_s->>'parts')::int;
  if v_complete and v_t is null then raise exception 'post-check: a complete snapshot returned no tabs'; end if;
  if not v_complete and v_t is not null then raise exception 'post-check: a partial snapshot (% of % parts) still returned tabs', v_s->>'parts_built', v_s->>'parts'; end if;
  perform set_config('cf.diag', format('summary parts_built %s of %s; tabs %s', coalesce(v_s->>'parts_built','none'), coalesce(v_s->>'parts','none'),
    case when v_t is null then 'null (skipped until complete)' else 'returned (complete)' end), true);
end $$;
