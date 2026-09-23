-- PERF-1: pre-computed Dashboard and layer-status summaries.
-- Problem: security.admin_dashboard_maturity() and admin_layer_status_summary()
-- counted across 27 tables on every screen open. With cold cache they took 2-5 s,
-- and parallel screen loads exceeded the 8 s authenticated statement timeout (HTTP 500).
-- Design (decided 23 Sep 2026):
--  * Counting moves to *_compute() functions, callable only by service_role.
--  * A background job refreshes security.admin_summary_snapshots every 2 minutes.
--  * The read functions keep their names, auth/role checks and output shape, and add
--    snapshot_at and snapshot_source ('snapshot' | 'live').
--  * If a snapshot is missing or older than 10 minutes, the read computes live.
--  * Dashboard open_reviews and recent review activity now use Layer 4 review items
--    (workflow.review_queue has never held an item and nothing writes to it).

create table if not exists security.admin_summary_snapshots(
  snapshot_key text primary key check (snapshot_key in ('dashboard','layer_status_summary')),
  payload jsonb not null,
  computed_at timestamptz not null default now(),
  compute_ms integer
);
alter table security.admin_summary_snapshots enable row level security;
revoke all on security.admin_summary_snapshots from public, anon, authenticated;

-- ---------- Dashboard: compute (no auth; service-only) ----------
create or replace function security.admin_dashboard_maturity_compute()
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','security','catalogue','scholarship','pipeline','workflow','pim','search','auth'
as $function$
declare
  v_activity jsonb := '[]'::jsonb;
  v_search_generation bigint;
  v_search_rows bigint;
  v_search_rebuilt_at timestamptz;
begin
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
      select 'review'::text kind,r.id,'Review · '||initcap(replace(coalesce(r.field_code,'review'),'_',' ')) title,
        'Layer 4 human resolution'::text detail,coalesce(r.status,'unknown') status,
        coalesce(r.decided_at,r.created_at) occurred_at
      from pipeline.layer4_review_items r
      where coalesce(r.decided_at,r.created_at) is not null
      order by coalesce(r.decided_at,r.created_at) desc limit 10
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
    'open_reviews',(select count(*) from pipeline.layer4_review_items where status='pending'),
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
$function$;

