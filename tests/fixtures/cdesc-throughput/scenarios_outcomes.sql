-- Guards: F-CDESC decline throughput (Platform Admin directive 10 Nov 2026): the machine rule admits a course description its stored evidence proves safe where it used to decline it for a false reason (a provable reader, a page bound by the course's own CRICOS code, a
-- pathway or "leading to" or programme points the official page itself states, "students" where the quote says "you", twins that waited for each other), and still declines everything that is not proved (an AI match, a thin title match, a shared page, a quote without the word,
-- a ranking "leading", a duration, a population of students, a hand lock). Every row is invented. Runs on the production-parity fixture after the base harness and the cdesc migrations (run.sh), on the database with the throughput migration (every check must pass) and
-- on the database from before it (the checks marked REGRESSION must fail there).
\set ON_ERROR_STOP 1
update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_machine_on'; -- scratch database only
create table if not exists pipeline.zoho_sync_items(entity text, item_key text, ref_id uuid, hash text, seq bigint, seq_at timestamptz, removed_at timestamptz, item jsonb);
create function pg_temp.one(p_text text, p_quote text) returns jsonb language sql as $$ select jsonb_build_array(jsonb_build_object('text', p_text, 'quote', coalesce(p_quote, p_text), 'on_page', true)) $$;
create function pg_temp.two(p_a text, p_b text) returns jsonb language sql as $$ select jsonb_build_array(jsonb_build_object('text', p_a, 'quote', p_a, 'on_page', true), jsonb_build_object('text', p_b, 'quote', p_b, 'on_page', true)) $$;
create function pg_temp.try(n int) returns text language plpgsql as $$ begin perform security.course_description_machine_admit_v1(pg_temp.rid(n), 'test'); return pg_temp.got(pg_temp.rid(n)); end $$;
create function pg_temp.nol3(n int) returns void language sql as $$ update pipeline.layer4_review_items set layer3_state = jsonb_build_object('item_id', (proposed_value->>'item_id')::bigint, 'held_first_admission', true) where id = pg_temp.rid(n) $$;
create function pg_temp.page(n int, p_basis text, p_score numeric, p_ru numeric) returns void language sql as $$ update pipeline.coverage_course_pages set basis = p_basis, score = p_score, runner_up = p_ru where course_id = pg_temp.cid(n) $$;

-- ---- 1. the reader: recorded nowhere, recorded on the reading, or only in the stored AI answer ------------------------------------------------------------------
select pg_temp.mk(n, 1) from generate_series(301, 306) n;
select pg_temp.nol3(n) from generate_series(301, 304) n;
-- 301: no reader anywhere. 302: the reader is on the reading. 303: the stored AI answer holds exactly the reading's sentences. 304: the stored answer holds other sentences. 305, 306 untouched (the item records the reader)
update pipeline.field_enrich_items set value = value || jsonb_build_object('reader', jsonb_build_object('model', 'openai/gpt-4.1-mini', 'prompt', 'course-text-v2', 'worker', 'w-0.59')) where course_id = pg_temp.cid(302) and field = 'description';
insert into pipeline.enrich_ai_answers(item_id, state, answer)
select f.id, 'recorded', jsonb_build_object('model', 'openai/gpt-4.1-mini', 'prompt_version', 'course-text-v1', 'worker', 'w-0.59', 'value', jsonb_build_object('sentences', f.value->'sentences', 'about_course', true))
  from pipeline.field_enrich_items f where f.course_id = pg_temp.cid(303) and f.field = 'description';
insert into pipeline.enrich_ai_answers(item_id, state, answer)
select f.id, 'recorded', jsonb_build_object('model', 'openai/gpt-4.1-mini', 'prompt_version', 'course-text-v1', 'worker', 'w-0.59', 'value', jsonb_build_object('sentences', pg_temp.one('Another reading altogether.', null), 'about_course', true))
  from pipeline.field_enrich_items f where f.course_id = pg_temp.cid(304) and f.field = 'description';
