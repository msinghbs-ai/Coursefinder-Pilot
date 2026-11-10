-- Guards: F-CDESC subset recovery (Platform Admin, 10 Nov 2026, Workstream C): a course reading stuck after the read because of a few sentences (held by the reader's check, or waiting in Layer 4 after a machine decline for its wording) is recovered by a deterministic SUBTRACTIVE subset
-- (ONLY the sentences that fail a per-sentence test or the wording policy are set aside; nothing is ever cut for length), admitted only through the existing record and machine admission with the distinct via 'subset_of_reading', with no AI call and no read; and every failure that dropping cannot fix stays exactly as it was
-- (a reading whose only fault is its length or sentence count, remainder below the minimum or still over the limits, generic or About page, wrong page kind, locked course, duplicate of another course, human rejection, a sentence that points back to a set-aside one, no provable reader, no place for the provider). Every row is invented.
-- Needs the subset migration (runs on the migrated database and, for the REGRESSION checks, on the database from before it).
\set ON_ERROR_STOP 1
update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_machine_on'; -- scratch database only
create table if not exists pipeline.zoho_sync_items(entity text, item_key text, ref_id uuid, hash text, seq bigint, seq_at timestamptz, removed_at timestamptz, item jsonb);
create function pg_temp.mkc(n int, prov int, p_url text default null) returns void language plpgsql as $$
declare v_hash text := md5(n::text) || md5((n + 1000)::text); v_path text; v_url text := coalesce(p_url, 'https://example.test/course/' || n);
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
-- the reader's own hold: the course, the reading (with its stored answer) and the reader's check (the record function), exactly as the worker does it
create function pg_temp.held(n int, prov int, p_sents jsonb, p_answer boolean default true, p_url text default null) returns text language plpgsql as $$
declare v_id bigint; v_res text;
begin
  perform pg_temp.mkc(n, prov, p_url);
  v_id := pg_temp.reading(n, prov, 'queued', null, p_sents, p_answer);
  v_res := security.enrich_course_text_record_v1(v_id, jsonb_build_object('value', (select value from pipeline.field_enrich_items where id = v_id), 'model', case when p_answer then 'openai/gpt-4.1-mini' end, 'prompt_version', case when p_answer then 'course-text-v2' end, 'worker', case when p_answer then 'w' end));
  return v_res;
end $$;
create function pg_temp.rd(n int) returns bigint language sql as $$ select max(id) from pipeline.field_enrich_items where course_id = pg_temp.cid(n) and field = 'description' $$;
create function pg_temp.sn(n int, k int) returns jsonb language sql as $$ -- one clean sentence (about 75 characters), quote equal to the text
  select jsonb_build_object('text', 'The ' || pg_temp.w(n, k) || ' unit explores ' || pg_temp.w(n, k + 20) || ' and ' || pg_temp.w(n, k + 40) || ' within the programme.',
                            'quote', 'The ' || pg_temp.w(n, k) || ' unit explores ' || pg_temp.w(n, k + 20) || ' and ' || pg_temp.w(n, k + 40) || ' within the programme.', 'on_page', true) $$;
create function pg_temp.pad(n int, k int, len int) returns jsonb language plpgsql as $$ -- one clean sentence of exactly len characters
declare t text := 'The ' || pg_temp.w(n, k) || ' unit covers '; j int := 0;
begin
  while length(t) < len loop j := j + 1; t := t || pg_temp.w(n, k * 100 + j) || ' '; end loop;
  t := rtrim(left(t, len - 1)) ; t := rpad(t, len - 1, 'x') || '.';
  return jsonb_build_object('text', t, 'quote', t, 'on_page', true);
end $$;
create function pg_temp.bad(n int, k int, kind text) returns jsonb language plpgsql as $$ -- one sentence with one fault
declare t text; q text; op boolean := true;
begin
  t := case kind when 'claim' then 'The ' || pg_temp.w(n, k) || ' graduates are highly employed after the unit ' || pg_temp.w(n, k + 20) || '.'
                 when 'campus' then 'The ' || pg_temp.w(n, k) || ' unit is taught on the main campus near ' || pg_temp.w(n, k + 20) || '.'
                 when 'figure' then 'The ' || pg_temp.w(n, k) || ' unit runs over 3 years and covers ' || pg_temp.w(n, k + 20) || '.'
                 when 'offpage' then 'The ' || pg_temp.w(n, k) || ' unit explores ' || pg_temp.w(n, k + 20) || ' within the programme.'
                 when 'back' then 'This unit also builds on ' || pg_temp.w(n, k + 20) || ' within the programme.'
                 else 'The ' || pg_temp.w(n, k) || ' unit explores ' || pg_temp.w(n, k + 20) || ' within the programme.' end;
  q := case kind when 'claim' then 'The ' || pg_temp.w(n, k) || ' graduates join the unit ' || pg_temp.w(n, k + 20) || '.' else t end;
  if kind = 'offpage' then op := false; end if;
  return jsonb_build_object('text', t, 'quote', q, 'on_page', op);
end $$;
create function pg_temp.arr(VARIADIC a jsonb[]) returns jsonb language sql as $$ select jsonb_agg(x order by o) from unnest(a) with ordinality e(x, o) $$;
create function pg_temp.five(n int) returns jsonb language sql as $$ select pg_temp.arr(pg_temp.sn(n, 1), pg_temp.bad(n, 2, 'claim'), pg_temp.sn(n, 3), pg_temp.sn(n, 4), pg_temp.sn(n, 5)) $$; -- five sentences, the second is an unsupported claim: four remain
create function pg_temp.late() returns jsonb language plpgsql as $$ -- the recovery called 46 s into the statement (the job has been running that long)
begin perform pg_sleep(46); return security.cdesc_subset_recover_v1(); end $$;
create function pg_temp.recover() returns jsonb language plpgsql as $$
begin
  begin return security.cdesc_subset_recover_v1(); exception when undefined_function then return null; end;
end $$;
create function pg_temp.prefix(s jsonb, k int) returns text language sql as $$ select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements(s) with ordinality e(x, o) where o <= k $$;
create function pg_temp.sub(n int) returns jsonb language sql as $$ select a.checks->'subset_of_reading' from pipeline.course_description_machine_admissions a where a.course_id = pg_temp.cid(n) and a.outcome = 'admitted' and a.withdrawn_at is null $$;
create function pg_temp.via(n int) returns text language sql as $$ select a.checks->>'via' from pipeline.course_description_machine_admissions a where a.course_id = pg_temp.cid(n) and a.outcome = 'admitted' and a.withdrawn_at is null $$;
create function pg_temp.att(n int) returns text language sql as $$ select value->'subset_attempt'->>'result' from pipeline.field_enrich_items where id = pg_temp.rd(n) $$;
create function pg_temp.l4(n int) returns int language sql as $$ select count(*)::int from pipeline.layer4_review_items where entity_id = pg_temp.cid(n) and field_code = 'course_description_first_read' $$;

-- ---- 0. the check is the same for every input: one battery, one fingerprint (compared by run.sh between the two databases) ---------------------------------------
select pg_temp.mkc(900, 1);
create temporary table cdsub_battery(id int primary key, s jsonb);
insert into cdsub_battery
select row_number() over (), s from (values
  (pg_temp.arr(pg_temp.sn(900, 1), pg_temp.sn(900, 2))),
  (pg_temp.arr(pg_temp.sn(900, 3))),
  ('[]'::jsonb),
  (pg_temp.arr(pg_temp.sn(900, 4), pg_temp.sn(900, 5), pg_temp.sn(900, 6), pg_temp.sn(900, 7), pg_temp.sn(900, 8))),
  (pg_temp.arr(pg_temp.sn(900, 9), pg_temp.bad(900, 10, 'offpage'))),
  (pg_temp.arr(pg_temp.sn(900, 11), jsonb_build_object('text', 'The unit explores things within the programme.', 'quote', '', 'on_page', true))),
  (pg_temp.arr(pg_temp.sn(900, 12), pg_temp.bad(900, 13, 'claim'))),
  (pg_temp.arr(pg_temp.sn(900, 14), jsonb_build_object('text', 'The unit is the best in the country for ' || pg_temp.w(900, 15) || ' and ' || pg_temp.w(900, 16) || ' studies.', 'quote', 'The unit covers ' || pg_temp.w(900, 15) || ' and ' || pg_temp.w(900, 16) || ' studies.', 'on_page', true))),
  (pg_temp.arr(pg_temp.sn(900, 17), jsonb_build_object('text', 'Students study ' || pg_temp.w(900, 18) || ' in depth through coursework and a project.', 'quote', 'You will study ' || pg_temp.w(900, 18) || ' in depth through coursework and a project.', 'on_page', true))),
  (pg_temp.arr(pg_temp.sn(900, 19), jsonb_build_object('text', 'The unit explores ' || pg_temp.w(900, 20) || ' and the rest of the programme', 'quote', 'The unit explores ' || pg_temp.w(900, 20) || ' and the rest of the programme', 'on_page', true))),
  (pg_temp.arr(pg_temp.sn(900, 21), jsonb_build_object('text', 'The unit explores ' || pg_temp.w(900, 22) || ' and more...', 'quote', 'The unit explores ' || pg_temp.w(900, 22) || ' and more...', 'on_page', true))),
  (pg_temp.arr(pg_temp.sn(900, 23), jsonb_build_object('text', 'The unit explores ' || pg_temp.w(900, 24) || ' within the programme in depth.', 'quote', 'Completely different words that carry nothing of the sentence at all here.', 'on_page', true))),
  (pg_temp.arr(jsonb_build_object('text', 'Short one.', 'quote', 'Short one.', 'on_page', true))),
  (pg_temp.arr(pg_temp.pad(900, 25, 300), pg_temp.pad(900, 26, 300), pg_temp.pad(900, 27, 300))),
  (pg_temp.arr(pg_temp.sn(900, 28), pg_temp.bad(900, 29, 'back')))
) v(s);
select pg_temp.expect('equivalence: the course description check gives one answer for every battery input (fingerprint ' ||
  (select md5(string_agg(security.course_description_check_v1(pg_temp.cid(900), jsonb_build_object('about_course', true, 'sentences', s))::text, '|' order by id)) from cdsub_battery) || ')', true);
select pg_temp.expect('equivalence: the battery reaches every per-sentence rule (not_stated, sentence_count, quote_not_on_page, unsupported_marketing, unsupported_claim, incomplete_sentence, unsupported_sentence, length)',
  (select count(distinct security.course_description_check_v1(pg_temp.cid(900), jsonb_build_object('about_course', true, 'sentences', s))->>'rule') >= 8 from cdsub_battery));

-- the provider places are set first: a policy setting changes the policy stamp, and the declines below must be at the stamp the recovery runs under
update pipeline.platform_toolset_settings set value = '2'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_pending_max'; -- scratch database only

-- ---- 1. the cases ------------------------------------------------------------------------------------------------------------------------------------------------
-- 501 five clean sentences (held: sentence_count) and 502 four clean sentences of 702 characters in all (held: length): the ONLY fault is the size, so nothing is cut and they stay held (over_length_needs_decision);
-- 503 six sentences, the second is an unsupported claim and the third is not on the page (held: sentence_count): four remain; 531 five sentences, the second an unsupported claim: four remain;
-- 532 four sentences of which the last is an unsupported claim, 702 or more characters in all (held): three remain, 632 characters; 533 six sentences, one an unsupported claim: five remain, still over the limit: stays held
select pg_temp.held(501, 1, pg_temp.arr(pg_temp.sn(501, 1), pg_temp.sn(501, 2), pg_temp.sn(501, 3), pg_temp.sn(501, 4), pg_temp.sn(501, 5))) h501 \gset
select pg_temp.held(502, 1, pg_temp.arr(pg_temp.pad(502, 1, 170), pg_temp.pad(502, 2, 170), pg_temp.pad(502, 3, 170), pg_temp.pad(502, 4, 189))) h502 \gset
select pg_temp.held(503, 2, pg_temp.arr(pg_temp.sn(503, 1), pg_temp.bad(503, 2, 'claim'), pg_temp.bad(503, 3, 'offpage'), pg_temp.sn(503, 4), pg_temp.sn(503, 5), pg_temp.sn(503, 6))) h503 \gset
select pg_temp.held(531, 1, pg_temp.five(531)) h531 \gset
select pg_temp.held(532, 1, pg_temp.arr(pg_temp.pad(532, 1, 210), pg_temp.pad(532, 2, 210), pg_temp.pad(532, 3, 210), pg_temp.bad(532, 4, 'claim'))) h532 \gset
select pg_temp.held(533, 1, pg_temp.arr(pg_temp.sn(533, 1), pg_temp.sn(533, 2), pg_temp.bad(533, 3, 'claim'), pg_temp.sn(533, 4), pg_temp.sn(533, 5), pg_temp.sn(533, 6))) h533 \gset
-- 504 waiting in Layer 4, declined for a refused word (campus) in the second of three sentences; 505 declined for a figure in the first of three
select pg_temp.mk(504, 3); select pg_temp.mk(505, 3);
select pg_temp.setsents(504, pg_temp.arr(pg_temp.sn(504, 1), pg_temp.bad(504, 2, 'campus'), pg_temp.sn(504, 3)));
select pg_temp.setsents(505, pg_temp.arr(pg_temp.bad(505, 1, 'figure'), pg_temp.sn(505, 2), pg_temp.sn(505, 3)));
select security.course_description_machine_admit_v1(pg_temp.rid(n), 'test') from generate_series(504, 505) n;
-- not recoverable: 506 one short sentence is left; 507 every sentence has a fault; 508 the page became a generic university page; 509 a requirements page; 510 a hand lock; 511 the remainder repeats another course of the provider;
-- 512 the remainder is exactly another provider's description; 513 a person rejected an earlier description; 514 the third sentence points back to the second, which is set aside; 516 no provable reader
select pg_temp.held(506, 1, pg_temp.arr(pg_temp.bad(506, 1, 'claim'), pg_temp.bad(506, 2, 'claim'), pg_temp.bad(506, 3, 'claim'), pg_temp.bad(506, 4, 'claim'), jsonb_build_object('text', 'The unit is short.', 'quote', 'The unit is short.', 'on_page', true))) h506 \gset
select pg_temp.held(507, 1, pg_temp.arr(pg_temp.bad(507, 1, 'claim'), pg_temp.bad(507, 2, 'claim'), pg_temp.bad(507, 3, 'claim'), pg_temp.bad(507, 4, 'claim'), pg_temp.bad(507, 5, 'claim'))) h507 \gset
select pg_temp.held(508, 1, pg_temp.five(508), true, 'https://example.test/course/bachelor-of-glazing-508') h508 \gset
update catalogue.courses set canonical_title = 'Bachelor of Glazing 508' where id = pg_temp.cid(508);
update pipeline.coverage_course_pages set identity_basis = 'host_page' where course_id = pg_temp.cid(508);
select pg_temp.held(509, 1, pg_temp.five(509), true, 'https://example.test/course/509/entry-requirements/') h509 \gset
select pg_temp.held(510, 1, pg_temp.five(510)) h510 \gset
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', pg_temp.cid(510), 'description', 'value');
select pg_temp.held(511, 1, pg_temp.five(511)) h511 \gset
insert into pim.entity_registry(id, stable_key) values (pg_temp.cid(611), 'cm-c611');
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, publication_status, description) values (pg_temp.cid(611), 'cm-c611', pg_temp.pid(1), 'Cm Course 611', 'published', pg_temp.prefix(pg_temp.arr(pg_temp.sn(511, 1), pg_temp.sn(511, 3), pg_temp.sn(511, 4), pg_temp.sn(511, 5)), 4));
select pg_temp.held(512, 3, pg_temp.five(512)) h512 \gset
insert into pim.entity_registry(id, stable_key) values (pg_temp.cid(612), 'cm-c612');
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, publication_status, description) values (pg_temp.cid(612), 'cm-c612', pg_temp.pid(4), 'Cm Course 612', 'published', pg_temp.prefix(pg_temp.arr(pg_temp.sn(512, 1), pg_temp.sn(512, 3), pg_temp.sn(512, 4), pg_temp.sn(512, 5)), 4));
select pg_temp.held(513, 1, pg_temp.five(513)) h513 \gset
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, change_control_ref, decided_at) values
  (pg_temp.rid(713), 'course', pg_temp.cid(513), 'course_description_first_read', pg_temp.eid(513), '{"description": null}', '{"description": "An older reading a person rejected."}', 'rejected', 'x', now() - interval '5 days');
