CREATE OR REPLACE FUNCTION public.svc_coverage_discovery_record(p_provider_id uuid, p_status text, p_method text, p_url_count integer, p_urls jsonb, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v_n int:=0;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.coverage_provider_urls(provider_id,url,title,tokens,title_tokens,source)
  select p_provider_id, left(e->>'url',1000), left(e->>'title',300), security.coverage_text_tokens(security.coverage_slug(e->>'url')),
         security.coverage_text_tokens(regexp_replace(coalesce(e->>'title',''),'\s[|–—]\s.*$','')), coalesce(p_method,'map')
    from jsonb_array_elements(coalesce(p_urls,'[]'::jsonb)) e where coalesce(e->>'url','')~'^https?://'
  on conflict (provider_id,url) do update set title=coalesce(excluded.title,pipeline.coverage_provider_urls.title), tokens=excluded.tokens, title_tokens=excluded.title_tokens, last_seen_at=now();
  get diagnostics v_n=row_count;
  update pipeline.coverage_provider_discovery set status=p_status, method=p_method, url_count=p_url_count, kept_count=v_n, last_error=left(p_error,500),
         leased_until=null, mapped_at=case when p_status='mapped' then now() else mapped_at end,
         next_due_at=case when p_status='mapped' then now()+make_interval(days => security.pipeline_num_v1('remap.site_days', 30)::int) when p_status='failed' then now()+make_interval(hours => security.pipeline_num_v1('retry.site_map_failed_hours', 6)::int) else null end, updated_at=now()
   where provider_id=p_provider_id;
  return jsonb_build_object('kept',v_n);
end $function$
