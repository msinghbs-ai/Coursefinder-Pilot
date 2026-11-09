-- Guards: Platform Admin operating model v1.5 (10 Nov 2026, delivery first): one weak sentence no longer sinks a provider-description proposal whose other sentences are fully supported. With drop_failing (only the record of a new read sets it) a sentence that fails any sentence rule is left out and the others are kept; every kept sentence passed every rule; fewer kept sentences than the set minimum hold the read with the first failing rule; every other caller still holds the answer on the first failing sentence.
-- Fixture data only (the pdesc-machine harness: fictional providers and stored official pages, no live data). Prints "<scenario>|<result>" lines; every block rolls back. Run by tests/fixtures/pdesc-sentence-filter/run.sh.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

create or replace function pg_temp.pid(n int) returns uuid language sql as $f$ select id from catalogue.providers where stable_key = 'fixture:provider:' || n::text $f$;
create or replace function pg_temp.set_s(k text, v jsonb) returns void language sql as $f$ update pipeline.platform_toolset_settings set value = v where toolset_key = 'pipeline' and key = k $f$;
-- a sentence as the worker hands it over (on_page proved by the worker)
create or replace function pg_temp.s(t text, q text, on_p boolean default true) returns jsonb language sql as $f$ select jsonb_build_object('text', t, 'quote', q, 'on_page', on_p) $f$;
-- the validator on provider 1 (Aurora Maritime University: its stored About page); prints outcome|rule|kept|dropped rules|characters
create or replace function pg_temp.v(p_sent jsonb, p_drop boolean) returns text language sql as $f$
  select concat_ws('|', g->>'outcome', case when g->>'outcome' = 'held' then g->>'rule' end, 'kept=' || coalesce(jsonb_array_length(g->'sentences'), -1),
                   'dropped=' || coalesce((select string_agg(d->>'rule', ',' order by o) from jsonb_array_elements(g->'checks'->'dropped') with ordinality e(d, o)), '-'), 'chars=' || (g->'checks'->>'chars'))
    from (select security.provider_description_validate_v1(pg_temp.pid(1), 'https://p1.example.edu/about', (select captured_at from pipeline.evidence_artifacts where id = (select evidence_id from fixture.documents where provider_id = pg_temp.pid(1))),
                                                          jsonb_build_object('about_page', true, 'sentences', p_sent) || case when p_drop then '{"drop_failing":true}'::jsonb else '{}'::jsonb end) g) z $f$;
-- the three quotes of the page
create or replace function pg_temp.q1() returns text language sql as $f$ select 'Aurora Maritime University offers education in marine navigation and coastal engineering.'::text $f$;
create or replace function pg_temp.q2() returns text language sql as $f$ select 'Its teaching and learning focus on ocean research and nautical practice, supporting the development of knowledge in these fields.'::text $f$;
-- two good sentences (a short paraphrase of each quote)
create or replace function pg_temp.good1() returns jsonb language sql as $f$ select pg_temp.s('Aurora Maritime University offers education in marine navigation and coastal engineering.', pg_temp.q1()) $f$;
create or replace function pg_temp.good2() returns jsonb language sql as $f$ select pg_temp.s('Teaching focuses on ocean research and nautical practice and develops knowledge through learning in these fields.', pg_temp.q2()) $f$;
-- the Sydney shape: the quote is on the page, the sentence adds an aim the quote does not state
create or replace function pg_temp.aim() returns jsonb language sql as $f$ select pg_temp.s('The university is dedicated to solving the world''s biggest problems through marine research and learning.', pg_temp.q2()) $f$;
-- a copied passage: the sentence is its quote (129 characters, over the 120 limit)
create or replace function pg_temp.copy() returns jsonb language sql as $f$ select pg_temp.s(pg_temp.q2(), pg_temp.q2()) $f$;
create or replace function pg_temp.off() returns jsonb language sql as $f$ select pg_temp.s('Teaching is offered on a second site in the north of the country.', pg_temp.q2(), false) $f$;
create or replace function pg_temp.mkt() returns jsonb language sql as $f$ select pg_temp.s('The university offers world-class education in marine navigation and coastal engineering.', pg_temp.q1()) $f$;
create or replace function pg_temp.rank() returns jsonb language sql as $f$ select pg_temp.s('Aurora Maritime University is ranked first for marine navigation and coastal engineering.', pg_temp.q1()) $f$;
create or replace function pg_temp.num() returns jsonb language sql as $f$ select pg_temp.s('Aurora Maritime University offers 40 programs in marine navigation and coastal engineering.', pg_temp.q1()) $f$;
create or replace function pg_temp.frag() returns jsonb language sql as $f$ select pg_temp.s('Teaching focuses on ocean research and nautical practice and develops knowledge through learning', pg_temp.q2()) $f$;

