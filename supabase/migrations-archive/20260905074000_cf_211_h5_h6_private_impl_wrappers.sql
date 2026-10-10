-- CF-211: public SECURITY INVOKER wrappers over private SECURITY DEFINER implementations.
create schema if not exists pim_api;
revoke all on schema pim_api from public,anon;
grant usage on schema pim_api to authenticated;
grant usage on schema l4_api to authenticated;

alter function public.manual_pim_candidate_register(text,uuid,text,text,text,uuid,jsonb,text) set schema pim_api;
alter function public.manual_pim_candidates_read(text,text,integer) set schema pim_api;
alter function public.manual_pim_candidate_decide(uuid,text,text) set schema pim_api;
alter function public.publication_control_preview(text,uuid[],text,text) set schema l4_api;
alter function public.publication_control_execute(text,uuid[],text,text,text,text,text) set schema l4_api;

revoke all on function pim_api.manual_pim_candidate_register(text,uuid,text,text,text,uuid,jsonb,text) from public,anon;
revoke all on function pim_api.manual_pim_candidates_read(text,text,integer) from public,anon;
revoke all on function pim_api.manual_pim_candidate_decide(uuid,text,text) from public,anon;
revoke all on function l4_api.publication_control_preview(text,uuid[],text,text) from public,anon;
revoke all on function l4_api.publication_control_execute(text,uuid[],text,text,text,text,text) from public,anon;
grant execute on function pim_api.manual_pim_candidate_register(text,uuid,text,text,text,uuid,jsonb,text) to authenticated;
grant execute on function pim_api.manual_pim_candidates_read(text,text,integer) to authenticated;
grant execute on function pim_api.manual_pim_candidate_decide(uuid,text,text) to authenticated;
grant execute on function l4_api.publication_control_preview(text,uuid[],text,text) to authenticated;
grant execute on function l4_api.publication_control_execute(text,uuid[],text,text,text,text,text) to authenticated;

create or replace function public.manual_pim_candidate_register(p_entity_type text,p_target_provider_id uuid default null,p_source_kind text default 'first_party',p_external_identifier text default null,p_source_url text default null,p_evidence_id uuid default null,p_candidate_payload jsonb default '{}'::jsonb,p_reason text default null)
returns jsonb language sql security invoker set search_path='pg_catalog','pim_api' as $$select pim_api.manual_pim_candidate_register(p_entity_type,p_target_provider_id,p_source_kind,p_external_identifier,p_source_url,p_evidence_id,p_candidate_payload,p_reason)$$;
create or replace function public.manual_pim_candidates_read(p_status text default null,p_entity_type text default null,p_limit integer default 100)
returns jsonb language sql stable security invoker set search_path='pg_catalog','pim_api' as $$select pim_api.manual_pim_candidates_read(p_status,p_entity_type,p_limit)$$;
create or replace function public.manual_pim_candidate_decide(p_candidate_id uuid,p_action text,p_reason text)
returns jsonb language sql security invoker set search_path='pg_catalog','pim_api' as $$select pim_api.manual_pim_candidate_decide(p_candidate_id,p_action,p_reason)$$;
create or replace function public.publication_control_preview(p_entity_type text,p_entity_ids uuid[],p_target_scope text,p_action text)
returns jsonb language sql stable security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.publication_control_preview(p_entity_type,p_entity_ids,p_target_scope,p_action)$$;
create or replace function public.publication_control_execute(p_entity_type text,p_entity_ids uuid[],p_target_scope text,p_action text,p_confirmation_token text,p_reason_code text,p_comment text default null)
returns jsonb language sql security invoker set search_path='pg_catalog','l4_api' as $$select l4_api.publication_control_execute(p_entity_type,p_entity_ids,p_target_scope,p_action,p_confirmation_token,p_reason_code,p_comment)$$;

revoke all on function public.manual_pim_candidate_register(text,uuid,text,text,text,uuid,jsonb,text) from public,anon;
revoke all on function public.manual_pim_candidates_read(text,text,integer) from public,anon;
revoke all on function public.manual_pim_candidate_decide(uuid,text,text) from public,anon;
revoke all on function public.publication_control_preview(text,uuid[],text,text) from public,anon;
revoke all on function public.publication_control_execute(text,uuid[],text,text,text,text,text) from public,anon;
grant execute on function public.manual_pim_candidate_register(text,uuid,text,text,text,uuid,jsonb,text) to authenticated;
grant execute on function public.manual_pim_candidates_read(text,text,integer) to authenticated;
grant execute on function public.manual_pim_candidate_decide(uuid,text,text) to authenticated;
grant execute on function public.publication_control_preview(text,uuid[],text,text) to authenticated;
grant execute on function public.publication_control_execute(text,uuid[],text,text,text,text,text) to authenticated;
