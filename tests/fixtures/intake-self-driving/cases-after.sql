-- Guards: F-INT (valid course intake dates; data population mandate 9 Nov 2026), defects D3 and D2 AFTER migration 20261109040000, applied to the production-equivalent
-- fixture. Proves: (D3) a row held for evidence is looked at again on its revisit time from stored inputs; a revisit spends nothing, never re-admits a rejected or
-- withdrawn date and never overrides a lock; the other deterministic failures still have no timer; the switch works; the repeat alert does not fire on a scheduled look
-- but still fires on a genuine unchanged repeat. (D2) the fingerprint holds the page wording: a page read again with new wording is queued, the same wording
-- (in any order) is not, and nothing that was settled before the migration is queued again (no storm). Course-specific proof is unchanged (fill regression).
\set ON_ERROR_STOP on
\set QUIET on

-- time travel for the cases: a decision's history is moved back, as if the days had passed; one cycle = move back, then the production job runs
create or replace function public.sd_age(p_intakes uuid[], p_days numeric) returns void language plpgsql as $f$
begin
  update pipeline.course_intake_date_events set run_at = run_at - p_days * interval '1 day', next_revisit_at = next_revisit_at - p_days * interval '1 day' where intake_id = any (p_intakes);
  update pipeline.course_intake_dates set applied_at = applied_at - p_days * interval '1 day', next_revisit_at = next_revisit_at - p_days * interval '1 day' where intake_id = any (p_intakes);
end $f$;
create or replace function public.sd_cycle(p_names text[]) returns jsonb language plpgsql as $f$
declare v_i uuid[] := (select array_agg(intake_id) from public.sd_cases where name = any (p_names)); v_c uuid[] := (select array_agg(course_id) from public.sd_cases where name = any (p_names));
begin
  perform public.sd_age(v_i, 15);
  return security.intake_dates_apply_v1(100, v_c);
end $f$;
-- the rows that spend money or call out when a look reaches for new evidence: counted before and after a revisit
create or replace function public.sd_acquisition_counts() returns jsonb language plpgsql as $f$
declare t record; o jsonb := '{}'::jsonb; n bigint;
begin
  for t in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname = 'pipeline' and c.relkind = 'r' and (c.relname in ('evidence_artifacts', 'coverage_course_pages', 'field_enrich_items') or c.relname ~ '(spend|ledger|usage|budget|queue|lease)') order by 1 loop
    execute format('select count(*) from pipeline.%I', t.relname) into n; o := o || jsonb_build_object(t.relname, n);
  end loop;
  return o;
end $f$;

-- 0 the migration is in place --------------------------------------------------------------------------------------------------------------------
do $$
declare s record;
begin
  select * into s from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.revisit_stored_inputs';
  if s.key is null or s.label is null or s.min_value is null or s.max_value is null or s.unit is null or s.used_by is null or s.section is null or s.value is distinct from to_jsonb(1) or s.kind <> 'number' then
    raise exception 'setting: %', row_to_json(s); end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.revisit_days' and value = to_jsonb(14)) <> 1 then raise exception 'revisit_days'; end if;
  raise notice 'PASS setting (G2): intake_dates.revisit_stored_inputs has a label, a range (0 to 1), a unit (on/off), a section and a used_by line; it is on by default; the days are the existing intake_dates.revisit_days (14)';
end $$;

-- 1 D3 backfill: rows already waiting get a spread revisit time ------------------------------------------------------------------------------------
do $$
declare n int; n_days int; n_max int; n_all int; r record; bad int;
begin
  select count(*) into n_all from public.sd_state_before b join pipeline.course_intake_dates d using (intake_id)
    join catalogue.course_intakes i on i.id = d.intake_id join catalogue.courses c on c.id = i.course_id
   where i.status = 'active' and c.lifecycle_status = 'active' and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
     and b.next_revisit_at is null and b.next_action in ('evidence_ambiguous', 'reader_correction_needed', 'calendar_needs_correction', 'human_decision_required');
  select count(*), count(distinct (d.next_revisit_at at time zone 'UTC')::date), max(z.c) into n, n_days, n_max
    from public.sd_state_before b join pipeline.course_intake_dates d using (intake_id),
         lateral (select count(*) c from public.sd_state_before b2 join pipeline.course_intake_dates d2 using (intake_id) where b2.next_revisit_at is null and (d2.next_revisit_at at time zone 'UTC')::date = (d.next_revisit_at at time zone 'UTC')::date
                     and b2.next_action in ('evidence_ambiguous', 'reader_correction_needed', 'calendar_needs_correction', 'human_decision_required')) z
   where b.next_revisit_at is null and b.next_action in ('evidence_ambiguous', 'reader_correction_needed', 'calendar_needs_correction', 'human_decision_required') and d.next_revisit_at is not null;
  if n_all < 100 then raise exception 'fixture too small for the spread case: %', n_all; end if;
  select count(*) into bad from public.sd_state_before b join pipeline.course_intake_dates d using (intake_id)
   where b.next_revisit_at is null and b.next_action in ('evidence_ambiguous', 'reader_correction_needed', 'calendar_needs_correction', 'human_decision_required') and d.next_revisit_at is not null
     and (d.next_revisit_at < now() - interval '1 minute' or d.next_revisit_at > now() + make_interval(days => 14, mins => 1));
  if bad <> 0 then raise exception 'backfilled revisit times outside the next 14 days: %', bad; end if;
  if n < n_all or n_days < 12 or n_max::numeric / n > 0.15 then raise exception 'spread: % of % rows, % distinct days, busiest day % rows', n, n_all, n_days, n_max; end if;
  raise notice 'PASS backfill (D3): % undated active rows held for evidence, none with a revisit time, were given one inside the next 14 days, spread over % distinct days (the busiest day holds % per cent), so the 14-day cycle starts without a storm', n_all, n_days, round(100.0 * n_max / n, 1);
