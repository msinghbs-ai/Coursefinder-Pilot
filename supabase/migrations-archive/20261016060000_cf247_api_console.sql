-- CF-247 (16 Oct 2026): API console for both API version URLs (zoho-api-v2, website-api-v2). Platform Admin 16 Oct 2026 14:31: "Create me a
-- ui to check stats on Both APIs with relevant metrics/API calls or statistics, success & failure, last login, full sync, delta sync,
-- bandwidth, load size etc. be able to rotate their keys. and on Demand fresh statistics by pressing a button, otherwise get refresh daily
-- basis."
-- 1 Key rotation: a new key is made in the database (random, shown once to the Platform Admin, only its SHA-256 kept); the old key keeps
--   working for an overlap (setting api.key_rotate_overlap_hours, 24; 0 ends it at once) so the consumer can switch. Keys can be switched
--   off and on. Every rotation and switch is recorded in pipeline.api_key_events.
-- 2 Statistics per key for the last 24 hours, 7 days and 30 days (calls, success and failure, last call and last success, bandwidth, reply
--   sizes, times, full loads and deltas, CSV exports, use of the old key during an overlap), kept in pipeline.api_usage_summary.
-- 3 Refresh daily, or on demand from the screen (button): security.api_usage_refresh_v1 sums the request log (as before) and rebuilds the
--   per-key statistics; each refresh is recorded in pipeline.api_usage_refreshes.
-- Replaces: the api-usage-rollup job every 15 minutes (now daily, and on demand from the screen); public.zoho_v2_auth(text) and
--   public.website_api_v2_auth(text) that accepted only the current key (now also the previous key until its overlap ends);
--   public.admin_api_usage(integer) (now with the statistics, refresh time, key events and each platform's own default rate)
-- Retires: nothing
-- Nothing dropped or deleted.

-- 0 Guard: the definitions this change replaces are the ones live
do $guard$
declare v_expected jsonb := '{"public.zoho_v2_auth(text)": "10efe693ba599f9f257444423ba4ece2", "public.website_api_v2_auth(text)": "96ac91c395237af9a20bab7a86b0546d", "public.admin_api_usage(integer)": "c9518cdc6f14f3d42ee14f32b5eb1656"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1 Setting
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'api.key_rotate_overlap_hours', 'API key rotation: hours the old key keeps working', 'When a key is rotated on Operations > API usage, the old key keeps working this many hours so the consumer can switch. 0 ends the old key at once. The screen can end it early.', 'number', to_jsonb(24), 0, 168, 'hours', 812, 'Platform Admin 16 Oct 2026 14:31: "be able to rotate their keys"', 'Zoho API', 'public.admin_api_key_rotate')
on conflict (toolset_key, key) do nothing;

-- 2 Keys: the previous key during an overlap
alter table private.api_keys add column if not exists previous_token_sha256 text check (previous_token_sha256 is null or previous_token_sha256 ~ '^[0-9a-f]{64}$');
alter table private.api_keys add column if not exists previous_valid_until timestamptz;
alter table private.api_keys add column if not exists rotated_by uuid;

create table if not exists pipeline.api_key_events (
  id bigserial primary key,
  at timestamptz not null default now(),
  key_name text not null,
  event text not null check (event in ('rotated', 'switched_off', 'switched_on', 'previous_ended')),
  by_user uuid,
  by_email text,
  note text,
  previous_valid_until timestamptz);
comment on table pipeline.api_key_events is 'CF-247 16 Oct 2026 (Platform Admin: "be able to rotate their keys"): every key rotation, switch off or on, and early end of an old key, from Operations > API usage: who, when, a note and how long the old key kept working. No key or key hash is kept here.';
alter table pipeline.api_key_events enable row level security;
revoke all on pipeline.api_key_events from anon, authenticated;

-- 3 Statistics per key and refreshes
create table if not exists pipeline.api_usage_summary (
  key_name text not null,
  period text not null check (period in ('24h', '7d', '30d')),
  computed_at timestamptz not null,
  stats jsonb not null,
  primary key (key_name, period));
comment on table pipeline.api_usage_summary is 'CF-247 16 Oct 2026: statistics per API key for the last 24 hours, 7 days and 30 days (calls, success and failure, last call, bandwidth, reply sizes, times, full loads, deltas, CSV exports, use of the old key during an overlap). Rebuilt from pipeline.api_requests daily and on demand (security.api_usage_refresh_v1).';
alter table pipeline.api_usage_summary enable row level security;
revoke all on pipeline.api_usage_summary from anon, authenticated;

