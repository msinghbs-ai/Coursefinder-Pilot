CREATE OR REPLACE FUNCTION security.bind_match_scope_refresh_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int;
begin
  insert into pipeline.bind_match_scope(provider_id, why, unbound)
  select x.provider_id, x.why, x.unbound from (
    select c.provider_id, case when exists (select 1 from pipeline.firecrawl_targets t where t.provider_id = c.provider_id and t.included) then 'tranche override' else 'top by courses without a page' end why,
           count(*) unbound, row_number() over (order by count(*) desc) rn,
           bool_or(exists (select 1 from pipeline.firecrawl_targets t where t.provider_id = c.provider_id and t.included)) ovr
      from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id
     where c.lifecycle_status = 'active' and k.iso_alpha2 = 'AU'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)
       and not exists (select 1 from catalogue.course_links l where l.course_id = c.id and l.link_type = 'official_course' and l.status = 'active')
       and not security.enrich_focus_v1(c.provider_id)
     group by c.provider_id) x
   where x.ovr or x.rn <= security.pipeline_num_v1('bind.match_scope_top_n', 100)
  on conflict (provider_id) do update set why = excluded.why, unbound = excluded.unbound, refreshed_at = now();
  get diagnostics v_n = row_count;
  return v_n;
end $function$
