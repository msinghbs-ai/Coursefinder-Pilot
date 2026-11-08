-- Guards: F-INT.01/SRC-01 (9 Nov 2026), performance proof: the calendar qualification route on production-shaped volume (read 9 Nov 2026: 3,103 providers, 2,882 fact sources,
-- 1,440 calendar readings of which 67 proposed over 51 providers, 16,178 intake events of which 17 withdrawn, 202,478 stored pages, 7,584 manual locks). The route is bounded work:
-- at most batch.calendar_qualify readings a run, selected by index lookups (no scan of the readings, events or pages), the cheap checks before the dated reader. Budget stated here and
-- asserted: first run (25 readings) under 2,000 ms, a run with nothing to do under 100 ms, a dry run of all proposed readings under 5,000 ms; and the quiet run must not grow with the volume
-- (four times the providers, events and pages: under 2.5 times the time).
\set ON_ERROR_STOP on
\set QUIET on
\ir helpers.sql

create or replace function public.perf_grow(p_providers int, p_events int, p_pages int) returns void language plpgsql as $f$
declare i int; v uuid; s uuid; n int := 0;
begin
  for i in 1..p_providers loop
    v := public.cq_provider('perf' || gen_random_uuid(), 'Perf Provider ' || i, 'https://www.perf' || i || '-' || substr(md5(random()::text), 1, 6) || '.edu.au');
    if i % 10 < 9 then perform public.cq_source(v, 'https://www.' || md5(v::text) || '.edu.au/study/key-dates', null, 5); end if;
  end loop;
  insert into pipeline.evidence_artifacts(id, evidence_type, source_url, content_hash, captured_at)
  select gen_random_uuid(), 'page', 'https://perf.example/' || g, md5(g::text), now() - make_interval(days => g % 300) from generate_series(1, p_pages) g;
  insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, outcome, reason)
  select gen_random_uuid(), gen_random_uuid(), (select id from catalogue.providers order by id limit 1 offset (g % 500)), case when g % 950 = 0 then 'withdrawn' else 'skipped' end, 'perf'
    from generate_series(1, p_events) g;
end $f$;

-- production-shaped volume --------------------------------------------------------------------------------------------------------------------------
do $$
declare y int := public.cq_y(); d0 date := current_date + 40; r record; k int := 0; v uuid; s uuid; st text;
begin
  perform public.perf_grow(greatest(0, 3103 - (select count(*)::int from catalogue.providers)), 16178, 200000);
  -- the history: calendar readings approved, rejected and superseded (1,373), with real-shaped periods
  for r in select p.id from catalogue.providers p order by p.id limit 1373 loop
    k := k + 1; st := (array['approved', 'rejected', 'superseded'])[1 + k % 3];
    s := (select id from pipeline.provider_fact_sources where provider_id = r.id and kind = 'intake_calendar' limit 1);
    if s is null then s := public.cq_source(r.id, 'https://www.hist' || k || '.edu.au/key-dates', null, 5); end if;
    perform public.cq_proposal(r.id, s, 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
      jsonb_build_object('p', 'semester 1', 'd', d0 + 20 + k % 5), jsonb_build_object('p', 'semester 2', 'd', d0 + 200 + k % 5)), true), st);
  end loop;
  -- the 67 proposed readings over 51 providers (a mix a real queue holds)
  k := 0;
  for r in select p.id from catalogue.providers p where p.id not in (select provider_id from pipeline.provider_policy_proposals where kind = 'intake_calendar') order by p.id limit 51 loop
    k := k + 1;
    update catalogue.providers set website = 'https://www.q' || k || '.edu.au' where id = r.id;   -- the calendar is on the provider's own website, so the reading reaches the dated reader
    for j in 1..(case when k <= 16 then 2 else 1 end) loop
      s := public.cq_source(r.id, 'https://www.q' || k || '.edu.au/' || (array['key-dates', 'important-dates', 'study/how-to-apply', 'academic-calendar', 'future-students/online/dates', 'term-dates'])[1 + (k + j) % 6] || '/' || j, null, 3 + k % 5);
      perform public.cq_proposal(r.id, s, 'ai:gpt-4.1-mini:calendar-v2.1', public.cq_periods(jsonb_build_array(
        jsonb_build_object('p', 'semester 1', 'd', d0 + 20 + j), jsonb_build_object('p', 'semester 2', 'd', d0 + 200 + j), jsonb_build_object('p', 'semester 3', 'd', d0 + 280 + j)), true));
    end loop;
  end loop;
end $$;
analyze;
select 'volume: ' || (select count(*) from catalogue.providers) || ' providers, ' || (select count(*) from pipeline.provider_fact_sources) || ' fact sources, ' || (select count(*) from pipeline.provider_policy_proposals where kind = 'intake_calendar') || ' calendar readings ('
  || (select count(*) from pipeline.provider_policy_proposals where kind = 'intake_calendar' and status = 'proposed') || ' proposed over ' || (select count(distinct provider_id) from pipeline.provider_policy_proposals where kind = 'intake_calendar' and status = 'proposed') || ' providers), '
  || (select count(*) from pipeline.course_intake_date_events) || ' events (' || (select count(*) from pipeline.course_intake_date_events where outcome = 'withdrawn') || ' withdrawn), ' || (select count(*) from pipeline.evidence_artifacts) || ' stored pages' as perf_volume \gset
