-- CF-247 Scholarship Coverage Recovery: behaviour after the migration (applied unchanged by run.sh). Every case prints "ok <case>" or stops
-- with an error. UNSW Sydney and UNSW College carry their live ids; the UNSW umbrella awards are the ten read from the official Term 1, 2027
-- page on 2 Nov 2026 (unsw-term1-2027.html, the same items the worker's awardSections returns in s224); other providers are synthetic.
create function fx_ok(p_case text, p_cond boolean, p_detail text default '') returns void language plpgsql as
$f$ begin if p_cond is not true then raise exception 'FAILED %: %', p_case, p_detail; end if; raise notice 'ok %', p_case; end $f$;

insert into ref.countries(id, iso_alpha2, scholarship_ingestion_enabled) values ('00000000-0000-0000-0000-0000000000a1', 'AU', true), ('00000000-0000-0000-0000-0000000000a2', 'NZ', true);
insert into ref.provider_types(id, code, name, status) values ('00000000-0000-0000-0000-0000000000b1', 'university', 'University', 'active'),
  ('00000000-0000-0000-0000-0000000000b2', 'university_college', 'University College', 'active'), ('00000000-0000-0000-0000-0000000000b3', 'school', 'School', 'active');
insert into catalogue.providers(id, canonical_name, country_id, website, provider_type_id, provider_type_basis, enrols_international) values
  ('22657140-1cb0-4fa7-91df-90518ea8b35b', 'UNSW Sydney', '00000000-0000-0000-0000-0000000000a1', 'https://www.unsw.edu.au', '00000000-0000-0000-0000-0000000000b1', 'register', true),
  ('93c852cf-6df7-4161-82bd-ca95941cc227', 'UNSW College', '00000000-0000-0000-0000-0000000000a1', 'https://www.unswcollege.edu.au', '00000000-0000-0000-0000-0000000000b2', 'register', true);
insert into fx_groups values ('22657140-1cb0-4fa7-91df-90518ea8b35b');   -- UNSW Sydney is a university by its group membership (baseline §1.2)
insert into pipeline.onboarding_pilot(cohort, provider_id) values ('au-top-2026-10-12', '22657140-1cb0-4fa7-91df-90518ea8b35b');
insert into catalogue.courses(provider_id, course_code) select '22657140-1cb0-4fa7-91df-90518ea8b35b', lpad(g::text, 6, '0') || 'G' from generate_series(1, 40) g;
insert into catalogue.courses(provider_id, course_code) select '93c852cf-6df7-4161-82bd-ca95941cc227', lpad(g::text, 6, '0') || 'K' from generate_series(1, 5) g;
-- 1,500 synthetic small providers queued, as the live queue holds 1,138
insert into catalogue.providers(id, canonical_name, country_id, website, provider_type_id, provider_type_basis, enrols_international)
select ('00000000-0000-0000-0001-' || lpad(to_hex(g), 12, '0'))::uuid, 'Synthetic provider ' || g, '00000000-0000-0000-0000-0000000000a1', 'https://www.p' || g || '.edu.au', '00000000-0000-0000-0000-0000000000b3', null, true
  from generate_series(1, 1500) g;
insert into catalogue.courses(provider_id, course_code) select p.id, lpad(g::text, 6, '0') || 'A' from catalogue.providers p, generate_series(1, 3) g where p.canonical_name like 'Synthetic%';
insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status)
select id, website, 4, 'largest_unsearched', 'pending' from catalogue.providers where canonical_name like 'Synthetic%';
-- UNSW as live on 2 Nov 2026: status empty after a refused map (12 Oct), 322 candidates kept; UNSW College pending
insert into pipeline.scholarship_discovery_providers(provider_id, website, site_origin, priority, reason, status, method, url_count, kept_count, attempts, discovered_at) values
  ('22657140-1cb0-4fa7-91df-90518ea8b35b', 'https://www.unsw.edu.au', 'https://www.unsw.edu.au', 0, 'on_demand', 'empty', 'map:budget', 0, 322, 1, '2026-10-12 13:07:22+00'),
  ('93c852cf-6df7-4161-82bd-ca95941cc227', 'https://www.unswcollege.edu.au', null, 0, 'on_demand', 'pending', 'sitemap(1)', 222, 4, 0, '2026-10-01 23:10:06+00');

