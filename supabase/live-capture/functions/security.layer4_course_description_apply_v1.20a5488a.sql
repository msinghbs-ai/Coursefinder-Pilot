CREATE OR REPLACE FUNCTION security.layer4_course_description_apply_v1(p_actor uuid, p_item_id uuid, p_value jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.layer4_review_items%rowtype; v_text text; v_now text; v_shown text;
begin
  select * into i from pipeline.layer4_review_items where id = p_item_id;
  if i.id is null or i.entity_type <> 'course' or i.field_code <> 'course_description_first_read' then raise exception 'not a course description item' using errcode = '22023'; end if;
  -- approved as read: an edited description has no quote for its new words (reject it; the page is read again later)
  if p_value is distinct from i.proposed_value then raise exception 'a description is approved as read, with every sentence quoted from the page; reject it instead of editing' using errcode = '22023'; end if;
  v_text := nullif(btrim(i.proposed_value->>'description'), '');
  if v_text is null then raise exception 'the proposal has no description' using errcode = '22023'; end if;
  if i.evidence_id is null then raise exception 'the proposal has no stored page' using errcode = '22023'; end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.entity_id and l.field in ('description', 'course_description', 'all')) then
    raise exception 'the description is locked by hand' using errcode = '22023';
  end if;
  select nullif(btrim(c.description), '') into v_now from catalogue.courses c where c.id = i.entity_id for update;
  if v_now is distinct from nullif(btrim(i.before_value->>'description'), '') then raise exception 'the description changed since this was proposed; reject this item' using errcode = '22023'; end if;
  update catalogue.courses set description = v_text, updated_at = now() where id = i.entity_id;
  select c.description into v_shown from catalogue.courses c where c.id = i.entity_id;  -- the column public.website_v2_course reads
  return jsonb_build_object('course_id', i.entity_id, 'description_chars', length(v_text), 'held', v_shown = v_text, 'evidence_id', i.evidence_id, 'actor', p_actor);
end $function$
