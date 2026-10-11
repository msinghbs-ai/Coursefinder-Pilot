-- CF-247 (11 Oct 2026, Platform Admin bugs 11/10-3):
--  Fix 4: Scheduled jobs > Automations failed with a server error: its read looked up the run history three times per job (34 s over
--         289,228 runs). One pass over the last 8 days now (about 1 s; less once the history is trimmed by the Platform Admin paste).
--  Fix 3 / Task manager: the live board shows what is running this moment and everything in the last 15 minutes (each scheduled job,
--         each worker or API call by kind, scraper credits, AI spend), the work waiting in each queue with the job that drains it, and
--         any job not in the catalogue.
--  Fix 2: a register whose change check is unreliable (NZQA: its listing page differs on every read, so 5 full runs a day found nothing)
--         waits for its due date once its last two change-started runs found nothing different (Platform Admin: due date + file changed).
--  Fix 1: Jobs shows one row per register run (its last batch), and the job detail opens into the whole run: totals, what changed
--         against the register, every batch and every evidence file.
--  Fix 5: the retired national scholarship registers stop running and leave the active list (kept, with history).
--  Feature 1: every job whose command carries a batch size can have it changed in Automations.
-- md5-checked before and after. Nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := '{"security.admin_automations_read_v1()": "351b3d2f2f87b6ec304897c0e74559fc", "security.admin_running_now_v1()": "a74881aa71370011a5b105cfd5212258", "security.layer1_auto_ingest_tick_v1()": "dabaedcfe615c3a335ae74f389e1d54b", "security.admin_pipeline_ops_read(text,jsonb)": "bff14ec41b2bfcfeae90fc3912681505"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1. A register run, for a job that belongs to one (Fix 1): its totals, what changed against the register, every batch and every
--    evidence file the batches saved, so one row in Jobs opens into the whole run.
create or replace function security.layer1_run_for_job_v1(p_job uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
declare v_j pipeline.jobs%rowtype; q record; v_batch uuid[];
begin
  select * into v_j from pipeline.jobs j where j.id = p_job;
  if v_j.id is null or v_j.job_type <> 'regulatory_sync' or v_j.source_id is null then return null; end if;
  select * into q from pipeline.layer1_run_queue r
   where r.source_id = v_j.source_id and r.started_at is not null
     and v_j.created_at between r.started_at - interval '5 seconds' and coalesce(r.completed_at, now()) + interval '5 seconds'
   order by r.started_at desc limit 1;
  if q.id is null then return null; end if;
  v_batch := array(select j.id from pipeline.jobs j where j.source_id = q.source_id and j.job_type = 'regulatory_sync'
                    and j.created_at between q.started_at - interval '5 seconds' and coalesce(q.completed_at, now()) + interval '5 seconds' order by j.created_at);
  return jsonb_build_object(
    'run_id', q.id, 'status', q.status, 'mode', q.mode, 'started_at', q.started_at, 'completed_at', q.completed_at,
    'seconds', round(extract(epoch from (coalesce(q.completed_at, now()) - q.started_at))::numeric, 1),
    'started_by', case when q.requested_by = 'c0ffee00-0000-4000-8000-000000000150' then 'automatic' else coalesce((select u.email from auth.users u where u.id = q.requested_by), 'scheduler') end,
    'why', coalesce(q.result->>'reason', q.result#>>'{driver,reason}'),
    'counts', jsonb_build_object('expected', q.expected_count, 'processed', q.processed_count, 'created', q.created_count, 'updated', q.updated_count,
                                 'unchanged', q.unchanged_count, 'rejected', q.rejected_count, 'conflicted', q.conflicted_count, 'failed', q.failed_count),
    'register', (select jsonb_build_object('total', p.register_total, 'new', p.new_count, 'changed', p.changed_count, 'unchanged', p.unchanged_count, 'departed', p.departed_count,
                                           'departures', p.departures_status) from pipeline.layer1_run_plans p where p.run_id = q.id),
    'batches', (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'status', j.status, 'offset', j.payload->>'offset', 'next', j.result->>'nextOffset',
                         'records', coalesce(j.result#>>'{reconciliation,records}', j.result->>'totalRecords'), 'ms', j.result->>'runtimeMs', 'error', j.error_text) order by j.created_at), '[]'::jsonb)
                  from pipeline.jobs j where j.id = any (v_batch)),
    'evidence', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'evidence_type', e.evidence_type, 'source_url', e.source_url, 'content_hash', e.content_hash, 'captured_at', e.captured_at) order by e.captured_at), '[]'::jsonb)
                  from pipeline.evidence_artifacts e
                 where e.job_id = any (v_batch)
                    or e.id in (select x::uuid from pipeline.jobs j, jsonb_array_elements_text(coalesce(j.result->'evidenceIds', '[]'::jsonb)) x where j.id = any (v_batch) and x ~ '^[0-9a-f-]{36}$')));
end $f$;
revoke all on function security.layer1_run_for_job_v1(uuid) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.admin_automations_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'cron', 'security'
AS $function$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  -- v2.15.246 (Fix 4): one pass over the last 8 days of run history instead of three lookups per job (34 s, so the list failed with
  -- a server error); the last run, runs and failures in 24 hours are read from it. Jobs not yet in the catalogue are named.
  return (with r as materialized (select d.jobid, d.start_time, d.end_time, d.status, d.return_message from cron.job_run_details d where d.start_time >= now() - interval '8 days'),
               agg as (select jobid, count(*) filter (where start_time >= now() - interval '24 hours') runs_24h,
                              count(*) filter (where start_time >= now() - interval '24 hours' and status = 'failed') failed_24h, max(start_time) last_at from r group by jobid),
               last as (select r.* from r join agg on agg.jobid = r.jobid and agg.last_at = r.start_time)
    select jsonb_build_object('generated_at',now(),'rank',security.current_role_rank(),
    'jobs',(select coalesce(jsonb_agg(jsonb_build_object(
        'job',j.jobname,'area',coalesce(c.area,'Other'),'sort',coalesce(c.sort,999),'label',coalesce(c.label,j.jobname),'description',coalesce(c.description,''),
        'schedule',j.schedule,'active',j.active,'control_rank',coalesce(c.control_rank,6),'catalogued',c.jobname is not null,
        'batch',case when coalesce(c.batch_editable,false) then security.automation_batch(j.command) end,
        'last',(select jsonb_build_object('at',l.start_time,'status',l.status,'seconds',round(extract(epoch from (l.end_time-l.start_time))::numeric,1),'message',case when l.status<>'succeeded' then left(l.return_message,200) end)
                  from last l where l.jobid=j.jobid limit 1),
        'runs_24h',coalesce(a.runs_24h,0),
        'failed_24h',coalesce(a.failed_24h,0)
      ) order by coalesce(c.area,'Other'), coalesce(c.sort,999), j.jobname),'[]'::jsonb) from cron.job j left join pipeline.automation_catalogue c on c.jobname=j.jobname left join agg a on a.jobid=j.jobid),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='automations' order by created_at desc limit 15) e)));