create table if not exists pipeline.api_usage_refreshes (
  id bigserial primary key,
  at timestamptz not null default now(),
  trigger text not null check (trigger in ('daily', 'on_demand')),
  by_user uuid,
  elapsed_ms integer,
  result jsonb);
comment on table pipeline.api_usage_refreshes is 'CF-247 16 Oct 2026: each refresh of the API statistics, daily (api-usage-rollup job) or on demand from Operations > API usage: when, by whom and how long it took. The latest row is the "statistics as of" time on the screen.';
alter table pipeline.api_usage_refreshes enable row level security;
revoke all on pipeline.api_usage_refreshes from anon, authenticated;

-- 4 Statistics for one key and period, from the request log. Sync calls are logged as sync_full_start, sync_full, sync_full_end and
--   sync_delta; calls made with the previous key during an overlap are logged as <key>#previous.
create or replace function security.api_key_stats_v1(p_key_name text, p_since timestamptz)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v jsonb; v_end timestamptz; v_start timestamptz; v_full jsonb;
begin
  select jsonb_build_object(
    'calls', count(*),
    'ok', count(*) filter (where r.status < 400),
    'client_errors', count(*) filter (where r.status >= 400 and r.status < 500 and r.status <> 429),
    'rate_limited', count(*) filter (where r.status = 429),
    'server_errors', count(*) filter (where r.status >= 500),
    'success_rate', case when count(*) > 0 then round(100.0 * count(*) filter (where r.status < 400) / count(*), 1) end,
    'bytes', coalesce(sum(r.bytes), 0),
    'avg_bytes', round(avg(r.bytes)),
    'max_bytes', max(r.bytes),
    'items', coalesce(sum(r.items), 0),
    'avg_ms', round(avg(r.elapsed_ms)),
    'p95_ms', round(percentile_cont(0.95) within group (order by r.elapsed_ms)),
    'max_ms', max(r.elapsed_ms),
    'first_call_at', min(r.at),
    'last_call_at', max(r.at),
    'last_ok_at', max(r.at) filter (where r.status < 400),
    'last_error_at', max(r.at) filter (where r.status >= 400),
    'last_error_code', (array_agg(r.error_code order by r.at desc) filter (where r.status >= 400))[1],
    'full_load_pages', count(*) filter (where r.action like 'sync\_full%' and r.status < 400),
    'full_load_bytes', coalesce(sum(r.bytes) filter (where r.action like 'sync\_full%' and r.status < 400), 0),
    'full_loads_completed', count(*) filter (where r.action = 'sync_full_end' and r.status < 400),
    'delta_calls', count(*) filter (where r.action = 'sync_delta' and r.status < 400),
    'delta_items', coalesce(sum(r.items) filter (where r.action = 'sync_delta' and r.status < 400), 0),
    'delta_bytes', coalesce(sum(r.bytes) filter (where r.action = 'sync_delta' and r.status < 400), 0),
    'last_delta_at', max(r.at) filter (where r.action = 'sync_delta' and r.status < 400),
    'exports', count(*) filter (where r.action = 'export' and r.status < 400),
    'export_bytes', coalesce(sum(r.bytes) filter (where r.action = 'export' and r.status < 400), 0),
    'searches', count(*) filter (where r.action = 'search' and r.status < 400),
    'previous_key_calls', (select count(*) from pipeline.api_requests p where p.key_name = p_key_name || '#previous' and p.at >= p_since),
    'previous_key_last_at', (select max(p.at) from pipeline.api_requests p where p.key_name = p_key_name || '#previous'))
    into v
    from pipeline.api_requests r where r.key_name = p_key_name and r.at >= p_since;
  -- the last completed full load (any time in the kept log): when it started and finished, pages, items, size
  select max(r.at) into v_end from pipeline.api_requests r where r.key_name = p_key_name and r.action = 'sync_full_end' and r.status < 400;
  if v_end is not null then
    select coalesce(max(r.at), v_end) into v_start from pipeline.api_requests r
     where r.key_name = p_key_name and r.action = 'sync_full_start' and r.status < 400 and r.at <= v_end
       and r.at > coalesce((select max(e.at) from pipeline.api_requests e where e.key_name = p_key_name and e.action = 'sync_full_end' and e.status < 400 and e.at < v_end), '-infinity');
    select jsonb_build_object('started_at', v_start, 'finished_at', v_end, 'pages', count(*), 'items', coalesce(sum(r.items), 0), 'bytes', coalesce(sum(r.bytes), 0),
                              'seconds', round(extract(epoch from v_end - v_start)))
      into v_full from pipeline.api_requests r
     where r.key_name = p_key_name and r.action like 'sync\_full%' and r.status < 400 and r.at between v_start and v_end;
  end if;
  return v || jsonb_build_object('last_full_load', v_full,
    'last_full_load_started_at', (select max(r.at) from pipeline.api_requests r where r.key_name = p_key_name and r.action = 'sync_full_start' and r.status < 400));
