create or replace function public.svc_layer1_validate_nz_gate_uat_token(p_job_id uuid, p_nonce text)
returns boolean
language sql
security definer
set search_path = public, pipeline
as $$
  select exists (
    select 1
    from pipeline.jobs j
    where j.id = p_job_id
      and j.payload->>'mode' = 'nz_gate_uat_token'
      and j.payload->>'uat_nonce' = p_nonce
      and nullif(j.payload->>'expires_at','')::timestamptz > now()
  );
$$;
revoke all on function public.svc_layer1_validate_nz_gate_uat_token(uuid,text) from public, anon, authenticated;
grant execute on function public.svc_layer1_validate_nz_gate_uat_token(uuid,text) to postgres, service_role;
