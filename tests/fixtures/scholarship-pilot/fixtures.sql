-- CF-247 scholarships beyond universities: behaviour after the 20261103090000 migration (applied unchanged by run.sh). Every case prints
-- "ok <case>" or stops with an error. Providers are synthetic; the rules are the live definitions (rebuilt and md5-checked by run.sh).
create function fx_ok(p_case text, p_cond boolean, p_detail text default '') returns void language plpgsql as
$f$ begin if p_cond is not true then raise exception 'FAILED %: %', p_case, p_detail; end if; raise notice 'ok %', p_case; end $f$;
create function fx_set(p_key text, p_value jsonb) returns void language sql as
$f$ update pipeline.platform_toolset_settings set value = p_value, updated_at = clock_timestamp() where toolset_key = 'pipeline' and key = p_key $f$;

insert into ref.countries(id, iso_alpha2, scholarship_ingestion_enabled) values ('00000000-0000-0000-0000-0000000000a1', 'AU', true),
  ('00000000-0000-0000-0000-0000000000a2', 'NZ', true), ('00000000-0000-0000-0000-0000000000a3', 'CA', true);
insert into ref.provider_types(id, code, name, status) values ('00000000-0000-0000-0000-0000000000b1', 'university', 'University', 'active'),
  ('00000000-0000-0000-0000-0000000000b2', 'tafe_polytechnic', 'TAFE / Polytechnic', 'active'), ('00000000-0000-0000-0000-0000000000b3', 'school', 'School', 'active'),
  ('00000000-0000-0000-0000-0000000000b4', 'private_vet', 'Private VET college', 'active'), ('00000000-0000-0000-0000-0000000000b5', 'wananga', 'Wānanga', 'active');
-- A pilot TAFE (AU, 5 courses), B unlisted private VET (AU, 5 courses), C unlisted wānanga (NZ), D untyped Canadian provider, E listed school, U university
insert into catalogue.providers(id, canonical_name, country_id, website, provider_type_id, provider_type_basis, enrols_international) values
  ('00000000-0000-0000-0002-00000000000a', 'Pilot TAFE', '00000000-0000-0000-0000-0000000000a1', 'https://www.pilottafe.edu.au', '00000000-0000-0000-0000-0000000000b2', 'register', true),
  ('00000000-0000-0000-0002-00000000000b', 'Unlisted VET', '00000000-0000-0000-0000-0000000000a1', 'https://www.unlistedvet.edu.au', '00000000-0000-0000-0000-0000000000b4', 'register', true),
  ('00000000-0000-0000-0002-00000000000c', 'Unlisted Wananga', '00000000-0000-0000-0000-0000000000a2', 'https://www.wananga.ac.nz', '00000000-0000-0000-0000-0000000000b5', 'register', true),
  ('00000000-0000-0000-0002-00000000000d', 'Canadian College', '00000000-0000-0000-0000-0000000000a3', 'https://www.cacollege.ca', null, null, true),
  ('00000000-0000-0000-0002-00000000000e', 'Listed School', '00000000-0000-0000-0000-0000000000a1', 'https://www.school.edu.au', '00000000-0000-0000-0000-0000000000b3', 'register', true),
  ('00000000-0000-0000-0002-0000000000f1', 'Fixture University', '00000000-0000-0000-0000-0000000000a1', 'https://www.fixture.edu.au', '00000000-0000-0000-0000-0000000000b1', 'register', true);
insert into fx_groups values ('00000000-0000-0000-0002-0000000000f1');
insert into catalogue.courses(provider_id, course_code) select p.id, lpad(g::text, 6, '0') || 'A' from catalogue.providers p, generate_series(1, 5) g;
-- the pilot TAFE: mapped 10 days ago, next due in 20 days; three stored pages refused (two because it is not a university, one old)
insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status, url_count, kept_count, attempts, discovered_at, next_discover_at, tier) values
  ('00000000-0000-0000-0002-00000000000a', 'https://www.pilottafe.edu.au', 4, 'largest_unsearched', 'mapped', 40, 3, 0, now() - interval '10 days', now() + interval '20 days', 3),
  ('00000000-0000-0000-0002-00000000000b', 'https://www.unlistedvet.edu.au', 4, 'largest_unsearched', 'pending', 0, 0, 0, null, now() + interval '5 hours', 3);
