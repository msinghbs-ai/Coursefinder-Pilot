CREATE OR REPLACE FUNCTION security.scholarship_task_fire_v1(p_steps text[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_step text; v_mode text; v_body jsonb; v_sent int := 0;
begin
  foreach v_step in array coalesce(p_steps, '{}') loop
    v_mode := case when v_step in ('discover', 'candidates') then 'scholarship_discover' else 'scholarship_read' end;
    v_body := case v_step
      when 'discover' then jsonb_build_object('mode', v_mode, 'phase', 'discover', 'limit', 6)
      when 'candidates' then jsonb_build_object('mode', v_mode, 'phase', 'candidates', 'read_limit', 30)
      else jsonb_build_object('mode', v_mode, 'limit', 40) end;
    if not exists (select 1 from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = v_mode and l.created_at > now() - interval '45 seconds'
                    and not exists (select 1 from net._http_response r where r.id = l.request_id)) then
      perform pipeline.svc_pilot_submit_nonce('coverage-sweep', v_body);
      v_sent := v_sent + 1;
    end if;
  end loop;
  return v_sent;
end $function$
