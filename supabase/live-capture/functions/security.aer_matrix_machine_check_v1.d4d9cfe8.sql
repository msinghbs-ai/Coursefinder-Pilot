CREATE OR REPLACE FUNCTION security.aer_matrix_machine_check_v1(p_item uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.layer4_review_items%rowtype; r pipeline.entry_matrix_runs%rowtype; f pipeline.entry_matrix_sources%rowtype; v_web text; v_sh text; v_ph text; g jsonb;
        v_conf numeric := security.pipeline_num_v1('aer.matrix_machine_min_confidence', 0.9); v_qmin int := security.pipeline_num_v1('aer.machine_min_quote_chars', 8)::int;
        v_pct numeric := security.pipeline_num_v1('aer.matrix_machine_audit_pct', 5); v_nm int; v_nq int; v_bad text; v_checks jsonb; v_ex jsonb; v_exids uuid[] := '{}'::uuid[];
        decline constant text := 'A person decides this in Layer 4 (Approve, Approve except or Reject).';
begin
  select * into i from pipeline.layer4_review_items where id = p_item;
  if i.id is null or i.status <> 'pending' then return jsonb_build_object('ok', false, 'rule', 'item_not_pending', 'reason', 'The item is no longer waiting.'); end if;
  if i.field_code = 'entry_matrix_change' then return jsonb_build_object('ok', false, 'rule', 'change_of_admitted_table', 'reason', 'A change to an admitted table stays with a person.', 'next_action', decline); end if;
  if i.field_code <> 'entry_matrix_first_run' or i.entity_type <> 'provider' then return jsonb_build_object('ok', false, 'rule', 'not_this_class', 'reason', 'Not an entry-matrix first read.'); end if;
  if i.claimed_at is not null or i.assigned_to is not null then return jsonb_build_object('ok', false, 'rule', 'claimed_by_person', 'reason', 'A person has taken this item.'); end if;
  if exists (select 1 from pipeline.layer4_decisions d where d.review_item_id = i.id) then return jsonb_build_object('ok', false, 'rule', 'decided', 'reason', 'The item already has a decision.'); end if;
  select * into r from pipeline.entry_matrix_runs where review_item_id = i.id;
  if r.id is null then return jsonb_build_object('ok', false, 'rule', 'no_run', 'reason', 'No read is linked to this item.', 'next_action', decline); end if;
  select * into f from pipeline.entry_matrix_sources where id = r.source_id;
  v_checks := jsonb_build_object('run_id', r.id, 'source_id', f.id, 'source_url', f.url, 'content_hash', r.content_hash, 'evidence_id', f.evidence_id);
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = i.entity_id and l.field in ('entry_requirements', 'all')) then
    return jsonb_build_object('ok', false, 'rule', 'manual_lock', 'reason', 'The provider''s entry requirements are locked by a person.', 'next_action', decline, 'checks', v_checks); end if;
  -- protected rejection: a person rejected or returned an earlier read of THIS source (a provider that publishes one page per country keeps its other pages on their merits)
  if exists (select 1 from pipeline.layer4_review_items o where o.entity_id = i.entity_id and o.field_code like 'entry_matrix%' and o.id <> i.id
               and o.status in ('rejected', 'more_evidence', 'returned_layer2', 'returned_layer3')
               and (o.layer2_state->>'entry_matrix_source_id' = f.id::text or o.proposed_value->>'url' = f.url)) then
    return jsonb_build_object('ok', false, 'rule', 'earlier_rejection', 'reason', 'A person rejected or returned an earlier entry-matrix read of this source.', 'next_action', decline, 'checks', v_checks); end if;
  if f.evidence_id is null or not exists (select 1 from pipeline.evidence_artifacts e where e.id = f.evidence_id and e.storage_path is not null) then
    return jsonb_build_object('ok', false, 'rule', 'evidence_missing', 'reason', 'The stored copy of the source is missing.', 'next_action', decline, 'checks', v_checks); end if;
  -- 12 Nov 2026 (D3): a copy a person uploaded is not proven to be what the official address serves; it stays with a person
  if f.read_via is null and exists (select 1 from pipeline.aer_source_attachments a where a.source_id = f.id and a.how = 'pdf_upload' and a.content_hash = f.content_hash) then
    return jsonb_build_object('ok', false, 'rule', 'uploaded_copy', 'reason', 'The stored copy was uploaded by a person, not fetched from the official address.', 'next_action', decline, 'checks', v_checks); end if;
  if r.content_hash is distinct from f.content_hash then
    return jsonb_build_object('ok', false, 'rule', 'stale_copy', 'reason', 'The read is not of the source''s current stored copy.', 'next_action', decline, 'checks', v_checks); end if;
  select p.website into v_web from catalogue.providers p where p.id = i.entity_id;
  v_sh := security.site_host_v1(f.url); v_ph := security.site_host_v1(v_web);
  if v_sh is null or v_ph is null or not (v_sh = v_ph or v_sh like '%.' || v_ph) then
    return jsonb_build_object('ok', false, 'rule', 'source_not_official_host', 'reason', format('The source host %s is not the provider''s own website host %s.', coalesce(v_sh, '?'), coalesce(v_ph, '?')),
                              'next_action', decline, 'checks', v_checks); end if;
  if exists (select 1 from catalogue.providers o where o.id <> i.entity_id and o.lifecycle_status = 'active' and security.site_host_v1(o.website) = v_ph) then
    return jsonb_build_object('ok', false, 'rule', 'host_shared', 'reason', 'Another active provider uses the same website host.', 'next_action', decline, 'checks', v_checks); end if;
  -- 12 Nov 2026 (Platform Admin 22:25, machine Approve except): rows that fail a row rule are held back; the gate is judged on the rows admitted
  if security.pipeline_num_v1('aer.matrix_machine_except_on', 0) >= 1 then
    v_ex := security.aer_matrix_machine_exclusions_v1(r.id);
    v_exids := coalesce(array(select jsonb_array_elements_text(v_ex->'ids')::uuid), '{}'::uuid[]);
  end if;
  g := security.entry_matrix_gate_v1(r.id, v_exids);
  if g is not null and not coalesce((g->>'complete')::boolean, true) then
    return jsonb_build_object('ok', false, 'rule', 'gate_incomplete', 'reason', 'The read cannot be shown complete (D-R3).', 'next_action', decline, 'checks', v_checks || jsonb_build_object('gate', g)); end if;
  if coalesce(r.result->'completeness'->>'status', 'missing') in ('incomplete', 'unparsed')
     or (security.entry_completeness_required_v1(i.entity_id) and coalesce(r.result->'completeness'->>'status', 'missing') <> 'complete') then
    return jsonb_build_object('ok', false, 'rule', 'completeness', 'reason', 'The read has not passed the completeness guard.', 'next_action', decline, 'checks', v_checks); end if;
  select count(*) into v_nm from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed';
  select count(*) into v_nq from catalogue.provider_qualification_requirements q where q.run_id = r.id and q.status = 'proposed';
  -- F-AER.08 (12 Nov 2026, decision 1): a read of an aligned PDF grid stays with a person until aer.grid_machine_admission_on (shadow validation first)
  if coalesce(r.result->>'reader', '') = 'pdf-grid-v1' and security.pipeline_num_v1('aer.grid_machine_admission_on', 0) < 1 then
    return jsonb_build_object('ok', false, 'rule', 'grid_reader_shadow', 'reason', 'A read of an aligned PDF grid stays with a person until its first reads are validated (aer.grid_machine_admission_on).',
                              'next_action', decline, 'checks', v_checks); end if;
  if v_ex is not null and v_nm + v_nq > 0 and v_nm + v_nq - cardinality(v_exids) <= 0 then
    return jsonb_build_object('ok', false, 'rule', 'all_rows_held', 'reason', 'Every proposed row fails a row rule, so nothing can be admitted automatically.', 'next_action', decline,
                              'checks', v_checks || jsonb_build_object('held_back_by_rule', v_ex->'by_rule')); end if;
  if v_nm + v_nq = 0 then return jsonb_build_object('ok', false, 'rule', 'no_rows', 'reason', 'The read proposes no row.', 'next_action', decline, 'checks', v_checks); end if;
  -- every row: confidence, quote, destination level, a published minimum (never inferred)
  select x.why into v_bad from (
    select case when coalesce(m.confidence, 0) < v_conf then 'low_confidence' when length(btrim(coalesce(m.quote, ''))) < v_qmin then 'short_quote'
                when m.study_level_id is null then 'level_unmapped'
                when not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null) then 'no_minimum'
                when not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value) then 'minimum_not_in_quote' end why
      from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed'
    union all
    select case when q.applicability = 'unresolved' then 'applicability_unresolved' when coalesce(q.confidence, 0) < v_conf then 'low_confidence'
                when length(btrim(coalesce(q.quote, ''))) < v_qmin then 'short_quote' when q.study_level_id is null then 'level_unmapped'
                when not ((q.min_value is not null and coalesce(q.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(q.min_grade, '')), '') is not null) then 'no_minimum'
                when not security.aer_quote_has_value_v1(q.quote, q.min_grade, q.min_value) then 'minimum_not_in_quote' end
      from catalogue.provider_qualification_requirements q where q.run_id = r.id and q.status = 'proposed') x
   where x.why is not null limit 1;
  if v_bad is not null and v_ex is null then return jsonb_build_object('ok', false, 'rule', 'row_' || v_bad, 'reason', 'At least one proposed row fails ' || v_bad || '.', 'next_action', decline,
                                                       'checks', v_checks || jsonb_build_object('rows', v_nm, 'qualification_rows', v_nq)); end if;
  if v_ex is null and (exists (select 1 from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed' group by m.row_hash having count(*) > 1)
     or exists (select 1 from catalogue.provider_qualification_requirements q where q.run_id = r.id and q.status = 'proposed' group by q.qualification_code, q.level_label having count(*) > 1)) then
    return jsonb_build_object('ok', false, 'rule', 'duplicate_identity', 'reason', 'Two proposed rows share one identity.', 'next_action', decline, 'checks', v_checks); end if;
  if v_ex is null and (exists (select 1 from catalogue.provider_entry_matrix p join catalogue.provider_entry_matrix a on a.row_hash = p.row_hash and a.status = 'active' and a.id <> p.id
              where p.run_id = r.id and p.status = 'proposed' and a.source_id is distinct from r.source_id)
     or exists (select 1 from catalogue.provider_qualification_requirements p join catalogue.provider_qualification_requirements a
                  on a.provider_id = p.provider_id and a.qualification_code = p.qualification_code and a.level_label is not distinct from p.level_label and a.status = 'active'
              where p.run_id = r.id and p.status = 'proposed' and a.source_id is distinct from r.source_id)) then
    return jsonb_build_object('ok', false, 'rule', 'conflicting_active', 'reason', 'A proposed row has the identity of an active row from another source.', 'next_action', decline, 'checks', v_checks); end if;
  v_checks := v_checks || jsonb_build_object('rows', v_nm, 'qualification_rows', v_nq, 'host', v_sh, 'min_confidence', v_conf)
              || case when v_ex is not null then jsonb_build_object('exclude_row_ids', coalesce(v_ex->'ids', '[]'::jsonb), 'held_back', cardinality(v_exids),
                                                                    'held_back_by_rule', coalesce(v_ex->'by_rule', '{}'::jsonb)) else '{}'::jsonb end;
  if abs(hashtext(i.id::text)) % 100 < v_pct then  -- fixed: a per cent sample
    return jsonb_build_object('ok', false, 'audit', true, 'rule', 'audit_sample', 'reason', 'Chosen for the audit sample: a person checks this passing item.', 'next_action', decline, 'checks', v_checks); end if;
  return jsonb_build_object('ok', true, 'rule', case when cardinality(v_exids) > 0 then 'aer-matrix-machine-v1-except' else 'aer-matrix-machine-v1' end, 'checks', v_checks);
end $function$