end $function$;

CREATE OR REPLACE FUNCTION security.admin_running_now_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- v2.15.246 (Platform Admin, 11 Oct 2026: "Task manager was supposed to represent every job running ... which consumes resources"):
  -- running this moment, plus everything in the last 15 minutes (each scheduled job, each worker or API call by kind, scraper
  -- credits, AI spend) and the work waiting in each queue with the job that drains it. One pass over each log.
  with jr as materialized (select d.jobid, d.start_time, d.end_time, d.status from cron.job_run_details d where d.start_time > now() - interval '15 minutes'),
       calls as materialized (select l.function_name, coalesce(l.mode, '') mode, l.created_at, r.status_code, r.timed_out, (r.id is null) pending
                                from pipeline.edge_request_log l left join net._http_response r on r.id = l.request_id where l.created_at > now() - interval '15 minutes')
  select jsonb_build_object('at', now(), 'window_minutes', 15,
    'scheduled', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'label', coalesce(c.label, j.jobname), 'area', coalesce(c.area, 'Other'), 'started_at', d.start_time,
                     'seconds', extract(epoch from now() - d.start_time)::int, 'active', j.active, 'schedule', j.schedule, 'control_rank', coalesce(c.control_rank, 6)) order by d.start_time), '[]'::jsonb)
                   from cron.job_run_details d join cron.job j on j.jobid = d.jobid left join pipeline.automation_catalogue c on c.jobname = j.jobname
                  where d.status in ('running', 'starting') and d.start_time > now() - interval '6 hours'),
    'worker_calls', (select coalesce(jsonb_agg(jsonb_build_object('function', x.function_name, 'mode', x.mode, 'calls', x.n, 'oldest_at', x.oldest, 'seconds', extract(epoch from now() - x.oldest)::int) order by x.oldest), '[]'::jsonb)
                      from (select function_name, mode, count(*) n, min(created_at) oldest from calls where pending and created_at > now() - interval '10 minutes' group by 1, 2) x),
    'credits_last_hour', (select coalesce(jsonb_object_agg(u.purpose, u.n), '{}'::jsonb) from (select purpose, sum(units) n from pipeline.coverage_vendor_usage where at > now() - interval '1 hour' group by 1) u),
    'recent_jobs', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'label', coalesce(c.label, j.jobname), 'area', coalesce(c.area, 'Other'), 'runs', a.n, 'failed', a.failed,
                         'avg_seconds', a.avg_s, 'max_seconds', a.max_s, 'last_at', a.last_at, 'active', j.active, 'schedule', j.schedule, 'control_rank', coalesce(c.control_rank, 6), 'catalogued', c.jobname is not null)
                         order by a.total_s desc), '[]'::jsonb)
                      from (select jobid, count(*) n, count(*) filter (where status = 'failed') failed, round(avg(extract(epoch from (end_time - start_time)))::numeric, 1) avg_s,
                                   round(max(extract(epoch from (end_time - start_time)))::numeric, 1) max_s, sum(extract(epoch from (coalesce(end_time, now()) - start_time))) total_s, max(start_time) last_at
                              from jr group by jobid) a join cron.job j on j.jobid = a.jobid left join pipeline.automation_catalogue c on c.jobname = j.jobname),
    'recent_calls', (select coalesce(jsonb_agg(jsonb_build_object('function', x.function_name, 'mode', x.mode, 'calls', x.n, 'failed', x.failed, 'on_their_way', x.pending) order by x.n desc), '[]'::jsonb)
                      from (select function_name, mode, count(*) n, count(*) filter (where status_code >= 400 or timed_out) failed, count(*) filter (where pending) pending from calls group by 1, 2) x),
    'credits_15m', (select coalesce(jsonb_object_agg(u.purpose, u.n), '{}'::jsonb) from (select purpose, sum(units) n from pipeline.coverage_vendor_usage where at > now() - interval '15 minutes' group by 1) u),
    'ai_15m', (select coalesce(jsonb_object_agg(s.what, jsonb_build_object('calls', s.n, 'usd', round(s.usd::numeric, 4))), '{}'::jsonb) from (
                 select 'Layer 3 checks' what, count(*) n, sum(coalesce(estimated_cost_usd, 0)) usd from pipeline.layer3_interpretations where created_at > now() - interval '15 minutes'
                 union all select 'Course page matching', count(*), sum(coalesce(cost_usd, 0)) from pipeline.coverage_ai_match where decided_at > now() - interval '15 minutes'
                 union all select 'Page identity checks', count(*), sum(coalesce(cost_usd, 0)) from pipeline.coverage_identity_results where created_at > now() - interval '15 minutes'
                 union all select 'Adapter proposals', count(*), sum(coalesce(cost_usd, 0)) from pipeline.uni_adapter_drafts where updated_at > now() - interval '15 minutes' and cost_usd > 0) s where s.n > 0),
    'queues', jsonb_build_array(
       jsonb_build_object('label', 'Providers waiting for a website search', 'job', 'coverage-find-site', 'waiting', (select count(*) from pipeline.coverage_provider_discovery d where d.status = 'no_website' and coalesce(d.site_searched_at, '-infinity') < now() - interval '30 days')),
       jsonb_build_object('label', 'Providers waiting for a central page search', 'job', 'central-find', 'waiting', (select count(*) from pipeline.provider_central_search s where s.state = 'queued')),
       jsonb_build_object('label', 'Courses waiting for a course page search', 'job', 'course-link-search', 'waiting', (select count(*) from pipeline.course_link_search s where s.state = 'queued')),
       jsonb_build_object('label', 'Scholarship pages due to be read', 'job', 'scholarship-read', 'waiting', (select count(*) from pipeline.scholarship_pages p where p.next_read_at <= now())),
       jsonb_build_object('label', 'Register runs waiting or running', 'job', 'layer1-run-driver', 'waiting', (select count(*) from pipeline.layer1_run_queue q where q.status in ('queued', 'running', 'pending'))),
       jsonb_build_object('label', 'Tasks waiting or running', 'job', 'admin-jobs', 'waiting', (select count(*) from pipeline.admin_jobs a where a.state in ('queued', 'running')))),
    'uncatalogued', (select coalesce(jsonb_agg(j.jobname order by j.jobname), '[]'::jsonb) from cron.job j where not exists (select 1 from pipeline.automation_catalogue c where c.jobname = j.jobname)))
