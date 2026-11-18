CREATE OR REPLACE FUNCTION security.course_description_machine_run_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_a jsonb; v_b jsonb; v_h jsonb; v_s jsonb; v_p jsonb;
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  -- one failure never stops the run: each part reports its own error
  -- cdesc-source-grounded-v1 (CF-247 F-CDESC, 12 Nov 2026): waiting descriptions an earlier prompt made that the machine declined for good are superseded and read again
  begin v_p := security.cdesc_prompt_supersede_v1(); exception when others then v_p := jsonb_build_object('error', sqlerrm); end;
  begin v_h := security.cdesc_recheck_held_v1(); exception when others then v_h := jsonb_build_object('error', sqlerrm); end;
  begin v_s := security.cdesc_subset_recover_v1(); exception when others then v_s := jsonb_build_object('error', sqlerrm); end;
  begin v_a := security.course_description_machine_settle_v1(); exception when others then v_a := jsonb_build_object('error', sqlerrm); end;
  begin v_b := security.course_description_machine_consumer_recheck_v1(); exception when others then v_b := jsonb_build_object('error', sqlerrm); end;
  return jsonb_build_object('on', true, 'prompt', v_p, 'held', v_h, 'subset', v_s, 'settle', v_a, 'consumer', v_b);
end $function$
