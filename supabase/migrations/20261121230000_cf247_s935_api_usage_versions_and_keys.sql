-- CF-247 S1-RM-Design s935 (Platform Admin 21 Nov 2026 13:11 AEDT): Settings > API usage is read from the database for every API version and key, and each
-- (consumer, API version) has its own key that can be rotated on its own.
-- What was read live (21 Nov 2026 13:20-13:40 AEDT, rolled-back dry runs only, head 20261121190000):
--   private.api_keys holds 4 keys, all v2: website_developer_v2, zoho_creator_v2, zoho_crm_sync_v2, zoho_live_check_v2 (off). There is no v3 key.
--   website-api-v3 and zoho-api-v3 sign in with the v2 functions (public.website_api_v2_auth and public.zoho_v2_auth, which accept v2 keys only) and log
--   through the v2 log functions with the action written "v3:<action>" and the version "v2". So v3 shares the v2 keys: 653 v3 calls in 30 days, all with
--   website_developer_v2 (last 20 Nov 16:23 UTC); no Zoho v3 call.
--   v1 (website-course-api, wix-course-api, zoho-course-api) keeps its keys in private.website_integration_credentials (3, 2 on) and
--   private.zoho_integration_credentials (1, on); it writes no per-request log.
--   Settings > API usage lists two fixed platforms, "Zoho API v2" and "Website API v2", written in the screen's code.
-- What this change does:
--   1 pipeline.api_versions registers each consumer API version (v1, v2, v3 for Website and Zoho) with its endpoints, key store and whether it is frozen (G3).
--     security.api_usage_versions_v1 reads the register, every key in each key store and the request log live (24 hours, 7 days, 30 days: calls, 2xx, 4xx,
--     5xx, error rate, 95th-percentile time, last call). A version or key the register does not name yet (a new key's version, or a version seen in the log)
--     is listed too, marked "not registered", so nothing is hidden. public.admin_api_usage returns it as "versions" (md5-guarded edit of one line).
--   2 Own keys for v3: website_developer_v3, zoho_creator_v3 and zoho_crm_sync_v3 in private.api_keys (rows only; the table's shape is unchanged).
--     Each starts "Not issued" (a random hash nobody holds; key hashes are unique). website_developer_v3 also accepts the v2 key as its previous key for
--     api.new_key_bridge_days (14), so the website's live v3 calls keep working: the screen shows it "Rotating / Grace" with the date the v2 key stops on v3.
--     The Platform Admin rotates it on Settings > API usage to issue its own key (shown once); the v2 key then works on v3 only for the rotation overlap
--     (api.key_rotate_overlap_hours) and stops. The two Zoho v3 keys have no bridge: Zoho has made no v3 call.
--     pipeline.api_key_auth_v1 and pipeline.api_request_log_v1 sign in and log by (consumer, version): website-api-v3 and zoho-api-v3 call them, so v3 accepts
--     only v3 keys and logs as v3 under its own key. Rotation (public.admin_api_key_rotate, md5-guarded edit) names the version in the key's prefix (cfw3_,
--     cfz3_) and clears "Not issued".
--   3 security.api_usage_coverage_v1 checks that every active registered version and every key is returned by the read path (post-check here; spec s935).
-- Not changed: the frozen consumer API (G3: the v1 and v2 endpoints, public.website_api_v2_*, public.zoho_v2_* functions, the tables' shapes; 75 functions and 48
-- relations read before and after), the v1 and v2 keys, the manual locks (7,585), the jobs (no new job). No AI, no Firecrawl. Nothing dropped or deleted.
-- Numbering: spec s935 and s936; migration 20261121230000, above the live head 20261121200000 (s931, #1457) and s940's 20261121220000 (#1459).
-- Replaces: the fixed platform list of Settings > API usage (the screen now reads "versions"); v3's sign-in and log through the v2 functions.
-- Retires: nothing.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> 7585 then raise exception 'guard: the manual locks are not 7,585 before this change'; end if;
  if md5(pg_get_functiondef('public.admin_api_usage(integer)'::regprocedure)) <> '3aa81da553a96b02861f7b0f69adbeee' then raise exception 'pre-check: public.admin_api_usage changed since it was read'; end if;
  if md5(pg_get_functiondef('public.admin_api_key_rotate(text,numeric,text)'::regprocedure)) <> '83e3fb935eb11a3be535c3d26ece1ee8' then raise exception 'pre-check: public.admin_api_key_rotate changed since it was read'; end if;
  if exists (select 1 from private.api_keys where api_version = 'v3') then raise exception 'pre-check: a v3 key already exists'; end if;
  if not exists (select 1 from private.api_keys where key_name = 'website_developer_v2' and platform = 'website' and api_version = 'v2' and enabled) then
    raise exception 'pre-check: website_developer_v2 is not the live website v2 key';
  end if;
end $g$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'api.new_key_bridge_days', 'New API version key: days the earlier version''s key still works',
  'When a new API version gets its own key, a consumer already calling it with the earlier version''s key keeps working this many days, until the new key is issued (rotated) and the rotation overlap ends.',
  'number', '14'::jsonb, 1, 60, 'days', 531, 'CF-247 s935, Platform Admin 21 Nov 2026 13:11', 'Search and API', 'migration 20261121230000 (website_developer_v3), public.admin_api_key_rotate')
on conflict (toolset_key, key) do nothing;

-- 1 the register of consumer API versions ------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.api_versions (
  platform      text not null check (platform ~ '^[a-z][a-z0-9_]*$'),
  api_version   text not null check (api_version ~ '^v[0-9]+$'),
  endpoint      text not null,
  label         text not null,
  key_store     text not null check (key_store in ('private.api_keys', 'private.website_integration_credentials', 'private.zoho_integration_credentials')),
  status        text not null default 'active' check (status in ('active', 'retired')),
  frozen        boolean not null default false,
  sort          int not null default 100,
  note          text,
  registered_at timestamptz not null default now(),
  primary key (platform, api_version, endpoint)
);
comment on table pipeline.api_versions is 'CF-247 s935 (Platform Admin 21 Nov 2026 13:11): the register of consumer API versions (consumer platform, version, endpoint, key store, frozen under G3). Settings > API usage reads it through security.api_usage_versions_v1; a new version is a row here and its keys rows in its key store, with no screen change. Never deleted (a retired version is status retired).';
alter table pipeline.api_versions enable row level security;
revoke all on pipeline.api_versions from public, anon, authenticated;

insert into pipeline.api_versions (platform, api_version, endpoint, label, key_store, status, frozen, sort, note) values
  ('website', 'v1', 'website-course-api', 'Website API v1', 'private.website_integration_credentials', 'active', true, 10, 'Frozen (G3). No per-request log.'),
  ('website', 'v1', 'wix-course-api', 'Website API v1', 'private.website_integration_credentials', 'active', true, 11, 'Frozen (G3). No per-request log.'),
  ('zoho', 'v1', 'zoho-course-api', 'Zoho API v1', 'private.zoho_integration_credentials', 'active', true, 20, 'Frozen (G3). No per-request log.'),
  ('website', 'v2', 'website-api-v2', 'Website API v2', 'private.api_keys', 'active', true, 30, 'Frozen (G3, Decision 266).'),
  ('zoho', 'v2', 'zoho-api-v2', 'Zoho API v2', 'private.api_keys', 'active', true, 40, 'Frozen (G3, Decision 266).'),
  ('website', 'v3', 'website-api-v3', 'Website API v3', 'private.api_keys', 'active', false, 50, 'Open to additions until the website goes live on v3 (Decision 277).'),
  ('zoho', 'v3', 'zoho-api-v3', 'Zoho API v3', 'private.api_keys', 'active', false, 60, 'Additive (Zoho v3).')
on conflict (platform, api_version, endpoint) do nothing;

-- 2 own keys for v3 (rows only) ----------------------------------------------------------------------------------------------------------------------
insert into private.api_keys (key_name, platform, api_version, consumer, token_sha256, enabled, rate_per_minute, note, previous_token_sha256, previous_valid_until)
select 'website_developer_v3', 'website', 'v3', k.consumer, encode(extensions.digest(encode(extensions.gen_random_bytes(32), 'hex'), 'sha256'), 'hex'), true, k.rate_per_minute,
       'CF-247 s935 (21 Nov 2026): own key for Website API v3. [not issued] Until it is issued (rotate it on Settings > API usage; shown once), the website''s v2 key keeps working on v3 as its previous key.',
       k.token_sha256, now() + make_interval(days => security.pipeline_num_v1('api.new_key_bridge_days', 14)::int)
  from private.api_keys k where k.key_name = 'website_developer_v2'
on conflict (key_name) do nothing;
insert into private.api_keys (key_name, platform, api_version, consumer, token_sha256, enabled, rate_per_minute, note)
select k.key_name_v3, 'zoho', 'v3', k.consumer, encode(extensions.digest(encode(extensions.gen_random_bytes(32), 'hex'), 'sha256'), 'hex'), true, k.rate_per_minute,
       'CF-247 s935 (21 Nov 2026): own key for Zoho API v3. [not issued] Nobody holds this key yet: rotate it on Settings > API usage to issue it (shown once).'
  from (select replace(key_name, '_v2', '_v3') key_name_v3, consumer, rate_per_minute from private.api_keys where key_name in ('zoho_creator_v2', 'zoho_crm_sync_v2')) k
on conflict (key_name) do nothing;
insert into pipeline.api_key_events (key_name, event, note)
select key_name, 'switched_on', 'CF-247 s935: own key for ' || platform || ' ' || api_version || ' added' from private.api_keys where api_version = 'v3';

-- 3 sign-in and log by (consumer, version) -----------------------------------------------------------------------------------------------------------
create or replace function pipeline.api_key_auth_v1(p_platform text, p_version text, p_token_sha256 text) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare k private.api_keys%rowtype; v_prev boolean := false; v_h text := lower(coalesce(p_token_sha256, ''));
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if v_h !~ '^[0-9a-f]{64}$' then return null; end if;
  select * into k from private.api_keys where platform = p_platform and api_version = p_version and enabled and token_sha256 = v_h;
  if k.key_name is null then
    select * into k from private.api_keys where platform = p_platform and api_version = p_version and enabled and previous_valid_until > now() and previous_token_sha256 = v_h;
    v_prev := k.key_name is not null;
  end if;
  if k.key_name is null then return null; end if;
  return jsonb_build_object('key_name', k.key_name, 'previous', v_prev, 'platform', k.platform, 'api_version', k.api_version,
    'rate_per_minute', coalesce(k.rate_per_minute, security.pipeline_num_v1(p_platform || '.rate_per_minute', case when p_platform = 'zoho' then 120 else 300 end)::int),  -- fixed: each platform's own default
    'logo_link_days', security.pipeline_num_v1(p_platform || '.logo_link_days', 365), 'page_max', security.pipeline_num_v1('zoho.page_max', 50)::int);
end $f$;
revoke all on function pipeline.api_key_auth_v1(text, text, text) from public, anon, authenticated;
grant execute on function pipeline.api_key_auth_v1(text, text, text) to service_role;
comment on function pipeline.api_key_auth_v1(text, text, text) is 'CF-247 s935: signs in a consumer API call by (consumer platform, API version): only a key of that version (or its previous key during a rotation overlap). Used by website-api-v3 and zoho-api-v3; v1 and v2 keep their frozen sign-in.';

create or replace function pipeline.api_request_log_v1(p_platform text, p_version text, p_key_name text, p_action text, p_status int, p_elapsed_ms int,
                                                       p_items int, p_bytes bigint, p_error_code text, p_request_id text) returns void
language plpgsql security definer set search_path to '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.api_requests(platform, api_version, key_name, action, status, elapsed_ms, items, bytes, error_code, request_id)
  values (left(p_platform, 20), left(p_version, 10), p_key_name, left(p_action, 40), p_status, p_elapsed_ms, p_items, p_bytes, left(p_error_code, 40), p_request_id);
end $f$;
revoke all on function pipeline.api_request_log_v1(text, text, text, text, int, int, int, bigint, text, text) from public, anon, authenticated;
grant execute on function pipeline.api_request_log_v1(text, text, text, text, int, int, int, bigint, text, text) to service_role;
comment on function pipeline.api_request_log_v1(text, text, text, text, int, int, int, bigint, text, text) is 'CF-247 s935: logs one consumer API call with its own platform, version and key (pipeline.api_requests). Used by website-api-v3 and zoho-api-v3.';

-- 4 the read path ------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.api_usage_versions_v1() returns jsonb
language sql stable security definer set search_path to '' as $f$
  with reg as (
    select platform, api_version, min(label) label, min(key_store) key_store, bool_or(status = 'active') active, bool_and(frozen) frozen, min(sort) sort,
           array_agg(endpoint order by endpoint) endpoints, true registered, min(note) note
      from pipeline.api_versions group by platform, api_version
  ), seen as (  -- versions a key or the log names that the register does not (shown, marked not registered)
    select distinct platform, api_version from private.api_keys
    union select distinct platform, case when action like 'v3:%' then 'v3' else api_version end from pipeline.api_requests
     where at > now() - interval '30 days' and platform is not null and api_version is not null  -- fixed: the screen's longest period
  ), ver as (
    select * from reg
    union all
    select s.platform, s.api_version, initcap(s.platform) || ' API ' || s.api_version, 'private.api_keys', true, false, 900, '{}'::text[], false, 'Not registered in pipeline.api_versions'
      from seen s where not exists (select 1 from reg r where r.platform = s.platform and r.api_version = s.api_version)
  ), req as (  -- the log, with each call's own version (v3 calls logged before s935 carry the action "v3:<action>")
    select r.platform, case when r.action like 'v3:%' then 'v3' else r.api_version end ver, split_part(r.key_name, '#', 1) key_name, r.key_name like '%#previous' prev,
           r.at, r.status, r.elapsed_ms
      from pipeline.api_requests r where r.at > now() - interval '30 days'
  ), keyset as (
    select k.platform, k.api_version ver, k.key_name, k.consumer, true rotatable, k.enabled, k.created_at, k.rotated_at, left(k.token_sha256, 8) hint,
           'cf' || case k.platform when 'zoho' then 'z' else 'w' end || regexp_replace(k.api_version, '\D', '', 'g') || '_' prefix,
           case when not k.enabled then 'revoked'
                when k.previous_valid_until > now() then 'rotating'
                when k.note like '%[not issued]%' then 'not_issued'
                else 'active' end status,
           k.previous_valid_until,
           (select o.key_name from private.api_keys o where o.key_name <> k.key_name and o.token_sha256 = k.previous_token_sha256 and k.previous_valid_until > now() limit 1) shares_with,
           k.note not like '%[not issued]%' or k.note is null issued
      from private.api_keys k
    union all
    select 'website', 'v1', c.credential_name, 'Website integration (v1)', false, c.enabled, c.created_at, c.rotated_at, null, null,
           case when c.enabled then 'active' else 'revoked' end, null, null, true from private.website_integration_credentials c
    union all
    select 'zoho', 'v1', c.credential_name, 'Zoho integration (v1)', false, c.enabled, c.created_at, c.rotated_at, null, null,
           case when c.enabled then 'active' else 'revoked' end, null, null, true from private.zoho_integration_credentials c
    union all  -- a key seen on a version that is not its own (v3 calls made with a v2 key before s935)
    select q.platform, q.ver, q.key_name, 'Key of ' || k.api_version || ' used on ' || q.ver, false, k.enabled, k.created_at, k.rotated_at, left(k.token_sha256, 8), null,
           'other_version', null, null, true
      from (select distinct platform, ver, key_name from req) q join private.api_keys k on k.key_name = q.key_name and k.api_version <> q.ver
  ), stats as (
    select platform, ver, key_name, jsonb_object_agg(w, o) win from (
      select r.platform, r.ver, r.key_name, p.w,
             jsonb_build_object('calls', count(*), 'ok', count(*) filter (where r.status < 400),
                                'client_errors', count(*) filter (where r.status between 400 and 499), 'server_errors', count(*) filter (where r.status >= 500),
                                'previous_key_calls', count(*) filter (where r.prev)) o
        from req r join (values ('24h', interval '24 hours'), ('7d', interval '7 days'), ('30d', interval '30 days')) p(w, span) on r.at > now() - p.span
       group by r.platform, r.ver, r.key_name, p.w) z
     group by platform, ver, key_name
  ), p95 as (
    select platform, ver, key_name,
           jsonb_build_object(
             '24h', percentile_cont(0.95) within group (order by elapsed_ms) filter (where at > now() - interval '24 hours'),
             '7d', percentile_cont(0.95) within group (order by elapsed_ms) filter (where at > now() - interval '7 days'),
             '30d', percentile_cont(0.95) within group (order by elapsed_ms)) p95, max(at) last_at
      from req group by platform, ver, key_name
  ), keyrows as (
    select ks.*, coalesce(s.win, '{}'::jsonb) win, p.p95, p.last_at from keyset ks
      left join stats s on s.platform = ks.platform and s.ver = ks.ver and s.key_name = ks.key_name
      left join p95 p on p.platform = ks.platform and p.ver = ks.ver and p.key_name = ks.key_name
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'platform', v.platform, 'api_version', v.api_version, 'label', v.label, 'endpoints', to_jsonb(v.endpoints), 'key_store', v.key_store,
           'status', case when v.active then 'active' else 'retired' end, 'frozen', v.frozen, 'registered', v.registered, 'note', v.note,
           'logged', v.key_store = 'private.api_keys',
           'keys', (select coalesce(jsonb_agg(jsonb_build_object(
                      'key_name', kr.key_name, 'consumer', kr.consumer, 'status', kr.status, 'enabled', kr.enabled, 'rotatable', kr.rotatable,
                      'masked', case when kr.hint is null then null else coalesce(kr.prefix, '') || '…' || kr.hint end, 'created_at', kr.created_at, 'rotated_at', kr.rotated_at,
                      'previous_valid_until', kr.previous_valid_until, 'shares_with', kr.shares_with, 'issued', kr.issued, 'last_used_at', kr.last_at,
                      'stats', (select jsonb_object_agg(w.k, (kr.win->w.k) || jsonb_build_object('p95_ms', round((kr.p95->>w.k)::numeric),
                                  'error_rate', case when coalesce((kr.win->w.k->>'calls')::int, 0) = 0 then null
                                                     else round(((kr.win->w.k->>'client_errors')::numeric + (kr.win->w.k->>'server_errors')::numeric) / (kr.win->w.k->>'calls')::numeric, 4) end))
                                from (values ('24h'), ('7d'), ('30d')) w(k) where kr.win ? w.k)
                    ) order by case kr.status when 'other_version' then 1 else 0 end, kr.key_name), '[]'::jsonb)
                      from keyrows kr where kr.platform = v.platform and kr.ver = v.api_version)
         ) order by v.sort, v.platform, v.api_version), '[]'::jsonb)
    from ver v
