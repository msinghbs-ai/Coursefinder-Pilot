-- Guards: F-CDESC recovery and throughput (S2-CF directive, Platform Admin 13 Nov 2026 10:25), migration 20261113280000: the subset plan tests a sentence as the check does (title and provider left out), sets a back-pointing sentence aside with the sentence it points to instead of failing the reading,
-- the recovery looks at copied_sentence holds, and nothing else moves: size-only faults stay held, a remainder of nothing stays held, a locked course is not touched. Every row is invented. Runs after the cdesc-machine prelude (lines 5 to 88) and the cdesc-subset helpers (lines 5 to 75).
create function pg_temp.ok(n int, k int) returns jsonb language sql as $$ -- one clean sentence in the reader's own words (nine words, so no ten-word run of the page; every word is in the quote)
  select jsonb_build_object('text', 'The ' || pg_temp.w(n, k) || ' unit explores ' || pg_temp.w(n, k + 20) || ' and ' || pg_temp.w(n, k + 40) || ' in depth.',
                            'quote', 'In depth, the ' || pg_temp.w(n, k) || ' unit explores ' || pg_temp.w(n, k + 20) || ' and also ' || pg_temp.w(n, k + 40) || ' within the programme of study.', 'on_page', true) $$;
create function pg_temp.back(n int, k int) returns jsonb language sql as $$ -- a clean sentence that opens by pointing back
  select jsonb_build_object('text', 'It also builds on ' || pg_temp.w(n, k) || ' in later units.', 'quote', 'Later units also build on ' || pg_temp.w(n, k) || ' and it is assessed.', 'on_page', true) $$;
create function pg_temp.plan(n int) returns jsonb language sql as $$ select security.cdesc_subset_plan_v1(pg_temp.cid(n), (select provider_id from catalogue.courses where id = pg_temp.cid(n)), (select value from pipeline.field_enrich_items where id = pg_temp.rd(n))) $$;
create function pg_temp.kept(n int) returns text language sql as $$ select (pg_temp.plan(n)->'subset'->'kept')::text $$;
create function pg_temp.dcause(n int) returns text language sql as $$ select string_agg((x->>'index') || ':' || (x->>'cause'), ',' order by (x->>'index')::int) from jsonb_array_elements(coalesce(pg_temp.plan(n)->'subset'->'dropped', pg_temp.plan(n)->'dropped')) x $$;
create function pg_temp.descr(n int) returns text language sql as $$ select description from catalogue.courses where id = pg_temp.cid(n) $$;

-- 801 a claim, then a sentence pointing back to it, then two clean sentences
select pg_temp.held(801, 1, pg_temp.arr(pg_temp.bad(801, 1, 'claim'), pg_temp.back(801, 2), pg_temp.ok(801, 3), pg_temp.ok(801, 4)));
-- 802 a chain: a claim, two sentences each pointing back, then two clean sentences
select pg_temp.held(802, 1, pg_temp.arr(pg_temp.bad(802, 1, 'claim'), pg_temp.back(802, 2), pg_temp.back(802, 3), pg_temp.ok(802, 4), pg_temp.ok(802, 5)));
-- 803 a pointing-back sentence after a KEPT sentence stays (nothing before it is set aside); the claim at the end is set aside
select pg_temp.held(803, 1, pg_temp.arr(pg_temp.ok(803, 1), pg_temp.back(803, 2), pg_temp.ok(803, 3), pg_temp.bad(803, 4, 'claim')));
-- 804 the first sentence passes only on the words of the course's own title: the check refuses it (title left out), and so must the plan
select pg_temp.mkc(804, 1);
update catalogue.courses set canonical_title = 'Advanced Diploma of Marine Engineering Practice' where id = pg_temp.cid(804);
do $$ declare v_id bigint; v jsonb := pg_temp.arr(
    jsonb_build_object('text', 'The Advanced Diploma of Marine Engineering Practice is offered by several colleges.', 'quote', 'Advanced Diploma of Marine Engineering Practice overview and fees', 'on_page', true), pg_temp.ok(804, 2), pg_temp.ok(804, 3));
begin
  v_id := pg_temp.reading(804, 1, 'queued', null, v, true);
  perform security.enrich_course_text_record_v1(v_id, jsonb_build_object('value', (select value from pipeline.field_enrich_items where id = v_id), 'model', 'openai/gpt-4.1-mini', 'prompt_version', 'course-text-v2', 'worker', 'w'));
