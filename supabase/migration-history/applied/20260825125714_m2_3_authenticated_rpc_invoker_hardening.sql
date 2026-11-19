-- M2.3 hardening: keep privileged implementations private; public API wrappers are SECURITY INVOKER.
-- Change Control: CF-CHG-20260825-038

-- Move current role-checked implementations into the private security schema.
alter function public.layer3_model_profiles_admin() set schema security;
alter function security.layer3_model_profiles_admin() rename to layer3_model_profiles_admin_impl;
alter function public.layer3_model_profile_set_state(uuid,boolean,boolean,text) set schema security;
alter function security.layer3_model_profile_set_state(uuid,boolean,boolean,text) rename to layer3_model_profile_set_state_impl;
alter function public.layer3_recent_interpretations(integer) set schema security;
alter function security.layer3_recent_interpretations(integer) rename to layer3_recent_interpretations_impl;
alter function public.layer3_model_profile_upsert(uuid,text,text,text,text,text,text[],text,text,jsonb,jsonb,integer,integer,integer,integer,integer,integer,uuid,numeric,boolean,boolean,text) set schema security;
alter function security.layer3_model_profile_upsert(uuid,text,text,text,text,text,text[],text,text,jsonb,jsonb,integer,integer,integer,integer,integer,integer,uuid,numeric,boolean,boolean,text) rename to layer3_model_profile_upsert_impl;
alter function public.layer4_review_queue(text,integer) set schema security;
alter function security.layer4_review_queue(text,integer) rename to layer4_review_queue_impl;
alter function public.layer4_review_decide(uuid,text,text,jsonb) set schema security;
alter function security.layer4_review_decide(uuid,text,text,jsonb) rename to layer4_review_decide_impl;
alter function public.refresh_intelligence_overview(integer) set schema security;
alter function security.refresh_intelligence_overview(integer) rename to refresh_intelligence_overview_impl;
alter function public.refresh_policy_upsert(uuid,text,smallint,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text) set schema security;
alter function security.refresh_policy_upsert(uuid,text,smallint,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text) rename to refresh_policy_upsert_impl;
alter function public.important_links_list(text) set schema security;
alter function security.important_links_list(text) rename to important_links_list_impl;
alter function public.important_link_upsert(uuid,text,text,text,text,text,text,smallint,uuid,integer,text) set schema security;
alter function security.important_link_upsert(uuid,text,text,text,text,text,text,smallint,uuid,integer,text) rename to important_link_upsert_impl;
alter function public.important_link_verify(uuid,text,text) set schema security;
alter function security.important_link_verify(uuid,text,text) rename to important_link_verify_impl;
alter function public.important_dates_ticker(text,integer) set schema security;
alter function security.important_dates_ticker(text,integer) rename to important_dates_ticker_impl;
alter function public.important_date_upsert(uuid,text,text,text,text,uuid,text,uuid,text,uuid,text,timestamptz,timestamptz,text,text,integer,timestamptz,smallint) set schema security;
alter function security.important_date_upsert(uuid,text,text,text,text,uuid,text,uuid,text,uuid,text,timestamptz,timestamptz,text,text,integer,timestamptz,smallint) rename to important_date_upsert_impl;
alter function public.important_date_queue_targeted_refresh(uuid,text) set schema security;
alter function security.important_date_queue_targeted_refresh(uuid,text) rename to important_date_queue_targeted_refresh_impl;

