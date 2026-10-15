CREATE OR REPLACE FUNCTION security.platform_health_check_v1(p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security', 'public', 'catalogue', 'scholarship'
 SET statement_timeout TO '60s'
AS $function$
declare
  v_t0 timestamptz:=clock_timestamp(); v_t timestamptz;
  v_found jsonb:='[]'::jsonb; v_ok text[]:='{}'; v_ms jsonb:='{}'::jsonb; v_det jsonb:='{}'::jsonb;
  v_slow_used boolean:=false; r record; v_n bigint; v_n2 bigint; v_n3 bigint; v_x jsonb; v_q jsonb; v_prev jsonb;
  v_ts timestamptz; v_ts2 timestamptz; v_num numeric; v_num2 numeric; v_txt text; v_args text; v_arr text[]; v_bool boolean;
  v_counts jsonb; v_jobs int:=0; v_fail int:=0; v_stale int:=0;
begin
  -- 4.1 scheduled jobs: failures in the last hour; active jobs not run in more than 3x their interval
  if security.platform_health_due_v1('cron',p_force) then
    v_t:=clock_timestamp();
    begin
      for r in
        with agg as (
          select d.jobid, max(d.start_time) last_run, min(d.start_time) first_run,
                 count(*) filter (where d.status='failed' and d.start_time>=now()-interval '1 hour') fails_1h,
                 count(*) filter (where d.start_time>=now()-interval '1 hour') runs_1h,
                 (array_agg(left(d.return_message,200) order by d.start_time desc) filter (where d.status='failed'))[1] last_error
            from cron.job_run_details d group by d.jobid)
        select j.jobid, j.jobname, j.schedule, security.platform_cron_interval_seconds(j.schedule) ival,
               a.last_run, coalesce(a.fails_1h,0) fails_1h, coalesce(a.runs_1h,0) runs_1h, a.last_error,
               (select min(a2.first_run) from agg a2 where a2.jobid>j.jobid) created_before
          from cron.job j left join agg a on a.jobid=j.jobid where j.active
      loop
        v_jobs:=v_jobs+1;
        if r.fails_1h>0 then
          v_fail:=v_fail+1;
          select bool_and(x.status='failed') into v_bool from (select d.status from cron.job_run_details d where d.jobid=r.jobid order by d.start_time desc limit 3) x;
          v_found:=v_found||security.platform_health_issue_v1('cron:failed:'||r.jobname, case when v_bool and r.runs_1h>=3 then 'critical' else 'warning' end,
            'scheduled jobs', 'Scheduled job "'||r.jobname||'" failed '||r.fails_1h||' of '||r.runs_1h||' run(s) in the last hour',
            jsonb_build_object('job',r.jobname,'schedule',r.schedule,'failures_1h',r.fails_1h,'runs_1h',r.runs_1h,'last_error',r.last_error,'last_three_failed',coalesce(v_bool,false)));
        end if;
        v_ts:=coalesce(r.last_run, r.created_before);
        if r.ival is not null and v_ts is not null and now()-v_ts > make_interval(secs=>3*r.ival) + interval '2 minutes' then
          v_stale:=v_stale+1;
          v_found:=v_found||security.platform_health_issue_v1('cron:stale:'||r.jobname,
            case when now()-v_ts > greatest(make_interval(secs=>12*r.ival), interval '2 hours') and r.ival<=3600 then 'critical' else 'warning' end,
            'scheduled jobs', 'Scheduled job "'||r.jobname||'" has not run '||case when r.last_run is null then 'since it was scheduled' else 'since '||to_char(r.last_run at time zone 'UTC','DD Mon HH24:MI')||' UTC' end,
            jsonb_build_object('job',r.jobname,'schedule',r.schedule,'expected_every_minutes',round(r.ival/60.0,1),'last_run',r.last_run));
        end if;
      end loop;
      v_det:=v_det||jsonb_build_object('cron',jsonb_build_object('active_jobs',v_jobs,'jobs_failing',v_fail,'jobs_overdue',v_stale));
      v_ok:=array_append(v_ok,'cron');
    exception when others then
      v_ok:=array_append(v_ok,'cron');
      v_found:=v_found||security.platform_health_issue_v1('cron:check_error','warning','scheduled jobs','The scheduled-job health check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('cron',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.2 Edge function calls made through pg_net over the last 30 minutes, grouped by function
  if security.platform_health_due_v1('edge_calls',p_force) then
    v_t:=clock_timestamp(); v_n:=0; v_n2:=0; v_q:='[]'::jsonb;
    begin
      for r in
        with resp as (
          select rr.id, rr.status_code, rr.timed_out, rr.error_msg, rr.content,
                 coalesce(c.function_name, substring(rr.content from '"workerVersion"\s*:\s*"([a-z0-9-]+?)-v[0-9]'), 'unattributed') fn,
                 (coalesce(rr.status_code,0)>=400 or rr.timed_out is true or rr.error_msg is not null) failed
            from net._http_response rr left join pipeline.platform_edge_calls c on c.id=rr.id
           where rr.created>=now()-interval '30 minutes')
        select fn, count(*) total, count(*) filter (where failed) failures, count(*) filter (where timed_out) timeouts,
               count(*) filter (where status_code=404 and (content ilike '%NOT_FOUND%' or content ilike '%function was not found%')) not_deployed,
               array_agg(distinct coalesce(status_code::text, case when timed_out then 'timeout' else 'error' end)) filter (where failed) codes,
               (array_agg(left(coalesce(content,error_msg),200) order by id desc) filter (where failed))[1] sample
          from resp group by fn order by count(*) filter (where failed) desc
      loop
        v_n:=v_n+r.total; v_n2:=v_n2+r.failures;
        if jsonb_array_length(v_q)<15 then v_q:=v_q||jsonb_build_object('function',r.fn,'calls',r.total,'failures',r.failures,'timeouts',r.timeouts); end if;
        if r.not_deployed>0 then
          v_found:=v_found||security.platform_health_issue_v1('edge_calls:not_deployed:'||r.fn,'critical','edge functions',
            'Edge function "'||r.fn||'" is called but not deployed (404, '||r.not_deployed||' call(s) in 30 minutes)',
            jsonb_build_object('function',r.fn,'calls',r.total,'not_found',r.not_deployed,'sample',r.sample));
        elsif r.failures>=2 then
          v_found:=v_found||security.platform_health_issue_v1('edge_calls:failing:'||r.fn,
            case when r.failures>=3 and r.failures=r.total then 'critical' else 'warning' end,'edge functions',
            case when r.fn='unattributed' then 'Edge function calls' else 'Edge function "'||r.fn||'"' end||': '||r.failures||' of '||r.total||' call(s) failed in the last 30 minutes'
              ||case when r.timeouts>0 then ' ('||r.timeouts||' timed out)' else '' end,
            jsonb_build_object('function',r.fn,'calls',r.total,'failures',r.failures,'timeouts',r.timeouts,'codes',to_jsonb(r.codes),'sample',r.sample));
        end if;
      end loop;
      select count(*) into v_n3 from net.http_request_queue;
      if v_n3>100 then
        v_found:=v_found||security.platform_health_issue_v1('edge_calls:queue_backlog', case when v_n3>500 then 'critical' else 'warning' end,'edge functions',
          v_n3||' outbound calls are waiting in the pg_net queue',jsonb_build_object('queued',v_n3));
      end if;
      v_det:=v_det||jsonb_build_object('edge_calls',jsonb_build_object('window_minutes',30,'calls',v_n,'failures',v_n2,'queued',v_n3,'by_function',v_q));
      v_ok:=array_append(v_ok,'edge_calls');
    exception when others then
      v_ok:=array_append(v_ok,'edge_calls');
      v_found:=v_found||security.platform_health_issue_v1('edge_calls:check_error','warning','edge functions','The Edge function call check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('edge_calls',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.3 Edge functions deployed vs expected: not queryable from the database (skipped; recently invoked list only)
  if security.platform_health_due_v1('edge_deployed',p_force) then
    v_t:=clock_timestamp();
    begin
      v_det:=v_det||jsonb_build_object('edge_deployed',jsonb_build_object(
        'note','Skipped: the live Edge function list cannot be read from the database. Compare supabase/functions in git with the live list (Supabase list_edge_functions). A call to a missing function shows here as a 404 under Edge function calls.',
        'invoked_last_24h',coalesce((select jsonb_agg(distinct function_name order by function_name) from pipeline.platform_edge_calls where created_at>=now()-interval '24 hours'),'[]'::jsonb)));
      v_ok:=array_append(v_ok,'edge_deployed');
    exception when others then null;
    end;
    v_ms:=v_ms||jsonb_build_object('edge_deployed',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.4 coverage sweep queues
  if security.platform_health_due_v1('coverage_queues',p_force) then
    v_t:=clock_timestamp(); v_q:='[]'::jsonb;
    begin
      select max(read_at) into v_ts from pipeline.coverage_course_pages;
      v_q:=v_q||security.platform_health_stall_v1('coverage_queues:read','coverage sweep','Coverage page reading','coverage-read',v_ts,
        $q$select count(*) from pipeline.coverage_course_pages p where p.status in ('bound','ambiguous') and coalesce(p.next_read_at,now())<=now() and p.read_attempts<3$q$);
      select max(updated_at) into v_ts from pipeline.coverage_provider_discovery;
      v_q:=v_q||security.platform_health_stall_v1('coverage_queues:discover','coverage sweep','Coverage provider discovery','coverage-discover',v_ts,
        $q$select count(*) from pipeline.coverage_provider_discovery d where (d.status='pending' or (d.status in ('mapped','failed') and d.next_due_at<=now())) and d.attempts<3$q$);
      -- re-extract has no timestamp: progress means the number of pages on an older extractor went down
      select c.candidates->>'extractor' into v_txt from pipeline.coverage_course_pages c where c.read_status='read' and c.read_at is not null order by c.read_at desc limit 1;
      select count(*) into v_n from pipeline.coverage_course_pages cp
       where cp.read_status='read' and cp.identity_basis is not null and cp.evidence_id is not null and coalesce(cp.candidates->>'extractor','')<>coalesce(v_txt,'');
      select c.detail->'reextract' into v_prev from pipeline.platform_health_checks c where c.key='coverage_queues';
      v_ts:=case when v_n=0 or v_n<coalesce((v_prev->>'pending')::bigint, v_n+1) then now() else coalesce((v_prev->>'progress_at')::timestamptz, now()) end;
      v_q:=v_q||(security.platform_health_stall_v1('coverage_queues:reextract','coverage sweep','Coverage re-extraction','coverage-reextract',v_ts,'select '||v_n)
                 ||jsonb_build_object('pending',v_n,'progress_at',v_ts,'extractor',v_txt));
      -- tuition hand-off to Layer 3 (only runs while a qualified tuition profile exists)
      select max(l3_handoff_at) into v_ts from pipeline.coverage_course_pages;
      v_bool:=exists(select 1 from pipeline.layer3_model_profiles where 'provider_current_tuition_validation'=any(allowed_task_classes) and enabled and not paused and coalesce((quality_benchmark->>'pass')::boolean,false));
      v_x:=security.platform_health_stall_v1('coverage_queues:tuition_handoff','coverage sweep','Tuition hand-off to Layer 3','coverage-tuition-handoff',v_ts,
        $q$select count(*) from pipeline.coverage_course_pages p join catalogue.courses co on co.id=p.course_id and co.lifecycle_status='active'
            where p.read_status='read' and p.identity_basis='cricos_code' and p.l3_work_item_id is null
              and (p.l3_handoff_at is null or p.l3_handoff_at<now()-interval '1 day')
              and security.coverage_tuition_target_v1(p.candidates->'fee') is not null
              and not exists (select 1 from catalogue.course_fees f where f.course_id=p.course_id and f.fee_type='provider_current_tuition' and f.status='active')$q$);
      if not v_bool and v_x ? 'issue' then
        v_x:=jsonb_set(v_x,'{issue}',(v_x->'issue')||jsonb_build_object('severity','info',
          'title','Tuition hand-off is paused: no qualified, enabled tuition model profile ('||(v_x->>'pending')||' pages waiting)'));
      end if;
      v_q:=v_q||(v_x||jsonb_build_object('qualified_profile',v_bool));
      select coalesce(jsonb_agg(e->'issue'),'[]'::jsonb) into v_x from jsonb_array_elements(v_q) e where e ? 'issue';
      v_found:=v_found||v_x;
      v_det:=v_det||jsonb_build_object('coverage_queues',jsonb_build_object('queues',(select jsonb_agg(e-'issue') from jsonb_array_elements(v_q) e),
        'reextract',(select e-'issue'-'queue'-'status' from jsonb_array_elements(v_q) e where e->>'queue'='coverage_queues:reextract')));
      v_ok:=array_append(v_ok,'coverage_queues');
    exception when others then
      v_ok:=array_append(v_ok,'coverage_queues');
      v_found:=v_found||security.platform_health_issue_v1('coverage_queues:check_error','warning','coverage sweep','The coverage queue check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('coverage_queues',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.5 scholarship queues
  if security.platform_health_due_v1('scholarship_queues',p_force) then
    v_t:=clock_timestamp(); v_q:='[]'::jsonb;
    begin
      select max(read_at) into v_ts from pipeline.scholarship_pages;
      v_q:=v_q||security.platform_health_stall_v1('scholarship_queues:read','scholarships','Scholarship page reading','scholarship-read',v_ts,
        $q$select count(*) from pipeline.scholarship_pages p join scholarship.scholarships s on s.id=p.scholarship_id and s.lifecycle_status='active'
            where p.next_read_at<=now() and p.attempts<5$q$);
      select max(read_at) into v_ts from pipeline.scholarship_page_candidates;
      v_q:=v_q||security.platform_health_stall_v1('scholarship_queues:candidates','scholarships','Scholarship candidate page reading','scholarship-discover',v_ts,
        $q$select count(*) from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
            where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and c.attempts<3$q$);
      select max(updated_at) into v_ts from pipeline.scholarship_discovery_providers;
      v_q:=v_q||security.platform_health_stall_v1('scholarship_queues:discover','scholarships','Scholarship provider discovery','scholarship-discover',v_ts,
        $q$select count(*) from pipeline.scholarship_discovery_providers d where d.status='pending' and d.attempts<3$q$);
      select coalesce(jsonb_agg(e->'issue'),'[]'::jsonb) into v_x from jsonb_array_elements(v_q) e where e ? 'issue';
      v_found:=v_found||v_x;
      v_det:=v_det||jsonb_build_object('scholarship_queues',jsonb_build_object('queues',(select jsonb_agg(e-'issue') from jsonb_array_elements(v_q) e)));
      v_ok:=array_append(v_ok,'scholarship_queues');
    exception when others then
      v_ok:=array_append(v_ok,'scholarship_queues');
      v_found:=v_found||security.platform_health_issue_v1('scholarship_queues:check_error','warning','scholarships','The scholarship queue check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('scholarship_queues',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.6 Layer 2 run items, Layer 3 work items, Layer 4 review backlog
  if security.platform_health_due_v1('layer_queues',p_force) then
    v_t:=clock_timestamp(); v_q:='[]'::jsonb;
    begin
      select count(*), min(coalesce(updated_at,created_at)) into v_n, v_ts from pipeline.layer2_run_items
       where status in ('queued','discovering','acquiring','extracting') and coalesce(updated_at,created_at)<now()-interval '2 hours';
      if v_n>0 then
        v_found:=v_found||security.platform_health_issue_v1('layer_queues:layer2_stuck','warning','Layer 3',
          v_n||' Layer 2 run item(s) have not moved for more than 2 hours',jsonb_build_object('stuck',v_n,'oldest_update',v_ts));
      end if;
      v_q:=v_q||jsonb_build_object('queue','layer2_run_items','stuck_over_2h',v_n);
      select count(*), min(coalesce(reserved_at,updated_at)), (array_agg(id order by coalesce(reserved_at,updated_at)))[1:5]::text
        into v_n, v_ts, v_txt from pipeline.layer3_work_items where status in ('reserved','interpreting') and coalesce(reserved_at,updated_at)<now()-interval '1 hour';
      if v_n>0 then
        v_found:=v_found||security.platform_health_issue_v1('layer_queues:layer3_stuck','warning','Layer 3',
          v_n||' Layer 3 work item(s) stuck in reserved/interpreting for more than an hour',jsonb_build_object('stuck',v_n,'since',v_ts,'ids',v_txt));
      end if;
      select max(completed_at) into v_ts from pipeline.layer3_work_items;
      v_x:=security.platform_health_stall_v1('layer_queues:layer3_dispatch','Layer 3','Layer 3 work dispatch','layer3-tuition-dispatch',v_ts,
        $q$select count(*) from pipeline.layer3_work_items w where w.status='pending' and coalesce(w.available_at,now())<=now()$q$);
      if v_x ? 'issue' then v_found:=v_found||jsonb_build_array(v_x->'issue'); end if;
      v_q:=v_q||(v_x-'issue')||jsonb_build_object('queue','layer3_stuck_over_1h','count',v_n);
      select count(*) filter (where status='pending'), count(*) filter (where created_at>=now()-interval '24 hours'),
             count(*) filter (where decided_at>=now()-interval '24 hours'), count(*) filter (where decided_at>=now()-interval '48 hours')
        into v_n, v_n2, v_n3, v_num from pipeline.layer4_review_items;
      if v_n2-v_n3>300 and v_num=0 then
        v_found:=v_found||security.platform_health_issue_v1('layer_queues:layer4_backlog','warning','Layer 3',
          'Layer 4 review backlog grew by '||(v_n2-v_n3)||' in 24 hours with no decisions in 48 hours ('||v_n||' waiting)',
          jsonb_build_object('pending',v_n,'created_24h',v_n2,'decided_24h',v_n3,'decided_48h',v_num));
      elsif v_n2-v_n3>100 then
        v_found:=v_found||security.platform_health_issue_v1('layer_queues:layer4_backlog','info','Layer 3',
          'Layer 4 review backlog grew by '||(v_n2-v_n3)||' in 24 hours ('||v_n||' waiting)',
          jsonb_build_object('pending',v_n,'created_24h',v_n2,'decided_24h',v_n3,'decided_48h',v_num));
      end if;
      v_q:=v_q||jsonb_build_object('queue','layer4_review','pending',v_n,'created_24h',v_n2,'decided_24h',v_n3);
      v_det:=v_det||jsonb_build_object('layer_queues',jsonb_build_object('queues',v_q));
      v_ok:=array_append(v_ok,'layer_queues');
    exception when others then
      v_ok:=array_append(v_ok,'layer_queues');
      v_found:=v_found||security.platform_health_issue_v1('layer_queues:check_error','warning','Layer 3','The Layer 2 to 4 queue check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('layer_queues',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.7 consumer API snapshot (slow, hourly)
  if (p_force or not v_slow_used) and security.platform_health_due_v1('consumer_snapshot',p_force) then
    v_t:=clock_timestamp(); v_slow_used:=true;
    begin
      v_x:=security.consumer_api_snapshot_v1();
      select coalesce(array_agg(e.k order by e.k),'{}'), max((e.v->>'ms')::numeric) into v_arr, v_num
        from jsonb_each(coalesce(v_x,'{}'::jsonb)) e(k,v) where jsonb_typeof(e.v)='object' and e.v ? 'ok' and (e.v->>'ok')::boolean is not true;
      select max((e.v->>'ms')::numeric) into v_num from jsonb_each(coalesce(v_x,'{}'::jsonb)) e(k,v) where jsonb_typeof(e.v)='object' and e.v ? 'ms';
      if v_x is null then
        v_found:=v_found||security.platform_health_issue_v1('consumer_snapshot:empty','critical','search/API','The consumer API snapshot returned nothing','{}'::jsonb);
      elsif cardinality(v_arr)>0 then
        v_found:=v_found||security.platform_health_issue_v1('consumer_snapshot:failing','critical','search/API',
          'Consumer API: '||cardinality(v_arr)||' probe(s) failing ('||array_to_string(v_arr[1:5],', ')||')',jsonb_build_object('failing',to_jsonb(v_arr)));
      end if;
      v_det:=v_det||jsonb_build_object('consumer_snapshot',jsonb_build_object('probes',(select count(*) from jsonb_each(coalesce(v_x,'{}'::jsonb)) e(k,v) where jsonb_typeof(e.v)='object' and e.v ? 'ok'),
        'failing',to_jsonb(v_arr),'slowest_probe_ms',v_num,'run_ms',round(extract(epoch from clock_timestamp()-v_t)*1000)));
      v_ok:=array_append(v_ok,'consumer_snapshot');
    exception when others then
      v_ok:=array_append(v_ok,'consumer_snapshot');
      v_found:=v_found||security.platform_health_issue_v1('consumer_snapshot:check_error','critical','search/API','The consumer API snapshot failed to run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('consumer_snapshot',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.8 admission: coverage-admit applied nothing in an hour while candidates exist (the plan is evaluated at most hourly)
  if security.platform_health_due_v1('admission',p_force) then
    v_t:=clock_timestamp();
    begin
      select max(captured_at) into v_ts from pipeline.consumer_api_baselines where label like 'after coverage admission batch%';
      select c.detail into v_prev from pipeline.platform_health_checks c where c.key='admission';
      if v_ts>=now()-interval '1 hour' then
        v_det:=v_det||jsonb_build_object('admission',jsonb_build_object('last_batch',v_ts,'plan_checked_at',v_prev->'plan_checked_at','candidates',v_prev->'candidates'));
        v_ok:=array_append(v_ok,'admission');
      elsif p_force or (not v_slow_used and coalesce((v_prev->>'plan_checked_at')::timestamptz,'-infinity'::timestamptz)<now()-interval '55 minutes') then
        v_slow_used:=true;
        -- follow the live defaults of coverage_admission_apply_v1 (what the coverage-admit job runs)
        v_args:=pg_get_function_arguments('security.coverage_admission_apply_v1'::regproc);
        v_txt:=substring(v_args from 'p_extractor text DEFAULT ''([^'']+)''');
        v_arr:=array(select m[1] from regexp_matches(coalesce(substring(v_args from 'p_attributes text\[\] DEFAULT ARRAY\[(.*)\]'),''),'''([^'']+)''','g') m);
        if cardinality(v_arr)=0 then v_arr:=array['official_url','english']; end if;
        execute 'select count(*) from security.coverage_admission_plan_v1($1) where action=''write'' and attribute=any($2)' into v_n using coalesce(v_txt,'coverage-sweep-v0.5.4'), v_arr;
        if v_n>0 then
          v_found:=v_found||security.platform_health_issue_v1('admission:stalled',
            case when v_ts is null or v_ts<now()-interval '3 hours' then 'critical' else 'warning' end,'admission',
            'Coverage admission has applied nothing for over an hour while '||v_n||' value(s) are ready to write',
            jsonb_build_object('candidates',v_n,'last_batch',v_ts,'extractor',v_txt,'attributes',to_jsonb(v_arr)));
        end if;
        v_det:=v_det||jsonb_build_object('admission',jsonb_build_object('last_batch',v_ts,'plan_checked_at',now(),'candidates',v_n,'extractor',v_txt));
        v_ok:=array_append(v_ok,'admission');
      end if;
    exception when others then
      v_ok:=array_append(v_ok,'admission');
      v_found:=v_found||security.platform_health_issue_v1('admission:check_error','warning','admission','The admission check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('admission',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.9 budgets
  if security.platform_health_due_v1('budgets',p_force) then
    v_t:=clock_timestamp();
    begin
      select security.layer2_provider_budget_status(p.id,1) into v_x from pipeline.layer2_acquisition_providers p where p.provider_key='firecrawl' and p.enabled;
      if v_x is null then
        v_found:=v_found||security.platform_health_issue_v1('budgets:firecrawl_disabled','warning','budgets','Firecrawl is not enabled: coverage site maps and scholarship searches cannot use it','{}'::jsonb);
      else
        v_num:=coalesce((v_x->>'remaining_units')::numeric,0)-coalesce((v_x->>'stop_at_remaining_units')::numeric,0);
        if (v_x->>'allowed')::boolean is false or v_num<=0 then
          v_found:=v_found||security.platform_health_issue_v1('budgets:firecrawl','critical','budgets',
            'Firecrawl has reached its reserve: paid page reads and site maps have stopped until '||to_char((v_x->>'period_end')::timestamptz,'DD Mon'),
            v_x-'provider_id');
        elsif v_num<0.1*coalesce((v_x->>'limit_units')::numeric,0) then
          v_found:=v_found||security.platform_health_issue_v1('budgets:firecrawl','warning','budgets',
            'Firecrawl is close to its reserve: '||v_num||' credits left above the reserve this period',v_x-'provider_id');
        end if;
      end if;
      -- scholarship work has its own 3,000-credit Firecrawl allowance (coverage-sweep SCH_FC_CAP)
      select coalesce(sum(units),0) into v_num2 from pipeline.coverage_vendor_usage where purpose in ('sch_map','sch_search','sch_scrape');
      if v_num2>=3000 then
        v_found:=v_found||security.platform_health_issue_v1('budgets:scholarship_firecrawl','warning','budgets',
          'Scholarship Firecrawl allowance is used up ('||v_num2||' of 3,000 credits): scholarship discovery falls back to direct reads only',jsonb_build_object('used',v_num2,'cap',3000));
      elsif v_num2>=2700 then
        v_found:=v_found||security.platform_health_issue_v1('budgets:scholarship_firecrawl','info','budgets',
          'Scholarship Firecrawl allowance is 90% used ('||v_num2||' of 3,000 credits)',jsonb_build_object('used',v_num2,'cap',3000));
      end if;
      -- OpenRouter: recorded spend over 24 hours against the US$5 daily ceiling (delivery plan v1.1)
      select coalesce((select sum(estimated_cost_usd) from pipeline.layer3_interpretations where created_at>=now()-interval '24 hours'),0)
           + coalesce((select sum(estimated_cost_usd) from pipeline.layer3_quality_benchmark_runs where created_at>=now()-interval '24 hours'),0)
           + coalesce((select sum(cost_usd) from pipeline.scholarship_ai_runs where created_at>=now()-interval '24 hours'),0) into v_num;
      if v_num>=14 then
        v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_daily','critical','budgets',
          'OpenRouter spend in the last 24 hours is US$'||round(v_num,2)||', at or over the US$14 combined daily ceiling',jsonb_build_object('spend_24h_usd',round(v_num,4),'ceiling_usd',14));
      elsif v_num>=11.2 then
        v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_daily','warning','budgets',
          'OpenRouter spend in the last 24 hours is US$'||round(v_num,2)||' (80% of the US$14 combined daily ceiling)',jsonb_build_object('spend_24h_usd',round(v_num,4),'ceiling_usd',14));
      end if;
      select count(*) into v_num from pipeline.layer3_interpretations i
       where i.created_at>=now()-interval '30 minutes' and i.validator_result::text ~ 'provider_(401|402|403|429)';
      if v_num>=5 then
        v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_refusing','critical','Layer 3',
          'OpenRouter is refusing Layer 3 calls ('||v_num||' in 30 minutes): '||coalesce((select left(i.validator_result->'errors'->>0,160)
             from pipeline.layer3_interpretations i where i.created_at>=now()-interval '30 minutes' and i.validator_result::text ~ 'provider_(401|402|403|429)' order by i.created_at desc limit 1),'see the Layer 3 work queue')||'. Check the OpenRouter key and billing.',
          jsonb_build_object('refusals_30m',v_num));
      end if;
      select o.remaining_usd into v_num from pipeline.layer3_openrouter_observations o where o.kind='credits' and o.remaining_usd is not null order by o.observed_at desc limit 1;
      if v_num is not null and v_num<=5 then
        v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_credit','critical','budgets',
          'OpenRouter credit is US$'||round(v_num,2)||': at the US$5 floor, so automated Layer 3 admission has stopped. Top up the credit.',jsonb_build_object('remaining_usd',round(v_num,2),'floor_usd',5));
      elsif v_num is not null and v_num<10 then
        v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_credit','warning','budgets',
          'OpenRouter credit is US$'||round(v_num,2)||': automated Layer 3 admission stops at US$5. Top up soon.',jsonb_build_object('remaining_usd',round(v_num,2),'floor_usd',5));
      end if;
      for r in select p.code, count(*) n, max(i.estimated_cost_usd) mx, p.cost_ceiling_usd ceil
                 from pipeline.layer3_interpretations i join pipeline.layer3_model_profiles p on p.id=i.profile_id
                where i.created_at>=now()-interval '24 hours' and coalesce(i.external_call_count,0)>0 and p.cost_ceiling_usd is not null and i.estimated_cost_usd>p.cost_ceiling_usd
                group by p.code, p.cost_ceiling_usd loop
        v_found:=v_found||security.platform_health_issue_v1('budgets:call_ceiling:'||r.code,'warning','budgets',
          r.n||' Layer 3 call(s) on "'||r.code||'" cost more than its US$'||r.ceil||' per-call ceiling in 24 hours',jsonb_build_object('profile',r.code,'calls',r.n,'max_cost_usd',r.mx,'ceiling_usd',r.ceil));
      end loop;
      for r in select p.code, count(*) n, max(b.estimated_cost_usd) mx, p.cost_ceiling_usd ceil
                 from pipeline.layer3_quality_benchmark_runs b join pipeline.layer3_model_profiles p on p.id=b.profile_id
                where b.created_at>=now()-interval '24 hours' and p.cost_ceiling_usd is not null and b.estimated_cost_usd>p.cost_ceiling_usd*greatest(coalesce(b.external_call_count,1),1)
                group by p.code, p.cost_ceiling_usd loop
        v_found:=v_found||security.platform_health_issue_v1('budgets:benchmark_ceiling:'||r.code,'warning','budgets',
          r.n||' benchmark run(s) on "'||r.code||'" cost more than the per-call ceiling allows in 24 hours',jsonb_build_object('profile',r.code,'runs',r.n,'max_cost_usd',r.mx,'ceiling_usd_per_call',r.ceil));
      end loop;
      for r in select s.country_code, s.daily_budget_usd, coalesce(sum(x.cost_usd),0) spent from pipeline.scholarship_ai_settings s
                 left join pipeline.scholarship_ai_runs x on x.country_code=s.country_code and x.created_at>=now()-interval '24 hours'
                group by s.country_code, s.daily_budget_usd having coalesce(sum(x.cost_usd),0)>s.daily_budget_usd loop
        v_found:=v_found||security.platform_health_issue_v1('budgets:scholarship_ai:'||r.country_code,'warning','budgets',
          'Scholarship AI spend for '||r.country_code||' is US$'||round(r.spent,2)||' in 24 hours, over its US$'||r.daily_budget_usd||' daily budget',jsonb_build_object('spent_usd',r.spent,'budget_usd',r.daily_budget_usd));
      end loop;
      v_det:=v_det||jsonb_build_object('budgets',jsonb_build_object(
        'firecrawl',case when v_x is null then null else jsonb_build_object('used',v_x->'used_units','limit',v_x->'limit_units','remaining',v_x->'remaining_units','reserve',v_x->'stop_at_remaining_units','period_end',v_x->'period_end') end,
        'scholarship_firecrawl_used',v_num2,'scholarship_firecrawl_cap',3000,'openrouter_spend_24h_usd',round(v_num,4),'openrouter_daily_ceiling_usd',5));
      v_ok:=array_append(v_ok,'budgets');
    exception when others then
      v_ok:=array_append(v_ok,'budgets');
      v_found:=v_found||security.platform_health_issue_v1('budgets:check_error','warning','budgets','The budget check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('budgets',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.10 database size and connections
  if security.platform_health_due_v1('db_capacity',p_force) then
    v_t:=clock_timestamp();
    begin
      v_n:=pg_database_size(current_database());
      select p.database_warn_bytes, p.database_high_bytes, p.database_critical_bytes into v_n2, v_n3, v_num
        from pipeline.platform_capacity_policy p order by (p.environment='production') desc, (p.environment='pilot') desc limit 1;
      if v_num is not null and v_n>=v_num then
        v_found:=v_found||security.platform_health_issue_v1('db_capacity:size','critical','storage/DB','Database is '||pg_size_pretty(v_n)||', over the critical level of '||pg_size_pretty(v_num::bigint),jsonb_build_object('bytes',v_n,'warn',v_n2,'high',v_n3,'critical',v_num));
      elsif v_n3 is not null and v_n>=v_n3 then
        v_found:=v_found||security.platform_health_issue_v1('db_capacity:size','warning','storage/DB','Database is '||pg_size_pretty(v_n)||', over the high level of '||pg_size_pretty(v_n3),jsonb_build_object('bytes',v_n,'warn',v_n2,'high',v_n3,'critical',v_num));
      elsif v_n2 is not null and v_n>=v_n2 then
        v_found:=v_found||security.platform_health_issue_v1('db_capacity:size','info','storage/DB','Database is '||pg_size_pretty(v_n)||', over the watch level of '||pg_size_pretty(v_n2),jsonb_build_object('bytes',v_n,'warn',v_n2,'high',v_n3,'critical',v_num));
      end if;
      select count(*), count(*) filter (where state='active') into v_n2, v_n3 from pg_stat_activity where backend_type='client backend';
      select coalesce(max_connections, current_setting('max_connections')::int) into v_num2 from pipeline.platform_compute_profile where id=1;
      v_num2:=coalesce(v_num2, current_setting('max_connections')::numeric);
      if v_n2>=0.9*v_num2 then
        v_found:=v_found||security.platform_health_issue_v1('db_capacity:connections','critical','storage/DB',v_n2||' of '||v_num2||' database connections in use',jsonb_build_object('connections',v_n2,'active',v_n3,'max',v_num2));
      elsif v_n2>=0.75*v_num2 then
        v_found:=v_found||security.platform_health_issue_v1('db_capacity:connections','warning','storage/DB',v_n2||' of '||v_num2||' database connections in use',jsonb_build_object('connections',v_n2,'active',v_n3,'max',v_num2));
      end if;
      v_det:=v_det||jsonb_build_object('db_capacity',jsonb_build_object('db_bytes',v_n,'db_size',pg_size_pretty(v_n),'connections',v_n2,'active_connections',v_n3,'max_connections',v_num2,
        'compute_size',(select compute_size from pipeline.platform_compute_profile where id=1)));
      v_ok:=array_append(v_ok,'db_capacity');
    exception when others then
      v_ok:=array_append(v_ok,'db_capacity');
      v_found:=v_found||security.platform_health_issue_v1('db_capacity:check_error','warning','storage/DB','The database capacity check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('db_capacity',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.11 search probe
  if security.platform_health_due_v1('search_probe',p_force) and (p_force or not ('consumer_snapshot'=any(v_ok))) then
    v_t:=clock_timestamp();
    begin
      v_x:=public.website_edge_course_search_v1('{}'::jsonb,1,5);
      v_num:=round(extract(epoch from clock_timestamp()-v_t)*1000);
      if v_x is null or not (v_x ? 'items') then
        v_found:=v_found||security.platform_health_issue_v1('search_probe:bad_response','critical','search/API','Course search returned an unexpected response',jsonb_build_object('ms',v_num,'keys',(select jsonb_agg(k) from jsonb_object_keys(coalesce(v_x,'{}'::jsonb)) k)));
      elsif v_num>3000 then
        v_found:=v_found||security.platform_health_issue_v1('search_probe:slow','warning','search/API','Course search took '||v_num||' ms (limit 3,000 ms)',jsonb_build_object('ms',v_num));
      end if;
      v_det:=v_det||jsonb_build_object('search_probe',jsonb_build_object('ms',v_num,'items',jsonb_array_length(coalesce(v_x->'items','[]'::jsonb))));
      v_ok:=array_append(v_ok,'search_probe');
    exception when others then
      v_ok:=array_append(v_ok,'search_probe');
      v_found:=v_found||security.platform_health_issue_v1('search_probe:check_error','critical','search/API','Course search failed',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('search_probe',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.12 reference bundle cache
  if security.platform_health_due_v1('reference_bundle',p_force) then
    v_t:=clock_timestamp();
    begin
      select max(built_at) into v_ts from pipeline.consumer_reference_bundle_cache;
      if v_ts is null or v_ts<now()-interval '6 hours' then
        v_found:=v_found||security.platform_health_issue_v1('reference_bundle:stale','critical','search/API',
          'Consumer reference bundle has not been rebuilt '||case when v_ts is null then 'at all' else 'since '||to_char(v_ts at time zone 'UTC','DD Mon HH24:MI')||' UTC' end,jsonb_build_object('built_at',v_ts));
      elsif v_ts<now()-interval '2 hours' then
        v_found:=v_found||security.platform_health_issue_v1('reference_bundle:stale','warning','search/API',
          'Consumer reference bundle is '||round(extract(epoch from now()-v_ts)/3600.0,1)||' hours old (rebuilt hourly)',jsonb_build_object('built_at',v_ts));
      end if;
      v_det:=v_det||jsonb_build_object('reference_bundle',jsonb_build_object('built_at',v_ts));
      v_ok:=array_append(v_ok,'reference_bundle');
    exception when others then
      v_ok:=array_append(v_ok,'reference_bundle');
      v_found:=v_found||security.platform_health_issue_v1('reference_bundle:check_error','warning','search/API','The reference bundle check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('reference_bundle',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.13 nightly scholarship publication review
  if security.platform_health_due_v1('scholarship_review',p_force) then
    v_t:=clock_timestamp();
    begin
      select j.jobid, j.active, j.schedule into r from cron.job j where j.jobname='scholarship-publication-review';
      if r.jobid is null or not r.active then
        v_found:=v_found||security.platform_health_issue_v1('scholarship_review:missing','warning','scholarships','The nightly scholarship publication review is not scheduled','{}'::jsonb);
        v_det:=v_det||jsonb_build_object('scholarship_review',jsonb_build_object('scheduled',false));
      else
        select max(d.start_time) filter (where d.status='succeeded'), max(d.start_time) into v_ts, v_ts2 from cron.job_run_details d where d.jobid=r.jobid;
        select d.status, left(d.return_message,200) into v_txt, v_args from cron.job_run_details d where d.jobid=r.jobid order by d.start_time desc limit 1;
        if v_txt='failed' then
          v_found:=v_found||security.platform_health_issue_v1('scholarship_review:failed','warning','scholarships','The last nightly scholarship publication review failed',jsonb_build_object('at',v_ts2,'error',v_args));
        end if;
        v_ts2:=coalesce(v_ts,(select min(d.start_time) from cron.job_run_details d where d.jobid>r.jobid));
        if v_ts2 is not null and v_ts2<now()-interval '26 hours' then
          v_found:=v_found||security.platform_health_issue_v1('scholarship_review:not_run','warning','scholarships',
            'The nightly scholarship publication review has not completed '||case when v_ts is null then 'since it was scheduled' else 'since '||to_char(v_ts at time zone 'UTC','DD Mon HH24:MI')||' UTC' end,
            jsonb_build_object('last_success',v_ts,'schedule',r.schedule));
        end if;
        v_det:=v_det||jsonb_build_object('scholarship_review',jsonb_build_object('scheduled',true,'schedule',r.schedule,'last_success',v_ts,'last_status',v_txt));
      end if;
      v_ok:=array_append(v_ok,'scholarship_review');
    exception when others then
      v_ok:=array_append(v_ok,'scholarship_review');
      v_found:=v_found||security.platform_health_issue_v1('scholarship_review:check_error','warning','scholarships','The scholarship review check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('scholarship_review',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 5. record issues (dedup on check_key), auto-resolve what cleared, store check status
  for r in select distinct on (x.check_key) x.check_key, x.severity, x.area, x.title, x.detail
             from jsonb_to_recordset(v_found) x(check_key text, severity text, area text, title text, detail jsonb)
            order by x.check_key, case x.severity when 'critical' then 1 when 'warning' then 2 else 3 end loop
    insert into pipeline.platform_issues as i (check_key,severity,area,title,detail)
    values (r.check_key, r.severity, r.area, left(r.title,300), coalesce(r.detail,'{}'::jsonb))
    on conflict (check_key) where resolved_at is null do update set
      severity=excluded.severity, area=excluded.area, title=excluded.title, detail=excluded.detail,
      last_seen=now(), occurrences=i.occurrences+1,
      acknowledged_at=case when (case excluded.severity when 'critical' then 1 when 'warning' then 2 else 3 end) < (case i.severity when 'critical' then 1 when 'warning' then 2 else 3 end) then null else i.acknowledged_at end,
      acknowledged_by=case when (case excluded.severity when 'critical' then 1 when 'warning' then 2 else 3 end) < (case i.severity when 'critical' then 1 when 'warning' then 2 else 3 end) then null else i.acknowledged_by end,
      acknowledged_note=case when (case excluded.severity when 'critical' then 1 when 'warning' then 2 else 3 end) < (case i.severity when 'critical' then 1 when 'warning' then 2 else 3 end) then null else i.acknowledged_note end;
  end loop;

  update pipeline.platform_issues i set resolved_at=now()
   where i.resolved_at is null and split_part(i.check_key,':',1)=any(v_ok)
     and not exists (select 1 from jsonb_array_elements(v_found) f where f->>'check_key'=i.check_key);

  update pipeline.platform_health_checks c set
    status=case when c.key='edge_deployed' then 'skipped'
                else coalesce((select case min(case f->>'severity' when 'critical' then 1 when 'warning' then 2 else 3 end) when 1 then 'critical' when 2 then 'warning' else 'ok' end
                                 from jsonb_array_elements(v_found) f where split_part(f->>'check_key',':',1)=c.key),'ok') end,
    detail=coalesce(v_det->c.key, c.detail), checked_at=now(), duration_ms=(v_ms->>c.key)::numeric::int
   where c.key=any(v_ok);

  delete from pipeline.platform_edge_calls where created_at<now()-interval '2 days';
  delete from pipeline.platform_health_runs where started_at<now()-interval '14 days';
  delete from pipeline.platform_issues where resolved_at<now()-interval '90 days';

  select jsonb_build_object('critical',count(*) filter (where severity='critical'),'warning',count(*) filter (where severity='warning'),'info',count(*) filter (where severity='info'))
    into v_counts from pipeline.platform_issues where resolved_at is null;
  insert into pipeline.platform_health_runs(started_at,duration_ms,checks_ran,check_ms,counts)
  values (v_t0, round(extract(epoch from clock_timestamp()-v_t0)*1000), v_ok, v_ms, v_counts);
  return jsonb_build_object('ran',to_jsonb(v_ok),'duration_ms',round(extract(epoch from clock_timestamp()-v_t0)*1000),'check_ms',v_ms,'open',v_counts,'found',jsonb_array_length(v_found));
end $function$
