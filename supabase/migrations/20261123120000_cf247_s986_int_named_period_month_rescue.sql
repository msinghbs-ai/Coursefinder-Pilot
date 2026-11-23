-- CF-247 s986 (session S2-INT; Platform Admin 23 Nov 2026 13:02 AEDT, F-INT exact intake dates, objective: repair the source-to-date path): an intake whose course
-- page names several study periods takes the next start of the period that starts in the intake's month, for every university, when the page itself states that month.
--
-- Found (live read-backs 23 Nov 2026, rolled back): security.intake_dates_plan_v3 holds an intake with "the named period starts sooner in another month" when ANY
-- named period starts sooner, so "Term 1, 2 & 3 (February, May, September)" held the May intake of Term 2 because Term 1 starts in February. 815 decisions carry this
-- reason (430 on active intakes with no start date: Griffith 202, Deakin 64, Wollongong 51, Edith Cowan 50, Southern Queensland 47, others 16). The 13 Nov 2026
-- decision (Intake Process Record §14, s542) corrected this for Canterbury and Massey only, through the list setting intake_dates.next_cycle_period_providers.
-- What (md5-guarded counted text edit of security.intake_dates_plan_v3, five edits; the listed providers behave exactly as before):
--   1. For a university that is not listed, the "starts sooner" check counts only named periods that themselves start in the intake's month (the §14 narrowing) when,
--      and only when, the course page states this month as an intake, start or entry (security.intake_course_applicability_v1) and the month is stated in a sentence
--      that is not about applications opening or closing. Otherwise the row is held with the same reason as before.
--   2. A rescued row is also held when its page ties the offering to other years (§14 item 4), as for a listed university.
--   3. Fingerprint: the rows of a university that holds "starts sooner" skips carry ";rescue=1", so only those rows are planned again (the scheduled planner, 150 rows
--      an hour); no other university's rows are looked at again. Nothing is shadowed or switched off by default.
-- Unchanged: identity (E16), offering evidence for the named period (applicability), withdrawn values, page dates, the horizon, manual locks, general-wording rule
-- (s925/s940), Rule B, publication and the Website and Zoho copies.
-- Rolled-back live trial (23 Nov 2026): 429 rows on 407 courses would be dated by the plain narrowing (0 month or year mismatches, every date one of the calendar's
-- own starts); the month-stated condition keeps 328 and holds the rest (see the Pilot pull request for the per-university figures).
-- G1: no job. G2: no new value (no number in code; the existing horizon and share settings are untouched). G3 stays 75/48 (no consumer API object changed; data only).
-- Locks and cron unchanged (checked below). Spend: none.
-- Replaces: security.intake_dates_plan_v3 (same name; md5-guarded text edit, resulting md5 checked).
-- Retires: nothing. Nothing dropped, deleted or renamed.
-- Reversal: reverse the edit (body f05b31dd74378cce5cdc77f0b20abb79 to cf7fff5026511c05be87c5e842a8570d); admitted dates are withdrawn through security.intake_date_day_withdraw_v1.
set local lock_timeout = '5s';
set local statement_timeout = '120s';  -- fixed: the planner body is replaced and its guards read the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s986_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s986_cron on commit drop as select count(*) n from cron.job where active;

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

select pg_temp.edit_counted('security.intake_dates_plan_v3(uuid[],integer)', 'cf7fff5026511c05be87c5e842a8570d', 'f05b31dd74378cce5cdc77f0b20abb79',
array[$o1$v_raw text; v_pq text; v_named text[]; v_named_all text[]; v_spec text; v_generic boolean := false;$o1$,
      $o2$  v_settings text := 'lists='$o2$,
      $o3$case when c.provider_id = any (v_next) then ';nextcycle=1' else '' end$o3$,
      $o4$case when r.provider_id = any (v_next) then ';nextcycle=1' else '' end$o4$,
      $o5$    -- §14 item 4: an offering the course page ties to other years is never rolled into the next year's start
    if v_start is null and r.provider_id = any (v_next) and v_year > extract(year from v_today)::int$o5$],
array[$n1$v_raw text; v_pq text; v_named text[]; v_named_all text[]; v_spec text; v_generic boolean := false; v_rescued boolean := false; v_narrow date;$n1$,
      $n2$  -- S2-INT s986 (23 Nov 2026): a university that holds intakes skipped with "the named period starts sooner in another month" is planned again under the
  -- month-stated rescue below; its rows carry ";rescue=1" in the inputs fingerprint, so they are looked at once more and no other university's rows are
  v_resc uuid[] := coalesce((select array_agg(distinct d.provider_id) from pipeline.course_intake_dates d
                              where d.outcome = 'skipped' and d.reason like 'the named period starts sooner%'), '{}');
  v_settings text := 'lists='$n2$,
      $n3$case when c.provider_id = any (v_next) then ';nextcycle=1' else '' end || case when c.provider_id = any (v_resc) then ';rescue=1' else '' end$n3$,
      $n4$case when r.provider_id = any (v_next) then ';nextcycle=1' else '' end || case when r.provider_id = any (v_resc) then ';rescue=1' else '' end$n4$,
      $n5$    -- S2-INT s986 (23 Nov 2026): the §14 narrowing for any university, when the course page itself states this month as an intake. A named period that does not
    -- start in this month holds the intake only when it starts sooner in another month AND also starts in this month (Monash "Semester one (February)"). Here no
    -- named period that starts in this month starts sooner, and the page states the month as an intake or start in a sentence that is not about applications
    -- opening or closing ("applications for Semester 1 open in August" is not an August intake), as for a listed university. Nothing else changes.
    v_rescued := false;
    if v_start is not null and not (r.provider_id = any (v_next)) then
      select min(s.on_date) into v_narrow from jsonb_to_recordset(v_cal) s(kind text, period text, on_date date, year_ok boolean)
       where s.kind = 'start' and s.period = any (v_named) and s.year_ok and s.on_date >= v_today and s.on_date < make_date(v_year, v_m, 1)
         and exists (select 1 from jsonb_to_recordset(v_cal) s2(kind text, period text, month int, year_ok boolean)
                      where s2.kind = 'start' and s2.period = s.period and s2.month = v_m and s2.year_ok);
      if v_narrow is null and security.intake_course_applicability_v1(v_raw, v_m, v_year, v_cal, false, null, null) is null
         and regexp_replace(lower(coalesce(v_raw, '')), '[^.;|]*(applications? (open|close|due)|apply by|closing date|clos(e|es|ing))[^.;|]*', ' ', 'g')
             ~* ('\m' || (array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])[v_m] || '[a-z]*\M') then
        v_rescued := true; v_start := null;
      end if;
    end if;
    -- §14 item 4: an offering the course page ties to other years is never rolled into the next year's start
    if v_start is null and (r.provider_id = any (v_next) or v_rescued) and v_year > extract(year from v_today)::int$n5$],
array[1, 1, 2, 1, 1]);

do $p$
declare v jsonb := security.consumer_api_check_v1();
begin
  if md5((select prosrc from pg_proc where oid = 'security.intake_dates_plan_v3(uuid[],integer)'::regprocedure)) <> 'f05b31dd74378cce5cdc77f0b20abb79' then
    raise exception 'post-check: the planner body is not the edited text';
  end if;
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API drifted: %', v;
  end if;
  if (select n from s986_locks) <> (select count(*) from pipeline.manual_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select n from s986_cron) <> (select count(*) from cron.job where active) then raise exception 'post-check: active cron jobs changed'; end if;
end $p$;
