CREATE OR REPLACE FUNCTION security.provider_policy_refresh_one_v1(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  select coalesce(jsonb_object_agg(o, n), '{}'::jsonb) into v from (select r.outcome o, count(*) n from security.provider_english_plan_v1(p_id) r group by 1) s;
  update pipeline.provider_policy_proposals set plan_summary = v, plan_at = now() where id = p_id;
  return v;
end $function$
