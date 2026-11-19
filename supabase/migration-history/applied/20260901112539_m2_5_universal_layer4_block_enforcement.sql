-- CF-CHG-20260901-057
-- M2.5 universal Layer 4 block enforcement.
-- Server-side enforcement only. No canonical data deletion/rewrite is performed merely to represent block state.

begin;

create or replace view security.layer4_active_blocks
with (security_barrier=true)
as
select id,entity_type,entity_id,block_scope,reason_code,comment,actor_id,actor_email,
       expires_at,review_at,approval_context,created_at
from (
  select distinct on(entity_type,entity_id,block_scope)
    d.id,d.entity_type,d.entity_id,d.block_scope,d.event_type,d.reason_code,d.comment,
    d.actor_id,d.actor_email,d.expires_at,d.review_at,d.approval_context,d.created_at
  from pipeline.layer4_block_decisions d
  order by d.entity_type,d.entity_id,d.block_scope,d.created_at desc,d.id desc
) x
where event_type='block'
  and (expires_at is null or expires_at>now());

revoke all on security.layer4_active_blocks from public,anon,authenticated;
grant select on security.layer4_active_blocks to service_role;

create or replace view security.layer4_search_blocked_providers
with (security_barrier=true)
as
select entity_id as provider_id
from security.layer4_active_blocks
where block_scope='search' and entity_type='provider';

create or replace view security.layer4_search_blocked_courses
with (security_barrier=true)
as
select entity_id as course_id
from security.layer4_active_blocks
where block_scope='search' and entity_type='course'
union
select c.id
from security.layer4_active_blocks b
join catalogue.courses c on c.provider_id=b.entity_id
where b.block_scope='search' and b.entity_type='provider';

create or replace view security.layer4_search_blocked_campuses
with (security_barrier=true)
as
select entity_id as campus_id
from security.layer4_active_blocks
where block_scope='search' and entity_type='campus'
union
select c.id
from security.layer4_active_blocks b
join catalogue.campuses c on c.provider_id=b.entity_id
where b.block_scope='search' and b.entity_type='provider';

create or replace view security.layer4_search_blocked_scholarships
with (security_barrier=true)
as
select entity_id as scholarship_id
from security.layer4_active_blocks
where block_scope='search' and entity_type='scholarship'
union
select s.id
from security.layer4_active_blocks b
join scholarship.scholarships s on s.provider_id=b.entity_id
where b.block_scope='search' and b.entity_type='provider';

revoke all on security.layer4_search_blocked_providers,
              security.layer4_search_blocked_courses,
              security.layer4_search_blocked_campuses,
              security.layer4_search_blocked_scholarships
from public,anon,authenticated;
grant select on security.layer4_search_blocked_providers,
                security.layer4_search_blocked_courses,
                security.layer4_search_blocked_campuses,
                security.layer4_search_blocked_scholarships
to service_role;

create or replace function security.layer4_entity_or_parent_blocked(
  p_entity_type text,p_entity_id uuid,p_block_scope text
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','catalogue','scholarship','pipeline'
as $$
declare v_type text:=lower(btrim(coalesce(p_entity_type,''))); v_provider uuid;
begin
  if p_block_scope not in ('operational','publication','search','data_quality_quarantine') then
    raise exception 'invalid block scope' using errcode='22023';
  end if;
  if exists(
    select 1 from security.layer4_active_blocks b
    where b.entity_type=v_type and b.entity_id=p_entity_id and b.block_scope=p_block_scope
  ) then return true; end if;

  if v_type='course' then
    select provider_id into v_provider from catalogue.courses where id=p_entity_id;
  elsif v_type='campus' then
    select provider_id into v_provider from catalogue.campuses where id=p_entity_id;
  elsif v_type='scholarship' then
    select provider_id into v_provider from scholarship.scholarships where id=p_entity_id;
  elsif v_type='provider_contact' then
    select provider_id into v_provider from pipeline.provider_contact_observations where id=p_entity_id;
  end if;

  return v_provider is not null and exists(
    select 1 from security.layer4_active_blocks b
    where b.entity_type='provider' and b.entity_id=v_provider and b.block_scope=p_block_scope
  );
end $$;

revoke all on function security.layer4_entity_or_parent_blocked(text,uuid,text) from public,anon,authenticated;
grant execute on function security.layer4_entity_or_parent_blocked(text,uuid,text) to service_role;

create or replace function security.data_quality_quarantine_impl(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','catalogue','scholarship','pipeline','ref'
as $$
declare
  v_entity text:=lower(nullif(btrim(coalesce(p_args->>'entity_type','')),''));
  v_country text:=upper(nullif(btrim(coalesce(p_args->>'country_code','')),''));
  v_query text:=nullif(btrim(coalesce(p_args->>'query','')),'');
  v_limit int:=least(greatest(coalesce(nullif(p_args->>'limit','')::int,50),1),200);
  v_offset int:=greatest(coalesce(nullif(p_args->>'offset','')::int,0),0);
  v_result jsonb;
begin
  if v_entity is not null and v_entity not in ('provider','course','campus','scholarship','provider_contact') then
    raise exception 'unsupported quarantine entity type' using errcode='22023';
  end if;

  with entities as (
    select 'provider'::text entity_type,p.id entity_id,coalesce(p.display_name,p.canonical_name) entity_name,
           p.id provider_id,coalesce(p.display_name,p.canonical_name) provider_name,co.iso_alpha2::text country_code
    from catalogue.providers p join ref.countries co on co.id=p.country_id
    union all
    select 'course',c.id,coalesce(c.display_title,c.canonical_title),p.id,coalesce(p.display_name,p.canonical_name),co.iso_alpha2::text
    from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
    union all
    select 'campus',ca.id,ca.name,p.id,coalesce(p.display_name,p.canonical_name),co.iso_alpha2::text
    from catalogue.campuses ca join catalogue.providers p on p.id=ca.provider_id join ref.countries co on co.id=p.country_id
    union all
    select 'scholarship',s.id,s.name,p.id,coalesce(p.display_name,p.canonical_name),co.iso_alpha2::text
    from scholarship.scholarships s left join catalogue.providers p on p.id=s.provider_id left join ref.countries co on co.id=p.country_id
    union all
    select 'provider_contact',o.id,coalesce(nullif(btrim(o.full_name),''),nullif(btrim(o.job_title),''),'Provider contact'),p.id,
           coalesce(p.display_name,p.canonical_name),co.iso_alpha2::text
    from pipeline.provider_contact_observations o join catalogue.providers p on p.id=o.provider_id join ref.countries co on co.id=p.country_id
  ), effective as (
    select e.*,
      db.id direct_decision_id,db.reason_code direct_reason_code,db.comment direct_comment,db.review_at direct_review_at,db.expires_at direct_expires_at,db.created_at direct_created_at,
      pb.id provider_decision_id,pb.reason_code provider_reason_code,pb.comment provider_comment,pb.review_at provider_review_at,pb.expires_at provider_expires_at,pb.created_at provider_created_at
    from entities e
    left join security.layer4_active_blocks db
      on db.entity_type=e.entity_type and db.entity_id=e.entity_id and db.block_scope='data_quality_quarantine'
    left join security.layer4_active_blocks pb
      on e.entity_type<>'provider' and e.provider_id is not null
     and pb.entity_type='provider' and pb.entity_id=e.provider_id and pb.block_scope='data_quality_quarantine'
    where db.id is not null or pb.id is not null
  ), filtered as (
    select *,count(*) over() total_count
    from effective
    where (v_entity is null or entity_type=v_entity)
      and (v_country is null or country_code=v_country)
      and (v_query is null or entity_name ilike '%'||v_query||'%' or coalesce(provider_name,'') ilike '%'||v_query||'%')
  ), paged as (
    select * from filtered
    order by entity_type,lower(entity_name),entity_id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'entity_type',entity_type,'entity_id',entity_id,'entity_name',entity_name,
      'provider_id',provider_id,'provider_name',provider_name,'country_code',country_code,
      'direct_quarantine',direct_decision_id is not null,
      'inherited_provider_quarantine',provider_decision_id is not null,
      'effective_decision_id',coalesce(direct_decision_id,provider_decision_id),
      'reason_code',coalesce(direct_reason_code,provider_reason_code),
      'comment',coalesce(direct_comment,provider_comment),
      'review_at',coalesce(direct_review_at,provider_review_at),
      'expires_at',coalesce(direct_expires_at,provider_expires_at),
      'created_at',coalesce(direct_created_at,provider_created_at)
    ) order by entity_type,lower(entity_name),entity_id),'[]'::jsonb),
    'total',coalesce(max(total_count),0),
    'limit',v_limit,'offset',v_offset,
    'entity_type',v_entity,'country_code',v_country,
    'scope','data_quality_quarantine'
  ) into v_result
  from paged;

  return coalesce(v_result,jsonb_build_object(
    'items','[]'::jsonb,'total',0,'limit',v_limit,'offset',v_offset,
    'entity_type',v_entity,'country_code',v_country,'scope','data_quality_quarantine'
  ));
end $$;

revoke all on function security.data_quality_quarantine_impl(jsonb) from public,anon,authenticated;
grant execute on function security.data_quality_quarantine_impl(jsonb) to service_role;


-- api.courses_list(uuid,character,text,text,integer,integer)
CREATE OR REPLACE FUNCTION api.courses_list(p_provider_id uuid DEFAULT NULL::uuid, p_country character DEFAULT NULL::bpchar, p_level_code text DEFAULT NULL::text, p_publication text DEFAULT NULL::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, stable_key text, provider_id uuid, provider_name text, canonical_title text, course_code text, level_code text, publication_status text, completeness_score numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'catalogue', 'ref', 'publishing', 'security'
AS $function$
select c.id,c.stable_key,c.provider_id,coalesce(p.display_name,p.canonical_name),c.canonical_title,c.course_code,sl.code,c.publication_status,max(es.completeness_score)
from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
left join ref.study_levels sl on sl.id=c.study_level_id left join publishing.entity_states es on es.entity_id=c.id
where security.current_role_rank()>=1
  and not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=c.id)
  and (p_provider_id is null or c.provider_id=p_provider_id)
  and (p_country is null or co.iso_alpha2=p_country)
  and (p_level_code is null or sl.code=p_level_code)
  and (p_publication is null or c.publication_status=p_publication)
group by c.id,p.canonical_name,p.display_name,sl.code
order by c.canonical_title
limit least(greatest(coalesce(p_limit,100),1),500) offset greatest(coalesce(p_offset,0),0)
$function$
;