end $function$;

-- 5 Refresh: sum the log (as before) and rebuild the per-key statistics
create or replace function security.api_usage_refresh_v1(p_trigger text)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare t timestamptz := clock_timestamp(); v_roll jsonb; v_n int := 0; k record; p record; v_ms int; v_res jsonb;
begin
  if coalesce(p_trigger, '') not in ('daily', 'on_demand') then raise exception 'INVALID_INPUT: trigger' using errcode = '22023'; end if;
  v_roll := security.api_usage_rollup_v1();
  for k in select key_name from private.api_keys loop
    for p in select * from (values ('24h', interval '1 day'), ('7d', interval '7 days'), ('30d', interval '30 days')) x(period, span) loop  -- fixed: the three periods the screen shows
      insert into pipeline.api_usage_summary(key_name, period, computed_at, stats)
      values (k.key_name, p.period, now(), security.api_key_stats_v1(k.key_name, now() - p.span))
      on conflict (key_name, period) do update set computed_at = excluded.computed_at, stats = excluded.stats;
      v_n := v_n + 1;
    end loop;
  end loop;
  v_ms := round(extract(epoch from clock_timestamp() - t) * 1000);
  v_res := v_roll || jsonb_build_object('summary_rows', v_n);
  insert into pipeline.api_usage_refreshes(trigger, by_user, elapsed_ms, result) values (p_trigger, auth.uid(), v_ms, v_res);
  return v_res || jsonb_build_object('at', now(), 'trigger', p_trigger, 'elapsed_ms', v_ms);
end $function$;

-- 6 Keys: accept the previous key until its overlap ends
CREATE OR REPLACE FUNCTION public.zoho_v2_auth(p_token_sha256 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare k private.api_keys%rowtype; v_prev boolean := false;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into k from private.api_keys where platform = 'zoho' and api_version = 'v2' and enabled and token_sha256 = lower(coalesce(p_token_sha256, ''));
  if k.key_name is null then
    select * into k from private.api_keys where platform = 'zoho' and api_version = 'v2' and enabled and previous_valid_until > now()
       and previous_token_sha256 = lower(coalesce(p_token_sha256, ''));
    v_prev := k.key_name is not null;
  end if;
  if k.key_name is null then return null; end if;
  return jsonb_build_object('key_name', k.key_name, 'previous', v_prev, 'rate_per_minute', coalesce(k.rate_per_minute, security.pipeline_num_v1('zoho.rate_per_minute', 120)::int),
                            'logo_link_days', security.pipeline_num_v1('zoho.logo_link_days', 365), 'page_max', security.pipeline_num_v1('zoho.page_max', 50)::int);
end $function$;

CREATE OR REPLACE FUNCTION public.website_api_v2_auth(p_token_sha256 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare k private.api_keys%rowtype; v_prev boolean := false;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into k from private.api_keys where platform = 'website' and api_version = 'v2' and enabled and token_sha256 = lower(coalesce(p_token_sha256, ''));
  if k.key_name is null then
    select * into k from private.api_keys where platform = 'website' and api_version = 'v2' and enabled and previous_valid_until > now()
       and previous_token_sha256 = lower(coalesce(p_token_sha256, ''));
    v_prev := k.key_name is not null;
  end if;
  if k.key_name is null then return null; end if;
  return jsonb_build_object('key_name', k.key_name, 'previous', v_prev, 'rate_per_minute', coalesce(k.rate_per_minute, security.pipeline_num_v1('website.rate_per_minute', 300)::int),
                            'logo_link_days', security.pipeline_num_v1('website.logo_link_days', 365));
end $function$;

-- 7 Screen: read (rank 4+), refresh now (rank 4+), rotate and switch keys (Platform Admin, rank 6)
CREATE OR REPLACE FUNCTION public.admin_api_usage(p_days integer DEFAULT 14)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_days int := least(greatest(coalesce(p_days, 14), 1), 90);
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 4 then raise exception 'pipeline_operator role required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'keys', (select coalesce(jsonb_agg(jsonb_build_object('key_name', k.key_name, 'platform', k.platform, 'api_version', k.api_version, 'consumer', k.consumer,
               'enabled', k.enabled,
               'rate_per_minute', coalesce(k.rate_per_minute, case k.platform when 'website' then security.pipeline_num_v1('website.rate_per_minute', 300)
                                                                              else security.pipeline_num_v1('zoho.rate_per_minute', 120) end::int),
               'created_at', k.created_at, 'rotated_at', k.rotated_at, 'last_used_at', k.last_used_at,
               'key_hint', left(k.token_sha256, 8), 'previous_valid_until', case when k.previous_valid_until > now() then k.previous_valid_until end,
               'stats', (select coalesce(jsonb_object_agg(s.period, s.stats), '{}'::jsonb) from pipeline.api_usage_summary s where s.key_name = k.key_name))
               order by k.platform, k.api_version, k.key_name), '[]'::jsonb) from private.api_keys k),
    'refreshed', (select jsonb_build_object('at', r.at, 'trigger', r.trigger, 'elapsed_ms', r.elapsed_ms,
                    'by', (select u.email from auth.users u where u.id = r.by_user)) from pipeline.api_usage_refreshes r order by r.at desc limit 1),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'key_name', e.key_name, 'event', e.event, 'by', e.by_email, 'note', e.note,
                    'previous_valid_until', e.previous_valid_until) order by e.at desc), '[]'::jsonb)
               from (select * from pipeline.api_key_events order by at desc limit 20) e),  -- fixed: the screen's latest key events
    'overlap_hours', security.pipeline_num_v1('api.key_rotate_overlap_hours', 24),
    'can_manage_keys', security.current_role_rank() >= 6,
    'daily', (select coalesce(jsonb_agg(to_jsonb(d) order by d.day desc, d.platform, d.key_name, d.action), '[]'::jsonb) from pipeline.api_usage_daily d
               where d.day > (now() at time zone 'Australia/Melbourne')::date - v_days),
    'recent_errors', (select coalesce(jsonb_agg(jsonb_build_object('at', r.at, 'platform', r.platform, 'key_name', r.key_name, 'action', r.action, 'status', r.status, 'error_code', r.error_code, 'request_id', r.request_id) order by r.at desc), '[]'::jsonb)
               from (select * from pipeline.api_requests where status >= 400 order by at desc limit 20) r),  -- fixed: the screen's latest errors
    'days', v_days);
