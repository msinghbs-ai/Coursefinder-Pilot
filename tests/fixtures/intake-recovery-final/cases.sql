-- Guards: Platform Admin mandate 5 Nov 2026 12:44 §11 (mandatory production-parity DB tests), R1, R2, §4, §6, §8, §9: migration
-- 20261105040000 on the calendar-v2 fixture database (production shapes, live definitions by md5). Cases: UNSW year-in-heading (year tabs),
-- year from the wrong section rejected, college rejected, offshore rejected, exact course start date, unique month, multiple periods, missing
-- year, old edition not used, explicit course date overrides the calendar, validated data admitted, held data protected, publication matches
-- the catalogue, duplicate recovery prevented; failure classes; re-read on a reader change; bounded refresh within its credits.
\set ON_ERROR_STOP on
\set QUIET on
create temp table k(name text primary key, id uuid);

do $$
declare src uuid; v_prov uuid := '08609bcf-387d-1316-2a52-9fbc0edff508';
begin
  select i.id into src from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id join pipeline.evidence_artifacts e on e.id = i.evidence_id
   where c.provider_id = v_prov and i.status = 'active' and c.lifecycle_status = 'active' and i.course_id not in (select course_id from catalogue.course_intakes where intake_label = 'Fixture')
     and not security.page_refused_v1(c.id, e.source_url) and security.course_page_check_v1(c.id, e.source_url, null, null)->>'verdict' = 'pass'
   order by i.id limit 1;
  if src is null then raise exception 'no proved Harbour intake to copy'; end if;
  -- a calendar-v2.1 reading of a UNSW-style page: the year of each term from the year tabs above repeated blocks (no year in the row)
  insert into k values ('unsw', public.fixture_calendar('https://www.harbour.edu.au/academic-calendars', 'ai:gpt-4.1-mini:calendar-v2.1', $j${"parser": "ai:gpt-4.1-mini:calendar-v2.1", "reader": "calendar-v2.1", "scope": "main_teaching", "periods": [
    {"period": "term 1", "months": [2], "years": [2027], "quotes": ["Teaching period T1 | 15 Feb - 23 Apr"],
     "starts": [{"year": 2027, "month": 2, "day": 15, "date": "2027-02-15", "quote": "Teaching period T1 | 15 Feb - 23 Apr", "year_quote": "year tabs 2026 | 2027: block 2 of \"### Term 1\" is 2027", "year_basis": "tabs", "meaning": "teaching_start"}], "deadlines": []},
    {"period": "term 2", "months": [5], "years": [2027], "quotes": ["Teaching period T2 | 31 May - 6 Aug"],
     "starts": [{"year": 2027, "month": 5, "day": 31, "date": "2027-05-31", "quote": "Teaching period T2 | 31 May - 6 Aug", "year_quote": "year tabs 2026 | 2027: block 2 of \"### Term 2\" is 2027", "year_basis": "tabs", "meaning": "teaching_start"}], "deadlines": []},
    {"period": "term 3", "months": [9], "years": [], "quotes": ["Teaching period T3 | 13 Sep - 19 Nov"],
     "starts": [{"year": null, "month": 9, "day": 13, "date": null, "quote": "Teaching period T3 | 13 Sep - 19 Nov", "meaning": "teaching_start"}], "deadlines": []},
    {"period": "semester 1", "months": [2], "years": [2028], "quotes": ["Teaching period S1 | 28 Feb - 26 May"],
     "starts": [{"year": 2028, "month": 2, "day": 28, "date": "2028-02-28", "quote": "Teaching period S1 | 28 Feb - 26 May", "meaning": "teaching_start"}], "deadlines": []}]}$j$::jsonb));
  insert into k values
    ('t1', public.fixture_clone_intake(src, 'February', 'Term 1 intake', 2027)),
    ('t2', public.fixture_clone_intake(src, 'May', 'Term 2 intake', 2027)),
    ('t3', public.fixture_clone_intake(src, 'September', 'Term 3 intake', 2027)),
    ('s1', public.fixture_clone_intake(src, 'February', 'Semester 1 intake', 2028)),
    ('own', public.fixture_clone_intake(src, 'February', 'Term 1 intake: classes begin 8 February 2027', 2027)),
    ('lock', public.fixture_clone_intake(src, 'February', 'Term 1 intake', 2027)),
    ('feb28', public.fixture_clone_intake(src, 'February', 'February intake', 2029));
  insert into pipeline.manual_locks(entity, entity_id, field) select 'course', course_id, 'intakes' from catalogue.course_intakes where id = (select id from k where name = 'lock');
