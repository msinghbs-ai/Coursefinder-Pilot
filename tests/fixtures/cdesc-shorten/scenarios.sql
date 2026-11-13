-- Guards: F-CDESC shortening by whole sentences (Platform Admin 13 Nov 2026 12:16, conditional approval), migration 20261113310000: a reading over its sentence or character limit is brought within it by setting aside whole sentences
-- (least course-specific substance first, the later on a tie, never the first kept sentence, a sentence pointing back to one set aside goes with it), nothing is cut inside a sentence, a reading that cannot fit stays held, a locked course is not touched,
-- and the record keeps the original, what was set aside and why. Every row is invented. Runs after the cdesc-machine prelude (lines 5 to 88) and the cdesc-subset helpers (lines 5 to 75).
create function pg_temp.ok(n int, k int) returns jsonb language sql as $$ -- a clean sentence in the reader's own words (nine words; every word is in the quote; substance 6)
  select jsonb_build_object('text', 'The ' || pg_temp.w(n, k) || ' unit explores ' || pg_temp.w(n, k + 20) || ' and ' || pg_temp.w(n, k + 40) || ' in depth.',
                            'quote', 'In depth, the ' || pg_temp.w(n, k) || ' unit explores ' || pg_temp.w(n, k + 20) || ' and also ' || pg_temp.w(n, k + 40) || ' within the programme of study.', 'on_page', true) $$;
create function pg_temp.thin() returns jsonb language sql as $$ -- a clean, supported sentence with little in it (substance 3)
  select jsonb_build_object('text', 'Graduates gain practical skills.', 'quote', 'Our graduates gain many practical skills over time.', 'on_page', true) $$;
create function pg_temp.back(n int, k int) returns jsonb language sql as $$ -- a clean sentence that opens by pointing back
  select jsonb_build_object('text', 'It also builds on ' || pg_temp.w(n, k) || ' in later units.', 'quote', 'Later units also build on ' || pg_temp.w(n, k) || ' and it is assessed.', 'on_page', true) $$;
create function pg_temp.lng(n int, k int, m int) returns jsonb language sql as $$ -- a long clean sentence: m topics, listed in the other order in the quote (no ten-word run of the page)
  select jsonb_build_object('text', 'The ' || pg_temp.w(n, k) || ' unit explores ' || (select string_agg(pg_temp.w(n, k * 100 + j), ', ' order by j) from generate_series(1, m) j) || ' in depth.',
                            'quote', 'In depth: ' || (select string_agg(pg_temp.w(n, k * 100 + j), '; ' order by j desc) from generate_series(1, m) j) || '. The ' || pg_temp.w(n, k) || ' unit explores these.', 'on_page', true) $$;
create function pg_temp.plan(n int) returns jsonb language sql as $$ select security.cdesc_subset_plan_v1(pg_temp.cid(n), (select provider_id from catalogue.courses where id = pg_temp.cid(n)), (select value from pipeline.field_enrich_items where id = pg_temp.rd(n))) $$;
create function pg_temp.kept(n int) returns text language sql as $$ select (pg_temp.plan(n)->'subset'->'kept')::text $$;
create function pg_temp.dcause(n int) returns text language sql as $$ select string_agg((x->>'index') || ':' || (x->>'cause'), ',' order by (x->>'index')::int) from jsonb_array_elements(coalesce(pg_temp.plan(n)->'subset'->'dropped', pg_temp.plan(n)->'dropped')) x $$;
create function pg_temp.descr(n int) returns text language sql as $$ select description from catalogue.courses where id = pg_temp.cid(n) $$;
create function pg_temp.pick(p_n int, VARIADIC o int[]) returns text language plpgsql as $$ begin return (select string_agg(btrim(x->>'text'), ' ' order by e.i) from crs_before b, jsonb_array_elements(b.s) with ordinality e(x, i) where b.n = p_n and e.i = any (o)); end $$; -- the reading's own sentences, as first read

