-- IQ-00055 fixture data and the snapshot of the OLD definitions' choices (run before the migration; see run.sh). Synthetic rows only.
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values
 ('pipeline', 'pdesc.enabled', '1'), ('pipeline', 'pdesc.pending_max', '10'), ('pipeline', 'pdesc.tries', '3'), ('pipeline', 'pdesc.acquire_direct', '1'),
 ('pipeline', 'pdesc.source_max_age_days', '365'), ('pipeline', 'pdesc.about_max_segments', '2'), ('pipeline', 'central.min_suggest_score', '4'),
 ('pipeline', 'pdesc.countries', '["AU"]'), ('pipeline', 'pdesc.provider_types', '["university"]'), ('pipeline', 'pdesc.provider_keys', '[]'),
 ('pipeline', 'pdesc.about_patterns', '["about","about-us","overview","our-university","who-we-are","discover"]'),
 ('pipeline', 'pdesc.about_prefixes', '["about-","about_"]'),
 ('pipeline', 'pdesc.refused_path_words', '["news","events","media","research","staff","school","study","courses","international"]'),
 ('pipeline', 'pdesc.refused_host_labels', '["staff","intranet","news","library"]'),
 ('pipeline', 'binding.provider_host_aliases', '["provider:fx:alpha=alpha-old.edu.au"]');
insert into ref.countries(id, iso_alpha2) values ('a0000000-0000-0000-0000-0000000000a1', 'AU'), ('a0000000-0000-0000-0000-0000000000a2', 'NZ');
insert into ref.provider_types(id, code) values ('b0000000-0000-0000-0000-0000000000b1', 'university');

-- hand-made providers: Alpha (main site, alias host, every kind of copy), Beta (another provider's host), Gamma (no About copy)
insert into catalogue.providers(id, stable_key, canonical_name, website, country_id, provider_type_id) values
 ('10000000-0000-0000-0000-000000000001', 'provider:fx:alpha', 'Alpha University', 'https://www.alpha.edu.au', 'a0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-0000000000b1'),
 ('10000000-0000-0000-0000-000000000002', 'provider:fx:beta', 'Beta University', 'beta.edu.au', 'a0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-0000000000b1'),
 ('10000000-0000-0000-0000-000000000003', 'provider:fx:gamma', 'Gamma University', 'https://gamma.edu.au/', 'a0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-0000000000b1');
insert into pipeline.sources(id, provider_id) values ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001'),
 ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002'), ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000003');
insert into pipeline.evidence_artifacts(id, source_id, source_url, storage_path, mime_type, captured_at) values
 -- Alpha: the main-site About page (older) wins over newer copies on other own hosts and over every refused copy
 ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'https://www.alpha.edu.au/about-alpha', 'p/1', 'text/html', now() - interval '30 days'),
 ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'https://alpha-old.edu.au/pharm/about/news/2025/new-dean', 'p/2', 'text/html', now() - interval '1 day'),
 ('30000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', 'https://staff.alpha.edu.au/about', 'p/3', 'text/html', now() - interval '1 day'),
 ('30000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000001', 'https://campus.alpha.edu.au/about', 'p/4', 'text/html', now() - interval '2 days'),
 ('30000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000001', 'https://www.alpha.edu.au/study/about', 'p/5', 'text/html', now() - interval '1 day'),
 ('30000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-000000000001', 'https://www.beta.edu.au/about', 'p/6', 'text/html', now() - interval '1 day'),
 ('30000000-0000-0000-0000-000000000007', '20000000-0000-0000-0000-000000000001', 'https://www.alpha.edu.au/about/history/1900', 'p/7', 'text/html', now() - interval '1 day'),
 ('30000000-0000-0000-0000-000000000008', '20000000-0000-0000-0000-000000000001', 'https://www.alpha.edu.au/about', 'p/8', 'application/pdf', now() - interval '1 day'),
 ('30000000-0000-0000-0000-000000000009', '20000000-0000-0000-0000-000000000001', 'https://www.alpha.edu.au/about', null, 'text/html', now() - interval '1 day'),
 ('30000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-000000000001', 'https://www.alpha.edu.au/about', 'p/a', 'text/html', now() - interval '400 days'),
 ('30000000-0000-0000-0000-00000000000b', '20000000-0000-0000-0000-000000000001', 'https://www.alpha.edu.au/courses/bachelor-of-arts', 'p/b', 'text/html', now() - interval '1 hour'),
 ('30000000-0000-0000-0000-00000000000c', '20000000-0000-0000-0000-000000000001', 'https://www.alpha.edu.au/about-', 'p/c', 'text/html', now() - interval '1 hour'),
 ('30000000-0000-0000-0000-00000000000d', '20000000-0000-0000-0000-000000000001', 'HTTPS://www.alpha.edu.au/about', 'p/d', 'text/html', now() - interval '1 hour'),
 -- Beta: two main-site copies with the same capture time (the id decides), and a language part
 ('30000000-0000-0000-0000-000000000011', '20000000-0000-0000-0000-000000000002', 'https://beta.edu.au/en-au/Who-We-Are/', 'p/11', null, '2026-10-01T00:00:00Z'),
 ('30000000-0000-0000-0000-000000000012', '20000000-0000-0000-0000-000000000002', 'https://www.beta.edu.au/overview?x=1#top', 'p/12', 'text/markdown', '2026-10-01T00:00:00Z'),
 ('30000000-0000-0000-0000-000000000013', '20000000-0000-0000-0000-000000000002', 'https://www.alpha.edu.au/about', 'p/13', 'text/html', now()),
 -- Gamma: nothing that passes
 ('30000000-0000-0000-0000-000000000021', '20000000-0000-0000-0000-000000000003', 'https://gamma.edu.au/news/about-us', 'p/21', 'text/html', now()),
 ('30000000-0000-0000-0000-000000000022', '20000000-0000-0000-0000-000000000003', 'https://gamma.edu.au/', 'p/22', 'text/html', now());

