-- Guards: D-R2, D-R3 and the E13 extension (Platform Admin direction 2 Nov 2026 23:24) on isolated fixtures.
-- Runs after both stubs files, the rebuilt live definitions and the 20261103070000 migration (see run.sh). Every block raises on a failed
-- check; each passing block prints "PASS <name>". Each failure fixture is labelled with the real pending Layer 4 item whose shape it reproduces
-- (readiness assessment 2 Nov 2026, ui-audit/aer-readiness-2026-11-02.csv). No live data is copied: quotes are shortened paraphrases of the
-- shape (the reason, the kind, the cell layout), never the page.
\set ON_ERROR_STOP 1
set client_min_messages = notice;

create function pg_temp.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is distinct from true then raise exception 'FAIL: %', p_what; end if; end $f$;
create function pg_temp.r(p_kind text, p_quote text, p_score numeric default null, p_basis text default null) returns jsonb language sql as $f$
  select jsonb_build_object('kind', p_kind, 'audience', 'all', 'description', p_quote, 'min_entry_score', p_score, 'min_entry_score_basis', p_basis,
                            'benchmark_band', null, 'min_grade', null, 'confidence', 0.95, 'quote', p_quote) $f$;
-- the worker's result for one enrich item (rows, and the rows the worker itself dropped, e.g. quote_not_on_page)
create function pg_temp.record(p_item bigint, p_rows jsonb, p_dropped jsonb default '[]') returns text language sql as $f$
  select security.enrich_entry_record_v1(p_item, jsonb_build_object('value', jsonb_build_object('rows', p_rows, 'dropped', p_dropped), 'model', 'fixture')) $f$;
create function pg_temp.read(p_course uuid, p_rows jsonb, p_dropped jsonb default '[]') returns uuid language plpgsql as $f$
declare v_id bigint;
begin
  insert into pipeline.field_enrich_items(provider_id, course_id, state) select c.provider_id, c.id, 'ai' from catalogue.courses c where c.id = p_course returning id into v_id;
  perform pg_temp.record(v_id, p_rows, p_dropped);
  return (select (value->>'review_item_id')::uuid from pipeline.field_enrich_items where id = v_id);
end $f$;
create function pg_temp.approve(p_item uuid, p_exclude uuid[] default '{}') returns text language plpgsql as $f$
begin
  perform security.course_entry_review_apply_v1(p_item, 'approve',
    case when cardinality(p_exclude) > 0 then jsonb_build_object('mode', 'approve_except', 'exclude_row_ids', to_jsonb(p_exclude), 'reviewer', 'fixture') end, 'fixture decision');
  return null;
exception when sqlstate '55000' then return sqlerrm;
end $f$;
create function pg_temp.gate(p_item uuid, p_exclude uuid[] default '{}') returns jsonb language sql as $f$ select security.course_entry_gate_v1(p_item, p_exclude) $f$;
create function pg_temp.rows_of(p_item uuid, p_like text) returns uuid[] language sql as $f$
  select array_agg(id) from catalogue.course_entry_requirements where provenance->>'review_item_id' = p_item::text and quote ilike p_like $f$;

insert into catalogue.courses(id, provider_id, canonical_title) values
 ('c0000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000000', 'Diploma in Design (Level 5)'),
 ('c0000000-0000-4000-8000-000000000002', 'd1000000-0000-4000-8000-000000000000', 'Master of Advanced Health Care Practice'),
 ('c0000000-0000-4000-8000-000000000003', 'd1000000-0000-4000-8000-000000000000', 'New Zealand Certificate in Foundation Skills (Level 2)'),
 ('c0000000-0000-4000-8000-000000000004', 'd1000000-0000-4000-8000-000000000000', 'Bachelor of Arts (NZSL-English Interpreting) (Level 7)'),
 ('c0000000-0000-4000-8000-000000000005', 'd1000000-0000-4000-8000-000000000000', 'Master of Engineering (Level 9)'),
 ('c0000000-0000-4000-8000-000000000006', 'd1000000-0000-4000-8000-000000000000', 'Master of Communication (Level 9)'),
 ('c0000000-0000-4000-8000-000000000007', 'd1000000-0000-4000-8000-000000000000', 'Master of Public Health (Level 9)'),
 ('c0000000-0000-4000-8000-000000000008', 'd1000000-0000-4000-8000-000000000000', 'Master of Social Work'),
 ('c0000000-0000-4000-8000-000000000009', 'd1000000-0000-4000-8000-000000000000', 'Master of Nursing Science (Level 9)');
