-- Seed (synthetic ids, shapes as live) and the defects reproduced on the live definitions; snapshots of the live output for the
-- compatibility checks in fixtures.sql.
create schema fx;
create table fx.ids (k text primary key, id uuid not null default gen_random_uuid());
insert into fx.ids(k) select unnest(array['AU','NZ','VIC','AUK','P1','P2','P3','A','B','C','NOCITY','INACT','OTHERK',
  'c1','c2','c3','c4','c5','c6','S1','S2','S3','S4','S5','S6','S7','S8','S9','S10']);
create function fx.i(text) returns uuid language sql stable as $$ select id from fx.ids where k = $1 $$;
insert into ref.countries values (fx.i('AU'),'AU'),(fx.i('NZ'),'NZ');
insert into ref.subdivisions values (fx.i('VIC'),'AU-VIC'),(fx.i('AUK'),'NZ-AUK');
insert into catalogue.providers(id, stable_key, display_name, country_id, primary_city) values
  (fx.i('P1'),'provider:nzqa:7001','University of Auckland',fx.i('NZ'),'Auckland'),
  (fx.i('P2'),'provider:fx:none','No Campus Provider',fx.i('AU'),null),
  (fx.i('P3'),'provider:fx:other','Other Provider',fx.i('AU'),'Melbourne');
-- P1: three campuses in the same city and region (merged into one item today), one without a city, one inactive
insert into catalogue.campuses(id, stable_key, provider_id, name, city, postcode, subdivision_id, status) values
  (fx.i('A'),'campus:fx:p1:city-campus',fx.i('P1'),'City Campus','Auckland',null,fx.i('AUK'),'active'),
  (fx.i('B'),'campus:fx:p1:grafton-campus',fx.i('P1'),'Grafton Campus','Auckland',null,fx.i('AUK'),'active'),
  (fx.i('C'),'campus:fx:p1:newmarket',fx.i('P1'),'  ',  'AUCKLAND',null,fx.i('AUK'),null),
  (fx.i('NOCITY'),'campus:fx:p1:online',fx.i('P1'),'Online',null,null,null,'active'),
  (fx.i('INACT'),'campus:fx:p1:closed',fx.i('P1'),'Closed Campus','Hamilton',null,fx.i('AUK'),'inactive'),
  (fx.i('OTHERK'),'campus:fx:p3:melbourne',fx.i('P3'),'Melbourne Campus','Melbourne','3000',fx.i('VIC'),'active');
insert into catalogue.courses(id, provider_id, lifecycle_status) values
  (fx.i('c1'),fx.i('P1'),'active'),(fx.i('c2'),fx.i('P1'),'active'),(fx.i('c3'),fx.i('P1'),'active'),
  (fx.i('c4'),fx.i('P1'),'active'),(fx.i('c5'),fx.i('P3'),'active'),(fx.i('c6'),fx.i('P1'),'withdrawn');
-- returned courses: c1, c2 (c3 not in the search documents; c4 held back by Layer 4; c5 another provider's; c6 not active)
insert into search.course_documents(course_id, provider_id) values (fx.i('c1'),fx.i('P1')),(fx.i('c2'),fx.i('P1')),(fx.i('c4'),fx.i('P1')),(fx.i('c5'),fx.i('P3')),(fx.i('c6'),fx.i('P1'));
insert into security.layer4_active_blocks values (fx.i('c4'),'search','course');
insert into catalogue.course_campuses(course_id, campus_id) values
  (fx.i('c1'),fx.i('A')),(fx.i('c1'),fx.i('A')),(fx.i('c1'),fx.i('B')),(fx.i('c2'),fx.i('A')),(fx.i('c3'),fx.i('A')),(fx.i('c4'),fx.i('A')),
  (fx.i('c5'),fx.i('A')),(fx.i('c6'),fx.i('B')),(fx.i('c1'),fx.i('NOCITY')),(fx.i('c1'),fx.i('INACT')),(fx.i('c5'),fx.i('OTHERK'));
-- scholarships: one per nationality case
insert into scholarship.scholarships(id, stable_key, provider_id, name) select fx.i(k), 'scholarship:fx:'||k, fx.i('P1'), 'Scholarship '||k
  from unnest(array['S1','S2','S3','S4','S5','S6','S7','S8','S9','S10']) k;
insert into scholarship.criteria(scholarship_id, criterion_type, value_codes) select fx.i(k), 'student_type', array['international']
  from unnest(array['S1','S2','S3','S4','S5','S7','S8','S9','S10']) k;
insert into scholarship.criteria(scholarship_id, criterion_type, value_codes) values (fx.i('S6'),'student_type',array['domestic']),
  (fx.i('S7'),'nationality',array['CN']);
insert into scholarship.nationality_readings(scholarship_id, codes, phrases, reader_version) values
  (fx.i('S1'),'{IN}','{"IN":"citizen of India"}','scholarship-nationality-v1'),
  (fx.i('S2'),'{R-SASIA}','{"R-SASIA":"student from South Asia"}','scholarship-nationality-v1'),
  (fx.i('S3'),'{}','{}','scholarship-nationality-v1'),
  (fx.i('S4'),'{}','{"ANY":"open to students of all nationalities"}','scholarship-nationality-v2'),
  (fx.i('S5'),'{IN}','{"IN":"Indian citizens"}','scholarship-nationality-v1'),
  (fx.i('S6'),'{}','{}','scholarship-nationality-v1'),
  (fx.i('S8'),'{}','{}','scholarship-nationality-v1'),
  (fx.i('S9'),'{}','{}','scholarship-nationality-v1'),
  (fx.i('S10'),'{}','{}','scholarship-nationality-v1');
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status) values
  ('scholarship',fx.i('S5'),'audience','pending'),('scholarship',fx.i('S9'),'award_value_text','pending'),('scholarship',fx.i('S10'),'nationalities','approved');
insert into pipeline.scholarship_ai_reviews(scholarship_id, reason, status) values
  (fx.i('S8'),'who it is for is not proven by a quote on the page','pending'),(fx.i('S10'),'who it is for is not proven by a quote on the page','refused');

create table fx.before (kind text, k text, j jsonb);
insert into fx.before select 'campus', k, api.website_v2_provider_campuses(fx.i(k)) from unnest(array['P1','P2','P3']) k;
insert into fx.before select 'scholarship', k, api.website_v2_scholarship_item(fx.i(k)) from unnest(array['S1','S2','S3','S4','S5','S6','S7','S8','S9','S10']) k;
do $d$
declare v jsonb := (select j from fx.before where k = 'P1');
begin
  raise notice 'before (defect): provider P1 has 3 active campuses with a city; the API returns % item(s), no campus name, identity or course count: %', jsonb_array_length(v), v;
  raise notice 'before (defect): S3 (nothing held) and S4 (explicit any nationality) both return citizenship_eligibility % and %, with nothing to tell them apart',
    (select j->'citizenship_eligibility' from fx.before where k = 'S3'), (select j->'citizenship_eligibility' from fx.before where k = 'S4');
end $d$;