-- F10, F1: the refill stores the tier (and sets the cadence on old mapped/empty rows)
do $$
declare r jsonb;
begin
  r := security.scholarship_discovery_refill_v1(30);
  perform fx_ok('F1 the tier refresh is bounded by its setting (500 an hour)', (r->>'tiers')::int = 500, r::text);
  update pipeline.platform_toolset_settings set value = '5000' where toolset_key = 'pipeline' and key = 'batch.scholarship_tier_refresh';
  r := security.scholarship_discovery_refill_v1(30);
  perform fx_ok('F1 refill stores tiers', (select count(*) from pipeline.scholarship_discovery_providers where tier is null) = 0 and (select tier from pipeline.scholarship_discovery_providers where provider_id = '22657140-1cb0-4fa7-91df-90518ea8b35b') = 0
    and (select tier from pipeline.scholarship_discovery_providers where provider_id = '93c852cf-6df7-4161-82bd-ca95941cc227') = 3, r::text);
  perform fx_ok('F3 cadence set on the old empty UNSW row', (select next_discover_at::date from pipeline.scholarship_discovery_providers where provider_id = '22657140-1cb0-4fa7-91df-90518ea8b35b') = date '2026-11-11', r::text);
end $$;

-- F1: with the normal limits (daily budget on, 30-course minimum) every synthetic provider is held; the picker looks only at a window, pushes the
-- held rows back by the retry time and answers quickly; the head of the queue no longer blocks it
do $$
declare t0 timestamptz := clock_timestamp(); v jsonb; ms numeric; v_held int;
begin
  v := public.svc_scholarship_discover_next(6);
  ms := extract(epoch from clock_timestamp() - t0) * 1000;
  select count(*) into v_held from pipeline.scholarship_discovery_providers where next_discover_at > now() + interval '5 hours' and status = 'pending';
  perform fx_ok('F1 picker: window only, held rows wait', jsonb_array_length(v) = 0 and v_held = 60, v::text || ' held ' || v_held);
  perform fx_ok('F1 picker answers well inside the statement time-out', ms < 2000, ms::text || ' ms');
  -- the authority settings (budget off) and a due UNSW row: UNSW first (tier 0), with its sources
  update pipeline.platform_toolset_settings set value = 'false' where toolset_key = 'firecrawl' and key = 'daily_budget_on';
  update pipeline.scholarship_discovery_providers set next_discover_at = now() - interval '1 minute' where provider_id = '22657140-1cb0-4fa7-91df-90518ea8b35b';
  insert into pipeline.scholarship_listing_pages(provider_id, url, url_norm, source, active, status) values
    ('22657140-1cb0-4fa7-91df-90518ea8b35b', 'https://www.scholarships.unsw.edu.au/scholarships/search', 'https://www.scholarships.unsw.edu.au/scholarships/search', 'manual', true, 'waiting'),
    ('22657140-1cb0-4fa7-91df-90518ea8b35b', 'https://www.unsw.edu.au/research/hdr/scholarships', 'https://www.unsw.edu.au/research/hdr/scholarships', 'manual', true, 'waiting'),
    ('22657140-1cb0-4fa7-91df-90518ea8b35b', 'https://www.unsw.edu.au/study/your-future/international-scholarships', 'https://www.unsw.edu.au/study/your-future/international-scholarships', 'auto', true, 'read'),
    ('22657140-1cb0-4fa7-91df-90518ea8b35b', 'https://scholarships.online.unsw.edu.au/scholarship/sc_al_search.search', 'https://scholarships.online.unsw.edu.au/scholarship/sc_al_search.search', 'suggested', false, 'suggested');
  v := public.svc_scholarship_discover_next(6);
  perform fx_ok('F1/F3 the empty UNSW row is due again and picked first', v->0->>'provider_id' = '22657140-1cb0-4fa7-91df-90518ea8b35b', v::text);
  perform fx_ok('F4 sources: manual catalogues first, then auto; suggested never', v->0->'sources' = '["https://www.scholarships.unsw.edu.au/scholarships/search", "https://www.unsw.edu.au/research/hdr/scholarships", "https://www.unsw.edu.au/study/your-future/international-scholarships"]'::jsonb, (v->0->'sources')::text);
  perform fx_ok('F1 picks are bounded by the setting', jsonb_array_length(v) = 6, jsonb_array_length(v)::text);
end $$;