end $$;
-- everything else is as it was: a row outside the four actions, a row that already had a time, a row that is not undated-active
do $$
declare bad int;
begin
  select count(*) into bad from public.sd_state_before b join pipeline.course_intake_dates d using (intake_id)
   where (b.next_action not in ('evidence_ambiguous', 'reader_correction_needed', 'calendar_needs_correction', 'human_decision_required') or b.next_revisit_at is not null) and d.next_revisit_at is distinct from b.next_revisit_at;
  if bad <> 0 then raise exception 'a revisit time outside the four actions or already set was changed: % rows', bad; end if;
  if exists (select 1 from pipeline.course_intake_dates d join public.sd_state_before b using (intake_id) where d.applied_at is distinct from b.applied_at or d.next_action is distinct from b.next_action) then raise exception 'a decision, outcome or action was changed'; end if;
  raise notice 'PASS backfill scope: no decision, next action or applied time changed; the revisit time of a row outside the four actions, or that already had one, is unchanged';
end $$;

-- 2 D2: rows settled before the migration are not queued again; the page read again is ------------------------------------------------------------------
-- (the cases set the revisit times of the settled rows beyond the look window so that only the fingerprint decides)
update pipeline.course_intake_dates set next_revisit_at = now() + interval '10 days' where intake_id in (select intake_id from public.sd_cases where name in ('sAmb1', 'sAmb2', 'sNoRead', 'sPage', 'sSame'));
do $$
declare n int; r record; v_set text; v_settings text := 'lists=true;unique=false;rules=fair-evidence-1'; f text := '';
begin
  -- the settled rows hold the new fingerprint form, computed from the stored inputs
  for r in select k.name, d.inputs_fp, i.evidence_id, c.course_url, k.course_id, k.provider_id from public.sd_cases k join pipeline.course_intake_dates d on d.intake_id = k.intake_id
             join catalogue.course_intakes i on i.id = k.intake_id join catalogue.courses c on c.id = k.course_id where k.name in ('sAmb1', 'sAmb2', 'sNoRead', 'sPage', 'sSame') loop
    v_set := security.calendar_set_v1(r.provider_id);
    if r.name in ('sAmb1', 'sAmb2', 'sNoRead') and r.inputs_fp is distinct from security.intake_inputs_fp_v1(v_set, r.evidence_id, r.course_url, v_settings || ';wording=' || security.intake_wording_fp_v1(r.course_id, r.evidence_id)) then
      f := f || ' ' || r.name || ' not rewritten'; end if;
    -- a page read after the decision keeps its old fingerprint (looked at again once)
    if r.name in ('sPage', 'sSame') and r.inputs_fp is distinct from security.intake_inputs_fp_v1(v_set, r.evidence_id, r.course_url, v_settings) then f := f || ' ' || r.name || ' fingerprint was rewritten'; end if;
  end loop;
  if f <> '' then raise exception 'fingerprint backfill:%', f; end if;
  -- no storm: nothing settled is queued
  select count(*) into n from security.intake_dates_plan_v3((select array_agg(course_id) from public.sd_cases where name in ('sAmb1', 'sAmb2', 'sNoRead')), 100);
  if n <> 0 then raise exception 'settled rows queued after the migration: %', n; end if;
  -- the two pages read after their decision are queued, once
  select count(*) into n from security.intake_dates_plan_v3((select array_agg(course_id) from public.sd_cases where name in ('sPage', 'sSame')), 100);
  if n <> 2 then raise exception 'pages read again after the decision: % queued (expected 2)', n; end if;
  raise notice 'PASS backfill (D2): the 3 settled rows hold the new fingerprint and none is queued (no storm); the 2 rows whose page was read after the decision keep the old fingerprint and are queued once';
