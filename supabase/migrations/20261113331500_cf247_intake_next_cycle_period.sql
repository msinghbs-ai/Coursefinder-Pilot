-- CF-247 F-INT: a named study period's next start in the intake's month, for the providers the Platform Admin approved (Canterbury and Massey).
-- Platform Admin decision 13 Nov 2026 14:58 (Admin Intake Process Record §14, F-INT acceptance): "Match the course's July/Semester Two offering to the next
--   verified July/Semester Two teaching start, even if February occurs earlier ... Never silently roll a course offering explicitly restricted to 2026 into
--   2027 ... Reuse the existing planner and admission functions. Do not create another rule engine, manually enter dates or raise global scheduler batches."
-- Found: security.intake_dates_plan_v3 holds an intake when "the named period starts sooner in another month". It checked every period the course page
--   names, so for "Start In Semester 1 or 2 (February or July)" Semester 1 (22 Feb 2027) held the July intake of Semester 2 (19 Jul 2027 at Canterbury,
--   12 Jul 2027 at Massey): 110 Canterbury and 6 Massey July intakes. The rule exists for one period that starts sooner in another month (Monash
--   "Semester one (February)": Semester 1 = 1 Mar 2027); that case is unchanged.
-- What (md5-guarded text edit of security.intake_dates_plan_v3, four edits):
--   1. New list setting intake_dates.next_cycle_period_providers (G2), set to Canterbury and Massey only. Empty: the planner behaves exactly as before.
--   2. For a listed provider the "starts sooner" check counts only named periods that themselves start in the intake's month.
--   3. For a listed provider, a page whose intake wording names years but not the matched year is held (never rolled into the next year).
--   4. The rows' inputs fingerprint carries ";nextcycle=1" for a listed provider, so their rows are looked at again by the scheduled planner; no other
--      provider's fingerprint changes.
--   Everything else is unchanged: identity (E16), offering evidence, applicability, withdrawn values, page dates, horizon, manual locks, publication.
-- Rolled-back live trial before release: see the Pilot PR.
-- Guards: G1 (no job), G2 (the provider list is a setting), G3 (no consumer API object), G4 (cf-247-s542).
-- Replaces: security.intake_dates_plan_v3 (same name; md5-guarded text edit, resulting md5 checked).
-- Retires: nothing.
-- Reversal: empty intake_dates.next_cycle_period_providers on Settings, or reverse the edit (body 98ab7972726d0b3ccef7e816be77fd8d).

insert into pipeline.platform_toolset_settings(toolset_key, key, value, label, help, kind, unit, section, sort, used_by, reason)
values ('pipeline', 'intake_dates.next_cycle_period_providers',
        '["db910e88-67d1-4d2b-a65c-cea290aa0692","229dc07d-c573-44a3-b5dc-cc423cc2c300"]'::jsonb,
        'Intake dates: providers whose named period takes its next start in the intake month',
        'For these providers (University of Canterbury, Massey University), an intake whose course page names several periods ("Semester 1 or 2 (February or July)") takes the next start of the period that starts in the intake''s month, even when another named period starts sooner. A page that ties its intakes to other years is held. Add a provider only with a Platform Admin decision. Empty: off.',
        'list', 'providers', 'Intake dates', 1029, 'security.intake_dates_plan_v3',
        'Platform Admin decision 13 Nov 2026 14:58 (Intake Process Record §14): next-year July intake matching for Canterbury and Massey')
on conflict (toolset_key, key) do nothing;

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

select pg_temp.edit_counted('security.intake_dates_plan_v3(uuid[],integer)', '98ab7972726d0b3ccef7e816be77fd8d', '020a047e45a9c8e82ad45be74a668b2b',
array[$o$  v_near_days int := security.pipeline_num_v1('intake_dates.nearest_start_days', 35)::int;$o$,
      $o$case when c.provider_id = any (v_near) then ';near=' || v_near_days else '' end$o$,
      $o$case when r.provider_id = any (v_near) then ';near=' || v_near_days else '' end$o$,
      $o$     where s.kind = 'start' and s.period = any (v_named) and s.year_ok and s.on_date >= v_today and s.on_date < make_date(v_year, v_m, 1);
    if v_start is not null then$o$],
array[$n$  v_near_days int := security.pipeline_num_v1('intake_dates.nearest_start_days', 35)::int;
  -- 13 Nov 2026 (Platform Admin decision, Intake Process Record §14): providers listed here take a named period's next start in the intake's month even when
  -- another named period starts sooner (Canterbury, Massey: "Semester 1 or 2 (February or July)"); empty: none
  v_next uuid[] := coalesce((select array_agg(x::uuid) from pipeline.platform_toolset_settings s, jsonb_array_elements_text(s.value) x
                              where s.toolset_key = 'pipeline' and s.key = 'intake_dates.next_cycle_period_providers' and jsonb_typeof(s.value) = 'array'), '{}');$n$,
      $n$case when c.provider_id = any (v_near) then ';near=' || v_near_days else '' end || case when c.provider_id = any (v_next) then ';nextcycle=1' else '' end$n$,
      $n$case when r.provider_id = any (v_near) then ';near=' || v_near_days else '' end || case when r.provider_id = any (v_next) then ';nextcycle=1' else '' end$n$,
      $n$     where s.kind = 'start' and s.period = any (v_named) and s.year_ok and s.on_date >= v_today and s.on_date < make_date(v_year, v_m, 1)
       -- §14: for a listed provider only a named period that itself starts in this month is checked, so Semester 1 starting sooner in February
       -- does not hold the July intake of Semester 2 (a period that starts sooner in another month still holds it, as for Monash)
       and (not (r.provider_id = any (v_next))
            or exists (select 1 from jsonb_to_recordset(v_cal) s2(kind text, period text, month int, year_ok boolean)
                        where s2.kind = 'start' and s2.period = s.period and s2.month = v_m and s2.year_ok));
    -- §14 item 4: an offering the course page ties to other years is never rolled into the next year's start
    if v_start is null and r.provider_id = any (v_next) and v_year > extract(year from v_today)::int
       and exists (select 1 from jsonb_to_recordset(v_cal) s3(kind text, period text, on_date date, year_ok boolean)
                    where s3.kind = 'start' and s3.period = any (v_named) and s3.year_ok and s3.on_date >= v_today and s3.on_date < make_date(v_year, v_m, 1))
       and coalesce(v_raw, '') ~ '\m20\d\d\M' and coalesce(v_raw, '') !~ ('\m' || v_year || '\M') then
      outcome := 'skipped'; start_precision := 'month'; periods := v_named; start_quote := null;
      reason := 'the course page names only other years for its intakes: the ' || v_year || ' start in this month is not taken (month only)';
      next_action := security.intake_next_action_v1(outcome, reason, false); next_revisit_at := security.intake_revisit_at_v1(next_action);
      return next; outcome := null; continue;
    end if;
    if v_start is not null then$n$],
array[1, 2, 1, 1]);

do $post$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.intake_dates_plan_v3(uuid[],integer)'::regprocedure)) <> '020a047e45a9c8e82ad45be74a668b2b' then
    raise exception 'post-check: security.intake_dates_plan_v3 does not have the recorded body'; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.next_cycle_period_providers') then
    raise exception 'post-check: the setting intake_dates.next_cycle_period_providers is missing'; end if;
end $post$;