end $$;

-- the plan and the classes ---------------------------------------------------------------------------------------------------------------
do $$
declare v jsonb; v_courses uuid[] := (select array_agg(course_id) from catalogue.course_intakes where id in (select id from k)); r record; f text := '';
begin
  update pipeline.platform_toolset_settings set value = to_jsonb(true) where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled';
  v := security.intake_dates_apply_v1(100, v_courses);
  for r in select k.name, d.*, i.start_date cat_start, i.intake_year cat_year from k join pipeline.course_intake_dates d on d.intake_id = k.id join catalogue.course_intakes i on i.id = k.id where k.name <> 'unsw' loop
    f := f || case
      -- UNSW year-in-heading: the year from the tabs is evidence; the term's exact date is admitted
      when r.name = 't1' and not (r.outcome = 'filled' and r.cat_start = '2027-02-15' and r.start_precision = 'day' and r.failure_class = 'missing_application_deadline_evidence' and r.deterministic and r.next_revisit_at is null
                                  and r.reader = 'ai:gpt-4.1-mini:calendar-v2.1' and r.evidence_year = 2027) then ' t1 ' || row_to_json(r)::text
      when r.name = 't2' and not (r.outcome = 'filled' and r.cat_start = '2027-05-31') then ' t2 ' || row_to_json(r)::text
      -- missing year: the reader kept no year for Term 3, so no date and the year is unproven (deterministic: waits for a change)
      when r.name = 't3' and not (r.outcome = 'skipped' and r.cat_start is null and r.failure_class = 'academic_year_unproven' and r.deterministic and r.next_revisit_at is null) then ' t3 ' || row_to_json(r)::text
      -- year from the wrong section: a 2028 start with no year evidence on its row is never used
      when r.name = 's1' and not (r.outcome = 'skipped' and r.cat_start is null and r.failure_class = 'academic_year_unproven') then ' s1 ' || row_to_json(r)::text
      -- explicit course date overrides the calendar: the calendar date is not admitted
      when r.name = 'own' and not (r.outcome = 'skipped' and r.cat_start is null and r.failure_class = 'course_level_exception' and r.reason like 'the course page gives its own start date%') then ' own ' || row_to_json(r)::text
      -- held data protected
      when r.name = 'lock' and not (r.outcome = 'skipped' and r.cat_start is null and r.failure_class = 'admission_held' and r.deterministic) then ' lock ' || row_to_json(r)::text
      -- old edition not used: no calendar proves the intake's year
      when r.name = 'feb28' and not (r.outcome = 'skipped' and r.cat_start is null and r.failure_class = 'stale_calendar_edition' and r.revisit_trigger like 'a newer calendar edition%') then ' feb28 ' || row_to_json(r)::text
      else '' end;
  end loop;
  if f <> '' then raise exception 'classes and values:%', f; end if;
  -- multiple periods and a unique month (decided in the calendar-v2 cases): their durable classes
  if (select failure_class from security.intake_failure_class_v1('skipped', 'several study periods start in this month (month only)', false, null, '08609bcf-387d-1316-2a52-9fbc0edff508', null, 7)) <> 'multiple_periods_match'
     or (select failure_class from security.intake_failure_class_v1('filled', null, true, 'date', '08609bcf-387d-1316-2a52-9fbc0edff508', 2027, 2)) is not null
     or (select failure_class from security.intake_failure_class_v1('skipped', 'no valid academic calendar: the approved calendars are set aside (not the main teaching calendar)', false, null, '08609bcf-387d-1316-2a52-9fbc0edff508', null, 2)) <> 'wrong_institution_or_campus'
  then raise exception 'class mapping'; end if;
  if exists (select 1 from pipeline.course_intake_date_events e where e.intake_id in (select id from k) and e.failure_class is distinct from (select d.failure_class from pipeline.course_intake_dates d where d.intake_id = e.intake_id)
               and e.outcome <> 'filled') then raise exception 'event class differs from the row'; end if;
  raise notice 'PASS R1 and §9: UNSW-style tab year admits 15 Feb and 31 May 2027 (day); missing year, wrong-section year, course date, lock, two periods and an old edition keep the month with their durable class; deterministic failures have no timer revisit';