-- api.providers_list(character,integer,integer)
CREATE OR REPLACE FUNCTION api.providers_list(p_country character DEFAULT NULL::bpchar, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, stable_key text, canonical_name text, display_name text, country_code character, publication_status text, course_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'catalogue', 'ref', 'security'
AS $function$
select p.id,p.stable_key,p.canonical_name,p.display_name,c.iso_alpha2,p.publication_status,count(cr.id)::bigint
from catalogue.providers p join ref.countries c on c.id=p.country_id left join catalogue.courses cr on cr.provider_id=p.id and not exists (select 1 from security.layer4_search_blocked_courses cf_course_block where cf_course_block.course_id=cr.id)
where security.current_role_rank()>=1 and not exists (select 1 from security.layer4_search_blocked_providers cf_block where cf_block.provider_id=p.id) and (p_country is null or c.iso_alpha2=p_country)
group by p.id,c.iso_alpha2
order by coalesce(p.display_name,p.canonical_name)
limit least(greatest(coalesce(p_limit,100),1),500) offset greatest(coalesce(p_offset,0),0)
$function$
;

-- api.search_courses(text,character,text,boolean,integer)
CREATE OR REPLACE FUNCTION api.search_courses(p_query text, p_country character DEFAULT NULL::bpchar, p_level_code text DEFAULT NULL::text, p_has_scholarship boolean DEFAULT NULL::boolean, p_limit integer DEFAULT 20)
 RETURNS TABLE(course_id uuid, provider_name text, course_title text, level_code text, rank real, has_fee boolean, has_intake boolean, has_english boolean, has_scholarship boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'search', 'ref', 'security'
AS $function$
select d.course_id,d.provider_name,d.course_title,sl.code,
       ts_rank_cd(d.search_tsv,websearch_to_tsquery('english',coalesce(p_query,'')))::real,
       d.has_fee,d.has_intake,d.has_english,d.has_scholarship
from search.course_documents d left join ref.study_levels sl on sl.id=d.study_level_id join ref.countries co on co.id=d.country_id
where security.current_role_rank()>=1 and not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id) and d.publication_status in ('published','internal')
 and (p_country is null or co.iso_alpha2=p_country)
 and (p_level_code is null or sl.code=p_level_code)
 and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
 and (coalesce(trim(p_query),'')='' or d.search_tsv @@ websearch_to_tsquery('english',p_query))
order by ts_rank_cd(d.search_tsv,websearch_to_tsquery('english',coalesce(p_query,''))) desc,d.course_title
limit least(greatest(coalesce(p_limit,20),1),50)
$function$
;

-- api.vector_candidates(vector,text,character,text,integer)
CREATE OR REPLACE FUNCTION api.vector_candidates(p_embedding vector, p_profile_code text, p_country character DEFAULT NULL::bpchar, p_level_code text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS TABLE(course_id uuid, distance double precision)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'search', 'ref', 'security', 'extensions'
AS $function$
select e.course_id,(e.embedding<=>p_embedding)::double precision
from search.course_embeddings e join search.profiles sp on sp.id=e.profile_id join search.course_documents d on d.course_id=e.course_id
join ref.countries co on co.id=d.country_id left join ref.study_levels sl on sl.id=d.study_level_id
where security.current_role_rank()>=1 and not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id) and sp.code=p_profile_code and (p_country is null or co.iso_alpha2=p_country) and (p_level_code is null or sl.code=p_level_code)
order by e.embedding<=>p_embedding limit least(greatest(coalesce(p_limit,50),1),100)
$function$
;

-- api.website_course_lookup_preview_v1(text)
CREATE OR REPLACE FUNCTION api.website_course_lookup_preview_v1(p_identifier text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'search', 'pg_catalog'
AS $function$
with hit as (
  select d.*, 'exact_course_code'::text as match_type, 0 as match_priority
  from search.course_documents d
  where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
    and nullif(trim(p_identifier),'') is not null
    and lower(d.course_code)=lower(trim(p_identifier))
  union all
  select d.*, 'exact_course_id'::text as match_type, 1 as match_priority
  from search.course_documents d
  where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
    and nullif(trim(p_identifier),'') is not null
    and lower(d.course_stable_key)=lower(trim(p_identifier))
), chosen as (
  select * from hit order by match_priority,course_stable_key limit 1
), state as (
  select generation,content_hash from search.projection_state where projection_code='courses'
)
select jsonb_build_object(
 'contract_version','website-course-lookup-preview-v1','boundary','server-side-showcase-only',
 'meta',jsonb_build_object('mode','exact','projection_version','course-v3','projection_generation',(select generation from state),'projection_hash',(select content_hash from state),'publication_authority','not_granted'),
 'item',(select jsonb_build_object(
   'course_id',course_stable_key,'title',course_title,'course_code',course_code,
   'provider',jsonb_build_object('provider_id',provider_stable_key,'name',provider_name),
   'country',country_code,'study_level',study_level_code,
   'field',case when primary_field_code is null then null else jsonb_build_object('code',primary_field_code,'name',primary_field_name) end,
   'locations',to_jsonb(subdivision_codes),'delivery_modes',to_jsonb(delivery_modes),
   'regulatory_tuition',jsonb_build_object('state',regulatory_tuition_state,'amount',regulatory_tuition_amount,'currency',trim(regulatory_tuition_currency),'basis',regulatory_tuition_basis),
   'provider_current_tuition',jsonb_build_object('has_value',has_provider_current_tuition,'annual_amount',provider_annual_tuition_amount,'annual_currency',trim(provider_annual_tuition_currency),'options',provider_tuition_options),
   'official_course_url',official_course_url,'intakes',intake_options,'english_requirements',english_requirement_options,'scholarships',scholarship_options,
   'visibility',jsonb_build_object('publication_status',publication_status),
   'freshness',jsonb_build_object('source_updated_at',source_updated_at,'generated_at',generated_at),
   'match',jsonb_build_object('mode',match_type,'keyword_score',1000)
 ) from chosen)
);
$function$
;

-- api.website_course_search_preview_v1(text,text[],text[],text,text[],text[],text[],text[],numeric,numeric,boolean,boolean,boolean,text,integer,integer)
CREATE OR REPLACE FUNCTION api.website_course_search_preview_v1(p_query text DEFAULT NULL::text, p_country_codes text[] DEFAULT NULL::text[], p_provider_keys text[] DEFAULT NULL::text[], p_provider_name text DEFAULT NULL::text, p_subdivision_codes text[] DEFAULT NULL::text[], p_level_codes text[] DEFAULT NULL::text[], p_field_codes text[] DEFAULT NULL::text[], p_delivery_modes text[] DEFAULT NULL::text[], p_provider_annual_tuition_min numeric DEFAULT NULL::numeric, p_provider_annual_tuition_max numeric DEFAULT NULL::numeric, p_has_intake boolean DEFAULT NULL::boolean, p_has_english boolean DEFAULT NULL::boolean, p_has_scholarship boolean DEFAULT NULL::boolean, p_sort text DEFAULT 'relevance'::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'search', 'pg_catalog'
AS $function$
with params as (
 select greatest(1,least(coalesce(p_limit,20),50)) lim,
        greatest(coalesce(p_offset,0),0) off,
        nullif(trim(coalesce(p_query,'')),'') q,
        case when nullif(trim(coalesce(p_query,'')),'') is null then null else websearch_to_tsquery('english',trim(p_query)) end tsq,
        case when p_sort in ('relevance','title','provider_annual_tuition_asc','provider_annual_tuition_desc','earliest_intake') then p_sort else 'relevance' end sort_code
), ranked as (
 select d.*,ts_rank_cd(d.search_tsv,(select tsq from params))::real score
 from search.course_documents d
 where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
    and (select q from params) is not null
   and d.search_tsv @@ (select tsq from params)
   and (p_country_codes is null or d.country_code=any(p_country_codes))
   and (p_provider_keys is null or d.provider_stable_key=any(p_provider_keys))
   and (p_provider_name is null or d.provider_name ilike '%'||trim(p_provider_name)||'%')
   and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
   and (p_level_codes is null or d.study_level_code=any(p_level_codes))
   and (p_field_codes is null or d.primary_field_code=any(p_field_codes))
   and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
   and (p_provider_annual_tuition_min is null or d.provider_annual_tuition_amount>=p_provider_annual_tuition_min)
   and (p_provider_annual_tuition_max is null or d.provider_annual_tuition_amount<=p_provider_annual_tuition_max)
   and (p_has_intake is null or d.has_intake=p_has_intake)
   and (p_has_english is null or d.has_english=p_has_english)
   and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
 union all
 select d.*,0::real score
 from search.course_documents d
 where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
    and (select q from params) is null
   and (p_country_codes is null or d.country_code=any(p_country_codes))
   and (p_provider_keys is null or d.provider_stable_key=any(p_provider_keys))
   and (p_provider_name is null or d.provider_name ilike '%'||trim(p_provider_name)||'%')
   and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
   and (p_level_codes is null or d.study_level_code=any(p_level_codes))
   and (p_field_codes is null or d.primary_field_code=any(p_field_codes))
   and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
   and (p_provider_annual_tuition_min is null or d.provider_annual_tuition_amount>=p_provider_annual_tuition_min)
   and (p_provider_annual_tuition_max is null or d.provider_annual_tuition_amount<=p_provider_annual_tuition_max)
   and (p_has_intake is null or d.has_intake=p_has_intake)
   and (p_has_english is null or d.has_english=p_has_english)
   and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
), paged as (
 select * from ranked
 order by case when (select sort_code from params)='relevance' then score end desc,
          case when (select sort_code from params)='title' then course_title end asc,
          case when (select sort_code from params)='provider_annual_tuition_asc' then provider_annual_tuition_amount end asc nulls last,
          case when (select sort_code from params)='provider_annual_tuition_desc' then provider_annual_tuition_amount end desc nulls last,
          case when (select sort_code from params)='earliest_intake' then earliest_intake_date end asc nulls last,
          course_title,course_stable_key
 limit (select lim from params) offset (select off from params)
), state as (select generation,content_hash from search.projection_state where projection_code='courses')
select jsonb_build_object(
 'contract_version','website-course-search-preview-v1','boundary','server-side-showcase-only',
 'meta',jsonb_build_object('mode','deterministic_fts','limit',(select lim from params),'offset',(select off from params),'projection_version','course-v3','projection_generation',(select generation from state),'projection_hash',(select content_hash from state),'sort',(select sort_code from params),'publication_authority','not_granted'),
 'items',coalesce(jsonb_agg(jsonb_build_object(
   'course_id',course_stable_key,'title',course_title,'course_code',course_code,
   'provider',jsonb_build_object('provider_id',provider_stable_key,'name',provider_name),
   'country',country_code,'study_level',study_level_code,
   'field',case when primary_field_code is null then null else jsonb_build_object('code',primary_field_code,'name',primary_field_name) end,
   'locations',to_jsonb(subdivision_codes),'delivery_modes',to_jsonb(delivery_modes),
   'regulatory_tuition',jsonb_build_object('state',regulatory_tuition_state,'amount',regulatory_tuition_amount,'currency',trim(regulatory_tuition_currency),'basis',regulatory_tuition_basis),
   'provider_current_tuition',jsonb_build_object('has_value',has_provider_current_tuition,'annual_amount',provider_annual_tuition_amount,'annual_currency',trim(provider_annual_tuition_currency),'options',provider_tuition_options),
   'official_course_url',official_course_url,'intakes',intake_options,'english_requirements',english_requirement_options,'scholarships',scholarship_options,
   'visibility',jsonb_build_object('publication_status',publication_status),
   'freshness',jsonb_build_object('source_updated_at',source_updated_at,'generated_at',generated_at),
   'match',jsonb_build_object('mode',case when (select q from params) is null then 'filter' else 'fts' end,'keyword_score',score)
 ) order by case when (select sort_code from params)='relevance' then score end desc,
            case when (select sort_code from params)='title' then course_title end asc,
            case when (select sort_code from params)='provider_annual_tuition_asc' then provider_annual_tuition_amount end asc nulls last,
            case when (select sort_code from params)='provider_annual_tuition_desc' then provider_annual_tuition_amount end desc nulls last,
            case when (select sort_code from params)='earliest_intake' then earliest_intake_date end asc nulls last,
            course_title,course_stable_key),'[]'::jsonb)
) from paged;
$function$
;

-- api.website_course_search_v1(text,text[],text[],text[],text[],text[],boolean,boolean,integer,integer)
CREATE OR REPLACE FUNCTION api.website_course_search_v1(p_query text DEFAULT NULL::text, p_country_codes text[] DEFAULT NULL::text[], p_subdivision_codes text[] DEFAULT NULL::text[], p_level_codes text[] DEFAULT NULL::text[], p_field_codes text[] DEFAULT NULL::text[], p_delivery_modes text[] DEFAULT NULL::text[], p_has_fee boolean DEFAULT NULL::boolean, p_has_scholarship boolean DEFAULT NULL::boolean, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'search'
AS $function$
with params as (
  select greatest(1,least(coalesce(p_limit,20),50)) as lim,
         greatest(coalesce(p_offset,0),0) as off,
         websearch_to_tsquery('english',coalesce(nullif(trim(p_query),''),'')) as tsq
), ranked as (
  select d.*,
    case when coalesce(trim(p_query),'')='' then 0::real else ts_rank_cd(d.search_tsv,(select tsq from params))::real end as score
  from search.course_documents d
  where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
    and d.publication_status='published'
    and (p_country_codes is null or d.country_code=any(p_country_codes))
    and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
    and (p_level_codes is null or d.study_level_code=any(p_level_codes))
    and (p_field_codes is null or d.primary_field_code=any(p_field_codes))
    and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
    and (p_has_fee is null or d.has_fee=p_has_fee)
    and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
    and (coalesce(trim(p_query),'')='' or d.search_tsv @@ (select tsq from params))
), paged as (
  select * from ranked
  order by score desc,course_title,course_stable_key
  limit (select lim from params) offset (select off from params)
)
select jsonb_build_object(
  'contract_version','website-course-search-v1',
  'meta',jsonb_build_object(
    'mode','keyword',
    'limit',(select lim from params),
    'offset',(select off from params),
    'projection_version','course-v2'
  ),
  'items',coalesce(jsonb_agg(jsonb_build_object(
    'course_key',course_stable_key,
    'title',course_title,
    'course_code',course_code,
    'provider',jsonb_build_object('provider_key',provider_stable_key,'name',provider_name),
    'country',country_code,
    'study_level',study_level_code,
    'field',case when primary_field_code is null then null else jsonb_build_object('code',primary_field_code,'name',primary_field_name) end,
    'states',to_jsonb(subdivision_codes),
    'delivery_modes',to_jsonb(delivery_modes),
    'readiness',jsonb_build_object('has_state',has_state,'has_link',has_link,'has_fee',has_fee,'has_intake',has_intake,'has_english',has_english,'has_scholarship',has_scholarship),
    'match',jsonb_build_object('keyword_score',score)
  ) order by score desc,course_title,course_stable_key),'[]'::jsonb)
)
from paged
$function$
;

-- api.website_course_search_v2(text,text[],text[],text[],text[],text[],boolean,numeric,boolean,boolean,boolean,text,integer,integer)
CREATE OR REPLACE FUNCTION api.website_course_search_v2(p_query text DEFAULT NULL::text, p_country_codes text[] DEFAULT NULL::text[], p_subdivision_codes text[] DEFAULT NULL::text[], p_level_codes text[] DEFAULT NULL::text[], p_field_codes text[] DEFAULT NULL::text[], p_delivery_modes text[] DEFAULT NULL::text[], p_has_provider_tuition boolean DEFAULT NULL::boolean, p_provider_annual_tuition_max numeric DEFAULT NULL::numeric, p_has_intake boolean DEFAULT NULL::boolean, p_has_english boolean DEFAULT NULL::boolean, p_has_scholarship boolean DEFAULT NULL::boolean, p_sort text DEFAULT 'relevance'::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'search'
AS $function$
with params as (
  select greatest(1,least(coalesce(p_limit,20),50)) lim,greatest(coalesce(p_offset,0),0) off,
         websearch_to_tsquery('english',coalesce(nullif(trim(p_query),''),'')) tsq,
         case when p_sort in ('relevance','title','regulatory_tuition_asc','regulatory_tuition_desc','provider_annual_tuition_asc','provider_annual_tuition_desc','earliest_intake') then p_sort else 'relevance' end sort_code
), ranked as (
  select d.*,case when coalesce(trim(p_query),'')='' then 0::real else ts_rank_cd(d.search_tsv,(select tsq from params))::real end score
  from search.course_documents d
  where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
    and d.publication_status='published'
    and (p_country_codes is null or d.country_code=any(p_country_codes))
    and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
    and (p_level_codes is null or d.study_level_code=any(p_level_codes))
    and (p_field_codes is null or d.primary_field_code=any(p_field_codes))
    and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
    and (p_has_provider_tuition is null or d.has_provider_current_tuition=p_has_provider_tuition)
    and (p_provider_annual_tuition_max is null or d.provider_annual_tuition_amount<=p_provider_annual_tuition_max)
    and (p_has_intake is null or d.has_intake=p_has_intake)
    and (p_has_english is null or d.has_english=p_has_english)
    and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
    and (coalesce(trim(p_query),'')='' or d.search_tsv @@ (select tsq from params))
), paged as (
  select * from ranked
  order by
    case when (select sort_code from params)='relevance' then score end desc,
    case when (select sort_code from params)='title' then course_title end asc,
    case when (select sort_code from params)='regulatory_tuition_asc' then regulatory_tuition_amount end asc nulls last,
    case when (select sort_code from params)='regulatory_tuition_desc' then regulatory_tuition_amount end desc nulls last,
    case when (select sort_code from params)='provider_annual_tuition_asc' then provider_annual_tuition_amount end asc nulls last,
    case when (select sort_code from params)='provider_annual_tuition_desc' then provider_annual_tuition_amount end desc nulls last,
    case when (select sort_code from params)='earliest_intake' then earliest_intake_date end asc nulls last,
    course_title,course_stable_key
  limit (select lim from params) offset (select off from params)
)
select jsonb_build_object(
 'contract_version','website-course-search-v2',
 'meta',jsonb_build_object('mode','keyword','limit',(select lim from params),'offset',(select off from params),'projection_version','course-v3','sort',(select sort_code from params)),
 'items',coalesce(jsonb_agg(jsonb_build_object(
   'course_key',course_stable_key,'title',course_title,'course_code',course_code,
   'provider',jsonb_build_object('provider_key',provider_stable_key,'name',provider_name),
   'country',country_code,'study_level',study_level_code,
   'field',case when primary_field_code is null then null else jsonb_build_object('code',primary_field_code,'name',primary_field_name) end,
   'states',to_jsonb(subdivision_codes),'delivery_modes',to_jsonb(delivery_modes),
   'regulatory_tuition',jsonb_build_object('state',regulatory_tuition_state,'amount',regulatory_tuition_amount,'currency',trim(regulatory_tuition_currency),'basis',regulatory_tuition_basis),
   'provider_current_tuition',jsonb_build_object('has_value',has_provider_current_tuition,'annual_amount',provider_annual_tuition_amount,'annual_currency',trim(provider_annual_tuition_currency),'options',provider_tuition_options),
   'official_course_url',official_course_url,'intakes',intake_options,'english_requirements',english_requirement_options,'scholarships',scholarship_options,
   'readiness',jsonb_build_object('has_state',has_state,'has_official_url',has_link,'has_provider_current_tuition',has_provider_current_tuition,'has_intake',has_intake,'has_english',has_english,'has_scholarship',has_scholarship),
   'match',jsonb_build_object('keyword_score',score)
 ) order by
    case when (select sort_code from params)='relevance' then score end desc,
    case when (select sort_code from params)='title' then course_title end asc,
    case when (select sort_code from params)='regulatory_tuition_asc' then regulatory_tuition_amount end asc nulls last,
    case when (select sort_code from params)='regulatory_tuition_desc' then regulatory_tuition_amount end desc nulls last,
    case when (select sort_code from params)='provider_annual_tuition_asc' then provider_annual_tuition_amount end asc nulls last,
    case when (select sort_code from params)='provider_annual_tuition_desc' then provider_annual_tuition_amount end desc nulls last,
    case when (select sort_code from params)='earliest_intake' then earliest_intake_date end asc nulls last,
    course_title,course_stable_key),'[]'::jsonb)
) from paged
$function$
;

-- api.zoho_campus_lookup_v1(text)
CREATE OR REPLACE FUNCTION api.zoho_campus_lookup_v1(p_identifier text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'api'
AS $function$
  with x as (
    select ca.*, p.stable_key provider_stable_key, p.canonical_name provider_name,
           co.iso_alpha2::text country_code, s.code subdivision_code, s.name subdivision_name
    from catalogue.campuses ca
    join catalogue.providers p on p.id=ca.provider_id
    join ref.countries co on co.id=ca.country_id
    left join ref.subdivisions s on s.id=ca.subdivision_id
    where not exists (select 1 from security.layer4_search_blocked_campuses cf_block where cf_block.campus_id=ca.id)
      and lower(ca.stable_key)=lower(btrim(p_identifier))
       or lower(coalesce(ca.campus_code,''))=lower(btrim(p_identifier))
    order by case when lower(ca.stable_key)=lower(btrim(p_identifier)) then 0 else 1 end, ca.stable_key
    limit 1
  )
  select case when exists(select 1 from x) then jsonb_build_object(
    'contract_version','zoho-integration-v1','resource','campus',
    'item',(select jsonb_build_object(
      'campus_id',stable_key,'name',name,'campus_code',campus_code,
      'provider',jsonb_build_object('provider_id',provider_stable_key,'name',provider_name),
      'country_code',country_code,
      'subdivision',case when subdivision_code is null then null else jsonb_build_object('code',subdivision_code,'name',subdivision_name) end,
      'city',city,'address',jsonb_build_object('line1',address_line1,'line2',address_line2,'postcode',postcode),
      'website',website,'lifecycle_status',status,'publication_status',publication_status,
      'freshness',jsonb_build_object('last_verified_at',last_verified_at,'updated_at',updated_at)
    ) from x),'generated_at',now()
  ) else jsonb_build_object(
    'contract_version','zoho-integration-v1','resource','campus',
    'error',jsonb_build_object('code','NOT_FOUND','message','Campus identifier not found')
  ) end;
$function$
;

-- api.zoho_campus_search_v1(text,text,text[],text[],timestamp with time zone,integer,integer)
CREATE OR REPLACE FUNCTION api.zoho_campus_search_v1(p_query text DEFAULT NULL::text, p_country_code text DEFAULT NULL::text, p_provider_ids text[] DEFAULT NULL::text[], p_subdivision_codes text[] DEFAULT NULL::text[], p_changed_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'api'
AS $function$
  with base as (
    select ca.*, p.stable_key provider_stable_key, p.canonical_name provider_name,
           co.iso_alpha2::text country_code, s.code subdivision_code, s.name subdivision_name
    from catalogue.campuses ca
    join catalogue.providers p on p.id=ca.provider_id
    join ref.countries co on co.id=ca.country_id
    left join ref.subdivisions s on s.id=ca.subdivision_id
    where not exists (select 1 from security.layer4_search_blocked_campuses cf_block where cf_block.campus_id=ca.id)
      and (p_query is null or btrim(p_query)='' or ca.name ilike '%'||btrim(p_query)||'%' or
           ca.stable_key ilike '%'||btrim(p_query)||'%' or ca.city ilike '%'||btrim(p_query)||'%')
      and (p_country_code is null or co.iso_alpha2=upper(p_country_code))
      and (p_provider_ids is null or p.stable_key=any(p_provider_ids))
      and (p_subdivision_codes is null or s.code=any(p_subdivision_codes))
      and (p_changed_since is null or ca.updated_at > p_changed_since)
  ),
  page as (
    select * from base
    order by lower(name), stable_key
    limit greatest(1, least(coalesce(p_limit,20),50))
    offset greatest(coalesce(p_offset,0),0)
  )
  select jsonb_build_object(
    'contract_version','zoho-integration-v1','resource','campuses',
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'campus_id',stable_key,'name',name,'campus_code',campus_code,
      'provider',jsonb_build_object('provider_id',provider_stable_key,'name',provider_name),
      'country_code',country_code,
      'subdivision',case when subdivision_code is null then null else jsonb_build_object('code',subdivision_code,'name',subdivision_name) end,
      'city',city,'postcode',postcode,'website',website,
      'lifecycle_status',status,'publication_status',publication_status,
      'freshness',jsonb_build_object('last_verified_at',last_verified_at,'updated_at',updated_at)
    ) order by lower(name),stable_key),'[]'::jsonb),
    'page',jsonb_build_object(
      'limit',greatest(1,least(coalesce(p_limit,20),50)),
      'offset',greatest(coalesce(p_offset,0),0),
      'total',(select count(*) from base)
    ),
    'ordering','name_asc,campus_id_asc','generated_at',now()
  ) from page;
$function$
;

-- api.zoho_course_candidates_v1(text,text[],text[],text[],text[],text[],boolean,boolean,integer)
CREATE OR REPLACE FUNCTION api.zoho_course_candidates_v1(p_query text DEFAULT NULL::text, p_country_codes text[] DEFAULT NULL::text[], p_subdivision_codes text[] DEFAULT NULL::text[], p_level_codes text[] DEFAULT NULL::text[], p_field_codes text[] DEFAULT NULL::text[], p_delivery_modes text[] DEFAULT NULL::text[], p_has_fee boolean DEFAULT NULL::boolean, p_has_scholarship boolean DEFAULT NULL::boolean, p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'search', 'security'
AS $function$
declare v_result jsonb;
begin
  if security.current_role_rank()<2 then
    raise exception 'forbidden' using errcode='42501';
  end if;
  with params as (
    select greatest(1,least(coalesce(p_limit,30),100)) as lim,
           websearch_to_tsquery('english',coalesce(nullif(trim(p_query),''),'')) as tsq
  ), ranked as (
    select d.*,
      case when coalesce(trim(p_query),'')='' then 0::real else ts_rank_cd(d.search_tsv,(select tsq from params))::real end as score
    from search.course_documents d
    where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
    and d.publication_status in ('published','internal')
      and (p_country_codes is null or d.country_code=any(p_country_codes))
      and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
      and (p_level_codes is null or d.study_level_code=any(p_level_codes))
      and (p_field_codes is null or d.primary_field_code=any(p_field_codes))
      and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
      and (p_has_fee is null or d.has_fee=p_has_fee)
      and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
      and (coalesce(trim(p_query),'')='' or d.search_tsv @@ (select tsq from params))
    order by score desc,d.course_title,d.course_stable_key
    limit (select lim from params)
  )
  select jsonb_build_object(
    'contract_version','zoho-course-candidates-v1',
    'meta',jsonb_build_object('mode','keyword','limit',(select lim from params),'projection_version','course-v3'),
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'course_key',course_stable_key,
      'provider_key',provider_stable_key,
      'title',course_title,
      'provider_name',provider_name,
      'country',country_code,
      'study_level',study_level_code,
      'field_code',primary_field_code,
      'states',to_jsonb(subdivision_codes),
      'delivery_modes',to_jsonb(delivery_modes),
      'academic_rank',score,
      'readiness',jsonb_build_object('has_state',has_state,'has_link',has_link,'has_fee',has_fee,'has_intake',has_intake,'has_english',has_english,'has_scholarship',has_scholarship)
    ) order by score desc,course_title,course_stable_key),'[]'::jsonb)
  ) into v_result
  from ranked;
  return v_result;
end
$function$
;

-- api.zoho_course_lookup_v1(text)
CREATE OR REPLACE FUNCTION api.zoho_course_lookup_v1(p_identifier text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'api'
AS $function$
  with x as (
    select d.* from search.course_documents d
    where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
      and lower(d.course_stable_key)=lower(btrim(p_identifier))
       or lower(d.course_code)=lower(btrim(p_identifier))
    order by case when lower(d.course_stable_key)=lower(btrim(p_identifier)) then 0 else 1 end
             ,d.course_stable_key
    limit 1
  )
  select case when exists(select 1 from x) then jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','course',
    'item',(select jsonb_build_object(
      'course_id',course_stable_key,'course_code',course_code,'title',course_title,
      'provider',jsonb_build_object('provider_id',provider_stable_key,'name',provider_name),
      'country_code',country_code,
      'study_level',jsonb_build_object('code',study_level_code),
      'field',jsonb_build_object('code',primary_field_code,'name',primary_field_name),
      'subdivision_codes',coalesce(to_jsonb(subdivision_codes),'[]'::jsonb),
      'delivery_modes',coalesce(to_jsonb(delivery_modes),'[]'::jsonb),
      'regulatory_tuition',jsonb_build_object(
        'state',regulatory_tuition_state,'amount',regulatory_tuition_amount,
        'currency',regulatory_tuition_currency,'basis',regulatory_tuition_basis
      ),
      'provider_current_tuition',jsonb_build_object(
        'has_value',has_provider_current_tuition,'annual_amount',provider_annual_tuition_amount,
        'annual_currency',provider_annual_tuition_currency,'options',coalesce(provider_tuition_options,'[]'::jsonb)
      ),
      'official_course_url',official_course_url,
      'intakes',coalesce(intake_options,'[]'::jsonb),
      'english_requirements',coalesce(english_requirement_options,'[]'::jsonb),
      'scholarships',coalesce(scholarship_options,'[]'::jsonb),
      'publication_status',publication_status,
      'context',jsonb_build_object(
        'qilt',jsonb_build_object('state','not_admitted','grain','provider_or_study_area','message','QILT remains contextual and is not yet admitted in this v1 Pilot read function'),
        'prisms',jsonb_build_object('state','not_admitted','grain','provider_state_or_sector','message','PRISMS remains contextual and is not yet admitted in this v1 Pilot read function')
      ),
      'freshness',jsonb_build_object(
        'source_updated_at',source_updated_at,'projection_updated_at',updated_at,'generated_at',generated_at
      )
    ) from x),
    'generated_at',now()
  ) else jsonb_build_object(
    'contract_version','zoho-integration-v1','resource','course','error',
    jsonb_build_object('code','NOT_FOUND','message','Course identifier not found')
  ) end;
$function$
;

-- api.zoho_course_search_v1(text,text[],text[],text[],boolean,timestamp with time zone,integer,integer)
CREATE OR REPLACE FUNCTION api.zoho_course_search_v1(p_query text DEFAULT NULL::text, p_country_codes text[] DEFAULT NULL::text[], p_provider_ids text[] DEFAULT NULL::text[], p_subdivision_codes text[] DEFAULT NULL::text[], p_has_scholarship boolean DEFAULT NULL::boolean, p_changed_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'api'
AS $function$
  with base as (
    select d.*
    from search.course_documents d
    where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
    and (
        p_query is null or btrim(p_query)='' or
        d.search_tsv @@ websearch_to_tsquery('english', btrim(p_query)) or
        d.course_title ilike '%' || btrim(p_query) || '%' or
        d.provider_name ilike '%' || btrim(p_query) || '%' or
        lower(d.course_code)=lower(btrim(p_query)) or
        lower(d.course_stable_key)=lower(btrim(p_query))
      )
      and (p_country_codes is null or d.country_code = any(p_country_codes))
      and (p_provider_ids is null or d.provider_stable_key = any(p_provider_ids))
      and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
      and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
      and (p_changed_since is null or greatest(d.updated_at,d.source_updated_at,d.generated_at) > p_changed_since)
  ),
  page as (
    select * from base
    order by lower(course_title), course_stable_key
    limit greatest(1, least(coalesce(p_limit,20),50))
    offset greatest(coalesce(p_offset,0),0)
  )
  select jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','courses',
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'course_id',course_stable_key,
      'course_code',course_code,
      'title',course_title,
      'provider',jsonb_build_object('provider_id',provider_stable_key,'name',provider_name),
      'country_code',country_code,
      'study_level',jsonb_build_object('code',study_level_code),
      'field',jsonb_build_object('code',primary_field_code,'name',primary_field_name),
      'subdivision_codes',coalesce(to_jsonb(subdivision_codes),'[]'::jsonb),
      'delivery_modes',coalesce(to_jsonb(delivery_modes),'[]'::jsonb),
      'regulatory_tuition',jsonb_build_object(
        'state',regulatory_tuition_state,'amount',regulatory_tuition_amount,
        'currency',regulatory_tuition_currency,'basis',regulatory_tuition_basis
      ),
      'provider_current_tuition',jsonb_build_object(
        'has_value',has_provider_current_tuition,'annual_amount',provider_annual_tuition_amount,
        'annual_currency',provider_annual_tuition_currency
      ),
      'official_course_url',official_course_url,
      'has_intake',has_intake,'has_english',has_english,'has_scholarship',has_scholarship,
      'publication_status',publication_status,
      'freshness',jsonb_build_object(
        'source_updated_at',source_updated_at,'projection_updated_at',updated_at,'generated_at',generated_at
      )
    ) order by lower(course_title), course_stable_key),'[]'::jsonb),
    'page',jsonb_build_object(
      'limit',greatest(1, least(coalesce(p_limit,20),50)),
      'offset',greatest(coalesce(p_offset,0),0),
      'total',(select count(*) from base)
    ),
    'ordering','title_asc,course_id_asc',
    'generated_at',now()
  ) from page;
