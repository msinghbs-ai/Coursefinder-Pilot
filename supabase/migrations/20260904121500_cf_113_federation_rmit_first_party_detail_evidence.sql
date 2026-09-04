do $block$
declare
  r record;
  v_trace pipeline.scholarship_acquisition_trace%rowtype;
  v_source_id uuid;
  v_evidence_id uuid;
  v_source_record_id uuid;
  v_hash text;
  v_payload jsonb;
begin
  for r in
    select * from (values
      ('Federation University Australia','Federation Merit Scholarship','https://www.federation.edu.au/study/scholarships/details/international/federation-merit-scholarship/',jsonb_build_object('name','2026 Federation Merit Scholarship','audience','international','student_status','new_commencing','study_levels',jsonb_build_array('Bachelor','Postgraduate'),'award_value_text','20% tuition fee reduction','academic_year',2026,'open_date','2025-11-10','close_date','2026-11-08','application_method','automatic assessment with offer','verification_method','first_party_detail_review')),
      ('Federation University Australia','Federation Global Merit Scholarship','https://www.federation.edu.au/study/scholarships/details/international/2027-global-merit-scholarship/',jsonb_build_object('name','2027 Global Merit Scholarship','audience','international','student_status','new_commencing','study_levels',jsonb_build_array('Bachelor','Postgraduate'),'award_value_text','25% tuition fee reduction','academic_year',2027,'open_date','2026-11-09','close_date','2027-11-07','application_method','automatic assessment with offer','verification_method','first_party_detail_review')),
      ('RMIT University (RMIT)','Academic Merit Scholarship for South East Asia','https://www.rmit.edu.au/scholarships/international-scholarships/academic-merit-scholarship-southeast-asia',jsonb_build_object('name','Academic Merit Scholarship for South East Asia','audience','international','award_value_text','20% of total course fee','application_status','open until places filled','eligible_regions',jsonb_build_array('Brunei Darussalam','Cambodia','Indonesia','Laos','Malaysia','Myanmar','Philippines','Singapore','Thailand','Timor-Leste','Vietnam'),'study_levels',jsonb_build_array('Vocational Education','Associate Degree','Bachelor','Graduate Certificate','Graduate Diploma','Masters by Coursework'),'verification_method','first_party_detail_review')),
      ('RMIT University (RMIT)','Future Leaders Scholarship','https://www.rmit.edu.au/scholarships/international-scholarships/future-leaders-scholarship',jsonb_build_object('name','Future Leaders Scholarship','audience','international','award_value_text','20% tuition fee reduction','intake_from',2026,'eligible_regions',jsonb_build_array('India','Sri Lanka','Bangladesh','Bhutan','Nepal','Pakistan'),'study_levels',jsonb_build_array('Bachelor','Masters by Coursework'),'application_method','no separate scholarship application required','verification_method','first_party_detail_review'))
    ) as x(provider_name,observed_title,detail_url,payload)
  loop
    select t.* into v_trace
    from pipeline.scholarship_acquisition_trace t
    join catalogue.providers p on p.id=t.provider_id
    where p.canonical_name=r.provider_name and t.observed_title=r.observed_title and t.first_party_detail_url=r.detail_url
    order by t.updated_at desc limit 1;
    if v_trace.id is null then continue; end if;

    select s.id into v_source_id
    from pipeline.sources s
    where s.provider_id=v_trace.provider_id and s.status='active'
      and s.source_type in ('web_catalogue','provider_course_page') and s.url not ilike '%hotcourses%'
    order by s.trust_rank desc nulls last,s.updated_at desc limit 1;
    if v_source_id is null then continue; end if;

    v_payload:=r.payload||jsonb_build_object('source_url',r.detail_url,'authority','first_party_university','provider_id',v_trace.provider_id,'observed_title',r.observed_title,'change_control_ref','CF-CHG-20260904-113');
    v_hash:=md5(v_payload::text);

    select e.id into v_evidence_id from pipeline.evidence_artifacts e
    where e.source_id=v_source_id and e.source_url=r.detail_url and e.content_hash=v_hash order by e.captured_at desc limit 1;
    if v_evidence_id is null then
      insert into pipeline.evidence_artifacts(source_id,evidence_type,source_url,content_hash,mime_type,metadata,retention_class,review_state,capture_version)
      values(v_source_id,'first_party_web_verification',r.detail_url,v_hash,'application/json',v_payload||jsonb_build_object('capture_scope','structured_verified_facts'),'governed_source','verified',1)
      returning id into v_evidence_id;
    end if;

    select sr.id into v_source_record_id from pipeline.scholarship_source_records sr
    where sr.source_id=v_source_id and sr.source_record_id='first-party:'||v_trace.id::text and sr.content_hash=v_hash order by sr.created_at desc limit 1;
    if v_source_record_id is null then
      insert into pipeline.scholarship_source_records(source_id,source_record_id,source_record_url,source_provider_id,source_provider_name,content_hash,evidence_id,payload,status)
      values(v_source_id,'first-party:'||v_trace.id::text,r.detail_url,v_trace.provider_id::text,r.provider_name,v_hash,v_evidence_id,v_payload,'captured')
      returning id into v_source_record_id;
    end if;

    update pipeline.scholarship_acquisition_trace
    set verification_evidence_id=v_evidence_id,source_record_id=v_source_record_id,stage='detail_acquired',verification_status='verified_first_party',
        verified_at=coalesce(verified_at,now()),updated_at=now(),metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('detail_evidence','captured','change_control_ref','CF-CHG-20260904-113')
    where id=v_trace.id;
  end loop;
end
$block$;
