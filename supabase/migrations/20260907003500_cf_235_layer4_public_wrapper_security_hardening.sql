-- CF-CHG-20260907-235 — Layer 4 public RPC security-boundary hardening
-- Preserve the accepted CF-205/206 semantics while moving privileged implementations
-- out of the exposed public schema. Public RPCs remain same-signature SECURITY INVOKER wrappers.

alter function public.layer4_mass_operations_history(integer) set schema l4_api;
alter function public.layer4_mass_summary() set schema l4_api;
alter function public.layer4_quality_diagnostics() set schema l4_api;
alter function public.layer4_quality_finding_resolve(uuid,text,text) set schema l4_api;
alter function public.layer4_quality_finding_upsert(text,text,text,text,text,jsonb) set schema l4_api;
alter function public.layer4_quality_findings_read(text,integer) set schema l4_api;
alter function public.layer4_review_bulk_decide(text,text,text,text,text,text,integer) set schema l4_api;
alter function public.layer4_review_groups(integer) set schema l4_api;
alter function public.layer4_scholarship_scope_bulk_decide(uuid,text,text,text,text) set schema l4_api;
alter function public.layer4_scholarship_scope_groups(integer) set schema l4_api;
alter function public.layer4_scholarship_scope_preview(uuid,text) set schema l4_api;
alter function public.layer4_scope_rule_apply(uuid,integer) set schema l4_api;
alter function public.layer4_scope_rule_save(uuid,text,text,text,text) set schema l4_api;
alter function public.layer4_scope_rule_set_state(uuid,boolean,text) set schema l4_api;
alter function public.layer4_scope_rules_read(integer) set schema l4_api;

revoke all on function l4_api.layer4_mass_operations_history(integer) from public,anon;
revoke all on function l4_api.layer4_mass_summary() from public,anon;
revoke all on function l4_api.layer4_quality_diagnostics() from public,anon;
revoke all on function l4_api.layer4_quality_finding_resolve(uuid,text,text) from public,anon;
revoke all on function l4_api.layer4_quality_finding_upsert(text,text,text,text,text,jsonb) from public,anon;
revoke all on function l4_api.layer4_quality_findings_read(text,integer) from public,anon;
revoke all on function l4_api.layer4_review_bulk_decide(text,text,text,text,text,text,integer) from public,anon;
revoke all on function l4_api.layer4_review_groups(integer) from public,anon;
revoke all on function l4_api.layer4_scholarship_scope_bulk_decide(uuid,text,text,text,text) from public,anon;
revoke all on function l4_api.layer4_scholarship_scope_groups(integer) from public,anon;
revoke all on function l4_api.layer4_scholarship_scope_preview(uuid,text) from public,anon;
revoke all on function l4_api.layer4_scope_rule_apply(uuid,integer) from public,anon;
revoke all on function l4_api.layer4_scope_rule_save(uuid,text,text,text,text) from public,anon;
revoke all on function l4_api.layer4_scope_rule_set_state(uuid,boolean,text) from public,anon;
revoke all on function l4_api.layer4_scope_rules_read(integer) from public,anon;

grant execute on function l4_api.layer4_mass_operations_history(integer) to authenticated,service_role;
grant execute on function l4_api.layer4_mass_summary() to authenticated,service_role;
grant execute on function l4_api.layer4_quality_diagnostics() to authenticated,service_role;
grant execute on function l4_api.layer4_quality_finding_resolve(uuid,text,text) to authenticated,service_role;
grant execute on function l4_api.layer4_quality_finding_upsert(text,text,text,text,text,jsonb) to authenticated,service_role;
grant execute on function l4_api.layer4_quality_findings_read(text,integer) to authenticated,service_role;
grant execute on function l4_api.layer4_review_bulk_decide(text,text,text,text,text,text,integer) to authenticated,service_role;
grant execute on function l4_api.layer4_review_groups(integer) to authenticated,service_role;
grant execute on function l4_api.layer4_scholarship_scope_bulk_decide(uuid,text,text,text,text) to authenticated,service_role;
grant execute on function l4_api.layer4_scholarship_scope_groups(integer) to authenticated,service_role;
grant execute on function l4_api.layer4_scholarship_scope_preview(uuid,text) to authenticated,service_role;
grant execute on function l4_api.layer4_scope_rule_apply(uuid,integer) to authenticated,service_role;
grant execute on function l4_api.layer4_scope_rule_save(uuid,text,text,text,text) to authenticated,service_role;
grant execute on function l4_api.layer4_scope_rule_set_state(uuid,boolean,text) to authenticated,service_role;
grant execute on function l4_api.layer4_scope_rules_read(integer) to authenticated,service_role;

