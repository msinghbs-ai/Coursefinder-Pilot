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
    'days', v_days,
    'versions', security.api_usage_versions_v1());  -- s935: every consumer API version and key, live
end $function$
