-- Guards: F-PDESC Directive 3 Blocker A (Platform Admin, 9 Nov 2026): the machine admission rule allows neutral population words (students, staff, alumni) only in context, when every sentence that uses one is supported by its exact official quote, and still refuses ranking, outcome, accreditation, award, facility, superlative, finance, visa and number-bearing claims.
-- Fixture data only (the pdesc-machine harness: fictional providers, no live data). Prints "<scenario>|<result>" lines; every block rolls back. Run by tests/fixtures/pdesc-claim-context/run.sh after migration 20261109120000.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

-- ---------------------------------------------------------------------------------------------------------------- helpers
create or replace function pg_temp.pid(n int) returns uuid language sql as $f$ select id from catalogue.providers where stable_key = 'fixture:provider:' || case when n = 13 then 'browser' else n::text end $f$;
create or replace function pg_temp.set_s(k text, v jsonb) returns void language sql as $f$ update pipeline.platform_toolset_settings set value = v where toolset_key = 'pipeline' and key = k $f$;
create or replace function pg_temp.queue(n int) returns void language plpgsql as $f$
begin insert into pipeline.provider_description_reads(provider_id, state) select pg_temp.pid(n), 'queued' on conflict do nothing; end $f$;
create or replace function pg_temp.desc_of(n int) returns text language sql as $f$ select coalesce(description, '(none)') from catalogue.providers where id = pg_temp.pid(n) $f$;
create or replace function pg_temp.items(n int, st text) returns bigint language sql as $f$ select count(*) from pipeline.layer4_review_items where entity_id = pg_temp.pid(n) and field_code = 'provider_description' and status = st $f$;
create or replace function pg_temp.try(q text) returns text language plpgsql as $f$
begin execute q; return 'ok'; exception when others then return sqlerrm; end $f$;
-- the worker step, as the real worker does it (lease with the reservation protocol, then record one answer for each leased item)
create or replace function pg_temp.run_worker(p_limit int, p_override jsonb default '{}'::jsonb) returns jsonb language plpgsql as $f$
declare v_lease jsonb; it jsonb; v_res jsonb := '[]'; d record; v_ans jsonb;
begin
  v_lease := public.svc_provider_description_lease_v1(p_limit, null, 'provider-description-reserve-v1');
  for it in select * from jsonb_array_elements(v_lease->'items') loop
    select * into d from fixture.documents where provider_id = (it->>'provider_id')::uuid;
    v_ans := coalesce(p_override->(it->>'provider_id'), d.model_answer);
    v_ans := jsonb_set(v_ans, '{sentences}', (select jsonb_agg(s || '{"on_page":true}'::jsonb) from jsonb_array_elements(v_ans->'sentences') s));
    v_res := v_res || jsonb_build_array(jsonb_build_object('item_id', it->>'item_id', 'stored_evidence_id', d.evidence_id, 'model', v_lease->>'model', 'prompt_version', 'provider-description-v2', 'worker', 'fixture',
              'cost', 0.0001, 'cost_known', true, 'ai_call_started', true, 'identity_check', jsonb_build_object('ok', true), 'answer', v_ans));
  end loop;
  return jsonb_build_object('leased', jsonb_array_length(coalesce(v_lease->'items', '[]'::jsonb)), 'recorded', case when jsonb_array_length(v_res) > 0 then public.svc_provider_description_record(v_res) end);
end $f$;
-- a worker answer: sentences as (text, quote) pairs
create or replace function pg_temp.ans(p_pairs text[][]) returns jsonb language sql as $f$
  select jsonb_build_object('about_page', true, 'sentences', (select jsonb_agg(jsonb_build_object('text', p_pairs[i][1], 'quote', p_pairs[i][2])) from generate_subscripts(p_pairs, 1) i))
$f$;
-- one gate call with sentence text/quote pairs; prints ok|rule|the word, figure or markup the rule names
create or replace function pg_temp.gate(p_n int, p_text text, p_sentences jsonb) returns text language sql as $f$
  select coalesce(g->>'ok', '') || '|' || coalesce(g->>'rule', '') || '|' || coalesce(substring(g->>'reason' from '\(([^)]*)\)'), '')
    from (select security.provider_description_machine_gate_v1(pg_temp.pid(p_n), p_text, jsonb_build_object('tier', 'stored', 'sentences', p_sentences)) g) z
