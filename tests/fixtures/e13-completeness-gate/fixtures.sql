-- Guards: E13 (Platform Admin 2 Nov 2026 05:18): the whole-read completeness gate on isolated fixtures.
-- Runs after stubs.sql, the rebuilt live definitions (before.mjs) and the E13 migration (see run.sh). Every block raises on a failed check;
-- each passing block prints "PASS <name>". Fixture names follow the E14 cases (EIT combined pages, a Monash joined condition) but no live
-- data is used.
\set ON_ERROR_STOP 1
set client_min_messages = notice;

create function pg_temp.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is distinct from true then raise exception 'FAIL: %', p_what; end if; end $f$;
-- one requirement row as the worker sends it
create function pg_temp.r(p_kind text, p_quote text, p_conf numeric default 0.95) returns jsonb language sql as $f$
  select jsonb_build_object('kind', p_kind, 'audience', 'all', 'description', p_quote, 'min_entry_score', null, 'min_entry_score_basis', null,
                            'benchmark_band', null, 'min_grade', null, 'confidence', p_conf, 'quote', p_quote) $f$;
-- a read of one course: an enrich item, then the worker's result recorded by the reader
create function pg_temp.read(p_course uuid, p_rows jsonb) returns table(outcome text, item bigint) language plpgsql as $f$
declare v_id bigint;
begin
  insert into pipeline.field_enrich_items(provider_id, course_id, state) select c.provider_id, c.id, 'ai' from catalogue.courses c where c.id = p_course returning id into v_id;
  return query select security.enrich_entry_record_v1(v_id, jsonb_build_object('value', jsonb_build_object('rows', p_rows, 'dropped', '[]'::jsonb), 'model', 'fixture')), v_id;
end $f$;
-- approval as the Layer 4 decision calls it; returns the refusal message, or null when approved
create function pg_temp.approve(p_item uuid, p_exclude uuid[] default '{}') returns text language plpgsql as $f$
begin
  perform security.course_entry_review_apply_v1(p_item, 'approve',
    case when cardinality(p_exclude) > 0 then jsonb_build_object('mode', 'approve_except', 'exclude_row_ids', to_jsonb(p_exclude), 'reviewer', 'fixture') end, 'fixture decision');
  return null;
exception when sqlstate '55000' then return sqlerrm;
end $f$;

-- providers and courses: an institute with combined pages (EIT-like) and a university (Monash-like)
insert into catalogue.courses(id, provider_id, canonical_title) values
 ('a0000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000000', 'Postgraduate Certificate in Information Technology (Level 8)'),
 ('a0000000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000000', 'Postgraduate Diploma in Information Technology (Level 8)'),
 ('a0000000-0000-4000-8000-000000000003', 'e1000000-0000-4000-8000-000000000000', 'Master of Information Technology (180) (Level 9)'),
 ('a0000000-0000-4000-8000-000000000004', 'e1000000-0000-4000-8000-000000000000', 'Master of Information Technology (240) (Level 9)'),
 ('a0000000-0000-4000-8000-000000000005', 'e1000000-0000-4000-8000-000000000000', 'Master of Digital Business (180) (Level 9)'),
 ('a0000000-0000-4000-8000-000000000006', 'e1000000-0000-4000-8000-000000000000', 'Postgraduate Diploma in Digital Business (Level 8)'),
 ('a0000000-0000-4000-8000-000000000007', 'e1000000-0000-4000-8000-000000000000', 'Master of Digital Business (240) (Level 9)'),
 ('b0000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000000', 'Master of Clinical Research'),
 ('b0000000-0000-4000-8000-000000000002', 'f1000000-0000-4000-8000-000000000000', 'Master of Public Health'),
 ('b0000000-0000-4000-8000-000000000003', 'f1000000-0000-4000-8000-000000000000', 'Master of Nursing Practice'),
 ('b0000000-0000-4000-8000-000000000004', 'f1000000-0000-4000-8000-000000000000', 'Master of Arts'),
 ('b0000000-0000-4000-8000-000000000005', 'f1000000-0000-4000-8000-000000000000', 'Bachelor of Arts'),
 ('b0000000-0000-4000-8000-000000000006', 'f1000000-0000-4000-8000-000000000000', 'Bachelor of Education - (Early Childhood Teaching)'),
 ('b0000000-0000-4000-8000-000000000007', 'f1000000-0000-4000-8000-000000000000', 'Bachelor of Education (Early Childhood Teaching) (Level 7)'),
 ('b0000000-0000-4000-8000-000000000008', 'f1000000-0000-4000-8000-000000000000', 'Master of Social Work');
