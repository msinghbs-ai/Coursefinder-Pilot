delete from search.query_embedding_cache where model_name='Supabase/gte-small';
delete from search.course_embeddings where model_name='Supabase/gte-small';

drop function if exists public.svc_search_hybrid_candidates_v1(text,extensions.vector,text,text[],text[],text[],text[],text[],integer);
drop function if exists public.svc_search_fts_candidates_v1(text,text[],text[],text[],text[],text[],integer);
drop function if exists public.svc_search_vector_candidates_v1(extensions.vector,text,text[],text[],text[],text[],text[],integer);
drop function if exists public.svc_search_query_cache_put_v1(text,text,text,text,extensions.vector,integer);
drop function if exists public.svc_search_query_cache_get_v1(text,text,text,text);
drop function if exists public.svc_search_embedding_upsert_batch_v1(text,text,text,integer,jsonb);
drop function if exists public.svc_search_embedding_pending_v1(text,text,text,integer);

drop function if exists api.svc_hybrid_candidates_v1(text,extensions.vector,text,text[],text[],text[],text[],text[],integer);
drop function if exists api.svc_fts_candidates_v1(text,text[],text[],text[],text[],text[],integer);
drop function if exists api.svc_vector_candidates_v1(extensions.vector,text,text[],text[],text[],text[],text[],integer);
drop function if exists api.svc_query_embedding_cache_put_v1(text,text,text,text,extensions.vector,integer);
drop function if exists api.svc_query_embedding_cache_get_v1(text,text,text,text);
drop function if exists api.svc_embedding_clone_profile_v1(text,text,text,text);
drop function if exists api.svc_embedding_upsert_batch_v1(text,text,text,integer,jsonb);
drop function if exists api.svc_embedding_pending_v1(text,text,text,integer);
drop function if exists api.svc_search_vector_authorize_key_v1(text);

drop index if exists search.course_embeddings_hnsw_idx;
drop index if exists search.course_embeddings_freshness_idx;

alter table search.course_embeddings alter column embedding type extensions.vector(1536) using null::extensions.vector(1536), alter column dimensions set default 1536;
alter table search.query_embedding_cache alter column embedding type extensions.vector(1536) using null::extensions.vector(1536);
alter table search.course_embeddings drop column if exists model_version;
alter table search.query_embedding_cache drop column if exists model_version;
alter table search.embedding_jobs drop column if exists model_version;
create index course_embeddings_hnsw_idx on search.course_embeddings using hnsw (embedding extensions.vector_cosine_ops);

update search.profiles set config=config-'embedding',updated_at=now() where code in ('website-default','zoho-default');
drop table if exists search.vector_gate_runs;

create or replace function api.query_embedding_cache_get(p_cache_key text,p_model_name text,p_profile_version text)
returns table(embedding extensions.vector(1536),hit_count bigint)
language plpgsql security definer set search_path=api,search,extensions as $$
begin
 update search.query_embedding_cache q set last_used_at=now(),hit_count=q.hit_count+1 where q.cache_key=p_cache_key and q.model_name=p_model_name and q.profile_version=p_profile_version and q.expires_at>now();
 return query select q.embedding,q.hit_count from search.query_embedding_cache q where q.cache_key=p_cache_key and q.model_name=p_model_name and q.profile_version=p_profile_version and q.expires_at>now();
end$$;
create or replace function api.query_embedding_cache_put(p_cache_key text,p_model_name text,p_profile_version text,p_embedding extensions.vector(1536),p_ttl_seconds integer default 604800)
returns void language sql security definer set search_path=api,search,extensions as $$
insert into search.query_embedding_cache(cache_key,model_name,profile_version,embedding,expires_at)
values(p_cache_key,p_model_name,p_profile_version,p_embedding,now()+make_interval(secs=>least(greatest(coalesce(p_ttl_seconds,604800),60),2592000)))
on conflict(cache_key) do update set model_name=excluded.model_name,profile_version=excluded.profile_version,embedding=excluded.embedding,created_at=now(),last_used_at=now(),hit_count=0,expires_at=excluded.expires_at;
$$;
create or replace function api.vector_candidates(p_embedding extensions.vector(1536),p_profile_code text,p_country character default null,p_level_code text default null,p_limit integer default 50)
returns table(course_id uuid,distance double precision)
language sql stable security definer set search_path=api,search,ref,security,extensions as $$
select e.course_id,(e.embedding<=>p_embedding)::double precision
from search.course_embeddings e join search.profiles sp on sp.id=e.profile_id join search.course_documents d on d.course_id=e.course_id
join ref.countries co on co.id=d.country_id left join ref.study_levels sl on sl.id=d.study_level_id
where security.current_role_rank()>=1 and sp.code=p_profile_code and (p_country is null or co.iso_alpha2=p_country) and (p_level_code is null or sl.code=p_level_code)
order by e.embedding<=>p_embedding limit least(greatest(coalesce(p_limit,50),1),100)
$$;
revoke all on function api.query_embedding_cache_get(text,text,text) from public,anon,authenticated;
revoke all on function api.query_embedding_cache_put(text,text,text,extensions.vector,integer) from public,anon,authenticated;
revoke all on function api.vector_candidates(extensions.vector,text,character,text,integer) from public,anon,authenticated;
grant execute on function api.query_embedding_cache_get(text,text,text) to service_role;
grant execute on function api.query_embedding_cache_put(text,text,text,extensions.vector,integer) to service_role;
grant execute on function api.vector_candidates(extensions.vector,text,character,text,integer) to service_role;
