CREATE OR REPLACE FUNCTION security.provider_description_publication_read_v1(p_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- the actual consumer reads (security.provider_description_consumer_read_v1 -> the Website and Zoho provider reads), one provider at a time so a failed read never hides the rest.
  -- A consumer that answers NOT_FOUND does not serve the provider: not_served, never an error. 'feed' is what the Catalogue's own Website and Zoho state says the sync expects (verified, pending or
  -- not_applicable); the read-back is what the consumer returns now, and the two can differ.
  return (
    with f as (select ff.provider_id, ff.website_state, ff.zoho_state from security.provider_catalogue_facts_v1(p_ids, true) ff) -- one call for the whole set: it runs both feed scans once, not once a provider
    select jsonb_build_object('as_at', now(), 'providers', coalesce(jsonb_agg(jsonb_build_object('provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name),
      'catalogue', jsonb_build_object('status', case when nullif(btrim(p.description), '') is null then 'no_description' else 'present' end),
      'website', jsonb_build_object('status', case when nullif(btrim(p.description), '') is null then 'awaiting_description' when w.body->'error'->>'code' = 'NOT_FOUND' then 'not_served' when w.body ? 'error' then 'error'
                                                   when w.body->'item' is null or jsonb_typeof(w.body->'item') <> 'object' then 'not_served'
                                                   when w.body->'item'->>'provider_id' = p.stable_key and w.body->'item'->>'description' = p.description then 'verified' else 'mismatch' end,
                                   'description', w.body->'item'->>'description', 'error', w.body->'error', 'feed', security.provider_description_publication_v1(f.website_state)),
      'zoho', jsonb_build_object('status', case when nullif(btrim(p.description), '') is null then 'awaiting_description' when z.body->'error'->>'code' = 'NOT_FOUND' then 'not_served' when z.body ? 'error' then 'error'
                                                when z.body->'item' is null or jsonb_typeof(z.body->'item') <> 'object' then 'not_served'
                                                when z.body->'item'->>'provider_id' = p.stable_key and z.body->'item'->>'description' = p.description then 'verified' else 'mismatch' end,
                                 'description', z.body->'item'->>'description', 'error', z.body->'error', 'feed', security.provider_description_publication_v1(f.zoho_state))) order by coalesce(p.display_name, p.canonical_name)), '[]'::jsonb))
      from catalogue.providers p
      left join lateral (select security.provider_description_consumer_read_v1('website', p.stable_key) body where nullif(btrim(p.description), '') is not null) w on true
      left join lateral (select security.provider_description_consumer_read_v1('zoho', p.stable_key) body where nullif(btrim(p.description), '') is not null) z on true
      left join f on f.provider_id = p.id
     where p.id = any(p_ids)
  );
end
$function$
