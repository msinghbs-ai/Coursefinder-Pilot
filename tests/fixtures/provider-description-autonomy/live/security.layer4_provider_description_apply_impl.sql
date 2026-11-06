CREATE OR REPLACE FUNCTION security.layer4_provider_description_apply_impl(p_actor uuid, p_item_id uuid, p_value jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.layer4_review_items%rowtype; v_text text; v_now text; v_pub jsonb; v_shown text; v_key text;
begin
  select * into i from pipeline.layer4_review_items where id = p_item_id;
  if i.id is null or i.entity_type <> 'provider' or i.field_code <> 'provider_description' then raise exception 'not a provider description item' using errcode = '22023'; end if;
  -- approved as read: an edited description has no quote for its new words, so it is not admitted (reject, and the page is read again later)
  if p_value is distinct from i.proposed_value then raise exception 'a description is approved as read, with every sentence quoted from the page; reject it instead of editing' using errcode = '22023'; end if;
  v_text := nullif(btrim(i.proposed_value->>'description'), '');
  if v_text is null then raise exception 'the proposal has no description' using errcode = '22023'; end if;
  if i.evidence_id is null then raise exception 'the proposal has no stored page' using errcode = '22023'; end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = i.entity_id and l.field in ('description', 'p_description', 'all')) then
    raise exception 'the description is locked by hand' using errcode = '22023';
  end if;
  select nullif(btrim(p.description), '') into v_now from catalogue.providers p where p.id = i.entity_id for update;
  if v_now is distinct from nullif(btrim(i.before_value->>'description'), '') then raise exception 'the description changed since this was proposed; reject this item' using errcode = '22023'; end if;
  update catalogue.providers set description = v_text, updated_at = now() where id = i.entity_id;
  -- verify publication: the Website API v2 provider payload is read back (a provider not published returns nothing yet)
  select p.stable_key into v_key from catalogue.providers p where p.id = i.entity_id;
  begin
    v_pub := public.website_v2_provider(v_key);
    v_shown := v_pub->'item'->>'description';
  exception when others then v_shown := null;
  end;
  update pipeline.provider_description_reads set state = 'admitted', last_verified_at = now(),
         published_at = case when v_shown = v_text then now() end, updated_at = now()
   where review_item_id = i.id;
  update pipeline.provider_description_reads set state = 'superseded', updated_at = now()
   where provider_id = i.entity_id and state = 'admitted' and review_item_id is distinct from i.id;
  return jsonb_build_object('provider_id', i.entity_id, 'description_chars', length(v_text), 'published', v_shown = v_text, 'evidence_id', i.evidence_id);
end $function$

