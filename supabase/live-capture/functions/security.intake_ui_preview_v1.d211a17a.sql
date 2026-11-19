CREATE OR REPLACE FUNCTION security.intake_ui_preview_v1(p_scope text, p_size integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s jsonb; body jsonb; signature text; expires timestamptz;
begin
 s:=security.intake_ui_selection_v1(p_scope,p_size);
 expires:=now()+make_interval(secs=>security.pipeline_num_v1('run_now.preview_seconds',600)::int);
 body:=jsonb_build_object('scope',p_scope,'size',p_size,'requester',auth.uid(),'expires_at',expires,'fingerprint',encode(extensions.digest(s::text,'sha256'),'hex'));
 select encode(extensions.hmac(body::text,secret,'sha256'),'hex') into signature from pipeline.intake_ui_signing_key;
 return s||jsonb_build_object('as_at',now(),'expires_at',expires,'token',jsonb_build_object('body',body,'signature',signature)::text);
end $function$
