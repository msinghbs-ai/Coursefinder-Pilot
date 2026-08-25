-- CF-CHG-20260825-036
-- Governed Scholarship Selection is decision support only. It separates sourced scholarship
-- facts from a transparent structural scope score and explicitly lists unresolved eligibility.
-- It must never infer that a student is eligible from provider/course matching alone.

create or replace function security.scholarship_selection_for_course_impl(p_course_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,security,catalogue,scholarship,ref
as $$
with course_base as (
  select c.id course_id,c.provider_id,c.study_level_id,c.primary_field_id,p.country_id,
         c.canonical_title,p.canonical_name provider_name
  from catalogue.courses c
  join catalogue.providers p on p.id=c.provider_id
  where c.id=p_course_id
), scholarship_base as (
  select s.*,
         (select count(*) from scholarship.scopes sc where sc.scholarship_id=s.id) scope_count,
         (select count(*) from scholarship.scopes sc
           join course_base b on true
          where sc.scholarship_id=s.id and coalesce(sc.include_exclude,'include')='include'
            and (sc.course_id=b.course_id
              or (sc.provider_id=b.provider_id and sc.course_id is null)
              or (sc.study_level_id=b.study_level_id and sc.provider_id is null and sc.course_id is null)
              or (sc.field_id=b.primary_field_id and sc.provider_id is null and sc.course_id is null)
              or (sc.country_id=b.country_id and sc.provider_id is null and sc.course_id is null))) include_match_count,
         (select count(*) from scholarship.scopes sc
           join course_base b on true
          where sc.scholarship_id=s.id and sc.include_exclude='exclude'
            and (sc.course_id=b.course_id or sc.provider_id=b.provider_id or sc.study_level_id=b.study_level_id or sc.field_id=b.primary_field_id or sc.country_id=b.country_id)) exclude_match_count
  from scholarship.scholarships s
  where s.lifecycle_status='active'
), candidates as (
  select s.*,
    case
      when s.exclude_match_count>0 then 0
      when exists(select 1 from scholarship.scopes sc where sc.scholarship_id=s.id and coalesce(sc.include_exclude,'include')='include' and sc.course_id=p_course_id) then 100
      when exists(select 1 from scholarship.scopes sc join course_base b on true where sc.scholarship_id=s.id and coalesce(sc.include_exclude,'include')='include' and sc.provider_id=b.provider_id) then 70
      when exists(select 1 from scholarship.scopes sc join course_base b on true where sc.scholarship_id=s.id and coalesce(sc.include_exclude,'include')='include' and sc.study_level_id=b.study_level_id) then 50
      when exists(select 1 from scholarship.scopes sc join course_base b on true where sc.scholarship_id=s.id and coalesce(sc.include_exclude,'include')='include' and sc.field_id=b.primary_field_id) then 50
      when exists(select 1 from scholarship.scopes sc join course_base b on true where sc.scholarship_id=s.id and coalesce(sc.include_exclude,'include')='include' and sc.country_id=b.country_id) then 40
      when s.scope_count=0 then 10
      else 0 end as scope_fit_score
  from scholarship_base s
  where s.exclude_match_count=0 and (s.include_match_count>0 or s.scope_count=0)
), rendered as (
  select jsonb_build_object(
    'scholarship_id',s.id,
    'name',s.name,
    'selection_state',case when s.scope_count=0 then 'MISSING_UNRESOLVED' else 'SCOPE_CANDIDATE' end,
    'eligibility_state','UNRESOLVED',
    'source_fact',jsonb_build_object(
      'label','SOURCE FACT',
      'audience',s.audience,
      'award_value_text',s.award_value_text,
      'application_required',s.application_required,
      'application_open_date',s.application_open_date,
      'application_close_date',s.application_close_date,
      'academic_year',s.academic_year,
      'source_url',s.source_url,
      'source_id',s.source_id,
      'evidence_id',s.evidence_id,
      'publication_status',s.publication_status,
      'scope_count',s.scope_count,
      'matched_scope_count',s.include_match_count
    ),
    'derived_score',jsonb_build_object(
      'label','DERIVED SCORE',
      'scope_fit_score',s.scope_fit_score,
      'meaning','Structural course/scope relevance only; not student eligibility',
      'weights',jsonb_build_object('course',100,'provider',70,'study_level',50,'field',50,'country',40,'unscoped',10)
    ),
    'missing_unresolved',jsonb_build_object(
      'label','MISSING / UNRESOLVED',
      'reason',case when s.scope_count=0 then 'No explicit scholarship scope is recorded; course relevance is unresolved.' else 'Student-specific eligibility has not been evaluated.' end,
      'mandatory_criteria',coalesce((select jsonb_agg(jsonb_build_object(
          'criterion_type',c.criterion_type,'human_text',c.human_text,'machine_evaluable',c.machine_evaluable,
          'source_id',c.source_id,'evidence_id',c.evidence_id,'confidence',c.confidence
        ) order by c.criterion_type,c.created_at)
        from scholarship.criteria c where c.scholarship_id=s.id and c.status='active' and c.is_mandatory),'[]'::jsonb),
      'non_machine_evaluable_count',(select count(*) from scholarship.criteria c where c.scholarship_id=s.id and c.status='active' and c.is_mandatory and not c.machine_evaluable)
    )
  ) item
  from candidates s
)
select jsonb_build_object(
  'course_id',b.course_id,
  'course_title',b.canonical_title,
  'provider_id',b.provider_id,
  'provider_name',b.provider_name,
  'contract','scholarship_selection_decision_support_v1',
  'eligibility_inference_permitted',false,
  'candidates',coalesce((select jsonb_agg(item order by (item->'derived_score'->>'scope_fit_score')::int desc,item->>'name') from rendered),'[]'::jsonb)
) from course_base b
$$;

revoke all on function security.scholarship_selection_for_course_impl(uuid) from public,anon,authenticated;
grant execute on function security.scholarship_selection_for_course_impl(uuid) to service_role;

create or replace function security.scholarship_selection_for_course_browser_bridge(p_course_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,security
as $$ select security.scholarship_selection_for_course_impl(p_course_id) $$;
revoke all on function security.scholarship_selection_for_course_browser_bridge(uuid) from public,anon;
grant execute on function security.scholarship_selection_for_course_browser_bridge(uuid) to authenticated;

create or replace function public.scholarship_selection_for_course(p_course_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path=pg_catalog,security
as $$ select security.scholarship_selection_for_course_browser_bridge(p_course_id) $$;
revoke all on function public.scholarship_selection_for_course(uuid) from public,anon;
grant execute on function public.scholarship_selection_for_course(uuid) to authenticated,service_role;