end $$;
-- the whole fixture: every row that was settled under the old fingerprint (and whose page was not read after its decision) is still settled under the new one
do $$
declare v_settings text := 'lists=true;unique=false;rules=fair-evidence-1'; v_i uuid[]; v_c uuid[]; n_set int; n_q int; n_all int;
begin
  select array_agg(d.intake_id), array_agg(d.course_id) into v_i, v_c
    from public.sd_state_before b join pipeline.course_intake_dates d using (intake_id) join catalogue.course_intakes i on i.id = d.intake_id join catalogue.courses co on co.id = i.course_id
   where i.status = 'active' and co.lifecycle_status = 'active' and (i.intake_year is null or i.start_date is null or i.application_deadline is null)
     and b.inputs_fp = security.intake_inputs_fp_v1(security.calendar_set_v1(d.provider_id), i.evidence_id, co.course_url, v_settings)
     and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = d.course_id and g.read_at > b.applied_at)
     and d.intake_id not in (select intake_id from public.sd_cases where intake_id is not null);
  n_set := coalesce(array_length(v_i, 1), 0);
  if n_set < 5 then raise exception 'fixture-wide no-storm case needs settled rows: %', n_set; end if;
  update pipeline.course_intake_dates set next_revisit_at = now() + interval '10 days' where intake_id = any (v_i);   -- only the fingerprint decides
  select count(*) into n_q from security.intake_dates_plan_v3(v_c, 100000) p where p.intake_id = any (v_i);
  if n_q <> 0 then raise exception 'storm: % of % settled rows are queued under the new fingerprint', n_q, n_set; end if;
  raise notice 'PASS no storm (fixture-wide): % undated active rows were settled under the old fingerprint with their page unread since; under the new fingerprint 0 of them are queued', n_set;
end $$;
do $$
declare v jsonb; p record; y0 int := public.fixture_dk_y0(); f text := '';
begin
  v := security.intake_dates_apply_v1(100, (select array_agg(course_id) from public.sd_cases where name in ('sPage', 'sSame')));
  select i.start_date, i.intake_year, d.outcome into p from public.sd_cases k join catalogue.course_intakes i on i.id = k.intake_id join pipeline.course_intake_dates d on d.intake_id = k.intake_id where k.name = 'sPage';
  if not (p.outcome = 'filled' and p.start_date = make_date(y0, 11, 1) and p.intake_year = y0) then raise exception 'sPage after its page was read again: %', row_to_json(p); end if;
  select i.start_date, i.intake_year, d.outcome into p from public.sd_cases k join catalogue.course_intakes i on i.id = k.intake_id join pipeline.course_intake_dates d on d.intake_id = k.intake_id where k.name = 'sSame';
  if not (p.outcome = 'skipped' and p.start_date is null) then raise exception 'sSame (same wording) was admitted: %', row_to_json(p); end if;
  if (select count(*) from security.intake_dates_plan_v3((select array_agg(course_id) from public.sd_cases where name in ('sPage', 'sSame')), 100)) <> 0 then raise exception 'looked at again after the new look'; end if;
  raise notice 'PASS re-read page (D2): the page that now names Trimester 3 is looked at again and filled with 1 November % through the same proof as any course; the page read again with the same wording is looked at once, stays held and settles under the new fingerprint', y0;
end $$;
-- the wording part: order does not matter, a change of wording does
do $$
declare w0 text; w1 text; w2 text; v_c uuid := (select course_id from public.sd_cases where name = 'sSame'); v_e uuid := (select i.evidence_id from public.sd_cases k join catalogue.course_intakes i on i.id = k.intake_id where k.name = 'sSame');
        n int;
begin
  update pipeline.coverage_course_pages g set candidates = g.candidates || jsonb_build_object('intake_context', jsonb_build_array('Intakes Trimesters 1, 2', 'Open day')), read_at = clock_timestamp() + interval '2 seconds' where g.course_id = v_c;
  w0 := security.intake_wording_fp_v1(v_c, v_e);
  update pipeline.coverage_course_pages g set candidates = g.candidates || jsonb_build_object('intake_context', jsonb_build_array('Open day', 'Intakes Trimesters 1, 2')), read_at = clock_timestamp() + interval '3 seconds' where g.course_id = v_c;
  w1 := security.intake_wording_fp_v1(v_c, v_e);
  if w0 is distinct from w1 then raise exception 'the wording fingerprint depends on the order of the stored quotes'; end if;
  -- the apply writes the new fingerprint of the wording it read; a repeat of the same wording in another order does not queue the row
  update pipeline.course_intake_dates set inputs_fp = security.intake_inputs_fp_v1(security.calendar_set_v1(provider_id), (select evidence_id from catalogue.course_intakes where id = intake_id), (select course_url from catalogue.courses where id = course_id),
         'lists=true;unique=false;rules=fair-evidence-1;wording=' || w0) where intake_id = (select intake_id from public.sd_cases where name = 'sSame');
  select count(*) into n from security.intake_dates_plan_v3(array[v_c], 10);
  if n <> 0 then raise exception 'the same wording in another order was queued'; end if;
  update pipeline.coverage_course_pages g set candidates = g.candidates || jsonb_build_object('intake_context', jsonb_build_array('Open day', 'Intakes Trimesters 1, 2, 3')), read_at = clock_timestamp() + interval '4 seconds' where g.course_id = v_c;
  w2 := security.intake_wording_fp_v1(v_c, v_e);
  select count(*) into n from security.intake_dates_plan_v3(array[v_c], 10);
  if w2 = w0 or n <> 1 then raise exception 'a change of wording was not queued: % rows', n; end if;
  update pipeline.coverage_course_pages g set candidates = g.candidates || jsonb_build_object('intake_context', jsonb_build_array('Intakes Trimesters 1, 2', 'Open day')) where g.course_id = v_c;
  if security.intake_wording_fp_v1(v_c, v_e) <> w0 then raise exception 'unrepeatable'; end if;
  raise notice 'PASS wording fingerprint (D2): the same stored quotes in another order give the same value and queue nothing; a changed quote gives another value and queues the row';
