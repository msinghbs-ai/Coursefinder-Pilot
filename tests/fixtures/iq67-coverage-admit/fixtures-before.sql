-- CF-247 IQ-00067: the seed, and the defect reproduced on the live definitions (before the migration). Scratch PostgreSQL only.
-- The plan (fx.plan) mirrors live on 3 Nov 2026 16:06 AEDT: one rule-decided official page for a course locked by hand (University of
-- Auckland 950d06f3: held page + "/1000.html", rule "the held page is a listing"), beside ordinary rows that must still be admitted.
insert into catalogue.providers(id, stable_key, canonical_name, country_id) values ('11111111-0000-4000-8000-000000000000', 'p', 'Fixture University', gen_random_uuid());
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, course_url)
select ('22222222-0000-4000-8000-00000000000' || n)::uuid, 'c' || n, '11111111-0000-4000-8000-000000000000', 'Course ' || n, u
  from (values ('1', 'https://www.auckland.ac.nz/en/study/study-options/find-a-study-option/bachelor-nursing-science.html'), ('2', 'https://uni.example.edu/courses'),
               ('3', null), ('4', 'https://uni.example.edu/c4'), ('5', 'https://uni.example.edu/c5'), ('6', null), ('7', 'https://uni.example.edu/study'),
               ('8', null), ('9', null)) v(n, u);
insert into catalogue.course_links(course_id, link_type, url, status, is_primary)
select id, 'official_course', course_url, 'active', true from catalogue.courses where course_url is not null;
-- C1: locked by hand (as live: official_url and course_url); C4: English requirement locked by hand
insert into pipeline.manual_locks(entity, entity_id, field, mode) values
  ('course', '22222222-0000-4000-8000-000000000001', 'official_url', 'value'), ('course', '22222222-0000-4000-8000-000000000001', 'course_url', 'value'),
  ('course', '22222222-0000-4000-8000-000000000004', 'english', 'value');
insert into fx.plan(course_id, provider_id, provider_cricos, course_cricos, evidence_id, content_hash, page_url, attribute, action, proposed, current) values
  -- C1 locked: rule "take" (held page is a listing) -> the link apply refuses it
  ('22222222-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000000', 'P1', 'C1', gen_random_uuid(), 'h1',
   'https://www.auckland.ac.nz/en/study/study-options/find-a-study-option/bachelor-nursing-science.html/1000.html', 'official_url', 'differs',
   '{"course_url": "https://www.auckland.ac.nz/en/study/study-options/find-a-study-option/bachelor-nursing-science.html/1000.html"}',
   '["https://www.auckland.ac.nz/en/study/study-options/find-a-study-option/bachelor-nursing-science.html"]'),
  -- C7 not locked: rule "take", but the apply refuses the address (not a full web address) -> another kind of refusal
  ('22222222-0000-4000-8000-000000000007', '11111111-0000-4000-8000-000000000000', 'P1', 'C7', gen_random_uuid(), 'h7', 'https://uni.example.edu/study/a b',
   'official_url', 'differs', '{"course_url": "https://uni.example.edu/study/a b"}', '["https://uni.example.edu/study"]'),
  -- C2 not locked: rule "take" -> decided and applied
  ('22222222-0000-4000-8000-000000000002', '11111111-0000-4000-8000-000000000000', 'P1', 'C2', gen_random_uuid(), 'h2', 'https://uni.example.edu/courses/bachelor-x',
   'official_url', 'differs', '{"course_url": "https://uni.example.edu/courses/bachelor-x"}', '["https://uni.example.edu/courses"]'),
  -- C5 not locked: no rule -> a person decides (pending Layer 4 item)
  ('22222222-0000-4000-8000-000000000005', '11111111-0000-4000-8000-000000000000', 'P1', 'C5', gen_random_uuid(), 'h5', 'https://other.example.edu/c5',
   'official_url', 'differs', '{"course_url": "https://other.example.edu/c5"}', '["https://uni.example.edu/c5"]'),
  -- C3 write; C4 write of an English requirement locked by hand; C6 write the record writer refuses
  ('22222222-0000-4000-8000-000000000003', '11111111-0000-4000-8000-000000000000', 'P1', 'C3', gen_random_uuid(), 'h3', 'https://uni.example.edu/c3',
   'official_url', 'write', '{"course_url": "https://uni.example.edu/c3"}', null),
  ('22222222-0000-4000-8000-000000000004', '11111111-0000-4000-8000-000000000000', 'P1', 'C4', gen_random_uuid(), 'h4', 'https://uni.example.edu/c4',
   'english', 'write', '{"english_requirements": [{"test_code": "IELTS", "overall_score": 6.5}]}', null),
  ('22222222-0000-4000-8000-000000000006', '11111111-0000-4000-8000-000000000000', 'P1', 'C6', gen_random_uuid(), 'h6', 'https://uni.example.edu/c6',
   'official_url', 'write', '{"course_url": "https://uni.example.edu/c6"}', null);
insert into fx.refuse values ('22222222-0000-4000-8000-000000000006');

-- the defect (live definitions): the locked course's refusal aborts the whole batch, and nothing persists
do $$
declare v_err text; v_ctx text;
begin
  begin
    perform security.coverage_admission_gated_v1('coverage-admit', 500, 'coverage-sweep-v0.5.6', array['official_url', 'english']);
    raise exception 'FAIL before: the batch was expected to abort';
  exception when raise_exception then
    get stacked diagnostics v_err = message_text, v_ctx = pg_exception_context;
    if v_err like 'FAIL%' then raise; end if;
  end;
  if v_err not like 'this course''s page was set by hand on the course record%' or v_ctx not like '%layer4_course_link_apply_impl(uuid,uuid,jsonb,text) line 17 at RAISE%' then
    raise exception 'FAIL before: unexpected error % / %', v_err, v_ctx;
  end if;
  raise notice 'before: the batch aborts with the live error ("%"), raised at layer4_course_link_apply_impl line 17', left(v_err, 60);
end $$;
do $$ begin
  if exists (select 1 from pipeline.layer4_review_items) or exists (select 1 from pipeline.layer4_decisions) or exists (select 1 from fx.applied)
     or exists (select 1 from pipeline.job_input_marks) or exists (select 1 from pipeline.consumer_api_baselines)
     or (select count(*) from catalogue.course_links) <> 5 then
    raise exception 'FAIL before: a failed batch left rows behind';
  end if;
  raise notice 'before: nothing persisted (no Layer 4 item, decision, write, job mark or baseline): C2, C3 and C5 were not admitted either';
end $$;
