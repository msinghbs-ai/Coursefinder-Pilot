CREATE OR REPLACE FUNCTION security.layer4_decision_outcome_v1(p_kind text, p_choice text, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- UR-06 (1 Nov 2026): what a Layer 4 decision actually did, read back from its destination after the decision. Classes: admitted (values
-- now active), applied (the correction is in place), reconciled (closed without admitting a value), downstream (queued: the result follows
-- later), deferred (asked again later), pending_check (saved, but the destination does not show it yet). A card leaving the list is not proof.
declare v_status text := p_result->>'status'; v_rows jsonb; v_aer jsonb; v_entity uuid; v_url text; v_ok boolean;
begin
  if p_kind = 'aer_review' and p_result ? 'review_item_id' then
    v_aer := public.layer4_aer_review_read((p_result->>'review_item_id')::uuid);
    select jsonb_object_agg(s, n) into v_rows
      from (select case when x->>'status' = 'inactive' and coalesce(x->>'status_reason', '') like 'excluded by %' then 'excluded' else x->>'status' end s, count(*) n
              from jsonb_array_elements(coalesce(v_aer->'rows', '[]'::jsonb)) x group by 1) q;
    v_rows := coalesce(v_rows, '{}'::jsonb);
    return jsonb_build_object('class', case when v_status = 'rejected' then 'reconciled' when coalesce((v_rows->>'active')::int, 0) > 0 then 'admitted'
                                            when coalesce((v_rows->>'proposed')::int, 0) > 0 then 'downstream' else 'pending_check' end,
                              'status', v_status, 'decision_id', p_result->>'decision_id', 'rows', v_rows, 'destination', 'entry_requirements');
  elsif p_result ? 'decision_id' then
    if v_status = 'rejected' then
      return jsonb_build_object('class', 'reconciled', 'status', v_status, 'decision_id', p_result->>'decision_id');
    elsif p_kind = 'course_link' and exists (select 1 from pipeline.layer4_review_items r where r.id = (p_result->>'review_item_id')::uuid
                                                and r.field_code = 'provider_current_tuition_validation') then
      -- SS-016 fee check (1 Nov 2026): the fee written for this review item by security.layer4_tuition_apply_impl
      select jsonb_build_object('amount', f.amount, 'currency', f.currency_code, 'fee_year', f.fee_year, 'basis', f.basis, 'course_fee_id', f.id)
        into v_rows from catalogue.course_fees f
       where f.notes like 'CF-247 Layer 4 human decision; review item ' || (p_result->>'review_item_id') || ';%' and f.status = 'active'
       order by f.updated_at desc limit 1;
      return jsonb_build_object('class', case when v_rows is not null then 'admitted' else 'pending_check' end, 'verified', v_rows is not null,
                                'status', v_status, 'decision_id', p_result->>'decision_id', 'fee', v_rows, 'destination', 'course_fees');
    elsif p_kind = 'course_link' then
      v_url := case jsonb_typeof(p_result->'final_value') when 'string' then p_result->>'final_value' else p_result->'final_value'->>'course_url' end;
      select r.entity_id into v_entity from pipeline.layer4_review_items r where r.id = (p_result->>'review_item_id')::uuid and r.entity_type = 'course';
      v_ok := v_url is not null and exists (select 1 from catalogue.course_links l where l.course_id = v_entity and l.link_type = 'official_course' and l.status = 'active'
                                                  and lower(rtrim(l.url, '/')) = lower(rtrim(v_url, '/')));
      return jsonb_build_object('class', case when v_ok then 'applied' else 'pending_check' end, 'verified', v_ok, 'status', v_status,
                                'decision_id', p_result->>'decision_id', 'value', v_url, 'course_id', v_entity, 'destination', 'course');
    end if;
    return jsonb_build_object('class', 'applied', 'status', v_status, 'decision_id', p_result->>'decision_id');
  elsif p_kind = 'course_link' then  -- a held fee: the page entered is read again; the fee is re-admitted only after that read
    return jsonb_build_object('class', 'downstream', 'note', 'the page is read again; its fee is admitted only after that read');
  elsif p_choice = 'wait' then
    return jsonb_build_object('class', 'deferred');
  elsif p_choice in ('rebuild', 'retry', 'cricos_only', 'website') then
    return jsonb_build_object('class', 'downstream');
  elsif p_choice in ('archive', 'archive_course') then
    return jsonb_build_object('class', 'applied');
  elsif p_kind = 'held_scholarship' then
    return jsonb_build_object('class', case when p_choice = 'publish' then 'admitted' else 'reconciled' end);
  elsif p_choice in ('release', 'keep') then
    return jsonb_build_object('class', 'reconciled', 'note', p_result->>'requeued');
  end if;
  return jsonb_build_object('class', 'reconciled');
end $function$
