CREATE OR REPLACE FUNCTION security.api_usage_versions_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
