CREATE OR REPLACE FUNCTION security.exit_awards_hourly_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u record; v jsonb := '[]'::jsonb;
begin
  for u in select a.provider_id from pipeline.uni_adapters a where a.enabled and a.admit and 'exit_awards' = any (a.admit_fields) loop
    v := v || jsonb_build_array(jsonb_build_object('provider_id', u.provider_id, 'found', security.exit_awards_detect_v2(u.provider_id), 'apply', security.exit_awards_apply_v2(u.provider_id)));
  end loop;
  return v;
end $function$
