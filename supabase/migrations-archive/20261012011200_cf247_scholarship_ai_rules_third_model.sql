-- CF-247 v2.15.256 (12 Oct 2026). Platform Admin status review, fix 2: "AI could not decide" held 1,012 pages. Looked at first:
-- (a) about 300 had a value the first model proved, but the confirming model answered with a value it could not prove (often "tiers" with
--     no tiers), so the pair counted as unsettled; (b) scholarships for one nationality ("students from Papua New Guinea") failed because
--     the quote does not say "international" (worker v0.20.3 now accepts a quote naming another country or region); (c) loose
--     "international" claims ("open to all RRU students") are rightly held. Decision: rules + a third model.
-- 1. svc_scholarship_ai_record: a value an earlier model in the same chain proved stands when a later model's value is not proven
--    (the answer records value_from); a later model's own proven value always wins.
-- 2. svc_scholarship_ai_next gives the worker the university's country (for the nationality rule).
-- 3. GPT-4.1 (openai/gpt-4.1, pinned) is added as a candidate and qualified with the current instructions. Qualifying never switches it
--    on: a Platform Admin adds it to the order on Scholarships › Extraction.
-- 4. admin_scholarship_ai('reviews_reread'): the pages waiting in AI could not decide are read again from the first model in the order,
--    on their stored copy (no scraper credit); their reviews are closed as superseded. Run once now.
-- Guarded on the live definitions; nothing dropped.
do $guard$
declare v_expected jsonb := '{"public.svc_scholarship_ai_next(integer)": "a1672720e4fb79fd58cbb59a4ef4c110", "public.svc_scholarship_ai_record(bigint, jsonb, jsonb, text, numeric, integer, integer, numeric, text, text, text, text, jsonb, boolean)": "50169fac6ad9d6abac805a1a2f1e26cb", "public.admin_scholarship_ai(text, jsonb)": "96603a24821563a3ba4990cc641219f9"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

insert into pipeline.scholarship_ai_models(code, model_identifier, label, status, sort, price_note)
values ('gpt-4.1', 'openai/gpt-4.1', 'GPT-4.1', 'candidate', 30, 'about US$0.01 a page; a stronger third reader before Layer 4 (v2.15.256)')
on conflict (code) do nothing;