end $$;

-- 3 D3 real path: the production job writes the revisit time; the row is looked at again when it is due, from stored inputs ----------------------------------
do $$
declare v_src uuid; v_prov uuid := (select provider_id from public.sd_cases where name = 'calendar'); v_int uuid; v_course uuid;
begin
  select i.intake_id into v_src from public.sd_cases i where i.name = 'sAmb1';
  v_int := public.fixture_clone_intake(v_src, 'November', 'Study with us. Apply now');
  select course_id into v_course from catalogue.course_intakes where id = v_int;
  update catalogue.courses set provider_id = v_prov where id = v_course;
  insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status, country_code, course_stable_key, intake_options)
  select c.id, v_prov, '6cc98ba2-045f-e409-8d24-356d14447085', 'Fixture Self-driving University', c.canonical_title, lower(c.canonical_title), to_tsvector('simple', c.canonical_title), 'published', 'AU', 'course:cricos:fixturesd:099', '[]'::jsonb from catalogue.courses c where c.id = v_course;
  insert into public.sd_cases(name, intake_id, course_id, provider_id, y0) values ('sNew', v_int, v_course, v_prov, public.fixture_dk_y0());
  perform search.refresh_course_enrichment_scoped_v1(array[v_course], true);
end $$;
create table public.sd_counts_before as select public.sd_acquisition_counts() c;
do $$
declare v jsonb; d record;
begin
  v := security.intake_dates_apply_v1(100, array[(select course_id from public.sd_cases where name = 'sNew')]);
  select * into d from pipeline.course_intake_dates x where x.intake_id = (select intake_id from public.sd_cases where name = 'sNew');
  if not (d.outcome = 'skipped' and d.next_action = 'evidence_ambiguous' and d.deterministic and d.failure_class = 'no_matching_commencement_period') then raise exception 'sNew: %', row_to_json(d); end if;
  if d.next_revisit_at is null or abs(extract(epoch from (d.next_revisit_at - (d.applied_at + interval '14 days')))) > 60 then raise exception 'revisit time is not intake_dates.revisit_days after the decision: % / %', d.applied_at, d.next_revisit_at; end if;
  -- the event row carries it too (the history shows when the look is due)
  if (select e.next_revisit_at from pipeline.course_intake_date_events e where e.intake_id = d.intake_id order by e.run_at desc limit 1) is distinct from d.next_revisit_at then raise exception 'event revisit time'; end if;
  if (select count(*) from security.intake_dates_plan_v3(array[d.course_id], 10)) <> 0 then raise exception 'looked at again before it is due'; end if;
  raise notice 'PASS revisit time (D3): the production job gives a deterministic evidence_ambiguous failure a revisit time 14 days after the decision (intake_dates.revisit_days); it is not looked at before then';
