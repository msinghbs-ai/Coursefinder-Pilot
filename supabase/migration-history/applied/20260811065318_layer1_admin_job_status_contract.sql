create or replace function public.ui_layer1_job(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, security, pipeline
as $$
declare
  v_rank int;
  v_job pipeline.jobs%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  select coalesce(max(r.rank),0) into v_rank
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=auth.uid() and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank < 6 then raise exception 'platform_admin required'; end if;

  select * into v_job from pipeline.jobs where id=p_job_id and job_type='regulatory_sync';
  if not found then return null; end if;
  return jsonb_build_object(
    'jobId',v_job.id,'status',v_job.status,'createdAt',v_job.created_at,'startedAt',v_job.started_at,
    'completedAt',v_job.completed_at,'error',v_job.error_text,'payload',v_job.payload,'result',v_job.result
  );
end $$;

create or replace function public.ui_layer1_latest_job(p_country_code text default 'AU')
returns jsonb
language plpgsql
security definer
set search_path = public, security, pipeline
as $$
declare
  v_rank int;
  v_job pipeline.jobs%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  select coalesce(max(r.rank),0) into v_rank
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=auth.uid() and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank < 6 then raise exception 'platform_admin required'; end if;

  select * into v_job from pipeline.jobs
  where job_type='regulatory_sync' and upper(coalesce(payload->>'country_code',''))=upper(p_country_code)
  order by created_at desc limit 1;
  if not found then return null; end if;
  return jsonb_build_object(
    'jobId',v_job.id,'status',v_job.status,'createdAt',v_job.created_at,'startedAt',v_job.started_at,
    'completedAt',v_job.completed_at,'error',v_job.error_text,'payload',v_job.payload,'result',v_job.result
  );
end $$;

revoke all on function public.ui_layer1_job(uuid) from public, anon;
revoke all on function public.ui_layer1_latest_job(text) from public, anon;
grant execute on function public.ui_layer1_job(uuid) to authenticated, service_role;
grant execute on function public.ui_layer1_latest_job(text) to authenticated, service_role;
