create or replace view pipeline.scholarship_provider_stats as
with canonical as (
  select provider_id,count(*)::int canonical_total,
    count(*) filter(where publication_status='published')::int published_total,
    count(*) filter(where publication_status<>'published')::int unpublished_total
  from scholarship.scholarships group by provider_id
), trace as (
  select provider_id,count(*)::int trace_total,
    count(*) filter(where verification_status='verified_first_party')::int first_party_verified_total,
    count(*) filter(where review_queue_id is not null)::int layer4_linked_total,
    count(*) filter(where scholarship_id is not null)::int canonical_linked_total,
    count(*) filter(where publication_decision_id is not null)::int publication_decision_linked_total,
    count(*) filter(where verification_evidence_id is not null and source_record_id is not null)::int evidence_acquired_total,
    max(updated_at) trace_last_updated_at
  from pipeline.scholarship_acquisition_trace group by provider_id
), candidates as (
  select s.provider_id,
    count(*)::int candidate_total,
    count(*) filter(where c.status='discovered' and c.classification='detail_ready')::int detail_ready_total,
    count(*) filter(where c.status='discovered' and c.classification='needs_review')::int candidate_needs_review_total,
    count(*) filter(where c.status='rejected')::int candidate_rejected_total,
    count(*) filter(where c.status='acquired')::int candidate_acquired_total,
    max(c.classified_at) candidate_last_classified_at
  from pipeline.layer2_scholarship_discovery_candidates c join pipeline.sources s on s.id=c.source_id
  where s.provider_id is not null group by s.provider_id
), latest_benchmark as (
  select distinct on (provider_id) provider_id,observed_count landscape_benchmark_total,observed_at benchmark_observed_at
  from pipeline.scholarship_coverage_benchmarks
  where benchmark_scope='provider' and provider_id is not null
  order by provider_id,observed_at desc
)
select p.id provider_id,p.canonical_name provider_name,
  coalesce(c.canonical_total,0) canonical_total,coalesce(c.published_total,0) published_total,coalesce(c.unpublished_total,0) unpublished_total,
  coalesce(t.trace_total,0) trace_total,coalesce(t.first_party_verified_total,0) first_party_verified_total,
  coalesce(t.layer4_linked_total,0) layer4_linked_total,coalesce(t.canonical_linked_total,0) canonical_linked_total,
  coalesce(t.publication_decision_linked_total,0) publication_decision_linked_total,
  lb.landscape_benchmark_total,
  case when lb.landscape_benchmark_total is null then null else greatest(lb.landscape_benchmark_total-coalesce(c.canonical_total,0),0) end indicative_gap_to_landscape,
  case when lb.landscape_benchmark_total is null or lb.landscape_benchmark_total=0 then null else round(coalesce(c.canonical_total,0)::numeric/lb.landscape_benchmark_total::numeric*100,1) end canonical_to_landscape_pct,
  lb.benchmark_observed_at,t.trace_last_updated_at,coalesce(t.evidence_acquired_total,0) evidence_acquired_total,
  coalesce(k.candidate_total,0) candidate_total,coalesce(k.detail_ready_total,0) detail_ready_total,
  coalesce(k.candidate_needs_review_total,0) candidate_needs_review_total,coalesce(k.candidate_rejected_total,0) candidate_rejected_total,
  coalesce(k.candidate_acquired_total,0) candidate_acquired_total,k.candidate_last_classified_at
from catalogue.providers p
left join canonical c on c.provider_id=p.id
left join trace t on t.provider_id=p.id
left join candidates k on k.provider_id=p.id
left join latest_benchmark lb on lb.provider_id=p.id
where coalesce(c.canonical_total,0)>0 or coalesce(t.trace_total,0)>0 or coalesce(k.candidate_total,0)>0 or lb.provider_id is not null;

revoke all on pipeline.scholarship_provider_stats from public,anon,authenticated;
grant select on pipeline.scholarship_provider_stats to service_role;

