CREATE OR REPLACE FUNCTION security.provider_description_quality_classes_v1()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  -- the order of the pipeline, from nothing to published; the Provider Catalogue sorts by it
  select array['missing', 'queued', 'processing', 'waiting_decision', 'held', 'basic_registry', 'unrecorded', 'enriched_admitted', 'consumer_pending', 'verified_published']::text[]
$function$