$function$
;

-- api.zoho_course_search_v2(text,text[],text[],text[],text[],text[],text[],boolean,boolean,boolean,boolean,boolean,boolean,integer[],text[],text[],numeric,numeric,numeric,numeric,text[],timestamp with time zone,integer,integer)
CREATE OR REPLACE FUNCTION api.zoho_course_search_v2(p_query text DEFAULT NULL::text, p_country_codes text[] DEFAULT NULL::text[], p_provider_ids text[] DEFAULT NULL::text[], p_subdivision_codes text[] DEFAULT NULL::text[], p_study_level_codes text[] DEFAULT NULL::text[], p_primary_field_codes text[] DEFAULT NULL::text[], p_delivery_modes text[] DEFAULT NULL::text[], p_has_scholarship boolean DEFAULT NULL::boolean, p_has_intake boolean DEFAULT NULL::boolean, p_has_english boolean DEFAULT NULL::boolean, p_has_provider_current_tuition boolean DEFAULT NULL::boolean, p_has_regulatory_tuition boolean DEFAULT NULL::boolean, p_has_link boolean DEFAULT NULL::boolean, p_intake_years integer[] DEFAULT NULL::integer[], p_intake_labels text[] DEFAULT NULL::text[], p_english_test_codes text[] DEFAULT NULL::text[], p_min_provider_annual_tuition numeric DEFAULT NULL::numeric, p_max_provider_annual_tuition numeric DEFAULT NULL::numeric, p_min_regulatory_total_tuition numeric DEFAULT NULL::numeric, p_max_regulatory_total_tuition numeric DEFAULT NULL::numeric, p_publication_statuses text[] DEFAULT NULL::text[], p_changed_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'api'
AS $function$
with base as (
  select d.*
  from search.course_documents d
  where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
    and (
      p_query is null or btrim(p_query)='' or
      d.search_tsv @@ websearch_to_tsquery('english', btrim(p_query)) or
      d.course_title ilike '%' || btrim(p_query) || '%' or
      d.provider_name ilike '%' || btrim(p_query) || '%' or
      lower(d.course_code)=lower(btrim(p_query)) or
      lower(d.course_stable_key)=lower(btrim(p_query))
    )
    and (p_country_codes is null or d.country_code = any(p_country_codes))
    and (p_provider_ids is null or d.provider_stable_key = any(p_provider_ids))
    and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
    and (p_study_level_codes is null or d.study_level_code = any(p_study_level_codes))
    and (p_primary_field_codes is null or d.primary_field_code = any(p_primary_field_codes))
    and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
    and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
    and (p_has_intake is null or d.has_intake=p_has_intake)
    and (p_has_english is null or d.has_english=p_has_english)
    and (p_has_provider_current_tuition is null or d.has_provider_current_tuition=p_has_provider_current_tuition)
    and (p_has_regulatory_tuition is null or d.has_regulatory_tuition=p_has_regulatory_tuition)
    and (p_has_link is null or d.has_link=p_has_link)
    and (p_publication_statuses is null or d.publication_status = any(p_publication_statuses))
    and (
      p_intake_years is null or exists (
        select 1 from jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) x
        where (x->>'year') ~ '^[0-9]+$' and (x->>'year')::int = any(p_intake_years)
      )
    )
    and (
      p_intake_labels is null or exists (
        select 1 from jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) x
        where x->>'label' = any(p_intake_labels)
      )
    )
    and (
      p_english_test_codes is null or exists (
        select 1 from jsonb_array_elements(coalesce(d.english_requirement_options,'[]'::jsonb)) x
        where x->>'test_code' = any(p_english_test_codes)
      )
    )
    and (p_min_provider_annual_tuition is null or d.provider_annual_tuition_amount >= p_min_provider_annual_tuition)
    and (p_max_provider_annual_tuition is null or d.provider_annual_tuition_amount <= p_max_provider_annual_tuition)
    and (p_min_regulatory_total_tuition is null or d.regulatory_tuition_amount >= p_min_regulatory_total_tuition)
    and (p_max_regulatory_total_tuition is null or d.regulatory_tuition_amount <= p_max_regulatory_total_tuition)
    and (p_changed_since is null or greatest(d.updated_at,d.source_updated_at,d.generated_at) > p_changed_since)
),
page as (
  select * from base
  order by lower(course_title), course_stable_key
  limit greatest(1, least(coalesce(p_limit,20),50))
  offset greatest(coalesce(p_offset,0),0)
)
select jsonb_build_object(
  'contract_version','zoho-integration-v2',
  'resource','courses',
  'items',coalesce(jsonb_agg(jsonb_build_object(
    'course_id',course_stable_key,
    'course_code',course_code,
    'title',course_title,
    'provider',jsonb_build_object('provider_id',provider_stable_key,'name',provider_name),
    'country_code',country_code,
    'study_level',jsonb_build_object('code',study_level_code),
    'field',jsonb_build_object('code',primary_field_code,'name',primary_field_name),
    'subdivision_codes',coalesce(to_jsonb(subdivision_codes),'[]'::jsonb),
    'delivery_modes',coalesce(to_jsonb(delivery_modes),'[]'::jsonb),
    'regulatory_tuition',jsonb_build_object(
      'state',regulatory_tuition_state,'amount',regulatory_tuition_amount,
      'currency',regulatory_tuition_currency,'basis',regulatory_tuition_basis
    ),
    'provider_current_tuition',jsonb_build_object(
      'has_value',has_provider_current_tuition,'annual_amount',provider_annual_tuition_amount,
      'annual_currency',provider_annual_tuition_currency
    ),
    'official_course_url',official_course_url,
    'has_intake',has_intake,'has_english',has_english,'has_scholarship',has_scholarship,
    'earliest_intake_date',earliest_intake_date,
    'publication_status',publication_status,
    'freshness',jsonb_build_object(
      'source_updated_at',source_updated_at,'projection_updated_at',updated_at,'generated_at',generated_at
    )
  ) order by lower(course_title), course_stable_key),'[]'::jsonb),
  'page',jsonb_build_object(
    'limit',greatest(1, least(coalesce(p_limit,20),50)),
    'offset',greatest(coalesce(p_offset,0),0),
    'total',(select count(*) from base)
  ),
  'ordering','title_asc,course_id_asc',
  'generated_at',now()
) from page;
$function$
;