end $$;
-- three cycles of fifteen days: each look is a separate job run
select public.sd_cycle(array['sNew', 'sAmb1', 'sAmb2', 'sNoRead', 'sPage']) is not null as cycle_1;
select public.sd_cycle(array['sNew', 'sAmb1', 'sAmb2', 'sNoRead']) is not null as cycle_2;
select public.sd_cycle(array['sNew', 'sAmb1', 'sAmb2', 'sNoRead']) is not null as cycle_3;
do $$
declare r record; f text := ''; c0 jsonb; c1 jsonb; n_ev int;
begin
  -- sPage was filled before the cycles: it is complete for the plan (dated) and is not looked at
  for r in select k.name, i.start_date, i.intake_year, d.outcome, d.next_action, d.next_revisit_at, (select count(*) from pipeline.course_intake_date_events e where e.intake_id = k.intake_id) ev
             from public.sd_cases k join catalogue.course_intakes i on i.id = k.intake_id join pipeline.course_intake_dates d on d.intake_id = k.intake_id where k.name in ('sNew', 'sAmb1', 'sAmb2', 'sNoRead') loop
    if r.start_date is not null or r.intake_year is not null or r.outcome <> 'skipped' then f := f || ' ' || r.name || ' was filled by a revisit of unchanged inputs: ' || row_to_json(r)::text; end if;
    if r.next_revisit_at is null or r.next_revisit_at < now() + interval '13 days' then f := f || ' ' || r.name || ' has no new revisit time'; end if;
    if r.name = 'sNew' and r.ev <> 4 then f := f || ' sNew events ' || r.ev; end if;
  end loop;
  if f <> '' then raise exception 'cycles:%', f; end if;
  c0 := (select c from public.sd_counts_before); c1 := public.sd_acquisition_counts();
  if c0 is distinct from c1 then raise exception 'a revisit changed the acquisition tables: % -> %', c0, c1; end if;
  raise notice 'PASS revisit cycles (D3): 3 further looks of 4 held rows (sNew 4 decisions in all) were made when due; each re-read the stored inputs, wrote a decision and a new revisit time 14 days on, and changed no date; the acquisition and spend tables (%) are identical before and after', (select string_agg(k || '=' || v, ' ') from jsonb_each_text(c1) e(k, v));
end $$;

-- 4 a revisit spends nothing: the code that a look runs reaches no crawler, reader, AI call or acquisition queue (transitive scan of every function it calls) ------------
do $$
declare todo text[] := array['security.intake_dates_apply_v1', 'security.intake_dates_plan_v3', 'security.intake_failure_class_trg_v1', 'security.intake_revisit_at_v1', 'security.intake_revisit_stored_inputs_v1', 'security.intake_wording_fp_v1'];
        seen text[] := '{}'; cur text; body text; m text[]; hits text := ''; nm text;
begin
  while array_length(todo, 1) > 0 loop
    cur := todo[1]; todo := todo[2:]; continue when cur = any (seen); seen := seen || cur;
    for body in select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname || '.' || p.proname = cur and p.prokind = 'f' loop
      if body ~* '(net\.http|http_post|http_get|firecrawl|openrouter|openai|anthropic|crawl|pg_net|svc_pilot_submit|dblink|coverage_queue|enrich_queue|insert into pipeline\.(coverage|enrich|field_enrich|evidence))' then hits := hits || ' ' || cur; end if;
      for m in select regexp_matches(body, '\m(security|public|search)\.([a-z0-9_]+)\(', 'g') loop
        nm := m[1] || '.' || m[2]; if not nm = any (seen) and not nm = any (todo) then todo := todo || nm; end if;
      end loop;
    end loop;
  end loop;
  if hits <> '' then raise exception 'a function a revisit runs reaches out:%', hits; end if;
  if array_length(seen, 1) < 20 then raise exception 'the scan reached only % functions', array_length(seen, 1); end if;
  raise notice 'PASS no spend (static): % functions reachable from the job (apply, plan, the trigger and the new helpers) contain no http call, crawler, reader, AI call or acquisition-queue write', array_length(seen, 1);
end $$;

-- 5 a revisit never re-admits a rejected, withdrawn or locked value ---------------------------------------------------------------------------------------
-- rejected: a person rejects the calendar's reading before the course is decided (the memory is per university, reading, quote and year); the plan holds it
do $$
declare v_c record; p record; y0 int := public.fixture_dk_y0();
begin
  select * into v_c from public.sd_cases where name = 'sRej';
  if (select p2.new_start from security.intake_dates_plan_v3(array[v_c.course_id], 10) p2) is distinct from make_date(y0, 11, 1) then raise exception 'sRej is not eligible before the rejection'; end if;
  insert into pipeline.intake_date_rejections(provider_id, proposal_id, quote, year, start_date, reason, case_ref, rejected_by)
  select v_c.provider_id, c.proposal_id, c.quote, c.year, c.on_date, 'fixture: a person rejected this reading of the calendar', 'F-INT', 'fixture'
    from security.calendar_dated_periods_v2(v_c.provider_id) c where c.period = 'trimester 3' and c.kind = 'start';
  if (select count(*) from pipeline.intake_date_rejections where provider_id = v_c.provider_id) <> 1 then raise exception 'rejection not recorded'; end if;
  perform security.intake_dates_apply_v1(100, array[v_c.course_id]);
  select i.start_date, d.outcome, d.next_action, d.next_revisit_at into p from catalogue.course_intakes i join pipeline.course_intake_dates d on d.intake_id = i.id where i.id = v_c.intake_id;
  if p.outcome <> 'skipped' or p.start_date is not null then raise exception 'rejected value admitted at once: %', row_to_json(p); end if;
  if p.next_revisit_at is null then raise exception 'the rejected value is not on a revisit timer (%)', p.next_action; end if;
