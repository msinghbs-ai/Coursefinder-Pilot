-- CF-CHG-20260825-037 / CF-CHG-20260825-038
-- Restore public SECURITY INVOKER contracts while keeping private *_impl helpers service-role-only.
-- The SECURITY DEFINER hop lives in non-exposed schema security and delegates immediately to
-- the existing auth.uid()/role-rank checked implementation.

create or replace function security.important_date_upsert_v2_browser_bridge(
  p_id uuid,p_country_code text,p_event_type text,p_title text,p_source_url text,p_evidence_id uuid,
  p_scope_type text,p_source_id uuid,p_source_profile_id uuid,p_entity_type text,p_entity_id uuid,
  p_date_precision text,p_starts_at timestamptz,p_ends_at timestamptz,p_starts_on date,p_ends_on date,
  p_timezone text,p_source_wording text,p_warning_days integer,p_expires_at timestamptz,p_refresh_layer smallint
) returns uuid
language sql security definer set search_path=pg_catalog,security
as $$ select security.important_date_upsert_v2_impl(p_id,p_country_code,p_event_type,p_title,p_source_url,p_evidence_id,p_scope_type,p_source_id,p_source_profile_id,p_entity_type,p_entity_id,p_date_precision,p_starts_at,p_ends_at,p_starts_on,p_ends_on,p_timezone,p_source_wording,p_warning_days,p_expires_at,p_refresh_layer) $$;

create or replace function security.refresh_policy_upsert_v2_browser_bridge(
  p_id uuid,p_country_code text,p_layer smallint,p_source_id uuid,p_source_profile_id uuid,p_entity_type text,p_entity_id uuid,
  p_freshness_class text,p_cadence_days integer,p_next_due_at timestamptz,p_hash_sensitive boolean,
  p_important_date_sensitive boolean,p_enabled boolean,p_reason text
) returns uuid
language sql security definer set search_path=pg_catalog,security
as $$ select security.refresh_policy_upsert_v2_impl(p_id,p_country_code,p_layer,p_source_id,p_source_profile_id,p_entity_type,p_entity_id,p_freshness_class,p_cadence_days,p_next_due_at,p_hash_sensitive,p_important_date_sensitive,p_enabled,p_reason) $$;

create or replace function security.layer4_review_context_browser_bridge(p_review_item_id uuid)
returns jsonb language sql stable security definer set search_path=pg_catalog,security
as $$ select security.layer4_review_context_impl(p_review_item_id) $$;

create or replace function security.onboarding_cases_list_browser_bridge(p_stage text,p_outcome text,p_country_code text,p_case_type text,p_limit integer)
returns jsonb language sql stable security definer set search_path=pg_catalog,security
as $$ select security.onboarding_cases_list_impl(p_stage,p_outcome,p_country_code,p_case_type,p_limit) $$;

create or replace function security.onboarding_case_context_browser_bridge(p_case_id uuid)
returns jsonb language sql stable security definer set search_path=pg_catalog,security
as $$ select security.onboarding_case_context_impl(p_case_id) $$;

create or replace function security.onboarding_case_create_browser_bridge(
  p_case_type text,p_country_code text,p_title text,p_source_id uuid,p_source_profile_id uuid,p_provider_id uuid,p_course_id uuid,
  p_adapter_family text,p_reason text,p_change_control_ref text,p_uat_ref text
) returns uuid language sql security definer set search_path=pg_catalog,security
as $$ select security.onboarding_case_create_impl(p_case_type,p_country_code,p_title,p_source_id,p_source_profile_id,p_provider_id,p_course_id,p_adapter_family,p_reason,p_change_control_ref,p_uat_ref) $$;

create or replace function security.onboarding_case_transition_browser_bridge(
  p_case_id uuid,p_to_stage text,p_outcome text,p_reason text,p_details jsonb,p_evidence_id uuid,p_uat_ref text
) returns jsonb language sql security definer set search_path=pg_catalog,security
as $$ select security.onboarding_case_transition_impl(p_case_id,p_to_stage,p_outcome,p_reason,p_details,p_evidence_id,p_uat_ref) $$;

create or replace function security.onboarding_case_metadata_update_browser_bridge(
  p_case_id uuid,p_adapter_family text,p_source_qualification jsonb,p_adapter_assessment jsonb,p_schema_assessment jsonb,
  p_operational_manifest jsonb,p_reason text,p_uat_ref text
) returns jsonb language sql security definer set search_path=pg_catalog,security
as $$ select security.onboarding_case_metadata_update_impl(p_case_id,p_adapter_family,p_source_qualification,p_adapter_assessment,p_schema_assessment,p_operational_manifest,p_reason,p_uat_ref) $$;

