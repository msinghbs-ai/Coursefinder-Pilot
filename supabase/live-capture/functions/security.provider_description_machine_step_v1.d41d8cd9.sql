CREATE OR REPLACE FUNCTION security.provider_description_machine_step_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_a jsonb; v_b jsonb;
begin
  -- one failure never stops the reader: each part reports its own error
  begin v_a := security.provider_description_machine_settle_pending_v1(); exception when others then v_a := jsonb_build_object('error', sqlerrm); end;
  begin v_b := security.provider_description_registry_tier_v1(); exception when others then v_b := jsonb_build_object('error', sqlerrm); end;
  return jsonb_build_object('settle', v_a, 'registry', v_b);
end $function$
