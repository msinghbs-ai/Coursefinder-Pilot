CREATE OR REPLACE FUNCTION security.aer_review_read_v1(p_item uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := coalesce(security.current_role_rank(), 0); i pipeline.layer4_review_items%rowtype; r pipeline.entry_matrix_runs%rowtype; v_rows jsonb;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into i from pipeline.layer4_review_items where id = p_item;
  if i.id is null or not (i.field_code = any (security.aer_review_kinds_v1())) then raise exception 'not an AER review item' using errcode = '22023'; end if;
  if i.field_code = 'course_entry_first_read' then
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'status', x.status, 'status_reason', x.status_reason, 'kind', x.kind, 'audience', x.audience,
             'description', x.description, 'min_grade', x.min_grade, 'scale', x.grade_scale, 'score', x.min_entry_score, 'basis', x.min_entry_score_basis,
             'band', x.benchmark_band, 'quote', x.quote, 'evidence_id', x.evidence_id) order by x.kind, x.created_at, x.id), '[]'::jsonb)
      into v_rows from catalogue.course_entry_requirements x where x.provenance->>'review_item_id' = p_item::text;
  else
    select * into r from pipeline.entry_matrix_runs where review_item_id = p_item;
    select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'status', m.status, 'status_reason', m.status_reason, 'country', m.country_code,
             'level', m.level_label, 'qualification', m.qualification_name, 'course', m.course_label, 'course_linked', m.course_id is not null, 'band', m.benchmark_band, 'min_grade', m.min_grade, 'scale', m.grade_scale,
             'quote', m.quote, 'evidence_id', m.evidence_id, 'content_hash', m.content_hash) order by m.country_code, m.level_label, m.qualification_name, m.id), '[]'::jsonb)
      into v_rows from catalogue.provider_entry_matrix m
     where (r.id is not null and m.run_id = r.id) or m.provenance->'aer_exclusion'->>'review_item_id' = p_item::text;
  end if;
  return jsonb_build_object('review_item_id', i.id, 'kind', i.field_code, 'status', i.status, 'can_decide', v_rank >= 6,
    'provider_id', (select case when li.entity_type = 'provider' then li.entity_id end from pipeline.layer4_review_items li where li.id = p_item),
    'lineage', security.aer_review_lineage_v1(p_item), 'rows', v_rows,
    -- E13: a course entry read's completeness (rows cut by the row limit, rows about another programme, a shared page); approval is held while incomplete
    'completeness_gate', case when i.field_code = 'course_entry_first_read' then security.course_entry_gate_v1(i.id)
                              -- D-R3: a matrix run's whole-read completeness; approval is held while incomplete
                              else security.entry_matrix_gate_v1((select x.id from pipeline.entry_matrix_runs x where x.review_item_id = i.id)) end,
    -- D-R2: the read this item replaced (with the reviewer's diff), and for a replaced item the item that replaced it
    'supersedes', i.proposed_value->'supersedes',
    'superseded_by', (select jsonb_build_object('review_item_id', s.new_item_id, 'at', s.closed_at, 'reason', s.reason) from pipeline.aer_read_supersessions s
                       where s.old_item_id = i.id and s.state = 'superseded' order by s.closed_at desc limit 1),
    'evidence_id', coalesce(i.evidence_id, (select (v->>'evidence_id')::uuid from jsonb_array_elements(v_rows) v where v->>'evidence_id' is not null limit 1)),
    'decision', (select jsonb_build_object('action', d.action, 'reason', d.reason, 'at', d.created_at, 'exclude_row_ids', d.final_value->'exclude_row_ids')
                   from pipeline.layer4_decisions d where d.review_item_id = i.id order by d.created_at desc limit 1));
end $function$
