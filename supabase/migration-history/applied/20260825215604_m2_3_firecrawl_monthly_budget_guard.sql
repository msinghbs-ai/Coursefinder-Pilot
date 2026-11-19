-- CF-CHG-20260825-036
-- User-confirmed Firecrawl entitlement: paid subscription, 5,000 pages/month.
-- No monetary subscription price is recorded because it is not an accepted fact.
-- Preserve a 5% safety reserve so automated acquisition stops before the allowance is exhausted.

update pipeline.layer2_acquisition_providers
set billing_config = billing_config || jsonb_build_object(
  'plan_tier','paid',
  'entitlement_basis','user_confirmed_subscription',
  'monthly_vendor_units_limit',5000,
  'vendor_unit_name','page',
  'stop_at_vendor_units_remaining',250,
  'safety_reserve_percent',5,
  'no_silent_paid_fallback',true,
  'subscription_cost_usd',null,
  'monetary_cost_basis','subscription_cost_not_recorded',
  'free_tier_limit_known',true
),
request_template = request_template || jsonb_build_object('fixed_credit_units',1)
where provider_key='firecrawl';

create or replace function security.layer2_provider_budget_status(p_provider_id uuid,p_planned_units numeric default 1)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,security,pipeline
as $$
declare
  v_provider pipeline.layer2_acquisition_providers%rowtype;
  v_limit numeric;
  v_stop numeric:=0;
  v_unit numeric:=1;
  v_used numeric:=0;
  v_remaining numeric;
  v_allowed boolean:=true;
begin
  select * into v_provider from pipeline.layer2_acquisition_providers where id=p_provider_id;
  if not found then raise exception 'Layer 2 provider not found' using errcode='22023'; end if;
  begin v_limit:=nullif(v_provider.billing_config->>'monthly_vendor_units_limit','')::numeric; exception when invalid_text_representation then v_limit:=null; end;
  begin v_stop:=coalesce(nullif(v_provider.billing_config->>'stop_at_vendor_units_remaining','')::numeric,0); exception when invalid_text_representation then v_stop:=0; end;
  begin v_unit:=coalesce(nullif(v_provider.request_template->>'fixed_credit_units','')::numeric,1); exception when invalid_text_representation then v_unit:=1; end;
  if v_limit is null then
    return jsonb_build_object('provider_id',p_provider_id,'provider_key',v_provider.provider_key,'bounded',false,'planned_units',greatest(coalesce(p_planned_units,v_unit),0),'allowed',true);
  end if;
  select count(*)::numeric*v_unit into v_used
  from pipeline.layer2_provider_attempts
  where acquisition_provider_id=p_provider_id
    and started_at>=date_trunc('month',now())
    and started_at<date_trunc('month',now())+interval '1 month';
  v_remaining:=greatest(v_limit-v_used,0);
  v_allowed:=(v_remaining-greatest(coalesce(p_planned_units,v_unit),0))>=v_stop;
  return jsonb_build_object(
    'provider_id',p_provider_id,'provider_key',v_provider.provider_key,'bounded',true,
    'period_start',date_trunc('month',now()),'period_end',date_trunc('month',now())+interval '1 month',
    'limit_units',v_limit,'used_units',v_used,'remaining_units',v_remaining,
    'planned_units',greatest(coalesce(p_planned_units,v_unit),0),'remaining_after_planned',greatest(v_remaining-greatest(coalesce(p_planned_units,v_unit),0),0),
    'stop_at_remaining_units',v_stop,'allowed',v_allowed,
    'no_silent_paid_fallback',coalesce((v_provider.billing_config->>'no_silent_paid_fallback')::boolean,false)
  );
end
$$;
revoke all on function security.layer2_provider_budget_status(uuid,numeric) from public,anon,authenticated;
grant execute on function security.layer2_provider_budget_status(uuid,numeric) to service_role;

create or replace function public.layer2_provider_runtime_config(p_provider_id uuid)
returns jsonb
language sql
security definer
set search_path=pg_catalog,public,pipeline,vault,security
as $$
select jsonb_build_object(
  'id',p.id,'provider_key',p.provider_key,'display_name',p.display_name,'adapter_type',p.adapter_type,'base_url',p.base_url,
  'auth_scheme',p.auth_scheme,'auth_field_name',p.auth_field_name,'secret',ds.decrypted_secret,'capabilities',p.capabilities,
  'request_template',p.request_template,'billing_config',p.billing_config,
  'budget_status',security.layer2_provider_budget_status(p.id,coalesce(nullif(p.request_template->>'fixed_credit_units','')::numeric,1)),
  'estimated_request_cost_usd',security.layer2_provider_effective_cost_usd(p.billing_config,1),'enabled',p.enabled,
  'rate_limit_per_minute',p.rate_limit_per_minute,'concurrency',p.concurrency,'timeout_seconds',p.timeout_seconds
)
from pipeline.layer2_acquisition_providers p
left join vault.decrypted_secrets ds on ds.id=p.vault_secret_id
where p.id=p_provider_id
$$;
revoke all on function public.layer2_provider_runtime_config(uuid) from public,anon,authenticated;
grant execute on function public.layer2_provider_runtime_config(uuid) to service_role;

create or replace function public.layer2_provider_attempt_start(p_job_id uuid,p_provider_id uuid,p_request_url text)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,pipeline,public,security
as $$
declare
  v_version uuid;
  v_attempt int;
  v_id uuid;
  v_budget jsonb;
  v_planned numeric:=1;
begin
  if auth.role()<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  select source_profile_version_id into v_version from pipeline.jobs where id=p_job_id;
  if v_version is null then raise exception 'versioned Layer 2 job required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtext('layer2-provider-budget:'||p_provider_id::text)::bigint);
  select coalesce(nullif(request_template->>'fixed_credit_units','')::numeric,1) into v_planned
  from pipeline.layer2_acquisition_providers where id=p_provider_id;
  v_budget:=security.layer2_provider_budget_status(p_provider_id,v_planned);
  if coalesce((v_budget->>'allowed')::boolean,true) is not true then
    raise exception 'provider monthly budget stop threshold reached: %',v_budget using errcode='P0001';
  end if;
  select coalesce(max(attempt_no),0)+1 into v_attempt from pipeline.layer2_provider_attempts where job_id=p_job_id;
  insert into pipeline.layer2_provider_attempts(job_id,profile_version_id,acquisition_provider_id,attempt_no,status,request_url,started_at,metrics)
  values(p_job_id,v_version,p_provider_id,v_attempt,'running',p_request_url,now(),jsonb_build_object('budget_at_start',v_budget))
  returning id into v_id;
  return v_id;
end
$$;
revoke all on function public.layer2_provider_attempt_start(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.layer2_provider_attempt_start(uuid,uuid,text) to service_role;
