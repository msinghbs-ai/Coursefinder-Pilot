CREATE OR REPLACE FUNCTION security.provider_description_fire_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-autonomy-v1
declare v_q int := 0; v_due int; v_open int; v_last timestamptz; v_pending int; v_dead int; v_cohort uuid; v_resumed int; v_sent int; v_i int;
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247 provider description fire')) then return jsonb_build_object('sent',0,'reason','reader_dispatch_in_flight'); end if; -- fixed: serialize the existing job dispatch, never wait or duplicate a nonce.
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return jsonb_build_object('enabled', false); end if;
  -- Publication and parked proposal progress do not require another paid read. Manual Run Now never adds work outside its fixed cohort.
  if nullif(current_setting('cf.pdesc_run_now',true),'') is null then
  perform security.provider_description_publication_check_v1();
  perform security.provider_description_settle_abandoned_v1(); -- reservations that nothing is working on are settled first (an abandoned paid call is counted, never assumed free); a settled read with the held rule below goes back to the queue
  update pipeline.provider_description_reads set state='queued',tries=greatest(0,tries-1),next_try_at=now()+make_interval(mins=>security.pipeline_num_v1('pdesc.retry_minutes',360)::int),leased_until=null,updated_at=now()
  where state='held' and rule in ('source_identity_proof_missing','ai_ceiling','ai_daily_guard','ai_refused','model_pricing_unavailable','invalid_model_pricing','unrecognised_pricing_component','ai_budget_refused','existing_cost_reservation_uncertain') and reserved_usd=0;

  update pipeline.provider_description_reads r set state='held',rule='selection_changed_before_lease',reason='Provider scope, identity, manual lock or pinned source changed; inspect saved evidence before preparing another cohort',updated_at=now()
  where r.state='queued' and exists(select 1 from pipeline.provider_description_cohort_members m join pipeline.provider_description_cohorts c on c.id=m.cohort_id where m.read_id=r.id and c.state='started')
  and (not security.provider_description_scope_v1(r.provider_id)
    or exists(select 1 from pipeline.provider_description_cohort_members m join catalogue.providers p on p.id=m.provider_id where m.read_id=r.id and p.description is distinct from m.snapshot->>'current_description')
    or exists(select 1 from catalogue.providers p where p.id=r.provider_id and not (security.provider_description_identity_v1(r.provider_id,coalesce((select m.snapshot->>'source_url' from pipeline.provider_description_cohort_members m where m.read_id=r.id order by m.pick limit 1),p.website))->>'ok')::boolean)
    or exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all'))
    or exists(select 1 from pipeline.provider_description_cohort_members m where m.read_id=r.id and m.evidence_id is not null and not exists(select 1 from pipeline.evidence_artifacts a where a.id=m.evidence_id and coalesce(a.content_hash,a.id::text)=m.snapshot->>'source_hash' and coalesce(a.captured_at,a.created_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.source_max_age_days',365)::int) and (security.provider_description_identity_v1(r.provider_id,a.source_url)->>'ok')::boolean)));
  v_resumed:=security.provider_description_resume_v1();
  v_q := security.provider_description_enqueue_v1();
  if security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then perform security.provider_description_machine_step_v1(); end if;
  else v_q:=0; v_resumed:=0; end if;
  select count(*) into v_dead from pipeline.provider_description_reads r where r.state = 'dead_letter';
  if not security.ai_use_allowed_v1(case when security.pdesc_on_demand_due_v1() then 'provider_description_on_demand' else 'provider_description' end) then return jsonb_build_object('queued', v_q, 'ai', 'stopped', 'dead_letter', v_dead); end if; /* 20261112010000 */
  if (select coalesce(sum(l.cost_usd), 0) from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening') >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) and not security.pdesc_on_demand_due_v1() then /* 20261112010000 */
    return jsonb_build_object('queued', v_q, 'ai', 'ceiling', 'dead_letter', v_dead);
  end if;
  select count(*) into v_pending from pipeline.layer4_review_items i where i.field_code = 'provider_description' and i.status = 'pending';
  if v_pending >= security.pipeline_num_v1('pdesc.pending_max', 10) and security.pipeline_num_v1('pdesc.machine_admit_on',0)<1 then return jsonb_build_object('queued', v_q, 'review', 'full', 'pending', v_pending); end if;
  select count(*) into v_due from pipeline.provider_description_reads r
   where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now())) and r.tries < security.pipeline_num_v1('pdesc.tries', 3)
     and (nullif(current_setting('cf.pdesc_run_now',true),'') is null or exists(select 1 from pipeline.provider_description_cohort_members m where m.cohort_id=nullif(current_setting('cf.pdesc_run_now',true),'')::uuid and m.read_id=r.id));
  select max(l.created_at) into v_last from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'provider_description'
     and l.created_at > now() - make_interval(mins => security.pipeline_num_v1('pdesc.every_minutes', 60)::int) + interval '30 seconds'; -- fixed: fire jitter, so a fire exactly one window after the last dispatch is not blocked by the milliseconds that dispatch started after its minute
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'provider_description' and l.created_at > now() - interval '4 minutes'  -- fixed: fire guard
     and not exists (select 1 from net._http_response h where h.id = l.request_id);
  if nullif(current_setting('cf.pdesc_run_now',true),'') is not null then v_last:=null; end if; -- Run Now bypasses frequency only; all other job guards remain.
  if v_due > 0 and v_open = 0 and v_last is null then
    if nullif(current_setting('cf.pdesc_run_now',true),'') is not null then v_cohort:=nullif(current_setting('cf.pdesc_run_now',true),'')::uuid;
    else
    select c.id into v_cohort from pipeline.provider_description_cohorts c
    where c.state='started' and exists(select 1 from pipeline.provider_description_cohort_members m join pipeline.provider_description_reads r on r.id=m.read_id where m.cohort_id=c.id and ((r.state='queued' and r.next_try_at<=now()) or (r.state='reading' and r.leased_until<now())))
    order by c.prepared_at,c.id limit 1;
    end if;
    -- automatic mode: as many worker calls as the due reads need, up to pdesc.dispatch_max (each lease is bounded by the concurrency and spend limits); otherwise one call, as before
    v_sent := case when security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 and v_cohort is null then least(security.pipeline_num_v1('pdesc.dispatch_max',3)::int, greatest(1, ceil(v_due::numeric / greatest(1, security.pipeline_num_v1('batch.provider_description', 3)))::int)) else 1 end;
    for v_i in 1 .. v_sent loop
      perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_description', 'limit', security.pipeline_num_v1('batch.provider_description', 3)::int,'cohort_id',v_cohort));
    end loop;
    return jsonb_build_object('queued', v_q, 'due', v_due, 'sent', v_sent, 'dead_letter', v_dead);
  end if;
  return jsonb_build_object('queued', v_q, 'due', v_due, 'sent', 0, 'dead_letter', v_dead);
end $function$