-- api.zoho_filter_options_v1(text,text,text,integer,integer)
CREATE OR REPLACE FUNCTION api.zoho_filter_options_v1(p_kind text, p_country_code text DEFAULT NULL::text, p_query text DEFAULT NULL::text, p_limit integer DEFAULT 10, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'api', 'ref', 'search'
AS $function$
declare
  v_kind text := lower(trim(coalesce(p_kind,'')));
  v_country text := upper(nullif(trim(coalesce(p_country_code,'')), ''));
  v_query text := nullif(trim(coalesce(p_query,'')), '');
  v_limit integer := least(greatest(coalesce(p_limit,10),1),50);
  v_offset integer := greatest(coalesce(p_offset,0),0);
  v_total bigint := 0;
  v_items jsonb := '[]'::jsonb;
begin
  if v_kind = 'country' then
    select count(*)
      into v_total
      from ref.countries c
     where exists (
             select 1 from search.course_documents d
             where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
               and d.country_id = c.id
           )
       and (
         v_query is null
         or c.name ilike '%'||v_query||'%'
         or c.iso_alpha2::text ilike '%'||v_query||'%'
       );

    select coalesce(jsonb_agg(jsonb_build_object(
             'code', x.iso_alpha2,
             'name', x.name
           ) order by x.name, x.iso_alpha2), '[]'::jsonb)
      into v_items
      from (
        select trim(c.iso_alpha2::text) as iso_alpha2, c.name
          from ref.countries c
         where exists (
                 select 1 from search.course_documents d
                 where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
               and d.country_id = c.id
               )
           and (
             v_query is null
             or c.name ilike '%'||v_query||'%'
             or c.iso_alpha2::text ilike '%'||v_query||'%'
           )
         order by c.name, c.iso_alpha2
         limit v_limit offset v_offset
      ) x;

  elsif v_kind = 'subdivision' then
    if v_country is null then
      raise exception using errcode='22023', message='country_code_required';
    end if;

    select count(*)
      into v_total
      from ref.subdivisions s
      join ref.countries c on c.id = s.country_id
     where trim(c.iso_alpha2::text) = v_country
       and exists (
             select 1
             from search.course_documents d
             where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
               and d.country_id = c.id
               and s.code = any(coalesce(d.subdivision_codes, '{}'::text[]))
           )
       and (
         v_query is null
         or s.name ilike '%'||v_query||'%'
         or s.code ilike '%'||v_query||'%'
       );

    select coalesce(jsonb_agg(jsonb_build_object(
             'code', x.code,
             'name', x.name,
             'country_code', v_country
           ) order by x.name, x.code), '[]'::jsonb)
      into v_items
      from (
        select s.code, s.name
          from ref.subdivisions s
          join ref.countries c on c.id = s.country_id
         where trim(c.iso_alpha2::text) = v_country
           and exists (
                 select 1
                 from search.course_documents d
                 where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id)
               and d.country_id = c.id
                   and s.code = any(coalesce(d.subdivision_codes, '{}'::text[]))
               )
           and (
             v_query is null
             or s.name ilike '%'||v_query||'%'
             or s.code ilike '%'||v_query||'%'
           )
         order by s.name, s.code
         limit v_limit offset v_offset
      ) x;
  else
    raise exception using errcode='22023', message='invalid_filter_kind';
  end if;

  return jsonb_build_object(
    'contract','zoho-integration-v1',
    'kind',v_kind,
    'items',v_items,
    'total',v_total,
    'limit',v_limit,
    'offset',v_offset,
    'has_more',(v_offset + v_limit) < v_total
  );