-- 901 five clean sentences of equal substance: the last is set aside
select pg_temp.held(901, 1, pg_temp.arr(pg_temp.ok(901, 1), pg_temp.ok(901, 2), pg_temp.ok(901, 3), pg_temp.ok(901, 4), pg_temp.ok(901, 5)));
-- 902 five sentences, the second says little: it is the one set aside, not the last
select pg_temp.held(902, 1, pg_temp.arr(pg_temp.ok(902, 1), pg_temp.thin(), pg_temp.ok(902, 3), pg_temp.ok(902, 4), pg_temp.ok(902, 5)));
-- 903 the first sentence says little: it is still never set aside (it opens the description); the last of the others goes
select pg_temp.held(903, 1, pg_temp.arr(pg_temp.thin(), pg_temp.ok(903, 2), pg_temp.ok(903, 3), pg_temp.ok(903, 4), pg_temp.ok(903, 5)));
-- 904 the fourth says little and the fifth points back to it: setting the fourth aside would take the fifth with it, so the fifth alone goes (the lesser loss)
select pg_temp.held(904, 1, pg_temp.arr(pg_temp.ok(904, 1), pg_temp.ok(904, 2), pg_temp.ok(904, 3), pg_temp.thin(), pg_temp.back(904, 5)));
-- 905 four long sentences, over the character limit only: one whole sentence goes, none is cut
select pg_temp.held(905, 1, pg_temp.arr(pg_temp.lng(905, 1, 16), pg_temp.lng(905, 2, 16), pg_temp.lng(905, 3, 16), pg_temp.lng(905, 4, 16)));
-- 906 one sentence that is itself over the character limit: it cannot fit and stays held
select pg_temp.held(906, 1, pg_temp.arr(pg_temp.lng(906, 1, 70)));
-- 907 as 901, but the course is locked by hand
select pg_temp.held(907, 1, pg_temp.arr(pg_temp.ok(907, 1), pg_temp.ok(907, 2), pg_temp.ok(907, 3), pg_temp.ok(907, 4), pg_temp.ok(907, 5)));
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', pg_temp.cid(907), 'description', 'value');
-- 908 six sentences (held for the count), the second an unsupported claim: a failing sentence and a size problem together are outside the approval, so it is not shortened
select pg_temp.held(908, 1, pg_temp.arr(pg_temp.ok(908, 1), pg_temp.bad(908, 2, 'claim'), pg_temp.ok(908, 3), pg_temp.ok(908, 4), pg_temp.ok(908, 5), pg_temp.ok(908, 6)));
-- 909 five sentences, the second a short sentence about registration: it is protected, and the last of the others goes
select pg_temp.held(909, 1, pg_temp.arr(pg_temp.ok(909, 1), jsonb_build_object('text', 'Graduates can apply for registration.', 'quote', 'Graduates can apply for professional registration after the course.', 'on_page', true), pg_temp.ok(909, 3), pg_temp.ok(909, 4), pg_temp.ok(909, 5)));
-- 910 five sentences: the second says little and the third and fourth lean on it ("It ..."): setting the second aside would take three, so the fourth alone goes
select pg_temp.held(910, 1, pg_temp.arr(pg_temp.ok(910, 1), pg_temp.thin(), pg_temp.back(910, 3), pg_temp.back(910, 4), pg_temp.ok(910, 5)));
-- 911 five sentences, every one after the first about a registration, placement, qualification or pathway: no choice is left that keeps them, so it stays held
select pg_temp.held(911, 1, pg_temp.arr(pg_temp.ok(911, 1), jsonb_build_object('text', 'Graduates can apply for registration.', 'quote', 'Graduates can apply for professional registration after the course.', 'on_page', true),
  jsonb_build_object('text', 'A work placement is part of study.', 'quote', 'A supervised work placement is part of your study.', 'on_page', true),
  jsonb_build_object('text', 'Entry needs a prior qualification.', 'quote', 'Entry needs a prior qualification in a related field.', 'on_page', true),
  jsonb_build_object('text', 'Graduates gain a pathway to further study.', 'quote', 'Graduates gain a pathway to further study at degree level.', 'on_page', true)));
