begin;

create or replace function public.layer2_shared_fetch_fanout_context(p_shared_fetch_id uuid)
returns jsonb language sql security definer
set search_path='pg_catalog','public','pipeline','catalogue' as $$
 select jsonb_build_object(
   'shared_fetch_id',f.id,
   'source_url',f.source_url,
   'evidence_id',e.id,
   'storage_path',e.storage_path,
   'mime_type',coalesce(e.mime_type,f.mime_type),
   'content_hash',coalesce(e.content_hash,f.content_hash),
   'source_id',e.source_id,
   'provider_id',s.provider_id,
   'provider_name',p.canonical_name,
   'logo_profile_id',(select lp.id from pipeline.layer2_source_profiles lp where lp.source_id=e.source_id and lp.domain='provider_asset' and lp.enabled and not lp.paused order by lp.updated_at desc limit 1),
   'scholarship_profile_id',(select sp.id from pipeline.layer2_source_profiles sp where sp.source_id=e.source_id and sp.domain='scholarship' and sp.enabled and not sp.paused order by sp.updated_at desc limit 1),
   'scholarship_profile_version_id',(select sp.current_version_id from pipeline.layer2_source_profiles sp where sp.source_id=e.source_id and sp.domain='scholarship' and sp.enabled and not sp.paused order by sp.updated_at desc limit 1)
 )
 from pipeline.layer2_shared_fetches f
 join pipeline.evidence_artifacts e on e.id=f.evidence_id
 join pipeline.sources s on s.id=e.source_id
 join catalogue.providers p on p.id=s.provider_id
 where f.id=p_shared_fetch_id
$$;
revoke all on function public.layer2_shared_fetch_fanout_context(uuid) from public,anon,authenticated;
grant execute on function public.layer2_shared_fetch_fanout_context(uuid) to service_role;

create or replace function public.layer2_provider_page_fanout_apply(
 p_shared_fetch_id uuid,
 p_logo_candidates jsonb default '[]'::jsonb,
 p_scholarship_links jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','pipeline','catalogue' as $$
declare v_ctx jsonb;v_logo jsonb;v_link jsonb;v_logo_count int:=0;v_sch_count int:=0;
begin
 select public.layer2_shared_fetch_fanout_context(p_shared_fetch_id) into v_ctx;
 if v_ctx is null or v_ctx='null'::jsonb then raise exception 'shared_fetch_not_found' using errcode='P0002'; end if;
 for v_logo in select value from jsonb_array_elements(coalesce(p_logo_candidates,'[]'::jsonb)) loop
   insert into pipeline.provider_asset_candidates(provider_id,profile_id,source_url,asset_url,asset_type,evidence_id,content_hash,confidence,status,metadata)
   values((v_ctx->>'provider_id')::uuid,nullif(v_ctx->>'logo_profile_id','')::uuid,v_ctx->>'source_url',v_logo->>'url','logo',
     (v_ctx->>'evidence_id')::uuid,null,nullif(v_logo->>'score','')::numeric,
     case when coalesce((v_logo->>'score')::numeric,0)>=0.90 then 'accepted'
          when coalesce((v_logo->>'score')::numeric,0)>=0.65 then 'needs_review' else 'discovered' end,
     jsonb_strip_nulls(jsonb_build_object(
       'worker_version','layer2-provider-page-fanout-v1.5','kind',v_logo->>'kind','alt',v_logo->>'alt',
       'selector_hint',v_logo->>'selector_hint','inline_svg',v_logo->>'inline_svg',
       'canonical_mutation_authorised',false,'approval_threshold',0.90,'change_control_ref','CF-CHG-20260903-101'))
   )
   on conflict(provider_id,asset_url) do update set profile_id=excluded.profile_id,source_url=excluded.source_url,evidence_id=excluded.evidence_id,
     confidence=excluded.confidence,status=excluded.status,metadata=excluded.metadata,discovered_at=now();
   v_logo_count:=v_logo_count+1;
 end loop;
 for v_link in select value from jsonb_array_elements(coalesce(p_scholarship_links,'[]'::jsonb)) loop
   insert into pipeline.layer2_scholarship_discovery_candidates(source_id,evidence_id,source_profile_version_id,scholarship_url,observed_title,status)
   values((v_ctx->>'source_id')::uuid,(v_ctx->>'evidence_id')::uuid,nullif(v_ctx->>'scholarship_profile_version_id','')::uuid,v_link->>'url',nullif(v_link->>'title',''),'discovered')
   on conflict(evidence_id,scholarship_url) do nothing;
   if found then v_sch_count:=v_sch_count+1; end if;
 end loop;
 update pipeline.layer2_fanout_tasks set status='completed',completed_at=now(),last_error=null,
   metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('worker_version','layer2-provider-page-fanout-v1.5','logo_candidates',jsonb_array_length(coalesce(p_logo_candidates,'[]'::jsonb)),'scholarship_links',jsonb_array_length(coalesce(p_scholarship_links,'[]'::jsonb)))
 where shared_fetch_id=p_shared_fetch_id and task_type in('provider_asset','scholarship_discovery');
 return jsonb_build_object('provider_id',v_ctx->>'provider_id','logo_rows_written',v_logo_count,'scholarship_rows_written',v_sch_count);
end $$;
revoke all on function public.layer2_provider_page_fanout_apply(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_provider_page_fanout_apply(uuid,jsonb,jsonb) to service_role;

create or replace function public.layer2_provider_asset_promotion_context(p_candidate_id uuid)
returns jsonb language sql security definer
set search_path='pg_catalog','public','pipeline','catalogue' as $$
 select jsonb_build_object(
   'candidate_id',c.id,'provider_id',c.provider_id,'provider_name',p.canonical_name,
   'asset_url',c.asset_url,'asset_type',c.asset_type,'candidate_status',c.status,
   'confidence',c.confidence,'evidence_id',c.evidence_id,'profile_id',c.profile_id,
   'source_url',c.source_url,'metadata',c.metadata
 )
 from pipeline.provider_asset_candidates c join catalogue.providers p on p.id=c.provider_id
 where c.id=p_candidate_id
$$;
revoke all on function public.layer2_provider_asset_promotion_context(uuid) from public,anon,authenticated;
grant execute on function public.layer2_provider_asset_promotion_context(uuid) to service_role;

commit;