-- every course has its own page, except the two Digital Business masters (one combined page) and the two records of one education degree
insert into pipeline.coverage_course_pages(course_id, provider_id, url)
select c.id, c.provider_id, case when c.id in ('a0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000007') then 'https://eit.example/master-of-digital-business/'
                                 when c.id in ('b0000000-0000-4000-8000-000000000006', 'b0000000-0000-4000-8000-000000000007') then 'https://uni.example/bed-early-childhood/'
                                 else 'https://example/' || c.id end
  from catalogue.courses c;

-- ------------------------------------------------------------------ settings: registered for Settings > Pipeline settings (G2)
do $t$ begin
  perform pg_temp.ok((select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('entry.max_rows_by_provider', 'entry.joined_condition_words',
            'entry.joined_condition_kinds', 'entry.variant_check', 'entry.shared_page_hold', 'entry.variant_check_off_providers', 'entry.award_abbreviations')
            and label is not null and unit is not null and used_by is not null and section = 'Entry requirements') = 7, 'seven settings with label, unit, used_by');
  perform pg_temp.ok((select count(*) from pipeline.platform_toolset_settings where key in ('entry.variant_check', 'entry.shared_page_hold') and min_value = 0 and max_value = 1 and value = '1'::jsonb) = 2, 'on/off settings ranged 0-1, on');
  perform pg_temp.ok((select value from pipeline.platform_toolset_settings where key = 'entry.max_rows_per_course') = '6'::jsonb, 'the global cap is unchanged (6)');
  raise notice 'PASS settings';
end $t$;

-- ------------------------------------------------------------------ 1. a clean read is proposed whole and approves
do $t$ declare o text; v_item bigint; v_rev uuid; v_msg text; begin
  select outcome, item into o, v_item from pg_temp.read('b0000000-0000-4000-8000-000000000001', jsonb_build_array(
    pg_temp.r('prior_qualification', 'An Australian bachelor degree (or equivalent) in a health-related discipline'),
    pg_temp.r('work_experience', 'plus a minimum of two years of relevant work experience'),
    pg_temp.r('general_note', 'Applicants must submit a curriculum vitae')));
  perform pg_temp.ok(o = 'review', 'clean read opens a review (' || o || ')');
  select (value->>'review_item_id')::uuid into v_rev from pipeline.field_enrich_items where id = v_item;
  perform pg_temp.ok((select count(*) from catalogue.course_entry_requirements where provenance->>'review_item_id' = v_rev::text and status = 'proposed') = 3, 'three rows proposed');
  perform pg_temp.ok((select (proposed_value->>'limit')::int from pipeline.layer4_review_items where id = v_rev) = 6, 'the item records the limit it was read under');
  perform pg_temp.ok((security.course_entry_gate_v1(v_rev)->>'complete')::boolean, 'gate: complete');
  v_msg := pg_temp.approve(v_rev);
  perform pg_temp.ok(v_msg is null, 'clean read approves: ' || coalesce(v_msg, ''));
  perform pg_temp.ok((select count(*) from catalogue.course_entry_requirements where provenance->>'review_item_id' = v_rev::text and status = 'active') = 3, 'three rows active');
  raise notice 'PASS clean read';
end $t$;

