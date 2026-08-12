-- PostgREST service-role RPCs execute through the authenticator session.
-- Function ACLs are the enforcement boundary; do not reject valid service-role calls by session_user.
create or replace function public.svc_layer1_apply_ca_ircc_providers(
  p_source_id uuid,
  p_evidence_id uuid,
  p_records jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'public','catalogue','pim','ref','pipeline'
as $function$
declare
  r jsonb; v_country uuid; v_provider uuid; v_family_provider uuid;
  v_pcode text; v_pname text; v_provider_key text;
  v_provider_created int:=0; v_provider_existing int:=0; v_conflicts int:=0;
begin
  select id into v_country from ref.countries where upper(iso_alpha2::text)='CA';
  if v_country is null then raise exception 'country seed missing: CA'; end if;
  select id into v_family_provider from pim.attribute_families where entity_type='provider' and status='active' order by case when code='provider_default' then 0 else 1 end limit 1;

  for r in select value from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) loop
    v_pcode:=upper(nullif(trim(r->>'provider_code'),''));
    v_pname:=nullif(trim(r->>'provider_name'),'');
    if v_pcode is null or v_pname is null or v_pcode !~ '^O[0-9]{10,15}$' then v_conflicts:=v_conflicts+1; continue; end if;
    v_provider_key:='provider:ca:ircc_dli:'||lower(v_pcode); v_provider:=null;
    select pi.provider_id into v_provider from catalogue.provider_identifiers pi where pi.country_id=v_country and lower(pi.scheme)='ircc_dli' and upper(pi.identifier)=v_pcode order by pi.is_primary desc, pi.verified_at desc nulls last limit 1;
    if v_provider is null then select id into v_provider from catalogue.providers where stable_key=v_provider_key limit 1; end if;
    if v_provider is null then
      insert into pim.entity_registry(entity_type,stable_key,family_id) values('provider',v_provider_key,v_family_provider) returning id into v_provider;
      insert into catalogue.providers(id,stable_key,canonical_name,display_name,country_id,lifecycle_status,publication_status,canonical_source_id,last_verified_at) values(v_provider,v_provider_key,v_pname,v_pname,v_country,'active','unpublished',p_source_id,now());
      v_provider_created:=v_provider_created+1;
    else
      update catalogue.providers set canonical_name=v_pname,display_name=v_pname,canonical_source_id=p_source_id,last_verified_at=now(),updated_at=now() where id=v_provider;
      v_provider_existing:=v_provider_existing+1;
    end if;
    insert into catalogue.provider_identifiers(provider_id,scheme,identifier,country_id,issuing_authority,is_primary,source_id,evidence_id,verified_at) values(v_provider,'ircc_dli',v_pcode,v_country,'IRCC',true,p_source_id,p_evidence_id,now()) on conflict (provider_id,scheme,identifier) do update set source_id=excluded.source_id,evidence_id=excluded.evidence_id,verified_at=excluded.verified_at,is_primary=true;
    insert into catalogue.provider_registrations(provider_id,source_id,registration_scheme,registration_code,status,checked_at,evidence_id) values(v_provider,p_source_id,'ircc_dli',v_pcode,'active',now(),p_evidence_id) on conflict do nothing;
  end loop;
  return jsonb_build_object('records',jsonb_array_length(coalesce(p_records,'[]'::jsonb)),'provider_created',v_provider_created,'provider_existing',v_provider_existing,'conflicts',v_conflicts,'course_writes',0,'identity_contract','provider=IRCC_DLI_only');
end $function$;

revoke all on function public.svc_layer1_apply_ca_ircc_providers(uuid,uuid,jsonb) from public, anon, authenticated;
grant execute on function public.svc_layer1_apply_ca_ircc_providers(uuid,uuid,jsonb) to service_role;
