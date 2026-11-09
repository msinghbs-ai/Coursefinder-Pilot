-- Seed for the R23/R24 fixture: synthetic records (no production rows), written through the production constraints, foreign keys and
-- triggers of schema-prod.sql + schema-live-patch.sql. Every case the change must handle has its own record.
create schema fx;
create table fx.ids (k text primary key, id uuid not null default gen_random_uuid());
insert into fx.ids(k) select unnest(array['AU','NZ','VIC','AUK','P1','P2','P3','P4','A','B','C','NOCITY','INACT','OTHERK','HIDK',
  'c1','c2','c3','c4','c5','c6','c7','c8','c9','S1','S2','S3','S4','S5','S6','S7','S8','S9','S10','S11','S12','S13','S14']);
create function fx.i(text) returns uuid language sql stable as $$ select id from fx.ids where k = $1 $$;
create table fx.before (kind text, k text, j jsonb, primary key (kind, k));

-- every provider, course and scholarship is first an entity in the PIM registry (foreign keys providers_id_fkey, courses_id_fkey,
-- scholarships_id_fkey)
insert into pim.entity_registry(id, entity_type, stable_key)
  select id, case when k ~ '^P' then 'provider' when k ~ '^c' then 'course' else 'scholarship' end, 'fx:'||k from fx.ids where k ~ '^(P|c|S)[0-9]';
insert into pipeline.platform_toolsets(key, label, kind) values ('pipeline', 'Pipeline', 'platform');
insert into ref.countries(id, iso_alpha2, iso_alpha3, name) values (fx.i('AU'),'AU','AUS','Australia'),(fx.i('NZ'),'NZ','NZL','New Zealand');
insert into ref.subdivisions(id, country_id, code, name) values (fx.i('VIC'),fx.i('AU'),'AU-VIC','Victoria'),(fx.i('AUK'),fx.i('NZ'),'NZ-AUK','Auckland');

-- providers: the live trigger provider_publish_by_default publishes every active provider on insert; P4's Published switch is then turned
-- off, as an administrator does in production
insert into catalogue.providers(id, stable_key, canonical_name, display_name, country_id, primary_city) values
  (fx.i('P1'),'provider:nzqa:7001','University of Auckland',null,fx.i('NZ'),'Auckland'),
  (fx.i('P2'),'provider:fx:no-campus','No Campus Institute',null,fx.i('AU'),null),
  (fx.i('P3'),'provider:fx:other','Other Provider Pty Ltd','Other Provider',fx.i('AU'),'Melbourne'),
  (fx.i('P4'),'provider:fx:hidden','Hidden Provider',null,fx.i('AU'),'Melbourne');
update catalogue.providers set publication_status = 'unpublished' where id = fx.i('P4');

-- P1: three campuses in the same city and region (one item today), one with a blank name, one without a city, one inactive
insert into catalogue.campuses(id, stable_key, provider_id, name, country_id, city, postcode, subdivision_id, status) values
  (fx.i('A'),'campus:fx:p1:city-campus',fx.i('P1'),'City Campus',fx.i('NZ'),'Auckland',null,fx.i('AUK'),'active'),
  (fx.i('B'),'campus:fx:p1:grafton-campus',fx.i('P1'),'Grafton Campus',fx.i('NZ'),'Auckland',null,fx.i('AUK'),'active'),
  (fx.i('C'),'campus:fx:p1:newmarket',fx.i('P1'),'  ',fx.i('NZ'),'AUCKLAND',null,fx.i('AUK'),'active'),
  (fx.i('NOCITY'),'campus:fx:p1:online',fx.i('P1'),'Online',fx.i('NZ'),null,null,null,'active'),
  (fx.i('INACT'),'campus:fx:p1:closed',fx.i('P1'),'Closed Campus',fx.i('NZ'),'Hamilton',null,fx.i('AUK'),'inactive'),
  (fx.i('OTHERK'),'campus:fx:p3:melbourne',fx.i('P3'),'Melbourne Campus',fx.i('AU'),'Melbourne','3000',fx.i('VIC'),'active'),
  (fx.i('HIDK'),'campus:fx:p4:melbourne',fx.i('P4'),'Hidden Campus',fx.i('AU'),'Melbourne','3000',fx.i('VIC'),'active');