$f$;
revoke all on function security.api_usage_versions_v1() from public, anon, authenticated;
comment on function security.api_usage_versions_v1() is 'CF-247 s935: Settings > API usage read path: every registered consumer API version (and any version a key or the last 30 days of the log names), each key of its key store with status (active, rotating, shared, not issued, revoked), masked hint, created, rotated and last used, and live usage for 24 hours, 7 days and 30 days (calls, 2xx, 4xx, 5xx, error rate, 95th-percentile time).';

create or replace function security.api_usage_coverage_v1() returns jsonb
language sql stable security definer set search_path to '' as $f$
  with v as (select security.api_usage_versions_v1() j), got as (
    select e.x->>'platform' platform, e.x->>'api_version' ver, k.y->>'key_name' key_name
      from v cross join lateral jsonb_array_elements(v.j) e(x) left join lateral jsonb_array_elements(e.x->'keys') k(y) on true)
  select jsonb_build_object(
    'missing_versions', (select coalesce(jsonb_agg(distinct a.platform || ' ' || a.api_version), '[]'::jsonb) from pipeline.api_versions a
                          where a.status = 'active' and not exists (select 1 from got g where g.platform = a.platform and g.ver = a.api_version)),
    'missing_keys', (select coalesce(jsonb_agg(x.key_name), '[]'::jsonb) from (
                       select key_name, platform, api_version from private.api_keys
                       union all select credential_name, 'website', 'v1' from private.website_integration_credentials
                       union all select credential_name, 'zoho', 'v1' from private.zoho_integration_credentials) x
                     where not exists (select 1 from got g where g.key_name = x.key_name and g.platform = x.platform and g.ver = x.api_version)))
