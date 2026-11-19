create or replace view pipeline.scholarship_provider_stats as
with canonical as (
  select provider_id,
         count(*)::int as canonical_total,
         count(*) filter (where publication_status='published')::int as published_total,
         count(*) filter (where publication_status<>'published')::int as unpublished_total
  from scholarship.scholarships
  group by provider_id
), trace as (
  select provider_id,
         count(*)::int as trace_total,
         count(*) filter (where verification_status='verified_first_party')::int as first_party_verified_total,
         count(*) filter (where review_queue_id is not null)::int as layer4_linked_total,
         count(*) filter (where scholarship_id is not null)::int as canonical_linked_total,
         count(*) filter (where publication_decision_id is not null)::int as publication_decision_linked_total,
         max(updated_at) as trace_last_updated_at
  from pipeline.scholarship_acquisition_trace
  group by provider_id
), latest_benchmark as (
  select distinct on (provider_id)
         provider_id,
         observed_count as landscape_benchmark_total,
         observed_at as benchmark_observed_at
  from pipeline.scholarship_coverage_benchmarks
  where benchmark_scope='provider' and provider_id is not null
  order by provider_id, observed_at desc
)
select p.id as provider_id,
       p.canonical_name as provider_name,
       coalesce(c.canonical_total,0) as canonical_total,
       coalesce(c.published_total,0) as published_total,
       coalesce(c.unpublished_total,0) as unpublished_total,
       coalesce(t.trace_total,0) as trace_total,
       coalesce(t.first_party_verified_total,0) as first_party_verified_total,
       coalesce(t.layer4_linked_total,0) as layer4_linked_total,
       coalesce(t.canonical_linked_total,0) as canonical_linked_total,
       coalesce(t.publication_decision_linked_total,0) as publication_decision_linked_total,
       lb.landscape_benchmark_total,
       case when lb.landscape_benchmark_total is null then null
            else greatest(lb.landscape_benchmark_total - coalesce(c.canonical_total,0),0)
       end as indicative_gap_to_landscape,
       case when lb.landscape_benchmark_total is null or lb.landscape_benchmark_total=0 then null
            else round((coalesce(c.canonical_total,0)::numeric / lb.landscape_benchmark_total::numeric) * 100,1)
       end as canonical_to_landscape_pct,
       lb.benchmark_observed_at,
       t.trace_last_updated_at
from catalogue.providers p
left join canonical c on c.provider_id=p.id
left join trace t on t.provider_id=p.id
left join latest_benchmark lb on lb.provider_id=p.id
where coalesce(c.canonical_total,0)>0
   or coalesce(t.trace_total,0)>0
   or lb.provider_id is not null;

revoke all on pipeline.scholarship_provider_stats from public, anon, authenticated;
grant select on pipeline.scholarship_provider_stats to service_role;
comment on view pipeline.scholarship_provider_stats is 'Internal scholarship provider summary for operational completeness and traceability. Landscape benchmark fields are non-authoritative internal coverage signals only.';
