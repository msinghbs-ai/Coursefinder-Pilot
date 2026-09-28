-- CF-247 Decision 162 step 4 (Platform Admin approval, 29 Sep 2026): open the Search gate for course English
-- requirements from the UQ English-requirements source (Procedure Table 1 and Table 3). Evidence: 54 courses
-- written through the governed path (Pilot PR #166); Table 1 agreed with UQ course pages 40/40 and the minimum
-- 149/150; no existing value changed. Consumer snapshots are recorded before and after; Search enrichment is
-- refreshed for the affected courses.
do $gate$
declare v_before jsonb; v_after jsonb; v_n int; v_courses uuid[];
begin
  v_before:=security.consumer_api_snapshot_v1();
  insert into search.enrichment_source_gates(projection_code,domain_code,source_id,gate_status,approval_ref,approved_at,created_at,updated_at)
  select 'courses','course_english',s.id,'approved',
         'CF-CHG-20260915-247; Decision 162 step 4; Platform Admin approval 29 Sep 2026; source qualification '||q.source_key, now(), now(), now()
    from pipeline.sources s join pipeline.course_fact_source_qualifications q on q.source_id=s.id and q.qualification_status='qualified'
   where s.source_type='provider_english_requirements' and s.metadata->>'provider_cricos'='00025B'
     and not exists (select 1 from search.enrichment_source_gates g where g.projection_code='courses' and g.domain_code='course_english' and g.source_id=s.id);
  get diagnostics v_n=row_count;
  if v_n<>1 then raise exception 'expected 1 new Search gate, got %; nothing changed', v_n; end if;
  update pipeline.course_fact_source_qualifications q set metadata=q.metadata||jsonb_build_object('search_admitted',true,'search_gate','approved 29 Sep 2026 (Decision 162 step 4)'), updated_at=now()
   where exists (select 1 from pipeline.sources s where s.id=q.source_id and s.source_type='provider_english_requirements' and s.metadata->>'provider_cricos'='00025B');
  select array_agg(distinct r.course_id) into v_courses from catalogue.course_english_requirements r join pipeline.sources s on s.id=r.source_id
   where s.source_type='provider_english_requirements' and r.status='active';
  perform search.refresh_course_enrichment_scoped_v1(v_courses,true);
  v_after:=security.consumer_api_snapshot_v1();
  insert into pipeline.consumer_api_baselines(label,snapshot) values
    ('before Search gate for UQ English requirements (Decision 162 step 4)',v_before),
    ('after Search gate for UQ English requirements (Decision 162 step 4)',v_after);
end $gate$;
