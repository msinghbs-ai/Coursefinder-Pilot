-- CF-247 Decision 162 step 4 (Platform Admin approval 28 Sep 2026: English requirements as provider default by
-- study level plus named exceptions). First provider: The University of Queensland (CRICOS 00025B).
-- Policy basis (UQ English Language Proficiency Admission Procedure, cl. 10-11 and Definitions): "All UQ programs
-- are minimum ELP programs unless specified otherwise in Table 1"; minimum scores are in Table 3.
--
-- Planning rules (one function, used by both preview and apply, so the dry run is exactly what apply writes):
--   * exact Table 1 program name (normalised; two reviewed aliases) -> that program's Table 1 requirement;
--   * a single award program not in Table 1 -> Table 3 minimum;
--   * held back and reported, never defaulted: double degrees (the policy has no double-degree rule, and course
--     pages show double degrees taking a component's higher requirement), research degrees (Table 1's research
--     exception names a setting, not a program), exit awards, non-award study, and any title that contains or
--     closely resembles a Table 1 program name;
--   * only courses with no English requirement are written; where a course page already gave a value the plan is
--     compared with it and differences are reported for Layer 4, never overwritten.
-- The source is qualified for course facts but not admitted to Search (search_admitted=false); the Search gate for
-- this source is a separate Platform Admin step.

insert into pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'provider_english_requirements', s.system_id, pr.provider_id, s.country_id,
       'https://policies.uq.edu.au/document/view-current.php?id=231',
       'The University of Queensland English Language Proficiency Admission Procedure, Table 1 and Table 3', 95, 'active',
       jsonb_build_object('facts',jsonb_build_array('english_requirement'),'provider_cricos','00025B','decision','Decision 162 step 4',
         'documents',jsonb_build_object(
           'procedure','https://policies.uq.edu.au/document/view-current.php?id=231',
           'table1','https://policies.uq.edu.au/download.php?associated=1&id=170',
           'table3','https://policies.uq.edu.au/download.php?associated=1&id=172'),
         'aliases',jsonb_build_object(
           'bachelor of exercise and sports sciences honours','bachelor of exercise and sport science honours',
           'doctor of medicine excluding provisional entry for school leavers','doctor of medicine'),
         'alias_review','Reviewed 28 Sep 2026: UQ course title "Bachelor of Exercise and Sport Science (Honours)"; Table 1 excludes only the provisional (school-leaver) entry path to the Doctor of Medicine')
  from catalogue.provider_registrations pr
  join lateral (select s0.* from pipeline.sources s0 where s0.source_type='provider_course_page' and s0.metadata->>'provider_cricos'='00025B' limit 1) s on true
 where upper(pr.registration_code)='00025B' and lower(pr.registration_scheme)='cricos'
   and not exists (select 1 from pipeline.sources e where e.source_type='provider_english_requirements' and e.metadata->>'provider_cricos'='00025B');

insert into pipeline.course_fact_source_qualifications(source_id,country_id,source_key,source_class,authority_name,provider_cricos,admitted_domains,mapping_strategy,evidence_strategy,qualification_status,notes,metadata)
select s.id, s.country_id, 'au_00025b_english_requirements','provider_first_party','The University of Queensland','00025B', array['english_requirement'],
       'exact program name within the provider (Table 1), otherwise the provider minimum for single award programs; double degrees, research degrees, exit awards, non-award study and near-name variants held back',
       'Table 1 and Table 3 files retained as evidence with their SHA-256',
       'qualified','Decision 162 step 4: deterministic English-table parser; reconciliation dry run before apply',
       jsonb_build_object('gate','Decision-162-english-table','qualified_at',now(),'apply_admitted',true,'search_admitted',false,'identity_authority',false,'change_control_ref','CF-CHG-20260915-247')
  from pipeline.sources s
 where s.source_type='provider_english_requirements' and s.metadata->>'provider_cricos'='00025B'
   and not exists (select 1 from pipeline.course_fact_source_qualifications q where q.source_id=s.id);

