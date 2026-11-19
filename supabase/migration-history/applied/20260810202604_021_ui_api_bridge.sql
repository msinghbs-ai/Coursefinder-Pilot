create or replace function public.ui_context()
returns jsonb
language sql
stable
security definer
set search_path=public,security,auth
as $$
select case when auth.uid() is null then jsonb_build_object('authenticated',false)
else jsonb_build_object(
  'authenticated',true,
  'user_id',auth.uid(),
  'email',auth.jwt()->>'email',
  'role',coalesce((select r.code from security.user_roles ur join security.roles r on r.code=ur.role_code where ur.user_id=auth.uid() and (ur.expires_at is null or ur.expires_at>now()) order by r.rank desc limit 1),'unassigned'),
  'role_rank',security.current_role_rank()
) end
$$;

create or replace function public.ui_dashboard()
returns jsonb
language sql
stable
security definer
set search_path=public,catalogue,scholarship,pipeline,workflow,pim,search,auth
as $$
select case when auth.uid() is null then '{}'::jsonb else jsonb_build_object(
 'providers',(select count(*) from catalogue.providers),
 'courses',(select count(*) from catalogue.courses),
 'scholarships',(select count(*) from scholarship.scholarships),
 'jobs',(select count(*) from pipeline.jobs),
 'open_reviews',(select count(*) from workflow.review_queue where status in ('open','in_review')),
 'evidence',(select count(*) from pipeline.evidence_artifacts),
 'attributes',(select count(*) from pim.attribute_definitions),
 'search_documents',(select count(*) from search.course_documents),
 'search_generation',(select generation from search.projection_state where projection_code='courses')
) end
$$;

create or replace function public.ui_providers_list(p_limit int default 500)
returns table(id uuid,stable_key text,canonical_name text,display_name text,country_code char(2),city text,website text,lifecycle_status text,publication_status text,course_count bigint)
language sql
stable
security definer
set search_path=public,catalogue,ref,auth
as $$
select p.id,p.stable_key,p.canonical_name,p.display_name,c.iso_alpha2,p.primary_city,p.website,p.lifecycle_status,p.publication_status,count(cr.id)::bigint
from catalogue.providers p join ref.countries c on c.id=p.country_id left join catalogue.courses cr on cr.provider_id=p.id
where auth.uid() is not null
group by p.id,c.iso_alpha2
order by coalesce(p.display_name,p.canonical_name)
limit least(greatest(coalesce(p_limit,500),1),1000)
$$;

create or replace function public.ui_courses_list(p_limit int default 1000)
returns table(course_id uuid,stable_key text,canonical_title text,provider_id uuid,provider_name text,level_code text,field_of_study text,duration_value numeric,duration_unit text,delivery_mode text,publication_status text,has_fee boolean,has_intake boolean,has_english boolean,has_scholarship boolean,completeness_score numeric)
language sql
stable
security definer
set search_path=public,catalogue,ref,search,auth
as $$
select c.id,c.stable_key,c.canonical_title,c.provider_id,coalesce(p.display_name,p.canonical_name),sl.code,fos.name,c.duration_value,c.duration_unit,c.delivery_mode,c.publication_status,
       coalesce(d.has_fee,false),coalesce(d.has_intake,false),coalesce(d.has_english,false),coalesce(d.has_scholarship,false),d.completeness_score
from catalogue.courses c join catalogue.providers p on p.id=c.provider_id
left join ref.study_levels sl on sl.id=c.study_level_id
left join ref.fields_of_study fos on fos.id=c.primary_field_id
left join search.course_documents d on d.course_id=c.id
where auth.uid() is not null
order by coalesce(p.display_name,p.canonical_name),c.canonical_title
limit least(greatest(coalesce(p_limit,1000),1),2000)
$$;

create or replace function public.ui_attributes_list()
returns table(id uuid,code text,name text,entity_type text,group_name text,data_type text,is_filterable boolean,is_searchable boolean,include_in_vector boolean,is_bulk_editable boolean,status text)
language sql
stable
security definer
set search_path=public,pim,auth
as $$
select a.id,a.code,a.name,a.entity_type,g.name,a.data_type,a.is_filterable,a.is_searchable,a.include_in_vector,a.is_bulk_editable,a.status
from pim.attribute_definitions a left join pim.attribute_groups g on g.id=a.group_id
where auth.uid() is not null
order by a.entity_type,g.display_order,a.display_order,a.name
$$;

