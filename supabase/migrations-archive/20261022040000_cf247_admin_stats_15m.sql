-- CF-247 (22 Oct 2026). Platform Admin 21:57: "Give me stat's and toolset usuage every 15 minutes". Scheduled tasks can report at most
-- hourly, so the 15-minute snapshots (job stats-15m) are also shown on Platform health › Work queues, refreshed every 15 minutes.
-- public.admin_stats_15m: the latest snapshot and the fields held per country at each snapshot of the last stats.trend_hours hours.
-- Replaces: nothing
-- Retires: nothing
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'stats.trend_hours', '15-minute stats: trend shown', 'Platform health › Work queues shows the 15-minute snapshots of this many hours.', 'number', to_jsonb(24), 1, 168, 'hours', 773, 'CF-247 22 Oct 2026 (15-minute stats)', 'Platform upkeep', 'public.admin_stats_15m')
on conflict do nothing;

create or replace function public.admin_stats_15m()
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'latest', security.stats_15m_report_v1(),
    'trend', (select coalesce(jsonb_agg(jsonb_build_object('at', s.at, 'countries', (select jsonb_object_agg(c.key, c.value->'now') from jsonb_each(s.data->'countries') c)) order by s.at), '[]'::jsonb)
                from pipeline.stats_15m s where s.at > now() - make_interval(hours => security.pipeline_num_v1('stats.trend_hours', 24)::int)));
end $function$;
revoke all on function public.admin_stats_15m() from public, anon;
grant execute on function public.admin_stats_15m() to authenticated;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'public.admin_stats_15m', 'Platform', 'Work queues screen: 15-minute stats', 'active', '{}', '20261022040000')
on conflict (kind, name) do nothing;