end $$;
-- 805 a copied sentence (ten words of the page in order) and two clean ones: held as copied_sentence
select pg_temp.held(805, 1, pg_temp.arr(pg_temp.sn(805, 1), pg_temp.ok(805, 2), pg_temp.ok(805, 3)));
-- 806 everything is set aside (a claim and the sentence pointing back to it): nothing is left
select pg_temp.held(806, 1, pg_temp.arr(pg_temp.bad(806, 1, 'claim'), pg_temp.back(806, 2)));
-- 807 five clean sentences: the only fault is the count, nothing is cut
select pg_temp.held(807, 1, pg_temp.arr(pg_temp.ok(807, 1), pg_temp.ok(807, 2), pg_temp.ok(807, 3), pg_temp.ok(807, 4), pg_temp.ok(807, 5)));
-- 808 as 801, but the course is locked by hand
select pg_temp.held(808, 1, pg_temp.arr(pg_temp.bad(808, 1, 'claim'), pg_temp.back(808, 2), pg_temp.ok(808, 3), pg_temp.ok(808, 4)));
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', pg_temp.cid(808), 'description', 'value');
-- 809 a claim, then a sentence that leans on it with an opener the first list missed ("Students then ..."), then two clean sentences
select pg_temp.held(809, 1, pg_temp.arr(pg_temp.bad(809, 1, 'claim'),
  jsonb_build_object('text', 'Students then apply ' || pg_temp.w(809, 2) || ' in later units.', 'quote', 'In later units students then apply ' || pg_temp.w(809, 2) || ' and are assessed.', 'on_page', true), pg_temp.ok(809, 3), pg_temp.ok(809, 4)));
-- 810 a sentence that copies ten words of the page in a run that goes through the course's own title (the title is left out of the other tests, not of the copy test), then a claim, then two clean sentences
select pg_temp.mkc(810, 1);
update catalogue.courses set canonical_title = 'Advanced Diploma of Marine Engineering Practice' where id = pg_temp.cid(810);
select pg_temp.reading(810, 1, 'skipped', 'held: unsupported_claim: x', pg_temp.arr(
  jsonb_build_object('text', 'The Advanced Diploma of Marine Engineering Practice explores hull design and propulsion systems.', 'quote', 'In depth, the Advanced Diploma of Marine Engineering Practice explores hull design and propulsion systems for vessels.', 'on_page', true),
  pg_temp.bad(810, 2, 'claim'), pg_temp.ok(810, 3), pg_temp.ok(810, 4)), true);

select pg_temp.expect('holds: the readings are held by the reader''s check for the expected reasons (801 claim, 804 unsupported sentence, 805 copied sentence, 807 sentence count)',
  (select reason from pipeline.field_enrich_items where id = pg_temp.rd(801)) like 'held: unsupported_claim:%' and (select reason from pipeline.field_enrich_items where id = pg_temp.rd(804)) like 'held: unsupported_sentence:%'
  and (select reason from pipeline.field_enrich_items where id = pg_temp.rd(805)) like 'held: copied_sentence:%' and (select reason from pipeline.field_enrich_items where id = pg_temp.rd(807)) like 'held: sentence_count:%');
select pg_temp.expect('REGRESSION plan: a sentence pointing back to a sentence set aside is set aside with it and the rest is kept (801: 1 claim, 2 with it; 3 and 4 kept)',
  (pg_temp.plan(801)->>'ok')::boolean and pg_temp.kept(801) = '[3, 4]' and pg_temp.dcause(801) = '1:unsupported_claim,2:depends_on_dropped_sentence');
select pg_temp.expect('REGRESSION plan: a chain of pointing-back sentences is followed (802: 1, 2 and 3 set aside; 4 and 5 kept)',
  (pg_temp.plan(802)->>'ok')::boolean and pg_temp.kept(802) = '[4, 5]' and pg_temp.dcause(802) = '1:unsupported_claim,2:depends_on_dropped_sentence,3:depends_on_dropped_sentence');
select pg_temp.expect('plan: a pointing-back sentence whose sentence before it is kept stays (803: 1, 2 and 3 kept, only the claim set aside)',
  (pg_temp.plan(803)->>'ok')::boolean and pg_temp.kept(803) = '[1, 2, 3]' and pg_temp.dcause(803) = '4:unsupported_claim');
select pg_temp.expect('REGRESSION plan: a sentence that stands only on the words of the course''s own title is set aside, as the check refuses it (804: 2 and 3 kept)',
  (pg_temp.plan(804)->>'ok')::boolean and pg_temp.kept(804) = '[2, 3]' and pg_temp.dcause(804) = '1:unsupported_sentence');
select pg_temp.expect('plan: nothing left stays held (806 remainder_below_minimum) and a size-only fault is not cut (807 over_length_needs_decision)',
  pg_temp.plan(806)->>'rule' = 'remainder_below_minimum' and pg_temp.plan(807)->>'rule' = 'over_length_needs_decision');
