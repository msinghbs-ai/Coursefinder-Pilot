-- Guards: F-CDESC a recovered description keeps its opening sentence (read of recovered descriptions, 13 Nov 2026), migration 20261113320000: a reading whose first sentence was set aside for a fault is not recovered
-- (what is left would read as a fragment) and stays held; a reading that loses a later sentence is recovered as before. Every row is invented. Runs after the cdesc-machine prelude (lines 5 to 88) and the cdesc-subset helpers (lines 5 to 75).
create function pg_temp.ok(n int, k int) returns jsonb language sql as $$ -- a clean sentence in the reader's own words (nine words; every word is in the quote; substance 6)
  select jsonb_build_object('text', 'The ' || pg_temp.w(n, k) || ' unit explores ' || pg_temp.w(n, k + 20) || ' and ' || pg_temp.w(n, k + 40) || ' in depth.',
                            'quote', 'In depth, the ' || pg_temp.w(n, k) || ' unit explores ' || pg_temp.w(n, k + 20) || ' and also ' || pg_temp.w(n, k + 40) || ' within the programme of study.', 'on_page', true) $$;
create function pg_temp.plan(n int) returns jsonb language sql as $$ select security.cdesc_subset_plan_v1(pg_temp.cid(n), (select provider_id from catalogue.courses where id = pg_temp.cid(n)), (select value from pipeline.field_enrich_items where id = pg_temp.rd(n))) $$;
create function pg_temp.kept(n int) returns text language sql as $$ select (pg_temp.plan(n)->'subset'->'kept')::text $$;
create function pg_temp.descr(n int) returns text language sql as $$ select description from catalogue.courses where id = pg_temp.cid(n) $$;
-- 921 four sentences, the first an unsupported claim: before, the other three were published without the opening sentence
select pg_temp.held(921, 1, pg_temp.arr(pg_temp.bad(921, 1, 'claim'), pg_temp.ok(921, 2), pg_temp.ok(921, 3), pg_temp.ok(921, 4)));
-- 922 four sentences, the second an unsupported claim: the first, third and fourth are kept, as before
select pg_temp.held(922, 1, pg_temp.arr(pg_temp.ok(922, 1), pg_temp.bad(922, 2, 'claim'), pg_temp.ok(922, 3), pg_temp.ok(922, 4)));
-- 923 the first and third fail: nothing that starts the description is left
select pg_temp.held(923, 1, pg_temp.arr(pg_temp.bad(923, 1, 'claim'), pg_temp.ok(923, 2), pg_temp.bad(923, 3, 'claim'), pg_temp.ok(923, 4), pg_temp.ok(923, 5)));
select pg_temp.expect('REGRESSION plan: a reading whose first sentence was set aside is not recovered (921 opening_sentence_dropped)', pg_temp.plan(921)->>'rule' = 'opening_sentence_dropped' and not coalesce((pg_temp.plan(921)->>'ok')::boolean, false));
select pg_temp.expect('REGRESSION plan: the same when a later sentence fails as well (923 opening_sentence_dropped)', pg_temp.plan(923)->>'rule' = 'opening_sentence_dropped');
select pg_temp.expect('plan: a reading that loses a later sentence is recovered as before (922: 1, 3, 4 kept)', (pg_temp.plan(922)->>'ok')::boolean and pg_temp.kept(922) = '[1, 3, 4]');
select pg_temp.recover();
select pg_temp.expect('REGRESSION recovery: 921 and 923 are not admitted and no Layer 4 item is made for them; the attempt is noted with its cause', pg_temp.descr(921) is null and pg_temp.descr(923) is null and pg_temp.l4(921) = 0 and pg_temp.l4(923) = 0
  and (select value->'subset_attempt'->>'result' from pipeline.field_enrich_items where id = pg_temp.rd(921)) = 'opening_sentence_dropped');
select pg_temp.expect('recovery: 922 is admitted by the machine rule and begins with its first sentence', pg_temp.descr(922) like (select btrim(x->>'text') from jsonb_array_elements((select value->'subset_of_reading'->'original'->'sentences' from pipeline.field_enrich_items where id = pg_temp.rd(922))) with ordinality e(x, i) where i = 1) || '%');
do $$ begin if exists (select 1 from g_t where not ok) then raise notice 'cop: FAILURES'; else raise notice 'cop: all % checks pass', (select count(*) from g_t); end if; end $$;
