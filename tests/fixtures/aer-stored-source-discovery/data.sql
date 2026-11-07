-- Fixture data for the AER stored-source discovery cases (invented providers and links; nothing is live data).
create schema if not exists fx;
create function fx.ok(c boolean, msg text) returns void language plpgsql as $f$ begin if not coalesce(c, false) then raise exception 'FAIL: %', msg; end if; end $f$;
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values
  ('pipeline', 'aer.eligible_countries', 'list', '["AU", "NZ"]'), ('pipeline', 'entry.matrix_enabled', 'number', '1'), ('pipeline', 'entry.countries', 'list', '["AU", "NZ"]'),
  ('pipeline', 'entry.attach_per_provider', 'number', '3'), ('pipeline', 'central.min_suggest_score', 'number', '4'), ('pipeline', 'fixture.countries_off', 'list', '["NZ"]');
-- the scheduled reading is on (job aer-scheduled-read active): the condition under which the first-page gate became circular
insert into cron.job(jobname, schedule, command, active) values ('aer-scheduled-read', '13 * * * *', 'select 1', true);
insert into pipeline.important_links(domain, uses, authority_category) values ('directory.example', array['not_provider_site'], 'third_party_directory');
-- AU 'a1' alpha: several links; 'b2' beta and 'c3' gamma share one website; 'd4' delta weak links only; 'e5' epsilon none; 'f6' zeta has a source;
-- 'g7' eta hidden; 'h8' theta on a third-party host; 'i9' iota is NZ (country off for scheduled reading); 'j0' kappa is Canada (not AER-eligible); 'l1' lambda a PDF only; 'm2' mu suggestion only
insert into catalogue.providers(id, canonical_name, website, country_id) select v.id::uuid, v.n, v.w, (select id from ref.countries where iso_alpha2 = v.c) from (values
  ('d1000000-0000-4000-8000-0000000000a1', 'Alpha University', 'https://www.alpha.edu.au', 'AU'),
  ('d1000000-0000-4000-8000-0000000000b2', 'Beta College', 'https://www.shared.edu.au', 'AU'),
  ('d1000000-0000-4000-8000-0000000000c3', 'Gamma Institute', 'https://shared.edu.au/gamma', 'AU'),
  ('d1000000-0000-4000-8000-0000000000d4', 'Delta Institute', 'https://www.delta.edu.au', 'AU'),
  ('d1000000-0000-4000-8000-0000000000e5', 'Epsilon College', 'https://www.epsilon.edu.au', 'AU'),
  ('d1000000-0000-4000-8000-0000000000f6', 'Zeta College', 'https://www.zeta.edu.au', 'AU'),
  ('d1000000-0000-4000-8000-0000000000a7', 'Eta College', 'https://www.eta.edu.au', 'AU'),
  ('d1000000-0000-4000-8000-0000000000a8', 'Theta College', 'https://www.directory.example/theta', 'AU'),
  ('d1000000-0000-4000-8000-0000000000a9', 'Iota Polytechnic', 'https://www.iota.ac.nz', 'NZ'),
  ('d1000000-0000-4000-8000-0000000000a0', 'Kappa College', 'https://www.kappa.ca', 'CA'),
  ('d1000000-0000-4000-8000-0000000000b1', 'Lambda College', 'https://www.lambda.edu.au', 'AU'),
  ('d1000000-0000-4000-8000-0000000000b3', 'Mu College', 'https://www.mu.edu.au', 'AU')) v(id, n, w, c);