insert into pipeline.scholarship_page_candidates(provider_id, url, url_norm, title, source, read_status, read_at, storage_path, final_url, facts, admit_status, admit_reasons) values
  ('00000000-0000-0000-0002-00000000000a', 'https://www.pilottafe.edu.au/international/merit-scholarship', 'https://www.pilottafe.edu.au/international/merit-scholarship', 'International Merit Scholarship', 'map', 'read', now() - interval '20 days', 'a.gz',
   'https://www.pilottafe.edu.au/international/merit-scholarship', '{"international": true, "admission": {"admit": true, "detail_page": true, "international_explicit": true, "offered": true, "name": "International Merit Scholarship"}}',
   'rejected', array['not a university provider in a scholarship country']),
  ('00000000-0000-0000-0002-00000000000a', 'https://www.pilottafe.edu.au/international/old-bursary', 'https://www.pilottafe.edu.au/international/old-bursary', 'Old International Bursary', 'map', 'read', now() - interval '200 days', 'b.gz',
   'https://www.pilottafe.edu.au/international/old-bursary', '{"international": true, "admission": {"admit": true, "detail_page": true, "international_explicit": true, "offered": true, "name": "Old International Bursary"}}',
   'rejected', array['not a university provider in a scholarship country']),
  ('00000000-0000-0000-0002-00000000000a', 'https://www.pilottafe.edu.au/domestic-grant', 'https://www.pilottafe.edu.au/domestic-grant', 'Domestic Equity Grant', 'map', 'read', now() - interval '20 days', 'c.gz',
   'https://www.pilottafe.edu.au/domestic-grant', '{"international": false, "admission": {"admit": false, "detail_page": true, "international_explicit": false, "offered": true, "name": "Domestic Equity Grant"}}',
   'rejected', array['not explicitly open to international students']);

-- shipped: the list is empty, pilot only, both proposals off
do $$
begin
  perform fx_ok('shipped: list empty, pilot only on, proposals off; the pilot does not start', security.toolset_setting('pipeline', 'scholarship.pilot_provider_ids') = '[]'::jsonb
    and security.scholarship_flag_v1('scholarship.pilot_only', false) and not security.scholarship_flag_v1('scholarship.non_university_admission', true)
    and not security.scholarship_flag_v1('scholarship.legitimacy_checks_on', true) and not (security.scholarship_pilot_start_v1()->>'pilot')::boolean);
  perform fx_ok('shipped: universities only, the course minimum (as today)', security.scholarship_admission_provider_ok_v1('00000000-0000-0000-0002-0000000000f1')
    and not security.scholarship_admission_provider_ok_v1('00000000-0000-0000-0002-00000000000a') and not security.fc_sch_eligible_v1('00000000-0000-0000-0002-00000000000a')
    and security.fc_sch_eligible_v1('00000000-0000-0000-0002-00000000000d') and security.fc_sch_eligible_v1('00000000-0000-0000-0002-00000000000c'));
end $$;