CREATE OR REPLACE FUNCTION public.svc_scholarship_ai_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select q.id from pipeline.scholarship_ai_queue q
     where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
     order by (q.run_kind = 'test') desc, (q.run_kind = 'qualify') desc, q.step desc, q.id
     limit greatest(1, least(coalesce(p_limit, 8), 20)) for update skip locked),
  upd as (update pipeline.scholarship_ai_queue q set state = 'leased', leased_until = now() + interval '4 minutes', attempts = q.attempts + 1 from pick where q.id = pick.id returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('queue_id', u.id, 'model_code', u.model_code, 'model', m.model_identifier, 'prompt_version', u.prompt_version,
           'prompt', (select p.text from pipeline.scholarship_ai_prompts p where p.version = u.prompt_version), 'run_kind', u.run_kind, 'url', u.url,
           'candidate_id', u.candidate_id, 'scholarship_id', u.scholarship_id, 'provider_id', u.provider_id, 'country', case when u.provider_id is not null then security.coverage_country(u.provider_id) end,  -- v2.15.256
           'provider', (select coalesce(pr.display_name, pr.canonical_name) from catalogue.providers pr where pr.id = u.provider_id),
           'currency', case when u.provider_id is not null then scholarship.provider_currency(u.provider_id) else 'AUD' end,
           'storage_path', coalesce(u.storage_path, (select c.storage_path from pipeline.scholarship_page_candidates c where c.id = u.candidate_id),
                                    (select e.storage_path from pipeline.scholarship_pages sp join pipeline.evidence_artifacts e on e.id = sp.evidence_id where sp.scholarship_id = u.scholarship_id),
                                    (select e.storage_path from scholarship.scholarships s join pipeline.evidence_artifacts e on e.id = s.evidence_id where s.id = u.scholarship_id)))), '[]'::jsonb)
    into v from upd u join pipeline.scholarship_ai_models m on m.code = u.model_code;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_ai_record(p_queue_id bigint, p_answer jsonb, p_checks jsonb, p_verdict text, p_cost numeric, p_tokens_in integer, p_tokens_out integer, p_seconds numeric, p_error text, p_storage_path text, p_sha256 text, p_final_url text, p_rule_facts jsonb, p_retry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare q pipeline.scholarship_ai_queue%rowtype; v_id bigint; v_ev uuid; v_on boolean; r jsonb; v_why text; v_next text; v_prev record;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into q from pipeline.scholarship_ai_queue where id = p_queue_id for update;
  if q.id is null then return jsonb_build_object('ok', false, 'reason', 'no queue item'); end if;
  if p_retry then
    update pipeline.scholarship_ai_queue set state = 'queued', leased_until = null, attempts = greatest(attempts - 1, 0), next_try_at = now() + interval '30 minutes' where id = q.id;
    return jsonb_build_object('ok', true, 'retry', true);
  end if;
  -- v2.15.256: a value an earlier model in this chain proved stands when this model's value is not proven (its own proven value wins)
  if p_error is null and p_verdict = 'scholarship' and not coalesce((p_checks->>'value')::boolean, false)
     and coalesce(p_answer->'value'->>'kind', 'not_stated') not in ('not_stated', 'non_monetary') then
    select e.answer->'value' val, e.model_code into v_prev from pipeline.scholarship_ai_extractions e join pipeline.scholarship_ai_queue x on x.id = e.queue_id
     where coalesce(x.root_id, x.id) = coalesce(q.root_id, q.id) and x.id <> q.id and e.verdict = 'scholarship' and e.error is null
       and coalesce((e.checks->>'value')::boolean, false) order by e.id desc limit 1;
    if v_prev.val is not null then
      p_answer := jsonb_set(p_answer, '{value}', v_prev.val) || jsonb_build_object('value_from', v_prev.model_code);
      p_checks := p_checks || jsonb_build_object('value', true);
    end if;
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
  -- v2.15.250 (23:50): an answer that would admit is confirmed by the next model while confirm_admissions is on
  if v_why is null and q.run_kind in ('admit', 'reread') and p_error is null and p_verdict = 'scholarship' and p_answer->>'audience' in ('international', 'both')
     and coalesce((p_checks->>'audience')::boolean, false) and coalesce(p_answer->>'offered', '') <> 'no'
     and coalesce((select s.confirm_admissions from pipeline.scholarship_ai_extract_settings s where s.id = 1), true)
     and security.scholarship_ai_next_model_v1(q.model_code) is not null then
    v_why := 'a second model confirms each admission';
  end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public.admin_scholarship_ai(p_action text DEFAULT 'read'::text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); a record; v_pv int; v_job uuid; v_n int; v_ids uuid[]; v_chain text[]; v_r jsonb;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into a from security.scholarship_ai_active_v1();
  -- v2.15.250: Layer 4 › AI could not decide (Curators and above): pages neither model could settle, with every answer
  if p_action = 'reviews' then
    return jsonb_build_object('can_decide', true, 'ai_admission', a.ai_admission, 'chain', (select s.chain from pipeline.scholarship_ai_extract_settings s where s.id = 1),
      'pending', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending'),
      'reviews', (select coalesce(jsonb_agg(z.x order by z.at desc), '[]'::jsonb) from (
          select r.created_at at, jsonb_build_object('id', r.id, 'url', r.url, 'reason', r.reason, 'status', r.status, 'created_at', r.created_at, 'decided_at', r.decided_at, 'note', r.note,
                 'provider', (select coalesce(pr.display_name, pr.canonical_name) from catalogue.providers pr where pr.id = r.provider_id), 'candidate_id', r.candidate_id, 'scholarship_id', r.scholarship_id,
                 'scholarship', (select s.name from scholarship.scholarships s where s.id = r.scholarship_id), 'decision', r.decision,
                 'answers', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'model_code', e.model_code, 'answer', e.answer, 'checks', e.checks, 'verdict', e.verdict, 'error', e.error, 'evidence_id', e.evidence_id) order by e.id), '[]'::jsonb)
                               from pipeline.scholarship_ai_extractions e where e.id = any (r.extraction_ids))) x
            from pipeline.scholarship_ai_reviews r
           where case when p_args->>'status' = 'decided' then r.status in ('admitted', 'refused') else r.status = 'pending' end
           order by r.created_at desc limit 200) z),
      'reroutes', (select coalesce(jsonb_object_agg(t.k, t.n), '{}'::jsonb) from (select x.route || ':' || x.field_code k, count(*) n from pipeline.layer4_reroutes x group by 1) t),
      'layer4_course_pending', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending' and i.entity_type = 'course'));
  end if;
  if p_action <> 'read' then
    if v_rank < 6 and p_action <> 'review_decide' then raise exception 'Platform Admin required' using errcode = '42501'; end if;
    if p_action not in ('label', 'test', 'review_decide') and length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    if p_action = 'set_prompt' then
      if length(btrim(coalesce(p_args->>'text', ''))) < 200 then raise exception 'the instructions are too short'; end if;
      update pipeline.scholarship_ai_prompts set active = false where active;
      insert into pipeline.scholarship_ai_prompts(text, active, reason, created_by) values (p_args->>'text', true, v_reason, auth.uid());
      -- new instructions: the active model must be qualified again before it admits anything
      if a.ai_admission then update pipeline.scholarship_ai_extract_settings set ai_admission = false, changed_by = auth.uid(), changed_at = now(), reason = 'instructions changed: qualify again before switching on' where id = 1; end if;
    elsif p_action = 'label' then
      if v_rank < 6 then raise exception 'Platform Admin required'; end if;
      if p_args ? 'sample_id' then
        update pipeline.scholarship_ai_sample set expected = coalesce(p_args->'expected', expected), active = coalesce((p_args->>'active')::boolean, active), note = coalesce(p_args->>'note', note), label_source = 'Platform Admin ' || to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI') where id = (p_args->>'sample_id')::int;
      else
        insert into pipeline.scholarship_ai_sample(url, provider_id, expected, label_source, note, added_by)
        values (btrim(p_args->>'url'), nullif(p_args->>'provider_id', '')::uuid, coalesce(p_args->'expected', '{}'::jsonb), 'Platform Admin ' || to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'), p_args->>'note', auth.uid())
        on conflict (url) do update set expected = excluded.expected, active = true, note = excluded.note, label_source = excluded.label_source;
      end if;
    elsif p_action = 'qualify' then
      if not exists (select 1 from pipeline.scholarship_ai_models m where m.code = p_args->>'model_code' and m.status <> 'retired') then raise exception 'choose a model'; end if;
      v_pv := coalesce(a.prompt_version, 1);
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
      values ('scholarship_ai_qualify', 'scholarship_ai:qualify:' || (p_args->>'model_code'), 'Qualify the scholarship AI: ' || (select m.label from pipeline.scholarship_ai_models m where m.code = p_args->>'model_code') || ' (instructions v' || v_pv || ')',
              jsonb_build_object('model_code', p_args->>'model_code', 'prompt_version', v_pv), jsonb_build_object('done', 0, 'total', (select count(*) from pipeline.scholarship_ai_sample where active)), auth.uid(), v_reason, p_args->>'model_code')
      returning id into v_job;
      insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, sample_id, candidate_id, scholarship_id, provider_id, url)
      select p_args->>'model_code', v_pv, 'qualify', v_job, s.id, s.candidate_id, s.scholarship_id, s.provider_id, s.url from pipeline.scholarship_ai_sample s where s.active;
      insert into pipeline.admin_job_events(job_id, note, detail) values (v_job, 'queued by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), ''), jsonb_build_object('reason', v_reason));
      perform security.scholarship_ai_fire_v1();
    elsif p_action = 'activate' then
      if not exists (select 1 from pipeline.admin_jobs j where j.kind = 'scholarship_ai_qualify' and j.state = 'done' and j.args->>'model_code' = p_args->>'model_code' and (j.args->>'prompt_version')::int = a.prompt_version) then
        raise exception 'qualify this model with the current instructions first';
      end if;
      update pipeline.scholarship_ai_models set status = 'candidate' where status = 'active';
      update pipeline.scholarship_ai_models set status = 'active', activated_at = now(), activated_by = auth.uid(), reason = v_reason where code = p_args->>'model_code';
      update pipeline.scholarship_ai_extract_settings set chain = array[p_args->>'model_code'] where id = 1;
    -- v2.15.250 (23:50): whether the next model confirms each admission by the first
    elsif p_action = 'set_confirm' then
      update pipeline.scholarship_ai_extract_settings set confirm_admissions = coalesce((p_args->>'on')::boolean, true), changed_by = auth.uid(), changed_at = now(), reason = v_reason where id = 1;
    elsif p_action = 'set_admission' then
      if coalesce((p_args->>'on')::boolean, false) and a.model_code is null then raise exception 'make a qualified model active first'; end if;
      update pipeline.scholarship_ai_extract_settings set ai_admission = coalesce((p_args->>'on')::boolean, false), changed_by = auth.uid(), changed_at = now(), reason = v_reason where id = 1;
    elsif p_action = 'backfill' then
      if a.model_code is null then raise exception 'make a qualified model active first'; end if;
      v_ids := case when p_args->>'scope' = 'watch' then array(select w.provider_id from pipeline.scholarship_watch w where w.active)
                    else array(select x::uuid from jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) x) end;
      if coalesce(cardinality(v_ids), 0) = 0 then raise exception 'choose universities'; end if;
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
      values ('scholarship_ai_backfill', 'scholarship_ai:backfill', 'Re-check scholarship pages with AI: ' || case when p_args->>'scope' = 'watch' then 'watch list (' || cardinality(v_ids) || ')' else cardinality(v_ids) || ' universities' end,
              jsonb_build_object('providers', to_jsonb(v_ids), 'model_code', a.model_code, 'prompt_version', a.prompt_version), jsonb_build_object('done', 0, 'total', 0), auth.uid(), v_reason, 'backfill:' || md5(array_to_string(v_ids, ',')))
      returning id into v_job;
      v_n := security.scholarship_ai_enqueue_v1('admit', v_ids, v_job, true);
      update pipeline.admin_jobs set progress = jsonb_build_object('done', 0, 'total', v_n) where id = v_job;
      insert into pipeline.admin_job_events(job_id, note, detail) values (v_job, 'queued by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), '') || ': ' || v_n || ' page(s)', jsonb_build_object('reason', v_reason));
    elsif p_action = 'test' then
      if a.model_code is null and coalesce(p_args->>'model_code', '') = '' then raise exception 'choose a model'; end if;
      insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, url, provider_id)
      values (coalesce(nullif(p_args->>'model_code', ''), a.model_code), coalesce(a.prompt_version, 1), 'test', btrim(p_args->>'url'), nullif(p_args->>'provider_id', '')::uuid);
      perform security.scholarship_ai_fire_v1();
    -- v2.15.250: the models read in this order; each must be qualified with the current instructions
    elsif p_action = 'set_chain' then
      v_chain := array(select jsonb_array_elements_text(coalesce(p_args->'models', '[]'::jsonb)));
      if cardinality(v_chain) = 0 or cardinality(v_chain) > 3 then raise exception 'choose one to three models, in order'; end if;
      if (select count(distinct x) from unnest(v_chain) x) <> cardinality(v_chain) or 'person' = any (v_chain) then raise exception 'each model can be in the chain once'; end if;
      if exists (select 1 from unnest(v_chain) x where not exists (select 1 from pipeline.admin_jobs j where j.kind = 'scholarship_ai_qualify' and j.state = 'done' and j.args->>'model_code' = x and (j.args->>'prompt_version')::int = a.prompt_version)) then
        raise exception 'qualify every model in the chain with the current instructions first';
      end if;
      update pipeline.scholarship_ai_models set status = 'candidate' where status = 'active';
      update pipeline.scholarship_ai_models set status = 'active', activated_at = now(), activated_by = auth.uid(), reason = v_reason where code = v_chain[1];
      update pipeline.scholarship_ai_extract_settings set chain = v_chain, changed_by = auth.uid(), changed_at = now(), reason = v_reason where id = 1;
    -- v2.15.250: scholarships parked as not published or held are read again by the AI (Layer 4 scholarship items are rerouted)
    elsif p_action = 'reroute_parked' then
      if a.model_code is null then raise exception 'set the model chain first'; end if;
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
      values ('scholarship_ai_backfill', 'scholarship_ai:backfill', 'Re-read parked scholarships with AI', jsonb_build_object('parked', true, 'model_code', a.model_code, 'prompt_version', a.prompt_version),
              jsonb_build_object('done', 0, 'total', 0), auth.uid(), v_reason, 'parked:' || to_char(now(), 'YYYYMMDDHH24MISS'))
      returning id into v_job;
      v_r := security.scholarship_ai_reroute_parked_v1(v_job);
      update pipeline.admin_jobs set progress = jsonb_build_object('done', 0, 'total', (v_r->>'queued')::int) where id = v_job;
      insert into pipeline.admin_job_events(job_id, note, detail) values (v_job, 'queued by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), '') || ': ' || (v_r->>'queued') || ' parked scholarship page(s); '
             || (v_r->>'layer4_items') || ' Layer 4 scholarship item(s) rerouted', v_r || jsonb_build_object('reason', v_reason));
    -- v2.15.256: the pages waiting in AI could not decide are read again from the first model in the order, on their stored copy
    elsif p_action = 'reviews_reread' then
      if a.model_code is null then raise exception 'set the model chain first'; end if;
      insert into pipeline.admin_jobs(kind, lane, title, args, progress, requested_by, reason, scope)
      values ('scholarship_ai_backfill', 'scholarship_ai:backfill', 'Read the AI could not decide pages again', jsonb_build_object('reviews', true, 'model_code', a.model_code, 'prompt_version', a.prompt_version),
              jsonb_build_object('done', 0, 'total', 0), auth.uid(), v_reason, 'reviews:' || to_char(now(), 'YYYYMMDDHH24MISS'))
      returning id into v_job;
      with rv as (
        update pipeline.scholarship_ai_reviews r set status = 'superseded', decided_at = now(), decided_by = auth.uid(), note = 'Read again from the first model (' || v_reason || ')'
         where r.status = 'pending' returning r.*)
      insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, candidate_id, scholarship_id, provider_id, url, storage_path)
      select a.model_code, a.prompt_version, case when rv.scholarship_id is not null then 'reread' else 'admit' end, v_job, rv.candidate_id, rv.scholarship_id, rv.provider_id, rv.url, rv.storage_path
        from rv where not exists (select 1 from pipeline.scholarship_ai_queue q where q.state in ('queued', 'leased')
                                   and (q.candidate_id = rv.candidate_id or q.scholarship_id = rv.scholarship_id));
      get diagnostics v_n = row_count;
      update pipeline.admin_jobs set progress = jsonb_build_object('done', 0, 'total', v_n) where id = v_job;
      insert into pipeline.admin_job_events(job_id, note, detail) values (v_job, 'queued by ' || coalesce((select u.email from auth.users u where u.id = auth.uid()), '') || ': ' || v_n || ' page(s) read again', jsonb_build_object('reason', v_reason));
      perform security.scholarship_ai_fire_v1();
      v_r := jsonb_build_object('queued', v_n);
    -- v2.15.250: a person decides a page neither model could settle (Curators and above); the decision is kept as an exception
    elsif p_action = 'review_decide' then
      if p_args->>'decision' = 'refuse' and length(v_reason) < 4 then raise exception 'give a reason for refusing (kept in the log)'; end if;
      v_r := security.scholarship_ai_review_apply_v1((p_args->>'review_id')::bigint, p_args->>'decision', nullif(p_args->>'extraction_id', '')::bigint, nullif(v_reason, ''), auth.uid());
    else raise exception 'unknown action';
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('scholarship_ai', p_action, coalesce(p_args->>'model_code', p_args->>'sample_id', p_args->>'url', ''), p_args - 'text', auth.uid());
    select * into a from security.scholarship_ai_active_v1();
  end if;
  return jsonb_build_object(
    'can_manage', v_rank >= 6, 'ai_admission', a.ai_admission, 'active_model', a.model_code, 'prompt_version', a.prompt_version,
    'chain', (select s.chain from pipeline.scholarship_ai_extract_settings s where s.id = 1), 'reviews_pending', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending'), 'applied', v_r,
    'settings', (select to_jsonb(s) - 'id' from pipeline.scholarship_ai_extract_settings s where s.id = 1),
    'models', (select jsonb_agg(to_jsonb(m) - 'activated_by' order by m.sort) from pipeline.scholarship_ai_models m where m.code <> 'person'),
    'prompts', (select jsonb_agg(jsonb_build_object('version', p.version, 'active', p.active, 'reason', p.reason, 'at', p.created_at, 'text', case when p.active then p.text end) order by p.version desc) from pipeline.scholarship_ai_prompts p),
    'scores', security.scholarship_ai_scores_v1(a.prompt_version),
    'qualify_runs', (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'model_code', j.args->>'model_code', 'prompt_version', j.args->>'prompt_version', 'state', j.state, 'progress', j.progress, 'at', j.created_at, 'finished_at', j.finished_at) order by j.created_at desc), '[]'::jsonb)
                      from (select * from pipeline.admin_jobs j where j.kind = 'scholarship_ai_qualify' order by j.created_at desc limit 10) j),
    'sample', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'url', s.url, 'expected', s.expected, 'label_source', s.label_source, 'note', s.note, 'active', s.active,
                 'provider', (select coalesce(pr.display_name, pr.canonical_name) from catalogue.providers pr where pr.id = s.provider_id),
                 'answers', (select coalesce(jsonb_object_agg(e.model_code, jsonb_build_object('answer', e.answer, 'checks', e.checks, 'verdict', e.verdict, 'error', e.error, 'evidence_id', e.evidence_id, 'cost', e.cost_usd)), '{}'::jsonb)
                               from (select distinct on (e.model_code) e.* from pipeline.scholarship_ai_extractions e where e.sample_id = s.id and e.prompt_version = a.prompt_version order by e.model_code, e.at desc) e))
                 order by s.id), '[]'::jsonb) from pipeline.scholarship_ai_sample s),
    'queue', (select jsonb_build_object('waiting', count(*) filter (where q.state in ('queued', 'leased')), 'done_today', count(*) filter (where q.state = 'done' and q.done_at > date_trunc('day', now()))) from pipeline.scholarship_ai_queue q),
    'cost_today', (select round(coalesce(sum(e.cost_usd), 0), 4) from pipeline.scholarship_ai_extractions e where e.at > date_trunc('day', now())),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'at', e.at, 'url', e.url, 'model_code', e.model_code, 'run_kind', e.run_kind, 'verdict', e.verdict, 'error', e.error, 'answer', e.answer, 'checks', e.checks,
                 'applied', e.applied, 'evidence_id', e.evidence_id, 'cost', e.cost_usd, 'provider', (select coalesce(pr.display_name, pr.canonical_name) from catalogue.providers pr where pr.id = e.provider_id)) order by e.at desc), '[]'::jsonb)
               from (select * from pipeline.scholarship_ai_extractions e where e.sample_id is null order by e.at desc limit 40) e));
