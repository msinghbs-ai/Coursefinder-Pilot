-- Guards: F-CDESC decline throughput (Platform Admin directive 10 Nov 2026): a provider's places for first descriptions are not taken by descriptions the machine has declined for good, so a paid reading is no longer held behind them; held readings are replayed
-- and promoted without an AI call (only where the reader is provable); the standing queue takes courses in rounds across providers and leaves out a university with every place taken; and the Data Delivery stages carry the eligible denominator, causes and blocker as one
-- additive key. Every row is invented. Needs the throughput migration (runs once, on the migrated database).
\set ON_ERROR_STOP 1
update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_machine_on'; -- scratch database only
update pipeline.platform_toolset_settings set value = '3'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_pending_max'; -- scratch database only
create table if not exists pipeline.zoho_sync_items(entity text, item_key text, ref_id uuid, hash text, seq bigint, seq_at timestamptz, removed_at timestamptz, item jsonb);
create function pg_temp.mkc(n int, prov int) returns void language plpgsql as $$
declare v_hash text := md5(n::text) || md5((n + 1000)::text); v_path text; v_url text := 'https://example.test/course/' || n;
begin
  insert into pim.entity_registry(id, stable_key) values (pg_temp.cid(n), 'cm-c' || n);
  insert into catalogue.courses(id, stable_key, provider_id, canonical_title, publication_status) values (pg_temp.cid(n), 'cm-c' || n, pg_temp.pid(prov), 'Cm Course ' || n, 'published');
  v_path := 'layer2/AU/coverage/src/' || pg_temp.cid(n) || '/' || v_hash || '.html.gz';
  insert into pipeline.evidence_artifacts(id, evidence_type, source_url, storage_path, content_hash, captured_at) values (pg_temp.eid(n), 'page', v_url, v_path, v_hash, now() - interval '3 days');
  insert into storage.objects(bucket_id, name, metadata) values ('evidence', v_path, '{"size": 5000}');
  insert into pipeline.coverage_course_pages(course_id, provider_id, status, identity_basis, url, evidence_id, read_status, read_at, basis, score, runner_up)
  values (pg_temp.cid(n), pg_temp.pid(prov), 'bound', 'course_title_on_page', v_url, pg_temp.eid(n), 'read', now() - interval '3 days', 'title_match', 0.95, 0.30);
end $$;
create function pg_temp.reading(n int, prov int, p_state text, p_reason text, p_sents jsonb, p_answer boolean) returns bigint language plpgsql as $$
declare v_id bigint;
begin
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, reason, value, evidence_id)
  values ('00000000-0000-4000-c000-0000000000f1', pg_temp.pid(prov), pg_temp.cid(n), 'description', p_state, 'ai_stored', p_reason,
          jsonb_build_object('about_course', true, 'sentences', p_sents, 'text', pg_temp.txt(p_sents)), pg_temp.eid(n)) returning id into v_id;
  if p_answer then
    insert into pipeline.enrich_ai_answers(item_id, state, answer) values (v_id, 'recorded', jsonb_build_object('model', 'openai/gpt-4.1-mini', 'prompt_version', 'course-text-v2', 'worker', 'w-0.59', 'value', jsonb_build_object('sentences', p_sents, 'about_course', true)));
  end if;
  return v_id;
end $$;
create function pg_temp.enrich(p_id bigint, p_model text) returns text language plpgsql as $$
begin return security.enrich_course_text_record_v1(p_id, jsonb_build_object('value', (select value from pipeline.field_enrich_items where id = p_id), 'model', p_model, 'prompt_version', 'course-text-v2', 'worker', 'w')); end $$;
create function pg_temp.stu(n int) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('text', 'Students study ' || pg_temp.w(n, 2) || ' and ' || pg_temp.w(n, 3) || ' in depth through coursework and a project.',
                                              'quote', 'You will study ' || pg_temp.w(n, 2) || ' and ' || pg_temp.w(n, 3) || ' in depth through coursework and a project.', 'on_page', true),
                           jsonb_build_object('text', 'Learners complete a ' || pg_temp.w(n, 6) || ' project in the final stage under academic guidance.',
                                              'quote', 'Learners complete a ' || pg_temp.w(n, 6) || ' project in the final stage under academic guidance.', 'on_page', true)) $$;