$f$;
revoke all on function security.api_usage_coverage_v1() from public, anon, authenticated;
comment on function security.api_usage_coverage_v1() is 'CF-247 s935: what Settings > API usage would miss: active registered versions or keys (any key store) the read path does not return. Empty lists when complete.';

-- 5 md5-guarded edits: the usage read returns the versions; rotation names the version and clears "not issued" ---------------------------------------
do $e$
declare v_def text := pg_get_functiondef('public.admin_api_usage(integer)'::regprocedure);
        v_old constant text := $q$    'days', v_days);$q$;
        v_new constant text := $q$    'days', v_days,
    'versions', security.api_usage_versions_v1());  -- s935: every consumer API version and key, live$q$;
begin
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'guard: the usage read''s last line is not found exactly once'; end if;
  execute replace(v_def, v_old, v_new);
end $e$;

do $r$
declare v_def text := pg_get_functiondef('public.admin_api_key_rotate(text,numeric,text)'::regprocedure);
        v_old1 constant text := $q$v_token := case k.platform when 'zoho' then 'cfz2_' else 'cfw2_' end$q$;
        v_new1 constant text := $q$v_token := 'cf' || case k.platform when 'zoho' then 'z' else 'w' end || regexp_replace(k.api_version, '\D', '', 'g') || '_'  -- s935: the version in the prefix (cfw3_, cfz3_)$q$;
        v_old2 constant text := $q$token_sha256 = v_hash, rotated_at = now(), rotated_by = auth.uid()$q$;
        v_new2 constant text := $q$token_sha256 = v_hash, rotated_at = now(), rotated_by = auth.uid(), note = replace(coalesce(note, ''), ' [not issued]', '')$q$;
        -- first issue of a new version's key: the earlier version's key it was bridging stays its previous key for the overlap (not the unissued random one)
        v_old3 constant text := $q$set previous_token_sha256 = case when v_until is not null then k.token_sha256 end, previous_valid_until = v_until,$q$;
        v_new3 constant text := $q$set previous_token_sha256 = case when v_until is null then null when k.note like '%[not issued]%' and k.previous_valid_until > now() then k.previous_token_sha256 when k.note like '%[not issued]%' then null else k.token_sha256 end,
         previous_valid_until = case when k.note like '%[not issued]%' and not coalesce(k.previous_valid_until > now(), false) then null else v_until end,  -- s935$q$;
