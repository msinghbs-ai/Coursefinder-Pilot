CREATE OR REPLACE FUNCTION public.svc_provider_description_record(p_results jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-autonomy-v1
declare x jsonb; r pipeline.provider_description_reads%rowtype; v_ev uuid; v_url text; v_cap timestamptz; v_via text; v_hash text;
        v_chk jsonb; v_item uuid; v_tally jsonb := '{}'::jsonb; v_out text; v_max int := security.pipeline_num_v1('pdesc.tries', 3)::int; v_err text; v_m jsonb; v_src uuid; v_idc jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  perform pg_advisory_xact_lock(hashtext('cf247 provider description capacity')); -- fixed: serialize final Layer 4 capacity check with leases.
  for x in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    select * into r from pipeline.provider_description_reads where id = (x->>'item_id')::uuid for update;
    if r.id is null or r.state <> 'reading' then v_tally := v_tally || jsonb_build_object('stale', coalesce((v_tally->>'stale')::int, 0) + 1); continue; end if;
    update pipeline.provider_description_reads set ai_calls=ai_calls+case when coalesce((x->>'ai_call_started')::boolean,false) then 1 else 0 end, checks=coalesce(checks,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object('identity',x->'identity_check','ai_reservation',x->'ai_reservation','cost_known',x->'cost_known')), reserved_usd=case when coalesce((x->>'cost_known')::boolean,false) or coalesce((x->>'cost')::numeric,0)>0 then 0 else reserved_usd end, cost_usd = cost_usd + greatest(coalesce((x->>'cost')::numeric, 0), 0),
           firecrawl_reads = firecrawl_reads + greatest(coalesce((x->>'fc_reads')::int, 0), 0),
           model = coalesce(nullif(x->>'model', ''), model), prompt_version = coalesce(nullif(x->>'prompt_version', ''), prompt_version),
           worker = coalesce(left(nullif(x->>'worker', ''), 60), worker), updated_at = now()
     where id = r.id;
    v_ev := null; v_url := null; v_cap := null; v_via := null; v_hash := null;
    -- the page: a stored copy, or a page the worker read and stored now (registered as evidence under the provider's coverage-sweep source)
    if (x->>'stored_evidence_id') is not null then
      select a.id, a.source_url, coalesce(a.captured_at, a.created_at), coalesce(a.content_hash, a.id::text) into v_ev, v_url, v_cap, v_hash
        from pipeline.evidence_artifacts a join pipeline.sources s on s.id = a.source_id
       where a.id = (x->>'stored_evidence_id')::uuid and s.provider_id = r.provider_id;
      v_via := case when v_ev is not null then 'stored' end;
    elsif x->'fetch'->>'status' = 'read' and x->'fetch'->>'storage_path' is not null and x->'fetch'->>'sha256' ~ '^[0-9a-f]{64}$' then
      v_url := x->'fetch'->>'url'; v_hash := x->'fetch'->>'sha256'; v_via := x->'fetch'->>'via'; v_cap := now();
      if security.provider_page_host_v1(r.provider_id, v_url) = 'own' then
        -- the sweep source is found once (9 Nov 2026, record time-out): security.coverage_sweep_source is volatile, so as a test on every row it could not be an index condition and the lookup read the whole (source, hash) index (22 ms on average, 142 ms at worst, against 0.2 ms with the id in hand)
        v_src := security.coverage_sweep_source(r.provider_id);
        select a.id into v_ev from pipeline.evidence_artifacts a where a.source_id = v_src and a.content_hash = v_hash and a.source_url = v_url limit 1;
        if v_ev is null then
          v_ev := public.svc_coursefacts_register_evidence(v_src, v_url, x->'fetch'->>'storage_path', v_hash,
                    coalesce(x->'fetch'->>'mime', 'text/html'),
                    jsonb_build_object('layer', 2, 'kind', 'provider_about_page', 'worker', 'coverage-sweep', 'provider_description_read_id', r.id, 'read_via', v_via) || case when jsonb_typeof(x->'fetch'->'http') = 'number' then jsonb_build_object('page_status', (x->'fetch'->>'http')::int) else '{}'::jsonb end);
        end if;
      end if;
    end if;
    update pipeline.provider_description_reads set evidence_id = coalesce(v_ev, evidence_id), source_url = coalesce(v_url, x->'fetch'->>'url', source_url),
           read_via = coalesce(v_via, read_via), content_hash = coalesce(v_hash, content_hash), source_captured_at = coalesce(v_cap, source_captured_at)
     where id = r.id;
    v_err := nullif(x->>'error', '');
    if v_err is not null or coalesce((x->>'retry')::boolean, false) then
      -- a failed read is tried again after pdesc.retry_minutes, at most pdesc.tries times; then the dead letter list
      update pipeline.provider_description_reads set state = case when tries >= v_max then 'dead_letter' else 'queued' end,
             next_try_at = now() + make_interval(mins => security.pipeline_num_v1('pdesc.retry_minutes', 360)::int), leased_until = null,
             rule = case when tries >= v_max then 'dead_letter' else 'retry' end, reason = left(coalesce(v_err, x->>'reason', 'retry'), 400), updated_at = now()
       where id = r.id returning state into v_out;
      v_tally := v_tally || jsonb_build_object(v_out, coalesce((v_tally->>v_out)::int, 0) + 1); continue;
    end if;
    if x->'answer' is null and x->>'rule' in ('source_identity_proof_missing','ai_ceiling','ai_daily_guard','ai_refused','model_pricing_unavailable','invalid_model_pricing','unrecognised_pricing_component','ai_budget_refused','existing_cost_reservation_uncertain') and coalesce((select reserved_usd from pipeline.provider_description_reads where id=r.id),0)=0 then
      update pipeline.provider_description_reads set state='queued',tries=greatest(0,tries-1),next_try_at=now()+make_interval(mins=>security.pipeline_num_v1('pdesc.retry_minutes',360)::int),leased_until=null,rule=x->>'rule',reason=left(coalesce(x->>'reason','Waiting for existing AI spending or pricing policy to allow the next read.'),400),updated_at=now() where id=r.id;
      v_tally:=v_tally||jsonb_build_object('parked_policy',coalesce((v_tally->>'parked_policy')::int,0)+1); continue;
    end if;
    if x->'answer' is null then
      -- no page to read: no About page on the provider's own hosts, robots.txt, another provider's host
      update pipeline.provider_description_reads set state = 'held', leased_until = null, rule = coalesce(nullif(x->>'rule', ''), 'no_about_page'),
             reason = left(coalesce(x->>'reason', 'no About page found on the provider''s own website'), 400), updated_at = now()
       where id = r.id;
      v_tally := v_tally || jsonb_build_object('held', coalesce((v_tally->>'held')::int, 0) + 1); continue;
    end if;
    select * into r from pipeline.provider_description_reads where id = r.id;
    -- sentence filter (migration 20261110110000): a sentence that fails a sentence rule is left out and the others are kept; a proposal stores and passes on the KEPT sentences (checks.dropped says what was left out and why)
    v_chk := security.provider_description_validate_v1(r.provider_id, r.source_url, r.source_captured_at, x->'answer' || jsonb_build_object('drop_failing', true));
    if v_chk->>'outcome' in ('propose', 'verified') and v_chk ? 'sentences' then x := jsonb_set(x, '{answer,sentences}', v_chk->'sentences'); end if;
    if v_chk->>'outcome' = 'propose' and r.evidence_id is null then
      v_chk := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'no_evidence', 'reason', 'the page copy is not stored as evidence', 'checks', v_chk->'checks');
    end if;
    if (select p.description from catalogue.providers p where p.id=r.provider_id) is distinct from r.checks->>'description_at_lease' then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule','description_changed_after_lease','reason','The description was edited while this read was in progress; retain the human value.','checks',v_chk->'checks');
    end if;
    if r.checks->'identity_snapshot' is not null and r.checks->'identity_snapshot' is distinct from security.provider_description_identity_snapshot_v1(r.provider_id) then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule','identity_changed_after_lease','reason','Provider names, type, country or website changed after source identity was checked.','checks',v_chk->'checks');
    end if;
    if not security.provider_description_scope_v1(r.provider_id) or exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all')) then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule','provider_eligibility_changed','reason','Provider eligibility or manual lock changed after the read was leased.','checks',v_chk->'checks');
    end if;
    if exists(select 1 from pipeline.provider_description_cohort_members m where m.read_id=r.id and (m.evidence_id is distinct from r.evidence_id or m.snapshot->>'source_hash' is distinct from r.content_hash) and m.evidence_id is not null) then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule','cohort_evidence_changed','reason','The recorded evidence differs from the immutable cohort source. Preview the changed evidence again.','checks',v_chk->'checks');
    end if;
    if x->'quality_hold' is not null then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule',coalesce(x->'quality_hold'->>'rule','worker_quality_hold'),'reason',x->'quality_hold'->>'reason','checks',v_chk->'checks');
    end if;
    v_idc := security.provider_description_identity_v1(r.provider_id,r.source_url); -- once: the same answer was asked for up to three times
    if not (v_idc->>'ok')::boolean then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule',v_idc->>'rule','reason',v_idc->>'reason','checks',v_chk->'checks');
    end if;
    if v_chk->>'outcome' in ('propose','verified') and not coalesce((x->'identity_check'->>'ok')::boolean,(r.checks->'identity'->>'ok')::boolean,false) then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule','source_identity_proof_missing','reason','The worker did not provide current source-identity proof; retain this evidence and retry only through the current approved reader.','checks',v_chk->'checks');
    end if;
    v_chk:=v_chk||jsonb_build_object('checks',coalesce(v_chk->'checks','{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object('identity',x->'identity_check','ai_reservation',x->'ai_reservation','cost_known',x->'cost_known','description_at_lease',r.checks->'description_at_lease','identity_snapshot',r.checks->'identity_snapshot')));
    if v_chk->>'outcome'='propose' and security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then
      -- machine rule pdesc-machine-v1. A description the TEXT rule refuses waits for a person in Layer 4 while there is room (pdesc.machine_pending_max); any other refusal (a lock, an earlier
      -- rejection, a withdrawal, an open finding ...) or no room: HELD with the whole proposal and the exact reason. Nothing is dropped.
      v_m:=security.provider_description_machine_gate_v1(r.provider_id,v_chk->>'text',jsonb_build_object('tier',r.read_via,'sentences',x->'answer'->'sentences'));
      if not (v_m->>'ok')::boolean and (v_m->>'rule' not like 'machine_text%' or (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending')>=security.pipeline_num_v1('pdesc.machine_pending_max',200)) then
        update pipeline.provider_description_reads set state='held',leased_until=null,proposal=jsonb_build_object('description',v_chk->>'text','sentences',x->'answer'->'sentences'),checks=v_chk->'checks',rule='machine_declined_'||(v_m->>'rule'),
          reason=left(v_m->>'reason'||case when v_m->>'rule' like 'machine_text%' then ' Held with the full proposal: the places for a person to decide in Layer 4 are taken (pdesc.machine_pending_max).' else '' end,400),last_verified_at=now(),updated_at=now() where id=r.id; -- fixed: the stored reason shows its first 400 characters
        v_tally:=v_tally||jsonb_build_object('machine_declined',coalesce((v_tally->>'machine_declined')::int,0)+1); continue;
      end if;
    end if;
    if v_chk->>'outcome'='propose' and security.pipeline_num_v1('pdesc.machine_admit_on',0)<1 and (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending')>=security.pipeline_num_v1('pdesc.pending_max',10) then
      -- Keep the complete validated proposal; scheduler resumes this exact evidence without another AI call.
      update pipeline.provider_description_reads set state='held',leased_until=null,proposal=jsonb_build_object('description',v_chk->>'text','sentences',x->'answer'->'sentences'),checks=v_chk->'checks',rule='review_full',reason='Layer 4 provider-description capacity is full; resume automatically when a slot is free',updated_at=now() where id=r.id;
      v_tally:=v_tally||jsonb_build_object('parked',coalesce((v_tally->>'parked')::int,0)+1); continue;
    end if;
    if v_chk->>'outcome' = 'propose' then
      insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
      values ('provider', r.provider_id, 'provider_description', r.evidence_id,
              jsonb_build_object('description', (select nullif(btrim(p.description), '') from catalogue.providers p where p.id = r.provider_id)),
              jsonb_build_object('description', v_chk->>'text', 'sentences', x->'answer'->'sentences', 'source_url', r.source_url, 'evidence_id', r.evidence_id,
                                 'captured_at', r.source_captured_at, 'read_id', r.id),
              jsonb_build_object('read_via', r.read_via, 'content_hash', r.content_hash, 'source_url', r.source_url),
              jsonb_build_object('model', r.model, 'prompt_version', r.prompt_version, 'worker', r.worker, 'cost_usd', r.cost_usd, 'checks', v_chk->'checks', 'rule', v_chk->>'rule'),
              'pending', 'Provider description read from the official page: every sentence quotes the page. A person approves or rejects it; nothing is published before.',
              'CF-247 P1 provider descriptions (Platform Admin 2 Nov 2026 10:28)')
      returning id into v_item;
      update pipeline.provider_description_reads set state = 'proposed', leased_until = null, proposal = jsonb_build_object('description', v_chk->>'text', 'sentences', x->'answer'->'sentences'),
             checks = v_chk->'checks', rule = v_chk->>'rule', reason = null, review_item_id = v_item, last_verified_at = now(), updated_at = now()
       where id = r.id;
      v_out := 'proposed';
      if security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then
        -- admitted here under the machine rule, or left waiting for a person with the reason on the item; a failure never undoes the proposal
        begin
          v_m:=security.provider_description_machine_admit_v1(v_item);
          if (v_m->>'ok')::boolean then v_out:='admitted'; end if;
        exception when others then null;
        end;
      end if;
    elsif v_chk->>'outcome' = 'verified' then
      update pipeline.provider_description_reads set state = 'verified', leased_until = null, proposal = jsonb_build_object('description', v_chk->>'text', 'sentences', x->'answer'->'sentences'),
             checks = v_chk->'checks', rule = v_chk->>'rule', reason = v_chk->>'reason', last_verified_at = now(), updated_at = now()
       where id = r.id;
      v_out := 'verified';
    else
      update pipeline.provider_description_reads set state = 'held', leased_until = null, proposal = jsonb_build_object('sentences', x->'answer'->'sentences'),
             checks = v_chk->'checks', rule = v_chk->>'rule', reason = left(v_chk->>'reason', 400), updated_at = now()
       where id = r.id;
      v_out := 'held';
    end if;
    v_tally := v_tally || jsonb_build_object(v_out, coalesce((v_tally->>v_out)::int, 0) + 1);
  end loop;
  return v_tally;
end $function$
