-- CF-247 IQ-00111 fixture seed: two countries, the courses of the live cases (titles, lengths and quotes as stored live on 2-3 Nov 2026), and a
-- helper that reads one course page through the live reader record (fx.read). Scratch database only.
insert into ref.countries values ('00000000-0000-0000-0000-0000000000a1', 'AU'), ('00000000-0000-0000-0000-0000000000a2', 'NZ');
insert into catalogue.providers values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', 'AU provider', null),
                                       ('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000a2', 'NZ provider', null);
insert into catalogue.courses(id, provider_id, canonical_title, duration_value, duration_unit) values
 ('00000000-0000-0000-0000-000000000c01', '00000000-0000-0000-0000-0000000000b1', 'Graduate Diploma in Australian Migration Law and Practice', 52, 'weeks'),  -- Murdoch 096011C
 ('00000000-0000-0000-0000-000000000c02', '00000000-0000-0000-0000-0000000000b1', 'Graduate Certificate in Data Science and Decisions', 34, 'weeks'),        -- UNSW 0100702
 ('00000000-0000-0000-0000-000000000c03', '00000000-0000-0000-0000-0000000000b1', 'Graduate Certificate in Computing', 34, 'weeks'),                        -- UNSW, page states its load
 ('00000000-0000-0000-0000-000000000c04', '00000000-0000-0000-0000-0000000000b1', 'Master of eLearning', 104, 'weeks'),                                      -- HELI 102291B
 ('00000000-0000-0000-0000-000000000c05', '00000000-0000-0000-0000-0000000000b1', 'Master of Teaching (Early Childhood Education)', 104, 'weeks'),           -- Barton 119513J
 ('00000000-0000-0000-0000-000000000c06', '00000000-0000-0000-0000-0000000000b1', 'Advanced Diploma of Civil Construction Design', 104, 'weeks'),           -- Reach 106655B
 ('00000000-0000-0000-0000-000000000c07', '00000000-0000-0000-0000-0000000000b1', 'Bachelor of Information Technology and Systems', 156, 'weeks'),          -- VIT 085576A
 ('00000000-0000-0000-0000-000000000c11', '00000000-0000-0000-0000-0000000000b1', 'Master of Creative Music Therapy', 104, 'weeks'),                        -- WSU 121432C: hold raised
 ('00000000-0000-0000-0000-000000000c12', '00000000-0000-0000-0000-0000000000b1', 'Bachelor of ICT (Professional)', 156, 'weeks'),                          -- Swinburne 088407E: hold released, exclusion kept
 ('00000000-0000-0000-0000-000000000c13', '00000000-0000-0000-0000-0000000000b1', 'Bachelor of Arts', 156, 'weeks'),                                        -- exclusion for another reason (no fee check)
 ('00000000-0000-0000-0000-000000000c21', '00000000-0000-0000-0000-0000000000b2', 'Graduate Certificate in Science', 26, 'weeks'),                         -- NZ 60 points
 ('00000000-0000-0000-0000-000000000c22', '00000000-0000-0000-0000-0000000000b2', 'Bachelor of Science', 156, 'weeks');                                    -- NZ 120 points a year

insert into pipeline.enrichment_flags(entity, entity_key, field, reason_code, reason, source, state) values
 ('course', '00000000-0000-0000-0000-000000000c11', 'fee', 'fee_crosscheck', 'automatic: more than 25% from the CRICOS total', 'adapter-overwrite', 'raised'),
 ('course', '00000000-0000-0000-0000-000000000c12', 'fee', 'fee_crosscheck', 'automatic: more than 25% from the CRICOS total', 'adapter-overwrite', 'released');
insert into pipeline.uni_adapter_exclusions(course_id, field, provider_id, reason) values
 ('00000000-0000-0000-0000-000000000c11', 'fee', '00000000-0000-0000-0000-0000000000b1', 'automatic: held back for review'),
 ('00000000-0000-0000-0000-000000000c12', 'fee', '00000000-0000-0000-0000-0000000000b1', 'automatic: held back for review'),
 ('00000000-0000-0000-0000-000000000c13', 'fee', '00000000-0000-0000-0000-0000000000b1', 'General-reader fee is a semester total');

-- one course page read: queue item and stored copy, then the live record with the model's rows; returns the record's tally
create function fx.read(p_course uuid, p_rows jsonb) returns jsonb language plpgsql as $f$
declare v_q uuid := gen_random_uuid(); v_e uuid := gen_random_uuid(); v_p uuid;
begin
  select provider_id into v_p from catalogue.courses where id = p_course;
  insert into pipeline.evidence_artifacts values (v_e, 'https://example.edu/' || p_course, 'layer2/x/' || v_e, md5(v_e::text));
  insert into pipeline.fee_reader_queue(id, fact_source_id, provider_id, content_hash, state, course_id, evidence_id) values (v_q, v_e, v_p, md5(v_e::text), 'leased', p_course, v_e);
  return public.svc_fee_ai_record(v_q, jsonb_build_object('rows', (select jsonb_agg(r || jsonb_build_object('course_id', p_course, 'match_confidence', 1, 'audience', 'international',
           'qualification', (select canonical_title from catalogue.courses where id = p_course))) from jsonb_array_elements(p_rows) r), 'model', 'fixture'), 0, null);
end $f$;
-- what the catalogue holds for a course now
create function fx.fee(p_course uuid) returns numeric language sql as $f$
  select amount from catalogue.course_fees where course_id = p_course and fee_type = 'provider_current_tuition' and status = 'active' order by created_at desc limit 1 $f$;
create function fx.reset() returns void language sql as $f$
  delete from catalogue.course_fees; delete from pipeline.fee_reader_rows; delete from pipeline.layer4_review_items; delete from pipeline.fee_reader_queue;
  delete from pipeline.evidence_artifacts; delete from pipeline.fee_reader_findings $f$;
create function fx.ok(p_cond boolean, p_what text) returns void language plpgsql as $f$
begin if p_cond is not true then raise exception 'FAIL: %', p_what; end if; raise notice 'ok: %', p_what; end $f$;
