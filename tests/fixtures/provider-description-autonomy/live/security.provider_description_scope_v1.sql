CREATE OR REPLACE FUNCTION security.provider_description_scope_v1(p_provider uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from catalogue.providers p join ref.countries k on k.id = p.country_id left join ref.provider_types t on t.id = p.provider_type_id
     where p.id = p_provider and p.lifecycle_status = 'active'
       and coalesce(security.toolset_setting('pipeline', 'pdesc.countries'), '["AU"]'::jsonb) ? k.iso_alpha2::text
       and coalesce(security.toolset_setting('pipeline', 'pdesc.provider_types'), '["university"]'::jsonb) ? coalesce(t.code, '')
       and (jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'pdesc.provider_keys'), '[]'::jsonb)) = 0
            or coalesce(security.toolset_setting('pipeline', 'pdesc.provider_keys'), '[]'::jsonb) ? lower(p.stable_key)
            or coalesce(security.toolset_setting('pipeline', 'pdesc.provider_keys'), '[]'::jsonb) ? p.stable_key))
$function$

