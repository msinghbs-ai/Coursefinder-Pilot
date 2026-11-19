create or replace function public.layer2_record_course_trial_result(
 p_course_id uuid,p_attempt_id uuid,p_fields_targeted integer,p_fields_resolved integer,p_correctness_status text,p_layer3_required boolean,p_blocker text,p_metrics jsonb)
returns uuid language plpgsql security definer set search_path=pg_catalog,public,pipeline as $$
declare tc record;a pipeline.layer2_provider_attempts%rowtype;ap pipeline.layer2_acquisition_providers%rowtype;v_id uuid;v_units numeric;v_latency integer;v_cost numeric;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select c.id as trial_course_id,c.trial_id into tc from pipeline.layer2_completeness_trial_courses c join pipeline.layer2_completeness_trials t on t.id=c.trial_id where c.course_id=p_course_id and t.status='running' order by t.started_at desc limit 1;
 if not found then return null; end if;
 select * into a from pipeline.layer2_provider_attempts where id=p_attempt_id; if not found then return null; end if;
 select * into ap from pipeline.layer2_acquisition_providers where id=a.acquisition_provider_id;
 v_latency:=nullif(a.metrics->>'latency_ms','')::integer;
 v_units:=case when nullif(a.metrics#>>'{provider_telemetry,scrape.do-request-cost}','') is not null then (a.metrics#>>'{provider_telemetry,scrape.do-request-cost}')::numeric when nullif(ap.request_template->>'fixed_credit_units','') is not null then (ap.request_template->>'fixed_credit_units')::numeric when ap.adapter_type='direct_http' then 0 else null end;
 v_cost:=case when coalesce(ap.billing_config->>'plan_tier','')='free' then 0 when nullif(ap.billing_config->>'unit_cost_usd','') is not null and v_units is not null then (ap.billing_config->>'unit_cost_usd')::numeric*v_units else null end;
 insert into pipeline.layer2_provider_trial_results(trial_id,trial_course_id,acquisition_provider_id,provider_attempt_id,domain_key,acquisition_success,gatekeeping_bypassed,javascript_rendered,evidence_quality_score,deterministic_extraction_success,correctness_status,latency_ms,request_count,vendor_cost_usd,fields_targeted,fields_resolved,layer3_required,layer4_required,blocker,metrics,vendor_units)
 values(tc.trial_id,tc.trial_course_id,a.acquisition_provider_id,a.id,'course_facts',a.status='succeeded',false,coalesce((ap.capabilities->>'javascript')::boolean,false),case when a.status='succeeded' then 1 else 0 end,p_fields_resolved>0,p_correctness_status,v_latency,1,v_cost,p_fields_targeted,p_fields_resolved,p_layer3_required,false,p_blocker,coalesce(p_metrics,'{}'::jsonb)||jsonb_build_object('pricing_mode',coalesce(ap.billing_config->>'plan_tier','unknown')),v_units)
 returning id into v_id;
 return v_id;
end $$;
revoke all on function public.layer2_record_course_trial_result(uuid,uuid,integer,integer,text,boolean,text,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_record_course_trial_result(uuid,uuid,integer,integer,text,boolean,text,jsonb) to service_role;
notify pgrst,'reload schema';
