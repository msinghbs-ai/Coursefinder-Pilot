-- S741 fixture data (invented). One read per case so no case can hold another as a duplicate.
create table t.cases(name text primary key, run_id uuid);
create function t.read(p_name text, p_prov uuid, p_rows jsonb, p_url text default 'https://college.test/entry') returns void language plpgsql as $f$
declare s uuid; r uuid; x jsonb;
begin
  insert into pipeline.entry_matrix_sources(url) values (p_url) returning id into s;
  insert into pipeline.entry_matrix_runs(source_id, result) values (s, '{"completeness":{"heading":"Entry Requirements"}}') returning id into r;
  for x in select * from jsonb_array_elements(p_rows) loop
    insert into catalogue.provider_entry_matrix(run_id, source_id, provider_id, course_label, level_label, study_level_id, country_code, min_grade, min_value, grade_scale, quote, row_hash)
    values (r, s, p_prov, x->>'course', x->>'level', (select id from ref.study_levels where code = x->>'lvl'), coalesce(x->>'cc', 'AU'), x->>'grade', (x->>'value')::numeric,
            coalesce(x->>'scale', 'none'), x->>'quote', md5(random()::text));
  end loop;
  insert into t.cases values (p_name, r);
end $f$;
do $d$
declare a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid();
begin
  -- provider A: a college with Diploma courses, twins, a stream course and a person's "no catalogue course" decision
  insert into catalogue.courses(provider_id, canonical_title) values (a, 'Diploma of Business'), (a, 'Diploma of Commerce'), (a, 'Diploma of Commerce (Accelerated)'),
    (a, 'Diploma of Engineering (52 weeks)'), (a, 'Diploma of Engineering (34 weeks)'), (a, 'Diploma of Health Science'), (a, 'Diploma of Computing'),
    (a, 'Diploma of Arts & Creative Industries'), (a, 'Diploma of Leadership'), (a, 'Advanced Diploma of Leadership'), (a, 'Bachelor of Design'), (a, 'Bachelor of Design (Honours)');
  insert into catalogue.courses(provider_id, canonical_title, lifecycle_status) values (a, 'Diploma of Tourism', 'inactive');
  insert into catalogue.entry_course_links(provider_id, label_key, course_label, state) values (a, security.entry_course_title_key_v1('Computing'), 'Computing', 'rejected');
  -- provider B: a registered training organisation whose titles carry training package codes on the page
  insert into catalogue.courses(provider_id, canonical_title) values (b, 'Certificate III in Painting and Decorating'), (b, 'Certificate III in Carpentry'), (b, 'Certificate III in Carpentry'),
    (b, 'Advanced Diploma of Civil Construction Design');
  perform t.read('LK1_award_field', a, '[{"course":"Business","level":"Diploma Program","lvl":"diploma","value":70,"scale":"percentage","quote":"Diploma Program | Business | Year 12 with 70%"}]');
  perform t.read('LK2_ampersand', a, '[{"course":"Arts & Creative Industries","level":"Diploma Course","lvl":"diploma","value":75,"scale":"percentage","quote":"Arts & Creative Industries | Year 12 @ 75% | None"}]');
  perform t.read('LK3_twin_exact', a, '[{"course":"Commerce","level":"Diploma Course","lvl":"diploma","value":75,"scale":"percentage","quote":"Commerce | Year 12 @ 75% | None"}]');
  perform t.read('LK4_twins_only', a, '[{"course":"Engineering","level":"Diploma Program","lvl":"diploma","value":70,"scale":"percentage","quote":"Diploma Program | Engineering | Year 12 with 70%"}]');
  perform t.read('LK5_stream', a, '[{"course":"Health Science [Nursing]","level":"Diploma Course","lvl":"diploma","value":75,"scale":"percentage","quote":"Health Science [Nursing] | Year 12 @ 75% | None"}]');
  perform t.read('LK6_person_rejected', a, '[{"course":"Computing","level":"Diploma Course","lvl":"diploma","value":75,"scale":"percentage","quote":"Computing | Year 12 @ 75% | None"}]');
  perform t.read('LK7_advanced', a, '[{"course":"Leadership","level":"Advanced Diploma","lvl":"advanced_diploma","value":65,"scale":"percentage","quote":"Advanced Diploma | Leadership | Year 12 with 65%"}]');
  perform t.read('LK8_honours_twin', a, '[{"course":"Design","level":"Bachelor","lvl":"bachelor","value":70,"scale":"percentage","quote":"Bachelor | Design | ATAR 70"}]');
  perform t.read('LK9_inactive', a, '[{"course":"Tourism","level":"Diploma Course","lvl":"diploma","value":60,"scale":"percentage","quote":"Tourism | Year 12 @ 60% | None"}]');
  perform t.read('LK10_level_names_no_award', a, '[{"course":"Business","level":"Undergraduate","lvl":"bachelor","value":70,"scale":"percentage","quote":"Undergraduate | Business | Year 12 with 70%"}]');
  perform t.read('TP1_code_title', b, '[{"course":"CPC30620 – Certificate III in Painting and Decorating","level":"Certificate III","lvl":"certificate_iii","quote":"CPC30620 – Certificate III in Painting and Decorating CRICOS Code: 119476J Duration: 92 weeks Entry Requirements Applicants must: Be at least 18 years of age at course commencement Have successfully completed Australian Year 11 or equivalent Demonstrate English language proficiency : IELTS 6.0 (Academic or General)"}]');
  perform t.read('TP2_two_records', b, '[{"course":"CPC30220 – Certificate III in Carpentry","level":"Certificate III","lvl":"certificate_iii","quote":"CPC30220 – Certificate III in Carpentry CRICOS Code: 119477H Duration: 104 weeks Entry Requirements Applicants must: Be at least 18 years of age at course commencement Have successfully completed Australian Year 12 or equivalent Demonstrate English language proficiency : IELTS 6.0 (Academic or General)"}]');
  perform t.read('CP1_age_english', c, '[{"level":"Certificate IV & Diploma Programs","lvl":"diploma","quote":"For Certificate IV & Diploma Programs | Academic Requirements: 18-years of Age or Older Completion of Year 12 or equivalent * Basic computer skills English Requirements: IELTS (Academic): minimum overall band of 6.0 (with no individual band below 5.5) or Equivalent* or Passed Alfa Education English Requ"}]');
  perform t.read('CP2_score_after_english', c, '[{"level":"Diploma","lvl":"diploma","quote":"Completion of Year 12 or equivalent. English requirements: IELTS 6.0 overall. Applicants from India need Year 12 with a 60% average"}]');
  perform t.read('CP3_average_after_english', c, '[{"level":"Diploma","lvl":"diploma","quote":"Successful completion of Year 12. IELTS 5.5 overall, and an average of B in senior subjects"}]');
  perform t.read('CP4_score_before', c, '[{"level":"Diploma","lvl":"diploma","quote":"Completion of Year 12 with 65% in English Requirements IELTS 6.0"}]');
  perform t.read('CP5_no_completion_words', c, '[{"level":"Masters","lvl":"masters","quote":"A minimum of an Australian Bachelor''s Degree (AQF Level 7) or higher in any discipline, or overseas equivalent IELTS 6.5"}]');
  perform t.read('CP6_plain_completion', c, '[{"level":"Diploma","lvl":"diploma","quote":"Successful completion of Australian Year 12 or equivalent"}]');
end $d$;
create table t.before_s741 as select c.name, security.aer_matrix_machine_exclusions_v1(c.run_id) x from t.cases c;