begin
  if (length(v_def) - length(replace(v_def, v_old1, ''))) / length(v_old1) <> 1 or (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2) <> 1
     or (length(v_def) - length(replace(v_def, v_old3, ''))) / length(v_old3) <> 1 then
    raise exception 'guard: a line to edit in public.admin_api_key_rotate is not found exactly once';
  end if;
  execute replace(replace(replace(v_def, v_old1, v_new1), v_old2, v_new2), v_old3, v_new3);
end $r$;

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('table', 'pipeline.api_versions', 'Service', 'Search and API', 'Register of consumer API versions read by Settings > API usage', 'active', '{}', '20261121230000'),
  ('function', 'pipeline.api_key_auth_v1', 'Service', 'Search and API', 'Sign-in by (consumer, API version) for website-api-v3 and zoho-api-v3', 'active', '{}', '20261121230000'),
  ('function', 'pipeline.api_request_log_v1', 'Service', 'Search and API', 'Log of a consumer API call with its own version and key', 'active', '{}', '20261121230000'),
  ('function', 'security.api_usage_versions_v1', 'Service', 'Search and API', 'Settings > API usage read path: versions, keys and live usage', 'active', '{}', '20261121230000'),
  ('function', 'security.api_usage_coverage_v1', 'Service', 'Search and API', 'What the API usage read path would miss', 'active', '{}', '20261121230000')
