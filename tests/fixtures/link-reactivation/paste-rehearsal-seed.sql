-- IQ-00043 paste rehearsal: the measured 13 (real link and course ids, as live on 3 Nov 2026 08:56) on fixtures; the paste file and its
-- rollback are then run unchanged by run.sh. Pages are placeholders; the shape is as live (kept page primary, fragment spelling re-activated).
\set ON_ERROR_STOP 1
insert into catalogue.courses(id, provider_id, course_code) values
  ('15b68867-632a-4c4a-96c9-abda0d49df34', '00000000-0000-0000-0000-0000000000bb', 'LT0'),
  ('1b27f371-1e3e-47ed-8ae5-0dbb608d31be', '00000000-0000-0000-0000-0000000000bb', 'LT1'),
  ('8396b2f9-30f6-48ef-b2df-ffedd27dcb4a', '00000000-0000-0000-0000-0000000000bb', 'LT2'),
  ('850532eb-766b-4ea7-bfa2-bad1781a09f1', '00000000-0000-0000-0000-0000000000bb', 'LT3'),
  ('9975e97b-dbd9-40ff-ae7d-3478f4db060f', '00000000-0000-0000-0000-0000000000bb', 'LT4'),
  ('aa948937-8653-4992-b820-87c82d31d02c', '00000000-0000-0000-0000-0000000000bb', 'LT5'),
  ('b6b4bfc1-bc55-4141-a5d1-be3b617d2b90', '00000000-0000-0000-0000-0000000000bb', 'LT6'),
  ('b7dc6d45-24a6-40cf-8396-62f81064be2e', '00000000-0000-0000-0000-0000000000bb', 'LT7'),
  ('c0c35720-8ff4-4751-90a4-961a826ec582', '00000000-0000-0000-0000-0000000000bb', 'LT8'),
  ('cf8be5ef-5bec-4f02-8b9a-ed4135376ac3', '00000000-0000-0000-0000-0000000000bb', 'LT9'),
  ('e41b6960-d986-4780-82ab-21bbe0a03294', '00000000-0000-0000-0000-0000000000bb', 'LT10'),
  ('e6d0e1c3-32eb-4673-a67e-ef4a6625f9ea', '00000000-0000-0000-0000-0000000000bb', 'LT11'),
  ('e87ae579-e345-4edf-9b4a-6a07b6b23c48', '00000000-0000-0000-0000-0000000000bb', 'LT12');
