create or replace function api.svc_search_vector_authorize_key_v1(p_key text)
returns boolean
language sql
stable
security definer
set search_path=api,vault
as $$
  select exists(
    select 1 from vault.decrypted_secrets
    where name='coursefinder_pilot_automation_key'
      and decrypted_secret=p_key
      and length(coalesce(p_key,''))>=32
  )
$$;
revoke all on function api.svc_search_vector_authorize_key_v1(text) from public,anon,authenticated;
grant execute on function api.svc_search_vector_authorize_key_v1(text) to service_role;