create or replace function security.english_title_key(p text) returns text language sql immutable as $f$
  select btrim(regexp_replace(regexp_replace(regexp_replace(
           replace(regexp_replace(lower(coalesce(p,'')),'\(\s*\d+\s+units(\s+and\s+\d+\s+units)?\s*\)','','g'),'&',' and '),
           '[^a-z0-9/]+',' ','g'),' ?/ ?','/','g'),'\s+',' ','g'))
$f$;

create or replace function security.english_title_overlap(a text, b text) returns numeric language sql immutable as $f$
  with x as (select distinct t from unnest(regexp_split_to_array(a,'[ /]+')) t where t not in ('of','and','in','the','')),
       y as (select distinct t from unnest(regexp_split_to_array(b,'[ /]+')) t where t not in ('of','and','in','the',''))
  select coalesce((select count(*) from x join y using (t))::numeric / nullif(greatest((select count(*) from x),(select count(*) from y)),0),0)
$f$;

create or replace function security.english_table_plan_v1(p_provider_cricos text, p_programs jsonb, p_minimum jsonb)
returns table(course_id uuid, course_cricos text, title text, study_level text, plan text, reason text, program text,
              requirements jsonb, existing jsonb, comparison text)
language plpgsql stable security definer set search_path to 'pg_catalog','catalogue','pipeline','ref','security' as $f$
declare v_provider uuid; v_aliases jsonb;
begin
  select s.provider_id, coalesce(s.metadata->'aliases','{}'::jsonb) into v_provider, v_aliases from pipeline.sources s
   where s.source_type='provider_english_requirements' and s.metadata->>'provider_cricos'=upper(btrim(p_provider_cricos)) limit 1;
  if v_provider is null then raise exception 'no English requirements source for provider %', p_provider_cricos; end if;
  return query
  with t1 as (
    select e->>'name' name, coalesce(e->>'section','coursework') section, e->'requirements' reqs,
           coalesce(v_aliases->>security.english_title_key(e->>'name'), security.english_title_key(e->>'name')) k
      from jsonb_array_elements(coalesce(p_programs,'[]'::jsonb)) e),
  c as (
    select co.id, co.canonical_title t, security.english_title_key(co.canonical_title) k, sl.code lvl,
           (select min(upper(btrim(cr.registration_code))) from catalogue.course_registrations cr where cr.course_id=co.id and lower(cr.scheme)='cricos') cricos,
           (select coalesce(jsonb_object_agg(et.code, r.overall_score),'{}'::jsonb) from catalogue.course_english_requirements r join ref.english_tests et on et.id=r.english_test_id
             where r.course_id=co.id and r.status='active') ex
      from catalogue.courses co left join ref.study_levels sl on sl.id=co.study_level_id
     where co.provider_id=v_provider and co.lifecycle_status='active'),
  m as (
    select c.*,
           (select jsonb_agg(jsonb_build_object('name',t1.name,'reqs',t1.reqs)) from t1 where t1.k=c.k) exact,
           exists(select 1 from t1 where t1.k<>c.k and (position(t1.k in c.k)>0 or security.english_title_overlap(c.k,t1.k)>=0.75)) close
      from c),
  p as (
    select m.*,
      case when m.exact is not null and (select count(distinct x->'reqs') from jsonb_array_elements(m.exact) x)>1 then 'held'
           when m.exact is not null then 'table1'
           when m.lvl='non_aqf_award' or m.lvl is null then 'held'
           when m.t ~* 'exit award' then 'held'
           when m.lvl in ('doctorate','masters_research') then 'held'
           when m.k ~ '/' or m.k ~ ' and (bachelor|master|doctor|graduate|diploma|associate) (of|in) ' then 'held'
           when m.close then 'held'
           else 'minimum' end pl,
      case when m.exact is not null and (select count(distinct x->'reqs') from jsonb_array_elements(m.exact) x)>1 then 'conflicting Table 1 entries for one name'
           when m.exact is not null then null
           when m.lvl is null then 'study level unknown'
           when m.lvl='non_aqf_award' then 'not an award program'
           when m.t ~* 'exit award' then 'exit award only: not an admission program'
           when m.lvl in ('doctorate','masters_research') then 'research degree: Table 1 research rule is not tied to a named program'
           when m.k ~ '/' or m.k ~ ' and (bachelor|master|doctor|graduate|diploma|associate) (of|in) ' then 'double degree: the policy has no double-degree rule'
           when m.close then 'close to a Table 1 program name: review'
           else null end rs
      from m)
  select p.id, p.cricos, p.t, p.lvl, p.pl, p.rs,
         case when p.pl='table1' then p.exact->0->>'name' end,
         case when p.pl='table1' then p.exact->0->'reqs' when p.pl='minimum' then p_minimum end,
         p.ex,
         case when p.pl not in ('table1','minimum') then null
              when p.ex='{}'::jsonb then 'none'
              when exists(select 1 from jsonb_array_elements(case when p.pl='table1' then p.exact->0->'reqs' else p_minimum end) q
                           where p.ex ? (q->>'test_code') and (p.ex->>(q->>'test_code'))::numeric<>(q->>'overall_score')::numeric) then 'differs'
              when exists(select 1 from jsonb_array_elements(case when p.pl='table1' then p.exact->0->'reqs' else p_minimum end) q where p.ex ? (q->>'test_code')) then 'agrees'
              else 'other_tests_only' end
    from p;