-- generated providers (deterministic): random mixes of About-like, refused and unrelated addresses on own, sub, alias and foreign hosts
select setseed(0.255);
insert into catalogue.providers(id, stable_key, canonical_name, website, country_id, provider_type_id)
select ('40000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'provider:fx:g' || g, 'Generated ' || g,
       case when g % 7 = 0 then 'http://g' || g || '.edu.au/home' else 'https://www.g' || g || '.edu.au' end,
       case when g % 11 = 0 then 'a0000000-0000-0000-0000-0000000000a2'::uuid else 'a0000000-0000-0000-0000-0000000000a1'::uuid end, 'b0000000-0000-0000-0000-0000000000b1'
  from generate_series(1, 60) g;
insert into pipeline.provider_extra_domains(provider_id, domain) select ('40000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'https://www.g' || g || '-extra.com' from generate_series(1, 60, 5) g;
insert into pipeline.sources(id, provider_id) select ('50000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, ('40000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid from generate_series(1, 60) g;
insert into pipeline.evidence_artifacts(source_id, source_url, storage_path, mime_type, captured_at)
select ('50000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
       (array['https://', 'http://', 'HTTP://'])[1 + floor(random() * 3)::int]
       || (array['www.g' || g || '.edu.au', 'g' || g || '.edu.au', 'campus.g' || g || '.edu.au', 'staff.g' || g || '.edu.au', 'www.g' || g || '-extra.com',
                 'www.g' || ((g % 60) + 1) || '.edu.au', 'unknown.example.com', 'NEWS.g' || g || '.edu.au'])[1 + floor(random() * 8)::int]
       || (array['', '/', '/en', '/en/', '/en-au', '/zz-yy', '/xyz', '/2026', '//'])[1 + floor(random() * 9)::int]
       || (array['/about', '/About', '/about-us', '/about-g', '/about_us', '/about-', '/aboutus', '/overview', '/Overview/', '/who-we-are', '/discover',
                 '/news', '/about-news', '/news-about', '/our-university', '/our_university', '/courses', '/', '', '/study/about', '/research-about',
                 '/school.about', '/faculty', '/aboutxus', '/ab%t', '/a\\b', '/_x', '/%25', '/about\\x'])[1 + floor(random() * 29)::int]
       || (array['', '', '/', '/overview', '/about', '/history', '/history/1900', '/news/item', '/media', '?q=about', '#about', '/About-Us', '/x/y/z', '/calendar/admission/criteria/', '/a/b/'])[1 + floor(random() * 15)::int],
       case when random() < 0.05 then null else 'p/g' end,
       (array['text/html', null, 'text/markdown', 'application/pdf', 'text/plain'])[1 + floor(random() * 5)::int],
       case when random() < 0.1 then null else now() - make_interval(days => floor(random() * 420)::int) end
  from generate_series(1, 60) g, generate_series(1, 12) n;
-- a few exact ties on capture time among generated copies
update pipeline.evidence_artifacts set captured_at = '2026-09-09T09:09:09Z' where storage_path = 'p/g' and source_url ~ '/(about|overview)$' and random() < 0.3;

analyze;

-- the settings variants the choice is compared under (the page rule's own lists)
create table fx_variants(v int primary key, patterns jsonb, prefixes jsonb, max_segments int);
insert into fx_variants values
 (1, '["about","about-us","overview","our-university","who-we-are","discover"]', '["about-","about_"]', 2),
 (2, '["About","OVERVIEW"]', '[]', 1),
 (3, '[]', '["about-"]', 3),
 (4, '[]', '[]', 2),
 (5, '["about",""]', '["", "ABOUT_"]', 2),
 (6, '["our_university","about"]', '["our"]', 4),
 -- LIKE wildcards and the escape character in the lists are literal: "about_us" must not match "aboutxus", nor "ab%t" match "about"
 (7, '["about_us","ab%t","a\\b"]', '["_", "%", "about\\"]', 2);
create function fx_variant(p_v int) returns void language sql as $f$
  update pipeline.platform_toolset_settings s set value = case s.key when 'pdesc.about_patterns' then x.patterns when 'pdesc.about_prefixes' then x.prefixes else to_jsonb(x.max_segments) end
    from fx_variants x where x.v = p_v and s.toolset_key = 'pipeline' and s.key in ('pdesc.about_patterns', 'pdesc.about_prefixes', 'pdesc.about_max_segments') $f$;

-- the OLD definitions' choices, per variant and provider
create table fx_old_stored(v int, provider_id uuid, stored uuid, primary key (v, provider_id));
do $$ declare x record; begin
  for x in select v from fx_variants order by v loop
    perform fx_variant(x.v);
    insert into fx_old_stored select x.v, p.id, security.provider_description_stored_v1(p.id) from catalogue.providers p;
  end loop;
  perform fx_variant(1);
end $$;

-- central page finder suggestions for the picker's candidates (ties on score and length included)
insert into pipeline.provider_central_search(provider_id, found) values
 ('10000000-0000-0000-0000-000000000001', '[{"kind":"about_page","url":"https://campus.alpha.edu.au/about","score":9},{"kind":"about_page","url":"https://www.alpha.edu.au/about-alpha","score":5},
   {"kind":"about_page","url":"https://www.alpha.edu.au/about-alpha","score":5},{"kind":"about_page","url":"https://www.alpha.edu.au/overview","score":5},
   {"kind":"about_page","url":"https://www.alpha.edu.au/news/about","score":9},{"kind":"about_page","url":"https://www.alpha.edu.au/about","score":3},
   {"kind":"courses","url":"https://www.alpha.edu.au/about-us","score":9},{"kind":"about_page","url":"ftp://www.alpha.edu.au/about","score":9},
   {"kind":"about_page","url":"https://www.alpha.edu.au/about-us","score":"7.5"},{"kind":"about_page","url":"https://www.alpha.edu.au/about-us","score":6}]'),
 ('10000000-0000-0000-0000-000000000003', '[{"kind":"about_page","url":"https://gamma.edu.au/about","score":4},{"kind":"about_page","url":"https://www.beta.edu.au/about","score":10}]');
-- the picker's queue: Alpha, Beta, Gamma and ten generated providers (pdesc.provider_keys empty: every AU university)
insert into pipeline.provider_description_reads(provider_id, next_try_at, created_at)
select id, now() - interval '1 hour', now() - make_interval(secs => 100 - row_number() over (order by stable_key)) from catalogue.providers
 where stable_key in ('provider:fx:alpha', 'provider:fx:beta', 'provider:fx:gamma') or stable_key ~ '^provider:fx:g([1-9]|10)$';
create function fx_requeue() returns void language sql as $f$ update pipeline.provider_description_reads set state = 'queued', tries = 0, leased_until = null $f$;
create function fx_items(p jsonb) returns jsonb language sql as $f$ select coalesce(jsonb_agg(i - 'item_id' order by i->>'provider_id'), '[]') from jsonb_array_elements(p->'items') i $f$;
-- the OLD picker's answers: direct acquisition on (every queued row), then off (only rows with a stored copy), each from a full queue
create table fx_old_next(acquire int primary key, items jsonb, rest jsonb);
do $$ declare a int; v jsonb; begin
  foreach a in array array[1, 0] loop
    perform fx_requeue();
    update pipeline.platform_toolset_settings set value = to_jsonb(a) where key = 'pdesc.acquire_direct';
    v := public.svc_provider_description_next(50);
    insert into fx_old_next values (a, fx_items(v), v - 'items');
  end loop;
  update pipeline.platform_toolset_settings set value = '1' where key = 'pdesc.acquire_direct';
  perform fx_requeue();
end $$;
