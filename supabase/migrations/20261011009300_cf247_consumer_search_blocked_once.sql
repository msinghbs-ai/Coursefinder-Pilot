-- CF-247 (11 Oct 2026) Fix 7: Zoho, website and search course queries timed out (60 s), and with them every coverage-admit run
-- since 10 Oct 14:10 UTC (the admission takes a consumer-API snapshot before and after, so each run was cancelled and rolled back).
-- Cause: the check "not exists (select 1 from security.layer4_search_blocked_courses ...)" was planned as a nested loop that rebuilt
-- the blocked-course list once per candidate course (5,479 times for one search). The list grew from a handful of rows to 6,502 when
-- R5 (20261010007000) added every course that is not active. Fix: the same rule written as "course_id not in (the list)", which the
-- database builds once per query and looks up by hash (60.9 s -> 0.5 s for the same 5,479 courses). A null course id is treated as
-- before (not blocked). The list itself (the view) is unchanged; nothing is dropped or deleted. md5-checked before and after.
do $guard$
declare v_expected jsonb := '{"api.courses_list(uuid,character,text,text,integer,integer)": "d84b603a2b24396d34f59b154b84b393", "api.providers_list(character,integer,integer)": "791a0626d43cd8ca5b1ad69a4e339118", "api.search_courses(text,character,text,boolean,integer)": "af119d70285a04edbd880ac353301b2b", "api.vector_candidates(vector,text,character,text,integer)": "5a5c227814dce91242c997beda346e9c", "api.website_course_lookup_preview_v1(text)": "c50a266e4e6ecc3d1199774c90439dcb", "api.website_course_search_preview_v1(text,text[],text[],text,text[],text[],text[],text[],numeric,numeric,boolean,boolean,boolean,text,integer,integer)": "8fc2c86eb11b3e8a3a81e54475a136b0", "api.website_course_search_v1(text,text[],text[],text[],text[],text[],boolean,boolean,integer,integer)": "cd10cc2273bc70db6f65d6f6dd7d1d17", "api.website_course_search_v2(text,text[],text[],text[],text[],text[],boolean,numeric,boolean,boolean,boolean,text,integer,integer)": "af1f072e7eeb0a5a47faecb985396a19", "api.zoho_course_candidates_v1(text,text[],text[],text[],text[],text[],boolean,boolean,integer)": "28f190eaec28ad7ae9524c84011537f5", "api.zoho_course_lookup_v1(text)": "a44a9ae48251a461cbbfb7407a49e770", "api.zoho_course_search_v1(text,text[],text[],text[],boolean,timestamp with time zone,integer,integer)": "be1376c3814813e85050686e5e2e4329", "api.zoho_course_search_v2(text,text[],text[],text[],text[],text[],text[],boolean,boolean,boolean,boolean,boolean,boolean,integer[],text[],text[],numeric,numeric,numeric,numeric,text[],timestamp with time zone,integer,integer)": "973c0ef77272b00b33ff4921c7c88c41", "api.zoho_filter_options_v1(text,text,text,integer,integer)": "adb29fcfdca6180d8db6e1494683c79d", "api.zoho_sync_manifest_v1(timestamp with time zone)": "ca03f289970122428561fe8c32ee35e2", "public.website_edge_course_search_v1(jsonb,integer,integer)": "4cfc7465e24cc3e00391c4876a1f88b0", "public.website_v2_course_search(jsonb,integer,integer,text)": "9df1297f579b0e142d1cc2db7e023629"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

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
  and (c.id is null or c.id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null))
  and (p_provider_id is null or c.provider_id=p_provider_id)
  and (p_country is null or co.iso_alpha2=p_country)
  and (p_level_code is null or sl.code=p_level_code)
  and (p_publication is null or c.publication_status=p_publication)
group by c.id,p.canonical_name,p.display_name,sl.code
order by c.canonical_title
limit least(greatest(coalesce(p_limit,100),1),500) offset greatest(coalesce(p_offset,0),0)
$function$;

