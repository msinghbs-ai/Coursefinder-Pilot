create or replace function public.svc_search_embedding_pending_v1(p_profile_code text,p_model_name text,p_model_version text,p_limit integer default 100)
returns table(course_id uuid,semantic_content_hash text,semantic_text text)
language sql stable security definer set search_path=public,api,search
as $$ select * from api.svc_embedding_pending_v1(p_profile_code,p_model_name,p_model_version,p_limit) $$;

create or replace function public.svc_search_embedding_upsert_batch_v1(p_profile_code text,p_model_name text,p_model_version text,p_dimensions integer,p_records jsonb)
returns integer language sql security definer set search_path=public,api
as $$ select api.svc_embedding_upsert_batch_v1(p_profile_code,p_model_name,p_model_version,p_dimensions,p_records) $$;

create or replace function public.svc_search_query_cache_get_v1(p_cache_key text,p_model_name text,p_model_version text,p_profile_version text)
returns table(embedding extensions.vector(384),hit_count bigint)
language sql security definer set search_path=public,api,extensions
as $$ select * from api.svc_query_embedding_cache_get_v1(p_cache_key,p_model_name,p_model_version,p_profile_version) $$;

create or replace function public.svc_search_query_cache_put_v1(p_cache_key text,p_model_name text,p_model_version text,p_profile_version text,p_embedding extensions.vector(384),p_ttl_seconds integer default 604800)
returns void language sql security definer set search_path=public,api,extensions
as $$ select api.svc_query_embedding_cache_put_v1(p_cache_key,p_model_name,p_model_version,p_profile_version,p_embedding,p_ttl_seconds) $$;

create or replace function public.svc_search_vector_candidates_v1(p_embedding extensions.vector(384),p_profile_code text default 'website-default',p_country_codes text[] default null,p_subdivision_codes text[] default null,p_level_codes text[] default null,p_field_codes text[] default null,p_delivery_modes text[] default null,p_limit integer default 20)
returns table(course_id uuid,course_title text,provider_name text,country_code text,study_level_code text,primary_field_code text,distance double precision)
language sql stable security definer set search_path=public,api,extensions
as $$ select * from api.svc_vector_candidates_v1(p_embedding,p_profile_code,p_country_codes,p_subdivision_codes,p_level_codes,p_field_codes,p_delivery_modes,p_limit) $$;

create or replace function public.svc_search_fts_candidates_v1(p_query text,p_country_codes text[] default null,p_subdivision_codes text[] default null,p_level_codes text[] default null,p_field_codes text[] default null,p_delivery_modes text[] default null,p_limit integer default 20)
returns table(course_id uuid,course_title text,provider_name text,country_code text,study_level_code text,primary_field_code text,score real)
language sql stable security definer set search_path=public,api
as $$ select * from api.svc_fts_candidates_v1(p_query,p_country_codes,p_subdivision_codes,p_level_codes,p_field_codes,p_delivery_modes,p_limit) $$;

create or replace function public.svc_search_hybrid_candidates_v1(p_query text,p_embedding extensions.vector(384),p_profile_code text default 'website-default',p_country_codes text[] default null,p_subdivision_codes text[] default null,p_level_codes text[] default null,p_field_codes text[] default null,p_delivery_modes text[] default null,p_limit integer default 20)
returns table(course_id uuid,course_title text,provider_name text,country_code text,study_level_code text,primary_field_code text,hybrid_score double precision,fts_rank bigint,vector_rank bigint)
language sql stable security definer set search_path=public,api,extensions
as $$ select * from api.svc_hybrid_candidates_v1(p_query,p_embedding,p_profile_code,p_country_codes,p_subdivision_codes,p_level_codes,p_field_codes,p_delivery_modes,p_limit) $$;

revoke all on function public.svc_search_embedding_pending_v1(text,text,text,integer) from public,anon,authenticated;
revoke all on function public.svc_search_embedding_upsert_batch_v1(text,text,text,integer,jsonb) from public,anon,authenticated;
revoke all on function public.svc_search_query_cache_get_v1(text,text,text,text) from public,anon,authenticated;
revoke all on function public.svc_search_query_cache_put_v1(text,text,text,text,extensions.vector,integer) from public,anon,authenticated;
revoke all on function public.svc_search_vector_candidates_v1(extensions.vector,text,text[],text[],text[],text[],text[],integer) from public,anon,authenticated;
revoke all on function public.svc_search_fts_candidates_v1(text,text[],text[],text[],text[],text[],integer) from public,anon,authenticated;
revoke all on function public.svc_search_hybrid_candidates_v1(text,extensions.vector,text,text[],text[],text[],text[],text[],integer) from public,anon,authenticated;
grant execute on function public.svc_search_embedding_pending_v1(text,text,text,integer) to service_role;
grant execute on function public.svc_search_embedding_upsert_batch_v1(text,text,text,integer,jsonb) to service_role;
grant execute on function public.svc_search_query_cache_get_v1(text,text,text,text) to service_role;
grant execute on function public.svc_search_query_cache_put_v1(text,text,text,text,extensions.vector,integer) to service_role;
grant execute on function public.svc_search_vector_candidates_v1(extensions.vector,text,text[],text[],text[],text[],text[],integer) to service_role;
grant execute on function public.svc_search_fts_candidates_v1(text,text[],text[],text[],text[],text[],integer) to service_role;
grant execute on function public.svc_search_hybrid_candidates_v1(text,extensions.vector,text,text[],text[],text[],text[],text[],integer) to service_role;
