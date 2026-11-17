-- CF-247 (16 Oct 2026): Zoho API v2, its own URL and keys. Platform Admin 09:43: "i want to create separate API URL and Key for Zoho V2 API and
-- keep it separate from Website API URL, so i can keep the changes independent for each platform with summary and stat collection as well";
-- 09:55: "I want a separate URL for each API version going forward. Lets keep it simple not with contracts calling in the URL". Decisions
-- (multiple choice): keys "Creator + CRM sync"; CRM load "CSV seed + sync feed"; contacts "Public + named contacts"; website URL "Later".
-- Asked by Zoho (emails 14 and 16 Oct): search results with intakes, English (overall and bands) and fees, so no lookup per result; provider
-- by name; institutes and courses in Zoho CRM kept up to date automatically, matched by CRICOS, Australia first, with a CSV for the first import.
-- The edge function zoho-api-v2 (its own URL) calls only the functions below. Nothing the website or Zoho v1 reads changes.
-- Replaces: nothing (Zoho v1 at zoho-course-api stays as it is until Zoho has moved; then retired by paste file)
-- Retires: nothing
-- 1 Settings (section Zoho API)  2 Keys per consumer  3 Request log and daily usage  4 Course and provider extras (CRICOS codes)
-- 5 Read actions  6 Zoho change stream (providers, campuses, contacts, courses)  7 CSV export  8 Jobs, catalogue, register
-- Nothing dropped or deleted.


-- 1 Settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'zoho.rate_per_minute', 'Zoho API calls per minute, per key', 'Each Zoho v2 key may make this many calls a minute; more are answered 429 with Retry-After. A key can have its own figure (Zoho API usage screen).', 'number', to_jsonb(120), 10, 1000, 'calls', 800, 'Platform Admin 16 Oct 2026: Zoho API v2 (same as Zoho v1 today)', 'Zoho API', 'zoho-api-v2'),
 ('pipeline', 'zoho.page_max', 'Zoho search page size, largest', 'search, providers, campuses, contacts, rankings, statistics and scholarships return at most this many items a page.', 'number', to_jsonb(50), 10, 200, 'items', 801, 'Platform Admin 16 Oct 2026: Zoho API v2 (same as v1)', 'Zoho API', 'public.zoho_v2_*'),
 ('pipeline', 'zoho.sync_page_max', 'Zoho sync page size, largest', 'A sync page holds up to this many items (fewer when items are large).', 'number', to_jsonb(200), 10, 500, 'items', 802, 'Platform Admin 16 Oct 2026: Zoho API v2 (as the website sync)', 'Zoho API', 'public.zoho_v2_sync'),
 ('pipeline', 'zoho.sync_item_unit_bytes', 'Zoho sync page size unit', 'A sync page holds up to the page size in units of this many bytes, so a page stays near 600 KB.', 'number', to_jsonb(3072), 512, 65536, 'bytes', 803, 'Platform Admin 16 Oct 2026: Zoho API v2 (as the website sync)', 'Zoho API', 'public.zoho_v2_sync'),
 ('pipeline', 'zoho.sync_countries', 'Countries in the Zoho change stream and CSV', 'Providers, campuses, contacts and courses of these countries go to the Zoho change stream and the CSV export. Live search and detail cover every country.', 'list', '["AU"]'::jsonb, null, null, null, 804, 'Platform Admin 16 Oct 2026: Dhivya (Zoho CRM), "Australia only for now"', 'Zoho API', 'security.zoho_sync_candidates_v1'),
 ('pipeline', 'zoho.logo_link_days', 'Zoho logo link valid for', 'Logo links in Zoho v2 answers are signed for this many days.', 'number', to_jsonb(365), 1, 3650, 'days', 805, 'Platform Admin 16 Oct 2026: Zoho API v2 (as the website)', 'Zoho API', 'zoho-api-v2'),
 ('pipeline', 'zoho.logo_renew_before_days', 'Send a provider again before its logo link ends', 'A provider with a logo is sent again in the change stream this many days before its logo link ends.', 'number', to_jsonb(30), 1, 365, 'days', 806, 'Platform Admin 16 Oct 2026: Zoho API v2 (as the website)', 'Zoho API', 'security.zoho_sync_check_v1'),
 ('pipeline', 'zoho.log_keep_days', 'Keep each API call in the request log for', 'Every call to the API v2 URLs is logged (key, action, result, time). Single calls are kept this long; the daily usage summary is kept.', 'number', to_jsonb(90), 7, 730, 'days', 807, 'Platform Admin 16 Oct 2026: "summary and stat collection"', 'Zoho API', 'security.api_usage_rollup_v1'),
 ('pipeline', 'batch.zoho_sync_check', 'Zoho change check items per run', 'Each run (every minute) checks this many Zoho stream items for new, changed and removed items. About 3 ms an item (16 Oct 2026).', 'number', to_jsonb(1500), 50, 5000, 'items', 808, 'Platform Admin 16 Oct 2026: Zoho API v2 (as the website check)', 'Zoho API', 'zoho-sync-check job')
on conflict do nothing;

-- 2 Keys: one row per consumer; only the SHA-256 of the key is kept
create table if not exists private.api_keys (
  key_name text primary key,
  platform text not null check (platform in ('zoho', 'website')),
  api_version text not null,
  consumer text not null,
  token_sha256 text not null unique check (token_sha256 ~ '^[0-9a-f]{64}$'),
  enabled boolean not null default true,
  rate_per_minute integer check (rate_per_minute is null or rate_per_minute between 1 and 10000),
  created_at timestamptz not null default now(),
  rotated_at timestamptz,
  last_used_at timestamptz,
  note text);
comment on table private.api_keys is 'CF-247 16 Oct 2026: keys for the versioned API URLs (from Zoho API v2 on). One row per consumer; a key works only on its own platform and version. Only the SHA-256 is kept; the key itself was handed to the Platform Admin once. rate_per_minute null = the platform setting.';
alter table private.api_keys enable row level security;
revoke all on private.api_keys from public, anon, authenticated;
insert into private.api_keys(key_name, platform, api_version, consumer, token_sha256, note) values
 ('zoho_creator_v2', 'zoho', 'v2', 'Zoho Creator app (counsellor search; Certify Technologies, Divya)', '13d9ff668e8c4460cd076e65e1cc035ea45b225932aae3af7afd16625c4677d8', 'Platform Admin 16 Oct 2026: "Creator + CRM sync"'),
 ('zoho_crm_sync_v2', 'zoho', 'v2', 'Zoho CRM sync (institutes and courses modules; StudySquare support team, Dhivya)', 'b401f0d61e70bc91dbebd853554d1ba71a3beec9b66bb47c269e99698219f68d', 'Platform Admin 16 Oct 2026: "Creator + CRM sync"')
on conflict (key_name) do nothing;

-- 3 Request log and daily usage
create table if not exists pipeline.api_requests (
  id bigserial primary key,
  at timestamptz not null default now(),
  platform text not null,
  api_version text not null,
  key_name text,
  action text,
  status integer not null,
  elapsed_ms integer,
  items integer,
  bytes integer,
  error_code text,
  request_id uuid);
comment on table pipeline.api_requests is 'CF-247 16 Oct 2026 (Platform Admin: "summary and stat collection"): one row per call to a versioned API URL (from Zoho API v2 on): key, action, HTTP status, time taken, items and bytes returned. Kept zoho.log_keep_days; summed into pipeline.api_usage_daily.';
create index if not exists api_requests_at on pipeline.api_requests (at);
create index if not exists api_requests_key_at on pipeline.api_requests (key_name, at);
alter table pipeline.api_requests enable row level security;
revoke all on pipeline.api_requests from anon, authenticated;

create table if not exists pipeline.api_usage_daily (
  day date not null,
  platform text not null,
  api_version text not null,
  key_name text not null,
  action text not null,
  calls integer not null,
  ok integer not null,
  client_errors integer not null,
  rate_limited integer not null,
  server_errors integer not null,
  avg_ms integer,
  p95_ms integer,
  max_ms integer,
  items bigint,
  bytes bigint,
  first_at timestamptz,
  last_at timestamptz,
  primary key (day, platform, api_version, key_name, action));
comment on table pipeline.api_usage_daily is 'CF-247 16 Oct 2026: calls per day, platform, version, key and action (ok, client errors, rate limited, server errors, average, 95th percentile and slowest time, items and bytes). Summed from pipeline.api_requests by the api-usage-rollup job; never removed.';
alter table pipeline.api_usage_daily enable row level security;
revoke all on pipeline.api_usage_daily from anon, authenticated;