-- F3: a refused map is deferred (count kept, retried after 6 hours); a map that ran is due again after 30 days
do $$
declare p uuid := '22657140-1cb0-4fa7-91df-90518ea8b35b'; r jsonb;
begin
  update pipeline.scholarship_discovery_providers set url_count = 72 where provider_id = p;
  r := public.svc_scholarship_discover_record(p, 'deferred', 'https://www.unsw.edu.au', 'map:scholarship_share+map_search(0)', 0, '[]'::jsonb, '[]'::jsonb, 'map:scholarship_share');
  perform fx_ok('F3 refused map deferred, not empty; count kept', (select status = 'deferred' and url_count = 72 and attempts = 0 and next_discover_at between now() + interval '5 hours 59 minutes' and now() + interval '6 hours 1 minute'
    and discovered_at = '2026-10-12 13:07:22+00' from pipeline.scholarship_discovery_providers where provider_id = p), r::text);
  perform fx_ok('F3 a deferred row is not picked before its time', not exists (select 1 from jsonb_array_elements(public.svc_scholarship_discover_next(6)) x where x->>'provider_id' = p::text));
  r := public.svc_scholarship_discover_record(p, 'mapped', 'https://www.unsw.edu.au', 'map_search(72)+map_search(41)', 113,
        '[{"url": "https://www.scholarships.unsw.edu.au/international-scientia-coursework-scholarship", "source": "map"}, {"url": "https://www.unsw.edu.au/news/2026/scholarship-winners", "source": "map"}]'::jsonb, '[]'::jsonb, null);
  perform fx_ok('F3 a map that ran is due again after the cadence', (select status = 'mapped' and next_discover_at::date = (now() + interval '30 days')::date and sources_mapped = '["map_search(72)", "map_search(41)"]'::jsonb
    from pipeline.scholarship_discovery_providers where provider_id = p), r::text);
end $$;

-- F1: skip rules run on the candidates just recorded
do $$
begin
  insert into pipeline.scholarship_skip_rules(pattern, label) values ('/news/', 'news');
  perform public.svc_scholarship_discover_record('22657140-1cb0-4fa7-91df-90518ea8b35b', 'mapped', 'https://www.unsw.edu.au', 'map_search(1)', 1,
        '[{"url": "https://www.unsw.edu.au/news/2026/open-day", "source": "map"}]'::jsonb, '[]'::jsonb, null);
  perform fx_ok('F1 skip rules on new candidates', (select admit_status = 'skipped' from pipeline.scholarship_page_candidates where url = 'https://www.unsw.edu.au/news/2026/open-day'));
end $$;

-- F5: the UNSW Term 1 2027 umbrella page: ten awards; two already held (PUCA1026 by its own page, the International Student Award); the
-- rest become one candidate each, keyed by the page address and the award code; reading it again adds nothing
insert into scholarship.scholarships(id, provider_id, name, source_url, lifecycle_status, publication_status) values
  ('e19c6b16-6ebb-54cd-a018-d8f19624aa47', '22657140-1cb0-4fa7-91df-90518ea8b35b', 'Australia''s Global University Award (PUCA1026)', 'https://www.scholarships.unsw.edu.au/australias-global-university-award-puca1026', 'active', 'published'),
  ('28e59737-a341-50b2-a972-4afa543c171c', '22657140-1cb0-4fa7-91df-90518ea8b35b', 'International Student Award', 'https://www.scholarships.unsw.edu.au/international-student-award', 'active', 'published');
insert into pipeline.scholarship_listing_pages(provider_id, url, url_norm, source, active, status) values
  ('22657140-1cb0-4fa7-91df-90518ea8b35b', 'https://www.scholarships.unsw.edu.au/scholarships/id/1988', 'https://www.scholarships.unsw.edu.au/scholarships/id/1988', 'manual', true, 'waiting');
