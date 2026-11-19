CREATE OR REPLACE FUNCTION security.provider_description_machine_report_v1(p_detail integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_out jsonb;
begin
  select jsonb_build_object(
    'contract', 'provider-description-machine-report-v1', 'as_at', now(),
    'providers', (select jsonb_object_agg(z.cc, jsonb_build_object('providers', z.n, 'live', z.live, 'described', z.described, 'machine_admitted', z.machine, 'website_verified', z.web, 'zoho_verified', z.zoho))
                    from (select k.iso_alpha2::text cc, count(*) n, count(*) filter (where p.lifecycle_status = 'active' and p.publication_status = 'published') live,
                                 count(*) filter (where nullif(btrim(p.description), '') is not null) described,
                                 count(a.id) machine,
                                 count(*) filter (where (rd.consumer_checks->>'website_verified')::boolean) web, count(*) filter (where (rd.consumer_checks->>'zoho_verified')::boolean) zoho
                            from catalogue.providers p join ref.countries k on k.id = p.country_id
                            left join pipeline.provider_description_machine_admissions a on a.provider_id = p.id and a.outcome = 'admitted' and a.withdrawn_at is null
                            left join pipeline.provider_description_reads rd on rd.id = a.read_id
                           group by k.iso_alpha2) z),
    'tiers', (select coalesce(jsonb_object_agg(t.tier, t.n), '{}'::jsonb) from (select tier, count(*) n from pipeline.provider_description_machine_admissions where outcome = 'admitted' and withdrawn_at is null group by tier) t),
    'declined', (select coalesce(jsonb_object_agg(d.reason_key, d.n), '{}'::jsonb) from (select split_part(reason, ' (', 1) reason_key, count(*) n from pipeline.provider_description_machine_admissions where outcome = 'declined' group by 1) d),
    'holds', (select coalesce(jsonb_object_agg(h.rule, h.n), '{}'::jsonb) from (select x.rule, count(*) n from pipeline.provider_description_reads x where x.state = 'held' and (x.rule like 'machine_declined%' or x.rule = 'insufficient_verified_facts') group by x.rule) h),
    'parity', (select jsonb_build_object('admitted', count(*), 'website_verified', count(*) filter (where (rd.consumer_checks->>'website_verified')::boolean), 'zoho_verified', count(*) filter (where (rd.consumer_checks->>'zoho_verified')::boolean),
                 'not_yet_checked', count(*) filter (where rd.consumer_checked_at is null),
                 'mismatched', coalesce((select jsonb_agg(jsonb_build_object('provider_id', m.provider_id, 'website', (m.consumer_checks->>'website_verified'), 'zoho', (m.consumer_checks->>'zoho_verified')) )
                                           from (select a2.provider_id, rd2.consumer_checks from pipeline.provider_description_machine_admissions a2 join pipeline.provider_description_reads rd2 on rd2.id = a2.read_id
                                                  where a2.outcome = 'admitted' and a2.withdrawn_at is null and rd2.consumer_checked_at is not null
                                                    and not (coalesce((rd2.consumer_checks->>'website_verified')::boolean, false) and coalesce((rd2.consumer_checks->>'zoho_verified')::boolean, false)) limit greatest(coalesce(p_detail, security.pipeline_num_v1('pdesc.report_detail', 20)::int), 0)) m), '[]'::jsonb))
                 from pipeline.provider_description_machine_admissions a join pipeline.provider_description_reads rd on rd.id = a.read_id where a.outcome = 'admitted' and a.withdrawn_at is null),
    'throughput', security.provider_description_throughput_v1()) into v_out;
  return v_out;
end $function$