on conflict do nothing;

do $p$
declare v jsonb := security.consumer_api_check_v1(); c jsonb := security.api_usage_coverage_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> 7585 then raise exception 'post-check: manual locks changed'; end if;
  if jsonb_array_length(c->'missing_versions') > 0 or jsonb_array_length(c->'missing_keys') > 0 then raise exception 'post-check: the API usage read path misses %', c; end if;
  if (select count(distinct api_version) from jsonb_to_recordset(security.api_usage_versions_v1()) x(api_version text)) < 3 then raise exception 'post-check: v1, v2 and v3 are not all listed'; end if;
  if (select count(*) from private.api_keys where api_version = 'v3') <> 3 then raise exception 'post-check: the three v3 keys are not there'; end if;
  if pipeline.api_key_auth_v1('website', 'v2', (select token_sha256 from private.api_keys where key_name = 'zoho_creator_v2')) is not null then
    raise exception 'post-check: the version sign-in accepted another platform''s key';
  end if;
  if (pipeline.api_key_auth_v1('website', 'v3', (select token_sha256 from private.api_keys where key_name = 'website_developer_v2'))->>'key_name') <> 'website_developer_v3' then
    raise exception 'post-check: the website''s live v3 calls would not sign in';
  end if;
  if pipeline.api_key_auth_v1('zoho', 'v3', (select token_sha256 from private.api_keys where key_name = 'zoho_creator_v2')) is not null then
    raise exception 'post-check: Zoho v3 accepted a v2 key';
  end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active jobs'; end if;
end $p$;
