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
end $function$
