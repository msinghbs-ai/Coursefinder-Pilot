CREATE OR REPLACE FUNCTION security.provider_policy_refresh_plans_v1(p_limit integer DEFAULT 12)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare r record; v_n int := 0;
begin
  for r in select id from pipeline.provider_policy_proposals
            where kind = 'english_policy' and status in ('proposed', 'approved') and (plan_at is null or plan_at < now() - interval '30 minutes')
            order by plan_at nulls first, created_at limit greatest(1, least(coalesce(p_limit, 12), 100)) loop
    perform security.provider_policy_refresh_one_v1(r.id); v_n := v_n + 1;
  end loop;
  return jsonb_build_object('refreshed', v_n);
end $function$
