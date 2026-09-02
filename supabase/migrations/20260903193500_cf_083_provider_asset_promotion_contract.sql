begin;

create or replace function public.layer2_provider_asset_promotion_context(p_candidate_id uuid)
returns jsonb language sql security definer
set search_path='pg_catalog','public','pipeline','catalogue' as $$
 select jsonb_build_object(
   'candidate_id',c.id,
   'provider_id',c.provider_id,
   'provider_name',p.canonical_name,
   'asset_url',c.asset_url,
   'asset_type',c.asset_type,
   'candidate_status',c.status,
   'confidence',c.confidence,
   'evidence_id',c.evidence_id,
   'profile_id',c.profile_id,
   'source_url',c.source_url
 )
 from pipeline.provider_asset_candidates c
 join catalogue.providers p on p.id=c.provider_id
 where c.id=p_candidate_id
$$;
revoke all on function public.layer2_provider_asset_promotion_context(uuid) from public,anon,authenticated;
grant execute on function public.layer2_provider_asset_promotion_context(uuid) to service_role;

create or replace function public.layer2_provider_asset_promote_apply(
 p_candidate_id uuid,
 p_storage_path text,
 p_mime_type text,
 p_content_hash text,
 p_width integer default null,
 p_height integer default null
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','pipeline','catalogue' as $$
declare c pipeline.provider_asset_candidates%rowtype; v_asset uuid;
begin
 select * into c from pipeline.provider_asset_candidates where id=p_candidate_id for update;
 if not found then raise exception 'asset_candidate_not_found' using errcode='P0002'; end if;
 if c.status<>'accepted' or coalesce(c.confidence,0)<0.90 then
   raise exception 'asset_candidate_not_approved_for_promotion' using errcode='23514';
 end if;
 if nullif(p_storage_path,'') is null or nullif(p_content_hash,'') is null then
   raise exception 'stored_asset_hash_required' using errcode='23514';
 end if;

 update catalogue.provider_assets
 set is_primary=false, status=case when status='approved' then 'superseded' else status end
 where provider_id=c.provider_id and is_primary and asset_type in('logo','logo_dark','logo_light');

 insert into catalogue.provider_assets(
   provider_id,asset_type,source_url,evidence_id,storage_path,mime_type,width,height,content_hash,
   is_primary,status,observed_at,verified_at,metadata
 ) values(
   c.provider_id,'logo',c.asset_url,c.evidence_id,p_storage_path,p_mime_type,p_width,p_height,p_content_hash,
   true,'approved',c.discovered_at,now(),
   jsonb_build_object('candidate_id',c.id,'confidence',c.confidence,'promotion_worker','layer2-provider-asset-promote-v1','change_control_ref','CF-CHG-20260903-083')
 )
 on conflict(provider_id,asset_type,coalesce(content_hash,''),source_url) do update set
   evidence_id=excluded.evidence_id,storage_path=excluded.storage_path,mime_type=excluded.mime_type,
   width=excluded.width,height=excluded.height,is_primary=true,status='approved',verified_at=now(),metadata=excluded.metadata
 returning id into v_asset;

 update pipeline.provider_asset_candidates
 set status='accepted',
     metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('promoted_asset_id',v_asset,'promoted_at',now())
 where id=c.id;

 return jsonb_build_object('provider_id',c.provider_id,'provider_asset_id',v_asset,'primary',true,'storage_path',p_storage_path,'content_hash',p_content_hash);
end $$;
revoke all on function public.layer2_provider_asset_promote_apply(uuid,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.layer2_provider_asset_promote_apply(uuid,text,text,text,integer,integer) to service_role;

commit;