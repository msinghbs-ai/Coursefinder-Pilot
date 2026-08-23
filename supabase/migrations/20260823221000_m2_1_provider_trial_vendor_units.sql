alter table pipeline.layer2_provider_trial_results add column if not exists vendor_units numeric;

update pipeline.layer2_acquisition_providers
set request_template=request_template||jsonb_build_object('credit_cost_header','Scrape.do-Request-Cost','remaining_credits_header','Scrape.do-Remaining-Credits')
where provider_key='scrape-do';

update pipeline.layer2_acquisition_providers
set request_template=request_template||jsonb_build_object('fixed_credit_units',1)
where provider_key='firecrawl';

create or replace function public.layer2_provider_trial_record(
 p_trial_course_id uuid,p_acquisition_provider_id uuid,p_domain_key text,p_provider_attempt_id uuid default null,
 p_acquisition_success boolean default null,p_gatekeeping_bypassed boolean default null,p_javascript_rendered boolean default null,
 p_evidence_quality_score numeric default null,p_deterministic_extraction_success boolean default null,p_correctness_status text default 'unverified',
 p_latency_ms integer default null,p_request_count integer default 1,p_vendor_cost_usd numeric default null,p_fields_targeted integer default 0,
 p_fields_resolved integer default 0,p_layer3_required boolean default false,p_layer4_required boolean default false,p_blocker text default null,p_metrics jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer
set search_path='public','pipeline','security'
as $$declare v_trial uuid;v_id uuid;v_cost numeric;v_requests integer:=greatest(coalesce(p_request_count,1),0);v_units numeric;begin
 if auth.role()<>'service_role' then raise exception 'service_role required';end if;
 select trial_id into v_trial from pipeline.layer2_completeness_trial_courses where id=p_trial_course_id;
 if v_trial is null then raise exception 'trial course not found';end if;
 begin v_units:=nullif(p_metrics->>'vendor_units','')::numeric;exception when invalid_text_representation then v_units:=null;end;
 if v_units is null then v_units:=v_requests;end if;
 v_cost:=p_vendor_cost_usd;
 if v_cost is null then select security.layer2_provider_effective_cost_usd(p.billing_config,v_units) into v_cost from pipeline.layer2_acquisition_providers p where p.id=p_acquisition_provider_id;end if;
 insert into pipeline.layer2_provider_trial_results(trial_id,trial_course_id,acquisition_provider_id,provider_attempt_id,domain_key,acquisition_success,gatekeeping_bypassed,javascript_rendered,evidence_quality_score,deterministic_extraction_success,correctness_status,latency_ms,request_count,vendor_units,vendor_cost_usd,fields_targeted,fields_resolved,layer3_required,layer4_required,blocker,metrics)
 values(v_trial,p_trial_course_id,p_acquisition_provider_id,p_provider_attempt_id,p_domain_key,p_acquisition_success,p_gatekeeping_bypassed,p_javascript_rendered,p_evidence_quality_score,p_deterministic_extraction_success,p_correctness_status,p_latency_ms,v_requests,v_units,v_cost,coalesce(p_fields_targeted,0),coalesce(p_fields_resolved,0),coalesce(p_layer3_required,false),coalesce(p_layer4_required,false),p_blocker,coalesce(p_metrics,'{}'::jsonb)||jsonb_build_object('estimated_vendor_cost',p_vendor_cost_usd is null,'effective_cost_usd',v_cost,'vendor_units',v_units)) returning id into v_id;
 return v_id;
end$$;

create or replace function pipeline.layer2_provider_trial_summary(p_trial_id uuid)
returns jsonb language sql stable security definer set search_path='pipeline' as $$
select coalesce(jsonb_agg(x order by (x->>'cost_per_resolved_field_usd')::numeric nulls last,(x->>'resolution_rate')::numeric desc),'[]'::jsonb)
from (
 select jsonb_build_object(
   'provider_id',r.acquisition_provider_id,'provider_key',max(ap.provider_key),'attempted_rows',count(*),
   'acquisition_success_rate',round((count(*) filter(where r.acquisition_success is true))::numeric/nullif(count(*),0),4),
   'deterministic_success_rate',round((count(*) filter(where r.deterministic_extraction_success is true))::numeric/nullif(count(*),0),4),
   'correct_rate',round((count(*) filter(where r.correctness_status='correct'))::numeric/nullif(count(*) filter(where r.correctness_status in ('correct','incorrect')),0),4),
   'fields_targeted',sum(r.fields_targeted),'fields_resolved',sum(r.fields_resolved),
   'resolution_rate',round(sum(r.fields_resolved)::numeric/nullif(sum(r.fields_targeted),0),4),
   'vendor_units',sum(coalesce(r.vendor_units,0)),
   'vendor_cost_usd',case when count(*) filter(where r.vendor_cost_usd is null)>0 then null else sum(r.vendor_cost_usd) end,
   'cost_per_resolved_field_usd',case when count(*) filter(where r.vendor_cost_usd is null)>0 then null else round(sum(r.vendor_cost_usd)/nullif(sum(r.fields_resolved),0),6) end,
   'avg_latency_ms',round(avg(r.latency_ms) filter(where r.latency_ms is not null),1),
   'layer3_escalation_rate',round((count(*) filter(where r.layer3_required))::numeric/nullif(count(*),0),4),
   'layer4_escalation_rate',round((count(*) filter(where r.layer4_required))::numeric/nullif(count(*),0),4),
   'avg_evidence_quality',round(avg(r.evidence_quality_score),4)
 ) x
 from pipeline.layer2_provider_trial_results r join pipeline.layer2_acquisition_providers ap on ap.id=r.acquisition_provider_id
 where r.trial_id=p_trial_id group by r.acquisition_provider_id
) s$$;
