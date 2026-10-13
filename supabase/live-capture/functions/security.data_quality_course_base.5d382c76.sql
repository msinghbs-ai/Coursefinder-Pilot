CREATE OR REPLACE FUNCTION security.data_quality_course_base(p_country_code text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, entity_name text, stable_key text, provider_id uuid, provider_name text, country_code text, source_id uuid, evidence_id uuid, last_verified_at timestamp with time zone, updated_at timestamp with time zone, publication_status text, identity_ok boolean, registration_count integer, campus_count integer, has_delivery boolean, taxonomy_complete boolean, taxonomy_ambiguous boolean, taxonomy_rejected boolean, reg_fee_count integer, reg_fee_value_count integer, reg_fee_zero_count integer, reg_fee_positive_count integer, reg_fee_source_id uuid, reg_fee_evidence_id uuid, provider_fee_count integer, provider_fee_value_count integer, provider_fee_zero_count integer, provider_fee_positive_count integer, provider_fee_suppressed boolean, provider_fee_rejected boolean, provider_fee_source_id uuid, provider_fee_evidence_id uuid, has_url boolean, url_suppressed boolean, url_rejected boolean, url_source_id uuid, url_evidence_id uuid, intake_count integer, intake_suppressed boolean, intake_rejected boolean, intake_source_id uuid, intake_evidence_id uuid, english_count integer, english_suppressed boolean, english_rejected boolean, english_source_id uuid, english_evidence_id uuid, scholarship_include_count integer, scholarship_exclude_count integer, evidence_count integer, search_projected boolean, search_status text, channel_state_count integer, channel_published_count integer, channel_rejected_count integer, channel_distinct_status_count integer, review_domains text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'scholarship', 'pipeline', 'workflow', 'search', 'publishing', 'auth'
AS $function$
with scope as materialized (
  select c.id,c.provider_id,c.stable_key,c.canonical_title,c.display_title,c.course_code,c.course_url,c.delivery_mode,
    c.study_level_id,c.primary_field_id,c.canonical_source_id,c.last_verified_at,c.updated_at,c.publication_status,
    co.iso_alpha2::text as country_code,coalesce(p.display_name,p.canonical_name) as provider_name
  from catalogue.courses c
  join catalogue.providers p on p.id=c.provider_id
  join ref.countries co on co.id=p.country_id
  where (p_country_code is null and co.iso_alpha2 in ('AU','NZ'))
     or (p_country_code is not null and co.iso_alpha2=upper(p_country_code))
), reg as (
  select r.course_id,
    count(*) filter(where coalesce(r.status,'active')='active')::int active_count,
    (array_agg(r.source_id order by r.valid_from desc nulls last,r.id) filter(where r.source_id is not null))[1] source_id,
    (array_agg(r.evidence_id order by r.valid_from desc nulls last,r.id) filter(where r.evidence_id is not null))[1] evidence_id
  from catalogue.course_registrations r join scope s on s.id=r.course_id group by r.course_id
), campus as (
  select cc.course_id,count(*)::int campus_count,
    bool_or(coalesce(nullif(btrim(cc.delivery_mode),''),null) is not null) has_delivery,
    (array_agg(cc.source_id order by cc.is_primary desc,cc.campus_id) filter(where cc.source_id is not null))[1] source_id,
    (array_agg(cc.evidence_id order by cc.is_primary desc,cc.campus_id) filter(where cc.evidence_id is not null))[1] evidence_id
  from catalogue.course_campuses cc join scope s on s.id=cc.course_id group by cc.course_id
), tax as (
  select o.course_id,
    bool_or(lower(o.mapping_status) in ('review_required','ambiguous')) filter(where o.status='current') ambiguous,
    bool_or(lower(o.mapping_status)='rejected') filter(where o.status='current') rejected
  from catalogue.course_study_level_observations o join scope s on s.id=o.course_id group by o.course_id
), fee as (
  select f.course_id,
    count(*) filter(where f.basis='registered_total_course' and f.fee_type='tuition' and coalesce(f.status,'active')='active')::int reg_count,
    count(*) filter(where f.basis='registered_total_course' and f.fee_type='tuition' and coalesce(f.status,'active')='active' and f.amount is not null)::int reg_values,
    count(*) filter(where f.basis='registered_total_course' and f.fee_type='tuition' and coalesce(f.status,'active')='active' and f.amount=0)::int reg_zero,
    count(*) filter(where f.basis='registered_total_course' and f.fee_type='tuition' and coalesce(f.status,'active')='active' and f.amount>0)::int reg_positive,
    (array_agg(f.source_id order by f.source_snapshot_at desc nulls last,f.created_at desc) filter(where f.basis='registered_total_course' and f.fee_type='tuition' and f.source_id is not null))[1] reg_source_id,
    (array_agg(f.evidence_id order by f.source_snapshot_at desc nulls last,f.created_at desc) filter(where f.basis='registered_total_course' and f.fee_type='tuition' and f.evidence_id is not null))[1] reg_evidence_id,
    count(*) filter(where f.fee_type='provider_current_tuition' and f.basis is distinct from 'registered_total_course' and coalesce(f.status,'active')='active')::int provider_count,
    count(*) filter(where f.fee_type='provider_current_tuition' and f.basis is distinct from 'registered_total_course' and coalesce(f.status,'active')='active' and f.amount is not null)::int provider_values,
    count(*) filter(where f.fee_type='provider_current_tuition' and f.basis is distinct from 'registered_total_course' and coalesce(f.status,'active')='active' and f.amount=0)::int provider_zero,
    count(*) filter(where f.fee_type='provider_current_tuition' and f.basis is distinct from 'registered_total_course' and coalesce(f.status,'active')='active' and f.amount>0)::int provider_positive,
    bool_or(lower(coalesce(f.status,''))='suppressed') filter(where f.fee_type='provider_current_tuition' and f.basis is distinct from 'registered_total_course') provider_suppressed,
    bool_or(lower(coalesce(f.status,''))='rejected') filter(where f.fee_type='provider_current_tuition' and f.basis is distinct from 'registered_total_course') provider_rejected,
    (array_agg(f.source_id order by f.source_snapshot_at desc nulls last,f.created_at desc) filter(where f.fee_type='provider_current_tuition' and f.basis is distinct from 'registered_total_course' and f.source_id is not null))[1] provider_source_id,
    (array_agg(f.evidence_id order by f.source_snapshot_at desc nulls last,f.created_at desc) filter(where f.fee_type='provider_current_tuition' and f.basis is distinct from 'registered_total_course' and f.evidence_id is not null))[1] provider_evidence_id
  from catalogue.course_fees f join scope s on s.id=f.course_id group by f.course_id
), link as (
  select l.course_id,
    count(*) filter(where lower(coalesce(l.status,'active'))='active')::int active_count,
    bool_or(lower(coalesce(l.status,''))='suppressed') suppressed,
    bool_or(lower(coalesce(l.status,''))='rejected') rejected,
    (array_agg(l.source_id order by l.is_primary desc,l.updated_at desc) filter(where l.source_id is not null))[1] source_id,
    (array_agg(l.evidence_id order by l.is_primary desc,l.updated_at desc) filter(where l.evidence_id is not null))[1] evidence_id
  from catalogue.course_links l join scope s on s.id=l.course_id where l.link_type = 'official_course' group by l.course_id
), intake as (
  select i.course_id,count(*) filter(where lower(coalesce(i.status,'active'))='active')::int active_count,
    bool_or(lower(coalesce(i.status,''))='suppressed') suppressed,
    bool_or(lower(coalesce(i.status,''))='rejected') rejected,
    (array_agg(i.source_id order by i.intake_year desc nulls last,i.start_date desc nulls last,i.id) filter(where i.source_id is not null))[1] source_id,
    (array_agg(i.evidence_id order by i.intake_year desc nulls last,i.start_date desc nulls last,i.id) filter(where i.evidence_id is not null))[1] evidence_id
  from catalogue.course_intakes i join scope s on s.id=i.course_id group by i.course_id
), english as (
  select e.course_id,count(*) filter(where lower(coalesce(e.status,'active'))='active')::int active_count,
    bool_or(lower(coalesce(e.status,''))='suppressed') suppressed,
    bool_or(lower(coalesce(e.status,''))='rejected') rejected,
    (array_agg(e.source_id order by e.last_verified_at desc nulls last,e.id) filter(where e.source_id is not null))[1] source_id,
    (array_agg(e.evidence_id order by e.last_verified_at desc nulls last,e.id) filter(where e.evidence_id is not null))[1] evidence_id
  from catalogue.course_english_requirements e join scope s on s.id=e.course_id group by e.course_id
), sch_course as (
  select sc.course_id,count(*) filter(where coalesce(sc.include_exclude,'include')='include')::int include_count,
    count(*) filter(where coalesce(sc.include_exclude,'include')='exclude')::int exclude_count
  from scholarship.scopes sc join scope s on s.id=sc.course_id where sc.course_id is not null group by sc.course_id
), sch_provider as (
  select sc.provider_id,count(*) filter(where coalesce(sc.include_exclude,'include')='include')::int include_count,
    count(*) filter(where coalesce(sc.include_exclude,'include')='exclude')::int exclude_count
  from scholarship.scopes sc join (select distinct provider_id from scope) p on p.provider_id=sc.provider_id
  where sc.scope_type='provider' and sc.provider_id is not null group by sc.provider_id
), ev as (
  select el.entity_id,count(distinct el.evidence_id)::int evidence_count,
    (array_agg(el.evidence_id order by el.updated_at desc))[1] evidence_id
  from pipeline.evidence_entity_links el join scope s on s.id=el.entity_id
  where el.entity_type='course' group by el.entity_id
), pub as (
  select es.entity_id,count(*)::int state_count,
    count(*) filter(where lower(es.publication_status)='published')::int published_count,
    count(*) filter(where lower(es.publication_status)='rejected')::int rejected_count,
    count(distinct lower(es.publication_status))::int distinct_status_count
  from publishing.entity_states es join scope s on s.id=es.entity_id group by es.entity_id
), rev as (
  select q.entity_id,array_agg(distinct lower(q.domain)) filter(where q.status in ('open','queued','pending','in_review')) review_domains
  from workflow.review_queue q join scope s on s.id=q.entity_id group by q.entity_id
)
select s.id,coalesce(s.display_title,s.canonical_title),s.stable_key,s.provider_id,s.provider_name,s.country_code,
  coalesce(s.canonical_source_id,reg.source_id),coalesce(ev.evidence_id,reg.evidence_id),s.last_verified_at,s.updated_at,s.publication_status,
  (s.stable_key is not null and btrim(s.stable_key)<>'' and s.canonical_title is not null and btrim(s.canonical_title)<>'' and s.course_code is not null and btrim(s.course_code)<>'' and s.provider_id is not null),
  coalesce(reg.active_count,0),coalesce(campus.campus_count,0),coalesce(campus.has_delivery,false) or coalesce(nullif(btrim(s.delivery_mode),''),null) is not null,
  (s.study_level_id is not null and s.primary_field_id is not null),coalesce(tax.ambiguous,false),coalesce(tax.rejected,false),
  coalesce(fee.reg_count,0),coalesce(fee.reg_values,0),coalesce(fee.reg_zero,0),coalesce(fee.reg_positive,0),fee.reg_source_id,fee.reg_evidence_id,
  coalesce(fee.provider_count,0),coalesce(fee.provider_values,0),coalesce(fee.provider_zero,0),coalesce(fee.provider_positive,0),coalesce(fee.provider_suppressed,false),coalesce(fee.provider_rejected,false),fee.provider_source_id,fee.provider_evidence_id,
  (coalesce(nullif(btrim(s.course_url),''),null) is not null or coalesce(link.active_count,0)>0),coalesce(link.suppressed,false),coalesce(link.rejected,false),coalesce(link.source_id,s.canonical_source_id),coalesce(link.evidence_id,ev.evidence_id),
  coalesce(intake.active_count,0),coalesce(intake.suppressed,false),coalesce(intake.rejected,false),intake.source_id,intake.evidence_id,
  coalesce(english.active_count,0),coalesce(english.suppressed,false),coalesce(english.rejected,false),english.source_id,english.evidence_id,
  coalesce(sch_course.include_count,0)+coalesce(sch_provider.include_count,0),coalesce(sch_course.exclude_count,0)+coalesce(sch_provider.exclude_count,0),coalesce(ev.evidence_count,0),
  (d.course_id is not null),d.publication_status,
  coalesce(pub.state_count,0),coalesce(pub.published_count,0),coalesce(pub.rejected_count,0),coalesce(pub.distinct_status_count,0),
  coalesce(rev.review_domains,'{}'::text[])
from scope s
left join reg on reg.course_id=s.id
left join campus on campus.course_id=s.id
left join tax on tax.course_id=s.id
left join fee on fee.course_id=s.id
left join link on link.course_id=s.id
left join intake on intake.course_id=s.id
left join english on english.course_id=s.id
left join sch_course on sch_course.course_id=s.id
left join sch_provider on sch_provider.provider_id=s.provider_id
left join ev on ev.entity_id=s.id
left join search.course_documents d on d.course_id=s.id
left join pub on pub.entity_id=s.id
left join rev on rev.entity_id=s.id
$function$
