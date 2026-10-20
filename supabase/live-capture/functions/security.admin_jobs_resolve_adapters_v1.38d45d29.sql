CREATE OR REPLACE FUNCTION security.admin_jobs_resolve_adapters_v1(p_args jsonb)
 RETURNS uuid[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_country text := upper(nullif(btrim(coalesce(p_args->>'country', '')), '')); v_state text := upper(nullif(btrim(coalesce(p_args->>'state', '')), ''));
        v_kind text := coalesce(nullif(p_args->>'provider_kind', ''), 'any'); v_adapter text := coalesce(nullif(p_args->>'adapter_state', ''), 'enabled');
        v_pat text := coalesce(security.firecrawl_setting('target_name_pattern') #>> '{}', '(^|[^a-z])universit(y|ies)([^a-z]|$)');
        v_ids uuid[];
begin
  if p_args ? 'provider_ids' and jsonb_typeof(p_args->'provider_ids') = 'array' and jsonb_array_length(p_args->'provider_ids') > 0 then
    return array(select distinct (x)::uuid from jsonb_array_elements_text(p_args->'provider_ids') x
                  where exists (select 1 from pipeline.uni_adapters u where u.provider_id = (x)::uuid));
  end if;
  v_ids := array(
    select p.id from catalogue.providers p
      join ref.countries k on k.id = p.country_id
      left join ref.subdivisions s on s.id = p.subdivision_id
      join pipeline.uni_adapters u on u.provider_id = p.id
     where (v_country is null or k.iso_alpha2 = v_country)
       and (v_state is null or upper(s.code) = v_state)
       and (v_kind <> 'university' or coalesce(p.display_name, p.canonical_name) ~* v_pat)
       and (v_adapter = 'any' or (v_adapter = 'enabled' and u.enabled) or (v_adapter = 'testing' and u.enabled and not u.admit) or (v_adapter = 'admitting' and u.enabled and u.admit))
     order by coalesce(p.display_name, p.canonical_name));
  return v_ids;
end $function$
