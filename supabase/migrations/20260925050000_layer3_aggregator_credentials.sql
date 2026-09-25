-- Layer 3: one API key per aggregator (programme owner decision, 25 Sep 2026).
-- OpenRouter exists so one key serves every model behind it, but keys were stored per
-- profile (seven vault copies). Profiles now resolve their key in this order:
--   1. a profile-specific key, if one was deliberately set (unchanged behaviour);
--   2. otherwise the aggregator's key, from this register.
-- The register stores only the vault secret NAME; secrets are never read out or copied.
-- Seeded to the vault entry of the currently verified Mistral profile.
create table if not exists security.layer3_aggregator_credentials(
  aggregator text primary key,
  vault_secret_name text not null,
  reason text not null,
  set_by text not null default current_user,
  set_at timestamptz not null default now()
);
alter table security.layer3_aggregator_credentials enable row level security;
revoke all on security.layer3_aggregator_credentials from public, anon, authenticated;

insert into security.layer3_aggregator_credentials(aggregator,vault_secret_name,reason)
select 'openrouter','coursefinder_layer3_profile_03beae2f-4fb1-4296-94e7-a6466df635d5',
       'CF-CHG-20260915-247: shared OpenRouter key for all Layer 3 profiles (programme owner decision 25 Sep 2026); references the verified Mistral profile entry'
where exists(select 1 from vault.secrets where name='coursefinder_layer3_profile_03beae2f-4fb1-4296-94e7-a6466df635d5')
on conflict (aggregator) do nothing;

create or replace function security.layer3_provider_credential_resolve_impl(p_profile_id uuid)
returns text language plpgsql stable security definer
set search_path to 'pg_catalog','security','vault','pipeline'
as $function$
declare v_secret text;
begin
  -- 1. Profile-specific key, if deliberately set.
  select decrypted_secret into v_secret from vault.decrypted_secrets
  where name=security.layer3_provider_credential_name(p_profile_id) limit 1;
  if v_secret is not null then return v_secret; end if;
  -- 2. The aggregator's shared key.
  select d.decrypted_secret into v_secret
  from pipeline.layer3_model_profiles p
  join security.layer3_aggregator_credentials a on a.aggregator=p.aggregator_provider
  join vault.decrypted_secrets d on d.name=a.vault_secret_name
  where p.id=p_profile_id limit 1;
  return v_secret;
end $function$;