insert into pipeline.campus_regional_class(campus_id, metro_area, category, category_name) values
  (fx.i('OTHERK'),'Melbourne',1,'Major city');

insert into catalogue.courses(id, stable_key, provider_id, canonical_title, lifecycle_status) values
  (fx.i('c1'),'course:fx:c1',fx.i('P1'),'Bachelor of Arts','active'),
  (fx.i('c2'),'course:fx:c2',fx.i('P1'),'Bachelor of Science','active'),
  (fx.i('c3'),'course:fx:c3',fx.i('P1'),'Not in the search documents','active'),
  (fx.i('c4'),'course:fx:c4',fx.i('P1'),'Held back by Layer 4','active'),
  (fx.i('c5'),'course:fx:c5',fx.i('P3'),'Another provider''s course','active'),
  (fx.i('c6'),'course:fx:c6',fx.i('P1'),'Withdrawn course','withdrawn'),
  (fx.i('c7'),'course:fx:c7',fx.i('P4'),'Hidden provider''s course','active'),
  (fx.i('c8'),'course:fx:c8',fx.i('P1'),'Blocked then unblocked','active'),
  (fx.i('c9'),'course:fx:c9',fx.i('P2'),'Course of a provider without campuses','active');
insert into search.course_documents(course_id, provider_id, country_id, provider_name, provider_stable_key, country_code, course_title, search_text,
                                    search_tsv, publication_status, study_level_code)
select fx.i(c), fx.i(p), fx.i(cc), n, sk, cc, 'Course '||c, 'Course '||c, to_tsvector('simple', 'Course '||c), 'published', 'bachelor'
  from (values ('c1','P1','NZ','University of Auckland','provider:nzqa:7001'),('c2','P1','NZ','University of Auckland','provider:nzqa:7001'),
               ('c4','P1','NZ','University of Auckland','provider:nzqa:7001'),('c5','P3','AU','Other Provider Pty Ltd','provider:fx:other'),
               ('c6','P1','NZ','University of Auckland','provider:nzqa:7001'),('c7','P4','AU','Hidden Provider','provider:fx:hidden'),
               ('c8','P1','NZ','University of Auckland','provider:nzqa:7001'),('c9','P2','AU','No Campus Institute','provider:fx:no-campus')) v(c, p, cc, n, sk);
-- Layer 4: c4 blocked from search; c8 blocked, then unblocked (the latest decision counts)
insert into pipeline.layer4_block_decisions(entity_type, entity_id, block_scope, event_type, reason_code, actor_id, created_at) values
  ('course',fx.i('c4'),'search','block','fixture_hold',gen_random_uuid(),now() - interval '2 hours'),
  ('course',fx.i('c8'),'search','block','fixture_hold',gen_random_uuid(),now() - interval '2 hours'),
  ('course',fx.i('c8'),'search','unblock','fixture_release',gen_random_uuid(),now() - interval '1 hour');
