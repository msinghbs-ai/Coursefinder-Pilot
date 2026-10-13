CREATE OR REPLACE FUNCTION security.data_quality_exceptions_impl(p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'ref', 'scholarship', 'pipeline', 'workflow', 'search', 'publishing'
 SET work_mem TO '128MB'
AS $function$
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
  with scope as (
   select c.id,coalesce(c.display_title,c.canonical_title) entity_name,c.stable_key,c.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,
    co.iso_alpha2::text country_code,c.canonical_source_id,c.last_verified_at,c.updated_at,c.publication_status,c.course_code,c.course_url,c.delivery_mode,c.study_level_id,c.primary_field_id
   from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
   where (v_country is null and co.iso_alpha2 in ('AU','NZ') or v_country is not null and co.iso_alpha2=v_country)
    and (v_query is null or c.canonical_title ilike '%'||v_query||'%' or coalesce(c.display_title,'') ilike '%'||v_query||'%' or coalesce(p.display_name,p.canonical_name,'') ilike '%'||v_query||'%' or c.stable_key ilike '%'||v_query||'%' or coalesce(c.course_code,'') ilike '%'||v_query||'%')
  ), classified as (
   select c.*,
    case v_domain
     when 'identity_completeness' then case
      when exists(select 1 from workflow.review_queue q where q.entity_id=c.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review')) then 'ambiguous'
      when c.stable_key is not null and btrim(c.stable_key)<>'' and c.entity_name is not null and btrim(c.entity_name)<>'' and c.course_code is not null and btrim(c.course_code)<>'' and c.provider_id is not null then 'present' else 'source_null' end
     when 'regulatory_completeness' then case
      when exists(select 1 from workflow.review_queue q where q.entity_id=c.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review')) then 'ambiguous'
      when exists(select 1 from catalogue.course_registrations r where r.course_id=c.id and coalesce(r.status,'active')='active') then 'present' else 'source_null' end
     when 'geography_delivery' then case
      when exists(select 1 from workflow.review_queue q where q.entity_id=c.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review')) then 'ambiguous'
      when exists(select 1 from catalogue.course_campuses cc where cc.course_id=c.id) and (coalesce(nullif(btrim(c.delivery_mode),''),null) is not null or exists(select 1 from catalogue.course_campuses cc where cc.course_id=c.id and coalesce(nullif(btrim(cc.delivery_mode),''),null) is not null)) then 'present'
      when c.country_code='AU' and not exists(select 1 from catalogue.course_campuses cc where cc.course_id=c.id) then 'source_null' else 'not_yet_enriched' end
     when 'taxonomy' then case
      when exists(select 1 from workflow.review_queue q where q.entity_id=c.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review')) or exists(select 1 from catalogue.course_study_level_observations o where o.course_id=c.id and o.status='current' and lower(o.mapping_status) in ('review_required','ambiguous')) then 'ambiguous'
      when exists(select 1 from catalogue.course_study_level_observations o where o.course_id=c.id and o.status='current' and lower(o.mapping_status)='rejected') then 'rejected'
      when c.study_level_id is not null and c.primary_field_id is not null then 'present' when c.country_code='AU' then 'source_null' else 'not_yet_enriched' end
     when 'regulatory_fee' then case
      when exists(select 1 from workflow.review_queue q where q.entity_id=c.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review')) then 'ambiguous'
      when c.country_code<>'AU' then 'not_applicable'
      when exists(select 1 from catalogue.course_fees f where f.course_id=c.id and f.basis='registered_total_course' and f.fee_type='tuition' and coalesce(f.status,'active')='active' and f.amount>0) then 'present'
      when exists(select 1 from catalogue.course_fees f where f.course_id=c.id and f.basis='registered_total_course' and f.fee_type='tuition' and coalesce(f.status,'active')='active' and f.amount=0) then 'zero'
      else 'source_null' end
     when 'provider_current_fee' then case
      when exists(select 1 from workflow.review_queue q where q.entity_id=c.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review')) then 'ambiguous'
      when exists(select 1 from catalogue.course_fees f where f.course_id=c.id and f.fee_type='provider_current_tuition' and f.basis is distinct from 'registered_total_course' and coalesce(f.status,'active')='active' and f.amount>0) then 'present'
      when exists(select 1 from catalogue.course_fees f where f.course_id=c.id and f.fee_type='provider_current_tuition' and f.basis is distinct from 'registered_total_course' and coalesce(f.status,'active')='active' and f.amount=0) then 'zero'
      when exists(select 1 from catalogue.course_fees f where f.course_id=c.id and f.fee_type='provider_current_tuition' and f.basis is distinct from 'registered_total_course' and coalesce(f.status,'active')='active' and f.amount is null) then 'source_null'
      when exists(select 1 from catalogue.course_fees f where f.course_id=c.id and f.fee_type='provider_current_tuition' and f.basis is distinct from 'registered_total_course' and lower(coalesce(f.status,''))='rejected') then 'rejected'
      when exists(select 1 from catalogue.course_fees f where f.course_id=c.id and f.fee_type='provider_current_tuition' and f.basis is distinct from 'registered_total_course' and lower(coalesce(f.status,''))='suppressed') then 'suppressed'
      else 'not_yet_enriched' end
     when 'course_url' then case
      when exists(select 1 from workflow.review_queue q where q.entity_id=c.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review')) then 'ambiguous'
      when coalesce(nullif(btrim(c.course_url),''),null) is not null or exists(select 1 from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=c.id and lower(coalesce(l.status,'active'))='active') then 'present'
      when exists(select 1 from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=c.id and lower(coalesce(l.status,''))='rejected') then 'rejected'
      when exists(select 1 from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=c.id and lower(coalesce(l.status,''))='suppressed') then 'suppressed'
      else 'not_yet_enriched' end
     when 'intake' then case
      when exists(select 1 from workflow.review_queue q where q.entity_id=c.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review')) then 'ambiguous'
      when exists(select 1 from catalogue.course_intakes i where i.course_id=c.id and lower(coalesce(i.status,'active'))='active') then 'present'
      when exists(select 1 from catalogue.course_intakes i where i.course_id=c.id and lower(coalesce(i.status,''))='rejected') then 'rejected'
      when exists(select 1 from catalogue.course_intakes i where i.course_id=c.id and lower(coalesce(i.status,''))='suppressed') then 'suppressed'
      else 'not_yet_enriched' end
     when 'english_requirement' then case
      when exists(select 1 from workflow.review_queue q where q.entity_id=c.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review')) then 'ambiguous'
      when exists(select 1 from catalogue.course_english_requirements e where e.course_id=c.id and lower(coalesce(e.status,'active'))='active') then 'present'
      when exists(select 1 from catalogue.course_english_requirements e where e.course_id=c.id and lower(coalesce(e.status,''))='rejected') then 'rejected'
      when exists(select 1 from catalogue.course_english_requirements e where e.course_id=c.id and lower(coalesce(e.status,''))='suppressed') then 'suppressed'
      else 'not_yet_enriched' end
     when 'scholarship' then case
      when exists(select 1 from workflow.review_queue q where q.entity_id=c.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review')) then 'ambiguous'
      when exists(select 1 from scholarship.scopes s where coalesce(s.include_exclude,'include')='include' and (s.course_id=c.id or (s.scope_type='provider' and s.provider_id=c.provider_id))) then 'present'
      when exists(select 1 from scholarship.scopes s where coalesce(s.include_exclude,'include')='exclude' and (s.course_id=c.id or (s.scope_type='provider' and s.provider_id=c.provider_id))) then 'not_applicable'
      else 'not_yet_enriched' end
     when 'evidence' then case
      when exists(select 1 from workflow.review_queue q where q.entity_id=c.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review')) then 'ambiguous'
      when exists(select 1 from pipeline.evidence_entity_links el where el.entity_type='course' and el.entity_id=c.id) then 'present' else 'not_yet_enriched' end
     when 'verification_freshness' then case
      when exists(select 1 from workflow.review_queue q where q.entity_id=c.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review')) then 'ambiguous'
      when c.last_verified_at is null or c.last_verified_at<now()-interval '180 days' then 'stale' else 'present' end
     when 'search_admission' then case
      when exists(select 1 from workflow.review_queue q where q.entity_id=c.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review')) then 'ambiguous'
      when exists(select 1 from search.course_documents d where d.course_id=c.id) then 'present' else 'not_yet_enriched' end
     when 'publication_readiness' then case
      when exists(select 1 from workflow.review_queue q where q.entity_id=c.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review')) then 'ambiguous'
      when (select count(distinct lower(es.publication_status)) from publishing.entity_states es where es.entity_id=c.id)>1 then 'ambiguous'
      when lower(coalesce(c.publication_status,''))='rejected' or exists(select 1 from publishing.entity_states es where es.entity_id=c.id and lower(es.publication_status)='rejected') then 'rejected'
      when lower(coalesce(c.publication_status,''))='published' or exists(select 1 from publishing.entity_states es where es.entity_id=c.id and lower(es.publication_status)='published') then 'present'
      else 'not_yet_enriched' end
     else null end state
   from scope c
  ), filtered as (
   select c.* from classified c where c.state is not null
    and ((v_state is not null and c.state=v_state) or (v_state is null and c.state in ('source_null','suppressed','not_yet_enriched','stale','ambiguous','rejected')))
  ), numbered as (select f.*,count(*) over() total_count from filtered f), paged0 as (
   select * from numbered order by case state when 'rejected' then 1 when 'ambiguous' then 2 when 'source_null' then 3 when 'suppressed' then 4 when 'stale' then 5 else 6 end,lower(entity_name),id limit v_limit offset v_offset
  ), paged as (
   select p.*,
    coalesce(
      case v_domain
       when 'regulatory_fee' then (select f.source_id from catalogue.course_fees f where f.course_id=p.id and f.basis='registered_total_course' and f.fee_type='tuition' and f.source_id is not null order by f.source_snapshot_at desc nulls last,f.created_at desc limit 1)
       when 'provider_current_fee' then (select f.source_id from catalogue.course_fees f where f.course_id=p.id and f.fee_type='provider_current_tuition' and f.basis is distinct from 'registered_total_course' and f.source_id is not null order by f.source_snapshot_at desc nulls last,f.created_at desc limit 1)
       when 'course_url' then (select l.source_id from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=p.id and l.source_id is not null order by l.is_primary desc,l.updated_at desc limit 1)
       when 'intake' then (select i.source_id from catalogue.course_intakes i where i.course_id=p.id and i.source_id is not null order by i.intake_year desc nulls last,i.start_date desc nulls last limit 1)
       when 'english_requirement' then (select e.source_id from catalogue.course_english_requirements e where e.course_id=p.id and e.source_id is not null order by e.last_verified_at desc nulls last limit 1)
       else null end,
      p.canonical_source_id,
      (select r.source_id from catalogue.course_registrations r where r.course_id=p.id and r.source_id is not null order by r.valid_from desc nulls last limit 1)
    ) domain_source_id,
    coalesce(
      case v_domain
       when 'regulatory_fee' then (select f.evidence_id from catalogue.course_fees f where f.course_id=p.id and f.basis='registered_total_course' and f.fee_type='tuition' and f.evidence_id is not null order by f.source_snapshot_at desc nulls last,f.created_at desc limit 1)
       when 'provider_current_fee' then (select f.evidence_id from catalogue.course_fees f where f.course_id=p.id and f.fee_type='provider_current_tuition' and f.basis is distinct from 'registered_total_course' and f.evidence_id is not null order by f.source_snapshot_at desc nulls last,f.created_at desc limit 1)
       when 'course_url' then (select l.evidence_id from catalogue.course_links l where l.link_type = 'official_course' and l.course_id=p.id and l.evidence_id is not null order by l.is_primary desc,l.updated_at desc limit 1)
       when 'intake' then (select i.evidence_id from catalogue.course_intakes i where i.course_id=p.id and i.evidence_id is not null order by i.intake_year desc nulls last,i.start_date desc nulls last limit 1)
       when 'english_requirement' then (select e.evidence_id from catalogue.course_english_requirements e where e.course_id=p.id and e.evidence_id is not null order by e.last_verified_at desc nulls last limit 1)
       else null end,
      (select el.evidence_id from pipeline.evidence_entity_links el where el.entity_type='course' and el.entity_id=p.id order by el.updated_at desc limit 1),
      (select r.evidence_id from catalogue.course_registrations r where r.course_id=p.id and r.evidence_id is not null order by r.valid_from desc nulls last limit 1)
    ) domain_evidence_id
   from paged0 p
  )
  select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object(
    'entity_id',p.id,'entity_type','course','entity_name',p.entity_name,'stable_key',p.stable_key,'provider_id',p.provider_id,'provider_name',p.provider_name,'country_code',p.country_code,
    'domain',v_domain,'state',p.state,'source_id',p.domain_source_id,'source_label',src.label,'evidence_id',p.domain_evidence_id,
    'review_id',(select q.id from workflow.review_queue q where q.entity_id=p.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review') order by q.priority desc,q.created_at limit 1),
    'last_verified_at',p.last_verified_at,'updated_at',p.updated_at,'context',jsonb_build_object('canonical_publication',p.publication_status)
   ) order by lower(p.entity_name)),'[]'::jsonb),'total',coalesce(max(p.total_count),0),'limit',v_limit,'offset',v_offset,'entity_type','course','domain',v_domain,'state',v_state)
  into v_result from paged p left join pipeline.sources src on src.id=p.domain_source_id;
  return v_result;
 elsif v_entity='provider' then
  with classified as (
   select p.*,case v_domain when 'identity_completeness' then case when v_domain=any(p.review_domains) then 'ambiguous' when p.identity_ok then 'present' else 'source_null' end when 'regulatory_completeness' then case when v_domain=any(p.review_domains) then 'ambiguous' when p.registration_count>0 then 'present' else 'source_null' end when 'geography_delivery' then case when v_domain=any(p.review_domains) then 'ambiguous' when p.geography_present then 'present' else 'not_yet_enriched' end when 'evidence' then case when v_domain=any(p.review_domains) then 'ambiguous' when p.evidence_count>0 then 'present' else 'not_yet_enriched' end when 'verification_freshness' then case when v_domain=any(p.review_domains) then 'ambiguous' when p.last_verified_at is null or p.last_verified_at<now()-interval '180 days' then 'stale' else 'present' end when 'publication_readiness' then case when v_domain=any(p.review_domains) then 'ambiguous' when p.channel_rejected_count>0 or lower(coalesce(p.publication_status,''))='rejected' then 'rejected' when p.channel_distinct_status_count>1 then 'ambiguous' when p.channel_published_count>0 or lower(coalesce(p.publication_status,''))='published' then 'present' else 'not_yet_enriched' end else null end state from security.data_quality_provider_base(v_country) p
  ), filtered as (select p.* from classified p where p.state is not null and ((v_state is not null and p.state=v_state) or (v_state is null and p.state in ('source_null','suppressed','not_yet_enriched','stale','ambiguous','rejected'))) and (v_query is null or p.entity_name ilike '%'||v_query||'%' or p.stable_key ilike '%'||v_query||'%')), numbered as (select f.*,count(*) over() total_count from filtered f), paged as (select * from numbered order by lower(entity_name),id limit v_limit offset v_offset)
  select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('entity_id',p.id,'entity_type','provider','entity_name',p.entity_name,'stable_key',p.stable_key,'country_code',p.country_code,'domain',v_domain,'state',p.state,'source_id',p.source_id,'source_label',src.label,'evidence_id',p.evidence_id,'review_id',(select q.id from workflow.review_queue q where q.entity_id=p.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review') order by q.priority desc,q.created_at limit 1),'last_verified_at',p.last_verified_at,'updated_at',p.updated_at) order by lower(p.entity_name)),'[]'::jsonb),'total',coalesce(max(p.total_count),0),'limit',v_limit,'offset',v_offset,'entity_type','provider','domain',v_domain,'state',v_state) into v_result from paged p left join pipeline.sources src on src.id=p.source_id; return v_result;
 elsif v_entity='campus' then
  with classified as (
   select c.*,case v_domain when 'identity_completeness' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.identity_ok then 'present' else 'source_null' end when 'geography_delivery' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.geography_present then 'present' else 'source_null' end when 'evidence' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.evidence_count>0 then 'present' else 'not_yet_enriched' end when 'verification_freshness' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.last_verified_at is null or c.last_verified_at<now()-interval '180 days' then 'stale' else 'present' end when 'publication_readiness' then case when v_domain=any(c.review_domains) then 'ambiguous' when c.channel_rejected_count>0 or lower(coalesce(c.publication_status,''))='rejected' then 'rejected' when c.channel_distinct_status_count>1 then 'ambiguous' when c.channel_published_count>0 or lower(coalesce(c.publication_status,''))='published' then 'present' else 'not_yet_enriched' end else null end state from security.data_quality_campus_base(v_country) c
  ), filtered as (select c.* from classified c where c.state is not null and ((v_state is not null and c.state=v_state) or (v_state is null and c.state in ('source_null','suppressed','not_yet_enriched','stale','ambiguous','rejected'))) and (v_query is null or c.entity_name ilike '%'||v_query||'%' or c.provider_name ilike '%'||v_query||'%' or c.stable_key ilike '%'||v_query||'%')), numbered as (select f.*,count(*) over() total_count from filtered f), paged as (select * from numbered order by lower(entity_name),id limit v_limit offset v_offset)
  select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('entity_id',p.id,'entity_type','campus','entity_name',p.entity_name,'stable_key',p.stable_key,'provider_id',p.provider_id,'provider_name',p.provider_name,'country_code',p.country_code,'domain',v_domain,'state',p.state,'source_id',p.source_id,'source_label',src.label,'evidence_id',p.evidence_id,'review_id',(select q.id from workflow.review_queue q where q.entity_id=p.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review') order by q.priority desc,q.created_at limit 1),'last_verified_at',p.last_verified_at,'updated_at',p.updated_at) order by lower(p.entity_name)),'[]'::jsonb),'total',coalesce(max(p.total_count),0),'limit',v_limit,'offset',v_offset,'entity_type','campus','domain',v_domain,'state',v_state) into v_result from paged p left join pipeline.sources src on src.id=p.source_id; return v_result;
 elsif v_entity='scholarship' then
  with classified as (
   select s.*,case v_domain when 'identity_completeness' then case when v_domain=any(s.review_domains) then 'ambiguous' when s.identity_ok then 'present' else 'source_null' end when 'scholarship' then case when v_domain=any(s.review_domains) then 'ambiguous' when s.semantic_present then 'present' else 'not_yet_enriched' end when 'evidence' then case when v_domain=any(s.review_domains) then 'ambiguous' when s.evidence_count>0 then 'present' else 'not_yet_enriched' end when 'verification_freshness' then case when v_domain=any(s.review_domains) then 'ambiguous' else 'not_yet_enriched' end when 'publication_readiness' then case when v_domain=any(s.review_domains) then 'ambiguous' when s.channel_rejected_count>0 or lower(coalesce(s.publication_status,''))='rejected' then 'rejected' when s.channel_distinct_status_count>1 then 'ambiguous' when s.channel_published_count>0 or lower(coalesce(s.publication_status,''))='published' then 'present' else 'not_yet_enriched' end else null end state from security.data_quality_scholarship_base(v_country) s
  ), filtered as (select s.* from classified s where s.state is not null and ((v_state is not null and s.state=v_state) or (v_state is null and s.state in ('source_null','suppressed','not_yet_enriched','stale','ambiguous','rejected'))) and (v_query is null or s.entity_name ilike '%'||v_query||'%' or coalesce(s.provider_name,'') ilike '%'||v_query||'%' or s.stable_key ilike '%'||v_query||'%')), numbered as (select f.*,count(*) over() total_count from filtered f), paged as (select * from numbered order by lower(entity_name),id limit v_limit offset v_offset)
  select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('entity_id',p.id,'entity_type','scholarship','entity_name',p.entity_name,'stable_key',p.stable_key,'provider_id',p.provider_id,'provider_name',p.provider_name,'country_code',p.country_code,'domain',v_domain,'state',p.state,'source_id',p.source_id,'source_label',src.label,'evidence_id',p.evidence_id,'review_id',(select q.id from workflow.review_queue q where q.entity_id=p.id and lower(q.domain)=v_domain and q.status in ('open','queued','pending','in_review') order by q.priority desc,q.created_at limit 1),'updated_at',p.updated_at) order by lower(p.entity_name)),'[]'::jsonb),'total',coalesce(max(p.total_count),0),'limit',v_limit,'offset',v_offset,'entity_type','scholarship','domain',v_domain,'state',v_state) into v_result from paged p left join pipeline.sources src on src.id=p.source_id; return v_result;
 else raise exception 'unsupported data quality entity type: %',v_entity using errcode='22023'; end if;
end
$function$
