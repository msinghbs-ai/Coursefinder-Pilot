CREATE OR REPLACE FUNCTION security.scholarship_ai_fire_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_open int; v_max int; v_due int; v_sent int := 0;
begin
  select calls_at_once into v_max from pipeline.scholarship_ai_extract_settings where id = 1;
  select count(*) into v_due from pipeline.scholarship_ai_queue q where (q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now());
  if v_due = 0 then return 0; end if;
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'scholarship_ai' and l.created_at > now() - interval '3 minutes'
     and not exists (select 1 from net._http_response r where r.id = l.request_id);
  while v_open + v_sent < coalesce(v_max, 3) and v_sent * 8 < v_due loop
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'scholarship_ai'));
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end $function$