select pg_temp.expect('plan: what is kept is the reading''s own sentences, unchanged and in order (801 text is sentences 3 and 4)',
  pg_temp.plan(801)->>'text' = (select string_agg(btrim(x->>'text'), ' ' order by o) from jsonb_array_elements((select value->'sentences' from pipeline.field_enrich_items where id = pg_temp.rd(801))) with ordinality e(x, o) where o in (3, 4)));
select pg_temp.expect('REGRESSION plan: a sentence that leans on a sentence set aside with "Students then ..." is set aside with it (809: 3 and 4 kept)',
  (pg_temp.plan(809)->>'ok')::boolean and pg_temp.kept(809) = '[3, 4]' and pg_temp.dcause(809) = '1:unsupported_claim,2:depends_on_dropped_sentence');
select pg_temp.expect('plan: ten words copied from the page in a run through the course''s title are still copied wording (810: sentence 1 set aside as copied_sentence, 3 and 4 kept)',
  (pg_temp.plan(810)->>'ok')::boolean and pg_temp.kept(810) = '[3, 4]' and pg_temp.dcause(810) = '1:copied_sentence,2:unsupported_claim');
create temporary table crt_before as select n, (select value->'sentences' from pipeline.field_enrich_items where id = pg_temp.rd(n)) s from generate_series(801, 810) n;
create temporary table crt_run as select pg_temp.recover() r;
select pg_temp.expect('REGRESSION recovery: 801, 802 and 804 are admitted by the machine rule with exactly the kept sentences, via subset_of_reading',
  pg_temp.descr(801) = (select string_agg(btrim(x->>'text'), ' ' order by o) from crt_before b, jsonb_array_elements(b.s) with ordinality e(x, o) where b.n = 801 and o in (3, 4)) and pg_temp.via(801) = 'subset_of_reading'
  and pg_temp.descr(802) = (select string_agg(btrim(x->>'text'), ' ' order by o) from crt_before b, jsonb_array_elements(b.s) with ordinality e(x, o) where b.n = 802 and o in (4, 5))
  and pg_temp.descr(804) = (select string_agg(btrim(x->>'text'), ' ' order by o) from crt_before b, jsonb_array_elements(b.s) with ordinality e(x, o) where b.n = 804 and o in (2, 3)));
select pg_temp.expect('REGRESSION recovery: a reading held as copied_sentence is looked at and admitted without the copied sentence (805: sentences 2 and 3)',
  pg_temp.descr(805) = (select string_agg(btrim(x->>'text'), ' ' order by o) from crt_before b, jsonb_array_elements(b.s) with ordinality e(x, o) where b.n = 805 and o in (2, 3)) and pg_temp.via(805) = 'subset_of_reading');
select pg_temp.expect('recovery: 806 (nothing left), 807 (size only) and 808 (locked by hand) are not admitted and no Layer 4 item is made for them',
  pg_temp.descr(806) is null and pg_temp.descr(807) is null and pg_temp.descr(808) is null and pg_temp.l4(806) = 0 and pg_temp.l4(807) = 0 and pg_temp.l4(808) = 0);
select pg_temp.expect('recovery: the admitted text holds no sentence that was set aside (no claim sentence, no pointing-back sentence, no copied sentence in 801, 802, 805)',
  pg_temp.descr(801) !~ 'highly employed|It also builds' and pg_temp.descr(802) !~ 'highly employed|It also builds' and pg_temp.descr(805) !~ 'within the programme\.');
create function pg_temp.pb() returns boolean language plpgsql as $$
begin
  return security.cdesc_points_back_v1('Students then apply x.') and security.cdesc_points_back_v1('As such, x is covered.') and security.cdesc_points_back_v1('Finally, x.') and not security.cdesc_points_back_v1('Thenar anatomy is covered.')
     and security.cdesc_points_back_v1('It also builds on x.') and security.cdesc_points_back_v1('  The program covers x.') and security.cdesc_points_back_v1('"Quoted" opening.')
     and not security.cdesc_points_back_v1('Students explore x.') and not security.cdesc_points_back_v1('Italian is taught.') and not security.cdesc_points_back_v1(null);
exception when undefined_function then return false;
end $$;
select pg_temp.expect('REGRESSION points back: the one definition answers as the plan''s test did (pronoun, "the program", "<subject> then", "as such", a quote; not an ordinary opening, not a word that only starts like one)', pg_temp.pb());
do $$ begin if exists (select 1 from g_t where not ok) then raise notice 'crt: FAILURES'; else raise notice 'crt: all % checks pass', (select count(*) from g_t); end if; end $$;
