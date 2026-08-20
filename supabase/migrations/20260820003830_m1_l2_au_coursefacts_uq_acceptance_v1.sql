begin;

update pipeline.course_fact_source_qualifications
set qualification_status='qualified',
    metadata=metadata||jsonb_build_object('gate_result','pass','qualified_at',now(),'source_class_uat','passed','apply_admitted',true,'search_admitted',false,'canonical_replay','passed','ambiguity_rejection','passed'),
    updated_at=now()
where source_key='au_uq_official_program_pages';

update pipeline.sources s
set metadata=s.metadata||jsonb_build_object('facts',jsonb_build_array('course_link','international_fee','intake','english_requirement'),'course_identity','exact_cricos_course_code'),updated_at=now()
where s.id in (
  select source_id from pipeline.course_fact_source_qualifications
  where source_key in ('au_rmit_official_course_pages','au_uq_official_program_pages')
);

commit;