insert into pipeline.coverage_course_pages(course_id, provider_id, url) select c.id, c.provider_id, 'https://uni.example/' || c.id from catalogue.courses c where c.id::text like 'c0000000%';
insert into auth.session values ('99999999-0000-4000-8000-000000000000', 6);

-- ------------------------------------------------------------------ settings: registered for Settings > Pipeline settings (G2)
do $t$ begin
  perform pg_temp.ok((select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('entry.gate_hold_reasons', 'entry.gate_cover_chars',
            'entry.gate_cover_min_chars', 'entry.nonrequirement_patterns', 'entry.domestic_audience_words', 'entry.matrix_gate', 'entry.matrix_gate_ignore_reasons',
            'entry.matrix_rank_words', 'entry.matrix_score_words', 'entry.supersede_claim_minutes', 'entry.supersede_lock_fields')
            and label is not null and unit is not null and used_by is not null and section = 'Entry requirements') = 11, 'eleven settings with label, unit, used_by');
  perform pg_temp.ok((select value from pipeline.platform_toolset_settings where key = 'entry.max_rows_per_course') = '6'::jsonb, 'the global cap is unchanged (6)');
  raise notice 'PASS settings';
end $t$;

-- ------------------------------------------------------------------ E13 extension (course reads)
-- [shape of University of Auckland 960bee1b-dde9-40e3-ad53-c7cf93f72ea2: a minimum dropped as score_without_basis and quotes dropped as
--  quote_not_on_page, none covered by a kept row: passed E13, now held]
do $t$ declare v uuid; g jsonb; begin
  v := pg_temp.read('c0000000-0000-4000-8000-000000000006', jsonb_build_array(
         pg_temp.r('prior_qualification', 'A bachelors degree in a relevant discipline'),
         pg_temp.r('minimum_grade', 'with a grade point average of 5.0', 5.0, 'GPA of 5.0 on a 9-point scale')),          -- basis not in the quote
       jsonb_build_array(jsonb_build_object('reason', 'quote_not_on_page', 'kind', 'minimum_grade', 'quote', 'Applicants need a B average in their final year courses')));
  g := pg_temp.gate(v);
  perform pg_temp.ok(not (g->>'complete')::boolean, 'uncovered drops hold the read');
  perform pg_temp.ok(jsonb_array_length(g->'drops_uncovered') = 2, 'two uncovered drops named (' || (g->'drops_uncovered')::text || ')');
  perform pg_temp.ok(pg_temp.approve(v) like 'Held (E13, incomplete read): %no waiting row covers%', 'approval refused');
  perform pg_temp.ok(pg_temp.approve(v, pg_temp.rows_of(v, 'A bachelors%')) like 'Held (E13%', 'Approve except cannot release a lost minimum');
  perform pg_temp.ok((select count(*) from catalogue.course_entry_requirements where provenance->>'review_item_id' = v::text and status = 'proposed') = 1, 'nothing changed');
  raise notice 'PASS uncovered dropped minimums hold the read';
end $t$;

