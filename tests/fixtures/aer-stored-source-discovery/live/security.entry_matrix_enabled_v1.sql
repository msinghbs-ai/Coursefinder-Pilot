CREATE OR REPLACE FUNCTION security.entry_matrix_enabled_v1(p_provider uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select security.pipeline_num_v1('entry.matrix_enabled', 0) >= 1
     and exists (select 1 from catalogue.providers p join ref.countries k on k.id = p.country_id
                  where p.id = p_provider
                    and coalesce(security.toolset_setting('pipeline', 'entry.countries'), '["AU","NZ"]'::jsonb) ? k.iso_alpha2::text)
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p_provider)
     -- AU completion week step 6 (26 Oct 2026): only the providers in entry.providers, when that list is not empty
     -- CF-247 scheduled entry reading (3 Nov 2026): while job aer-scheduled-read is on, eligibility rules replace that list: an AER-eligible provider
     -- (security.aer_eligible_v1) of a country switched on for scheduled reading (security.aer_schedule_country_v1) with an entry page recorded
     and (case when security.aer_schedule_active_v1()
               then exists (select 1 from security.aer_eligible_v1() e where e.provider_id = p_provider and (security.aer_schedule_country_v1(e.country)->>'on')::boolean)
                    and exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = p_provider)
               else jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb)) = 0
                    or coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb) ? p_provider::text end)
$function$
