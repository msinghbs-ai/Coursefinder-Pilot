-- CF-247 v2.15.265 (Platform Admin, 13 Oct 2026: "learn and establish how best to find the uni official website ... use training.gov.au
-- or ASQA, CRICOS/RTO code, flag the exceptions"): the 124 active Australian providers with no website on record are searched again now
-- with worker v0.21.6, which looks them up on training.gov.au and the TEQSA National Register before the CRICOS-code search. Largest first
-- (svc_coverage_site_next orders by request time, then active courses). Data only; nothing dropped or deleted.
update pipeline.coverage_provider_discovery d set site_searched_at = null, requested_at = now(), leased_until = null, updated_at = now()
  from catalogue.providers p
 where p.id = d.provider_id and p.lifecycle_status = 'active' and nullif(btrim(p.website), '') is null
   and d.status = 'no_website' and security.coverage_country(d.provider_id) = 'AU';

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('firecrawl', 'official_site_requeue', 'v2.15.265',
        jsonb_build_object('requeued', (select count(*) from pipeline.coverage_provider_discovery d where d.status = 'no_website' and d.site_searched_at is null
                                          and security.coverage_country(d.provider_id) = 'AU'), 'worker', 'coverage-sweep-worker-v0.21.6', 'change', 'CF-247 v2.15.265'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
