-- CF-CHG-20260902-080 security hardening:
-- public browser RPCs remain SECURITY INVOKER; privileged implementation stays in private security schema.

do $$
declare v_manage text;v_export text;
begin
 select pg_get_functiondef('public.provider_contact_manage(text,jsonb)'::regprocedure) into v_manage;
 v_manage:=replace(v_manage,'CREATE OR REPLACE FUNCTION public.provider_contact_manage','CREATE OR REPLACE FUNCTION security.provider_contact_manage_impl');
 execute v_manage;

 select pg_get_functiondef('public.provider_contact_export_audit(jsonb)'::regprocedure) into v_export;
 v_export:=replace(v_export,'CREATE OR REPLACE FUNCTION public.provider_contact_export_audit','CREATE OR REPLACE FUNCTION security.provider_contact_export_audit_impl');
 execute v_export;
end $$;

revoke all on function security.provider_contact_manage_impl(text,jsonb) from public,anon,authenticated;
grant execute on function security.provider_contact_manage_impl(text,jsonb) to authenticated,service_role;

revoke all on function security.provider_contact_export_audit_impl(jsonb) from public,anon,authenticated;
grant execute on function security.provider_contact_export_audit_impl(jsonb) to authenticated,service_role;

create or replace function public.provider_contact_manage(p_action text,p_payload jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path to 'pg_catalog','security'
as $$
 select security.provider_contact_manage_impl(p_action,p_payload)
$$;

create or replace function public.provider_contact_export_audit(p_payload jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path to 'pg_catalog','security'
as $$
 select security.provider_contact_export_audit_impl(p_payload)
$$;

revoke all on function public.provider_contact_manage(text,jsonb) from public,anon;
grant execute on function public.provider_contact_manage(text,jsonb) to authenticated,service_role;
revoke all on function public.provider_contact_export_audit(jsonb) from public,anon;
grant execute on function public.provider_contact_export_audit(jsonb) to authenticated,service_role;

create index if not exists provider_contact_mappings_provider_idx on pipeline.provider_contact_provider_mappings(provider_id);
create index if not exists provider_contact_import_batches_evidence_idx on pipeline.provider_contact_import_batches(evidence_artifact_id);
create index if not exists provider_contact_import_rows_provider_idx on pipeline.provider_contact_import_rows(mapped_provider_id);
create index if not exists provider_contact_import_rows_contact_idx on pipeline.provider_contact_import_rows(matched_contact_id);
create index if not exists provider_contact_versions_evidence_idx on pipeline.provider_contact_versions(evidence_id);
create index if not exists provider_contact_versions_import_batch_idx on pipeline.provider_contact_versions(import_batch_id);
create index if not exists provider_contact_versions_import_row_idx on pipeline.provider_contact_versions(import_row_id);
create index if not exists provider_contact_versions_superseded_idx on pipeline.provider_contact_versions(superseded_by);
create index if not exists provider_contact_audit_before_version_idx on pipeline.provider_contact_audit_events(before_version_id);
create index if not exists provider_contact_audit_after_version_idx on pipeline.provider_contact_audit_events(after_version_id);