-- ---------- Layer status: compute (no auth; service-only) ----------
create or replace function security.admin_layer_status_summary_compute()
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','scholarship','auth'
as $function$
begin
 return jsonb_build_object(
  'layer1',jsonb_build_object(
    'active_sources',(select count(*) from pipeline.sources where status='active' and coalesce(metadata->>'layer','')='1'),
    'running_jobs',(select count(*) from pipeline.jobs where job_type='regulatory_sync' and status='running'),
    'failed_24h',(select count(*) from pipeline.jobs where job_type='regulatory_sync' and status='failed' and created_at>now()-interval '24 hours'),
    'latest_activity',(select max(created_at) from pipeline.jobs where job_type='regulatory_sync')
  ),
  'layer2',jsonb_build_object(
    'active_batches',(select count(*) from pipeline.layer2_run_batches where status in('queued','running','partial')),
    'scheduled_wave_requests',(select count(*) from pipeline.layer2_scope_wave_requests where status in('scheduled','running','wave1_dispatched')),
    'wave_pending_courses',(select count(*) from pipeline.layer2_scope_wave_items where status='pending'),
    'processed_24h',(select count(*) from pipeline.layer2_run_items where completed_at>now()-interval '24 hours'),
    'evidence_24h',(select count(*) from pipeline.evidence_artifacts where coalesce(metadata->>'layer','') like '2%' and captured_at>now()-interval '24 hours')
  ),
  'layer3',jsonb_build_object(
    'qualified_profiles',(select count(*) from pipeline.layer3_model_profiles where enabled and not paused and coalesce((quality_benchmark->>'pass')::boolean,false)),
    'pending_evidence_candidates',(
      select count(distinct ri.entity_id)
      from pipeline.layer2_run_items ri
      join pipeline.layer2_provider_attempts pa on pa.job_id=ri.job_id and pa.status='succeeded'
      where ri.entity_type='course' and ri.status='layer3_required'
        and exists (
          select 1 from pipeline.evidence_artifacts e
          where e.id in (pa.raw_evidence_id,pa.html_evidence_id)
            and e.storage_path is not null and e.content_hash is not null
            and (e.valid_to is null or e.valid_to>now())
            and coalesce(e.review_state,'') not in ('rejected','invalid')
            and (e.mime_type is null or e.mime_type like 'text/%' or e.mime_type in ('application/json','application/xml','application/xhtml+xml'))
        )
    ),
    'interpretations_24h',(select count(*) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours'),
    'calls_24h',(select coalesce(sum(external_call_count),0) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours'),
    'tokens_24h',(select coalesce(sum(input_tokens+output_tokens),0) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours'),
    'recorded_cost_24h',(select coalesce(sum(estimated_cost_usd),0) from pipeline.layer3_interpretations where created_at>now()-interval '24 hours')
  ),
  'layer4',jsonb_build_object(
    'pending_reviews',(select count(*) from pipeline.layer4_review_items where status='pending'),
    'active_overrides',(select count(*) from (
      select distinct on(entity_type,entity_id,field_code) event_type
      from pipeline.layer4_override_decisions order by entity_type,entity_id,field_code,created_at desc,id desc
    ) x where event_type<>'revert'),
    'publication_decisions',(select count(*) from pipeline.layer4_publication_decisions)
  ),
  'scholarships',jsonb_build_object(
    'scholarships',(select count(*) from scholarship.scholarships),
    'course_mappings',(select count(*) from scholarship.course_mappings where mapping_state='mapped'),
    'review_candidates',(select count(*) from scholarship.course_mapping_candidates where status='needs_review')
  )
 );
end $function$;

-- ---------- Background refresh (service only) ----------
create or replace function security.admin_summary_snapshots_refresh()
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','security'
as $function$
declare v_caller text; t timestamptz; v jsonb; d_ms int; l_ms int;
begin
  v_caller := coalesce(nullif(current_setting('request.jwt.claim.role',true),''),nullif(current_setting('request.jwt.role',true),''),session_user);
  if v_caller not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  t := clock_timestamp(); v := security.admin_dashboard_maturity_compute(); d_ms := round(extract(epoch from clock_timestamp()-t)*1000);
  insert into security.admin_summary_snapshots(snapshot_key,payload,computed_at,compute_ms) values('dashboard',v,now(),d_ms)
  on conflict(snapshot_key) do update set payload=excluded.payload, computed_at=excluded.computed_at, compute_ms=excluded.compute_ms;
  t := clock_timestamp(); v := security.admin_layer_status_summary_compute(); l_ms := round(extract(epoch from clock_timestamp()-t)*1000);
  insert into security.admin_summary_snapshots(snapshot_key,payload,computed_at,compute_ms) values('layer_status_summary',v,now(),l_ms)
  on conflict(snapshot_key) do update set payload=excluded.payload, computed_at=excluded.computed_at, compute_ms=excluded.compute_ms;
  return jsonb_build_object('ok',true,'dashboard_ms',d_ms,'layer_status_summary_ms',l_ms);
end $function$;

-- ---------- Reads used by screens (same names, checks and shape) ----------
create or replace function security.admin_dashboard_maturity()
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','security','auth'
as $function$
declare v_rank integer := 0; v_payload jsonb; v_at timestamptz;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  select payload, computed_at into v_payload, v_at from security.admin_summary_snapshots
  where snapshot_key='dashboard' and computed_at > now() - interval '10 minutes';
  if v_payload is not null then
    return v_payload || jsonb_build_object('snapshot_at', v_at, 'snapshot_source', 'snapshot');
  end if;
  return security.admin_dashboard_maturity_compute() || jsonb_build_object('snapshot_at', now(), 'snapshot_source', 'live');
end $function$;

create or replace function security.admin_layer_status_summary()
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','security','auth'
as $function$
declare v_rank integer; v_payload jsonb; v_at timestamptz;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 v_rank:=security.current_role_rank(); if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
 select payload, computed_at into v_payload, v_at from security.admin_summary_snapshots
 where snapshot_key='layer_status_summary' and computed_at > now() - interval '10 minutes';
 if v_payload is not null then
   return v_payload || jsonb_build_object('snapshot_at', v_at, 'snapshot_source', 'snapshot');
 end if;
 return security.admin_layer_status_summary_compute() || jsonb_build_object('snapshot_at', now(), 'snapshot_source', 'live');
end $function$;

revoke all on function security.admin_dashboard_maturity_compute() from public, anon, authenticated;
revoke all on function security.admin_layer_status_summary_compute() from public, anon, authenticated;
revoke all on function security.admin_summary_snapshots_refresh() from public, anon, authenticated;
grant execute on function security.admin_dashboard_maturity_compute() to service_role;
grant execute on function security.admin_layer_status_summary_compute() to service_role;
grant execute on function security.admin_summary_snapshots_refresh() to service_role;

-- Every 2 minutes (decided 23 Sep 2026).
select cron.unschedule(jobid) from cron.job where jobname='admin-summary-snapshots-refresh';
select cron.schedule('admin-summary-snapshots-refresh', '*/2 * * * *', $cron$select security.admin_summary_snapshots_refresh();$cron$);

-- Populate immediately so screens never start on the live fallback.
select security.admin_summary_snapshots_refresh();
