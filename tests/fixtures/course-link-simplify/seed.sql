-- CF-247 Course Link simplification: a production-shaped backlog (classes in the proportions read live on 4 Nov 2026 17:18-17:28 AEDT, about
-- one twentieth: 2,323 Decision 179 refusals of 2,958, 188 old-year addresses, 175 held-page refusals, 162 CRICOS-differs, 160 unlinked stored
-- copies, 55 refused active pages, 28 retired, 12 refused pages where the course has since got a page, 9 E16, 5 manual, 1 H05, 1 decided
-- before). Ids are fx.u('<name>'). Northbank (AU) and Kauri (NZ) hold the mix; Lakeshore (CA) is retired; Control (AU) is never reconciled
-- (other providers continue, §10.10). Nothing here is live data.
create or replace function fx.u(p text) returns uuid language sql immutable as $f$ select md5(p)::uuid $f$;

insert into catalogue.providers(id, stable_key, canonical_name, website, country_id, lifecycle_status) values
 (fx.u('p-north'), 'provider:cricos:09999n', 'Northbank University', 'https://www.northbank.edu.au', 'f0000000-0000-0000-0000-0000000000a1', 'active'),
 (fx.u('p-kauri'), 'provider:nzqa:9999', 'Kauri Polytechnic', 'https://www.kauri.ac.nz', 'f0000000-0000-0000-0000-0000000000e1', 'active'),
 (fx.u('p-lake'), 'provider:ca:lake', 'Lakeshore College', 'https://www.lakeshore.ca', 'f0000000-0000-0000-0000-0000000000c1', 'inactive'),
 (fx.u('p-ctrl'), 'provider:cricos:08888c', 'Control University', 'https://www.control.edu.au', 'f0000000-0000-0000-0000-0000000000a1', 'active');
update catalogue.providers set lifecycle_status = 'active' where lifecycle_status is null;
-- the Kauri sub-brand host is the provider's own (binding.provider_host_aliases, as live for Whitireia and WelTec)
update pipeline.platform_toolset_settings set value = value || '["provider:nzqa:9999=kauri.ac.nz kauritech.nz"]'::jsonb where key = 'binding.provider_host_aliases';
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value)
select 'pipeline', 'binding.provider_host_aliases', 'list', '["provider:nzqa:9999=kauri.ac.nz kauritech.nz"]'::jsonb
 where not exists (select 1 from pipeline.platform_toolset_settings where key = 'binding.provider_host_aliases');

create table fx.plan(name text primary key, prov text, n int, expect text);
insert into fx.plan values
 ('d179', 'p-north', 60, 'page_needed_d179'), ('d179k', 'p-kauri', 56, 'page_needed_d179'), ('d179c', 'p-ctrl', 3, 'page_needed_d179'),
 ('claimed', 'p-north', 1, 'claimed'), ('retired', 'p-lake', 2, 'entity_retired'),
 ('held', 'p-north', 6, 'held_page_dispute'), ('heldk', 'p-kauri', 3, 'held_page_dispute'),
 ('h13', 'p-north', 9, 'old_year_address'), ('cov', 'p-kauri', 4, 'cricos_page_differs'), ('covc', 'p-kauri', 1, 'cricos_page_differs'),
 ('nolink', 'p-north', 5, 'evidence_not_linked'), ('nocopy', 'p-north', 1, 'evidence_missing'),
 ('actref', 'p-north', 3, 'active_page_refused'), ('later', 'p-north', 1, 'refused_page_course_has_page'), ('lock', 'p-north', 1, 'manual_binding'),
 ('e16', 'p-north', 1, 'e16_unclear'), ('h05', 'p-kauri', 1, 'record_names_other_page'), ('active', 'p-kauri', 1, 'covered_by_active'),
 ('dupe', 'p-kauri', 1, 'duplicate_pending'), ('decided', 'p-kauri', 1, 'decided_before'), ('offdom', 'p-kauri', 1, 'off_domain'),
 ('aliasdom', 'p-kauri', 1, 'cricos_page_differs');

-- courses: one per item (code AU format for AU providers)
insert into catalogue.courses(id, provider_id, canonical_title, course_code, lifecycle_status, open_to_international)
select fx.u('c-' || p.name || '-' || g), fx.u(p.prov), 'Course ' || p.name || ' ' || g,
       case when p.prov in ('p-north', 'p-ctrl') then lpad((100000 + abs(hashtext(p.name || g)) % 899999)::text, 6, '0') || 'K' else 'NZ' || g end, 'active', true
  from fx.plan p, generate_series(1, p.n) g where p.name not in ('dupe');

update pipeline.platform_toolset_settings set value = '0' where key = 'layer4.evidence_link_on';

