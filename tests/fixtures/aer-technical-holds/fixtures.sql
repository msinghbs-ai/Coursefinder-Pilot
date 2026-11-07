-- Guards: Platform Admin mandate 7 Nov 2026 21:57 (AER technical holds: classify and correct the actual blockers; recover automatically to the next governed stage;
-- Layer 4 admission authority preserved; no extra spend). Runs after seed.sql (old reader) and the migrations. Every block raises on a failed check.
\set ON_ERROR_STOP 1
set client_min_messages = notice;
create function pg_temp.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is distinct from true then raise exception 'FAIL: %', p_what; end if; end $f$;
create function pg_temp.it(p_tag text) returns uuid language sql as $f$ select item from seeded where tag = p_tag $f$;
create function pg_temp.st(p_item uuid) returns text language sql as $f$ select status from pipeline.layer4_review_items where id = p_item $f$;
create function pg_temp.rows(p_item uuid) returns int language sql as $f$ select count(*)::int from catalogue.course_entry_requirements where provenance->>'review_item_id' = p_item::text and status = 'proposed' $f$;
create function pg_temp.newitem(p_item uuid) returns uuid language sql as $f$ select new_item_id from pipeline.aer_read_supersessions where old_item_id = p_item and state = 'superseded' $f$;

-- BEFORE (the live reader lost the printed requirement): the held read has dropped printed requirements and E13 holds it
do $t$ declare v_gate jsonb := security.course_entry_gate_v1(pg_temp.it('score')); begin
  perform pg_temp.ok(not (v_gate->>'complete')::boolean and jsonb_array_length(v_gate->'drops_uncovered') = 1, 'S1 is held for one dropped printed requirement (score_without_basis)');
  perform pg_temp.ok(pg_temp.rows(pg_temp.it('score')) = 3, 'S1 keeps 3 proposed rows');
  raise notice 'PASS before: the live reader drops a verified requirement for its score field';
end $t$;

\echo apply migrations
\i supabase/migrations/20261107130000_cf247_aer_stored_read_recovery.sql

-- 1 the reader: a requirement is never lost to its score field; a repeated requirement is one row
do $t$ declare v_course uuid := 'c1000000-0000-4000-8000-000000000001'; v_id bigint; v_job uuid := gen_random_uuid(); v_res text; v_item uuid; v_sc numeric; v_notes jsonb; v_n int; v_drop jsonb;
begin
  insert into catalogue.courses(id, provider_id, canonical_title) values ('c1000000-0000-4000-8000-0000000000b1', 'd3000000-0000-4000-8000-000000000000', 'Reader Test');
  insert into pipeline.coverage_course_pages(course_id, provider_id, url) values ('c1000000-0000-4000-8000-0000000000b1', 'd3000000-0000-4000-8000-000000000000', 'https://uni.example/reader');
  insert into pipeline.admin_jobs(id, kind, lane, state) values (v_job, 'enrich_fields', 'enrich', 'done');
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state) values (v_job, 'd3000000-0000-4000-8000-000000000000', 'c1000000-0000-4000-8000-0000000000b1', 'entry_requirements', 'ai') returning id into v_id;
  v_res := security.enrich_entry_record_v1(v_id, jsonb_build_object('model', 'fixture', 'value', jsonb_build_object('rows', jsonb_build_array(
     jsonb_build_object('kind', 'minimum_grade', 'description', 'GPA 2.5', 'confidence', 0.95, 'quote', 'a grade point average of at least 2.5 (out of 4.0)', 'min_entry_score', 2.5, 'min_entry_score_basis', 'GPA 2.5 out of 4.0'),
     jsonb_build_object('kind', 'minimum_grade', 'description', 'ATAR', 'confidence', 0.95, 'quote', 'a selection rank of at least 70 in the final year', 'min_entry_score', 70, 'min_entry_score_basis', 'selection rank of at least 70'),
     jsonb_build_object('kind', 'prior_qualification', 'description', 'degree', 'confidence', 0.95, 'quote', 'You must hold an Australian bachelor degree.'),
     jsonb_build_object('kind', 'prior_qualification', 'description', 'degree again', 'confidence', 0.95, 'quote', 'You must hold an Australian  bachelor degree', 'min_entry_score', null)), 'dropped', '[]'::jsonb)));
  select (value->>'review_item_id')::uuid, value->'notes', value->'dropped' into v_item, v_notes, v_drop from pipeline.field_enrich_items where id = v_id;
  perform pg_temp.ok(v_res = 'review', 'the read is proposed, not held: ' || v_res);
  v_n := pg_temp.rows(v_item);
  perform pg_temp.ok(v_n = 3, 'the repeated requirement is one row, the unbased score keeps its row: ' || v_n);
  select min_entry_score into v_sc from catalogue.course_entry_requirements where provenance->>'review_item_id' = v_item::text and quote like 'a grade point%';
  perform pg_temp.ok(v_sc is null, 'the number without a printed basis is not stored');
  perform pg_temp.ok((select min_entry_score from catalogue.course_entry_requirements where provenance->>'review_item_id' = v_item::text and quote like 'a selection rank%') = 70, 'a score with its printed basis is stored');
  perform pg_temp.ok(exists (select 1 from jsonb_array_elements(v_notes) n where n->>'note' = 'score_without_basis'), 'the nulled score is recorded as a note');
  perform pg_temp.ok(not exists (select 1 from jsonb_array_elements(v_drop) d where d->>'reason' = 'score_without_basis'), 'nothing is dropped as score_without_basis');
  raise notice 'PASS reader: requirement kept, score nulled, repeat is one row';
