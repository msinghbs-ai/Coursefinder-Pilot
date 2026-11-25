-- CF-247 s1170 (S2-Build; live UAT bug, Platform Admin 25 Nov 2026 22:53 AEDT): portal course search failed with "Something went wrong on our side"
-- for "Master of Nursing in Victoria".
-- Root cause (Postgres log, 25 Nov 2026 22:50 to 22:51 AEDT, SQLSTATE 42702, PostgREST role authenticator): search.course_candidates_v1, line 68
-- at RETURN QUERY: column reference "course_id" is ambiguous ("It could refer to either a PL/pgSQL variable or a table column"). The function
-- returns TABLE(course_id ...), and its hybrid / vector branch selected a bare course_id in the fts and vec CTEs, so that statement has never
-- run. The keyword branch qualifies it (b.course_id) and works. catalogue.portal_course_search_v1 (s1153) asks for hybrid only once a phrase's
-- query vector is cached: the Platform Admin's first search cached this phrase at 22:50, and every later search of it failed. Phrases with no
-- cached vector (for example "Master of Data Science in Sydney" in the s1153 smoke tests) run keyword only and worked, which is why it was not seen.
-- Fix: the two CTEs qualify course_id with their source alias, as the keyword branch does. Every other line is the live definition byte for
-- byte (pg_get_functiondef md5 cea852088f24fd566999dda4094d071e, checked below before the replace). Nothing that ran before changes meaning.
-- Callers: catalogue.portal_course_search_v1 only. api.zoho_course_candidates_v1 ranks with its own query and does not call this function (the
-- name match is its own name); no edge function or screen calls it. It is not one of the 75 functions / 48 relations of the frozen consumer
-- API baseline (G3, checked below). G1: no job. G2: no new value (the existing weights are unchanged). Manual locks untouched. Nothing dropped.
-- No AI or Firecrawl call.
-- Replaces: search.course_candidates_v1 hybrid / vector branch (unqualified course_id in the fts and vec CTEs).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replace

create temp table s1170_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if md5(pg_get_functiondef('search.course_candidates_v1(text,vector,text,text,text,text[],text[],text[],text[],text[],boolean,boolean,text[],integer)'::regprocedure))
     <> 'cea852088f24fd566999dda4094d071e' then
    raise exception 'pre-check: search.course_candidates_v1 is not the definition this fix was written against';
  end if;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if exists (select 1 from pipeline.consumer_api_baseline where name like 'search.course_candidates_v1%') then
    raise exception 'pre-check: search.course_candidates_v1 is in the frozen consumer API baseline';
  end if;
end $pre$;

CREATE OR REPLACE FUNCTION search.course_candidates_v1(p_query text DEFAULT NULL::text, p_query_embedding vector DEFAULT NULL::vector, p_embedding_model text DEFAULT NULL::text, p_profile_code text DEFAULT 'website-default'::text, p_mode text DEFAULT 'keyword'::text, p_country_codes text[] DEFAULT NULL::text[], p_subdivision_codes text[] DEFAULT NULL::text[], p_level_codes text[] DEFAULT NULL::text[], p_field_codes text[] DEFAULT NULL::text[], p_delivery_modes text[] DEFAULT NULL::text[], p_has_fee boolean DEFAULT NULL::boolean, p_has_scholarship boolean DEFAULT NULL::boolean, p_publication_statuses text[] DEFAULT ARRAY['published'::text, 'internal'::text], p_limit integer DEFAULT 20)
 RETURNS TABLE(course_id uuid, fts_rank real, vector_similarity real, fused_score double precision, mode_used text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'search', 'extensions'
AS $function$
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

  if v_profile_id is null then
    return;
  end if;

  v_candidate_limit := greatest(200,least(v_limit*20,2000));

  if p_mode in ('hybrid','vector') and p_query_embedding is not null and p_embedding_model is not null then
    select exists(
      select 1 from search.course_embeddings e
      where e.profile_id=v_profile_id and e.model_name=p_embedding_model
      limit 1
    ) into v_has_vectors;
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
    select r.course_id,r.score,null::real,
      (v_fts_weight/(v_rrf_k+r.pos))::double precision,
      case when p_mode='hybrid' then 'fts_fallback' else 'keyword' end::text
    from ranked r
    order by r.pos;
    return;
  end if;

  if p_mode='vector' and not v_has_vectors then
    return;
  end if;

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
    select fb.course_id,fb.score,row_number() over(order by fb.score desc,fb.course_id) as pos from fts_base fb  -- s1170: qualified; a bare course_id clashed with the output column
  ), vec_base as (
    select d.course_id,(1-(e.embedding <=> p_query_embedding))::real as similarity
    from search.course_embeddings e
    join search.course_documents d on d.course_id=e.course_id
    where e.profile_id=v_profile_id
      and e.model_name=p_embedding_model
      and e.content_hash=d.semantic_content_hash
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
    select vb.course_id,vb.similarity,row_number() over(order by vb.similarity desc,vb.course_id) as pos from vec_base vb  -- s1170: qualified, as above
  ), merged as (
    select coalesce(f.course_id,v.course_id) as course_id,
           f.score as fts_rank,v.similarity as vector_similarity,
           f.pos as fts_pos,v.pos as vec_pos
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

do $post$
declare v jsonb := security.consumer_api_check_v1(); v_vec extensions.vector; v_n integer; v_hyb integer;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1170_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1170_guard) then raise exception 'post-check: manual locks changed'; end if;
  -- the hybrid branch now runs: rank "nursing" in Victoria with a stored portal vector as the query vector
  select e.embedding into v_vec from search.course_embeddings e join search.profiles p on p.id = e.profile_id and p.code = 'portal-default' limit 1;
  if v_vec is not null then
    select count(*), count(*) filter (where vector_similarity is not null) into v_n, v_hyb
      from search.course_candidates_v1('nursing', v_vec, security.portal_search_text_v1('embedding_model', 'openai/text-embedding-3-small'), 'portal-default', 'hybrid',
                                       null, array['AU-VIC'], null, null, null, null, null, null, 100);  -- fixed: the function's largest page
    if v_n = 0 or v_hyb = 0 then raise exception 'post-check: hybrid ranking returned % rows, % with a vector score', v_n, v_hyb; end if;
  end if;
end $post$;
