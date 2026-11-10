\set ON_ERROR_STOP on
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
create or replace function pg_temp.cfg(k text, v text) returns void language sql as $$ insert into pipeline.platform_toolset_settings values ('pipeline', k, v::jsonb) on conflict (toolset_key, key) do update set value = excluded.value $$;
create or replace function pg_temp.plan(p uuid, c uuid default null) returns jsonb language sql as $$ select security.aer_read_now_plan_v1(p, c) $$;
create or replace function pg_temp.mut() returns text language sql as $$
  select (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.layer4_review_items r) || (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.field_enrich_items r) || (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.entry_matrix_runs r)
      || (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.entry_matrix_sources r) || (select md5(string_agg(r::text, '|' order by r.id)) from catalogue.provider_entry_matrix r) || (select md5(string_agg(r::text, '|' order by r.id)) from catalogue.course_entry_requirements r)
      || (select md5(string_agg(r::text, '|' order by r.key)) from pipeline.platform_toolset_settings r) || (select count(*) from pipeline.admin_control_events) || (select count(*) from pipeline.aer_read_supersessions) $$;

-- 1. the eligibility rules, once ------------------------------------------------------------------------------------------------------------------
do $$ begin
  perform pg_temp.ok((select count(*) from security.aer_course_population_v1('10000000-0000-0000-0000-000000000002')) = 4, 'population: one provider''s eligible courses (4 stored, bound pages)');
  perform pg_temp.ok((select count(*) from security.aer_course_population_v1(null)) = 16 and (select count(*) from security.aer_course_population_v1()) = 16, 'population: all providers is the same 16 (11 plus 5 already-read evidence cases) whichever form is called (a locked course, an unstored page, a title-matched page, a candidate page and an inactive course are left out)');
  perform pg_temp.ok(not exists (select 1 from (select * from security.aer_course_population_v1() except select * from security.aer_course_population_v1(null)) z), 'population: the no-argument form (the scheduled reader''s) returns exactly the rows of the new form');
end $$;

-- 2. packet facts: nothing filled in, nothing inferred ---------------------------------------------------------------------------------------------
do $$ declare m text; f jsonb; begin
  m := pg_temp.mut();
  f := security.aer_packet_facts_v1('40000000-0000-0000-0000-000000000001');
  perform pg_temp.ok((f->>'rows')::int = 4 and (f->>'complete_rows')::int = 1 and (f->>'flagged_rows')::int = 3, 'facts: the Nepal / IB matrix has 4 proposed rows, 1 with every fact stated and 3 flagged (the active row is not a candidate)');
  perform pg_temp.ok((f->'not_stated'->>'year')::int = 2 and (f->'not_stated'->>'scale')::int = 1 and (f->'not_stated'->>'country')::int = 1 and (f->'not_stated'->>'grade')::int = 1 and (f->'not_stated'->>'applicability')::int = 1 and (f->'not_stated'->>'source_page')::int = 1 and not f->'not_stated' ? 'qualification',
    'facts: year not stated on 2 rows, scale on 1, country on 1, grade on 1, applicability on 1, source page on 1, qualification on none');
  perform pg_temp.ok((select country from security.aer_packet_rows_v1('40000000-0000-0000-0000-000000000001') where row_id = '70000000-0000-0000-0000-000000000003') = 'not_stated' and (select country_code is null from catalogue.provider_entry_matrix where id = '70000000-0000-0000-0000-000000000003'),
    'facts: a row with no country stays "not stated" although the other rows of the page say Nepal; the row itself is not changed');
  perform pg_temp.ok((select year from security.aer_packet_rows_v1('40000000-0000-0000-0000-000000000001') where row_id = '70000000-0000-0000-0000-000000000003') = 'stated' and (select intake_year is null from catalogue.provider_entry_matrix where id = '70000000-0000-0000-0000-000000000003'),
    'facts: a printed edition counts as the year, and the capture date does not (the row 2 year is not stated, as_at is null)');
  perform pg_temp.ok((select scale from security.aer_packet_rows_v1('40000000-0000-0000-0000-000000000001') where row_id = '70000000-0000-0000-0000-000000000004') = 'not_applicable' and (select grade from security.aer_packet_rows_v1('40000000-0000-0000-0000-000000000001') where row_id = '70000000-0000-0000-0000-000000000004') = 'not_stated',
    'facts: a row with no grade has no scale to state (not applicable) and its missing grade is flagged');
  f := security.aer_packet_facts_v1('42000000-0000-0000-0000-000000000001');
  perform pg_temp.ok((f->>'rows')::int = 3 and (f->>'complete_rows')::int = 1 and (f->'not_stated'->>'scale')::int = 2 and (f->'not_recorded'->>'year')::int = 3 and not f->'not_stated' ? 'year',
    'facts: a course read has no intake-year field, so the year is "not recorded" on all 3 rows (said, not guessed); a grade or score without its scale is flagged on 2');
  perform pg_temp.ok((select country from security.aer_packet_rows_v1('42000000-0000-0000-0000-000000000001') where row_id = '80000000-0000-0000-0000-000000000001') = 'not_applicable' and (select country from security.aer_packet_rows_v1('42000000-0000-0000-0000-000000000001') where row_id = '80000000-0000-0000-0000-000000000002') = 'stated',
    'facts: a course row names a country only when it has one');
  perform pg_temp.ok(f->'section' ? 'Note' and f->'section'->>'Note' like '%never filled in%', 'facts: the reviewer section states the rule');
  perform pg_temp.ok(m = pg_temp.mut(), 'facts: read only (no row, item, setting or event changed)');
end $$;