CREATE OR REPLACE FUNCTION api.providers_list(p_country character DEFAULT NULL::bpchar, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, stable_key text, canonical_name text, display_name text, country_code character, publication_status text, course_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'catalogue', 'ref', 'security'
AS $function$
select p.id,p.stable_key,p.canonical_name,p.display_name,c.iso_alpha2,p.publication_status,count(cr.id)::bigint
from catalogue.providers p join ref.countries c on c.id=p.country_id left join catalogue.courses cr on cr.provider_id=p.id and (cr.id is null or cr.id not in (select cf_course_block.course_id from security.layer4_search_blocked_courses cf_course_block where cf_course_block.course_id is not null))
where security.current_role_rank()>=1 and not exists (select 1 from security.layer4_search_blocked_providers cf_block where cf_block.provider_id=p.id) and (p_country is null or c.iso_alpha2=p_country)
group by p.id,c.iso_alpha2
order by coalesce(p.display_name,p.canonical_name)
limit least(greatest(coalesce(p_limit,100),1),500) offset greatest(coalesce(p_offset,0),0)
$function$;

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
where security.current_role_rank()>=1 and (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null)) and d.publication_status in ('published','internal')
 and (p_country is null or co.iso_alpha2=p_country)
 and (p_level_code is null or sl.code=p_level_code)
 and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
 and (coalesce(trim(p_query),'')='' or d.search_tsv @@ websearch_to_tsquery('english',p_query))
order by ts_rank_cd(d.search_tsv,websearch_to_tsquery('english',coalesce(p_query,''))) desc,d.course_title
limit least(greatest(coalesce(p_limit,20),1),50)
$function$;

CREATE OR REPLACE FUNCTION api.vector_candidates(p_embedding extensions.vector, p_profile_code text, p_country character DEFAULT NULL::bpchar, p_level_code text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS TABLE(course_id uuid, distance double precision)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'search', 'ref', 'security', 'extensions'
AS $function$
select e.course_id,(e.embedding<=>p_embedding)::double precision
from search.course_embeddings e join search.profiles sp on sp.id=e.profile_id join search.course_documents d on d.course_id=e.course_id
join ref.countries co on co.id=d.country_id left join ref.study_levels sl on sl.id=d.study_level_id
where security.current_role_rank()>=1 and (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null)) and sp.code=p_profile_code and (p_country is null or co.iso_alpha2=p_country) and (p_level_code is null or sl.code=p_level_code)
order by e.embedding<=>p_embedding limit least(greatest(coalesce(p_limit,50),1),100)
$function$;

CREATE OR REPLACE FUNCTION api.website_course_lookup_preview_v1(p_identifier text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'api', 'search', 'pg_catalog'
AS $function$
with hit as (
  select d.*, 'exact_course_code'::text as match_type, 0 as match_priority
  from search.course_documents d
  where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null))
    and nullif(trim(p_identifier),'') is not null
    and lower(d.course_code)=lower(trim(p_identifier))
  union all
  select d.*, 'exact_course_id'::text as match_type, 1 as match_priority
  from search.course_documents d
  where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null))
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
$function$;

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
 where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null))
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
 where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null))
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
$function$;

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
  where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null))
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
$function$;

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
  where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null))
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
$function$;

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
    where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null))
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
$function$;

CREATE OR REPLACE FUNCTION api.zoho_course_lookup_v1(p_identifier text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'api'
AS $function$
  with x as (
    select d.* from search.course_documents d
    where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null))
      and (lower(d.course_stable_key)=lower(btrim(p_identifier))
       or lower(d.course_code)=lower(btrim(p_identifier)))
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
      'fee_used',security.course_fee_used_v1(course_id),
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
$function$;

CREATE OR REPLACE FUNCTION api.zoho_course_search_v1(p_query text DEFAULT NULL::text, p_country_codes text[] DEFAULT NULL::text[], p_provider_ids text[] DEFAULT NULL::text[], p_subdivision_codes text[] DEFAULT NULL::text[], p_has_scholarship boolean DEFAULT NULL::boolean, p_changed_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'api'
AS $function$
  with base as (
    select d.*
    from search.course_documents d
    where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null))
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
$function$;

