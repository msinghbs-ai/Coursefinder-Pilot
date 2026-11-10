-- Guards: Platform Admin operating model v1.5 (10 Nov 2026, delivery first), record time-out of the provider-description reader: the duplicate test of security.provider_description_validate_v1 counts shared words before it works out the similarity (migration 20261110140000), and its result is the same as before for every description: a copy, a close copy, a copy in other case or punctuation, a text just under the set share, a longer text, an unrelated text, a different share setting. The count is never below the true overlap, so no row the exact test matches is skipped.
-- Fixture data only (the pdesc-machine harness: fictional providers and stored official pages, no live data). Prints "<scenario>|<result>" lines; every block rolls back. Run by tests/fixtures/pdesc-reservation-settlement/run.sh BEFORE and AFTER the migration; the two outputs are the same file (expected-duplicate.txt).
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

create or replace function pg_temp.pid(n int) returns uuid language sql as $f$ select id from catalogue.providers where stable_key = 'fixture:provider:' || n::text $f$;
create or replace function pg_temp.set_s(k text, v jsonb) returns void language sql as $f$ update pipeline.platform_toolset_settings set value = v where toolset_key = 'pipeline' and key = k $f$;
create or replace function pg_temp.s(t text, q text, on_p boolean default true) returns jsonb language sql as $f$ select jsonb_build_object('text', t, 'quote', q, 'on_page', on_p) $f$;
create or replace function pg_temp.q1() returns text language sql as $f$ select 'Aurora Maritime University offers education in marine navigation and coastal engineering.'::text $f$;
create or replace function pg_temp.q2() returns text language sql as $f$ select 'Its teaching and learning focus on ocean research and nautical practice, supporting the development of knowledge in these fields.'::text $f$;
create or replace function pg_temp.good1() returns jsonb language sql as $f$ select pg_temp.s('Aurora Maritime University offers education in marine navigation and coastal engineering.', pg_temp.q1()) $f$;
create or replace function pg_temp.good2() returns jsonb language sql as $f$ select pg_temp.s('Teaching focuses on ocean research and nautical practice and develops knowledge through learning in these fields.', pg_temp.q2()) $f$;
-- the text the validator builds from the two sentences
create or replace function pg_temp.t() returns text language sql as $f$ select 'Aurora Maritime University offers education in marine navigation and coastal engineering. Teaching focuses on ocean research and nautical practice and develops knowledge through learning in these fields.'::text $f$;
-- the validator on provider 1 with the two good sentences: outcome|rule|the provider and similarity of a duplicate
create or replace function pg_temp.v() returns text language sql as $f$
  select concat_ws('|', g->>'outcome', g->>'rule', coalesce((select 'p' || regexp_replace(s.stable_key, '^.*:', '') from catalogue.providers s where s.id = (g->'checks'->>'duplicate_of')::uuid), '-'), coalesce(g->'checks'->>'similarity', '-'))
    from (select security.provider_description_validate_v1(pg_temp.pid(1), 'https://p1.example.edu/about', (select captured_at from pipeline.evidence_artifacts where id = (select evidence_id from fixture.documents where provider_id = pg_temp.pid(1))),
                                                          jsonb_build_object('about_page', true, 'sentences', jsonb_build_array(pg_temp.good1(), pg_temp.good2()))) g) z $f$;
-- the text with its first n distinct words replaced by words that are not on the page
create or replace function pg_temp.changed(n int) returns text language sql as $f$
  select (select string_agg(x.new_w, ' ' order by x.o) from (select o, case when o <= n then 'qq' || o else w end new_w from regexp_split_to_table(pg_temp.t(), ' ') with ordinality e(w, o)) x) $f$;
create or replace function pg_temp.desc_of(n int, d text) returns void language sql as $f$ update catalogue.providers set description = d where id = pg_temp.pid(n) $f$;

