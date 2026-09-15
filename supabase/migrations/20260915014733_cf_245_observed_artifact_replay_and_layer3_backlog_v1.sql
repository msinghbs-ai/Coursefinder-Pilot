-- CF-CHG-20260915-245
-- Reuse qualified, Evidence-backed observed course-fact artefacts before acquiring the same pages again.
-- Deterministic replay is limited to month-level intake and bounded English requirements.
-- Ambiguous provider-current tuition remains a separate Layer 3 validation backlog.
begin;

create or replace function public.svc_cf245_replay_observed_coursefacts(
  p_limit integer default 100,
  p_apply boolean default false,
  p_source_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','catalogue','ref','security'
as $$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,100),1),500);
  v_intake_courses integer:=0; v_english_courses integer:=0;
  v_intake_rows integer:=0; v_english_rows integer:=0; v_fee_backlog integer:=0;
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then
    raise exception 'service_role required' using errcode='42501';
  end if;
  create temporary table if not exists pg_temp.cf245_replay_candidates(
    source_record_id uuid primary key,source_id uuid not null,evidence_id uuid not null,course_id uuid not null,
    provider_cricos text not null,course_cricos text not null,source_url text not null,parsed_payload jsonb not null,
    search_admitted boolean not null,intake_safe boolean not null,english_safe boolean not null,
    intake_missing_before boolean not null,english_missing_before boolean not null,fee_requires_layer3 boolean not null
  ) on commit drop;
  truncate pg_temp.cf245_replay_candidates;
  insert into pg_temp.cf245_replay_candidates
  with ranked as (
    select r.*,q.admitted_domains,q.metadata qualification_metadata,
           row_number() over(partition by r.source_id,r.course_cricos order by r.observed_at desc,r.id desc) rn
    from pipeline.course_fact_source_records r
    join pipeline.course_fact_source_qualifications q on q.source_id=r.source_id
      and upper(btrim(q.provider_cricos))=upper(btrim(r.provider_cricos))
      and q.qualification_status in ('qualified','bounded')
      and coalesce((q.metadata->>'apply_admitted')::boolean,false)
    where r.status='observed' and r.evidence_id is not null and (p_source_id is null or r.source_id=p_source_id)
      and coalesce((r.parsed_payload->>'identity_match')::boolean,false)
      and coalesce((r.parsed_payload->>'regulatory_code_seen')::boolean,false)
      and nullif(r.parsed_payload->>'course_id','') is not null
  ), resolved as (
    select r.*,(r.parsed_payload->>'course_id')::uuid course_id,
      exists(select 1 from catalogue.course_intakes ci where ci.course_id=(r.parsed_payload->>'course_id')::uuid and coalesce(ci.status,'active')='active') intake_exists,
      exists(select 1 from catalogue.course_english_requirements ce where ce.course_id=(r.parsed_payload->>'course_id')::uuid and coalesce(ce.status,'active')='active') english_exists,
      coalesce((r.qualification_metadata->>'search_admitted')::boolean,false) search_admitted
    from ranked r where r.rn=1
      and exists(select 1 from catalogue.courses c where c.id=(r.parsed_payload->>'course_id')::uuid
        and exists(select 1 from catalogue.course_registrations cr where cr.course_id=c.id and lower(cr.scheme)='cricos' and upper(btrim(cr.registration_code))=upper(btrim(r.course_cricos)))
        and exists(select 1 from catalogue.provider_registrations pr where pr.provider_id=c.provider_id and lower(pr.registration_scheme)='cricos' and upper(btrim(pr.registration_code))=upper(btrim(r.provider_cricos)) and coalesce(pr.status,'active') not in ('inactive','cancelled','archived')))
      and not security.layer4_entity_or_parent_blocked('course',(r.parsed_payload->>'course_id')::uuid,'operational')
  )
  select id,source_id,evidence_id,course_id,provider_cricos,course_cricos,source_url,parsed_payload,search_admitted,
    ('intake'=any(admitted_domains)) and jsonb_typeof(coalesce(parsed_payload->'intakes','[]'::jsonb))='array'
      and exists(select 1 from jsonb_array_elements(coalesce(parsed_payload->'intakes','[]'::jsonb)) x(v)
        where jsonb_typeof(x.v)='string' and lower(trim(both '"' from x.v::text)) in ('january','february','march','april','may','june','july','august','september','october','november','december')) as intake_safe,
    ('english_requirement'=any(admitted_domains)) and (
      nullif(parsed_payload->'english_requirements'->>'ielts_overall','')::numeric between 1 and 9
      or nullif(parsed_payload->'english_requirements'->>'pte_overall','')::numeric between 10 and 90
      or nullif(parsed_payload->'english_requirements'->>'toefl_overall','')::numeric between 1 and 120) as english_safe,
    not intake_exists,not english_exists,
    ('international_fee'=any(admitted_domains)) and coalesce((parsed_payload->>'fee_safe')::boolean,false)
      and nullif(parsed_payload->'provider_current_tuition'->>'amount','')::numeric>0
      and coalesce(parsed_payload->'provider_current_tuition'->>'basis','')='annual_or_indicative_requires_validation' as fee_requires_layer3
  from resolved
  where not intake_exists or not english_exists or (('international_fee'=any(admitted_domains)) and coalesce((parsed_payload->>'fee_safe')::boolean,false) and parsed_payload->'provider_current_tuition' is not null)
  order by (not intake_exists)::int+(not english_exists)::int desc,observed_at desc limit v_limit;
  select count(*) filter(where intake_safe and intake_missing_before),count(*) filter(where english_safe and english_missing_before),count(*) filter(where fee_requires_layer3)
    into v_intake_courses,v_english_courses,v_fee_backlog from pg_temp.cf245_replay_candidates;
  if not p_apply then return jsonb_build_object('apply',false,'selected_records',(select count(*) from pg_temp.cf245_replay_candidates),'intake_courses',v_intake_courses,'english_courses',v_english_courses,'fee_candidates_for_layer3',v_fee_backlog,'change_control_ref','CF-CHG-20260915-245'); end if;
  with rows as (
    select c.*,initcap(lower(trim(both '"' from x.v::text))) intake_label from pg_temp.cf245_replay_candidates c
    cross join lateral jsonb_array_elements(coalesce(c.parsed_payload->'intakes','[]'::jsonb)) x(v)
    where c.intake_safe and c.intake_missing_before and jsonb_typeof(x.v)='string'
      and lower(trim(both '"' from x.v::text)) in ('january','february','march','april','may','june','july','august','september','october','november','december')
  ), ins as (
    insert into catalogue.course_intakes(course_id,intake_year,intake_label,start_date,application_deadline,campus_id,status,source_id,evidence_id,confidence,source_intake_key)
    select course_id,null,intake_label,null,null,null,'active',source_id,evidence_id,1,'cf245:'||lower(course_cricos)||':month:'||lower(intake_label) from rows
    on conflict(course_id,source_id,source_intake_key) where source_id is not null and source_intake_key is not null do nothing returning 1
  ) select count(*) into v_intake_rows from ins;
  with e as (
    select c.*,x.test_code,x.score from pg_temp.cf245_replay_candidates c
    cross join lateral (values ('IELTS'::text,nullif(c.parsed_payload->'english_requirements'->>'ielts_overall','')::numeric),('PTE'::text,nullif(c.parsed_payload->'english_requirements'->>'pte_overall','')::numeric),('TOEFL_IBT'::text,nullif(c.parsed_payload->'english_requirements'->>'toefl_overall','')::numeric)) x(test_code,score)
    where c.english_safe and c.english_missing_before and ((x.test_code='IELTS' and x.score between 1 and 9) or (x.test_code='PTE' and x.score between 10 and 90) or (x.test_code='TOEFL_IBT' and x.score between 1 and 120))
  ), ins as (
    insert into catalogue.course_english_requirements(course_id,english_test_id,overall_score,component_scores,notes,source_id,evidence_id,confidence,source_requirement_key,status,valid_from,valid_to,last_verified_at)
    select e.course_id,t.id,e.score,'{}'::jsonb,'CF-245 deterministic replay from qualified first-party Evidence',e.source_id,e.evidence_id,1,'cf245:'||lower(e.course_cricos)||':'||lower(e.test_code),'active',null,null,now() from e join ref.english_tests t on t.code=e.test_code
    on conflict(course_id,english_test_id) do nothing returning 1
  ) select count(*) into v_english_rows from ins;
  insert into pipeline.layer2_field_admissions(source_record_id,course_id,source_id,evidence_id,field_key,status,reason_code,candidate_payload,canonical_changed,search_admission_eligible,change_control_ref,decided_at)
  select c.source_record_id,c.course_id,c.source_id,c.evidence_id,'intake_availability','admitted','deterministic_observed_replay',c.parsed_payload->'intakes',true,c.search_admitted,'CF-CHG-20260915-245',now() from pg_temp.cf245_replay_candidates c
  where c.intake_safe and c.intake_missing_before and exists(select 1 from catalogue.course_intakes ci where ci.course_id=c.course_id and ci.source_id=c.source_id and ci.evidence_id=c.evidence_id)
  on conflict(source_record_id,field_key) do nothing;
  insert into pipeline.layer2_field_admissions(source_record_id,course_id,source_id,evidence_id,field_key,status,reason_code,candidate_payload,canonical_changed,search_admission_eligible,change_control_ref,decided_at)
  select c.source_record_id,c.course_id,c.source_id,c.evidence_id,'english_requirements','admitted','deterministic_observed_replay',c.parsed_payload->'english_requirements',true,c.search_admitted,'CF-CHG-20260915-245',now() from pg_temp.cf245_replay_candidates c
  where c.english_safe and c.english_missing_before and exists(select 1 from catalogue.course_english_requirements ce where ce.course_id=c.course_id and ce.source_id=c.source_id and ce.evidence_id=c.evidence_id)
  on conflict(source_record_id,field_key) do nothing;
  return jsonb_build_object('apply',true,'selected_records',(select count(*) from pg_temp.cf245_replay_candidates),'intake_courses_targeted',v_intake_courses,'intake_rows_inserted',v_intake_rows,'english_courses_targeted',v_english_courses,'english_rows_inserted',v_english_rows,'fee_candidates_for_layer3',v_fee_backlog,'change_control_ref','CF-CHG-20260915-245');