end $$;
select public.sd_cycle(array['sRej']) is not null as cycle_1;
select public.sd_cycle(array['sRej']) is not null as cycle_2;
select public.sd_cycle(array['sRej']) is not null as cycle_3;
do $$
declare p record;
begin
  select i.start_date, i.intake_year, d.outcome, d.next_revisit_at, (select count(*) from pipeline.course_intake_date_events e where e.intake_id = i.id) ev into p
    from public.sd_cases k join catalogue.course_intakes i on i.id = k.intake_id join pipeline.course_intake_dates d on d.intake_id = i.id where k.name = 'sRej';
  if p.start_date is not null or p.intake_year is not null or p.outcome <> 'skipped' or p.ev <> 4 or p.next_revisit_at is null then raise exception 'rejected value after 3 looks: %', row_to_json(p); end if;
  delete from pipeline.intake_date_rejections;   -- the fixture sets the rejection aside so the other cases see the whole calendar
  raise notice 'PASS no re-admission (rejected): a calendar value in pipeline.intake_date_rejections was looked at again on 3 revisit times (4 decisions in all) and never admitted';
end $$;
-- withdrawn: filled, then withdrawn by a person through the governed function; the hold is lifted so only the withdrawn-value guard is in play
do $$
declare v_c record; v jsonb; y0 int := public.fixture_dk_y0();
begin
  select * into v_c from public.sd_cases where name = 'sWd';
  perform security.intake_dates_apply_v1(100, array[v_c.course_id]);
  if (select start_date from catalogue.course_intakes where id = v_c.intake_id) is distinct from make_date(y0, 11, 1) then raise exception 'sWd was not filled'; end if;
  v := security.intake_date_withdraw_v1(v_c.intake_id, 'F-INT fixture: value withdrawn by a person', 'fixture', true);
  if not (v->>'withdrawn')::boolean then raise exception 'withdraw: %', v; end if;
  delete from pipeline.manual_locks where entity = 'course' and entity_id = v_c.course_id and field = 'intakes';
  update pipeline.course_intake_dates set inputs_fp = 'fixture: a person lifted the hold' where intake_id = v_c.intake_id;
  perform security.intake_dates_apply_v1(100, array[v_c.course_id]);
end $$;
-- locked by hand: a person's lock holds the intake
do $$
declare v_c record;
begin
  select * into v_c from public.sd_cases where name = 'sLock';
  insert into pipeline.manual_locks(entity, entity_id, field, mode, set_at) values ('course', v_c.course_id, 'intakes', 'value', now());
  perform security.intake_dates_apply_v1(100, array[v_c.course_id]);
end $$;
select public.sd_cycle(array['sWd', 'sLock']) is not null as cycle_1;
select public.sd_cycle(array['sWd', 'sLock']) is not null as cycle_2;
select public.sd_cycle(array['sWd', 'sLock']) is not null as cycle_3;
do $$
declare r record; f text := '';
begin
  for r in select k.name, i.start_date, i.intake_year, d.outcome, d.reason, d.next_action, d.next_revisit_at, (select count(*) from pipeline.course_intake_date_events e where e.intake_id = k.intake_id) ev
             from public.sd_cases k join catalogue.course_intakes i on i.id = k.intake_id join pipeline.course_intake_dates d on d.intake_id = k.intake_id where k.name in ('sWd', 'sLock') loop
    if r.start_date is not null or r.intake_year is not null or r.outcome <> 'skipped' then f := f || ' ' || r.name || ' admitted by a revisit: ' || row_to_json(r)::text; end if;
    if r.name = 'sWd' and r.reason not like 'withdrawn: %' then f := f || ' sWd reason ' || r.reason; end if;
    if r.name = 'sLock' and r.reason <> 'intakes locked by hand' then f := f || ' sLock reason ' || r.reason; end if;
    if r.next_revisit_at is null then f := f || ' ' || r.name || ' not on a revisit timer (' || r.next_action || ')'; end if;
    if r.ev < 4 then f := f || ' ' || r.name || ' was not looked at on each cycle (events ' || r.ev || ')'; end if;
  end loop;
  if f <> '' then raise exception 'non-readmission:%', f; end if;
  raise notice 'PASS no re-admission (withdrawn, locked): the withdrawn value (withdrawn-value guard) and the intake locked by hand were each looked at again on 3 revisit times and never admitted';
end $$;
-- the lock lifted by a person: the next look finds it and fills the intake (the platform drives the recovery)
do $$
declare v_c record;
begin
  select * into v_c from public.sd_cases where name = 'sLock';
  delete from pipeline.manual_locks where entity = 'course' and entity_id = v_c.course_id and field = 'intakes';
