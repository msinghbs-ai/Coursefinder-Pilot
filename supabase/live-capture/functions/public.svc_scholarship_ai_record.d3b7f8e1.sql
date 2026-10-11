CREATE OR REPLACE FUNCTION public.svc_scholarship_ai_record(p_queue_id bigint, p_answer jsonb, p_checks jsonb, p_verdict text, p_cost numeric, p_tokens_in integer, p_tokens_out integer, p_seconds numeric, p_error text, p_storage_path text, p_sha256 text, p_final_url text, p_rule_facts jsonb, p_retry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare q pipeline.scholarship_ai_queue%rowtype; v_id bigint; v_ev uuid; v_on boolean; r jsonb; v_why text; v_next text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into q from pipeline.scholarship_ai_queue where id = p_queue_id for update;
  if q.id is null then return jsonb_build_object('ok', false, 'reason', 'no queue item'); end if;
  if p_retry then
    update pipeline.scholarship_ai_queue set state = 'queued', leased_until = null, attempts = greatest(attempts - 1, 0), next_try_at = now() + interval '30 minutes' where id = q.id;
    return jsonb_build_object('ok', true, 'retry', true);
  end if;
  -- a candidate page read live for the first time: its copy and read are recorded on the candidate, as the scheduled reader does
  if q.candidate_id is not null and p_storage_path is not null then
    update pipeline.scholarship_page_candidates set storage_path = p_storage_path, content_hash = p_sha256, final_url = coalesce(p_final_url, final_url), read_at = now(),
           read_status = coalesce(nullif(p_rule_facts->>'read_status', ''), 'read'), next_read_at = now() + interval '90 days', leased_until = null,
           facts = case when p_rule_facts ? 'facts' then p_rule_facts->'facts' else facts end
     where id = q.candidate_id;
  end if;
  if p_storage_path is not null then
    insert into pipeline.evidence_artifacts(source_id, evidence_type, source_url, storage_path, content_hash, mime_type, metadata, capture_version, evidence_group_key)
    values (security.coverage_sweep_source(q.provider_id), 'scholarship_ai_page', coalesce(p_final_url, q.url), p_storage_path, p_sha256, 'application/gzip',
            jsonb_build_object('queue_id', q.id, 'candidate_id', q.candidate_id, 'scholarship_id', q.scholarship_id, 'model', q.model_code, 'worker', 'coverage-sweep scholarship_ai'), 1, 'scholarship_ai:' || q.id)
    returning id into v_ev;
    if q.candidate_id is not null then update pipeline.scholarship_page_candidates set evidence_id = coalesce(evidence_id, v_ev) where id = q.candidate_id; end if;
  end if;
  insert into pipeline.scholarship_ai_extractions(queue_id, model_code, model_identifier, prompt_version, run_kind, job_id, sample_id, candidate_id, scholarship_id, provider_id, url,
         storage_path, content_hash, evidence_id, answer, checks, verdict, cost_usd, tokens_in, tokens_out, seconds, error)
  values (q.id, q.model_code, (select m.model_identifier from pipeline.scholarship_ai_models m where m.code = q.model_code), q.prompt_version, q.run_kind, q.job_id, q.sample_id, q.candidate_id, q.scholarship_id, q.provider_id,
          coalesce(p_final_url, q.url), coalesce(p_storage_path, (select c.storage_path from pipeline.scholarship_page_candidates c where c.id = q.candidate_id)), p_sha256,
          coalesce(v_ev, (select c.evidence_id from pipeline.scholarship_page_candidates c where c.id = q.candidate_id), (select sp.evidence_id from pipeline.scholarship_pages sp where sp.scholarship_id = q.scholarship_id)),
          p_answer, p_checks, p_verdict, p_cost, p_tokens_in, p_tokens_out, p_seconds, p_error)
  returning id into v_id;
  -- v2.15.250 (bugs 11/10-6 follow-up): an unsettled answer (failed reply, name not proven, or a stated fact not proven by its quote)
  -- goes to the next model in the chain, on the same stored copy; after the last model it goes to Layer 4 while AI admission is on
  v_why := case when q.run_kind in ('admit', 'reread') then security.scholarship_ai_unsettled_v1(p_answer, p_checks, p_verdict, p_error) end;
  v_next := case when v_why is not null then security.scholarship_ai_next_model_v1(q.model_code) end;
  if v_next is not null then
    update pipeline.scholarship_ai_queue set state = 'done', done_at = now(), leased_until = null, extraction_id = v_id where id = q.id;
    insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, sample_id, candidate_id, scholarship_id, provider_id, url, step, storage_path, root_id)
    values (v_next, q.prompt_version, q.run_kind, q.job_id, q.sample_id, q.candidate_id, q.scholarship_id, q.provider_id, coalesce(p_final_url, q.url), q.step + 1,
            coalesce(p_storage_path, q.storage_path), coalesce(q.root_id, q.id));
    return jsonb_build_object('ok', true, 'extraction', v_id, 'escalated_to', v_next, 'why', v_why);
  end if;
  update pipeline.scholarship_ai_queue set state = case when p_error is null or attempts >= 3 then 'done' else 'queued' end, done_at = case when p_error is null or attempts >= 3 then now() end,
         leased_until = null, next_try_at = now() + interval '10 minutes', extraction_id = v_id where id = q.id;
  select ai_admission into v_on from pipeline.scholarship_ai_extract_settings where id = 1;
  if v_on and v_why is not null and (p_error is null or q.attempts >= 3) then r := security.scholarship_ai_review_open_v1(v_id, v_why);
  elsif p_error is null and v_on and q.run_kind in ('admit', 'reread') then r := security.scholarship_ai_apply_v1(v_id); end if;
  return jsonb_build_object('ok', true, 'extraction', v_id, 'applied', r);
end $function$