select pg_temp.expect('REGRESSION reader: a reading whose reader is recorded on the reading itself is admitted', pg_temp.try(302) = 'admitted');
select pg_temp.try(303);
select pg_temp.expect('REGRESSION reader: a reading whose reader is only in the stored AI answer that holds exactly its sentences is admitted, with that model and prompt in the ledger',
  (select model || '/' || prompt_version from pipeline.course_description_machine_admissions where review_item_id = pg_temp.rid(303) and outcome = 'admitted') = 'openai/gpt-4.1-mini/course-text-v1');
select pg_temp.expect('reader: nothing recorded anywhere is still declined reader_unrecorded', pg_temp.try(301) = 'reader_unrecorded');
select pg_temp.expect('reader: a stored AI answer that holds other sentences proves nothing and is still declined reader_unrecorded', pg_temp.try(304) = 'reader_unrecorded');
select pg_temp.expect('reader: a reading whose Layer 4 item records the reader is admitted as before', pg_temp.try(305) = 'admitted');

-- ---- 2. the page margin ----------------------------------------------------------------------------------------------------------------------------------------
select pg_temp.mk(n, 1) from generate_series(311, 318) n;
select pg_temp.page(311, 'cricos_code_on_page', 0.889, 0.889);
select pg_temp.page(312, 'cricos_code_on_page', 0.889, 0.889);
select pg_temp.page(313, 'title_match', 0.889, 0.889);
select pg_temp.page(314, 'ai_match', null, null);
select pg_temp.page(315, 'cricos_code_on_page', 1.0, 0.5);
select pg_temp.page(316, 'ai_match', 0.95, 0.20);
update pipeline.coverage_course_pages set url = (select url from pipeline.coverage_course_pages where course_id = pg_temp.cid(317)) where course_id = pg_temp.cid(312); -- 312 shares its address with 317
select pg_temp.page(317, 'cricos_code_on_page', 0.889, 0.889);
update pipeline.layer4_review_items set proposed_value = proposed_value || jsonb_build_object('source_url', (select url from pipeline.coverage_course_pages where course_id = pg_temp.cid(312))) where id = pg_temp.rid(312);
select pg_temp.expect('REGRESSION margin: a page bound by the course''s own CRICOS code on the page, tied with its runner-up, no other course on the address, is admitted', pg_temp.try(311) = 'admitted');
select pg_temp.expect('margin: the same page shared with another course is still declined identity_margin_thin', pg_temp.try(312) = 'identity_margin_thin');
select pg_temp.expect('margin: a title match with no margin is still declined identity_margin_thin', pg_temp.try(313) = 'identity_margin_thin');
select pg_temp.expect('margin: an AI match is still declined identity_margin_thin', pg_temp.try(314) = 'identity_margin_thin' and pg_temp.try(316) = 'identity_margin_thin');
select pg_temp.expect('margin: a clear CRICOS-code match is admitted as before', pg_temp.try(315) = 'admitted');

-- ---- 3. the wording policy of a course ------------------------------------------------------------------------------------------------------------------------
select pg_temp.mk(n, 1) from generate_series(321, 336) n;
select pg_temp.setsents(321, pg_temp.two('The ' || pg_temp.w(321, 1) || ' degree may be a pathway to a ' || pg_temp.w(321, 2) || ' research programme.', 'Learners complete a ' || pg_temp.w(321, 6) || ' project in the final stage under academic guidance.'));
select pg_temp.setsents(322, jsonb_build_array(jsonb_build_object('text', 'The ' || pg_temp.w(322, 1) || ' degree may be a pathway to a ' || pg_temp.w(322, 2) || ' research programme under academic guidance and supervision.',
       'quote', 'The ' || pg_temp.w(322, 1) || ' degree leads on to a ' || pg_temp.w(322, 2) || ' research programme under academic guidance and supervision.', 'on_page', true)));
