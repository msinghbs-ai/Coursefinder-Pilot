create or replace function search.course_candidates_v1(
  p_query text default null,
  p_query_embedding extensions.vector(1536) default null,
  p_embedding_model text default null,
  p_profile_code text default 'website-default',
  p_mode text default 'keyword',
  p_country_codes text[] default null,
  p_subdivision_codes text[] default null,
  p_level_codes text[] default null,
  p_field_codes text[] default null,
  p_delivery_modes text[] default null,
  p_has_fee boolean default null,
  p_has_scholarship boolean default null,
  p_publication_statuses text[] default array['published','internal']::text[],
  p_limit integer default 20
)
returns table(course_id uuid,fts_rank real,vector_similarity real,fused_score double precision,mode_used text)
language sql
stable
security invoker
set search_path=search,extensions
as $function$
with pr as (
  select id,config from search.profiles where code=p_profile_code and status='active' limit 1
), params as (
  select greatest(1,least(coalesce(p_limit,20),100)) as result_limit,
    greatest(200,least(greatest(1,least(coalesce(p_limit,20),100))*20,2000)) as candidate_limit,
    coalesce((select (config->>'rrf_k')::integer from pr),60) as rrf_k,
    coalesce((select (config->>'fts_weight')::double precision from pr),1.0) as fts_weight,
    coalesce((select (config->>'vector_weight')::double precision from pr),0.55) as vector_weight,
    websearch_to_tsquery('english',coalesce(nullif(trim(p_query),''),'')) as tsq
), filtered as materialized (
  select d.* from search.course_documents d
  where (p_country_codes is null or d.country_code=any(p_country_codes))
    and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
    and (p_level_codes is null or d.study_level_code=any(p_level_codes))
    and (p_field_codes is null or d.primary_field_code=any(p_field_codes))
    and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
    and (p_has_fee is null or d.has_fee=p_has_fee)
    and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
    and (p_publication_statuses is null or d.publication_status=any(p_publication_statuses))
), fts_base as (
  select f.course_id,case when coalesce(trim(p_query),'')='' then 0::real else ts_rank_cd(f.search_tsv,(select tsq from params))::real end as score
  from filtered f
  where p_mode in ('keyword','hybrid') and (coalesce(trim(p_query),'')='' or f.search_tsv @@ (select tsq from params))
  order by score desc,f.course_title,f.course_id
  limit (select candidate_limit from params)
), fts as (
  select course_id,score,row_number() over(order by score desc,course_id) as pos from fts_base
), vec_base as (
  select f.course_id,(1-(e.embedding <=> p_query_embedding))::real as similarity
  from search.course_embeddings e
  join filtered f on f.course_id=e.course_id
  join pr on pr.id=e.profile_id
  where p_mode in ('hybrid','vector') and p_query_embedding is not null and p_embedding_model is not null
    and e.model_name=p_embedding_model and e.content_hash=f.semantic_content_hash
  order by e.embedding <=> p_query_embedding
  limit (select candidate_limit from params)
), vec as (
  select course_id,similarity,row_number() over(order by similarity desc,course_id) as pos from vec_base
), merged as (
  select coalesce(f.course_id,v.course_id) as course_id,f.score as fts_rank,v.similarity as vector_similarity,f.pos as fts_pos,v.pos as vec_pos
  from fts f full outer join vec v using(course_id)
), scored as (
  select m.course_id,m.fts_rank,m.vector_similarity,
    (case when m.fts_pos is null then 0 else (select fts_weight from params)/((select rrf_k from params)+m.fts_pos) end
     + case when m.vec_pos is null then 0 else (select vector_weight from params)/((select rrf_k from params)+m.vec_pos) end)::double precision as fused_score,
    case when p_mode='vector' then 'vector' when p_mode='hybrid' and exists(select 1 from vec) then 'hybrid' when p_mode='hybrid' then 'fts_fallback' else 'keyword' end as mode_used
  from merged m
)
select s.course_id,s.fts_rank,s.vector_similarity,s.fused_score,s.mode_used
from scored s
order by s.fused_score desc,s.fts_rank desc nulls last,s.vector_similarity desc nulls last,s.course_id
limit (select result_limit from params)
$function$;

revoke all on function search.course_candidates_v1(text,extensions.vector,text,text,text,text[],text[],text[],text[],text[],boolean,boolean,text[],integer) from public,anon,authenticated;
grant execute on function search.course_candidates_v1(text,extensions.vector,text,text,text,text[],text[],text[],text[],text[],boolean,boolean,text[],integer) to service_role;

