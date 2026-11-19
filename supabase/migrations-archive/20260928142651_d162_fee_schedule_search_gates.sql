-- CF-247 Decision 162 (Platform Admin approval, 28 Sep 2026): open the Search gate for provider tuition from the
-- four provider fee-schedule sources (Federation 00103D, Western Sydney 00917K, Charles Darwin 00300K, Swinburne
-- 00111D). Evidence: 426 schedule fees applied through the governed path; values match the published PDFs; no
-- course has two current tuitions. Consumer snapshots are recorded before and after; Search enrichment is
-- refreshed for the affected courses.
do $gate$
declare v_before jsonb; v_after jsonb; v_n int; v_courses uuid[];
begin
  v_before:=security.consumer_api_snapshot_v1();
  insert into search.enrichment_source_gates(projection_code,domain_code,source_id,gate_status,approval_ref,approved_at,created_at,updated_at)
  select 'courses','provider_current_tuition',s.id,'approved',
         'CF-CHG-20260915-247; Decision 162; Platform Admin approval 28 Sep 2026; source qualification '||q.source_key, now(), now(), now()
    from pipeline.sources s join pipeline.course_fact_source_qualifications q on q.source_id=s.id and q.qualification_status='qualified'
   where s.source_type='provider_fee_schedule' and s.metadata->>'provider_cricos' in ('00103D','00917K','00300K','00111D')
     and not exists (select 1 from search.enrichment_source_gates g where g.projection_code='courses' and g.domain_code='provider_current_tuition' and g.source_id=s.id);
  get diagnostics v_n=row_count;
  if v_n<>4 then raise exception 'expected 4 new Search gates, got %; nothing changed', v_n; end if;
  update pipeline.course_fact_source_qualifications q set metadata=q.metadata||jsonb_build_object('search_admitted',true,'search_gate','approved 28 Sep 2026 (Decision 162)'), updated_at=now()
   where exists (select 1 from pipeline.sources s where s.id=q.source_id and s.source_type='provider_fee_schedule');
  select array_agg(distinct f.course_id) into v_courses from catalogue.course_fees f join pipeline.sources s on s.id=f.source_id
   where s.source_type='provider_fee_schedule' and f.status='active';
  perform search.refresh_course_enrichment_scoped_v1(v_courses,true);
  v_after:=security.consumer_api_snapshot_v1();
  insert into pipeline.consumer_api_baselines(label,snapshot) values
    ('before Search gates for provider fee schedules (Decision 162)',v_before),
    ('after Search gates for provider fee schedules (Decision 162)',v_after);
end $gate$;
