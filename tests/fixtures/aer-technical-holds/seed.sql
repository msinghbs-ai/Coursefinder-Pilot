-- Production shapes (no live data; quotes are short paraphrases of the shape). Runs BEFORE the migration, with the live (old) reader.
\set ON_ERROR_STOP 1
create function pg_temp.r(p_kind text, p_quote text, p_score numeric default null, p_basis text default null) returns jsonb language sql as $f$
  select jsonb_build_object('kind', p_kind, 'audience', 'all', 'description', p_quote, 'min_entry_score', p_score, 'min_entry_score_basis', p_basis,
                            'benchmark_band', null, 'min_grade', null, 'confidence', 0.95, 'quote', p_quote) $f$;
create function pg_temp.read(p_course uuid, p_rows jsonb, p_dropped jsonb default '[]') returns uuid language plpgsql as $f$
declare v_id bigint; v_job uuid := gen_random_uuid();
begin
  insert into pipeline.admin_jobs(id, kind, lane, state, requested_by) values (v_job, 'enrich_fields', 'enrich', 'done', 'c0ffee00-0000-4000-8000-000000000150');
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state) select v_job, c.provider_id, c.id, 'entry_requirements', 'ai' from catalogue.courses c where c.id = p_course returning id into v_id;
  perform security.enrich_entry_record_v1(v_id, jsonb_build_object('value', jsonb_build_object('rows', p_rows, 'dropped', p_dropped), 'model', 'fixture'));
  return (select (value->>'review_item_id')::uuid from pipeline.field_enrich_items where id = v_id);
end $f$;
create function pg_temp.gate_all() returns void language sql as $f$
  insert into pipeline.layer4_item_readiness(item_id, gate, gate_checked_at, readiness) select i.id, security.course_entry_gate_v1(i.id), now(), 'x' from pipeline.layer4_review_items i where i.status = 'pending'
  on conflict (item_id) do update set gate = excluded.gate $f$;

insert into catalogue.courses(id, provider_id, canonical_title) values
 ('c1000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000000', 'Graduate Certificate in Scores'),
 ('c1000000-0000-4000-8000-000000000002', 'd1000000-0000-4000-8000-000000000000', 'Diploma of Commerce'),
 ('c1000000-0000-4000-8000-000000000003', 'd1000000-0000-4000-8000-000000000000', 'Bachelor of Quotes'),
 ('c1000000-0000-4000-8000-000000000004', 'd1000000-0000-4000-8000-000000000000', 'Bachelor of Locks'),
 ('c1000000-0000-4000-8000-000000000005', 'd1000000-0000-4000-8000-000000000000', 'Bachelor of Pages'),
 ('c1000000-0000-4000-8000-000000000006', 'd1000000-0000-4000-8000-000000000000', 'Bachelor of Pages (Honours)'),
 ('c1000000-0000-4000-8000-000000000007', 'd1000000-0000-4000-8000-000000000000', 'Master of Cut Rows'),
 ('c1000000-0000-4000-8000-000000000008', 'd2000000-0000-4000-8000-000000000000', 'Master of Other University'),
 ('c1000000-0000-4000-8000-000000000009', 'd2000000-0000-4000-8000-000000000000', 'Master of Other University Two');
insert into pipeline.coverage_course_pages(course_id, provider_id, url) select c.id, c.provider_id, 'https://uni.example/' || case when c.id::text like '%0005' or c.id::text like '%0006' then 'shared' else c.id::text end from catalogue.courses c where c.id::text like 'c1000000%';

-- S1 (shape of a GPA minimum dropped as score_without_basis): 3 kept rows + 1 dropped requirement the page prints
create table public.seeded(tag text primary key, item uuid);
insert into seeded select 'score', pg_temp.read('c1000000-0000-4000-8000-000000000001', jsonb_build_array(
  pg_temp.r('prior_qualification', 'You must hold an Australian bachelor degree or equivalent.'),
  pg_temp.r('work_experience', 'Two years of relevant work experience is preferred for this program.'),
  pg_temp.r('portfolio_interview', 'You may be asked to attend an interview with the course coordinator.'),
  pg_temp.r('minimum_grade', 'a bachelor degree with a grade point average of at least 2.5 (out of 4.0)', 2.5, 'GPA 2.5 out of 4.0')));
-- S2 (Diploma of Commerce shape): the read of a page with 9 requirements; the corrected read keeps all 9 (value.rows_read) when the limit is too low
-- build the old waiting item by hand (pre-E13 reader: first 6 kept, 3 cut), then the stored corrected read with its rows
do $s2$ declare v_item uuid := gen_random_uuid(); v_job uuid := gen_random_uuid(); i int; q text[] := array[
  'You must have completed an Australian Year 12 or equivalent with a minimum average of 50 percent.', 'You must have completed the Victorian Certificate of Education (VCE) or equivalent.',
  'Successful completion of an approved pathway qualification guarantees entry.', 'You must have completed at least two undergraduate courses at an Australian university.',
  'Equivalent qualifications include the RMIT Foundation Studies program.', 'Prerequisites VCE units 3 and 4: a study score of at least 20 in English.',
  'You may satisfy the academic requirements by completing the STAT multiple choice.', 'There are no prerequisite subjects required for entry into this qualification.',
  'A selection task is not required for entry into this qualification.'];
