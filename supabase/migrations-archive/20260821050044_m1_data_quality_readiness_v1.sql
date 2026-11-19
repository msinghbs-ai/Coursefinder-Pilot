create or replace function security.data_quality_course_base(p_country_code text default null)
returns table(
  id uuid, entity_name text, stable_key text, provider_id uuid, provider_name text, country_code text,
  source_id uuid, evidence_id uuid, last_verified_at timestamptz, updated_at timestamptz, publication_status text,
  identity_ok boolean, registration_count integer, campus_count integer, has_delivery boolean,
  taxonomy_complete boolean, taxonomy_ambiguous boolean, taxonomy_rejected boolean,
  reg_fee_count integer, reg_fee_value_count integer, reg_fee_zero_count integer, reg_fee_positive_count integer,
  reg_fee_source_id uuid, reg_fee_evidence_id uuid,
  provider_fee_count integer, provider_fee_value_count integer, provider_fee_zero_count integer, provider_fee_positive_count integer,
  provider_fee_suppressed boolean, provider_fee_rejected boolean, provider_fee_source_id uuid, provider_fee_evidence_id uuid,
  has_url boolean, url_suppressed boolean, url_rejected boolean, url_source_id uuid, url_evidence_id uuid,
  intake_count integer, intake_suppressed boolean, intake_rejected boolean, intake_source_id uuid, intake_evidence_id uuid,
  english_count integer, english_suppressed boolean, english_rejected boolean, english_source_id uuid, english_evidence_id uuid,
  scholarship_include_count integer, scholarship_exclude_count integer,
  evidence_count integer, search_projected boolean, search_status text,
  channel_state_count integer, channel_published_count integer, channel_rejected_count integer, channel_distinct_status_count integer,
  review_domains text[]
)
language sql
stable
security definer
set search_path = pg_catalog, security, catalogue, ref, scholarship, pipeline, workflow, search, publishing, auth
as $$
with scope as (
  select c.*, co.iso_alpha2::text as country_code, coalesce(p.display_name,p.canonical_name) as provider_name
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
  from catalogue.course_links l join scope s on s.id=l.course_id group by l.course_id
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
), sch as (
  select s.id course_id,
    count(sc.id) filter(where coalesce(sc.include_exclude,'include')='include')::int include_count,
    count(sc.id) filter(where coalesce(sc.include_exclude,'include')='exclude')::int exclude_count
  from scope s left join scholarship.scopes sc on sc.course_id=s.id or (sc.scope_type='provider' and sc.provider_id=s.provider_id)
  group by s.id
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
  coalesce(sch.include_count,0),coalesce(sch.exclude_count,0),coalesce(ev.evidence_count,0),
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
left join sch on sch.course_id=s.id
left join ev on ev.entity_id=s.id
left join search.course_documents d on d.course_id=s.id
left join pub on pub.entity_id=s.id
left join rev on rev.entity_id=s.id
$$;

create or replace function security.data_quality_provider_base(p_country_code text default null)
returns table(
  id uuid, entity_name text, stable_key text, country_code text, source_id uuid, evidence_id uuid,
  last_verified_at timestamptz, updated_at timestamptz, publication_status text,
  identity_ok boolean, registration_count integer, geography_present boolean, evidence_count integer,
  channel_state_count integer, channel_published_count integer, channel_rejected_count integer, channel_distinct_status_count integer,
  review_domains text[]
)
language sql stable security definer
set search_path = pg_catalog, security, catalogue, ref, pipeline, workflow, publishing, auth
as $$
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
$$;

create or replace function security.data_quality_campus_base(p_country_code text default null)
returns table(
 id uuid, entity_name text, stable_key text, provider_id uuid, provider_name text, country_code text, source_id uuid, evidence_id uuid,
 last_verified_at timestamptz, updated_at timestamptz, publication_status text, identity_ok boolean, geography_present boolean, evidence_count integer,
 channel_state_count integer, channel_published_count integer, channel_rejected_count integer, channel_distinct_status_count integer, review_domains text[]
)
language sql stable security definer
set search_path = pg_catalog, security, catalogue, ref, pipeline, workflow, publishing, auth
as $$
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
$$;

create or replace function security.data_quality_scholarship_base(p_country_code text default null)
returns table(
 id uuid, entity_name text, stable_key text, provider_id uuid, provider_name text, country_code text, source_id uuid, evidence_id uuid,
 updated_at timestamptz, publication_status text, identity_ok boolean, semantic_present boolean, evidence_count integer,
 channel_state_count integer, channel_published_count integer, channel_rejected_count integer, channel_distinct_status_count integer, review_domains text[]
)
language sql stable security definer
set search_path = pg_catalog, security, scholarship, catalogue, ref, pipeline, workflow, publishing, auth
as $$
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
$$;

create or replace function security.data_quality_overview_impl(p_args jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, security
as $$
with params as (select nullif(upper(btrim(coalesce(p_args->>'country_code',''))),'') country_code),
course_states as (
 select 'course'::text entity_type,v.domain,v.state
 from security.data_quality_course_base((select country_code from params)) c
 cross join lateral (values
   ('identity_completeness',case when 'identity_completeness'=any(c.review_domains) then 'ambiguous' when c.identity_ok then 'present' else 'source_null' end),
   ('regulatory_completeness',case when 'regulatory_completeness'=any(c.review_domains) then 'ambiguous' when c.registration_count>0 then 'present' else case when c.country_code in ('AU','NZ') then 'source_null' else 'not_yet_enriched' end end),
   ('geography_delivery',case when 'geography_delivery'=any(c.review_domains) then 'ambiguous' when c.campus_count>0 and c.has_delivery then 'present' when c.country_code='AU' and c.campus_count=0 then 'source_null' else 'not_yet_enriched' end),
   ('taxonomy',case when 'taxonomy'=any(c.review_domains) or c.taxonomy_ambiguous then 'ambiguous' when c.taxonomy_rejected then 'rejected' when c.taxonomy_complete then 'present' when c.country_code='AU' then 'source_null' else 'not_yet_enriched' end),
   ('regulatory_fee',case when 'regulatory_fee'=any(c.review_domains) then 'ambiguous' when c.country_code<>'AU' then 'not_applicable' when c.reg_fee_count=0 or c.reg_fee_value_count=0 then 'source_null' when c.reg_fee_positive_count>0 then 'present' when c.reg_fee_zero_count>0 then 'zero' else 'source_null' end),
   ('provider_current_fee',case when 'provider_current_fee'=any(c.review_domains) then 'ambiguous' when c.provider_fee_rejected then 'rejected' when c.provider_fee_suppressed and c.provider_fee_count=0 then 'suppressed' when c.provider_fee_count=0 then 'not_yet_enriched' when c.provider_fee_value_count=0 then 'source_null' when c.provider_fee_positive_count>0 then 'present' when c.provider_fee_zero_count>0 then 'zero' else 'source_null' end),
   ('course_url',case when 'course_url'=any(c.review_domains) then 'ambiguous' when c.url_rejected then 'rejected' when c.url_suppressed and not c.has_url then 'suppressed' when c.has_url then 'present' else 'not_yet_enriched' end),
   ('intake',case when 'intake'=any(c.review_domains) then 'ambiguous' when c.intake_rejected then 'rejected' when c.intake_suppressed and c.intake_count=0 then 'suppressed' when c.intake_count>0 then 'present' else 'not_yet_enriched' end),
   ('english_requirement',case when 'english_requirement'=any(c.review_domains) then 'ambiguous' when c.english_rejected then 'rejected' when c.english_suppressed and c.english_count=0 then 'suppressed' when c.english_count>0 then 'present' else 'not_yet_enriched' end),
   ('scholarship',case when 'scholarship'=any(c.review_domains) then 'ambiguous' when c.scholarship_include_count>0 then 'present' when c.scholarship_exclude_count>0 then 'not_applicable' else 'not_yet_enriched' end),
   ('evidence',case when 'evidence'=any(c.review_domains) then 'ambiguous' when c.evidence_count>0 then 'present' else 'not_yet_enriched' end),
   ('verification_freshness',case when 'verification_freshness'=any(c.review_domains) then 'ambiguous' when c.last_verified_at is null or c.last_verified_at<now()-interval '180 days' then 'stale' else 'present' end),
   ('search_admission',case when 'search_admission'=any(c.review_domains) then 'ambiguous' when c.search_projected then 'present' else 'not_yet_enriched' end),
   ('publication_readiness',case when 'publication_readiness'=any(c.review_domains) then 'ambiguous' when c.channel_rejected_count>0 or lower(coalesce(c.publication_status,''))='rejected' then 'rejected' when c.channel_distinct_status_count>1 then 'ambiguous' when c.channel_published_count>0 or lower(coalesce(c.publication_status,''))='published' then 'present' else 'not_yet_enriched' end)
 ) v(domain,state)
), provider_states as (
 select 'provider'::text entity_type,v.domain,v.state
 from security.data_quality_provider_base((select country_code from params)) p
 cross join lateral (values
   ('identity_completeness',case when 'identity_completeness'=any(p.review_domains) then 'ambiguous' when p.identity_ok then 'present' else 'source_null' end),
   ('regulatory_completeness',case when 'regulatory_completeness'=any(p.review_domains) then 'ambiguous' when p.registration_count>0 then 'present' else 'source_null' end),
   ('geography_delivery',case when 'geography_delivery'=any(p.review_domains) then 'ambiguous' when p.geography_present then 'present' else 'not_yet_enriched' end),
   ('evidence',case when 'evidence'=any(p.review_domains) then 'ambiguous' when p.evidence_count>0 then 'present' else 'not_yet_enriched' end),
   ('verification_freshness',case when 'verification_freshness'=any(p.review_domains) then 'ambiguous' when p.last_verified_at is null or p.last_verified_at<now()-interval '180 days' then 'stale' else 'present' end),
   ('publication_readiness',case when 'publication_readiness'=any(p.review_domains) then 'ambiguous' when p.channel_rejected_count>0 or lower(coalesce(p.publication_status,''))='rejected' then 'rejected' when p.channel_distinct_status_count>1 then 'ambiguous' when p.channel_published_count>0 or lower(coalesce(p.publication_status,''))='published' then 'present' else 'not_yet_enriched' end)
 ) v(domain,state)
), campus_states as (
 select 'campus'::text entity_type,v.domain,v.state
 from security.data_quality_campus_base((select country_code from params)) c
 cross join lateral (values
   ('identity_completeness',case when 'identity_completeness'=any(c.review_domains) then 'ambiguous' when c.identity_ok then 'present' else 'source_null' end),
   ('geography_delivery',case when 'geography_delivery'=any(c.review_domains) then 'ambiguous' when c.geography_present then 'present' else 'source_null' end),
   ('evidence',case when 'evidence'=any(c.review_domains) then 'ambiguous' when c.evidence_count>0 then 'present' else 'not_yet_enriched' end),
   ('verification_freshness',case when 'verification_freshness'=any(c.review_domains) then 'ambiguous' when c.last_verified_at is null or c.last_verified_at<now()-interval '180 days' then 'stale' else 'present' end),
   ('publication_readiness',case when 'publication_readiness'=any(c.review_domains) then 'ambiguous' when c.channel_rejected_count>0 or lower(coalesce(c.publication_status,''))='rejected' then 'rejected' when c.channel_distinct_status_count>1 then 'ambiguous' when c.channel_published_count>0 or lower(coalesce(c.publication_status,''))='published' then 'present' else 'not_yet_enriched' end)
 ) v(domain,state)
), scholarship_states as (
 select 'scholarship'::text entity_type,v.domain,v.state
 from security.data_quality_scholarship_base((select country_code from params)) s
 cross join lateral (values
   ('identity_completeness',case when 'identity_completeness'=any(s.review_domains) then 'ambiguous' when s.identity_ok then 'present' else 'source_null' end),
   ('scholarship',case when 'scholarship'=any(s.review_domains) then 'ambiguous' when s.semantic_present then 'present' else 'not_yet_enriched' end),
   ('evidence',case when 'evidence'=any(s.review_domains) then 'ambiguous' when s.evidence_count>0 then 'present' else 'not_yet_enriched' end),
   ('verification_freshness',case when 'verification_freshness'=any(s.review_domains) then 'ambiguous' else 'not_yet_enriched' end),
   ('publication_readiness',case when 'publication_readiness'=any(s.review_domains) then 'ambiguous' when s.channel_rejected_count>0 or lower(coalesce(s.publication_status,''))='rejected' then 'rejected' when s.channel_distinct_status_count>1 then 'ambiguous' when s.channel_published_count>0 or lower(coalesce(s.publication_status,''))='published' then 'present' else 'not_yet_enriched' end)
 ) v(domain,state)
), all_states as (
 select * from course_states union all select * from provider_states union all select * from campus_states union all select * from scholarship_states
), defs(domain,label,sort_order,definition,authority) as (values
 ('identity_completeness','Identity completeness',10,'Stable governed identity fields required to resolve the entity without title/name inference.','Layer 1 canonical identity'),
 ('regulatory_completeness','Regulatory completeness',20,'Current authoritative registration/Layer 1 regulatory presence; country-specific authority is preserved.','CRICOS / NZQA Layer 1'),
 ('geography_delivery','Geography / delivery',30,'Provider/Campus geography and Course delivery relationships remain distinct. AU CRICOS source-absent Course Locations are not synthesised.','Layer 1 location authority / later enrichment'),
 ('taxonomy','Taxonomy',40,'Governed Study Level and Field mappings; ambiguous/rejected source mappings remain exceptions.','Governed reference taxonomy'),
 ('regulatory_fee','Regulatory fee',50,'AU CRICOS registered total-course tuition only. NZ has no CRICOS-equivalent fee dimension in the accepted Layer 1 contract.','CRICOS regulatory source'),
 ('provider_current_fee','Current Provider fee',60,'Current Provider-published fee observations remain separate from CRICOS registered total-course fees.','Layer 2 Provider first-party source'),
 ('course_url','Course URL',70,'Official Course URL/link enrichment; absence before a successful enrichment is not treated as source-null.','Layer 2 Provider first-party source'),
 ('intake','Intake',80,'Provider-current intake observations with suppression/rejection retained distinctly.','Layer 2 Provider first-party source'),
 ('english_requirement','English requirement',90,'Provider-current English entry requirements with suppression/rejection retained distinctly.','Layer 2 Provider first-party source'),
 ('scholarship','Scholarship',100,'Relational Scholarship applicability; no scholarship relationship is not treated as a canonical Course defect.','Layer 2 Scholarship sources'),
 ('evidence','Evidence',110,'Presence of governed evidence lineage for the canonical/enrichment entity.','Evidence workspace / source snapshots'),
 ('verification_freshness','Verification / freshness',120,'Explicit verification timestamps only; missing or older-than-180-day verification is stale. Scholarship verification is not inferred from updated_at.','Canonical verification semantics'),
 ('search_admission','Search admission',130,'Presence in the governed Search projection; this does not imply enrichment admission or publication.','Search course-v2 projection'),
 ('publication_readiness','Publication readiness',140,'Recorded canonical/channel publication progression; no channel state is not invented as published.','Canonical + publishing channel state')
), agg as (
 select entity_type,domain,count(*)::bigint scope_count,
   count(*) filter(where state<>'not_applicable')::bigint applicable_count,
   count(*) filter(where state in ('present','zero'))::bigint ready_count,
   count(*) filter(where state in ('source_null','suppressed','not_yet_enriched','stale','ambiguous','rejected'))::bigint attention_count,
   jsonb_build_object(
    'present',count(*) filter(where state='present'),'source_null',count(*) filter(where state='source_null'),
    'not_applicable',count(*) filter(where state='not_applicable'),'zero',count(*) filter(where state='zero'),
    'suppressed',count(*) filter(where state='suppressed'),'not_yet_enriched',count(*) filter(where state='not_yet_enriched'),
    'stale',count(*) filter(where state='stale'),'ambiguous',count(*) filter(where state='ambiguous'),'rejected',count(*) filter(where state='rejected')
   ) states
 from all_states group by entity_type,domain
), metrics as (
 select a.*,d.label,d.sort_order,d.definition,d.authority,
   case when a.applicable_count=0 then null else round(a.ready_count*100.0/a.applicable_count,2) end readiness_pct
 from agg a join defs d using(domain)
)
select jsonb_build_object(
 'scope',jsonb_build_object('country_code',(select country_code from params),'default_scope',case when (select country_code from params) is null then 'AU+NZ' else (select country_code from params) end,'as_of',now()),
 'policy',jsonb_build_object('composite_score','not_exposed','reason','Cross-domain equal weighting conflates regulatory authority, enrichment coverage, Search admission and publication state. Domain readiness is reported instead.','ready_states',jsonb_build_array('present','zero'),'excluded_from_denominator',jsonb_build_array('not_applicable')),
 'state_vocabulary',jsonb_build_array('present','source_null','not_applicable','zero','suppressed','not_yet_enriched','stale','ambiguous','rejected'),
 'metrics',coalesce((select jsonb_agg(jsonb_build_object('entity_type',entity_type,'domain',domain,'label',label,'scope_count',scope_count,'applicable_count',applicable_count,'ready_count',ready_count,'attention_count',attention_count,'readiness_pct',readiness_pct,'states',states,'definition',definition,'authority',authority) order by sort_order,entity_type) from metrics),'[]'::jsonb)
)
$$;

create or replace function security.data_quality_exceptions_impl(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, pipeline, workflow
as $$
declare
 v_entity text:=lower(coalesce(nullif(p_args->>'entity_type',''),'course'));
 v_domain text:=lower(coalesce(nullif(p_args->>'domain',''),'identity_completeness'));
 v_state text:=lower(nullif(p_args->>'state',''));
 v_country text:=nullif(upper(btrim(coalesce(p_args->>'country_code',''))),'');
 v_query text:=nullif(btrim(coalesce(p_args->>'query','')),'');
 v_limit int:=least(greatest(coalesce(nullif(p_args->>'limit','')::int,50),1),200);
 v_offset int:=greatest(coalesce(nullif(p_args->>'offset','')::int,0),0);
 v_result jsonb;
begin
 if v_entity='course' then
  with classified as (
   select c.*,
    case v_domain
     when 'identity_completeness' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.identity_ok then 'present' else 'source_null' end
     when 'regulatory_completeness' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.registration_count>0 then 'present' else case when c.country_code in ('AU','NZ') then 'source_null' else 'not_yet_enriched' end end
     when 'geography_delivery' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.campus_count>0 and c.has_delivery then 'present' when c.country_code='AU' and c.campus_count=0 then 'source_null' else 'not_yet_enriched' end
     when 'taxonomy' then case when v_domain=any(c.review_domains) or c.taxonomy_ambiguous then 'ambiguous' when c.taxonomy_rejected then 'rejected' when c.taxonomy_complete then 'present' when c.country_code='AU' then 'source_null' else 'not_yet_enriched' end
     when 'regulatory_fee' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.country_code<>'AU' then 'not_applicable' when c.reg_fee_count=0 or c.reg_fee_value_count=0 then 'source_null' when c.reg_fee_positive_count>0 then 'present' when c.reg_fee_zero_count>0 then 'zero' else 'source_null' end
     when 'provider_current_fee' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.provider_fee_rejected then 'rejected' when c.provider_fee_suppressed and c.provider_fee_count=0 then 'suppressed' when c.provider_fee_count=0 then 'not_yet_enriched' when c.provider_fee_value_count=0 then 'source_null' when c.provider_fee_positive_count>0 then 'present' when c.provider_fee_zero_count>0 then 'zero' else 'source_null' end
     when 'course_url' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.url_rejected then 'rejected' when c.url_suppressed and not c.has_url then 'suppressed' when c.has_url then 'present' else 'not_yet_enriched' end
     when 'intake' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.intake_rejected then 'rejected' when c.intake_suppressed and c.intake_count=0 then 'suppressed' when c.intake_count>0 then 'present' else 'not_yet_enriched' end
     when 'english_requirement' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.english_rejected then 'rejected' when c.english_suppressed and c.english_count=0 then 'suppressed' when c.english_count>0 then 'present' else 'not_yet_enriched' end
     when 'scholarship' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.scholarship_include_count>0 then 'present' when c.scholarship_exclude_count>0 then 'not_applicable' else 'not_yet_enriched' end
     when 'evidence' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.evidence_count>0 then 'present' else 'not_yet_enriched' end
     when 'verification_freshness' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.last_verified_at is null or c.last_verified_at<now()-interval '180 days' then 'stale' else 'present' end
     when 'search_admission' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.search_projected then 'present' else 'not_yet_enriched' end
     when 'publication_readiness' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.channel_rejected_count>0 or lower(coalesce(c.publication_status,''))='rejected' then 'rejected' when c.channel_distinct_status_count>1 then 'ambiguous' when c.channel_published_count>0 or lower(coalesce(c.publication_status,''))='published' then 'present' else 'not_yet_enriched' end
     else null end state,
    case v_domain when 'regulatory_fee' then coalesce(c.reg_fee_source_id,c.source_id) when 'provider_current_fee' then coalesce(c.provider_fee_source_id,c.source_id) when 'course_url' then coalesce(c.url_source_id,c.source_id) when 'intake' then coalesce(c.intake_source_id,c.source_id) when 'english_requirement' then coalesce(c.english_source_id,c.source_id) else c.source_id end domain_source_id,
    case v_domain when 'regulatory_fee' then coalesce(c.reg_fee_evidence_id,c.evidence_id) when 'provider_current_fee' then coalesce(c.provider_fee_evidence_id,c.evidence_id) when 'course_url' then coalesce(c.url_evidence_id,c.evidence_id) when 'intake' then coalesce(c.intake_evidence_id,c.evidence_id) when 'english_requirement' then coalesce(c.english_evidence_id,c.evidence_id) else c.evidence_id end domain_evidence_id
   from security.data_quality_course_base(v_country) c
  ), filtered as (
   select c.* from classified c where c.state is not null
    and (v_state is not null and c.state=v_state or v_state is null and c.state in ('source_null','suppressed','not_yet_enriched','stale','ambiguous','rejected'))
    and (v_query is null or c.entity_name ilike '%'||v_query||'%' or c.provider_name ilike '%'||v_query||'%' or c.stable_key ilike '%'||v_query||'%')
  ), numbered as (select f.*,count(*) over() total_count from filtered f), paged as (
   select * from numbered order by case state when 'rejected' then 1 when 'ambiguous' then 2 when 'source_null' then 3 when 'suppressed' then 4 when 'stale' then 5 else 6 end,lower(entity_name),id limit v_limit offset v_offset
  )
  select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object(
    'entity_id',p.id,'entity_type','course','entity_name',p.entity_name,'stable_key',p.stable_key,'provider_id',p.provider_id,'provider_name',p.provider_name,'country_code',p.country_code,
    'domain',v_domain,'state',p.state,'source_id',p.domain_source_id,'source_label',src.label,'evidence_id',p.domain_evidence_id,
    'review_id',(select q.id from workflow.review_queue q where q.entity_id=p.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review') order by q.priority desc,q.created_at limit 1),
    'last_verified_at',p.last_verified_at,'updated_at',p.updated_at,
    'context',jsonb_build_object('campus_count',p.campus_count,'registration_count',p.registration_count,'reg_fee_count',p.reg_fee_count,'provider_fee_count',p.provider_fee_count,'intake_count',p.intake_count,'english_count',p.english_count,'scholarship_relations',p.scholarship_include_count,'search_projected',p.search_projected,'canonical_publication',p.publication_status)
   ) order by lower(p.entity_name)),'[]'::jsonb),'total',coalesce(max(p.total_count),0),'limit',v_limit,'offset',v_offset,'entity_type','course','domain',v_domain,'state',v_state)
   into v_result from paged p left join pipeline.sources src on src.id=p.domain_source_id;
  return v_result;
 elsif v_entity='provider' then
  with classified as (
   select p.*,
    case v_domain
     when 'identity_completeness' then case when v_domain=any(p.review_domains) then 'ambiguous' when p.identity_ok then 'present' else 'source_null' end
     when 'regulatory_completeness' then case when v_domain=any(p.review_domains) then 'ambiguous' when p.registration_count>0 then 'present' else 'source_null' end
     when 'geography_delivery' then case when v_domain=any(p.review_domains) then 'ambiguous' when p.geography_present then 'present' else 'not_yet_enriched' end
     when 'evidence' then case when v_domain=any(p.review_domains) then 'ambiguous' when p.evidence_count>0 then 'present' else 'not_yet_enriched' end
     when 'verification_freshness' then case when v_domain=any(p.review_domains) then 'ambiguous' when p.last_verified_at is null or p.last_verified_at<now()-interval '180 days' then 'stale' else 'present' end
     when 'publication_readiness' then case when v_domain=any(p.review_domains) then 'ambiguous' when p.channel_rejected_count>0 or lower(coalesce(p.publication_status,''))='rejected' then 'rejected' when p.channel_distinct_status_count>1 then 'ambiguous' when p.channel_published_count>0 or lower(coalesce(p.publication_status,''))='published' then 'present' else 'not_yet_enriched' end
     else null end state
   from security.data_quality_provider_base(v_country) p
  ), filtered as (
   select p.* from classified p where p.state is not null and (v_state is not null and p.state=v_state or v_state is null and p.state in ('source_null','suppressed','not_yet_enriched','stale','ambiguous','rejected'))
    and (v_query is null or p.entity_name ilike '%'||v_query||'%' or p.stable_key ilike '%'||v_query||'%')
  ), numbered as (select f.*,count(*) over() total_count from filtered f), paged as (select * from numbered order by lower(entity_name),id limit v_limit offset v_offset)
  select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('entity_id',p.id,'entity_type','provider','entity_name',p.entity_name,'stable_key',p.stable_key,'country_code',p.country_code,'domain',v_domain,'state',p.state,'source_id',p.source_id,'source_label',src.label,'evidence_id',p.evidence_id,'review_id',(select q.id from workflow.review_queue q where q.entity_id=p.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review') order by q.priority desc,q.created_at limit 1),'last_verified_at',p.last_verified_at,'updated_at',p.updated_at) order by lower(p.entity_name)),'[]'::jsonb),'total',coalesce(max(p.total_count),0),'limit',v_limit,'offset',v_offset,'entity_type','provider','domain',v_domain,'state',v_state)
  into v_result from paged p left join pipeline.sources src on src.id=p.source_id; return v_result;
 elsif v_entity='campus' then
  with classified as (
   select c.*,
    case v_domain
     when 'identity_completeness' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.identity_ok then 'present' else 'source_null' end
     when 'geography_delivery' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.geography_present then 'present' else 'source_null' end
     when 'evidence' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.evidence_count>0 then 'present' else 'not_yet_enriched' end
     when 'verification_freshness' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.last_verified_at is null or c.last_verified_at<now()-interval '180 days' then 'stale' else 'present' end
     when 'publication_readiness' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.channel_rejected_count>0 or lower(coalesce(c.publication_status,''))='rejected' then 'rejected' when c.channel_distinct_status_count>1 then 'ambiguous' when c.channel_published_count>0 or lower(coalesce(c.publication_status,''))='published' then 'present' else 'not_yet_enriched' end
     else null end state
   from security.data_quality_campus_base(v_country) c
  ), filtered as (
   select c.* from classified c where c.state is not null and (v_state is not null and c.state=v_state or v_state is null and c.state in ('source_null','suppressed','not_yet_enriched','stale','ambiguous','rejected'))
    and (v_query is null or c.entity_name ilike '%'||v_query||'%' or c.provider_name ilike '%'||v_query||'%' or c.stable_key ilike '%'||v_query||'%')
  ), numbered as (select f.*,count(*) over() total_count from filtered f), paged as (select * from numbered order by lower(entity_name),id limit v_limit offset v_offset)
  select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('entity_id',p.id,'entity_type','campus','entity_name',p.entity_name,'stable_key',p.stable_key,'provider_id',p.provider_id,'provider_name',p.provider_name,'country_code',p.country_code,'domain',v_domain,'state',p.state,'source_id',p.source_id,'source_label',src.label,'evidence_id',p.evidence_id,'review_id',(select q.id from workflow.review_queue q where q.entity_id=p.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review') order by q.priority desc,q.created_at limit 1),'last_verified_at',p.last_verified_at,'updated_at',p.updated_at) order by lower(p.entity_name)),'[]'::jsonb),'total',coalesce(max(p.total_count),0),'limit',v_limit,'offset',v_offset,'entity_type','campus','domain',v_domain,'state',v_state)
  into v_result from paged p left join pipeline.sources src on src.id=p.source_id; return v_result;
 elsif v_entity='scholarship' then
  with classified as (
   select s.*,
    case v_domain
     when 'identity_completeness' then case when v_domain=any(s.review_domains) then 'ambiguous' when s.identity_ok then 'present' else 'source_null' end
     when 'scholarship' then case when v_domain=any(s.review_domains) then 'ambiguous' when s.semantic_present then 'present' else 'not_yet_enriched' end
     when 'evidence' then case when v_domain=any(s.review_domains) then 'ambiguous' when s.evidence_count>0 then 'present' else 'not_yet_enriched' end
     when 'verification_freshness' then case when v_domain=any(s.review_domains) then 'ambiguous' else 'not_yet_enriched' end
     when 'publication_readiness' then case when v_domain=any(s.review_domains) then 'ambiguous' when s.channel_rejected_count>0 or lower(coalesce(s.publication_status,''))='rejected' then 'rejected' when s.channel_distinct_status_count>1 then 'ambiguous' when s.channel_published_count>0 or lower(coalesce(s.publication_status,''))='published' then 'present' else 'not_yet_enriched' end
     else null end state
   from security.data_quality_scholarship_base(v_country) s
  ), filtered as (
   select s.* from classified s where s.state is not null and (v_state is not null and s.state=v_state or v_state is null and s.state in ('source_null','suppressed','not_yet_enriched','stale','ambiguous','rejected'))
    and (v_query is null or s.entity_name ilike '%'||v_query||'%' or coalesce(s.provider_name,'') ilike '%'||v_query||'%' or s.stable_key ilike '%'||v_query||'%')
  ), numbered as (select f.*,count(*) over() total_count from filtered f), paged as (select * from numbered order by lower(entity_name),id limit v_limit offset v_offset)
  select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('entity_id',p.id,'entity_type','scholarship','entity_name',p.entity_name,'stable_key',p.stable_key,'provider_id',p.provider_id,'provider_name',p.provider_name,'country_code',p.country_code,'domain',v_domain,'state',p.state,'source_id',p.source_id,'source_label',src.label,'evidence_id',p.evidence_id,'review_id',(select q.id from workflow.review_queue q where q.entity_id=p.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review') order by q.priority desc,q.created_at limit 1),'updated_at',p.updated_at) order by lower(p.entity_name)),'[]'::jsonb),'total',coalesce(max(p.total_count),0),'limit',v_limit,'offset',v_offset,'entity_type','scholarship','domain',v_domain,'state',v_state)
  into v_result from paged p left join pipeline.sources src on src.id=p.source_id; return v_result;
 else
  raise exception 'unsupported data quality entity type: %',v_entity using errcode='22023';
 end if;
end
$$;

create or replace function security.admin_data_quality_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, auth
as $$
declare v_rank int:=0;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 select security.current_role_rank() into v_rank;
 if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
 if p_operation='data_quality_overview' then return security.data_quality_overview_impl(p_args); end if;
 if p_operation='data_quality_exceptions' then return security.data_quality_exceptions_impl(p_args); end if;
 raise exception 'unsupported data quality operation: %',p_operation using errcode='22023';
end
$$;

revoke all on function security.data_quality_course_base(text) from public,anon,authenticated;
revoke all on function security.data_quality_provider_base(text) from public,anon,authenticated;
revoke all on function security.data_quality_campus_base(text) from public,anon,authenticated;
revoke all on function security.data_quality_scholarship_base(text) from public,anon,authenticated;
revoke all on function security.data_quality_overview_impl(jsonb) from public,anon,authenticated;
revoke all on function security.data_quality_exceptions_impl(jsonb) from public,anon,authenticated;
revoke all on function security.admin_data_quality_read(text,jsonb) from public,anon;
grant execute on function security.admin_data_quality_read(text,jsonb) to authenticated,service_role;

create or replace function public.admin_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public, security
as $$
declare
  v_result jsonb;
  v_id uuid;
begin
  if p_operation='dashboard' then return security.admin_dashboard_maturity(); end if;
  if p_operation in ('provider_filters','course_filters') then return security.admin_catalogue_filter_options(p_operation,p_args); end if;
  if p_operation in ('evidence_page','evidence_filters','evidence_detail','evidence_observations','evidence_entities') then return security.admin_evidence_read(p_operation,p_args); end if;
  if p_operation='courses_page' then return security.admin_course_page_fast(p_args); end if;
  if p_operation in ('providers_page','campuses_page','scholarships_page') then return security.admin_catalogue_page(p_operation,p_args); end if;
  if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then return security.admin_insights_read(p_operation,p_args); end if;
  if p_operation='reviews_page' then return security.admin_operational_page(p_operation,p_args); end if;
  if p_operation in ('reviews','jobs','sources') then return security.admin_operations_read(p_operation,p_args); end if;
  if p_operation='attributes' then return security.admin_pim_governance_read(p_args); end if;
  if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then
    v_result:=security.admin_pipeline_ops_read(p_operation,p_args);
    return security.admin_pipeline_ops_sanitise_result(p_operation,v_result);
  end if;
  if p_operation in ('data_quality_overview','data_quality_exceptions') then return security.admin_data_quality_read(p_operation,p_args); end if;
  if p_operation='publication_overview' then return security.admin_publication_overview(); end if;
  if p_operation='provider_detail' then v_id:=nullif(p_args->>'id','')::uuid; return security.admin_provider_detail(v_id); end if;
  if p_operation='campus_detail' then v_id:=nullif(p_args->>'id','')::uuid; return security.admin_campus_detail(v_id); end if;
  v_result:=security.admin_read_impl(p_operation,p_args);
  if p_operation='course_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    return v_result || jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id)) || jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id)) || jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id)) || jsonb_build_object('state_summary',security.admin_course_state_summary(v_id));
  end if;
  if p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid; return v_result || jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id)); end if;
  return v_result;
end
$$;
