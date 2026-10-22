-- CF-247 (22 Oct 2026). Found on the watchdog's second live run (10:19 UTC): Read course pages was called Stuck although 18 pages were
-- read in the hour, because its last-finished time counted only pages read as the right page, while its finished count also counts pages
-- read and found to be another page. A queue that finished anything in the progress window is not Stuck, Waiting or Out of toolset, and
-- the course page reader's last-finished time counts every page it read. The one alert this raised was withdrawn before it was sent.
-- Replaces: security.queue_watch_run_v1 (md5-guarded edit); pipeline.queue_watch row course_page_read (progress_sql)
-- Retires: nothing
do $edit$
declare v_def text := pg_get_functiondef('security.queue_watch_run_v1(boolean)'::regprocedure);
        v_old text := $o$coalesce(v_last, '-infinity') < now() - v_stuck_default$o$;
begin
  if position('v_done = 0 and coalesce(v_last' in v_def) > 0 then return; end if;
  if md5(v_def) <> 'ce7eac324e9f6731edf20ad57a99c212' then raise exception 'live security.queue_watch_run_v1 differs from the definition this change edits'; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 3 then raise exception 'the no-progress test must occur three times'; end if;
  execute replace(v_def, v_old, $n$v_done = 0 and coalesce(v_last, '-infinity') < now() - v_stuck_default$n$);
end $edit$;

update pipeline.queue_watch set progress_sql = $q$select max(read_at) from pipeline.coverage_course_pages where read_status is not null and read_status not in ('fetch_failed', 'blocked')$q$
 where key = 'course_page_read' and progress_sql = $q$select max(read_at) from pipeline.coverage_course_pages where read_status = 'read'$q$;

update pipeline.queue_watch_alerts set sent_at = now(), sent_via = 'withdrawn: false Stuck (fixed by 20261022037000)'
 where key = 'course_page_read' and state = 'stuck' and sent_at is null;
update pipeline.platform_issues set resolved_at = now() where check_key = 'queue_watch:course_page_read' and resolved_at is null;