-- ------------------------------------------------------------------ 2. rows over the limit hold the whole read; a joined condition is named
do $t$ declare o text; v_item bigint; i record; begin
  select outcome, item into o, v_item from pg_temp.read('b0000000-0000-4000-8000-000000000002', jsonb_build_array(
    pg_temp.r('prior_qualification', 'A bachelor degree in any discipline'), pg_temp.r('prior_qualification', 'A graduate certificate in public health'),
    pg_temp.r('minimum_grade', 'A weighted average mark of at least 60'), pg_temp.r('general_note', 'Applicants are ranked on academic merit'),
    pg_temp.r('prior_qualification', 'A bachelor degree in a health discipline'), pg_temp.r('prior_qualification', 'An honours degree in science'),
    pg_temp.r('work_experience', 'plus two years of relevant work experience'), pg_temp.r('general_note', 'and a statement of purpose of up to 500 words')));
  select * into i from pipeline.field_enrich_items where id = v_item;
  perform pg_temp.ok(o = 'held_partial', 'over the limit: held (' || o || ')');
  perform pg_temp.ok(i.state = 'skipped' and i.reason like 'held_partial: over_row_limit: the page has 8 requirements and the limit is 6, 2 of those past the limit joined to an earlier requirement%', 'reason: ' || i.reason);
  perform pg_temp.ok(not exists (select 1 from catalogue.course_entry_requirements where course_id = i.course_id), 'no row proposed from a held read');
  perform pg_temp.ok(not exists (select 1 from pipeline.layer4_review_items where entity_id = i.course_id), 'no Layer 4 item from a held read');
  perform pg_temp.ok(jsonb_array_length(i.value->'rows_read') = 8 and i.value->>'held' = 'over_row_limit' and (i.value->>'limit')::int = 6, 'every row read is kept on the item');
  perform pg_temp.ok((select count(*) from jsonb_array_elements(i.value->'dropped') d where d->>'reason' = 'over_row_limit') = 2, 'rows past the limit recorded as over_row_limit');
  raise notice 'PASS over the limit held whole';
end $t$;

-- ------------------------------------------------------------------ 3. provider-specific limit, within the global range only
do $t$ declare o text; v_rows jsonb := '[]'::jsonb; k int; begin
  for k in 1 .. 8 loop v_rows := v_rows || pg_temp.r('prior_qualification', 'Route ' || k || ': a bachelor degree with honours in nursing'); end loop;
  update pipeline.platform_toolset_settings set value = '["f1000000-0000-4000-8000-000000000000=50"]' where key = 'entry.max_rows_by_provider';
  perform pg_temp.ok(security.course_entry_max_rows_v1('f1000000-0000-4000-8000-000000000000') = 6, 'a provider value outside 1-10 is ignored');
  select outcome into o from pg_temp.read('b0000000-0000-4000-8000-000000000003', v_rows);
  perform pg_temp.ok(o = 'held_partial', 'out-of-range provider value: global limit applies, held (' || o || ')');
  update pipeline.platform_toolset_settings set value = '["f1000000-0000-4000-8000-000000000000=10"]' where key = 'entry.max_rows_by_provider';
  perform pg_temp.ok(security.course_entry_max_rows_v1('f1000000-0000-4000-8000-000000000000') = 10 and security.course_entry_max_rows_v1('e1000000-0000-4000-8000-000000000000') = 6, 'provider limit 10, others 6');
  select outcome into o from pg_temp.read('b0000000-0000-4000-8000-000000000003', v_rows);
  perform pg_temp.ok(o = 'review', 'provider limit 10: 8 rows proposed (' || o || ')');
  perform pg_temp.ok((select count(*) from catalogue.course_entry_requirements where course_id = 'b0000000-0000-4000-8000-000000000003' and status = 'proposed') = 8, 'eight rows proposed');
  update pipeline.platform_toolset_settings set value = '[]' where key = 'entry.max_rows_by_provider';
  raise notice 'PASS provider limit';
end $t$;

