CREATE OR REPLACE FUNCTION pipeline.svc_layer2_provider_probe_start(p_profile_key text, p_provider_key text, p_target_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'vault', 'net', 'public'
AS $function$
declare v_cfg jsonb;v_provider record;v_secret text;v_host text;v_allowed boolean:=false;v_req bigint;v_url text;v_params jsonb:='{}';v_body jsonb:='{}';v_headers jsonb:='{}';begin
 select v.configuration into v_cfg from pipeline.layer2_source_profiles p join pipeline.layer2_source_profile_versions v on v.id=p.current_version_id where p.profile_key=p_profile_key and p.enabled and not p.paused and v.validation_status='valid';
 if v_cfg is null then raise exception 'executable source profile not found';end if;
 v_host:=lower(split_part(split_part(p_target_url,'://',2),'/',1));if v_host='' then raise exception 'invalid target url';end if;
 select exists(select 1 from jsonb_array_elements_text(coalesce(v_cfg->'url_patterns','[]'::jsonb)) x where lower(split_part(split_part(x,'://',2),'/',1))=v_host or v_host like '%.'||lower(split_part(split_part(x,'://',2),'/',1))) or lower(split_part(split_part(coalesce(v_cfg->>'base_domain',''),'://',2),'/',1))=v_host into v_allowed;
 if not v_allowed then raise exception 'target url outside source profile boundary';end if;
 select p.* into v_provider from pipeline.layer2_acquisition_providers p join pipeline.layer2_profile_provider_routes r on r.acquisition_provider_id=p.id join pipeline.layer2_source_profiles sp on sp.id=r.profile_id where sp.profile_key=p_profile_key and p.provider_key=p_provider_key and p.enabled and r.enabled;
 if not found then raise exception 'provider is not an enabled route for profile';end if;
 if v_provider.auth_scheme<>'none' then select decrypted_secret into v_secret from vault.decrypted_secrets where id=v_provider.vault_secret_id;if v_secret is null then raise exception 'provider credential missing';end if;end if;
 if v_provider.adapter_type='direct_http' then v_req:=net.http_get(p_target_url,'{}',jsonb_build_object('User-Agent','CourseFinder Layer2 bounded probe/1.1'),least(v_provider.timeout_seconds*1000,120000));
 elsif v_provider.provider_key='firecrawl' then v_body:=coalesce(v_provider.request_template->'static_body','{}')||jsonb_build_object(coalesce(v_provider.request_template->>'target_url_field','url'),p_target_url);v_headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_secret);v_req:=net.http_post(v_provider.base_url,v_body,'{}',v_headers,least(v_provider.timeout_seconds*1000,120000));
 else v_url:=v_provider.base_url;v_params:=coalesce(v_provider.request_template->'static_query','{}')||jsonb_build_object(coalesce(v_provider.request_template->>'target_url_parameter','url'),p_target_url);if v_provider.auth_scheme='query_param' then v_params:=v_params||jsonb_build_object(coalesce(v_provider.auth_field_name,'token'),v_secret);elsif v_provider.auth_scheme='bearer' then v_headers:=jsonb_build_object('Authorization','Bearer '||v_secret);elsif v_provider.auth_scheme='header' then v_headers:=jsonb_build_object(coalesce(v_provider.auth_field_name,'X-API-Key'),v_secret);end if;v_req:=net.http_get(v_url,v_params,v_headers,least(v_provider.timeout_seconds*1000,120000));end if;
 insert into pipeline.layer2_provider_probe_requests(request_id,profile_key,provider_key,target_url) values(v_req,p_profile_key,p_provider_key,p_target_url);
 return jsonb_build_object('ok',true,'request_id',v_req,'profile_key',p_profile_key,'provider_key',p_provider_key,'queued_at',now());
end$function$