-- Private implementations: no direct public/anon access; authenticated execute is only to permit invoker wrappers.
revoke all on function security.layer3_model_profiles_admin_impl() from public,anon,authenticated;
revoke all on function security.layer3_model_profile_set_state_impl(uuid,boolean,boolean,text) from public,anon,authenticated;
revoke all on function security.layer3_recent_interpretations_impl(integer) from public,anon,authenticated;
revoke all on function security.layer3_model_profile_upsert_impl(uuid,text,text,text,text,text,text[],text,text,jsonb,jsonb,integer,integer,integer,integer,integer,integer,uuid,numeric,boolean,boolean,text) from public,anon,authenticated;
revoke all on function security.layer4_review_queue_impl(text,integer) from public,anon,authenticated;
revoke all on function security.layer4_review_decide_impl(uuid,text,text,jsonb) from public,anon,authenticated;
revoke all on function security.refresh_intelligence_overview_impl(integer) from public,anon,authenticated;
revoke all on function security.refresh_policy_upsert_impl(uuid,text,smallint,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text) from public,anon,authenticated;
revoke all on function security.important_links_list_impl(text) from public,anon,authenticated;
revoke all on function security.important_link_upsert_impl(uuid,text,text,text,text,text,text,smallint,uuid,integer,text) from public,anon,authenticated;
revoke all on function security.important_link_verify_impl(uuid,text,text) from public,anon,authenticated;
revoke all on function security.important_dates_ticker_impl(text,integer) from public,anon,authenticated;
revoke all on function security.important_date_upsert_impl(uuid,text,text,text,text,uuid,text,uuid,text,uuid,text,timestamptz,timestamptz,text,text,integer,timestamptz,smallint) from public,anon,authenticated;
revoke all on function security.important_date_queue_targeted_refresh_impl(uuid,text) from public,anon,authenticated;

grant execute on function security.layer3_model_profiles_admin_impl() to authenticated;
grant execute on function security.layer3_model_profile_set_state_impl(uuid,boolean,boolean,text) to authenticated;
grant execute on function security.layer3_recent_interpretations_impl(integer) to authenticated;
grant execute on function security.layer3_model_profile_upsert_impl(uuid,text,text,text,text,text,text[],text,text,jsonb,jsonb,integer,integer,integer,integer,integer,integer,uuid,numeric,boolean,boolean,text) to authenticated;
grant execute on function security.layer4_review_queue_impl(text,integer) to authenticated;
grant execute on function security.layer4_review_decide_impl(uuid,text,text,jsonb) to authenticated;
grant execute on function security.refresh_intelligence_overview_impl(integer) to authenticated;
grant execute on function security.refresh_policy_upsert_impl(uuid,text,smallint,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text) to authenticated;
grant execute on function security.important_links_list_impl(text) to authenticated;
grant execute on function security.important_link_upsert_impl(uuid,text,text,text,text,text,text,smallint,uuid,integer,text) to authenticated;
grant execute on function security.important_link_verify_impl(uuid,text,text) to authenticated;
grant execute on function security.important_dates_ticker_impl(text,integer) to authenticated;
grant execute on function security.important_date_upsert_impl(uuid,text,text,text,text,uuid,text,uuid,text,uuid,text,timestamptz,timestamptz,text,text,integer,timestamptz,smallint) to authenticated;
grant execute on function security.important_date_queue_targeted_refresh_impl(uuid,text) to authenticated;

