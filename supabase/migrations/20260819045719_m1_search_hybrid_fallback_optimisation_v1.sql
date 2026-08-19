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
language plpgsql
stable
security invoker
set search_path=search,extensions
as $function$
declare
  v_profile_id uuid;
  v_rrf_k integer := 60;
  v_fts_weight double precision := 1.0;
  v_vector_weight double precision := 0.55;
  v_limit integer := greatest(1,least(coalesce(p_limit,20),100));
  v_candidate_limit integer;
  v_has_vectors boolean := false;
begin
  select id,
         coalesce((config->>'rrf_k')::integer,60),
         coalesce((config->>'fts_weight')::double precision,1.0),
         coalesce((config->>'vector_weight')::double precision,0.55)
  into v_profile_id,v_rrf_k,v_fts_weight,v_vector_weight
  from search.profiles
  where code=p_profile_code and status='active'
  limit 1;

  if v_profile_id is null then return; end if;
  v_candidate_limit := greatest(200,least(v_limit*20,2000));

  if p_mode in ('hybrid','vector') and p_query_embedding is not null and p_embedding_model is not null then
    select exists(select 1 from search.course_embeddings e where e.profile_id=v_profile_id and e.model_name=p_embedding_model limit 1)
    into v_has_vectors;
  end if;

  if p_mode='keyword' or (p_mode='hybrid' and not v_has_vectors) then
    return query
    with q as (
      select websearch_to_tsquery('english',coalesce(nullif(trim(p_query),''),'')) as tsq
    ), base as (
      select d.course_id,
        case when coalesce(trim(p_query),'')='' then 0::real else ts_rank_cd(d.search_tsv,(select tsq from q))::real end as score
      from search.course_documents d
      where (p_country_codes is null or d.country_code=any(p_country_codes))
        and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
        and (p_level_codes is null or d.study_level_code=any(p_level_codes))
        and (p_field_codes is null or d.primary_field_code=any(p_field_codes))
        and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
        and (p_has_fee is null or d.has_fee=p_has_fee)
        and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
        and (p_publication_statuses is null or d.publication_status=any(p_publication_statuses))
        and (coalesce(trim(p_query),'')='' or d.search_tsv @@ (select tsq from q))
      order by score desc,d.course_title,d.course_id
      limit v_limit
    ), ranked as (
      select b.*,row_number() over(order by b.score desc,b.course_id) as pos from base b
    )
    select r.course_id,r.score,null::real,(v_fts_weight/(v_rrf_k+r.pos))::double precision,
      case when p_mode='hybrid' then 'fts_fallback' else 'keyword' end::text
    from ranked r order by r.pos;
    return;
  end if;

  if p_mode='vector' and not v_has_vectors then return; end if;

  return query
  with q as (
    select websearch_to_tsquery('english',coalesce(nullif(trim(p_query),''),'')) as tsq
  ), fts_base as (
    select d.course_id,
      case when coalesce(trim(p_query),'')='' then 0::real else ts_rank_cd(d.search_tsv,(select tsq from q))::real end as score
    from search.course_documents d
    where p_mode='hybrid'
      and (p_country_codes is null or d.country_code=any(p_country_codes))
      and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
      and (p_level_codes is null or d.study_level_code=any(p_level_codes))
      and (p_field_codes is null or d.primary_field_code=any(p_field_codes))
      and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
      and (p_has_fee is null or d.has_fee=p_has_fee)
      and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
      and (p_publication_statuses is null or d.publication_status=any(p_publication_statuses))
      and (coalesce(trim(p_query),'')='' or d.search_tsv @@ (select tsq from q))
    order by score desc,d.course_title,d.course_id
    limit v_candidate_limit
  ), fts as (
    select course_id,score,row_number() over(order by score desc,course_id) as pos from fts_base
  ), vec_base as (
    select d.course_id,(1-(e.embedding <=> p_query_embedding))::real as similarity
    from search.course_embeddings e
    join search.course_documents d on d.course_id=e.course_id
    where e.profile_id=v_profile_id and e.model_name=p_embedding_model and e.content_hash=d.semantic_content_hash
      and (p_country_codes is null or d.country_code=any(p_country_codes))
      and (p_subdivision_codes is null or d.subdivision_codes && p_subdivision_codes)
      and (p_level_codes is null or d.study_level_code=any(p_level_codes))
      and (p_field_codes is null or d.primary_field_code=any(p_field_codes))
      and (p_delivery_modes is null or d.delivery_modes && p_delivery_modes)
      and (p_has_fee is null or d.has_fee=p_has_fee)
      and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
      and (p_publication_statuses is null or d.publication_status=any(p_publication_statuses))
    order by e.embedding <=> p_query_embedding
    limit v_candidate_limit
  ), vec as (
    select course_id,similarity,row_number() over(order by similarity desc,course_id) as pos from vec_base
  ), merged as (
    select coalesce(f.course_id,v.course_id) as course_id,f.score as fts_rank,v.similarity as vector_similarity,f.pos as fts_pos,v.pos as vec_pos
    from fts f full outer join vec v using(course_id)
  )
  select m.course_id,m.fts_rank,m.vector_similarity,
    (case when m.fts_pos is null then 0 else v_fts_weight/(v_rrf_k+m.fts_pos) end
     + case when m.vec_pos is null then 0 else v_vector_weight/(v_rrf_k+m.vec_pos) end)::double precision,
    case when p_mode='vector' then 'vector' else 'hybrid' end::text
  from merged m
  order by 4 desc,m.fts_rank desc nulls last,m.vector_similarity desc nulls last,m.course_id
  limit v_limit;
end
$function$;

revoke all on function search.course_candidates_v1(text,extensions.vector,text,text,text,text[],text[],text[],text[],text[],boolean,boolean,text[],integer) from public,anon,authenticated;
grant execute on function search.course_candidates_v1(text,extensions.vector,text,text,text,text[],text[],text[],text[],text[],boolean,boolean,text[],integer) to service_role;