-- ---------------------------------------------------------------------------------------------------------------- 1. the validator, the sentence rules
select 'setting_min_sentences|' || (select value::text from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.min_sentences');
select 'two_good_plain|' || pg_temp.v(jsonb_build_array(pg_temp.good1(), pg_temp.good2()), false);
select 'two_good_flag|' || pg_temp.v(jsonb_build_array(pg_temp.good1(), pg_temp.good2()), true);
-- the Sydney shape
select 'aim_plain_holds|' || pg_temp.v(jsonb_build_array(pg_temp.good1(), pg_temp.good2(), pg_temp.aim()), false);
select 'aim_flag_keeps_two|' || pg_temp.v(jsonb_build_array(pg_temp.good1(), pg_temp.good2(), pg_temp.aim()), true);
select 'aim_first_flag_keeps_two|' || pg_temp.v(jsonb_build_array(pg_temp.aim(), pg_temp.good1(), pg_temp.good2()), true);
-- a copied passage
select 'copy_plain_holds|' || pg_temp.v(jsonb_build_array(pg_temp.good1(), pg_temp.copy(), pg_temp.good2()), false);
select 'copy_flag_keeps_two|' || pg_temp.v(jsonb_build_array(pg_temp.good1(), pg_temp.copy(), pg_temp.good2()), true);
-- a quote that is not on the page
select 'off_plain_holds|' || pg_temp.v(jsonb_build_array(pg_temp.good1(), pg_temp.good2(), pg_temp.off()), false);
select 'off_flag_keeps_two|' || pg_temp.v(jsonb_build_array(pg_temp.good1(), pg_temp.good2(), pg_temp.off()), true);
-- the other sentence rules are not loosened: each failing sentence is left out under its own rule
select 'marketing_flag|' || pg_temp.v(jsonb_build_array(pg_temp.good1(), pg_temp.good2(), pg_temp.mkt()), true);
select 'ranking_flag|' || pg_temp.v(jsonb_build_array(pg_temp.good1(), pg_temp.good2(), pg_temp.rank()), true);
select 'number_flag|' || pg_temp.v(jsonb_build_array(pg_temp.good1(), pg_temp.good2(), pg_temp.num()), true);
select 'fragment_flag|' || pg_temp.v(jsonb_build_array(pg_temp.good1(), pg_temp.good2(), pg_temp.frag()), true);
select 'five_failures_flag|' || pg_temp.v(jsonb_build_array(pg_temp.good1(), pg_temp.good2(), pg_temp.aim(), pg_temp.copy(), pg_temp.mkt()), true);
-- too few sentences kept: held with the rule of the FIRST failing sentence
select 'one_kept_holds_first_rule|' || pg_temp.v(jsonb_build_array(pg_temp.good1(), pg_temp.aim(), pg_temp.copy()), true);
select 'one_kept_holds_first_rule_b|' || pg_temp.v(jsonb_build_array(pg_temp.copy(), pg_temp.good1(), pg_temp.aim()), true);
select 'none_kept_holds|' || pg_temp.v(jsonb_build_array(pg_temp.copy(), pg_temp.aim()), true);
select 'all_copied_holds|' || pg_temp.v(jsonb_build_array(pg_temp.copy(), pg_temp.copy()), true);
-- the count rule still comes first: six sentences are over the set maximum whatever the flag says
select 'six_sentences_flag|' || pg_temp.v(jsonb_build_array(pg_temp.good1(), pg_temp.good2(), pg_temp.good1(), pg_temp.good2(), pg_temp.good1(), pg_temp.good2()), true);
-- the length rule runs on what is kept: two kept sentences shorter than pdesc.min_chars are held
select 'kept_too_short_holds|' || pg_temp.v(jsonb_build_array(pg_temp.s('Aurora Maritime University offers education.', pg_temp.q1()), pg_temp.s('It teaches marine navigation.', pg_temp.q1()), pg_temp.aim()), true);
-- the flag is read as a boolean: an absent flag, false, and a false string are the earlier behaviour
select 'flag_false_holds|' || (select concat_ws('|', g->>'outcome', g->>'rule') from (select security.provider_description_validate_v1(pg_temp.pid(1), 'https://p1.example.edu/about', (select captured_at from pipeline.evidence_artifacts where id = (select evidence_id from fixture.documents where provider_id = pg_temp.pid(1))),
  jsonb_build_object('about_page', true, 'drop_failing', false, 'sentences', jsonb_build_array(pg_temp.good1(), pg_temp.good2(), pg_temp.aim()))) g) z);
-- what the dropped list carries
select 'dropped_detail|' || (select concat_ws('|', jsonb_array_length(z.g->'checks'->'dropped'), d->>'rule', d->>'index', d->>'text', ((d->>'support') is not null)::text, ((d->>'reason') is not null)::text, z.g->'checks'->>'sentences_given', z.g->'checks'->>'sentences')
  from (select security.provider_description_validate_v1(pg_temp.pid(1), 'https://p1.example.edu/about', (select captured_at from pipeline.evidence_artifacts where id = (select evidence_id from fixture.documents where provider_id = pg_temp.pid(1))),
  jsonb_build_object('about_page', true, 'drop_failing', true, 'sentences', jsonb_build_array(pg_temp.good1(), pg_temp.aim(), pg_temp.good2()))) as g) z, lateral jsonb_array_elements(z.g->'checks'->'dropped') d);
-- the kept sentences are exactly the ones given, in order
select 'kept_order|' || (select string_agg(x->>'text', ' / ' order by o) from (select security.provider_description_validate_v1(pg_temp.pid(1), 'https://p1.example.edu/about', (select captured_at from pipeline.evidence_artifacts where id = (select evidence_id from fixture.documents where provider_id = pg_temp.pid(1))),
  jsonb_build_object('about_page', true, 'drop_failing', true, 'sentences', jsonb_build_array(pg_temp.good1(), pg_temp.aim(), pg_temp.good2()))) as g) z, jsonb_array_elements(z.g->'sentences') with ordinality e(x, o));

-- ---------------------------------------------------------------------------------------------------------------- 2. the record: a proposal stores and passes on the kept sentences
create or replace function pg_temp.queue(n int) returns void language plpgsql as $f$
begin insert into pipeline.provider_description_reads(provider_id, state) select pg_temp.pid(n), 'queued' on conflict do nothing; end $f$;
-- the worker step as the real worker does it (lease with the reservation protocol, then record the one answer given for the provider)
create or replace function pg_temp.run_worker(p_n int, p_sentences jsonb) returns jsonb language plpgsql as $f$
declare v_lease jsonb; it jsonb; d record; v_ans jsonb;
begin
  perform pg_temp.queue(p_n);
  v_lease := public.svc_provider_description_lease_v1(3, null, 'provider-description-reserve-v1');
  for it in select * from jsonb_array_elements(v_lease->'items') loop
    continue when (it->>'provider_id')::uuid <> pg_temp.pid(p_n);
    select * into d from fixture.documents where provider_id = pg_temp.pid(p_n);
    v_ans := jsonb_build_object('about_page', true, 'sentences', p_sentences);
    return public.svc_provider_description_record(jsonb_build_array(jsonb_build_object('item_id', it->>'item_id', 'stored_evidence_id', d.evidence_id, 'model', v_lease->>'model', 'prompt_version', 'provider-description-v2', 'worker', 'fixture',
              'cost', 0.0001, 'cost_known', true, 'ai_call_started', true, 'identity_check', jsonb_build_object('ok', true), 'answer', v_ans)));
  end loop;
  return jsonb_build_object('leased', 0);
end $f$;
-- the stored result of the latest read of a provider: state|rule|proposal sentences|dropped rules|Layer 4 item sentences
create or replace function pg_temp.read_of(p_n int) returns text language sql as $f$
  select concat_ws('|', r.state, coalesce(r.rule, '-'), 'proposal=' || coalesce(jsonb_array_length(r.proposal->'sentences'), -1), 'dropped=' || coalesce((select string_agg(d->>'rule', ',' order by o) from jsonb_array_elements(r.checks->'dropped') with ordinality e(d, o)), '-'),
                   'item=' || coalesce((select jsonb_array_length(i.proposed_value->'sentences')::text from pipeline.layer4_review_items i where i.id = r.review_item_id), '-'),
                   'text_has_aim=' || (coalesce(r.proposal->>'description', '') like '%biggest problems%')::text)
    from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(p_n) order by r.created_at desc limit 1 $f$;

begin;
select 'e2e_aim|' || (pg_temp.run_worker(2, jsonb_build_array(
  pg_temp.s('Birch Valley University offers education in forest ecology and sustainable agriculture.', 'Birch Valley University offers education in forest ecology and sustainable agriculture.'),
  pg_temp.s('The university is dedicated to solving the world''s biggest problems through forest research.', 'Its teaching and learning focus on woodland conservation and agricultural science, supporting the development of knowledge in these fields.'),
  pg_temp.s('Teaching focuses on woodland conservation and agricultural science and develops knowledge through learning in these fields.', 'Its teaching and learning focus on woodland conservation and agricultural science, supporting the development of knowledge in these fields.'))) is not null)::text;
select 'e2e_aim_read|' || pg_temp.read_of(2);
rollback;
begin;
-- one kept sentence only: the read is held, with all the model's sentences for the record and the first rule
select 'e2e_one_kept|' || (pg_temp.run_worker(3, jsonb_build_array(
  pg_temp.s('Copper Ridge University offers education in mineral geology and resource surveying.', 'Copper Ridge University offers education in mineral geology and resource surveying.'),
  pg_temp.s('The university is dedicated to solving the world''s biggest problems through geology.', 'Copper Ridge University offers education in mineral geology and resource surveying.'),
  pg_temp.s('The university is dedicated to solving the world''s biggest problems through surveying.', 'Copper Ridge University offers education in mineral geology and resource surveying.'))) is not null)::text;
select 'e2e_one_kept_read|' || pg_temp.read_of(3);
rollback;