end $$;
select public.sd_cycle(array['sLock']) is not null as cycle_after_lock_lifted;
do $$
declare y0 int := public.fixture_dk_y0();
begin
  if (select start_date from catalogue.course_intakes i join public.sd_cases k on k.intake_id = i.id where k.name = 'sLock') is distinct from make_date(y0, 11, 1) then raise exception 'the look after the lock was lifted did not fill the intake'; end if;
  raise notice 'PASS self-driving: after a person lifts the lock, the next scheduled look fills 1 November % through the same proof, with no manual run', y0;
end $$;

-- 6 the other deterministic failures still have no timer; the four have one; the switch ----------------------------------------------------------------
begin;
do $$
declare v_i uuid := (select intake_id from public.sd_cases where name = 'sAmb2'); d record; f text := '';
begin
  -- each of the four next actions, with a real reason of the production classifier, gets the time
  update pipeline.course_intake_dates set reason = 'the course page names no study period', next_action = 'evidence_ambiguous', next_revisit_at = null where intake_id = v_i;
  select * into d from pipeline.course_intake_dates where intake_id = v_i; if d.next_revisit_at is null or not d.deterministic then f := f || ' evidence_ambiguous'; end if;
  update pipeline.course_intake_dates set reason = 'no stored reading of the page (month only)', next_action = 'reader_correction_needed', next_revisit_at = null where intake_id = v_i;
  select * into d from pipeline.course_intake_dates where intake_id = v_i; if d.next_revisit_at is null or not d.deterministic then f := f || ' reader_correction_needed'; end if;
  update pipeline.course_intake_dates set reason = 'no valid academic calendar (the approved reading was set aside)', next_action = 'calendar_needs_correction', next_revisit_at = null where intake_id = v_i;
  select * into d from pipeline.course_intake_dates where intake_id = v_i; if d.next_revisit_at is null or not d.deterministic then f := f || ' calendar_needs_correction (' || coalesce(d.failure_class, '-') || ')'; end if;
  update pipeline.course_intake_dates set reason = 'kept by a lock or the same-month guard', next_action = 'human_decision_required', next_revisit_at = null where intake_id = v_i;
  select * into d from pipeline.course_intake_dates where intake_id = v_i; if d.next_revisit_at is null then f := f || ' human_decision_required'; end if;
  -- every other deterministic failure: still no timer (the 5 Nov mandate, section 9, stands for them)
  update pipeline.course_intake_dates set reason = 'no valid academic calendar for this university', next_action = 'awaiting_official_calendar', next_revisit_at = null where intake_id = v_i;
  select * into d from pipeline.course_intake_dates where intake_id = v_i; if d.next_revisit_at is not null or not d.deterministic then f := f || ' awaiting_official_calendar has a timer'; end if;
  update pipeline.course_intake_dates set reason = 'the calendar does not print the year of the named period', next_action = 'waiting_for_next_academic_year', next_revisit_at = null where intake_id = v_i;
  select * into d from pipeline.course_intake_dates where intake_id = v_i; if d.next_revisit_at is not null and d.deterministic then f := f || ' a deterministic wait kept a timer'; end if;
  if f <> '' then raise exception 'timers:%', f; end if;
  -- the switch: off, the four get none; on again, they do
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.revisit_stored_inputs';
  if security.intake_revisit_stored_inputs_v1('evidence_ambiguous') or security.intake_revisit_at_v1('evidence_ambiguous') is not null then raise exception 'switch off: helper'; end if;
  if security.intake_revisit_at_v1('awaiting_official_calendar') is null then raise exception 'switch off: the original waiting actions lost their time'; end if;
  update pipeline.course_intake_dates set reason = 'the course page names no study period', next_action = 'evidence_ambiguous', next_revisit_at = null where intake_id = v_i;
  select * into d from pipeline.course_intake_dates where intake_id = v_i; if d.next_revisit_at is not null then raise exception 'switch off: the failure still got a timer'; end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.revisit_stored_inputs';
  update pipeline.platform_toolset_settings set value = to_jsonb(30) where toolset_key = 'pipeline' and key = 'intake_dates.revisit_days';
  update pipeline.course_intake_dates set reason = 'the course page names no study period', next_action = 'evidence_ambiguous', next_revisit_at = null where intake_id = v_i;
  select * into d from pipeline.course_intake_dates where intake_id = v_i; if d.next_revisit_at is null or d.next_revisit_at < now() + interval '29 days' then raise exception 'revisit_days is not read: %', d.next_revisit_at; end if;
  raise notice 'PASS timers and switch: evidence_ambiguous, reader_correction_needed, calendar_needs_correction and human_decision_required get a revisit time; awaiting_official_calendar and a deterministic wait for the next year keep none (mandate section 9 stands for them); with intake_dates.revisit_stored_inputs off the four get none; the days come from intake_dates.revisit_days';
end $$;
rollback;

