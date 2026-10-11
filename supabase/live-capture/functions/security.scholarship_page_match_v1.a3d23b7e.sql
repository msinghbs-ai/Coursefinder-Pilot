CREATE OR REPLACE FUNCTION security.scholarship_page_match_v1(p_scholarship_id uuid, p_url text, p_basis text, p_candidate_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'
AS $function$
declare s record; v_site text; v_norm text:=security.scholarship_url_norm(p_url);
begin
  select * into s from scholarship.scholarships where id=p_scholarship_id for update;
  if s.id is null or s.lifecycle_status<>'active' then return jsonb_build_object('matched',false,'reason','not active'); end if;
  if not security.reference_url_has_use(coalesce(s.source_url,''), 'scholarship_placeholder') then return jsonb_build_object('matched',false,'reason','already has a provider source'); end if;
  -- a page already read for it stays, except a discovered page the reader rejected (it did not name the scholarship)
  if exists (select 1 from pipeline.scholarship_pages where scholarship_id=s.id and not (url_source='discovered' and read_status in ('name_mismatch','robots_disallowed','gone')))
    then return jsonb_build_object('matched',false,'reason','already has a page'); end if;
  select coalesce(site_origin, website) into v_site from pipeline.scholarship_discovery_providers where provider_id=s.provider_id;
  if v_site is null or not security.url_on_provider_sites(p_url, s.provider_id) or security.reference_url_has_use(p_url, 'scholarship_placeholder') then return jsonb_build_object('matched',false,'reason','not on the provider site'); end if;
  if exists (select 1 from pipeline.scholarship_pages sp where security.scholarship_url_norm(sp.url)=v_norm)
     or exists (select 1 from scholarship.scholarships x where x.id<>s.id and security.scholarship_url_norm(x.source_url)=v_norm)
     or exists (select 1 from scholarship.identifiers i where i.scheme='first_party_detail_url' and security.scholarship_url_norm(i.identifier_value)=v_norm)
    then return jsonb_build_object('matched',false,'reason','page already belongs to another scholarship'); end if;
  delete from pipeline.scholarship_pages where scholarship_id=s.id and url_source='discovered' and read_status in ('name_mismatch','robots_disallowed','gone');
  insert into pipeline.scholarship_pages(scholarship_id,url,url_source,candidate_id,next_read_at) values (s.id,p_url,'discovered',p_candidate_id,now());
  if p_candidate_id is not null then
    update pipeline.scholarship_page_candidates set matched_scholarship_id=s.id, match_basis=p_basis, matched_at=now() where id=p_candidate_id;
  end if;
  insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value)
  values (s.id,'provider_page_matched',jsonb_build_object('source_url',s.source_url),jsonb_build_object('url',p_url,'basis',p_basis,'candidate_id',p_candidate_id));
  return jsonb_build_object('matched',true);
end $function$
