drop function if exists public.svc_layer1_runtime_uat_grant_admin(uuid);
drop function if exists public.svc_layer1_runtime_uat_revoke_admin(uuid);
drop function if exists public.svc_layer1_runtime_uat_stats();
drop function if exists public.svc_layer1_runtime_uat_token();
drop table if exists pipeline.layer1_runtime_uat_control;
drop extension if exists pg_net;
