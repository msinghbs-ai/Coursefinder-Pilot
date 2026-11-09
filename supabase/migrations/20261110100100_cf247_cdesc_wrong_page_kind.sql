-- CF-247 F-CDESC quality guard (Platform Admin, 10 Nov 2026): a new decline wrong_page_kind in the machine rule's one evaluator, security.course_description_machine_check_v1 (the admission calls it
-- again at write time, so both the first look and the write-time check apply it). A reading whose bound source page address names a requirements, entry, fees, how-to-apply or programme-structure
-- page (a path segment; the query and fragment are left out) is not a course overview, and its text is not a description of the course: the reading stays for a person in Layer 4.
-- Why: 3 of the first 9 machine admissions (courses 2e5056ef, 3c2a090a, 073cfad9) were read from /requirements pages and their text is an admission statement or a list of course names.
-- Existing admissions are not touched; the Platform Admin withdraws them through admin_course_description_machine_withdraw_v1. The page kinds are a quality rule marked -- fixed: (no setting added).
-- Live definition (pg_proc.prosrc md5, read 10 Nov 2026, project fxcwkweaxjtknorudmwp), original -> edited:
--   security.course_description_machine_check_v1(uuid)  fca43249b1846aae9eae0df7fc83ecb4 -> 3e0fe24d762e7fc4348865ea09499690
-- Forward recovery (the original body, byte for byte): supabase/held/cdesc_wrong_page_kind_forward_recovery.sql.
-- The consumer API (G3) is not touched. No setting value changes, nothing is switched on or off, nothing is dropped or deleted.
-- Replaces: security.course_description_machine_check_v1 is edited in place (md5-guarded, one new decline); otherwise nothing
-- Retires: nothing

do $g$ declare s text; begin
  foreach s in array array['security.course_description_machine_check_v1(uuid)', 'security.cdesc_machine_fail_v1(text,text,text,boolean)'] loop
    if to_regprocedure(s) is null then raise exception 'required % is missing (apply 20261110060000 first)', s; end if;
  end loop;
end $g$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the md5-guarded edit
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.course_description_machine_check_v1(uuid)', 'fca43249b1846aae9eae0df7fc83ecb4', '3e0fe24d762e7fc4348865ea09499690',
     array[$o$v_recheck text := 'not_run';$o$,
           $o$  v_fid := case when coalesce(i.proposed_value->>'item_id', '') ~ '^\d+$' then (i.proposed_value->>'item_id')::bigint end;$o$],
     array[$n$v_recheck text := 'not_run'; v_kind text;$n$,
           $n$  -- the kind of page: a requirements, entry, fees, how-to-apply or programme-structure page is not a course overview, so its text is not a description of the course
  select seg.s into v_kind from regexp_split_to_table(lower(regexp_replace(split_part(split_part(coalesce(g.url, ''), '#', 1), '?', 1), '^[a-z][a-z0-9+.-]*://[^/]*', '')), '/') seg(s)
   where seg.s ~ '^(entry|entry-requirements|admission-requirements|requirements|fees|tuition-fees|how-to-apply|programme-structure|program-structure|course-structure)$' limit 1; -- fixed: the page kinds a person decides (10 Nov 2026); a quality rule, no setting exists and none is added
  if v_kind is not null then
    return security.cdesc_machine_fail_v1('wrong_page_kind', 'The description was read from a page whose address has the part "' || v_kind || '" (' || coalesce(g.url, 'no address') || '), so it is not the course overview.', 'A person decides in Layer 4.'); end if;
  v_fid := case when coalesce(i.proposed_value->>'item_id', '') ~ '^\d+$' then (i.proposed_value->>'item_id')::bigint end;$n$])
  ) v(sig, md5_before, md5_after, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then continue; end if; -- already applied
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
  end loop;
end $m$;


do $post$ begin
  if position('wrong_page_kind' in (select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_check_v1(uuid)'::regprocedure)) = 0 then raise exception 'post-check: the page kind decline is missing'; end if;
  if security.pipeline_num_v1('enrich.course_description_machine_on', -1) not in (0, 1) then raise exception 'post-check: the machine switch must exist (0 or 1; this change does not touch it)'; end if;
end $post$;