end $$;

-- unchanged deterministic failures are not looked at again; a change of inputs brings them back -------------------------------------------
do $$
declare v jsonb; v_courses uuid[] := (select array_agg(course_id) from catalogue.course_intakes where id in (select id from k));
begin
  update pipeline.course_intake_dates set next_revisit_at = null where intake_id in (select id from k);  -- as the trigger left them
  v := security.intake_dates_apply_v1(100, v_courses);
  if (v->>'looked_at')::int <> 0 then raise exception 'unchanged deterministic failures looked at again: %', v; end if;
  raise notice 'PASS §9: an unchanged deterministic failure is never repeated without a change';
end $$;

-- publication matches the catalogue -------------------------------------------------------------------------------------------------------
do $$
declare v jsonb; t1 uuid := (select id from k where name = 't1'); v_course uuid;
begin
  select course_id into v_course from catalogue.course_intakes where id = t1;
  v := security.intake_publication_check_v1();
  if (select publication_state from pipeline.course_intake_dates where intake_id = t1) is null then raise exception 'not checked: %', v; end if;
  if (select publication_state from pipeline.course_intake_dates where intake_id = t1) = 'published'
     and not exists (select 1 from search.course_documents cd, jsonb_array_elements(cd.intake_options) e where cd.course_id = v_course and e->>'start_date' = '2027-02-15') then
    raise exception 'published without the value in the source'; end if;
  -- a value admitted but missing from the consumer source is a durable failure, not a silent drop
  update search.course_documents set intake_options = '[]'::jsonb where course_id = v_course;
  if not found then insert into search.course_documents(course_id, provider_id, intake_options) select v_course, provider_id, '[]'::jsonb from catalogue.courses where id = v_course; end if;
  update pipeline.course_intake_dates set publication_checked_at = null where intake_id = t1;
  v := security.intake_publication_check_v1();
  if (select publication_state || '/' || failure_class from pipeline.course_intake_dates where intake_id = t1) <> 'consumer_publication_failed/consumer_publication_failed' then
    raise exception 'publication failure not recorded: %', (select row_to_json(d) from pipeline.course_intake_dates d where intake_id = t1); end if;
  -- the projection refresh puts it back: the next check records it published
  perform search.refresh_course_enrichment_scoped_v1(array[v_course], true);
  v := security.intake_publication_check_v1();
  if (select publication_state from pipeline.course_intake_dates where intake_id = t1) <> 'published' then
    raise exception 'after refresh: % %', v, (select intake_options from search.course_documents where course_id = v_course); end if;
  raise notice 'PASS §6: admitted values compared with the Website API v2 source: published, or consumer publication failed until the source carries it';
end $$;