-- 7 the repeat alert: a look on its own revisit time is not an unchanged repeat; a repeat before the time still is ---------------------------------------------------
begin;
do $$
declare v jsonb; ev int; r record;
begin
  -- the cases look at the history of the cycled rows only, and the settings are older than the decisions (no setting-change exclusion)
  delete from pipeline.course_intake_date_events where intake_id not in (select intake_id from public.sd_cases where name in ('sNew', 'sAmb1', 'sAmb2', 'sNoRead'));
  update pipeline.platform_toolset_settings set updated_at = now() - interval '60 days';
  v := security.intake_progress_repeats_v1();
  select count(distinct intake_id) into ev from pipeline.course_intake_date_events where run_at >= now() - interval '1 day' and deterministic and outcome = 'skipped';
  if (v->>'confirmed')::int <> 0 or (v->>'excluded_scheduled_revisit')::int <> 4 or ev <> 4 then raise exception 'scheduled looks: %', v; end if;
  -- a genuine unchanged repeat: the same refusal decided again BEFORE the earlier decision's revisit time
  insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, rule, outcome, reason, next_action, calendar_set, proposal_id, periods, start_precision, deadline_kind, before_value, after_value, page_quote, start_quote, deadline_quote, calendar_url, calendar_evidence_id, bounded)
  select e.intake_id, e.course_id, e.provider_id, e.rule, e.outcome, e.reason, e.next_action, e.calendar_set, e.proposal_id, e.periods, e.start_precision, e.deadline_kind, e.before_value, e.after_value, e.page_quote, e.start_quote, e.deadline_quote, e.calendar_url, e.calendar_evidence_id, e.bounded
    from pipeline.course_intake_date_events e where e.intake_id = (select intake_id from public.sd_cases where name = 'sNew') order by e.run_at desc limit 1;
  v := security.intake_progress_repeats_v1();
  if (v->>'confirmed')::int <> 1 then raise exception 'a repeat before the revisit time is not confirmed: %', v; end if;
  raise notice 'PASS repeat alert: the 4 looks made on their own revisit time are classified excluded_scheduled_revisit (shown, never raised; confirmed 0); the same refusal decided again before the revisit time is still confirmed (1) and raises intake-progress:repeated-deterministic';
end $$;
rollback;

-- 8 the eligible course is filled exactly as before: course-specific proof is unchanged -----------------------------------------------------------------------
do $$
declare a jsonb; b jsonb; y0 int := public.fixture_dk_y0(); k record;
begin
  select * into k from public.sd_cases where name = 'sElig';
  select to_jsonb(x) into a from (select new_year, new_start, new_deadline, outcome, reason, start_precision, deadline_kind, start_quote, periods, next_action from security.intake_dates_plan_v3(array[k.course_id], 10)) x;
  select to_jsonb(x) into b from public.sd_plan_before x;
  if a is distinct from b then raise exception 'the plan result for an eligible course changed: % / %', a, b; end if;
  perform security.intake_dates_apply_v1(100, array[k.course_id]);
  if (select start_date from catalogue.course_intakes where id = k.intake_id) is distinct from make_date(y0, 11, 1) then raise exception 'eligible course not filled'; end if;
  raise notice 'PASS fill regression: the plan result for the eligible course (outcome, reason, start, year, period, quote) is identical before and after the migration, and the job fills 1 November %', y0;
end $$;

-- 9 the applicability fix: the same inputs, no error; every input without a month followed by a year returns exactly what it returned before ------------------------
do $$
declare r record; f text := ''; a text; y0 int := public.fixture_dk_y0();
begin
  for r in select b.n, b.result before_result, public.sd_appl(b.n) after_result from public.sd_appl_before b order by 1 loop
    if r.n in (1, 2, 3) and r.after_result <> '<offered>' then f := f || ' input ' || r.n || ' gave ' || r.after_result; end if;
    if r.n = 4 and r.after_result not like 'the course page does not state February as an intake%' then f := f || ' past year: ' || r.after_result; end if;
    if r.n > 4 and r.after_result is distinct from r.before_result then f := f || ' input ' || r.n || ' changed: ' || r.before_result || ' -> ' || r.after_result; end if;
  end loop;
  if f <> '' then raise exception 'applicability after the fix:%', f; end if;
  -- the plan no longer raises, and the course is filled through the same proof as any other
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';
  select p.new_start into a from security.intake_dates_plan_v3(array[(select course_id from public.sd_cases where name = 'sMY')], 10) p;
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.month_unique_match';
  if a::date is distinct from make_date(y0, 11, 1) then raise exception 'sMY after the fix: %', a; end if;
  raise notice 'PASS applicability fix: "February 2027", "25 January 2027" and "May 2027, September 2027" are read as offerings (a month of a past year still is not), 8 inputs return exactly what they returned before, and on the month-only path the plan fills the course whose page prints "November % intake" with 1 November %', y0, y0;
end $$;
