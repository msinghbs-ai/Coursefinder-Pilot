CREATE OR REPLACE FUNCTION security.provider_lifecycle_held_v1(p_provider uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CF-247 ops G: a provider held by an executed (not reversed) temporarily_unavailable event: its new work waits, nothing is retired
  select exists (select 1 from pipeline.provider_lifecycle_events e where e.provider_id = p_provider and e.scope = 'provider'
                  and e.transition = 'temporarily_unavailable' and e.state = 'executed')
$function$