end;
$function$
;

-- api.zoho_provider_lookup_v1(text)
CREATE OR REPLACE FUNCTION api.zoho_provider_lookup_v1(p_identifier text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'api'
AS $function$
  with x as (
    select
      p.id, p.stable_key, p.canonical_name, p.display_name, p.short_name,
      c.iso_alpha2::text country_code, p.website, p.description,
      p.primary_city, p.lifecycle_status, p.publication_status,
      p.last_verified_at, p.updated_at
    from catalogue.providers p
    join ref.countries c on c.id=p.country_id
    where not exists (select 1 from security.layer4_search_blocked_providers cf_block where cf_block.provider_id=p.id)
      and lower(p.stable_key)=lower(btrim(p_identifier))
       or exists (
         select 1 from catalogue.provider_identifiers i
         where i.provider_id=p.id and lower(i.identifier)=lower(btrim(p_identifier))
       )
    order by case when lower(p.stable_key)=lower(btrim(p_identifier)) then 0 else 1 end
    limit 1
  )
  select case when exists(select 1 from x) then jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','provider',
    'item',(select jsonb_build_object(
      'provider_id',stable_key,'name',canonical_name,'display_name',display_name,
      'short_name',short_name,'country_code',country_code,'website',website,
      'description',description,'primary_city',primary_city,
      'lifecycle_status',lifecycle_status,'publication_status',publication_status,
      'freshness',jsonb_build_object('last_verified_at',last_verified_at,'updated_at',updated_at)
    ) from x),
    'generated_at',now()
  ) else jsonb_build_object(
    'contract_version','zoho-integration-v1','resource','provider','error',
    jsonb_build_object('code','NOT_FOUND','message','Provider identifier not found')
  ) end;
