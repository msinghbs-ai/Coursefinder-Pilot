begin;
update pipeline.course_fact_source_qualifications
set metadata=metadata||jsonb_build_object('worker_version','coursefacts-au-uq-v0.3.0','qualified_course_count',8,'coverage_expansion_v3_uat','passed','coverage_expanded_at',now(),'search_admitted',false),updated_at=now()
where source_key='au_uq_official_program_pages' and qualification_status='qualified';
commit;
