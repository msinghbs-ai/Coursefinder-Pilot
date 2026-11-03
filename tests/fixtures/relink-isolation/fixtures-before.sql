-- the live university step (before this change) on the seed: its answers are kept to compare, then cleared. Scratch PostgreSQL only.
update fx.slugs_calls set n = 0;
select security.course_relink_provider_v1('00000000-0000-0000-0000-0000000000a2', 100);
create table fx.before_slugs as select n from fx.slugs_calls;
create table fx.before as select course_id, provider_id, state, candidates, sources, reason from pipeline.course_relink;
create table fx.before_binds as select course_id, url, basis from fx.binds;
delete from pipeline.course_relink; delete from pipeline.course_link_search; delete from fx.binds; update fx.slugs_calls set n = 0;
do $$ begin
  if (select n from fx.before_slugs) < 300 then raise exception 'FAILED: the live step should work out title forms once per address (got %)', (select n from fx.before_slugs); end if;
  raise notice 'ok: before: the live step works out the title forms % times for 6 courses and 305 addresses', (select n from fx.before_slugs);
end $$;