$function$;

CREATE OR REPLACE FUNCTION security.layer1_auto_ingest_tick_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare rec record; v_queued int:=0; v_skipped jsonb:='[]'::jsonb; v_run jsonb;
begin
  for rec in
    select o.source_id, o.variance_decision, o.last_source_hash, o.previous_accepted_hash
      from pipeline.layer1_source_operations o
     where o.auto_ingest and o.active and not o.paused
       and o.last_source_hash is not null and o.last_source_hash is distinct from o.previous_accepted_hash
       and coalesce(o.verification_status,'') in ('passed','warning')
       and (o.next_verification_at is null or o.next_verification_at>now())
       and not exists (select 1 from pipeline.layer1_run_queue q where q.source_id=o.source_id and q.status in ('queued','running'))
       -- do not retry a hash that an automatic run already failed on; a person decides
       and not exists (select 1 from pipeline.layer1_run_queue q where q.source_id=o.source_id and q.source_hash=o.last_source_hash
                         and q.status in ('failed','blocked') and q.requested_by='c0ffee00-0000-4000-8000-000000000150')
  loop
    -- v2.15.246 (Fix 2): when the last two runs started by a change found nothing new, changed or departed, this source's change
    -- check is not reliable (its page differs on every read); it waits for its due date (Platform Admin: due date + file changed)
    if (select count(*) from (select coalesce(p.new_count, 0) + coalesce(p.changed_count, 0) + coalesce(p.departed_count, 0) d
                                from pipeline.layer1_run_plans p join pipeline.layer1_run_queue q on q.id = p.run_id
                               where p.source_id = rec.source_id and q.status = 'completed' order by p.created_at desc limit 2) z where z.d = 0) = 2
       and exists (select 1 from pipeline.layer1_run_queue q join pipeline.layer1_source_operations o on o.source_id = q.source_id
                    where q.source_id = rec.source_id and q.status = 'completed'
                      and q.completed_at > now() - make_interval(days => coalesce(o.ingestion_cadence_days, 30))) then
      v_skipped:=v_skipped||jsonb_build_object('source_id',rec.source_id,'reason','the last two change-started runs found nothing different; waiting for the due date');
      continue;
    end if;
    if rec.variance_decision is distinct from 'pass' then
      v_skipped:=v_skipped||jsonb_build_object('source_id',rec.source_id,'reason','variance '||coalesce(rec.variance_decision,'unknown'));
      continue;
    end if;
    v_run:=security.layer1_queue_system_run_v1(rec.source_id,'apply',0,null,'Automatic ingestion: the register changed and the record count is within the pass band');
    v_queued:=v_queued+1;
  end loop;
  return jsonb_build_object('queued',v_queued,'skipped',v_skipped,'at',now());
end $function$;

