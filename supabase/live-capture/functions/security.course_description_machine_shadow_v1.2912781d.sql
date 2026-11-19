CREATE OR REPLACE FUNCTION security.course_description_machine_shadow_v1(p_limit integer DEFAULT NULL::integer, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v jsonb; v_lim int := coalesce(p_limit, 200); -- fixed: a report page, the evaluation is the bounded cost
        v_by jsonb := '{}'::jsonb; v_ok int := 0; v_n int := 0; v_sample jsonb := '[]'::jsonb; v_total int; v_prov jsonb := '{}'::jsonb; v_held int; v_held_policy int; hr record;
begin
  select count(*) into v_total from pipeline.layer4_review_items li where li.field_code = 'course_description_first_read' and li.entity_type = 'course' and li.status = 'pending';
  for r in select li.id, li.entity_id from pipeline.layer4_review_items li where li.field_code = 'course_description_first_read' and li.entity_type = 'course' and li.status = 'pending'
            order by li.created_at, li.id limit v_lim offset greatest(coalesce(p_offset, 0), 0) loop
    v := security.course_description_machine_check_v1(r.id);
    v_n := v_n + 1;
    if (v->>'ok')::boolean then
      v_ok := v_ok + 1;
      if jsonb_array_length(v_sample) < 5 then v_sample := v_sample || jsonb_build_array(jsonb_build_object('review_item_id', r.id, 'course_id', r.entity_id, 'chars', length(v->>'text'))); end if;
    else
      v_by := jsonb_set(v_by, array[v->>'rule'], to_jsonb(coalesce((v_by->>(v->>'rule'))::int, 0) + 1));
    end if;
  end loop;
  -- readings held at the provider's waiting cap: not yet items; counted, and how many pass the wording policy alone
  select count(*) into v_held from pipeline.field_enrich_items e where e.field = 'description' and e.state = 'skipped' and e.reason like 'held_first_admission:%' and nullif(btrim(e.value->>'text'), '') is not null;
  select count(*) into v_held_policy from pipeline.field_enrich_items e where e.field = 'description' and e.state = 'skipped' and e.reason like 'held_first_admission:%' and nullif(btrim(e.value->>'text'), '') is not null
     and security.pdesc_machine_text_check_ctx_v1(e.provider_id, e.value->>'text', '{}', coalesce(e.value->'sentences', '[]'::jsonb)) is null;
  return jsonb_build_object('contract', 'course-description-machine-shadow-v1', 'rule', 'cdesc-machine-v2', 'as_at', now(), 'switch_on', security.pipeline_num_v1('enrich.course_description_machine_on', 0) >= 1,
    'waiting_items', v_total, 'examined', v_n, 'offset', greatest(coalesce(p_offset, 0), 0), 'would_admit', v_ok, 'stay_for_a_person', v_n - v_ok, 'by_reason', v_by, 'sample_would_admit', v_sample,
    'held_readings', jsonb_build_object('count', v_held, 'pass_wording_policy', v_held_policy, 'note', 'held at the provider''s waiting cap; promoted to items by the existing promote-held step as room appears, then evaluated like any waiting item'),
    'next_offset', case when greatest(coalesce(p_offset, 0), 0) + v_n < v_total then greatest(coalesce(p_offset, 0), 0) + v_n end);
end $function$