-- 912 over the character limit only: two short sentences and a long last one. Setting the long one aside fits at once; the short ones are not taken first
select pg_temp.held(912, 1, pg_temp.arr(pg_temp.lng(912, 1, 20), pg_temp.thin(), jsonb_build_object('text', 'Students attend weekly workshops.', 'quote', 'All students attend weekly workshops on campus.', 'on_page', true), pg_temp.lng(912, 4, 36)));
-- 913 the second says little and the third says "these skills" in the middle of the sentence: the third is never left without the second
select pg_temp.held(913, 1, pg_temp.arr(pg_temp.ok(913, 1), pg_temp.thin(), jsonb_build_object('text', 'Students apply these skills in a final project.', 'quote', 'Students apply these practical skills in a final industry project.', 'on_page', true), pg_temp.ok(913, 4), pg_temp.ok(913, 5)));
create temporary table crs_before as select n, (select value->'sentences' from pipeline.field_enrich_items where id = pg_temp.rd(n)) s from generate_series(901, 913) n;
select pg_temp.expect('holds: 911 and 913 are held for the sentence count, 912 for its length', (select bool_and(value->'check'->>'rule' = 'sentence_count') from pipeline.field_enrich_items where id in (pg_temp.rd(911), pg_temp.rd(913))) and (select value->'check'->>'rule' = 'length' from pipeline.field_enrich_items where id = pg_temp.rd(912)));

select pg_temp.expect('holds: the readings are held for their size (901 to 904, 907 and 908 sentence count; 905 and 906 length)',
  (select bool_and(reason like 'held: sentence_count:%') from pipeline.field_enrich_items where id in (pg_temp.rd(901), pg_temp.rd(902), pg_temp.rd(903), pg_temp.rd(904), pg_temp.rd(907), pg_temp.rd(908)))
  and (select bool_and(reason like 'held: length:%') from pipeline.field_enrich_items where id in (pg_temp.rd(905), pg_temp.rd(906))));
select pg_temp.expect('REGRESSION plan: equal sentences, the last is set aside (901: 1 to 4 kept, 5 over_limit)', (pg_temp.plan(901)->>'ok')::boolean and pg_temp.kept(901) = '[1, 2, 3, 4]' and pg_temp.dcause(901) = '5:over_limit');
select pg_temp.expect('REGRESSION plan: the sentence that says least is set aside, not simply the last (902: 2 over_limit)', (pg_temp.plan(902)->>'ok')::boolean and pg_temp.kept(902) = '[1, 3, 4, 5]' and pg_temp.dcause(902) = '2:over_limit');
select pg_temp.expect('REGRESSION plan: the first kept sentence is never set aside for size (903: 5 over_limit)', (pg_temp.plan(903)->>'ok')::boolean and pg_temp.kept(903) = '[1, 2, 3, 4]' and pg_temp.dcause(903) = '5:over_limit');
select pg_temp.expect('REGRESSION plan: the loss counts the sentences that would dangle, so one sentence goes, not two (904: 5 over_limit; 1 to 4 kept)', (pg_temp.plan(904)->>'ok')::boolean and pg_temp.kept(904) = '[1, 2, 3, 4]' and pg_temp.dcause(904) = '5:over_limit');
select pg_temp.expect('REGRESSION plan: over the character limit only, one whole sentence is set aside and the rest is within the limit (905: 1 to 3 kept)',
  (pg_temp.plan(905)->>'ok')::boolean and pg_temp.kept(905) = '[1, 2, 3]' and length(pg_temp.plan(905)->>'text') <= 700 and pg_temp.plan(905)->>'text' = pg_temp.pick(905, 1, 2, 3));
