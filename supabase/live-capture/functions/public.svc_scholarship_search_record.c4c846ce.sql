CREATE OR REPLACE FUNCTION public.svc_scholarship_search_record(p_scholarship_id uuid, p_query text, p_status text, p_results jsonb, p_match jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'scholarship', 'security'
AS $function$
declare v_pid uuid; v_site text; v_cid bigint; r jsonb:=jsonb_build_object('matched',false);
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select s.provider_id, coalesce(d.site_origin,d.website) into v_pid, v_site from scholarship.scholarships s join pipeline.scholarship_discovery_providers d on d.provider_id=s.provider_id where s.id=p_scholarship_id;
  update pipeline.scholarship_page_searches set query=p_query, status=p_status, results=p_results, matched_url=p_match->>'url', searched_at=now() where scholarship_id=p_scholarship_id;
  insert into pipeline.scholarship_page_candidates(provider_id,url,url_norm,title,source)
  select v_pid, x->>'url', security.scholarship_url_norm(x->>'url'), nullif(left(x->>'title',300),''), 'search'
    from jsonb_array_elements(coalesce(p_results,'[]')) x where x->>'kept'='true' and security.url_on_provider_sites(x->>'url', v_pid)
  on conflict (provider_id,url_norm) do update set title=coalesce(pipeline.scholarship_page_candidates.title, excluded.title);
  if p_match ? 'url' then
    select id into v_cid from pipeline.scholarship_page_candidates where provider_id=v_pid and url_norm=security.scholarship_url_norm(p_match->>'url');
    if v_cid is not null then r:=security.scholarship_page_match_v1(p_scholarship_id, p_match->>'url', p_match->>'basis', v_cid); end if;
  end if;
  return r;
end $function$
