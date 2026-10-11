CREATE OR REPLACE FUNCTION security.scholarship_admit_from_provider_page_v1(p_candidate_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'catalogue', 'pim', 'security'
AS $function$
declare c record; d record; f jsonb; v_name text; v_url text; v_norm text; v_key text; v_id uuid; v_src uuid; v_ev uuid; v_dup uuid; v_dup_sa boolean; v_apply jsonb; r jsonb;
begin
  select * into c from pipeline.scholarship_page_candidates where id=p_candidate_id for update;
  if c.id is null then return jsonb_build_object('admitted',false,'reason','no candidate'); end if;
  if c.admitted_scholarship_id is not null or c.matched_scholarship_id is not null then return jsonb_build_object('admitted',false,'reason','already handled'); end if;
  select * into d from pipeline.scholarship_discovery_providers where provider_id=c.provider_id;
  f:=c.facts; v_name:=btrim(f->'admission'->>'name'); v_url:=coalesce(c.final_url,c.url); v_norm:=security.scholarship_url_norm(v_url);
  -- the rules, checked again here from the recorded page facts
  if c.read_status is distinct from 'read' or c.storage_path is null then r:=jsonb_build_object('admitted',false,'reason','page not read');
  elsif not security.scholarship_university(c.provider_id) then r:=jsonb_build_object('admitted',false,'reason','not a university provider in a scholarship country');
  elsif not security.url_on_provider_sites(v_url, c.provider_id) or security.reference_url_has_use(v_url, 'scholarship_placeholder') then r:=jsonb_build_object('admitted',false,'reason','not on the provider site');
  elsif coalesce(v_name,'')='' or length(v_name)<8 or v_name !~* '(scholarship|bursary|award|grant|fee (remission|reduction|waiver|discount)|tuition (discount|reduction|waiver))' then r:=jsonb_build_object('admitted',false,'reason','no named scholarship title');
  elsif coalesce((f->'admission'->>'detail_page')::boolean,false) is not true then r:=jsonb_build_object('admitted',false,'reason','not a single scholarship page');
  elsif coalesce((f->'admission'->>'international_explicit')::boolean,false) is not true or coalesce((f->>'international')::boolean,false) is not true then r:=jsonb_build_object('admitted',false,'reason','not explicitly open to international students');
  elsif coalesce((f->'admission'->>'offered')::boolean,false) is not true then r:=jsonb_build_object('admitted',false,'reason','not currently offered');
  elsif coalesce((f->'admission'->>'admit')::boolean,false) is not true then r:=jsonb_build_object('admitted',false,'reason','page rules not met');
  end if;
  if r is not null then
    update pipeline.scholarship_page_candidates set admit_status='rejected', admit_reasons=array[r->>'reason'] where id=c.id;
    insert into pipeline.scholarship_admission_log(candidate_id,provider_id,action,detail) values (c.id,c.provider_id,'rejected',r);
    return r;
  end if;
  -- already held: same page, or same name at this provider
  select s.id, security.reference_url_has_use(s.source_url, 'scholarship_placeholder') into v_dup, v_dup_sa from scholarship.scholarships s
   where s.provider_id=c.provider_id and s.lifecycle_status='active'
     and (security.scholarship_url_norm(s.source_url)=v_norm or scholarship.normalise_title(s.name)=scholarship.normalise_title(v_name)
          or exists (select 1 from scholarship.identifiers i where i.scholarship_id=s.id and i.scheme='first_party_detail_url' and security.scholarship_url_norm(i.identifier_value) in (v_norm, c.url_norm))
          or exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id=s.id and security.scholarship_url_norm(sp.url) in (v_norm, c.url_norm)))
   order by (security.reference_url_has_use(s.source_url, 'scholarship_placeholder')) limit 1;
  if v_dup is not null then
    if v_dup_sa and not exists (select 1 from pipeline.scholarship_pages where scholarship_id=v_dup) then
      -- a held Study Australia-only scholarship named by this page's heading: step 1 match, read and confirmed by the reader
      r:=security.scholarship_page_match_v1(v_dup, c.url, 'page_heading', c.id);
      update pipeline.scholarship_page_candidates set admit_status='matched_held' where id=c.id;
      insert into pipeline.scholarship_admission_log(candidate_id,scholarship_id,provider_id,action,detail) values (c.id,v_dup,c.provider_id,'matched_held',r);
      return jsonb_build_object('admitted',false,'reason','held scholarship matched','scholarship_id',v_dup,'match',r);
    end if;
    update pipeline.scholarship_page_candidates set admit_status='duplicate', admit_reasons=array['already held'] where id=c.id;
    insert into pipeline.scholarship_admission_log(candidate_id,scholarship_id,provider_id,action,detail) values (c.id,v_dup,c.provider_id,'duplicate',jsonb_build_object('name',v_name));
    return jsonb_build_object('admitted',false,'reason','already held','scholarship_id',v_dup);
  end if;

  v_key:='scholarship:'||coalesce((select k.iso_alpha2 from catalogue.providers pp join ref.countries k on k.id=pp.country_id where pp.id=c.provider_id),'AU')||':first-party:'||replace(c.provider_id::text,'-','')||':'||md5(v_norm);
  v_id:=scholarship.deterministic_uuid(v_key);
  if exists (select 1 from scholarship.scholarships where id=v_id) then
    update pipeline.scholarship_page_candidates set admit_status='duplicate', admit_reasons=array['same stable key'] where id=c.id;
    return jsonb_build_object('admitted',false,'reason','same stable key','scholarship_id',v_id);
  end if;
  v_src:=security.coverage_sweep_source(c.provider_id);
  insert into pim.entity_registry(id,entity_type,stable_key,lifecycle_status) values (v_id,'scholarship',v_key,'active') on conflict (stable_key) do update set lifecycle_status='active', updated_at=now();
  insert into pipeline.evidence_artifacts(entity_id,source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key)
  values (v_id, v_src, 'scholarship_page', v_url, c.storage_path, c.content_hash, 'application/gzip',
          jsonb_build_object('worker','coverage-sweep scholarship_discover','decision','CF-247 scholarship discovery (Decision 139 sweep)','candidate_id',c.id,'extractor',f->>'extractor'), 1, 'scholarship:'||v_id)
  returning id into v_ev;
  insert into scholarship.scholarships(id,stable_key,provider_id,name,scholarship_type,audience,source_url,lifecycle_status,publication_status,source_id,evidence_id,confidence,award_value_type,updated_at)
  values (v_id,v_key,c.provider_id,left(v_name,300),'provider_scholarship','international',v_url,'active','unpublished',v_src,v_ev,0.9,'text_only',now());
  insert into scholarship.identifiers(scholarship_id,scheme,identifier_value,source_id,evidence_id,is_primary,status)
  values (v_id,'first_party_detail_url',v_url,v_src,v_ev,true,'active') on conflict do nothing;
  insert into pipeline.scholarship_acquisition_trace(provider_id,observed_title,first_party_detail_url,scholarship_id,verification_evidence_id,stage,verification_status,observed_at,verified_at,updated_at,metadata)
  values (c.provider_id,left(v_name,300),v_url,v_id,v_ev,'canonical_unpublished','verified_first_party',c.found_at,now(),now(),
          jsonb_build_object('admission','security.scholarship_admit_from_provider_page_v1','candidate_id',c.id,'candidate_source',c.source,'rule','single named scholarship detail page on the provider site, explicitly open to international students, currently offered'));
  insert into pipeline.scholarship_pages(scholarship_id,url,url_source,candidate_id,final_url,read_status,http_status,fetched_via,read_at,next_read_at,attempts,evidence_id,facts,name_check)
  values (v_id,v_url,'admitted',c.id,c.final_url,'read',c.http_status,c.fetched_via,c.read_at,now()+interval '90 days',0,v_ev,f,jsonb_build_object('ok',true,'basis','admitted_from_page_title','heading',v_name));
  update pipeline.scholarship_page_candidates set admit_status='admitted', admitted_scholarship_id=v_id, admitted_at=now() where id=c.id;
  insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id) values (v_id,'admitted',null,jsonb_build_object('name',v_name,'url',v_url,'candidate_id',c.id),v_ev);
  v_apply:=security.scholarship_sweep_apply_v1(v_id);
  insert into pipeline.scholarship_admission_log(candidate_id,scholarship_id,provider_id,action,detail) values (c.id,v_id,c.provider_id,'admitted',jsonb_build_object('name',v_name,'url',v_url,'apply',v_apply));
  return jsonb_build_object('admitted',true,'scholarship_id',v_id,'apply',v_apply);
end $function$
