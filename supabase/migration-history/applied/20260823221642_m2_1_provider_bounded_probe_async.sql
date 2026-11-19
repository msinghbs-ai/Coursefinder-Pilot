create table if not exists pipeline.layer2_provider_probe_requests(
 request_id bigint primary key,profile_key text not null,provider_key text not null,target_url text not null,started_at timestamptz not null default now(),change_control_ref text not null default 'CF-CHG-20260823-029'
);
alter table pipeline.layer2_provider_probe_requests enable row level security;
revoke all on pipeline.layer2_provider_probe_requests from public,anon,authenticated;
grant select,insert,update,delete on pipeline.layer2_provider_probe_requests to service_role;

drop function if exists pipeline.svc_layer2_provider_bounded_probe(text,text,text);

create or replace function pipeline.svc_layer2_provider_probe_start(p_profile_key text,p_provider_key text,p_target_url text)
returns jsonb language plpgsql security definer set search_path='pg_catalog','pipeline','vault','net','public' as $$
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
end$$;

create or replace function pipeline.svc_layer2_provider_probe_result(p_request_id bigint)
returns jsonb language plpgsql security definer set search_path='pg_catalog','pipeline','net','public','extensions' as $$
declare v_probe record;v_rec net._http_response;v_headers jsonb;v_body text;v_credit numeric;v_remaining numeric;v_fixed numeric;v_is_json boolean;begin
 select * into v_probe from pipeline.layer2_provider_probe_requests where request_id=p_request_id;if not found then raise exception 'probe request not found';end if;
 select * into v_rec from net._http_response where id=p_request_id;if not found then return jsonb_build_object('ok',false,'pending',true,'request_id',p_request_id,'provider_key',v_probe.provider_key,'profile_key',v_probe.profile_key);end if;
 if v_rec.error_msg is not null then return jsonb_build_object('ok',false,'pending',false,'request_id',p_request_id,'provider_key',v_probe.provider_key,'profile_key',v_probe.profile_key,'error_class','transport','message',v_rec.error_msg,'elapsed_ms',round(extract(epoch from(v_rec.created-v_probe.started_at))*1000)::int);end if;
 v_headers:=v_rec.headers;v_body:=v_rec.content;v_is_json:=coalesce(v_headers->>'content-type',v_headers->>'Content-Type','') ilike '%json%';
 begin v_credit:=coalesce(nullif(v_headers->>'Scrape.do-Request-Cost','')::numeric,nullif(v_headers->>'scrape.do-request-cost','')::numeric);exception when invalid_text_representation then v_credit:=null;end;
 begin v_remaining:=coalesce(nullif(v_headers->>'Scrape.do-Remaining-Credits','')::numeric,nullif(v_headers->>'scrape.do-remaining-credits','')::numeric);exception when invalid_text_representation then v_remaining:=null;end;
 select nullif(request_template->>'fixed_credit_units','')::numeric into v_fixed from pipeline.layer2_acquisition_providers where provider_key=v_probe.provider_key;v_credit:=coalesce(v_credit,v_fixed);
 return jsonb_build_object('ok',v_rec.status_code between 200 and 299,'pending',false,'request_id',p_request_id,'provider_key',v_probe.provider_key,'profile_key',v_probe.profile_key,'http_status',v_rec.status_code,'elapsed_ms',round(extract(epoch from(v_rec.created-v_probe.started_at))*1000)::int,'content_type',coalesce(v_headers->>'content-type',v_headers->>'Content-Type'),'response_bytes',octet_length(coalesce(v_body,'')),'vendor_units',v_credit,'remaining_vendor_units',v_remaining,'body_sha256',encode(digest(coalesce(v_body,''),'sha256'),'hex'),'json_success',case when v_is_json then coalesce((v_body::jsonb->>'success')::boolean,true) else null end,'has_markdown',case when v_is_json then coalesce(length(v_body::jsonb#>>'{data,markdown}')>0,false) else null end,'has_html',case when v_is_json then coalesce(length(v_body::jsonb#>>'{data,html}')>0,false) else v_rec.status_code between 200 and 299 end,'has_screenshot',case when v_is_json then coalesce(length(v_body::jsonb#>>'{data,screenshot}')>0,false) else null end);
exception when others then return jsonb_build_object('ok',false,'pending',false,'request_id',p_request_id,'provider_key',coalesce(v_probe.provider_key,'unknown'),'error_class','result_parse','message',sqlerrm);end$$;
revoke all on function pipeline.svc_layer2_provider_probe_start(text,text,text) from public,anon,authenticated;
revoke all on function pipeline.svc_layer2_provider_probe_result(bigint) from public,anon,authenticated;
grant execute on function pipeline.svc_layer2_provider_probe_start(text,text,text),pipeline.svc_layer2_provider_probe_result(bigint) to service_role;