$function$
;

-- api.zoho_provider_search_v1(text,text,timestamp with time zone,integer,integer)
CREATE OR REPLACE FUNCTION api.zoho_provider_search_v1(p_query text DEFAULT NULL::text, p_country_code text DEFAULT NULL::text, p_changed_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'api'
AS $function$
  with base as (
    select
      p.id,
      p.stable_key,
      p.canonical_name,
      p.display_name,
      c.iso_alpha2::text as country_code,
      p.website,
      p.lifecycle_status,
      p.publication_status,
      p.last_verified_at,
      p.updated_at
    from catalogue.providers p
    join ref.countries c on c.id = p.country_id
    where not exists (select 1 from security.layer4_search_blocked_providers cf_block where cf_block.provider_id=p.id)
      and (p_query is null or btrim(p_query) = '' or
           p.canonical_name ilike '%' || btrim(p_query) || '%' or
           p.display_name ilike '%' || btrim(p_query) || '%' or
           p.stable_key ilike '%' || btrim(p_query) || '%')
      and (p_country_code is null or c.iso_alpha2 = upper(p_country_code))
      and (p_changed_since is null or p.updated_at > p_changed_since)
  ),
  page as (
    select * from base
    order by lower(canonical_name), stable_key
    limit greatest(1, least(coalesce(p_limit,20),50))
    offset greatest(coalesce(p_offset,0),0)
  )
  select jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','providers',
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'provider_id', stable_key,
      'name', canonical_name,
      'display_name', display_name,
      'country_code', country_code,
      'website', website,
      'lifecycle_status', lifecycle_status,
      'publication_status', publication_status,
      'freshness', jsonb_build_object(
        'last_verified_at', last_verified_at,
        'updated_at', updated_at
      )
    ) order by lower(canonical_name), stable_key), '[]'::jsonb),
    'page', jsonb_build_object(
      'limit', greatest(1, least(coalesce(p_limit,20),50)),
      'offset', greatest(coalesce(p_offset,0),0),
      'total', (select count(*) from base)
    ),
    'generated_at', now()
  ) from page;
$function$
;

-- api.zoho_scholarship_lookup_v1(text)
CREATE OR REPLACE FUNCTION api.zoho_scholarship_lookup_v1(p_identifier text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'api'
AS $function$
  with x as (
    select s.*, p.stable_key provider_stable_key, p.canonical_name provider_name
    from scholarship.scholarships s
    left join catalogue.providers p on p.id=s.provider_id
    where not exists (select 1 from security.layer4_search_blocked_scholarships cf_block where cf_block.scholarship_id=s.id)
      and lower(s.stable_key)=lower(btrim(p_identifier))
    limit 1
  )
  select case when exists(select 1 from x) then jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','scholarship',
    'item',(select jsonb_build_object(
      'scholarship_id',stable_key,'name',name,
      'provider',case when provider_stable_key is null then null else jsonb_build_object('provider_id',provider_stable_key,'name',provider_name) end,
      'scholarship_type',scholarship_type,'description',description,'audience',audience,
      'award_value_text',award_value_text,'application_required',application_required,
      'application_open_date',application_open_date,'application_close_date',application_close_date,
      'academic_year',academic_year,'source_url',source_url,
      'lifecycle_status',lifecycle_status,'publication_status',publication_status,
      'freshness',jsonb_build_object('updated_at',updated_at)
    ) from x),
    'generated_at',now()
  ) else jsonb_build_object(
    'contract_version','zoho-integration-v1','resource','scholarship','error',
    jsonb_build_object('code','NOT_FOUND','message','Scholarship identifier not found')
  ) end;
$function$
;

-- api.zoho_scholarship_search_v1(text,text[],timestamp with time zone,integer,integer)
CREATE OR REPLACE FUNCTION api.zoho_scholarship_search_v1(p_query text DEFAULT NULL::text, p_provider_ids text[] DEFAULT NULL::text[], p_changed_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'api'
AS $function$
  with base as (
    select s.*, p.stable_key provider_stable_key, p.canonical_name provider_name
    from scholarship.scholarships s
    left join catalogue.providers p on p.id=s.provider_id
    where not exists (select 1 from security.layer4_search_blocked_scholarships cf_block where cf_block.scholarship_id=s.id)
      and (p_query is null or btrim(p_query)='' or s.name ilike '%'||btrim(p_query)||'%' or s.stable_key ilike '%'||btrim(p_query)||'%')
      and (p_provider_ids is null or p.stable_key = any(p_provider_ids))
      and (p_changed_since is null or s.updated_at > p_changed_since)
  ),
  page as (
    select * from base
    order by lower(name), stable_key
    limit greatest(1, least(coalesce(p_limit,20),50))
    offset greatest(coalesce(p_offset,0),0)
  )
  select jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'resource','scholarships',
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'scholarship_id',stable_key,'name',name,
      'provider',case when provider_stable_key is null then null else jsonb_build_object('provider_id',provider_stable_key,'name',provider_name) end,
      'scholarship_type',scholarship_type,'audience',audience,'award_value_text',award_value_text,
      'application_required',application_required,'application_open_date',application_open_date,
      'application_close_date',application_close_date,'academic_year',academic_year,
      'source_url',source_url,'lifecycle_status',lifecycle_status,'publication_status',publication_status,
      'freshness',jsonb_build_object('updated_at',updated_at)
    ) order by lower(name), stable_key),'[]'::jsonb),
    'page',jsonb_build_object(
      'limit',greatest(1, least(coalesce(p_limit,20),50)),
      'offset',greatest(coalesce(p_offset,0),0),
      'total',(select count(*) from base)
    ),
    'ordering','name_asc,scholarship_id_asc',
    'generated_at',now()
  ) from page;
$function$
;

-- api.zoho_sync_manifest_v1(timestamp with time zone)
CREATE OR REPLACE FUNCTION api.zoho_sync_manifest_v1(p_changed_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'scholarship', 'search', 'api'
AS $function$
  select jsonb_build_object(
    'contract_version','zoho-integration-v1',
    'boundary','server-side-pilot-only',
    'changed_since',p_changed_since,
    'providers',jsonb_build_object(
      'count',(select count(*) from catalogue.providers p where not exists (select 1 from security.layer4_search_blocked_providers cf_block where cf_block.provider_id=p.id) and (p_changed_since is null or p.updated_at > p_changed_since)),
      'max_updated_at',(select max(p.updated_at) from catalogue.providers p where not exists (select 1 from security.layer4_search_blocked_providers cf_block where cf_block.provider_id=p.id))
    ),
    'courses',jsonb_build_object(
      'count',(select count(*) from search.course_documents d where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id) and (p_changed_since is null or greatest(d.updated_at,d.source_updated_at,d.generated_at) > p_changed_since)),
      'max_updated_at',(select max(greatest(d.updated_at,d.source_updated_at,d.generated_at)) from search.course_documents d where not exists (select 1 from security.layer4_search_blocked_courses cf_block where cf_block.course_id=d.course_id))
    ),
    'scholarships',jsonb_build_object(
      'count',(select count(*) from scholarship.scholarships s where not exists (select 1 from security.layer4_search_blocked_scholarships cf_block where cf_block.scholarship_id=s.id) and (p_changed_since is null or s.updated_at > p_changed_since)),
      'max_updated_at',(select max(s.updated_at) from scholarship.scholarships s where not exists (select 1 from security.layer4_search_blocked_scholarships cf_block where cf_block.scholarship_id=s.id))
    ),
    'ordering',jsonb_build_object(
      'providers','name_asc,provider_id_asc',
      'courses','title_asc,course_id_asc',
      'scholarships','name_asc,scholarship_id_asc'
    ),
    'generated_at',now()
  );
$function$
;