create or replace function public.layer4_mass_operations_history(p_limit integer default 50)
returns jsonb language sql stable security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.layer4_mass_operations_history(p_limit)$$;
create or replace function public.layer4_mass_summary()
returns jsonb language sql stable security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.layer4_mass_summary()$$;
create or replace function public.layer4_quality_diagnostics()
returns jsonb language sql stable security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.layer4_quality_diagnostics()$$;
create or replace function public.layer4_quality_finding_resolve(p_finding_id uuid,p_status text,p_note text)
returns jsonb language sql security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.layer4_quality_finding_resolve(p_finding_id,p_status,p_note)$$;
create or replace function public.layer4_quality_finding_upsert(p_finding_type text,p_domain text,p_title text,p_detail text,p_severity text,p_group_key jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.layer4_quality_finding_upsert(p_finding_type,p_domain,p_title,p_detail,p_severity,p_group_key)$$;
create or replace function public.layer4_quality_findings_read(p_status text default 'open',p_limit integer default 100)
returns jsonb language sql stable security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.layer4_quality_findings_read(p_status,p_limit)$$;
create or replace function public.layer4_review_bulk_decide(p_entity_type text,p_field_code text,p_escalation_reason text,p_action text,p_reason text,p_confirmation text,p_limit integer default 500)
returns jsonb language sql security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.layer4_review_bulk_decide(p_entity_type,p_field_code,p_escalation_reason,p_action,p_reason,p_confirmation,p_limit)$$;
create or replace function public.layer4_review_groups(p_limit integer default 100)
returns jsonb language sql stable security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.layer4_review_groups(p_limit)$$;
create or replace function public.layer4_scholarship_scope_bulk_decide(p_scholarship_id uuid,p_candidate_reason text,p_action text,p_reason text,p_confirmation text)
returns jsonb language sql security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.layer4_scholarship_scope_bulk_decide(p_scholarship_id,p_candidate_reason,p_action,p_reason,p_confirmation)$$;
create or replace function public.layer4_scholarship_scope_groups(p_limit integer default 100)
returns jsonb language sql stable security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.layer4_scholarship_scope_groups(p_limit)$$;
create or replace function public.layer4_scholarship_scope_preview(p_scholarship_id uuid,p_candidate_reason text)
returns jsonb language sql stable security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.layer4_scholarship_scope_preview(p_scholarship_id,p_candidate_reason)$$;
create or replace function public.layer4_scope_rule_apply(p_rule_id uuid,p_limit integer default 1000)
returns jsonb language sql security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.layer4_scope_rule_apply(p_rule_id,p_limit)$$;
create or replace function public.layer4_scope_rule_save(p_scholarship_id uuid,p_candidate_reason text,p_decision text,p_reason text,p_confirmation text)
returns jsonb language sql security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.layer4_scope_rule_save(p_scholarship_id,p_candidate_reason,p_decision,p_reason,p_confirmation)$$;
create or replace function public.layer4_scope_rule_set_state(p_rule_id uuid,p_enabled boolean,p_reason text)
returns jsonb language sql security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.layer4_scope_rule_set_state(p_rule_id,p_enabled,p_reason)$$;
create or replace function public.layer4_scope_rules_read(p_limit integer default 100)
returns jsonb language sql stable security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.layer4_scope_rules_read(p_limit)$$;

revoke all on function public.layer4_mass_operations_history(integer) from public,anon;
revoke all on function public.layer4_mass_summary() from public,anon;
revoke all on function public.layer4_quality_diagnostics() from public,anon;
revoke all on function public.layer4_quality_finding_resolve(uuid,text,text) from public,anon;
revoke all on function public.layer4_quality_finding_upsert(text,text,text,text,text,jsonb) from public,anon;
revoke all on function public.layer4_quality_findings_read(text,integer) from public,anon;
revoke all on function public.layer4_review_bulk_decide(text,text,text,text,text,text,integer) from public,anon;
revoke all on function public.layer4_review_groups(integer) from public,anon;
revoke all on function public.layer4_scholarship_scope_bulk_decide(uuid,text,text,text,text) from public,anon;
revoke all on function public.layer4_scholarship_scope_groups(integer) from public,anon;
revoke all on function public.layer4_scholarship_scope_preview(uuid,text) from public,anon;
revoke all on function public.layer4_scope_rule_apply(uuid,integer) from public,anon;
revoke all on function public.layer4_scope_rule_save(uuid,text,text,text,text) from public,anon;
revoke all on function public.layer4_scope_rule_set_state(uuid,boolean,text) from public,anon;
revoke all on function public.layer4_scope_rules_read(integer) from public,anon;

grant execute on function public.layer4_mass_operations_history(integer) to authenticated,service_role;
grant execute on function public.layer4_mass_summary() to authenticated,service_role;
grant execute on function public.layer4_quality_diagnostics() to authenticated,service_role;
grant execute on function public.layer4_quality_finding_resolve(uuid,text,text) to authenticated,service_role;
grant execute on function public.layer4_quality_finding_upsert(text,text,text,text,text,jsonb) to authenticated,service_role;
grant execute on function public.layer4_quality_findings_read(text,integer) to authenticated,service_role;
grant execute on function public.layer4_review_bulk_decide(text,text,text,text,text,text,integer) to authenticated,service_role;
grant execute on function public.layer4_review_groups(integer) to authenticated,service_role;
grant execute on function public.layer4_scholarship_scope_bulk_decide(uuid,text,text,text,text) to authenticated,service_role;
grant execute on function public.layer4_scholarship_scope_groups(integer) to authenticated,service_role;
grant execute on function public.layer4_scholarship_scope_preview(uuid,text) to authenticated,service_role;
grant execute on function public.layer4_scope_rule_apply(uuid,integer) to authenticated,service_role;
grant execute on function public.layer4_scope_rule_save(uuid,text,text,text,text) to authenticated,service_role;
grant execute on function public.layer4_scope_rule_set_state(uuid,boolean,text) to authenticated,service_role;
grant execute on function public.layer4_scope_rules_read(integer) to authenticated,service_role;