end $t$;

-- 3 plans (read only)
do $t$ declare p jsonb; begin
  p := security.aer_replay_plan_v1(pg_temp.it('score'));
  perform pg_temp.ok((p->>'ok')::boolean and (p->>'rows_needed')::int = 4 and p->>'source' = 'the waiting read', 'S1 plan: 3 kept rows + the dropped requirement = 4, ok: ' || p::text);
  perform pg_temp.ok((select min_entry_score from jsonb_to_recordset(p->'rows') as x(min_entry_score numeric, quote text) where quote like 'a bachelor degree with a grade%') is null, 'the recovered requirement carries no number');
  p := security.aer_replay_plan_v1(pg_temp.it('limit9'));
  perform pg_temp.ok(not (p->>'ok')::boolean and (p->>'rows_needed')::int = 9 and (p->>'row_limit')::int = 6 and p->>'why' like '%needs at least 9%' and p->>'source' like 'stored read%', 'S2 (Diploma of Commerce shape) needs a row limit of 9: ' || p::text);
  perform pg_temp.ok((p->'check_ok')::boolean, 'S2: apart from the limit, the 9 stored rows pass the D-R2 check');
  p := security.aer_replay_plan_v1(pg_temp.it('notonpage'));
  perform pg_temp.ok(not (p->>'ok')::boolean and p->>'why' like '%still drops%', 'S3: a quote not on the page is not recovered: ' || p::text);
  p := security.aer_replay_plan_v1(pg_temp.it('locked'));
  perform pg_temp.ok(not (p->>'ok')::boolean and p->>'why' like '%manual lock%', 'S4: a manual lock stops it: ' || p::text);
  perform pg_temp.ok(not (security.aer_replay_plan_v1(pg_temp.it('shared'))->>'ok')::boolean, 'S5: a shared page is not recovered');
  raise notice 'PASS plans';
end $t$;

-- 4 preview writes nothing and ignores the switch
do $t$ declare p jsonb; v_before int := (select count(*) from pipeline.aer_read_supersessions); begin
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where key = 'aer.replay_on';
  p := security.aer_replay_v1(true);
  perform pg_temp.ok((p->>'can_be_recovered')::int = 3 and (p->>'replaced')::int = 0, 'preview sees S1, S6, S7 and replaces nothing: ' || p::text);
  perform pg_temp.ok((select count(*) from pipeline.aer_read_supersessions) = v_before and (select count(*) from pipeline.aer_replay_checks) = 0, 'preview writes nothing');
  p := security.aer_replay_v1(false);
  perform pg_temp.ok(p->>'held' = 'aer.replay_on is 0' and (select count(*) from pipeline.aer_read_supersessions) = v_before, 'the switch stops the run');
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where key = 'aer.replay_on';
  raise notice 'PASS preview and switch';
