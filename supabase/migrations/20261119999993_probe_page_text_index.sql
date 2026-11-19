-- temporary probe (not for merge): the page-text claim with a partial covering index, inside a rolled-back dry run
create or replace function pg_temp.ex(q text) returns text language plpgsql as $f$
declare r text; o text := '';
begin
  for r in execute 'explain (analyze, timing on, costs off) ' || q loop o := o || r || ' | '; end loop;
  return o;
end $f$;
create index coverage_course_pages_bound_read_course_idx on pipeline.coverage_course_pages (course_id) include (evidence_id)
  where status = 'bound' and read_status = 'read';
analyze pipeline.coverage_course_pages;