-- re-read on a reader change, relevant documents only, never twice --------------------------------------------------------------------------
do $$
declare v jsonb; v_src uuid; v_col uuid; n int;
begin
  select fact_source_id into v_src from pipeline.provider_policy_proposals where id = (select id from k where name = 'unsw');
  update pipeline.provider_fact_sources set evidence_id = (select evidence_id from catalogue.course_intakes where id = (select id from k where name = 't1')) where id = v_src;
  select id into v_col from pipeline.provider_fact_sources where url = 'https://www.harbour.edu.au/residential-college/key-dates';
  update pipeline.provider_fact_sources set evidence_id = (select evidence_id from catalogue.course_intakes where id = (select id from k where name = 't1')) where id = v_col;
  update pipeline.central_ai_queue set state = 'done' where state in ('queued', 'leased');
  v := public.svc_calendar_reread_next_v2(60, 'calendar-v2.1');
  if not exists (select 1 from jsonb_array_elements(v) x where (x->>'id')::uuid = v_src) then raise exception 'reader change: main calendar not leased: %', v; end if;
  -- college rejected: a residential college address is never read for intake dates
  if exists (select 1 from jsonb_array_elements(v) x where (x->>'id')::uuid = v_col)
     or (select reason from pipeline.calendar_reread_state where fact_source_id = v_col) not like 'not needed: the address is not a main teaching calendar' then
    raise exception 'college calendar read: %', (select row_to_json(s) from pipeline.calendar_reread_state s where fact_source_id = v_col); end if;
  perform public.svc_calendar_reread_record_v2((x->>'id')::uuid, null, false, 'fixture', null, 'calendar-v2.1') from jsonb_array_elements(v) x;
  v := public.svc_calendar_reread_next_v2(60, 'calendar-v2.1');
  if jsonb_array_length(v) <> 0 then raise exception 'read twice by the same reader: %', v; end if;
  v := public.svc_calendar_reread_next_v2(60, 'calendar-v2.2');
  if not exists (select 1 from jsonb_array_elements(v) x where (x->>'id')::uuid = v_src) or exists (select 1 from jsonb_array_elements(v) x where (x->>'id')::uuid = v_col) then
    raise exception 'next reader: %', v; end if;
  perform public.svc_calendar_reread_record_v2((x->>'id')::uuid, null, false, 'fixture', null, 'calendar-v2.1') from jsonb_array_elements(v) x;
  raise notice 'PASS R1 re-read: a reader change reads every needed main calendar again once; the college address is set aside as not needed';
end $$;

-- bounded refresh (R2): an equivalent edition held stops it; otherwise the oldest needed calendars within the credit budget; never twice ---
do $$
declare v jsonb; v_src uuid; v_off uuid; r_asked int; r_status text; r_spent numeric; r_again int; r_budget int; r_found text; r_old uuid; r_old_kept boolean;
begin
  select f.id into v_src from pipeline.provider_fact_sources f join pipeline.provider_policy_proposals p on p.fact_source_id = f.id where p.id = '24818cee-28f3-8368-8e3f-5454e23dda68';
  select id into v_off from pipeline.provider_fact_sources where url = 'https://www.harbour.edu.au/singapore/dates';
  update pipeline.provider_fact_sources set read_at = now() - interval '30 days', status = 'read' where provider_id = '08609bcf-387d-1316-2a52-9fbc0edff508' and kind = 'intake_calendar';
  update pipeline.calendar_reread_state set reader_version = 'calendar-v2.1', state = 'read_by_ai', reason = 'fixture' where provider_id = '08609bcf-387d-1316-2a52-9fbc0edff508';
  insert into pipeline.calendar_reread_state(fact_source_id, provider_id, state, reader_version) select id, provider_id, 'read_by_ai', 'calendar-v2.1' from pipeline.provider_fact_sources
   where provider_id = '08609bcf-387d-1316-2a52-9fbc0edff508' and kind = 'intake_calendar' on conflict do nothing;
  -- Harbour holds a 2027 edition: nothing is asked
  v := public.svc_calendar_refresh_v1('calendar-v2.1');
  if (v->>'asked')::int <> 0 then raise exception 'refresh asked although an equivalent edition is held: %', v; end if;
  -- without the 2027 editions (rolled back afterwards): the needed main calendars are asked, never the offshore one, within the budget
  begin
    update pipeline.provider_policy_proposals set status = 'superseded' where provider_id = '08609bcf-387d-1316-2a52-9fbc0edff508' and kind = 'intake_calendar' and status = 'approved'
       and exists (select 1 from security.calendar_proposal_dates_v1(id) d where d.kind = 'start' and d.year >= 2027);
    update pipeline.platform_toolset_settings set value = to_jsonb(3) where toolset_key = 'pipeline' and key = 'central.calendar_refresh_credit_budget';
    update pipeline.platform_toolset_settings set value = to_jsonb(5) where toolset_key = 'pipeline' and key = 'batch.calendar_refresh';
    v := public.svc_calendar_refresh_v1('calendar-v2.1');
    r_asked := (v->>'asked')::int; r_spent := (v->>'credits_counted')::numeric;
    r_found := (select string_agg(f.url, ',') from pipeline.calendar_refresh_requests q join pipeline.provider_fact_sources f on f.id = q.fact_source_id where f.status = 'found');
    if exists (select 1 from pipeline.calendar_refresh_requests where fact_source_id = v_off) then raise exception 'offshore calendar asked'; end if;
    -- the read happens (a new edition, 5 credits used): outcome, credits and the old edition recorded; budget spent; never asked twice
    select old_evidence_id into r_old from pipeline.calendar_refresh_requests limit 1;
    update pipeline.provider_fact_sources f set status = 'read', content_hash = 'new-edition', updated_at = now() + interval '1 second'
     where f.id in (select fact_source_id from pipeline.calendar_refresh_requests);
    insert into pipeline.firecrawl_calls(use_case, endpoint, url, credits_used, success) select 'provider_facts', 'scrape', url, 5, true from pipeline.calendar_refresh_requests;
    v := public.svc_calendar_refresh_v1('calendar-v2.1');
    select string_agg(status || ':' || coalesce(credits_used::text, '-') || ':' || coalesce(yield, '-'), ',') into r_status from pipeline.calendar_refresh_requests;
    r_old_kept := exists (select 1 from pipeline.evidence_artifacts where id = r_old);
    r_budget := (v->>'asked')::int;
    update pipeline.platform_toolset_settings set value = to_jsonb(400) where toolset_key = 'pipeline' and key = 'central.calendar_refresh_credit_budget';
    update pipeline.provider_fact_sources f set status = 'read', updated_at = now() - interval '1 second' where f.id in (select fact_source_id from pipeline.calendar_refresh_requests);
    v := public.svc_calendar_refresh_v1('calendar-v2.1');
    r_again := (select count(*) from pipeline.calendar_refresh_requests q group by q.url order by 1 desc limit 1);
    raise exception 'rollback' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  if r_asked <> 1 or r_spent <> 2 then raise exception 'budget 3 with 2 credits a request should ask once: asked %, counted %', r_asked, r_spent; end if;
  if r_status <> 'new_edition_stored:5:pending' or not r_old_kept then raise exception 'outcome: % (old kept %)', r_status, r_old_kept; end if;
  if r_budget <> 0 then raise exception 'asked beyond the budget after 5 credits were used'; end if;
  if r_again <> 1 then raise exception 'the same address asked twice'; end if;
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'central.calendar_refresh_credit_budget') <> to_jsonb(40) then raise exception 'budget setting not restored'; end if;
  raise notice 'PASS R2: an equivalent edition held asks nothing; otherwise one needed main calendar within the credit budget (offshore never), its old edition kept, credits from the Firecrawl log, never asked twice (% asked first)', r_found;
