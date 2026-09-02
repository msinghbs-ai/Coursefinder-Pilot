begin;

create or replace function public.layer2_shared_fetch_register(
 p_source_url text,p_evidence_id uuid,p_content_hash text,p_mime_type text,
 p_acquisition_provider_id uuid,p_profile_id uuid,p_ttl_hours integer default 24
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','pipeline','public' as $$
declare v_id uuid;v_source uuid;v_fanout integer:=0;
begin
 select source_id into v_source from pipeline.layer2_source_profiles where id=p_profile_id;

 insert into pipeline.layer2_shared_fetches(
   url_hash,source_url,evidence_id,content_hash,mime_type,acquisition_provider_id,source_profile_id,
   captured_at,reusable_until,metadata
 ) values(
   encode(extensions.digest(lower(trim(p_source_url)),'sha256'),'hex'),
   p_source_url,p_evidence_id,p_content_hash,p_mime_type,p_acquisition_provider_id,p_profile_id,
   now(),now()+make_interval(hours=>greatest(1,least(coalesce(p_ttl_hours,24),168))),
   jsonb_build_object('registered_by','layer2-acquire-v2','canonical_mutation_authorised',false)
 )
 on conflict(url_hash) do update set
   source_url=excluded.source_url,evidence_id=excluded.evidence_id,content_hash=excluded.content_hash,
   mime_type=excluded.mime_type,acquisition_provider_id=excluded.acquisition_provider_id,
   source_profile_id=excluded.source_profile_id,captured_at=excluded.captured_at,
   reusable_until=excluded.reusable_until,metadata=excluded.metadata
 returning id into v_id;

 insert into pipeline.layer2_fanout_tasks(shared_fetch_id,profile_id,task_type,metadata)
 select v_id,p.id,
   case when p.target_entity_type='provider_asset' then 'provider_asset' else 'scholarship_discovery' end,
   jsonb_build_object('source_profile_id',p_profile_id,'source_id',v_source,'shared_evidence_id',p_evidence_id)
 from pipeline.layer2_source_profiles p
 where p.source_id=v_source
   and p.id<>p_profile_id
   and p.enabled and not p.paused
   and (p.target_entity_type='provider_asset' or p.domain='scholarship')
 on conflict(shared_fetch_id,profile_id,task_type) do nothing;
 get diagnostics v_fanout=row_count;

 return jsonb_build_object('shared_fetch_id',v_id,'fanout_tasks_created',v_fanout);
end $$;

revoke all on function public.layer2_shared_fetch_register(text,uuid,text,text,uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.layer2_shared_fetch_register(text,uuid,text,text,uuid,uuid,integer) to service_role;

update pipeline.layer2_fanout_tasks
set status='skipped',
    completed_at=now(),
    last_error='CF-082 reconciliation: Course extraction is explicit/reuse-only and is not auto-fan-out from Provider-page acquisition'
where status='queued' and task_type='extract';

commit;