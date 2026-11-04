CREATE OR REPLACE FUNCTION security.no_page_review_apply_v1(p_item uuid, p_action text, p_final jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t pipeline.no_page_trust%rowtype; v_sample int; v_has uuid[]; v_conf int; v_trusted boolean;
begin
  select * into t from pipeline.no_page_trust where review_item_id = p_item for update;
  if t.provider_id is null then raise exception 'no first run for this review item'; end if;
  if t.kind = 'no_page' then
    select count(*) into v_sample from pipeline.course_no_page where review_item_id = p_item;
    v_has := coalesce(array(select jsonb_array_elements_text(coalesce(p_final->'has_page_course_ids', '[]'::jsonb))::uuid), '{}');
    if p_action = 'approve' then
      update pipeline.course_no_page set state = case when course_id = any (v_has) then 'rejected' else 'confirmed' end, decided_at = now(), updated_at = now(),
             basis = basis || jsonb_build_object('decided', p_reason) where review_item_id = p_item;
      v_conf := v_sample - (select count(*) from pipeline.course_no_page where review_item_id = p_item and state = 'rejected');
      v_trusted := v_sample > 0 and v_conf::numeric / v_sample >= security.pipeline_num_v1('bind.no_page_trust_pct', 0.6);
    else
      update pipeline.course_no_page set state = 'rejected', decided_at = now(), updated_at = now(), basis = basis || jsonb_build_object('decided', p_reason)
       where review_item_id = p_item and state = 'proposed';
      v_conf := 0; v_trusted := false;
    end if;
    update pipeline.no_page_trust set state = case when v_trusted then 'trusted' else 'not_trusted' end, sample = v_sample, confirmed = v_conf, decided_at = now()
     where provider_id = t.provider_id and kind = 'no_page';
    return jsonb_build_object('no_page', true, 'sample', v_sample, 'confirmed', v_conf, 'trusted', v_trusted);
  else
    if p_action = 'approve' then
      update pipeline.no_page_trust set state = 'trusted', decided_at = now(), parent_url = coalesce(nullif(p_final->>'parent_url', ''), parent_url)
       where provider_id = t.provider_id and kind = 'conjoint';
      update pipeline.course_no_page set state = 'conjoint', decided_at = now(), updated_at = now(),
             basis = basis || jsonb_build_object('decided', p_reason, 'parent_url', coalesce(nullif(p_final->>'parent_url', ''), t.parent_url)) where review_item_id = p_item;
    else
      update pipeline.no_page_trust set state = 'not_trusted', decided_at = now() where provider_id = t.provider_id and kind = 'conjoint';
      update pipeline.course_no_page set state = 'rejected', decided_at = now(), updated_at = now(), basis = basis || jsonb_build_object('decided', p_reason)
       where review_item_id = p_item and state = 'proposed';
    end if;
    return jsonb_build_object('conjoint', true, 'approved', p_action = 'approve');
  end if;
end $function$