select pg_temp.held(514, 1, pg_temp.arr(pg_temp.sn(514, 1), pg_temp.bad(514, 2, 'claim'), pg_temp.bad(514, 3, 'back'), pg_temp.sn(514, 4), pg_temp.sn(514, 5))) h514 \gset
select pg_temp.held(516, 1, pg_temp.five(516), false) h516 \gset
-- 518 a reading held for a reason the subset cannot change (the same words as another course): not looked at
select pg_temp.held(518, 1, pg_temp.arr(pg_temp.sn(511, 1), pg_temp.sn(511, 3), pg_temp.sn(511, 4), pg_temp.sn(511, 5))) h518 \gset
-- 519 a provider with every place taken by waiting descriptions that no one has looked at (pending_max): its held reading is left for a later run
select pg_temp.mk(n, 7) from generate_series(721, 722) n;
select pg_temp.mkc(519, 7);
select pg_temp.reading(519, 7, 'skipped', 'held: sentence_count: 5 sentence(s), outside the set range', pg_temp.arr(pg_temp.sn(519, 1), pg_temp.sn(519, 2), pg_temp.sn(519, 3), pg_temp.sn(519, 4), pg_temp.sn(519, 5)), true) r519 \gset

select pg_temp.expect('setup: 501 is held for the sentence count, 502 for the length, 503 for the sentence count', (select reason like 'held: sentence_count:%' from pipeline.field_enrich_items where id = pg_temp.rd(501)) and (select reason like 'held: length:%' from pipeline.field_enrich_items where id = pg_temp.rd(502))
  and (select reason like 'held: sentence_count:%' from pipeline.field_enrich_items where id = pg_temp.rd(503)) and :'h501' = 'held' and :'h502' = 'held');
