-- M2.4.4 cross-layer housekeeping: recover abandoned legacy Layer 1 regulatory jobs.
-- Scope is intentionally narrow: pipeline.jobs regulatory_sync rows only, older than 45 minutes,
-- and never where a live Layer 1 run-queue heartbeat still owns the job.
-- Governed Evidence/source versions/canonical history are not deleted or mutated.

create or replace function public.svc_layer1_housekeeping()
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'pipeline'
as $function$
declare
  v_recovered bigint := 0;
  v_deleted bigint := 0;
begin
  update pipeline.jobs j
  set status = 'failed',
      completed_at = now(),
      error_text = coalesce(
        j.error_text,
        'Layer 1 housekeeping recovered abandoned legacy regulatory_sync job.'
      ),
      result = coalesce(j.result, '{}'::jsonb)
        || jsonb_build_object(
             'recovery', 'layer1_housekeeping_stale_legacy_job',
             'recovered_at', now()
           )
  where j.status = 'running'
    and j.job_type = 'regulatory_sync'
    and coalesce(j.started_at, j.created_at) < now() - interval '45 minutes'
    and not exists (
      select 1
      from pipeline.layer1_run_queue q
      where q.actual_job_id = j.id
        and q.status = 'running'
        and coalesce(q.heartbeat_at, q.updated_at, q.started_at, q.requested_at)
            >= now() - interval '30 minutes'
    );

  get diagnostics v_recovered = row_count;

  delete from pipeline.layer1_run_queue
  where status in ('completed','failed','cancelled','blocked','no_change')
    and expires_at < now();

  get diagnostics v_deleted = row_count;

  return jsonb_build_object(
    'stale_legacy_jobs_recovered', v_recovered,
    'deleted_transient_runs', v_deleted,
    'governed_evidence_deleted', 0,
    'source_versions_deleted', 0,
    'canonical_history_deleted', 0,
    'policy',
    'Recovery only for abandoned legacy regulatory_sync jobs plus expired terminal Layer 1 queue rows; governed Evidence, source-operation versions and canonical history are retained.'
  );
end
$function$;