create temp table fx_umbrella(items jsonb);
insert into fx_umbrella values ('[
 {"name": "International Scientia Coursework Scholarship", "url": null, "code": "PUCA1025", "kind": "award_section"},
 {"name": "UNSW Law & Justice International Award", "url": null, "code": "PUCA1028", "kind": "award_section"},
 {"name": "UNSW Business School International Pathways Award", "url": null, "code": "PUCA1023", "kind": "award_section"},
 {"name": "UNSW Business School International Scholarship", "url": null, "code": "PUCA1024", "kind": "award_section"},
 {"name": "UNSW Hong Kong Foundation Scholarship", "url": null, "code": "UGCA1603", "kind": "award_section"},
 {"name": "Dr Vincent Lo Asia Undergraduate Scholarship", "url": null, "code": "UGCA1606", "kind": "award_section"},
 {"name": "Australia''s Global University Award", "url": "https://www.scholarships.unsw.edu.au/australias-global-university-award-puca1026", "code": "PUCA1026", "kind": "link"},
 {"name": "UNSW College Award", "url": null, "code": "PUCA1027", "kind": "award_section"},
 {"name": "UNSW Masters of Laws Scholarship", "url": null, "code": "PGCA1107", "kind": "award_section"},
 {"name": "UNSW Articulation Scholarships", "url": null, "code": "UGCA1815", "kind": "award_section"},
 {"name": "International Student Award", "url": "https://www.scholarships.unsw.edu.au/international-student-award", "kind": "link"},
 {"name": "Scholarship Application Online portal", "url": "https://scholarships.online.example.com/login", "kind": "link"}]'::jsonb);
do $$
declare l bigint := (select id from pipeline.scholarship_listing_pages where url_norm = 'https://www.scholarships.unsw.edu.au/scholarships/id/1988'); r jsonb; r2 jsonb;
begin
  r := public.svc_scholarship_listing_record_v2(l, 'read', 200, (select items from fx_umbrella), null, '{"state": "complete", "reason": "no_next_page", "pages_read": 1, "items": 12, "total_stated": null, "next_url": null}'::jsonb);
  perform fx_ok('F5 UNSW umbrella: 9 awards become candidates (PUCA1024 too: live it is only an inactive retired-register record), 2 held records are not added again, an off-site link is ignored',
    (r->>'new_candidates')::int = 9 and (r->>'members')::int = 11
    and (select count(*) from pipeline.scholarship_page_candidates where url like 'https://www.scholarships.unsw.edu.au/scholarships/id/1988#award-%') = 9
    and (select count(*) from pipeline.scholarship_listing_members where listing_id = l and held_scholarship_id is not null) = 2, r::text);
  perform fx_ok('F5 the section address is the page address plus the award code', exists (select 1 from pipeline.scholarship_page_candidates where url_norm = 'https://www.scholarships.unsw.edu.au/scholarships/id/1988#award-puca1025' and title = 'International Scientia Coursework Scholarship' and source = 'map'));
  r2 := public.svc_scholarship_listing_record_v2(l, 'read', 200, (select items from fx_umbrella), null, '{"state": "complete", "pages_read": 1}'::jsonb);
  perform fx_ok('F5 reading the same page again adds nothing (idempotent)', (r2->>'new_candidates')::int = 0 and (select count(*) from pipeline.scholarship_listing_members where listing_id = l) = 11, r2::text);
  -- F6: a partial read never says an item has gone; a complete read that no longer lists one does
  r2 := public.svc_scholarship_listing_record_v2(l, 'read', 200, (select jsonb_path_query_array(items, '$[0 to 8]') from fx_umbrella), null, '{"state": "partial", "reason": "page_limit", "pages_read": 10, "next_url": "https://www.scholarships.unsw.edu.au/scholarships/search?page=11"}'::jsonb);
  perform fx_ok('F6 partial: nothing marked absent; continues from next_url within the hour', (select count(*) from pipeline.scholarship_listing_members where listing_id = l and not present) = 0
    and (select page_state = 'partial' and next_url like '%page=11' and next_read_at < now() + interval '61 minutes' from pipeline.scholarship_listing_pages where id = l));
  update pipeline.scholarship_listing_pages set next_read_at = now() - interval '1 minute' where id = l;
  perform fx_ok('F6 the picker hands the continuation address back', (select x->>'next_url' from jsonb_array_elements(public.svc_scholarship_listing_next(20)) x where (x->>'id')::bigint = l) like '%page=11');
  r2 := public.svc_scholarship_listing_record_v2(l, 'read', 200, (select jsonb_path_query_array(items, '$[0 to 8]') from fx_umbrella), null, '{"state": "complete", "reason": "no_next_page", "pages_read": 1}'::jsonb);
  perform fx_ok('F6 complete: an item no longer listed is marked absent; completed_at set', (select count(*) from pipeline.scholarship_listing_members where listing_id = l and not present) = 2
    and (select page_state = 'complete' and completed_at is not null and next_url is null from pipeline.scholarship_listing_pages where id = l));
end $$;

