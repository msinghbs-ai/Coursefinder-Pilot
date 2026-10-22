-- CF-247 (22 Oct 2026). Found right after 20261022038000: marking the fill's central page search as asked for did not move it. The
-- worker took it, but the Firecrawl spend check refused it as not due (central pages are read again only after central_refresh_days, 30),
-- put it back and cleared the request; the task fired again the next minute (417 refusals "not_due" today, one empty worker call a
-- minute). The refresh rule is right (it stops paying twice for the same pages), so the task respects it: when the provider's central
-- pages are held until due (or by today's central share), step 3 is done with the hold noted instead of waiting.
-- The 15-minute stats count Firecrawl refusals as a gap only when the reason is not "not due" (held by design).
-- Replaces: security.admin_job_watch_v1, security.stats_15m_v1 (md5-guarded edits; the requested_at line of 20261022038000 is removed);
--   pipeline.queue_watch row central_find (pending_sql: held providers are not waiting work)
-- Retires: nothing
do $edit$
declare v_def text := pg_get_functiondef('security.admin_job_watch_v1(uuid)'::regprocedure);
        v_old text := $o$        if exists (select 1 from pipeline.provider_central_search s where s.provider_id = v_pid and s.state in ('queued', 'leased')) then
          v_phase := 'finding central pages';
          -- CF-247 22 Oct 2026: a fill asks for its central page search (the search takes only asked-for or due providers)
          update pipeline.provider_central_search s set requested_at = now() where s.provider_id = v_pid and s.state = 'queued' and s.requested_at is null;
          perform security.provider_task_fire_v1('central_find');$o$;
begin
  if position('central pages held until due' in v_def) > 0 then return; end if;
  if md5(v_def) <> '40e1c7cfd4d924dd0bb7e8f395ad4d9a' then raise exception 'live security.admin_job_watch_v1 differs from the definition this change edits'; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'central page step must occur once'; end if;
  execute replace(v_def, v_old, $n$        -- CF-247 22 Oct 2026: central pages held until due (or by today's central share) count as done for the fill; the hold is in the note
        if exists (select 1 from pipeline.provider_central_search s where s.provider_id = v_pid and s.state in ('queued', 'leased'))
           and not security.flag_provider_held_v1(v_pid, array['central_not_due', 'central_budget']) then
          v_phase := 'finding central pages';
          perform security.provider_task_fire_v1('central_find');$n$);
end $edit$;

do $edit$
declare v_def text := pg_get_functiondef('security.stats_15m_v1(text[])'::regprocedure);
        v_old text := $o$((x->>'used')::numeric >= (x->>'share')::numeric or (x->>'refused')::numeric > 0)$o$;
begin
  if position('r.reason <> ''not_due''' in v_def) > 0 then return; end if;
  if md5(v_def) <> 'a69fdf8d625021b8e20f5ecf46734fad' then raise exception 'live security.stats_15m_v1 differs from the definition this change edits'; end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'share gap test must occur once'; end if;
  execute replace(v_def, v_old, $n$((x->>'used')::numeric >= (x->>'share')::numeric
                   or exists (select 1 from pipeline.firecrawl_budget_refusals r where r.day = (v_now at time zone 'Australia/Melbourne')::date and r.grp = x->>'group' and r.reason <> 'not_due'))$n$);
end $edit$;

-- the watchdog counts as waiting only central searches the spend check will allow (held until due is not waiting work)
update pipeline.queue_watch set pending_sql = $q$select count(*) from pipeline.provider_central_search s join catalogue.providers p on p.id = s.provider_id where (s.state = 'queued' or (s.state = 'leased' and s.leased_until < now())) and s.attempts < 3 and p.lifecycle_status = 'active' and p.website ~* '^https?://' and not security.third_party_host_v1(p.website) and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id) and not security.flag_provider_held_v1(s.provider_id, array['central_not_due', 'central_budget', 'site_unreachable'])$q$
 where key = 'central_find';
do $dry$ declare r jsonb; begin
  r := security.queue_watch_run_v1(false);
  raise exception 'DRYRUN OK %', (select state||' p'||pending from pipeline.queue_watch_state where key='central_find');
end $dry$;