select pg_temp.setsents(323, pg_temp.two('The ' || pg_temp.w(323, 1) || ' course covers ' || pg_temp.w(323, 2) || ' and ' || pg_temp.w(323, 3) || ' in depth.', 'Graduates complete training leading to registration as a ' || pg_temp.w(323, 4) || ' practitioner.'));
select pg_temp.setsents(324, pg_temp.two('The ' || pg_temp.w(324, 1) || ' course covers ' || pg_temp.w(324, 2) || ' and ' || pg_temp.w(324, 3) || ' in depth.', 'Placements are with some of the leading ' || pg_temp.w(324, 4) || ' providers in the region.'));
select pg_temp.setsents(325, pg_temp.two('The ' || pg_temp.w(325, 1) || ' diploma is a 120-point coursework programme covering ' || pg_temp.w(325, 2) || ' and ' || pg_temp.w(325, 3) || '.', 'Learners complete a ' || pg_temp.w(325, 6) || ' project in the final stage under academic guidance.'));
select pg_temp.setsents(326, pg_temp.two('The ' || pg_temp.w(326, 1) || ' diploma runs over 3 years and covers ' || pg_temp.w(326, 2) || ' and ' || pg_temp.w(326, 3) || ' in depth.', 'Learners complete a ' || pg_temp.w(326, 6) || ' project in the final stage under academic guidance.'));
select pg_temp.setsents(327, pg_temp.two('The programme consists of the papers CHHE 701 and CHHE 702 and covers ' || pg_temp.w(327, 2) || ' and ' || pg_temp.w(327, 3) || ' in depth.', 'Learners complete a ' || pg_temp.w(327, 6) || ' project in the final stage under academic guidance.'));
select pg_temp.setsents(328, pg_temp.two('Learners study ' || pg_temp.w(328, 2) || ' and ' || pg_temp.w(328, 3) || ' for 40 hours a week over the first stage.', 'Learners complete a ' || pg_temp.w(328, 6) || ' project in the final stage under academic guidance.'));
select pg_temp.expect('REGRESSION wording: a pathway the sentence''s own on-page quote states is kept', pg_temp.try(321) = 'admitted');
select pg_temp.expect('wording: a pathway whose quote does not hold the word is still declined policy_refused_word', pg_temp.try(322) = 'policy_refused_word');
select pg_temp.expect('REGRESSION wording: "leading to" (a direction, not a ranking) is kept', pg_temp.try(323) = 'admitted');
select pg_temp.expect('wording: "leading providers" (a ranking claim) is still declined policy_refused_word', pg_temp.try(324) = 'policy_refused_word');
select pg_temp.expect('REGRESSION wording: a 120-point programme and a paper code in a sentence that names its papers are programme structure, not a figure claim', pg_temp.try(325) = 'admitted' and pg_temp.try(327) = 'admitted');
select pg_temp.expect('wording: a duration in years and a count of hours are still declined policy_figure', pg_temp.try(326) = 'policy_figure' and pg_temp.try(328) = 'policy_figure');

-- ---- 4. "students" where the page says "you" -------------------------------------------------------------------------------------------------------------------
select pg_temp.mk(n, 1) from generate_series(341, 346) n;
select pg_temp.setsents(341, jsonb_build_array(jsonb_build_object('text', 'Students study ' || pg_temp.w(341, 2) || ' and ' || pg_temp.w(341, 3) || ' in depth through coursework and a project.',
       'quote', 'You will study ' || pg_temp.w(341, 2) || ' and ' || pg_temp.w(341, 3) || ' in depth through coursework and a project.', 'on_page', true)));
select pg_temp.setsents(342, jsonb_build_array(jsonb_build_object('text', 'Our students study ' || pg_temp.w(342, 2) || ' and ' || pg_temp.w(342, 3) || ' in depth through coursework and a project.',
       'quote', 'You will study ' || pg_temp.w(342, 2) || ' and ' || pg_temp.w(342, 3) || ' in depth through coursework and a project.', 'on_page', true)));
