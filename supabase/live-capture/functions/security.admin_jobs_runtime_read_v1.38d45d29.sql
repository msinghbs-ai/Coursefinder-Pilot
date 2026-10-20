CREATE OR REPLACE FUNCTION security.admin_jobs_runtime_read_v1(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=case when coalesce(p_args->>'limit','') ~ '^\d{1,9}$'
    then least(greatest((p_args->>'limit')::integer,1),200)
    else 50 end;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  with recent as (
    select
      j.id,j.job_type,j.domain,j.status,j.created_at,j.started_at,j.completed_at,j.source_profile_version_id,
      case when coalesce(j.result->>'processed','') ~ '^\d{1,18}$' then (j.result->>'processed')::bigint end processed_count,
      case when coalesce(j.result->>'selected','') ~ '^\d{1,18}$' then (j.result->>'selected')::bigint end selected_count,
      case when coalesce(j.result->>'accepted','') ~ '^\d{1,18}$' then (j.result->>'accepted')::bigint
           when coalesce(j.result->>'applied','') ~ '^\d{1,18}$' then (j.result->>'applied')::bigint end accepted_count,
      case when coalesce(j.result->>'failed','') ~ '^\d{1,18}$' then (j.result->>'failed')::bigint end failed_count,
      case when coalesce(j.result->>'retry_exhausted_count','') ~ '^\d{1,18}$' then (j.result->>'retry_exhausted_count')::bigint
           when coalesce(j.payload->>'retry_exhausted_count','') ~ '^\d{1,18}$' then (j.payload->>'retry_exhausted_count')::bigint end retry_exhausted_count,
      case when j.result ? 'idempotent_replay' and lower(j.result->>'idempotent_replay') in ('true','false') then (j.result->>'idempotent_replay')::boolean end dedupe_replay,
      case
        when j.status<>'failed' then nullif(j.result->>'completion_class','')
        when coalesce(j.error_text,'') ilike '%401%' then 'authentication_401'
        when coalesce(j.error_text,'') ilike '%credential%' then 'credential_unavailable'
        when coalesce(j.error_text,'') ilike '%provider%' and coalesce(j.error_text,'') ilike '%exhaust%' then 'provider_exhausted'
        when coalesce(j.error_text,'') ilike '%budget%' then 'acquisition_budget_exhausted'
        when coalesce(j.error_text,'') ilike '%timeout%' then 'timeout'
        else 'failed'
      end failure_class
    from pipeline.jobs j
    order by j.created_at desc
    limit v_limit
  ), evidence_counts as (
    select e.job_id,
      count(*) evidence_count,
      count(*) filter(where e.review_state in ('verified','verified_source_reference')) verified_evidence_count
    from pipeline.evidence_artifacts e
    where e.job_id in (select id from recent)
    group by e.job_id
  )
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id',j.id,
    'job_type',j.job_type,
    'domain',j.domain,
    'status',j.status,
    'created_at',j.created_at,
    'started_at',j.started_at,
    'completed_at',j.completed_at,
    'source_profile_version_id',j.source_profile_version_id,
    'profile_id',p.id,
    'profile_key',p.profile_key,
    'processed_count',j.processed_count,
    'selected_count',j.selected_count,
    'accepted_count',j.accepted_count,
    'failed_count',j.failed_count,
    'retry_exhausted_count',j.retry_exhausted_count,
    'evidence_count',coalesce(ec.evidence_count,0),
    'verified_evidence_count',coalesce(ec.verified_evidence_count,0),
    'throughput_records_per_min',case when j.processed_count is not null and j.started_at is not null and j.completed_at>j.started_at then round((j.processed_count::numeric/nullif(extract(epoch from (j.completed_at-j.started_at)),0))*60,2) end,
    'dedupe_replay',j.dedupe_replay,
    'failure_class',j.failure_class
  )) order by j.created_at desc),'[]'::jsonb)
  into v_result
  from recent j
  left join pipeline.layer2_source_profile_versions pv on pv.id=j.source_profile_version_id
  left join pipeline.layer2_source_profiles p on p.id=pv.profile_id
  left join evidence_counts ec on ec.job_id=j.id;

  return v_result;
end
$function$
