begin;

create or replace function public.layer2_hotcourses_directory_apply(
 p_evidence_id uuid,
 p_rows jsonb
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline','catalogue','ref','ranking','public'
as $$
declare
 v_source uuid;
 v_country text;
 v_row jsonb;
 v_provider uuid;
 v_inserted integer:=0;
 v_matched integer:=0;
 v_candidates integer:=0;
 v_dir_id text;
 v_norm text;
begin
 select e.source_id,c.iso_alpha2 into v_source,v_country
 from pipeline.evidence_artifacts e
 join pipeline.sources s on s.id=e.source_id
 left join ref.countries c on c.id=s.country_id
 where e.id=p_evidence_id
   and s.source_type='third_party_directory'
   and s.metadata->>'directory'='hotcourses_abroad';
 if v_source is null then raise exception 'hotcourses_directory_evidence_required' using errcode='22023'; end if;
 if jsonb_typeof(coalesce(p_rows,'[]'::jsonb))<>'array' then raise exception 'rows must be array' using errcode='22023'; end if;

 for v_row in select value from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb))
 loop
   v_provider:=null;
   v_norm:=regexp_replace(regexp_replace(lower(coalesce(v_row->>'name','')),'^the\s+','','g'),'[^a-z0-9]+','','g');

   -- 1. Exact canonical/display match inside the same country after harmless leading-The normalisation.
   select p.id into v_provider
   from catalogue.providers p
   join ref.countries c on c.id=p.country_id
   where c.iso_alpha2=v_country
     and coalesce(p.lifecycle_status,'active')='active'
     and regexp_replace(regexp_replace(lower(coalesce(p.display_name,p.canonical_name,'')),'^the\s+','','g'),'[^a-z0-9]+','','g')=v_norm
   order by p.id limit 1;

   -- 2. Exact governed alias match, still constrained to the same country.
   if v_provider is null then
     select p.id into v_provider
     from catalogue.provider_aliases a
     join catalogue.providers p on p.id=a.provider_id
     join ref.countries c on c.id=p.country_id
     where c.iso_alpha2=v_country
       and coalesce(p.lifecycle_status,'active')='active'
       and regexp_replace(regexp_replace(lower(a.alias),'^the\s+','','g'),'[^a-z0-9]+','','g')=v_norm
     order by p.id limit 1;
   end if;

   v_dir_id:=coalesce(v_row->>'directory_id',
     substring(coalesce(v_row->>'institution_url','') from '/([0-9]+)/international(?:\.html)?'));

   insert into pipeline.provider_directory_observations(
     source_id,evidence_id,directory_name,directory_id,observed_name,country_code,
     institution_url,logo_url,matched_provider_id,match_method,match_confidence,metadata
   ) values(
     v_source,p_evidence_id,'hotcourses_abroad',nullif(v_dir_id,''),
     v_row->>'name',v_country,nullif(v_row->>'institution_url',''),nullif(v_row->>'logo_url',''),
     v_provider,
     case when v_provider is not null then 'country_exact_name_or_governed_alias' else 'unmatched' end,
     case when v_provider is not null then 1.0 else null end,
     jsonb_build_object(
       'parser_version','hotcourses-directory-v1.1',
       'change_control_ref','CF-CHG-20260904-102',
       'canonical_identity_mutation',false,
       'logo_candidate_policy','review_only_if_primary_missing'
     )
   )
   on conflict(source_id,evidence_id,observed_name,institution_url) do update set
     directory_id=excluded.directory_id,logo_url=excluded.logo_url,matched_provider_id=excluded.matched_provider_id,
     match_method=excluded.match_method,match_confidence=excluded.match_confidence,metadata=excluded.metadata,observed_at=now();

   v_inserted:=v_inserted+1;
   if v_provider is not null then
     v_matched:=v_matched+1;

     insert into pipeline.sources(source_type,provider_id,country_id,url,label,trust_rank,status,metadata)
     select 'third_party_directory',v_provider,p.country_id,nullif(v_row->>'institution_url',''),
       coalesce(p.display_name,p.canonical_name)||' — Hotcourses Abroad reconciliation',30,'active',
       jsonb_build_object(
         'directory','hotcourses_abroad','directory_id',nullif(v_dir_id,''),
         'purpose','provider_logo_discovery_and_reconciliation_only',
         'canonical_asset_authority',false,'operator_fallback_reuse_approved',true,
         'rights_owner_basis','university_provider_mark',
         'source_host_role','aggregator_transport_copy',
         'change_control_ref','CF-CHG-20260904-102'
       )
     from catalogue.providers p where p.id=v_provider
     on conflict do nothing;

     -- Feed the existing Provider Asset workflow only for ranked AU/NZ university Providers
     -- that do not already have an approved primary logo. Never replace an approved primary.
     if nullif(v_row->>'logo_url','') is not null
        and exists(
          select 1 from (
            select provider_id from ranking.observations where provider_id=v_provider
            union all
            select provider_id from ranking.observation_provider_links where provider_id=v_provider
          ) z
        )
        and not exists(
          select 1 from catalogue.provider_assets a
          where a.provider_id=v_provider and a.is_primary and a.status='approved'
            and a.asset_type in('logo','logo_light','logo_dark')
        )
     then
       insert into pipeline.provider_asset_candidates(
         provider_id,profile_id,source_url,asset_url,asset_type,evidence_id,
         confidence,status,metadata
       )
       select v_provider,
         (select sp.id from pipeline.layer2_source_profiles sp
          join pipeline.sources s on s.id=sp.source_id
          where s.provider_id=v_provider and sp.domain='provider_asset'
          order by sp.updated_at desc limit 1),
         nullif(v_row->>'institution_url',''),v_row->>'logo_url','logo',p_evidence_id,
         0.85,'needs_review',
         jsonb_build_object(
           'mapping_method','hotcourses_country_directory_exact_provider_match',
           'directory_id',nullif(v_dir_id,''),
           'rights_owner_basis','university_provider_mark',
           'source_host_role','aggregator_transport_copy',
           'operator_fallback_reuse_approved',true,
           'candidate_policy','review_before_promotion',
           'change_control_ref','CF-CHG-20260904-102',
           'canonical_mutation_authorised',false
         )
       on conflict(provider_id,asset_url) do update set
         source_url=excluded.source_url,evidence_id=excluded.evidence_id,
         confidence=excluded.confidence,status=case
           when pipeline.provider_asset_candidates.status='accepted' then 'accepted'
           else 'needs_review' end,
         metadata=coalesce(pipeline.provider_asset_candidates.metadata,'{}'::jsonb)||excluded.metadata,
         discovered_at=now();
       v_candidates:=v_candidates+1;
     end if;
   end if;
 end loop;

 return jsonb_build_object(
   'evidence_id',p_evidence_id,'country_code',v_country,
   'rows',v_inserted,'matched',v_matched,'unmatched',v_inserted-v_matched,
   'provider_asset_review_candidates',v_candidates
 );
end $$;

revoke all on function public.layer2_hotcourses_directory_apply(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_hotcourses_directory_apply(uuid,jsonb) to service_role;

commit;
