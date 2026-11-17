-- CF-247 F-INT: a named study period never takes a later year's start when it starts sooner in another month (Platform Admin 11 Nov 2026 13:41 AEDT "Yes":
-- the named-period fix found validating the Monash Rule B switch-on).
-- Evidence (production, 11 Nov 2026 13:1x AEDT): 47 Monash intakes whose course page says "Semester one (February)" were filled with 28 Feb 2028 by the named-period
--   route (rule calendar-v3). It looks for a start of the named period in the stated month: Semester 1 2027 starts on 1 Mar 2027 (not in February), so the first
--   February start of Semester 1 was the 2028 column (28 Feb 2028), a year late. It became possible when reader calendar-v2.3 (#1008) read Monash's 2028 column.
--   None of the 47 courses is published. All 47 were withdrawn through security.intake_date_withdraw_v1 with the reason; a withdrawn value is never re-admitted.
-- What: md5-guarded text edit of security.intake_dates_plan_v3 (body ef496c19... -> 98ab7972...): before the horizon check, when the named period(s) start on or after
--   today and before the 1st of the chosen month, the later year's start is not taken. A provider listed for Rule B (intake_dates.nearest_start_providers) takes the
--   nearest start by security.intake_nearest_start_v1 with the withdrawn-value and offering checks (Monash: 1 Mar 2027); any other provider's row is held with the
--   reason "the named period starts sooner in another month (date) ...".
-- Verified on production in a rolled-back transaction with the exact edit applied to the live definition: the edit applies once; the inserted block's md5
--   (517f2612...) equals this file's; resulting body md5 98ab7972726d0b3ccef7e816be77fd8d.
-- Guards: G1 (no job), G2 (no new operational value), G3 (no consumer API object), G4 (cf-247-s533).
-- Replaces: security.intake_dates_plan_v3 (same name; md5-guarded text edit, resulting md5 checked).
-- Retires: nothing.
-- Reversal: reverse the one edit (body ef496c19edb842c19a6aa1aef19e3644).

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

select pg_temp.edit_all('security.intake_dates_plan_v3(uuid[],integer)', 'ef496c19edb842c19a6aa1aef19e3644', '98ab7972726d0b3ccef7e816be77fd8d',
  array[$o$    -- P0 IQ-00313: the next dated start must lie within the horizon$o$],
  array[$n$    -- 11 Nov 2026 (F-INT): the named period's next start must be the one in this month. When the period starts sooner in another month (Monash "Semester one
    -- (February)": Semester 1 = 1 Mar 2027, its February start is 28 Feb 2028), a later year's start in this month is never taken. A provider listed for Rule B
    -- takes the nearest start by Rule B (Decision 271); any other is held.
    select min(s.on_date) into v_start from jsonb_to_recordset(v_cal) s(kind text, period text, on_date date, year_ok boolean)
     where s.kind = 'start' and s.period = any (v_named) and s.year_ok and s.on_date >= v_today and s.on_date < make_date(v_year, v_m, 1);
    if v_start is not null then
      if r.provider_id = any (v_near) then
        v_pd := security.intake_nearest_start_v1(r.course_id, r.id, v_m, r.intake_year, v_raw, v_cal, v_today, v_ahead, v_near_days);
        if coalesce((v_pd->>'admit')::boolean, false)
           and not exists (select 1 from pipeline.course_intake_date_events w where w.intake_id = r.id and w.outcome = 'withdrawn'
                              and (w.before_value->>'start_date')::date is not distinct from (v_pd->>'date')::date) then
          reason := security.intake_course_applicability_v1(v_raw, v_m, coalesce((v_pd->>'target_year')::int, extract(year from (v_pd->>'date')::date)::int), v_cal, false, null, null);
          if reason is null then
            v_start := (v_pd->>'date')::date; v_year := extract(year from v_start)::int;
            rule := 'calendar-v3-nearest-start'; start_precision := 'day'; start_quote := v_pd->>'quote'; deadline_kind := 'not_stated';
            periods := case when v_pd->>'period' is not null then array[v_pd->>'period'] end;
            proposal_id := nullif(v_pd->>'proposal_id', '')::uuid;
            calendar_url := v_pd->>'calendar_url'; calendar_evidence_id := nullif(v_pd->>'calendar_evidence_id', '')::uuid;
            new_year := case when r.intake_year is null then v_year end; new_start := v_start;
            outcome := 'filled';
            next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
            return next; outcome := null; continue;
          end if;
        end if;
      end if;
      outcome := 'skipped'; start_precision := 'month'; periods := v_named; start_quote := null;
      reason := 'the named period starts sooner in another month (' || v_start || '): a later year''s start in this month is not taken (month only)';
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
      return next; outcome := null; continue;
    end if;
    -- P0 IQ-00313: the next dated start must lie within the horizon$n$]);

do $post$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.intake_dates_plan_v3(uuid[],integer)'::regprocedure)) <> '98ab7972726d0b3ccef7e816be77fd8d' then
    raise exception 'post-check: security.intake_dates_plan_v3 does not have the recorded body'; end if;
end $post$;