select pg_temp.setsents(343, jsonb_build_array(jsonb_build_object('text', 'More than 900 students study ' || pg_temp.w(343, 2) || ' and ' || pg_temp.w(343, 3) || ' in depth through coursework and a project.',
       'quote', 'You will study ' || pg_temp.w(343, 2) || ' and ' || pg_temp.w(343, 3) || ' in depth through coursework and a project.', 'on_page', true)));
select pg_temp.setsents(344, jsonb_build_array(jsonb_build_object('text', 'Students study ' || pg_temp.w(344, 2) || ' and ' || pg_temp.w(344, 3) || ' in depth through coursework and a project.',
       'quote', 'You will study ' || pg_temp.w(344, 2) || ' and ' || pg_temp.w(344, 3) || ' in depth through coursework and a project.', 'on_page', false)));
select pg_temp.setsents(345, jsonb_build_array(jsonb_build_object('text', 'Staff teach ' || pg_temp.w(345, 2) || ' and ' || pg_temp.w(345, 3) || ' in depth through coursework and a project.',
       'quote', 'You will study ' || pg_temp.w(345, 2) || ' and ' || pg_temp.w(345, 3) || ' in depth through coursework and a project.', 'on_page', true)));
select pg_temp.diag('check_students', $q$select (security.course_description_check_v1(pg_temp.cid(341), (select value from pipeline.field_enrich_items where course_id = pg_temp.cid(341) and field = 'description')))->>'rule'$q$);
select pg_temp.expect('REGRESSION students: the reader check passes a sentence that says students where the on-page quote says you',
  (security.course_description_check_v1(pg_temp.cid(341), (select value from pipeline.field_enrich_items where course_id = pg_temp.cid(341) and field = 'description')))->>'ok' = 'true');
select pg_temp.expect('students: "our students" and "900 students" are population statements and are still held as unsupported_claim',
  (security.course_description_check_v1(pg_temp.cid(342), (select value from pipeline.field_enrich_items where course_id = pg_temp.cid(342) and field = 'description')))->>'rule' = 'unsupported_claim'
  and (security.course_description_check_v1(pg_temp.cid(343), (select value from pipeline.field_enrich_items where course_id = pg_temp.cid(343) and field = 'description')))->>'rule' = 'unsupported_claim');
select pg_temp.expect('students: a quote that is not on the page is still held quote_not_on_page',
  (security.course_description_check_v1(pg_temp.cid(344), (select value from pipeline.field_enrich_items where course_id = pg_temp.cid(344) and field = 'description')))->>'rule' = 'quote_not_on_page');
select pg_temp.expect('students: "staff" (not a learner word) is still held as unsupported_claim when the quote lacks it',
  (security.course_description_check_v1(pg_temp.cid(345), (select value from pipeline.field_enrich_items where course_id = pg_temp.cid(345) and field = 'description')))->>'rule' = 'unsupported_claim');
select pg_temp.expect('REGRESSION students: the machine rule admits the reading', pg_temp.try(341) = 'admitted');
update pipeline.platform_toolset_settings set value = '[]'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_learner_words';
select pg_temp.expect('students: with the word removed from the list the reader check holds it again',
  (security.course_description_check_v1(pg_temp.cid(346), (select jsonb_build_object('about_course', true, 'sentences', jsonb_build_array(jsonb_build_object('text', 'Students study ' || pg_temp.w(346, 2) || ' and ' || pg_temp.w(346, 3) || ' in depth through coursework and a project.', 'quote', 'You will study ' || pg_temp.w(346, 2) || ' and ' || pg_temp.w(346, 3) || ' in depth through coursework and a project.', 'on_page', true))))))->>'rule' = 'unsupported_claim');
update pipeline.platform_toolset_settings set value = '["students"]'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_learner_words';

