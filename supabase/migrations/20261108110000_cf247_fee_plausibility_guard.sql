-- CF-247 FEE lane (IQ-00111 verification, new gap linked under IQ-00111): a daily read-only plausibility guard on the provider fees consumers read.
-- Why (live, read-only, 8 Nov 2026 ~03:20 UTC, project fxcwkweaxjtknorudmwp):
--   * 65 active University-adapter fees of La Cité collégiale (CA, international, annual) are a calendar year or a part of one, not a tuition fee:
--     64 have amount = fee_year (CAD 2,022 for 2022, CAD 2,027 for 2027 ...), 1 is CAD 1,991. The adapter fee pattern ("Frais d'études.*?\b(\d{3,4}...)")
--     captures the first 3-4 digit number after the label. Website API v2 returns them: api.website_v2_tuition gives amount 2027, basis annual, source
--     provider_current for 53 of the course documents checked (the API only drops amounts under 1,000). They were written on 18 Oct, five days before the
--     fee floor (20261023026000) existed, and open item O6 left them live "until read again"; the adapter has no read cycle, so they never were.
--   * security.fee_integrity_measure_v1() (IQ-00111 verification) reports ai_active_on_held = 5, so the IQ-00111 check does not pass: 5 AI fee rows
--     written on 26-27 Oct stay active on courses whose page fee a fee check excluded (Nan Tien 072350D, Reach 105389A, AIBT 107010J, UTas 114382M and 093282D).
--   * 11 active provider fees carry a fee year of 2020-2024 or 2030.
--   Nothing watches these: the containment of 4 Nov was a one-off paste.
-- What:
--   1 security.fee_plausibility_check_v1(): READ-ONLY on fees. Counts, per reason, the active international provider_current_tuition fees that look
--     wrong, and raises (or clears) one flag per reason in pipeline.enrichment_flags (entity fees, key plausibility) with the row keys. Hard reasons:
--     fee_amount_is_a_year, fee_ai_on_held_course. Soft (watch) reasons: fee_year_out_of_range, fee_annual_equals_registered_total.
--     It never changes, withdraws or admits a fee: withdrawal stays a Platform Admin paste.
--   2 Job fee-plausibility-guard, daily, catalogued (G1). Settings (G2): fees.guard_on 1 (read-only, ships on), fees.guard_year_min 1990,
--     fees.guard_year_max 2040, fees.guard_year_old_gap 2, fees.guard_year_ahead 3, fees.guard_total_min_years 1.4, fees.guard_total_match_pct 2,
--     fees.guard_sample 25.
-- Do not weaken fee plausibility rules: none is changed; the fee floor, the cross-check and the holds are untouched. This only reports.
-- Replaces: nothing
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object changes (G3): it reads catalogue.course_fees and writes only pipeline.enrichment_flags.
-- No AI or Firecrawl spend.