-- F5: two awards of one page are two records; an award's own page with the same name is a duplicate, not a third record
do $$
declare a jsonb; b jsonb; c jsonb; v_c1 bigint; v_c2 bigint; v_c3 bigint; f jsonb;
begin
  f := '{"international": true, "admission": {"admit": true, "detail_page": true, "international_explicit": true, "offered": true}}'::jsonb;
  select id into v_c1 from pipeline.scholarship_page_candidates where url_norm like '%#award-puca1025';
  select id into v_c2 from pipeline.scholarship_page_candidates where url_norm like '%#award-puca1028';
  update pipeline.scholarship_page_candidates set read_status = 'read', storage_path = 'layer2/AU/scholarships/x/' || id || '.html.gz', final_url = url,
         facts = f || jsonb_build_object('admission', (f->'admission') || jsonb_build_object('name', title)) where id in (v_c1, v_c2);
  a := security.scholarship_admit_from_provider_page_v1(v_c1);
  b := security.scholarship_admit_from_provider_page_v1(v_c2);
  perform fx_ok('F5 two awards of one umbrella page are two records', (a->>'admitted')::boolean and (b->>'admitted')::boolean and a->>'scholarship_id' <> b->>'scholarship_id', a::text || b::text);
  perform fx_ok('F5 the record keeps the official page address with its award', (select source_url from scholarship.scholarships where id = (a->>'scholarship_id')::uuid) = 'https://www.scholarships.unsw.edu.au/scholarships/id/1988#award-puca1025');
  insert into pipeline.scholarship_page_candidates(provider_id, url, url_norm, title, source, read_status, storage_path, final_url, facts)
  values ('22657140-1cb0-4fa7-91df-90518ea8b35b', 'https://www.scholarships.unsw.edu.au/international-scientia-coursework-scholarship-puca1025', 'https://www.scholarships.unsw.edu.au/international-scientia-coursework-scholarship-puca1025',
          'International Scientia Coursework Scholarship', 'map', 'read', 'x.gz', 'https://www.scholarships.unsw.edu.au/international-scientia-coursework-scholarship-puca1025',
          f || jsonb_build_object('admission', (f->'admission') || jsonb_build_object('name', 'International Scientia Coursework Scholarship'))) returning id into v_c3;
  c := security.scholarship_admit_from_provider_page_v1(v_c3);
  perform fx_ok('F5 the same award found on its own page is a duplicate, not a new record', c->>'reason' = 'already held' and c->>'scholarship_id' = a->>'scholarship_id', c::text);
end $$;

-- P1 (proposed, off): UNSW College is refused as today; switched on, a governed non-university with its own website is allowed
do $$
declare r jsonb; v_c bigint;
begin
  perform fx_ok('P1 off: universities only (UNSW Sydney yes, UNSW College no)', security.scholarship_admission_provider_ok_v1('22657140-1cb0-4fa7-91df-90518ea8b35b')
    and not security.scholarship_admission_provider_ok_v1('93c852cf-6df7-4161-82bd-ca95941cc227'));
  insert into pipeline.scholarship_page_candidates(provider_id, url, url_norm, title, source, read_status, storage_path, final_url, facts)
  values ('93c852cf-6df7-4161-82bd-ca95941cc227', 'https://www.unswcollege.edu.au/regional-merit-scholarship', 'https://www.unswcollege.edu.au/regional-merit-scholarship', 'Regional Merit Scholarship', 'map', 'read', 'y.gz',
          'https://www.unswcollege.edu.au/regional-merit-scholarship', '{"international": true, "admission": {"admit": true, "detail_page": true, "international_explicit": true, "offered": true, "name": "Regional Merit Scholarship"}}') returning id into v_c;
  r := security.scholarship_admit_from_provider_page_v1(v_c);
  perform fx_ok('P1 off: the admission still refuses a non-university', r->>'reason' = 'not a university provider in a scholarship country', r::text);
  update pipeline.platform_toolset_settings set value = 'true' where toolset_key = 'pipeline' and key = 'scholarship.non_university_admission';
  perform fx_ok('P1 on: a governed university college with its own website is allowed', security.scholarship_admission_provider_ok_v1('93c852cf-6df7-4161-82bd-ca95941cc227'));
  update catalogue.providers set provider_type_basis = null where id = '93c852cf-6df7-4161-82bd-ca95941cc227';
  perform fx_ok('P1 on: not without a recorded provider type basis', not security.scholarship_admission_provider_ok_v1('93c852cf-6df7-4161-82bd-ca95941cc227'));
  update catalogue.providers set provider_type_basis = 'register' where id = '93c852cf-6df7-4161-82bd-ca95941cc227';
  perform fx_ok('P1 on: a school is never a scholarship provider', not security.scholarship_admission_provider_ok_v1('00000000-0000-0000-0001-000000000001'));
  update pipeline.platform_toolset_settings set value = 'false' where toolset_key = 'pipeline' and key = 'scholarship.non_university_admission';