select pg_temp.expect('setup: 504 and 505 wait in Layer 4, declined by the machine rule for their wording', pg_temp.got(pg_temp.rid(504)) = 'policy_refused_word' and pg_temp.got(pg_temp.rid(505)) = 'policy_figure' and pg_temp.pending(504) and pg_temp.pending(505));

-- the bound page must be a page about this course. 524 an institution-level About address; 525 a bare overview address with no course in it; 526 a course page that ends in /overview (a course tab: fine);
-- 527 a page proved only by its host with no course in the address. 529 and 530 are modelled on live samples 3 and 5 (a first sentence set aside; a middle sentence set aside), to show the remainder still names the course.
select pg_temp.held(524, 2, pg_temp.arr(pg_temp.sn(524, 1), pg_temp.sn(524, 2), pg_temp.sn(524, 3), pg_temp.sn(524, 4), pg_temp.sn(524, 5)), true, 'https://example.test/about-us/our-university/') h524 \gset
select pg_temp.held(525, 2, pg_temp.arr(pg_temp.sn(525, 1), pg_temp.sn(525, 2), pg_temp.sn(525, 3), pg_temp.sn(525, 4), pg_temp.sn(525, 5)), true, 'https://example.test/overview') h525 \gset
select pg_temp.held(526, 2, pg_temp.arr(pg_temp.sn(526, 1), pg_temp.sn(526, 2), pg_temp.sn(526, 3), pg_temp.sn(526, 4), pg_temp.bad(526, 5, 'claim')), true, 'https://example.test/explore/bachelor-of-glazing-studies/overview') h526 \gset
update catalogue.courses set canonical_title = 'Bachelor of Glazing Studies' where id = pg_temp.cid(526);
select pg_temp.held(527, 2, pg_temp.arr(pg_temp.sn(527, 1), pg_temp.sn(527, 2), pg_temp.sn(527, 3), pg_temp.sn(527, 4), pg_temp.sn(527, 5)), true, 'https://example.test/study/') h527 \gset
update pipeline.coverage_course_pages set identity_basis = 'host_page' where course_id = pg_temp.cid(527);
select pg_temp.held(529, 2, pg_temp.arr(
  jsonb_build_object('text', 'The Certificate III in Glass and Glazing is a nationally recognised course that runs over 3 years part time.', 'quote', 'The Certificate III in Glass and Glazing is a nationally recognised course that runs over 3 years part time.', 'on_page', true),
  jsonb_build_object('text', 'With this course, you will learn residential, commercial and industrial glass applications.', 'quote', 'With this course, you will learn residential, commercial and industrial glass applications.', 'on_page', true),
  jsonb_build_object('text', 'This course will teach you how to work with a wide range of glass products and their installation.', 'quote', 'This course will teach you how to work with a wide range of glass products and their installation.', 'on_page', true),
  jsonb_build_object('text', 'You will obtain hands-on experience installing glass windows, doors and mirrors.', 'quote', 'You will obtain hands-on experience installing glass windows, doors and mirrors.', 'on_page', true))) h529 \gset
