-- CF-247 platform health: a check is due when its cadence has (nearly) passed. The first version allowed only 30 seconds of
-- slack, so a manual forced run 8 minutes before a scheduled run made that scheduled run skip every check (29 Sep 13:28 UTC).
-- Slack is now 30% of the cadence, capped at 3 minutes (10-minute checks: due after 7 minutes; hourly: after 57 minutes).
do $patch$
begin
  if (select md5(prosrc) from pg_proc where oid='security.platform_health_due_v1(text,boolean)'::regprocedure)<>'1bb34684b80dc8b8993fa8bdca3f4272' then
    raise exception 'platform_health_due_v1 changed since review; not replaced'; end if;
end $patch$;

create or replace function security.platform_health_due_v1(p_key text, p_force boolean)
returns boolean language sql stable set search_path to 'pg_catalog','pipeline'
as $fn$
  select p_force or coalesce((select c.checked_at is null
                                  or c.checked_at <= now() - make_interval(mins=>c.cadence_minutes) + least(interval '3 minutes', make_interval(mins=>c.cadence_minutes)*0.3)
                               from pipeline.platform_health_checks c where c.key=p_key), true)
$fn$;
revoke all on function security.platform_health_due_v1(text,boolean) from public, anon, authenticated;