revoke all on function security.important_date_upsert_v2_browser_bridge(uuid,text,text,text,text,uuid,text,uuid,uuid,text,uuid,text,timestamptz,timestamptz,date,date,text,text,integer,timestamptz,smallint) from public,anon;
revoke all on function security.refresh_policy_upsert_v2_browser_bridge(uuid,text,smallint,uuid,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text) from public,anon;
revoke all on function security.layer4_review_context_browser_bridge(uuid) from public,anon;
revoke all on function security.onboarding_cases_list_browser_bridge(text,text,text,text,integer) from public,anon;
revoke all on function security.onboarding_case_context_browser_bridge(uuid) from public,anon;
revoke all on function security.onboarding_case_create_browser_bridge(text,text,text,uuid,uuid,uuid,uuid,text,text,text,text) from public,anon;
revoke all on function security.onboarding_case_transition_browser_bridge(uuid,text,text,text,jsonb,uuid,text) from public,anon;
revoke all on function security.onboarding_case_metadata_update_browser_bridge(uuid,text,jsonb,jsonb,jsonb,jsonb,text,text) from public,anon;
grant execute on function security.important_date_upsert_v2_browser_bridge(uuid,text,text,text,text,uuid,text,uuid,uuid,text,uuid,text,timestamptz,timestamptz,date,date,text,text,integer,timestamptz,smallint) to authenticated;
grant execute on function security.refresh_policy_upsert_v2_browser_bridge(uuid,text,smallint,uuid,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text) to authenticated;
grant execute on function security.layer4_review_context_browser_bridge(uuid) to authenticated;
grant execute on function security.onboarding_cases_list_browser_bridge(text,text,text,text,integer) to authenticated;
grant execute on function security.onboarding_case_context_browser_bridge(uuid) to authenticated;
grant execute on function security.onboarding_case_create_browser_bridge(text,text,text,uuid,uuid,uuid,uuid,text,text,text,text) to authenticated;
grant execute on function security.onboarding_case_transition_browser_bridge(uuid,text,text,text,jsonb,uuid,text) to authenticated;
grant execute on function security.onboarding_case_metadata_update_browser_bridge(uuid,text,jsonb,jsonb,jsonb,jsonb,text,text) to authenticated;

create or replace function public.important_date_upsert_v2(
  p_id uuid,p_country_code text,p_event_type text,p_title text,p_source_url text,p_evidence_id uuid,p_scope_type text,
  p_source_id uuid,p_source_profile_id uuid,p_entity_type text,p_entity_id uuid,p_date_precision text,p_starts_at timestamptz,
  p_ends_at timestamptz,p_starts_on date,p_ends_on date,p_timezone text,p_source_wording text,p_warning_days integer,
  p_expires_at timestamptz,p_refresh_layer smallint
) returns uuid language sql security invoker set search_path=pg_catalog,security
as $$ select security.important_date_upsert_v2_browser_bridge(p_id,p_country_code,p_event_type,p_title,p_source_url,p_evidence_id,p_scope_type,p_source_id,p_source_profile_id,p_entity_type,p_entity_id,p_date_precision,p_starts_at,p_ends_at,p_starts_on,p_ends_on,p_timezone,p_source_wording,p_warning_days,p_expires_at,p_refresh_layer) $$;

create or replace function public.refresh_policy_upsert_v2(
  p_id uuid,p_country_code text,p_layer smallint,p_source_id uuid,p_source_profile_id uuid,p_entity_type text,p_entity_id uuid,
  p_freshness_class text,p_cadence_days integer,p_next_due_at timestamptz,p_hash_sensitive boolean,p_important_date_sensitive boolean,
  p_enabled boolean,p_reason text
) returns uuid language sql security invoker set search_path=pg_catalog,security
as $$ select security.refresh_policy_upsert_v2_browser_bridge(p_id,p_country_code,p_layer,p_source_id,p_source_profile_id,p_entity_type,p_entity_id,p_freshness_class,p_cadence_days,p_next_due_at,p_hash_sensitive,p_important_date_sensitive,p_enabled,p_reason) $$;

create or replace function public.layer4_review_context(p_review_item_id uuid)
returns jsonb language sql stable security invoker set search_path=pg_catalog,security
as $$ select security.layer4_review_context_browser_bridge(p_review_item_id) $$;

