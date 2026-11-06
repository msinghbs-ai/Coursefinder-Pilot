CREATE OR REPLACE FUNCTION security.course_entry_review_apply_v1(p_item uuid, p_action text, p_final jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.layer4_review_items%rowtype; v_ex uuid[]; v_on int := 0; v_off int := 0; v_sup int := 0; v_enrich bigint; v_gate jsonb;
begin
  select * into r from pipeline.layer4_review_items where id = p_item;
  if r.id is null or r.field_code <> 'course_entry_first_read' then raise exception 'not a course entry review item'; end if;
  v_enrich := nullif(r.proposed_value->>'item_id', '')::bigint;
  if p_action = 'approve' then
    v_ex := coalesce(array(select jsonb_array_elements_text(coalesce(p_final->'exclude_row_ids', '[]'::jsonb))::uuid), '{}');
    -- E13 (Platform Admin 2 Nov 2026 05:18): an incomplete read never reaches approval. Rows cut by the row limit (a joined condition among
    -- them named), a waiting row about another programme that is not left out, or a page shared with another programme hold the whole
    -- decision; nothing is changed
    v_gate := security.course_entry_gate_v1(p_item, v_ex);
    if v_gate is not null and not coalesce((v_gate->>'complete')::boolean, true) then
      raise exception 'Held (E13, incomplete read): %. Nothing was changed',
        (select string_agg(w, '; ') from jsonb_array_elements_text(v_gate->'reasons') w) using errcode = '55000';
    end if;
    -- D4 (Platform Admin 30 Oct 2026 08:45): course rows have no identity key, so an excluded row cannot be matched to the active row it would
    -- replace; Approve except on a course that already has active rows holds the whole decision rather than guess
    if cardinality(v_ex) > 0 and exists (select 1 from catalogue.course_entry_requirements x
                                         where x.course_id = r.entity_id and x.status = 'active' and x.provenance->>'reader' = 'enrich_ai') then
      raise exception 'Held (decision D4): course % has % active entry requirement rows and course rows have no identity to match an excluded row to the row it would replace; nothing was changed. Use Approve all rows if every waiting row is right, or Reject the read',
        r.entity_id, (select count(*) from catalogue.course_entry_requirements x where x.course_id = r.entity_id and x.status = 'active' and x.provenance->>'reader' = 'enrich_ai')
        using errcode = '55000';
    end if;
    update catalogue.course_entry_requirements x set status = 'superseded', status_reason = 'replaced by Layer 4 item ' || p_item, updated_at = now()
     where x.course_id = r.entity_id and x.status = 'active' and x.provenance->>'reader' = 'enrich_ai';
    get diagnostics v_sup = row_count;
    -- A1: an excluded row stays unadmitted and identifiable: inactive, its reason names the item and the reviewer, provenance keeps the record
    update catalogue.course_entry_requirements x set status = 'inactive',
           status_reason = 'excluded by approve except (Layer 4 item ' || p_item::text || ', reviewer ' || coalesce(p_final->>'reviewer', 'unknown') || '): ' || coalesce(p_reason, ''),
           provenance = coalesce(x.provenance, '{}'::jsonb) || jsonb_build_object('aer_exclusion', jsonb_build_object('review_item_id', p_item,
             'enrich_item_id', v_enrich, 'evidence_id', x.evidence_id, 'reviewer', p_final->>'reviewer', 'reason', p_reason, 'at', now(), 'decision', 'approve_except (A1)')),
           updated_at = now()
     where x.provenance->>'review_item_id' = p_item::text and x.status = 'proposed' and x.id = any (v_ex);
    get diagnostics v_off = row_count;
    update catalogue.course_entry_requirements x set status = 'active', status_reason = null, updated_at = now()
     where x.provenance->>'review_item_id' = p_item::text and x.status = 'proposed';
    get diagnostics v_on = row_count;
    update pipeline.field_enrich_items set state = 'filled', updated_at = now() where id = v_enrich and state = 'review';
  else
    update catalogue.course_entry_requirements x set status = 'inactive', status_reason = 'quarantined (' || p_action || '): ' || coalesce(p_reason, ''), updated_at = now()
     where x.provenance->>'review_item_id' = p_item::text and x.status = 'proposed';
    get diagnostics v_off = row_count;
    update pipeline.field_enrich_items set state = 'skipped', reason = 'Layer 4 ' || p_action || ' (not admitted)', updated_at = now() where id = v_enrich and state = 'review';
  end if;
  return jsonb_build_object('course_entry_review', p_item, 'admitted', v_on, 'quarantined', v_off, 'superseded', v_sup);
end $function$