CREATE OR REPLACE FUNCTION security.api_usage_rollup_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int; v_del int;
begin
  insert into pipeline.api_usage_daily(day, platform, api_version, key_name, action, calls, ok, client_errors, rate_limited, server_errors, avg_ms, p95_ms, max_ms, items, bytes, first_at, last_at)
  select (r.at at time zone 'Australia/Melbourne')::date, r.platform, r.api_version, coalesce(r.key_name, '(no key)'), coalesce(r.action, '(none)'),
         count(*), count(*) filter (where r.status < 400), count(*) filter (where r.status >= 400 and r.status < 500 and r.status <> 429),
         count(*) filter (where r.status = 429), count(*) filter (where r.status >= 500),
         round(avg(r.elapsed_ms)), round(percentile_cont(0.95) within group (order by r.elapsed_ms)), max(r.elapsed_ms),
         sum(coalesce(r.items, 0)), sum(coalesce(r.bytes, 0)), min(r.at), max(r.at)
    from pipeline.api_requests r
   where r.at >= date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne' - make_interval(days => 1)  -- fixed: today and yesterday (Melbourne) are summed again each run
   group by 1, 2, 3, 4, 5
  on conflict (day, platform, api_version, key_name, action) do update set calls = excluded.calls, ok = excluded.ok, client_errors = excluded.client_errors,
     rate_limited = excluded.rate_limited, server_errors = excluded.server_errors, avg_ms = excluded.avg_ms, p95_ms = excluded.p95_ms, max_ms = excluded.max_ms,
     items = excluded.items, bytes = excluded.bytes, first_at = excluded.first_at, last_at = excluded.last_at;
  get diagnostics v_n = row_count;
  update private.api_keys k set last_used_at = x.last_at
    from (select key_name, max(at) last_at from pipeline.api_requests where key_name is not null group by 1) x
   where x.key_name = k.key_name and (k.last_used_at is null or k.last_used_at < x.last_at);
  delete from pipeline.api_requests where at < now() - make_interval(days => security.pipeline_num_v1('zoho.log_keep_days', 90)::int);
  get diagnostics v_del = row_count;
  return jsonb_build_object('summary_rows', v_n, 'log_rows_removed', v_del);
end $function$;

-- for the edge function: who is calling, may it call now, and the log line
CREATE OR REPLACE FUNCTION public.zoho_v2_auth(p_token_sha256 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare k private.api_keys%rowtype;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into k from private.api_keys where platform = 'zoho' and api_version = 'v2' and enabled and token_sha256 = lower(coalesce(p_token_sha256, ''));
  if k.key_name is null then return null; end if;
  return jsonb_build_object('key_name', k.key_name, 'rate_per_minute', coalesce(k.rate_per_minute, security.pipeline_num_v1('zoho.rate_per_minute', 120)::int),
                            'logo_link_days', security.pipeline_num_v1('zoho.logo_link_days', 365), 'page_max', security.pipeline_num_v1('zoho.page_max', 50)::int);
end $function$;

CREATE OR REPLACE FUNCTION public.zoho_v2_rate(p_key_name text, p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return api.zoho_integration_rate_check_v1('zoho-v2:' || p_key_name, 'all', p_limit, 60);  -- fixed: the limit is per minute
end $function$;

CREATE OR REPLACE FUNCTION public.zoho_v2_log(p_key_name text, p_action text, p_status integer, p_elapsed_ms integer, p_items integer, p_bytes integer, p_error_code text, p_request_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.api_requests(platform, api_version, key_name, action, status, elapsed_ms, items, bytes, error_code, request_id)
  values ('zoho', 'v2', p_key_name, left(p_action, 40), p_status, p_elapsed_ms, p_items, p_bytes, left(p_error_code, 40), p_request_id);
end $function$;

-- usage for the admin screen (Platform Admin and pipeline operators)
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
               'enabled', k.enabled, 'rate_per_minute', coalesce(k.rate_per_minute, security.pipeline_num_v1('zoho.rate_per_minute', 120)::int),
               'created_at', k.created_at, 'last_used_at', k.last_used_at) order by k.platform, k.api_version, k.key_name), '[]'::jsonb) from private.api_keys k),
    'daily', (select coalesce(jsonb_agg(to_jsonb(d) order by d.day desc, d.platform, d.key_name, d.action), '[]'::jsonb) from pipeline.api_usage_daily d
               where d.day > (now() at time zone 'Australia/Melbourne')::date - v_days),
    'last_hour', (select coalesce(jsonb_agg(jsonb_build_object('key_name', x.key_name, 'action', x.action, 'calls', x.n, 'errors', x.e, 'avg_ms', x.ms)), '[]'::jsonb)
               from (select key_name, action, count(*) n, count(*) filter (where status >= 400) e, round(avg(elapsed_ms)) ms from pipeline.api_requests
                      where at > now() - interval '1 hour' group by 1, 2) x),  -- fixed: the screen's last-hour panel
    'recent_errors', (select coalesce(jsonb_agg(jsonb_build_object('at', r.at, 'key_name', r.key_name, 'action', r.action, 'status', r.status, 'error_code', r.error_code, 'request_id', r.request_id) order by r.at desc), '[]'::jsonb)
               from (select * from pipeline.api_requests where status >= 400 order by at desc limit 20) r),
    'days', v_days);
end $function$;