CREATE OR REPLACE FUNCTION api.zoho_course_search_v2(p_query text DEFAULT NULL::text, p_country_codes text[] DEFAULT NULL::text[], p_provider_ids text[] DEFAULT NULL::text[], p_subdivision_codes text[] DEFAULT NULL::text[], p_study_level_codes text[] DEFAULT NULL::text[], p_primary_field_codes text[] DEFAULT NULL::text[], p_delivery_modes text[] DEFAULT NULL::text[], p_has_scholarship boolean DEFAULT NULL::boolean, p_has_intake boolean DEFAULT NULL::boolean, p_has_english boolean DEFAULT NULL::boolean, p_has_provider_current_tuition boolean DEFAULT NULL::boolean, p_has_regulatory_tuition boolean DEFAULT NULL::boolean, p_has_link boolean DEFAULT NULL::boolean, p_intake_years integer[] DEFAULT NULL::integer[], p_intake_labels text[] DEFAULT NULL::text[], p_english_test_codes text[] DEFAULT NULL::text[], p_min_provider_annual_tuition numeric DEFAULT NULL::numeric, p_max_provider_annual_tuition numeric DEFAULT NULL::numeric, p_min_regulatory_total_tuition numeric DEFAULT NULL::numeric, p_max_regulatory_total_tuition numeric DEFAULT NULL::numeric, p_publication_statuses text[] DEFAULT NULL::text[], p_changed_since timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'api'
AS $function$
with base as (
  select d.*
  from search.course_documents d
  where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null))
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
    'fee_used',security.course_fee_used_v1(course_id),
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
$function$;

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
             where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null))
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
                 where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null))
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
             where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null))
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
                 where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null))
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
$function$;

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
      'count',(select count(*) from search.course_documents d where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null)) and (p_changed_since is null or greatest(d.updated_at,d.source_updated_at,d.generated_at) > p_changed_since)),
      'max_updated_at',(select max(greatest(d.updated_at,d.source_updated_at,d.generated_at)) from search.course_documents d where (d.course_id is null or d.course_id not in (select cf_block.course_id from security.layer4_search_blocked_courses cf_block where cf_block.course_id is not null)))
    ),
    'scholarships',jsonb_build_object(
      'count',(select count(*) from scholarship.scholarships s where not exists (select 1 from security.layer4_search_blocked_scholarships cf_block where cf_block.scholarship_id=s.id) and s.lifecycle_status='active' and s.publication_status='published' and (p_changed_since is null or s.updated_at > p_changed_since)),
      'max_updated_at',(select max(s.updated_at) from scholarship.scholarships s where not exists (select 1 from security.layer4_search_blocked_scholarships cf_block where cf_block.scholarship_id=s.id) and s.lifecycle_status='active' and s.publication_status='published')
    ),
    'ordering',jsonb_build_object(
      'providers','name_asc,provider_id_asc',
      'courses','title_asc,course_id_asc',
      'scholarships','name_asc,scholarship_id_asc'
    ),
    'generated_at',now()
  );
$function$;

CREATE OR REPLACE FUNCTION public.website_edge_course_search_v1(p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1, p_page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'catalogue', 'ref', 'security', 'api'
AS $function$
declare
  f jsonb := coalesce(p_filters,'{}'::jsonb);
  v_page int := coalesce(p_page,1);
  v_size int := coalesce(p_page_size,20);
  v_kw text := nullif(btrim(coalesce(f->>'keyword','')),'');
  v_countries text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(coalesce(f->'country_codes',f->'country_code'))) x);
  v_areas text[] := api.website_text_array(f->'study_area_codes');
  v_levels text[] := api.website_text_array(f->'study_level_codes');
  v_subdivs text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(f->'subdivision_codes')) x);
  v_cities text[] := (select array_agg(lower(x)) from unnest(api.website_text_array(coalesce(f->'cities',f->'city'))) x);
  v_postcodes text[] := api.website_text_array(f->'postcodes');
  v_providers text[] := api.website_text_array(f->'provider_ids');
  v_groups text[] := (select array_agg(lower(regexp_replace(btrim(x),'^au_','','i'))) from unnest(api.website_text_array(coalesce(f->'university_groups',f->'university_group'))) x);
  v_modes text[] := api.website_text_array(f->'delivery_modes');
  v_min numeric := nullif(f->>'tuition_annual_min','')::numeric;
  v_max numeric := nullif(f->>'tuition_annual_max','')::numeric;
  v_result jsonb;