-- 3. the waiting packets -------------------------------------------------------------------------------------------------------------------------------
do $$ begin
  perform pg_temp.ok((select count(*) from security.aer_pending_packets_v1(null, null)) = 5 and (select count(*) filter (where packet_state = 'reviewer_ready') from security.aer_pending_packets_v1(null, null)) = 2
                     and (select count(*) filter (where packet_state = 'technical_hold') from security.aer_pending_packets_v1(null, null)) = 2 and (select count(*) filter (where packet_state = 'needs_input') from security.aer_pending_packets_v1(null, null)) = 1,
    'packets: 5 waiting, 2 reviewer-ready, 2 technically held, 1 parked for input');
  perform pg_temp.ok((select parked_reason from security.aer_pending_packets_v1(null, '33000000-0000-0000-0000-000000000002')) like '%row limit%', 'packets: a parked read carries the lane''s exact reason');
end $$;

-- 4. the plan: every outcome ---------------------------------------------------------------------------------------------------------------------------
do $$ declare p jsonb; m text; begin
  m := pg_temp.mut();
  p := pg_temp.plan('10000000-0000-0000-0000-000000000002');
  perform pg_temp.ok(p->>'outcome' = 'queued' and jsonb_array_length(p->'actions') = 4 and (select bool_and(a->>'kind' = 'read_course') from jsonb_array_elements(p->'actions') a), 'plan: a provider with 4 stored course pages queues 4 first reads (the per-provider cap is 5)');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000003');
  perform pg_temp.ok(p->>'outcome' = 'source_unavailable' and p->>'reason' = 'identity_not_admitted', 'plan: course pages matched by title only are source unavailable, pending the Platform Admin decision, and not read');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000004');
  perform pg_temp.ok(p->>'outcome' = 'source_unavailable' and p->>'reason' = 'nothing_stored' and p->>'text' like '%scraper credits%', 'plan: nothing stored is source unavailable; no page search is started');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000005');
  perform pg_temp.ok(p->>'outcome' = 'queued' and jsonb_array_length(p->'actions') = 1 and p->'actions'->0->>'kind' = 'reread_source' and p->'actions'->0->>'source_id' = '50000000-0000-0000-0000-000000000002', 'plan: a source whose read failed technically is read again from its stored copy; a source held unparsed is left to its own guard');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000006');
  perform pg_temp.ok(p->>'outcome' = 'already_up_to_date' and p->>'reason' = 'sources_read', 'plan: every source read on its current copy is already up to date');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000007');
  perform pg_temp.ok(p->>'outcome' = 'queued' and jsonb_array_length(p->'actions') = 1 and p->'actions'->0->>'kind' = 'replay_item' and p->'actions'->0->>'item_id' = '41000000-0000-0000-0000-000000000001', 'plan: a held read the stored records can replace is replayed (no AI, no fetch); the one they cannot is not');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000008');
  perform pg_temp.ok(p->>'outcome' = 'human_review_required' and p->>'reason' = 'packet_ready' and p->>'text' like '%Nothing is published until a person decides%', 'plan: a complete reviewer packet is human review required, never published');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'outcome' = 'human_review_required' and (p->'packets'->>'reviewer_ready')::int = 1, 'plan: the university matrix packet waits for a person');
  p := pg_temp.plan('10000000-0000-0000-0000-00000000000a');
  perform pg_temp.ok(p->>'outcome' = 'no_eligible_work' and p->>'reason' = 'not_aer_eligible', 'plan: a provider outside entry-requirements reading has no eligible work');
  p := pg_temp.plan('10000000-0000-0000-0000-00000000000b');
  perform pg_temp.ok(p->>'outcome' = 'in_progress' and p->>'reason' = 'work_in_flight', 'plan: a queued course read is in progress');
  p := pg_temp.plan('10000000-0000-0000-0000-00000000000c');
  perform pg_temp.ok(p->>'outcome' = 'in_progress', 'plan: a queued matrix run is in progress');
  p := pg_temp.plan('99999999-9999-9999-9999-999999999999');
  perform pg_temp.ok(p->>'outcome' = 'no_eligible_work' and p->>'reason' = 'unknown_scope', 'plan: an unknown provider has no eligible work');
  -- switches and budgets
  perform pg_temp.cfg('fx.countries_off', '["NZ"]');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000009');
  perform pg_temp.ok(p->>'outcome' = 'switch_off' and p->>'reason' = 'country_off', 'plan: a country switched off is a switch-off outcome');
  perform pg_temp.cfg('fx.countries_off', '[]');
  perform pg_temp.cfg('aer.schedule_daily_max', '0');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000002');
  perform pg_temp.ok(p->>'outcome' = 'budget_reached' and p->>'reason' = 'daily_cap' and jsonb_array_length(p->'actions') = 0, 'plan: the daily allowance used is budget reached, nothing queued');
  perform pg_temp.cfg('aer.schedule_daily_max', '200');
  perform pg_temp.cfg('aer.schedule_layer4_max', '1');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000002');
  perform pg_temp.ok(p->>'outcome' = 'human_review_required' and p->>'reason' = 'layer4_full', 'plan: Layer 4 full (waiting decisions at the limit, parked ones not counted) holds new reads for people');
  perform pg_temp.cfg('aer.schedule_layer4_max', '600');
  insert into pipeline.platform_toolset_settings values ('fx', 'ai_refusal_enrich_fields', '"AI reading is stopped for the test"');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000002');
  perform pg_temp.ok(p->>'outcome' = 'budget_reached' and p->>'reason' = 'ai_stopped', 'plan: an AI limit stops the course reads');
  delete from pipeline.platform_toolset_settings where toolset_key = 'fx' and key = 'ai_refusal_enrich_fields';
  insert into pipeline.layer3_openrouter_observations(kind, remaining_usd, observed_at) values ('credits', 5.01, now() + interval '1 second');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000002');
  perform pg_temp.ok(p->>'outcome' = 'budget_reached' and p->>'reason' = 'credit_floor', 'plan: reads that would take the balance under its floor are budget reached');
  delete from pipeline.layer3_openrouter_observations where observed_at > now();
  insert into pipeline.platform_toolset_settings values ('fx', 'matrix_off', 'true');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000005');
  perform pg_temp.ok(p->>'outcome' = 'switch_off' and p->>'reason' = 'matrix_reader_off', 'plan: the matrix reader off for the provider is a switch-off outcome');
  delete from pipeline.platform_toolset_settings where toolset_key = 'fx' and key = 'matrix_off';
  insert into pipeline.platform_toolset_settings values ('fx', 'ai_refusal_entry_matrix', '"entry matrices stopped for the test"');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000005');
  perform pg_temp.ok(p->>'outcome' = 'budget_reached' and p->>'reason' = 'ai_stopped', 'plan: an AI limit on entry matrices stops the read-again');
  delete from pipeline.platform_toolset_settings where toolset_key = 'fx' and key = 'ai_refusal_entry_matrix';
  perform pg_temp.cfg('aer.replay_on', '0');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000007');
  perform pg_temp.ok(p->>'outcome' = 'switch_off' and p->>'reason' = 'replay_off', 'plan: the replay switch off is a switch-off outcome for held reads');
  perform pg_temp.cfg('aer.replay_on', '1'); perform pg_temp.cfg('aer.replay_daily_max', '0');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000007');
  perform pg_temp.ok(p->>'outcome' = 'budget_reached' and p->>'reason' = 'replay_daily_cap', 'plan: the daily replay allowance used is budget reached');
  perform pg_temp.cfg('aer.replay_daily_max', '100');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000002');
  perform pg_temp.ok(p->>'outcome' = 'queued', 'plan: with every setting restored the provider queues again');