-- 4 Extras every Zoho v2 course and provider carries
CREATE OR REPLACE FUNCTION security.zoho_v2_provider_cricos_v1(p_provider_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select upper(pr.registration_code) from catalogue.provider_registrations pr
   where pr.provider_id = p_provider_id and lower(pr.registration_scheme) = 'cricos' and nullif(btrim(pr.registration_code), '') is not null
   order by (coalesce(pr.status, 'active') in ('inactive', 'cancelled', 'archived')), pr.checked_at desc nulls last limit 1
$function$;

CREATE OR REPLACE FUNCTION security.zoho_v2_course_extra_v1(p_item jsonb, p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb := p_item; v_pid uuid;
begin
  if v is null or v = 'null'::jsonb then return null; end if;
  select c.provider_id into v_pid from catalogue.courses c where c.id = p_course_id;
  v := v || jsonb_build_object(
    'cricos_course_code', (select upper(cr.registration_code) from catalogue.course_registrations cr where cr.course_id = p_course_id and lower(cr.scheme) = 'cricos' order by cr.registration_code limit 1),
    'publication_status', 'published');  -- Zoho v2: returned items are those the provider Published switch allows
  if jsonb_typeof(v->'provider') = 'object' then
    v := jsonb_set(v, '{provider,cricos_provider_code}', coalesce(to_jsonb(security.zoho_v2_provider_cricos_v1(v_pid)), 'null'::jsonb));
  end if;
  return v;
end $function$;

-- a provider of the Zoho stream: every published provider, with or without courses
CREATE OR REPLACE FUNCTION security.zoho_v2_provider_item_v1(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p catalogue.providers%rowtype; v jsonb;
begin
  select * into p from catalogue.providers where id = p_provider_id;
  if p.id is null or p.lifecycle_status <> 'active' or exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id) then return null; end if;
  -- the website item where the provider has courses (rankings, outcomes, logo, campuses summary), else the basic facts
  select w.item into v from pipeline.website_sync_items w where w.entity = 'provider' and w.item_key = p.stable_key and w.removed_at is null;
  v := coalesce(v, jsonb_build_object('provider_id', p.stable_key, 'name', coalesce(p.display_name, p.canonical_name), 'legal_name', p.canonical_name,
         'website', p.website, 'institution_type', api.website_v2_institution_type(p.id), 'course_count', 0, 'publication_status', 'published'));
  return v || jsonb_build_object(
    'cricos_provider_code', security.zoho_v2_provider_cricos_v1(p.id),
    'country_code', (select c.iso_alpha2 from ref.countries c where c.id = p.country_id),
    'subdivision_code', (select s.code from ref.subdivisions s where s.id = p.subdivision_id),
    'city', p.primary_city, 'postcode', p.postcode, 'phone', p.phone, 'email', p.email,
    'campus_count', (select count(*) from catalogue.campuses k where k.provider_id = p.id and coalesce(k.status, 'active') = 'active'),
    'contact_count', (select count(*) from pipeline.provider_contact_points cp where cp.provider_id = p.id and cp.is_current)
                     + (select count(*) from pipeline.provider_contacts pc where pc.provider_id = p.id and pc.lifecycle_status = 'active' and pc.deleted_at is null),
    'updated_at', p.updated_at);
end $function$;

CREATE OR REPLACE FUNCTION security.zoho_v2_campus_item_v1(p_campus_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'campus_id', coalesce(k.stable_key, k.id::text), 'name', k.name, 'campus_code', k.campus_code,
    'provider_id', p.stable_key, 'cricos_provider_code', security.zoho_v2_provider_cricos_v1(p.id), 'provider_name', coalesce(p.display_name, p.canonical_name),
    'address_line1', k.address_line1, 'address_line2', k.address_line2, 'city', k.city, 'postcode', k.postcode,
    'subdivision_code', (select s.code from ref.subdivisions s where s.id = k.subdivision_id),
    'country_code', (select c.iso_alpha2 from ref.countries c where c.id = coalesce(k.country_id, p.country_id)),
    'latitude', k.latitude, 'longitude', k.longitude, 'phone', k.phone, 'website', k.website,
    'metro_area', rc.metro_area, 'regional_category', rc.category,
    'course_count', (select count(*) from catalogue.course_campuses cc join catalogue.courses c on c.id = cc.course_id where cc.campus_id = k.id and c.lifecycle_status = 'active'),
    'status', coalesce(k.status, 'active'), 'updated_at', k.updated_at)
  from catalogue.campuses k join catalogue.providers p on p.id = k.provider_id
  left join pipeline.campus_regional_class rc on rc.campus_id = k.id
  where k.id = p_campus_id and p.lifecycle_status = 'active'
    and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
$function$;

-- a contact: 'pt:<id>' a contact point (public general contact from the provider's site, or the head of institution from CRICOS);
-- 'pc:<id>' a team or named staff contact (current version)
CREATE OR REPLACE FUNCTION security.zoho_v2_contact_item_v1(p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if p_key like 'pt:%' then
    select jsonb_build_object('contact_id', p_key, 'provider_id', p.stable_key, 'cricos_provider_code', security.zoho_v2_provider_cricos_v1(p.id),
             'provider_name', coalesce(p.display_name, p.canonical_name),
             'type', case cp.kind when 'regulatory_peo' then 'head_of_institution' when 'public_general' then 'general' else cp.kind end,
             'name', cp.name, 'title', cp.title, 'team', null, 'email', cp.email, 'phone', cp.phone,
             'source', case cp.source when 'cricos' then 'CRICOS register' when 'provider_site' then 'Provider website' else cp.source end,
             'source_url', cp.source_url, 'checked_at', cp.observed_at)
      into v
      from pipeline.provider_contact_points cp join catalogue.providers p on p.id = cp.provider_id
     where cp.id::text = substr(p_key, 4) and cp.is_current and p.lifecycle_status = 'active'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id);
  elsif p_key like 'pc:%' then
    select jsonb_build_object('contact_id', p_key, 'provider_id', p.stable_key, 'cricos_provider_code', security.zoho_v2_provider_cricos_v1(p.id),
             'provider_name', coalesce(p.display_name, p.canonical_name),
             'type', case pc.record_type when 'named_staff' then 'staff' when 'team_contact' then 'team' else pc.record_type end,
             'name', cv.full_name, 'title', cv.job_title, 'team', cv.team_name, 'email', cv.work_email, 'phone', cv.work_phone,
             'source', coalesce(cv.source_class, 'Contact list'), 'source_url', cv.source_url, 'checked_at', coalesce(cv.verified_on::timestamptz, cv.created_at))
      into v
      from pipeline.provider_contacts pc join pipeline.provider_contact_versions cv on cv.id = pc.current_version_id
      join catalogue.providers p on p.id = pc.provider_id
     where pc.id::text = substr(p_key, 4) and pc.lifecycle_status = 'active' and pc.deleted_at is null and p.lifecycle_status = 'active'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id);
  end if;
  return v;
end $function$;


CREATE OR REPLACE FUNCTION security.zoho_v2_csv_v1(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when p is null then '' when p ~ '[",\r\n]' or p <> btrim(p) then '"' || replace(p, '"', '""') || '"' else p end
$function$;

-- 5 Read actions (service role only; the edge function zoho-api-v2 is the only caller)
CREATE OR REPLACE FUNCTION public.zoho_v2_reference()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return (public.website_v2_reference() - 'contract_version') || jsonb_build_object('api_version', 'zoho-v2',
    'sync', jsonb_build_object('entities', jsonb_build_array('provider', 'campus', 'contact', 'course'),
      'countries', coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zoho.sync_countries'), '["AU"]'::jsonb),
      'items', (select coalesce(jsonb_object_agg(z.entity, z.n), '{}'::jsonb) from (select entity, count(*) n from pipeline.zoho_sync_items where removed_at is null group by 1) z),
      'checked_through', (select case when bool_or(s.last_cycle_at is null) then null else min(s.last_cycle_at) end from pipeline.zoho_sync_scan s)));
end $function$;

CREATE OR REPLACE FUNCTION public.zoho_v2_course_search(p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1, p_page_size integer DEFAULT 20, p_sort text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'catalogue', 'ref', 'pipeline', 'security', 'api'
AS $function$
declare
  f jsonb := coalesce(p_filters,'{}'::jsonb);
  v_page int := coalesce(p_page,1);
  v_size int := coalesce(p_page_size,20);
  v_kw text := nullif(btrim(coalesce(f->>'keyword','')),'');
  v_q tsquery;
  v_countries text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(coalesce(f->'country_codes',f->'country_code'))) x);
  v_areas text[] := api.website_text_array(f->'study_area_codes');
  v_levels text[] := api.website_text_array(f->'study_level_codes');
  v_subdivs text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(f->'subdivision_codes')) x);
  v_cities text[] := (select array_agg(lower(x)) from unnest(api.website_text_array(coalesce(f->'cities',f->'city'))) x);
  v_postcodes text[] := api.website_text_array(f->'postcodes');
  v_regional int[] := (select array_agg(x::int) from unnest(api.website_text_array(f->'regional_categories')) x where x ~ '^[1-3]$');
  v_providers text[] := api.website_text_array(f->'provider_ids');
  v_groups text[] := (select array_agg(lower(regexp_replace(btrim(x),'^au_','','i'))) from unnest(api.website_text_array(coalesce(f->'university_groups',f->'university_group'))) x);
  v_modes text[] := api.website_text_array(f->'delivery_modes');
  v_months int[] := (select array_agg(x::int) from unnest(api.website_text_array(f->'intake_months')) x where x ~ '^([1-9]|1[0-2])$');
  v_tests text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(f->'english_test_codes')) x);
  v_score_max numeric := nullif(f->>'english_score_max','')::numeric;
  v_band_max numeric := nullif(f->>'english_band_max','')::numeric;  -- Zoho v2: the student's lowest band; courses whose every band asks no more
  v_pname text := nullif(btrim(coalesce(f->>'provider_name','')),'');  -- Zoho v2: provider name as text
  v_pcricos text[] := (select array_agg(upper(btrim(x))) from unnest(api.website_text_array(f->'provider_cricos_codes')) x);
  v_page_max int := greatest(security.pipeline_num_v1('zoho.page_max', 50)::int, 1);
  v_min numeric := nullif(f->>'tuition_annual_min','')::numeric;
  v_max numeric := nullif(f->>'tuition_annual_max','')::numeric;
  v_changed timestamptz := nullif(f->>'changed_since','')::timestamptz;
  v_sort text := coalesce(nullif(p_sort,''), case when nullif(btrim(coalesce(f->>'keyword','')),'') is not null then 'relevance' else 'title_asc' end);
  v_known text[] := array['keyword','country_codes','country_code','study_area_codes','study_level_codes','subdivision_codes','cities','city','postcodes','regional_categories',
                          'provider_ids','university_groups','university_group','delivery_modes','intake_months','english_test_codes','english_score_max',
                          'tuition_annual_min','tuition_annual_max','has_intake','has_english','has_official_url','has_scholarship','has_tuition','changed_since','institution_types',
                          'english_band_max','provider_name','provider_cricos_codes'];
  v_not_applied jsonb;
  v_total bigint; v_ids uuid[];
  v_need_fee boolean;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if v_page < 1 then raise exception 'INVALID_INPUT: page must be >= 1' using errcode='22023'; end if;
  if v_size < 1 or v_size > v_page_max then raise exception 'INVALID_INPUT: page_size must be 1-%', v_page_max using errcode='22023'; end if;
  if v_sort not in ('relevance','title_asc','tuition_annual_asc','tuition_annual_desc','duration_asc','updated_asc') then raise exception 'INVALID_INPUT: unknown sort' using errcode='22023'; end if;
  if (v_score_max is not null or v_band_max is not null) and coalesce(cardinality(v_tests),0) <> 1 then raise exception 'INVALID_INPUT: english_score_max and english_band_max need exactly one english_test_codes value' using errcode='22023'; end if;
  if v_kw is not null then v_q := websearch_to_tsquery('english', v_kw); end if;
  v_need_fee := (v_min is not null or v_max is not null or coalesce((f->>'has_tuition')::boolean,false) or v_sort in ('tuition_annual_asc','tuition_annual_desc'));
  select coalesce(jsonb_agg(k),'[]'::jsonb) into v_not_applied from jsonb_object_keys(f) k where k <> all(v_known);

  with base as (
    select d.course_id, d.course_title, d.course_stable_key, d.updated_at, d.provider_name,
      case when not v_need_fee then null
           when pt.amt is not null then
             case when pt.bas ~* 'total|course' and pt.bas !~* 'annual' then case when w.wk >= 52 then round(pt.amt / (w.wk/52.0)) end
                  when pt.bas ~* 'session|semester|trimester|unit|credit' then null
                  when pt.bas ~* 'indicative|annual|per.?year|yearly' then pt.amt end
           when d.regulatory_tuition_amount >= 1000 and w.wk >= 52 then round(d.regulatory_tuition_amount / (w.wk/52.0)) end ann,
      case when v_need_fee then (pt.amt is not null or coalesce(d.regulatory_tuition_amount,0) >= 1000) end has_fee,
      w.wk * 12.0 / 52 dur_months,
      case when v_kw is null then 0 else
        ts_rank(d.search_tsv, v_q) + case when d.course_title ilike '%'||v_kw||'%' then 1 else 0 end
          + case when d.course_title ilike v_kw||'%' then 0.5 else 0 end + case when lower(d.course_code) = lower(v_kw) then 2 else 0 end end rel
    from search.course_documents d
    left join catalogue.courses c on c.id = d.course_id
    cross join lateral (select case lower(coalesce(c.duration_unit,'')) when 'weeks' then c.duration_value when 'months' then c.duration_value*52/12.0 when 'years' then c.duration_value*52 end wk) w
    left join lateral (select (o->>'amount')::numeric amt, o->>'basis' bas
                       from jsonb_array_elements(coalesce(d.provider_tuition_options,'[]'::jsonb)) o
                       where (o->>'amount') ~ '^[0-9]+(\.[0-9]+)?$' and (o->>'amount')::numeric >= 1000
                       order by nullif(o->>'fee_year','')::int desc nulls last limit 1) pt on v_need_fee
    where (d.course_id is null or d.course_id not in (select b.course_id from security.layer4_search_blocked_courses b where b.course_id is not null))
      and (v_kw is null or d.search_tsv @@ v_q or d.course_title ilike '%'||v_kw||'%' or d.provider_name ilike '%'||v_kw||'%'
           or lower(d.course_code) = lower(v_kw) or lower(d.course_stable_key) = lower(v_kw))
      and (v_countries is null or d.country_code = any(v_countries))
      and (v_areas is null or d.primary_field_code = any(v_areas))
      and (v_levels is null or d.study_level_code = any(v_levels))
      and (v_subdivs is null or d.subdivision_codes && v_subdivs)
      and (v_providers is null or d.provider_stable_key = any(v_providers))
      and (v_pname is null or d.provider_name ilike '%'||v_pname||'%')
      and (v_pcricos is null or exists (select 1 from catalogue.provider_registrations pr where pr.provider_id = d.provider_id
            and lower(pr.registration_scheme) = 'cricos' and upper(pr.registration_code) = any(v_pcricos)))
      and (f->'institution_types' is null or api.website_v2_institution_type_code(d.provider_id) = any(api.website_text_array(f->'institution_types')))
      and (v_groups is null or exists (select 1 from catalogue.provider_collection_memberships gm join ref.institution_collections gic on gic.id=gm.collection_id
            where gm.provider_id=d.provider_id and gm.status='active' and (gm.valid_to is null or gm.valid_to>=current_date)
              and gic.collection_type='university_group' and gic.status='active' and replace(gic.code,'au_','') = any(v_groups)))
      and (v_modes is null or d.delivery_modes && v_modes)
      and (not coalesce((f->>'has_intake')::boolean,false) or d.has_intake)
      and (not coalesce((f->>'has_english')::boolean,false) or d.has_english)
      and (not coalesce((f->>'has_official_url')::boolean,false) or d.has_link)
      and (not coalesce((f->>'has_scholarship')::boolean,false) or d.has_scholarship)
      and (v_changed is null or greatest(d.updated_at, d.source_updated_at) >= v_changed)
      and (v_months is null or exists (select 1 from jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) i where api.website_v2_label_month(i->>'label') = any(v_months)))
      and (v_tests is null or exists (select 1 from jsonb_array_elements(coalesce(d.english_requirement_options,'[]'::jsonb)) e
            where upper(e->>'test_code') = any(v_tests) and (v_score_max is null or ((e->>'overall_score') ~ '^[0-9]+(\.[0-9]+)?$' and (e->>'overall_score')::numeric <= v_score_max))
              and (v_band_max is null or not exists (select 1 from jsonb_each_text(case when jsonb_typeof(e->'component_scores') = 'object' then e->'component_scores' else '{}'::jsonb end) cs
                                                  where cs.value ~ '^[0-9]+(\.[0-9]+)?$' and cs.value::numeric > v_band_max))))
      and ((v_cities is null and v_postcodes is null and v_regional is null) or exists (
            select 1 from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id left join pipeline.campus_regional_class rc on rc.campus_id = k.id
            where cc.course_id = d.course_id
              and (v_cities is null or lower(btrim(k.city)) = any(v_cities) or lower(rc.metro_area) = any(v_cities))
              and (v_postcodes is null or btrim(k.postcode) = any(v_postcodes))
              and (v_regional is null or rc.category = any(v_regional))))
  ), filtered as (
    select * from base b
    where (not coalesce((f->>'has_tuition')::boolean,false) or b.has_fee)
      and (v_min is null or b.ann >= v_min)
      and (v_max is null or b.ann <= v_max)
  ), ordered as (
    select course_id, count(*) over () total,
      row_number() over (order by
        case when v_sort='relevance' then rel end desc nulls last,
        case when v_sort='tuition_annual_asc' then ann end asc nulls last,
        case when v_sort='tuition_annual_desc' then ann end desc nulls last,
        case when v_sort='duration_asc' then dur_months end asc nulls last,
        case when v_sort='updated_asc' then updated_at end asc,
        lower(course_title), course_stable_key) rn
    from filtered
  )
  select coalesce(max(total),0), array_agg(course_id order by rn) filter (where rn > (v_page-1)*v_size and rn <= v_page*v_size)
    into v_total, v_ids from ordered;

  return jsonb_build_object(
    'api_version','zoho-v2',
    'total', v_total, 'page', v_page, 'page_size', v_size, 'sort', v_sort,
    'filters_not_applied', v_not_applied,
    'items', coalesce((select jsonb_agg(security.zoho_v2_course_extra_v1(api.website_v2_course_item(x.id, v_cities, v_postcodes), x.id) order by x.ord) from unnest(v_ids) with ordinality x(id, ord)), '[]'::jsonb));
