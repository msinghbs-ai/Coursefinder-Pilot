-- Cases shaped on what production holds on 8 Nov 2026 (read only, 03:00-03:30 UTC): an Australian university searched with a successful map and nothing kept, one
-- whose "search" was a budget refusal (map:budget), providers out of scope for each reason the refill names, an in-scope provider never queued, and the suggested
-- listing pages and failed candidate pages the two new jobs act on. Fixed ids so the cases can name them.
insert into ref.countries(id, iso_alpha2, scholarship_ingestion_enabled) values ('00000000-0000-0000-0000-0000000000a1', 'AU', true), ('00000000-0000-0000-0000-0000000000a2', 'CA', true);
insert into ref.provider_types(id, code) values ('00000000-0000-0000-0000-0000000000b1', 'university'), ('00000000-0000-0000-0000-0000000000b3', 'private_vet')
  on conflict do nothing;
insert into catalogue.providers(id, canonical_name, display_name, country_id, provider_type_id, provider_type_basis, lifecycle_status, website) values
 ('20000000-0000-0000-0000-000000000001', 'Alpha University', 'Alpha', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'TEQSA register', 'active', 'https://www.alpha.edu.au'),
 ('20000000-0000-0000-0000-000000000002', 'Beta University', 'Beta', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'TEQSA register', 'active', 'https://www.beta.edu.au'),
 ('20000000-0000-0000-0000-000000000003', 'Gamma Career College', 'Gamma', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b3', 'x', 'active', 'https://www.gamma.ca'),
 ('20000000-0000-0000-0000-000000000004', 'Delta University', 'Delta', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'TEQSA register', 'active', null),
 ('20000000-0000-0000-0000-000000000005', 'Epsilon University', 'Epsilon', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'TEQSA register', 'active', 'https://www.epsilon.edu.au'),
 ('20000000-0000-0000-0000-000000000006', 'Zeta University', 'Zeta', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'TEQSA register', 'active', 'https://www.zeta.edu.au'),
 ('20000000-0000-0000-0000-000000000007', 'Eta University', 'Eta', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'TEQSA register', 'active', 'https://www.eta.edu.au'),
 ('20000000-0000-0000-0000-000000000008', 'Theta University', 'Theta', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'TEQSA register', 'active', 'https://www.theta.edu.au'),
 ('20000000-0000-0000-0000-000000000009', 'Iota University', 'Iota', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'TEQSA register', 'active', 'https://www.iota.edu.au'),
 ('20000000-0000-0000-0000-000000000010', 'Kappa University', 'Kappa', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'TEQSA register', 'active', 'https://www.kappa.edu.au'),
 ('20000000-0000-0000-0000-000000000011', 'Lambda Career College', 'Lambda', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b3', 'x', 'active', 'https://www.lambda.ca'),
 ('20000000-0000-0000-0000-000000000012', 'Mu University', 'Mu', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'TEQSA register', 'active', 'https://www.mu.edu.au');
-- every provider but Epsilon has an active course
insert into catalogue.courses(id, provider_id, lifecycle_status)
select gen_random_uuid(), p.id, 'active' from catalogue.providers p where p.id::text not like '20000000-0000-0000-0000-000000000005';
-- discovery rows: Alpha searched (successful map, nothing kept); Beta "empty" only because the map was refused for budget; Eta not eligible by policy
insert into pipeline.scholarship_discovery_providers(provider_id, website, site_origin, priority, status, method, url_count, kept_count, allowed_hosts, discovered_at, next_discover_at) values
 ('20000000-0000-0000-0000-000000000001', 'https://www.alpha.edu.au', 'https://www.alpha.edu.au', 0, 'empty', 'map_search(40)', 40, 0, '{}', now() - interval '20 days', now() + interval '10 days'),
 ('20000000-0000-0000-0000-000000000002', 'https://www.beta.edu.au', 'https://www.beta.edu.au', 0, 'empty', 'map:budget', 0, 0, '{}', now() - interval '26 days', now() + interval '4 days'),
 ('20000000-0000-0000-0000-000000000007', 'https://www.eta.edu.au', 'https://www.eta.edu.au', 0, 'not_eligible', null, 0, 0, '{}', now() - interval '20 days', null),
 ('20000000-0000-0000-0000-000000000008', 'https://www.theta.edu.au', 'https://www.theta.edu.au', 0, 'mapped', 'map_search(60)', 60, 4, '{}', now() - interval '20 days', now() + interval '10 days'),
 ('20000000-0000-0000-0000-000000000009', 'https://www.iota.edu.au', 'https://www.iota.edu.au', 0, 'mapped', 'map_search(60)', 60, 4, '{}', now() - interval '20 days', now() + interval '10 days'),
 ('20000000-0000-0000-0000-000000000010', 'https://www.kappa.edu.au', 'https://www.kappa.edu.au', 0, 'mapped', 'map_search(60)', 60, 4, '{}', now() - interval '20 days', now() + interval '10 days');
-- Iota's scholarship search is switched off by a person
insert into pipeline.provider_scholarship_search(provider_id, enabled, auto, reason) values ('20000000-0000-0000-0000-000000000009', false, false, 'fixture: switched off');

-- suggested listing pages (ids 1..8)
insert into pipeline.scholarship_listing_pages(provider_id, url, url_norm, source, active, status, added_at) values
 ('20000000-0000-0000-0000-000000000008', 'https://www.theta.edu.au/scholarships', security.scholarship_url_norm('https://www.theta.edu.au/scholarships'), 'suggested', false, 'suggested', now() - interval '28 days'),
 ('20000000-0000-0000-0000-000000000008', 'https://www.theta.edu.au/scholarships/int', security.scholarship_url_norm('https://www.theta.edu.au/scholarships/int'), 'suggested', false, 'suggested', now() - interval '27 days'),
 ('20000000-0000-0000-0000-000000000008', 'https://www.theta.edu.au/scholarships/research', security.scholarship_url_norm('https://www.theta.edu.au/scholarships/research'), 'suggested', false, 'suggested', now() - interval '26 days'),
 ('20000000-0000-0000-0000-000000000008', 'https://www.theta.edu.au/scholarships/other', security.scholarship_url_norm('https://www.theta.edu.au/scholarships/other'), 'suggested', false, 'suggested', now() - interval '25 days'),
 ('20000000-0000-0000-0000-000000000009', 'https://www.iota.edu.au/scholarships', security.scholarship_url_norm('https://www.iota.edu.au/scholarships'), 'suggested', false, 'suggested', now() - interval '28 days'),
 ('20000000-0000-0000-0000-000000000003', 'https://www.gamma.ca/scholarships', security.scholarship_url_norm('https://www.gamma.ca/scholarships'), 'suggested', false, 'suggested', now() - interval '28 days'),
 ('20000000-0000-0000-0000-000000000010', 'https://www.kappa.edu.au/scholarships', security.scholarship_url_norm('https://www.kappa.edu.au/scholarships'), 'suggested', false, 'suggested', now() - interval '28 days'),
 ('20000000-0000-0000-0000-000000000010', 'https://scholarships.example-directory.com/kappa', security.scholarship_url_norm('https://scholarships.example-directory.com/kappa'), 'suggested', false, 'suggested', now() - interval '28 days');
-- a listing source already accepted (id 9), for the unchanged-catalogue cases
insert into pipeline.scholarship_listing_pages(provider_id, url, url_norm, source, active, status, added_at) values
 ('20000000-0000-0000-0000-000000000006', 'https://www.zeta.edu.au/scholarships', security.scholarship_url_norm('https://www.zeta.edu.au/scholarships'), 'auto', true, 'waiting', now() - interval '20 days');

-- candidate pages (ids 1..): Theta's transient failures and the cases around them
insert into pipeline.scholarship_page_candidates(provider_id, url, url_norm, title, source, read_status, http_status, read_at, attempts, next_read_at, admit_status) values
 ('20000000-0000-0000-0000-000000000008', 'https://www.theta.edu.au/scholarships/a', 'theta.edu.au/scholarships/a', 'A', 'map', 'scrape_failed', 500, now() - interval '3 days', 3, now() - interval '2 days', null),
 ('20000000-0000-0000-0000-000000000008', 'https://www.theta.edu.au/scholarships/b', 'theta.edu.au/scholarships/b', 'B', 'map', 'scrape_failed', 402, now() - interval '3 days', 3, now() - interval '2 days', null),
 ('20000000-0000-0000-0000-000000000008', 'https://www.theta.edu.au/scholarships/c', 'theta.edu.au/scholarships/c', 'C', 'map', 'scrape_failed', 500, now() - interval '1 hour', 3, now() - interval '1 hour', null),
 ('20000000-0000-0000-0000-000000000008', 'https://www.theta.edu.au/scholarships/d', 'theta.edu.au/scholarships/d', 'D', 'map', 'blocked', 403, now() - interval '3 days', 3, now() - interval '2 days', null),
 ('20000000-0000-0000-0000-000000000008', 'https://www.theta.edu.au/scholarships/e', 'theta.edu.au/scholarships/e', 'E', 'map', 'gone', 404, now() - interval '3 days', 3, now() - interval '2 days', null),
 ('20000000-0000-0000-0000-000000000008', 'https://www.theta.edu.au/scholarships/f', 'theta.edu.au/scholarships/f', 'F', 'map', 'scrape_failed', 500, now() - interval '9 days', 3, now() - interval '8 days', null),
 ('20000000-0000-0000-0000-000000000008', 'https://www.theta.edu.au/scholarships/g', 'theta.edu.au/scholarships/g', 'G', 'map', 'scrape_failed', null, now() - interval '3 days', 3, now() - interval '2 days', null),
 ('20000000-0000-0000-0000-000000000008', 'https://www.theta.edu.au/scholarships/h', 'theta.edu.au/scholarships/h', 'H', 'map', 'scrape_failed', 408, now() - interval '3 days', 3, now() - interval '2 days', null),
 ('20000000-0000-0000-0000-000000000008', 'https://www.theta.edu.au/scholarships/i', 'theta.edu.au/scholarships/i', 'I', 'map', 'read', 200, now() - interval '1 hour', 1, now() + interval '90 days', null),
 ('20000000-0000-0000-0000-000000000003', 'https://www.gamma.ca/scholarships/a', 'gamma.ca/scholarships/a', 'GA', 'map', 'scrape_failed', 500, now() - interval '3 days', 3, now() - interval '2 days', null),
 ('20000000-0000-0000-0000-000000000009', 'https://www.iota.edu.au/scholarships/a', 'iota.edu.au/scholarships/a', 'IA', 'map', 'scrape_failed', 500, now() - interval '3 days', 3, now() - interval '2 days', null),
 ('20000000-0000-0000-0000-000000000010', 'https://coursesearch.studymelbourne.vic.gov.au/kappa/a', 'coursesearch.studymelbourne.vic.gov.au/kappa/a', 'KA', 'map', 'scrape_failed', 500, now() - interval '3 days', 3, now() - interval '2 days', null);