end $$;

-- P2 (proposed, off): the course minimum; switched on, legitimacy evidence instead
do $$
begin
  perform fx_ok('P2 off: UNSW College (5 courses) is below the 30-course minimum', not security.fc_sch_eligible_v1('93c852cf-6df7-4161-82bd-ca95941cc227'));
  update pipeline.platform_toolset_settings set value = 'true' where toolset_key = 'pipeline' and key = 'scholarship.legitimacy_checks_on';
  perform fx_ok('P2 on: legitimacy evidence decides (UNSW College yes; a school no)', security.fc_sch_eligible_v1('93c852cf-6df7-4161-82bd-ca95941cc227')
    and not security.fc_sch_eligible_v1('00000000-0000-0000-0001-000000000001'));
  update catalogue.providers set website = 'https://www.oneuedu.com/unsw-college' where id = '93c852cf-6df7-4161-82bd-ca95941cc227';
  perform fx_ok('P2 on: never on a directory website', not security.fc_sch_eligible_v1('93c852cf-6df7-4161-82bd-ca95941cc227'));
  update catalogue.providers set website = 'https://www.unswcollege.edu.au' where id = '93c852cf-6df7-4161-82bd-ca95941cc227';
  update pipeline.platform_toolset_settings set value = 'false' where toolset_key = 'pipeline' and key = 'scholarship.legitimacy_checks_on';
end $$;

-- F7: a candidate that now opens the catalogue home is refused without an AI read; a scholarship page that moved is recorded once per address
do $$
declare v_c bigint; r jsonb;
begin
  insert into pipeline.scholarship_page_candidates(provider_id, url, url_norm, source) values ('22657140-1cb0-4fa7-91df-90518ea8b35b', 'https://www.scholarships.unsw.edu.au/scholarships/id/1895', 'https://www.scholarships.unsw.edu.au/scholarships/id/1895', 'sitemap') returning id into v_c;
  r := public.svc_scholarship_candidate_record(v_c, 'redirected_away', 200, 'firecrawl', 'https://www.scholarships.unsw.edu.au/', null, null, null);
  perform fx_ok('F7 redirected away: refused, not queued for the AI, read again only after the long re-read', (select admit_status = 'rejected' and admit_reasons = array['redirected_away'] and next_read_at > now() + interval '80 days'
    from pipeline.scholarship_page_candidates where id = v_c) and not exists (select 1 from pipeline.scholarship_ai_queue where candidate_id = v_c), r::text);
  insert into pipeline.scholarship_pages(scholarship_id, url, url_source) values ('7077aa43-648e-50a4-a98e-682340c2a821', 'https://www.scholarships.unsw.edu.au/scholarships/id/102', 'discovered');
  insert into scholarship.scholarships(id, provider_id, name, source_url, lifecycle_status, publication_status) values ('7077aa43-648e-50a4-a98e-682340c2a821', '22657140-1cb0-4fa7-91df-90518ea8b35b', 'Scientia Scholarship', 'https://www.scholarships.unsw.edu.au/scholarships/id/102', 'active', 'published');
  perform public.svc_scholarship_read_record('7077aa43-648e-50a4-a98e-682340c2a821', 'redirected_away', 200, 'firecrawl', 'https://www.scholarships.unsw.edu.au/', null, null, null);
  perform public.svc_scholarship_read_record('7077aa43-648e-50a4-a98e-682340c2a821', 'redirected_away', 200, 'firecrawl', 'https://www.scholarships.unsw.edu.au/', null, null, null);
  perform fx_ok('F7 the stored Scientia Scholarship address redirecting away is recorded once, seen twice; the record is not withdrawn',
    (select count(*) = 1 and min(seen) = 2 and min(outcome) = 'redirected_away' from pipeline.scholarship_source_moves where ref = '7077aa43-648e-50a4-a98e-682340c2a821')
    and (select publication_status from scholarship.scholarships where id = '7077aa43-648e-50a4-a98e-682340c2a821') = 'published');