end $$;

-- 5. the plan for one course ---------------------------------------------------------------------------------------------------------------------
do $$ declare p jsonb; begin
  p := pg_temp.plan(null, '30000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'outcome' = 'queued' and p->'actions'->0->>'kind' = 'read_course' and p->>'url' is not null, 'course: a course with a stored bound page queues one read from the stored copy');
  p := pg_temp.plan(null, '3c000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'outcome' = 'in_progress' and p->>'reason' = 'read_in_progress', 'course: a read already waiting is in progress');
  p := pg_temp.plan(null, '33000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'outcome' = 'human_review_required' and p->>'reason' = 'packet_ready' and p->>'item_id' = '42000000-0000-0000-0000-000000000001', 'course: a complete reviewer packet is human review required and names the item');
  p := pg_temp.plan(null, '33000000-0000-0000-0000-000000000002');
  perform pg_temp.ok(p->>'outcome' = 'human_review_required' and p->>'reason' = 'needs_input' and p->>'text' like '%row limit%', 'course: a parked read needs input and says why');
  p := pg_temp.plan(null, '32000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'outcome' = 'queued' and p->'actions'->0->>'kind' = 'replay_item', 'course: a held read is replayed from stored records');
  p := pg_temp.plan(null, '32000000-0000-0000-0000-000000000002');
  perform pg_temp.ok(p->>'outcome' = 'switch_off' and p->>'reason' = 'e13_recover_off', 'course: a held read that needs the E13 recovery switch reports the switch off (it is not changed here)');
  p := pg_temp.plan(null, '36000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'outcome' = 'source_unavailable' and p->>'reason' = 'no_course_page', 'course: no bound page is source unavailable');
  p := pg_temp.plan(null, '37000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'outcome' = 'source_unavailable' and p->>'reason' = 'no_stored_copy', 'course: a page with no stored copy is source unavailable (fetching it would use scraper budget)');
  p := pg_temp.plan(null, '38000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'outcome' = 'human_review_required' and p->>'reason' = 'manual_lock', 'course: a manual lock is a person''s decision and is respected');
  p := pg_temp.plan(null, '39000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'outcome' = 'source_unavailable' and p->>'reason' = 'identity_not_admitted', 'course: a title-matched page is not read');
  p := pg_temp.plan(null, '3a000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'outcome' = 'source_unavailable' and p->>'reason' = 'course_page_not_bound', 'course: a candidate page that is not bound is source unavailable');
  p := pg_temp.plan(null, '3b000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'outcome' = 'no_eligible_work' and p->>'reason' = 'course_not_active', 'course: an inactive course has no eligible work');
  p := pg_temp.plan(null, '35000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'outcome' = 'already_up_to_date' and p->>'reason' = 'same_stored_copy', 'course: a course read on the current stored copy is already up to date and costs nothing');
  perform pg_temp.cfg('entry.course_read_countries', '["AU"]');
  p := pg_temp.plan(null, '34000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'outcome' = 'switch_off' and p->>'reason' = 'course_read_country_off', 'course: a country not in the course-read setting is a switch-off outcome');
  perform pg_temp.cfg('entry.course_read_countries', '["AU", "NZ"]');
end $$;

-- 5b. evidence-backed absence (Operating Model v1.7): each kind of "nothing" is named from stored state only, unchanged evidence is not read again, a refusal consumes nothing ------------
do $$ declare p jsonb; rr jsonb; m text; k text; begin
  k := 'security.aer_read_now_class_v1';
  -- 1. no official source found
  p := pg_temp.plan('10000000-0000-0000-0000-000000000004');
  perform pg_temp.ok(security.aer_read_now_class_v1(p->>'outcome', p->>'reason') = 'no_source_on_record', 'evidence: nothing stored is "no source on record" (not a finding that discovery ran)');
  p := pg_temp.plan(null, '36000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(security.aer_read_now_class_v1(p->>'outcome', p->>'reason') = 'no_source_on_record', 'evidence: a course with no bound page is "no source on record" (not a finding that discovery ran)');
  -- 2. source found but not read
  p := pg_temp.plan('10000000-0000-0000-0000-000000000003');
  perform pg_temp.ok(security.aer_read_now_class_v1(p->>'outcome', p->>'reason') = 'source_found_not_read', 'evidence: course pages matched by title only are "source found, not read"');
  p := pg_temp.plan(null, '37000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(security.aer_read_now_class_v1(p->>'outcome', p->>'reason') = 'source_found_not_read' and p->'url' is not null, 'evidence: a page with no stored copy is "source found, not read" and names the page');
  p := pg_temp.plan('10000000-0000-0000-0000-00000000000f');
  perform pg_temp.ok(p->>'outcome' = 'source_unavailable' and p->>'reason' = 'robots_disallowed' and p->>'text' like '%robots.txt%' and p->>'text' like '%pp.edu.au/entry%' and security.aer_read_now_class_v1(p->>'outcome', p->>'reason') = 'source_found_not_read',
    'evidence: a source the website disallows is "source found, not read", with the source named');
  -- 3. read, nothing kept (tried, not found): only where a stored result says so
  p := pg_temp.plan('10000000-0000-0000-0000-00000000000d');
  perform pg_temp.ok(p->>'outcome' = 'already_up_to_date' and p->>'reason' = 'tried_not_found' and p->>'text' like '%no entry-requirement row was kept%' and p->>'text' like '%pn.edu.au/entry%' and (p->'source_counts'->>'read_nothing_kept')::int = 1,
    'evidence: a source read with no row kept is "tried, not found", with the source named and nothing spent');
  p := pg_temp.plan(null, '3d000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'outcome' = 'already_up_to_date' and p->>'reason' = 'tried_not_found' and p->>'text' like '%the page does not state it%' and jsonb_array_length(p->'actions') = 0, 'evidence: a course read whose stored result says the page does not state it is "tried, not found" and is not read again');
  p := pg_temp.plan(null, '3d000000-0000-0000-0000-000000000002');
  perform pg_temp.ok(p->>'outcome' = 'already_up_to_date' and p->>'reason' = 'tried_not_found', 'evidence: another stored copy with the same content hash is unchanged evidence: not read again');
  p := pg_temp.plan(null, '3d000000-0000-0000-0000-000000000004');
  perform pg_temp.ok(p->>'outcome' = 'already_up_to_date' and p->>'reason' = 'same_stored_copy' and p->>'text' like '%held_partial%' and security.aer_read_now_class_v1(p->>'outcome', p->>'reason') is null,
    'evidence: a read that kept nothing for another reason (over the row limit) is not described as searched and not found; its recorded reason is shown as recorded');
  p := pg_temp.plan(null, '3d000000-0000-0000-0000-000000000005');
  perform pg_temp.ok(p->>'outcome' = 'queued' and p->>'reason' = 'course_read', 'evidence: a page whose content changed since the last read is read again');
  -- 4. technical failure, retryable
  p := pg_temp.plan('10000000-0000-0000-0000-00000000000e');
  perform pg_temp.ok(p->>'outcome' = 'source_unavailable' and p->>'reason' = 'source_fetch_failed' and p->>'text' like '%blocked_pdf%' and p->>'text' like '%po.edu.au/entry.pdf%' and security.aer_read_now_class_v1(p->>'outcome', p->>'reason') = 'technical_failure',
    'evidence: a source that could not be fetched is a technical failure, with the source and the recorded error');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000005');
  perform pg_temp.ok(p->>'outcome' = 'queued' and p->>'reason' = 'technical_failure_retry' and p->'actions'->0->>'kind' = 'reread_source', 'evidence: a source whose read failed technically is read again from its stored copy, as a technical failure');
  p := pg_temp.plan(null, '3d000000-0000-0000-0000-000000000003');
  perform pg_temp.ok(p->>'outcome' = 'queued' and p->>'reason' = 'technical_failure_retry' and p->>'text' like '%timeout%', 'evidence: a course read that failed is read again, naming the recorded failure');
  -- 5. a budget refusal creates no job or item and uses none of a reader's attempts; it is a budget hold, not a source finding
  insert into pipeline.platform_toolset_settings values ('fx', 'ai_refusal_enrich_fields', '"AI reading is stopped for the test"');
  m := (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.field_enrich_items r) || (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.entry_matrix_runs r) || (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.entry_matrix_sources r);
  rr := security.aer_read_now_v1(null, '3d000000-0000-0000-0000-000000000003', 'budget refusal', '00000000-0000-0000-0000-0000000000aa');
  perform pg_temp.ok(rr->>'outcome' = 'budget_reached' and rr->>'class' = 'budget_hold'
    and m = (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.field_enrich_items r) || (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.entry_matrix_runs r) || (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.entry_matrix_sources r),
    'evidence: a budget refusal is a budget hold; it creates no read item, run or source change and changes no attempt count');
  delete from pipeline.platform_toolset_settings where toolset_key = 'fx' and key = 'ai_refusal_enrich_fields';
  -- 6. the source examined is shown as recorded, and a missing record is said to be missing
  p := security.aer_read_now_source_v1(null, '3d000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'kind' = 'course_page' and (p->>'recorded')::boolean and p->>'url' like 'https://pq.edu.au/%' and p->>'content_hash' = 'h1' and p->'last_read'->>'recorded_reason' = 'the page does not state it', 'source: the bound page, its stored copy hash and the last read result as recorded');
  p := security.aer_read_now_source_v1(null, '36000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(p->>'kind' = 'course_page' and not (p->>'recorded')::boolean and p->'url' is null, 'source: a course with no page says no page is recorded');
  p := security.aer_read_now_source_v1('10000000-0000-0000-0000-00000000000e', null);
  perform pg_temp.ok(p->>'kind' = 'matrix_sources' and (p->>'count')::int = 1 and p->'sources'->0->>'status' = 'failed' and p->'sources'->0->>'error' = 'blocked_pdf', 'source: each entry source with its status and recorded error');
  p := security.aer_read_now_source_v1('10000000-0000-0000-0000-000000000004', null);
  perform pg_temp.ok(p->>'kind' = 'matrix_sources' and not (p->>'recorded')::boolean and p->>'count' = '0', 'source: a provider with no entry source says none is recorded');
  p := security.aer_read_now_status_v1('10000000-0000-0000-0000-00000000000d', null);
  perform pg_temp.ok(p->'outcome'->>'class' = 'tried_not_found' and p->'source'->'sources'->0->>'url' = 'https://pn.edu.au/entry' and p->'outcome'->>'next_action' is not null and (p->'outcome')::text !~* 'published', 'status: the outcome carries its kind, the source examined and the next action, and never says published');
end $$;

-- 5c. QA round: a reader hold is not an absence; no re-queue of a failed read against an unchanged page; on-demand rereads and replays count against the shared allowance ------
do $$ declare p jsonb; rr jsonb; n int; before_runs text; begin
  -- reader holds (held_unparsed, held_incomplete): a hold for a person, never "tried, not found", never green, never queued
  p := pg_temp.plan('10000000-0000-0000-0000-000000000011');
  perform pg_temp.ok(p->>'outcome' = 'human_review_required' and p->>'reason' = 'reader_held' and security.aer_read_now_class_v1(p->>'outcome', p->>'reason') = 'human_review' and jsonb_array_length(p->'actions') = 0
    and (p->'source_counts'->>'held_by_the_reader')::int = 2 and (p->'source_counts'->>'read_nothing_kept')::int = 0 and p->>'text' like '%could not read the page reliably%' and p->>'text' not like '%no entry-requirement row was kept%',
    'held: sources the reader held (unparsed, incomplete) are a hold for a person, not an absence, and are not queued');
  p := pg_temp.plan('10000000-0000-0000-0000-000000000005');
  perform pg_temp.ok(p->>'reason' <> 'tried_not_found', 'held: a held_unparsed run never reads as tried, not found');
  -- a technically failed read is asked once for this page (same content hash); the click then no longer re-queues it
  p := pg_temp.plan('10000000-0000-0000-0000-000000000012');
  perform pg_temp.ok(p->>'outcome' = 'queued' and p->>'reason' = 'technical_failure_retry' and p->'actions'->0->>'content_hash' = 'h1', 'retry: a failed read not yet asked from here is queued once, carrying its content hash');
  insert into pipeline.admin_control_events(area, action, target, detail) values ('aer_read_now', 'provider', '10000000-0000-0000-0000-000000000012',
    jsonb_build_object('outcome', 'queued', 'started', jsonb_build_array(jsonb_build_object('kind', 'reread_source', 'source_id', '50000000-0000-0000-0000-00000000000b', 'content_hash', 'h1')), 'rereads', 1));
  p := pg_temp.plan('10000000-0000-0000-0000-000000000012');
  perform pg_temp.ok(p->>'outcome' = 'no_eligible_work' and p->>'reason' = 'technical_failure_retried' and jsonb_array_length(p->'actions') = 0 and security.aer_read_now_class_v1(p->>'outcome', p->>'reason') = 'technical_failure',
    'retry: asked once already for the same page, a failed read is not queued again (and attempts are not reset again)');
  update pipeline.admin_control_events set detail = jsonb_set(detail, '{started,0,content_hash}', '"h0"') where target = '10000000-0000-0000-0000-000000000012';
  p := pg_temp.plan('10000000-0000-0000-0000-000000000012');
  perform pg_temp.ok(p->>'outcome' = 'queued', 'retry: a request made for an earlier version of the page does not block the page as it is now');
  update pipeline.admin_control_events set detail = jsonb_set(detail, '{started,0,content_hash}', '"h1"'), created_at = now() - interval '31 days' where target = '10000000-0000-0000-0000-000000000012';
  p := pg_temp.plan('10000000-0000-0000-0000-000000000012');
  perform pg_temp.ok(p->>'outcome' = 'queued', 'retry: after the retry interval (aer.schedule_retry_days) it can be asked again');
  delete from pipeline.admin_control_events where target = '10000000-0000-0000-0000-000000000012';
  -- the same for a failed course read
  insert into pipeline.admin_control_events(area, action, target, detail) values ('aer_read_now', 'course', '3d000000-0000-0000-0000-000000000003',
    jsonb_build_object('outcome', 'queued', 'started', jsonb_build_array(jsonb_build_object('kind', 'read_course', 'course_id', '3d000000-0000-0000-0000-000000000003', 'content_hash', 'h1')), 'course_reads', 1));
  p := pg_temp.plan(null, '3d000000-0000-0000-0000-000000000003');
  perform pg_temp.ok(p->>'outcome' = 'no_eligible_work' and p->>'reason' = 'technical_failure_retried' and p->>'text' like '%timeout%' and p->>'text' like '%already asked again%', 'retry: a failed course read already asked again for the same stored copy is not queued again');
  insert into pipeline.platform_toolset_settings values ('fx', 'ai_refusal_enrich_fields', '"AI reading is stopped for the test"');
  p := pg_temp.plan(null, '3d000000-0000-0000-0000-000000000003');
  perform pg_temp.ok(p->>'reason' = 'technical_failure_retried', 'retry: the unchanged-page rule is stated before the budget (the read would not start whatever the budget)');
  delete from pipeline.platform_toolset_settings where toolset_key = 'fx' and key = 'ai_refusal_enrich_fields';
  delete from pipeline.admin_control_events where target = '3d000000-0000-0000-0000-000000000003';
  -- the shared daily allowance counts on-demand course reads, source reads again and replays
  perform pg_temp.cfg('aer.schedule_daily_max', '3');
  insert into pipeline.admin_control_events(area, action, target, detail) values ('aer_read_now', 'provider', 'x', jsonb_build_object('outcome', 'queued', 'course_reads', 0, 'rereads', 2, 'replays', 1, 'started', '[]'::jsonb));
  p := pg_temp.plan('10000000-0000-0000-0000-000000000002');
  perform pg_temp.ok(p->>'outcome' = 'budget_reached' and p->>'reason' = 'daily_cap', 'cap: 2 source reads again and 1 replay asked today use up a daily allowance of 3 for first reads');
  perform pg_temp.cfg('aer.schedule_daily_max', '200');
  delete from pipeline.admin_control_events where target = 'x';
end $$;

-- 6. the action: governed, shared with the scheduled reader's allowance, idempotent -------------------------------------------------------------------------
do $$ declare r jsonb; n int; ev int; begin
  r := security.aer_read_now_v1('10000000-0000-0000-0000-000000000002', null, 'test run', '00000000-0000-0000-0000-0000000000aa');
  perform pg_temp.ok(r->>'outcome' = 'queued' and jsonb_array_length(r->'started') = 4 and (select count(*) from pipeline.field_enrich_items where provider_id = '10000000-0000-0000-0000-000000000002' and state = 'queued') = 4, 'run: 4 first reads are queued through the scheduled reader''s own function');
  perform pg_temp.ok((select detail->>'outcome' from pipeline.admin_control_events where area = 'aer_read_now' order by id desc limit 1) = 'queued' and (select (detail->>'course_reads')::int from pipeline.admin_control_events where area = 'aer_read_now' order by id desc limit 1) = 4
                     and (select actor from pipeline.admin_control_events where area = 'aer_read_now' order by id desc limit 1) = '00000000-0000-0000-0000-0000000000aa', 'run: one event records the request, its outcome, its reads and who asked');
  n := (select count(*) from pipeline.field_enrich_items); ev := (select count(*) from pipeline.admin_control_events);
  r := security.aer_read_now_v1('10000000-0000-0000-0000-000000000002', null, 'second click', '00000000-0000-0000-0000-0000000000aa');
  perform pg_temp.ok(r->>'outcome' = 'in_progress' and jsonb_array_length(r->'started') = 0 and (select count(*) from pipeline.field_enrich_items) = n, 'run: a second click while the reads are queued starts nothing (idempotent)');
  perform pg_temp.ok((select count(*) from pipeline.admin_control_events) = ev + 1, 'run: the second click is recorded as a request that started nothing');
  perform pg_temp.cfg('aer.schedule_daily_max', '4');
  r := security.aer_read_now_v1('10000000-0000-0000-0000-000000000009', null, 'cap test', '00000000-0000-0000-0000-0000000000aa');
  perform pg_temp.ok(r->>'outcome' = 'budget_reached' and r->>'reason' = 'daily_cap', 'run: on-demand reads count against the daily allowance (4 already asked today against a cap of 4)');
  perform pg_temp.cfg('aer.schedule_daily_max', '200');
  r := security.aer_read_now_v1('10000000-0000-0000-0000-000000000005', null, null, '00000000-0000-0000-0000-0000000000aa');
  perform pg_temp.ok(r->>'outcome' = 'queued' and (select count(*) from pipeline.entry_matrix_runs where source_id = '50000000-0000-0000-0000-000000000002' and state = 'queued') = 1 and (select status from pipeline.entry_matrix_sources where id = '50000000-0000-0000-0000-000000000002') = 'found', 'run: a failed source is read again through the workspace function');
  perform pg_temp.ok((select (detail->>'rereads')::int from pipeline.admin_control_events where area = 'aer_read_now' order by id desc limit 1) = 1 and (select detail->'started'->0 ? 'content_hash' from pipeline.admin_control_events where area = 'aer_read_now' order by id desc limit 1),
    'cap: the event records the source reads again asked and their content hash (so an unchanged page is not asked again)');
  r := security.aer_read_now_v1('10000000-0000-0000-0000-000000000005', null, null, '00000000-0000-0000-0000-0000000000aa');
  perform pg_temp.ok(r->>'outcome' = 'in_progress' and (select count(*) from pipeline.entry_matrix_runs where source_id = '50000000-0000-0000-0000-000000000002' and state = 'queued') = 1, 'run: asking again does not queue a second read of the same source');
  r := security.aer_read_now_v1('10000000-0000-0000-0000-000000000007', null, null, '00000000-0000-0000-0000-0000000000aa');
  perform pg_temp.ok(r->>'outcome' = 'queued' and (select status from pipeline.layer4_review_items where id = '41000000-0000-0000-0000-000000000001') = 'superseded'
                     and (select count(*) from pipeline.aer_read_supersessions where reason like 'Replay of the stored read%') = 1 and (select count(*) from pipeline.layer4_review_items where entity_id = '32000000-0000-0000-0000-000000000001' and status = 'pending') = 1,
    'run: a held read is replaced by a new waiting item through the replay (counted as a replay); it is not approved');
  perform pg_temp.ok((select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) = 0 and (select count(*) from catalogue.provider_entry_matrix where status = 'active') = 1 and (select count(*) from catalogue.course_entry_requirements where status = 'active') = 0,
    'run: nothing was approved, rejected or made active by any click (F-AER.04)');
  perform pg_temp.ok((select count(*) from pipeline.aer_schedule_runs) = 0, 'run: the scheduled reader''s own run record is not written by a click');
  -- a refusal inside the reader leaves a truthful record
  alter function security.course_entry_read_enqueue_v1(uuid, uuid, text) rename to course_entry_read_enqueue_v1_x;
  create function security.course_entry_read_enqueue_v1(uuid, uuid, text) returns uuid language plpgsql as $f$ begin raise exception 'the reader refused'; end $f$;
  r := security.aer_read_now_v1('10000000-0000-0000-0000-000000000009', null, null, '00000000-0000-0000-0000-0000000000aa');
  perform pg_temp.ok(r->>'outcome' = 'no_eligible_work' and r->>'reason' = 'refused' and r->>'text' like '%the reader refused%' and (select count(*) from pipeline.field_enrich_items where provider_id = '10000000-0000-0000-0000-000000000009') = 0, 'run: when the reader refuses, nothing is started and the outcome says so');
  drop function security.course_entry_read_enqueue_v1(uuid, uuid, text);
  alter function security.course_entry_read_enqueue_v1_x(uuid, uuid, text) rename to course_entry_read_enqueue_v1;
  r := security.aer_read_now_v1(null, '34000000-0000-0000-0000-000000000001', 'one course', '00000000-0000-0000-0000-0000000000aa');
  perform pg_temp.ok(r->>'outcome' = 'queued' and (select count(*) from pipeline.field_enrich_items where course_id = '34000000-0000-0000-0000-000000000001' and state = 'queued') = 1 and (select action from pipeline.admin_control_events where area = 'aer_read_now' order by id desc limit 1) = 'course', 'run: one course is queued and recorded as a course request');
end $$;

-- 7. the public wrapper: permission, switch of the outcome, errors --------------------------------------------------------------------------------------
do $$ declare r jsonb; ev int; ok boolean; begin
  perform set_config('fx.uid', '', false); perform set_config('fx.rank', '0', false);
  ok := false; begin perform public.admin_aer_read_now('{"provider_id": "10000000-0000-0000-0000-000000000006"}'); exception when sqlstate '42501' then ok := true; end;
  perform pg_temp.ok(ok, 'wrapper: no signed-in user is refused');
  perform set_config('fx.uid', '00000000-0000-0000-0000-0000000000bb', false); perform set_config('fx.rank', '3', false);
  r := public.admin_aer_read_now('{"provider_id": "10000000-0000-0000-0000-000000000001"}');
  perform pg_temp.ok((r->>'known')::boolean and not (r->>'can_run')::boolean and jsonb_array_length(r->'stages') = 6 and r->'outcome'->>'outcome' = 'human_review_required', 'wrapper: any assigned role reads the status (6 stages and the outcome a click would have); it cannot run');
  ev := (select count(*) from pipeline.admin_control_events);
  r := public.admin_aer_read_now('{"action": "run", "provider_id": "10000000-0000-0000-0000-00000000000b"}');
  perform pg_temp.ok(r->>'outcome' = 'permission_denied' and not (r->>'can_run')::boolean and (select count(*) from pipeline.admin_control_events) = ev, 'wrapper: a role below Platform Admin is told permission denied and nothing is recorded or started');
  perform set_config('fx.rank', '6', false);
  r := public.admin_aer_read_now('{"action": "run", "provider_id": "10000000-0000-0000-0000-000000000006", "note": "check"}');
  perform pg_temp.ok(r->>'outcome' = 'already_up_to_date' and (r->>'can_run')::boolean and (select detail->>'note' from pipeline.admin_control_events where area = 'aer_read_now' order by id desc limit 1) = 'check', 'wrapper: a Platform Admin runs it; an up-to-date provider says so and records the note');
  ok := false; begin perform public.admin_aer_read_now('{"action": "drop", "provider_id": "10000000-0000-0000-0000-000000000006"}'); exception when sqlstate '22023' then ok := true; end;
  perform pg_temp.ok(ok, 'wrapper: an unknown action is refused');
  ok := false; begin perform public.admin_aer_read_now('{}'); exception when sqlstate '22023' then ok := true; end;
  perform pg_temp.ok(ok, 'wrapper: a provider or a course is required');
end $$;

-- 8. the stage timeline: separate, truthful stages; never published for a packet awaiting a person ---------------------------------------------------------
do $$ declare s jsonb; st jsonb; m text; begin
  m := pg_temp.mut();
  s := security.aer_read_now_status_v1('10000000-0000-0000-0000-000000000001', null);
  perform pg_temp.ok((select string_agg(x->>'key', ',' order by o) from jsonb_array_elements(s->'stages') with ordinality t(x, o)) = 'source_found,parsed,packet,human,active,consumer', 'stages: the six stages in order (source found, AI parsed candidates, complete reviewer packet, awaiting a person, approved and active, consumer visible)');
  perform pg_temp.ok((select x->>'state' from jsonb_array_elements(s->'stages') x where x->>'key' = 'human') = 'waiting' and (select (x->>'n')::int from jsonb_array_elements(s->'stages') x where x->>'key' = 'human') = 1, 'stages: one packet is awaiting a person');
  perform pg_temp.ok(not exists (select 1 from jsonb_array_elements(s->'stages') x where x->>'key' in ('parsed', 'packet', 'human') and x->>'detail' ilike '%published%'), 'stages: no stage before approval says published');
  perform pg_temp.ok((select (x->>'n')::int from jsonb_array_elements(s->'stages') x where x->>'key' = 'parsed') = 4 and (select (x->>'n')::int from jsonb_array_elements(s->'stages') x where x->>'key' = 'active') = 1, 'stages: 4 AI-parsed candidate rows are counted apart from the 1 approved and active row');
  perform pg_temp.ok((select x->>'state' from jsonb_array_elements(s->'stages') x where x->>'key' = 'consumer') = 'unknown' and (select x->'n' from jsonb_array_elements(s->'stages') x where x->>'key' = 'consumer') = 'null'::jsonb, 'stages: consumer visibility is not measured here and is never shown as 0');
  perform pg_temp.ok((s->'facts'->>'rows_in_reviewer_ready_packets')::int = 4 and (s->'facts'->>'rows_every_fact_stated')::int = 1 and (s->'facts'->>'rows_with_a_fact_not_stated')::int = 3, 'stages: the facts check counts 4 rows in the complete packet, 1 with every fact stated and 3 flagged');
  perform pg_temp.ok(s->>'next_scheduled_read' is not null, 'stages: the next scheduled read is named');
  s := security.aer_read_now_status_v1('10000000-0000-0000-0000-000000000002', null);
  perform pg_temp.ok((s->'last_request'->>'outcome') = 'in_progress' and s->'last_request'->>'at' is not null and s->'last_request'->>'by' = '00000000-0000-0000-0000-0000000000aa' and (select x->>'state' from jsonb_array_elements(s->'stages') x where x->>'key' = 'source_found') = 'done', 'stages: the last request and its outcome are shown from the server, so closing the browser loses nothing');
  s := security.aer_read_now_status_v1(null, '33000000-0000-0000-0000-000000000001');
  perform pg_temp.ok(s->>'scope' = 'course' and (select (x->>'n')::int from jsonb_array_elements(s->'stages') x where x->>'key' = 'packet') = 1 and (s->'facts'->>'rows_with_a_fact_not_stated')::int = 2, 'stages: a course shows its own packet and its 2 flagged rows');
  perform pg_temp.ok(m = pg_temp.mut(), 'stages: read only');
end $$;

-- 9. the reviewer detail and Data Delivery -------------------------------------------------------------------------------------------------------------
do $$ declare d jsonb; a jsonb; b jsonb; rv jsonb; rec jsonb; begin
  d := security.layer4_aer_review_detail_v1('42000000-0000-0000-0000-000000000001');
  perform pg_temp.ok((select x->>'key' from jsonb_array_elements(d->'sections') with ordinality t(x, o) where o = 4) = 'facts' and (select x->'body'->>'Rows' from jsonb_array_elements(d->'sections') x where x->>'key' = 'facts') = '3'
                     and (select x->'body'->>'Rows with a fact not stated' from jsonb_array_elements(d->'sections') x where x->>'key' = 'facts') = '2', 'detail: the reviewer card gains a Facts section before the proposed rows; the other sections are unchanged');
  perform pg_temp.ok(jsonb_array_length(d->'sections') = 6, 'detail: the card has the 5 sections it had and the new one');
  -- Data Delivery: every old key unchanged, one new key
  a := security.data_delivery_aer_v1(); b := (select x.a from pipeline.fx_dd_before x);
  perform pg_temp.ok(not exists (select 1 from jsonb_object_keys(b) k where not a ? k), 'Data Delivery: every key the aer stream had is still there');
  perform pg_temp.ok(a ? 'reviewer' and (a->'reviewer'->>'known')::boolean, 'Data Delivery: the new key reviewer is measured');
  rv := a->'reviewer';
  perform pg_temp.ok((rv->>'pending')::int = 5 and (rv->>'reviewer_ready')::int = 3 and (rv->>'technical_hold')::int = 1 and (rv->>'needs_input')::int = 1 and (rv->>'not_checked')::int = 0, 'Data Delivery: reviewer-ready packets (3, one of them the replay''s) are counted apart from held (1) and parked (1) ones');
  perform pg_temp.ok((rv->'active_rows'->>'matrix')::int = 1 and (rv->'active_rows'->>'course')::int = 0 and (rv->'by_kind'->'entry_matrix_first_run'->>'reviewer_ready')::int = 1, 'Data Delivery: active approved rows are a separate figure from reviewer-ready packets');
  perform pg_temp.ok((rv->'ready_rows'->>'rows')::int = 7 and (rv->'ready_rows'->>'every_fact_stated')::int = 2 and (rv->'ready_rows'->>'with_a_fact_not_stated')::int = 5 and (rv->'ready_rows'->'not_stated'->>'year')::int = 2, 'Data Delivery: the facts flagged in the reviewer-ready rows are counted (7 rows, 2 with every fact stated)');
  perform pg_temp.ok((rv->'decided'->>'approved')::int = 0 and (rv->'on_demand'->>'requests_24h')::int >= 5 and (rv->'on_demand'->>'queued_24h')::int >= 3, 'Data Delivery: decisions to date and the on-demand requests of the last day');
  -- the recovery display defect
  d := security.data_delivery_v1();
  rec := (select s->'recovery' from jsonb_array_elements(d->'streams') s where s->>'stream' = 'aer');
  perform pg_temp.ok(rec->>'state' = 'healthy' and rec->>'text' like '%Switched off, so these routes do not run: aer.e13_recover_on' and (select s->'recovery'->'switches_off' from jsonb_array_elements(d->'streams') s where s->>'stream' = 'aer') = '["aer.e13_recover_on"]'::jsonb,
    'Data Delivery: with the E13 pilot off on purpose and the replay and stored-link switches on, the aer recovery is no longer off; the switch that is off is named');
  perform pg_temp.ok((select s->'recovery'->>'state' from jsonb_array_elements(d->'streams') s where s->>'stream' = 'alloff') = 'off', 'Data Delivery: a stream whose every switch is off still reads off');
  perform pg_temp.ok((select s->'recovery'->>'state' from jsonb_array_elements(d->'streams') s where s->>'stream' = 'nosw') <> 'off' and (select s->'recovery'->'switches_off' from jsonb_array_elements(d->'streams') s where s->>'stream' = 'nosw') = '[]'::jsonb, 'Data Delivery: a lane whose switches are not set is not off (as before)');
  perform pg_temp.ok((select s->'aer_sources' ? 'reviewer' from jsonb_array_elements(d->'streams') s where s->>'stream' = 'aer'), 'Data Delivery: the aer stream carries the reviewer key');
end $$;