-- l4_api.publication_decide(text,uuid,text,text,jsonb,jsonb,text,text,jsonb)
CREATE OR REPLACE FUNCTION l4_api.publication_decide(p_entity_type text, p_entity_id uuid, p_target_scope text, p_event_type text, p_readiness_snapshot jsonb, p_overridden_checks jsonb, p_reason_code text, p_comment text DEFAULT NULL::text, p_approval_context jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'l4_api', 'security', 'pipeline', 'auth'
AS $function$
declare v_actor uuid:=auth.uid(); v_rank int; v_prev uuid; v_id uuid; v_email text;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<5 then raise exception 'PIM Admin role required for publication override' using errcode='42501'; end if;
  if not security.layer4_entity_exists(p_entity_type,p_entity_id) then raise exception 'entity not found' using errcode='22023'; end if;
  if p_event_type='publishable' and security.layer4_entity_or_parent_blocked(p_entity_type,p_entity_id,'publication') then raise exception 'entity publication blocked by Layer 4' using errcode='42501'; end if;
  if p_event_type not in ('publishable','not_publishable','revert') then raise exception 'invalid publication decision' using errcode='22023'; end if;
  if length(trim(coalesce(p_reason_code,'')))<3 then raise exception 'reason code required' using errcode='22023'; end if;
  select id into v_prev from pipeline.layer4_publication_decisions
   where entity_type=p_entity_type and entity_id=p_entity_id and target_scope=coalesce(nullif(trim(p_target_scope),''),'governed_publication')
   order by created_at desc,id desc limit 1;
  if p_event_type='revert' and v_prev is null then raise exception 'no publication override to revert' using errcode='22023'; end if;
  select email into v_email from auth.users where id=v_actor;
  insert into pipeline.layer4_publication_decisions(
    entity_type,entity_id,target_scope,event_type,readiness_snapshot,overridden_checks,
    reason_code,comment,actor_id,actor_email,supersedes_decision_id,approval_context
  ) values (
    p_entity_type,p_entity_id,coalesce(nullif(trim(p_target_scope),''),'governed_publication'),p_event_type,
    coalesce(p_readiness_snapshot,'{}'),coalesce(p_overridden_checks,'[]'),trim(p_reason_code),
    nullif(trim(coalesce(p_comment,'')),''),v_actor,v_email,v_prev,coalesce(p_approval_context,'{}')
  ) returning id into v_id;
  return jsonb_build_object('ok',true,'publication_decision_id',v_id,'event_type',p_event_type,'publication_status_changed',false,'consumer_cutover_authorised',false);
end $function$
;

-- layer3_reserve_interpretation_service(uuid,uuid,text,uuid,text,uuid,jsonb,text)
CREATE OR REPLACE FUNCTION public.layer3_reserve_interpretation_service(p_actor uuid, p_evidence_id uuid, p_entity_type text, p_entity_id uuid, p_task_class text, p_profile_id uuid, p_layer2_state jsonb DEFAULT '{}'::jsonb, p_revalidation_ref text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline'
AS $function$
declare
  v_rank int:=0; v_ev pipeline.evidence_artifacts%rowtype; v_p pipeline.layer3_model_profiles%rowtype;
  v_prev pipeline.layer3_interpretations%rowtype; v_active pipeline.layer3_interpretations%rowtype; v_reason text; v_id uuid; v_selection text;
begin
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
  select coalesce(max(r.rank),0) into v_rank
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor and r.status='active' and (ur.expires_at is null or ur.expires_at>now());
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
  if security.layer4_entity_or_parent_blocked(lower(p_entity_type),p_entity_id,'operational') then
    return jsonb_build_object('call_required',false,'reason','layer4_operational_block','entity_type',lower(p_entity_type),'entity_id',p_entity_id);
  end if;

  select * into v_ev from pipeline.evidence_artifacts where id=p_evidence_id;
  if not found or v_ev.content_hash is null then raise exception 'governed evidence with content hash required'; end if;

  select * into v_p from pipeline.layer3_model_profiles where id=p_profile_id;
  if not found then raise exception 'model profile not found'; end if;
  if not v_p.enabled or v_p.paused then raise exception 'model profile not executable'; end if;
  if coalesce((v_p.quality_benchmark->>'pass')::boolean,false) is not true then
    raise exception 'model profile quality benchmark not passed';
  end if;
  if not (p_task_class=any(v_p.allowed_task_classes)) then raise exception 'task class not allowed by profile'; end if;

  if coalesce(p_layer2_state->>'status','')='resolved_l2' then
    return jsonb_build_object('call_required',false,'reason','layer2_resolved','evidence_hash',v_ev.content_hash);
  end if;

  perform pg_advisory_xact_lock(hashtext(lower(p_entity_type)||':'||p_entity_id::text||':'||p_task_class||':'||p_profile_id::text));
  select * into v_active
  from pipeline.layer3_interpretations
  where entity_type=lower(p_entity_type) and entity_id=p_entity_id and task_class=p_task_class
    and profile_id=p_profile_id and status in ('reserved','calling')
  order by created_at desc limit 1;
  if found then
    return jsonb_build_object('call_required',false,'reason','in_flight','prior_interpretation_id',v_active.id,'evidence_hash',v_active.evidence_hash);
  end if;

  select * into v_prev
  from pipeline.layer3_interpretations
  where entity_type=lower(p_entity_type) and entity_id=p_entity_id and task_class=p_task_class
    and profile_id=p_profile_id and status in ('validated','low_confidence','no_candidate')
  order by created_at desc limit 1;

  if p_revalidation_ref is not null then
    if length(trim(p_revalidation_ref))<5 then raise exception 'governed revalidation reference required'; end if;
    v_reason:='governed_revalidation';
  elsif found and v_prev.evidence_hash=v_ev.content_hash
        and (v_prev.interpretation_expires_at is null or v_prev.interpretation_expires_at>now()) then
    return jsonb_build_object(
      'call_required',false,'reason','unchanged_evidence',
      'prior_interpretation_id',v_prev.id,'evidence_hash',v_ev.content_hash
    );
  elsif found and v_prev.evidence_hash<>v_ev.content_hash then v_reason:='changed_evidence';
  elsif found and v_prev.interpretation_expires_at is not null and v_prev.interpretation_expires_at<=now() then v_reason:='freshness_expired';
  elsif coalesce(p_layer2_state->>'status','') in ('unresolved','blocked','partial','escalated_l3','layer3_required') then v_reason:='layer2_unresolved';
  else v_reason:='new_evidence';
  end if;

  v_selection:=nullif(p_layer2_state->>'evidence_selection_reason','');

  insert into pipeline.layer3_interpretations(
    evidence_id,evidence_hash,entity_type,entity_id,task_class,profile_id,prompt_profile_version,
    eligibility_reason,revalidation_ref,layer2_state,requested_by,selected_evidence_reason,
    change_control_ref,uat_ref
  ) values(
    p_evidence_id,v_ev.content_hash,lower(p_entity_type),p_entity_id,p_task_class,p_profile_id,
    v_p.prompt_profile_version,v_reason,p_revalidation_ref,coalesce(p_layer2_state,'{}'::jsonb),
    p_actor,v_selection,'CF-CHG-20260829-047','M2.4.3-layer3-operations'
  ) returning id into v_id;

  return jsonb_build_object(
    'call_required',true,'interpretation_id',v_id,'eligibility_reason',v_reason,
    'evidence_hash',v_ev.content_hash,'selected_evidence_reason',v_selection,
    'profile',jsonb_build_object(
      'id',v_p.id,'aggregator_provider',v_p.aggregator_provider,'base_url',v_p.base_url,
      'model_identifier',v_p.model_identifier,'secret_env_key',v_p.secret_env_key,
      'prompt_profile_version',v_p.prompt_profile_version,'prompt_system',v_p.prompt_system,
      'schema',v_p.structured_output_schema,'validators',v_p.deterministic_validators,
      'max_input_tokens',v_p.max_input_tokens,'max_output_tokens',v_p.max_output_tokens,
      'requests_per_minute',v_p.requests_per_minute,'requests_per_day',v_p.requests_per_day,
      'retry_ceiling',v_p.retry_ceiling,'timeout_ms',v_p.timeout_ms,
      'cost_ceiling_usd',v_p.cost_ceiling_usd,'fallback_profile_id',v_p.fallback_profile_id
    )
  );
end $function$
;

-- layer3_source_pattern_request_context_service(uuid,uuid)
CREATE OR REPLACE FUNCTION public.layer3_source_pattern_request_context_service(p_actor uuid, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security', 'catalogue'
AS $function$
declare
  v_rank integer:=0;
  r pipeline.refresh_requests%rowtype;
  e pipeline.evidence_artifacts%rowtype;
  mp pipeline.layer3_model_profiles%rowtype;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
  select coalesce(max(ro.rank),0) into v_rank
  from security.user_roles ur join security.roles ro on ro.code=ur.role_code
  where ur.user_id=p_actor and ro.status='active' and (ur.expires_at is null or ur.expires_at>now());
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;

  select * into r from pipeline.refresh_requests where id=p_request_id for update;
  if not found then raise exception 'source-pattern request not found' using errcode='22023'; end if;
  if r.requested_layer<>3 or r.entity_type<>'provider' or r.revalidation_ref not like 'A23-SOURCE-PATTERN:%' then
    raise exception 'source-pattern request contract mismatch' using errcode='22023';
  end if;
  if security.layer4_entity_or_parent_blocked('provider',r.entity_id,'operational') then
    return jsonb_build_object('ok',true,'executable',false,'reason','layer4_operational_block','request_id',r.id,'entity_id',r.entity_id);
  end if;
  if r.status='completed' then
    return jsonb_build_object('ok',true,'executable',false,'reason','request_completed','request_id',r.id);
  end if;
  if r.status not in('queued','failed','blocked') then
    return jsonb_build_object('ok',true,'executable',false,'reason','request_'||r.status,'request_id',r.id);
  end if;
  if r.evidence_id is null or r.layer3_profile_id is null or r.source_profile_id is null then
    raise exception 'source-pattern request lineage incomplete' using errcode='22023';
  end if;

  select * into e from pipeline.evidence_artifacts where id=r.evidence_id;
  if not found or e.content_hash is null or e.storage_path is null then raise exception 'governed retained Evidence required' using errcode='22023'; end if;
  select * into mp from pipeline.layer3_model_profiles where id=r.layer3_profile_id;
  if not found or not mp.enabled or mp.paused or coalesce((mp.quality_benchmark->>'pass')::boolean,false) is not true
     or not ('source_pattern'=any(mp.allowed_task_classes)) then
    raise exception 'source-pattern model profile not executable' using errcode='22023';
  end if;
  if not exists(
    select 1 from pipeline.layer2_source_profiles lp
    join pipeline.sources s on s.id=lp.source_id
    where lp.id=r.source_profile_id and s.provider_id=r.entity_id
      and lp.domain='course_facts' and lp.enabled and not lp.paused
  ) then raise exception 'source-pattern Layer 2 profile mismatch' using errcode='22023'; end if;

  update pipeline.refresh_requests set status='queued',schedule_error=null where id=r.id and status in('failed','blocked');

  return jsonb_build_object(
    'ok',true,'executable',true,'request_id',r.id,
    'evidence_id',r.evidence_id,'entity_type','provider','entity_id',r.entity_id,
    'task_class','source_pattern','profile_id',r.layer3_profile_id,
    'revalidation_ref',r.revalidation_ref,'source_profile_id',r.source_profile_id,
    'source_id',r.source_id,'evidence_source_url',e.source_url,'evidence_hash',e.content_hash,
    'layer2_state',jsonb_build_object(
      'status','layer3_required',
      'evidence_selection_reason','governed_source_pattern_refresh_request',
      'source_pattern_request_id',r.id,
      'source_profile_id',r.source_profile_id
    )
  );
end
$function$
;

-- svc_coursefacts_apply_record(uuid,uuid,text,text,text,text,text,jsonb,boolean)
CREATE OR REPLACE FUNCTION public.svc_coursefacts_apply_record(p_source_id uuid, p_evidence_id uuid, p_provider_cricos text, p_course_cricos text, p_source_record_id text, p_source_url text, p_content_hash text, p_payload jsonb, p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_provider uuid;v_course uuid;v_record uuid;v_test uuid;r jsonb;
 v_fee_year int;v_amount numeric;v_currency text;v_basis text;v_fee_key text;v_audience text;
 v_links int:=0;v_fees int:=0;v_intakes int:=0;v_english int:=0;
begin
 if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required';end if;
 select pr.provider_id into v_provider from catalogue.provider_registrations pr join catalogue.providers p on p.id=pr.provider_id join ref.countries c on c.id=p.country_id where c.iso_alpha2='AU' and lower(pr.registration_scheme)='cricos' and upper(btrim(pr.registration_code))=upper(btrim(p_provider_cricos)) and coalesce(pr.status,'active') not in ('inactive','cancelled','archived') order by pr.checked_at desc nulls last limit 1;
 if v_provider is null then raise exception 'provider CRICOS not resolved';end if;
 select cr.course_id into v_course from catalogue.course_registrations cr join catalogue.courses c on c.id=cr.course_id where c.provider_id=v_provider and lower(cr.scheme)='cricos' and upper(btrim(cr.registration_code))=upper(btrim(p_course_cricos)) limit 1;
 if v_course is null then raise exception 'course CRICOS not resolved';end if;
 if p_apply and security.layer4_entity_or_parent_blocked('course',v_course,'operational') then raise exception 'course operationally blocked by Layer 4' using errcode='42501'; end if;
 if coalesce(btrim(p_source_record_id),'')='' or coalesce(btrim(p_source_url),'')='' or coalesce(btrim(p_content_hash),'')='' then raise exception 'source identity/evidence fields required';end if;
 if not exists(select 1 from pipeline.course_fact_source_qualifications q where q.source_id=p_source_id and q.provider_cricos=upper(btrim(p_provider_cricos)) and q.qualification_status in ('qualified','bounded')) then raise exception 'source not qualified for AU course facts';end if;
 if not p_apply then return jsonb_build_object('resolved',true,'provider_id',v_provider,'course_id',v_course,'would_apply_link',nullif(btrim(p_payload->>'course_url'),'') is not null,'would_apply_fee',p_payload ? 'fee_amount','would_apply_intakes',coalesce(jsonb_array_length(coalesce(p_payload->'intakes','[]'::jsonb)),0),'would_apply_english',coalesce(jsonb_array_length(coalesce(p_payload->'english_requirements','[]'::jsonb)),0));end if;
 insert into pipeline.course_fact_source_records(source_id,source_record_id,source_url,provider_cricos,course_cricos,content_hash,evidence_id,parsed_payload,status,observed_at)
 values(p_source_id,p_source_record_id,p_source_url,upper(btrim(p_provider_cricos)),upper(btrim(p_course_cricos)),p_content_hash,p_evidence_id,p_payload,'observed',now())
 on conflict(source_id,source_record_id,content_hash) do update set evidence_id=coalesce(excluded.evidence_id,pipeline.course_fact_source_records.evidence_id),parsed_payload=excluded.parsed_payload,observed_at=now(),error_text=null returning id into v_record;
 if nullif(btrim(p_payload->>'course_url'),'') is not null then
   insert into catalogue.course_links(course_id,link_type,url,audience,label,is_primary,status,source_id,evidence_id,confidence,last_verified_at,updated_at)
   values(v_course,coalesce(nullif(btrim(p_payload->>'link_type'),''),'official_course'),btrim(p_payload->>'course_url'),coalesce(nullif(btrim(p_payload->>'audience'),''),'international'),'Official provider course page',false,'active',p_source_id,p_evidence_id,1,now(),now())
   on conflict(course_id,link_type,url) do update set audience=excluded.audience,label=excluded.label,status='active',source_id=excluded.source_id,evidence_id=excluded.evidence_id,confidence=1,last_verified_at=now(),updated_at=now();
   v_links:=1;
 end if;
 if p_payload ? 'fee_amount' then
   v_fee_year:=nullif(p_payload->>'fee_year','')::int;v_amount:=nullif(p_payload->>'fee_amount','')::numeric;v_currency:=coalesce(nullif(btrim(p_payload->>'currency_code'),''),'AUD');v_basis:=nullif(btrim(p_payload->>'fee_basis'),'');v_audience:=coalesce(nullif(btrim(p_payload->>'audience'),''),'international');v_fee_key:=coalesce(nullif(btrim(p_payload->>'fee_key'),''),lower(upper(btrim(p_course_cricos))||':'||v_audience||':'||coalesce(v_fee_year::text,'current')||':'||coalesce(v_basis,'tuition')));
   if v_amount is null or v_amount<=0 then raise exception 'positive fee amount required';end if;
   if not exists(select 1 from ref.currencies where code=v_currency) then raise exception 'currency not seeded: %',v_currency;end if;
   insert into catalogue.course_fees(course_id,fee_year,audience,fee_type,amount,currency_code,basis,notes,source_id,evidence_id,confidence,campus_id,source_fee_key,status,last_verified_at,source_snapshot_at,updated_at)
   values(v_course,v_fee_year,v_audience,'provider_current_tuition',v_amount,v_currency,v_basis,p_payload->>'fee_notes',p_source_id,p_evidence_id,1,null,v_fee_key,'active',now(),now(),now())
   on conflict(course_id,source_id,source_fee_key) where source_id is not null and source_fee_key is not null do update set fee_year=excluded.fee_year,audience=excluded.audience,fee_type=excluded.fee_type,amount=excluded.amount,currency_code=excluded.currency_code,basis=excluded.basis,notes=excluded.notes,evidence_id=excluded.evidence_id,confidence=1,status='active',last_verified_at=now(),source_snapshot_at=now(),updated_at=now();
   v_fees:=1;
 end if;
 for r in select value from jsonb_array_elements(coalesce(p_payload->'intakes','[]'::jsonb)) loop
   if nullif(btrim(r->>'intake_label'),'') is null then raise exception 'intake_label required';end if;
   insert into catalogue.course_intakes(course_id,intake_year,intake_label,start_date,application_deadline,campus_id,status,source_id,evidence_id,confidence,source_intake_key)
   values(v_course,nullif(r->>'intake_year','')::int,r->>'intake_label',nullif(r->>'start_date','')::date,nullif(r->>'application_deadline','')::date,null,coalesce(nullif(r->>'status',''),'active'),p_source_id,p_evidence_id,1,coalesce(nullif(r->>'source_intake_key',''),lower(upper(btrim(p_course_cricos))||':'||coalesce((r->>'intake_year'),'current')||':'||(r->>'intake_label'))))
   on conflict(course_id,source_id,source_intake_key) where source_id is not null and source_intake_key is not null do update set intake_year=excluded.intake_year,intake_label=excluded.intake_label,start_date=excluded.start_date,application_deadline=excluded.application_deadline,status=excluded.status,evidence_id=excluded.evidence_id,confidence=1;
   v_intakes:=v_intakes+1;
 end loop;
 for r in select value from jsonb_array_elements(coalesce(p_payload->'english_requirements','[]'::jsonb)) loop
   select id into v_test from ref.english_tests where code=upper(btrim(r->>'test_code')) limit 1;
   if v_test is null then raise exception 'english test not seeded: %',r->>'test_code';end if;
   insert into catalogue.course_english_requirements(course_id,english_test_id,overall_score,component_scores,notes,source_id,evidence_id,confidence,source_requirement_key,status,valid_from,valid_to,last_verified_at)
   values(v_course,v_test,nullif(r->>'overall_score','')::numeric,coalesce(r->'component_scores','{}'::jsonb),r->>'notes',p_source_id,p_evidence_id,1,coalesce(nullif(r->>'source_requirement_key',''),lower(upper(btrim(p_course_cricos))||':'||upper(btrim(r->>'test_code')))),coalesce(nullif(r->>'status',''),'active'),nullif(r->>'valid_from','')::date,nullif(r->>'valid_to','')::date,now())
   on conflict(course_id,english_test_id) do update set overall_score=excluded.overall_score,component_scores=excluded.component_scores,notes=excluded.notes,source_id=excluded.source_id,evidence_id=excluded.evidence_id,confidence=1,source_requirement_key=excluded.source_requirement_key,status=excluded.status,valid_from=excluded.valid_from,valid_to=excluded.valid_to,last_verified_at=now();
   v_english:=v_english+1;
 end loop;
 update pipeline.course_fact_source_records set status='applied',applied_at=now() where id=v_record;
 return jsonb_build_object('resolved',true,'provider_id',v_provider,'course_id',v_course,'links_applied',v_links,'fees_applied',v_fees,'intakes_applied',v_intakes,'english_applied',v_english,'source_record_id',v_record);
end $function$
;

-- publishing.course_publication_readiness_v1(uuid,text)
CREATE OR REPLACE FUNCTION publishing.course_publication_readiness_v1(p_course_id uuid, p_profile_code text DEFAULT 'pilot-course-positive-v1'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'publishing', 'catalogue', 'search', 'ref', 'pipeline', 'pg_temp'
AS $function$
declare v_profile_active boolean:=false; v_approved boolean:=false; v_active boolean:=false; v_country text; v_course_key text; v_provider_key text; v_course_code text; v_title text; v_projected boolean:=false; v_evidence bigint:=0; v_blockers text[]:='{}'::text[]; v_exists boolean:=false; v_layer4_publication_blocked boolean:=false;
begin
select exists(select 1 from publishing.publication_profiles pp where pp.profile_code=p_profile_code and pp.entity_type='course' and pp.profile_status='active') into v_profile_active;
select true,c.lifecycle_status='active',trim(co.iso_alpha2::text),c.stable_key,p.stable_key,c.course_code,c.canonical_title,exists(select 1 from search.course_documents d where d.course_id=c.id)
into v_exists,v_active,v_country,v_course_key,v_provider_key,v_course_code,v_title,v_projected from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id where c.id=p_course_id;
if not coalesce(v_exists,false) then return jsonb_build_object('eligible',false,'profile_code',p_profile_code,'course_id',p_course_id,'blockers',jsonb_build_array('course_not_found')); end if;
select exists(select 1 from publishing.publication_approvals pa where pa.profile_code=p_profile_code and pa.entity_id=p_course_id and pa.approval_status='approved') into v_approved;
select coalesce(sum(el.link_count),0)::bigint into v_evidence from pipeline.evidence_entity_links el where el.entity_type='course' and el.entity_id=p_course_id;
select security.layer4_entity_or_parent_blocked('course',p_course_id,'publication') into v_layer4_publication_blocked;
if v_layer4_publication_blocked then v_blockers:=array_append(v_blockers,'layer4_publication_block'); end if;
if not v_profile_active then v_blockers:=array_append(v_blockers,'profile_not_active'); end if;
if not v_approved then v_blockers:=array_append(v_blockers,'not_explicitly_approved'); end if;
if not v_active then v_blockers:=array_append(v_blockers,'lifecycle_not_active'); end if;
if v_country is null or v_country not in ('AU','NZ') then v_blockers:=array_append(v_blockers,'country_out_of_scope'); end if;
if nullif(trim(v_course_key),'') is null then v_blockers:=array_append(v_blockers,'course_stable_key_missing'); end if;
if nullif(trim(v_provider_key),'') is null then v_blockers:=array_append(v_blockers,'provider_stable_key_missing'); end if;
if nullif(trim(v_course_code),'') is null then v_blockers:=array_append(v_blockers,'course_code_missing'); end if;
if nullif(trim(v_title),'') is null then v_blockers:=array_append(v_blockers,'course_title_missing'); end if;
if not v_projected then v_blockers:=array_append(v_blockers,'search_not_projected'); end if;
if v_evidence<1 then v_blockers:=array_append(v_blockers,'governed_evidence_missing'); end if;
return jsonb_build_object('eligible',cardinality(v_blockers)=0,'profile_code',p_profile_code,'course_id',p_course_id,'country',v_country,'signals',jsonb_build_object('layer4_publication_blocked',v_layer4_publication_blocked,'profile_active',v_profile_active,'explicitly_approved',v_approved,'lifecycle_active',v_active,'stable_course_identity',nullif(trim(v_course_key),'') is not null,'stable_provider_identity',nullif(trim(v_provider_key),'') is not null,'course_code_present',nullif(trim(v_course_code),'') is not null,'course_title_present',nullif(trim(v_title),'') is not null,'search_projected',v_projected,'governed_evidence_links',v_evidence),'blockers',to_jsonb(v_blockers));
end $function$
;

-- security.admin_data_quality_read(text,jsonb)
CREATE OR REPLACE FUNCTION security.admin_data_quality_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'auth'
AS $function$
declare v_rank int:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  if p_operation='data_quality_overview' then return security.data_quality_overview_cached(p_args); end if;
  if p_operation='data_quality_exceptions' then return security.data_quality_exceptions_impl(p_args); end if;
  if p_operation='data_quality_quarantine' then
    if v_rank<3 then raise exception 'curator role required for quarantine details' using errcode='42501'; end if;
    return security.data_quality_quarantine_impl(p_args);
  end if;
  raise exception 'unsupported data quality operation: %',p_operation using errcode='22023';
end
$function$
;

commit;