end $t$;

-- 5 per-university cap: university 2 has two recoverable reads, one place a run
do $t$ declare p jsonb; begin
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where key = 'aer.replay_per_provider';
  p := security.aer_replay_v1(false);
  perform pg_temp.ok((p->>'replaced')::int = 2, 'one place for each university this run: ' || p::text);
  perform pg_temp.ok(pg_temp.st(pg_temp.it('score')) = 'superseded', 'S1 is superseded (history kept)');
  perform pg_temp.ok((select count(*) from pipeline.layer4_review_items where status = 'pending' and entity_id in ('c1000000-0000-4000-8000-000000000008', 'c1000000-0000-4000-8000-000000000009')) = 2
                      and (select count(*) from pipeline.layer4_review_items where status = 'superseded' and entity_id in ('c1000000-0000-4000-8000-000000000008', 'c1000000-0000-4000-8000-000000000009')) = 1, 'one of the two reads of the other university waited for room');
  update pipeline.platform_toolset_settings set value = to_jsonb(5) where key = 'aer.replay_per_provider';
  raise notice 'PASS per-university cap';
end $t$;

-- 6 the recovered read: new waiting item for a person, old one superseded, audit kept, nothing approved, no AI
do $t$ declare v_old uuid := pg_temp.it('score'); v_new uuid := pg_temp.newitem(pg_temp.it('score')); v_gate jsonb; begin
  perform pg_temp.ok(v_new is not null and pg_temp.st(v_new) = 'pending', 'a NEW waiting Layer 4 item carries the recovered read');
  perform pg_temp.ok(pg_temp.rows(v_new) = 4, 'the new item has all 4 requirements');
  v_gate := security.course_entry_gate_v1(v_new);
  perform pg_temp.ok((v_gate->>'complete')::boolean, 'the new item passes E13: ' || v_gate::text);
  perform pg_temp.ok((select count(*) from catalogue.course_entry_requirements where status = 'active') = 0 and (select count(*) from pipeline.layer4_decisions) = 0, 'nothing is approved or admitted');
  perform pg_temp.ok((select s.reason from pipeline.aer_read_supersessions s where s.old_item_id = v_old) like 'Replay of the stored read (no AI)%', 'the request records that it is a replay with no AI');
  perform pg_temp.ok(not exists (select 1 from pipeline.admin_jobs where state in ('queued', 'running')) and not exists (select 1 from pipeline.field_enrich_items where state in ('queued', 'ai', 'leased', 'waiting')), 'no read is queued: no AI, no page fetch');
  perform pg_temp.ok((select proposed_value->'supersedes'->>'review_item_id' from pipeline.layer4_review_items where id = v_new) = v_old::text, 'the new item names the item it replaced');
  raise notice 'PASS recovered read: new item, old superseded, nothing admitted';
end $t$;

-- 7 the row limit: the Diploma of Commerce shape recovers once the university's limit is 9 (a setting the Platform Admin owns)
do $t$ declare p jsonb; v_new uuid; begin
  perform security.aer_replay_v1(false);
  perform pg_temp.ok(pg_temp.st(pg_temp.it('limit9')) = 'pending', 'at limit 6 the 9-row read is not touched');
  update pipeline.platform_toolset_settings set value = to_jsonb(array['d1000000-0000-4000-8000-000000000000=9']) where key = 'entry.max_rows_by_provider';
  perform pg_temp.ok((security.aer_replay_plan_v1(pg_temp.it('limit9'))->>'ok')::boolean, 'with the limit at 9 the plan passes');
  p := security.aer_replay_v1(false);
  v_new := pg_temp.newitem(pg_temp.it('limit9'));
  perform pg_temp.ok(v_new is not null and pg_temp.rows(v_new) = 9 and pg_temp.st(pg_temp.it('limit9')) = 'superseded', 'the 9 stored rows become a new waiting item: ' || p::text);
  perform pg_temp.ok((security.course_entry_gate_v1(v_new)->>'complete')::boolean, 'the 9-row item passes E13');
  raise notice 'PASS row limit 9 recovers the Diploma of Commerce shape';
end $t$;

