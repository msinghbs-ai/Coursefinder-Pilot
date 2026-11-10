\set ON_ERROR_STOP on
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
do $$ declare t jsonb; begin
  t := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok((t->>'back_pressure')::boolean and (t->>'course_reads')::int = 0 and (t->>'layer4_waiting')::int = 12, 'before: 12 pending items against the limit of 10 stop every new course read (the live defect)');
  perform pg_temp.ok(not (select evidence ? 'route' from security.aer_current_findings_v1() where root_cause = 'no_source' limit 1), 'before: the no_source finding names no route');
end $$;
