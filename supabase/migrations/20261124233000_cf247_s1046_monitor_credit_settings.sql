-- CF-247 s1046 (S1-Build; Platform Admin 24 Nov 2026 15:10 AEDT, approved in chat): Firecrawl Monitor credit settings.
-- firecrawl.monitor_credits_per_url 5 -> 6 (Firecrawl's own estimate at registration was about 5.8 credits per page per check: 75 credits a month
-- for each 3-page monitor), and firecrawl.monitor_weekly_credits 150 -> 160, so all 26 registered targets (24 pages x 6 + 2 searches x 2 = 148,
-- Platform Admin's own count 26 x 6 = 156) run every Monday 03:17 AEDT without pausing.
-- The change is made as public.admin_toolsets_write('setting', ...) makes it (range check, value, reason, updated_at, and one
-- pipeline.admin_control_events row per setting with before, after and reason); the Platform Admin is not signed in here, so the actor is
-- empty and the event names the approval. The watchlist is re-planned at the new price (registered targets stay registered).
-- G1: no job. G2: this is the setting change. G3: no consumer object changed (checked). Manual locks and active cron checked unchanged.
-- Nothing dropped or deleted.
-- Replaces: firecrawl.monitor_credits_per_url 5 and firecrawl.monitor_weekly_credits 150.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1046_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1046_cron on commit drop as select count(*) n from cron.job where active;

do $s$
declare r record; v_before jsonb;
  v_reason text := 'Platform Admin 24 Nov 2026 15:10 AEDT (chat approval): Firecrawl estimates about 5.8 credits per watched page per check; 6 per page and a 160 weekly cap keep all 26 monitor targets running (CF-247 s1046)';
begin
  for r in select * from (values ('monitor_credits_per_url', 6::numeric), ('monitor_weekly_credits', 160::numeric)) x(k, v) loop
    select s.value into v_before from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = r.k for update;
    if not found then raise exception 'unknown setting firecrawl.%', r.k; end if;
    if not exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = r.k and s.kind = 'number'
                    and (s.min_value is null or r.v >= s.min_value) and (s.max_value is null or r.v <= s.max_value)) then
      raise exception 'firecrawl.% must stay within its range', r.k;
    end if;
    update pipeline.platform_toolset_settings set value = to_jsonb(r.v), reason = v_reason, updated_at = now() where toolset_key = 'firecrawl' and key = r.k;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('toolsets', 'setting', 'firecrawl.' || r.k, jsonb_build_object('before', v_before, 'after', to_jsonb(r.v), 'reason', v_reason,
            'approved_by', 'Platform Admin (chat, 24 Nov 2026 15:10 AEDT)', 'via', 'CF-247 s1046 migration'), null);
  end loop;
end $s$;

do $post$
declare v_api jsonb := security.consumer_api_check_v1(); v_plan jsonb;
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1046_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1046_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if security.monitor_setting_v1('monitor_credits_per_url', 0) <> 6 or security.monitor_setting_v1('monitor_weekly_credits', 0) <> 160 then
    raise exception 'post-check: the settings did not take';
  end if;
  v_plan := security.monitor_watchlist_plan_v1();
  if (v_plan->>'held_budget')::int <> 0 or (v_plan->>'est_week_credits')::numeric > 160 then raise exception 'post-check: a target no longer fits the weekly cap: %', v_plan; end if;
  if exists (select 1 from pipeline.monitor_watchlist where status = 'held_budget') then raise exception 'post-check: a target is held for budget'; end if;
end $post$;
