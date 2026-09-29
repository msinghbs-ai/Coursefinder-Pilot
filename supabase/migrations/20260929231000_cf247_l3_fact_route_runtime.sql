-- CF-CHG-20260915-247 Layer 3 model routing (Platform Admin direction 29 Sep 2026 18:30 IST): runtime for the
-- intake and English Layer 3 routes, following the tuition pattern (Decision 163 Option A). NOTHING IS ACTIVATED HERE:
-- no cron, no enabled profile. Activation is a separate, explicit migration per task class.
--  * hand-off + claim (public.layer3_fact_claim_service): only when a routed profile for the task class is enabled,
--    unpaused, not retired, has a passing fresh-holdout qualification, and the worker's binding hash equals the
--    qualified one; within the task's daily spend guard and the profile's requests/day; and only while the latest
--    OpenRouter credit observation is at or above the US$5 floor. Pages: coverage-sweep pages that print the course's
--    CRICOS code, active courses, not blocked by Layer 4, and only courses that hold no value for the attribute
--    (write-only-when-empty). Each hand-off is recorded as a Layer 2 run item, a Layer 3 work item and a Layer 3
--    interpretation (audit trail identical in shape to tuition).
--  * completion (public.layer3_fact_complete_service): a valid answer with a value waits for admission; a valid
--    "not stated" closes as no_candidate; anything rejected by the validators (or a returned model other than the
--    pinned one) goes to Layer 4 with a plain reason. Nothing is admitted by the worker.
--  * admission (security.layer3_fact_admit_v1): the governed path public.svc_coursefacts_apply_record, write-only-when-
--    empty; a course that meanwhile holds a different value goes to Layer 4; Search gates for the sweep sources;
--    Search refresh for the courses written; consumer snapshots before and after every batch that writes. Admission
--    stops by itself when the task's routed profile is paused or disabled.
--  * credit floor (public.layer3_route_credit_floor_service): below US$5 of OpenRouter credit, every Layer 3 route cron
--    (intake, English, tuition hand-off and tuition dispatch) is switched off and the event is logged.

create table if not exists pipeline.layer3_route_budget (
  task_class text primary key,
  daily_usd_max numeric not null check (daily_usd_max >= 0),
  credit_floor_usd numeric not null default 5 check (credit_floor_usd >= 0),
  note text,
  updated_at timestamptz not null default now()
);
insert into pipeline.layer3_route_budget(task_class,daily_usd_max,note) values
  ('provider_intake_validation',0,'set by the activation migration'),
  ('provider_english_validation',0,'set by the activation migration')
on conflict (task_class) do nothing;

create table if not exists pipeline.layer3_fact_handoffs (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id),
  task_class text not null check (task_class in ('provider_intake_validation','provider_english_validation')),
  evidence_id uuid not null references pipeline.evidence_artifacts(id),
  work_item_id uuid,
  attempts int not null default 1,
  handed_at timestamptz not null default now(),
  unique (course_id, task_class, evidence_id)
);
create index if not exists layer3_fact_handoffs_wi_idx on pipeline.layer3_fact_handoffs(work_item_id);

