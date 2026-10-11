CREATE OR REPLACE FUNCTION pipeline.svc_pilot_invoke_scholarship_edge(p_body jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_nonce uuid:=gen_random_uuid();v_request_id bigint;v_base text;
begin
 insert into pipeline.pilot_edge_nonces(id,function_name,expires_at) values(v_nonce,'scholarships-au-etl',now()+interval '5 minutes');
 v_base:=public.coursefinder_runtime_edge_base_url();
 if v_base is null then raise exception 'runtime Edge base URL missing';end if;
 select net.http_post(url:=rtrim(v_base,'/')||'/scholarships-au-etl',headers:=jsonb_build_object('content-type','application/json','x-cf-run-nonce',v_nonce::text),body:=coalesce(p_body,'{}'::jsonb),timeout_milliseconds:=30000) into v_request_id;
 return jsonb_build_object('request_id',v_request_id,'nonce',v_nonce);
end $function$