select pg_temp.expect('plan: a single sentence over the character limit cannot fit and stays held, never cut (906 over_length_needs_decision)', pg_temp.plan(906)->>'rule' = 'over_length_needs_decision');
select pg_temp.expect('plan: a reading with a failing sentence and a size problem is not shortened and stays held (908 over_length_needs_decision)', pg_temp.plan(908)->>'rule' = 'over_length_needs_decision');
select pg_temp.expect('REGRESSION plan: a sentence about registration is not the one set aside though it is the shortest (909: 5 over_limit; 2 kept)', (pg_temp.plan(909)->>'ok')::boolean and pg_temp.kept(909) = '[1, 2, 3, 4]' and pg_temp.dcause(909) = '5:over_limit');
select pg_temp.expect('REGRESSION plan: sentences that lean on a thin one are not swept away with it (910: one sentence set aside, four kept)', (pg_temp.plan(910)->>'ok')::boolean and jsonb_array_length(pg_temp.plan(910)->'subset'->'kept') = 4 and pg_temp.kept(910) like '[1, 2,%');
select pg_temp.expect('plan: when every choice would remove a protected sentence nothing is set aside and the reading stays held (911 over_length_needs_decision)', pg_temp.plan(911)->>'rule' = 'over_length_needs_decision');
select pg_temp.expect('REGRESSION plan: the choice that fits at once is taken, not the shortest sentences first (912: 4 over_limit; 1 to 3 kept)', (pg_temp.plan(912)->>'ok')::boolean and pg_temp.kept(912) = '[1, 2, 3]' and pg_temp.dcause(912) = '4:over_limit');
select pg_temp.expect('REGRESSION plan: a sentence that says "these skills" is not left behind without the sentence it refers to (913: 2 and 3 both kept, one other set aside)', (pg_temp.plan(913)->>'ok')::boolean and pg_temp.kept(913) like '[1, 2, 3,%' and jsonb_array_length(pg_temp.plan(913)->'subset'->'kept') = 4);
select pg_temp.expect('plan: every kept sentence is one of the reading''s own sentences, whole and in order (901, 902, 904)',
  pg_temp.plan(901)->>'text' = pg_temp.pick(901, 1, 2, 3, 4) and pg_temp.plan(902)->>'text' = pg_temp.pick(902, 1, 3, 4, 5) and pg_temp.plan(904)->>'text' = pg_temp.pick(904, 1, 2, 3, 4));
create temporary table crs_run as select pg_temp.recover() r;
select pg_temp.expect('REGRESSION recovery: 901, 902, 904, 905 and 909 are admitted by the machine rule with exactly the kept sentences, via subset_of_reading',
  pg_temp.descr(901) = pg_temp.pick(901, 1, 2, 3, 4) and pg_temp.descr(902) = pg_temp.pick(902, 1, 3, 4, 5) and pg_temp.descr(904) = pg_temp.pick(904, 1, 2, 3, 4) and pg_temp.descr(905) = pg_temp.pick(905, 1, 2, 3)
  and pg_temp.descr(909) = pg_temp.pick(909, 1, 2, 3, 4) and pg_temp.via(901) = 'subset_of_reading' and pg_temp.via(905) = 'subset_of_reading');
select pg_temp.expect('REGRESSION recovery: the reading keeps its original text, and the machine admission records the sentence set aside for size with its cause and the reason the reading was held (902)',
  (select value->'subset_of_reading'->'original'->>'text' from pipeline.field_enrich_items where id = pg_temp.rd(902)) = pg_temp.pick(902, 1, 2, 3, 4, 5) and pg_temp.sub(902)->'dropped'->0->>'cause' = 'over_limit' and pg_temp.sub(902)->'dropped'->0->>'text' = 'Graduates gain practical skills.' and pg_temp.sub(902)->>'cause' = 'sentence_count');
select pg_temp.expect('recovery: 906 (cannot fit), 907 (locked by hand) and 908 (a failing sentence and a size problem) are not admitted and no Layer 4 item is made for them', pg_temp.descr(906) is null and pg_temp.descr(907) is null and pg_temp.descr(908) is null and pg_temp.l4(906) = 0 and pg_temp.l4(907) = 0 and pg_temp.l4(908) = 0);
select pg_temp.expect('recovery: 911 (only protected choices) is not admitted and no Layer 4 item is made; 912 is admitted with its first three sentences', pg_temp.descr(911) is null and pg_temp.l4(911) = 0 and pg_temp.descr(912) = pg_temp.pick(912, 1, 2, 3));
do $$ begin if exists (select 1 from g_t where not ok) then raise notice 'crs: FAILURES'; else raise notice 'crs: all % checks pass', (select count(*) from g_t); end if; end $$;
