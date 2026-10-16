CREATE OR REPLACE FUNCTION security.platform_health_state_v1(p_detail boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
  select jsonb_build_object(
    'generated_at', now(),
    'overall', coalesce((select case min(case severity when 'critical' then 1 when 'warning' then 2 else 3 end) when 1 then 'critical' when 2 then 'warning' else 'ok' end
                           from pipeline.platform_issues where resolved_at is null and acknowledged_at is null),'ok'),
    'counts', (select jsonb_build_object('critical',count(*) filter (where severity='critical'),'warning',count(*) filter (where severity='warning'),'info',count(*) filter (where severity='info'))
                 from pipeline.platform_issues where resolved_at is null),
    'issues', coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'check_key',i.check_key,'severity',i.severity,'area',i.area,'title',i.title,
                           'detail',case when p_detail then i.detail else '{}'::jsonb end,'first_seen',i.first_seen,'last_seen',i.last_seen,
                           'occurrences',i.occurrences,'acknowledged_at',i.acknowledged_at) order by i.rk, i.last_seen desc)
                          from (select p.*, case p.severity when 'critical' then 1 when 'warning' then 2 else 3 end rk from pipeline.platform_issues p
                                 where p.resolved_at is null order by rk, p.last_seen desc limit 200) i),'[]'::jsonb),
    'checks', coalesce((select jsonb_agg(jsonb_build_object('key',c.key,'area',c.area,'label',c.label,'status',c.status,
                           'detail',case when p_detail then c.detail else '{}'::jsonb end,'checked_at',c.checked_at) order by c.sort_order)
                          from pipeline.platform_health_checks c),'[]'::jsonb),
    'history', (select jsonb_agg(jsonb_build_object('day',to_char(g.d,'YYYY-MM-DD'),
                   'critical',(select count(*) from pipeline.platform_issues i where i.severity='critical' and i.first_seen<(g.d at time zone 'UTC')+interval '1 day' and coalesce(i.resolved_at,'infinity'::timestamptz)>=(g.d at time zone 'UTC')),
                   'warning',(select count(*) from pipeline.platform_issues i where i.severity='warning' and i.first_seen<(g.d at time zone 'UTC')+interval '1 day' and coalesce(i.resolved_at,'infinity'::timestamptz)>=(g.d at time zone 'UTC'))) order by g.d)
                  from generate_series(((now() at time zone 'UTC')::date-13)::timestamp,((now() at time zone 'UTC')::date)::timestamp,interval '1 day') g(d)))
$function$
