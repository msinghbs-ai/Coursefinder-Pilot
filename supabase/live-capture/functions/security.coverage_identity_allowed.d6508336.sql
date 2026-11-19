CREATE OR REPLACE FUNCTION security.coverage_identity_allowed(p_provider_id uuid, p_basis text, p_attr text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when p_basis in ('cricos_code', 'cricos_code_on_page', 'cricos_search') and not exists (select 1 from catalogue.providers p0 join ref.countries k0 on k0.id = p0.country_id where p0.id = p_provider_id and k0.iso_alpha2 = 'AU') then false -- 24 Oct 2026: a CRICOS proof exists only in Australia -- fixed: the register is Australian
            when p_basis in ('adapter_code', 'adapter_title')
                   -- 23 Oct 2026 (Platform Admin 12:40): in the countries of identity.adapter_title_countries an adapter title match counts
                   -- like an exact title for the fields its country list names, whatever the adapter admits
                   and not (p_basis = 'adapter_title' and p_attr is not null
                            and exists (select 1 from catalogue.providers p2 join ref.countries k2 on k2.id = p2.country_id
                                         where p2.id = p_provider_id and k2.iso_alpha2 in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s
                                                                                            where s.toolset_key = 'pipeline' and s.key = 'identity.adapter_title_countries')))
                   and not exists (select 1 from pipeline.uni_adapters u where u.provider_id = p_provider_id and u.enabled and u.admit and (p_attr is null or p_attr not in ('intakes', 'english', 'tuition') or (case p_attr when 'tuition' then 'fee' else p_attr end) = any (u.admit_fields))) then false
         else coalesce((
    select case when p_attr is null
                then exists (select 1 from jsonb_each(a.identities) e, jsonb_array_elements_text(e.value) b where b = p_basis)
                else coalesce(a.identities->p_attr ? p_basis, false) end
      from catalogue.providers p join pipeline.coverage_admission_countries a on a.country_id = p.country_id and a.active
     where p.id = p_provider_id), false) end
$function$
