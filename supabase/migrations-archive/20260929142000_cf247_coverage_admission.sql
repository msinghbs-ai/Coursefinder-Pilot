-- CF-247 Decision 163 admission rule (Platform Admin approval 29 Sep 2026 09:56 IST):
-- values found by the coverage sweep are admitted only from pages that print the course's CRICOS code
-- (identity_basis='cricos_code'), read by the current extractor, and only where the course has no value:
--   official_course_url  -> course has no active official course link;
--   english (IELTS overall + minimum band, PTE and TOEFL iBT overall where stated) -> course has no active English requirement;
--   intakes (months)     -> course has no active intake.
-- Where the course already has a value and the page says something different, a Layer 4 item is raised with a plain
-- reason (never overwritten). Writes go through public.svc_coursefacts_apply_record with the stored page as evidence.
-- Each provider's sweep source is qualified 'bounded' for these three domains, and Search gates are opened for them.
-- Tuition is not admitted here (it goes through the qualified Layer 3 model).

create or replace function security.coverage_norm_url(p text) returns text language sql immutable as $f$
  select rtrim(regexp_replace(regexp_replace(lower(coalesce(p,'')),'^https?://(www\.)?',''),'[?#].*$',''),'/')
$f$;

create or replace function security.coverage_admission_plan_v1(p_extractor text default 'coverage-sweep-v0.5.3')
returns table(course_id uuid, provider_id uuid, provider_cricos text, course_cricos text, evidence_id uuid, content_hash text,
              page_url text, attribute text, action text, proposed jsonb, current jsonb)
language sql stable security definer set search_path to 'pg_catalog','catalogue','pipeline','security' as $f$
  with pg as (
    select p.course_id, p.provider_id, p.url, p.evidence_id, p.candidates c, e.content_hash,
           (select pr.registration_code from catalogue.provider_registrations pr where pr.provider_id=p.provider_id and lower(pr.registration_scheme)='cricos' and coalesce(pr.status,'active') not in ('inactive','cancelled','archived') order by pr.checked_at desc nulls last limit 1) pc,
           (select cr.registration_code from catalogue.course_registrations cr where cr.course_id=p.course_id and lower(cr.scheme)='cricos' limit 1) cc
      from pipeline.coverage_course_pages p join pipeline.evidence_artifacts e on e.id=p.evidence_id
      join catalogue.courses co on co.id=p.course_id and co.lifecycle_status='active'
     where p.read_status='read' and p.identity_basis='cricos_code' and p.candidates->>'extractor'=p_extractor
       and not security.layer4_entity_or_parent_blocked('course',p.course_id,'operational')),
  url as (
    select pg.*, 'official_url'::text attribute,
           jsonb_build_object('course_url',coalesce(nullif(pg.c->>'final_url',''),pg.url)) proposed,
           (select jsonb_agg(l.url) from catalogue.course_links l where l.course_id=pg.course_id and l.link_type='official_course' and l.status='active') cur
      from pg),
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
      from pg where pg.c->'english' ?| array['ielts_overall','pte_overall','toefl_overall']),
  itk as (
    select pg.*, 'intakes'::text attribute,
           jsonb_build_object('intakes',(select jsonb_agg(jsonb_build_object('intake_label',m,'source_intake_key',lower(pg.cc)||':current:'||lower(m))) from jsonb_array_elements_text(pg.c->'intakes') mm(m))) proposed,
           (select jsonb_agg(i.intake_label) from catalogue.course_intakes i where i.course_id=pg.course_id and coalesce(i.status,'active')='active') cur
      from pg where jsonb_array_length(coalesce(pg.c->'intakes','[]'))>0),
  allx as (select * from url union all select * from eng union all select * from itk)
  select a.course_id, a.provider_id, a.pc, a.cc, a.evidence_id, a.content_hash, a.url, a.attribute,
         case
           when a.pc is null or a.cc is null then 'unresolved'
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
$f$;
revoke all on function security.coverage_admission_plan_v1(text) from public, anon, authenticated;