end $f$;
revoke all on function security.english_table_plan_v1(text,jsonb,jsonb) from public, anon, authenticated;

create or replace function public.svc_english_table_preview(p_provider_cricos text, p_programs jsonb, p_minimum jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','public','security' as $f$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pl as (select * from security.english_table_plan_v1(p_provider_cricos,p_programs,p_minimum)),
       t1 as (select e->>'name' name, e->>'section' section from jsonb_array_elements(p_programs) e)
  select jsonb_build_object(
    'courses',(select count(*) from pl),
    'by_plan',(select jsonb_object_agg(plan,n) from (select plan,count(*) n from pl group by 1) x),
    'by_comparison',(select jsonb_object_agg(plan||':'||comparison,n) from (select plan,comparison,count(*) n from pl where comparison is not null group by 1,2) x),
    'would_write',(select count(*) from pl where plan in ('table1','minimum') and comparison='none' and course_cricos is not null),
    'held_by_reason',(select jsonb_object_agg(reason,n) from (select reason,count(*) n from pl where plan='held' group by 1) x),
    'table1_programs',(select jsonb_agg(jsonb_build_object('program',t1.name,'section',t1.section,
         'courses',(select count(*) from pl where pl.program=t1.name)) order by t1.name) from t1),
    'table1_not_in_catalogue',(select jsonb_agg(t1.name order by t1.name) from t1 where not exists(select 1 from pl where pl.program=t1.name)),
    'differs',(select jsonb_agg(jsonb_build_object('title',title,'plan',plan,'program',program,'planned',(select jsonb_object_agg(q->>'test_code',q->'overall_score') from jsonb_array_elements(requirements) q),'existing',existing) order by title) from pl where comparison='differs'),
    'held',(select jsonb_agg(jsonb_build_object('title',title,'reason',reason,'existing',existing) order by reason,title) from pl where plan='held'),
    'written_sample',(select jsonb_agg(x) from (select jsonb_build_object('title',title,'plan',plan,'ielts',(select q->'overall_score' from jsonb_array_elements(requirements) q where q->>'test_code'='IELTS')) x from pl where plan in ('table1','minimum') and comparison='none' order by plan desc,title limit 12) s)
  ) into v;
  return v;
end $f$;
revoke all on function public.svc_english_table_preview(text,jsonb,jsonb) from public, anon, authenticated;
grant execute on function public.svc_english_table_preview(text,jsonb,jsonb) to service_role;

create or replace function public.svc_english_table_apply(p_provider_cricos text, p_programs jsonb, p_minimum jsonb, p_table1 jsonb, p_table3 jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public','pipeline','security','search' as $f$
declare v_source uuid; v_e1 uuid; v_e3 uuid; r record; v_ok int:=0; v_skipped jsonb:='[]'::jsonb; v_courses uuid[]:='{}'; v_doc jsonb; v_ev uuid; v_res jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  -- only courses with no English requirement are written; existing course-page values are never overwritten
  if jsonb_array_length(coalesce(p_programs,'[]'::jsonb))<30 then raise exception 'too few Table 1 programs; apply refused'; end if;
  if not exists(select 1 from jsonb_array_elements(p_minimum) q where q->>'test_code'='IELTS') then raise exception 'minimum IELTS requirement missing; apply refused'; end if;
  select s.id into v_source from pipeline.sources s where s.source_type='provider_english_requirements' and s.metadata->>'provider_cricos'=upper(btrim(p_provider_cricos))
     and exists(select 1 from pipeline.course_fact_source_qualifications q where q.source_id=s.id and q.qualification_status='qualified' and 'english_requirement'=any(q.admitted_domains));
  if v_source is null then raise exception 'no qualified English requirements source for provider %', p_provider_cricos; end if;
  foreach v_doc in array array[p_table1,p_table3] loop
    if coalesce(v_doc->>'storage_path','')='' or coalesce(v_doc->>'sha256','') !~ '^[0-9a-f]{64}$' then raise exception 'stored table file and its SHA-256 are required'; end if;
    select e.id into v_ev from pipeline.evidence_artifacts e where e.source_id=v_source and e.content_hash=v_doc->>'sha256' limit 1;
    if v_ev is null then
      v_ev:=public.svc_coursefacts_register_evidence(v_source,v_doc->>'url',v_doc->>'storage_path',v_doc->>'sha256','application/pdf',
        jsonb_build_object('layer',2,'kind','provider_english_requirements','document',v_doc->>'document','worker','fee-schedule-etl','decision','Decision 162 step 4'));
    end if;
    if v_doc is not distinct from p_table1 then v_e1:=v_ev; else v_e3:=v_ev; end if;
  end loop;
  for r in select * from security.english_table_plan_v1(p_provider_cricos,p_programs,p_minimum)
            where plan in ('table1','minimum') and comparison='none' and course_cricos is not null loop
    begin
      v_res:=public.svc_coursefacts_apply_record(v_source, case when r.plan='table1' then v_e1 else v_e3 end, p_provider_cricos, r.course_cricos,
        'uq-elp:'||r.plan||':'||r.course_cricos, case when r.plan='table1' then p_table1->>'url' else p_table3->>'url' end,
        case when r.plan='table1' then p_table1->>'sha256' else p_table3->>'sha256' end,
        jsonb_build_object('english_requirements',(select jsonb_agg(jsonb_build_object('test_code',q->>'test_code','overall_score',q->'overall_score','component_scores',coalesce(q->'component_scores','{}'::jsonb),
            'source_requirement_key','d162-elp:'||lower(r.course_cricos)||':'||lower(q->>'test_code'),
            'notes',case when r.plan='table1' then 'Decision 162: UQ ELP Table 1 (higher-than-minimum) - '||r.program else 'Decision 162: UQ minimum ELP (Procedure cl. 10-11; Table 3)' end))
          from jsonb_array_elements(r.requirements) q),'extraction_worker','fee-schedule-etl','plan',r.plan,'table1_program',r.program), true);
      v_ok:=v_ok+1; v_courses:=v_courses||r.course_id;
    exception when others then v_skipped:=v_skipped||jsonb_build_object('course',r.title,'reason',left(sqlerrm,200));
    end;
  end loop;
  if cardinality(v_courses)>0 then perform search.refresh_course_enrichment_scoped_v1(v_courses,true); end if;
  return jsonb_build_object('applied',v_ok,'skipped',jsonb_array_length(v_skipped),'skipped_detail',v_skipped,'source_id',v_source,'table1_evidence',v_e1,'table3_evidence',v_e3);
end $f$;
revoke all on function public.svc_english_table_apply(text,jsonb,jsonb,jsonb,jsonb) from public, anon, authenticated;
grant execute on function public.svc_english_table_apply(text,jsonb,jsonb,jsonb,jsonb) to service_role;