select pg_temp.held(530, 2, pg_temp.arr(
  jsonb_build_object('text', 'The Bachelor of Engineering (Honours) - Bachelor of Computer Science develops a set of skills in software and systems.', 'quote', 'The Bachelor of Engineering (Honours) - Bachelor of Computer Science develops a set of skills in software and systems.', 'on_page', true),
  jsonb_build_object('text', 'The Bachelor of Computer Science covers the theoretical foundations of computer science and its applications.', 'quote', 'The Bachelor of Computer Science covers the theoretical foundations of computer science and its applications.', 'on_page', true),
  jsonb_build_object('text', 'The Bachelor of Engineering (Honours) runs over 3 years with specialisation options.', 'quote', 'The Bachelor of Engineering (Honours) runs over 3 years with specialisation options.', 'on_page', true),
  jsonb_build_object('text', 'The double degree provides a qualification in less time and cost than studying the two degrees separately.', 'quote', 'The double degree provides a qualification in less time and cost than studying the two degrees separately.', 'on_page', true))) h530 \gset
update catalogue.courses set canonical_title = 'Certificate III in Glass and Glazing' where id = pg_temp.cid(529);
update catalogue.courses set canonical_title = 'Bachelor of Engineering (Honours) - Bachelor of Computer Science' where id = pg_temp.cid(530);
-- 517 and 523 were never tried: no valid source was read (attempts 0, "no correct course page" / "no allowed source had a value"). Even with sentences in the row they are not a held reading and not evidence of absence
select pg_temp.mkc(517, 1); select pg_temp.mkc(523, 1);
select pg_temp.reading(517, 1, 'skipped', 'no correct course page: the page found is for another course', pg_temp.arr(pg_temp.sn(517, 1), pg_temp.sn(517, 2), pg_temp.sn(517, 3), pg_temp.sn(517, 4), pg_temp.sn(517, 5)), true);
select pg_temp.reading(523, 1, 'skipped', 'no allowed source had a value', pg_temp.arr(pg_temp.sn(523, 1), pg_temp.sn(523, 2), pg_temp.sn(523, 3), pg_temp.sn(523, 4), pg_temp.sn(523, 5)), true);
select max(id) att_max, md5(string_agg(id::text || ':' || attempts::text, ',' order by id)) att_md5 from pipeline.field_enrich_items where field = 'description' \gset b_

-- ---- 2. one run of the recovery -----------------------------------------------------------------------------------------------------------------------------
select count(*) n_rd, (select count(*) from pipeline.enrich_ai_answers) n_ans, (select count(*) from pipeline.field_enrich_items where created_at > now() - interval '1 day') n_day from pipeline.field_enrich_items \gset b_
select pg_temp.recover() r1 \gset
select pg_temp.expect('REGRESSION recovery: a five-sentence reading with one unsupported claim (531) is admitted without that sentence, by the machine rule, via subset_of_reading',
  pg_temp.dsc(531) = pg_temp.prefix(pg_temp.arr(pg_temp.sn(531, 1), pg_temp.sn(531, 3), pg_temp.sn(531, 4), pg_temp.sn(531, 5)), 4) and pg_temp.via(531) = 'subset_of_reading'
  and (pg_temp.sub(531)->>'cause') = 'sentence_count' and (pg_temp.sub(531)->>'kept_count')::int = 4 and (pg_temp.sub(531)->>'original_count')::int = 5
  and (pg_temp.sub(531)->'dropped'->0->>'index')::int = 2 and (pg_temp.sub(531)->'dropped'->0->>'cause') = 'unsupported_claim' and jsonb_array_length(pg_temp.sub(531)->'dropped') = 1);
select pg_temp.expect('REGRESSION recovery: a reading over the character limit whose last sentence is an unsupported claim (532) is admitted with its first three sentences (632 characters); every kept sentence is whole and in order',
  pg_temp.dsc(532) = pg_temp.prefix((select value->'sentences' from pipeline.field_enrich_items where id = pg_temp.rd(532)), 3) and length(pg_temp.dsc(532)) = 632
  and (pg_temp.sub(532)->'dropped'->0->>'index')::int = 4 and (pg_temp.sub(532)->'dropped'->0->>'cause') = 'unsupported_claim' and jsonb_array_length(pg_temp.sub(532)->'dropped') = 1
  and (select length(string_agg(btrim(x->>'text'), ' ' order by o)) > 700 from pipeline.field_enrich_items e, jsonb_array_elements(e.value->'subset_of_reading'->'original'->'sentences') with ordinality t(x, o) where e.id = pg_temp.rd(532)));
select pg_temp.expect('REGRESSION recovery: unsupported and off-page sentences are set aside and the others kept in order (503: sentences 2 and 3 dropped, 1, 4, 5, 6 -> first four kept)',
  pg_temp.dsc(503) = pg_temp.prefix(pg_temp.arr(pg_temp.sn(503, 1), pg_temp.sn(503, 4), pg_temp.sn(503, 5), pg_temp.sn(503, 6)), 4)
  and (select string_agg(d->>'index' || ':' || (d->>'cause'), ',' order by (d->>'index')::int) from jsonb_array_elements(pg_temp.sub(503)->'dropped') d) = '2:unsupported_claim,3:quote_not_on_page');