-- 8 what cannot be recovered stays as it was; a second run changes nothing
do $t$ declare v_a jsonb; v_b int; begin
  perform pg_temp.ok(pg_temp.st(pg_temp.it('notonpage')) = 'pending' and pg_temp.st(pg_temp.it('locked')) = 'pending' and pg_temp.st(pg_temp.it('shared')) = 'pending', 'unrecoverable holds are untouched');
  select count(*) into v_b from pipeline.aer_read_supersessions;
  v_a := security.aer_replay_v1(false);
  perform pg_temp.ok((v_a->>'replaced')::int = 0 and (select count(*) from pipeline.aer_read_supersessions) = v_b, 'a second run replaces nothing: ' || v_a::text);
  perform pg_temp.ok((select count(*) from pipeline.aer_replay_checks) > 0, 'judgements are recorded');
  raise notice 'PASS unrecoverable holds untouched; second run changes nothing';
end $t$;

-- 9 daily cap
do $t$ declare v_a jsonb; begin
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where key = 'aer.replay_daily_max';
  v_a := security.aer_replay_v1(false);
  perform pg_temp.ok((v_a->>'replaced')::int = 0, 'the daily cap is counted over 24 hours and is reached: ' || v_a::text);
  raise notice 'PASS daily cap';
end $t$;

-- 10 governance: settings (G2), job (G1), no number in the command, new table commented
do $t$ begin
  perform pg_temp.ok((select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('aer.replay_on', 'batch.aer_replay', 'aer.replay_per_provider', 'aer.replay_daily_max', 'aer.replay_scan')
                       and label is not null and unit is not null and used_by is not null and min_value is not null and max_value is not null) = 5, 'five settings with label, range, unit, used_by');
  perform pg_temp.ok((select value from pipeline.platform_toolset_settings where key = 'entry.max_rows_per_course') = '6'::jsonb, 'the global row limit is unchanged (6)');
  perform pg_temp.ok(exists (select 1 from pipeline.automation_catalogue where jobname = 'aer-replay') and regexp_replace((select command from cron.job where jobname = 'aer-replay'), '_v1', '') !~ '[0-9]', 'job aer-replay catalogued, command without a number');
  perform pg_temp.ok(obj_description('pipeline.aer_replay_checks'::regclass) is not null, 'new table commented');
  raise notice 'PASS governance';
end $t$;