-- 1 settings (G2; Settings > Pipeline settings, section Enrichment) -----------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'fees.guard_on', 'Fee plausibility guard: on',
  'On (1): once a day the guard lists the active provider fees that look wrong (amount is a calendar year, AI fee on a held course, odd fee year, annual fee equal to the whole-course total) and raises a flag with the row keys. It changes no fee. Off (0): it does not run.',
  'number', to_jsonb(1), 0, 1, 'on/off', 365, 'Enrichment', 'security.fee_plausibility_check_v1; job fee-plausibility-guard', 'IQ-00111 verification (8 Nov 2026): read-only, ships on'),
 ('pipeline', 'fees.guard_year_min', 'Fee plausibility guard: first calendar year an amount may be mistaken for',
  'A whole-number fee between this year and the last year below is treated as a year read as a fee (La Cité collégiale: CAD 2,027 for 2027).',
  'number', to_jsonb(1990), 1900, 2100, 'year', 366, 'Enrichment', 'security.fee_plausibility_check_v1', 'IQ-00111 verification: lowest year-like amount seen live is 1,991'),
 ('pipeline', 'fees.guard_year_max', 'Fee plausibility guard: last calendar year an amount may be mistaken for',
  'See the first year above.', 'number', to_jsonb(2040), 1900, 2100, 'year', 367, 'Enrichment', 'security.fee_plausibility_check_v1', 'IQ-00111 verification'),
 ('pipeline', 'fees.guard_year_old_gap', 'Fee plausibility guard: oldest fee year before this year',
  'A live fee whose fee year is more than this many years before the current year is listed for a look.',
  'number', to_jsonb(2), 0, 10, 'years', 368, 'Enrichment', 'security.fee_plausibility_check_v1', 'IQ-00111 verification: 11 live fees carry 2020-2024 or 2030'),
 ('pipeline', 'fees.guard_year_ahead', 'Fee plausibility guard: furthest fee year after this year',
  'A live fee whose fee year is more than this many years after the current year is listed for a look.',
  'number', to_jsonb(3), 0, 10, 'years', 369, 'Enrichment', 'security.fee_plausibility_check_v1', 'IQ-00111 verification'),
 ('pipeline', 'fees.guard_total_min_years', 'Fee plausibility guard: shortest course checked against the whole-course total',
  'An annual provider fee that equals the CRICOS registered whole-course total of a course at least this many years long may be the whole fee labelled annual; it is listed for a look (a watch item, not an error).',
  'number', to_jsonb(1.4), 1, 10, 'years', 370, 'Enrichment', 'security.fee_plausibility_check_v1', 'IQ-00111 verification: 18 live annual fees equal the registered total of 1.5 to 4 year courses'),
 ('pipeline', 'fees.guard_total_match_pct', 'Fee plausibility guard: how close counts as equal to the total',
  'Share by which the annual fee may differ from the registered whole-course total and still count as equal.',
  'number', to_jsonb(2), 0, 20, '%', 371, 'Enrichment', 'security.fee_plausibility_check_v1', 'IQ-00111 verification'),
 ('pipeline', 'fees.guard_sample', 'Fee plausibility guard: fee keys listed in a flag',
  'How many fee and course keys each flag lists (the count is always complete).', 'number', to_jsonb(25), 1, 200, 'rows', 372, 'Enrichment', 'security.fee_plausibility_check_v1', 'IQ-00111 verification')
on conflict (toolset_key, key) do nothing;

-- 2 the check ----------------------------------------------------------------------------------------------------------------------------
create or replace function security.fee_plausibility_check_v1() returns jsonb
 language plpgsql security definer set search_path to '' as $f$
declare
  v_ymin numeric := security.pipeline_num_v1('fees.guard_year_min', 1990); v_ymax numeric := security.pipeline_num_v1('fees.guard_year_max', 2040);
  v_old int := security.pipeline_num_v1('fees.guard_year_old_gap', 2)::int; v_ahead int := security.pipeline_num_v1('fees.guard_year_ahead', 3)::int;
  v_min_years numeric := security.pipeline_num_v1('fees.guard_total_min_years', 1.4); v_pct numeric := security.pipeline_num_v1('fees.guard_total_match_pct', 2);
  v_sample int := security.pipeline_num_v1('fees.guard_sample', 25)::int;
  v_year int := extract(year from now() at time zone 'Australia/Melbourne')::int;  -- fixed: the platform's calendar year
  r record; v_out jsonb := '{}'::jsonb;