-- [shape of AUT 6a562cff-daab-41ec-a3ed-78faa6173291 Diploma in Design: the dropped score row repeats a kept row's quote: covered, not lost]
do $t$ declare v uuid; g jsonb; begin
  v := pg_temp.read('c0000000-0000-4000-8000-000000000001', jsonb_build_array(
         pg_temp.r('prior_qualification', 'NCEA Level 2 with 12 credits in each of three subjects, and a portfolio of creative work'),
         pg_temp.r('minimum_grade', 'NCEA Level 2 with 12 credits in each of three subjects', 12, 'credits at Level 3')));
  g := pg_temp.gate(v);
  perform pg_temp.ok((g->>'complete')::boolean, 'a covered drop does not hold: ' || (g->'reasons')::text);
  perform pg_temp.ok((g->>'drops_covered')::int = 1, 'the covered drop is counted');
  raise notice 'PASS a dropped duplicate of a kept row is not a lost requirement';
end $t$;

-- [shape of Monash 1ee33f6e-c36f-48cc-99ae-9d00a0adbbf9: the whole read is course description text]
do $t$ declare v uuid; g jsonb; begin
  v := pg_temp.read('c0000000-0000-4000-8000-000000000002', jsonb_build_array(
         pg_temp.r('prior_qualification', 'This is a postgraduate course that equips registered health care practitioners with advanced skills')));
  g := pg_temp.gate(v);
  perform pg_temp.ok(not (g->>'complete')::boolean and jsonb_array_length(g->'not_requirement') = 1, 'description text held');
  perform pg_temp.ok(pg_temp.approve(v) like 'Held (E13%not entry requirements%', 'approval refused');
  raise notice 'PASS non-requirement rows hold approval';
end $t$;

-- [shape of MIT 27757e93-8dd4-459a-a45e-01c604b21490: "Open entry for domestic students" stored for every applicant]
do $t$ declare v uuid; g jsonb; begin
  v := pg_temp.read('c0000000-0000-4000-8000-000000000003', jsonb_build_array(
         pg_temp.r('override', 'Open entry for domestic students. There are no academic requirements for this programme'),
         pg_temp.r('general_note', 'Applicants must be at least 16 years old')));
  g := pg_temp.gate(v);
  perform pg_temp.ok(not (g->>'complete')::boolean and jsonb_array_length(g->'audience') = 1, 'domestic route stored as all is held');
  perform pg_temp.ok(pg_temp.approve(v, pg_temp.rows_of(v, 'Open entry%')) is null, 'Approve except of that row releases it');
  perform pg_temp.ok((select status from catalogue.course_entry_requirements where provenance->>'review_item_id' = v::text and quote like 'Applicants must%') = 'active', 'the rest admitted');
  raise notice 'PASS domestic routes stored for everyone are held until left out';
end $t$;

-- [shape of AUT e0944462-2cd5-4f80-bad9-d041cf6d5c9a: an English competency note the B1 filter does not catch]
do $t$ declare v uuid; g jsonb; begin
  v := pg_temp.read('c0000000-0000-4000-8000-000000000004', jsonb_build_array(
         pg_temp.r('general_note', 'High level of competency in English (NZSL fluency is not required)'),
         pg_temp.r('minimum_grade', 'You need to complete Year 1 courses with at least a B grade average')));
  g := pg_temp.gate(v);
  perform pg_temp.ok(not (g->>'complete')::boolean, 'English note held');
  perform pg_temp.ok((pg_temp.gate(v, pg_temp.rows_of(v, 'High level%'))->>'complete')::boolean, 'left out, the read is whole');
  raise notice 'PASS English notes are held until left out';
end $t$;

-- [shape of VUW cf6ac55c-8e38-4e73-aa67-d19337e4e4df: a clean read stays approvable]
do $t$ declare v uuid; begin
  v := pg_temp.read('c0000000-0000-4000-8000-000000000005', jsonb_build_array(
         pg_temp.r('prior_qualification', 'A BE(Hons) degree with First or Second Class Honours or the equivalent')));
  perform pg_temp.ok((pg_temp.gate(v)->>'complete')::boolean, 'clean read whole');
  perform pg_temp.ok(pg_temp.approve(v) is null, 'clean read approves');
  raise notice 'PASS a clean read is unchanged';
end $t$;

-- ------------------------------------------------------------------ D-R2: a corrected read replaces a waiting one, whole or not at all
do $t$ declare v1 uuid; v2 uuid; q jsonb; e bigint; o text; d jsonb; begin
  -- the waiting read: incomplete (its score row is dropped as score_without_basis: the basis words are not in the quote)
  v1 := pg_temp.read('c0000000-0000-4000-8000-000000000007', jsonb_build_array(
          pg_temp.r('prior_qualification', 'A relevant bachelors degree'),
          pg_temp.r('minimum_grade', 'with a B average or higher', 5, 'grade point average')));
  perform pg_temp.ok(not (pg_temp.gate(v1)->>'complete')::boolean, 'the waiting read is incomplete');
  -- an ordinary second read is still refused while it waits
  insert into pipeline.field_enrich_items(provider_id, course_id, state) values ('d1000000-0000-4000-8000-000000000000', 'c0000000-0000-4000-8000-000000000007', 'ai') returning id into e;
  perform pg_temp.ok(pg_temp.record(e, jsonb_build_array(pg_temp.r('prior_qualification', 'A relevant bachelors degree'))) = 'already', 'an ordinary read is refused');
  -- a correction is asked, and its read is still incomplete: nothing changes, the request is refused
  q := security.course_entry_correction_v1(v1, '99999999-0000-4000-8000-000000000000', 'quote and basis fixed (R2/R3)');
  o := pg_temp.record((q->>'enrich_item_id')::bigint, jsonb_build_array(
          pg_temp.r('prior_qualification', 'A relevant bachelors degree'),
          pg_temp.r('minimum_grade', 'with a B average or higher', 5, 'grade point average')));
  perform pg_temp.ok(o = 'not_admitted', 'an incomplete correction is refused (' || o || ')');
  perform pg_temp.ok((select status from pipeline.layer4_review_items where id = v1) = 'pending', 'the waiting read still waits');
  perform pg_temp.ok((select count(*) from catalogue.course_entry_requirements where provenance->>'review_item_id' = v1::text and status = 'proposed') = 1, 'its rows untouched');
  perform pg_temp.ok((select state || ':' || outcome from pipeline.aer_read_supersessions where id = (q->>'request_id')::uuid) like 'refused:%still drops%', 'the request is recorded as refused');
  -- a complete correction: one transaction supersedes the waiting item and opens the new one, pending, with the diff
  q := security.course_entry_correction_v1(v1, '99999999-0000-4000-8000-000000000000', 'quote and basis fixed (R2/R3), second attempt');
  o := pg_temp.record((q->>'enrich_item_id')::bigint, jsonb_build_array(
          pg_temp.r('prior_qualification', 'A relevant bachelors degree'),
          pg_temp.r('minimum_grade', 'with a grade point average of 5 or higher', 5, 'grade point average')));
  perform pg_temp.ok(o = 'review', 'a complete correction opens a review (' || o || ')');
  v2 := (select new_item_id from pipeline.aer_read_supersessions where id = (q->>'request_id')::uuid);
  perform pg_temp.ok((select status from pipeline.layer4_review_items where id = v1) = 'superseded', 'the old item is superseded');
  perform pg_temp.ok((select status from pipeline.layer4_review_items where id = v2) = 'pending', 'the new item waits for a person (no automatic approval)');
  perform pg_temp.ok((select count(*) from pipeline.layer4_review_items where entity_id = 'c0000000-0000-4000-8000-000000000007' and status = 'pending') = 1, 'exactly one waiting read');
  perform pg_temp.ok((select count(*) from catalogue.course_entry_requirements where provenance->>'review_item_id' = v1::text and status = 'inactive' and status_reason like 'quarantined (superseded)%') = 1,
                     'old rows kept, quarantined: ' || (select string_agg(status || '/' || coalesce(status_reason, ''), '; ') from catalogue.course_entry_requirements where provenance->>'review_item_id' = v1::text));
  perform pg_temp.ok((select count(*) from catalogue.course_entry_requirements where status = 'active' and course_id = 'c0000000-0000-4000-8000-000000000007') = 0, 'nothing admitted');
  d := (select proposed_value->'supersedes' from pipeline.layer4_review_items where id = v2);
  perform pg_temp.ok(d->>'review_item_id' = v1::text and (d->>'unchanged')::int = 1 and jsonb_array_length(d->'added') = 1 and jsonb_array_length(d->'removed') = 0
                     and d->'dropped_before' ? 'score_without_basis' and d->'dropped_after' = '{}'::jsonb, 'the diff: ' || d::text);
  perform pg_temp.ok((pg_temp.gate(v2)->>'complete')::boolean, 'the corrected read is whole');
  perform pg_temp.ok(security.aer_review_read_v1(v2)->'supersedes'->>'review_item_id' = v1::text, 'the review screen shows what it replaced');
  perform pg_temp.ok(security.aer_review_read_v1(v1)->'superseded_by'->>'review_item_id' = v2::text, 'the old item names its replacement');
  raise notice 'PASS a complete corrected read supersedes the waiting read atomically; an incomplete one changes nothing';
end $t$;

-- decisions, claims, locks and the page are protected
do $t$ declare v uuid; m text; begin
  v := pg_temp.read('c0000000-0000-4000-8000-000000000008', jsonb_build_array(pg_temp.r('prior_qualification', 'A bachelors degree in social sciences')));
  update pipeline.layer4_review_items set claimed_at = now() where id = v;
  begin perform security.course_entry_correction_v1(v, null, 'try while claimed'); m := null; exception when sqlstate '55000' then m := sqlerrm; end;
  perform pg_temp.ok(m like '%a reviewer claimed it%', 'a claimed item is protected: ' || coalesce(m, 'not refused'));
  update pipeline.layer4_review_items set claimed_at = now() - interval '2 days' where id = v;  -- fixed: fixture time
  insert into pipeline.manual_locks values ('course', 'c0000000-0000-4000-8000-000000000008', 'entry_requirements');
  begin perform security.course_entry_correction_v1(v, null, 'try while locked'); m := null; exception when sqlstate '55000' then m := sqlerrm; end;
  perform pg_temp.ok(m like '%manual lock%', 'a locked course is protected');
  delete from pipeline.manual_locks;
  update pipeline.coverage_course_pages set url = 'https://uni.example/moved' where course_id = 'c0000000-0000-4000-8000-000000000008';
  begin perform security.course_entry_correction_v1(v, null, 'try after the page moved'); m := null; exception when sqlstate '55000' then m := sqlerrm; end;
  perform pg_temp.ok(m like '%not the page of the waiting read%', 'another page is a new first read, not a correction');
  update pipeline.coverage_course_pages set url = 'https://uni.example/c0000000-0000-4000-8000-000000000008' where course_id = 'c0000000-0000-4000-8000-000000000008';
  insert into pipeline.layer4_decisions(review_item_id, action, reason) values (v, 'approve', 'a person decided');
  begin perform security.course_entry_correction_v1(v, null, 'try after a decision'); m := null; exception when sqlstate '55000' then m := sqlerrm; end;
  perform pg_temp.ok(m like '%a person has decided it%', 'a decided item is protected');
  raise notice 'PASS decisions, claims, locks and the bound page are protected';
end $t$;

-- a correction whose waiting read was decided meanwhile is refused; history is immutable; one waiting read per course
do $t$ declare v uuid; q jsonb; o text; m text; begin
  v := pg_temp.read('c0000000-0000-4000-8000-000000000009', jsonb_build_array(pg_temp.r('prior_qualification', 'A bachelors degree in nursing')));
  q := security.course_entry_correction_v1(v, null, 'decided before the read returns');
  update pipeline.layer4_review_items set status = 'approved' where id = v;
  o := pg_temp.record((q->>'enrich_item_id')::bigint, jsonb_build_array(pg_temp.r('prior_qualification', 'A bachelors degree in nursing, registered')));
  perform pg_temp.ok(o = 'not_admitted' and (select state from pipeline.aer_read_supersessions where id = (q->>'request_id')::uuid) = 'refused', 'decided meanwhile: refused');
  perform pg_temp.ok((select count(*) from pipeline.layer4_review_items where entity_id = 'c0000000-0000-4000-8000-000000000009' and status = 'pending') = 0, 'no new item');
  begin update pipeline.aer_read_supersessions set reason = 'rewritten' where id = (q->>'request_id')::uuid; m := null; exception when sqlstate '42501' then m := sqlerrm; end;
  perform pg_temp.ok(m like 'D-R2 history is kept%', 'a closed record cannot be rewritten');
  begin delete from pipeline.aer_read_supersessions where id = (q->>'request_id')::uuid; m := null; exception when sqlstate '42501' then m := sqlerrm; end;
  perform pg_temp.ok(m like 'D-R2 history is kept%', 'a record cannot be deleted');
  begin
    insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status) values ('course', 'c0000000-0000-4000-8000-000000000008', 'course_entry_first_read', 'pending');
    m := null;
  exception when unique_violation then m := 'unique';
  end;
  perform pg_temp.ok(m = 'unique', 'a second waiting read of one course is refused by the index');
  raise notice 'PASS decided-meanwhile refusal, immutable history, one waiting read per course';
