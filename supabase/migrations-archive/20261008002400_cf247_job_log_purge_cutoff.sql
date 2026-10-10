-- CF-247, 8 Oct 2026: the Scheduled-job run log purge could not finish. It removed run records older than 7 days counted from now,
-- and scheduled jobs add records continuously, so every 2-minute batch found newly aged records and the run never reached zero
-- (42,740 records removed before a Platform Admin stopped it; the course-directory purge was queued behind it). The cut-off is now
-- 7 days before the run started, so a run ends once the records that were old at its start are gone. Patch of
-- security.retention_tick_v1 (migration 1300, pasted) behind an md5 guard and an exact anchor; nothing else changes.
do $p$
declare d text; a text := $a$d.start_time < now() - interval '7 days' limit 20000$a$;
begin
  if (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'security.retention_tick_v1()'::regprocedure) is distinct from '1c12893558eb9f633329792b2f8bebcb' then
    raise exception 'retention_tick_v1 is not the migration 1300 definition; refusing to patch it';
  end if;
  d := pg_get_functiondef('security.retention_tick_v1()'::regprocedure);
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'anchor not found exactly once'; end if;
  d := replace(d, a, $b$d.start_time < coalesce(r.started_at, now()) - interval '7 days' limit 20000$b$);
  execute d;
end $p$;
