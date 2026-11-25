-- PROBE carrier (do not merge): read-backs through the rolled-back rehearsal. Replaces: nothing. Retires: nothing.
create or replace function pg_temp.ex(q text) returns text language plpgsql as $f$
declare r record; o text := ''; begin
  for r in execute 'explain (analyze, buffers, format text) ' || q loop o := o || r."QUERY PLAN" || chr(10); end loop; return o; end $f$;
select 1;