end $t$;

-- ------------------------------------------------------------------ D-R3: matrix runs
create function pg_temp.run(p_run uuid, p_item uuid, p_hash text, p_rows jsonb, p_dropped jsonb default '[]', p_outcome text default null) returns void language plpgsql as $f$
begin
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status) values (p_item, 'provider', 'e2000000-0000-4000-8000-000000000000', 'entry_matrix_first_run', 'pending');
  insert into pipeline.entry_matrix_runs(id, review_item_id, provider_id, source_id, content_hash, state, rows_admitted, rows_dropped, result)
  values (p_run, p_item, 'e2000000-0000-4000-8000-000000000000', 'e3000000-0000-4000-8000-000000000000', p_hash, 'done', jsonb_array_length(p_rows), jsonb_array_length(p_dropped),
          jsonb_build_object('dropped', p_dropped, 'completeness', jsonb_build_object('status', 'not_applicable')) || case when p_outcome is not null then jsonb_build_object('outcome', p_outcome) else '{}'::jsonb end);
  insert into catalogue.provider_entry_matrix(id, run_id, provider_id, source_id, content_hash, status, country_code, qualification_name, min_grade, min_value, grade_scale, benchmark_band, quote, row_hash)
  select coalesce((x->>'id')::uuid, gen_random_uuid()), p_run, 'e2000000-0000-4000-8000-000000000000', 'e3000000-0000-4000-8000-000000000000', p_hash, 'proposed', x->>'cc', x->>'q', x->>'g',
         (x->>'v')::numeric, coalesce(x->>'s', 'none'), x->>'b', x->>'quote', coalesce(x->>'h', md5(x::text))
    from jsonb_array_elements(p_rows) x;