create or replace function public.ui_jobs_list(p_limit int default 500)
returns table(id uuid,job_type text,domain text,status text,attempt_count int,created_at timestamptz,started_at timestamptz,completed_at timestamptz,error_text text)
language sql
stable
security definer
set search_path=public,pipeline,auth
as $$
select j.id,j.job_type,j.domain,j.status,j.attempt_count,j.created_at,j.started_at,j.completed_at,j.error_text
from pipeline.jobs j where auth.uid() is not null order by j.created_at desc limit least(greatest(coalesce(p_limit,500),1),1000)
$$;

create or replace function public.ui_review_queue(p_limit int default 500)
returns table(id uuid,entity_id uuid,domain text,field_code text,priority smallint,status text,previous_review_id uuid,reopen_reason text,created_at timestamptz,updated_at timestamptz)
language sql
stable
security definer
set search_path=public,workflow,auth
as $$
select r.id,r.entity_id,r.domain,r.field_code,r.priority,r.status,r.previous_review_id,r.reopen_reason,r.created_at,r.updated_at
from workflow.review_queue r where auth.uid() is not null order by r.priority desc,r.created_at desc limit least(greatest(coalesce(p_limit,500),1),1000)
$$;

create or replace function public.ui_scholarships_list(p_limit int default 500)
returns table(id uuid,stable_key text,name text,provider_id uuid,provider_name text,scholarship_type text,audience text,award_value_text text,academic_year int,publication_status text)
language sql
stable
security definer
set search_path=public,scholarship,catalogue,auth
as $$
select s.id,s.stable_key,s.name,s.provider_id,coalesce(p.display_name,p.canonical_name),s.scholarship_type,s.audience,s.award_value_text,s.academic_year,s.publication_status
from scholarship.scholarships s left join catalogue.providers p on p.id=s.provider_id
where auth.uid() is not null order by coalesce(p.display_name,p.canonical_name),s.name limit least(greatest(coalesce(p_limit,500),1),1000)
$$;

create or replace function public.ui_search_courses(p_query text,p_limit int default 50)
returns table(course_id uuid,provider_name text,course_title text,level_code text,rank real,has_scholarship boolean)
language sql
stable
security definer
set search_path=public,search,ref,auth
as $$
select d.course_id,d.provider_name,d.course_title,sl.code,
       ts_rank_cd(d.search_tsv,websearch_to_tsquery('english',coalesce(p_query,'')))::real,d.has_scholarship
from search.course_documents d left join ref.study_levels sl on sl.id=d.study_level_id
where auth.uid() is not null and (coalesce(trim(p_query),'')='' or d.search_tsv @@ websearch_to_tsquery('english',p_query))
order by ts_rank_cd(d.search_tsv,websearch_to_tsquery('english',coalesce(p_query,''))) desc,d.course_title
limit least(greatest(coalesce(p_limit,50),1),100)
$$;

revoke all on function public.ui_context() from public,anon;
revoke all on function public.ui_dashboard() from public,anon;
revoke all on function public.ui_providers_list(integer) from public,anon;
revoke all on function public.ui_courses_list(integer) from public,anon;
revoke all on function public.ui_attributes_list() from public,anon;
revoke all on function public.ui_jobs_list(integer) from public,anon;
revoke all on function public.ui_review_queue(integer) from public,anon;
revoke all on function public.ui_scholarships_list(integer) from public,anon;
revoke all on function public.ui_search_courses(text,integer) from public,anon;

grant execute on function public.ui_context() to authenticated,service_role;
grant execute on function public.ui_dashboard() to authenticated,service_role;
grant execute on function public.ui_providers_list(integer) to authenticated,service_role;
grant execute on function public.ui_courses_list(integer) to authenticated,service_role;
grant execute on function public.ui_attributes_list() to authenticated,service_role;
grant execute on function public.ui_jobs_list(integer) to authenticated,service_role;
grant execute on function public.ui_review_queue(integer) to authenticated,service_role;
grant execute on function public.ui_scholarships_list(integer) to authenticated,service_role;
grant execute on function public.ui_search_courses(text,integer) to authenticated,service_role;
