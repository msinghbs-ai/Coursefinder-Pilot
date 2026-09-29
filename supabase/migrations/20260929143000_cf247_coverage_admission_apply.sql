-- CF-247 Decision 163 admission (approved 29 Sep 2026 09:56 IST): apply the admission plan in batches (official page and English).
--  * each provider's sweep source is qualified 'bounded' for official page, English and intakes (CRICOS-code pages only);
--  * 'write' rows go through public.svc_coursefacts_apply_record with the stored page as evidence;
--  * 'differs' rows raise one pending Layer 4 item per course and attribute, with a plain reason;
--  * Search gates are opened for the sweep sources, and Search is refreshed for the courses written;
--  * consumer snapshots before and after every batch that writes.
-- Runs every 10 minutes ('coverage-admit') so newly read pages are admitted continuously.
create or replace function security.coverage_admission_apply_v1(p_limit int default 300, p_extractor text default 'coverage-sweep-v0.5.4', p_attributes text[] default array['official_url','english'])
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','catalogue','pipeline','security','search' as $f$
declare r record; v_src uuid; v_ok int:=0; v_err int:=0; v_l4 int:=0; v_courses uuid[]:='{}'; v_before jsonb; v_after jsonb; v_payload jsonb; v_last text;
begin
  drop table if exists _adm;
  create temp table _adm on commit drop as select * from security.coverage_admission_plan_v1(p_extractor) where action in ('write','differs') and attribute=any(p_attributes);
  if not exists (select 1 from _adm) then return jsonb_build_object('written',0,'layer4',0); end if;

  -- qualify each provider's sweep source (bounded: CRICOS-code pages, three domains)
  insert into pipeline.course_fact_source_qualifications(source_id,country_id,source_key,source_class,authority_name,provider_cricos,admitted_domains,mapping_strategy,evidence_strategy,qualification_status,notes,metadata)
  select distinct on (s.id) s.id, s.country_id, 'au_'||lower(a.provider_cricos)||'_coverage_sweep','provider_first_party',
         coalesce(p.display_name,p.canonical_name), upper(a.provider_cricos), array['official_course_url','english_requirement','intake'],
         'course page accepted only when it prints the course''s CRICOS code',
         'page stored gzipped as evidence with its SHA-256; values written only where the course has none',
         'bounded','Decision 163 admission rule (Platform Admin 29 Sep 2026)',
         jsonb_build_object('decision','Decision 163','apply_admitted',true,'search_admitted',true,'identity_authority',false,'change_control_ref','CF-CHG-20260915-247')
    from _adm a join catalogue.providers p on p.id=a.provider_id
    cross join lateral (select security.coverage_sweep_source(a.provider_id) id) x
    join pipeline.sources s on s.id=x.id
   where a.action='write'
     and not exists (select 1 from pipeline.course_fact_source_qualifications q where q.source_id=s.id and q.provider_cricos=upper(a.provider_cricos));

  -- Search gates for the sweep sources
  insert into search.enrichment_source_gates(projection_code,domain_code,source_id,gate_status,approval_ref,approved_at,created_at,updated_at)
  select distinct 'courses', d, security.coverage_sweep_source(a.provider_id), 'approved',
         'CF-CHG-20260915-247; Decision 163 admission rule; Platform Admin approval 29 Sep 2026 09:56 IST', now(), now(), now()
    from _adm a cross join unnest(array_remove(array['official_course_url', case when 'english'=any(p_attributes) then 'course_english' end, case when 'intakes'=any(p_attributes) then 'course_intake' end],null)) d
   where a.action='write'
     and not exists (select 1 from search.enrichment_source_gates g where g.projection_code='courses' and g.domain_code=d and g.source_id=security.coverage_sweep_source(a.provider_id));

  v_before:=security.consumer_api_snapshot_v1();
  for r in select a.course_id, a.provider_id, a.provider_cricos, a.course_cricos, a.evidence_id, a.content_hash, a.page_url,
                  jsonb_object_agg(a.attribute, a.proposed) props
             from _adm a where a.action='write'
            group by 1,2,3,4,5,6,7 order by md5(a.course_id::text||clock_timestamp()::text) limit greatest(1,least(coalesce(p_limit,300),1000)) loop
    v_payload:='{}'::jsonb;
    if r.props ? 'official_url' then v_payload:=v_payload||jsonb_build_object('course_url',r.props->'official_url'->>'course_url','link_type','official_course','audience','international'); end if;
    if r.props ? 'english' then v_payload:=v_payload||jsonb_build_object('english_requirements',r.props->'english'->'english_requirements'); end if;
    if r.props ? 'intakes' then v_payload:=v_payload||jsonb_build_object('intakes',r.props->'intakes'->'intakes'); end if;
    begin
      perform public.svc_coursefacts_apply_record(security.coverage_sweep_source(r.provider_id), r.evidence_id, r.provider_cricos, r.course_cricos,
              'coverage:'||r.course_id, r.page_url, r.content_hash, v_payload, true);
      v_ok:=v_ok+1; v_courses:=v_courses||r.course_id;
    exception when others then v_err:=v_err+1; v_last:=left(sqlerrm,200);
    end;
  end loop;

  -- differences: one pending Layer 4 item per course and attribute
  insert into pipeline.layer4_review_items(entity_type,entity_id,field_code,evidence_id,before_value,proposed_value,layer2_state,layer3_state,status,escalation_reason,change_control_ref)
  select 'course', a.course_id,
         case a.attribute when 'official_url' then 'official_course_url' when 'english' then 'course_english' else 'course_intake' end,
         a.evidence_id, a.current, a.proposed, jsonb_build_object('source','coverage sweep','page',a.page_url), '{}'::jsonb, 'pending',
         case a.attribute
           when 'official_url' then 'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.'
           when 'english' then 'The course page gives a different English score from the one we hold. Please check the page and confirm the requirement.'
           else 'The course page lists different intake months from the ones we hold. Please check the page and confirm the intakes.' end,
         'CF-CHG-20260915-247'
    from _adm a
   where a.action='differs'
     and not exists (select 1 from pipeline.layer4_review_items i where i.entity_type='course' and i.entity_id=a.course_id and i.status='pending'
                       and i.field_code=case a.attribute when 'official_url' then 'official_course_url' when 'english' then 'course_english' else 'course_intake' end);
  get diagnostics v_l4=row_count;

  if cardinality(v_courses)>0 then
    perform search.refresh_course_enrichment_scoped_v1(v_courses,true);
    v_after:=security.consumer_api_snapshot_v1();
    insert into pipeline.consumer_api_baselines(label,snapshot) values
      ('before coverage admission batch ('||cardinality(v_courses)||' courses, Decision 163)',v_before),
      ('after coverage admission batch ('||cardinality(v_courses)||' courses, Decision 163)',v_after);
  end if;
  return jsonb_build_object('written',v_ok,'errors',v_err,'last_error',v_last,'layer4',v_l4);
end $f$;
revoke all on function security.coverage_admission_apply_v1(int,text,text[]) from public, anon, authenticated;
-- Intakes are held back: a hand-check of 14 sweep intake values found about 9 right ("monthly intakes except June and
-- December" read as June and December; orientation/end-date tables). They go to the Layer 3 benchmark instead.
select cron.schedule('coverage-admit','*/10 * * * *',$$select security.coverage_admission_apply_v1(300)$$);
