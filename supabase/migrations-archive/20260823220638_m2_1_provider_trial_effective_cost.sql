update pipeline.layer2_acquisition_providers
set billing_config=jsonb_build_object('currency','USD','unit','request','unit_cost_usd',0,'source','internal_no_vendor_fee')
where provider_key='direct-http' and billing_config='{}'::jsonb;

create or replace function public.layer2_provider_trial_record(
 p_trial_course_id uuid,p_acquisition_provider_id uuid,p_domain_key text,p_provider_attempt_id uuid default null,
 p_acquisition_success boolean default null,p_gatekeeping_bypassed boolean default null,p_javascript_rendered boolean default null,
 p_evidence_quality_score numeric default null,p_deterministic_extraction_success boolean default null,p_correctness_status text default 'unverified',
 p_latency_ms integer default null,p_request_count integer default 1,p_vendor_cost_usd numeric default null,p_fields_targeted integer default 0,
 p_fields_resolved integer default 0,p_layer3_required boolean default false,p_layer4_required boolean default false,p_blocker text default null,p_metrics jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer
set search_path='public','pipeline','security'
as $$declare v_trial uuid;v_id uuid;v_cost numeric;v_requests integer:=greatest(coalesce(p_request_count,1),0);begin
 if auth.role()<>'service_role' then raise exception 'service_role required';end if;
 select trial_id into v_trial from pipeline.layer2_completeness_trial_courses where id=p_trial_course_id;
 if v_trial is null then raise exception 'trial course not found';end if;
 v_cost:=p_vendor_cost_usd;
 if v_cost is null then select security.layer2_provider_effective_cost_usd(p.billing_config,v_requests) into v_cost from pipeline.layer2_acquisition_providers p where p.id=p_acquisition_provider_id;end if;
 insert into pipeline.layer2_provider_trial_results(trial_id,trial_course_id,acquisition_provider_id,provider_attempt_id,domain_key,acquisition_success,gatekeeping_bypassed,javascript_rendered,evidence_quality_score,deterministic_extraction_success,correctness_status,latency_ms,request_count,vendor_cost_usd,fields_targeted,fields_resolved,layer3_required,layer4_required,blocker,metrics)
 values(v_trial,p_trial_course_id,p_acquisition_provider_id,p_provider_attempt_id,p_domain_key,p_acquisition_success,p_gatekeeping_bypassed,p_javascript_rendered,p_evidence_quality_score,p_deterministic_extraction_success,p_correctness_status,p_latency_ms,v_requests,v_cost,coalesce(p_fields_targeted,0),coalesce(p_fields_resolved,0),coalesce(p_layer3_required,false),coalesce(p_layer4_required,false),p_blocker,coalesce(p_metrics,'{}'::jsonb)||jsonb_build_object('estimated_vendor_cost',p_vendor_cost_usd is null,'effective_cost_usd',v_cost)) returning id into v_id;
 return v_id;
end$$;
revoke all on function public.layer2_provider_trial_record(uuid,uuid,text,uuid,boolean,boolean,boolean,numeric,boolean,text,integer,integer,numeric,integer,integer,boolean,boolean,text,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_provider_trial_record(uuid,uuid,text,uuid,boolean,boolean,boolean,numeric,boolean,text,integer,integer,numeric,integer,integer,boolean,boolean,text,jsonb) to service_role;