-- ---- 1. the provider's places ------------------------------------------------------------------------------------------------------------------------------------
-- provider 6 holds 3 waiting descriptions that the machine declines for good (hand locks); provider 7 holds 3 that no one has looked at (pending_max is 3 for this file)
select pg_temp.mk(n, 6) from generate_series(371, 373) n;
insert into pipeline.manual_locks(entity, entity_id, field, mode) select 'course', pg_temp.cid(n), 'description', 'value' from generate_series(371, 373) n;
select security.course_description_machine_admit_v1(pg_temp.rid(n), 'test') from generate_series(371, 373) n;
select pg_temp.mk(n, 7) from generate_series(376, 378) n;
\if :{?oldmode}
\else
select pg_temp.expect('places: three waiting descriptions the machine declined for good take no place (3 left of 3)', security.cdesc_provider_slots_v1(pg_temp.pid(6)) = 3);
select pg_temp.expect('places: three waiting descriptions no one has looked at take all three places (0 left)', security.cdesc_provider_slots_v1(pg_temp.pid(7)) = 0);
\endif
select pg_temp.mkc(374, 6); select pg_temp.mkc(379, 7);
select pg_temp.reading(374, 6, 'queued', null, pg_temp.stu(374), false) a \gset
select pg_temp.reading(379, 7, 'queued', null, pg_temp.stu(379), false) b \gset
select pg_temp.enrich(:a, 'openai/gpt-4.1-mini') r6 \gset
select pg_temp.expect('REGRESSION places: a new reading for provider 6 goes to Layer 4 (it used to be held behind the three declined descriptions)', :'r6' = 'review');
select pg_temp.enrich(:b, 'openai/gpt-4.1-mini') r7 \gset
select pg_temp.expect('places: a new reading for provider 7 is still held behind its three waiting descriptions', :'r7' = 'held_first_admission');
\if :{?oldmode}
\else
select pg_temp.expect('places: the held reading records its reader (model, prompt, worker)', (select value->'reader'->>'model' || '/' || (value->'reader'->>'prompt') from pipeline.field_enrich_items where id = :b) = 'openai/gpt-4.1-mini/course-text-v2');
\endif
select pg_temp.expect('places: the machine rule admitted the provider 6 reading as it arrived (students where the page says you)', pg_temp.dsc(374) is not null);
-- on the database from before the migration only the places checks above run (the REGRESSION one must fail there)
\if :{?oldmode}
do $$ declare n_fail int := (select count(*) from g_t where not ok); n int := (select count(*) from g_t);
begin
  if n_fail > 0 then raise exception 'cdt-flow: % of % checks FAILED', n_fail, n; end if;
  raise notice 'cdt-flow: all % checks passed', n;
end $$;
\q
\endif

-- ---- 2. replay of held readings and promotion into free places ----------------------------------------------------------------------------------------------------
update pipeline.platform_toolset_settings set value = '100'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_pending_max';
select pg_temp.mkc(n, 2) from generate_series(381, 384) n;
-- 381 held for "students" with a provable reader; 382 the same with no provable reader; 383 held for a quote that is not on the page; 384 held first-admission with a provable reader
select pg_temp.reading(381, 2, 'skipped', 'held: unsupported_claim: a ranking, outcome or accreditation claim that is not in the quote', pg_temp.stu(381), true) x1 \gset
select pg_temp.reading(382, 2, 'skipped', 'held: unsupported_claim: a ranking, outcome or accreditation claim that is not in the quote', pg_temp.stu(382), false) x2 \gset
select pg_temp.reading(383, 2, 'skipped', 'held: quote_not_on_page: a sentence''s words are not on the course page', jsonb_set(pg_temp.stu(383), '{0,on_page}', 'false'), true) x3 \gset
select pg_temp.reading(384, 2, 'skipped', 'held_first_admission: the provider''s first descriptions wait in Layer 4; admitted once they are approved', pg_temp.stu(384), true) x4 \gset
update pipeline.field_enrich_items set value = value || jsonb_build_object('text', pg_temp.txt(value->'sentences')) where id = :x4;
select pg_temp.diag('recheck1', $q$select security.cdesc_recheck_held_v1()::text$q$);
select pg_temp.expect('replay: a held reading that now passes the live check with a provable reader reaches Layer 4 and is admitted by the machine rule, with no AI call', pg_temp.dsc(381) is not null
  and (select state from pipeline.field_enrich_items where id = :x1) = 'filled'
  and (select count(*) from pipeline.course_description_machine_admissions where course_id = pg_temp.cid(381) and outcome = 'admitted' and model = 'openai/gpt-4.1-mini' and prompt_version = 'course-text-v2') = 1);
