CREATE OR REPLACE FUNCTION security.data_quality_scholarship_base(p_country_code text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, entity_name text, stable_key text, provider_id uuid, provider_name text, country_code text, source_id uuid, evidence_id uuid, updated_at timestamp with time zone, publication_status text, identity_ok boolean, semantic_present boolean, evidence_count integer, channel_state_count integer, channel_published_count integer, channel_rejected_count integer, channel_distinct_status_count integer, review_domains text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'scholarship', 'catalogue', 'ref', 'pipeline', 'workflow', 'publishing', 'auth'
AS $function$
with scope as (
 select s.*,coalesce(p.display_name,p.canonical_name) provider_name,coalesce(pc.iso_alpha2::text,sc.iso_alpha2::text) country_code
 from scholarship.scholarships s
 left join catalogue.providers p on p.id=s.provider_id
 left join ref.countries pc on pc.id=p.country_id
 left join pipeline.sources src on src.id=s.source_id
 left join ref.countries sc on sc.id=src.country_id
 where ((p_country_code is null and coalesce(pc.iso_alpha2::text,sc.iso_alpha2::text) in ('AU','NZ'))
    or (p_country_code is not null and coalesce(pc.iso_alpha2::text,sc.iso_alpha2::text)=upper(p_country_code)))
), scp as (
 select sc.scholarship_id,count(*) filter(where coalesce(sc.include_exclude,'include')='include')::int include_count
 from scholarship.scopes sc join scope s on s.id=sc.scholarship_id group by sc.scholarship_id
), ev as (
 select el.entity_id,count(distinct el.evidence_id)::int evidence_count,(array_agg(el.evidence_id order by el.updated_at desc))[1] evidence_id
 from pipeline.evidence_entity_links el join scope s on s.id=el.entity_id where el.entity_type='scholarship' group by el.entity_id
), pub as (
 select es.entity_id,count(*)::int state_count,count(*) filter(where lower(es.publication_status)='published')::int published_count,
 count(*) filter(where lower(es.publication_status)='rejected')::int rejected_count,count(distinct lower(es.publication_status))::int distinct_status_count
 from publishing.entity_states es join scope s on s.id=es.entity_id group by es.entity_id
), rev as (
 select q.entity_id,array_agg(distinct lower(q.domain)) filter(where q.status in ('open','queued','pending','in_review')) review_domains
 from workflow.review_queue q join scope s on s.id=q.entity_id group by q.entity_id
)
select s.id,s.name,s.stable_key,s.provider_id,s.provider_name,s.country_code,s.source_id,coalesce(s.evidence_id,ev.evidence_id),s.updated_at,s.publication_status,
 (s.stable_key is not null and btrim(s.stable_key)<>'' and s.name is not null and btrim(s.name)<>''),
 (coalesce(nullif(btrim(s.description),''),null) is not null and coalesce(nullif(btrim(s.source_url),''),null) is not null and s.evidence_id is not null and (coalesce(scp.include_count,0)>0 or s.provider_id is null)),
 coalesce(ev.evidence_count,case when s.evidence_id is not null then 1 else 0 end),coalesce(pub.state_count,0),coalesce(pub.published_count,0),coalesce(pub.rejected_count,0),coalesce(pub.distinct_status_count,0),coalesce(rev.review_domains,'{}'::text[])
from scope s left join scp on scp.scholarship_id=s.id left join ev on ev.entity_id=s.id left join pub on pub.entity_id=s.id left join rev on rev.entity_id=s.id
$function$
