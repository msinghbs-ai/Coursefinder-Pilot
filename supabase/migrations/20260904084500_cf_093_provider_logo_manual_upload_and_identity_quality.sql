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

  update catalogue.provider_assets set is_primary=false,status=case when status='approved' then 'superseded' else status end
  where provider_id=p_provider_id and is_primary and asset_type in ('logo','logo_dark','logo_light');

  select id into v_asset_id from catalogue.provider_assets
  where provider_id=p_provider_id and asset_type='logo' and coalesce(content_hash,'')=p_content_hash and source_url=v_source_url
  order by verified_at desc nulls last,id limit 1;

  if v_asset_id is null then
    insert into catalogue.provider_assets(provider_id,asset_type,source_url,evidence_id,storage_path,mime_type,width,height,content_hash,is_primary,status,observed_at,verified_at,metadata)
    values(p_provider_id,'logo',v_source_url,null,p_storage_path,p_mime_type,null,null,p_content_hash,true,'approved',now(),now(),jsonb_build_object('source_class','manual_admin_upload','uploaded_by',p_actor_id,'uploaded_at',now(),'change_control_ref','CF-CHG-20260904-093','managed_storage',true))
    returning id into v_asset_id;
  else
    update catalogue.provider_assets set storage_path=p_storage_path,mime_type=p_mime_type,is_primary=true,status='approved',verified_at=now(),metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('source_class','manual_admin_upload','uploaded_by',p_actor_id,'uploaded_at',now(),'change_control_ref','CF-CHG-20260904-093','managed_storage',true)
    where id=v_asset_id;
  end if;
  return jsonb_build_object('provider_id',p_provider_id,'provider_asset_id',v_asset_id,'storage_path',p_storage_path,'content_hash',p_content_hash,'primary',true,'status','approved');
end
$$;
revoke all on function public.svc_provider_asset_manual_upload_apply(uuid,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.svc_provider_asset_manual_upload_apply(uuid,text,text,text,uuid) to service_role;

create or replace function public.svc_provider_asset_access_descriptors(p_stable_keys text[])
returns jsonb language sql security definer set search_path='pg_catalog','catalogue','public' as $$
  with requested as (select distinct nullif(btrim(x),'') stable_key from unnest(coalesce(p_stable_keys,array[]::text[])) x),
  matched as (
    select p.stable_key,p.id provider_id,a.id provider_asset_id,a.asset_type,a.storage_path,a.mime_type,a.content_hash,a.verified_at,a.source_url
    from requested r join catalogue.providers p on p.stable_key=r.stable_key
    left join lateral (
      select x.* from catalogue.provider_assets x where x.provider_id=p.id and x.is_primary and x.status='approved' and x.asset_type in('logo','logo_dark','logo_light') and x.storage_path is not null
      order by case x.asset_type when 'logo' then 0 when 'logo_light' then 1 else 2 end,x.verified_at desc nulls last,x.id limit 1
    ) a on true
  )
  select coalesce(jsonb_agg(jsonb_build_object('stable_key',stable_key,'provider_id',provider_id,'provider_asset_id',provider_asset_id,'asset_type',asset_type,'storage_path',storage_path,'mime_type',mime_type,'content_hash',content_hash,'verified_at',verified_at,'source_url',source_url) order by stable_key),'[]'::jsonb) from matched
$$;
revoke all on function public.svc_provider_asset_access_descriptors(text[]) from public,anon,authenticated;
grant execute on function public.svc_provider_asset_access_descriptors(text[]) to service_role;

create or replace function public.provider_identity_quality_summary()
returns jsonb language plpgsql stable security definer set search_path='pg_catalog','catalogue','ref','security','auth' as $$
declare v_rank integer:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  return (select jsonb_build_object(
    'providers',count(*),
    'missing_canonical_name',count(*) filter(where canonical_name is null or btrim(canonical_name)=''),
    'missing_display_name',count(*) filter(where display_name is null or btrim(display_name)=''),
    'institution_like_city',count(*) filter(where nullif(primary_city,'') is not null and primary_city ~* '(university|institute|college|school|academy|pty|limited|ltd|education|tafe)'),
    'display_matches_subdivision',count(*) filter(where exists(select 1 from ref.subdivisions s where lower(btrim(s.name))=lower(btrim(coalesce(display_name,''))))),
    'canonical_matches_subdivision',count(*) filter(where exists(select 1 from ref.subdivisions s where lower(btrim(s.name))=lower(btrim(coalesce(canonical_name,''))))),
    'display_differs_from_canonical',count(*) filter(where nullif(btrim(display_name),'') is not null and lower(btrim(display_name))<>lower(btrim(canonical_name)))
  ) from catalogue.providers);
end
$$;
revoke all on function public.provider_identity_quality_summary() from public,anon;
grant execute on function public.provider_identity_quality_summary() to authenticated;

update catalogue.providers set primary_city='Sydney',updated_at=now()
where stable_key='provider:cricos:00026a' and canonical_name='The University of Sydney' and primary_city='The University of Sydney';

commit;