end $f$;
create function pg_temp.mx_approve(p_item uuid, p_exclude uuid[] default '{}') returns text language plpgsql as $f$
begin
  perform security.entry_matrix_review_apply_v1(p_item, 'approve',
    case when cardinality(p_exclude) > 0 then jsonb_build_object('mode', 'approve_except', 'exclude_row_ids', to_jsonb(p_exclude), 'reviewer', 'fixture') end, 'fixture decision');
  return null;
exception when sqlstate '55000' then return sqlerrm;
end $f$;
create function pg_temp.mgate(p_item uuid, p_exclude uuid[] default '{}') returns jsonb language sql as $f$
  select security.entry_matrix_gate_v1((select id from pipeline.entry_matrix_runs where review_item_id = p_item), p_exclude) $f$;
insert into pipeline.entry_matrix_sources(id, provider_id, content_hash) values ('e3000000-0000-4000-8000-000000000000', 'e2000000-0000-4000-8000-000000000000', 'h1');

-- [shape of UWA a0595bd2-740a-48fd-bb88-596749e6727c: every China Gaokao row dropped (value_not_in_quote on a score range), AP subjects share one identity]
do $t$ declare g jsonb; m text; begin
  perform pg_temp.run('f0000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'h1', jsonb_build_array(
    jsonb_build_object('id', 'b1000000-0000-4000-8000-000000000001', 'cc', 'GB', 'q', 'GCE A Levels', 'g', '9', 'v', 9, 's', 'points', 'b', '70', 'quote', '9 | 70% | 70 GCE A Levels'),
    jsonb_build_object('id', 'b1000000-0000-4000-8000-000000000002', 'cc', 'US', 'q', 'US College Board Advanced Placement (AP)', 'g', '3 or higher', 'v', 3, 's', 'points', 'quote', 'Chemistry | Chemistry; 3 or higher', 'h', 'ap'),
    jsonb_build_object('id', 'b1000000-0000-4000-8000-000000000003', 'cc', 'US', 'q', 'US College Board Advanced Placement (AP)', 'g', '3 or higher', 'v', 3, 's', 'points', 'quote', 'Biology | Biology; 3 or higher', 'h', 'ap')),
    jsonb_build_array(jsonb_build_object('reason', 'value_not_in_quote', 'country', 'CN', 'quote', '488 to 491 | 65% | 70'),
                      jsonb_build_object('reason', 'value_not_in_quote', 'country', 'CN', 'quote', '675 to 689 | 90% | 98')));
  g := pg_temp.mgate('a1000000-0000-4000-8000-000000000001');
  perform pg_temp.ok(not (g->>'complete')::boolean, 'UWA shape held');
  perform pg_temp.ok(g->'countries_missing' = '["CN"]'::jsonb and jsonb_array_length(g->'dropped_lost') = 2, 'China named as left with no row: ' || g::text);
  perform pg_temp.ok(jsonb_array_length(g->'same_identity') = 1 and not (g->>'except_fixable')::boolean, 'shared identity named; not fixable by exclusion');
  m := pg_temp.mx_approve('a1000000-0000-4000-8000-000000000001');
  perform pg_temp.ok(m like 'Held (D-R3, incomplete read): %left with no row at all: CN%', 'approval refused: ' || coalesce(m, 'approved'));
  perform pg_temp.ok(pg_temp.mx_approve('a1000000-0000-4000-8000-000000000001', array['b1000000-0000-4000-8000-000000000003'::uuid]) like 'Held (D-R3%', 'Approve except refused too');
  perform pg_temp.ok((select count(*) from catalogue.provider_entry_matrix where run_id = 'f0000000-0000-4000-8000-000000000001' and status = 'proposed') = 3, 'nothing changed');
  raise notice 'PASS UWA shape: 177 rows without China cannot be approved';
