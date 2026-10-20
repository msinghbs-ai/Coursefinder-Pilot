CREATE OR REPLACE FUNCTION pipeline.layer2_provider_trial_summary(p_trial_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pipeline'
AS $function$
select coalesce(jsonb_agg(x order by (x->>'cost_per_resolved_field_usd')::numeric nulls last,(x->>'resolution_rate')::numeric desc),'[]'::jsonb)
from (
 select jsonb_build_object(
   'provider_id',r.acquisition_provider_id,'provider_key',max(ap.provider_key),'attempted_rows',count(*),
   'acquisition_success_rate',round((count(*) filter(where r.acquisition_success is true))::numeric/nullif(count(*),0),4),
   'deterministic_success_rate',round((count(*) filter(where r.deterministic_extraction_success is true))::numeric/nullif(count(*),0),4),
   'correct_rate',round((count(*) filter(where r.correctness_status='correct'))::numeric/nullif(count(*) filter(where r.correctness_status in ('correct','incorrect')),0),4),
   'fields_targeted',sum(r.fields_targeted),'fields_resolved',sum(r.fields_resolved),
   'resolution_rate',round(sum(r.fields_resolved)::numeric/nullif(sum(r.fields_targeted),0),4),
   'vendor_units',sum(coalesce(r.vendor_units,0)),'vendor_cost_usd',case when count(*) filter(where r.vendor_cost_usd is null)>0 then null else sum(r.vendor_cost_usd) end,
   'cost_per_resolved_field_usd',case when count(*) filter(where r.vendor_cost_usd is null)>0 then null else round(sum(r.vendor_cost_usd)/nullif(sum(r.fields_resolved),0),6) end,
   'avg_latency_ms',round(avg(r.latency_ms) filter(where r.latency_ms is not null),1),
   'layer3_escalation_rate',round((count(*) filter(where r.layer3_required))::numeric/nullif(count(*),0),4),
   'layer4_escalation_rate',round((count(*) filter(where r.layer4_required))::numeric/nullif(count(*),0),4),
   'avg_evidence_quality',round(avg(r.evidence_quality_score),4)
 ) x
 from pipeline.layer2_provider_trial_results r join pipeline.layer2_acquisition_providers ap on ap.id=r.acquisition_provider_id
 where r.trial_id=p_trial_id group by r.acquisition_provider_id
) s$function$
