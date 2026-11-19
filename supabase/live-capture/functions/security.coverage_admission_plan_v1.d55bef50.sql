CREATE OR REPLACE FUNCTION security.coverage_admission_plan_v1(p_extractor text DEFAULT 'coverage-sweep-v0.5.3'::text)
 RETURNS TABLE(course_id uuid, provider_id uuid, provider_cricos text, course_cricos text, evidence_id uuid, content_hash text, page_url text, attribute text, action text, proposed jsonb, current jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security'
AS $function$
  with pg as (
    select p.course_id, p.provider_id, p.url, p.evidence_id, p.candidates c, e.content_hash, p.identity_basis ib,
           (select pr.registration_code from catalogue.provider_registrations pr where pr.provider_id=p.provider_id and lower(pr.registration_scheme)='cricos' and coalesce(pr.status,'active') not in ('inactive','cancelled','archived') order by pr.checked_at desc nulls last limit 1) pc,
           (select cr.registration_code from catalogue.course_registrations cr where cr.course_id=p.course_id and lower(cr.scheme)='cricos' limit 1) cc
      from pipeline.coverage_course_pages p join pipeline.evidence_artifacts e on e.id=p.evidence_id
      join catalogue.courses co on co.id=p.course_id and co.lifecycle_status='active'
     where p.read_status='read' and security.coverage_identity_allowed(p.provider_id, p.identity_basis, null) and p.candidates->>'extractor'=p_extractor
       and not security.layer4_entity_or_parent_blocked('course',p.course_id,'operational')
       and not security.course_held_v1(p.course_id)),  -- SS-007 (1 Nov 2026): a course under an open binding remediation hold is never admitted from its page
  url as (
    select pg.*, 'official_url'::text attribute,
           jsonb_build_object('course_url',coalesce(nullif(pg.c->>'final_url',''),pg.url)) proposed,
           (select jsonb_agg(l.url) from catalogue.course_links l where l.course_id=pg.course_id and l.link_type='official_course' and l.status='active') cur
      from pg where security.coverage_identity_allowed(pg.provider_id, pg.ib, 'official_url')),
  eng as (
    select pg.*, 'english'::text attribute,
           jsonb_build_object('english_requirements',
             (select jsonb_agg(x) from (
                select jsonb_build_object('test_code','IELTS','overall_score',(pg.c->'english'->>'ielts_overall')::numeric,
                         'component_scores',case when pg.c->'english' ? 'ielts_min_band' then jsonb_build_object('listening',(pg.c->'english'->>'ielts_min_band')::numeric,'reading',(pg.c->'english'->>'ielts_min_band')::numeric,'writing',(pg.c->'english'->>'ielts_min_band')::numeric,'speaking',(pg.c->'english'->>'ielts_min_band')::numeric) else '{}'::jsonb end,
                         'notes','Course page (CRICOS code on page), coverage sweep') x where pg.c->'english' ? 'ielts_overall'
                union all select jsonb_build_object('test_code','PTE','overall_score',(pg.c->'english'->>'pte_overall')::numeric,'notes','Course page (CRICOS code on page), coverage sweep') where pg.c->'english' ? 'pte_overall'
                union all select jsonb_build_object('test_code','TOEFL_IBT','overall_score',(pg.c->'english'->>'toefl_overall')::numeric,'notes','Course page (CRICOS code on page), coverage sweep') where pg.c->'english' ? 'toefl_overall') q)) proposed,
           (select jsonb_agg(jsonb_build_object('test',t.code,'overall',r.overall_score)) from catalogue.course_english_requirements r join ref.english_tests t on t.id=r.english_test_id where r.course_id=pg.course_id and r.status='active') cur
      from pg where pg.c->'english' ?| array['ielts_overall','pte_overall','toefl_overall'] and security.coverage_identity_allowed(pg.provider_id, pg.ib, 'english') and (coalesce(pg.c->>'english_by','')<>'adapter' or exists (select 1 from pipeline.uni_adapters u where u.provider_id=pg.provider_id and u.enabled and u.admit and 'english' = any (u.admit_fields)))),
  itk as (
    select pg.*, 'intakes'::text attribute,
           jsonb_build_object('intakes',(select jsonb_agg(jsonb_build_object('intake_label',m,'source_intake_key',lower(pg.cc)||':current:'||lower(m))) from jsonb_array_elements_text(pg.c->'intakes') mm(m))) proposed,
           (select jsonb_agg(i.intake_label) from catalogue.course_intakes i where i.course_id=pg.course_id and coalesce(i.status,'active')='active') cur
      from pg where jsonb_array_length(coalesce(pg.c->'intakes','[]'))>0 and security.coverage_identity_allowed(pg.provider_id, pg.ib, 'intakes') and pg.c->>'intakes_by'='adapter' and exists (select 1 from pipeline.uni_adapters u where u.provider_id=pg.provider_id and u.enabled and u.admit and 'intakes' = any (u.admit_fields))),
  allx as (select * from url union all select * from eng union all select * from itk)
  select a.course_id, a.provider_id, a.pc, a.cc, a.evidence_id, a.content_hash, a.url, a.attribute,
         case
           when (a.pc is null or a.cc is null) and security.coverage_country(a.provider_id) = 'AU' then 'unresolved'
           when a.cur is null then 'write'
           when a.attribute='official_url' and exists (select 1 from jsonb_array_elements_text(a.cur) k(v) where security.coverage_norm_url(k.v)=security.coverage_norm_url(a.proposed->>'course_url')) then 'same'
           when a.attribute='english' and not exists (
                  select 1 from jsonb_array_elements(a.proposed->'english_requirements') r(p)
                   where not exists (select 1 from jsonb_array_elements(a.cur) k(v) where k.v->>'test'=p->>'test_code' and (k.v->>'overall')::numeric=(p->>'overall_score')::numeric)
                     and exists (select 1 from jsonb_array_elements(a.cur) k(v) where k.v->>'test'=p->>'test_code')) then 'same'
           when a.attribute='intakes' and not exists (
                  select 1 from jsonb_array_elements(a.proposed->'intakes') r(p)
                   where not exists (select 1 from jsonb_array_elements_text(a.cur) k(v) where k.v ilike '%'||(p->>'intake_label')||'%')) then 'same'
           else 'differs' end,
         a.proposed, a.cur
    from allx a
$function$
