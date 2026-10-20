CREATE OR REPLACE FUNCTION security.data_quality_provider_base(p_country_code text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, entity_name text, stable_key text, country_code text, source_id uuid, evidence_id uuid, last_verified_at timestamp with time zone, updated_at timestamp with time zone, publication_status text, identity_ok boolean, registration_count integer, geography_present boolean, evidence_count integer, channel_state_count integer, channel_published_count integer, channel_rejected_count integer, channel_distinct_status_count integer, review_domains text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'pipeline', 'workflow', 'publishing', 'auth'
AS $function$
with scope as (
  select p.*,co.iso_alpha2::text country_code
  from catalogue.providers p join ref.countries co on co.id=p.country_id
  where (p_country_code is null and co.iso_alpha2 in ('AU','NZ')) or (p_country_code is not null and co.iso_alpha2=upper(p_country_code))
), reg as (
  select r.provider_id,count(*) filter(where coalesce(r.status,'active')='active')::int active_count,
    (array_agg(r.source_id order by r.checked_at desc nulls last,r.id) filter(where r.source_id is not null))[1] source_id,
    (array_agg(r.evidence_id order by r.checked_at desc nulls last,r.id) filter(where r.evidence_id is not null))[1] evidence_id
  from catalogue.provider_registrations r join scope s on s.id=r.provider_id group by r.provider_id
), ev as (
  select el.entity_id,count(distinct el.evidence_id)::int evidence_count,(array_agg(el.evidence_id order by el.updated_at desc))[1] evidence_id
  from pipeline.evidence_entity_links el join scope s on s.id=el.entity_id where el.entity_type='provider' group by el.entity_id
), pub as (
  select es.entity_id,count(*)::int state_count,count(*) filter(where lower(es.publication_status)='published')::int published_count,
    count(*) filter(where lower(es.publication_status)='rejected')::int rejected_count,count(distinct lower(es.publication_status))::int distinct_status_count
  from publishing.entity_states es join scope s on s.id=es.entity_id group by es.entity_id
), rev as (
  select q.entity_id,array_agg(distinct lower(q.domain)) filter(where q.status in ('open','queued','pending','in_review')) review_domains
  from workflow.review_queue q join scope s on s.id=q.entity_id group by q.entity_id
)
select s.id,coalesce(s.display_name,s.canonical_name),s.stable_key,s.country_code,coalesce(s.canonical_source_id,reg.source_id),coalesce(ev.evidence_id,reg.evidence_id),
 s.last_verified_at,s.updated_at,s.publication_status,
 (s.stable_key is not null and btrim(s.stable_key)<>'' and s.canonical_name is not null and btrim(s.canonical_name)<>'' and s.country_id is not null),
 coalesce(reg.active_count,0),
 (s.subdivision_id is not null or coalesce(nullif(btrim(s.primary_city),''),null) is not null or coalesce(nullif(btrim(s.address_line1),''),null) is not null),
 coalesce(ev.evidence_count,0),coalesce(pub.state_count,0),coalesce(pub.published_count,0),coalesce(pub.rejected_count,0),coalesce(pub.distinct_status_count,0),coalesce(rev.review_domains,'{}'::text[])
from scope s left join reg on reg.provider_id=s.id left join ev on ev.entity_id=s.id left join pub on pub.entity_id=s.id left join rev on rev.entity_id=s.id
$function$
