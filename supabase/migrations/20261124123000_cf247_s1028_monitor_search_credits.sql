-- CF-247 s1028 (S1-Build; Platform Admin 24 Nov 2026 09:06 AEDT; UI-UX plan v1.2 slice 8 fix): the Firecrawl Monitor week counts a search check at
-- Firecrawl's search price. s1027 counted every completed check at firecrawl.monitor_credits_per_url (5) per page, so the two search monitors
-- (Monash, Adelaide; 10 results each) would have counted 100 credits a week instead of 4 and paused every monitor over the 150 cap
-- (HELD:BUDGET_GATE) after the first checks (shown live, rolled back, 24 Nov 2026: one search check counted 50). Found reading Firecrawl's estimates
-- at registration (24 Nov 2026 11:50 AEDT: 8 page monitors at 75 credits a month and 2 search monitors at 20, about 148 a week).
-- Only public.svc_monitor_event_v1 changes (guarded against s1027's text).
-- G1: no job. G2: settings unchanged. G3: no consumer object changed (checked). Manual locks and active cron checked unchanged. Nothing dropped.
-- Replaces: s1027's credit count for search checks.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if position($t$* security.monitor_setting_v1('monitor_credits_per_url', 5);$t$ in pg_get_functiondef('public.svc_monitor_event_v1(jsonb)'::regprocedure)) = 0 then
    raise exception 'guard: public.svc_monitor_event_v1 is not the s1027 definition';
  end if;
end $g$;
create temp table s1028_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1028_cron on commit drop as select count(*) n from cron.job where active;

CREATE OR REPLACE FUNCTION public.svc_monitor_event_v1(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id bigint; v_prov uuid; v_cred numeric := 0; v_type text := p->>'event_type'; v_status text := p->>'page_status'; v_week numeric; v_cap numeric;
begin
  v_prov := coalesce(nullif(p->>'provider_id', '')::uuid, (select m.provider_id from pipeline.monitor_watchlist m where m.monitor_id = p->>'monitor_id' limit 1));
  if v_type = 'monitor.check.completed' then
    -- a search check costs 2 credits per 10 results; a page check costs firecrawl.monitor_credits_per_url per page (CF-247 s1028)
    v_cred := case when exists (select 1 from pipeline.monitor_watchlist m where m.monitor_id = p->>'monitor_id' and m.target_type = 'search')
                   then 2 * ceil(coalesce((p->'summary'->>'totalPages')::numeric, 0) / 10.0)  -- fixed: Firecrawl's search price, 2 credits per 10 results
                   else coalesce((p->'summary'->>'totalPages')::numeric, 0) * security.monitor_setting_v1('monitor_credits_per_url', 5) end;
  end if;
  insert into pipeline.monitor_events (webhook_id, event_type, monitor_id, check_id, provider_id, url, page_status, is_meaningful, diff, payload, credits_est, outcome)
  values (p->>'webhook_id', v_type, p->>'monitor_id', p->>'check_id', v_prov, nullif(p->>'url', ''), v_status, (p->>'is_meaningful')::boolean, p->'diff', p->'payload', v_cred,
          case when v_type = 'monitor.check.completed' then 'check_completed' when v_status in ('changed', 'new') then 'received' when v_status = 'same' then 'no_change' else coalesce(v_status, 'received') end)
  on conflict (webhook_id, event_type, coalesce(url, '')) do nothing
  returning id into v_id;
  if v_id is null then return jsonb_build_object('duplicate', true); end if;
  if nullif(p->>'url', '') is not null then
    update pipeline.monitor_watchlist m set last_event_at = now() where m.provider_id = v_prov and security.monitor_url_key_v1(m.url) = security.monitor_url_key_v1(p->>'url');
  end if;
  v_week := security.monitor_week_credits_v1(); v_cap := security.monitor_setting_v1('monitor_weekly_credits', 150);
  return jsonb_build_object('duplicate', false, 'id', v_id, 'provider_id', v_prov, 'route', v_type = 'monitor.page' and v_status in ('changed', 'new'),
                            'week_credits', v_week, 'weekly_cap', v_cap, 'over_cap', v_type = 'monitor.check.completed' and v_week > v_cap,
                            'monitor_ids', (select jsonb_agg(distinct m.monitor_id) from pipeline.monitor_watchlist m where m.status = 'registered' and m.monitor_id is not null));
end $function$;

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1028_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1028_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if position($t$m.target_type = 'search'$t$ in pg_get_functiondef('public.svc_monitor_event_v1(jsonb)'::regprocedure)) = 0 then raise exception 'post-check: search checks are not priced'; end if;
end $post$;
