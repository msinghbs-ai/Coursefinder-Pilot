create or replace function public.layer2_provider_runtime_config_by_key(p_provider_key text)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','public','pipeline','vault','security'
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
where p.provider_key=p_provider_key
$$;

revoke all on function public.layer2_provider_runtime_config_by_key(text) from public, anon, authenticated;
grant execute on function public.layer2_provider_runtime_config_by_key(text) to service_role;
