-- CF-247 s994 (session S2-INT; Platform Admin 23 Nov 2026 17:49 AEDT, Decision 271 follow-up): every new Rule B admission needs the stated month to equal the calendar start's month.
-- Decision text: "Leave Monash and RMIT's existing Decision 271 admitted rows untouched; do NOT regress live admitted intake rows. Enforce the strict same-month rule
-- (stated month == calendar start month) on all new admissions going forward."
-- What: security.intake_nearest_start_v1 (md5-guarded counted text edit, two edits) no longer takes the one start "within intake_dates.nearest_start_days after" the stated month
-- (the next-month path, for example February -> 1 March); only the one main-teaching start in the stated month is used. Otherwise the row is skipped (month only), as for any
-- row without a start in its month. Every other check (research degree, vocational hold, rolling intakes, several starts, same-start months, page day, withdrawn values,
-- offering evidence) is unchanged. Admitted dates stay as they are: nothing is withdrawn or rewritten; rows already dated are "nothing new" to the planner.
-- The setting intake_dates.nearest_start_days stays (it still bounds the look-ahead window of the same function); no setting, job, schedule or consumer API object changes.
-- G1: no job. G2: no number in code. G3 stays 75/48 (checked). Locks unchanged (checked). Spend: none.
-- Replaces: security.intake_nearest_start_v1 (same name; md5-guarded text edit, resulting md5 checked).
-- Retires: nothing. Nothing dropped, deleted or renamed. Reversal: reverse the edit (body 4eee36d45fa627c7626df362377eed22 to 5e864efd7758ea2149e28f6566ac466b).
set local lock_timeout = '5s';
set local statement_timeout = '120s';  -- fixed: one function body is replaced

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s994_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s994_dated on commit drop as select count(*) n from catalogue.course_intakes where start_date is not null;

create or replace function pg_temp.edit_counted(p_sig text, p_before text, p_after text, p_olds text[], p_news text[], p_counts int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then raise notice '%: already applied', p_sig; return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> p_counts[i] then raise exception '%: edit % must apply exactly % time(s) (found %)', p_sig, i, p_counts[i], v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  raise notice '%: applied', p_sig;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_counted('security.intake_nearest_start_v1(uuid,uuid,integer,integer,text,jsonb,date,integer,integer)', '5e864efd7758ea2149e28f6566ac466b', '4eee36d45fa627c7626df362377eed22',
array[$o1$v_cand := coalesce(v_s1[1], v_s2[1]); v_path := case when v_s1 is not null then 'in_month' else 'next_start' end;$o1$,
      $o2$'no main-teaching calendar start in this month or within ' || p_days || ' days after it (month only)'$o2$],
array[$n1$v_cand := v_s1[1]; v_path := 'in_month';  -- s994 (Platform Admin 23 Nov 2026 17:49): only a start in the month the page names; a start in the next month is never used$n1$,
      $n2$'no main-teaching calendar start in the month the page names (a start in another month is not used) (month only)'$n2$],
array[1, 1]);

do $p$
declare v jsonb := security.consumer_api_check_v1();
begin
  if md5((select prosrc from pg_proc where oid = 'security.intake_nearest_start_v1(uuid,uuid,integer,integer,text,jsonb,date,integer,integer)'::regprocedure)) <> '4eee36d45fa627c7626df362377eed22' then
    raise exception 'post-check: the function body is not the edited text';
  end if;
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API drifted: %', v;
  end if;
  if (select n from s994_locks) <> (select count(*) from pipeline.manual_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select n from s994_dated) <> (select count(*) from catalogue.course_intakes where start_date is not null) then raise exception 'post-check: an admitted start date changed'; end if;
end $p$;