insert into catalogue.course_links(course_id, link_type, url, is_primary, status, source_id) values
  ('15b68867-632a-4c4a-96c9-abda0d49df34', 'official_course', 'https://www.latrobe.edu.au/courses/p0', true, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('1b27f371-1e3e-47ed-8ae5-0dbb608d31be', 'official_course', 'https://www.latrobe.edu.au/courses/p1', true, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('8396b2f9-30f6-48ef-b2df-ffedd27dcb4a', 'official_course', 'https://www.latrobe.edu.au/courses/p2', true, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('850532eb-766b-4ea7-bfa2-bad1781a09f1', 'official_course', 'https://www.latrobe.edu.au/courses/p3', true, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('9975e97b-dbd9-40ff-ae7d-3478f4db060f', 'official_course', 'https://www.latrobe.edu.au/courses/p4', true, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('aa948937-8653-4992-b820-87c82d31d02c', 'official_course', 'https://www.latrobe.edu.au/courses/p5', true, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('b6b4bfc1-bc55-4141-a5d1-be3b617d2b90', 'official_course', 'https://www.latrobe.edu.au/courses/p6', true, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('b7dc6d45-24a6-40cf-8396-62f81064be2e', 'official_course', 'https://www.latrobe.edu.au/courses/p7', true, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('c0c35720-8ff4-4751-90a4-961a826ec582', 'official_course', 'https://www.latrobe.edu.au/courses/p8', true, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('cf8be5ef-5bec-4f02-8b9a-ed4135376ac3', 'official_course', 'https://www.latrobe.edu.au/courses/p9', true, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('e41b6960-d986-4780-82ab-21bbe0a03294', 'official_course', 'https://www.latrobe.edu.au/courses/p10', true, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('e6d0e1c3-32eb-4673-a67e-ef4a6625f9ea', 'official_course', 'https://www.latrobe.edu.au/courses/p11', true, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('e87ae579-e345-4edf-9b4a-6a07b6b23c48', 'official_course', 'https://www.latrobe.edu.au/courses/p12', true, 'active', '00000000-0000-0000-0000-00000000005a');
insert into catalogue.course_links(id, course_id, link_type, url, is_primary, status, source_id) values
  ('b742bbd0-896a-446f-bfdc-04c15d697a54', '15b68867-632a-4c4a-96c9-abda0d49df34', 'official_course', 'https://www.latrobe.edu.au/courses/p0#/overview?studentType=int', false, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('c4a81adb-2fae-4d0f-b3df-fb60cc54f287', '1b27f371-1e3e-47ed-8ae5-0dbb608d31be', 'official_course', 'https://www.latrobe.edu.au/courses/p1#/overview?studentType=int', false, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('8778302e-4ed5-41ea-b92c-293f91355d49', '8396b2f9-30f6-48ef-b2df-ffedd27dcb4a', 'official_course', 'https://www.latrobe.edu.au/courses/p2#/overview?studentType=int', false, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('f26f995c-9566-4b0a-ac59-e2df65566da1', '850532eb-766b-4ea7-bfa2-bad1781a09f1', 'official_course', 'https://www.latrobe.edu.au/courses/p3#/overview?studentType=int', false, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('d0ef4f13-b9ea-4a34-8701-bb91a518e60a', '9975e97b-dbd9-40ff-ae7d-3478f4db060f', 'official_course', 'https://www.latrobe.edu.au/courses/p4#/overview?studentType=int', false, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('42d55182-a0e7-4a62-af44-f96611216ae9', 'aa948937-8653-4992-b820-87c82d31d02c', 'official_course', 'https://www.latrobe.edu.au/courses/p5#/overview?studentType=int', false, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('be0436ae-f7b6-4167-a9f3-13f955242f27', 'b6b4bfc1-bc55-4141-a5d1-be3b617d2b90', 'official_course', 'https://www.latrobe.edu.au/courses/p6#/overview?studentType=int', false, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('06d3e2ce-54b8-44a6-9476-2684063f619c', 'b7dc6d45-24a6-40cf-8396-62f81064be2e', 'official_course', 'https://www.latrobe.edu.au/courses/p7#/overview?studentType=int', false, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('ce12ebcf-f554-44af-b802-7515ec0680ea', 'c0c35720-8ff4-4751-90a4-961a826ec582', 'official_course', 'https://www.latrobe.edu.au/courses/p8#/overview?studentType=int', false, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('80651f64-b8ad-40e4-bb6c-d8c51580e0af', 'cf8be5ef-5bec-4f02-8b9a-ed4135376ac3', 'official_course', 'https://www.latrobe.edu.au/courses/p9#/overview?studentType=int', false, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('c3cecd39-6578-48c3-a24d-d3c81ccee2a5', 'e41b6960-d986-4780-82ab-21bbe0a03294', 'official_course', 'https://www.latrobe.edu.au/courses/p10#/overview?studentType=int', false, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('041158b3-aeac-42a6-8006-cf2017bb5470', 'e6d0e1c3-32eb-4673-a67e-ef4a6625f9ea', 'official_course', 'https://www.latrobe.edu.au/courses/p11#/overview?studentType=int', false, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('1418d09f-9dbf-4d72-b180-7463758c898f', 'e87ae579-e345-4edf-9b4a-6a07b6b23c48', 'official_course', 'https://www.latrobe.edu.au/courses/p12#/overview?studentType=int', false, 'active', '00000000-0000-0000-0000-00000000005a');
insert into pipeline.admin_control_events(id, area, action, target, detail, created_at) values (28622, 'housekeeping', 'h01_duplicate_link_tranche', 'catalogue.course_links', '{"made_inactive":["b742bbd0-896a-446f-bfdc-04c15d697a54","c4a81adb-2fae-4d0f-b3df-fb60cc54f287","8778302e-4ed5-41ea-b92c-293f91355d49","f26f995c-9566-4b0a-ac59-e2df65566da1","d0ef4f13-b9ea-4a34-8701-bb91a518e60a","42d55182-a0e7-4a62-af44-f96611216ae9","be0436ae-f7b6-4167-a9f3-13f955242f27","06d3e2ce-54b8-44a6-9476-2684063f619c","ce12ebcf-f554-44af-b802-7515ec0680ea","80651f64-b8ad-40e4-bb6c-d8c51580e0af","c3cecd39-6578-48c3-a24d-d3c81ccee2a5","041158b3-aeac-42a6-8006-cf2017bb5470","1418d09f-9dbf-4d72-b180-7463758c898f"]}', '2026-11-02 04:57:26+00');
select search.refresh_course_enrichment_scoped_v1(array(select id from catalogue.courses), true);
