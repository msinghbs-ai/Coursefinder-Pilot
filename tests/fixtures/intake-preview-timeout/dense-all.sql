-- Dense evidence in every calendar-backed university's pending rows, not only the largest provider.
update catalogue.courses set course_code='DX'||replace(id::text,'-',''),study_level_id=(select id from ref.study_levels where code='masters_coursework'),canonical_title='Master of Dense Page '||id
where id::text like 'ffffffff-%' and provider_id<>md5('nocal')::uuid;
insert into pipeline.evidence_artifacts(id,storage_path,source_url)
select md5('dense evidence '||c.id)::uuid,'fixture/dense/'||c.id||'.html',p.website||'/study/master-of-dense-page-'||c.id||'-'||lower(c.course_code)
from catalogue.courses c join catalogue.providers p on p.id=c.provider_id where c.course_code like 'DX%';
alter table pipeline.coverage_course_pages disable trigger coverage_page_refused_host;
insert into pipeline.coverage_course_pages(course_id,provider_id,url,basis,status,read_status,identity_basis,evidence_id,candidates)
select c.id,c.provider_id,e.source_url,'cricos_search','bound','read','cricos_code',e.id,
jsonb_build_object('page_title',c.canonical_title||' ('||c.course_code||')','final_url',e.source_url,'intake_context','["March intake only"]'::jsonb)
from catalogue.courses c join pipeline.evidence_artifacts e on e.id=md5('dense evidence '||c.id)::uuid where c.course_code like 'DX%';
alter table pipeline.coverage_course_pages enable trigger coverage_page_refused_host;
update catalogue.course_intakes set evidence_id=md5('dense evidence '||course_id)::uuid where course_id in(select id from catalogue.courses where course_code like 'DX%');
analyze catalogue.courses;analyze pipeline.coverage_course_pages;analyze catalogue.course_intakes;