select pg_temp.expect('REGRESSION recovery: a waiting item declined for a refused word is admitted without that sentence (504), and one declined for a figure without that sentence (505)',
  pg_temp.dsc(504) = pg_temp.prefix(pg_temp.arr(pg_temp.sn(504, 1), pg_temp.sn(504, 3)), 2) and pg_temp.dsc(505) = pg_temp.prefix(pg_temp.arr(pg_temp.sn(505, 2), pg_temp.sn(505, 3)), 2)
  and (pg_temp.sub(504)->>'cause') = 'policy_refused_word' and (pg_temp.sub(505)->>'cause') = 'policy_figure' and pg_temp.via(504) = 'subset_of_reading' and pg_temp.via(505) = 'subset_of_reading'
  and not pg_temp.pending(504) and not pg_temp.pending(505));
select pg_temp.expect('REGRESSION recovery: the admission is the machine rule''s, with a reason that names the sentences set aside, and the original reading and proposal are kept',
  (select d.layer2_state->>'actor_kind' = 'machine' and d.layer2_state->>'via' = 'subset_of_reading' and d.reason like '%Subset of the reading: 4 of its 5 sentences were kept in their original order; set aside: sentence 2 (unsupported_claim). Nothing was reworded, added or cut%'
          and d.before_value->>'description' is null and d.layer2_state->'subset_of_reading'->>'original_count' = '5'
     from pipeline.layer4_decisions d where d.review_item_id = (select review_item_id from pipeline.course_description_machine_admissions where course_id = pg_temp.cid(531) and outcome = 'admitted'))
  and (select jsonb_array_length(value->'subset_of_reading'->'original'->'sentences') = 5 and state = 'filled' from pipeline.field_enrich_items where id = pg_temp.rd(531))
  and (select proposed_value->'subset_of_reading'->'original_proposal'->>'description' = pg_temp.txt(pg_temp.arr(pg_temp.sn(504, 1), pg_temp.bad(504, 2, 'campus'), pg_temp.sn(504, 3))) from pipeline.layer4_review_items where id = pg_temp.rid(504))
  and (select jsonb_array_length(proposed_value->'subset_of_reading'->'original_proposal'->'sentences') = 3 and status = 'approved' from pipeline.layer4_review_items where id = pg_temp.rid(504)));
select pg_temp.expect('recovery: no read happened (no new reading, no new stored AI answer, none counted against the day''s reads)',
  (select count(*) = :b_n_rd from pipeline.field_enrich_items) and (select count(*) = :b_n_ans from pipeline.enrich_ai_answers) and (select count(*) = :b_n_day from pipeline.field_enrich_items where created_at > now() - interval '1 day'));
-- the failures dropping cannot fix
select pg_temp.expect('NEG size only: a reading whose every sentence passes but is over the sentence limit (501) or the character limit (502), or whose remainder after the failing sentence is still over the limit (533), is NOT cut: it stays held as it was, noted over_length_needs_decision',
  pg_temp.dsc(501) is null and pg_temp.dsc(502) is null and pg_temp.dsc(533) is null and pg_temp.att(501) = 'over_length_needs_decision' and pg_temp.att(502) = 'over_length_needs_decision' and pg_temp.att(533) = 'over_length_needs_decision'
  and pg_temp.l4(501) = 0 and pg_temp.l4(502) = 0 and pg_temp.l4(533) = 0
  and (select state = 'skipped' and reason like 'held: sentence_count:%' and jsonb_array_length(value->'sentences') = 5 and not value ? 'subset_of_reading' from pipeline.field_enrich_items where id = pg_temp.rd(501))
  and (select state = 'skipped' and reason like 'held: length:%' and jsonb_array_length(value->'sentences') = 4 and not value ? 'subset_of_reading' from pipeline.field_enrich_items where id = pg_temp.rd(502))
  and (select state = 'skipped' and jsonb_array_length(value->'sentences') = 6 and not value ? 'subset_of_reading' from pipeline.field_enrich_items where id = pg_temp.rd(533))
  and not exists (select 1 from pipeline.course_description_machine_admissions where course_id in (pg_temp.cid(501), pg_temp.cid(502), pg_temp.cid(533))));
select pg_temp.expect('NEG remainder below the minimum: one short sentence is left (506), or no sentence at all (507): nothing is admitted, nothing is created',
  pg_temp.dsc(506) is null and pg_temp.dsc(507) is null and pg_temp.att(506) = 'remainder_length' and pg_temp.att(507) = 'remainder_below_minimum' and pg_temp.l4(506) = 0 and pg_temp.l4(507) = 0
  and (select state = 'skipped' and reason like 'held: sentence_count:%' from pipeline.field_enrich_items where id = pg_temp.rd(506)));
select pg_temp.expect('NEG generic university page (508, identity proof not admitted for a description) and a requirements page (509): not admitted, the reading is as it was, no waiting item is left behind',
  pg_temp.dsc(508) is null and pg_temp.dsc(509) is null and pg_temp.att(508) = 'record_not_admitted' and pg_temp.att(509) like 'machine_wrong_page_kind' and pg_temp.l4(508) = 0 and pg_temp.l4(509) = 0
  and (select state = 'skipped' and reason like 'held: sentence_count:%' and jsonb_array_length(value->'sentences') = 5 from pipeline.field_enrich_items where id = pg_temp.rd(508))
  and (select state = 'skipped' and reason like 'held: sentence_count:%' and jsonb_array_length(value->'sentences') = 5 from pipeline.field_enrich_items where id = pg_temp.rd(509))
  and not exists (select 1 from pipeline.course_description_machine_admissions where course_id in (pg_temp.cid(508), pg_temp.cid(509))));
select pg_temp.expect('NEG locked course (510): not admitted, reading as it was', pg_temp.dsc(510) is null and pg_temp.att(510) = 'record_locked' and pg_temp.l4(510) = 0 and (select state = 'skipped' and jsonb_array_length(value->'sentences') = 5 from pipeline.field_enrich_items where id = pg_temp.rd(510)));
select pg_temp.expect('NEG duplicate of another course: the same provider (511, refused by the check) and another provider''s exact wording (512, refused by the machine rule): not admitted',
  pg_temp.dsc(511) is null and pg_temp.dsc(512) is null and pg_temp.att(511) = 'remainder_duplicate_other_course' and pg_temp.att(512) = 'machine_duplicate_exact_described' and pg_temp.l4(511) = 0 and pg_temp.l4(512) = 0);
select pg_temp.expect('NEG a person''s earlier rejection (513): not admitted, the rejected item stays the only item', pg_temp.dsc(513) is null and pg_temp.att(513) = 'machine_rejected_before_course' and pg_temp.l4(513) = 1
  and (select status = 'rejected' from pipeline.layer4_review_items where id = pg_temp.rid(713)));
