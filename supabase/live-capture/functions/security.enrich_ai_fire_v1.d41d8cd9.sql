CREATE OR REPLACE FUNCTION security.enrich_ai_fire_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_open int; v_max int := security.pipeline_num_v1('enrich.ai_calls_at_once', 2)::int; v_due int; v_sent int := 0;
begin
  if not security.ai_use_allowed_v1('enrich_fields') then return 0; end if;
  select count(*) into v_due from pipeline.field_enrich_items where state = 'ai' or (state = 'leased' and leased_until < now());
  if v_due = 0 then return 0; end if;
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'enrich_ai' and l.created_at > now() - make_interval(mins => 3)
     and not exists (select 1 from net._http_response r where r.id = l.request_id);
  while v_open + v_sent < v_max and v_sent * 10 < v_due loop
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'enrich_ai'));
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end $function$
