create or replace function security.current_role_rank()
returns smallint
language sql
stable
security definer
set search_path=security,auth
as $$
select coalesce(max(r.rank),0)::smallint
from security.user_roles ur join security.roles r on r.code=ur.role_code
where ur.user_id=auth.uid() and (ur.expires_at is null or ur.expires_at>now()) and r.status='active'
$$;
revoke all on function security.current_role_rank() from public,anon;
grant execute on function security.current_role_rank() to authenticated,service_role;

create or replace function api.providers_list(p_country char(2) default null,p_limit int default 100,p_offset int default 0)
returns table(id uuid,stable_key text,canonical_name text,display_name text,country_code char(2),publication_status text,course_count bigint)
language sql
stable
security definer
set search_path=api,catalogue,ref,security
as $$
select p.id,p.stable_key,p.canonical_name,p.display_name,c.iso_alpha2,p.publication_status,count(cr.id)::bigint
from catalogue.providers p join ref.countries c on c.id=p.country_id left join catalogue.courses cr on cr.provider_id=p.id
where security.current_role_rank()>=1 and (p_country is null or c.iso_alpha2=p_country)
group by p.id,c.iso_alpha2
order by coalesce(p.display_name,p.canonical_name)
limit least(greatest(coalesce(p_limit,100),1),500) offset greatest(coalesce(p_offset,0),0)
$$;

create or replace function api.courses_list(p_provider_id uuid default null,p_country char(2) default null,p_level_code text default null,p_publication text default null,p_limit int default 100,p_offset int default 0)
returns table(id uuid,stable_key text,provider_id uuid,provider_name text,canonical_title text,course_code text,level_code text,publication_status text,completeness_score numeric)
language sql
stable
security definer
set search_path=api,catalogue,ref,publishing,security
as $$
select c.id,c.stable_key,c.provider_id,coalesce(p.display_name,p.canonical_name),c.canonical_title,c.course_code,sl.code,c.publication_status,max(es.completeness_score)
from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries co on co.id=p.country_id
left join ref.study_levels sl on sl.id=c.study_level_id left join publishing.entity_states es on es.entity_id=c.id
where security.current_role_rank()>=1
  and (p_provider_id is null or c.provider_id=p_provider_id)
  and (p_country is null or co.iso_alpha2=p_country)
  and (p_level_code is null or sl.code=p_level_code)
  and (p_publication is null or c.publication_status=p_publication)
group by c.id,p.canonical_name,p.display_name,sl.code
order by c.canonical_title
limit least(greatest(coalesce(p_limit,100),1),500) offset greatest(coalesce(p_offset,0),0)
$$;

create or replace function api.search_courses(
  p_query text,
  p_country char(2) default null,
  p_level_code text default null,
  p_has_scholarship boolean default null,
  p_limit int default 20
)
returns table(course_id uuid,provider_name text,course_title text,level_code text,rank real,has_fee boolean,has_intake boolean,has_english boolean,has_scholarship boolean)
language sql
stable
security definer
set search_path=api,search,ref,security
as $$
select d.course_id,d.provider_name,d.course_title,sl.code,
       ts_rank_cd(d.search_tsv,websearch_to_tsquery('english',coalesce(p_query,'')))::real,
       d.has_fee,d.has_intake,d.has_english,d.has_scholarship
from search.course_documents d left join ref.study_levels sl on sl.id=d.study_level_id join ref.countries co on co.id=d.country_id
where security.current_role_rank()>=1 and d.publication_status in ('published','internal')
 and (p_country is null or co.iso_alpha2=p_country)
 and (p_level_code is null or sl.code=p_level_code)
 and (p_has_scholarship is null or d.has_scholarship=p_has_scholarship)
 and (coalesce(trim(p_query),'')='' or d.search_tsv @@ websearch_to_tsquery('english',p_query))
order by ts_rank_cd(d.search_tsv,websearch_to_tsquery('english',coalesce(p_query,''))) desc,d.course_title
limit least(greatest(coalesce(p_limit,20),1),50)
$$;

create or replace function api.vector_candidates(
  p_embedding extensions.vector(1536),
  p_profile_code text,
  p_country char(2) default null,
  p_level_code text default null,
  p_limit int default 50
)
returns table(course_id uuid,distance double precision)
language sql
stable
security definer
set search_path=api,search,ref,security,extensions
as $$
select e.course_id,(e.embedding <=> p_embedding)::double precision
from search.course_embeddings e join search.profiles sp on sp.id=e.profile_id join search.course_documents d on d.course_id=e.course_id
join ref.countries co on co.id=d.country_id left join ref.study_levels sl on sl.id=d.study_level_id
where security.current_role_rank()>=1 and sp.code=p_profile_code
 and (p_country is null or co.iso_alpha2=p_country)
 and (p_level_code is null or sl.code=p_level_code)
order by e.embedding <=> p_embedding
limit least(greatest(coalesce(p_limit,50),1),100)
$$;

revoke all on all functions in schema api from public,anon;
grant usage on schema api to authenticated,service_role;
grant execute on function api.providers_list(char,integer,integer) to authenticated,service_role;
grant execute on function api.courses_list(uuid,char,text,text,integer,integer) to authenticated,service_role;
grant execute on function api.search_courses(text,char,text,boolean,integer) to authenticated,service_role;
grant execute on function api.vector_candidates(extensions.vector,text,char,text,integer) to authenticated,service_role;
