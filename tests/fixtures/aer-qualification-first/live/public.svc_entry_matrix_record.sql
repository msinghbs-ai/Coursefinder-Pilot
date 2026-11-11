CREATE OR REPLACE FUNCTION public.svc_entry_matrix_record(p_run_id uuid, p_result jsonb, p_cost numeric, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.entry_matrix_runs%rowtype; f pipeline.entry_matrix_sources%rowtype; x jsonb; v_country uuid; v_conf numeric;
        v_min_conf numeric := security.pipeline_num_v1('entry.matrix_min_confidence', 0.85);
        v_in int := 0; v_dropped jsonb := coalesce(p_result->'dropped', '[]'::jsonb); v_item uuid; v_first boolean; v_field text;
        v_all_conf boolean := true;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into r from pipeline.entry_matrix_runs where id = p_run_id for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'unknown run'); end if;
  -- completeness guard (26 Oct 2026): under entry.completeness_providers only a read the worker found complete proposes rows
  if p_error is null and security.entry_completeness_required_v1(r.provider_id) and coalesce(p_result->'completeness'->>'status', 'missing') <> 'complete' then
    p_error := 'held_incomplete: no complete verdict (' || coalesce(p_result->'completeness'->>'status', 'missing') || ')';
  end if;
  if p_error is not null then
    update pipeline.entry_matrix_runs set
           -- a held read is kept whole in the run history; an unreadable page is not read again, an incomplete read is retried within entry.matrix_attempts
           previous_results = case when p_result is null then previous_results
                                   else previous_results || jsonb_build_array(jsonb_build_object('held', p_error like 'held_%', 'reason', left(p_error, 400),
                                          'attempt', attempts, 'model', model_code, 'at', now(), 'result', p_result)) end,
           state = case when p_error like 'held_unparsed%' then 'failed' when p_error = 'time budget' and coalesce(p_cost, 0) = 0 then 'queued' when attempts >= security.pipeline_num_v1('entry.matrix_attempts', 3) then 'failed' else 'queued' end,
           attempts = case when p_error = 'time budget' and coalesce(p_cost, 0) = 0 then greatest(attempts - 1, 0) else attempts end,  -- 29 Oct 2026: a cut read that spent uses a try
           leased_until = null, error = left(p_error, 400), cost_usd = cost_usd + coalesce(p_cost, 0), updated_at = now()
     where id = r.id;
    return jsonb_build_object('ok', true, 'status', 'error');
  end if;
  select * into f from pipeline.entry_matrix_sources where id = r.source_id;
  v_first := not exists (select 1 from catalogue.provider_entry_matrix m where m.provider_id = r.provider_id and m.status = 'active');
  for x in select * from jsonb_array_elements(coalesce(p_result->'rows', '[]'::jsonb)) loop
    select k.id into v_country from ref.countries k where k.iso_alpha2 = upper(x->>'country_code');
    v_conf := nullif(x->>'confidence', '')::numeric;
    if v_country is null then v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'unknown_country', 'country', x->>'country_name')); continue; end if;
    if coalesce(v_conf, 0) < v_min_conf then v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'low_confidence', 'country', x->>'country_code')); continue; end if;
    if nullif(trim(x->>'quote'), '') is null or nullif(trim(x->>'qualification_name'), '') is null then
      v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'missing_quote_or_qualification', 'country', x->>'country_code')); continue; end if;
    if (x->>'min_value') is not null and coalesce(x->>'grade_scale', 'none') = 'none' then
      v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'value_without_scale', 'country', x->>'country_code')); continue; end if;
    insert into catalogue.provider_entry_matrix(provider_id, course_label, matrix_kind, benchmark_band, level_label, study_level_id, country_id, country_code,
             qualification_name, min_grade, min_value, grade_scale, conditions, edition, intake_year, quote, source_url, source_id, evidence_id,
             content_hash, run_id, confidence, status, provenance)
    values (r.provider_id, nullif(trim(x->>'course_name'), ''),
            case when nullif(trim(x->>'course_name'), '') is not null then 'course_minimum' when x->>'grade_scale' = 'rank' then 'rank_band'
                 when nullif(trim(x->>'benchmark_band'), '') is not null then 'band_ladder' else 'provider_minimum' end,
            nullif(trim(x->>'benchmark_band'), ''), nullif(trim(x->>'study_level'), ''), security.entry_level_map_v1(x->>'study_level'),
            v_country, upper(x->>'country_code'), left(trim(x->>'qualification_name'), 300), nullif(trim(x->>'min_grade'), ''),
            (x->>'min_value')::numeric, coalesce(nullif(x->>'grade_scale', ''), 'none'), coalesce(x->'conditions', '{}'::jsonb),
            nullif(trim(p_result->>'edition'), ''), nullif(p_result->>'intake_year', '')::int, left(trim(x->>'quote'), 300), f.url, f.id, f.evidence_id,
            r.content_hash, r.id, v_conf, 'proposed',
            jsonb_build_object('reader', 'entry_ai', 'model', r.model_code, 'run_id', r.id, 'worker', p_result->>'worker', 'prompt', p_result->>'prompt_version'));
    v_in := v_in + 1;
  end loop;
  if v_in > 0 then
    v_field := case when v_first then 'entry_matrix_first_run' else 'entry_matrix_change' end;
    if v_first or security.pipeline_num_v1('entry.matrix_first_run_review', 1) >= 1 then
      insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state,
                                               status, escalation_reason, change_control_ref)
      values ('provider', r.provider_id, v_field, f.evidence_id,
              jsonb_build_object('active_rows', (select count(*) from catalogue.provider_entry_matrix m where m.provider_id = r.provider_id and m.status = 'active')),
              jsonb_build_object('run_id', r.id, 'url', f.url, 'rows', v_in, 'dropped', jsonb_array_length(v_dropped),
                'countries', (select count(distinct m.country_id) from catalogue.provider_entry_matrix m where m.run_id = r.id),
                'sample', (select jsonb_agg(jsonb_build_object('id', m.id, 'country', m.country_code, 'level', m.level_label, 'qualification', m.qualification_name,
                                   'min_grade', m.min_grade, 'scale', m.grade_scale, 'band', m.benchmark_band, 'quote', m.quote) order by m.country_code, m.level_label)
                             from (select * from catalogue.provider_entry_matrix m2 where m2.run_id = r.id order by m2.country_code, m2.level_label limit 12) m)),
              jsonb_build_object('source', 'entry matrix reader', 'page', f.url, 'entry_matrix_source_id', f.id), jsonb_build_object('run_id', r.id, 'model', r.model_code),
              'pending',
              case when v_first then 'Entry matrix first run: a person approves the matrix before any row is admitted (entry.matrix_first_run_review)'
                   else 'Entry matrix page changed: the new reading replaces the admitted rows only on approval' end,
              'CF-CHG-20260915-247')
      returning id into v_item;
    else
      -- changed page, review of changes off: admitted only when every row met the confidence (the first run always went to a person)
      perform security.entry_matrix_review_apply_v1(null, 'approve', null, 'entry.matrix_first_run_review 0: changed page admitted', r.id);
    end if;
  end if;
  update pipeline.entry_matrix_runs set state = 'done', done_at = now(), leased_until = null, error = null, rows_admitted = v_in,
         rows_dropped = jsonb_array_length(v_dropped), slices = nullif(p_result->>'slices', '')::int,
         result = jsonb_build_object('dropped', v_dropped, 'edition', p_result->'edition', 'worker', p_result->'worker',
                                     'prompt_version', p_result->'prompt_version', 'page_basis', p_result->'page_basis', 'completeness', p_result->'completeness'),
         cost_usd = cost_usd + coalesce(p_cost, 0), review_item_id = v_item, updated_at = now()
   where id = r.id;
  -- Step C (29 Oct 2026): a rendered page (entry.render_hosts) read with no row opens a Layer 4 note; a person confirms "no matrix published here"
  if v_in = 0 and f.read_via = 'firecrawl'
     and coalesce(security.toolset_setting('pipeline', 'entry.render_hosts'), '[]'::jsonb) ? lower(substring(f.url from '^https?://(?:www\.)?([^/:?#]+)')) then
    v_item := security.entry_rendered_note_v1(r.id);
  end if;
  return jsonb_build_object('ok', true, 'status', case when v_in = 0 then 'no_rows' when v_item is not null then 'layer4' else 'admitted' end,
                            'rows', v_in, 'dropped', jsonb_array_length(v_dropped), 'review_item_id', v_item);
end $function$