-- campus links: c1 at A in two delivery modes (two rows, one course) and at B; c2, c3, c4, c5 (another provider's course), c8 at A;
-- c6 (withdrawn) at B; c1 at the campus without a city and at the inactive campus; c7 at the hidden provider's campus
insert into catalogue.course_campuses(course_id, campus_id, delivery_mode) values
  (fx.i('c1'),fx.i('A'),'on_campus'),(fx.i('c1'),fx.i('A'),'blended'),(fx.i('c1'),fx.i('B'),'on_campus'),(fx.i('c2'),fx.i('A'),'on_campus'),
  (fx.i('c3'),fx.i('A'),'on_campus'),(fx.i('c4'),fx.i('A'),'on_campus'),(fx.i('c5'),fx.i('A'),'on_campus'),(fx.i('c8'),fx.i('A'),'on_campus'),
  (fx.i('c6'),fx.i('B'),'on_campus'),(fx.i('c1'),fx.i('NOCITY'),'online'),(fx.i('c1'),fx.i('INACT'),'on_campus'),
  (fx.i('c5'),fx.i('OTHERK'),'on_campus'),(fx.i('c7'),fx.i('HIDK'),'on_campus');

-- scholarships: one per nationality case. S12 is the hidden provider's; S14 is not published.
insert into scholarship.scholarships(id, stable_key, provider_id, name, publication_status)
  select fx.i(k), 'scholarship:fx:'||lower(k), case when k = 'S12' then fx.i('P4') else fx.i('P1') end, 'Scholarship '||k,
         case when k = 'S14' then 'unpublished' else 'published' end
    from unnest(array['S1','S2','S3','S4','S5','S6','S7','S8','S9','S10','S11','S12','S13','S14']) k;
insert into scholarship.criteria(scholarship_id, criterion_type, value_codes, human_text)
  select fx.i(k), 'student_type', array['international'], 'Open to international students'
    from unnest(array['S1','S2','S3','S4','S5','S7','S8','S9','S10','S11','S12','S13','S14']) k;
insert into scholarship.criteria(scholarship_id, criterion_type, value_codes, human_text) values
  (fx.i('S6'),'student_type',array['domestic'],'Australian and New Zealand citizens only'),
  (fx.i('S7'),'nationality',array['CN'],'Be a citizen of China'),
  (fx.i('S11'),'nationality',array['ID','VN'],'Be a citizen of one of the following countries in the Southeast Asia region'),
  (fx.i('S10'),'nationality',array['IN'],'Withdrawn criterion'),
  (fx.i('S9'),'citizenship_and_residency',array[]::text[],'Residency evidence, no country named');
update scholarship.criteria set status = 'withdrawn' where scholarship_id = fx.i('S10') and criterion_type = 'nationality';
insert into scholarship.nationality_readings(scholarship_id, codes, phrases, reader_version) values
  (fx.i('S1'),'{IN}','{"IN":"citizen of India"}','scholarship-nationality-v1'),
  (fx.i('S2'),'{R-SASIA}','{"R-SASIA":"student from South Asia"}','scholarship-nationality-v1'),
  (fx.i('S3'),'{}','{}','scholarship-nationality-v1'),
  (fx.i('S4'),'{}','{"ANY":"open to students of all nationalities"}','scholarship-nationality-v2'),
  (fx.i('S5'),'{IN}','{"IN":"Indian citizens"}','scholarship-nationality-v1'),
  (fx.i('S6'),'{}','{}','scholarship-nationality-v1'),
  (fx.i('S8'),'{}','{}','scholarship-nationality-v1'),
  (fx.i('S9'),'{}','{}','scholarship-nationality-v1'),
  (fx.i('S10'),'{}','{}','scholarship-nationality-v1'),
  (fx.i('S11'),'{}','{}','scholarship-nationality-v1'),
  (fx.i('S13'),'{VN}','{"VN":"citizens of Vietnam"}','scholarship-nationality-v1');
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status) values
  ('scholarship',fx.i('S5'),'audience','pending'),
  ('scholarship',fx.i('S13'),'nationalities','pending'),
  ('scholarship',fx.i('S9'),'award_value_text','pending'),
  ('scholarship',fx.i('S10'),'nationalities','approved'),
  ('course',fx.i('S3'),'nationalities','pending');
insert into pipeline.scholarship_ai_reviews(scholarship_id, provider_id, url, reason, status) values
  (fx.i('S8'),fx.i('P1'),'https://example.org/s8','who it is for is not proven by a quote on the page','pending'),
  (fx.i('S10'),fx.i('P1'),'https://example.org/s10','who it is for is not proven by a quote on the page','refused'),
  (fx.i('S3'),fx.i('P1'),'https://example.org/s3','the award value is not proven by a quote on the page','pending');
