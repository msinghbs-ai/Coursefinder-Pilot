begin;
do $$
declare v_source pipeline.layer3_model_profiles%rowtype;v_target pipeline.layer3_model_profiles%rowtype;v_secret text;v_target_name text;v_existing uuid;
begin
  select * into v_source from pipeline.layer3_model_profiles where code='openrouter-free-router-v1';
  select * into v_target from pipeline.layer3_model_profiles where code='openrouter-provider-tuition-validation-v1';
  if not found or v_source.id is null or v_target.id is null then raise exception 'source/target Layer3 profile missing'; end if;
  if v_source.aggregator_provider<>v_target.aggregator_provider or v_source.base_url<>v_target.base_url then raise exception 'credential binding provider mismatch'; end if;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name=security.layer3_provider_credential_name(v_source.id) limit 1;
  if v_secret is null or length(v_secret)<20 then raise exception 'governed source profile credential unavailable'; end if;
  v_target_name:=security.layer3_provider_credential_name(v_target.id);
  select id into v_existing from vault.secrets where name=v_target_name limit 1;
  if v_existing is null then perform vault.create_secret(v_secret,v_target_name,'CF-245 dedicated tuition validation profile credential binding from governed OpenRouter base profile'); end if;
  update pipeline.layer3_model_profiles set paused=true,
    last_validation_result=jsonb_build_object('state','credential_bound_pending_fee_specific_benchmark','validated',false,'credential_configured',true,'credential_configured_at',now(),'provider',aggregator_provider,'credential_source_profile','openrouter-free-router-v1','change_control_ref','CF-CHG-20260915-245'),updated_at=now()
  where id=v_target.id;
  insert into pipeline.layer3_provider_credential_audit(profile_id,action,actor_id,reason)
  values(v_target.id,case when v_existing is null then 'set' else 'verified' end,'00000000-0000-0000-0000-000000000000'::uuid,'CF-245 same-provider server-side credential binding; benchmark remains mandatory and profile remains paused');
end $$;
commit;
