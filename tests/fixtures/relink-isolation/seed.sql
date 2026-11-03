-- seed: three universities with refused course pages (fixture data only)
--   U2 (most pages, first in the order): 6 courses, 300 stored addresses (exact slugs, title matches, noise), a page swap and a blocked page
--   U1 (second): 3 courses whose titles make course_relink_slugs_v1 slow ("Slow")
--   U3 (third): 2 courses with exact stored addresses
insert into catalogue.providers(id, stable_key, canonical_name, country_id) values
 ('00000000-0000-0000-0000-0000000000a1', 'u1', 'University One', '00000000-0000-0000-0000-0000000000aa'),
 ('00000000-0000-0000-0000-0000000000a2', 'u2', 'University Two', '00000000-0000-0000-0000-0000000000aa'),
 ('00000000-0000-0000-0000-0000000000a3', 'u3', 'University Three', '00000000-0000-0000-0000-0000000000aa');
insert into catalogue.courses(id, stable_key, provider_id, canonical_title)
select ('00000000-0000-0000-0002-00000000000' || n)::uuid, 'c2' || n, '00000000-0000-0000-0000-0000000000a2', t
  from (values (1, 'Bachelor of Applied Science'), (2, 'Master of Engineering Practice'), (3, 'Graduate Diploma of Teaching'),
               (4, 'Bachelor of Nursing Science'), (5, 'Diploma of Applied Languages'), (6, 'Master of Public Health Policy')) v(n, t);
insert into catalogue.courses(id, stable_key, provider_id, canonical_title)
select ('00000000-0000-0000-0001-00000000000' || n)::uuid, 'c1' || n, '00000000-0000-0000-0000-0000000000a1', 'Slow Bachelor of Arts Number ' || n from generate_series(1, 3) n;
insert into catalogue.courses(id, stable_key, provider_id, canonical_title)
select ('00000000-0000-0000-0003-00000000000' || n)::uuid, 'c3' || n, '00000000-0000-0000-0000-0000000000a3', 'Bachelor of Commerce Studies ' || n from generate_series(1, 2) n;
insert into pipeline.coverage_course_pages(course_id, provider_id, read_status, url, candidates)
select c.id, c.provider_id, 'identity_mismatch', 'https://' || c.stable_key || '.example/old/' || c.stable_key, null from catalogue.courses c;
-- U2: a refused page of course 6 whose title is course 1's title (page swap for course 1)
update pipeline.coverage_course_pages set candidates = '{"h1": "Bachelor of Applied Science", "page_title": "Something else | U2"}' where course_id = '00000000-0000-0000-0002-000000000006';
-- U2 stored addresses: exact slugs for courses 2 and 3 (one in the discovery links), a title-only match for course 4, 300 noise addresses
insert into pipeline.coverage_provider_urls(provider_id, url, title) values
 ('00000000-0000-0000-0000-0000000000a2', 'https://u2.example/study/master-of-engineering-practice', 'Master of Engineering Practice | U2'),
 ('00000000-0000-0000-0000-0000000000a2', 'https://u2.example/courses/c/4411', 'Bachelor of Nursing Science - U2'),
 ('00000000-0000-0000-0000-0000000000a2', 'https://u2.example/study/blocked/master-of-public-health-policy.html', null);
insert into pipeline.provider_discovery_links(provider_id, url, anchor_text) values
 ('00000000-0000-0000-0000-0000000000a2', 'https://u2.example/study/graduate-diploma-of-teaching/', 'Graduate Diploma of Teaching'),
 ('00000000-0000-0000-0000-0000000000a2', 'https://u2.example/study/master-of-engineering-practice', 'Engineering');
insert into pipeline.coverage_provider_urls(provider_id, url, title)
select '00000000-0000-0000-0000-0000000000a2', 'https://u2.example/page/' || n, 'Page ' || n from generate_series(1, 300) n;
insert into pipeline.course_page_blocks(course_id, url) values ('00000000-0000-0000-0002-000000000006', 'https://u2.example/study/blocked/master-of-public-health-policy.html');
-- U1 and U3 stored addresses
insert into pipeline.coverage_provider_urls(provider_id, url, title)
select '00000000-0000-0000-0000-0000000000a1', 'https://u1.example/study/slow-bachelor-of-arts-number-' || n, null from generate_series(1, 3) n;
insert into pipeline.coverage_provider_urls(provider_id, url, title)
select '00000000-0000-0000-0000-0000000000a3', 'https://u3.example/study/bachelor-of-commerce-studies-' || n, null from generate_series(1, 2) n;
-- extra refused pages so the order is U2 (most), U1, U3
insert into pipeline.coverage_course_pages(course_id, provider_id, read_status)
select gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1', 'not_found' from generate_series(1, 1);
