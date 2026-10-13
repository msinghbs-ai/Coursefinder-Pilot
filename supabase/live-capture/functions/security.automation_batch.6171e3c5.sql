CREATE OR REPLACE FUNCTION security.automation_batch(p_command text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  -- v2.15.269: a job that reads its size from a setting shows that setting
  select coalesce((select (s.value #>> '{}')::int from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = substring(p_command from 'pipeline_num_v1\(''([^'']+)''')),
                  (select s.value::int from pipeline.scholarship_layer_settings s where s.key = substring(p_command from 'scholarship_setting\(''([^'']+)''')),
                  (substring(p_command from '"limit"\s*:\s*(\d+)'))::int, (substring(p_command from '\(\s*(\d+)\s*\)'))::int)
$function$
