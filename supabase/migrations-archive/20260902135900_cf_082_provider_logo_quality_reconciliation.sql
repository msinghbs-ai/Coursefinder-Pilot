begin;
create or replace function public.layer2_shared_fetch_fanout_context(p_shared_fetch_id uuid)
returns jsonb language sql security definer
set search_path='pg_catalog','public','pipeline','catalogue' as $$
 select jsonb_build_object(
   'shared_fetch_id',f.id,'source_url',f.source_url,'evidence_id',e.id,'storage_path',e.storage_path,
   'mime_type',coalesce(e.mime_type,f.mime_type),'content_hash',coalesce(e.content_hash,f.content_hash),
   'source_id',e.source_id,'provider_id',s.provider_id,'provider_name',p.canonical_name,
   'logo_profile_id',(select x.id from pipeline.layer2_source_profiles x where x.source_id=e.source_id and x.domain='provider_asset' and x.enabled and not x.paused order by x.updated_at desc limit 1),
   'scholarship_profile_id',(select x.id from pipeline.layer2_source_profiles x where x.source_id=e.source_id and x.domain='scholarship' and x.enabled and not x.paused order by x.updated_at desc limit 1),
   'scholarship_profile_version_id',(select x.current_version_id from pipeline.layer2_source_profiles x where x.source_id=e.source_id and x.domain='scholarship' and x.enabled and not x.paused order by x.updated_at desc limit 1)
 )
 from pipeline.layer2_shared_fetches f
 join pipeline.evidence_artifacts e on e.id=f.evidence_id
 join pipeline.sources s on s.id=e.source_id
 join catalogue.providers p on p.id=s.provider_id
 where f.id=p_shared_fetch_id
$$;
revoke all on function public.layer2_shared_fetch_fanout_context(uuid) from public,anon,authenticated;
grant execute on function public.layer2_shared_fetch_fanout_context(uuid) to service_role;

update pipeline.provider_asset_candidates
set status='rejected',
    metadata=metadata||jsonb_build_object('review_reason','CF-082 bounded UAT false positive: partner/network logo','reviewed_at',now())
where asset_url in (
 'https://www.acu.edu.au/-/media/feature/pagecontent/richtext/about-acu/our-partnerships/2050alliance_logo_col_stacked.svg?rev=598e8bc74d334f79a803363843145ab6',
 'https://assets.cqu.edu.au/api/public/content/run-logo.png'
);

commit;