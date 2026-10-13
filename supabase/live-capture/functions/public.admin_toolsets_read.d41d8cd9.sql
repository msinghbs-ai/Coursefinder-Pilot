CREATE OR REPLACE FUNCTION public.admin_toolsets_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'toolsets', (select coalesce(jsonb_agg(jsonb_build_object('key', t.key, 'label', t.label, 'kind', t.kind, 'layers', t.layers, 'enforcement', t.enforcement, 'help', t.help,
        'updated_at', t.updated_at, 'reason', t.reason,
        'key_saved', (select p.vault_secret_id is not null from pipeline.layer2_acquisition_providers p where p.provider_key = t.provider_key),
        'switched_on', (select p.enabled from pipeline.layer2_acquisition_providers p where p.provider_key = t.provider_key),
        'plan', case when exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = t.key and s.key = 'plan_credits') then security.toolset_plan_status(t.key) end,
        'settings', (select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'help', s.help, 'kind', s.kind, 'value', s.value, 'min', s.min_value, 'max', s.max_value,
                        'unit', s.unit, 'section', s.section, 'updated_at', s.updated_at, 'reason', s.reason) order by s.sort, s.key), '[]'::jsonb)
                     from pipeline.platform_toolset_settings s where s.toolset_key = t.key)) order by t.sort), '[]'::jsonb)
      from pipeline.platform_toolsets t),
    'openrouter', jsonb_build_object(
      'balance', (select jsonb_build_object('remaining_usd', o.remaining_usd, 'observed_at', o.observed_at, 'total_credits', o.payload->'total_credits', 'total_usage', o.payload->'total_usage')
                  from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1),
      -- v2.15.258 (bug 12/10-01): the AI uses that run now, with their daily guards and the credit floor (Layer 3 retired)
      'credit_floor_usd', (security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric,
      'uses', (select coalesce(jsonb_agg(jsonb_build_object('use', g.use, 'label', g.label, 'spent_today', g.spent, 'guard', g.guard, 'calls', g.calls,
                    'allowed', security.ai_use_allowed_v1(g.use))), '[]'::jsonb) from security.ai_spend_today_v1() g),
      'spend_by_day', (select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'usd', d.usd, 'calls', d.calls) order by d.day), '[]'::jsonb)
                       from (select r.day, round(sum(r.usd), 4) usd, sum(r.calls) calls from (
                               select (x.at at time zone 'UTC')::date as day, sum(x.cost_usd) usd, count(*) calls from pipeline.scholarship_ai_extractions x where x.at > now() - interval '14 days' group by 1
                               union all select (x.created_at at time zone 'UTC')::date, sum(x.cost_usd), count(*) from pipeline.uni_adapter_drafts x where x.created_at > now() - interval '14 days' and coalesce(x.cost_usd, 0) > 0 group by 1
                               union all select (x.created_at at time zone 'UTC')::date, sum(x.cost_usd), count(*) from pipeline.central_ai_queue x where x.created_at > now() - interval '14 days' and coalesce(x.cost_usd, 0) > 0 group by 1
                               union all select (coalesce(x.decided_at, x.created_at) at time zone 'UTC')::date, sum(x.cost_usd), count(*) from pipeline.coverage_ai_match x where x.created_at > now() - interval '14 days' and coalesce(x.cost_usd, 0) > 0 group by 1) r
                             group by 1) d)),
    'job_layers', (select coalesce(jsonb_object_agg(l.jobname, l.layer), '{}'::jsonb) from pipeline.platform_job_layers l));
end $function$
