CREATE OR REPLACE FUNCTION public.admin_key_dates_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 2 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_edit', v_rank >= 3,
    'items', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'country', d.country_code, 'event_type', d.event_type, 'title', d.title,
                'source_url', d.source_url, 'precision', d.date_precision, 'starts_on', coalesce(d.starts_on, (d.starts_at at time zone coalesce(d.timezone, 'Australia/Melbourne'))::date),
                'ends_on', coalesce(d.ends_on, (d.ends_at at time zone coalesce(d.timezone, 'Australia/Melbourne'))::date), 'wording', d.source_wording,
                'warning_days', extract(day from d.warning_window)::int, 'scope', d.scope_type, 'refresh_layer', d.refresh_layer, 'status', d.status, 'updated_at', d.updated_at)
              order by d.status <> 'active', coalesce(d.starts_on, d.starts_at::date) nulls last, d.title), '[]'::jsonb) from pipeline.important_dates d),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.created_at, 'action', e.action, 'target', e.target, 'by', u.email) order by e.created_at desc), '[]'::jsonb)
               from (select * from pipeline.admin_control_events where area = 'key_dates' order by created_at desc limit 15) e left join auth.users u on u.id = e.actor));
end $function$