CREATE OR REPLACE FUNCTION security.admin_pipeline_ops_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue', 'pim', 'ref', 'workflow', 'search', 'publishing', 'integration', 'auth'
AS $function$
declare
  v_rank integer := 0;
  v_limit integer := least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer := greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text := lower(coalesce(nullif(p_args->>'sort',''),'created'));
  v_dir text := case when lower(coalesce(nullif(p_args->>'direction',''),'desc'))='asc' then 'asc' else 'desc' end;
  v_id uuid;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0) < 4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  if p_operation='pipeline_jobs_page' then
    with projected as (
      select j.id,j.job_type,j.domain,j.status,j.source_id,s.label source_label,s.source_type,co.iso_alpha2::text country_code,co.name country_name,j.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,j.entity_id,er.entity_type,er.stable_key entity_stable_key,j.started_at,j.completed_at,j.created_at,j.attempt_count,
        case when lower(coalesce(s.metadata->>'layer','')) like '1%' or j.domain='regulatory' or j.job_type='regulatory_sync' then 'L1' when lower(coalesce(s.metadata->>'layer','')) like '2%' or j.job_type like 'layer2%' or s.source_type in ('provider_course_page','structured_outcomes','scholarship_catalogue','government_scholarship_program') then 'L2' when j.job_type ~* '(ai|llm|model|extract)' then 'L3' when j.job_type ~* '(review|resolve)' then 'L4' else 'UNCLASSIFIED' end layer_code,
        case when j.payload ? 'apply' then case when coalesce((j.payload->>'apply')::boolean,false) then 'APPLY' else 'DRY_RUN' end when lower(coalesce(j.result->>'mode',j.payload->>'mode',''))='apply' then 'APPLY' when lower(coalesce(j.result->>'mode',j.payload->>'mode','')) ~ '(dry|inventory|validate|qualification)' then 'DRY_RUN' else upper(nullif(coalesce(j.result->>'mode',j.payload->>'mode',''),'')) end run_mode,
        coalesce(j.payload->>'version',j.result->>'workerVersion',j.result->>'worker_version') worker_version,coalesce(j.payload->>'scope',j.result->>'scope',j.domain) run_scope,
        case when coalesce(j.payload->>'offset','') ~ '^-?[0-9]+$' then (j.payload->>'offset')::bigint else null end cursor_offset,
        case when coalesce(j.payload->>'batch_size','') ~ '^[0-9]+$' then (j.payload->>'batch_size')::integer when coalesce(j.result->>'batchSize','') ~ '^[0-9]+$' then (j.result->>'batchSize')::integer else null end batch_size,
        case when coalesce(j.result->>'nextOffset','') ~ '^-?[0-9]+$' then (j.result->>'nextOffset')::bigint when coalesce(j.result->>'next_offset','') ~ '^-?[0-9]+$' then (j.result->>'next_offset')::bigint else null end next_cursor,
        case when lower(coalesce(j.result->>'hasMore',j.result->>'has_more','')) in ('true','false') then lower(coalesce(j.result->>'hasMore',j.result->>'has_more'))::boolean else null end has_more,
        case when coalesce(j.result->>'sourceRows','') ~ '^[0-9]+$' then (j.result->>'sourceRows')::bigint when coalesce(j.result->>'source_rows','') ~ '^[0-9]+$' then (j.result->>'source_rows')::bigint when coalesce(j.result->>'discoveredRecords','') ~ '^[0-9]+$' then (j.result->>'discoveredRecords')::bigint else null end discovered_count,
        case when coalesce(j.result->>'selectedRecords','') ~ '^[0-9]+$' then (j.result->>'selectedRecords')::bigint when coalesce(j.result->>'selected_records','') ~ '^[0-9]+$' then (j.result->>'selected_records')::bigint when coalesce(j.result#>>'{reconciliation,records}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,records}')::bigint else null end selected_count,
        case when coalesce(j.result#>>'{reconciliation,records}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,records}')::bigint when coalesce(j.result->>'processedRecords','') ~ '^[0-9]+$' then (j.result->>'processedRecords')::bigint when coalesce(j.result->>'selectedRecords','') ~ '^[0-9]+$' then (j.result->>'selectedRecords')::bigint else null end processed_count,
        case when coalesce(j.result#>>'{reconciliation,mapped}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,mapped}')::bigint when coalesce(j.result->>'acceptedRecords','') ~ '^[0-9]+$' then (j.result->>'acceptedRecords')::bigint when coalesce(j.result->>'accepted_records','') ~ '^[0-9]+$' then (j.result->>'accepted_records')::bigint else null end accepted_count,
        (case when coalesce(j.result#>>'{reconciliation,unmapped}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,unmapped}')::bigint else 0 end + case when coalesce(j.result#>>'{reconciliation,course_missing}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,course_missing}')::bigint else 0 end + case when coalesce(j.result->>'rejectedRecords','') ~ '^[0-9]+$' then (j.result->>'rejectedRecords')::bigint else 0 end) rejected_count,
        case when coalesce(j.result#>>'{reconciliation,review_required}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,review_required}')::bigint else 0 end ambiguity_count,
        case when coalesce(j.result#>>'{reconciliation,observation_created}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,observation_created}')::bigint when coalesce(j.result->>'created','') ~ '^[0-9]+$' then (j.result->>'created')::bigint else null end creates_count,
        case when coalesce(j.result#>>'{reconciliation,observation_updated}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,observation_updated}')::bigint when coalesce(j.result->>'updated','') ~ '^[0-9]+$' then (j.result->>'updated')::bigint else null end updates_count,
        case when coalesce(j.result#>>'{reconciliation,observation_unchanged}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,observation_unchanged}')::bigint when coalesce(j.result->>'unchanged','') ~ '^[0-9]+$' then (j.result->>'unchanged')::bigint else null end unchanged_count,
        case when coalesce(j.result#>>'{reconciliation,conflicts}','') ~ '^[0-9]+$' then (j.result#>>'{reconciliation,conflicts}')::bigint when coalesce(j.result->>'conflicts','') ~ '^[0-9]+$' then (j.result->>'conflicts')::bigint else 0 end conflicts_count,
        (select count(*)::bigint from pipeline.evidence_artifacts e where e.job_id=j.id) evidence_count,
        case when j.started_at is not null then (extract(epoch from (coalesce(j.completed_at,now())-j.started_at))*1000)::bigint else null end duration_ms,
        case when j.status='running' and j.started_at < now()-interval '30 minutes' then 'stale_running' when j.status='blocked' then 'blocked' when j.status='failed' then 'incomplete_failure' when lower(coalesce(j.result->>'hasMore',j.result->>'has_more',''))='true' then 'partial_batch' when lower(coalesce(j.result->>'hasMore',j.result->>'has_more',''))='false' then 'source_or_scope_complete' when j.status='completed' then 'completed_scope_unknown' else 'in_progress_or_unknown' end completion_class,
        case when j.status='running' and j.started_at < now()-interval '30 minutes' then 'stale_runtime' when j.status='blocked' then 'governed_blocker' when j.status<>'failed' then null when lower(coalesce(j.error_text,'')) like '%superseded%' then 'historical_superseded' when lower(coalesce(j.error_text,'')) ~ '(inventory unstable|inventory incomplete|coverage blocker|source.*unstable)' then 'source_validation' when lower(coalesce(j.error_text,'')) ~ '(statement timeout|resource limit|compute limit|signal has been aborted|edge worker)' then 'technical_runtime' when lower(coalesce(j.error_text,'')) ~ '(schema cache|not defined|assignment to constant|requires a where clause|cannot insert|does not exist)' then 'technical_defect' when lower(coalesce(j.error_text,'')) like '%rejected%' then 'governed_rejection' else 'technical_failure' end failure_class,
        j.result->>'searchAction' search_action,coalesce(j.payload->>'change_control_ref',j.result->>'change_control_ref') change_control_ref,coalesce(j.payload->>'uat_ref',j.result->>'uat_ref') uat_ref,j.error_text,
        rq.run_id,rq.run_last_job_id,rq.run_summary
      from pipeline.jobs j left join pipeline.sources s on s.id=j.source_id left join ref.countries co on co.id=s.country_id left join catalogue.providers p on p.id=j.provider_id left join pim.entity_registry er on er.id=j.entity_id
      -- v2.15.246 (Fix 1): a register run's batches are one row (the run's last batch carries the run's totals)
      left join lateral (select q.id run_id, q.actual_job_id run_last_job_id, jsonb_build_object('status', q.status, 'started_at', q.started_at, 'completed_at', q.completed_at, 'expected', q.expected_count, 'processed', q.processed_count, 'created', q.created_count, 'updated', q.updated_count, 'unchanged', q.unchanged_count, 'conflicted', q.conflicted_count, 'failed', q.failed_count, 'register', (select jsonb_build_object('total', pl.register_total, 'new', pl.new_count, 'changed', pl.changed_count, 'departed', pl.departed_count) from pipeline.layer1_run_plans pl where pl.run_id = q.id)) run_summary
                           from pipeline.layer1_run_queue q where j.job_type='regulatory_sync' and q.source_id=j.source_id and q.started_at is not null and j.created_at between q.started_at - interval '5 seconds' and coalesce(q.completed_at, now()) + interval '5 seconds' order by q.started_at desc limit 1) rq on true
    ), filtered as (
      select * from projected x where (x.run_id is null or x.run_last_job_id is null or x.id = x.run_last_job_id) and (nullif(trim(coalesce(p_args->>'query','')),'') is null or x.id::text ilike '%'||trim(p_args->>'query')||'%' or coalesce(x.job_type,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(x.source_label,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(x.provider_name,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(x.worker_version,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(x.error_text,'') ilike '%'||trim(p_args->>'query')||'%') and (nullif(p_args->>'status','') is null or x.status=p_args->>'status') and (nullif(p_args->>'job_type','') is null or x.job_type=p_args->>'job_type') and (nullif(p_args->>'layer','') is null or x.layer_code=upper(p_args->>'layer')) and (nullif(p_args->>'mode','') is null or x.run_mode=upper(p_args->>'mode')) and (nullif(p_args->>'country_code','') is null or x.country_code=upper(p_args->>'country_code')) and (nullif(p_args->>'source_id','') is null or x.source_id=nullif(p_args->>'source_id','')::uuid) and (nullif(p_args->>'failure_class','') is null or x.failure_class=p_args->>'failure_class') and (nullif(p_args->>'completion_class','') is null or x.completion_class=p_args->>'completion_class')
    ), numbered as (select f.*,count(*) over()::bigint total_count from filtered f), ordered as (
      select * from numbered order by case when v_sort='created' and v_dir='asc' then created_at end asc,case when v_sort='created' and v_dir='desc' then created_at end desc,case when v_sort='duration' and v_dir='asc' then duration_ms end asc nulls last,case when v_sort='duration' and v_dir='desc' then duration_ms end desc nulls last,case when v_sort='status' and v_dir='asc' then status end asc,case when v_sort='status' and v_dir='desc' then status end desc,case when v_sort='layer' and v_dir='asc' then layer_code end asc,case when v_sort='layer' and v_dir='desc' then layer_code end desc,created_at desc,id limit v_limit offset v_offset
    ) select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) into v_result from ordered o; return v_result;
  elsif p_operation='pipeline_job_detail' then
    v_id:=nullif(p_args->>'id','')::uuid; if v_id is null then raise exception 'job id required' using errcode='22023'; end if;
    select jsonb_build_object('job',jsonb_build_object('id',j.id,'job_type',j.job_type,'domain',j.domain,'status',j.status,'source_id',j.source_id,'source_label',s.label,'source_type',s.source_type,'country_code',co.iso_alpha2,'country_name',co.name,'provider_id',j.provider_id,'provider_name',coalesce(p.display_name,p.canonical_name),'entity_id',j.entity_id,'entity_type',er.entity_type,'entity_stable_key',er.stable_key,'requested_by',j.requested_by,'started_at',j.started_at,'completed_at',j.completed_at,'duration_ms',case when j.started_at is null then null else (extract(epoch from (coalesce(j.completed_at,now())-j.started_at))*1000)::bigint end,'attempt_count',j.attempt_count,'created_at',j.created_at,'error_text',j.error_text,'payload',j.payload,'result',j.result),'run_semantics',jsonb_build_object('layer',case when lower(coalesce(s.metadata->>'layer','')) like '1%' or j.domain='regulatory' or j.job_type='regulatory_sync' then 'L1' when lower(coalesce(s.metadata->>'layer','')) like '2%' or j.job_type like 'layer2%' or s.source_type in ('provider_course_page','structured_outcomes','scholarship_catalogue','government_scholarship_program') then 'L2' when j.job_type ~* '(ai|llm|model|extract)' then 'L3' when j.job_type ~* '(review|resolve)' then 'L4' else 'UNCLASSIFIED' end,'authority',case when lower(coalesce(s.metadata->>'layer','')) like '1%' or j.domain='regulatory' or j.job_type='regulatory_sync' then 'regulatory_or_identity_authority' when lower(coalesce(s.metadata->>'layer','')) like '2%' or j.job_type like 'layer2%' then 'deterministic_enrichment_non_identity' when j.job_type ~* '(ai|llm|model|extract)' then 'suggestion_only_no_silent_overwrite' when j.job_type ~* '(review|resolve)' then 'human_resolution_auditable' else 'unclassified' end,'mode',case when j.payload ? 'apply' then case when coalesce((j.payload->>'apply')::boolean,false) then 'APPLY' else 'DRY_RUN' end when lower(coalesce(j.result->>'mode',j.payload->>'mode',''))='apply' then 'APPLY' when lower(coalesce(j.result->>'mode',j.payload->>'mode','')) ~ '(dry|inventory|validate|qualification)' then 'DRY_RUN' else upper(nullif(coalesce(j.result->>'mode',j.payload->>'mode',''),'')) end,'completion_class',case when j.status='running' and j.started_at < now()-interval '30 minutes' then 'stale_running' when j.status='blocked' then 'blocked' when j.status='failed' then 'incomplete_failure' when lower(coalesce(j.result->>'hasMore',j.result->>'has_more',''))='true' then 'partial_batch' when lower(coalesce(j.result->>'hasMore',j.result->>'has_more',''))='false' then 'source_or_scope_complete' when j.status='completed' then 'completed_scope_unknown' else 'in_progress_or_unknown' end,'search_action',j.result->>'searchAction','change_control_ref',coalesce(j.payload->>'change_control_ref',j.result->>'change_control_ref'),'uat_ref',coalesce(j.payload->>'uat_ref',j.result->>'uat_ref')),'source',case when s.id is null then null else jsonb_build_object('id',s.id,'label',s.label,'source_type',s.source_type,'url',s.url,'status',s.status,'trust_rank',s.trust_rank,'last_checked_at',s.last_checked_at,'last_success_at',s.last_success_at,'last_failure_at',s.last_failure_at,'last_error',s.last_error,'metadata',s.metadata) end,'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'evidence_type',e.evidence_type,'source_url',e.source_url,'storage_path',e.storage_path,'content_hash',e.content_hash,'mime_type',e.mime_type,'captured_at',e.captured_at,'valid_from',e.valid_from,'valid_to',e.valid_to,'supersedes_evidence_id',e.supersedes_evidence_id) order by e.captured_at desc) from pipeline.evidence_artifacts e where e.job_id=j.id),'[]'::jsonb),'entity_impact',jsonb_build_object('direct_entity',case when er.id is null then null else jsonb_build_object('id',er.id,'entity_type',er.entity_type,'stable_key',er.stable_key,'lifecycle_status',er.lifecycle_status) end,'direct_provider',case when p.id is null then null else jsonb_build_object('id',p.id,'stable_key',p.stable_key,'name',coalesce(p.display_name,p.canonical_name)) end,'scope_note',case when j.entity_id is null and j.provider_id is null then 'Batch/source-scoped job: entity-level impact links are not persisted on this job row; use evidence and adapter result counts.' else 'Direct entity/provider reference persisted on the job.' end),'safe_actions',jsonb_build_object('retry',jsonb_build_object('enabled',false,'reason','No generic retry command is exposed. Retry must be adapter-specific and idempotency-governed.'),'replay',jsonb_build_object('enabled',false,'reason','No generic replay command is exposed. Replay requires preserved evidence/hash plus adapter-specific scope validation.'),'reset',jsonb_build_object('enabled',false,'reason','Generic reset is intentionally prohibited. Any destructive reset requires an explicit governed scope and confirmation contract.'))) into v_result from pipeline.jobs j left join pipeline.sources s on s.id=j.source_id left join ref.countries co on co.id=s.country_id left join catalogue.providers p on p.id=j.provider_id left join pim.entity_registry er on er.id=j.entity_id where j.id=v_id; v_result := coalesce(v_result,'{}'::jsonb) || jsonb_build_object('run', security.layer1_run_for_job_v1(v_id)); return v_result;
  elsif p_operation='pipeline_sources_page' then
    with base as (select s.id source_id,s.label source_label,s.source_type,s.url source_url,s.status,s.trust_rank,s.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,co.iso_alpha2::text country_code,co.name country_name,case when lower(coalesce(s.metadata->>'layer','')) like '1%' then 'L1' when lower(coalesce(s.metadata->>'layer','')) like '2%' or s.source_type in ('provider_course_page','structured_outcomes','scholarship_catalogue','government_scholarship_program') then 'L2' when lower(coalesce(s.metadata->>'layer','')) like '3%' then 'L3' when lower(coalesce(s.metadata->>'layer','')) like '4%' then 'L4' else case when s.source_type in ('dataset','regulatory_programme','provincial_regulator','provincial_catalogue','institutional_catalogue','first_party_programme','web_catalogue') then 'L1' else 'UNCLASSIFIED' end end layer_code,s.last_checked_at,s.last_success_at,s.last_failure_at,s.last_error,case when s.last_failure_at is not null and (s.last_success_at is null or s.last_failure_at>s.last_success_at) then 'unhealthy' when s.last_success_at is not null then 'healthy' else 'untested' end health,case when s.last_success_at is null then null else round((extract(epoch from (now()-s.last_success_at))/86400.0)::numeric,2) end freshness_age_days,case when s.last_success_at is null then 'never_successful' when nullif(s.metadata->>'refresh_cadence','') is null then 'schedule_not_declared' else 'compare_to_declared_cadence' end freshness_class,s.metadata,(select max(j.completed_at) from pipeline.jobs j where j.source_id=s.id and j.status='completed') last_job_success_at,(select count(*)::bigint from pipeline.jobs j where j.source_id=s.id and j.status='running') running_jobs,(select count(*)::bigint from pipeline.jobs j where j.source_id=s.id and j.status in ('failed','blocked')) problem_jobs,(select count(*)::bigint from pipeline.evidence_artifacts e where e.source_id=s.id) evidence_count from pipeline.sources s left join ref.countries co on co.id=s.country_id left join catalogue.providers p on p.id=s.provider_id), filtered as (select * from base b where (nullif(trim(coalesce(p_args->>'query','')),'') is null or coalesce(b.source_label,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(b.source_type,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(b.provider_name,'') ilike '%'||trim(p_args->>'query')||'%' or coalesce(b.source_url,'') ilike '%'||trim(p_args->>'query')||'%') and (nullif(p_args->>'country_code','') is null or b.country_code=upper(p_args->>'country_code')) and (nullif(p_args->>'layer','') is null or b.layer_code=upper(p_args->>'layer')) and (nullif(p_args->>'status','') is null or b.status=p_args->>'status') and (nullif(p_args->>'source_type','') is null or b.source_type=p_args->>'source_type') and (nullif(p_args->>'health','') is null or b.health=p_args->>'health')), numbered as (select f.*,count(*) over()::bigint total_count from filtered f), ordered as (select * from numbered order by case when v_sort in ('source','name') and v_dir='asc' then lower(source_label) end asc,case when v_sort in ('source','name') and v_dir='desc' then lower(source_label) end desc,case when v_sort='country' and v_dir='asc' then country_code end asc nulls last,case when v_sort='country' and v_dir='desc' then country_code end desc nulls last,case when v_sort='health' and v_dir='asc' then health end asc,case when v_sort='health' and v_dir='desc' then health end desc,case when v_sort='freshness' and v_dir='asc' then freshness_age_days end asc nulls last,case when v_sort='freshness' and v_dir='desc' then freshness_age_days end desc nulls last,lower(source_label),source_id limit v_limit offset v_offset) select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),'total',coalesce(max(total_count),0),'limit',v_limit,'offset',v_offset,'sort',v_sort,'direction',v_dir) into v_result from ordered o; return v_result;
  elsif p_operation='pipeline_filters' then
    select jsonb_build_object('countries',coalesce((select jsonb_agg(x order by x->>'code') from (select distinct jsonb_build_object('code',co.iso_alpha2::text,'name',co.name) x from pipeline.sources s join ref.countries co on co.id=s.country_id) q),'[]'::jsonb),'job_types',coalesce((select jsonb_agg(job_type order by job_type) from (select distinct job_type from pipeline.jobs where job_type is not null) q),'[]'::jsonb),'statuses',coalesce((select jsonb_agg(status order by status) from (select distinct status from pipeline.jobs where status is not null) q),'[]'::jsonb),'source_types',coalesce((select jsonb_agg(source_type order by source_type) from (select distinct source_type from pipeline.sources where source_type is not null) q),'[]'::jsonb),'layers',jsonb_build_array('L1','L2','L3','L4','UNCLASSIFIED'),'modes',jsonb_build_array('DRY_RUN','APPLY')) into v_result; return v_result;
  elsif p_operation='pipeline_overview' then
    with job_stage as (select j.*,case when lower(coalesce(s.metadata->>'layer','')) like '1%' or j.domain='regulatory' or j.job_type='regulatory_sync' then 'L1' when lower(coalesce(s.metadata->>'layer','')) like '2%' or j.job_type like 'layer2%' or s.source_type in ('provider_course_page','structured_outcomes','scholarship_catalogue','government_scholarship_program') then 'L2' when j.job_type ~* '(ai|llm|model|extract)' then 'L3' when j.job_type ~* '(review|resolve)' then 'L4' else 'UNCLASSIFIED' end layer_code from pipeline.jobs j left join pipeline.sources s on s.id=j.source_id),source_stage as (select s.*,case when lower(coalesce(s.metadata->>'layer','')) like '1%' then 'L1' when lower(coalesce(s.metadata->>'layer','')) like '2%' or s.source_type in ('provider_course_page','structured_outcomes','scholarship_catalogue','government_scholarship_program') then 'L2' when lower(coalesce(s.metadata->>'layer','')) like '3%' then 'L3' when lower(coalesce(s.metadata->>'layer','')) like '4%' then 'L4' else case when s.source_type in ('dataset','regulatory_programme','provincial_regulator','provincial_catalogue','institutional_catalogue','first_party_programme','web_catalogue') then 'L1' else 'UNCLASSIFIED' end end layer_code from pipeline.sources s),layers as (select 'L1' code,'Layer 1 Regulatory' name,'regulatory_authority' authority,1 seq union all select 'L2','Layer 2 Deterministic / Structured Enrichment','non_identity_structured_enrichment',2 union all select 'L3','Layer 3 AI Suggestions','suggestion_only_no_silent_overwrite',3 union all select 'L4','Layer 4 Human Resolution','auditable_human_decision',4),layer_cards as (select jsonb_build_object('code',l.code,'name',l.name,'authority',l.authority,'source_count',(select count(*)::bigint from source_stage s where s.layer_code=l.code),'job_count',(select count(*)::bigint from job_stage j where j.layer_code=l.code),'running_jobs',(select count(*)::bigint from job_stage j where j.layer_code=l.code and j.status='running'),'stale_running_jobs',(select count(*)::bigint from job_stage j where j.layer_code=l.code and j.status='running' and j.started_at<now()-interval '30 minutes'),'failed_jobs',(select count(*)::bigint from job_stage j where j.layer_code=l.code and j.status='failed'),'blocked_jobs',(select count(*)::bigint from job_stage j where j.layer_code=l.code and j.status='blocked'),'last_success_at',(select max(j.completed_at) from job_stage j where j.layer_code=l.code and j.status='completed'),'current_job',(select jsonb_build_object('id',j.id,'job_type',j.job_type,'status',j.status,'started_at',j.started_at) from job_stage j where j.layer_code=l.code and j.status='running' order by j.started_at desc nulls last limit 1),'evidence_count',(select count(*)::bigint from pipeline.evidence_artifacts e join source_stage s on s.id=e.source_id where s.layer_code=l.code),'next_allowed_action',case when l.code='L3' then 'AI suggestions may be generated only into governed suggestion/claim surfaces; no silent overwrite of L1/L2.' when l.code='L4' then 'Resolve queued ambiguity/conflict through auditable review actions; direct canonical overwrite is not a review action.' when exists(select 1 from job_stage j where j.layer_code=l.code and j.status='running' and j.started_at<now()-interval '30 minutes') then 'Investigate stale running job before any replay.' when exists(select 1 from job_stage j where j.layer_code=l.code and j.status='blocked') then 'Resolve explicit blocker before rerun.' else 'Use adapter-specific dry-run/APPLY runbook; generic replay/reset is not exposed.' end,'blocker',case when exists(select 1 from job_stage j where j.layer_code=l.code and j.status='running' and j.started_at<now()-interval '30 minutes') then 'STALE_RUNNING_JOB' when exists(select 1 from job_stage j where j.layer_code=l.code and j.status='blocked') then 'BLOCKED_JOB_PRESENT' when l.code='L3' and (select count(*) from workflow.suggestions)=0 then 'NOT_OPERATIONAL_NO_SUGGESTIONS' when l.code='L4' and (select count(*) from workflow.review_queue)=0 then null else null end,'governance_ref',null,'uat_ref',null) item,l.seq from layers l) select jsonb_build_object('journey',jsonb_build_array('Layer 1 Regulatory','Layer 2 Deterministic/Structured Enrichment','Layer 3 AI Suggestions','Layer 4 Human Resolution','Search Admission','Publication'),'layers',(select jsonb_agg(item order by seq) from layer_cards),'layer3',jsonb_build_object('suggestions_total',(select count(*)::bigint from workflow.suggestions),'claims_total',(select count(*)::bigint from pipeline.claims where layer=3),'overwrite_policy','Layer 3 is suggestion-only and has no direct authority to overwrite Layer 1/2 facts.'),'layer4',jsonb_build_object('review_queue_total',(select count(*)::bigint from workflow.review_queue),'review_open',(select count(*)::bigint from workflow.review_queue where coalesce(status,'open') not in ('closed','resolved','rejected')),'review_actions_total',(select count(*)::bigint from workflow.review_actions),'audit_policy','Every human resolution must be represented by review_actions with before/after/reason/evidence where applicable.'),'search_admission',jsonb_build_object('documents',(select count(*)::bigint from search.course_documents),'projection',coalesce((select jsonb_build_object('projection_code',ps.projection_code,'generation',ps.generation,'row_count',ps.row_count,'rebuilt_at',ps.rebuilt_at,'content_hash',ps.content_hash,'metadata',ps.metadata) from search.projection_state ps where ps.projection_code='courses' limit 1),'{}'::jsonb),'country_gates',coalesce((select jsonb_agg(jsonb_build_object('projection_code',g.projection_code,'country_code',co.iso_alpha2,'gate_status',g.gate_status,'approval_ref',g.approval_ref,'approved_at',g.approved_at,'updated_at',g.updated_at) order by co.iso_alpha2) from search.projection_country_gates g left join ref.countries co on co.id=g.country_id),'[]'::jsonb),'enrichment_gates',coalesce((select jsonb_agg(to_jsonb(g) order by g.domain_code) from search.enrichment_gates g),'[]'::jsonb),'blocked_enrichment_gates',(select count(*)::bigint from search.enrichment_gates where gate_status<>'approved'),'definition','Ingestion/enrichment completion does not imply Search admission. Search gates are reported independently.'),'publication',jsonb_build_object('entity_states_total',(select count(*)::bigint from publishing.entity_states),'channels',coalesce((select jsonb_agg(to_jsonb(c) order by c.code) from publishing.channels c),'[]'::jsonb),'status_counts',coalesce((select jsonb_object_agg(publication_status,cnt) from (select publication_status,count(*)::bigint cnt from publishing.entity_states group by publication_status) q),'{}'::jsonb),'definition','Publication is a downstream channel state and is not equivalent to successful ingestion or Search projection.'),'guardrails',jsonb_build_object('generic_reset',false,'generic_retry',false,'generic_replay',false,'reason','Destructive/replay operations require adapter-specific governed scope, preserved evidence/hash, explicit confirmation and idempotency semantics.'),'observed_volumes',jsonb_build_object('jobs',(select count(*)::bigint from pipeline.jobs),'sources',(select count(*)::bigint from pipeline.sources),'evidence',(select count(*)::bigint from pipeline.evidence_artifacts),'claims',(select count(*)::bigint from pipeline.claims))) into v_result; return v_result;
  else raise exception 'unsupported pipeline ops read: %',p_operation using errcode='22023'; end if;
end $function$;

-- 2. Fix 5: the national scholarship registers retired on 11 Oct 2026 (Study Australia, DFAT Australia Awards, Manaaki) stop running
--    and leave the active source list. Kept, with their history.
update pipeline.layer1_source_operations
   set active = false, paused = true, auto_ingest = false, updated_at = now(),
       change_reason = 'Retired 11 Oct 2026 (CF-247, Platform Admin): scholarships come from providers'' own pages only'
 where source_id in ('17a7d379-9448-41ca-bca5-bb7537ffff4b', 'a9443687-678b-436f-9c16-62fcb800af14', '717432c7-32f9-47c3-9111-7f75fd79c128') and (active or auto_ingest);
update pipeline.sources set status = 'retired', updated_at = now()
 where id in ('17a7d379-9448-41ca-bca5-bb7537ffff4b', 'a9443687-678b-436f-9c16-62fcb800af14', '717432c7-32f9-47c3-9111-7f75fd79c128') and status <> 'retired';

-- 3. Feature 1: every job whose command carries a batch size can have it changed in Automations
update pipeline.automation_catalogue c set batch_editable = true
  from cron.job j where j.jobname = c.jobname and not c.batch_editable and security.automation_batch(j.command) is not null;

do $post$
declare v_expected jsonb := '{"security.admin_automations_read_v1()": "e4564f611f4bcc79cd26991d42bf4500", "security.admin_running_now_v1()": "420627ee07ef97a4dd34f6687b0c90a5", "security.layer1_auto_ingest_tick_v1()": "21f3251500f1824fcff82713d15339ce", "security.admin_pipeline_ops_read(text,jsonb)": "b5d89ce1e5b3b7c3de2398d5ef27289d"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $chk$
begin
  if exists (select 1 from pipeline.layer1_source_operations where source_id in ('17a7d379-9448-41ca-bca5-bb7537ffff4b', 'a9443687-678b-436f-9c16-62fcb800af14', '717432c7-32f9-47c3-9111-7f75fd79c128') and (active or auto_ingest)) then
    raise exception 'CF-247 post-check: a retired scholarship register is still active';
  end if;
  if exists (select 1 from cron.job j join pipeline.automation_catalogue c on c.jobname = j.jobname where not c.batch_editable and security.automation_batch(j.command) is not null) then
    raise exception 'CF-247 post-check: a job with a batch size cannot have it changed';
  end if;
end $chk$;