-- held pages for the classes that hold one
insert into catalogue.course_links(course_id, link_type, url, is_primary, status)
select fx.u('c-' || p.name || '-' || g), 'official_course',
       case p.name when 'h13' then 'https://handbook.northbank.edu.au/2019/course-' || g
                   when 'actref' then 'https://www.northbank.edu.au/study/shared-' || g
                   else 'https://www.' || case when p.prov = 'p-kauri' then 'kauri.ac.nz' else 'northbank.edu.au' end || '/held/' || p.name || '-' || g end, true, 'active'
  from fx.plan p, generate_series(1, p.n) g
 where p.name in ('held', 'heldk', 'h13', 'cov', 'covc', 'nolink', 'nocopy', 'actref', 'later', 'lock', 'e16', 'h05', 'active', 'decided', 'offdom', 'aliasdom');
insert into catalogue.course_links(course_id, link_type, url, is_primary, status)   -- E16: the second page the course holds
values (fx.u('c-e16-1'), 'official_course', 'https://handbook.northbank.edu.au/2025/bm009', false, 'active');

-- refusals recorded by the binding check
insert into pipeline.page_rejections(course_id, url, provider_id, source, reason)
select fx.u('c-' || p.name || '-' || g),
       case p.name when 'actref' then 'https://www.northbank.edu.au/study/shared-' || g
                   else 'https://www.' || case when p.prov = 'p-kauri' then 'kauri.ac.nz' when p.prov = 'p-lake' then 'lakeshore.ca' when p.prov = 'p-ctrl' then 'control.edu.au' else 'northbank.edu.au' end || '/found/' || p.name || '-' || g end,
       fx.u(p.prov), 'binding_check', case when p.name = 'actref' then 'the page is shared by several courses' else 'the page is for another qualification level' end
  from fx.plan p, generate_series(1, p.n) g
 where p.name in ('d179', 'd179k', 'd179c', 'claimed', 'retired', 'held', 'heldk', 'nolink', 'nocopy', 'actref', 'later', 'lock');

-- stored copies of the proposed pages (none for nocopy)
insert into pipeline.evidence_artifacts(id, source_url, content_hash, captured_at, metadata)
select fx.u('e-' || p.name || '-' || g),
       case when p.name in ('h13', 'e16', 'active', 'actref') then null else 'https://www.' || case when p.prov = 'p-kauri' then 'kauri.ac.nz' when p.prov = 'p-lake' then 'lakeshore.ca' when p.prov = 'p-ctrl' then 'control.edu.au' else 'northbank.edu.au' end || '/found/' || p.name || '-' || g end,
       'h-' || p.name || g, now() - interval '3 days',
       jsonb_build_object('course_id', fx.u('c-' || p.name || '-' || g), 'identity_basis', case when p.name = 'covc' then 'nzqa_code' else 'exact_title' end)
  from fx.plan p, generate_series(1, p.n) g where p.name not in ('nocopy', 'dupe');
-- the old-year, E16, active and refused-active items carry the copy of the page they ask about
update pipeline.evidence_artifacts e set source_url = l.url from catalogue.course_links l
 where l.course_id = (e.metadata->>'course_id')::uuid and l.is_primary and e.source_url is null;
update pipeline.evidence_artifacts set source_url = 'https://handbook.northbank.edu.au/2025/bm009' where id = fx.u('e-e16-1');
update pipeline.evidence_artifacts set source_url = 'https://www.otherhost.com/found/offdom-1' where id = fx.u('e-offdom-1');
update pipeline.evidence_artifacts set source_url = 'https://www.kauritech.nz/found/aliasdom-1' where id = fx.u('e-aliasdom-1');
insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, identity_basis)
values (fx.u('c-lock-1'), fx.u('p-north'), 'https://www.northbank.edu.au/held/lock-1', 'manual', 'bound', 'exact_title');
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', fx.u('c-lock-1'), 'official_url', 'value');

