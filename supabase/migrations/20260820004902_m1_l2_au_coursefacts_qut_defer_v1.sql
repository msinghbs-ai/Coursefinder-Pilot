begin;
update pipeline.course_fact_source_qualifications
set qualification_status='deferred',metadata=metadata||jsonb_build_object('gate_result','deferred','apply_admitted',false,'search_admitted',false,'runtime_fetch_status',403,'runtime_fetch_attempts',2,'worker_version','coursefacts-au-qut-v0.1.1','defer_reason','Official QUT course pages return HTTP 403 to the production Supabase Edge runtime, including browser-equivalent request headers; no bypass attempted.'),notes='Authoritative public source verified, but production runtime acquisition is blocked by HTTP 403. Source remains deferred until an authorised stable first-party acquisition path is available.',updated_at=now()
where source_key='au_qut_official_course_pages';
commit;