select 'nobody_has_a_description|' || pg_temp.v();
begin; select pg_temp.desc_of(2, pg_temp.t()); select 'same_text|' || pg_temp.v(); rollback;
begin; select pg_temp.desc_of(3, replace(replace(pg_temp.t(), 'ocean', 'sea'), 'nautical', 'maritime')); select 'two_words_changed|' || pg_temp.v(); rollback;
begin; select pg_temp.desc_of(8, upper(pg_temp.t())); select 'upper_case|' || pg_temp.v(); rollback;
begin; select pg_temp.desc_of(9, replace(replace(pg_temp.t(), ' and ', ' & '), ', ', '; ') || ' (2026)'); select 'punctuation_and_year|' || pg_temp.v(); rollback;
-- just under the share: eight of the text's distinct words are replaced (similarity below 0.8)
begin; select pg_temp.desc_of(4, pg_temp.changed(8)); select 'eight_words_changed|' || pg_temp.v(); rollback;
begin; select pg_temp.desc_of(12, pg_temp.changed(3)); select 'three_words_changed|' || pg_temp.v(); rollback;
begin; select pg_temp.desc_of(12, pg_temp.changed(4)); select 'four_words_changed|' || pg_temp.v(); rollback;
begin; select pg_temp.desc_of(12, pg_temp.changed(5)); select 'five_words_changed|' || pg_temp.v(); rollback;
begin; select pg_temp.set_s('pdesc.duplicate_share', '0.6'::jsonb); select pg_temp.desc_of(12, pg_temp.changed(8)); select 'share_0_6_eight_words_changed|' || pg_temp.v(); rollback;
-- the share is exactly the similarity of the pair (the test is "at or above"), and 0.0001 above it
begin; select pg_temp.set_s('pdesc.duplicate_share', to_jsonb(security.pdesc_similarity_v1(pg_temp.t(), pg_temp.changed(4)))); select pg_temp.desc_of(12, pg_temp.changed(4)); select 'share_equals_similarity|' || pg_temp.v(); rollback;
begin; select pg_temp.set_s('pdesc.duplicate_share', to_jsonb(security.pdesc_similarity_v1(pg_temp.t(), pg_temp.changed(4)) + 0.0001)); select pg_temp.desc_of(12, pg_temp.changed(4)); select 'share_just_above_similarity|' || pg_temp.v(); rollback;
begin; select pg_temp.set_s('pdesc.duplicate_share', to_jsonb(security.pdesc_similarity_v1(pg_temp.t(), pg_temp.changed(1)))); select pg_temp.desc_of(12, pg_temp.changed(1)); select 'share_equals_similarity_one_word|' || pg_temp.v(); rollback;
begin; select pg_temp.desc_of(5, 'The institute trains nurses, midwives and paramedics for hospitals across the region, with clinical placements in public and private health services.'); select 'unrelated|' || pg_temp.v(); rollback;
begin; select pg_temp.desc_of(6, 'Aurora Maritime University offers education in marine navigation.'); select 'shorter_subset|' || pg_temp.v(); rollback;
begin; select pg_temp.desc_of(7, pg_temp.t() || ' The university also runs an extensive programme of community partnerships, public lectures, summer schools, alumni events, scholarships, industry placements and international exchange.'); select 'longer_superset|' || pg_temp.v(); rollback;
begin; select pg_temp.desc_of(10, '   '); select 'blank_description|' || pg_temp.v(); rollback;
-- the same provider (not a duplicate of itself)
begin; select pg_temp.desc_of(1, pg_temp.t()); select 'own_description_is_not_a_duplicate|' || pg_temp.v(); rollback;
-- the share is a setting
begin; select pg_temp.set_s('pdesc.duplicate_share', '0.5'::jsonb); select pg_temp.desc_of(4, pg_temp.changed(8)); select 'share_0_5_eight_words_changed|' || pg_temp.v(); rollback;
begin; select pg_temp.set_s('pdesc.duplicate_share', '0.95'::jsonb); select pg_temp.desc_of(3, replace(replace(pg_temp.t(), 'ocean', 'sea'), 'nautical', 'maritime')); select 'share_0_95_two_words_changed|' || pg_temp.v(); rollback;
begin; select pg_temp.set_s('pdesc.duplicate_share', '1'::jsonb); select pg_temp.desc_of(2, pg_temp.t()); select 'share_1_same_text|' || pg_temp.v(); rollback;
-- the best of several matches is reported (the closest copy)
begin; select pg_temp.desc_of(2, replace(pg_temp.t(), 'ocean', 'sea')); select pg_temp.desc_of(3, pg_temp.t()); select 'closest_of_two|' || pg_temp.v(); rollback;
-- another provider's proposal waiting is a duplicate too (the second half of the union is unchanged)
begin;
insert into pipeline.provider_description_reads(provider_id, state, proposal) values (pg_temp.pid(11), 'proposed', jsonb_build_object('description', pg_temp.t()));
select 'waiting_proposal_of_another|' || pg_temp.v();
rollback;

-- the count never skips a row the exact test matches: for 80 fictional descriptions (words of a 120 word vocabulary, 40 to 80 words each, md5-derived so the file is repeatable) and 16 texts made from them with
-- 0 to 12 words replaced, every pair with a similarity at or above the share (0.5, 0.8, 0.95) passes the count tested at the share minus 0.0001 (violations must be 0), and the count removes pairs (it is not a no-op)
create temp table fx_words as select g w_id, 'w' || substr(md5('word' || g), 1, 3 + g % 6) w from generate_series(1, 120) g;
create temp table fx_desc as select d id, (select string_agg(w.w, ' ' order by k) from generate_series(1, 40 + (d * 7) % 41) k join fx_words w on w.w_id = 1 + (('x' || substr(md5(d::text || ':' || k), 1, 6))::bit(24)::int % 120)) description from generate_series(1, 80) d;
create temp table fx_text as
  select t id, (select string_agg(case when k <= (t % 13) then 'zz' || k else split_part(base.description, ' ', k) end, ' ' order by k) from generate_series(1, array_length(string_to_array(base.description, ' '), 1)) k) txt
    from generate_series(1, 16) t join fx_desc base on base.id = t * 5;
create temp table fx_pair as
  select x.id tid, d.id did, security.pdesc_similarity_v1(x.txt, d.description) sim,
         (select count(*) from unnest(security.pdesc_words_v1(x.txt)) w where position(w in lower(d.description)) > 0) hits, cardinality(security.pdesc_words_v1(x.txt)) n
    from fx_text x cross join fx_desc d;
select 'count_never_below_overlap|' || string_agg(share::text || ':' || violations::text || ':' || (pruned > 0)::text, ',' order by share) from (
  select s.share, count(*) filter (where p.sim >= s.share and not (p.hits >= (s.share - 0.0001) * p.n)) violations, count(*) filter (where not (p.hits >= (s.share - 0.0001) * p.n)) pruned
    from (values (0.5), (0.8), (0.95)) s(share) cross join fx_pair p group by s.share) z;
select 'pairs_that_match_exactly|' || (select count(*) from fx_pair where sim >= 0.5) || ':' || (select count(*) from fx_pair where sim >= 0.8);