-- ---- 5. twins that waited for each other -----------------------------------------------------------------------------------------------------------------------
select pg_temp.mk(n, case when n % 2 = 0 then 3 else 4 end) from generate_series(351, 354) n;
-- 351 (older) and 352 (younger) share one wording; 353 and 354 share another, and 353 (older) is declined for good for a hand lock
create function pg_temp.same(a int, b int, s jsonb) returns void language sql as $$ select pg_temp.setsents(a, s), pg_temp.setsents(b, s) $$;
select pg_temp.same(351, 352, pg_temp.two('The ' || pg_temp.w(351, 1) || ' qualification covers ' || pg_temp.w(351, 2) || ', ' || pg_temp.w(351, 3) || ' and ' || pg_temp.w(351, 4) || ' in depth.', 'Learners complete a ' || pg_temp.w(351, 6) || ' project in the final stage under academic guidance.'));
select pg_temp.same(353, 354, pg_temp.two('The ' || pg_temp.w(353, 1) || ' qualification covers ' || pg_temp.w(353, 2) || ', ' || pg_temp.w(353, 3) || ' and ' || pg_temp.w(353, 4) || ' in depth.', 'Learners complete a ' || pg_temp.w(353, 6) || ' project in the final stage under academic guidance.'));
update pipeline.layer4_review_items set created_at = now() - interval '2 hours' where id in (pg_temp.rid(351), pg_temp.rid(353));
update pipeline.layer4_review_items set created_at = now() - interval '1 hour' where id in (pg_temp.rid(352), pg_temp.rid(354));
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', pg_temp.cid(353), 'description', 'value');
select pg_temp.expect('REGRESSION twins: the YOUNGER twin waits (declined duplicate_exact_waiting) while an older twin can still be admitted', pg_temp.try(352) = 'duplicate_exact_waiting');
select pg_temp.expect('REGRESSION twins: the OLDER twin is admitted (it used to be declined too, so neither ever was)', pg_temp.try(351) = 'admitted');
select pg_temp.expect('twins: the younger twin is then declined as a duplicate of the described course, never admitted', pg_temp.try(352) = 'duplicate_exact_described' and pg_temp.dsc(352) is null);
select pg_temp.expect('REGRESSION twins: an older twin that is parked for another reason (a hand lock) does not hold up the younger', pg_temp.try(353) = 'manual_lock' and pg_temp.try(354) = 'admitted');


-- ---- 5b. QA conditions on the first head (B1 money codes, B2 leading the way, N1 the quote must speak to the reader, N2 the same page by another spelling, N3 wording at three providers) ----------------------
select pg_temp.mk(n, 1) from generate_series(501, 506) n;
create function pg_temp.body(n int, lead text) returns jsonb language sql as $$ select pg_temp.two(lead || ' and covers ' || pg_temp.w(n, 2) || ' and ' || pg_temp.w(n, 3) || ' in depth.', 'Learners complete a ' || pg_temp.w(n, 6) || ' project in the final stage under academic guidance.') $$;
select pg_temp.setsents(501, pg_temp.body(501, 'The ' || pg_temp.w(501, 1) || ' unit costs AUD 250'));
select pg_temp.setsents(502, pg_temp.body(502, 'The ' || pg_temp.w(502, 1) || ' unit ENGR 101 is charged USD 120'));
select pg_temp.setsents(503, pg_temp.body(503, 'Each ' || pg_temp.w(503, 1) || ' module is NZD 300'));
select pg_temp.setsents(504, pg_temp.body(504, 'The ' || pg_temp.w(504, 1) || ' school is leading the way in education'));
select pg_temp.setsents(505, pg_temp.body(505, 'The ' || pg_temp.w(505, 1) || ' school is leading the nation'));
select pg_temp.setsents(506, pg_temp.body(506, 'The ' || pg_temp.w(506, 1) || ' school prepares teams leading people and others'));
select pg_temp.expect('B1 money: a currency code beside an amount (AUD 250, USD 120, NZD 300) is never set aside as a paper code and still declines policy_figure',
  pg_temp.try(501) = 'policy_figure' and pg_temp.try(502) = 'policy_figure' and pg_temp.try(503) = 'policy_figure');