end $t$;

-- [shapes of ANU cad93a9a-6551-4fae-a507-20e5d3f01d0b (rank stored as minimum), 02bc7d80-b0f9-4b48-9d64-5713535f66cc (qualification named by the rank
--  label) and d01d7b4f-4c3a-48dc-8718-cbcbf56717c5 (band holds label text)]
do $t$ declare g jsonb; begin
  perform pg_temp.run('f0000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000002', 'h1', jsonb_build_array(
    jsonb_build_object('cc', 'BE', 'q', 'Belgium Certificate of Access to Higher Education', 'g', 'Program Required Entrance Rank: 80', 'v', 80, 's', 'rank', 'b', '13',
                       'quote', 'Program Required Entrance Rank: 80 | Indicative score required: 13')));
  g := pg_temp.mgate('a1000000-0000-4000-8000-000000000002');
  perform pg_temp.ok(not (g->>'complete')::boolean and g->'flagged'->0->>'why' = 'the provider''s rank is stored as the qualification''s minimum', 'rank as minimum: ' || g::text);
  perform pg_temp.run('f0000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000003', 'h1', jsonb_build_array(
    jsonb_build_object('cc', 'BE', 'q', 'Program Required Entrance Rank: 70', 'g', '68', 'v', 68, 's', 'points', 'b', '70', 'quote', 'Program Required Entrance Rank: 70 | Indicative score required: 68')));
  perform pg_temp.ok(pg_temp.mgate('a1000000-0000-4000-8000-000000000003')->'flagged'->0->>'why' = 'qualification named by a column label', 'column label as qualification');
  -- [shape of ANU 987dac71-a146-495e-b3b4-02a40854a50a: a header-row ladder ("Rank | Indicative score required" then "70 | 43") with the rank stored as a percentage minimum]
  perform pg_temp.run('f0000000-0000-4000-8000-00000000000a', 'a1000000-0000-4000-8000-00000000000a', 'h1', jsonb_build_array(
    jsonb_build_object('cc', 'BA', 'q', 'Bosnia & Herzegovina Secondary School Leaving Certificate', 'g', '70', 'v', 70, 's', 'percentage', 'b', '43',
                       'quote', E'Program Required Entrance Rank | Indicative score required\n70 | 43')));
  perform pg_temp.ok(pg_temp.mgate('a1000000-0000-4000-8000-00000000000a')->'flagged'->0->>'why' = 'the provider''s rank is stored as the qualification''s minimum', 'header-row ladder inverted');
  perform pg_temp.run('f0000000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-000000000004', 'h1', jsonb_build_array(
    jsonb_build_object('id', 'b1000000-0000-4000-8000-000000000041', 'cc', 'US', 'q', 'USA American College Test (ACT)', 'g', '20', 'v', 20, 's', 'points', 'b', 'ANU Entrance Rank: 70',
                       'quote', 'ANU Entrance Rank: 70 | Indicative score required: 20'),
    jsonb_build_object('id', 'b1000000-0000-4000-8000-000000000042', 'cc', 'US', 'q', 'USA American College Test (ACT)', 'g', '23', 'v', 23, 's', 'points', 'b', '80',
                       'quote', 'ANU Entrance Rank: 80 | Indicative score required: 23')));
  g := pg_temp.mgate('a1000000-0000-4000-8000-000000000004');
  perform pg_temp.ok(not (g->>'complete')::boolean and (g->>'except_fixable')::boolean and g->'flagged'->0->>'why' = 'the band holds label text, not a band', 'label band, fixable');
  perform pg_temp.ok(pg_temp.mx_approve('a1000000-0000-4000-8000-000000000004') like 'Held (D-R3%', 'approve refused');
  perform pg_temp.ok(pg_temp.mx_approve('a1000000-0000-4000-8000-000000000004', array['b1000000-0000-4000-8000-000000000041'::uuid]) is null, 'Approve except of the flagged row admits the rest');
  perform pg_temp.ok((select status from catalogue.provider_entry_matrix where id = 'b1000000-0000-4000-8000-000000000042') = 'active', 'the whole row admitted');
  raise notice 'PASS ANU ladder shapes: rank as minimum, label as qualification, label as band';