end $$;

-- F8: the all-time cap retired into the daily share (nothing unlimited); the old cap only with the setting on
do $$
begin
  insert into pipeline.coverage_vendor_usage(units, purpose) values (30596, 'sch_scrape');
  perform fx_ok('F8 off (default): ceiling is used + the daily scholarship share', (public.svc_scholarship_fc_budget()->>'cap')::numeric = 30596 + 3500 and (public.svc_scholarship_fc_budget()->>'lifetime_cap')::boolean = false);
  update pipeline.platform_toolset_settings set value = 'true' where toolset_key = 'pipeline' and key = 'scholarship.lifetime_cap_on';
  perform fx_ok('F8 on: the old all-time cap', (public.svc_scholarship_fc_budget()->>'cap')::numeric = 60000);
  update pipeline.platform_toolset_settings set value = 'false' where toolset_key = 'pipeline' and key = 'scholarship.lifetime_cap_on';
end $$;

-- F9: closed round (close date passed, page still offers it), ended (page redirects away), open, no dates; publication untouched
do $$
begin
  insert into scholarship.scholarships(id, provider_id, name, source_url, lifecycle_status, publication_status, application_close_date) values
    ('4daa1a43-40aa-5369-aeb7-11f93989bc2c', '22657140-1cb0-4fa7-91df-90518ea8b35b', 'Green Fellow PhD Scholarship in Comparative Constitutional Law', 'https://www.unsw.edu.au/law-justice/x', 'active', 'published', '2026-08-21'),
    ('00000000-0000-0000-0000-00000000c0de', '22657140-1cb0-4fa7-91df-90518ea8b35b', 'Synthetic open scholarship', 'https://www.unsw.edu.au/y', 'active', 'unpublished', current_date + 30);
  insert into pipeline.scholarship_pages(scholarship_id, url, read_status, facts) values ('4daa1a43-40aa-5369-aeb7-11f93989bc2c', 'https://www.unsw.edu.au/law-justice/x', 'read', '{"admission": {"offered": true}}');
  perform security.scholarship_round_state_refresh_v1(1000);
  perform fx_ok('F9 round states', (select jsonb_object_agg(scholarship_id::text, state) from pipeline.scholarship_round_states) @> jsonb_build_object(
      '4daa1a43-40aa-5369-aeb7-11f93989bc2c', 'closed_round', '7077aa43-648e-50a4-a98e-682340c2a821', 'ended', '00000000-0000-0000-0000-00000000c0de', 'open', '28e59737-a341-50b2-a972-4afa543c171c', 'no_dates'),
    (select jsonb_object_agg(scholarship_id::text, state || ':' || basis) from pipeline.scholarship_round_states)::text);
  perform fx_ok('F9 nothing published or withdrawn by the classification', (select count(*) from scholarship.scholarships where publication_status = 'published') = 4);
end $$;

-- F10: task sizes from the settings
do $$
begin
  update pipeline.scholarship_layer_settings set value = 4 where key = 'discover_limit';
  perform security.scholarship_task_fire_v1(array['discover']);
  truncate pipeline.edge_request_log;  -- the fire guard holds a second call of the same mode within 45 seconds
  perform security.scholarship_task_fire_v1(array['candidates']);
  perform fx_ok('F10 task sizes are the Scholarships settings', (select jsonb_agg(body order by at, body->>'phase') from fx_sent) @> '[{"phase": "discover", "limit": 4}, {"phase": "candidates", "read_limit": 30}]'::jsonb,
    (select jsonb_agg(body) from fx_sent)::text);
  perform fx_ok('F10 worker settings include the scholarship keys', (public.svc_worker_settings_v1() ? 'scholarship.listing_pages_max') and (public.svc_worker_settings_v1()->>'scholarship.render_wait_ms')::int = 1500);
end $$;

-- F1: the candidate picker: a window, holds per provider, requested first
do $$
declare v jsonb;
begin
  update pipeline.scholarship_page_candidates set requested_at = now() where url_norm like '%#award-ugca1603';
  v := public.svc_scholarship_candidate_next(5);
  perform fx_ok('F1 candidate picker: requested first, bounded', v->0->>'url' like '%#award-ugca1603' and jsonb_array_length(v) = 5, v::text);
  insert into fx_hidden values ('22657140-1cb0-4fa7-91df-90518ea8b35b');
  update pipeline.scholarship_page_candidates set leased_until = null;
  v := public.svc_scholarship_candidate_next(5);
  perform fx_ok('F1 candidate picker: an unpublished provider''s pages are not taken', not exists (select 1 from jsonb_array_elements(v) x where x->>'provider_id' = '22657140-1cb0-4fa7-91df-90518ea8b35b'), v::text);
  delete from fx_hidden;