-- ------------------------------------------------------------------ 4. sibling programme rows are not proposed and do not count towards the limit
do $t$ declare o text; v_item bigint; v_rev uuid; v_d jsonb; v_rows jsonb := '[]'::jsonb; k int; begin
  select outcome, item into o, v_item from pg_temp.read('a0000000-0000-4000-8000-000000000001', jsonb_build_array(
    pg_temp.r('prior_qualification', 'The academic entry requirement for the PGCertIT is one of the following: A NZQF-listed undergraduate degree (or equivalent) in Information Technology'),
    pg_temp.r('prior_qualification', 'The academic entry requirement for the MIT (240) is one of the following: A NZQF-listed undergraduate degree (or equivalent)'),
    pg_temp.r('prior_qualification', 'Postgraduate Diploma in Information Technology An undergraduate degree in the field of Information Technology.'),
    pg_temp.r('prior_qualification', 'Postgraduate Certificate in Information Technology An undergraduate degree in the field of Information Technology.'),
    pg_temp.r('prior_qualification', 'Completion of the Postgraduate Diploma in Information Technology with a minimum B average')));
  perform pg_temp.ok(o = 'review', 'read with sibling rows opens a review (' || o || ')');
  select value into v_d from pipeline.field_enrich_items where id = v_item;
  v_rev := (v_d->>'review_item_id')::uuid;
  perform pg_temp.ok((select count(*) from catalogue.course_entry_requirements where provenance->>'review_item_id' = v_rev::text) = 3, 'own rows (and a qualification to hold) proposed: 3');
  perform pg_temp.ok((select jsonb_agg(d->>'names' order by d->>'names') from jsonb_array_elements(v_d->'dropped') d where d->>'reason' = 'other_programme')
                     = '["MIT (240)", "Postgraduate Diploma in Information Technology"]'::jsonb, 'sibling rows dropped as other_programme, named: ' || (v_d->'dropped')::text);
  -- six own rows and two sibling rows: within the limit, so proposed
  for k in 1 .. 6 loop v_rows := v_rows || pg_temp.r('prior_qualification', 'Route ' || k || ': an undergraduate degree in computing'); end loop;
  v_rows := v_rows || pg_temp.r('prior_qualification', 'The academic entry requirement for the PGCertIT is: a degree') || pg_temp.r('prior_qualification', 'The academic entry requirement for the MIT (180) is: a degree');
  select outcome into o from pg_temp.read('a0000000-0000-4000-8000-000000000002', v_rows);
  perform pg_temp.ok(o = 'review', 'sibling rows do not count towards the limit (' || o || ')');
  raise notice 'PASS sibling rows at read';
end $t$;

-- ------------------------------------------------------------------ 5. the other-programme check, case by case
do $t$ begin
  perform pg_temp.ok(security.course_entry_variant_v1('a0000000-0000-4000-8000-000000000003', 'The academic entry requirement for the MIT (180) is one of the following: a degree') is null, 'own abbreviation and credit');
  perform pg_temp.ok(security.course_entry_variant_v1('a0000000-0000-4000-8000-000000000003', 'Master of Information Technology (240 Credits) An undergraduate degree or graduate diploma') = 'Master of Information Technology (240)', 'sibling credit in a heading');
  perform pg_temp.ok(security.course_entry_variant_v1('a0000000-0000-4000-8000-000000000001', 'The academic entry requirement for the MIT (240) is one of the following') = 'MIT (240)', 'another award by abbreviation');
  perform pg_temp.ok(security.course_entry_variant_v1('a0000000-0000-4000-8000-000000000005', 'PGDipDigiBus and PGCertDigiBus A NZQF listed undergraduate degree (or equivalent)') = 'PGDipDigiBus', 'abbreviations as a heading');
  perform pg_temp.ok(security.course_entry_variant_v1('a0000000-0000-4000-8000-000000000006', 'A Master of Digital Business applicant who does not meet the entry criteria above may be admitted') = 'Master of Digital Business', 'another programme''s applicants');
  perform pg_temp.ok(security.course_entry_variant_v1('a0000000-0000-4000-8000-000000000001', 'Postgraduate Certificate in Information Technology An undergraduate degree in the field') is null, 'own title as a heading');
  perform pg_temp.ok(security.course_entry_variant_v1('a0000000-0000-4000-8000-000000000003', 'Completion of the Postgraduate Diploma in Information Technology with a minimum B average') is null, 'a programme to hold is not another programme');
  perform pg_temp.ok(security.course_entry_variant_v1('b0000000-0000-4000-8000-000000000004', 'completed the requirements for the Bachelor of Arts from this University, with a Grade Point Average of 5') is null, 'completing a degree is not another programme');
  perform pg_temp.ok(security.course_entry_variant_v1('b0000000-0000-4000-8000-000000000004', 'Bachelor of Arts with a credit average') is null, 'a title followed by lower case is not a heading');
  perform pg_temp.ok(security.course_entry_variant_v1('b0000000-0000-4000-8000-000000000001', 'requirements for the IELTS test') is null, 'not an award abbreviation');
  update pipeline.platform_toolset_settings set value = '["e1000000-0000-4000-8000-000000000000"]' where key = 'entry.variant_check_off_providers';
  perform pg_temp.ok(security.course_entry_variant_v1('a0000000-0000-4000-8000-000000000001', 'The academic entry requirement for the MIT (240) is one of the following') is null, 'provider switched off');
  update pipeline.platform_toolset_settings set value = '[]' where key = 'entry.variant_check_off_providers';
  update pipeline.platform_toolset_settings set value = '0' where key = 'entry.variant_check';
  perform pg_temp.ok(security.course_entry_variant_v1('a0000000-0000-4000-8000-000000000001', 'The academic entry requirement for the MIT (240) is one of the following') is null, 'check switched off');
  update pipeline.platform_toolset_settings set value = '1' where key = 'entry.variant_check';
  raise notice 'PASS other-programme cases';