end $t$;

-- [shape of VUW f6941f3d-0e0e-4528-b918-0736618af419: a zero-row "no table" page whose global qualification rows were dropped; and a true empty page]
do $t$ declare m text; begin
  perform pg_temp.run('f0000000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-000000000005', 'h1', '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('reason', 'unknown_country', 'country', 'INT', 'quote', 'IB (International Baccalaureate) Diploma: Minimum 24 points')), 'no_requirements_table');
  m := pg_temp.mx_approve('a1000000-0000-4000-8000-000000000005');
  perform pg_temp.ok(m like 'Held (D-R3%unknown_country 1%', '"no matrix published" refused when rows were dropped: ' || coalesce(m, 'approved'));
  perform pg_temp.run('f0000000-0000-4000-8000-000000000006', 'a1000000-0000-4000-8000-000000000006', 'h1', '[]'::jsonb, '[]'::jsonb, 'no_requirements_table');
  perform pg_temp.ok((pg_temp.mgate('a1000000-0000-4000-8000-000000000006')->>'no_table')::boolean, 'an empty page is shown as a no-table read');
  perform pg_temp.ok(pg_temp.mx_approve('a1000000-0000-4000-8000-000000000006') is null, 'an empty page with nothing dropped can still be confirmed by a person');
  raise notice 'PASS zero-row pages: dropped rows prove a table exists';
end $t$;

-- a whole run approves; a covered drop does not hold; a stale copy and changed rows hold; reject and the automatic path are unchanged
do $t$ declare g jsonb; m text; begin
  perform pg_temp.run('f0000000-0000-4000-8000-000000000007', 'a1000000-0000-4000-8000-000000000007', 'h1', jsonb_build_array(
    jsonb_build_object('cc', 'IN', 'q', 'Indian State Board Examination', 'g', '85', 'v', 85, 's', 'points', 'quote', 'Design | 85 | English'),
    jsonb_build_object('cc', 'IN', 'q', 'Indian State Board Examination', 'g', '90', 'v', 90, 's', 'points', 'quote', 'Biomedicine | 90 | English, Chemistry and Mathematics')),
    jsonb_build_array(jsonb_build_object('reason', 'quote_not_on_page', 'country', 'IN', 'quote', 'Biomedicine | 90 | English, Chemistry')));
  g := pg_temp.mgate('a1000000-0000-4000-8000-000000000007');
  perform pg_temp.ok((g->>'complete')::boolean and (g->>'dropped_covered')::int = 1, 'whole, the drop covered: ' || g::text);
  perform pg_temp.ok(pg_temp.mx_approve('a1000000-0000-4000-8000-000000000007') is null, 'a whole run approves');
  perform pg_temp.ok((select count(*) from catalogue.provider_entry_matrix where run_id = 'f0000000-0000-4000-8000-000000000007' and status = 'active') = 2, 'rows active');
  perform pg_temp.run('f0000000-0000-4000-8000-000000000008', 'a1000000-0000-4000-8000-000000000008', 'h0', jsonb_build_array(
    jsonb_build_object('cc', 'IN', 'q', 'Indian State Board Examination', 'g', '75', 'v', 75, 's', 'points', 'quote', 'Agriculture | 75 | English and Mathematics')));
  perform pg_temp.ok(pg_temp.mx_approve('a1000000-0000-4000-8000-000000000008') like 'Held (D-R3%current stored copy%', 'a stale copy is held');
  perform security.entry_matrix_review_apply_v1(null, 'approve', null, 'automatic path', 'f0000000-0000-4000-8000-000000000008');  -- no Layer 4 item: unchanged
  perform pg_temp.run('f0000000-0000-4000-8000-000000000009', 'a1000000-0000-4000-8000-000000000009', 'h1', jsonb_build_array(
    jsonb_build_object('id', 'b1000000-0000-4000-8000-000000000091', 'cc', 'IN', 'q', 'Indian State Board Examination', 'g', '93', 'v', 93, 's', 'points', 'quote', 'Commerce | 93 | English and Mathematics'),
    jsonb_build_object('cc', 'IN', 'q', 'Indian State Board Examination', 'g', '95', 'v', 95, 's', 'points', 'quote', 'Oral Health | 95 | English and one of Biology or Chemistry')));
  update catalogue.provider_entry_matrix set status = 'inactive' where id = 'b1000000-0000-4000-8000-000000000091';
  perform pg_temp.ok(pg_temp.mx_approve('a1000000-0000-4000-8000-000000000009') like 'Held (D-R3%rows changed since the read%', 'rows changed since the read are held');
  perform security.entry_matrix_review_apply_v1('a1000000-0000-4000-8000-000000000009', 'rejected', null, 'reject unchanged');
  perform pg_temp.ok((select count(*) from catalogue.provider_entry_matrix where run_id = 'f0000000-0000-4000-8000-000000000009' and status = 'proposed') = 0, 'reject still quarantines');
  perform pg_temp.ok((security.aer_review_read_v1('a1000000-0000-4000-8000-000000000001')->'completeness_gate'->>'rule') = 'D-R3', 'the review screen shows the matrix gate');
  raise notice 'PASS whole run approves; stale and changed runs held; reject and automatic path unchanged';
end $t$;
