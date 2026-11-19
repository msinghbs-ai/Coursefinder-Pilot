begin;

-- CF-CHG-20260903-101 — Hotcourses reconciliation layer for remaining H11 university logo exceptions.
-- Hotcourses remains discovery/reconciliation only. No Hotcourses-hosted asset is promoted.

with hc(provider_id,hotcourses_id,hotcourses_slug,hotcourses_url) as (values
 ('030992c3-72c6-452d-8a3b-10ceb0fd77f2'::uuid,'72206','australian-catholic-university','https://www.hotcoursesabroad.com/study/australia/school-college-university/australian-catholic-university/72206/international.html'),
 ('188103a5-1aba-4f99-bd3e-0416659086d3'::uuid,'72221','macquarie-university','https://www.hotcoursesabroad.com/study/australia/school-college-university/macquarie-university/72221/international.html'),
 ('2c4f515c-c146-4e90-ba8a-294130aa1f40'::uuid,'72224','queensland-university-of-technology','https://www.hotcoursesabroad.com/study/australia/school-college-university/queensland-university-of-technology/72224/international.html'),
 ('36086f5e-9fe0-4878-aa40-1897a7d8cb24'::uuid,'72218','griffith-university','https://www.hotcoursesabroad.com/study/australia/school-college-university/griffith-university/72218/international.html'),
 ('39301fa8-bff2-4389-bbcd-32d8415fae04'::uuid,'142314','auckland-university-of-technology','https://www.hotcoursesabroad.com/study/newzealand/school-college-university/auckland-university-of-technology/142314/international.html'),
 ('4f86e09a-557c-4544-a0a3-3eb5dc8468a9'::uuid,'72220','la-trobe-university','https://www.hotcoursesabroad.com/study/australia/school-college-university/la-trobe-university/72220/international.html'),
 ('543b87b8-f0dd-4bc7-80d6-76252cfaabec'::uuid,'72222','monash-university','https://www.hotcoursesabroad.com/study/australia/school-college-university/monash-university/72222/international.html'),
 ('719403bc-6957-4d21-af69-2b3b102df578'::uuid,'72240','university-of-tasmania','https://www.hotcoursesabroad.com/study/australia/school-college-university/university-of-tasmania/72240/international.html'),
 ('ab12c7f8-e368-453d-9dfe-4ab8bd744829'::uuid,'142319','university-of-otago','https://www.hotcoursesabroad.com/study/newzealand/school-college-university/university-of-otago/142319/international.html'),
 ('dce54a01-39c1-4bdf-877d-b67da3afc81e'::uuid,'115245','university-of-notre-dame','https://www.hotcoursesabroad.com/study/australia/school-college-university/university-of-notre-dame/115245/international.html'),
 ('f34fae5e-b5b9-4c82-a6ca-44bf0803020e'::uuid,'72213','charles-sturt-university','https://www.hotcoursesabroad.com/study/australia/school-college-university/charles-sturt-university/72213/international.html'),
 ('fa0e0d13-838a-42ff-b6a3-9cea84bd80b2'::uuid,'72232','university-of-new-england-une','https://www.hotcoursesabroad.com/study/australia/school-college-university/university-of-new-england-une/72232/international.html'),
 ('fe6af182-f5ca-4a3c-bfb4-b0773ff1b113'::uuid,'72219','james-cook-university','https://www.hotcoursesabroad.com/study/australia/school-college-university/james-cook-university/72219/international.html')
)
insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'third_party_directory',h.provider_id,p.country_id,h.hotcourses_url,
       p.canonical_name||' — Hotcourses Abroad reconciliation',30,'active',
       jsonb_build_object(
         'directory','hotcourses_abroad',
         'directory_id',h.hotcourses_id,
         'directory_slug',h.hotcourses_slug,
         'purpose','provider_logo_discovery_and_reconciliation_only',
         'canonical_asset_authority',false,
         'operator_fallback_reuse_approved',true,
         'rights_owner_basis','university_provider_mark',
         'source_host_role','aggregator_transport_copy',
         'terms_note','operator approved use of exact university-owned logo copy; preserve source provenance',
         'change_control_ref','CF-CHG-20260903-101'
       )
