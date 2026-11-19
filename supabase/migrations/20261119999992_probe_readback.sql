-- temporary read-back carrier (not for merge): the probe expression is the read; pg_temp.ex returns a query plan
create or replace function pg_temp.ex(q text) returns text language plpgsql as $f$
declare r text; o text := '';
begin
  for r in execute 'explain (analyze, timing on, costs off) ' || q loop o := o || r || ' | '; end loop;
  return o;
end $f$;