begin
  if v_page < 1 then raise exception 'INVALID_INPUT: page must be >= 1' using errcode='22023'; end if;
  if v_size < 1 or v_size > 50 then raise exception 'INVALID_INPUT: page_size must be 1-50' using errcode='22023'; end if;
  if (v_min is not null and v_min < 0) or (v_max is not null and v_max < 0) then raise exception 'INVALID_INPUT: tuition bounds must be >= 0' using errcode='22023'; end if;

  with base as (
    select d.*,
      round(c.duration_value * case lower(coalesce(c.duration_unit,'')) when 'weeks' then 12.0/52 when 'months' then 1 when 'years' then 12 else null end)::int as duration_months,
      case lower(coalesce(c.duration_unit,'')) when 'weeks' then c.duration_value when 'months' then c.duration_value*52/12 when 'years' then c.duration_value*52 end as duration_weeks
    from search.course_documents d
    left join catalogue.courses c on c.id = d.course_id
    where (d.course_id is null or d.course_id not in (select b.course_id from security.layer4_search_blocked_courses b where b.course_id is not null))
      and (v_kw is null
           or d.search_tsv @@ websearch_to_tsquery('english', v_kw)
           or d.course_title ilike '%'||v_kw||'%'
           or d.provider_name ilike '%'||v_kw||'%'
           or lower(d.course_code) = lower(v_kw)
           or lower(d.course_stable_key) = lower(v_kw))
      and (v_countries is null or d.country_code = any(v_countries))
      and (v_areas is null or d.primary_field_code = any(v_areas))
      and (v_levels is null or d.study_level_code = any(v_levels))
      and (v_subdivs is null or d.subdivision_codes && v_subdivs)
      and (v_providers is null or d.provider_stable_key = any(v_providers))
      and (v_groups is null or exists (select 1 from catalogue.provider_collection_memberships gm join ref.institution_collections gic on gic.id=gm.collection_id
            where gm.provider_id=d.provider_id and gm.status='active' and (gm.valid_to is null or gm.valid_to>=current_date)
              and gic.collection_type='university_group' and gic.status='active' and replace(gic.code,'au_','') = any(v_groups)))
      and (v_modes is null or d.delivery_modes && v_modes)
      and (not coalesce((f->>'has_intake')::boolean,false) or d.has_intake)
      and (not coalesce((f->>'has_english')::boolean,false) or d.has_english)
      and (not coalesce((f->>'has_official_url')::boolean,false) or d.has_link)
      and (v_cities is null and v_postcodes is null or exists (
            select 1 from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id left join pipeline.campus_regional_class rc on rc.campus_id = k.id
            where cc.course_id = d.course_id
              and (v_cities is null or lower(btrim(k.city)) = any(v_cities) or lower(rc.metro_area) = any(v_cities))
              and (v_postcodes is null or btrim(k.postcode) = any(v_postcodes))))
  ), priced as (
    select b.*, t.*
    from base b
    cross join lateral (
      select
        case when pt.amount is not null then pt.amount else b.regulatory_tuition_amount end as t_amount,
        case when pt.amount is not null then pt.currency else b.regulatory_tuition_currency end as t_currency,
        case when pt.amount is not null then
               case when pt.basis ~* 'total|course' and pt.basis !~* 'annual' then 'course_total'
                    when pt.basis ~* 'indicative' then 'indicative_annual'
                    when pt.basis ~* 'annual|per.?year|yearly' then 'annual'
                    else 'unspecified' end
             when b.regulatory_tuition_amount is not null then 'course_total' end as t_basis,
        case when pt.amount is not null then 'provider_current' when b.regulatory_tuition_amount is not null then 'regulatory_registered' end as t_source,
        pt.basis as t_basis_label
      from (select (o->>'amount')::numeric amount, o->>'currency' currency, o->>'basis' basis
            from jsonb_array_elements(coalesce(b.provider_tuition_options,'[]'::jsonb)) o
            where (o->>'amount') is not null
            order by (o->>'fee_year') desc nulls last limit 1) pt
      right join (select 1) one on true
    ) t
  ), annualised as (
    select p.*,
      case when p.t_basis in ('annual','indicative_annual') then p.t_amount
           when p.t_basis = 'course_total' and p.duration_weeks >= 52 then round(p.t_amount / (p.duration_weeks/52.0))
      end as annual_amount,
      (p.t_basis = 'course_total' and p.duration_weeks >= 52) as annual_is_derived
    from priced p
  ), filtered as (
    select * from annualised a
    where (not coalesce((f->>'has_tuition')::boolean,false) or a.t_amount is not null)
      and (v_min is null or a.annual_amount >= v_min)
      and (v_max is null or a.annual_amount <= v_max)
  ), counted as (select count(*) total from filtered),
  paged as (
    select * from filtered order by lower(course_title), course_stable_key
    limit v_size offset (v_page-1)*v_size
  )
  select jsonb_build_object(
    'contract_version','website-search-v1',
    'total',(select total from counted),
    'page',v_page,'page_size',v_size,'sort','title_asc',
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'course_id',p.course_stable_key,
      'course_code',p.course_code,
      'title',p.course_title,
      'provider',jsonb_build_object('provider_id',p.provider_stable_key,'name',security.provider_presentable_name(p.provider_name),'legal_name',p.provider_name,'university_groups',security.provider_university_groups(p.provider_id)),
      'campus_city',(select security.place_presentable(k.city) from catalogue.course_campuses cc join catalogue.campuses k on k.id=cc.campus_id left join pipeline.campus_regional_class rc on rc.campus_id=k.id
                     where cc.course_id=p.course_id and nullif(btrim(k.city),'') is not null
                     order by (v_cities is not null and (lower(btrim(k.city)) = any(v_cities) or lower(rc.metro_area) = any(v_cities))) desc, (v_postcodes is not null and btrim(k.postcode) = any(v_postcodes)) desc, cc.is_primary desc nulls last, k.city limit 1),
      'campus_metro_area',(select rc.metro_area from catalogue.course_campuses cc join catalogue.campuses k on k.id=cc.campus_id left join pipeline.campus_regional_class rc on rc.campus_id=k.id
                     where cc.course_id=p.course_id and nullif(btrim(k.city),'') is not null
                     order by (v_cities is not null and (lower(btrim(k.city)) = any(v_cities) or lower(rc.metro_area) = any(v_cities))) desc, (v_postcodes is not null and btrim(k.postcode) = any(v_postcodes)) desc, cc.is_primary desc nulls last, k.city limit 1),
      'campuses',coalesce((select jsonb_agg(jsonb_build_object('city',security.place_presentable(k.city),'postcode',k.postcode,'subdivision_code',s.code,'is_primary',coalesce(cc.is_primary,false),'metro_area',rc.metro_area,'regional_category',rc.category,'regional_category_name',rc.category_name)
                           order by (v_cities is not null and (lower(btrim(k.city)) = any(v_cities) or lower(rc.metro_area) = any(v_cities))) desc, cc.is_primary desc nulls last, k.city)
                           from catalogue.course_campuses cc join catalogue.campuses k on k.id=cc.campus_id
                           left join ref.subdivisions s on s.id=k.subdivision_id left join pipeline.campus_regional_class rc on rc.campus_id=k.id
                           where cc.course_id=p.course_id),'[]'::jsonb),
      'study_level',jsonb_build_object('code',p.study_level_code,'name',(select sl.name from ref.study_levels sl where sl.code=p.study_level_code limit 1)),
      'study_area',jsonb_build_object('code',p.primary_field_code,'name',p.primary_field_name),
      'duration_months',p.duration_months,
      'tuition',case when p.t_amount is null then null else jsonb_build_object(
          'amount',p.t_amount,'currency',p.t_currency,'basis',p.t_basis,'basis_label',p.t_basis_label,'source',p.t_source,
          'annual_amount',p.annual_amount,'annual_is_derived',coalesce(p.annual_is_derived,false)) end,
      'intakes',coalesce((select jsonb_agg(distinct jsonb_build_object('label',i->>'label','year',i->'year','start_date',i->'start_date','application_deadline',i->'application_deadline'))
                          from jsonb_array_elements(coalesce(p.intake_options,'[]'::jsonb)) i where nullif(i->>'label','') is not null),'[]'::jsonb),
      'english_requirements',coalesce((select jsonb_agg(jsonb_build_object('test_code',e->>'test_code','test_name',e->>'test_name','min_overall_score',e->'overall_score','min_band_score',(select min(z.v::numeric) from jsonb_each_text(case when jsonb_typeof(e->'component_scores')='object' then e->'component_scores' else '{}'::jsonb end) z(k2,v) where z.v ~ '^[0-9]+(\.[0-9]+)?$')))
                          from jsonb_array_elements(coalesce(p.english_requirement_options,'[]'::jsonb)) e),'[]'::jsonb),
      'entry_requirements',jsonb_build_object('summary',(select 'English: '||string_agg(
                   case e->>'test_code' when 'IELTS' then 'IELTS '||to_char((e->>'overall_score')::numeric,'FM90.0')
                          ||coalesce(' (no band below '||to_char((select min(z.v::numeric) from jsonb_each_text(case when jsonb_typeof(e->'component_scores')='object' then e->'component_scores' else '{}'::jsonb end) z(k2,v) where z.v ~ '^[0-9]+(\.[0-9]+)?$'),'FM90.0')||')','')
                        when 'PTE' then 'PTE Academic '||trim(to_char((e->>'overall_score')::numeric,'FM999'))
                        when 'TOEFL_IBT' then 'TOEFL iBT '||trim(to_char((e->>'overall_score')::numeric,'FM999'))
                        else coalesce(e->>'test_name',e->>'test_code')||' '||(e->>'overall_score') end, ', '
                   order by case e->>'test_code' when 'IELTS' then 1 when 'PTE' then 2 when 'TOEFL_IBT' then 3 else 4 end)
                 from jsonb_array_elements(coalesce(p.english_requirement_options,'[]'::jsonb)) e where (e->>'overall_score') ~ '^[0-9]+(\.[0-9]+)?$'),
                 'basis',case when jsonb_array_length(coalesce(p.english_requirement_options,'[]'::jsonb))>0 then 'english_only' end),
      'official_url',p.official_course_url,
      'delivery_modes',to_jsonb(p.delivery_modes),
      'subdivision_codes',to_jsonb(p.subdivision_codes),
      'publication_status',p.publication_status,
      'freshness',jsonb_build_object('projection_updated_at',p.updated_at,'source_updated_at',p.source_updated_at)
    ) order by lower(p.course_title), p.course_stable_key) from paged p),'[]'::jsonb)
  ) into v_result;
  return v_result;
