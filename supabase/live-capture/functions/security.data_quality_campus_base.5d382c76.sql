CREATE OR REPLACE FUNCTION security.data_quality_campus_base(p_country_code text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, entity_name text, stable_key text, provider_id uuid, provider_name text, country_code text, source_id uuid, evidence_id uuid, last_verified_at timestamp with time zone, updated_at timestamp with time zone, publication_status text, identity_ok boolean, geography_present boolean, evidence_count integer, channel_state_count integer, channel_published_count integer, channel_rejected_count integer, channel_distinct_status_count integer, review_domains text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'pipeline', 'workflow', 'publishing', 'auth'
AS $function$
with scope as (
 select ca.*,co.iso_alpha2::text country_code,coalesce(p.display_name,p.canonical_name) provider_name
 from catalogue.campuses ca join catalogue.providers p on p.id=ca.provider_id join ref.countries co on co.id=ca.country_id
 where (p_country_code is null and co.iso_alpha2 in ('AU','NZ')) or (p_country_code is not null and co.iso_alpha2=upper(p_country_code))
), ev as (
 select el.entity_id,count(distinct el.evidence_id)::int evidence_count,(array_agg(el.evidence_id order by el.updated_at desc))[1] evidence_id
 from pipeline.evidence_entity_links el join scope s on s.id=el.entity_id where el.entity_type='campus' group by el.entity_id
), pub as (
 select es.entity_id,count(*)::int state_count,count(*) filter(where lower(es.publication_status)='published')::int published_count,
 count(*) filter(where lower(es.publication_status)='rejected')::int rejected_count,count(distinct lower(es.publication_status))::int distinct_status_count
 from publishing.entity_states es join scope s on s.id=es.entity_id group by es.entity_id
), rev as (
 select q.entity_id,array_agg(distinct lower(q.domain)) filter(where q.status in ('open','queued','pending','in_review')) review_domains
 from workflow.review_queue q join scope s on s.id=q.entity_id group by q.entity_id
)
select s.id,s.name,s.stable_key,s.provider_id,s.provider_name,s.country_code,s.source_id,coalesce(s.evidence_id,ev.evidence_id),s.last_verified_at,s.updated_at,s.publication_status,
 (s.stable_key is not null and btrim(s.stable_key)<>'' and s.name is not null and btrim(s.name)<>'' and s.provider_id is not null and s.country_id is not null),
 (s.subdivision_id is not null or coalesce(nullif(btrim(s.city),''),null) is not null or coalesce(nullif(btrim(s.address_line1),''),null) is not null or (s.latitude is not null and s.longitude is not null)),
 coalesce(ev.evidence_count,case when s.evidence_id is not null then 1 else 0 end),coalesce(pub.state_count,0),coalesce(pub.published_count,0),coalesce(pub.rejected_count,0),coalesce(pub.distinct_status_count,0),coalesce(rev.review_domains,'{}'::text[])
from scope s left join ev on ev.entity_id=s.id left join pub on pub.entity_id=s.id left join rev on rev.entity_id=s.id
$function$
