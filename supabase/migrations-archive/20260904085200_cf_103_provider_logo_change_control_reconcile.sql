begin;

create or replace function public.svc_provider_asset_manual_upload_apply(
  p_provider_id uuid,
  p_storage_path text,
  p_mime_type text,
  p_content_hash text,
  p_actor_id uuid
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','catalogue','security','public'
as $$
declare v_asset_id uuid;v_source_url text;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if not exists(select 1 from catalogue.providers p where p.id=p_provider_id) then raise exception 'provider_not_found' using errcode='P0002'; end if;
  if nullif(p_storage_path,'') is null or nullif(p_content_hash,'') is null then raise exception 'stored_asset_hash_required' using errcode='23514'; end if;
  if p_mime_type not in ('image/svg+xml','image/png','image/jpeg','image/webp') then raise exception 'unsupported_asset_mime' using errcode='23514'; end if;
  v_source_url:='manual-upload://provider/'||p_provider_id::text||'/logo/'||p_content_hash;
  update catalogue.provider_assets set is_primary=false,status=case when status='approved' then 'superseded' else status end where provider_id=p_provider_id and is_primary and asset_type in ('logo','logo_dark','logo_light');
  select id into v_asset_id from catalogue.provider_assets where provider_id=p_provider_id and asset_type='logo' and coalesce(content_hash,'')=p_content_hash and source_url=v_source_url order by verified_at desc nulls last,id limit 1;
  if v_asset_id is null then
    insert into catalogue.provider_assets(provider_id,asset_type,source_url,evidence_id,storage_path,mime_type,width,height,content_hash,is_primary,status,observed_at,verified_at,metadata)
    values(p_provider_id,'logo',v_source_url,null,p_storage_path,p_mime_type,null,null,p_content_hash,true,'approved',now(),now(),jsonb_build_object('source_class','manual_admin_upload','uploaded_by',p_actor_id,'uploaded_at',now(),'change_control_ref','CF-CHG-20260904-103','managed_storage',true))
    returning id into v_asset_id;
  else
    update catalogue.provider_assets set storage_path=p_storage_path,mime_type=p_mime_type,is_primary=true,status='approved',verified_at=now(),metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('source_class','manual_admin_upload','uploaded_by',p_actor_id,'uploaded_at',now(),'change_control_ref','CF-CHG-20260904-103','managed_storage',true) where id=v_asset_id;
  end if;
  return jsonb_build_object('provider_id',p_provider_id,'provider_asset_id',v_asset_id,'storage_path',p_storage_path,'content_hash',p_content_hash,'primary',true,'status','approved');
end
$$;

update catalogue.provider_assets
set metadata=jsonb_set(coalesce(metadata,'{}'::jsonb),'{change_control_ref}','"CF-CHG-20260904-103"'::jsonb,true)
where metadata->>'source_class'='manual_admin_upload' and metadata->>'change_control_ref'='CF-CHG-20260904-093';

commit;