$f$;
-- sentence objects as the reader holds them (on_page proved by the worker)
create or replace function pg_temp.s(p_text text, p_quote text, p_on boolean default true) returns jsonb language sql as $f$ select jsonb_build_object('text', p_text, 'quote', p_quote, 'on_page', p_on) $f$;
-- the gate on one supported sentence: text and quote
create or replace function pg_temp.one(p_n int, p_text text, p_quote text) returns text language sql as $f$ select pg_temp.gate(p_n, p_text, jsonb_build_array(pg_temp.s(p_text, p_quote))) $f$;

-- the real quotes of the two declined proposals (stored official pages, read 9 Nov 2026)
create or replace function pg_temp.q_unsw() returns text language sql as $f$ select 'The essence of UNSW Sydney is not found in our impressive facilities or beautiful grounds. It is found in our students, our staff, our alumni and our generous donors. Our collective difference reflects the unique perspectives of our people, place and purpose as we play our part in the creation of a just society.'::text $f$;
create or replace function pg_temp.q_monash() returns text language sql as $f$ select 'When our first students began their studies at our foundation campus in Clayton in 1961, we became the first university established in the state of Victoria in over 100 years. From a single campus with fewer than 400 students, Monash has grown into a network of campuses, education centres and partnerships spanning the globe.'::text $f$;

select pg_temp.set_s('pdesc.machine_admit_on', '1');

