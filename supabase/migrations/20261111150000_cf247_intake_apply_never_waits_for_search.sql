-- CF-247 F-INT: the intake apply never waits for the search-document writer (Platform Admin 11 Nov 2026 12:21 AEDT "settings saved, validate": Rule B listed for
-- Monash; the validation found the hourly job failing).
-- Evidence (production, read only, 11 Nov 2026 12:2x AEDT): job intake-dates-apply (hourly at :26) failed at 10:26 and 11:26 after exactly 120 s:
--   "canceling statement due to statement timeout ... pg_advisory_xact_lock(hashtext('cf247:search_course_documents_writer')) ... refresh_course_enrichment_scoped_v1
--   ... security.intake_dates_apply_v1 line 55". Job search-refresh-requested runs every 10 minutes (6-59/10), holds the same writer lock for 56-120 s and starts at
--   the same second (10:26:00, 11:26:00). The apply plans for about 75 s, then waits for the lock, reaches the 120 s time-out and rolls back every planned row, so no
--   intake date was admitted since 09:26 (for any provider). The 09:26 run succeeded because that search run was shorter. Not caused by Rule B (10:26 predates it).
-- What: md5-guarded text edit of security.intake_dates_apply_v1(integer,uuid[]) (body 0cb3cd42... -> 8eb3fa7f...): try the writer lock once; when it is free the
--   scoped search refresh runs as before; when it is busy the courses go to the existing search refresh queue (search.refresh_requests), processed by
--   search-refresh-requested on its next run (at most 10 minutes). Admissions are no longer lost to the lock.
-- Guards: G1 (no job), G2 (no new operational value; the lock name is the existing W27 writer lock), G3 (no consumer API object), G4 (cf-247-s532).
-- Replaces: security.intake_dates_apply_v1(integer,uuid[]) (same name; md5-guarded text edit, resulting md5 checked).
-- Retires: nothing.
-- Reversal: reverse the one edit (body 0cb3cd422f99ac0d520deef99ea0ee36).

do $g$
begin
  if to_regprocedure('security.intake_dates_apply_v1(integer,uuid[])') is null then raise exception 'required security.intake_dates_apply_v1 is missing'; end if;
end $g$;

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then raise notice '%: already applied', p_sig; return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  raise notice '%: applied', p_sig;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.intake_dates_apply_v1(integer,uuid[])', '0cb3cd422f99ac0d520deef99ea0ee36', '8eb3fa7f92cc6953faf0234715dfee2e',
  array[$o$    perform search.refresh_course_enrichment_scoped_v1((select array_agg(distinct x) from unnest(v_courses) x), true);$o$],
  array[$n$    -- 11 Nov 2026 (F-INT): never wait for the search-document writer. search-refresh-requested (every 10 minutes) holds it for 1-2 minutes and started at the
    -- same second as this job (10:26, 11:26): the apply waited, hit the statement time-out and rolled back every planned row. When the writer is busy the
    -- courses go to the search refresh queue instead (search.refresh_requests, processed by that job's next run).
    if pg_try_advisory_xact_lock(hashtext('cf247:search_course_documents_writer')) then  -- fixed: the one writer lock (W27)
      perform search.refresh_course_enrichment_scoped_v1((select array_agg(distinct x) from unnest(v_courses) x), true);
    else
      insert into search.refresh_requests(requested_by)
      values ('intake dates apply: ' || coalesce(cardinality((select array_agg(distinct x) from unnest(v_courses) x)), 0) || ' courses (search writer busy)');
    end if;$n$]);

do $post$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.intake_dates_apply_v1(integer,uuid[])'::regprocedure)) <> '8eb3fa7f92cc6953faf0234715dfee2e' then
    raise exception 'post-check: security.intake_dates_apply_v1 does not have the recorded body'; end if;
end $post$;