-- Exposed wrappers are invoker functions. Role/rank enforcement remains in the private implementations.
create function public.layer3_model_profiles_admin() returns jsonb language sql stable security invoker set search_path=pg_catalog,security as $$ select security.layer3_model_profiles_admin_impl() $$;
create function public.layer3_model_profile_set_state(p_profile_id uuid,p_enabled boolean,p_paused boolean,p_reason text) returns jsonb language sql security invoker set search_path=pg_catalog,security as $$ select security.layer3_model_profile_set_state_impl(p_profile_id,p_enabled,p_paused,p_reason) $$;
create function public.layer3_recent_interpretations(p_limit integer default 100) returns jsonb language sql stable security invoker set search_path=pg_catalog,security as $$ select security.layer3_recent_interpretations_impl(p_limit) $$;
create function public.layer3_model_profile_upsert(p_id uuid,p_code text,p_aggregator_provider text,p_base_url text,p_model_identifier text,p_secret_env_key text,p_allowed_task_classes text[],p_prompt_profile_version text,p_prompt_system text,p_structured_output_schema jsonb,p_deterministic_validators jsonb,p_max_input_tokens integer,p_max_output_tokens integer,p_requests_per_minute integer,p_requests_per_day integer,p_retry_ceiling integer,p_timeout_ms integer,p_fallback_profile_id uuid,p_cost_ceiling_usd numeric,p_enabled boolean,p_paused boolean,p_reason text) returns uuid language sql security invoker set search_path=pg_catalog,security as $$ select security.layer3_model_profile_upsert_impl(p_id,p_code,p_aggregator_provider,p_base_url,p_model_identifier,p_secret_env_key,p_allowed_task_classes,p_prompt_profile_version,p_prompt_system,p_structured_output_schema,p_deterministic_validators,p_max_input_tokens,p_max_output_tokens,p_requests_per_minute,p_requests_per_day,p_retry_ceiling,p_timeout_ms,p_fallback_profile_id,p_cost_ceiling_usd,p_enabled,p_paused,p_reason) $$;
create function public.layer4_review_queue(p_status text default 'pending',p_limit integer default 100) returns jsonb language sql stable security invoker set search_path=pg_catalog,security as $$ select security.layer4_review_queue_impl(p_status,p_limit) $$;
create function public.layer4_review_decide(p_review_item_id uuid,p_action text,p_reason text,p_final_value jsonb default null) returns jsonb language sql security invoker set search_path=pg_catalog,security as $$ select security.layer4_review_decide_impl(p_review_item_id,p_action,p_reason,p_final_value) $$;
create function public.refresh_intelligence_overview(p_limit integer default 100) returns jsonb language sql stable security invoker set search_path=pg_catalog,security as $$ select security.refresh_intelligence_overview_impl(p_limit) $$;
create function public.refresh_policy_upsert(p_id uuid,p_country_code text,p_layer smallint,p_source_profile_id uuid,p_entity_type text,p_entity_id uuid,p_freshness_class text,p_cadence_days integer,p_next_due_at timestamptz,p_hash_sensitive boolean,p_important_date_sensitive boolean,p_enabled boolean,p_reason text) returns uuid language sql security invoker set search_path=pg_catalog,security as $$ select security.refresh_policy_upsert_impl(p_id,p_country_code,p_layer,p_source_profile_id,p_entity_type,p_entity_id,p_freshness_class,p_cadence_days,p_next_due_at,p_hash_sensitive,p_important_date_sensitive,p_enabled,p_reason) $$;
create function public.important_links_list(p_country_code text default null) returns jsonb language sql stable security invoker set search_path=pg_catalog,security as $$ select security.important_links_list_impl(p_country_code) $$;
create function public.important_link_upsert(p_id uuid,p_country_code text,p_authority_category text,p_authority_name text,p_owner_label text,p_url text,p_purpose text,p_related_layer smallint,p_related_source_profile_id uuid,p_verification_days integer,p_health_status text) returns uuid language sql security invoker set search_path=pg_catalog,security as $$ select security.important_link_upsert_impl(p_id,p_country_code,p_authority_category,p_authority_name,p_owner_label,p_url,p_purpose,p_related_layer,p_related_source_profile_id,p_verification_days,p_health_status) $$;
create function public.important_link_verify(p_id uuid,p_health_status text,p_note text) returns jsonb language sql security invoker set search_path=pg_catalog,security as $$ select security.important_link_verify_impl(p_id,p_health_status,p_note) $$;
create function public.important_dates_ticker(p_country_code text default null,p_days integer default 60) returns jsonb language sql stable security invoker set search_path=pg_catalog,security as $$ select security.important_dates_ticker_impl(p_country_code,p_days) $$;
create function public.important_date_upsert(p_id uuid,p_country_code text,p_event_type text,p_title text,p_source_url text,p_evidence_id uuid,p_scope_type text,p_source_profile_id uuid,p_entity_type text,p_entity_id uuid,p_date_precision text,p_starts_at timestamptz,p_ends_at timestamptz,p_timezone text,p_source_wording text,p_warning_days integer,p_expires_at timestamptz,p_refresh_layer smallint) returns uuid language sql security invoker set search_path=pg_catalog,security as $$ select security.important_date_upsert_impl(p_id,p_country_code,p_event_type,p_title,p_source_url,p_evidence_id,p_scope_type,p_source_profile_id,p_entity_type,p_entity_id,p_date_precision,p_starts_at,p_ends_at,p_timezone,p_source_wording,p_warning_days,p_expires_at,p_refresh_layer) $$;
create function public.important_date_queue_targeted_refresh(p_important_date_id uuid,p_reason text) returns uuid language sql security invoker set search_path=pg_catalog,security as $$ select security.important_date_queue_targeted_refresh_impl(p_important_date_id,p_reason) $$;

