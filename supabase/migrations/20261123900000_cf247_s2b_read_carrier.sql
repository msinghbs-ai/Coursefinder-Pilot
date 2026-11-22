-- CF-247 S2-Build read carrier (never merged; rolled-back dry runs only). Defines temporary helpers for the probe.
-- Replaces: nothing. Retires: nothing.
create or replace function pg_temp.j(q text) returns text language plpgsql as $f$
declare r text; begin execute 'select coalesce(json_agg(t)::text, ''[]'') from (' || q || ') t' into r; return r; end $f$;
create or replace function pg_temp.x(q text) returns text language plpgsql as $f$
declare r text; l text; begin r := ''; for l in execute 'explain (analyze, buffers, costs off, timing on) ' || q loop r := r || l || E'\n'; end loop; return r; end $f$;
create or replace function pg_temp.t(q text, n int default 3) returns text language plpgsql as $f$
declare t0 timestamptz; r text := ''; i int; d text; begin
  for i in 1..n loop t0 := clock_timestamp(); execute 'select length(coalesce((' || q || ')::text, ''''))' into d;
    r := r || round(extract(epoch from clock_timestamp() - t0) * 1000) || 'ms/' || d || 'c '; end loop; return r; end $f$;
select 1;