end $function$;

create or replace function public.admin_api_usage_refresh()
returns jsonb language plpgsql security definer set search_path = '' as $function$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 4 then raise exception 'pipeline_operator role required' using errcode = '42501'; end if;
  return security.api_usage_refresh_v1('on_demand');
end $function$;

create or replace function public.admin_api_key_rotate(p_key_name text, p_overlap_hours numeric default null, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare k private.api_keys%rowtype; v_token text; v_hash text; v_hours numeric; v_until timestamptz; v_email text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 6 then raise exception 'platform_admin role required' using errcode = '42501'; end if;
  select * into k from private.api_keys where key_name = p_key_name for update;
  if k.key_name is null then raise exception 'INVALID_INPUT: unknown key' using errcode = '22023'; end if;
  v_hours := coalesce(p_overlap_hours, security.pipeline_num_v1('api.key_rotate_overlap_hours', 24));
  if v_hours < 0 or v_hours > 168 then raise exception 'INVALID_INPUT: overlap must be 0 to 168 hours' using errcode = '22023'; end if;  -- fixed: the setting's range
  -- the new key: a prefix that names the API, then 30 random bytes (URL-safe base64); only its SHA-256 is kept
  v_token := case k.platform when 'zoho' then 'cfz2_' else 'cfw2_' end
             || rtrim(translate(encode(extensions.gen_random_bytes(30), 'base64'), '+/', '-_'), '=');  -- fixed: key length
  v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');
  v_until := case when v_hours > 0 then now() + make_interval(secs => (v_hours * 3600)::double precision) end;
  update private.api_keys
     set previous_token_sha256 = case when v_until is not null then k.token_sha256 end, previous_valid_until = v_until,
         token_sha256 = v_hash, rotated_at = now(), rotated_by = auth.uid()
   where key_name = k.key_name;
  select u.email into v_email from auth.users u where u.id = auth.uid();
  insert into pipeline.api_key_events(key_name, event, by_user, by_email, note, previous_valid_until)
  values (k.key_name, 'rotated', auth.uid(), v_email, nullif(btrim(coalesce(p_note, '')), ''), v_until);
  return jsonb_build_object('key_name', k.key_name, 'key', v_token, 'key_hint', left(v_hash, 8), 'previous_valid_until', v_until, 'platform', k.platform);
end $function$;

create or replace function public.admin_api_key_set_enabled(p_key_name text, p_enabled boolean, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare k private.api_keys%rowtype; v_email text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 6 then raise exception 'platform_admin role required' using errcode = '42501'; end if;
  if p_enabled is null then raise exception 'INVALID_INPUT: enabled' using errcode = '22023'; end if;
  select * into k from private.api_keys where key_name = p_key_name for update;
  if k.key_name is null then raise exception 'INVALID_INPUT: unknown key' using errcode = '22023'; end if;
  update private.api_keys set enabled = p_enabled where key_name = k.key_name;
  select u.email into v_email from auth.users u where u.id = auth.uid();
  insert into pipeline.api_key_events(key_name, event, by_user, by_email, note)
  values (k.key_name, case when p_enabled then 'switched_on' else 'switched_off' end, auth.uid(), v_email, nullif(btrim(coalesce(p_note, '')), ''));
  return jsonb_build_object('key_name', k.key_name, 'enabled', p_enabled);
end $function$;

create or replace function public.admin_api_key_end_previous(p_key_name text, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare k private.api_keys%rowtype; v_email text;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 6 then raise exception 'platform_admin role required' using errcode = '42501'; end if;
  select * into k from private.api_keys where key_name = p_key_name for update;
  if k.key_name is null then raise exception 'INVALID_INPUT: unknown key' using errcode = '22023'; end if;
  update private.api_keys set previous_token_sha256 = null, previous_valid_until = null where key_name = k.key_name;
  select u.email into v_email from auth.users u where u.id = auth.uid();
  insert into pipeline.api_key_events(key_name, event, by_user, by_email, note) values (k.key_name, 'previous_ended', auth.uid(), v_email, nullif(btrim(coalesce(p_note, '')), ''));
  return jsonb_build_object('key_name', k.key_name, 'previous_valid_until', null);
end $function$;

revoke execute on function security.api_key_stats_v1(text, timestamptz), security.api_usage_refresh_v1(text) from public, anon, authenticated;
revoke execute on function public.admin_api_usage_refresh(), public.admin_api_key_rotate(text, numeric, text), public.admin_api_key_set_enabled(text, boolean, text),
  public.admin_api_key_end_previous(text, text) from public, anon;
grant execute on function public.admin_api_usage_refresh(), public.admin_api_key_rotate(text, numeric, text), public.admin_api_key_set_enabled(text, boolean, text),
  public.admin_api_key_end_previous(text, text) to authenticated;

-- 8 The statistics job: daily (about 00:20 Melbourne) instead of every 15 minutes; the screen refreshes on demand
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('api-usage-rollup', 'Search and API', 43, 'API usage: daily statistics', 'Daily (about 00:20 Melbourne) and on demand from Operations > API usage: sums the API v2 request log into calls per day, key and action, rebuilds the statistics per key (24 hours, 7 days, 30 days) and removes log rows older than the setting.', 6, false)
on conflict (jobname) do update set label = excluded.label, description = excluded.description;
select cron.schedule('api-usage-rollup', '20 13 * * *', 'select security.api_usage_refresh_v1(''daily'')');

-- 9 Register and first statistics
insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.api_key_events', 'API', 'Key rotations and switches', 'active', '20261016060000'),
 ('table', 'pipeline.api_usage_summary', 'API', 'Statistics per API key (24 hours, 7 days, 30 days)', 'active', '20261016060000'),
 ('table', 'pipeline.api_usage_refreshes', 'API', 'Each refresh of the API statistics', 'active', '20261016060000')
on conflict (kind, name) do nothing;
select security.api_usage_refresh_v1('daily');

do $post$
begin
  if position('previous_valid_until > now()' in pg_get_functiondef('public.zoho_v2_auth(text)'::regprocedure)) = 0
     or position('previous_valid_until > now()' in pg_get_functiondef('public.website_api_v2_auth(text)'::regprocedure)) = 0 then
    raise exception 'api console post-check: auth functions not as intended';
  end if;
  if (select command from cron.job where jobname = 'api-usage-rollup') <> 'select security.api_usage_refresh_v1(''daily'')' then
    raise exception 'api console post-check: job not as intended';
  end if;
  if (select count(*) from pipeline.api_usage_summary) <> 3 * (select count(*) from private.api_keys) then
    raise exception 'api console post-check: statistics not built';
  end if;
end $post$;