select pg_temp.expect('replay: a held reading with no provable reader is not replayed (and is noted for this policy stamp, so it is not looked at again)', pg_temp.dsc(382) is null
  and (select state from pipeline.field_enrich_items where id = :x2) = 'skipped' and (select value->>'recheck_stamp' from pipeline.field_enrich_items where id = :x2) = security.course_description_machine_policy_stamp_v1());
select pg_temp.expect('replay: a reading whose quote is not on the page stays held', pg_temp.dsc(383) is null and (select state from pipeline.field_enrich_items where id = :x3) = 'skipped');
select pg_temp.expect('promotion: a held first-admission reading takes a free place and is admitted by the machine rule', pg_temp.dsc(384) is not null);
select pg_temp.expect('replay: nothing is looked at twice for the same policy stamp', (security.cdesc_recheck_held_v1()->>'looked_at')::int = 0);
select pg_temp.expect('the job reports the replay', security.course_description_machine_run_v1() ? 'held');

-- ---- 3. the standing queue ----------------------------------------------------------------------------------------------------------------------------------------
-- provider 6: four more courses to read, provider 3: one, provider 2: two with its places all taken by waiting descriptions (pending_max 2 for this part)
update pipeline.platform_toolset_settings set value = '2'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_pending_max';
update pipeline.platform_toolset_settings set value = '3'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_text_items_per_day';
select security.course_description_machine_admit_v1(pg_temp.rid(n), 'test') from generate_series(371, 373) n; -- the policy stamp moved with the setting: the three hand-locked descriptions are declined again under the new stamp
select pg_temp.mkc(n, 6) from generate_series(401, 404) n;
select pg_temp.mkc(405, 3);
select pg_temp.mkc(n, 2) from generate_series(406, 407) n;
select pg_temp.mk(n, 2) from generate_series(411, 412) n; -- two waiting descriptions, no one has looked at them: provider 2 is full
create temporary table g_gaps as select * from security.enrich_course_text_gaps_v1(array['description']);
select pg_temp.diag('gaps', $q$select provider_id::text || ' ' || course_id::text || ' ' || pri from g_gaps order by pri, course_id$q$);
select pg_temp.expect('queue: the day''s three reads go in rounds across providers (two of the four provider 6 courses, the provider 3 course), never all to provider 6',
  (select count(*) from g_gaps) = 3 and (select count(*) from g_gaps where provider_id = pg_temp.pid(6)) = 2 and exists (select 1 from g_gaps where course_id = pg_temp.cid(405)));
select pg_temp.expect('queue: a university whose every place is taken by waiting descriptions (provider 2) gets no new reading', not exists (select 1 from g_gaps where provider_id = pg_temp.pid(2)));
update pipeline.platform_toolset_settings set value = '500'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_text_items_per_day';
select pg_temp.expect('queue: the same courses, no rounds needed, are all offered when the cap allows (priority unchanged)', (select count(*) from security.enrich_course_text_gaps_v1(array['description']) where provider_id = pg_temp.pid(6)) >= 4);