insert into catalogue.courses(provider_id) select 'd1000000-0000-4000-8000-0000000000a1'::uuid from generate_series(1, 5);   -- alpha has most courses: looked at first
insert into catalogue.courses(provider_id) select 'd1000000-0000-4000-8000-0000000000d4'::uuid from generate_series(1, 2);
insert into security.provider_hidden_v1 values ('d1000000-0000-4000-8000-0000000000a7');
insert into pipeline.entry_matrix_sources(provider_id, url, found_via) values ('d1000000-0000-4000-8000-0000000000f6', 'https://www.zeta.edu.au/already', 'manual');
insert into pipeline.provider_discovery_links(provider_id, url, anchor_text, pages) values
  ('d1000000-0000-4000-8000-0000000000a1', 'https://www.alpha.edu.au/international/academic-entry-requirements', 'Academic entry requirements', 12),
  ('d1000000-0000-4000-8000-0000000000a1', 'https://www.alpha.edu.au/admissions/overseas-qualifications', 'Overseas qualifications', 4),
  ('d1000000-0000-4000-8000-0000000000a1', 'https://www.alpha.edu.au/international/entry-requirements', 'Entry requirements', 2),
  ('d1000000-0000-4000-8000-0000000000a1', 'https://study.alpha.edu.au/international/entry-requirements-by-country', 'Entry requirements by country', 1),
  ('d1000000-0000-4000-8000-0000000000a1', 'https://www.alpha.edu.au/study/international/entry-requirements', 'Entry requirements', 9),
  ('d1000000-0000-4000-8000-0000000000a1', 'https://www.alpha.edu.au/english-language-requirements', 'English requirements', 9),
  ('d1000000-0000-4000-8000-0000000000a1', 'https://other.example.org/international/academic-entry-requirements', 'Academic entry requirements', 3),
  ('d1000000-0000-4000-8000-0000000000a1', 'https://www.alpha.edu.au.evil.com/international/academic-entry-requirements', 'Academic entry requirements', 3),
  ('d1000000-0000-4000-8000-0000000000a1', 'https://www.alpha.edu.au/news/entry-requirements-change', 'Entry requirements change', 1),
  ('d1000000-0000-4000-8000-0000000000b2', 'https://www.shared.edu.au/international/academic-entry-requirements', 'Academic entry requirements', 3),
  ('d1000000-0000-4000-8000-0000000000c3', 'https://shared.edu.au/international/academic-entry-requirements', 'Academic entry requirements', 3),
  ('d1000000-0000-4000-8000-0000000000d4', 'https://www.delta.edu.au/entry-requirements', 'Entry requirements', 2),
  ('d1000000-0000-4000-8000-0000000000d4', 'https://www.delta.edu.au/courses/diploma-of-business', 'Diploma of Business', 2),
  ('d1000000-0000-4000-8000-0000000000a7', 'https://www.eta.edu.au/international/academic-entry-requirements', 'Academic entry requirements', 2),
  ('d1000000-0000-4000-8000-0000000000a8', 'https://www.directory.example/theta/international/academic-entry-requirements', 'Academic entry requirements', 2),
  ('d1000000-0000-4000-8000-0000000000a9', 'https://www.iota.ac.nz/international/academic-entry-requirements', 'Academic entry requirements', 2),
  ('d1000000-0000-4000-8000-0000000000a0', 'https://www.kappa.ca/international/academic-entry-requirements', 'Academic entry requirements', 2),
  ('d1000000-0000-4000-8000-0000000000b1', 'https://www.lambda.edu.au/files/international-entry-requirements.pdf', 'Download', 3);
insert into pipeline.coverage_provider_urls(provider_id, url, title) values
  ('d1000000-0000-4000-8000-0000000000a1', 'https://alpha.edu.au/international/academic-entry-requirements/', null),
  ('d1000000-0000-4000-8000-0000000000a1', 'https://www.alpha.edu.au/courses/bachelor-of-arts', 'Bachelor of Arts'),
  ('d1000000-0000-4000-8000-0000000000d4', 'https://www.delta.edu.au/courses/certificate-iv', 'Certificate IV');
-- a central-find suggestion for a provider with no entry page (what job central-find writes once it has run for page type entry_requirements)
insert into pipeline.provider_central_search(provider_id, state, found) values
  ('d1000000-0000-4000-8000-0000000000b3', 'done', '[{"kind": "entry_requirements", "url": "https://www.mu.edu.au/international/academic-entry-requirements", "title": "Academic entry requirements", "score": 8.6}]');