end $t$;

-- ------------------------------------------------------------------ 6. joined conditions
do $t$ begin
  perform pg_temp.ok(security.course_entry_joined_v1('plus a minimum of two years of relevant work experience', 'prior_qualification'), 'plus');
  perform pg_temp.ok(security.course_entry_joined_v1('and (b) a research proposal approved by the supervisor', 'general_note'), 'and');
  perform pg_temp.ok(security.course_entry_joined_v1('(and) as well as an interview', 'general_note'), 'leading punctuation');
  perform pg_temp.ok(security.course_entry_joined_v1('At least two years in a clinical role', 'work_experience'), 'work experience kind');
  perform pg_temp.ok(not security.course_entry_joined_v1('Android development experience is assumed', 'general_note'), 'a word that only starts with "and"');
  perform pg_temp.ok(not security.course_entry_joined_v1('An undergraduate degree in computing', 'prior_qualification'), '"An" is not "and"');
  raise notice 'PASS joined conditions';
end $t$;

-- ------------------------------------------------------------------ 7. approval refuses a stored read cut by the limit (as the pending items read before E13 are)
do $t$ declare v_rev uuid := gen_random_uuid(); v_row uuid; v_msg text; begin
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, proposed_value, status)
  values (v_rev, 'course', 'b0000000-0000-4000-8000-000000000008', 'course_entry_first_read',
          jsonb_build_object('rows', 1, 'dropped', jsonb_build_array(jsonb_build_object('reason', 'over_row_limit', 'kind', 'work_experience', 'quote', 'plus two years of supervised practice'),
                                                                       jsonb_build_object('reason', 'over_row_limit', 'kind', 'general_note', 'quote', 'Applicants are interviewed'),
                                                                       jsonb_build_object('reason', 'low_confidence', 'kind', 'general_note', 'quote', 'Maybe'))), 'pending');
  insert into catalogue.course_entry_requirements(course_id, kind, audience, description, quote, status, provenance)
  values ('b0000000-0000-4000-8000-000000000008', 'prior_qualification', 'all', 'A bachelor degree', 'A bachelor degree in social science', 'proposed', jsonb_build_object('review_item_id', v_rev)) returning id into v_row;
  v_msg := pg_temp.approve(v_rev);
  perform pg_temp.ok(v_msg like 'Held (E13, incomplete read): the reader cut 2 requirement(s) on this page at its row limit, so the read is incomplete: reject it; 1 of the cut requirement(s) belong to a requirement that was kept (for example "plus two years of supervised practice"). Nothing was changed', 'message: ' || coalesce(v_msg, 'approved'));
  v_msg := pg_temp.approve(v_rev, array[v_row]);
  perform pg_temp.ok(v_msg like 'Held (E13%', 'Approve except is refused too');
  perform pg_temp.ok((select status from catalogue.course_entry_requirements where id = v_row) = 'proposed', 'nothing changed');
  perform security.course_entry_review_apply_v1(v_rev, 'rejected', null, 'Layer 4 rejected');
  perform pg_temp.ok((select status from catalogue.course_entry_requirements where id = v_row) = 'inactive', 'reject still works');
  raise notice 'PASS approval held: cut read';
end $t$;

