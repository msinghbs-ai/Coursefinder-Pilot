-- CF-CHG-20260820-001 — fee semantics/read-contract correction.
-- No canonical Provider/Course identity or fee observations are modified.

create or replace function public.ui_course_completeness_list(p_limit integer default 2000)
returns table(
  course_id uuid,
  canonical_title text,
  provider_name text,
  level_code text,
  field_of_study text,
  fee_amount numeric,
  fee_currency character,
  ielts_overall numeric,
  has_scholarship boolean,
  scholarship_status text,
  scholarship_count integer,
  has_registration boolean,
  has_structure boolean,
  has_fee boolean,
  has_intake boolean,
  has_english boolean,
  has_description boolean,
  completeness_score_v2 numeric,
  completeness_score numeric
)
language sql
stable
security definer
set search_path = public, catalogue, ref, scholarship, auth, pg_catalog
as $$
select
  c.id,
  c.canonical_title,
  coalesce(p.display_name,p.canonical_name),
  sl.code,
  fos.name,
  f.amount,
  f.currency_code,
  e.overall_score,
  (sch.scholarship_count > 0),
  case when sch.scholarship_count > 0 then 'linked' else 'unknown' end,
  sch.scholarship_count,
  sig.has_registration,
  sig.has_structure,
  sig.has_fee,
  sig.has_intake,
  sig.has_english,
  sig.has_description,
  round(((sig.has_registration::int + sig.has_structure::int + sig.has_fee::int + sig.has_intake::int + sig.has_english::int + sig.has_description::int) * 100.0 / 6.0)::numeric,2),
  round(((sig.has_registration::int + sig.has_structure::int + sig.has_fee::int + sig.has_intake::int + sig.has_english::int + sig.has_description::int) * 100.0 / 6.0)::numeric,2)
from catalogue.courses c
join catalogue.providers p on p.id=c.provider_id
left join ref.study_levels sl on sl.id=c.study_level_id
left join ref.fields_of_study fos on fos.id=c.primary_field_id
left join lateral (
  select cf.amount,cf.currency_code
  from catalogue.course_fees cf
  where cf.course_id=c.id
    and cf.fee_type='tuition'
    and cf.basis='registered_total_course'
    and coalesce(cf.status,'active')='active'
  order by cf.source_snapshot_at desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc
  limit 1
) f on true
left join lateral (
  select er.overall_score
  from catalogue.course_english_requirements er
  join ref.english_tests t on t.id=er.english_test_id
  where er.course_id=c.id and t.code='IELTS' and coalesce(er.status,'active')='active'
  order by er.last_verified_at desc nulls last
  limit 1
) e on true
cross join lateral (
  select count(*)::int as scholarship_count
  from scholarship.scopes ss
  where ss.course_id=c.id or (ss.scope_type='provider' and ss.provider_id=c.provider_id)
) sch
cross join lateral (
  select
    exists(select 1 from catalogue.course_registrations r where r.course_id=c.id) as has_registration,
    (c.duration_value is not null or exists(select 1 from catalogue.course_academic_options a where a.course_id=c.id)) as has_structure,
    exists(select 1 from catalogue.course_fees cf where cf.course_id=c.id and coalesce(cf.status,'active')='active') as has_fee,
    exists(select 1 from catalogue.course_intakes ci where ci.course_id=c.id and coalesce(ci.status,'active')='active') as has_intake,
    exists(select 1 from catalogue.course_english_requirements er where er.course_id=c.id and coalesce(er.status,'active')='active') as has_english,
    (c.description is not null and length(trim(c.description))>0) as has_description
) sig
where auth.uid() is not null
order by coalesce(p.display_name,p.canonical_name),c.canonical_title
limit least(greatest(coalesce(p_limit,2000),1),5000)
$$;

comment on function public.ui_course_completeness_list(integer) is
  'Admin operational completeness/readiness projection. Presence signals are derived from canonical/relational data, not Search publication flags. fee_amount is CRICOS tuition with registered_total_course basis only. completeness scores are display-only equal-weight presence scores across registration, structure, fee, intake, English and description; they are not publication approval.';