-- the waiting items, as raised live (binding check, coverage sweep, housekeeping H13 and H05, E16)
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, status, escalation_reason, change_control_ref, created_at, claimed_at)
select fx.u('i-' || p.name || '-' || g), 'course', fx.u('c-' || p.name || '-' || g), 'official_course_url',
       case when p.name in ('nolink', 'nocopy', 'd179', 'd179k', 'd179c', 'retired', 'decided') then null else fx.u('e-' || p.name || '-' || g) end,
       case when p.name in ('d179', 'd179k', 'd179c', 'claimed', 'retired', 'later') then '[]'::jsonb
            else coalesce((select jsonb_agg(l.url order by l.is_primary desc, l.url) from catalogue.course_links l where l.course_id = fx.u('c-' || p.name || '-' || g)), '[]'::jsonb) end,
       jsonb_build_object('course_url', coalesce((select e.source_url from pipeline.evidence_artifacts e where e.id = fx.u('e-' || p.name || '-' || g)),
                                                 'https://www.northbank.edu.au/found/' || p.name || '-' || g)),
       case when p.name = 'h13' then jsonb_build_object('source', 'housekeeping H13', 'rule', 'address_year', 'year', 2019)
            when p.name = 'h05' then jsonb_build_object('source', 'housekeeping H05', 'rule', 'course_url_differs')
            when p.name = 'e16' then jsonb_build_object('source', 'e16 unclear', 'rule', 'e16_unclear')
            when p.name in ('cov', 'covc', 'active', 'decided', 'offdom', 'aliasdom') then jsonb_build_object('source', 'coverage sweep')
            else jsonb_build_object('source', 'binding check', 'rule', 'level', 'lane', 'title_search') end,
       'pending',
       case when p.name in ('cov', 'covc', 'active', 'decided', 'offdom', 'aliasdom') then 'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.'
            when p.name = 'h13' then 'The page we show carries the year 2019 in its address and may be an archived handbook.'
            else 'The page found automatically was not linked: the page is for another qualification level. If it is this course''s own page, choose Use the new page; otherwise keep the page we hold.' end,
       'CF-CHG-20260915-247', now() - interval '2 days' + make_interval(secs => g), case when p.name = 'claimed' then now() end
  from fx.plan p, generate_series(1, p.n) g where p.name not in ('dupe');
-- the active page in another spelling (http, no www): already the course's page
update pipeline.layer4_review_items set proposed_value = jsonb_build_object('course_url', 'http://kauri.ac.nz/held/active-1/') where id = fx.u('i-active-1');
-- the later page for "refused, course has since got a page"
update catalogue.course_links set url = 'https://www.northbank.edu.au/held/later-1-new' where course_id = fx.u('c-later-1');
-- a repeat: a second waiting item on the course of cov-1, same page, raised later
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, status, escalation_reason, created_at)
select fx.u('i-dupe-1'), 'course', i.entity_id, i.field_code, i.evidence_id, i.before_value, i.proposed_value, i.layer2_state, 'pending', i.escalation_reason, i.created_at + interval '1 hour'
  from pipeline.layer4_review_items i where i.id = fx.u('i-cov-1');
-- decided before: the same page was refused by a person on 30 Oct (no new evidence on the new item)
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, before_value, proposed_value, layer2_state, status, escalation_reason, created_at, decided_at)
select fx.u('i-decided-old'), 'course', i.entity_id, i.field_code, i.before_value, i.proposed_value, i.layer2_state, 'rejected', i.escalation_reason, now() - interval '6 days', now() - interval '5 days'
  from pipeline.layer4_review_items i where i.id = fx.u('i-decided-1');

-- an approved Decision 263 rule university (Canberra): one item the rule covers, one it does not (title-only copy)
insert into catalogue.courses(id, provider_id, canonical_title, course_code, lifecycle_status, open_to_international) values
 (fx.u('c-cbr-pass'), '0e1532b8-de30-4761-87fe-460684608633', 'Course cbr pass', '777001K', 'active', true),
 (fx.u('c-cbr-fail'), '0e1532b8-de30-4761-87fe-460684608633', 'Course cbr fail', '777002K', 'active', true);
insert into catalogue.course_links(course_id, link_type, url, is_primary, status) values
 (fx.u('c-cbr-pass'), 'official_course', 'https://www.canberra.edu.au/course/s1/7/2027', true, 'active'),
 (fx.u('c-cbr-fail'), 'official_course', 'https://www.canberra.edu.au/course/s2/7/2027', true, 'active');
insert into pipeline.evidence_artifacts(id, source_url, content_hash, captured_at, metadata) values
 (fx.u('e-cbr-pass'), 'https://www.canberra.edu.au/course/s1/7', 'h-s1', now() - interval '1 day', jsonb_build_object('course_id', fx.u('c-cbr-pass'), 'identity_basis', 'cricos_code')),
 (fx.u('e-cbr-fail'), 'https://www.canberra.edu.au/course/s2/7', 'h-s2', now() - interval '1 day', jsonb_build_object('course_id', fx.u('c-cbr-fail'), 'identity_basis', 'exact_title'));
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, status, escalation_reason, created_at)
select fx.u('i-' || x), 'course', fx.u('c-' || x), 'official_course_url', fx.u('e-' || x), jsonb_build_array(l.url), jsonb_build_object('course_url', regexp_replace(l.url, '/2027$', '')),
       '{"source": "coverage sweep"}', 'pending', 'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.', now() - interval '1 day'
  from unnest(array['cbr-pass', 'cbr-fail']) x join catalogue.course_links l on l.course_id = fx.u('c-' || x);

update pipeline.platform_toolset_settings set value = '1' where key = 'layer4.evidence_link_on';
