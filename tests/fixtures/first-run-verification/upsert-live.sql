-- SS-021 F2 (migration 20261104320000, v2.15.450) as it reached production: security.integration_issue_allowed_v1 and the md5-guarded edit of
-- security.integration_issue_upsert_v1 (c5ce0cb9 -> b0a1a649), copied by run.sh's awk from the migration; kept here for review. Fixture database only.
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
create or replace function security.integration_issue_allowed_v1(p_check text, p_value text) returns boolean
language sql stable security definer set search_path to '' as $function$
-- CF-247 SS-021 F2: whether a value is one the named check on pipeline.integration_issues allows (its quoted literals). A check that does not
-- exist does not restrict the value.
  select coalesce((select p_value = any (array(select m[1] from regexp_matches(pg_get_constraintdef(c.oid), '''([^'']*)''', 'g') m))
                     from pg_constraint c where c.conrelid = 'pipeline.integration_issues'::regclass and c.conname = p_check), true)
$function$;
revoke all on function security.integration_issue_allowed_v1(text, text) from public, anon, authenticated;
select pg_temp.edit_once('security.integration_issue_upsert_v1(jsonb,text)', 'c5ce0cb9c431a337789d67bc1878be62', 'b0a1a64982680ae5d588c2d73b779e4e',
  array[array[$o$        r pipeline.integration_issues; v_new_prov uuid[]; v_new_course uuid[]; v_more boolean; v_action text; v_status text;
$o$, $n$        r pipeline.integration_issues; v_new_prov uuid[]; v_new_course uuid[]; v_more boolean; v_action text; v_status text;
        v_rcc text; v_ws text; v_vl text; v_unmapped jsonb := '{}'::jsonb;
$n$],
        array[$o$    if v_status not in ('detected', 'triaged', 'assigned', 'in_progress') then raise exception 'a new issue starts as detected, triaged, assigned or in_progress' using errcode = '22023'; end if;
$o$, $n$    if v_status not in ('detected', 'triaged', 'assigned', 'in_progress') then raise exception 'a new issue starts as detected, triaged, assigned or in_progress' using errcode = '22023'; end if;
    -- 4 Nov 2026 (SS-021 F2, IQ-00077): a root cause class, workstream or validation layer the queue's checks refuse is mapped (unclassified, A10,
    -- manual) and the value sent is kept in evidence.unmapped, so a reporting job's own issue write never aborts its run
    v_rcc := coalesce(nullif(p->>'root_cause_class', ''), 'unclassified');
    v_ws := coalesce(nullif(p->>'workstream', ''), 'A10');
    v_vl := coalesce(nullif(p->>'validation_layer', ''), 'manual');
    if not security.integration_issue_allowed_v1('integration_issues_root_cause_class_check', v_rcc) then
      v_unmapped := v_unmapped || jsonb_build_object('root_cause_class', v_rcc); v_rcc := 'unclassified'; end if;
    if not security.integration_issue_allowed_v1('integration_issues_workstream_check', v_ws) then
      v_unmapped := v_unmapped || jsonb_build_object('workstream', v_ws); v_ws := 'A10'; end if;
    if not security.integration_issue_allowed_v1('integration_issues_validation_layer_check', v_vl) then
      v_unmapped := v_unmapped || jsonb_build_object('validation_layer', v_vl); v_vl := 'manual'; end if;
    if v_unmapped <> '{}'::jsonb then v_unmapped := jsonb_build_object('unmapped', v_unmapped); end if;
$n$],
        array[$o$coalesce(nullif(p->>'validation_layer', ''), 'manual'), coalesce(p->'evidence', '{}'::jsonb), v_refs,
           coalesce(nullif(p->>'root_cause_class', ''), 'unclassified'), v_sev, p->>'impact', coalesce(nullif(p->>'workstream', ''), 'A10'), v_blk, v_deps,$o$,
              $n$v_vl, coalesce(p->'evidence', '{}'::jsonb) || v_unmapped, v_refs,
           v_rcc, v_sev, p->>'impact', v_ws, v_blk, v_deps,$n$]], array[1, 1, 1]);