-- both proposals on with the list empty: nobody is affected (exactly today's rules)
do $$
begin
  perform fx_set('scholarship.non_university_admission', 'true'); perform fx_set('scholarship.legitimacy_checks_on', 'true');
  perform fx_ok('empty list = nobody: a TAFE is not admitted, the course minimum holds', not security.scholarship_admission_provider_ok_v1('00000000-0000-0000-0002-00000000000a')
    and not security.fc_sch_eligible_v1('00000000-0000-0000-0002-00000000000a') and not security.scholarship_admission_provider_ok_v1('00000000-0000-0000-0002-00000000000c'));
  perform fx_ok('empty list = nobody: an untyped Canadian provider is still searched (P2 globally would stop it)', security.fc_sch_eligible_v1('00000000-0000-0000-0002-00000000000d'));
  perform fx_ok('empty list = nobody: the pilot does not start, tiers unchanged', not (security.scholarship_pilot_start_v1()->>'pilot')::boolean
    and security.fc_provider_tier_v1('00000000-0000-0000-0002-00000000000a') = 3);
end $$;

-- the pilot: the TAFE and a school listed (saved on Settings, its own transaction: the pilot measurement starts here)
select fx_set('scholarship.pilot_provider_ids', '["00000000-0000-0000-0002-00000000000a", "00000000-0000-0000-0002-00000000000e"]');
do $$
declare r jsonb;
begin
  perform fx_ok('pilot: a listed TAFE is admitted and searched by the legitimacy checks', security.scholarship_admission_provider_ok_v1('00000000-0000-0000-0002-00000000000a')
    and security.fc_sch_eligible_v1('00000000-0000-0000-0002-00000000000a'));
  perform fx_ok('pilot: providers not listed keep today''s rules', not security.scholarship_admission_provider_ok_v1('00000000-0000-0000-0002-00000000000b')
    and not security.fc_sch_eligible_v1('00000000-0000-0000-0002-00000000000b') and not security.scholarship_admission_provider_ok_v1('00000000-0000-0000-0002-00000000000c')
    and security.fc_sch_eligible_v1('00000000-0000-0000-0002-00000000000d'));
  perform fx_ok('pilot: a listed school is never admitted or searched', not security.scholarship_admission_provider_ok_v1('00000000-0000-0000-0002-00000000000e')
    and not security.fc_sch_eligible_v1('00000000-0000-0000-0002-00000000000e'));
  perform fx_ok('pilot: a listed provider is first in the discovery order', security.fc_provider_tier_v1('00000000-0000-0000-0002-00000000000a') = 0
    and security.fc_provider_tier_v1('00000000-0000-0000-0002-00000000000b') = 3);
  r := security.scholarship_discovery_refill_v1(0);
  perform fx_ok('pilot start (hourly refill): one fresh discovery, the recent refused page admitted again; the school is not queued', (r->'pilot'->>'due')::int = 1
    and (r->'pilot'->>'readmitted')::int = 1 and (r->'pilot'->>'admitted')::int = 1 and (r->'pilot'->>'queued')::int = 0
    and (select next_discover_at <= now() and tier = 0 from pipeline.scholarship_discovery_providers where provider_id = '00000000-0000-0000-0002-00000000000a')
    and not exists (select 1 from pipeline.scholarship_discovery_providers where provider_id = '00000000-0000-0000-0002-00000000000e'), r::text);
  perform fx_ok('pilot start: the old page and the page refused for another reason are left alone; the record starts unpublished',
    (select admit_status from pipeline.scholarship_page_candidates where title = 'Old International Bursary') = 'rejected'
    and (select admit_status from pipeline.scholarship_page_candidates where title = 'Domestic Equity Grant') = 'rejected'
    and (select publication_status from scholarship.scholarships where name = 'International Merit Scholarship') = 'unpublished');
  insert into pipeline.scholarship_page_candidates(provider_id, url, url_norm, title, source, read_status, read_at, storage_path, final_url, facts) values
    ('00000000-0000-0000-0002-00000000000a', 'https://www.pilottafe.edu.au/international/australia-awards', 'https://www.pilottafe.edu.au/international/australia-awards', 'Australia Awards Scholarships', 'map', 'read', now(), 'd.gz',
     'https://www.pilottafe.edu.au/international/australia-awards', '{"international": true, "admission": {"admit": true, "detail_page": true, "international_explicit": true, "offered": true, "name": "Australia Awards Scholarships"}}');
  r := security.scholarship_admit_from_provider_page_v1((select id from pipeline.scholarship_page_candidates where title = 'Australia Awards Scholarships'));
  perform fx_ok('award source: a college''s page naming a government award is refused as an award of another body', r->>'reason' = 'award of another body', r::text);
  insert into pipeline.scholarship_page_candidates(provider_id, url, url_norm, title, source, read_status, read_at, storage_path, final_url, facts) values
    ('00000000-0000-0000-0002-0000000000f1', 'https://www.fixture.edu.au/scholarships/university-of-fixture-award', 'https://www.fixture.edu.au/scholarships/university-of-fixture-award', 'University of Fixture International Award', 'map', 'read', now(), 'e.gz',
     'https://www.fixture.edu.au/scholarships/university-of-fixture-award', '{"international": true, "admission": {"admit": true, "detail_page": true, "international_explicit": true, "offered": true, "name": "University of Fixture International Award"}}');
  r := security.scholarship_admit_from_provider_page_v1((select id from pipeline.scholarship_page_candidates where title = 'University of Fixture International Award'));
  perform fx_ok('award source: universities are unchanged (a university''s own "University of" award is admitted)', (r->>'admitted')::boolean, r::text);
  r := security.scholarship_discovery_refill_v1(0);
  perform fx_ok('pilot start runs once: a second refill changes nothing', (r->'pilot'->>'due')::int = 0 and (r->'pilot'->>'readmitted')::int = 0, r::text);
end $$;

-- the stop conditions
do $$
declare s jsonb; v_sid uuid;
begin
  perform fx_ok('report: the listed providers, one admission, no stop', (select count(*) from security.scholarship_pilot_report_v1()) = 2
    and (select admitted = 1 and wrong_provider = 0 and unsupported_eligibility = 0 and not stop from security.scholarship_pilot_report_v1() where provider_name = 'Pilot TAFE')
    and not (security.scholarship_pilot_stop_v1()->>'stop')::boolean, (select jsonb_agg(r)::text from security.scholarship_pilot_report_v1() r));
  -- wrong provider: an admitted record whose page is not on the provider's sites
  v_sid := gen_random_uuid();
  insert into scholarship.scholarships(id, provider_id, name, audience, source_url, lifecycle_status, publication_status) values
    (v_sid, '00000000-0000-0000-0002-00000000000a', 'Partner University Scholarship', 'international', 'https://www.partneruni.com/scholarship', 'active', 'unpublished');
  insert into pipeline.scholarship_pages(scholarship_id, url, facts) values (v_sid, 'https://www.partneruni.com/scholarship', '{"admission": {"detail_page": true, "international_explicit": true, "offered": true}}');
  insert into pipeline.scholarship_admission_log(scholarship_id, provider_id, action, detail) values (v_sid, '00000000-0000-0000-0002-00000000000a', 'admitted', '{}');
  s := security.scholarship_pilot_stop_v1();
  perform fx_ok('stop 1: a wrong-provider admission stops the expansion', (s->>'stop')::boolean and (s->>'wrong_provider')::int = 1 and s->>'reasons' ~ 'wrong-provider', s::text);
  update scholarship.scholarships set source_url = 'https://www.pilottafe.edu.au/partner' where id = v_sid;
  insert into pipeline.layer4_block_decisions(entity_type, entity_id, reason_code) values ('scholarship', v_sid, 'wrong_provider');
  perform fx_ok('stop 1: a Layer 4 decision naming the provider counts too', (security.scholarship_pilot_stop_v1()->>'wrong_provider')::int = 1);
  delete from pipeline.layer4_block_decisions;
  -- unsupported eligibility: the page did not say it is explicitly open to international students
  update pipeline.scholarship_pages set facts = '{"admission": {"detail_page": true, "international_explicit": false, "offered": true}}' where scholarship_id = v_sid;
  s := security.scholarship_pilot_stop_v1();
  perform fx_ok('stop 2: an admission without eligibility evidence stops the expansion', (s->>'stop')::boolean and (s->>'unsupported_eligibility')::int = 1
    and (s->>'wrong_provider')::int = 0, s::text);
  update pipeline.scholarship_pages set facts = '{"admission": {"detail_page": true, "international_explicit": true, "offered": true}}' where scholarship_id = v_sid;
  perform fx_ok('stop: cleared when the evidence is there', not (security.scholarship_pilot_stop_v1()->>'stop')::boolean, security.scholarship_pilot_stop_v1()::text);
  -- budget: Firecrawl over 20% of the 3,500 daily scholarship share; AI over 20% of US$20
  insert into pipeline.coverage_vendor_usage(units, purpose, provider_id) values (800, 'sch_map', '00000000-0000-0000-0002-00000000000a');
  s := security.scholarship_pilot_stop_v1();
  perform fx_ok('stop 3: Firecrawl over the pilot share a day', (s->>'stop')::boolean and (s->>'firecrawl_limit_per_day')::numeric = 700 and s->>'reasons' ~ 'Firecrawl', s::text);
  delete from pipeline.coverage_vendor_usage;
  insert into pipeline.scholarship_ai_extractions(candidate_id, provider_id, url, cost_usd)
  select id, provider_id, url, 5 from pipeline.scholarship_page_candidates where title = 'International Merit Scholarship';
  s := security.scholarship_pilot_stop_v1();
  perform fx_ok('stop 3: AI over the pilot share a day', (s->>'stop')::boolean and (s->>'ai_limit_usd_per_day')::numeric = 4 and s->>'reasons' ~ 'AI', s::text);
  delete from pipeline.scholarship_ai_extractions;
  -- operational: most reads failed, or discovery stuck
  insert into pipeline.scholarship_page_candidates(provider_id, url, url_norm, source, read_status, read_at)
  select '00000000-0000-0000-0002-00000000000a', 'https://www.pilottafe.edu.au/p' || g, 'https://www.pilottafe.edu.au/p' || g, 'map', case when g % 2 = 0 then 'scrape_failed' else 'blocked' end, now() from generate_series(1, 10) g;
  s := security.scholarship_pilot_stop_v1();
  perform fx_ok('stop 4: failed page reads over the share', (s->>'stop')::boolean and s->>'reasons' ~ 'failed page reads', s::text);
  delete from pipeline.scholarship_page_candidates where read_status in ('scrape_failed', 'blocked');
  update pipeline.scholarship_discovery_providers set attempts = 3 where provider_id = '00000000-0000-0000-0002-00000000000a';
  perform fx_ok('stop 4: stuck discovery', security.scholarship_pilot_stop_v1()->>'reasons' ~ 'discovery stuck');
  update pipeline.scholarship_discovery_providers set attempts = 0 where provider_id = '00000000-0000-0000-0002-00000000000a';
  perform fx_ok('the stop thresholds are settings', exists (select 1 from pipeline.platform_toolset_settings where key = 'scholarship.pilot_stop_fc_share_pct' and used_by is not null and unit = '%'));
end $$;

-- wider activation: pilot only off, both proposals for everyone; back to the pilot
do $$
begin
  perform fx_set('scholarship.pilot_only', 'false');
  perform fx_ok('wider activation: an unlisted VET is admitted and searched by legitimacy; the untyped Canadian provider is no longer searched',
    security.scholarship_admission_provider_ok_v1('00000000-0000-0000-0002-00000000000b') and security.fc_sch_eligible_v1('00000000-0000-0000-0002-00000000000b')
    and not security.fc_sch_eligible_v1('00000000-0000-0000-0002-00000000000d'));
  perform fx_set('scholarship.pilot_only', 'true');
  perform fx_set('scholarship.non_university_admission', 'false'); perform fx_set('scholarship.legitimacy_checks_on', 'false');
  perform fx_ok('proposals off: the list alone changes nothing (TAFE refused, tier as before)', not security.scholarship_admission_provider_ok_v1('00000000-0000-0000-0002-00000000000a')
    and not security.fc_sch_eligible_v1('00000000-0000-0000-0002-00000000000a') and security.fc_provider_tier_v1('00000000-0000-0000-0002-00000000000a') = 3
    and not (security.scholarship_pilot_start_v1()->>'pilot')::boolean);
end $$;