select pg_temp.expect('NEG a kept sentence that points back to a set-aside sentence (514): not used', pg_temp.dsc(514) is null and pg_temp.att(514) = 'depends_on_dropped_sentence' and pg_temp.l4(514) = 0);
select pg_temp.expect('NEG no provable reader (516): not tried, noted', pg_temp.dsc(516) is null and pg_temp.att(516) = 'reader_unrecorded' and pg_temp.l4(516) = 0);
select pg_temp.expect('NEG a reading held for another reason (518, the same words as another course) is not looked at', pg_temp.dsc(518) is null and pg_temp.att(518) is null);
select pg_temp.expect('NEG the provider places (519): a provider whose places are all taken is left for a later run, nothing is written, nothing is marked', pg_temp.dsc(519) is null and pg_temp.att(519) is null and pg_temp.l4(519) = 0
  and (select state = 'skipped' and jsonb_array_length(value->'sentences') = 5 from pipeline.field_enrich_items where id = :r519));
select pg_temp.expect('the run reports what it did', (:'r1'::jsonb->>'recovered_held_readings')::int = 4 and (:'r1'::jsonb->>'recovered_waiting_items')::int = 4 and (:'r1'::jsonb->'recovered_by_cause'->>'sentence_count')::int = 3
  and (:'r1'::jsonb->'not_recovered_by_reason'->>'record_not_admitted')::int = 1 and (:'r1'::jsonb->'not_recovered_by_reason'->>'over_length_needs_decision')::int = 3 and (:'r1'::jsonb->>'provider_places_full')::int >= 1
  and not (:'r1'::jsonb->>'time_box_reached')::boolean);

-- ---- 3. once per policy stamp; a changed policy looks again ----------------------------------------------------------------------------------------------
select pg_temp.recover() r2 \gset
select pg_temp.expect('recovery: nothing is looked at twice for the same policy stamp', (:'r2'::jsonb->>'looked_at')::int = 1 and (:'r2'::jsonb->>'recovered_held_readings')::int = 0 and (:'r2'::jsonb->>'recovered_waiting_items')::int = 0); -- only 519 (places) is looked at again
update pipeline.platform_toolset_settings set value = '4'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_examples'; -- scratch database only: any enrich.course_description_* setting changes the policy stamp
select pg_temp.recover() r3 \gset
select pg_temp.expect('recovery: a changed policy stamp looks at the unrecovered readings again, and recovers none of them', (:'r3'::jsonb->>'looked_at')::int >= 10 and (:'r3'::jsonb->>'recovered_held_readings')::int = 0 and pg_temp.dsc(506) is null and pg_temp.dsc(513) is null);

-- ---- 4. the job, the withdrawal, the flow --------------------------------------------------------------------------------------------------------------------
select security.course_description_machine_run_v1() r4 \gset
select pg_temp.expect('the job runs the recovery before the settle and reports it', :'r4'::jsonb ? 'subset' and :'r4'::jsonb->'subset' ? 'looked_at' and :'r4'::jsonb ? 'settle' and :'r4'::jsonb ? 'held');
select pg_temp.expect('Data Delivery: the flow carries the additive key subset with the recovered descriptions by cause and the readings not recovered by reason',
  (select (f->'subset'->>'known')::boolean and (f->'subset'->'recovered'->>'retained_total')::int = 8 and (f->'subset'->'recovered'->>'admitted_24h')::int = 8 and (f->'subset'->'recovered'->>'withdrawn_total')::int = 0
          and (select (x->>'n')::int from jsonb_array_elements(f->'subset'->'recovered_by_cause') x where x->>'code' = 'sentence_count') = 3
          and (select (x->>'n')::int from jsonb_array_elements(f->'subset'->'recovered_by_cause') x where x->>'code' = 'policy_figure') = 3
          and (select count(*) >= 6 from jsonb_array_elements(f->'subset'->'not_recovered_by_reason') x)
          and f ? 'declined_by_cause' and f ? 'held_by_cause' and f ? 'eligible' and f ? 'gain' and f ? 'blocker'
     from (select security.data_delivery_cdesc_flow_v1() f) z));
select pg_temp.expect('evidence-backed absence: a reading that was never tried (attempts 0: no valid source was read) is not recovered, not stamped, and the recovery changes no attempts count anywhere',
  pg_temp.att(517) is null and pg_temp.att(523) is null and pg_temp.dsc(517) is null and pg_temp.dsc(523) is null and pg_temp.l4(517) = 0 and pg_temp.l4(523) = 0
  and (select md5(string_agg(id::text || ':' || attempts::text, ',' order by id)) from pipeline.field_enrich_items where field = 'description' and id <= :b_att_max) = :'b_att_md5');
select pg_temp.expect('Fill result per field: the latest description item is shown as stored (state, reason, attempts, source, evidence id, storage path); a never-tried item has attempts 0 and its own reason',
  (select (x->'item'->>'attempts')::int = 0 and x->'item'->>'reason' like 'no correct course page%' and x->'item'->>'evidence_id' is not null and x->'item' ? 'storage_path' and x->'item' ? 'source' and (x->>'catalogue_chars')::int = 0
     from jsonb_array_elements(security.cdesc_item_detail_v1(array[pg_temp.cid(517)])) x)
  and (select (x->'item'->>'state') in ('skipped', 'filled') and x->'item'->>'reason' is not distinct from (select reason from pipeline.field_enrich_items where id = pg_temp.rd(532)) and (x->>'catalogue_chars')::int > 0 from jsonb_array_elements(security.cdesc_item_detail_v1(array[pg_temp.cid(532)])) x)
  and jsonb_array_length(security.cdesc_item_detail_v1(array[]::uuid[])) = 0);
select pg_temp.expect('NEG page kind: an institution-level About address (524), a bare overview address (525) and a page proved only by its host with no course in the address (527) are not admitted, their reading is as it was, and the rule is recorded',
  pg_temp.dsc(524) is null and pg_temp.dsc(525) is null and pg_temp.dsc(527) is null and pg_temp.att(524) = 'university_about_page' and pg_temp.att(525) = 'university_about_page' and pg_temp.att(527) = 'host_page_no_course_evidence'
  and pg_temp.l4(524) = 0 and pg_temp.l4(525) = 0 and pg_temp.l4(527) = 0
  and not exists (select 1 from pipeline.course_description_machine_admissions where course_id in (pg_temp.cid(524), pg_temp.cid(525), pg_temp.cid(527))));
select pg_temp.expect('page kind: a course page that ends in /overview, with the course named by the segment before it (526), is a page about the course and recovers by subset',
  pg_temp.dsc(526) = pg_temp.prefix(pg_temp.arr(pg_temp.sn(526, 1), pg_temp.sn(526, 2), pg_temp.sn(526, 3), pg_temp.sn(526, 4)), 4) and pg_temp.via(526) = 'subset_of_reading');
