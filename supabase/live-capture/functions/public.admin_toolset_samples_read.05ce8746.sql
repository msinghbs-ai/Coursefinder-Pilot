CREATE OR REPLACE FUNCTION public.admin_toolset_samples_read(p_run_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'toolset', r.toolset_key, 'purpose', r.purpose, 'countries', r.countries, 'status', r.status, 'status_note', r.status_note,
                'credits_used', r.credits_used, 'reason', r.reason, 'created_at', r.created_at, 'finished_at', r.finished_at,
                'cases', (select count(*) from pipeline.toolset_sample_items i where i.run_id = r.id),
                'done', (select count(*) from pipeline.toolset_sample_items i where i.run_id = r.id and i.status = 'done'),
                'usd_per_1k_credits', r.settings->'usd_per_1k_credits', 'plan_name', r.settings->'plan_name') order by r.created_at desc), '[]'::jsonb)
             from (select * from pipeline.toolset_sample_runs order by created_at desc limit 30) r),
    'summary', (select coalesce(jsonb_agg(jsonb_build_object('toolset', z.toolset_key, 'purpose', z.purpose, 'country', z.country, 'outcome', z.outcome, 'n', z.n,
                    'credits', z.credits, 'avg_latency_ms', z.lat) order by z.toolset_key, z.purpose, z.country, z.n desc), '[]'::jsonb)
                from (select r.toolset_key, r.purpose, i.country, i.outcome, count(*) n, sum(i.credits) credits, round(avg(i.latency_ms)) lat
                      from pipeline.toolset_sample_items i join pipeline.toolset_sample_runs r on r.id = i.run_id
                      where i.status = 'done' and (p_run_id is null or r.id = p_run_id) group by 1, 2, 3, 4) z),
    'backlog', (select coalesce(jsonb_agg(jsonb_build_object('toolset', t.toolset, 'purpose', t.purpose, 'country', c.cc, 'n', (select count(*) from security.toolset_backlog(t.purpose, c.cc)))), '[]'::jsonb)
                from (values ('serper', 'find_course_page'), ('serper', 'find_provider_site'), ('scrapingbee', 'render_page')) t(toolset, purpose)
                cross join lateral (select jsonb_array_elements_text(coalesce(security.toolset_setting(t.toolset, 'sample_countries'), '[]'::jsonb)) cc) c),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('country', i.country, 'input', i.input, 'outcome', i.outcome, 'http_status', i.http_status, 'credits', i.credits,
                 'latency_ms', i.latency_ms, 'result', i.result, 'done_at', i.done_at) order by i.country, i.outcome, i.done_at), '[]'::jsonb)
              from pipeline.toolset_sample_items i where p_run_id is not null and i.run_id = p_run_id and i.status = 'done'));
end $function$
