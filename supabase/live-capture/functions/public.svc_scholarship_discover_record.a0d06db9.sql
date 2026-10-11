CREATE OR REPLACE FUNCTION public.svc_scholarship_discover_record(p_provider_id uuid, p_status text, p_site_origin text, p_method text, p_url_count integer, p_candidates jsonb, p_matches jsonb, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v_kept int; v_matched int:=0; m jsonb; r jsonb; v_cid bigint;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.scholarship_page_candidates(provider_id,url,url_norm,title,source)
  select p_provider_id, c->>'url', security.scholarship_url_norm(c->>'url'), nullif(left(c->>'title',300),''), coalesce(c->>'source','sitemap')
    from jsonb_array_elements(coalesce(p_candidates,'[]')) c
   where coalesce(c->>'url','') ~* '^https?://' and (security.url_on_provider_sites(c->>'url', p_provider_id) or security.url_on_provider_site(c->>'url', p_site_origin))
  on conflict (provider_id,url_norm) do update set title=coalesce(pipeline.scholarship_page_candidates.title, excluded.title);
  select count(*) into v_kept from pipeline.scholarship_page_candidates where provider_id=p_provider_id;
  update pipeline.scholarship_discovery_providers set status=p_status, site_origin=coalesce(p_site_origin,site_origin), method=p_method, url_count=p_url_count,
         kept_count=v_kept, discovered_at=now(), leased_until=null, last_error=p_error, updated_at=now() where provider_id=p_provider_id;
  for m in select * from jsonb_array_elements(coalesce(p_matches,'[]')) loop
    select id into v_cid from pipeline.scholarship_page_candidates where provider_id=p_provider_id and url_norm=security.scholarship_url_norm(m->>'url');
    if v_cid is null then continue; end if;
    if (select provider_id from scholarship.scholarships where id=(m->>'scholarship_id')::uuid) is distinct from p_provider_id then continue; end if;
    r:=security.scholarship_page_match_v1((m->>'scholarship_id')::uuid, m->>'url', m->>'basis', v_cid);
    if (r->>'matched')::boolean then v_matched:=v_matched+1; end if;
  end loop;
  update pipeline.scholarship_discovery_providers set matched_count=coalesce(matched_count,0)+v_matched where provider_id=p_provider_id;
  return jsonb_build_object('kept',v_kept,'matched',v_matched);
end $function$