create temporary table cdsub_kind(url text, title text, basis text, want text);
insert into cdsub_kind values
  -- fails closed
  (null, 'Bachelor of Nursing', null, 'no_bound_page'), ('', 'Bachelor of Nursing', 'cricos_code', 'no_bound_page'), ('  ', 'Bachelor of Nursing', null, 'no_bound_page'), ('https://x.edu/', 'Bachelor of Nursing', null, 'no_course_in_address'),
  -- institution-level names, by pattern and with a file extension
  ('https://x.edu/about-us/college-profile', 'Bachelor of Health Science (Naturopathy)', 'cricos_code', 'university_about_page'),
  ('https://x.edu/about-us/about-the-university/the-university/official-publications/university-calendar/c', 'Transitional Certificate (Level 7)', 'adapter_title', 'university_about_page'),
  ('https://x.edu/about-us.html', 'Bachelor of Nursing', null, 'university_about_page'), ('https://x.edu/about-us.aspx', 'Bachelor of Nursing', null, 'university_about_page'),
  ('https://x.edu/about-monash', 'Bachelor of Nursing', null, 'university_about_page'), ('https://x.edu/about-monash.php', 'Bachelor of Nursing', null, 'university_about_page'), ('https://x.edu/monash-about-us', 'Bachelor of Nursing', null, 'university_about_page'),
  ('https://x.edu/why-study-with-us', 'Bachelor of Nursing', null, 'university_about_page'), ('https://x.edu/our-story-and-values', 'Bachelor of Nursing', null, 'university_about_page'), ('https://x.edu/facts-and-figures', 'Bachelor of Nursing', null, 'university_about_page'),
  ('https://x.edu/who-we-are/', 'Bachelor of Nursing', null, 'university_about_page'), ('https://x.edu/university-profile.aspx', 'Bachelor of Nursing', null, 'university_about_page'), ('https://x.edu/at-a-glance', 'Bachelor of Nursing', null, 'university_about_page'),
  -- a bare about / overview with no course: the institution
  ('https://x.edu/overview', 'Master of Music', 'exact_title', 'university_about_page'), ('https://x.edu/about', 'Master of Music', null, 'university_about_page'), ('https://x.edu/about/index.html', 'Bachelor of Nursing', null, 'university_about_page'),
  -- a parent /about/ section is not a course tab, even if one word of the course is shared
  ('https://x.edu/about/faculty-of-nursing', 'Bachelor of Nursing', null, 'university_about_page'), ('https://x.edu/about/bachelor-of-nursing', 'Bachelor of Nursing', null, 'university_about_page'),
  ('https://x.edu/study/about/x/bachelor-of-nursing', 'Bachelor of Nursing', null, 'university_about_page'),
  -- a course tab: the segment before names the whole course (word-set containment); a faculty, a subject area or another course does not
  ('https://x.edu/explore/postgraduate-programmes/master-of-renewable-energy/overview', 'Master of Renewable Energy (Level 9)', 'adapter_title', null),
  ('https://x.edu/explore/degrees/laws/overview', 'Bachelor of Laws (Level 7)', 'adapter_title', 'university_about_page'),
  ('https://x.edu/explore/degrees/bachelor-of-laws/overview', 'Bachelor of Laws (Level 7)', 'adapter_title', null),
  ('https://x.edu/explore/postgraduate-programmes/master-of-music/about?programme=master-of-music', 'Master of Music (Level 9)', 'degree_name', null),
  ('https://x.edu/explore/postgraduate-programmes/master-of-music/about', 'Master of Nursing Science (Level 9)', 'adapter_title', 'university_about_page'),
  ('https://x.edu/courses/master-of-business/overview', 'Master of Business', null, null), ('https://x.edu/courses/master-of-business/overview.html', 'Master of Business', null, null), ('https://x.edu/courses/master-of-business/overview/index.html', 'Master of Business', null, null),
  ('https://x.edu/courses/bachelor-of-nursing/about-this-course', 'Bachelor of Nursing', null, null),
  ('https://x.edu/faculty-of-nursing/overview', 'Bachelor of Nursing', null, 'university_about_page'), ('https://x.edu/school-of-business/overview', 'Master of Business', null, 'university_about_page'),
  ('https://x.edu/study/nursing/overview', 'Bachelor of Nursing', null, 'university_about_page'), ('https://x.edu/courses/bachelor-of-commerce/overview', 'Bachelor of Nursing', null, 'university_about_page'),
  ('https://x.edu/courses/master-of-it/overview', 'Master of IT', null, 'university_about_page'),
  -- a course page that merely sits below an "about our courses" section is a course page
  ('https://x.edu/future-students/study-at-x/about-our-courses/master-of-communication', 'Master of Communication', 'exact_title', null),
  -- the host alone proves nothing: the course must be in the address
  ('https://x.edu/study/', 'Master of Music', 'host_page', 'host_page_no_course_evidence'), ('https://x.edu/study/master-of-music', 'Master of Music', 'host_page', null), ('https://x.edu/courses/bachelor-of-commerce', 'Bachelor of Nursing', 'host_page', 'host_page_no_course_evidence'),
  ('https://x.edu/nursing', 'Bachelor of Nursing', 'host_page', 'host_page_no_course_evidence'), ('https://x.edu/school-of-nursing/bachelor-of-nursing-honours', 'Bachelor of Nursing (Honours)', 'host_page', null),
  -- an ordinary course address is fine
  ('https://x.edu/courses/master-of-music', 'Master of Music', 'exact_title', null), ('https://x.edu/course.aspx?id=5', 'Bachelor of Nursing', null, null), ('https://x.edu/courses/undergraduate/bachelor-of-nursing?x=1#about', 'Bachelor of Nursing', null, null);
select pg_temp.expect('page kind function (table): institution-level names by pattern, file extensions, a parent /about/ section, a course tab by word-set containment, the host alone, and fail closed for no address - every row gives the stated answer',
  (select count(*) = 0 from cdsub_kind where security.cdesc_page_kind_v1(url, title, basis) is distinct from want));
select pg_temp.diag('page kind differs', $q$select url || ' => ' || coalesce(security.cdesc_page_kind_v1(url, title, basis), 'null') || ' (want ' || coalesce(want, 'null') || ')' from cdsub_kind where security.cdesc_page_kind_v1(url, title, basis) is distinct from want$q$);
select pg_temp.mkc(534, 1); delete from pipeline.coverage_course_pages where course_id = pg_temp.cid(534);
select pg_temp.expect('fail closed: a course with no bound page row gets no plan (no_bound_page), so nothing is admitted on a page nobody proved',
  security.cdesc_subset_plan_v1(pg_temp.cid(534), pg_temp.pid(1), jsonb_build_object('sentences', pg_temp.five(534)))->>'rule' = 'no_bound_page'
  and security.cdesc_subset_plan_v1(pg_temp.cid(534), pg_temp.pid(1), jsonb_build_object('sentences', pg_temp.five(534)))->>'ok' = 'false');
