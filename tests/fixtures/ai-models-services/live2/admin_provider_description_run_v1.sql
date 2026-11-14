CREATE OR REPLACE FUNCTION public.admin_provider_description_run_v1(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_rank int:=security.current_role_rank(); c pipeline.provider_description_cohorts%rowtype;
 v_res jsonb; v_preview jsonb; v_fresh jsonb; x jsonb; v_id uuid; v_reason text:=btrim(coalesce(p_args->>'reason','')); v_n int:=0; v_run uuid; v_why text;
 v_mode text; v_args jsonb; v_ids uuid[]; v_history jsonb; v_rule text; v_diagnosis jsonb; v_context jsonb; v_issue bigint; v_ai_request bigint; v_ai_model text; v_ai_why text; v_job pipeline.automation_catalogue%rowtype; v_dispatch_error text; v_dispatch_sqlstate text;
begin
 if v_actor is null or v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
 select * into v_job from pipeline.automation_catalogue where jobname='provider-description-read';
 if p_action='verify' and v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot verify this job publication' using errcode='42501'; end if;
 if p_action='capabilities' then
 return jsonb_build_object('contract','provider-description-run-v1','can_run',v_rank>=coalesce(v_job.control_rank,6),'control_rank',coalesce(v_job.control_rank,6),'reason_min_chars',security.pipeline_num_v1('pdesc.reason_min_chars',5)::int,
 'can_explain',v_rank>=coalesce(v_job.control_rank,6),'can_diagnose',security.pipeline_num_v1('ops.ai_diagnosis_on',0)>=1 and security.ai_use_allowed_v1('ops_diagnose') and nullif(security.toolset_setting('pipeline','ops.ai_diagnosis_model')#>>'{}','') is not null,'ai_diagnosis_reason','AI assistance requires the existing approved Operations diagnosis switch, model and spending guards plus an existing open issue linked to this exact provider and evidence. Explain evidence always uses stored checks.',
 'countries',coalesce((select jsonb_agg(jsonb_build_object('code',k.iso_alpha2,'label',coalesce(to_jsonb(k)->>'name',to_jsonb(k)->>'country_name',k.iso_alpha2::text),'enabled',coalesce(security.toolset_setting('pipeline','pdesc.countries'),'[]')?k.iso_alpha2::text)) from ref.countries k where k.iso_alpha2 in ('AU','NZ','CA')),'[]'),
 'provider_types',coalesce((select jsonb_agg(jsonb_build_object('code',t.code,'label',coalesce(to_jsonb(t)->>'label',to_jsonb(t)->>'name',t.code),'enabled',coalesce(security.toolset_setting('pipeline','pdesc.provider_types'),'[]')?t.code)) from ref.provider_types t),'[]'),
 'providers',coalesce((select jsonb_agg(jsonb_build_object('provider_id',p.id,'name',coalesce(p.display_name,p.canonical_name),'country',k.iso_alpha2,'type',t.code) order by coalesce(p.display_name,p.canonical_name)) from catalogue.providers p join ref.countries k on k.id=p.country_id left join ref.provider_types t on t.id=p.provider_type_id where security.provider_description_scope_v1(p.id)),'[]'),
 'min_size',1,'max_size',security.provider_description_cohort_cap_v1(),'default_size',security.pipeline_num_v1('batch.provider_description',3)::int,
 'modes',jsonb_build_array(jsonb_build_object('id','stored','label','Stored official evidence + approved AI','allowed',true),jsonb_build_object('id','approved','label','Existing authorised acquisition + approved AI','allowed',security.pipeline_num_v1('pdesc.acquire_direct',0)>=1)),
 'model',(select model_identifier from pipeline.central_ai_settings where id=1),'enabled',security.pipeline_num_v1('pdesc.enabled',0)>=1,
 'job_active',coalesce((select active from cron.job where jobname='provider-description-read'),false),
 'policy',jsonb_build_object('countries',security.toolset_setting('pipeline','pdesc.countries'),'types',security.toolset_setting('pipeline','pdesc.provider_types'),'provider_keys',security.toolset_setting('pipeline','pdesc.provider_keys'),'ai_usd_max',security.pipeline_num_v1('pdesc.ai_usd_max',1),'pending_max',security.pipeline_num_v1('pdesc.pending_max',10),'reserved_usd',(select coalesce(sum(reserved_usd),0) from pipeline.provider_description_reads),'remaining_usd',greatest(0,security.pipeline_num_v1('pdesc.ai_usd_max',1)-(select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening')-(select coalesce(sum(reserved_usd),0) from pipeline.provider_description_reads)),'actual_ai_calls',(select coalesce(sum(ai_calls),0) from pipeline.provider_description_reads),'recorded_billable_calls',(select coalesce(sum(calls),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening'),'recorded_cost_usd',(select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening'),'ai_call_counter_scope','reported model calls since provider-description-autonomy instrumentation; ledger calls are separate recorded billable calls','budget_period','lifetime pilot','required_approval','Individual human Layer 4 decision'));
 elsif p_action='preview' then
 v_args:=p_args||jsonb_build_object('mode',coalesce(nullif(p_args->>'mode',''),'stored'));
 -- Fill fields (Provider Catalogue and Provider Detail): the screen names what it wants to do; the governed selection gets the same description state it always had.
 if nullif(p_args->>'fill_mode','') is not null then
  if p_args->>'fill_mode' not in ('missing','upgrade_basic') then raise exception 'unsupported fill mode' using errcode='22023'; end if;
  v_args:=v_args||jsonb_build_object('description_state',case p_args->>'fill_mode' when 'upgrade_basic' then 'stale' else 'missing' end,'upgrade',p_args->>'fill_mode'='upgrade_basic');
 end if;
 v_res:=security.provider_description_selection_multi_v1(v_args);
 insert into pipeline.provider_description_cohorts(requested_by,selection,snapshot,expires_at)
 values(v_actor,v_args,v_res,now()+make_interval(mins=>security.pipeline_num_v1('pdesc.ui_preview_minutes',10)::int)) returning id into v_id;
 return v_res||jsonb_build_object('token',v_id,'preview_token',v_id,'expires_at',now()+make_interval(mins=>security.pipeline_num_v1('pdesc.ui_preview_minutes',10)::int));
 elsif p_action='prepare' then
 if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot prepare this job' using errcode='42501'; end if;
 if length(v_reason)<security.pipeline_num_v1('pdesc.reason_min_chars',5) then raise exception 'audit reason is shorter than the governed minimum' using errcode='22023'; end if;
 select * into c from pipeline.provider_description_cohorts where id=nullif(p_args->>'preview_token','')::uuid and requested_by=v_actor for update;
 if c.id is null then raise exception 'unknown owned preview' using errcode='42501'; end if;
 if c.state in ('prepared','started') then return security.provider_description_run_result_v1(c.id); end if;
 if c.expires_at<now() then raise exception 'preview expired; preview again' using errcode='22023'; end if;
 v_fresh:=security.provider_description_selection_multi_v1(c.selection);
 for x in select * from jsonb_array_elements(c.snapshot->'providers') where (value->>'eligible')::boolean loop
  if not exists(select 1 from jsonb_array_elements(v_fresh->'providers') f where f->>'provider_id'=x->>'provider_id' and (f->>'eligible')::boolean and f->>'evidence_id' is not distinct from x->>'evidence_id' and f->>'source_hash' is not distinct from x->>'source_hash' and f->>'current_description' is not distinct from x->>'current_description' and f->>'last_read_id' is not distinct from x->>'last_read_id') then raise exception 'preview changed; preview again' using errcode='22023'; end if;
  v_n:=v_n+1;
  insert into pipeline.provider_description_cohort_members(cohort_id,provider_id,evidence_id,pick,snapshot) values(c.id,(x->>'provider_id')::uuid,(x->>'evidence_id')::uuid,v_n,x);
 end loop;
 if v_n=0 then raise exception 'no eligible provider with approved evidence in this preview' using errcode='22023'; end if;
 update pipeline.provider_description_cohorts set state='prepared',reason=v_reason,prepared_at=now() where id=c.id;
 insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','cohort_prepare',c.id::text,jsonb_build_object('selected',v_n,'reason',v_reason,'selection',c.selection),v_actor);
 return security.provider_description_run_result_v1(c.id);
 elsif p_action='run' then
 if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot start this job' using errcode='42501'; end if;
 select * into c from pipeline.provider_description_cohorts where id=nullif(p_args->>'cohort_id','')::uuid and requested_by=v_actor for update;
 if c.id is null or c.state='preview' then raise exception 'unknown owned fixed cohort' using errcode='42501'; end if;
 if c.run_id is not null then return security.provider_description_run_result_v1(c.id)||jsonb_build_object('repeat',true); end if;
 if (select count(*) from pipeline.provider_description_cohort_members where cohort_id=c.id)>security.provider_description_cohort_cap_v1() then
   raise exception 'current_cap_changed: the fixed cohort exceeds the current governed cap; prepare a new cohort' using errcode='22023';
 end if;
 -- Same task kind, catalogue permission, pause/spend/review rules and provider-description job. Never a second scheduler.
 v_why:=case when not coalesce(security.toolset_setting('pipeline','run_now.jobs'),'[]'::jsonb)?'provider-description-read' then 'job_not_allowlisted'
 when v_job.jobname is null then 'job_not_catalogued'
 when not exists(select 1 from cron.job where jobname='provider-description-read' and active) then 'job_paused'
 when security.pipeline_num_v1('pdesc.enabled',0)<1 then 'reader_off'
 when not security.ai_use_allowed_v1('provider_description') then 'ai_refused'
 when (select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening')>=security.pipeline_num_v1('pdesc.ai_usd_max',1) then 'ai_ceiling'
 when (select count(*) from pipeline.layer4_review_items where field_code='provider_description' and status='pending')>=security.pipeline_num_v1('pdesc.pending_max',10) then 'review_full' end;
 -- Policy/capacity holds are durable: the fixed cohort stays recoverable and the existing scheduled job resumes it.
 for x in select m.snapshot from pipeline.provider_description_cohort_members m where m.cohort_id=c.id order by m.pick loop
   v_fresh:=security.provider_description_selection_v1(c.selection||jsonb_build_object('provider_id',x->>'provider_id','size',1));
   if not exists(select 1 from jsonb_array_elements(v_fresh->'providers') f where (f->>'eligible')::boolean and f->>'evidence_id' is not distinct from x->>'evidence_id' and f->>'source_hash' is not distinct from x->>'source_hash' and f->>'current_description' is not distinct from x->>'current_description') then
     update pipeline.provider_description_cohort_members set snapshot=snapshot||jsonb_build_object('eligibility_reason','selection_changed_before_run','eligible',false) where cohort_id=c.id and provider_id=(x->>'provider_id')::uuid; continue;
   end if;
   insert into pipeline.provider_description_reads(provider_id) values((x->>'provider_id')::uuid) on conflict do nothing returning id into v_id;
   if v_id is null then select id into v_id from pipeline.provider_description_reads where provider_id=(x->>'provider_id')::uuid and state in ('queued','reading','proposed') order by created_at desc limit 1; end if;
   update pipeline.provider_description_cohort_members set read_id=v_id where cohort_id=c.id and provider_id=(x->>'provider_id')::uuid;
   v_n:=v_n+1; v_id:=null;
 end loop;
 update pipeline.provider_description_cohorts set state='started' where id=c.id;
 if v_why is null and v_n>0 then
   perform set_config('cf.pdesc_run_now',c.id::text,true);
   begin
     v_res:=security.provider_description_fire_v1();
   exception when others then
     -- OTHERS deliberately excludes query cancellation: the caller's statement/lock limits remain authoritative.
     get stacked diagnostics v_dispatch_error=message_text,v_dispatch_sqlstate=returned_sqlstate;
     v_res:=jsonb_build_object('sent',0,'parked',true,'reason','reader_dispatch_failed','error',v_dispatch_error,'sqlstate',v_dispatch_sqlstate,'retry_strategy','existing provider-description-read schedule resumes this saved queued cohort');
   end;
 else v_res:=jsonb_build_object('sent',0,'parked',true,'reason',coalesce(v_why,'selection_changed_before_run')); end if;
 insert into pipeline.admin_jobs(kind,lane,state,title,args,result,error,requested_by,reason,started_at,finished_at,scope,outcome)
 values('job_run_now','run_now',case when v_dispatch_error is not null then 'failed' when v_why is null then 'done' else 'cancelled' end,'Provider descriptions: bounded Run Now',jsonb_build_object('job','provider-description-read','cohort_id',c.id,'idempotency_key',c.request_key),v_res||jsonb_build_object('selected',v_n,'admitted',0,'publication_measured_separately',true),v_dispatch_error,v_actor,c.reason,now(),clock_timestamp(),'cohort:'||c.id,case when v_dispatch_error is not null then 'failed_retryable' when v_why is not null then 'blocked_policy' else 'succeeded_no_movement' end) returning id into v_run;
 update pipeline.provider_description_cohorts set run_id=v_run where id=c.id;
 insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','run_now','provider-description-read',jsonb_build_object('cohort_id',c.id,'run_id',v_run,'dispatch',v_res,'reason',c.reason),v_actor);
 return security.provider_description_run_result_v1(c.id)||jsonb_build_object('dispatch',v_res);
  elsif p_action='fill_caps' then
 -- Fill fields: what the panel needs to know before it asks anything. No provider list (capabilities carries every provider in scope; the panel does not need it).
 return jsonb_build_object('contract','provider-description-fill-v1','can_run',v_rank>=coalesce(v_job.control_rank,6),'control_rank',coalesce(v_job.control_rank,6),'reason_min_chars',security.pipeline_num_v1('pdesc.reason_min_chars',5)::int,
  'min_size',1,'max_size',security.provider_description_cohort_cap_v1(),
  'cap',jsonb_build_object('queue_per_run',security.pipeline_num_v1('pdesc.queue_per_run',10),'pending_max',security.pipeline_num_v1('pdesc.pending_max',10),'pilot_cap',security.pipeline_num_v1('run_now.pilot_cap',20),'queue_cap',security.pipeline_num_v1('pdesc.queue_cap',60),'effective',security.provider_description_cohort_cap_v1()),
  'enabled',security.pipeline_num_v1('pdesc.enabled',0)>=1,'job_active',coalesce((select active from cron.job where jobname='provider-description-read'),false),
  'run_now_allowed',coalesce(security.toolset_setting('pipeline','run_now.jobs'),'[]'::jsonb)?'provider-description-read',
  'poll_seconds',greatest(30,security.pipeline_num_v1('pdesc.every_minutes',60)::int*15) /* fixed: a quarter of the reader's own window (minutes x 60 / 4), never faster than twice a minute */,'status_max',security.provider_description_cohort_cap_v1(),
  'modes',jsonb_build_array(jsonb_build_object('id','stored','label','Stored official evidence + approved AI','allowed',true),jsonb_build_object('id','approved','label','Existing authorised acquisition + approved AI','allowed',security.pipeline_num_v1('pdesc.acquire_direct',0)>=1)),
  'fill_modes',jsonb_build_array('missing','upgrade_basic','preview_only','verify_publication'),
  'upgrade_basic_on',security.pipeline_num_v1('pdesc.registry_upgrade_on',0)>=1 and security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1,
  'quality_classes',to_jsonb(security.provider_description_quality_classes_v1()));
 elsif p_action in ('provider_status','provider_publication') then
 -- Fill fields, read only: the state of up to the governed number of providers, and the task that last included each. Needs no saved cohort, so it works after the browser was closed.
 select coalesce(array_agg(distinct (e)::uuid),array[]::uuid[]) into v_ids from jsonb_array_elements_text(case when jsonb_typeof(p_args->'provider_ids')='array' then p_args->'provider_ids' else '[]'::jsonb end) e;
 if cardinality(v_ids)=0 or cardinality(v_ids)>security.provider_description_cohort_cap_v1() then raise exception 'name between 1 and % providers',security.provider_description_cohort_cap_v1() using errcode='22023'; end if;
 if p_action='provider_publication' then
  if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot verify this job publication' using errcode='42501'; end if;
  v_res:=security.provider_description_publication_read_v1(v_ids);
  insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','verify_provider_publication',array_to_string(v_ids,','),jsonb_build_object('providers',cardinality(v_ids),'as_at',now(),'reason','Operator requested actual catalogue and consumer read-back from Fill fields'),v_actor);
  return v_res;
 end if;
 return security.provider_description_fill_status_v1(v_ids,coalesce((p_args->>'feeds')::boolean,false),v_actor);
 elsif p_action='quality_counts' then
 return security.provider_description_quality_counts_v1();
 elsif p_action='quality_refresh' then
 if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot refresh the quality snapshot' using errcode='42501'; end if;
 select array_agg(distinct (e)::uuid) into v_ids from jsonb_array_elements_text(case when jsonb_typeof(p_args->'provider_ids')='array' then p_args->'provider_ids' else '[]'::jsonb end) e;
 return security.provider_description_quality_refresh_v1(v_ids);
 elsif p_action in ('saved','verify','diagnose') then
 if p_action='diagnose' and nullif(p_args->>'preview_token','') is not null then select * into c from pipeline.provider_description_cohorts where id=(p_args->>'preview_token')::uuid and requested_by=v_actor;
 elsif nullif(p_args->>'cohort_id','') is not null then select * into c from pipeline.provider_description_cohorts where id=(p_args->>'cohort_id')::uuid and requested_by=v_actor;
 else select * into c from pipeline.provider_description_cohorts where requested_by=v_actor order by created_at desc,id desc limit 1; end if;
 if p_action='diagnose' then
   if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot diagnose this job' using errcode='42501'; end if;
   if length(v_reason)<security.pipeline_num_v1('pdesc.reason_min_chars',5) then raise exception 'audit reason required'; end if;
   if c.id is null and nullif(p_args->>'preview_token','') is not null then select * into c from pipeline.provider_description_cohorts where id=(p_args->>'preview_token')::uuid and requested_by=v_actor; end if;
   if c.id is null then raise exception 'owned saved evidence required' using errcode='42501'; end if;
   select coalesce(r.rule,m.snapshot->>'eligibility_reason'),coalesce(r.reason,m.snapshot->>'reason') into v_rule,v_why from pipeline.provider_description_cohort_members m left join pipeline.provider_description_reads r on r.id=m.read_id where m.cohort_id=c.id and m.provider_id=(p_args->>'provider_id')::uuid;
   if v_rule is null then select x->>'eligibility_reason',x->>'reason' into v_rule,v_why from jsonb_array_elements(c.snapshot->'providers') x where x->>'provider_id'=p_args->>'provider_id'; end if;
   if v_rule is null then raise exception 'provider is not in owned saved evidence' using errcode='42501'; end if;
   v_diagnosis:=jsonb_build_object('method','stored_checks','rule',v_rule,'explanation',coalesce(v_why,case v_rule when 'no_verified_stored_source' then 'A current official About/Overview page stored against this exact provider is needed.' when 'unchanged_unsuitable_evidence' then 'The same evidence previously failed or was rejected. A changed approved source is needed before another AI read.' when 'review_full' then 'The validated proposal is parked until Layer 4 capacity becomes available; no further AI read is needed.' else 'Inspect the official source, identity references and validation checks. Only the existing human Layer 4 decision can authorise admission.' end),'ai_used',false,'cost_usd',0,'ai_reason','Provider-description AI diagnostics have no approved existing route.','at',now());
   -- AI is advice through the existing Operations lane only, bound to an already recorded issue and the exact stored source.
   select coalesce((select m.snapshot||jsonb_build_object('evidence_id',coalesce(r.evidence_id,m.evidence_id),'source_hash',coalesce(r.content_hash,m.snapshot->>'source_hash'),'checks',r.checks,'sentences',r.proposal->'sentences') from pipeline.provider_description_cohort_members m left join pipeline.provider_description_reads r on r.id=m.read_id where m.cohort_id=c.id and m.provider_id=(p_args->>'provider_id')::uuid),
     (select z from jsonb_array_elements(c.snapshot->'providers') z where z->>'provider_id'=p_args->>'provider_id')) into v_context;
   v_ai_model:=nullif(security.toolset_setting('pipeline','ops.ai_diagnosis_model')#>>'{}','');
   v_ai_why:=case when security.pipeline_num_v1('ops.ai_diagnosis_on',0)<1 then 'ops.ai_diagnosis_on is 0'
      when v_ai_model is null then 'no approved Operations diagnosis model'
      when not security.ai_use_allowed_v1('ops_diagnose') then 'existing Operations AI spending guard refuses assistance'
      when nullif(v_context->>'evidence_id','') is null then 'no exact stored evidence reference for an existing issue' end;
   if v_ai_why is null then
    select i.id into v_issue from pipeline.integration_issues i where i.status not in ('closed','superseded') and (p_args->>'provider_id')::uuid=any(i.provider_ids)
      and jsonb_path_exists(i.evidence,'$.**.evidence_id ? (@ == $id)',jsonb_build_object('id',v_context->>'evidence_id')) order by i.id desc limit 1;
    if v_issue is null then v_ai_why:='no existing open integration issue links this exact provider and stored evidence'; end if;
   end if;
   if v_ai_why is null then
    perform pg_advisory_xact_lock(hashtext('cf247 pdesc diagnosis '||v_issue::text)); -- fixed: duplicate request suppression for the existing issue/evidence.
    select q.id into v_ai_request from pipeline.ops_ai_diagnosis_requests q where q.issue_id=v_issue and q.context->>'provider_description_evidence_id'=v_context->>'evidence_id' and q.state in ('queued','leased','answered','refused') order by q.id desc limit 1;
    if v_ai_request is null then
     insert into pipeline.ops_ai_diagnosis_requests(issue_id,context,model,note)
     values(v_issue,jsonb_build_object('issue',v_issue,'provider_id',p_args->>'provider_id','provider_description_evidence_id',v_context->>'evidence_id','evidence',v_context,'question','Explain why this official source or claim is unsuitable and which evidence is missing. Advice only; do not authorise a description or change any setting.',
       'deterministic',v_diagnosis,'root_causes',(select jsonb_agg(jsonb_build_object('code',rc.code,'class',rc.class,'title',rc.title,'description',rc.description)) from pipeline.ops_root_causes rc)),v_ai_model,'Provider description evidence explanation; advice through existing Operations diagnosis') returning id into v_ai_request;
    end if;
    v_diagnosis:=v_diagnosis||jsonb_build_object('request_id',v_ai_request,'request_status','queued','integration_issue_id',v_issue,'model',v_ai_model,'ai_reason','Queued through the existing Operations diagnosis worker; no approval or settings authority.');
   else v_diagnosis:=v_diagnosis||jsonb_build_object('ai_reason',v_ai_why); end if;
   update pipeline.provider_description_cohort_members set snapshot=snapshot||jsonb_build_object('diagnosis',v_diagnosis) where cohort_id=c.id and provider_id=(p_args->>'provider_id')::uuid;
   update pipeline.provider_description_cohorts set snapshot=jsonb_set(snapshot,'{providers}',(select jsonb_agg(case when z->>'provider_id'=p_args->>'provider_id' then z||jsonb_build_object('diagnosis',v_diagnosis) else z end) from jsonb_array_elements(snapshot->'providers') z)) where id=c.id;
   insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','explain_evidence',c.id::text,jsonb_build_object('provider_id',p_args->>'provider_id','reason',v_reason,'diagnosis',v_diagnosis),v_actor);
   return v_diagnosis;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('cohort_id',h.id,'state',h.state,'created_at',h.created_at,'reason',h.reason,'run_id',h.run_id) order by h.created_at desc),'[]') into v_history from (select * from pipeline.provider_description_cohorts where requested_by=v_actor order by created_at desc limit security.pipeline_num_v1('pdesc.queue_per_run',10)::int) h;
 if c.state='preview' then
   v_preview:=jsonb_set(c.snapshot,'{providers}',coalesce((select jsonb_agg(z||case when z->'diagnosis'->>'request_id' is not null then jsonb_build_object('diagnosis',(z->'diagnosis')||coalesce((select jsonb_build_object('request_status',q.state,'ai_used',q.state='answered','explanation',coalesce(q.answer->>'reasoning',z->'diagnosis'->>'explanation'),'answer',q.answer,'model',q.model,'cost_usd',q.cost_usd,'answered_at',q.answered_at) from pipeline.ops_ai_diagnosis_requests q where q.id=(z->'diagnosis'->>'request_id')::bigint),'{}'::jsonb)) else '{}'::jsonb end) from jsonb_array_elements(c.snapshot->'providers') z),'[]'::jsonb));
   return jsonb_build_object('preview',v_preview||jsonb_build_object('token',c.id,'expires_at',c.expires_at),'scope',c.selection,'history',v_history);
 end if;
 if c.id is null then return jsonb_build_object('history',v_history,'providers','[]'::jsonb,'runs','[]'::jsonb); end if;
 v_res:=security.provider_description_run_result_v1(c.id);
 if p_action='verify' then
   update pipeline.provider_description_cohorts set verified_at=now(),verification=v_res-'last_verification' where id=c.id;
   insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','verify',c.id::text,jsonb_build_object('totals',v_res->'totals','as_at',now(),'reason','Operator requested actual catalogue and consumer read-back'),v_actor);
 end if;
 return v_res||jsonb_build_object('history',v_history);
 end if;
 raise exception 'unknown provider-description action %',p_action using errcode='22023';
end $function$
