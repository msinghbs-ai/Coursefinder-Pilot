-- Guards: F-PDESC (Platform Admin decision 9 Nov 2026, QA B2): the whole-platform reader stays inside the statement time-outs (authenticated 8 s, server 120 s) at the real catalogue size.
-- Fictional data only: 3,103 providers in the live proportions (AU 1,556, NZ 417, CA 1,130; CA with no type), 2,323 with a website, 750 holding a stored About page, an active register listing each,
-- and the live indexes' shape. Added to the scratch database by tests/fixtures/pdesc-machine/run.sh; every row is a fixture.
set client_min_messages = warning;
-- the live indexes the reader's lookups use (read 9 Nov 2026), so the timings are not flattered by a missing index or hurt by one the live table has
create index if not exists provider_description_reads_provider_idx on pipeline.provider_description_reads (provider_id, created_at desc);
create index if not exists provider_description_reads_state_idx on pipeline.provider_description_reads (state, next_try_at);
create unique index if not exists provider_description_reads_open_uq on pipeline.provider_description_reads (provider_id) where state in ('queued', 'reading', 'proposed');
create index if not exists pipeline_sources_provider_idx on pipeline.sources (provider_id);
create index if not exists evidence_source_idx on pipeline.evidence_artifacts (source_id);
create index if not exists evidence_artifacts_source_url_pattern_idx on pipeline.evidence_artifacts (lower(source_url) text_pattern_ops);
create index if not exists provider_registrations_provider_idx on catalogue.provider_registrations (provider_id);
create index if not exists layer4_review_items_entity_field_iq_idx on pipeline.layer4_review_items (entity_id, field_code, status);
create index if not exists providers_country_pub_idx on catalogue.providers (country_id, publication_status);
insert into ref.provider_types(id, code, name) values
  ('00000000-0000-0000-0000-0000000000b3', 'private_vet', 'Private VET provider'), ('00000000-0000-0000-0000-0000000000b4', 'school', 'School'),
  ('00000000-0000-0000-0000-0000000000b5', 'tafe', 'TAFE'), ('00000000-0000-0000-0000-0000000000b6', 'other', 'Other') on conflict do nothing;
do $$
declare n int; pid uuid; sid uuid; eid uuid; cc uuid; ccode text; ky text; tp uuid; web text; nm text; scheme text; k int := 0;
begin
  for n in 1 .. 3103 loop
    -- live proportions: the first 1,556 are Australian, the next 417 New Zealand, the rest Canadian
    ccode := case when n <= 1556 then 'AU' when n <= 1973 then 'NZ' else 'CA' end;
    cc := ('00000000-0000-0000-0000-0000000000a' || case ccode when 'AU' then '1' when 'NZ' then '2' else '3' end)::uuid;
    tp := case when ccode = 'CA' then null else (array['00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000b4',
          '00000000-0000-0000-0000-0000000000b5', '00000000-0000-0000-0000-0000000000b6', '00000000-0000-0000-0000-0000000000b1'])[1 + n % 7]::uuid end;
    web := case when (ccode = 'AU' and n % 100 < 93) or (ccode = 'NZ' and n % 100 < 97) or (ccode = 'CA' and n % 100 < 42) then 'https://s' || n || '.example.edu' end;
    pid := ('20000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid;
    ky := 'scale:provider:' || n;
    nm := 'Scale Provider ' || n || case when tp = '00000000-0000-0000-0000-0000000000b1' then ' University' else ' Institute' end;
    insert into pim.entity_registry(id) values (pid);
    insert into catalogue.providers(id, stable_key, canonical_name, website, country_id, provider_type_id, lifecycle_status, publication_status, primary_city)
    values (pid, ky, nm, web, cc, tp, 'active', 'published', case when n % 3 = 0 then 'Scaletown' end);
    if n % 4 = 0 then insert into catalogue.courses(id, provider_id, canonical_title, lifecycle_status) select gen_random_uuid(), pid, 'Scale programme ' || g, 'active' from generate_series(1, 3) g; end if;
    scheme := case ccode when 'AU' then 'cricos' when 'NZ' then 'nzqa' else 'ircc_dli' end;
    -- the register listing and its stored evidence
    insert into pipeline.sources(source_type, provider_id, label, url) values ('provider_register', pid, 'Register listing', 'https://register.example.org/' || n) returning id into sid;
    insert into pipeline.evidence_artifacts(source_id, evidence_type, source_url, storage_path, content_hash, mime_type, captured_at)
    values (sid, 'page', 'https://register.example.org/' || n, 'fixture/register-' || n || '.html', md5('reg' || n) || md5('reg2' || n), 'text/html', now()) returning id into eid;
    insert into catalogue.provider_registrations(provider_id, registration_scheme, registration_code, provider_classification, status, checked_at, source_id, evidence_id)
    values (pid, scheme, 'SC' || lpad(n::text, 6, '0'), 'Fictional', 'active', now(), sid, eid);
    -- 750 providers (about one in four of those with a website) hold a stored official About page
    if web is not null and n % 3 = 1 and k < 750 then
      k := k + 1;
      insert into pipeline.sources(source_type, provider_id, label, url) values ('provider_course_page_sweep', pid, 'Stored institutional About page', web || '/about') returning id into sid;
      insert into pipeline.evidence_artifacts(source_id, evidence_type, source_url, storage_path, content_hash, mime_type, captured_at)
      values (sid, 'page', web || '/about', 'fixture/about-s' || n || '.html', md5('about' || n) || md5('about2' || n), 'text/html', now());
    end if;
  end loop;
  raise notice 'scale fixture: % providers, % stored About pages', (select count(*) from catalogue.providers where stable_key like 'scale:%'), k;
end $$;
analyze;
