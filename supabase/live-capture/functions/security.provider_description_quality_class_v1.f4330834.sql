CREATE OR REPLACE FUNCTION security.provider_description_quality_class_v1(p_filled boolean, p_adm text, p_tier text, p_reader text, p_l4 text, p_web text, p_zoho text, p_feeds boolean DEFAULT true)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO ''
AS $function$
  select case
    when coalesce(p_filled, false) then
      case when p_adm = 'admitted' and p_tier = 'registry_factual' then
             case when p_reader = 'reading' then 'processing' when p_reader = 'queued' then 'queued' when p_reader = 'proposed' then 'waiting_decision' else 'basic_registry' end
           when p_adm = 'admitted' then
             case when not coalesce(p_feeds, false) or security.provider_description_publication_v1(p_web) is null or security.provider_description_publication_v1(p_zoho) is null then null
                  when 'pending' in (security.provider_description_publication_v1(p_web), security.provider_description_publication_v1(p_zoho)) then 'consumer_pending'
                  when 'verified' in (security.provider_description_publication_v1(p_web), security.provider_description_publication_v1(p_zoho)) then 'verified_published'
                  else 'enriched_admitted' end
           else 'unrecorded' end
    else
      case when p_adm = 'pending' and (p_reader = 'proposed' or p_l4 = 'pending') then 'waiting_decision'
           when p_adm = 'pending' and p_reader = 'reading' then 'processing'
           when p_adm = 'pending' then 'queued'
           when p_adm in ('held', 'declined') then 'held'
           else 'missing' end
  end
$function$