end $function$;

CREATE OR REPLACE FUNCTION public.website_v2_course_search(p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1, p_page_size integer DEFAULT 20, p_sort text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'search', 'catalogue', 'ref', 'pipeline', 'security', 'api'
AS $function$
declare
  f jsonb := coalesce(p_filters,'{}'::jsonb);
  v_page int := coalesce(p_page,1);
  v_size int := coalesce(p_page_size,20);
  v_kw text := nullif(btrim(coalesce(f->>'keyword','')),'');
  v_q tsquery;
  v_countries text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(coalesce(f->'country_codes',f->'country_code'))) x);
  v_areas text[] := api.website_text_array(f->'study_area_codes');
  v_levels text[] := api.website_text_array(f->'study_level_codes');
  v_subdivs text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(f->'subdivision_codes')) x);
  v_cities text[] := (select array_agg(lower(x)) from unnest(api.website_text_array(coalesce(f->'cities',f->'city'))) x);
  v_postcodes text[] := api.website_text_array(f->'postcodes');
  v_regional int[] := (select array_agg(x::int) from unnest(api.website_text_array(f->'regional_categories')) x where x ~ '^[1-3]$');
  v_providers text[] := api.website_text_array(f->'provider_ids');
  v_groups text[] := (select array_agg(lower(regexp_replace(btrim(x),'^au_','','i'))) from unnest(api.website_text_array(coalesce(f->'university_groups',f->'university_group'))) x);
  v_modes text[] := api.website_text_array(f->'delivery_modes');
  v_months int[] := (select array_agg(x::int) from unnest(api.website_text_array(f->'intake_months')) x where x ~ '^([1-9]|1[0-2])$');
  v_tests text[] := (select array_agg(upper(x)) from unnest(api.website_text_array(f->'english_test_codes')) x);
  v_score_max numeric := nullif(f->>'english_score_max','')::numeric;
  v_min numeric := nullif(f->>'tuition_annual_min','')::numeric;
  v_max numeric := nullif(f->>'tuition_annual_max','')::numeric;
  v_changed timestamptz := nullif(f->>'changed_since','')::timestamptz;
  v_sort text := coalesce(nullif(p_sort,''), case when nullif(btrim(coalesce(f->>'keyword','')),'') is not null then 'relevance' else 'title_asc' end);
  v_known text[] := array['keyword','country_codes','country_code','study_area_codes','study_level_codes','subdivision_codes','cities','city','postcodes','regional_categories',
                          'provider_ids','university_groups','university_group','delivery_modes','intake_months','english_test_codes','english_score_max',
                          'tuition_annual_min','tuition_annual_max','has_intake','has_english','has_official_url','has_scholarship','has_tuition','changed_since'];
  v_not_applied jsonb;
  v_total bigint; v_ids uuid[];
  v_need_fee boolean;