create table if not exists pipeline.layer3_route_events (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
do $g$ declare t text;
begin
  foreach t in array array['layer3_route_budget','layer3_fact_handoffs','layer3_route_events'] loop
    execute format('alter table pipeline.%I enable row level security', t);
    execute format('revoke all on pipeline.%I from public, anon, authenticated', t);
  end loop;
end $g$;

-- the routed profile for a task class (one at most: enabled, unpaused, not retired, qualified on a fresh holdout)
create or replace function pipeline.layer3_routed_profile(p_task_class text)
returns pipeline.layer3_model_profiles language sql stable set search_path to 'pg_catalog','pipeline' as $f$
  select p.* from pipeline.layer3_model_profiles p
   where p_task_class=any(p.allowed_task_classes) and p.enabled and not p.paused and p.retired_at is null
     and coalesce((p.quality_benchmark->>'pass')::boolean,false) and coalesce((p.holdout_qualification->>'pass')::boolean,false)
   order by p.updated_at desc limit 1
$f$;
revoke all on function pipeline.layer3_routed_profile(text) from public, anon, authenticated;

create or replace function public.layer3_fact_route_profile_service(p_task_class text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare p pipeline.layer3_model_profiles;
begin
  perform public.layer3_routing_service_guard();
  if p_task_class not in ('provider_intake_validation','provider_english_validation') then raise exception 'unsupported task class'; end if;
  p:=pipeline.layer3_routed_profile(p_task_class);
  if p.id is null then return jsonb_build_object('reason','no qualified, enabled and unpaused profile for '||p_task_class); end if;
  return jsonb_build_object('id',p.id,'code',p.code,'model_identifier',p.model_identifier,'max_output_tokens',p.max_output_tokens,'timeout_ms',p.timeout_ms,
    'prompt_profile_version',p.prompt_profile_version);
end $f$;

create or replace function public.layer3_fact_claim_service(p_task_class text, p_limit int, p_worker text, p_binding_hash text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','catalogue','security' as $f$
declare p pipeline.layer3_model_profiles; b pipeline.layer3_route_budget%rowtype; v_spent numeric; v_calls int; v_credit record; v_batch uuid; v_run uuid; v_wi uuid; v_int uuid;
        r record; v_items jsonb:='[]'::jsonb; v_limit int; v_key text;
begin
  perform public.layer3_routing_service_guard();
  if p_task_class not in ('provider_intake_validation','provider_english_validation') then raise exception 'unsupported task class'; end if;
  if nullif(btrim(p_worker),'') is null then raise exception 'worker required'; end if;
  p:=pipeline.layer3_routed_profile(p_task_class);
  if p.id is null then return jsonb_build_object('items','[]'::jsonb,'reason','no qualified, enabled and unpaused profile'); end if;
  if p_binding_hash is distinct from p.quality_benchmark->>'binding_hash' then
    insert into pipeline.layer3_route_events(kind,detail) values ('claim_refused_binding_drift',jsonb_build_object('task_class',p_task_class,'profile',p.code,'worker_hash',p_binding_hash,'qualified_hash',p.quality_benchmark->>'binding_hash'));
    return jsonb_build_object('items','[]'::jsonb,'reason','binding hash differs from the qualified one; execution refused');
  end if;
  select * into b from pipeline.layer3_route_budget where task_class=p_task_class;
  select coalesce(sum(i.estimated_cost_usd),0), count(*) into v_spent, v_calls from pipeline.layer3_interpretations i
   where i.task_class=p_task_class and i.created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
  if b.task_class is null or v_spent>=b.daily_usd_max then return jsonb_build_object('items','[]'::jsonb,'reason',format('daily spend guard: spent %s of %s USD today',round(v_spent,4),coalesce(b.daily_usd_max,0))); end if;
  if v_calls>=p.requests_per_day then return jsonb_build_object('items','[]'::jsonb,'reason','profile requests/day reached'); end if;
  select remaining_usd, observed_at into v_credit from pipeline.layer3_openrouter_observations where kind='credits' order by observed_at desc limit 1;
  if v_credit.remaining_usd is null or v_credit.observed_at<now()-interval '20 minutes' or v_credit.remaining_usd<b.credit_floor_usd then
    return jsonb_build_object('items','[]'::jsonb,'reason',format('credit floor: latest remaining %s USD at %s (floor %s)',v_credit.remaining_usd,v_credit.observed_at,b.credit_floor_usd));
  end if;
  v_limit:=greatest(1,least(coalesce(p_limit,10),40,p.requests_per_day-v_calls));

  -- stale claims (worker lost): the work item fails and the page may be handed off again (at most 3 attempts)
  with stale as (
    update pipeline.layer3_work_items w set status='failed', last_error='stale claim released', updated_at=now()
     where w.task_class=p_task_class and w.status='interpreting' and w.updated_at<now()-interval '30 minutes' returning w.id)
  update pipeline.layer3_fact_handoffs h set work_item_id=null, attempts=h.attempts+1 from stale where h.work_item_id=stale.id;

  -- one open Layer 2 batch for the sweep profile (shared with the tuition hand-off)
  select bt.id into v_batch from pipeline.layer2_run_batches bt join pipeline.layer2_source_profiles sp on sp.id=bt.profile_id
   where sp.profile_key='au-coverage-sweep-course-pages' and bt.status in ('queued','running') order by bt.created_at limit 1;
  if v_batch is null then
    perform pg_advisory_xact_lock(hashtext('coverage-sweep-l3-batch'));
    select bt.id into v_batch from pipeline.layer2_run_batches bt join pipeline.layer2_source_profiles sp on sp.id=bt.profile_id
     where sp.profile_key='au-coverage-sweep-course-pages' and bt.status in ('queued','running') order by bt.created_at limit 1;
    if v_batch is null then
      v_key:='coverage-sweep-l3:'||to_char(now() at time zone 'UTC','YYYY-MM-DD')||':'||p_task_class;
      insert into pipeline.layer2_run_batches(profile_id,profile_version_id,trigger_type,status,policy_snapshot,started_at,idempotency_key)
      select sp.id, sp.current_version_id, 'schedule', 'running', jsonb_build_object('decision','Decision 163 Option A','worker','layer3-model-routing'), now(), v_key
        from pipeline.layer2_source_profiles sp where sp.profile_key='au-coverage-sweep-course-pages'
      returning id into v_batch;
    end if;
  end if;

  for r in
    select pg.course_id, pg.provider_id, pg.url, pg.evidence_id, pg.read_at, e.storage_path, e.content_hash, co.course_code, h.id handoff_id
      from pipeline.coverage_course_pages pg
      join pipeline.evidence_artifacts e on e.id=pg.evidence_id and e.storage_path is not null and e.content_hash is not null
      join catalogue.courses co on co.id=pg.course_id and co.lifecycle_status='active'
      left join pipeline.layer3_fact_handoffs h on h.course_id=pg.course_id and h.task_class=p_task_class and h.evidence_id=pg.evidence_id
     where pg.read_status='read' and pg.identity_basis='cricos_code'
       and (h.id is null or (h.work_item_id is null and h.attempts<3))
       and not security.layer4_entity_or_parent_blocked('course',pg.course_id,'operational')
       and case p_task_class
             when 'provider_intake_validation' then not exists (select 1 from catalogue.course_intakes i where i.course_id=pg.course_id and coalesce(i.status,'active')='active')
             else not exists (select 1 from catalogue.course_english_requirements er where er.course_id=pg.course_id and er.status='active')
                  -- pages with a clear Layer 2 score stay with the deterministic coverage admission (coverage-admit)
                  and not (coalesce(pg.candidates->'english','{}'::jsonb) ?| array['ielts_overall','pte_overall','toefl_overall'])
           end
       and not exists (select 1 from pipeline.layer4_review_items l where l.entity_type='course' and l.entity_id=pg.course_id and l.status='pending'
                         and l.field_code=case p_task_class when 'provider_intake_validation' then 'course_intake' else 'course_english' end)
     order by md5(pg.course_id::text||to_char(now(),'YYYYMMDDHH24'))
     limit v_limit
     for update of pg skip locked
  loop
    insert into pipeline.layer2_run_items(batch_id,entity_type,entity_id,source_url,status,evidence_count,fields_targeted,fields_resolved,started_at,completed_at,outcome_code)
    values (v_batch,'course',r.course_id,r.url,'layer3_required',1,1,0,r.read_at,now(),case p_task_class when 'provider_intake_validation' then 'intake_requires_layer3' else 'english_requires_layer3' end)
    returning id into v_run;
    update pipeline.layer2_run_batches set target_count=target_count+1, processed_count=processed_count+1, escalated_l3_count=escalated_l3_count+1, heartbeat_at=now(), updated_at=now() where id=v_batch;
    insert into pipeline.layer3_work_items(layer2_run_item_id,evidence_id,entity_type,entity_id,task_class,profile_id,status,reason,reserved_at,reserved_by,attempt_count,policy_version,change_control_ref,candidate_context)
    values (v_run,r.evidence_id,'course',r.course_id,p_task_class,p.id,'interpreting',
            case p_task_class when 'provider_intake_validation' then 'requires_layer3_intake_validation' else 'requires_layer3_english_validation' end,
            now(),p_worker,1,'cf247-l3-model-routing-v1','CF-CHG-20260915-247',
            jsonb_build_object('task_class',p_task_class,'identity_match',true,'identity_basis','cricos_code','expected_course_code',r.course_code,
              'source_record_id','coverage:'||r.course_id,'page_url',r.url,'routing','cf247-l3-model-routing-v1'))
    returning id into v_wi;
    insert into pipeline.layer3_interpretations(evidence_id,evidence_hash,entity_type,entity_id,task_class,profile_id,prompt_profile_version,eligibility_reason,status,layer2_state,
      selected_evidence_reason,change_control_ref,uat_ref,call_started_at)
    values (r.evidence_id,r.content_hash,'course',r.course_id,p_task_class,p.id,p.prompt_profile_version,'layer2_unresolved','calling',
      jsonb_build_object('status','layer3_required','layer2_run_item_id',v_run,'work_item_id',v_wi,'routing','cf247-l3-model-routing-v1'),
      'coverage-sweep page that prints the course CRICOS code','CF-CHG-20260915-247','CF-247-layer3-model-routing',now())
    returning id into v_int;
    update pipeline.layer3_work_items set interpretation_id=v_int where id=v_wi;
    if r.handoff_id is null then
      insert into pipeline.layer3_fact_handoffs(course_id,task_class,evidence_id,work_item_id) values (r.course_id,p_task_class,r.evidence_id,v_wi);
    else
      update pipeline.layer3_fact_handoffs set work_item_id=v_wi, handed_at=now() where id=r.handoff_id;
    end if;
    v_items:=v_items||jsonb_build_object('work_item_id',v_wi,'interpretation_id',v_int,'course_id',r.course_id,'storage_path',r.storage_path,'evidence_id',r.evidence_id,'url',r.url);
  end loop;
  return jsonb_build_object('items',v_items,'profile',jsonb_build_object('id',p.id,'code',p.code,'model_identifier',p.model_identifier,'base_url',p.base_url,'secret_env_key',p.secret_env_key,
    'max_output_tokens',p.max_output_tokens,'timeout_ms',p.timeout_ms,'retry_ceiling',p.retry_ceiling,'prompt_profile_version',p.prompt_profile_version),
    'spent_today_usd',v_spent,'daily_usd_max',b.daily_usd_max);
end $f$;

create or replace function public.layer3_fact_complete_service(p_work_item_id uuid, p_interpretation_id uuid, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','catalogue' as $f$
declare w pipeline.layer3_work_items%rowtype; v_valid boolean; v_admitted jsonb; v_status text; v_wstatus text; v_reason text; v_field text; v_errors text;
begin
  perform public.layer3_routing_service_guard();
  select * into w from pipeline.layer3_work_items where id=p_work_item_id for update;
  if w.id is null or w.interpretation_id is distinct from p_interpretation_id then raise exception 'work item / interpretation mismatch'; end if;
  if w.task_class not in ('provider_intake_validation','provider_english_validation') then raise exception 'unsupported task class'; end if;
  if w.status<>'interpreting' then return jsonb_build_object('work_status',w.status,'note','already completed'); end if;
  v_valid:=coalesce((p_result->>'valid')::boolean,false);
  v_admitted:=case when jsonb_typeof(p_result->'admitted')='object' then p_result->'admitted' end;
  v_status:=case when not v_valid then 'rejected_validation' when v_admitted is null then 'no_candidate' else 'validated' end;
  v_field:=case w.task_class when 'provider_intake_validation' then 'course_intake' else 'course_english' end;
  v_errors:=coalesce((select string_agg(x,'; ') from jsonb_array_elements_text(coalesce(p_result->'errors','[]'::jsonb)) x),'');
  update pipeline.layer3_interpretations set
    status=v_status, raw_result=p_result->'answer', candidate_value=v_admitted,
    rationale=left(coalesce(p_result->'answer'->>'rationale',''),4000),
    evidence_quotes=coalesce(p_result->'answer'->'quotes',(select jsonb_agg(t->'quote') from jsonb_array_elements(coalesce(p_result->'answer'->'tests','[]'::jsonb)) t),'[]'::jsonb),
    validator_result=jsonb_build_object('valid',v_valid,'errors',coalesce(p_result->'errors','[]'::jsonb),'safety_blockers',coalesce(p_result->'safety_blockers','[]'::jsonb),
      'text_sha256',p_result->>'text_sha256','binding_hash',p_result->>'binding_hash','routing','cf247-l3-model-routing-v1'),
    aggregator_response_model=p_result->>'returned_model', input_tokens=nullif(p_result->>'input_tokens','')::int, output_tokens=nullif(p_result->>'output_tokens','')::int,
    estimated_cost_usd=greatest(coalesce((p_result->>'cost_usd')::numeric,0),0), external_call_count=coalesce((p_result->>'external_calls')::int,0),
    retry_count=greatest(coalesce((p_result->>'external_calls')::int,0)-1,0), call_latency_ms=nullif(p_result->>'latency_ms','')::int, call_completed_at=now()
  where id=p_interpretation_id;
  if v_status='validated' then v_wstatus:='validated';
  elsif v_status='no_candidate' then v_wstatus:='no_candidate';
  else
    v_wstatus:='layer4_required';
    v_reason:=case
      when v_errors ~ 'returned_model_mismatch' then 'The AI service answered with a different model from the approved one, so the answer was not used. Please check the page.'
      when v_errors ~ 'quote_not_in_page_text|quote_not_in_page' then 'The AI quoted text that is not on the saved page, so its answer cannot be trusted. Please check the page.'
      when v_errors ~ 'month_not_in_quotes|overall_not_in_quote|min_band_not_in_quote|quote_does_not_name_test' then 'The AI''s answer was not fully supported by the words it quoted from the page. Please check the page.'
      when v_errors ~ 'provider_|no_answer|unparseable|worker_error' then 'The AI service could not give a usable answer for this page. Please check the page.'
      else 'The AI''s answer did not pass the automatic checks. Please check the page.' end
      || case w.task_class when 'provider_intake_validation' then ' Confirm the months this course starts for international students.' else ' Confirm the English test scores international students need.' end;
    insert into pipeline.layer4_review_items(entity_type,entity_id,field_code,evidence_id,layer3_interpretation_id,before_value,proposed_value,layer2_state,layer3_state,status,escalation_reason,change_control_ref)
    values ('course',w.entity_id,v_field,w.evidence_id,p_interpretation_id,null,v_admitted,jsonb_build_object('source','coverage sweep','page',w.candidate_context->>'page_url'),
            jsonb_build_object('errors',coalesce(p_result->'errors','[]'::jsonb),'answer',p_result->'answer','model',p_result->>'returned_model'),'pending',v_reason,'CF-CHG-20260915-247');
  end if;
  update pipeline.layer3_work_items set status=v_wstatus, completed_at=case when v_wstatus in ('no_candidate','layer4_required') then now() end,
    last_error=case when v_wstatus='layer4_required' then left(v_errors,500) end, updated_at=now() where id=w.id;
  return jsonb_build_object('work_status',v_wstatus,'interpretation_status',v_status);
end $f$;

-- Admission: governed path, write-only-when-empty, differences to Layer 4, Search gates, consumer snapshots.
create or replace function security.layer3_fact_admit_v1(p_task_class text, p_limit int default 100)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','catalogue','pipeline','security','search' as $f$
declare p pipeline.layer3_model_profiles; r record; v_payload jsonb; v_cur jsonb; v_prop jsonb; v_same boolean; v_ok int:=0; v_same_n int:=0; v_l4 int:=0; v_err int:=0; v_last text;
        v_courses uuid[]:='{}'; v_before jsonb; v_after jsonb; v_src uuid; v_domain text; v_gate text; v_field text; v_label text;
begin
  if current_user not in ('postgres','service_role') and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
  if p_task_class not in ('provider_intake_validation','provider_english_validation') then raise exception 'unsupported task class'; end if;
  p:=pipeline.layer3_routed_profile(p_task_class);
  if p.id is null then return jsonb_build_object('admitted',0,'reason','no routed profile: admission stopped for '||p_task_class); end if;
  v_domain:=case p_task_class when 'provider_intake_validation' then 'intake' else 'english_requirement' end;
  v_gate:=case p_task_class when 'provider_intake_validation' then 'course_intake' else 'course_english' end;
  v_field:=v_gate;
  if not exists (select 1 from pipeline.layer3_work_items w where w.task_class=p_task_class and w.status='validated') then
    return jsonb_build_object('task_class',p_task_class,'admitted',0,'note','nothing waiting');
  end if;
  v_before:=security.consumer_api_snapshot_v1();
  for r in
    select w.id wid, w.entity_id course_id, w.evidence_id, i.id iid, i.candidate_value cv, i.aggregator_response_model model, i.profile_id,
           pg.provider_id, pg.url, e.content_hash,
           (select pr.registration_code from catalogue.provider_registrations pr where pr.provider_id=pg.provider_id and lower(pr.registration_scheme)='cricos' and coalesce(pr.status,'active') not in ('inactive','cancelled','archived') order by pr.checked_at desc nulls last limit 1) pc,
           (select cr.registration_code from catalogue.course_registrations cr where cr.course_id=w.entity_id and lower(cr.scheme)='cricos' limit 1) cc
      from pipeline.layer3_work_items w
      join pipeline.layer3_interpretations i on i.id=w.interpretation_id and i.status='validated'
      join pipeline.coverage_course_pages pg on pg.course_id=w.entity_id and pg.evidence_id=w.evidence_id and pg.identity_basis='cricos_code'
      join pipeline.evidence_artifacts e on e.id=w.evidence_id
     where w.task_class=p_task_class and w.status='validated' and i.profile_id=p.id
     order by w.updated_at limit greatest(1,least(coalesce(p_limit,100),300))
     for update of w skip locked
  loop
    begin
      if r.pc is null or r.cc is null then raise exception 'provider or course CRICOS unresolved'; end if;
      if security.layer4_entity_or_parent_blocked('course',r.course_id,'operational') then raise exception 'course operationally blocked by Layer 4'; end if;
      if p_task_class='provider_intake_validation' then
        v_prop:=(select jsonb_agg(jsonb_build_object('intake_label',(array['January','February','March','April','May','June','July','August','September','October','November','December'])[m::int],
                   'source_intake_key',lower(r.cc)||':current:'||lower((array['January','February','March','April','May','June','July','August','September','October','November','December'])[m::int])) order by m::int)
                   from jsonb_array_elements_text(r.cv->'months') m);
        select jsonb_agg(i.intake_label) into v_cur from catalogue.course_intakes i where i.course_id=r.course_id and coalesce(i.status,'active')='active';
        v_same:=v_cur is not null and not exists (select 1 from jsonb_array_elements(v_prop) x where not exists (select 1 from jsonb_array_elements_text(v_cur) k(v) where k.v ilike '%'||(x->>'intake_label')||'%'));
        v_payload:=jsonb_build_object('intakes',v_prop);
      else
        v_prop:=(select jsonb_agg(case when t->>'test'='IELTS' then
                    jsonb_build_object('test_code','IELTS','overall_score',(t->>'overall')::numeric,
                      'component_scores',case when t->>'min_band' is not null then jsonb_build_object('listening',(t->>'min_band')::numeric,'reading',(t->>'min_band')::numeric,'writing',(t->>'min_band')::numeric,'speaking',(t->>'min_band')::numeric) else '{}'::jsonb end,
                      'notes','Course page (CRICOS code on page), Layer 3 '||coalesce(r.model,''))
                  else jsonb_build_object('test_code',t->>'test','overall_score',(t->>'overall')::numeric,'notes','Course page (CRICOS code on page), Layer 3 '||coalesce(r.model,'')) end)
                   from jsonb_array_elements(r.cv->'tests') t);
        select jsonb_agg(jsonb_build_object('test',t.code,'overall',er.overall_score)) into v_cur from catalogue.course_english_requirements er join ref.english_tests t on t.id=er.english_test_id
         where er.course_id=r.course_id and er.status='active';
        v_same:=v_cur is not null and not exists (select 1 from jsonb_array_elements(v_prop) x where not exists (select 1 from jsonb_array_elements(v_cur) k(v) where k.v->>'test'=x->>'test_code' and (k.v->>'overall')::numeric=(x->>'overall_score')::numeric));
        v_payload:=jsonb_build_object('english_requirements',v_prop);
      end if;
      if v_prop is null or jsonb_array_length(v_prop)=0 then raise exception 'empty admitted value'; end if;

      if v_cur is not null then
        if v_same then
          update pipeline.layer3_work_items set status='admitted', completed_at=now(), last_error='admitted: the same value is already held', updated_at=now() where id=r.wid;
          v_same_n:=v_same_n+1;
        else
          insert into pipeline.layer4_review_items(entity_type,entity_id,field_code,evidence_id,layer3_interpretation_id,before_value,proposed_value,layer2_state,layer3_state,status,escalation_reason,change_control_ref)
          values ('course',r.course_id,v_field,r.evidence_id,r.iid,v_cur,v_prop,jsonb_build_object('source','coverage sweep','page',r.url),jsonb_build_object('model',r.model,'candidate_value',r.cv),'pending',
                  case p_task_class when 'provider_intake_validation' then 'The course page lists different intake months from the ones we hold. Please check the page and confirm the intakes.'
                       else 'The course page gives a different English score from the one we hold. Please check the page and confirm the requirement.' end,'CF-CHG-20260915-247');
          update pipeline.layer3_work_items set status='layer4_required', last_error='differs from the value already held', updated_at=now() where id=r.wid;
          v_l4:=v_l4+1;
        end if;
        continue;
      end if;

      v_src:=security.coverage_sweep_source(r.provider_id);
      if not exists (select 1 from pipeline.course_fact_source_qualifications q where q.source_id=v_src and q.provider_cricos=upper(r.pc)) then
        insert into pipeline.course_fact_source_qualifications(source_id,country_id,source_key,source_class,authority_name,provider_cricos,admitted_domains,mapping_strategy,evidence_strategy,qualification_status,notes,metadata)
        select v_src, s.country_id, 'au_'||lower(r.pc)||'_coverage_sweep','provider_first_party', coalesce(pv.display_name,pv.canonical_name), upper(r.pc),
               array['official_course_url','english_requirement','intake'], 'course page accepted only when it prints the course''s CRICOS code',
               'page stored gzipped as evidence with its SHA-256; values written only where the course has none; value read by the qualified Layer 3 model',
               'bounded','Decision 163 admission rule; Layer 3 model routing (Platform Admin 29 Sep 2026 18:30 IST)',
               jsonb_build_object('decision','Decision 163','apply_admitted',true,'search_admitted',true,'identity_authority',false,'change_control_ref','CF-CHG-20260915-247')
          from pipeline.sources s join catalogue.providers pv on pv.id=r.provider_id where s.id=v_src;
      else
        update pipeline.course_fact_source_qualifications set admitted_domains=array(select distinct unnest(admitted_domains||array[v_domain])), updated_at=now()
         where source_id=v_src and provider_cricos=upper(r.pc) and not (v_domain=any(admitted_domains));
      end if;
      insert into search.enrichment_source_gates(projection_code,domain_code,source_id,gate_status,approval_ref,approved_at,created_at,updated_at)
      select 'courses',v_gate,v_src,'approved','CF-CHG-20260915-247; Layer 3 model routing; Platform Admin direction 29 Sep 2026 18:30 IST',now(),now(),now()
       where not exists (select 1 from search.enrichment_source_gates g where g.projection_code='courses' and g.domain_code=v_gate and g.source_id=v_src);

      perform public.svc_coursefacts_apply_record(v_src, r.evidence_id, r.pc, r.cc, 'l3:'||p_task_class||':'||r.course_id, r.url, r.content_hash, v_payload, true);
      update pipeline.layer3_work_items set status='admitted', completed_at=now(), last_error=null, updated_at=now() where id=r.wid;
      v_ok:=v_ok+1; v_courses:=v_courses||r.course_id;
    exception when others then
      v_err:=v_err+1; v_last:=left(sqlerrm,200);
      update pipeline.layer3_work_items set status='layer4_required', last_error=left('admission failed: '||sqlerrm,500), updated_at=now() where id=r.wid;
      insert into pipeline.layer4_review_items(entity_type,entity_id,field_code,evidence_id,layer3_interpretation_id,proposed_value,layer2_state,layer3_state,status,escalation_reason,change_control_ref)
      values ('course',r.course_id,v_field,r.evidence_id,r.iid,r.cv,'{}'::jsonb,jsonb_build_object('admission_error',left(sqlerrm,300)),'pending',
              'The AI''s answer could not be recorded automatically. Please check the page and confirm the value.','CF-CHG-20260915-247');
    end;
  end loop;
  if cardinality(v_courses)>0 then
    perform search.refresh_course_enrichment_scoped_v1(v_courses,true);
    v_after:=security.consumer_api_snapshot_v1();
    v_label:=case p_task_class when 'provider_intake_validation' then 'intake' else 'English' end;
    insert into pipeline.consumer_api_baselines(label,snapshot) values
      ('before Layer 3 '||v_label||' admission batch ('||cardinality(v_courses)||' courses, model routing)',v_before),
      ('after Layer 3 '||v_label||' admission batch ('||cardinality(v_courses)||' courses, model routing)',v_after);
  end if;
  return jsonb_build_object('task_class',p_task_class,'admitted',v_ok,'already_held_same',v_same_n,'layer4_differs',v_l4,'errors',v_err,'last_error',v_last);
end $f$;
revoke all on function security.layer3_fact_admit_v1(text,int) from public, anon, authenticated;

-- Credit floor: below the floor every Layer 3 route cron is switched off (logged); a person switches them back on.
create or replace function public.layer3_route_credit_floor_service(p_remaining numeric, p_floor numeric)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','cron' as $f$
declare v_jobs text[]:='{}'; j record;
begin
  perform public.layer3_routing_service_guard();
  if p_remaining is null or p_remaining>=p_floor then return jsonb_build_object('stopped',false); end if;
  for j in select jobid, jobname from cron.job where active and jobname in ('layer3-intake-route','layer3-english-route','coverage-tuition-handoff','layer3-tuition-dispatch') loop
    perform cron.alter_job(j.jobid, active:=false);
    v_jobs:=v_jobs||j.jobname;
  end loop;
  insert into pipeline.layer3_route_events(kind,detail) values ('credit_floor_stop',jsonb_build_object('remaining_usd',p_remaining,'floor_usd',p_floor,'jobs_stopped',v_jobs));
  return jsonb_build_object('stopped',true,'jobs_stopped',v_jobs,'remaining_usd',p_remaining);
end $f$;

do $g$ declare fn text;
begin
  foreach fn in array array['layer3_fact_route_profile_service(text)','layer3_fact_claim_service(text,int,text,text)','layer3_fact_complete_service(uuid,uuid,jsonb)',
                            'layer3_route_credit_floor_service(numeric,numeric)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', fn);
    execute format('grant execute on function public.%s to service_role', fn);
  end loop;
end $g$;