-- the owning layer: the machine rule itself refuses an About page, so the settle and fresh-reading routes cannot admit one either
select pg_temp.mk(535, 1);
update pipeline.coverage_course_pages set url = 'https://example.test/about-us/535' where course_id = pg_temp.cid(535);
update pipeline.layer4_review_items set proposed_value = proposed_value || jsonb_build_object('source_url', 'https://example.test/about-us/535') where id = pg_temp.rid(535);
select pg_temp.expect('owning layer: the machine rule refuses a waiting description read from a university About page (wrong_page_kind) and admits nothing',
  security.course_description_machine_admit_v1(pg_temp.rid(535), 'test')->>'rule' = 'wrong_page_kind' and pg_temp.dsc(535) is null and pg_temp.pending(535)
  and security.course_description_machine_check_v1(pg_temp.rid(535))->>'rule' = 'wrong_page_kind');
-- a kept sentence that points back to a set-aside sentence is not used: pronouns and connecting words, "the program / course / degree", Another / Alternatively / Further / And / Which / Here / Each, a leading quote or bracket
select pg_temp.expect('dangling openers: a sentence that opens by pointing back, right after a set-aside sentence, makes the plan refuse (depends_on_dropped_sentence); an ordinary opener does not',
  (select count(*) = 0 from unnest(array['This unit covers %s in depth.', 'It covers %s in depth.', 'However, the unit covers %s in depth.', 'The program covers %s in depth.', 'The course covers %s in depth.', 'The degree covers %s in depth.', 'Another pathway covers %s in depth.',
                                       'Alternatively, the unit covers %s in depth.', 'Further, the unit covers %s in depth.', 'And the unit covers %s in depth.', 'Which covers %s in depth.', 'Here the unit covers %s in depth.', 'Each unit covers %s in depth.',
                                       '"The unit covers %s in depth."', '(The unit covers %s in depth.)']) t
     where security.cdesc_subset_plan_v1(pg_temp.cid(531), pg_temp.pid(1), jsonb_build_object('about_course', true, 'sentences', jsonb_build_array(pg_temp.bad(531, 40, 'claim'),
             jsonb_build_object('text', format(t, pg_temp.w(531, 41)), 'quote', format(t, pg_temp.w(531, 41)), 'on_page', true), pg_temp.sn(531, 42))))->>'rule' is distinct from 'depends_on_dropped_sentence')
  and (security.cdesc_subset_plan_v1(pg_temp.cid(531), pg_temp.pid(1), jsonb_build_object('about_course', true, 'sentences', jsonb_build_array(pg_temp.bad(531, 40, 'claim'),
             jsonb_build_object('text', format('The unit covers %s in depth.', pg_temp.w(531, 41)), 'quote', format('The unit covers %s in depth.', pg_temp.w(531, 41)), 'on_page', true), pg_temp.sn(531, 42))))->>'ok')::boolean);
select pg_temp.expect('samples 3 and 5 (live): a first sentence set aside (529) and a middle one set aside (530); the remainder is admitted by subset and still names the course (a distinctive word of its title)',
  pg_temp.via(529) = 'subset_of_reading' and pg_temp.via(530) = 'subset_of_reading'
  and pg_temp.dsc(529) = 'With this course, you will learn residential, commercial and industrial glass applications. This course will teach you how to work with a wide range of glass products and their installation. You will obtain hands-on experience installing glass windows, doors and mirrors.'
  and pg_temp.dsc(529) ilike '%glass%' and pg_temp.dsc(530) ilike '%computer science%'
  and (pg_temp.sub(529)->'dropped'->0->>'index')::int = 1 and (pg_temp.sub(529)->'dropped'->0->>'cause') = 'policy_figure'
  and (pg_temp.sub(530)->'dropped'->0->>'index')::int = 3 and (pg_temp.sub(530)->'dropped'->0->>'cause') = 'policy_figure'
  and (pg_temp.sub(530)->>'kept_count')::int = 3);
select pg_temp.expect('Data Delivery: the existing stages still carry the flow key and the subset key sits inside it', (select (s->'flow' ? 'subset') and s ? 'validation' from (select security.data_delivery_cdesc_stages_v1() s) z));
select pg_temp.expect('withdrawal: a description admitted by subset is withdrawn like any machine admission and the empty description comes back',
  (select (security.course_description_machine_withdraw_v1(pg_temp.cid(531), 'fixture', '00000000-0000-4000-c000-0000000000aa')->>'ok')::boolean) and pg_temp.dsc(531) is null);
select pg_temp.expect('settle: the existing machine settle still runs after the recovery and admits nothing it should not', (security.course_description_machine_settle_v1()->>'on')::boolean and pg_temp.dsc(506) is null and pg_temp.dsc(513) is null and pg_temp.dsc(508) is null);
select pg_temp.expect('G3: no consumer-facing function reads or calls the recovery (catalogue.courses.description is written only by the existing machine admission)',
  not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where (n.nspname in ('api') or p.proname like 'website\_v2\_%' or p.proname like 'website\_edge\_%' or p.proname like 'zoho\_edge\_%' or p.proname = 'svc_website_settings_v1') and p.prosrc ilike '%cdesc_subset%'));

-- ---- 5. the time box: the recovery ends 45 s after the job began (here: called 46 s into the statement), and says so ----------------------------------------------------
update pipeline.platform_toolset_settings set value = '5'::jsonb where toolset_key = 'pipeline' and key = 'enrich.course_description_examples'; -- scratch database only: a new policy stamp, so there is work to look at
select pg_temp.late() r5 \gset
select pg_temp.expect('time box: a recovery called 46 s into the job looks at nothing, recovers nothing, and reports that the box was reached (the settle and the follow-up keep their share of the job)',
  (:'r5'::jsonb->>'looked_at')::int = 0 and (:'r5'::jsonb->>'recovered_held_readings')::int = 0 and (:'r5'::jsonb->>'recovered_waiting_items')::int = 0 and (:'r5'::jsonb->>'time_box_reached')::boolean);
do $$ begin
  if exists (select 1 from g_t where not ok) then raise exception 'cdsub: % check(s) failed', (select count(*) from g_t where not ok); end if;
  raise notice 'cdsub: all % checks passed', (select count(*) from g_t);
end $$;
