-- Forward recovery for migration 20261112060000_cf247_aer_qualification_first (F-AER.03). Paste in the SQL editor (Platform Admin) or apply as a new migration.
-- Restores public.svc_entry_matrix_record and security.entry_matrix_review_apply_v1 to their bodies before the change (md5 3e76d77b... and 6d7b47fe...), byte for byte (the
-- same guarded edits, reversed), and switches qualification-first off. The tables, their rows, the settings and the reads are kept (nothing is dropped or deleted).
-- A quicker reversal without code: reading.entry_qualification_first_on 0 on Settings > Pipeline settings.

do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('public.svc_entry_matrix_record(uuid,jsonb,numeric,text)', '7eee2ef2229520266fd56c8aa8f1f1fb', '3e76d77b83bc8c1f9514b40f7cb4ac3e',
     array[$o$        v_all_conf boolean := true;$o$,
           $o$    v_in := v_in + 1;
  end loop;
  if v_in > 0 then$o$,
           $o$              jsonb_build_object('run_id', r.id, 'url', f.url, 'rows', v_in, 'dropped', jsonb_array_length(v_dropped),$o$,
           $o$'page_basis', p_result->'page_basis', 'completeness', p_result->'completeness'),$o$,
           $o$  if v_in = 0 and f.read_via = 'firecrawl'$o$,
           $o$  return jsonb_build_object('ok', true, 'status', case when v_in = 0 then 'no_rows' when v_item is not null then 'layer4' else 'admitted' end,
                            'rows', v_in, 'dropped', jsonb_array_length(v_dropped), 'review_item_id', v_item);$o$],
     array[$n$        v_all_conf boolean := true;
        v_qin int := 0; v_qx jsonb; v_qcode text;  -- 12 Nov 2026 (F-AER.03): qualification rows$n$,
           $n$    v_in := v_in + 1;
  end loop;
  -- 12 Nov 2026 (F-AER.03 qualification-first): rows the reader kept for a recognised international qualification that name no country of education are recorded
  -- beside the matrix with their identity and applicability, on the same Layer 4 item; an unrecognised qualification is dropped (unknown_qualification)
  if security.pipeline_num_v1('reading.entry_qualification_first_on', 0) >= 1 then
    for v_qx in select * from jsonb_array_elements(coalesce(p_result->'qualification_rows', '[]'::jsonb)) loop
      select q.code into v_qcode from ref.aer_qualifications q where q.code = v_qx->>'qualification_code' and q.scope = 'international';
      v_conf := nullif(v_qx->>'confidence', '')::numeric;
      if v_qcode is null then v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'unknown_qualification', 'country', v_qx->>'country_token', 'qualification', v_qx->>'qualification_name')); continue; end if;
      if coalesce(v_conf, 0) < v_min_conf then v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'low_confidence', 'qualification', v_qcode)); continue; end if;
      if nullif(trim(v_qx->>'quote'), '') is null then v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'missing_quote_or_qualification', 'qualification', v_qcode)); continue; end if;
      if (v_qx->>'min_value') is not null and coalesce(v_qx->>'grade_scale', 'none') = 'none' then
        v_dropped := v_dropped || jsonb_build_array(jsonb_build_object('reason', 'value_without_scale', 'qualification', v_qcode)); continue; end if;
      insert into catalogue.provider_qualification_requirements(provider_id, qualification_code, qualification_label, applicability, level_label, study_level_id, min_grade, min_value,
               grade_scale, conditions, quote, source_url, source_id, evidence_id, content_hash, run_id, confidence, status, provenance)
      values (r.provider_id, v_qcode, left(coalesce(nullif(trim(v_qx->>'qualification_name'), ''), v_qcode), 300),
              case when v_qx->>'applicability' = 'global' then 'global' else 'unresolved' end,
              nullif(trim(v_qx->>'study_level'), ''), security.entry_level_map_v1(v_qx->>'study_level'), nullif(trim(v_qx->>'min_grade'), ''), (v_qx->>'min_value')::numeric,
              coalesce(nullif(v_qx->>'grade_scale', ''), 'none'), coalesce(v_qx->'conditions', '{}'::jsonb), left(trim(v_qx->>'quote'), 300), f.url, f.id, f.evidence_id,
              r.content_hash, r.id, v_conf, 'proposed',
              jsonb_build_object('reader', 'entry_ai', 'model', r.model_code, 'run_id', r.id, 'worker', p_result->>'worker', 'prompt', p_result->>'prompt_version',
                                 'country_token', v_qx->>'country_token', 'applicability_basis', v_qx->>'applicability_basis'));
      v_qin := v_qin + 1;
    end loop;
  end if;
  if v_in + v_qin > 0 then$n$,
           $n$              jsonb_build_object('run_id', r.id, 'url', f.url, 'rows', v_in, 'dropped', jsonb_array_length(v_dropped),
                'qualification_rows', v_qin,
                'qualification_sample', (select jsonb_agg(jsonb_build_object('id', q.id, 'qualification', q.qualification_code, 'label', q.qualification_label, 'applicability', q.applicability,
                                   'level', q.level_label, 'min_grade', q.min_grade, 'min_value', q.min_value, 'scale', q.grade_scale, 'quote', q.quote) order by q.qualification_code, q.level_label)
                             from (select * from catalogue.provider_qualification_requirements q2 where q2.run_id = r.id order by q2.qualification_code, q2.level_label limit 12) q),$n$,
           $n$'page_basis', p_result->'page_basis', 'completeness', p_result->'completeness', 'qualification_rows', v_qin),$n$,
           $n$  if v_in + v_qin = 0 and f.read_via = 'firecrawl'$n$,
           $n$  return jsonb_build_object('ok', true, 'status', case when v_in + v_qin = 0 then 'no_rows' when v_item is not null then 'layer4' else 'admitted' end,
                            'rows', v_in, 'qualification_rows', v_qin, 'dropped', jsonb_array_length(v_dropped), 'review_item_id', v_item);$n$]),
    ('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', 'c46ef6d3f9820c3d4d822846909e35ce', '6d7b47fe7d2cd40b9cfb8f3547bad158',
     array[$o$declare r pipeline.entry_matrix_runs%rowtype; v_ex uuid[]; v_on int := 0; v_off int := 0; v_sup int := 0; v_map jsonb; v_ret int := 0; v_gate jsonb;$o$,
           $o$    update catalogue.provider_entry_matrix m set status = 'active', status_reason = null, updated_at = now()
     where m.run_id = r.id and m.status = 'proposed';
    get diagnostics v_on = row_count;$o$,
           $o$    update catalogue.provider_entry_matrix m set status = 'inactive', status_reason = 'quarantined (' || p_action || '): ' || coalesce(p_reason, ''), updated_at = now()
     where m.run_id = r.id and m.status = 'proposed';
    get diagnostics v_off = row_count;$o$,
           $o$  return jsonb_build_object('entry_matrix_run', r.id, 'admitted', v_on, 'quarantined', v_off, 'superseded', v_sup)$o$],
     array[$n$declare r pipeline.entry_matrix_runs%rowtype; v_ex uuid[]; v_on int := 0; v_off int := 0; v_sup int := 0; v_map jsonb; v_ret int := 0; v_gate jsonb;
        v_qon int := 0; v_qoff int := 0; v_qsup int := 0;  -- 12 Nov 2026 (F-AER.03): qualification rows of the read$n$,
           $n$    update catalogue.provider_entry_matrix m set status = 'active', status_reason = null, updated_at = now()
     where m.run_id = r.id and m.status = 'proposed';
    get diagnostics v_on = row_count;
    -- 12 Nov 2026 (F-AER.03): the read's qualification rows follow the same decision: a row left out stays out; an earlier active row of this source for the same
    -- qualification is replaced by the approved one; the rest become active
    update catalogue.provider_qualification_requirements q set status = 'inactive',
           status_reason = 'excluded by approve except (Layer 4 item ' || coalesce(p_item, r.review_item_id)::text || '): ' || coalesce(p_reason, ''), updated_at = now()
     where q.run_id = r.id and q.status = 'proposed' and q.id = any(v_ex);
    update catalogue.provider_qualification_requirements a set status = 'superseded', status_reason = 'replaced by run ' || r.id, updated_at = now()
     where a.provider_id = r.provider_id and a.source_id = r.source_id and a.status = 'active' and a.run_id is distinct from r.id
       and exists (select 1 from catalogue.provider_qualification_requirements p where p.run_id = r.id and p.status = 'proposed' and p.qualification_code = a.qualification_code);
    get diagnostics v_qsup = row_count;
    update catalogue.provider_qualification_requirements q set status = 'active', status_reason = null, updated_at = now() where q.run_id = r.id and q.status = 'proposed';
    get diagnostics v_qon = row_count;$n$,
           $n$    update catalogue.provider_entry_matrix m set status = 'inactive', status_reason = 'quarantined (' || p_action || '): ' || coalesce(p_reason, ''), updated_at = now()
     where m.run_id = r.id and m.status = 'proposed';
    get diagnostics v_off = row_count;
    update catalogue.provider_qualification_requirements q set status = 'inactive', status_reason = 'quarantined (' || p_action || '): ' || coalesce(p_reason, ''), updated_at = now()
     where q.run_id = r.id and q.status = 'proposed';
    get diagnostics v_qoff = row_count;$n$,
           $n$  return jsonb_build_object('entry_matrix_run', r.id, 'admitted', v_on, 'quarantined', v_off, 'superseded', v_sup)
         || jsonb_build_object('qualification_admitted', v_qon, 'qualification_quarantined', v_qoff, 'qualification_superseded', v_qsup)$n$])
  ) v(sig, md5_before, md5_after, news, olds) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then raise notice '%: already applied', r.sig; continue; end if;
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
    raise notice '%: applied', r.sig;
  end loop;
end $m$;

update pipeline.platform_toolset_settings set value = to_jsonb(0), reason = 'F-AER.03 forward recovery: qualification-first off', updated_at = now()
 where toolset_key = 'pipeline' and key = 'reading.entry_qualification_first_on';
