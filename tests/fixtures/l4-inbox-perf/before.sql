-- CF-247 Layer 4 Inbox performance fixture, before migration 20261104440000: what the live definitions return and how long they take on the
-- production-scale seed, kept in fx.* to compare after the migration. Scratch PostgreSQL only.
create schema if not exists fx;
create table fx.v1_before as select to_jsonb(i) j from security.layer4_inbox_items_v1() i;
create table fx.timing(at_stage text, action text, ms numeric, primary key (at_stage, action));
create table fx.reply(action text primary key, r jsonb);

-- each read in its own transaction, as each call of the screen is (the live function keeps its temporary table until the transaction ends)
select set_config('fx.uid', 'b0000000-0000-0000-0000-000000000006', false), set_config('fx.rank', '6', false) \gset
do $$ declare t timestamptz := clock_timestamp(); r jsonb; begin
  r := public.admin_layer4_inbox('summary', '{}');
  insert into fx.timing values ('before', 'summary', round(extract(epoch from clock_timestamp() - t) * 1000, 1)); insert into fx.reply values ('summary', r);
end $$;
do $$ declare t timestamptz := clock_timestamp(); r jsonb; begin
  r := public.admin_layer4_inbox('universities', '{"limit": 25, "offset": 0}');
  insert into fx.timing values ('before', 'universities', round(extract(epoch from clock_timestamp() - t) * 1000, 1)); insert into fx.reply values ('universities', r);
end $$;
do $$ declare t timestamptz := clock_timestamp(); r jsonb; begin
  r := public.admin_layer4_inbox('items', jsonb_build_object('provider_id', (select x.r->'items'->0->>'provider_id' from fx.reply x where x.action = 'universities'), 'limit', 25));
  insert into fx.timing values ('before', 'items_first_university', round(extract(epoch from clock_timestamp() - t) * 1000, 1)); insert into fx.reply values ('items_first_university', r);
end $$;
do $$ declare t timestamptz := clock_timestamp(); r jsonb; begin
  r := public.admin_layer4_inbox('items', '{"provider_id": "10000000-0000-0000-0000-000000000007", "kind": "aer_review", "limit": 25}');
  insert into fx.timing values ('before', 'items_aer_pill', round(extract(epoch from clock_timestamp() - t) * 1000, 1)); insert into fx.reply values ('items_aer_pill', r);
end $$;
do $$ declare t timestamptz := clock_timestamp(); r jsonb; begin
  r := public.admin_layer4_inbox('items', '{"kind": "course_link", "limit": 25}');
  insert into fx.timing values ('before', 'items_kind_course_link', round(extract(epoch from clock_timestamp() - t) * 1000, 1)); insert into fx.reply values ('items_kind_course_link', r);
end $$;
do $$ begin raise notice 'B0 before: % waiting items; timings (ms) %', (select count(*) from fx.v1_before), (select jsonb_object_agg(action, ms) from fx.timing where at_stage = 'before'); end $$;