begin
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status, proposed_value, evidence_id)
  values (v_item, 'course', 'c1000000-0000-4000-8000-000000000002', 'course_entry_first_read', 'pending',
          jsonb_build_object('url', 'https://uni.example/c1000000-0000-4000-8000-000000000002', 'rows', 6, 'limit', 6,
            'dropped', (select jsonb_agg(jsonb_build_object('reason', 'over_row_limit', 'kind', 'general_note', 'quote', q[n])) from generate_series(7, 9) n)), null);
  for i in 1 .. 6 loop
    insert into catalogue.course_entry_requirements(course_id, kind, audience, description, quote, confidence, status, provenance)
    values ('c1000000-0000-4000-8000-000000000002', case when i = 6 then 'subject_prerequisite' else 'prior_qualification' end, 'all', q[i], q[i], 0.95, 'proposed', jsonb_build_object('review_item_id', v_item));
  end loop;
  insert into pipeline.admin_jobs(id, kind, lane, state, requested_by) values (v_job, 'enrich_fields', 'enrich', 'done', 'c0ffee00-0000-4000-8000-000000000150');
  -- the corrected read refused at the row limit kept all 9 rows it read
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, reason, value)
  values (v_job, 'd1000000-0000-4000-8000-000000000000', 'c1000000-0000-4000-8000-000000000002', 'entry_requirements', 'skipped', 'held_partial: over_row_limit: the page has 9 requirements and the limit is 6',
          jsonb_build_object('held', 'over_row_limit', 'limit', 6,
            'rows_read', (select jsonb_agg(jsonb_build_object('kind', case when n = 6 then 'subject_prerequisite' else 'prior_qualification' end, 'audience', 'all', 'description', q[n], 'quote', q[n], 'confidence', 0.95, 'min_entry_score', null)) from generate_series(1, 9) n),
            'dropped', (select jsonb_agg(jsonb_build_object('reason', 'over_row_limit', 'kind', 'general_note', 'quote', q[n])) from generate_series(7, 9) n)));
  insert into seeded values ('limit9', v_item);
end $s2$;
-- S3: a requirement the reader dropped because its quote was not on the page: not recoverable from stored records
insert into seeded select 'notonpage', pg_temp.read('c1000000-0000-4000-8000-000000000003', jsonb_build_array(pg_temp.r('prior_qualification', 'You must hold an Australian bachelor degree or equivalent.')),
  jsonb_build_array(jsonb_build_object('reason', 'quote_not_on_page', 'kind', 'minimum_grade', 'quote', 'A credit average in the final year... and evidence of experience')));
-- S4: as S1 but the course has a manual lock
insert into catalogue.courses(id, provider_id, canonical_title) values ('c1000000-0000-4000-8000-0000000000a4', 'd1000000-0000-4000-8000-000000000000', 'Bachelor of Locks Two');
insert into pipeline.coverage_course_pages(course_id, provider_id, url) values ('c1000000-0000-4000-8000-0000000000a4', 'd1000000-0000-4000-8000-000000000000', 'https://uni.example/lock');
insert into seeded select 'locked', pg_temp.read('c1000000-0000-4000-8000-0000000000a4', jsonb_build_array(pg_temp.r('prior_qualification', 'You must hold a Year 12 certificate or equivalent.'),
  pg_temp.r('minimum_grade', 'a grade point average of at least 3.0 (out of 4.0)', 3.0, 'GPA 3 out of 4')));
-- S5: two courses on one page: shared page (a person confirms which programme)
insert into seeded select 'shared', pg_temp.read('c1000000-0000-4000-8000-000000000005', jsonb_build_array(pg_temp.r('prior_qualification', 'You must hold an Australian bachelor degree or equivalent.'),
  pg_temp.r('minimum_grade', 'a grade point average of at least 2.0 (out of 4.0)', 2.0, 'GPA 2 out of 4')));
-- S6, S7: another university, two score holds: the per-university cap
insert into seeded select 'other1', pg_temp.read('c1000000-0000-4000-8000-000000000008', jsonb_build_array(pg_temp.r('prior_qualification', 'You must hold a recognised degree or equivalent qualification.'),
  pg_temp.r('minimum_grade', 'a weighted average mark of at least 65 percent in the final degree', 65, 'average mark of 65 percent')));
insert into seeded select 'other2', pg_temp.read('c1000000-0000-4000-8000-000000000009', jsonb_build_array(pg_temp.r('prior_qualification', 'You must hold a recognised degree or equivalent qualification here.'),
  pg_temp.r('minimum_grade', 'a weighted average mark of at least 70 percent in the final degree', 70, 'average mark of 70 percent')));
insert into pipeline.manual_locks(entity, entity_id, field) values ('course', 'c1000000-0000-4000-8000-0000000000a4', 'entry_requirements');
select pg_temp.gate_all();
