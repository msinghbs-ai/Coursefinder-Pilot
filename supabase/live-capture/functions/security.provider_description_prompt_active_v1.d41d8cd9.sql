CREATE OR REPLACE FUNCTION security.provider_description_prompt_active_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CF-247 F-PDESC (20261112010000): the active prompt while pdesc.prompt_on is 1; null means the worker's built-in prompt v2
  select case when security.pipeline_num_v1('pdesc.prompt_on', 0) >= 1 then
    (select jsonb_build_object('version', 'provider-description-p' || p.version, 'system', p.system_prompt) from pipeline.provider_description_prompts p where p.status = 'active')
  end
$function$
