create table search.course_embeddings (
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  profile_id uuid not null references search.profiles(id) on delete cascade,
  model_name text not null,
  dimensions int not null default 1536,
  embedding extensions.vector(1536) not null,
  content_hash text not null,
  embedded_at timestamptz not null default now(),
  primary key(course_id,profile_id,model_name)
);
create index course_embeddings_hnsw_idx on search.course_embeddings using hnsw (embedding extensions.vector_cosine_ops);
create index course_embeddings_profile_idx on search.course_embeddings(profile_id,model_name);

create table search.query_embedding_cache (
  cache_key text primary key,
  model_name text not null,
  profile_version text not null,
  embedding extensions.vector(1536) not null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz not null default now(),
  hit_count bigint not null default 0,
  expires_at timestamptz not null default (now() + interval '7 days')
);
create index query_embedding_cache_expires_idx on search.query_embedding_cache(expires_at);

create table search.embedding_jobs (
  id uuid primary key default extensions.gen_random_uuid(),
  course_id uuid references catalogue.courses(id) on delete cascade,
  profile_id uuid references search.profiles(id) on delete cascade,
  model_name text not null,
  content_hash text,
  status text not null default 'queued',
  attempt_count int not null default 0,
  error_text text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
create index embedding_jobs_status_idx on search.embedding_jobs(status,created_at);

create or replace function api.query_embedding_cache_get(
  p_cache_key text,
  p_model_name text,
  p_profile_version text
)
returns table(embedding extensions.vector(1536), hit_count bigint)
language plpgsql
security definer
set search_path = api,search,extensions
as $$
begin
  update search.query_embedding_cache q
  set last_used_at=now(), hit_count=q.hit_count+1
  where q.cache_key=p_cache_key and q.model_name=p_model_name and q.profile_version=p_profile_version and q.expires_at>now();
  return query select q.embedding,q.hit_count from search.query_embedding_cache q
  where q.cache_key=p_cache_key and q.model_name=p_model_name and q.profile_version=p_profile_version and q.expires_at>now();
end$$;

create or replace function api.query_embedding_cache_put(
  p_cache_key text,
  p_model_name text,
  p_profile_version text,
  p_embedding extensions.vector(1536),
  p_ttl_seconds integer default 604800
) returns void
language sql
security definer
set search_path = api,search,extensions
as $$
insert into search.query_embedding_cache(cache_key,model_name,profile_version,embedding,expires_at)
values(p_cache_key,p_model_name,p_profile_version,p_embedding,now()+make_interval(secs=>least(greatest(coalesce(p_ttl_seconds,604800),60),2592000)))
on conflict(cache_key) do update set model_name=excluded.model_name,profile_version=excluded.profile_version,embedding=excluded.embedding,created_at=now(),last_used_at=now(),hit_count=0,expires_at=excluded.expires_at;
$$;

revoke all on function api.query_embedding_cache_get(text,text,text) from public,anon,authenticated;
revoke all on function api.query_embedding_cache_put(text,text,text,extensions.vector,integer) from public,anon,authenticated;
grant execute on function api.query_embedding_cache_get(text,text,text) to service_role;
grant execute on function api.query_embedding_cache_put(text,text,text,extensions.vector,integer) to service_role;