-- ------------------------------------------------------------------ 8. approval refuses a waiting row about another programme unless it is left out
do $t$ declare v_rev uuid := gen_random_uuid(); v_own uuid; v_sib uuid; v_msg text; begin
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, proposed_value, status)
  values (v_rev, 'course', 'a0000000-0000-4000-8000-000000000004', 'course_entry_first_read', jsonb_build_object('rows', 2, 'dropped', '[]'::jsonb), 'pending');
  insert into catalogue.course_entry_requirements(course_id, kind, audience, description, quote, status, provenance) values
   ('a0000000-0000-4000-8000-000000000004', 'prior_qualification', 'all', 'own', 'The academic entry requirement for the MIT (240) is one of the following: a degree', 'proposed', jsonb_build_object('review_item_id', v_rev))
  returning id into v_own;
  insert into catalogue.course_entry_requirements(course_id, kind, audience, description, quote, status, provenance) values
   ('a0000000-0000-4000-8000-000000000004', 'prior_qualification', 'all', 'sibling', 'The academic entry requirement for the MIT (180) is one of the following: a Bachelor Honours degree', 'proposed', jsonb_build_object('review_item_id', v_rev))
  returning id into v_sib;
  v_msg := pg_temp.approve(v_rev);
  perform pg_temp.ok(v_msg like '%1 waiting row(s) are about another programme (MIT (180)): leave them out with Approve except, or reject the read%', 'message: ' || coalesce(v_msg, 'approved'));
  perform pg_temp.ok((security.course_entry_gate_v1(v_rev, array[v_sib])->>'complete')::boolean, 'leaving the row out completes the read');
  v_msg := pg_temp.approve(v_rev, array[v_sib]);
  perform pg_temp.ok(v_msg is null, 'Approve except leaving it out is accepted: ' || coalesce(v_msg, ''));
  perform pg_temp.ok((select status from catalogue.course_entry_requirements where id = v_own) = 'active' and (select status from catalogue.course_entry_requirements where id = v_sib) = 'inactive', 'own row active, sibling row left out');
  raise notice 'PASS approval held: other programme';
end $t$;

-- ------------------------------------------------------------------ 9. a page shared with a differently named programme holds approval
do $t$ declare v_rev uuid := gen_random_uuid(); v_rev2 uuid := gen_random_uuid(); v_msg text; begin
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, proposed_value, status)
  values (v_rev, 'course', 'a0000000-0000-4000-8000-000000000005', 'course_entry_first_read', jsonb_build_object('rows', 1, 'dropped', '[]'::jsonb), 'pending'),
         (v_rev2, 'course', 'b0000000-0000-4000-8000-000000000006', 'course_entry_first_read', jsonb_build_object('rows', 1, 'dropped', '[]'::jsonb), 'pending');
  insert into catalogue.course_entry_requirements(course_id, kind, audience, description, quote, status, provenance) values
   ('a0000000-0000-4000-8000-000000000005', 'prior_qualification', 'all', 'a', 'A Bachelor Honours degree with 120 credits at Level 8', 'proposed', jsonb_build_object('review_item_id', v_rev)),
   ('b0000000-0000-4000-8000-000000000006', 'prior_qualification', 'all', 'b', 'A teaching qualification', 'proposed', jsonb_build_object('review_item_id', v_rev2));
  v_msg := pg_temp.approve(v_rev);
  perform pg_temp.ok(v_msg like '%the stored page is also the page of 1 other programme(s) (Master of Digital Business (240) (Level 9)), so its rows cannot be told apart by programme: reject the read%', 'message: ' || coalesce(v_msg, 'approved'));
  perform pg_temp.ok(pg_temp.approve(v_rev2) is null, 'two records of the same programme on one page are not another programme');
  update pipeline.platform_toolset_settings set value = '0' where key = 'entry.shared_page_hold';
  perform pg_temp.ok(pg_temp.approve(v_rev) is null, 'shared-page hold switched off: approves');
  update pipeline.platform_toolset_settings set value = '1' where key = 'entry.shared_page_hold';
  raise notice 'PASS approval held: shared page';
end $t$;

-- ------------------------------------------------------------------ 10. the review screen carries the gate
do $t$ declare v_rev uuid := gen_random_uuid(); v jsonb; begin
  insert into auth.session values ('c0000000-0000-4000-8000-000000000001', 6);
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, proposed_value, status)
  values (v_rev, 'course', 'a0000000-0000-4000-8000-000000000003', 'course_entry_first_read',
          jsonb_build_object('rows', 0, 'dropped', jsonb_build_array(jsonb_build_object('reason', 'over_row_limit', 'kind', 'general_note', 'quote', 'and an interview'))), 'pending');
  v := security.aer_review_read_v1(v_rev);
  perform pg_temp.ok(v->'completeness_gate'->>'complete' = 'false' and (v->'completeness_gate'->>'rows_cut')::int = 1 and jsonb_array_length(v->'completeness_gate'->'joined') = 1
                     and jsonb_array_length(v->'completeness_gate'->'reasons') = 2, 'gate on the review read: ' || (v->'completeness_gate')::text);
  raise notice 'PASS review screen';
end $t$;