end $$;

-- F2: a worker call's outcome; three failed or zero-work-error runs in a row open one issue naming the job; a good run resolves it
insert into cron.job(jobname, schedule, command) values ('scholarship-discover', '*/10 * * * *',
  'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'',''scholarship_discover'',''limit'',security.scholarship_setting(''discover_limit'',6)::int,''read_limit'',security.scholarship_setting(''candidate_read_limit'',30)::int))');
do $$
declare r jsonb;
begin
  perform public.svc_worker_report_v1('scholarship_discover', 500, 8100, '{"ok": false, "error": "svc_scholarship_discover_next: canceling statement due to statement timeout", "workerVersion": "coverage-sweep-v0.5.6"}', 'coverage-sweep-worker-v0.57.0');
  perform public.svc_worker_report_v1('scholarship_discover', 200, 12518, '{"ok": true, "mode": "scholarship_discover", "phase": "all", "discover": [], "candidates": {"items": 0, "tally": {}, "admitted": []}}', 'coverage-sweep-worker-v0.57.0');
  perform public.svc_worker_report_v1('scholarship_discover', 200, 9000, '{"ok": true, "discover": [{"provider_id": "x", "status": "deferred", "methods": ["map:scholarship_share"]}], "candidates": {"items": 0, "tally": {"waiting_scraper": 30}}}', 'coverage-sweep-worker-v0.58.0');
  perform public.svc_worker_report_v1('scholarship_listing', 200, 4700, '{"ok": true, "pages": [], "items": 0}', 'coverage-sweep-worker-v0.57.0');
  perform fx_ok('F2 outcomes: 500 failed; nothing to do idle; refusals with no work zero_work_error',
    (select array_agg(outcome order by id) from pipeline.mode_outcome_ledger) = array['failed', 'idle', 'zero_work_error', 'idle'], (select array_agg(outcome order by id) from pipeline.mode_outcome_ledger)::text);
  perform public.svc_worker_report_v1('scholarship_discover', 503, 100, '{"code": "BOOT_ERROR", "message": "Function failed to start"}', 'x');
  perform public.svc_worker_report_v1('scholarship_discover', 200, 100, '{"ok": true, "discover": [], "candidates": {"items": 30, "tally": {"waiting_scraper": 30}}}', 'x');
  r := security.worker_outcome_check_v1();
  perform fx_ok('F2 three bad runs in a row: one issue naming the scheduled job', (r->>'open')::int = 1 and exists (select 1 from pipeline.platform_issues where check_key = 'worker:scholarship_discover' and resolved_at is null
    and detail->'jobs' = '["scholarship-discover"]'::jsonb), r::text);
  r := security.worker_outcome_check_v1();
  perform fx_ok('F2 a second check updates the same issue (no duplicate)', (select count(*) from pipeline.platform_issues where check_key = 'worker:scholarship_discover') = 1
    and (select occurrences from pipeline.platform_issues where check_key = 'worker:scholarship_discover') = 2);
  perform public.svc_worker_report_v1('scholarship_discover', 200, 9000, '{"ok": true, "discover": [{"provider_id": "x", "status": "mapped"}], "candidates": {"items": 30, "tally": {"admitted": 2}, "admitted": [1, 2]}, "done": 30}', 'x');
  r := security.worker_outcome_check_v1();
  perform fx_ok('F2 a good run resolves it', (r->>'resolved')::int = 1 and not exists (select 1 from pipeline.platform_issues where check_key = 'worker:scholarship_discover' and resolved_at is null), r::text);
end $$;

-- shipped state: nothing switched on
do $$
begin
  perform fx_ok('shipped: the job is paused, proposals off, lifetime cap off', not (select active from cron.job where jobname = 'worker-outcome-check')
    and not security.scholarship_flag_v1('scholarship.non_university_admission', true) and not security.scholarship_flag_v1('scholarship.legitimacy_checks_on', true)
    and not security.scholarship_flag_v1('scholarship.lifetime_cap_on', true));
end $$;