end $$;
revoke all on function public.svc_cf245_replay_observed_coursefacts(integer,boolean,uuid) from public,anon,authenticated;
grant execute on function public.svc_cf245_replay_observed_coursefacts(integer,boolean,uuid) to service_role;

create or replace view pipeline.cf245_layer3_fee_validation_backlog_v1 with (security_barrier=true) as
with ranked as (
 select r.*,q.admitted_domains,q.metadata qualification_metadata,row_number() over(partition by r.source_id,r.course_cricos order by r.observed_at desc,r.id desc) rn
 from pipeline.course_fact_source_records r join pipeline.course_fact_source_qualifications q on q.source_id=r.source_id
  and upper(btrim(q.provider_cricos))=upper(btrim(r.provider_cricos)) and q.qualification_status in ('qualified','bounded')
 where r.status='observed' and r.evidence_id is not null and coalesce((r.parsed_payload->>'identity_match')::boolean,false)
  and coalesce((r.parsed_payload->>'regulatory_code_seen')::boolean,false)
)
select r.id source_record_id,r.source_id,r.evidence_id,(r.parsed_payload->>'course_id')::uuid course_id,r.provider_cricos,r.course_cricos,r.source_url,r.observed_at,
 r.parsed_payload->'provider_current_tuition' candidate_payload,'requires_layer3_fee_validation'::text reason_code,
 'benchmark_required_before_automatic_interpretation'::text execution_state,'CF-CHG-20260915-245'::text change_control_ref
from ranked r where r.rn=1 and 'international_fee'=any(r.admitted_domains) and coalesce((r.parsed_payload->>'fee_safe')::boolean,false)
 and nullif(r.parsed_payload->'provider_current_tuition'->>'amount','')::numeric>0
 and coalesce(r.parsed_payload->'provider_current_tuition'->>'basis','')='annual_or_indicative_requires_validation'
 and nullif(r.parsed_payload->>'course_id','') is not null and exists(select 1 from catalogue.courses c where c.id=(r.parsed_payload->>'course_id')::uuid)
 and not security.layer4_entity_or_parent_blocked('course',(r.parsed_payload->>'course_id')::uuid,'operational')
 and not exists(select 1 from catalogue.course_fees f where f.course_id=(r.parsed_payload->>'course_id')::uuid and f.fee_type='provider_current_tuition' and coalesce(f.status,'active')='active');
revoke all on pipeline.cf245_layer3_fee_validation_backlog_v1 from public,anon,authenticated;
grant select on pipeline.cf245_layer3_fee_validation_backlog_v1 to service_role;
commit;
