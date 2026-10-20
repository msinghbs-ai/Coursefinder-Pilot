CREATE OR REPLACE FUNCTION public.manual_pim_candidate_register(p_entity_type text, p_target_provider_id uuid DEFAULT NULL::uuid, p_source_kind text DEFAULT 'first_party'::text, p_external_identifier text DEFAULT NULL::text, p_source_url text DEFAULT NULL::text, p_evidence_id uuid DEFAULT NULL::uuid, p_candidate_payload jsonb DEFAULT '{}'::jsonb, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'pg_catalog', 'pim_api'
AS $function$
 select pim_api.manual_pim_candidate_register(p_entity_type,p_target_provider_id,p_source_kind,p_external_identifier,p_source_url,p_evidence_id,p_candidate_payload,p_reason)
$function$