end $function$;


CREATE OR REPLACE FUNCTION public.zoho_v2_course(p_identifier text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r jsonb; v_id uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  r := public.website_v2_course(p_identifier);
  if r ? 'error' then return jsonb_build_object('api_version', 'zoho-v2', 'error', r->'error'); end if;
  select d.course_id into v_id from search.course_documents d where d.course_stable_key = r->'item'->>'course_id';
  return jsonb_build_object('api_version', 'zoho-v2', 'item', security.zoho_v2_course_extra_v1(r->'item', v_id));
end $function$;

-- several courses at once (for example the CRICOS codes on a lead), in the order asked; ones not found are listed
CREATE OR REPLACE FUNCTION public.zoho_v2_courses(p_identifiers text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare x text; r jsonb; v_items jsonb := '[]'::jsonb; v_missing jsonb := '[]'::jsonb; v_max int := greatest(security.pipeline_num_v1('zoho.page_max', 50)::int, 1);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_identifiers is null or cardinality(p_identifiers) = 0 or cardinality(p_identifiers) > v_max then
    raise exception 'INVALID_INPUT: identifiers must hold 1-% values', v_max using errcode = '22023'; end if;
  foreach x in array p_identifiers loop
    r := public.zoho_v2_course(x);
    if r ? 'item' then v_items := v_items || jsonb_build_array(r->'item'); else v_missing := v_missing || to_jsonb(x); end if;
  end loop;
  return jsonb_build_object('api_version', 'zoho-v2', 'items', v_items, 'not_found', v_missing);
end $function$;

CREATE OR REPLACE FUNCTION public.zoho_v2_providers(p_filters jsonb, p_page integer, p_page_size integer, p_sort text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f jsonb := coalesce(p_filters, '{}'::jsonb); r jsonb; v_codes text[]; v_ids jsonb; v_max int := greatest(security.pipeline_num_v1('zoho.page_max', 50)::int, 1);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if coalesce(p_page_size, 20) > v_max then raise exception 'INVALID_INPUT: page_size must be 1-%', v_max using errcode = '22023'; end if;
  -- Zoho v2 filters: provider_name (text, as keyword) and provider_cricos_codes (as provider_ids)
  if nullif(btrim(coalesce(f->>'provider_name', '')), '') is not null and f->>'keyword' is null then f := (f - 'provider_name') || jsonb_build_object('keyword', f->>'provider_name'); end if;
  v_codes := (select array_agg(upper(btrim(x))) from unnest(api.website_text_array(f->'provider_cricos_codes')) x);
  if v_codes is not null then
    select coalesce(jsonb_agg(distinct p.stable_key), '[]'::jsonb) into v_ids from catalogue.provider_registrations pr join catalogue.providers p on p.id = pr.provider_id
     where lower(pr.registration_scheme) = 'cricos' and upper(pr.registration_code) = any(v_codes);
    if jsonb_array_length(v_ids) = 0 then return jsonb_build_object('api_version', 'zoho-v2', 'total', 0, 'page', coalesce(p_page, 1), 'page_size', coalesce(p_page_size, 20), 'items', '[]'::jsonb); end if;
    f := (f - 'provider_cricos_codes') || jsonb_build_object('provider_ids', v_ids);
  end if;
  r := public.website_v2_providers(f, p_page, p_page_size, p_sort);
  if r ? 'error' then return jsonb_build_object('api_version', 'zoho-v2', 'error', r->'error'); end if;
  return (r - 'contract_version') || jsonb_build_object('api_version', 'zoho-v2', 'items',
    coalesce((select jsonb_agg(x.it || jsonb_build_object('cricos_provider_code', security.zoho_v2_provider_cricos_v1(p.id)) order by x.ord)
                from jsonb_array_elements(r->'items') with ordinality x(it, ord) left join catalogue.providers p on p.stable_key = x.it->>'provider_id'), '[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.zoho_v2_provider(p_identifier text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_pid uuid; v jsonb; w jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if nullif(btrim(coalesce(p_identifier, '')), '') is null then raise exception 'INVALID_INPUT: provider_id or cricos_provider_code required' using errcode = '22023'; end if;
  select p.id into v_pid from catalogue.providers p where lower(p.stable_key) = lower(btrim(p_identifier)) limit 1;
  if v_pid is null then
    select pr.provider_id into v_pid from catalogue.provider_registrations pr where lower(pr.registration_scheme) = 'cricos' and upper(pr.registration_code) = upper(btrim(p_identifier)) limit 1;
  end if;
  v := case when v_pid is null then null else security.zoho_v2_provider_item_v1(v_pid) end;
  if v is null then return jsonb_build_object('api_version', 'zoho-v2', 'error', jsonb_build_object('code', 'NOT_FOUND')); end if;
  w := public.website_v2_provider(v->>'provider_id');  -- full detail (rankings with indicators, outcomes) where the provider has courses
  if w ? 'item' then v := (w->'item') || (v - 'logo' - 'rankings' - 'outcomes' - 'campuses'); end if;
  return jsonb_build_object('api_version', 'zoho-v2', 'item', v || jsonb_build_object(
    'campuses', coalesce((select jsonb_agg(security.zoho_v2_campus_item_v1(k.id) order by k.name) from catalogue.campuses k where k.provider_id = v_pid and coalesce(k.status, 'active') = 'active'), '[]'::jsonb),
    'contacts', coalesce((select jsonb_agg(c order by c->>'type', c->>'name') from (
        select security.zoho_v2_contact_item_v1('pt:' || cp.id) c from pipeline.provider_contact_points cp where cp.provider_id = v_pid and cp.is_current
        union all select security.zoho_v2_contact_item_v1('pc:' || pc.id) from pipeline.provider_contacts pc where pc.provider_id = v_pid and pc.lifecycle_status = 'active' and pc.deleted_at is null) z where c is not null), '[]'::jsonb)));
end $function$;

-- campuses and contacts as lists (filters: provider_ids, provider_cricos_codes, country_codes, subdivision_codes, changed_since)
CREATE OR REPLACE FUNCTION public.zoho_v2_list(p_entity text, p_filters jsonb, p_page integer, p_page_size integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f jsonb := coalesce(p_filters, '{}'::jsonb); v_page int := coalesce(p_page, 1); v_size int := coalesce(p_page_size, 20);
        v_max int := greatest(security.pipeline_num_v1('zoho.page_max', 50)::int, 1);
        v_prov text[] := api.website_text_array(f->'provider_ids');
        v_codes text[] := (select array_agg(upper(btrim(x))) from unnest(api.website_text_array(f->'provider_cricos_codes')) x);
        v_countries text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(f->'country_codes')) x);
        v_subdivs text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(f->'subdivision_codes')) x);
        v_types text[] := api.website_text_array(f->'contact_types');
        v_total bigint; v_items jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_entity not in ('campus', 'contact') then raise exception 'INVALID_INPUT: entity' using errcode = '22023'; end if;
  if v_page < 1 or v_size < 1 or v_size > v_max then raise exception 'INVALID_INPUT: page >= 1, page_size 1-%', v_max using errcode = '22023'; end if;
  with pv as (
    select p.id from catalogue.providers p
     where p.lifecycle_status = 'active' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
       and (v_prov is null or p.stable_key = any(v_prov))
       and (v_codes is null or exists (select 1 from catalogue.provider_registrations pr where pr.provider_id = p.id and lower(pr.registration_scheme) = 'cricos' and upper(pr.registration_code) = any(v_codes)))
       and (v_countries is null or exists (select 1 from ref.countries c where c.id = p.country_id and c.iso_alpha2 = any(v_countries)))),
  -- cheap keys first; items are built for the page only
  rows as (
    select 'campus' kind, k.id::text ref, coalesce(p.display_name, p.canonical_name) pn, coalesce(k.name, '') sk, null::text typ from catalogue.campuses k join catalogue.providers p on p.id = k.provider_id
     where p_entity = 'campus' and k.provider_id in (select id from pv) and coalesce(k.status, 'active') = 'active'
       and (v_subdivs is null or exists (select 1 from ref.subdivisions s where s.id = k.subdivision_id and s.code = any(v_subdivs)))
    union all
    select 'pt', cp.id::text, coalesce(p.display_name, p.canonical_name), coalesce(cp.name, ''),
           case cp.kind when 'regulatory_peo' then 'head_of_institution' when 'public_general' then 'general' else cp.kind end
      from pipeline.provider_contact_points cp join catalogue.providers p on p.id = cp.provider_id
     where p_entity = 'contact' and cp.is_current and cp.provider_id in (select id from pv)
    union all
    select 'pc', pc.id::text, coalesce(p.display_name, p.canonical_name), '', case pc.record_type when 'named_staff' then 'staff' when 'team_contact' then 'team' else pc.record_type end
      from pipeline.provider_contacts pc join catalogue.providers p on p.id = pc.provider_id
     where p_entity = 'contact' and pc.lifecycle_status = 'active' and pc.deleted_at is null and pc.provider_id in (select id from pv)),
  kept as (select * from rows where v_types is null or typ = any(v_types)),
  ordered as (select kind, ref, count(*) over () total, row_number() over (order by pn, typ, sk, ref) rn from kept),
  page as (select * from ordered where rn > (v_page - 1) * v_size and rn <= v_page * v_size)
  select coalesce((select max(total) from ordered), 0),
         coalesce((select jsonb_agg(case when kind = 'campus' then security.zoho_v2_campus_item_v1(ref::uuid) else security.zoho_v2_contact_item_v1(kind || ':' || ref) end order by rn) from page), '[]'::jsonb)
    into v_total, v_items;
  return jsonb_build_object('api_version', 'zoho-v2', 'total', v_total, 'page', v_page, 'page_size', v_size, 'items', v_items);
end $function$;

-- statistics: QILT (provider grain) and PRISMS (international enrolments by region, sector and study area)
CREATE OR REPLACE FUNCTION public.zoho_v2_statistics(p_kind text, p_filters jsonb, p_page integer, p_page_size integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f jsonb := coalesce(p_filters, '{}'::jsonb); v_page int := coalesce(p_page, 1); v_size int := coalesce(p_page_size, 20);
        v_max int := greatest(security.pipeline_num_v1('zoho.page_max', 50)::int, 1);
        v_prov text[] := api.website_text_array(f->'provider_ids');
        v_codes text[] := (select array_agg(upper(btrim(x))) from unnest(api.website_text_array(f->'provider_cricos_codes')) x);
        v_subdivs text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(f->'subdivision_codes')) x);
        v_sectors text[] := api.website_text_array(f->'sectors');
        v_total bigint; v_items jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if coalesce(p_kind, '') not in ('qilt', 'prisms') then raise exception 'INVALID_INPUT: kind must be qilt or prisms' using errcode = '22023'; end if;
  if v_page < 1 or v_size < 1 or v_size > v_max then raise exception 'INVALID_INPUT: page >= 1, page_size 1-%', v_max using errcode = '22023'; end if;
  if p_kind = 'qilt' then
    with r as (
      select jsonb_build_object('provider_id', p.stable_key, 'cricos_provider_code', security.zoho_v2_provider_cricos_v1(p.id), 'provider_name', coalesce(p.display_name, p.canonical_name),
               'survey', sv.code, 'survey_name', sv.name, 'metric_code', m.code, 'metric_name', m.name, 'unit', m.unit, 'study_level', o.source_cohort_code,
               'value', o.metric_value, 'ci_low', o.confidence_low, 'ci_high', o.confidence_high, 'national_benchmark', o.national_benchmark,
               'responses', o.response_count, 'reference_year', o.collection_year_to, 'grain', 'provider') it, coalesce(p.display_name, p.canonical_name) n, sv.code s, m.code mc, o.source_cohort_code c
        from catalogue.provider_outcomes o join catalogue.providers p on p.id = o.provider_id join ref.outcome_metrics m on m.id = o.metric_id join ref.outcome_surveys sv on sv.id = o.survey_id
       where o.external_study_area_id is null and o.status in ('current', 'active', 'accepted') and left(sv.code, 5) = 'qilt_'
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
         and (v_prov is null or p.stable_key = any(v_prov))
         and (v_codes is null or exists (select 1 from catalogue.provider_registrations pr where pr.provider_id = p.id and lower(pr.registration_scheme) = 'cricos' and upper(pr.registration_code) = any(v_codes)))),
    o as (select it, count(*) over () t, row_number() over (order by n, s, mc, c) rn from r)
    select coalesce(max(t), 0), coalesce(jsonb_agg(it order by rn) filter (where rn > (v_page - 1) * v_size and rn <= v_page * v_size), '[]'::jsonb) into v_total, v_items from o;
  else
    with r as (
      select jsonb_build_object('region_code', so.source_geography_key, 'region_name', so.source_geography_name, 'region_type', so.source_geography_type,
               'subdivision_code', s.code, 'sector', so.source_sector_code, 'study_area', so.source_study_area_name, 'metric', m.name, 'value', so.metric_value,
               'suppressed', so.is_suppressed, 'period_start', so.period_start, 'period_end', so.period_end, 'period_type', so.period_type, 'grain', 'region') it,
             so.source_geography_name g, so.source_sector_code sc, so.source_study_area_name sa
        from catalogue.student_flow_observations so left join ref.subdivisions s on s.id = so.subdivision_id left join ref.outcome_metrics m on m.id = so.metric_id
       where coalesce(so.status, 'current') in ('current', 'active', 'accepted')
         and (v_subdivs is null or s.code = any(v_subdivs)) and (v_sectors is null or so.source_sector_code = any(v_sectors))),
    o as (select it, count(*) over () t, row_number() over (order by g, sc, sa) rn from r)
    select coalesce(max(t), 0), coalesce(jsonb_agg(it order by rn) filter (where rn > (v_page - 1) * v_size and rn <= v_page * v_size), '[]'::jsonb) into v_total, v_items from o;
  end if;
  return jsonb_build_object('api_version', 'zoho-v2', 'kind', p_kind, 'total', v_total, 'page', v_page, 'page_size', v_size, 'items', v_items);
end $function$;

-- rankings, scholarships, scholarship and report: the shared answers, as Zoho v2
CREATE OR REPLACE FUNCTION public.zoho_v2_passthrough(p_action text, p_filters jsonb, p_page integer, p_page_size integer, p_id text, p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r jsonb; v_max int := greatest(security.pipeline_num_v1('zoho.page_max', 50)::int, 1);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_action in ('rankings', 'scholarships') and coalesce(p_page_size, 20) > v_max then raise exception 'INVALID_INPUT: page_size must be 1-%', v_max using errcode = '22023'; end if;
  r := case p_action
    when 'rankings' then public.website_v2_rankings(coalesce(p_filters, '{}'::jsonb), coalesce(p_page, 1), coalesce(p_page_size, 20))
    when 'scholarships' then public.website_v2_scholarships(coalesce(p_filters, '{}'::jsonb), coalesce(p_page, 1), coalesce(p_page_size, 20))
    when 'scholarship' then public.website_v2_scholarship(p_id)
    when 'report' then public.zoho_edge_report_v1(p_id, coalesce(p_body->>'field', 'other'), p_body->>'note', coalesce(p_body->'reporter', '{}'::jsonb))
  end;
  if r is null then raise exception 'INVALID_INPUT: action' using errcode = '22023'; end if;
  if r ? 'error' and (r->'error'->>'code' = 'NOT_FOUND' or r->>'error' = 'NOT_FOUND') then return jsonb_build_object('api_version', 'zoho-v2', 'error', jsonb_build_object('code', 'NOT_FOUND')); end if;
  return (r - 'contract_version') || jsonb_build_object('api_version', 'zoho-v2');
end $function$;

-- 6 Zoho change stream (its own numbering, so a Zoho delta never depends on the website's)
create sequence if not exists pipeline.zoho_sync_seq;
create table if not exists pipeline.zoho_sync_items (
  entity text not null check (entity in ('provider', 'campus', 'contact', 'course')),
  item_key text not null,
  ref_id uuid,
  hash text,
  seq bigint not null,
  seq_at timestamptz not null default now(),
  removed_at timestamptz,
  item jsonb,
  primary key (entity, item_key));
comment on table pipeline.zoho_sync_items is 'CF-247 16 Oct 2026 (Zoho API v2): the Zoho change stream. One row per provider, campus, contact and course of the countries in zoho.sync_countries, numbered (seq) when new, changed or removed; the item as last built. Served by the sync action and the CSV export.';
create index if not exists zoho_sync_items_seq on pipeline.zoho_sync_items (seq);
alter table pipeline.zoho_sync_items enable row level security;
revoke all on pipeline.zoho_sync_items from anon, authenticated;
create table if not exists pipeline.zoho_sync_scan (
  entity text primary key, after_key text, done boolean not null default false, cycles integer not null default 0,
  last_cycle_at timestamptz, last_run_at timestamptz, last_result jsonb);
comment on table pipeline.zoho_sync_scan is 'CF-247 16 Oct 2026 (Zoho API v2): where the Zoho change check has got to in its rolling pass, per entity, and when it last finished a pass.';
alter table pipeline.zoho_sync_scan enable row level security;
revoke all on pipeline.zoho_sync_scan from anon, authenticated;
insert into pipeline.zoho_sync_scan(entity) values ('provider'), ('campus'), ('contact'), ('course') on conflict do nothing;

CREATE OR REPLACE FUNCTION security.zoho_sync_candidates_v1(p_entity text)
 RETURNS TABLE(item_key text, ref_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with cn as (select c.id from ref.countries c
               where c.iso_alpha2 in (select jsonb_array_elements_text(coalesce((select s.value from pipeline.platform_toolset_settings s
                                       where s.toolset_key = 'pipeline' and s.key = 'zoho.sync_countries'), '["AU"]'::jsonb)))),
       pv as (select p.id, p.stable_key from catalogue.providers p
               where p.lifecycle_status = 'active' and p.stable_key is not null and p.country_id in (select id from cn)
                 and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id))
  select k, max(r::text)::uuid from (
    select pv.stable_key k, pv.id r from pv where p_entity = 'provider'
    union all
    select coalesce(k.stable_key, k.id::text), k.id from catalogue.campuses k where p_entity = 'campus' and k.provider_id in (select id from pv) and coalesce(k.status, 'active') = 'active'
    union all
    select 'pt:' || cp.id, cp.provider_id from pipeline.provider_contact_points cp where p_entity = 'contact' and cp.is_current and cp.provider_id in (select id from pv)
    union all
    select 'pc:' || pc.id, pc.provider_id from pipeline.provider_contacts pc where p_entity = 'contact' and pc.lifecycle_status = 'active' and pc.deleted_at is null and pc.provider_id in (select id from pv)
    union all
    select d.course_stable_key, d.course_id from search.course_documents d where p_entity = 'course' and d.course_stable_key is not null and d.provider_id in (select id from pv)
    union all
    select i.item_key, i.ref_id from pipeline.zoho_sync_items i where i.entity = p_entity and i.removed_at is null) z
  group by k
$function$;

CREATE OR REPLACE FUNCTION security.zoho_sync_item_v1(p_entity text, p_ref uuid, p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; v_country boolean;
begin
  if p_ref is null then return null; end if;
  if p_entity = 'provider' then
    select exists (select 1 from catalogue.providers p join ref.countries c on c.id = p.country_id where p.id = p_ref
                    and c.iso_alpha2 in (select jsonb_array_elements_text(coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zoho.sync_countries'), '["AU"]'::jsonb))))
      into v_country;
    v := case when v_country then security.zoho_v2_provider_item_v1(p_ref) end;
  elsif p_entity = 'campus' then
    v := security.zoho_v2_campus_item_v1(p_ref);
    if v is not null and not (v->>'country_code' in (select jsonb_array_elements_text(coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zoho.sync_countries'), '["AU"]'::jsonb)))) then v := null; end if;
  elsif p_entity = 'contact' then
    v := security.zoho_v2_contact_item_v1(p_key);
  elsif p_entity = 'course' then
    -- the website's stored course item (already built by its change check), else built now; then the Zoho extras
    select w.item into v from pipeline.website_sync_items w where w.entity = 'course' and w.item_key = p_key and w.removed_at is null;
    if v is null and exists (select 1 from search.course_documents d where d.course_id = p_ref) then v := api.website_v2_course_item(p_ref, null, null); end if;
    v := security.zoho_v2_course_extra_v1(v, p_ref);
    if v is not null and not (v->>'country_code' in (select jsonb_array_elements_text(coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zoho.sync_countries'), '["AU"]'::jsonb)))) then v := null; end if;
  end if;
  return case when v = 'null'::jsonb then null else v end;
end $function$;

CREATE OR REPLACE FUNCTION security.zoho_sync_check_v1(p_items integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_left int := greatest(coalesce(p_items, 0), 1); e text; r record; v jsonb; h text; it pipeline.zoho_sync_items%rowtype;
        st pipeline.zoho_sync_scan%rowtype; v_lim int; v_cnt int; v_w int; v_out jsonb := '{}'::jsonb; v_new int; v_chg int; v_rem int; v_ren int; v_renew interval;
begin
  if not pg_try_advisory_xact_lock(hashtext('zoho-sync-check')) then return jsonb_build_object('skipped', 'another run is working'); end if;  -- fixed: one run at a time
  v_renew := make_interval(days => greatest(security.pipeline_num_v1('zoho.logo_link_days', 365) - security.pipeline_num_v1('zoho.logo_renew_before_days', 30), 1)::int);
  -- a pass walks the entities in order; each run carries on where the last stopped; a new pass starts when all are done
  if not exists (select 1 from pipeline.zoho_sync_scan where not done) then update pipeline.zoho_sync_scan set done = false; end if;
  foreach e in array array['provider', 'campus', 'contact', 'course'] loop
    exit when v_left <= 0;
    select * into st from pipeline.zoho_sync_scan where entity = e for update;
    continue when st.done;
    v_w := 1;  -- fixed: every Zoho item is about one course's build cost (providers and courses reuse stored items), measured 16 Oct 2026
    v_lim := greatest(ceil(v_left::numeric / v_w)::int, 1); v_cnt := 0; v_new := 0; v_chg := 0; v_rem := 0; v_ren := 0;
    for r in select c.item_key, c.ref_id from security.zoho_sync_candidates_v1(e) c
              where st.after_key is null or c.item_key > st.after_key order by c.item_key limit v_lim loop
      v_cnt := v_cnt + 1; v_left := v_left - v_w;
      v := security.zoho_sync_item_v1(e, r.ref_id, r.item_key);
      h := case when v is null then null else md5((v - 'generated_at' - 'freshness')::text) end;  -- CF-247 16 Oct 2026: freshness timestamps are not a change
      select * into it from pipeline.zoho_sync_items where entity = e and item_key = r.item_key;
      if it.item_key is null then
        if v is not null then
          insert into pipeline.zoho_sync_items(entity, item_key, ref_id, hash, seq, item) values (e, r.item_key, r.ref_id, h, nextval('pipeline.zoho_sync_seq'), v);
          v_new := v_new + 1;
        end if;
      elsif v is null then
        if it.removed_at is null then
          update pipeline.zoho_sync_items set removed_at = now(), hash = null, item = null, seq = nextval('pipeline.zoho_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
          v_rem := v_rem + 1;
        end if;
      elsif it.removed_at is not null then
        update pipeline.zoho_sync_items set removed_at = null, hash = h, item = v, ref_id = r.ref_id, seq = nextval('pipeline.zoho_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
        v_new := v_new + 1;
      elsif it.hash is null then
        update pipeline.zoho_sync_items set hash = h, item = v, ref_id = r.ref_id where entity = e and item_key = r.item_key;  -- first check: not a change
      elsif it.hash <> h then
        update pipeline.zoho_sync_items set hash = h, item = v, ref_id = r.ref_id, seq = nextval('pipeline.zoho_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
        v_chg := v_chg + 1;
      elsif e = 'provider' and it.item ? 'logo' and it.seq_at < now() - v_renew then  -- a provider whose logo link is near its end is sent again
        update pipeline.zoho_sync_items set item = v, seq = nextval('pipeline.zoho_sync_seq'), seq_at = now() where entity = e and item_key = r.item_key;
        v_ren := v_ren + 1;
      elsif it.item is null then
        update pipeline.zoho_sync_items set item = v where entity = e and item_key = r.item_key;  -- CF-247 15 Oct 2026: unchanged, stored for sync
      end if;
      st.after_key := r.item_key;
    end loop;
    if v_cnt < v_lim then
      update pipeline.zoho_sync_scan set after_key = null, done = true, cycles = cycles + 1, last_cycle_at = now(), last_run_at = now(),
             last_result = jsonb_build_object('checked', v_cnt, 'new', v_new, 'changed', v_chg, 'removed', v_rem, 'renewed', v_ren) where entity = e;
    else
      update pipeline.zoho_sync_scan set after_key = st.after_key, last_run_at = now(),
             last_result = jsonb_build_object('checked', v_cnt, 'new', v_new, 'changed', v_chg, 'removed', v_rem, 'renewed', v_ren) where entity = e;
    end if;
    v_out := v_out || jsonb_build_object(e, jsonb_build_object('checked', v_cnt, 'new', v_new, 'changed', v_chg, 'removed', v_rem, 'renewed', v_ren));
  end loop;
  return v_out;
end $function$;


CREATE OR REPLACE FUNCTION public.zoho_v2_sync(p_cursor text DEFAULT NULL::text, p_full boolean DEFAULT false, p_entities text[] DEFAULT NULL::text[], p_page_size integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_all text[] := array['provider', 'campus', 'contact', 'course'];
        v_c jsonb; v_mode text; v_a bigint := 0; v_s bigint; v_e text[]; v_max int; v_size int; v_rows jsonb; v_n int; v_more boolean; v_last bigint;
        v_next jsonb; v_items jsonb; t text; v_unit numeric;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if nullif(btrim(p_cursor), '') is not null and not coalesce(p_full, false) then
    begin
      t := translate(btrim(p_cursor), '-_', '+/');
      v_c := convert_from(decode(t || repeat('=', (4 - length(t) % 4) % 4), 'base64'), 'utf8')::jsonb;
    exception when others then return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', 'cursor'));
    end;
    if v_c->>'v' is distinct from '1' or v_c->>'m' not in ('full', 'delta') or (v_c->>'a') !~ '^\d+$' then
      return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', 'cursor')); end if;
    v_mode := v_c->>'m'; v_a := (v_c->>'a')::bigint; v_s := nullif(v_c->>'s', '')::bigint;
    v_e := array(select jsonb_array_elements_text(coalesce(v_c->'e', to_jsonb(v_all))));
  else
    v_mode := 'full'; v_a := 0; v_s := (select coalesce(max(seq), 0) from pipeline.zoho_sync_items);
    v_e := coalesce(nullif(p_entities, '{}'::text[]), v_all);
  end if;
  if not (v_e <@ v_all) or (v_mode = 'full' and v_s is null) then
    return jsonb_build_object('error', jsonb_build_object('code', 'INVALID_INPUT', 'detail', 'entities')); end if;
  v_max := greatest(security.pipeline_num_v1('zoho.sync_page_max', 200)::int, 1);
  v_unit := greatest(security.pipeline_num_v1('zoho.sync_item_unit_bytes', 3072), 1);
  v_size := least(greatest(coalesce(p_page_size, v_max), 1), v_max);
  -- 15 Oct 2026: a page is filled by build cost up to page_size (at least one item); has_more when rows are left
  select coalesce(jsonb_agg(to_jsonb(x) - 'cw' - 'rn' order by x.seq) filter (where x.rn = 1 or x.cw <= v_size), '[]'::jsonb), count(*) into v_rows, v_n from (
    -- CF-247 15 Oct 2026: a stored item counts by its size (one unit per setting bytes); one not yet stored by its build cost as before
    select y.*, sum(case when y.removed_at is not null then 1
                         when y.item is not null then greatest(ceil(octet_length(y.item::text)::numeric / v_unit), 1)::int
                         when y.entity = 'provider' then 16 else 1 end) over (order by y.seq) cw,  -- fixed: build cost relative to a course item, measured 14 Oct 2026
           row_number() over (order by y.seq) rn
      from (select i.entity, i.item_key, i.ref_id, i.seq, i.removed_at, i.item from pipeline.zoho_sync_items i
             where i.entity = any (v_e) and i.seq > v_a
               and (v_mode = 'delta' or (i.removed_at is null and i.seq <= v_s))
             order by i.seq limit v_size + 1) y) x;
  v_more := jsonb_array_length(v_rows) < v_n;
  v_last := (v_rows->-1->>'seq')::bigint;
  select coalesce(jsonb_agg(case when z.item is null then jsonb_build_object('entity', z.entity, 'id', z.item_key, 'seq', z.seq, 'change', 'remove')
                                 else jsonb_build_object('entity', z.entity, 'id', z.item_key, 'seq', z.seq, 'change', 'upsert', 'item', z.item) end order by z.seq), '[]'::jsonb)
    into v_items
    from (select r->>'entity' entity, r->>'item_key' item_key, (r->>'seq')::bigint seq,
                 case when r->>'removed_at' is null then coalesce(nullif(r->'item', 'null'::jsonb), security.zoho_sync_item_v1(r->>'entity', (r->>'ref_id')::uuid, r->>'item_key')) end item
            from jsonb_array_elements(v_rows) r) z;
  v_next := case when v_mode = 'full' and v_more then jsonb_build_object('v', 1, 'm', 'full', 'a', v_last, 's', v_s, 'e', to_jsonb(v_e))
                 when v_mode = 'full' then jsonb_build_object('v', 1, 'm', 'delta', 'a', v_s, 'e', to_jsonb(v_e))
                 else jsonb_build_object('v', 1, 'm', 'delta', 'a', coalesce(v_last, v_a), 'e', to_jsonb(v_e)) end;
  return jsonb_build_object(
    'api_version', 'zoho-v2', 'mode', v_mode, 'entities', to_jsonb(v_e), 'items', v_items, 'has_more', v_more,
    'full_load_complete', case when v_mode = 'full' then not v_more end,
    'next_cursor', rtrim(translate(replace(encode(convert_to(v_next::text, 'utf8'), 'base64'), E'\n', ''), '+/', '-_'), '='),
    'checked_through', (select case when bool_or(s.last_cycle_at is null) then null else min(s.last_cycle_at) end from pipeline.zoho_sync_scan s where s.entity = any (v_e)),
    'as_of', now());
end $function$;


-- 7 CSV export (Australia first, by setting): one entity a call, from the change stream's stored items, columns fixed
CREATE OR REPLACE FUNCTION public.zoho_v2_export(p_entity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare q text := '"'; v_head text; v_csv text; v_n bigint;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if coalesce(p_entity, '') not in ('provider', 'campus', 'contact', 'course') then raise exception 'INVALID_INPUT: entity must be provider, campus, contact or course' using errcode = '22023'; end if;
  if p_entity = 'provider' then
    v_head := 'provider_id,cricos_provider_code,name,legal_name,institution_type,country_code,state,city,postcode,website,phone,email,course_count,campus_count,contact_count,qs_rank,the_rank,updated_at';
    select count(*), string_agg(concat_ws(',', security.zoho_v2_csv_v1(i->>'provider_id'), security.zoho_v2_csv_v1(i->>'cricos_provider_code'), security.zoho_v2_csv_v1(i->>'name'),
             security.zoho_v2_csv_v1(i->>'legal_name'), security.zoho_v2_csv_v1(i->'institution_type'->>'name'), security.zoho_v2_csv_v1(i->>'country_code'), security.zoho_v2_csv_v1(i->>'subdivision_code'),
             security.zoho_v2_csv_v1(i->>'city'), security.zoho_v2_csv_v1(i->>'postcode'), security.zoho_v2_csv_v1(i->>'website'), security.zoho_v2_csv_v1(i->>'phone'), security.zoho_v2_csv_v1(i->>'email'),
             security.zoho_v2_csv_v1(i->>'course_count'), security.zoho_v2_csv_v1(i->>'campus_count'), security.zoho_v2_csv_v1(i->>'contact_count'),
             security.zoho_v2_csv_v1(i->'ranking_summary'->'qs_wur'->>'rank_display'), security.zoho_v2_csv_v1(i->'ranking_summary'->'the_wur'->>'rank_display'), security.zoho_v2_csv_v1(i->>'updated_at')), E'\n' order by i->>'name', k)
      into v_n, v_csv from (select z.item i, z.item_key k from pipeline.zoho_sync_items z where z.entity = 'provider' and z.removed_at is null and z.item is not null) x;
  elsif p_entity = 'campus' then
    v_head := 'campus_id,provider_id,cricos_provider_code,provider_name,name,address_line1,address_line2,city,state,postcode,country_code,latitude,longitude,metro_area,regional_category,course_count';
    select count(*), string_agg(concat_ws(',', security.zoho_v2_csv_v1(i->>'campus_id'), security.zoho_v2_csv_v1(i->>'provider_id'), security.zoho_v2_csv_v1(i->>'cricos_provider_code'),
             security.zoho_v2_csv_v1(i->>'provider_name'), security.zoho_v2_csv_v1(i->>'name'), security.zoho_v2_csv_v1(i->>'address_line1'), security.zoho_v2_csv_v1(i->>'address_line2'),
             security.zoho_v2_csv_v1(i->>'city'), security.zoho_v2_csv_v1(i->>'subdivision_code'), security.zoho_v2_csv_v1(i->>'postcode'), security.zoho_v2_csv_v1(i->>'country_code'),
             security.zoho_v2_csv_v1(i->>'latitude'), security.zoho_v2_csv_v1(i->>'longitude'), security.zoho_v2_csv_v1(i->>'metro_area'), security.zoho_v2_csv_v1(i->>'regional_category'),
             security.zoho_v2_csv_v1(i->>'course_count')), E'\n' order by i->>'provider_name', i->>'name', k)
      into v_n, v_csv from (select z.item i, z.item_key k from pipeline.zoho_sync_items z where z.entity = 'campus' and z.removed_at is null and z.item is not null) x;
  elsif p_entity = 'contact' then
    v_head := 'contact_id,provider_id,cricos_provider_code,provider_name,type,name,title,team,email,phone,source,source_url,checked_at';
    select count(*), string_agg(concat_ws(',', security.zoho_v2_csv_v1(i->>'contact_id'), security.zoho_v2_csv_v1(i->>'provider_id'), security.zoho_v2_csv_v1(i->>'cricos_provider_code'),
             security.zoho_v2_csv_v1(i->>'provider_name'), security.zoho_v2_csv_v1(i->>'type'), security.zoho_v2_csv_v1(i->>'name'), security.zoho_v2_csv_v1(i->>'title'), security.zoho_v2_csv_v1(i->>'team'),
             security.zoho_v2_csv_v1(i->>'email'), security.zoho_v2_csv_v1(i->>'phone'), security.zoho_v2_csv_v1(i->>'source'), security.zoho_v2_csv_v1(i->>'source_url'), security.zoho_v2_csv_v1(i->>'checked_at')), E'\n' order by i->>'provider_name', i->>'type', k)
      into v_n, v_csv from (select z.item i, z.item_key k from pipeline.zoho_sync_items z where z.entity = 'contact' and z.removed_at is null and z.item is not null) x;
  else
    v_head := 'course_id,cricos_course_code,title,provider_id,cricos_provider_code,provider_name,study_level,study_area,country_code,states,campus_cities,delivery_modes,duration_months,intake_months,ielts_overall,ielts_band,pte_overall,tuition_annual,tuition_currency,tuition_year,official_url,scholarship_count';
    select count(*), string_agg(concat_ws(',', security.zoho_v2_csv_v1(i->>'course_id'), security.zoho_v2_csv_v1(i->>'cricos_course_code'), security.zoho_v2_csv_v1(i->>'title'),
             security.zoho_v2_csv_v1(i->'provider'->>'provider_id'), security.zoho_v2_csv_v1(i->'provider'->>'cricos_provider_code'), security.zoho_v2_csv_v1(i->'provider'->>'name'),
             security.zoho_v2_csv_v1(i->'study_level'->>'name'), security.zoho_v2_csv_v1(i->'study_area'->>'name'), security.zoho_v2_csv_v1(i->>'country_code'),
             security.zoho_v2_csv_v1((select string_agg(x, '; ') from jsonb_array_elements_text(coalesce(i->'subdivision_codes', '[]'::jsonb)) x)),
             security.zoho_v2_csv_v1((select string_agg(distinct c->>'city', '; ') from jsonb_array_elements(coalesce(i->'campuses', '[]'::jsonb)) c)),
             security.zoho_v2_csv_v1((select string_agg(x, '; ') from jsonb_array_elements_text(coalesce(i->'delivery_modes', '[]'::jsonb)) x)),
             security.zoho_v2_csv_v1(i->>'duration_months'),
             security.zoho_v2_csv_v1((select string_agg(distinct coalesce(n->>'label', n->>'month'), '; ') from jsonb_array_elements(coalesce(i->'intakes', '[]'::jsonb)) n)),
             security.zoho_v2_csv_v1((select min(e->>'min_overall_score') from jsonb_array_elements(coalesce(i->'english_requirements', '[]'::jsonb)) e where e->>'test_code' = 'IELTS')),
             security.zoho_v2_csv_v1((select min(e->>'min_band_score') from jsonb_array_elements(coalesce(i->'english_requirements', '[]'::jsonb)) e where e->>'test_code' = 'IELTS')),
             security.zoho_v2_csv_v1((select min(e->>'min_overall_score') from jsonb_array_elements(coalesce(i->'english_requirements', '[]'::jsonb)) e where e->>'test_code' = 'PTE')),
             security.zoho_v2_csv_v1(i->'tuition'->>'annual_amount'), security.zoho_v2_csv_v1(i->'tuition'->>'currency'), security.zoho_v2_csv_v1(i->'tuition'->>'year'),
             security.zoho_v2_csv_v1(i->>'official_url'), security.zoho_v2_csv_v1(i->>'scholarship_count')), E'\n' order by i->'provider'->>'name', i->>'title', k)
      into v_n, v_csv from (select z.item i, z.item_key k from pipeline.zoho_sync_items z where z.entity = 'course' and z.removed_at is null and z.item is not null) x;
  end if;
  return jsonb_build_object('api_version', 'zoho-v2', 'entity', p_entity, 'rows', coalesce(v_n, 0),
    'countries', coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zoho.sync_countries'), '["AU"]'::jsonb),
    'complete', (select s.last_cycle_at is not null from pipeline.zoho_sync_scan s where s.entity = p_entity),
    'csv', v_head || E'\n' || coalesce(v_csv || E'\n', ''));
end $function$;

-- 8 Jobs, catalogue, register; access
revoke execute on function public.zoho_v2_auth(text), public.zoho_v2_rate(text, integer), public.zoho_v2_log(text, text, integer, integer, integer, integer, text, uuid),
  public.zoho_v2_reference(), public.zoho_v2_course_search(jsonb, integer, integer, text), public.zoho_v2_course(text), public.zoho_v2_courses(text[]),
  public.zoho_v2_providers(jsonb, integer, integer, text), public.zoho_v2_provider(text), public.zoho_v2_list(text, jsonb, integer, integer),
  public.zoho_v2_statistics(text, jsonb, integer, integer), public.zoho_v2_passthrough(text, jsonb, integer, integer, text, jsonb),
  public.zoho_v2_sync(text, boolean, text[], integer), public.zoho_v2_export(text) from public, anon, authenticated;
revoke execute on function security.api_usage_rollup_v1(), security.zoho_v2_provider_cricos_v1(uuid), security.zoho_v2_course_extra_v1(jsonb, uuid),
  security.zoho_v2_provider_item_v1(uuid), security.zoho_v2_campus_item_v1(uuid), security.zoho_v2_contact_item_v1(text), security.zoho_v2_csv_v1(text),
  security.zoho_sync_candidates_v1(text), security.zoho_sync_item_v1(text, uuid, text), security.zoho_sync_check_v1(integer) from public, anon, authenticated;
revoke execute on function public.admin_api_usage(integer) from public, anon;
grant execute on function public.admin_api_usage(integer) to authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('zoho-sync-check', 'Search and API', 42, 'Zoho sync: change check', 'Every minute: builds Zoho API v2 items (providers, campuses, contacts, courses of the countries in Zoho API settings) in a rolling pass and numbers each new, changed or removed item for the sync action and the CSV export.', 6, true),
 ('api-usage-rollup', 'Search and API', 43, 'API usage: daily summary', 'Every 15 minutes: sums the API v2 request log into calls per day, key and action (ok, errors, rate limited, times) and removes log rows older than the setting.', 6, false)
on conflict (jobname) do nothing;
select cron.schedule('zoho-sync-check', '* * * * *', 'select security.zoho_sync_check_v1(security.pipeline_num_v1(''batch.zoho_sync_check'', 1500)::int)');
select cron.schedule('api-usage-rollup', '4-59/15 * * * *', 'select security.api_usage_rollup_v1()');

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('edge_function', 'zoho-api-v2', 'Zoho API', 'Zoho API v2: its own URL and keys (Creator search, CRM sync)', 'active', '20261016020000'),
 ('table', 'private.api_keys', 'API', 'Keys for the versioned API URLs, one per consumer', 'active', '20261016020000'),
 ('table', 'pipeline.api_requests', 'API', 'One row per API v2 call (usage statistics)', 'active', '20261016020000'),
 ('table', 'pipeline.api_usage_daily', 'API', 'API calls per day, key and action', 'active', '20261016020000'),
 ('table', 'pipeline.zoho_sync_items', 'Zoho API', 'Zoho change stream items', 'active', '20261016020000'),
 ('table', 'pipeline.zoho_sync_scan', 'Zoho API', 'Zoho change check position', 'active', '20261016020000'),
 ('job', 'zoho-sync-check', 'Zoho API', 'Zoho change check', 'active', '20261016020000'),
 ('job', 'api-usage-rollup', 'API', 'API usage daily summary', 'active', '20261016020000'),
 ('screen', 'Integrations › API usage', 'API', 'Calls, errors and times per key and action', 'active', '20261016020000')
on conflict (kind, name) do update set purpose = excluded.purpose, status = 'active', introduced_in = excluded.introduced_in, updated_at = now();

do $post$
begin
  if (select count(*) from private.api_keys where platform = 'zoho' and api_version = 'v2' and enabled) <> 2 then raise exception 'zoho v2 post-check: keys'; end if;
  if (select count(*) from cron.job where jobname in ('zoho-sync-check', 'api-usage-rollup') and active) <> 2 then raise exception 'zoho v2 post-check: jobs'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and section = 'Zoho API') <> 9 then raise exception 'zoho v2 post-check: settings'; end if;
  if public.zoho_v2_course('082960F')->'item'->>'cricos_course_code' is distinct from '082960F' then raise exception 'zoho v2 post-check: course lookup by CRICOS code'; end if;
  if security.zoho_v2_csv_v1('a,"b"') <> '"a,""b"""' then raise exception 'zoho v2 post-check: csv quoting'; end if;
end $post$;
