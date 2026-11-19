CREATE OR REPLACE FUNCTION security.provider_description_quality_v1(p_ids uuid[] DEFAULT NULL::uuid[], p_feeds boolean DEFAULT true)
 RETURNS TABLE(provider_id uuid, quality_class text, description_filled boolean, admission_state text, source_tier text, evidence_id uuid, source_url text, reader_state text, reader_rule text, reader_tries integer, l4_status text, hold_reason text, next_retry_at timestamp with time zone, last_read_ok_at timestamp with time zone, admitted_at timestamp with time zone, admitted_by text, website_state text, zoho_state text, website_publication text, zoho_publication text, readback_at timestamp with time zone, missing_fields text[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
#variable_conflict use_column
begin
  return query
  select f.provider_id, security.provider_description_quality_class_v1(f.description_filled, f.admission_state, f.source_tier, f.reader_state, f.l4_status, f.website_state, f.zoho_state, p_feeds),
         f.description_filled, f.admission_state, f.source_tier, f.evidence_id, f.source_url, f.reader_state, f.reader_rule, f.reader_tries, f.l4_status, f.hold_reason, f.next_retry_at, f.last_read_ok_at,
         f.admitted_at, f.admitted_by, f.website_state, f.zoho_state,
         security.provider_description_publication_v1(f.website_state), security.provider_description_publication_v1(f.zoho_state), f.readback_at, security.provider_missing_fields_v1(p)
    from security.provider_catalogue_facts_v1(p_ids, p_feeds) f join catalogue.providers p on p.id = f.provider_id;
end
$function$