create or replace function public.onboarding_cases_list(p_stage text default null,p_outcome text default null,p_country_code text default null,p_case_type text default null,p_limit integer default 100)
returns jsonb language sql stable security invoker set search_path=pg_catalog,security
as $$ select security.onboarding_cases_list_browser_bridge(p_stage,p_outcome,p_country_code,p_case_type,p_limit) $$;

create or replace function public.onboarding_case_context(p_case_id uuid)
returns jsonb language sql stable security invoker set search_path=pg_catalog,security
as $$ select security.onboarding_case_context_browser_bridge(p_case_id) $$;

create or replace function public.onboarding_case_create(
  p_case_type text,p_country_code text,p_title text,p_source_id uuid default null,p_source_profile_id uuid default null,
  p_provider_id uuid default null,p_course_id uuid default null,p_adapter_family text default null,p_reason text default null,
  p_change_control_ref text default 'CF-CHG-20260825-037',p_uat_ref text default null
) returns uuid language sql security invoker set search_path=pg_catalog,security
as $$ select security.onboarding_case_create_browser_bridge(p_case_type,p_country_code,p_title,p_source_id,p_source_profile_id,p_provider_id,p_course_id,p_adapter_family,p_reason,p_change_control_ref,p_uat_ref) $$;

create or replace function public.onboarding_case_transition(
  p_case_id uuid,p_to_stage text,p_outcome text,p_reason text,p_details jsonb default '{}'::jsonb,p_evidence_id uuid default null,p_uat_ref text default null
) returns jsonb language sql security invoker set search_path=pg_catalog,security
as $$ select security.onboarding_case_transition_browser_bridge(p_case_id,p_to_stage,p_outcome,p_reason,p_details,p_evidence_id,p_uat_ref) $$;

create or replace function public.onboarding_case_metadata_update(
  p_case_id uuid,p_adapter_family text default null,p_source_qualification jsonb default null,p_adapter_assessment jsonb default null,
  p_schema_assessment jsonb default null,p_operational_manifest jsonb default null,p_reason text default null,p_uat_ref text default null
) returns jsonb language sql security invoker set search_path=pg_catalog,security
as $$ select security.onboarding_case_metadata_update_browser_bridge(p_case_id,p_adapter_family,p_source_qualification,p_adapter_assessment,p_schema_assessment,p_operational_manifest,p_reason,p_uat_ref) $$;

-- Keep browser-facing ACLs authenticated-only and private implementation ACLs service-role-only.
revoke all on function public.important_date_upsert_v2(uuid,text,text,text,text,uuid,text,uuid,uuid,text,uuid,text,timestamptz,timestamptz,date,date,text,text,integer,timestamptz,smallint) from public,anon;
revoke all on function public.refresh_policy_upsert_v2(uuid,text,smallint,uuid,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text) from public,anon;
revoke all on function public.layer4_review_context(uuid) from public,anon;
revoke all on function public.onboarding_cases_list(text,text,text,text,integer) from public,anon;
revoke all on function public.onboarding_case_context(uuid) from public,anon;
revoke all on function public.onboarding_case_create(text,text,text,uuid,uuid,uuid,uuid,text,text,text,text) from public,anon;
revoke all on function public.onboarding_case_transition(uuid,text,text,text,jsonb,uuid,text) from public,anon;
revoke all on function public.onboarding_case_metadata_update(uuid,text,jsonb,jsonb,jsonb,jsonb,text,text) from public,anon;
grant execute on function public.important_date_upsert_v2(uuid,text,text,text,text,uuid,text,uuid,uuid,text,uuid,text,timestamptz,timestamptz,date,date,text,text,integer,timestamptz,smallint) to authenticated,service_role;
grant execute on function public.refresh_policy_upsert_v2(uuid,text,smallint,uuid,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text) to authenticated,service_role;
grant execute on function public.layer4_review_context(uuid) to authenticated,service_role;
grant execute on function public.onboarding_cases_list(text,text,text,text,integer) to authenticated,service_role;
grant execute on function public.onboarding_case_context(uuid) to authenticated,service_role;
grant execute on function public.onboarding_case_create(text,text,text,uuid,uuid,uuid,uuid,text,text,text,text) to authenticated,service_role;
grant execute on function public.onboarding_case_transition(uuid,text,text,text,jsonb,uuid,text) to authenticated,service_role;
grant execute on function public.onboarding_case_metadata_update(uuid,text,jsonb,jsonb,jsonb,jsonb,text,text) to authenticated,service_role;