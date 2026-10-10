create or replace function security.layer3_benchmark_claim_job_impl(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline'
as $$
declare v pipeline.layer3_benchmark_jobs%rowtype;
begin
  update pipeline.layer3_benchmark_jobs set status='expired' where status='pending' and expires_at<=now();
  select * into v from pipeline.layer3_benchmark_jobs where id=p_job_id and status='pending' and expires_at>now() for update skip locked;
  if not found then raise exception 'benchmark job not available' using errcode='42501'; end if;
  update pipeline.layer3_benchmark_jobs set status='claimed',claimed_at=now() where id=v.id;
  return jsonb_build_object('job_id',v.id,'profile_id',v.profile_id,'actor_id',v.actor_id);
end $$;
revoke all on function security.layer3_benchmark_claim_job_impl(uuid) from public,anon,authenticated;
grant execute on function security.layer3_benchmark_claim_job_impl(uuid) to service_role;

create or replace function public.layer3_benchmark_claim_job_service(p_job_id uuid)
returns jsonb
language sql
security invoker
set search_path='pg_catalog','security'
as $$ select security.layer3_benchmark_claim_job_impl(p_job_id) $$;
revoke all on function public.layer3_benchmark_claim_job_service(uuid) from public,anon,authenticated;
grant execute on function public.layer3_benchmark_claim_job_service(uuid) to service_role;