begin
  if v_page < 1 then raise exception 'INVALID_INPUT: page must be >= 1' using errcode='22023'; end if;
  if v_size < 1 or v_size > 50 then raise exception 'INVALID_INPUT: page_size must be 1-50' using errcode='22023'; end if;
  if v_sort not in ('relevance','title_asc','tuition_annual_asc','tuition_annual_desc','duration_asc','updated_asc') then raise exception 'INVALID_INPUT: unknown sort' using errcode='22023'; end if;
  if v_score_max is not null and coalesce(cardinality(v_tests),0) <> 1 then raise exception 'INVALID_INPUT: english_score_max needs exactly one english_test_codes value' using errcode='22023'; end if;
  if v_kw is not null then v_q := websearch_to_tsquery('english', v_kw); end if;
  v_need_fee := (v_min is not null or v_max is not null or coalesce((f->>'has_tuition')::boolean,false) or v_sort in ('tuition_annual_asc','tuition_annual_desc'));
  select coalesce(jsonb_agg(k),'[]'::jsonb) into v_not_applied from jsonb_object_keys(f) k where k <> all(v_known);

  with base as (
    select d.course_id, d.course_title, d.course_stable_key, d.updated_at, d.provider_name,
      case when not v_need_fee then null
           when pt.amt is not null then
             case when pt.bas ~* 'total|course' and pt.bas !~* 'annual' then case when w.wk >= 52 then round(pt.amt / (w.wk/52.0)) end
                  when pt.bas ~* 'session|semester|trimester|unit|credit' then null
                  when pt.bas ~* 'indicative|annual|per.?year|yearly' then pt.amt end
           when d.regulatory_tuition_amount >= 1000 and w.wk >= 52 then round(d.regulatory_tuition_amount / (w.wk/52.0)) end ann,
      case when v_need_fee then (pt.amt is not null or coalesce(d.regulatory_tuition_amount,0) >= 1000) end has_fee,
      w.wk * 12.0 / 52 dur_months,
      case when v_kw is null then 0 else
        ts_rank(d.search_tsv, v_q) + case when d.course_title ilike '%'||v_kw||'%' then 1 else 0 end
          + case when d.course_title ilike v_kw||'%' then 0.5 else 0 end + case when lower(d.course_code) = lower(v_kw) then 2 else 0 end end rel
    from search.course_documents d
    left join catalogue.courses c on c.id = d.course_id
    cross join lateral (select case lower(coalesce(c.duration_unit,'')) when 'weeks' then c.duration_value when 'months' then c.duration_value*52/12.0 when 'years' then c.duration_value*52 end wk) w
    left join lateral (select (o->>'amount')::numeric amt, o->>'basis' bas
                       from jsonb_array_elements(coalesce(d.provider_tuition_options,'[]'::jsonb)) o
                       where (o->>'amount') ~ '^[0-9]+(\.[0-9]+)?$' and (o->>'amount')::numeric >= 1000
                       order by nullif(o->>'fee_year','')::int desc nulls last limit 1) pt on v_need_fee
    where (d.course_id is null or d.course_id not in (select b.course_id from security.layer4_search_blocked_courses b where b.course_id is not null))
      and (v_kw is null or d.search_tsv @@ v_q or d.course_title ilike '%'||v_kw||'%' or d.provider_name ilike '%'||v_kw||'%'
           or lower(d.course_code) = lower(v_kw) or lower(d.course_stable_key) = lower(v_kw))
      and (v_countries is null or d.country_code = any(v_countries))
      and (v_areas is null or d.primary_field_code = any(v_areas))
      and (v_levels is null or d.study_level_code = any(v_levels))
      and (v_subdivs is null or d.subdivision_codes && v_subdivs)
      and (v_providers is null or d.provider_stable_key = any(v_providers))
      and (v_groups is null or exists (select 1 from catalogue.provider_collection_memberships gm join ref.institution_collections gic on gic.id=gm.collection_id
            where gm.provider_id=d.provider_id and gm.status='active' and (gm.valid_to is null or gm.valid_to>=current_date)
              and gic.collection_type='university_group' and gic.status='active' and replace(gic.code,'au_','') = any(v_groups)))
      and (v_modes is null or d.delivery_modes && v_modes)
      and (not coalesce((f->>'has_intake')::boolean,false) or d.has_intake)
      and (not coalesce((f->>'has_english')::boolean,false) or d.has_english)
      and (not coalesce((f->>'has_official_url')::boolean,false) or d.has_link)
      and (not coalesce((f->>'has_scholarship')::boolean,false) or d.has_scholarship)
      and (v_changed is null or greatest(d.updated_at, d.source_updated_at) >= v_changed)
      and (v_months is null or exists (select 1 from jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) i where api.website_v2_label_month(i->>'label') = any(v_months)))
      and (v_tests is null or exists (select 1 from jsonb_array_elements(coalesce(d.english_requirement_options,'[]'::jsonb)) e
            where upper(e->>'test_code') = any(v_tests) and (v_score_max is null or ((e->>'overall_score') ~ '^[0-9]+(\.[0-9]+)?$' and (e->>'overall_score')::numeric <= v_score_max))))
      and ((v_cities is null and v_postcodes is null and v_regional is null) or exists (
            select 1 from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id left join pipeline.campus_regional_class rc on rc.campus_id = k.id
            where cc.course_id = d.course_id
              and (v_cities is null or lower(btrim(k.city)) = any(v_cities) or lower(rc.metro_area) = any(v_cities))
              and (v_postcodes is null or btrim(k.postcode) = any(v_postcodes))
              and (v_regional is null or rc.category = any(v_regional))))
  ), filtered as (
    select * from base b
    where (not coalesce((f->>'has_tuition')::boolean,false) or b.has_fee)
      and (v_min is null or b.ann >= v_min)
      and (v_max is null or b.ann <= v_max)
  ), ordered as (
    select course_id, count(*) over () total,
      row_number() over (order by
        case when v_sort='relevance' then rel end desc nulls last,
        case when v_sort='tuition_annual_asc' then ann end asc nulls last,
        case when v_sort='tuition_annual_desc' then ann end desc nulls last,
        case when v_sort='duration_asc' then dur_months end asc nulls last,
        case when v_sort='updated_asc' then updated_at end asc,
        lower(course_title), course_stable_key) rn
    from filtered
  )
  select coalesce(max(total),0), array_agg(course_id order by rn) filter (where rn > (v_page-1)*v_size and rn <= v_page*v_size)
    into v_total, v_ids from ordered;

  return jsonb_build_object(
    'contract_version','website-search-v2',
    'total', v_total, 'page', v_page, 'page_size', v_size, 'sort', v_sort,
    'filters_not_applied', v_not_applied,
    'items', coalesce((select jsonb_agg(api.website_v2_course_item(x.id, v_cities, v_postcodes) order by x.ord) from unnest(v_ids) with ordinality x(id, ord)), '[]'::jsonb));
