CREATE OR REPLACE FUNCTION security.cdesc_reading_provenance_v1(p_item bigint, p_value jsonb, p_l3 jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_m text; v_p text; v_w text; a jsonb;
begin
  -- 1. recorded on the Layer 4 item
  v_m := nullif(btrim(p_l3->>'model'), ''); v_p := nullif(btrim(p_l3->>'prompt'), ''); v_w := nullif(btrim(p_l3->>'worker'), '');
  if v_m is not null and v_p is not null then return jsonb_build_object('model', v_m, 'prompt', v_p, 'worker', v_w, 'from', 'layer4_item'); end if;
  -- 2. recorded on the reading itself (held readings, from this change on)
  v_m := nullif(btrim(p_value->'reader'->>'model'), ''); v_p := nullif(btrim(p_value->'reader'->>'prompt'), ''); v_w := nullif(btrim(p_value->'reader'->>'worker'), '');
  if v_m is not null and v_p is not null then return jsonb_build_object('model', v_m, 'prompt', v_p, 'worker', v_w, 'from', 'reading'); end if;
  -- 3. the AI answer stored for this reading, only when it holds exactly the sentences the reading holds (the same reading, not another attempt)
  select x.answer into a from pipeline.enrich_ai_answers x
   where x.item_id = p_item and nullif(btrim(x.answer->>'model'), '') is not null and nullif(btrim(x.answer->>'prompt_version'), '') is not null
     and x.answer->'value'->'sentences' is not null and x.answer->'value'->'sentences' = p_value->'sentences'
   order by x.id desc limit 1;
  if a is not null then return jsonb_build_object('model', a->>'model', 'prompt', a->>'prompt_version', 'worker', nullif(btrim(a->>'worker'), ''), 'from', 'ai_answer'); end if;
  return jsonb_build_object('from', 'none');
end $function$