\echo PERF :perf_volume

-- the dry run, the first runs, the quiet run ---------------------------------------------------------------------------------------------------------
select public.cq_set('central.calendar_qualify_main_teaching', 1);
select public.cq_set('batch.calendar_qualify', 25);
do $$
declare t0 timestamptz; n int; ms_dry numeric; ms_first numeric; ms_all numeric := 0; ms_q numeric := 0; ms_q2 numeric := 0; r jsonb; runs int := 0; tot int := 0; i int; proposed int;
begin
  select count(*) into proposed from pipeline.provider_policy_proposals where kind = 'intake_calendar' and status = 'proposed';
  t0 := clock_timestamp(); select count(*) into n from security.calendar_qualify_dry_run_v1(); ms_dry := extract(epoch from clock_timestamp() - t0) * 1000;
  raise notice 'PERF dry run of % proposed readings (read only): % ms (% ms a reading)', n, round(ms_dry), round(ms_dry / n, 1);
  perform public.cq_assert('perf: the dry run covers every proposed reading', n = proposed);
  perform public.cq_assert('perf budget: dry run of all proposed readings under 5,000 ms', ms_dry < 5000, ms_dry::text);
  loop
    t0 := clock_timestamp(); r := security.calendar_qualify_v1(); ms_all := extract(epoch from clock_timestamp() - t0) * 1000;
    exit when coalesce((r->>'examined')::int, 0) = 0 or runs > 10;
    runs := runs + 1; tot := tot + (r->>'examined')::int;
    if runs = 1 then ms_first := ms_all; raise notice 'PERF first run: % readings, % approved, % ms (% ms a reading)', r->>'examined', r->>'approved', round(ms_first), round(ms_first / (r->>'examined')::int, 1); end if;
    raise notice 'PERF run %: examined %, approved %, held %, % ms', runs, r->>'examined', r->>'approved', r->>'held', round(ms_all);
  end loop;
  perform public.cq_assert('perf: all proposed readings were checked once in ' || runs || ' runs of at most 25', tot = proposed and runs = ceil(proposed / 25.0)::int, tot || ' of ' || proposed);
  perform public.cq_assert('perf budget: first run (25 readings, never checked) under 2,000 ms', ms_first < 2000, ms_first::text);
  -- the quiet run (nothing to do), the mean of 20 calls
  t0 := clock_timestamp(); for i in 1..20 loop perform security.calendar_qualify_v1(); end loop; ms_q := extract(epoch from clock_timestamp() - t0) * 1000 / 20;
  raise notice 'PERF quiet run (nothing due, nothing changed): % ms', round(ms_q, 2);
  perform public.cq_assert('perf budget: a run with nothing to do under 100 ms', ms_q < 100, ms_q::text);
  -- four times the volume: the quiet run must not grow with it
  perform public.perf_grow(9300, 48534, 600000);
  analyze;
  t0 := clock_timestamp(); for i in 1..20 loop perform security.calendar_qualify_v1(); end loop; ms_q2 := extract(epoch from clock_timestamp() - t0) * 1000 / 20;
  raise notice 'PERF quiet run at four times the providers, events and pages (% providers, % events, % pages): % ms (was % ms)', (select count(*) from catalogue.providers), (select count(*) from pipeline.course_intake_date_events), (select count(*) from pipeline.evidence_artifacts), round(ms_q2, 2), round(ms_q, 2);
  perform public.cq_assert('perf: the quiet run does not grow with the volume (four times the data, under 2.5 times the time, or under 20 ms)', ms_q2 < 2.5 * ms_q or ms_q2 < 20, ms_q2 || ' vs ' || ms_q);
  -- one change: one provider's new rejection brings back only its own readings
  insert into pipeline.intake_date_rejections(provider_id, quote, year, start_date, reason, case_ref, rejected_by, rejected_at)
  select provider_id, 'perf', extract(year from current_date)::int + 1, current_date + 700, 'perf', 'F-INT', 'Platform Admin', clock_timestamp() from pipeline.provider_policy_proposals where kind = 'intake_calendar' and status = 'proposed' order by id limit 1;
  t0 := clock_timestamp(); r := security.calendar_qualify_v1(); ms_all := extract(epoch from clock_timestamp() - t0) * 1000;
  raise notice 'PERF one change: examined %, % ms', r->>'examined', round(ms_all, 1);
  perform public.cq_assert('perf: one change looks at that provider''s readings only', (r->>'examined')::int between 1 and 2, r::text);
  -- the check of one reading
  t0 := clock_timestamp(); for i in 1..20 loop perform * from security.calendar_qualify_check_v1((select id from pipeline.provider_policy_proposals where kind = 'intake_calendar' and status = 'proposed' order by id limit 1)); end loop;
  raise notice 'PERF one check of one reading: % ms', round(extract(epoch from clock_timestamp() - t0) * 1000 / 20, 2);
end $$;