create or replace function public.scholarship_operations_read()
returns jsonb language plpgsql stable set search_path to 'pg_catalog','public','security','pipeline','scholarship','auth' as $function$
declare v_rank integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  return jsonb_build_object(
    'schedules',(select coalesce(jsonb_agg(jsonb_build_object('feed',feed,'enabled',enabled,'cadence_hours',cadence_hours,'mode',mode,'max_records',max_records,'page_start',page_start,'page_end',page_end,'next_due_at',next_due_at,'last_dispatched_at',last_dispatched_at,'last_request_id',last_request_id,'last_error',last_error) order by feed),'[]'::jsonb) from pipeline.scholarship_etl_schedules),
    'qualifications',(select coalesce(jsonb_agg(jsonb_build_object('source_key',source_key,'authority_name',authority_name,'qualification_status',qualification_status,'source_url',source_url,'updated_at',updated_at) order by source_key),'[]'::jsonb) from pipeline.scholarship_source_qualifications),
    'source_records',(select jsonb_build_object('total',count(*),'applied',count(*) filter(where status='applied' and applied_at is not null),'unapplied',count(*) filter(where status<>'applied' or applied_at is null),'stale_45d',count(*) filter(where observed_at<now()-interval '45 days'),'latest_observed_at',max(observed_at)) from pipeline.scholarship_source_records),
    'discovery_candidates',(select jsonb_build_object('discovered',count(*) filter(where status='discovered'),'detail_ready',count(*) filter(where status='discovered' and classification='detail_ready'),'needs_review',count(*) filter(where status='discovered' and classification='needs_review'),'rejected',count(*) filter(where status='rejected'),'acquired',count(*) filter(where status='acquired'),'total',count(*)) from pipeline.layer2_scholarship_discovery_candidates),
    'course_mapping',(select jsonb_build_object('mapped',count(*) filter(where mapping_state='mapped'),'needs_review',(select count(*) from scholarship.course_mapping_candidates where status='needs_review')) from scholarship.course_mappings),
    'provider_stats',(select coalesce(jsonb_agg(to_jsonb(s) order by s.canonical_total desc,s.provider_name),'[]'::jsonb) from pipeline.scholarship_provider_stats s),
    'provider_stats_summary',(select jsonb_build_object('providers',count(*),'canonical_total',coalesce(sum(canonical_total),0),'published_total',coalesce(sum(published_total),0),'unpublished_total',coalesce(sum(unpublished_total),0),'first_party_verified_total',coalesce(sum(first_party_verified_total),0),'evidence_acquired_total',coalesce(sum(evidence_acquired_total),0),'candidate_total',coalesce(sum(candidate_total),0),'detail_ready_total',coalesce(sum(detail_ready_total),0),'candidate_needs_review_total',coalesce(sum(candidate_needs_review_total),0),'candidate_rejected_total',coalesce(sum(candidate_rejected_total),0),'candidate_acquired_total',coalesce(sum(candidate_acquired_total),0),'layer4_linked_total',coalesce(sum(layer4_linked_total),0),'canonical_linked_total',coalesce(sum(canonical_linked_total),0),'publication_decision_linked_total',coalesce(sum(publication_decision_linked_total),0),'benchmarked_providers',count(*) filter(where landscape_benchmark_total is not null),'last_trace_update',max(trace_last_updated_at),'last_candidate_classification',max(candidate_last_classified_at)) from pipeline.scholarship_provider_stats),
    'latest_maintenance',(select to_jsonb(x) from (select id,started_at,completed_at,status,deterministic_mappings,mapping_candidates,source_records,unapplied_source_records,discovery_candidates,stale_source_records,evidence_deleted,source_records_deleted from pipeline.scholarship_maintenance_runs order by started_at desc limit 1) x)
  );
end
$function$;
revoke all on function public.scholarship_operations_read() from public,anon;
grant execute on function public.scholarship_operations_read() to authenticated,service_role;