-- ---------------------------------------------------------------------------------------------------------------- 1. the setting
select 'setting|' || (select value::text || '|' || kind || '|' || min_value || '|' || unit || '|' || section || '|' || (label <> '')::text || '|' || (help <> '')::text || '|' || (used_by like '%pdesc_machine_text_check_ctx_v1%')::text || '|' || (reason <> '')::text from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.machine_neutral_words');
select 'numbers_not_loosened|' || (select value::text from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.machine_numbers_allowed');
select 'claim_words_untouched|' || (select (value ? 'students' and value ? 'staff' and value ? 'alumni' and value ? 'ranked' and value ? 'employability' and value ? 'accredited')::text from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.claim_words');

-- ---------------------------------------------------------------------------------------------------------------- 2. admitted: neutral, source-backed sentences
begin;
-- UNSW Sydney: who the university is made of; the quote says the same
select 'unsw_admitted|' || pg_temp.one(12, 'The university''s essence is found in its students, staff, alumni and donors, reflecting the perspectives of its people, place and purpose.', pg_temp.q_unsw());
select 'unsw_short_admitted|' || pg_temp.one(12, 'The university''s essence is found in its students, staff, alumni and donors.', pg_temp.q_unsw());
-- Monash University: its first students began in 1961 (a year in range is not a figure)
select 'monash_admitted|' || pg_temp.one(12, 'The first students began their studies in Clayton in 1961, when the university was established in Victoria.', pg_temp.q_monash());
-- two supported sentences, each with its own quote
select 'two_sentences_admitted|' || pg_temp.gate(12, 'Teaching is led by academic staff and supported by professional staff. The alumni community keeps in touch with the university.',
  jsonb_build_array(pg_temp.s('Teaching is led by academic staff and supported by professional staff.', 'Our teaching is led by academic staff and supported by professional staff across every faculty.'),
                    pg_temp.s('The alumni community keeps in touch with the university.', 'Our alumni community keeps in touch with the university through events and publications.')));
-- the same text with no sentence given (the strict rule, as before this change): still refused
select 'unsw_without_sentences|' || pg_temp.gate(12, 'The university''s essence is found in its students, staff, alumni and donors.', '[]'::jsonb);
select 'unsw_sentences_null|' || (select coalesce(g->>'ok', '') || '|' || (g->>'rule') from (select security.provider_description_machine_gate_v1(pg_temp.pid(12), 'The university''s essence is found in its students, staff, alumni and donors.', '{"tier":"stored"}') g) z);
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 3. still refused: unsupported or promotional claims, even beside a neutral word
begin;
-- a neutral word whose exact quote does not contain it (unsupported), not negated, not on the page, a text that is not the sentences
select 'quote_lacks_word|' || pg_temp.one(12, 'The university serves its students with a broad range of programs.', 'The university offers a broad range of programs in many fields.');
select 'quote_has_other_form|' || pg_temp.one(12, 'The university serves its students with a broad range of programs.', 'The university serves each student with a broad range of programs.');
select 'quote_negates_word|' || pg_temp.one(12, 'The university has alumni who keep in touch with the university.', 'The university has no alumni who keep in touch with the university yet.');
select 'quote_not_on_page|' || pg_temp.gate(12, 'The university serves its students with a broad range of programs.', jsonb_build_array(pg_temp.s('The university serves its students with a broad range of programs.', 'The university serves its students with a broad range of programs.', false)));
select 'text_is_not_the_sentences|' || pg_temp.gate(12, 'The university serves its students and its staff with a broad range of programs.', jsonb_build_array(pg_temp.s('The university serves its students with a broad range of programs.', 'The university serves its students with a broad range of programs.')));
select 'one_of_two_unsupported|' || pg_temp.gate(12, 'Teaching is led by academic staff. The alumni community keeps in touch with the university.',
  jsonb_build_array(pg_temp.s('Teaching is led by academic staff.', 'Our teaching is led by academic staff.'), pg_temp.s('The alumni community keeps in touch with the university.', 'The community keeps in touch with the university.')));
select 'word_in_second_sentence_only_unsupported|' || pg_temp.gate(12, 'Teaching is led by academic staff and supported by staff. Staff also teach.',
  jsonb_build_array(pg_temp.s('Teaching is led by academic staff and supported by staff.', 'Our teaching is led by academic staff and supported by staff.'), pg_temp.s('Staff also teach.', 'Teachers also teach.')));

-- ranking and rating claims with a supported neutral word
select 'ranking|' || pg_temp.one(12, 'The university is ranked top for student employability and its students are valued.', 'The university is ranked top for student employability and our students are valued.');
select 'ranking_plain|' || pg_temp.one(12, 'Its students study at a university that is ranked in the world top fifty.', 'Our students study at a university that is ranked in the world top fifty.');
select 'rating|' || pg_temp.one(12, 'Its students give the university a five-star rating.', 'Our students give the university a five-star rating.');
-- outcome claims
select 'outcome_employment|' || pg_temp.one(12, 'Its students enjoy strong employability and graduate outcomes.', 'Our students enjoy strong employability and graduate outcomes.');
select 'outcome_salary|' || pg_temp.one(12, 'Students who graduate earn higher salaries than their peers.', 'Students who graduate earn higher salaries than their peers.');
select 'outcome_employers|' || pg_temp.one(12, 'Its students are sought after by employers.', 'Our students are sought after by employers.');
select 'outcome_earnings_figure|' || pg_temp.one(12, 'Graduates earn more than $90,000 a year and students benefit.', 'Graduates earn more than $90,000 a year and our students benefit.');
-- accreditation, award and facility claims
select 'accreditation|' || pg_temp.one(12, 'Its students study in programs accredited by the professional body.', 'Our students study in programs accredited by the professional body.');
select 'accreditation_noun|' || pg_temp.one(12, 'The university holds accreditation and its staff are well qualified.', 'The university holds accreditation and our staff are well qualified.');
select 'award|' || pg_temp.one(12, 'Its students and staff have won awards.', 'Our students and our staff have won awards.');
select 'facilities|' || pg_temp.one(12, 'Its students use the university facilities.', 'Our students use the university facilities.');
-- superlatives
select 'superlative_best|' || pg_temp.one(12, 'Its students are taught by the best staff.', 'Our students are taught by the best staff.');
select 'superlative_leading|' || pg_temp.one(12, 'Its staff are leading researchers and teachers.', 'Our staff are leading researchers and teachers.');
select 'superlative_world_class|' || pg_temp.one(12, 'Its students enjoy a world-class education.', 'Our students enjoy a world-class education.');
-- finance, visa and availability words (pdesc.machine_refused_words) and campus, scholarship and guarantee (pdesc.evidence_claim_words)
select 'visa|' || pg_temp.one(12, 'International students can apply for a student visa.', 'International students can apply for a student visa.');
select 'fees|' || pg_temp.one(12, 'Its students pay tuition fees each semester.', 'Our students pay tuition fees each semester.');
select 'scholarships|' || pg_temp.one(12, 'Its students receive scholarships.', 'Our students receive scholarships.');
select 'guaranteed|' || pg_temp.one(12, 'Its students are guaranteed a place.', 'Our students are guaranteed a place.');
select 'campus_beside_students|' || pg_temp.one(12, 'Its students and staff work on a campus in Clayton.', 'Our students and our staff work on a campus in Clayton.');
select 'partnership|' || pg_temp.one(12, 'Its students and staff work in partnership with industry.', 'Our students and our staff work in partnership with industry.');
-- numbers: a figure is refused (pdesc.machine_numbers_allowed stays 0) however well the quote supports it
select 'figure_count|' || pg_temp.one(12, 'More than 400 students study at the university.', 'More than 400 students study at the university.');
select 'figure_percentage|' || pg_temp.one(12, 'Ninety five students in a hundred are satisfied, which is 95 per cent.', 'Ninety five students in a hundred are satisfied, which is 95 per cent.');
select 'figure_year_out_of_range|' || pg_temp.one(12, 'The first students began in 1500 at the university.', 'The first students began in 1500 at the university.');
-- page markup
select 'markup|' || pg_temp.one(12, 'The university&#039;s students and staff teach and learn.', 'The university&#039;s students and staff teach and learn.');
-- the two proposals as they were actually declined: the words other than students and alumni still stop them (campus and a figure in Monash; the French list''s "unique" in UNSW)
select 'monash_as_proposed|' || pg_temp.one(12, 'The university began in 1961 as the first university established in Victoria in over 100 years, starting from a single campus with fewer than 400 students.', pg_temp.q_monash());
select 'unsw_as_proposed|' || pg_temp.one(12, 'The university''s essence is found in its students, staff, alumni and donors, reflecting unique perspectives of people, place and purpose.', pg_temp.q_unsw());
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 4. the setting is the control: emptied, every claim word stops automatic admission again; with one word, only that word is allowed
begin;
select pg_temp.set_s('pdesc.machine_neutral_words', '[]'::jsonb);
select 'setting_empty|' || pg_temp.one(12, 'The university''s essence is found in its students, staff, alumni and donors.', pg_temp.q_unsw());
select pg_temp.set_s('pdesc.machine_neutral_words', '["alumni"]'::jsonb);
select 'setting_alumni_only_students_refused|' || pg_temp.one(12, 'The university''s essence is found in its students, staff, alumni and donors.', pg_temp.q_unsw());
select 'setting_alumni_only_alumni_admitted|' || pg_temp.one(12, 'The alumni community keeps in touch with the university.', 'Our alumni community keeps in touch with the university.');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 5. the reader: a supported neutral sentence is admitted by the machine rule; a promotional one waits for a person
begin;
select pg_temp.queue(2); select pg_temp.queue(3);
select 'record_tally|' || ((pg_temp.run_worker(3, jsonb_build_object(
   pg_temp.pid(2)::text, pg_temp.ans(array[
     ['The university''s essence is found in its students, staff, alumni and donors.', pg_temp.q_unsw()],
     ['The first students began their studies in Clayton in 1961.', pg_temp.q_monash()],
     ['The university is a place of learning and research for people from many places and backgrounds.', 'Birch Valley University is a place of learning and research for people from many places and backgrounds.']]),
   pg_temp.pid(3)::text, pg_temp.ans(array[
     ['The university''s essence is found in its students, staff, alumni and donors.', pg_temp.q_unsw()],
     ['Its students study at a university that is ranked in the world top fifty.', 'Our students study at a university that is ranked in the world top fifty, with strong support for every learner.'],
     ['Copper Ridge University teaches engineering and design to a wide range of learners.', 'Copper Ridge University teaches engineering and design to a wide range of learners.']]))))->'recorded')::text;
select 'record_admitted|' || (select r.state || '|' || (r.checks->>'actor_kind') || '|' || (r.checks->>'machine_rule') from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(2) order by r.created_at desc limit 1) || '|' || pg_temp.items(2, 'approved') || '|' || pg_temp.items(2, 'pending');
select 'record_description|' || (pg_temp.desc_of(2) like 'The university''s essence is found in its students, staff, alumni and donors. The first students began%')::text;
-- provenance kept: the audit row has the source address, source hash, evidence id, every sentence with its exact quote, the neutral words relied on, and the machine actor
select 'record_audit|' || (select a.outcome || '|' || a.tier || '|' || (a.source_url is not null)::text || '|' || (a.source_hash is not null)::text || '|' || (a.evidence_id is not null)::text || '|' || jsonb_array_length(a.facts)::text
   || '|' || (a.facts->0->>'quote' = pg_temp.q_unsw())::text || '|' || (a.facts->0->>'source_hash' is not null)::text || '|' || (a.facts->0->>'evidence_id' is not null)::text || '|' || (a.checks->'neutral_words')::text
   || '|' || (a.actor = 'c0ffee00-0000-4000-8000-000000000150')::text
   from pipeline.provider_description_machine_admissions a where a.provider_id = pg_temp.pid(2));
select 'record_decision_is_machine|' || (select (d.layer2_state->>'actor_kind') || '|' || (d.layer2_state->>'machine_rule') from pipeline.layer4_decisions d join pipeline.layer4_review_items li on li.id = d.review_item_id where li.entity_id = pg_temp.pid(2));
-- the ranked sentence: not admitted; the proposal waits in Layer 4 with the exact reason; nothing is published
select 'record_declined|' || (select r.state from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(3) order by r.created_at desc limit 1) || '|' || pg_temp.items(3, 'pending') || '|' || pg_temp.desc_of(3)
   || '|' || (select substring(a.reason from '\(([^)]*)\)') from pipeline.provider_description_machine_admissions a where a.provider_id = pg_temp.pid(3) and a.outcome = 'declined')
   || '|' || (select left(escalation_reason, 70) from pipeline.layer4_review_items where entity_id = pg_temp.pid(3) and status = 'pending');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 6. a proposal declined for a neutral word is re-evaluated by the existing settlement of waiting items, not by a rewrite of any row
begin;
-- the world as it was before the change: a neutral word stops the proposal, which waits in Layer 4 as a declined item
select pg_temp.set_s('pdesc.machine_neutral_words', '[]'::jsonb);
select pg_temp.queue(4);
select pg_temp.run_worker(3, jsonb_build_object(pg_temp.pid(4)::text, pg_temp.ans(array[
     ['The university''s essence is found in its students, staff, alumni and donors.', pg_temp.q_unsw()],
     ['The first students began their studies in Clayton in 1961.', pg_temp.q_monash()],
     ['Dune Plains University teaches botany and ecology to a wide range of learners.', 'Dune Plains University teaches botany and ecology to a wide range of learners.']]))) is not null;
select 'waiting_declined|' || pg_temp.items(4, 'pending') || '|' || pg_temp.desc_of(4) || '|' || (select substring(a.reason from '\(([^)]*)\)') from pipeline.provider_description_machine_admissions a where a.provider_id = pg_temp.pid(4) and a.outcome = 'declined');
-- the setting is what the migration seeds; the next settlement run (fire_v1 calls machine_step_v1 -> settle_pending_v1) finds the item once its hour has passed
select pg_temp.set_s('pdesc.machine_neutral_words', '["students", "staff", "alumni"]'::jsonb);
select 'settle_within_the_hour|' || (security.provider_description_machine_settle_pending_v1())::text || '|' || pg_temp.items(4, 'pending');
update pipeline.provider_description_machine_admissions set created_at = now() - interval '2 hours' where provider_id = pg_temp.pid(4) and outcome = 'declined'; -- fixture only: the declined item has waited more than the hour
select 'settle_after_the_hour|' || (security.provider_description_machine_settle_pending_v1())::text || '|' || pg_temp.items(4, 'pending') || '|' || pg_temp.items(4, 'approved') || '|' || (pg_temp.desc_of(4) like 'The university''s essence is found in its students%')::text;
select 'settle_audit|' || (select string_agg(a.outcome || ':' || coalesce(a.checks->>'published', '-'), ',' order by a.created_at) from pipeline.provider_description_machine_admissions a where a.provider_id = pg_temp.pid(4));
select 'settle_step_is_the_scheduled_path|' || (position('provider_description_machine_step_v1' in pg_get_functiondef('security.provider_description_fire_v1()'::regprocedure)) > 0)::text || '|' || (position('provider_description_machine_settle_pending_v1' in pg_get_functiondef('security.provider_description_machine_step_v1()'::regprocedure)) > 0)::text;
rollback;

-- a waiting item that still has a promotional word stays for a person with the reason on the item
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '0');
select pg_temp.queue(5);
select pg_temp.run_worker(3, jsonb_build_object(pg_temp.pid(5)::text, pg_temp.ans(array[
     ['The university''s essence is found in its students, staff, alumni and donors.', pg_temp.q_unsw()],
     ['Its students are taught by the best staff, with a long record of teaching in many fields.', 'Our students are taught by the best staff, with a long record of teaching in many fields.'],
     ['Elm Arts University offers music composition and theatre performance to its community.', 'Elm Arts University offers music composition and theatre performance to its community.']]))) is not null;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select 'waiting_promotional_settle|' || (security.provider_description_machine_settle_pending_v1())::text;
select 'waiting_promotional|' || pg_temp.items(5, 'pending') || '|' || pg_temp.desc_of(5) || '|' || (select substring(a.reason from '\(([^)]*)\)') from pipeline.provider_description_machine_admissions a where a.provider_id = pg_temp.pid(5));
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 7. the register-fact profile (tier 4) is unchanged: it has no quotes, so no neutral word is allowed there
begin;
select 'tier4_strict|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(12), 'The college teaches students carpentry.'), 'clean') || '|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(12), 'The college teaches carpentry.'), 'clean');
rollback;