-- 11 matrix rows: the provider rank stored as the qualification's minimum (ANU shape) is put the right way round; admitted rows are never touched
create function pg_temp.mgate(p_item uuid) returns jsonb language sql as $f$ select security.entry_matrix_gate_v1((select id from pipeline.entry_matrix_runs where review_item_id = p_item), '{}') $f$;
do $t$ declare g jsonb; v_item uuid := 'a2000000-0000-4000-8000-000000000001'; v_run uuid := 'f2000000-0000-4000-8000-000000000001'; r jsonb; v_prev jsonb;
begin
  insert into pipeline.entry_matrix_sources(id, provider_id, content_hash) values ('e3000000-0000-4000-8000-000000000009', 'e2000000-0000-4000-8000-000000000009', 'h9');
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status, proposed_value) values (v_item, 'provider', 'e2000000-0000-4000-8000-000000000009', 'entry_matrix_first_run', 'pending', jsonb_build_object('run_id', v_run));
  insert into pipeline.entry_matrix_runs(id, review_item_id, provider_id, source_id, content_hash, state, rows_admitted, rows_dropped, result)
  values (v_run, v_item, 'e2000000-0000-4000-8000-000000000009', 'e3000000-0000-4000-8000-000000000009', 'h9', 'done', 3, 0, jsonb_build_object('dropped', '[]'::jsonb, 'completeness', jsonb_build_object('status', 'not_applicable')));
  insert into catalogue.provider_entry_matrix(id, run_id, provider_id, source_id, content_hash, status, country_code, qualification_name, min_grade, min_value, grade_scale, benchmark_band, quote, row_hash)
  values ('b2000000-0000-4000-8000-000000000001', v_run, 'e2000000-0000-4000-8000-000000000009', 'e3000000-0000-4000-8000-000000000009', 'h9', 'proposed', 'BG', 'Bulgarian Diploma of Completion of Secondary Education',
          'Program Required Entrance Rank: 70', 70, 'rank', '2.9', 'Program Required Entrance Rank: 70 | Indicative score required: 2.9', 'r1'),
         ('b2000000-0000-4000-8000-000000000002', v_run, 'e2000000-0000-4000-8000-000000000009', 'e3000000-0000-4000-8000-000000000009', 'h9', 'proposed', 'CA', 'Canada Manitoba High School Diploma',
          'Program Required Entrance Rank: 80', 80, 'rank', 'Indicative score required: 52', 'Program Required Entrance Rank: 80 | Indicative score required: 52', 'r2'),
         ('b2000000-0000-4000-8000-000000000003', v_run, 'e2000000-0000-4000-8000-000000000009', 'e3000000-0000-4000-8000-000000000009', 'h9', 'proposed', 'US', 'USA American College Test (ACT)',
          '23', 23, 'points', '80', 'ANU Entrance Rank: 80 | Indicative score required: 23', 'r3');
  insert into catalogue.provider_entry_matrix(id, run_id, provider_id, source_id, content_hash, status, country_code, qualification_name, min_grade, min_value, grade_scale, benchmark_band, quote, row_hash)
  values ('b2000000-0000-4000-8000-0000000000a1', gen_random_uuid(), 'e2000000-0000-4000-8000-000000000009', 'e3000000-0000-4000-8000-000000000009', 'h8', 'active', 'NZ', 'NCEA Level 3', 'Program Required Entrance Rank: 70', 70, 'rank', '2.9',
          'Program Required Entrance Rank: 70 | Indicative score required: 2.9', 'ra');
  g := pg_temp.mgate(v_item);
  perform pg_temp.ok(not (g->>'complete')::boolean and jsonb_array_length(g->'flagged') = 2 and g->'flagged'->0->>'why' = 'the provider''s rank is stored as the qualification''s minimum', 'BEFORE: two rows held by D-R3 as rank stored as minimum: ' || g::text);
  v_prev := security.aer_matrix_rank_repair_v1(true);
  perform pg_temp.ok((v_prev->>'rows')::int = 2 and (select count(*) from pipeline.aer_row_repairs) = 0 and (select min_value from catalogue.provider_entry_matrix where id = 'b2000000-0000-4000-8000-000000000001') = 70, 'preview counts 2 rows and writes nothing: ' || v_prev::text);
  r := security.aer_replay_v1(false)->'matrix_rank_repair';
  perform pg_temp.ok((r->>'rows')::int = 2, 'two rows repaired by the job: ' || r::text);
  perform pg_temp.ok((select (min_value, min_grade, grade_scale, benchmark_band) = (2.9, '2.9', 'points', '70') from catalogue.provider_entry_matrix where id = 'b2000000-0000-4000-8000-000000000001'), 'row 1: score is the value, rank is the band');
  perform pg_temp.ok((select (min_value, min_grade, grade_scale, benchmark_band) = (52, '52', 'points', '80') from catalogue.provider_entry_matrix where id = 'b2000000-0000-4000-8000-000000000002'), 'row 2: label text in the band is read as its number');
  perform pg_temp.ok((select min_value = 23 and benchmark_band = '80' from catalogue.provider_entry_matrix where id = 'b2000000-0000-4000-8000-000000000003'), 'a row already the right way round is untouched');
  perform pg_temp.ok((select min_value = 70 and grade_scale = 'rank' from catalogue.provider_entry_matrix where id = 'b2000000-0000-4000-8000-0000000000a1'), 'an admitted row is never touched');
  perform pg_temp.ok((select count(*) from pipeline.aer_row_repairs) = 2 and (select before->>'min_value' from pipeline.aer_row_repairs where row_id = 'b2000000-0000-4000-8000-000000000001') = '70', 'the original is kept');
  g := pg_temp.mgate(v_item);
  perform pg_temp.ok((g->>'complete')::boolean, 'AFTER: the run passes D-R3: ' || g::text);
  perform pg_temp.ok((security.aer_matrix_rank_repair_v1(false)->>'rows')::int = 0 and (select count(*) from pipeline.layer4_decisions) = 0, 'a second run repairs nothing; nothing was decided');
  raise notice 'PASS matrix rank repair';
end $t$;