end $function$;

-- qualify GPT-4.1 now (as the Platform Admin who asked); qualifying never adds it to the order or switches anything on
do $q$ begin
  perform set_config('request.jwt.claims', '{"sub":"63ba56cb-48d4-4169-98c2-7c4d1f72925b","role":"authenticated"}', true);
  perform public.admin_scholarship_ai('qualify', jsonb_build_object('model_code', 'gpt-4.1', 'reason', 'Platform Admin 12 Oct 2026 13:06 status review, fix 2: a stronger third reader before Layer 4'));
  perform public.admin_scholarship_ai('reviews_reread', jsonb_build_object('reason', 'Platform Admin 12 Oct 2026 status review, fix 2: read again with the v2.15.256 rules (proven value stands; nationality proves international)'));
  perform set_config('request.jwt.claims', '', true);
end $q$;

do $post$
declare v_expected jsonb := '{"public.svc_scholarship_ai_next(integer)": "e8154195063bc519ecef412d487d958f", "public.svc_scholarship_ai_record(bigint, jsonb, jsonb, text, numeric, integer, integer, numeric, text, text, text, text, jsonb, boolean)": "46ed31a16023e656f790e3e8633e7ccb", "public.admin_scholarship_ai(text, jsonb)": "fba8a1f36f2deb75ab92e43f9c5f2927"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.256 AI post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