end $function$;

do $post$
declare v_expected jsonb := '{"api.courses_list(uuid,character,text,text,integer,integer)": "09040b2280b04fd84728ae749cb8fdc2", "api.providers_list(character,integer,integer)": "f448dee4067b5d92fcb66b338ddaabbf", "api.search_courses(text,character,text,boolean,integer)": "70a323ed2971109b504266fff5557b27", "api.vector_candidates(vector,text,character,text,integer)": "7562b4e05cffd63c08c78b8f82f32a21", "api.website_course_lookup_preview_v1(text)": "0ca79241f53d1b53b429856b68baa08f", "api.website_course_search_preview_v1(text,text[],text[],text,text[],text[],text[],text[],numeric,numeric,boolean,boolean,boolean,text,integer,integer)": "77708090365dc270614a30e229470971", "api.website_course_search_v1(text,text[],text[],text[],text[],text[],boolean,boolean,integer,integer)": "13fb156671a0fc33d2856f97a7307b65", "api.website_course_search_v2(text,text[],text[],text[],text[],text[],boolean,numeric,boolean,boolean,boolean,text,integer,integer)": "8bd714f95ec8fe73646175e7ecf89dd9", "api.zoho_course_candidates_v1(text,text[],text[],text[],text[],text[],boolean,boolean,integer)": "4dae4aa8225a9e840b7d93e839b6c66c", "api.zoho_course_lookup_v1(text)": "ae31644b0ba16eff3b6a765b66d36353", "api.zoho_course_search_v1(text,text[],text[],text[],boolean,timestamp with time zone,integer,integer)": "14a801f0e7362ce53776d9524e5540dc", "api.zoho_course_search_v2(text,text[],text[],text[],text[],text[],text[],boolean,boolean,boolean,boolean,boolean,boolean,integer[],text[],text[],numeric,numeric,numeric,numeric,text[],timestamp with time zone,integer,integer)": "f04c4f546b2e7d2605ba957e2c05214e", "api.zoho_filter_options_v1(text,text,text,integer,integer)": "c098ecd5827b0c01a1147700c38d2cf2", "api.zoho_sync_manifest_v1(timestamp with time zone)": "6f93773c583b090e46dd26a06870f196", "public.website_edge_course_search_v1(jsonb,integer,integer)": "c238f70fd7f01939613a413f13e23565", "public.website_v2_course_search(jsonb,integer,integer,text)": "19b602f54ae10b932f1515c55c45d14f"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
