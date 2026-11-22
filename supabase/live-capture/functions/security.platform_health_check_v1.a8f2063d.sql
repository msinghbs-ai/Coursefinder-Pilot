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
  v_counts jsonb; v_jobs int:=0; v_fail int:=0; v_stale int:=0; v_spend numeric;
begin
  -- 4.1 scheduled jobs: failures in the last hour; active jobs not run in more than 3x their interval
  if security.platform_health_due_v1('cron',p_force) then
    v_t:=clock_timestamp();
    begin
      for r in
        with agg as (
          select d.jobid, max(d.start_time) last_run, min(d.start_time) first_run,
                 count(*) filter (where d.status='failed' and d.start_time>=now()-interval '1 hour') fails_1h,  -- fixed: health check observation window
                 count(*) filter (where d.start_time>=now()-interval '1 hour') runs_1h,  -- fixed: health check observation window
                 -- SS-014 (31 Oct 2026): a failure stays visible until the job runs cleanly again, and repeats are counted over a set window
                 count(*) filter (where d.status='failed' and d.start_time>=now()-make_interval(hours=>security.pipeline_num_v1('health.job_failure_window_hours', 24)::int)) fails_win,
                 (array_agg(d.status order by d.start_time desc))[1] last_status,
                 (array_agg(left(d.return_message,200) order by d.start_time desc) filter (where d.status='failed'))[1] last_error
            from (select d0.jobid, d0.start_time, d0.return_message, case when d0.status='failed' and d0.return_message='job canceled' then security.cron_run_outcome_v1(j0.jobname, d0.status, d0.return_message, d0.start_time) else d0.status end status  -- SS-004 (1 Nov 2026): classified only when cancelled (keeps the section at its former run time)
                  from cron.job_run_details d0 join cron.job j0 on j0.jobid=d0.jobid) d group by d.jobid)  -- SS-004 (1 Nov 2026): a run cancelled by the flag unit's idle pause is paused, not failed
        select j.jobid, j.jobname, j.schedule, security.platform_cron_interval_seconds(j.schedule) ival,
               a.last_run, coalesce(a.fails_1h,0) fails_1h, coalesce(a.runs_1h,0) runs_1h, a.last_error, coalesce(a.fails_win,0) fails_win, a.last_status,
               (select min(a2.first_run) from agg a2 where a2.jobid>j.jobid) created_before
          from cron.job j left join agg a on a.jobid=j.jobid where j.active
      loop
        v_jobs:=v_jobs+1;
        if r.fails_1h>0 or r.last_status='failed' or r.fails_win>=security.pipeline_num_v1('health.job_failure_repeat_count', 3) then
          v_fail:=v_fail+1;
          select bool_and(x.status='failed') into v_bool from (select case when d.status='failed' and d.return_message='job canceled' then security.cron_run_outcome_v1(r.jobname, d.status, d.return_message, d.start_time) else d.status end status from cron.job_run_details d where d.jobid=r.jobid order by d.start_time desc limit security.pipeline_num_v1('health.job_failure_critical_consecutive', 3)::int) x;
          v_found:=v_found||security.platform_health_issue_v1('cron:failed:'||r.jobname, case when v_bool then 'critical' else 'warning' end,
            'scheduled jobs', 'Scheduled job "'||r.jobname||'" failed '||r.fails_1h||' of '||r.runs_1h||' run(s) in the last hour'||case when r.fails_win>r.fails_1h then '; '||r.fails_win||' failure(s) in the last '||security.pipeline_num_v1('health.job_failure_window_hours', 24)::int||' hours' else '' end||case when r.last_status='failed' then '; the last run failed' else '' end,
            jsonb_build_object('job',r.jobname,'schedule',r.schedule,'failures_1h',r.fails_1h,'runs_1h',r.runs_1h,'last_error',r.last_error,'last_three_failed',coalesce(v_bool,false),'failures_window',r.fails_win,'last_status',r.last_status));
        end if;
        -- 16 Oct 2026: a job the flag unit switched on again (trial run) counts from that moment, not from its last run before the pause
        v_ts:=greatest(coalesce(r.last_run, r.created_before), (select max(f.released_at) from pipeline.enrichment_flags f where f.entity='job' and f.entity_key=r.jobname and f.field=''));
        if r.ival is not null and v_ts is not null and now()-v_ts > make_interval(secs=>3*r.ival) + interval '2 minutes' then
          v_stale:=v_stale+1;
          v_found:=v_found||security.platform_health_issue_v1('cron:stale:'||r.jobname,
            case when now()-v_ts > greatest(make_interval(secs=>12*r.ival), interval '2 hours') and r.ival<=3600 then 'critical' else 'warning' end,  -- fixed: health check observation window
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
        'invoked_last_24h',coalesce((select jsonb_agg(distinct function_name order by function_name) from pipeline.platform_edge_calls where created_at>=now()-interval '24 hours'),'[]'::jsonb)));  -- fixed: health check observation window
      v_ok:=array_append(v_ok,'edge_deployed');
    exception when others then null;
    end;
    v_ms:=v_ms||jsonb_build_object('edge_deployed',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.4 coverage sweep queues
  if security.platform_health_due_v1('coverage_queues',p_force) then
    v_t:=clock_timestamp(); v_q:='[]'::jsonb;
    begin
      -- SS-004 (1 Nov 2026): waiting is measured from the later of the last read and the moment the oldest waiting page became due, so a page that
      -- has only just become due after a quiet spell is not reported as hours of stall; a page left waiting still ages and goes critical
      -- SS-014 P2 (2 Nov 2026): waiting means what the reader takes (security.coverage_read_eligible_v1: hidden providers and leased pages left out)
      select greatest(max(read_at), (select min(e.due_at) from security.coverage_read_eligible_v1() e)) into v_ts from pipeline.coverage_course_pages;
      v_q:=v_q||security.platform_health_stall_v1('coverage_queues:read','coverage sweep','Coverage page reading','coverage-read',v_ts,
        $q$select count(*) from security.coverage_read_eligible_v1()$q$);  -- SS-014 P2 (2 Nov 2026): the same pages the reader takes
      select greatest(max(updated_at), (select min(coalesce(q.next_due_at, q.updated_at)) from pipeline.coverage_provider_discovery q
                                         where (q.status='pending' or (q.status in ('mapped','failed') and q.next_due_at<=now())) and q.attempts<3
                                           and security.enrich_focus_v1(q.provider_id) and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id=q.provider_id))) into v_ts from pipeline.coverage_provider_discovery;  -- SS-004 (1 Nov 2026): as above
      v_q:=v_q||security.platform_health_stall_v1('coverage_queues:discover','coverage sweep','Coverage provider discovery','coverage-discover',v_ts,
        $q$select count(*) from pipeline.coverage_provider_discovery d where (d.status='pending' or (d.status in ('mapped','failed') and d.next_due_at<=now())) and d.attempts<3 and security.enrich_focus_v1(d.provider_id) and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id=d.provider_id)$q$);
      -- re-extract has no timestamp: progress means the number of pages on an older extractor went down
      select c.candidates->>'extractor' into v_txt from pipeline.coverage_course_pages c where c.read_status='read' and c.read_at is not null order by c.read_at desc limit 1;
      select count(*) into v_n from pipeline.coverage_course_pages cp
       where cp.read_status='read' and cp.identity_basis is not null and cp.evidence_id is not null and coalesce(cp.candidates->>'extractor','')<>coalesce(v_txt,'');
      select c.detail->'reextract' into v_prev from pipeline.platform_health_checks c where c.key='coverage_queues';
      v_ts:=case when v_n=0 or v_n<coalesce((v_prev->>'pending')::bigint, v_n+1) then now() else coalesce((v_prev->>'progress_at')::timestamptz, now()) end;
      v_q:=v_q||(security.platform_health_stall_v1('coverage_queues:reextract','coverage sweep','Coverage re-extraction','coverage-reextract',v_ts,'select '||v_n)
                 ||jsonb_build_object('pending',v_n,'progress_at',v_ts,'extractor',v_txt));
      -- 16 Oct 2026: the tuition hand-off to Layer 3 is retired (Layer 3 retired for tuition on 12 Oct 2026; university adapters admit fees)
      v_q:=v_q||jsonb_build_object('queue','coverage_queues:tuition_handoff','status','retired','note','Layer 3 was retired for tuition on 12 Oct 2026; fees are admitted by university adapters');
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
            where p.next_read_at<=now() and p.attempts<5 and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id=s.provider_id)
              and (p.requested_at is not null or not security.fc_sch_held_v1(s.provider_id, false))$q$);  -- 16 Oct 2026: only pages a reader can take
      -- SS-014A (31 Oct 2026): whether each provider is held by the scholarship Firecrawl rules is worked out once and shared by the candidate,
      -- discovery and held counts (it was worked out up to three times per provider, about 10 s a run); same rules, same counts
      with dp as materialized (select d.provider_id, d.website from pipeline.scholarship_discovery_providers d where d.status='pending' and d.attempts<3),
           cand as materialized (select c.provider_id, c.url from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
                                  where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and c.attempts<3),
           hp as materialized (select x.provider_id, security.fc_sch_held_v1(x.provider_id, true) held from (select dp.provider_id from dp union select cand.provider_id from cand) x)
      select (select count(*) from cand join hp on hp.provider_id=cand.provider_id where not hp.held and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id=cand.provider_id)
                and not security.third_party_host_v1(cand.url) and not security.provider_sch_search_off_v1(cand.provider_id)),
             (select count(*) from dp join hp on hp.provider_id=dp.provider_id where not hp.held and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id=dp.provider_id)
                and not security.third_party_host_v1(coalesce(dp.website, '')) and not security.provider_sch_search_off_v1(dp.provider_id)),
             (select count(*) from dp join hp on hp.provider_id=dp.provider_id where hp.held)
        into v_n, v_n2, v_n3;
      select max(read_at) into v_ts from pipeline.scholarship_page_candidates;
      v_q:=v_q||security.platform_health_stall_v1('scholarship_queues:candidates','scholarships','Scholarship candidate page reading','scholarship-discover',v_ts,'select '||v_n);  -- 16 Oct 2026: only pages a reader can take
      select max(updated_at) into v_ts from pipeline.scholarship_discovery_providers;
      v_q:=v_q||security.platform_health_stall_v1('scholarship_queues:discover','scholarships','Scholarship provider discovery','scholarship-discover',v_ts,'select '||v_n2);  -- 16 Oct 2026: only providers discovery can take
      -- 16 Oct 2026: work held by the per-university cap, by policy (small Australian providers) or by settings, shown apart from stalls
      v_q:=v_q||jsonb_build_object('queue','scholarship_queues:held','status','held',
        'pages_held_by_cap',(select count(*) from pipeline.scholarship_pages p join scholarship.scholarships s on s.id=p.scholarship_id and s.lifecycle_status='active'
            where p.next_read_at<=now() and p.attempts<5 and p.requested_at is null and security.fc_sch_held_v1(s.provider_id, false)),
        'providers_not_searched',v_n3,
        'note','Held by the per-university Firecrawl cap or by the rule that small Australian providers are not searched; not a stall');
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
       where status in ('queued','discovering','acquiring','extracting') and coalesce(updated_at,created_at)<now()-interval '2 hours';  -- fixed: health check observation window
      if v_n>0 then
        v_found:=v_found||security.platform_health_issue_v1('layer_queues:layer2_stuck','warning','Layer 3',
          v_n||' Layer 2 run item(s) have not moved for more than 2 hours',jsonb_build_object('stuck',v_n,'oldest_update',v_ts));
      end if;
      v_q:=v_q||jsonb_build_object('queue','layer2_run_items','stuck_over_2h',v_n);
      select count(*), min(coalesce(reserved_at,updated_at)), (array_agg(id order by coalesce(reserved_at,updated_at)))[1:5]::text
        into v_n, v_ts, v_txt from pipeline.layer3_work_items where status in ('reserved','interpreting') and coalesce(reserved_at,updated_at)<now()-interval '1 hour';  -- fixed: health check observation window
      if v_n>0 then
        v_found:=v_found||security.platform_health_issue_v1('layer_queues:layer3_stuck','warning','Layer 3',
          v_n||' Layer 3 work item(s) stuck in reserved/interpreting for more than an hour',jsonb_build_object('stuck',v_n,'since',v_ts,'ids',v_txt));
      end if;
      select max(completed_at) into v_ts from pipeline.layer3_work_items;
      v_x:=security.platform_health_stall_v1('layer_queues:layer3_dispatch','Layer 3','Layer 3 work dispatch','layer3-tuition-dispatch',v_ts,
        $q$select count(*) from pipeline.layer3_work_items w where w.status='pending' and coalesce(w.available_at,now())<=now()$q$);
      if v_x ? 'issue' then v_found:=v_found||jsonb_build_array(v_x->'issue'); end if;
      v_q:=v_q||(v_x-'issue')||jsonb_build_object('queue','layer3_stuck_over_1h','count',v_n);
      select count(*) filter (where status='pending'), count(*) filter (where created_at>=now()-interval '24 hours'),  -- fixed: health check observation window
             count(*) filter (where decided_at>=now()-interval '24 hours'), count(*) filter (where decided_at>=now()-interval '48 hours')  -- fixed: health check observation window
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
      if v_ts>=now()-interval '1 hour' then  -- fixed: health check observation window
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
            case when v_ts is null or v_ts<now()-interval '3 hours' then 'critical' else 'warning' end,'admission',  -- fixed: health check observation window
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
      -- 16 Oct 2026: scholarship work has its own Firecrawl allowance, read from its setting (Scholarships settings firecrawl_cap; was written here as 3,000)
      select coalesce(sum(units),0) into v_num2 from pipeline.coverage_vendor_usage where purpose in ('sch_map','sch_search','sch_scrape');
      v_n3:=coalesce((select s.value from pipeline.scholarship_layer_settings s where s.key='firecrawl_cap'),0);
      if v_n3>0 and v_num2>=v_n3 then
        v_found:=v_found||security.platform_health_issue_v1('budgets:scholarship_firecrawl','warning','budgets',
          'Scholarship Firecrawl allowance is used up ('||v_num2||' of '||v_n3||' credits): scholarship pages are not read until it is raised',jsonb_build_object('used',v_num2,'cap',v_n3));
      elsif v_n3>0 and v_num2>=0.9*v_n3 then  -- fixed: 90% notice
        v_found:=v_found||security.platform_health_issue_v1('budgets:scholarship_firecrawl','info','budgets',
          'Scholarship Firecrawl allowance is 90% used ('||v_num2||' of '||v_n3||' credits)',jsonb_build_object('used',v_num2,'cap',v_n3));
      end if;
      -- OpenRouter: recorded spend over 24 hours against the US$5 daily ceiling (delivery plan v1.1)
      -- SS-014 (31 Oct 2026): all OpenRouter spend (enrichment, AI match, entry reads, Layer 3), measured from the credit balance; top-ups are not counted
      select coalesce((select sum(greatest(o.prev - o.remaining_usd, 0)) from (select x.remaining_usd, lag(x.remaining_usd) over (order by x.observed_at) prev
                         from pipeline.layer3_openrouter_observations x where x.kind = 'credits' and x.remaining_usd is not null and x.observed_at>=now()-interval '24 hours') o),0)  -- fixed: health check observation window
           into v_num; v_spend:=round(v_num,4);  -- CF-247 20 Oct 2026 (D11): retired benchmark and scholarship AI run tables no longer counted
      if v_num>=security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14) then
        v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_daily','critical','budgets',
          'OpenRouter spend in the last 24 hours is US$'||round(v_num,2)||', at or over the US$'||security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14)||' combined daily ceiling',jsonb_build_object('spend_24h_usd',round(v_num,4),'ceiling_usd',security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14)));
      elsif v_num>=0.8*security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14) then  -- fixed: notice at 80% of the ceiling
        v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_daily','warning','budgets',
          'OpenRouter spend in the last 24 hours is US$'||round(v_num,2)||' (80% of the US$'||security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14)||' combined daily ceiling)',jsonb_build_object('spend_24h_usd',round(v_num,4),'ceiling_usd',security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14)));
      end if;
      -- CF-247 worker v1.0.3 (15 Nov 2026): the OpenRouter key's own limit (job openrouter-balance reads it; a refusal records it at once)
      declare k jsonb := security.openrouter_key_room_v1();
      begin
        if coalesce((k->>'held')::boolean, false) then
          v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_key','critical','budgets',
            'The OpenRouter key has no room: about US$'||round((k->>'estimated_usd')::numeric,2)||' left of its '||coalesce(k->>'limit_reset','total')||' limit of US$'||coalesce(k->>'limit_usd','?')
            ||'. All AI work is held until the limit resets or is raised on OpenRouter',k);
        elsif (k->>'period_ceiling_usd') is not null and (k->>'limit_usd') is not null and (k->>'limit_usd')::numeric < (k->>'period_ceiling_usd')::numeric then
          v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_key','warning','budgets',
            'The OpenRouter key''s '||(k->>'limit_reset')||' limit of US$'||(k->>'limit_usd')||' is below the daily ceiling over that period (US$'||(k->>'ceiling_usd')||' x '||(k->>'period_days')
            ||' days = US$'||(k->>'period_ceiling_usd')||'): the key will stop AI work before the ceiling does',k);
        elsif not coalesce((k->>'reading')::boolean, false) then
          v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_key','warning','budgets',
            'The OpenRouter key''s limit has not been read in the last '||(k->>'max_age_minutes')||' minutes (job openrouter-balance): a key limit would not be seen before it refuses',k);
        end if;
      end;
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
                where i.created_at>=now()-interval '24 hours' and coalesce(i.external_call_count,0)>0 and p.cost_ceiling_usd is not null and i.estimated_cost_usd>p.cost_ceiling_usd  -- fixed: health check observation window
                group by p.code, p.cost_ceiling_usd loop
        v_found:=v_found||security.platform_health_issue_v1('budgets:call_ceiling:'||r.code,'warning','budgets',
          r.n||' Layer 3 call(s) on "'||r.code||'" cost more than its US$'||r.ceil||' per-call ceiling in 24 hours',jsonb_build_object('profile',r.code,'calls',r.n,'max_cost_usd',r.mx,'ceiling_usd',r.ceil));
      end loop;
      v_det:=v_det||jsonb_build_object('budgets',jsonb_build_object(
        'firecrawl',case when v_x is null then null else jsonb_build_object('used',v_x->'used_units','limit',v_x->'limit_units','remaining',v_x->'remaining_units','reserve',v_x->'stop_at_remaining_units','period_end',v_x->'period_end') end,
        'scholarship_firecrawl_used',v_num2,'scholarship_firecrawl_cap',v_n3,'openrouter_credit_remaining_usd',round(v_num,4),'openrouter_spend_24h_usd',v_spend,'ai_daily_ceiling_usd',security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14)));
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
      v_num2:=current_setting('max_connections')::numeric;  -- 16 Oct 2026: the live limit (the profile said 60 after the move to Medium)
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
      if v_ts is null or v_ts<now()-interval '6 hours' then  -- fixed: health check observation window
        v_found:=v_found||security.platform_health_issue_v1('reference_bundle:stale','critical','search/API',
          'Consumer reference bundle has not been rebuilt '||case when v_ts is null then 'at all' else 'since '||to_char(v_ts at time zone 'UTC','DD Mon HH24:MI')||' UTC' end,jsonb_build_object('built_at',v_ts));
      elsif v_ts<now()-interval '2 hours' then  -- fixed: health check observation window
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
        if v_ts2 is not null and v_ts2<now()-interval '26 hours' then  -- fixed: health check observation window
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

  -- CF-247 21 Oct 2026: fields below target that are not moving, by country; fields with no reader; the standing queue not running
  if security.platform_health_due_v1('field_stalled',p_force) then
    v_t:=clock_timestamp();
    begin
      perform security.field_coverage_record_v1();
      v_x:=security.field_stalled_v1();
      for r in select x->>'country' cc, count(*) filter (where x->>'reason'='flat') flat, count(*) filter (where x->>'reason'='behind') behind,
                      string_agg(case when x->>'reason' in ('flat','behind') then (x->>'label')||' '||(x->>'pct')||'%' end, ', ' order by (x->>'reason'), (x->>'label')) fields,
                      jsonb_agg(jsonb_build_object('field',x->>'field','pct',x->'pct','target',x->'target','moved',x->'moved','reason',x->>'reason','cause',x->>'cause') order by x->>'field') filter (where x->>'reason' in ('flat','behind')) det
                 from jsonb_array_elements(v_x) x group by 1 loop
        if r.flat+r.behind>0 then
          v_found:=v_found||security.platform_health_issue_v1('field_stalled:'||r.cc, case when r.flat>0 then 'warning' else 'info' end, 'coverage sweep',
            coalesce((select k.name from ref.countries k where k.iso_alpha2=r.cc limit 1), r.cc)||': '||(r.flat+r.behind)||' field(s) below target and '||
            case when r.flat>0 then 'not moving' else 'behind other countries' end||' ('||r.fields||')',
            jsonb_build_object('country',r.cc,'flat',r.flat,'behind',r.behind,'fields',r.det,'resolve','Coverage › Attributes › Stalled fields'));
        end if;
      end loop;
      select string_agg(distinct x->>'label', ', ') into v_txt from jsonb_array_elements(v_x) x where x->>'reason'='no_reader';
      if v_txt is not null then
        v_found:=v_found||security.platform_health_issue_v1('field_stalled:no_reader','info','coverage sweep','Fields with a target but no reader yet: '||v_txt,
          jsonb_build_object('fields',v_txt,'resolve','Build a reader, or set the target to 0 on Coverage › Attributes'));
      end if;
      if (select enabled from pipeline.field_gap_queue_control where id=1) then
        select max(d.start_time) into v_ts from cron.job_run_details d join cron.job j on j.jobid=d.jobid where j.jobname='field-gap-queue' and d.status='succeeded';
        if not exists (select 1 from cron.job j where j.jobname='field-gap-queue' and j.active)
           or coalesce(v_ts, (select min(d.start_time) from cron.job_run_details d where d.jobid>(select j.jobid from cron.job j where j.jobname='field-gap-queue'))) < now()-make_interval(hours=>security.pipeline_num_v1('stall.queue_hours',7)::int) then
          v_found:=v_found||security.platform_health_issue_v1('field_stalled:queue','warning','coverage sweep','Fill the gaps (standing queue) is switched on but has not run since '||coalesce(to_char(v_ts at time zone 'Australia/Melbourne','DD Mon HH24:MI'),'it was scheduled'),
            jsonb_build_object('last_success',v_ts,'resolve','Scheduled jobs › field-gap-queue; Check now on Coverage › Attributes'));
        end if;
      end if;
      v_det:=v_det||jsonb_build_object('field_stalled',jsonb_build_object('flat',(select count(*) from jsonb_array_elements(v_x) x where x->>'reason'='flat'),
                                                                         'behind',(select count(*) from jsonb_array_elements(v_x) x where x->>'reason'='behind'),
                                                                         'no_reader',(select count(*) from jsonb_array_elements(v_x) x where x->>'reason'='no_reader')));
      v_ok:=array_append(v_ok,'field_stalled');
    exception when others then
      v_ok:=array_append(v_ok,'field_stalled');
      v_found:=v_found||security.platform_health_issue_v1('field_stalled:check_error','warning','coverage sweep','The stalled fields check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('field_stalled',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.15 SS-014B (31 Oct 2026): search refresh requests. Slow = waiting past the target for a known reason (the refresh gap, another
  -- writer); stalled = nothing is processing them (job missing, paused, failing or not running) or waiting past the stalled limit.
  if security.platform_health_due_v1('search_refresh',p_force) then
    v_t:=clock_timestamp();
    begin
      select count(*), min(q.requested_at) into v_n, v_ts from search.refresh_requests q where q.processed_at is null;
      select max(q.processed_at) into v_ts2 from search.refresh_requests q where q.processed_at is not null;
      v_num:=coalesce(round(extract(epoch from now()-v_ts)/60),0);
      select j.jobid, j.active, j.schedule into r from cron.job j where j.jobname='search-refresh-requested';
      v_x:=null; v_q:=null;
      select jsonb_build_object('at',d.start_time,'status',d.status,'result',left(d.return_message,200)) into v_x
        from cron.job_run_details d where d.jobid=r.jobid order by d.start_time desc limit 1;
      select jsonb_build_object('pid',a.pid,'since',coalesce(a.xact_start,a.query_start),'query',left(regexp_replace(a.query,'\s+',' ','g'),120)) into v_q
        from pg_locks l join pg_stat_activity a on a.pid=l.pid
       where l.locktype='advisory' and l.granted and l.objsubid=1 and l.objid=((hashtext('cf247:search_course_documents_writer')::bigint) & 4294967295)::oid limit 1;  -- fixed: the one writer lock (W27)
      v_txt:=case when r.jobid is null then 'job_missing' when not r.active then 'job_paused'
                  when v_x->>'status'='failed' then 'job_failing'
                  when v_x is null or (v_x->>'at')::timestamptz < now()-make_interval(secs=>3*coalesce(security.platform_cron_interval_seconds(r.schedule),600)) then 'job_not_running'  -- fixed: three missed runs
                  when v_q is not null or v_x->>'result' ilike '%another search-document writer%' then 'writer_busy'
                  when v_x->>'result' ilike '%refresh gap%' then 'refresh_gap'
                  else 'waiting_for_next_run' end;
      if v_n>0 and v_num>security.pipeline_num_v1('health.search_refresh_slow_minutes', 40) then
        v_bool:=v_num>security.pipeline_num_v1('health.search_refresh_stalled_minutes', 90) or v_txt in ('job_missing','job_paused','job_failing','job_not_running');
        v_args:=case v_txt
          when 'job_missing' then 'Schedule the job search-refresh-requested again (Automations); the requests are kept and are processed at its first run.'
          when 'job_paused' then 'Switch on the job search-refresh-requested (Automations); the requests are kept and are processed at its next run.'
          when 'job_failing' then 'Its last run failed ('||coalesce(v_x->>'result','no message')||'). Fix the error; the requests are kept and are processed at the next successful run.'
          when 'job_not_running' then 'The job is switched on but has not run since '||coalesce(to_char((v_x->>'at')::timestamptz at time zone 'Australia/Melbourne','DD Mon HH24:MI'),'it was scheduled')||'. Check the scheduler and the database connections.'
          when 'writer_busy' then 'Another search-document writer holds the writer lock'||coalesce(' since '||to_char((v_q->>'since')::timestamptz at time zone 'Australia/Melbourne','HH24:MI')||' (process '||(v_q->>'pid')||')','')||'. The requests are processed when it finishes; if it has run for over an hour, look at that writer.'
          when 'refresh_gap' then 'Automatic requests wait for the refresh gap (setting search.refresh_min_gap_minutes, '||security.pipeline_num_v1('search.refresh_min_gap_minutes', 30)||' minutes). No action unless the gap was raised by mistake.'
          else 'The job ran without processing them; they are processed at its next run. If this persists, look at its last result.' end;
        v_found:=v_found||security.platform_health_issue_v1('search_refresh:waiting', case when v_bool then 'critical' else 'warning' end, 'search/API',
          'Search refresh '||case when v_bool then 'has stalled' else 'is slow' end||': '||v_n||' request(s) waiting, the oldest for '||v_num||' minutes ('||replace(v_txt,'_',' ')||')',
          jsonb_build_object('pending',v_n,'oldest_requested_at',v_ts,'oldest_minutes',v_num,'cause',v_txt,'next_step',v_args,'last_processed_at',v_ts2,
            'job_active',coalesce(r.active,false),'last_run',v_x,'writer',v_q,
            'slow_after_minutes',security.pipeline_num_v1('health.search_refresh_slow_minutes', 40),'stalled_after_minutes',security.pipeline_num_v1('health.search_refresh_stalled_minutes', 90)));
      end if;
      v_det:=v_det||jsonb_build_object('search_refresh',jsonb_build_object('pending',v_n,'oldest_minutes',case when v_n>0 then v_num end,'last_processed_at',v_ts2,'cause',case when v_n>0 then v_txt end));
      v_ok:=array_append(v_ok,'search_refresh');
    exception when others then
      v_ok:=array_append(v_ok,'search_refresh');
      v_found:=v_found||security.platform_health_issue_v1('search_refresh:check_error','warning','search/API','The search refresh check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('search_refresh',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 4.16 SS-014C (31 Oct 2026): the alert outbox itself: deliveries that failed, and alerts nobody collects while delivery is on
  if security.platform_health_due_v1('alerts',p_force) then
    v_t:=clock_timestamp();
    begin
      select count(*) filter (where a.status='failed' and a.created_at>=now()-interval '24 hours'),  -- fixed: health check observation window
             count(*) filter (where a.status in ('pending','sending')), min(a.created_at) filter (where a.status in ('pending','sending')),
             count(*) filter (where a.status='held' and a.created_at>=now()-interval '24 hours')  -- fixed: health check observation window
        into v_n, v_n2, v_ts, v_n3 from pipeline.platform_alerts a;
      v_bool:=coalesce((security.toolset_setting('pipeline','alerts.delivery_enabled') #>> '{}')::boolean,false);
      if v_n>0 then
        v_found:=v_found||security.platform_health_issue_v1('alerts:delivery_failed','warning','scheduled jobs',
          v_n||' alert(s) could not be delivered in the last 24 hours (every attempt used)',jsonb_build_object('failed_24h',v_n,'resolve','Platform health › Alerts'));
      end if;
      if v_bool and v_n2>0 and v_ts<now()-make_interval(mins=>security.pipeline_num_v1('alerts.collect_within_minutes', 120)::int) then
        v_found:=v_found||security.platform_health_issue_v1('alerts:not_collected','critical','scheduled jobs',
          v_n2||' alert(s) have waited since '||to_char(v_ts at time zone 'Australia/Melbourne','DD Mon HH24:MI')||': the alert destination is not collecting them',
          jsonb_build_object('waiting',v_n2,'since',v_ts,'resolve','Check the alert destination (scheduled task or webhook)'));
      end if;
      v_det:=v_det||jsonb_build_object('alerts',jsonb_build_object('delivery',case when v_bool then 'on' else 'off (recorded only)' end,'waiting',v_n2,'held_24h',v_n3,'failed_24h',v_n,
        'last_sent_at',(select max(a.sent_at) from pipeline.platform_alerts a)));
      v_ok:=array_append(v_ok,'alerts');
    exception when others then
      v_ok:=array_append(v_ok,'alerts');
      v_found:=v_found||security.platform_health_issue_v1('alerts:check_error','warning','scheduled jobs','The alert outbox check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('alerts',round(extract(epoch from clock_timestamp()-v_t)*1000));
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

  delete from pipeline.platform_edge_calls where created_at<now()-interval '2 days';  -- fixed: health check log retention
  delete from pipeline.platform_health_runs where started_at<now()-interval '14 days';  -- fixed: health check log retention
  delete from pipeline.platform_issues where resolved_at<now()-interval '90 days';  -- fixed: health check log retention

  select jsonb_build_object('critical',count(*) filter (where severity='critical'),'warning',count(*) filter (where severity='warning'),'info',count(*) filter (where severity='info'))
    into v_counts from pipeline.platform_issues where resolved_at is null;
  insert into pipeline.platform_health_runs(started_at,duration_ms,checks_ran,check_ms,counts)
  values (v_t0, round(extract(epoch from clock_timestamp()-v_t0)*1000), v_ok, v_ms, v_counts);
  return jsonb_build_object('ran',to_jsonb(v_ok),'duration_ms',round(extract(epoch from clock_timestamp()-v_t0)*1000),'check_ms',v_ms,'open',v_counts,'found',jsonb_array_length(v_found));
end $function$
