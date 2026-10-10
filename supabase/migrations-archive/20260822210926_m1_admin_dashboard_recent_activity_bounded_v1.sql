create or replace function security.admin_dashboard_maturity()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, security, catalogue, scholarship, pipeline, workflow, pim, search, auth
as $$
declare
  v_rank integer := 0;
  v_activity jsonb := '[]'::jsonb;
  v_search_generation bigint;
  v_search_rows bigint;
  v_search_rebuilt_at timestamptz;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  select generation,row_count,rebuilt_at into v_search_generation,v_search_rows,v_search_rebuilt_at
  from search.projection_state where projection_code='courses';

  with activity as (
    select * from (
      select 'job'::text kind,j.id,initcap(replace(coalesce(j.job_type,'job'),'_',' ')) title,
        coalesce(j.domain,'Pipeline') detail,coalesce(j.status,'unknown') status,
        coalesce(j.completed_at,j.started_at,j.created_at) occurred_at
      from pipeline.jobs j
      where coalesce(j.completed_at,j.started_at,j.created_at) is not null
      order by coalesce(j.completed_at,j.started_at,j.created_at) desc limit 10
    ) jobs
    union all
    select * from (
      select 'review'::text kind,r.id,'Review · '||initcap(replace(coalesce(r.domain,'general'),'_',' ')) title,
        coalesce(r.field_code,'Human resolution') detail,coalesce(r.status,'unknown') status,
        coalesce(r.updated_at,r.created_at) occurred_at
      from workflow.review_queue r
      where coalesce(r.updated_at,r.created_at) is not null
      order by coalesce(r.updated_at,r.created_at) desc limit 10
    ) reviews
    union all
    select * from (
      select 'evidence'::text kind,e.id,initcap(replace(coalesce(e.evidence_type,'evidence'),'_',' ')) title,
        'Evidence captured'::text detail,'captured'::text status,coalesce(e.captured_at,e.created_at) occurred_at
      from pipeline.evidence_artifacts e
      where coalesce(e.captured_at,e.created_at) is not null
      order by coalesce(e.captured_at,e.created_at) desc limit 10
    ) evidence
  ), recent as (select * from activity order by occurred_at desc limit 10)
  select coalesce(jsonb_agg(to_jsonb(recent) order by occurred_at desc),'[]'::jsonb) into v_activity from recent;

  return jsonb_build_object(
    'providers',(select count(*) from catalogue.providers),'courses',(select count(*) from catalogue.courses),
    'campuses',(select count(*) from catalogue.campuses),'course_campus_links',(select count(*) from catalogue.course_campuses),
    'scholarships',(select count(*) from scholarship.scholarships),'jobs',(select count(*) from pipeline.jobs),
    'open_reviews',(select count(*) from workflow.review_queue where status in ('open','in_review')),
    'evidence',(select count(*) from pipeline.evidence_artifacts),'attributes',(select count(*) from pim.attribute_definitions),
    'search_documents',(select count(*) from search.course_documents),'search_generation',v_search_generation,
    'operational',jsonb_build_object(
      'running_jobs',(select count(*) from pipeline.jobs where status in ('queued','pending','running','processing')),
      'failed_jobs_24h',(select count(*) from pipeline.jobs where status in ('failed','error') and coalesce(completed_at,created_at)>=now()-interval '24 hours'),
      'completed_jobs_24h',(select count(*) from pipeline.jobs where status in ('completed','succeeded') and coalesce(completed_at,created_at)>=now()-interval '24 hours'),
      'evidence_24h',(select count(*) from pipeline.evidence_artifacts where coalesce(captured_at,created_at)>=now()-interval '24 hours'),
      'latest_job_at',(select max(coalesce(completed_at,started_at,created_at)) from pipeline.jobs),
      'latest_evidence_at',(select max(coalesce(captured_at,created_at)) from pipeline.evidence_artifacts),
      'search_rebuilt_at',v_search_rebuilt_at,'search_row_count',v_search_rows),
    'recent_activity',v_activity);
end
$$;