-- a reading held behind the provider's places that never recorded its reader (and no stored answer proves it) is read once more, ahead of a course that was never read; one with a provable reader is not (it is promoted or replayed with no AI call)
select pg_temp.mkc(408, 3);
select pg_temp.mkc(409, 3);
select pg_temp.reading(408, 3, 'skipped', 'held_first_admission: the provider''s first descriptions wait in Layer 4; admitted once they are approved', pg_temp.stu(408), false) x5 \gset
select pg_temp.reading(409, 3, 'skipped', 'held_first_admission: the provider''s first descriptions wait in Layer 4; admitted once they are approved', pg_temp.stu(409), true) x6 \gset
select pg_temp.diag('gaps2', $q$select course_id::text || ' ' || pri from security.enrich_course_text_gaps_v1(array['description']) where provider_id = pg_temp.pid(3) order by pri, course_id$q$);
select pg_temp.expect('queue: a held-first reading with no recorded reader is read again, first', exists (select 1 from security.enrich_course_text_gaps_v1(array['description']) g where g.course_id = pg_temp.cid(408) and g.pri = 0));
select pg_temp.expect('queue: a held-first reading whose reader is proved is not read again', not exists (select 1 from security.enrich_course_text_gaps_v1(array['description']) g where g.course_id = pg_temp.cid(409)));

-- ---- 4. Data Delivery -----------------------------------------------------------------------------------------------------------------------------------------------
select security.data_delivery_cdesc_flow_v1() j \gset flow_
create temporary table g_flow as select security.data_delivery_cdesc_flow_v1() j;
select pg_temp.diag('flow', $q$select j::text from g_flow$q$);
select pg_temp.expect('flow: known, with the eligible denominator equal to the courses that lack a description and hold a stored read identity-proved page',
  (select (j->>'known')::boolean and (j->'eligible'->>'without_description')::int = (select count(*) from catalogue.courses c where c.lifecycle_status = 'active' and nullif(btrim(c.description), '') is null
        and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.evidence_id is not null and g.status in ('bound', 'ambiguous') and g.read_status = 'read' and g.identity_basis is not null)) from g_flow));
select pg_temp.expect('flow: the stages of the eligible courses add up', (select (j->'eligible'->>'without_description')::int = (j->'eligible'->>'never_read')::int + (j->'eligible'->>'waiting_in_layer4')::int + (j->'eligible'->>'held_behind_provider_cap')::int
        + (j->'eligible'->>'held_by_a_check')::int + (j->'eligible'->>'read_other')::int from g_flow));
select pg_temp.expect('flow: every decline of a waiting item is counted by cause', (select (select coalesce(sum((x->>'n')::int), 0) from jsonb_array_elements(j->'declined_by_cause') x) from g_flow)
        = (select count(*) from pipeline.course_description_machine_admissions d join pipeline.layer4_review_items q on q.id = d.review_item_id and q.status = 'pending' where d.outcome = 'declined' and d.withdrawn_at is null));
select pg_temp.expect('flow: held readings are counted by cause', exists (select 1 from g_flow, jsonb_array_elements(j->'held_by_cause') x where x->>'code' = 'unsupported_claim'));
select pg_temp.expect('flow: admissions in 24 hours are the retained ones and equal the ledger', (select (j->'gain'->>'admitted_24h')::int from g_flow) = (select count(*) from pipeline.course_description_machine_admissions where outcome = 'admitted' and withdrawn_at is null and created_at > now() - interval '1 day'));
select pg_temp.expect('flow: reads today against the cap, the job schedule and the last admission are shown', (select (j->'reads'->>'daily_cap')::int = 500 and j->'run'->>'schedule' is not null and j->'run'->>'last_admission_at' is not null from g_flow));
select pg_temp.expect('flow: the blocker names the places when a university is full', (select j->>'blocker' like '%universities have every place taken%' from g_flow));
select pg_temp.expect('stages: the existing course description stages carry the flow key and keep their other keys', (select s ? 'flow' and s ? 'validation' and s ? 'admitted' and s ? 'consumers' and (s->'flow'->>'known')::boolean from (select security.data_delivery_cdesc_stages_v1() s) z));

do $$ declare n_fail int := (select count(*) from g_t where not ok); n int := (select count(*) from g_t);
begin
  if n_fail > 0 then raise exception 'cdt-flow: % of % checks FAILED', n_fail, n; end if;
  raise notice 'cdt-flow: all % checks passed', n;
end $$;