begin
  if security.pipeline_num_v1('fees.guard_on', 1) < 1 then return jsonb_build_object('skipped', 'fees.guard_on is 0'); end if;
  for r in
    with live as (
      select f.id, f.course_id, f.amount, f.currency_code, f.basis, f.fee_year, f.notes
        from catalogue.course_fees f
       where f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international'),
    hit as (
      select 'fee_amount_is_a_year'::text reason, l.id, l.course_id, l.amount, l.fee_year from live l
       where l.basis in ('annual', 'indicative_annual', 'total_indicative') and l.amount = trunc(l.amount) and l.amount between v_ymin and v_ymax
      union all
      select 'fee_ai_on_held_course', l.id, l.course_id, l.amount, l.fee_year from live l
       where l.notes like '%AI fee reader (%' and security.fee_reader_hold_v1(l.course_id) is not null
         and (security.fee_reader_hold_v1(l.course_id) like 'a fee check hold%'
              or exists (select 1 from pipeline.uni_adapter_exclusions e where e.course_id = l.course_id and e.field = 'fee' and e.active and e.set_at < (select x.created_at from catalogue.course_fees x where x.id = l.id)))
      union all
      select 'fee_year_out_of_range', l.id, l.course_id, l.amount, l.fee_year from live l
       where l.fee_year is not null and (l.fee_year < v_year - v_old or l.fee_year > v_year + v_ahead)
      union all
      select 'fee_annual_equals_registered_total', l.id, l.course_id, l.amount, l.fee_year from live l
        join catalogue.courses c on c.id = l.course_id
        join lateral (select t.amount from catalogue.course_fees t where t.course_id = l.course_id and t.fee_type = 'tuition' and t.basis = 'registered_total_course' and t.status = 'active'
                       order by t.created_at desc limit 1) reg on true
       where l.basis in ('annual', 'indicative_annual') and reg.amount > 0 and abs(l.amount - reg.amount) <= reg.amount * v_pct / 100.0
         and (case c.duration_unit when 'weeks' then c.duration_value / 52.0 when 'months' then c.duration_value / 12.0 when 'years' then c.duration_value end) >= v_min_years)  -- fixed: calendar conversions
    select reason, count(*) n,
           (select jsonb_agg(x) from (select jsonb_build_object('fee', h2.id, 'course', h2.course_id, 'amount', h2.amount, 'year', h2.fee_year) x from hit h2
                                       where h2.reason = hit.reason order by h2.id limit v_sample) s) sample
      from hit group by reason
  loop
    v_out := v_out || jsonb_build_object(r.reason, jsonb_build_object('count', r.n, 'sample', r.sample));
  end loop;
  -- one flag per reason: raised with the count and a sample while any row matches, released when none does
  for r in select * from (values ('fee_amount_is_a_year', 'hard', 'an active provider fee whose amount is a calendar year (the adapter read a year as the fee)'),
                                 ('fee_ai_on_held_course', 'hard', 'an active AI fee reader fee on a course whose page fee a fee check keeps out (IQ-00111)'),
                                 ('fee_year_out_of_range', 'soft', 'an active provider fee with a fee year far from this year'),
                                 ('fee_annual_equals_registered_total', 'soft', 'an annual provider fee equal to the registered whole-course total of a multi-year course')) v(reason, kind, what) loop
    if coalesce((v_out->r.reason->>'count')::int, 0) > 0 then
      insert into pipeline.enrichment_flags(entity, entity_key, field, reason_code, reason, source, kind, state, raised_by_kind, evidence)
      values ('fees', 'plausibility', '', r.reason,
              format('%s fees: %s. The guard changes no fee; withdrawal is a Platform Admin paste (docs/paste/FEE-*).', v_out->r.reason->>'count', r.what), 'fee-plausibility-guard', r.kind, 'raised', 'auto',
              jsonb_build_object('count', (v_out->r.reason->>'count')::int, 'sample', v_out->r.reason->'sample'))
      on conflict (entity, entity_key, field, reason_code) do update
        set reason = excluded.reason, evidence = excluded.evidence, flagged_at = now(), cleared_at = null, state = 'raised', kind = excluded.kind;
    else
      update pipeline.enrichment_flags set cleared_at = now(), state = 'released', released_at = now(), release_kind = 'auto', release_reason = 'No active fee matches this reason'
       where entity = 'fees' and entity_key = 'plausibility' and field = '' and reason_code = r.reason and state = 'raised';
    end if;
  end loop;
  return jsonb_build_object('checked_at', now(), 'counts', v_out);
end $f$;
revoke execute on function security.fee_plausibility_check_v1() from public, anon, authenticated;
comment on function security.fee_plausibility_check_v1() is 'CF-247 FEE (8 Nov 2026): read-only daily guard on active international provider_current_tuition fees; raises or clears one fee-plausibility flag per reason with row keys. Changes no fee.';

-- 3 the job (G1) ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('fee-plausibility-guard', 'Fees', 40, 'Fee plausibility guard', 'Daily, read-only: lists active provider fees that look wrong (an amount that is a calendar year, an AI fee on a held course, an odd fee year, an annual fee equal to the whole-course total) and raises a flag with the row keys. Changes no fee.', 4, false)
on conflict (jobname) do nothing;
select cron.schedule('fee-plausibility-guard', '41 17 * * *', $$select security.fee_plausibility_check_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('job', 'fee-plausibility-guard', 'Layer 2', 'Daily read-only plausibility guard on active provider fees', 'active', '20261108110000'),
 ('function', 'security.fee_plausibility_check_v1', 'Layer 2', 'Counts and flags implausible active provider fees (changes none)', 'active', '20261108110000')
on conflict (kind, name) do nothing;

do $post$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'fees.guard\_%') <> 8 then raise exception 'FEE guard post-check: settings'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'fee-plausibility-guard') then raise exception 'FEE guard post-check: catalogue'; end if;
end $post$;

select 'fee plausibility guard in place' ok;