create or replace function api.website_course_search_v1(
  p_query text default null,
  p_country_codes text[] default null,
  p_subdivision_codes text[] default null,
  p_level_codes text[] default null,
  p_field_codes text[] default null,
  p_delivery_modes text[] default null,
  p_has_fee boolean default null,
  p_has_scholarship boolean default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language sql
stable
security definer
set search_path=api,search
as $function$
with params as (
  select greatest(1,least(coalesce(p_limit,20),50)) as lim,greatest(coalesce(p_offset,0),0) as off,
         websearch_to_tsquery('english',coalesce(nullif(trim(p_query),''),'')) as tsq
), ranked as (
  select d.*,case when coalesce(trim(p_query),'')='' then 0::real else ts_rank_cd(d.search_tsv,(select tsq from params))::real end as score
  from search.course_documents d
  where d.publication_status='published'
    and (p_country_codes is null or d.country_code=any(p_country_codes))
    and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
    and (p_level_codes is null or d.study_level_code=any(p_level_codes))
    and (p_field_codes is null or d.primary_field_code=any(p_field_codes))
    and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
    and (p_has_fee is null or d.has_fee=p_has_fee)
    and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
    and (coalesce(trim(p_query),'')='' or d.search_tsv @@ (select tsq from params))
), paged as (
  select * from ranked order by score desc,course_title,course_stable_key
  limit (select lim from params) offset (select off from params)
)
select jsonb_build_object(
  'contract_version','website-course-search-v1',
  'meta',jsonb_build_object('mode','keyword','limit',(select lim from params),'offset',(select off from params),'projection_version','course-v2'),
  'items',coalesce(jsonb_agg(jsonb_build_object(
    'course_key',course_stable_key,'title',course_title,'course_code',course_code,
    'provider',jsonb_build_object('provider_key',provider_stable_key,'name',provider_name),
    'country',country_code,'study_level',study_level_code,
    'field',case when primary_field_code is null then null else jsonb_build_object('code',primary_field_code,'name',primary_field_name) end,
    'states',to_jsonb(subdivision_codes),'delivery_modes',to_jsonb(delivery_modes),
    'readiness',jsonb_build_object('has_state',has_state,'has_link',has_link,'has_fee',has_fee,'has_intake',has_intake,'has_english',has_english,'has_scholarship',has_scholarship),
    'match',jsonb_build_object('keyword_score',score)
  ) order by score desc,course_title,course_stable_key),'[]'::jsonb)
) from paged
$function$;

revoke all on function api.website_course_search_v1(text,text[],text[],text[],text[],text[],boolean,boolean,integer,integer) from public,anon,authenticated;
grant usage on schema api to service_role;
grant execute on function api.website_course_search_v1(text,text[],text[],text[],text[],text[],boolean,boolean,integer,integer) to service_role;

create or replace function api.zoho_course_candidates_v1(
  p_query text default null,
  p_country_codes text[] default null,
  p_subdivision_codes text[] default null,
  p_level_codes text[] default null,
  p_field_codes text[] default null,
  p_delivery_modes text[] default null,
  p_has_fee boolean default null,
  p_has_scholarship boolean default null,
  p_limit integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path=api,search,security
as $function$
declare v_result jsonb;
begin
  if security.current_role_rank()<2 then
    raise exception 'forbidden' using errcode='42501';
  end if;

  with params as (
    select greatest(1,least(coalesce(p_limit,30),100)) as lim,websearch_to_tsquery('english',coalesce(nullif(trim(p_query),''),'')) as tsq
  ), ranked as (
    select d.*,case when coalesce(trim(p_query),'')='' then 0::real else ts_rank_cd(d.search_tsv,(select tsq from params))::real end as score
    from search.course_documents d
    where d.publication_status in ('published','internal')
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
    'meta',jsonb_build_object('mode','keyword','limit',(select lim from params),'projection_version','course-v2'),
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'course_key',course_stable_key,'provider_key',provider_stable_key,'title',course_title,'provider_name',provider_name,
      'country',country_code,'study_level',study_level_code,'field_code',primary_field_code,'states',to_jsonb(subdivision_codes),'delivery_modes',to_jsonb(delivery_modes),
      'academic_rank',score,'readiness',jsonb_build_object('has_state',has_state,'has_link',has_link,'has_fee',has_fee,'has_intake',has_intake,'has_english',has_english,'has_scholarship',has_scholarship)
    ) order by score desc,course_title,course_stable_key),'[]'::jsonb)
  ) into v_result from ranked;

  return v_result;
end
$function$;

revoke all on function api.zoho_course_candidates_v1(text,text[],text[],text[],text[],text[],boolean,boolean,integer) from public,anon;
grant usage on schema api to authenticated;
grant execute on function api.zoho_course_candidates_v1(text,text[],text[],text[],text[],text[],boolean,boolean,integer) to authenticated;
