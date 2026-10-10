create or replace view pipeline.scholarship_provider_stats as
with canonical as (
  select provider_id,count(*)::integer canonical_total,
         count(*) filter(where publication_status='published')::integer published_total,
         count(*) filter(where publication_status<>'published')::integer unpublished_total
  from scholarship.scholarships group by provider_id
), trace as (
  select provider_id,count(*)::integer trace_total,
         count(*) filter(where verification_status='verified_first_party')::integer first_party_verified_total,
         count(*) filter(where review_queue_id is not null)::integer layer4_linked_total,
         count(*) filter(where scholarship_id is not null)::integer canonical_linked_total,
         count(*) filter(where publication_decision_id is not null)::integer publication_decision_linked_total,
         max(updated_at) trace_last_updated_at,
         count(*) filter(where verification_evidence_id is not null and source_record_id is not null)::integer evidence_acquired_total
  from pipeline.scholarship_acquisition_trace group by provider_id
), latest_benchmark as (
  select distinct on(provider_id) provider_id,observed_count landscape_benchmark_total,observed_at benchmark_observed_at
  from pipeline.scholarship_coverage_benchmarks where benchmark_scope='provider' and provider_id is not null
  order by provider_id,observed_at desc
)
select p.id provider_id,p.canonical_name provider_name,coalesce(c.canonical_total,0) canonical_total,
       coalesce(c.published_total,0) published_total,coalesce(c.unpublished_total,0) unpublished_total,
       coalesce(t.trace_total,0) trace_total,coalesce(t.first_party_verified_total,0) first_party_verified_total,
       coalesce(t.layer4_linked_total,0) layer4_linked_total,coalesce(t.canonical_linked_total,0) canonical_linked_total,
       coalesce(t.publication_decision_linked_total,0) publication_decision_linked_total,lb.landscape_benchmark_total,
       case when lb.landscape_benchmark_total is null then null::integer else greatest(lb.landscape_benchmark_total-coalesce(c.canonical_total,0),0) end indicative_gap_to_landscape,
       case when lb.landscape_benchmark_total is null or lb.landscape_benchmark_total=0 then null::numeric else round(coalesce(c.canonical_total,0)::numeric/lb.landscape_benchmark_total::numeric*100,1) end canonical_to_landscape_pct,
       lb.benchmark_observed_at,t.trace_last_updated_at,coalesce(t.evidence_acquired_total,0) evidence_acquired_total
from catalogue.providers p left join canonical c on c.provider_id=p.id left join trace t on t.provider_id=p.id left join latest_benchmark lb on lb.provider_id=p.id
where coalesce(c.canonical_total,0)>0 or coalesce(t.trace_total,0)>0 or lb.provider_id is not null;
revoke all on pipeline.scholarship_provider_stats from public,anon,authenticated;
grant select on pipeline.scholarship_provider_stats to service_role;
