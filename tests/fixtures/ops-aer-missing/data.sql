-- the eight universities of the missing-university strategy (catalogue ids as live), plus RMIT and UWA as source-present recovery cases
insert into catalogue.providers(id, display_name, country_id, provider_type_id, publication_status, enrols_international, website)
select v.id::uuid, v.nm, 'a0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-000000000001', 'published', true, v.site from (values
  ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2', 'Charles Darwin University', 'https://www.cdu.edu.au'),
  ('c5c5d225-3d4c-4e41-8275-78eddd261073', 'Deakin University (Deakin)', 'https://www.deakin.edu.au'),
  ('fa0e0d13-838a-42ff-b6a3-9cea84bd80b2', 'University of New England', 'https://www.une.edu.au'),
  ('fec52f92-a8a3-4de8-a862-06f355e4e2f7', 'Torrens University Australia', 'https://www.torrens.edu.au'),
  ('030992c3-72c6-452d-8a3b-10ceb0fd77f2', 'Australian Catholic University', 'https://www.acu.edu.au'),
  ('fe6af182-f5ca-4a3c-bfb4-b0773ff1b113', 'James Cook University', 'https://www.jcu.edu.au'),
  ('f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6', 'Central Queensland University', 'https://www.cqu.edu.au'),
  ('551383f9-7732-4588-a843-dd2b97c13f6f', 'University of Southern Queensland', 'https://www.unisq.edu.au')) v(id, nm, site)
on conflict (id) do nothing;
-- active courses with bound pages at Deakin (course-page route while the site is blocked)
insert into catalogue.courses(provider_id, canonical_title, publication_status, open_to_international)
select 'c5c5d225-3d4c-4e41-8275-78eddd261073', 'Deakin course ' || g, 'unpublished', true from generate_series(1, 4) g;
insert into pipeline.aer_course_outcomes(course_id, provider_id, country, provider_published, outcome, detail, course_url, page_status, built_at)
select c.id, c.provider_id, 'AU', true, 'awaiting_review', 'fixture', 'https://www.deakin.edu.au/course/x' || c.canonical_title, 'bound', now()
  from catalogue.courses c where c.provider_id = 'c5c5d225-3d4c-4e41-8275-78eddd261073';
create table if not exists pipeline.admin_control_events(id bigserial primary key, at timestamptz not null default now(), area text, action text, target text, detail jsonb);
