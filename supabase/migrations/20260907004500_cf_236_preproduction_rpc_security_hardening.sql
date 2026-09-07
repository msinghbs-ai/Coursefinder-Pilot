-- CF-CHG-20260907-236 — Remaining pre-production RPC boundary hardening
-- Preserve existing Scholarship/statistics authority semantics while removing exposed
-- SECURITY DEFINER functions and fixing mutable search_path helper warnings.

create schema if not exists admin_api;
revoke all on schema admin_api from public, anon;
grant usage on schema admin_api to authenticated, service_role;

alter function public.scholarship_ai_run_status(uuid) set schema admin_api;
alter function public.scholarship_ai_settings_write(text,jsonb) set schema admin_api;
alter function public.scholarship_runtime_settings_write(jsonb) set schema admin_api;
alter function public.statistics_dataset_registry_read() set schema admin_api;
alter function public.statistics_dataset_registry_write(jsonb) set schema admin_api;

revoke all on function admin_api.scholarship_ai_run_status(uuid) from public,anon;
revoke all on function admin_api.scholarship_ai_settings_write(text,jsonb) from public,anon;
revoke all on function admin_api.scholarship_runtime_settings_write(jsonb) from public,anon;
revoke all on function admin_api.statistics_dataset_registry_read() from public,anon;
revoke all on function admin_api.statistics_dataset_registry_write(jsonb) from public,anon;

grant execute on function admin_api.scholarship_ai_run_status(uuid) to authenticated,service_role;
grant execute on function admin_api.scholarship_ai_settings_write(text,jsonb) to authenticated,service_role;
grant execute on function admin_api.scholarship_runtime_settings_write(jsonb) to authenticated,service_role;
grant execute on function admin_api.statistics_dataset_registry_read() to authenticated,service_role;
grant execute on function admin_api.statistics_dataset_registry_write(jsonb) to authenticated,service_role;

create or replace function public.scholarship_ai_run_status(p_run_id uuid)
returns jsonb language sql stable security invoker set search_path='pg_catalog','admin_api' as $$
 select admin_api.scholarship_ai_run_status(p_run_id)
$$;

create or replace function public.scholarship_ai_settings_write(p_country_code text,p_patch jsonb)
returns jsonb language sql security invoker set search_path='pg_catalog','admin_api' as $$
 select admin_api.scholarship_ai_settings_write(p_country_code,p_patch)
$$;

create or replace function public.scholarship_runtime_settings_write(p_patch jsonb)
returns jsonb language sql security invoker set search_path='pg_catalog','admin_api' as $$
 select admin_api.scholarship_runtime_settings_write(p_patch)
$$;

create or replace function public.statistics_dataset_registry_read()
returns jsonb language sql stable security invoker set search_path='pg_catalog','admin_api' as $$
 select admin_api.statistics_dataset_registry_read()
$$;

create or replace function public.statistics_dataset_registry_write(p_dataset jsonb)
returns jsonb language sql security invoker set search_path='pg_catalog','admin_api' as $$
 select admin_api.statistics_dataset_registry_write(p_dataset)
$$;

revoke all on function public.scholarship_ai_run_status(uuid) from public,anon;
revoke all on function public.scholarship_ai_settings_write(text,jsonb) from public,anon;
revoke all on function public.scholarship_runtime_settings_write(jsonb) from public,anon;
revoke all on function public.statistics_dataset_registry_read() from public,anon;
revoke all on function public.statistics_dataset_registry_write(jsonb) from public,anon;

grant execute on function public.scholarship_ai_run_status(uuid) to authenticated,service_role;
grant execute on function public.scholarship_ai_settings_write(text,jsonb) to authenticated,service_role;
grant execute on function public.scholarship_runtime_settings_write(jsonb) to authenticated,service_role;
grant execute on function public.statistics_dataset_registry_read() to authenticated,service_role;
grant execute on function public.statistics_dataset_registry_write(jsonb) to authenticated,service_role;

alter function scholarship.normalise_first_party_url(text) set search_path='pg_catalog';
alter function scholarship.normalise_title(text) set search_path='pg_catalog';