revoke all on function public.layer3_model_profiles_admin() from public,anon,authenticated;
revoke all on function public.layer3_model_profile_set_state(uuid,boolean,boolean,text) from public,anon,authenticated;
revoke all on function public.layer3_recent_interpretations(integer) from public,anon,authenticated;
revoke all on function public.layer3_model_profile_upsert(uuid,text,text,text,text,text,text[],text,text,jsonb,jsonb,integer,integer,integer,integer,integer,integer,uuid,numeric,boolean,boolean,text) from public,anon,authenticated;
revoke all on function public.layer4_review_queue(text,integer) from public,anon,authenticated;
revoke all on function public.layer4_review_decide(uuid,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.refresh_intelligence_overview(integer) from public,anon,authenticated;
revoke all on function public.refresh_policy_upsert(uuid,text,smallint,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text) from public,anon,authenticated;
revoke all on function public.important_links_list(text) from public,anon,authenticated;
revoke all on function public.important_link_upsert(uuid,text,text,text,text,text,text,smallint,uuid,integer,text) from public,anon,authenticated;
revoke all on function public.important_link_verify(uuid,text,text) from public,anon,authenticated;
revoke all on function public.important_dates_ticker(text,integer) from public,anon,authenticated;
revoke all on function public.important_date_upsert(uuid,text,text,text,text,uuid,text,uuid,text,uuid,text,timestamptz,timestamptz,text,text,integer,timestamptz,smallint) from public,anon,authenticated;
revoke all on function public.important_date_queue_targeted_refresh(uuid,text) from public,anon,authenticated;

grant execute on function public.layer3_model_profiles_admin() to authenticated;
grant execute on function public.layer3_model_profile_set_state(uuid,boolean,boolean,text) to authenticated;
grant execute on function public.layer3_recent_interpretations(integer) to authenticated;
grant execute on function public.layer3_model_profile_upsert(uuid,text,text,text,text,text,text[],text,text,jsonb,jsonb,integer,integer,integer,integer,integer,integer,uuid,numeric,boolean,boolean,text) to authenticated;
grant execute on function public.layer4_review_queue(text,integer) to authenticated;
grant execute on function public.layer4_review_decide(uuid,text,text,jsonb) to authenticated;
grant execute on function public.refresh_intelligence_overview(integer) to authenticated;
grant execute on function public.refresh_policy_upsert(uuid,text,smallint,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text) to authenticated;
grant execute on function public.important_links_list(text) to authenticated;
grant execute on function public.important_link_upsert(uuid,text,text,text,text,text,text,smallint,uuid,integer,text) to authenticated;
grant execute on function public.important_link_verify(uuid,text,text) to authenticated;
grant execute on function public.important_dates_ticker(text,integer) to authenticated;
grant execute on function public.important_date_upsert(uuid,text,text,text,text,uuid,text,uuid,text,uuid,text,timestamptz,timestamptz,text,text,integer,timestamptz,smallint) to authenticated;
grant execute on function public.important_date_queue_targeted_refresh(uuid,text) to authenticated;
