CREATE OR REPLACE FUNCTION security.provider_description_signature_v1(p_hash text, p_model text, p_prompt text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select md5(coalesce(p_hash,'')||'|'||coalesce(p_model,'')||'|'||coalesce(p_prompt,'provider-description-v2')||'|'||md5(pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure))||'|'||coalesce((select jsonb_object_agg(key,value order by key)::text from pipeline.platform_toolset_settings where toolset_key='pipeline' and key in ('pdesc.min_quote_chars','pdesc.min_sentences','pdesc.max_sentences','pdesc.min_chars','pdesc.max_chars','pdesc.support_min_share','pdesc.duplicate_share','pdesc.source_max_age_days','pdesc.verbatim_span_max_chars','pdesc.claim_words','pdesc.evidence_claim_words','pdesc.superlatives')),'')||coalesce('|'||security.pdesc_reader_behaviour_v1(),''))
$function$
