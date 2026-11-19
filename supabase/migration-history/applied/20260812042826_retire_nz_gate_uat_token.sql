drop function if exists public.svc_layer1_validate_nz_gate_uat_token(uuid,text); delete from pipeline.jobs where payload->>'mode'='nz_gate_uat_token';
