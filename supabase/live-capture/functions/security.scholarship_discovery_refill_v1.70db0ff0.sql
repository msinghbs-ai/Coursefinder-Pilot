CREATE OR REPLACE FUNCTION security.scholarship_discovery_refill_v1(p_keep integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_pending int; v_added int := 0;
begin
  select count(*) into v_pending from pipeline.scholarship_discovery_providers where status = 'pending';
  if v_pending < p_keep then
    insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status)
    select q.provider_id, q.website, case when q.cc = 'AU' then 4 else 1 end, case when q.cc = 'AU' then 'largest_unsearched' else 'university_' || lower(q.cc) end, 'pending'
      from (select p.id provider_id, k.iso_alpha2 cc,
                   coalesce(nullif(btrim(p.website), ''), (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p.id and d.status = 'mapped')) website,
                   count(*) n
              from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
             where co.lifecycle_status = 'active' and k.scholarship_ingestion_enabled
               and (k.iso_alpha2 = 'AU' or security.scholarship_university(p.id))
               and not exists (select 1 from pipeline.scholarship_discovery_providers d where d.provider_id = p.id)
             group by p.id, p.website, k.iso_alpha2) q
     where q.website is not null
     order by (q.cc <> 'AU') desc, q.n desc, q.provider_id limit greatest(0, p_keep - v_pending)
    on conflict do nothing;
    get diagnostics v_added = row_count;
  end if;
  return jsonb_build_object('pending_before', v_pending, 'added', v_added);
end $function$