end $$;

-- process results: the recovery measurement and the screen view ------------------------------------------------------------------------------
do $$
declare v jsonb; n int;
begin
  v := security.process_results_recovery_record_v1();
  select summary into v from pipeline.process_results where id = (v->>'id')::bigint;
  if not exists (select 1 from jsonb_array_elements(v->'admitted') x where x->>'university' = 'Harbour University' and (x->>'year')::int = 2027 and x->>'precision' = 'day' and (x->>'published')::int >= 1)
     or not exists (select 1 from jsonb_array_elements(v->'classes') x where x->>'class' = 'stale_calendar_edition')
     or (v->'refresh'->>'budget')::numeric <> 40 then raise exception 'recovery measurement: %', left(v::text, 1500); end if;
  perform set_config('request.jwt.claim.sub', md5('admin')::uuid::text, true);
  v := public.admin_process_results_v1('recovery', '{}'::jsonb);
  if v->'classes' is null or v->'reader' is null then raise exception 'recovery view: %', left(v::text, 400); end if;
  if (select command from cron.job where jobname = 'intake-dates-apply') not like '%security.intake_publication_check_v1()%'
     or (select command from cron.job where jobname = 'process-results') not like '%process_results_recovery_record_v1()%' then raise exception 'job commands'; end if;
  if (select count(*) from cron.job where jobname in ('intake-dates-apply', 'process-results', 'calendar-reread')) <> 3 then raise exception 'jobs'; end if;
  raise notice 'PASS §10: recovery measurement recorded (admitted by university, year and precision with publication; classes; refresh; reader) and shown by view recovery; no new job';
end $$;