select pg_temp.expect('B2 leading: "leading the way" and "leading the nation" are rankings and still decline policy_refused_word', pg_temp.try(504) = 'policy_refused_word' and pg_temp.try(505) = 'policy_refused_word');
select pg_temp.expect('B2 leading: leading teams / people / others (a verb) is kept', pg_temp.try(506) = 'admitted');

-- N1: the learner word needs a quote that speaks to the reader
create function pg_temp.chk(n int) returns text language sql as $$ select (security.course_description_check_v1(pg_temp.cid(n), (select value from pipeline.field_enrich_items where course_id = pg_temp.cid(n) and field = 'description')))->>'rule' $$;
select pg_temp.mk(n, 1) from generate_series(511, 514) n;
select pg_temp.setsents(511, jsonb_build_array(jsonb_build_object('text', 'The programme prepares students for work in ' || pg_temp.w(511, 2) || ' and ' || pg_temp.w(511, 3) || ' in depth.',
       'quote', 'Surveyors have to be skilled in ' || pg_temp.w(511, 2) || ' and ' || pg_temp.w(511, 3) || ' in depth.', 'on_page', true)));
select pg_temp.setsents(512, jsonb_build_array(jsonb_build_object('text', 'Students learn about ' || pg_temp.w(512, 2) || ' and ' || pg_temp.w(512, 3) || ' in depth through coursework and a project.',
       'quote', 'Learn about ' || pg_temp.w(512, 2) || ' and ' || pg_temp.w(512, 3) || ' in depth through coursework and a project.', 'on_page', true)));
select pg_temp.setsents(513, jsonb_build_array(jsonb_build_object('text', 'Students learn about ' || pg_temp.w(513, 2) || ' and ' || pg_temp.w(513, 3) || ' in depth through coursework and a project.',
       'quote', 'Graduates study ' || pg_temp.w(513, 2) || ' and ' || pg_temp.w(513, 3) || ' in depth through coursework and a project.', 'on_page', true)));
select pg_temp.setsents(514, jsonb_build_array(jsonb_build_object('text', 'Current students study ' || pg_temp.w(514, 2) || ' and ' || pg_temp.w(514, 3) || ' in depth through coursework and a project.',
       'quote', 'You will study ' || pg_temp.w(514, 2) || ' and ' || pg_temp.w(514, 3) || ' in depth through coursework and a project.', 'on_page', true)));
select pg_temp.diag('n1', $q$select pg_temp.chk(511) || ' ' || pg_temp.chk(512) || ' ' || pg_temp.chk(513) || ' ' || pg_temp.chk(514)$q$);
select pg_temp.expect('N1 reader: a quote about the profession ("Surveyors have to be skilled in ...") for "prepares students for" proves nothing and is still held unsupported_claim', pg_temp.chk(511) = 'unsupported_claim');
select pg_temp.expect('N1 reader: an instruction that opens with the same verb ("Learn about ...") speaks to the reader and is kept', pg_temp.chk(512) = 'ok');
select pg_temp.expect('N1 reader: a quote with no you and a different verb is still held unsupported_claim', pg_temp.chk(513) = 'unsupported_claim');
select pg_temp.expect('N1 reader: "current students" is a population statement even when the quote says you', pg_temp.chk(514) = 'unsupported_claim');

