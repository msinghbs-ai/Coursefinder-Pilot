CREATE OR REPLACE FUNCTION security.admin_provider_asset_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'pipeline', 'ref', 'ranking', 'auth'
AS $function$
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
$function$
