CREATE OR REPLACE FUNCTION security.admin_course_fee_summary(p_course_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'pipeline', 'auth'
AS $function$
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
    'fee_used',security.course_fee_used_v1(p_course_id),
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
$function$
