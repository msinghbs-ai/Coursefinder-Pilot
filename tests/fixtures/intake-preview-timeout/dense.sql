-- Controlled regression: candidates have proved page evidence, unlike the old no-evidence skew shortcut.
-- The first 150 low-sorting candidates reach E16. Their month-only wording remains ineligible.
update catalogue.courses set course_code='DC'||right(id::text,12), study_level_id=(select id from ref.study_levels where code='masters_coursework'), canonical_title='Master of Dense Identity '||right(id::text,12)
where id in(select id from catalogue.courses where id::text like '00000000-%' order by id limit 150);
insert into pipeline.evidence_artifacts(id,storage_path,source_url)
select md5('dense evidence '||id)::uuid,'fixture/dense/'||id||'.html','https://fixture1.edu.au/study/master-of-dense-identity-'||right(id::text,12)||'-'||lower(course_code)
from catalogue.courses where course_code like 'DC%';
alter table pipeline.coverage_course_pages disable trigger coverage_page_refused_host;
insert into pipeline.coverage_course_pages(course_id,provider_id,url,basis,status,read_status,identity_basis,evidence_id,candidates)
select c.id,c.provider_id,e.source_url,'cricos_search','bound','read','cricos_code',e.id,
jsonb_build_object('page_title',c.canonical_title||' ('||c.course_code||')','final_url',e.source_url,'intake_context','["March intake only"]'::jsonb)
from catalogue.courses c join pipeline.evidence_artifacts e on e.id=md5('dense evidence '||c.id)::uuid where c.course_code like 'DC%';
alter table pipeline.coverage_course_pages enable trigger coverage_page_refused_host;
update catalogue.course_intakes i set evidence_id=md5('dense evidence '||course_id)::uuid where course_id in(select id from catalogue.courses where course_code like 'DC%');
analyze catalogue.courses; analyze pipeline.coverage_course_pages; analyze catalogue.course_intakes;
