CREATE OR REPLACE FUNCTION security.central_ai_fire_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_open int; v_max int; v_due int; v_sent int := 0;
begin
  -- v2.15.258: in Stop at limits, not past the daily guard or below the credit floor
  if not security.ai_use_allowed_v1('central_ai') then return 0; end if;
  select calls_at_once into v_max from pipeline.central_ai_settings where id = 1 and enabled;
  select count(*) into v_due from pipeline.central_ai_queue q where (q.state = 'queued' or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3;
  if v_due = 0 or coalesce(v_max, 0) = 0 then return 0; end if;
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'central_ai' and l.created_at > now() - interval '3 minutes'
     and not exists (select 1 from net._http_response r where r.id = l.request_id);
  while v_open + v_sent < v_max and v_sent * 6 < v_due loop
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'central_ai', 'limit', 6));
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end $function$