from hc h join catalogue.providers p on p.id=h.provider_id
where not exists(
 select 1 from pipeline.sources s
 where s.provider_id=h.provider_id
   and s.source_type='third_party_directory'
   and s.metadata->>'directory'='hotcourses_abroad'
);

create or replace function security.admin_provider_asset_read(
  p_operation text,
  p_args jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','security','catalogue','pipeline','ref','ranking','auth'
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_country text:=upper(nullif(btrim(p_args->>'country_code'),''));
  v_query text:=nullif(btrim(p_args->>'query'),'');
  v_state text:=nullif(btrim(p_args->>'state'),'');
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  if p_operation='provider_asset_summary' then
    return (
      with university_scope as (
        select distinct p.id,p.canonical_name,p.display_name,p.stable_key,c.iso_alpha2 country_code
        from catalogue.providers p
        join ref.countries c on c.id=p.country_id
        join (
          select provider_id from ranking.observations where provider_id is not null
          union
          select provider_id from ranking.observation_provider_links
        ) r on r.provider_id=p.id
        where c.iso_alpha2 in('AU','NZ')
          and coalesce(p.lifecycle_status,'active')='active'
          and (v_country is null or c.iso_alpha2=v_country)
          and (v_query is null or p.canonical_name ilike '%'||v_query||'%' or coalesce(p.display_name,'') ilike '%'||v_query||'%' or coalesce(p.stable_key,'') ilike '%'||v_query||'%')
      ), base as (
        select u.*,
          exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=u.id and pc.asset_type ilike 'logo%') discovered,
          exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=u.id and pc.asset_type ilike 'logo%' and pc.evidence_id is not null) evidence_backed,
          exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=u.id and pc.asset_type ilike 'logo%' and pc.status='accepted') accepted_candidate,
          exists(select 1 from catalogue.provider_assets pa where pa.provider_id=u.id and pa.is_primary and pa.status='approved' and pa.asset_type in ('logo','logo_dark','logo_light')) approved_primary,
          exists(select 1 from pipeline.sources s where s.provider_id=u.id and s.source_type='third_party_directory' and s.metadata->>'directory'='hotcourses_abroad') hotcourses_matched
        from university_scope u
      )
      select jsonb_build_object(
        'scope_basis','AU/NZ canonical university cohort defined by accepted ranking Provider mappings; Hotcourses is discovery/reconciliation only',
        'country_code',v_country,'expected',count(*),'discovered',count(*) filter(where discovered),
        'acquired',count(*) filter(where evidence_backed or approved_primary),'approved',count(*) filter(where approved_primary),
        'blocked',count(*) filter(where accepted_candidate and not approved_primary),'missing',count(*) filter(where not discovered),
        'needs_review',count(*) filter(where discovered and not accepted_candidate and not approved_primary),
        'hotcourses_matched',count(*) filter(where hotcourses_matched),
        'refresh_cadence','quarterly','authority','first_party_provider',
        'third_party_discovery_policy','Exact university-logo copies from Hotcourses may be promoted as operator-approved fallbacks; canonical ownership remains the Provider and Hotcourses provenance is retained'
      ) from base
    );
  elsif p_operation='provider_asset_coverage' then
    return (
      with university_scope as (
        select distinct p.id provider_id,p.stable_key,coalesce(p.display_name,p.canonical_name) provider_name,p.website,p.lifecycle_status,
          c.iso_alpha2 country_code,c.name country_name
        from catalogue.providers p
        join ref.countries c on c.id=p.country_id
        join (
          select provider_id from ranking.observations where provider_id is not null
          union
          select provider_id from ranking.observation_provider_links
        ) r on r.provider_id=p.id
        where c.iso_alpha2 in('AU','NZ')
          and coalesce(p.lifecycle_status,'active')='active'
          and (v_country is null or c.iso_alpha2=v_country)
          and (v_query is null or p.canonical_name ilike '%'||v_query||'%' or coalesce(p.display_name,'') ilike '%'||v_query||'%' or coalesce(p.stable_key,'') ilike '%'||v_query||'%')
      ), base as (
        select u.*,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%') candidate_count,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%' and pc.evidence_id is not null) evidence_candidate_count,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%' and pc.status='accepted') accepted_candidate_count,
          (select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%' and pc.status='rejected') rejected_candidate_count,
          (select max(pc.discovered_at) from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%') latest_candidate_at,
          (select s.url from pipeline.sources s where s.provider_id=u.provider_id and s.source_type='third_party_directory' and s.metadata->>'directory'='hotcourses_abroad' order by s.updated_at desc limit 1) hotcourses_url,
          (select s.metadata->>'directory_id' from pipeline.sources s where s.provider_id=u.provider_id and s.source_type='third_party_directory' and s.metadata->>'directory'='hotcourses_abroad' order by s.updated_at desc limit 1) hotcourses_id,
          pa.id primary_asset_id,pa.source_url primary_source_url,pa.evidence_id primary_evidence_id,pa.storage_path primary_storage_path,
          pa.mime_type primary_mime_type,pa.content_hash primary_content_hash,pa.verified_at primary_verified_at,
          case when pa.id is not null then 'approved'
            when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%' and pc.status='accepted') then 'blocked'
            when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=u.provider_id and pc.asset_type ilike 'logo%') then 'needs_review'
            else 'missing' end coverage_state
        from university_scope u
        left join lateral (
          select x.* from catalogue.provider_assets x where x.provider_id=u.provider_id and x.is_primary and x.status='approved'
            and x.asset_type in ('logo','logo_dark','logo_light')
          order by x.verified_at desc nulls last,x.id limit 1
        ) pa on true
      ), filtered as (select * from base where v_state is null or coverage_state=v_state),
      page as (
        select * from filtered order by case coverage_state when 'blocked' then 1 when 'needs_review' then 2 when 'missing' then 3 else 4 end,
          lower(provider_name),provider_id limit v_limit offset v_offset
      )
      select jsonb_build_object('total',(select count(*) from filtered),'limit',v_limit,'offset',v_offset,
        'items',coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb))
    );
  elsif p_operation='provider_asset_context' then
    return (
      select jsonb_build_object(
        'provider_id',p.id,
        'state',case when pa.id is not null then 'approved'
          when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%' and pc.status='accepted') then 'blocked'
          when exists(select 1 from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%') then 'needs_review'
          else 'missing' end,
        'primary_asset',case when pa.id is null then null else jsonb_build_object('id',pa.id,'source_url',pa.source_url,'evidence_id',pa.evidence_id,'storage_path',pa.storage_path,'mime_type',pa.mime_type,'content_hash',pa.content_hash,'verified_at',pa.verified_at) end,
        'candidate_count',(select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%'),
        'accepted_candidate_count',(select count(*) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%' and pc.status='accepted'),
        'hotcourses_reference',(select jsonb_build_object('id',s.metadata->>'directory_id','url',s.url,'fallback_reuse_approved',coalesce((s.metadata->>'operator_fallback_reuse_approved')::boolean,false),'rights_owner_basis',s.metadata->>'rights_owner_basis') from pipeline.sources s where s.provider_id=p.id and s.source_type='third_party_directory' and s.metadata->>'directory'='hotcourses_abroad' order by s.updated_at desc limit 1),
        'latest_candidate_at',(select max(pc.discovered_at) from pipeline.provider_asset_candidates pc where pc.provider_id=p.id and pc.asset_type ilike 'logo%'),
        'authority','first_party_provider','refresh_cadence','quarterly')
      from catalogue.providers p
      left join lateral (
        select x.* from catalogue.provider_assets x where x.provider_id=p.id and x.is_primary and x.status='approved'
          and x.asset_type in ('logo','logo_dark','logo_light')
        order by x.verified_at desc nulls last,x.id limit 1
      ) pa on true
      where p.id=nullif(p_args->>'provider_id','')::uuid
    );
  end if;
  raise exception 'unsupported provider asset read operation: %',p_operation using errcode='22023';
end
$$;

revoke all on function security.admin_provider_asset_read(text,jsonb) from public,anon,authenticated;
grant execute on function security.admin_provider_asset_read(text,jsonb) to authenticated;

commit;