create or replace function security.admin_course_fee_summary(p_course_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, catalogue, pipeline, auth
as $$
declare
  v_rank integer := 0;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 1 then
    raise exception 'assigned CourseFinder role required' using errcode='42501';
  end if;

  return jsonb_build_object(
    'cricos_registered',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',cf.id,
        'fee_type',cf.fee_type,
        'amount',cf.amount,
        'currency',cf.currency_code,
        'basis',cf.basis,
        'load_basis',cf.load_basis,
        'fee_year',cf.fee_year,
        'audience',cf.audience,
        'campus_id',cf.campus_id,
        'valid_from',cf.valid_from,
        'valid_to',cf.valid_to,
        'status',cf.status,
        'source_fee_key',cf.source_fee_key,
        'source_id',cf.source_id,
        'source_snapshot_at',cf.source_snapshot_at,
        'last_verified_at',cf.last_verified_at,
        'evidence_id',cf.evidence_id,
        'source',case when s.id is null then null else jsonb_build_object(
          'id',s.id,'label',s.label,'type',s.source_type,'url',s.url
        ) end,
        'evidence',case when e.id is null then null else jsonb_build_object(
          'id',e.id,'type',e.evidence_type,'source_url',e.source_url,
          'content_hash',e.content_hash,'captured_at',e.captured_at
        ) end
      ) order by case cf.fee_type when 'tuition' then 1 when 'non_tuition' then 2 when 'estimated_total_course_cost' then 3 else 9 end,cf.fee_type)
      from catalogue.course_fees cf
      left join pipeline.sources s on s.id=cf.source_id
      left join pipeline.evidence_artifacts e on e.id=cf.evidence_id
      where cf.course_id=p_course_id
        and cf.basis='registered_total_course'
        and coalesce(cf.status,'active')='active'
    ),'[]'::jsonb),
    'provider_current',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',cf.id,
        'fee_type',cf.fee_type,
        'amount',cf.amount,
        'currency',cf.currency_code,
        'basis',cf.basis,
        'load_basis',cf.load_basis,
        'fee_year',cf.fee_year,
        'audience',cf.audience,
        'campus_id',cf.campus_id,
        'valid_from',cf.valid_from,
        'valid_to',cf.valid_to,
        'status',cf.status,
        'source_fee_key',cf.source_fee_key,
        'source_id',cf.source_id,
        'source_snapshot_at',cf.source_snapshot_at,
        'last_verified_at',cf.last_verified_at,
        'evidence_id',cf.evidence_id,
        'source',case when s.id is null then null else jsonb_build_object(
          'id',s.id,'label',s.label,'type',s.source_type,'url',s.url
        ) end,
        'evidence',case when e.id is null then null else jsonb_build_object(
          'id',e.id,'type',e.evidence_type,'source_url',e.source_url,
          'content_hash',e.content_hash,'captured_at',e.captured_at
        ) end
      ) order by cf.fee_year desc nulls last,cf.last_verified_at desc nulls last,cf.created_at desc)
      from catalogue.course_fees cf
      left join pipeline.sources s on s.id=cf.source_id
      left join pipeline.evidence_artifacts e on e.id=cf.evidence_id
      where cf.course_id=p_course_id
        and cf.fee_type ~ '^provider_current_'
        and coalesce(cf.status,'active')='active'
    ),'[]'::jsonb),
    'other',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',cf.id,'fee_type',cf.fee_type,'amount',cf.amount,'currency',cf.currency_code,
        'basis',cf.basis,'load_basis',cf.load_basis,'fee_year',cf.fee_year,'audience',cf.audience,
        'campus_id',cf.campus_id,'valid_from',cf.valid_from,'valid_to',cf.valid_to,'status',cf.status,
        'source_id',cf.source_id,'source_snapshot_at',cf.source_snapshot_at,'last_verified_at',cf.last_verified_at,
        'evidence_id',cf.evidence_id
      ) order by cf.created_at desc)
      from catalogue.course_fees cf
      where cf.course_id=p_course_id
        and cf.basis is distinct from 'registered_total_course'
        and not (cf.fee_type ~ '^provider_current_')
        and coalesce(cf.status,'active')='active'
    ),'[]'::jsonb)
  );
end
$$;

revoke all on function security.admin_course_fee_summary(uuid) from public,anon;
grant execute on function security.admin_course_fee_summary(uuid) to authenticated,service_role;
comment on function security.admin_course_fee_summary(uuid) is
  'CF-CHG-20260820-001 private role-checked Admin fee read helper. Preserves fee type, basis, year/audience/campus scope, validity, source/evidence, snapshot and verification. Unknown non-CRICOS/non-provider-current fee semantics are isolated in other rather than mislabeled.';

create or replace function public.admin_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog,public,security
as $$
declare
  v_result jsonb;
  v_id uuid;
begin
  v_result := security.admin_read_impl(p_operation,p_args);
  if p_operation='course_detail' then
    v_id := nullif(p_args->>'id','')::uuid;
    return v_result || jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id));
  end if;
  return v_result;
end
$$;

revoke all on function public.admin_read(text,jsonb) from public,anon;
grant execute on function public.admin_read(text,jsonb) to authenticated,service_role;
comment on function public.admin_read(text,jsonb) is
  'Governed browser read contract. Course detail fee_summary is enriched by CF-CHG-20260820-001 without changing canonical fee observations or identity.';