-- N2: the same page by another spelling or the same stored evidence is still a shared page
select pg_temp.mk(n, 1) from generate_series(521, 524) n;
select pg_temp.page(n, 'cricos_code_on_page', 0.889, 0.889) from generate_series(521, 524) n;
update pipeline.coverage_course_pages set url = (select url from pipeline.coverage_course_pages where course_id = pg_temp.cid(521)) || '/?utm_source=x#top' where course_id = pg_temp.cid(522);
update pipeline.coverage_course_pages set evidence_id = (select evidence_id from pipeline.coverage_course_pages where course_id = pg_temp.cid(523)) where course_id = pg_temp.cid(524);
select pg_temp.diag('n2', $q$select (select url from pipeline.coverage_course_pages where course_id = pg_temp.cid(521)) || ' | ' || (select url from pipeline.coverage_course_pages where course_id = pg_temp.cid(522))$q$);
select pg_temp.expect('N2 page: the same address with a query, a fragment and a trailing slash is a shared page and still declines identity_margin_thin', pg_temp.try(521) = 'identity_margin_thin');
select pg_temp.expect('N2 page: two courses bound to the same stored evidence are a shared page and still decline identity_margin_thin', pg_temp.try(523) = 'identity_margin_thin');

-- N3: wording that waits at three different providers is shared training-package wording: no tie-break, the oldest waits too
select pg_temp.mk(541, 1); select pg_temp.mk(542, 2); select pg_temp.mk(543, 4);
select pg_temp.setsents(541, pg_temp.two('The ' || pg_temp.w(541, 1) || ' training package covers ' || pg_temp.w(541, 2) || ', ' || pg_temp.w(541, 3) || ' and ' || pg_temp.w(541, 4) || ' in depth.', 'Learners complete a ' || pg_temp.w(541, 6) || ' project in the final stage under academic guidance.'));
select pg_temp.setsents(542, (select value->'sentences' from pipeline.field_enrich_items where course_id = pg_temp.cid(541) and field = 'description'));
select pg_temp.setsents(543, (select value->'sentences' from pipeline.field_enrich_items where course_id = pg_temp.cid(541) and field = 'description'));
update pipeline.layer4_review_items set created_at = now() - interval '3 hours' where id = pg_temp.rid(541);
update pipeline.layer4_review_items set created_at = now() - interval '2 hours' where id = pg_temp.rid(542);
update pipeline.layer4_review_items set created_at = now() - interval '1 hour' where id = pg_temp.rid(543);
select pg_temp.expect('N3 twins: the same wording at three providers keeps the old rule, so even the oldest is declined duplicate_exact_waiting (two providers are tie-broken, see above)',
  pg_temp.try(541) = 'duplicate_exact_waiting' and pg_temp.try(542) = 'duplicate_exact_waiting' and pg_temp.try(543) = 'duplicate_exact_waiting');

-- ---- 6. protections that stay -----------------------------------------------------------------------------------------------------------------------------------
select pg_temp.mk(n, 1) from generate_series(361, 362) n;
select pg_temp.setsents(361, jsonb_build_array(jsonb_build_object('text', 'Students study ' || pg_temp.w(361, 2) || ' and ' || pg_temp.w(361, 3) || ' in depth through coursework and a project.',
       'quote', 'You will study ' || pg_temp.w(361, 2) || ' and ' || pg_temp.w(361, 3) || ' in depth through coursework and a project.', 'on_page', true)));
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', pg_temp.cid(361), 'description', 'value');
update pipeline.coverage_course_pages set status = 'ambiguous' where course_id = pg_temp.cid(362);
select pg_temp.expect('a hand lock still stops a reading the new rules would otherwise admit', pg_temp.try(361) = 'manual_lock' and pg_temp.dsc(361) is null);
select pg_temp.expect('an ambiguous binding is still declined binding_ambiguous', pg_temp.try(362) = 'binding_ambiguous');

do $$ declare n_fail int := (select count(*) from g_t where not ok); n int := (select count(*) from g_t);
begin
  if n_fail > 0 then raise exception 'cdt-outcomes: % of % checks FAILED', n_fail, n; end if;
  raise notice 'cdt-outcomes: all % checks passed', n;
end $$;
