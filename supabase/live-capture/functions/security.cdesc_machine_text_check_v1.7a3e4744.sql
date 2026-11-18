CREATE OR REPLACE FUNCTION security.cdesc_machine_text_check_v1(p_provider uuid, p_text text, p_sentences jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_s jsonb; v_t text; v_norm text := regexp_replace(lower(btrim(coalesce(p_text, ''))), '\s+', ' ', 'g');
begin
  if jsonb_typeof(p_sentences) is distinct from 'array' or jsonb_array_length(p_sentences) = 0
     or v_norm is distinct from (select regexp_replace(lower(string_agg(btrim(x->>'text'), ' ' order by o)), '\s+', ' ', 'g') from jsonb_array_elements(p_sentences) with ordinality e(x, o)) then
    -- no quote speaks for this text: the shared policy runs on it as it is
    return security.pdesc_machine_text_check_ctx_v1(p_provider, p_text, '{}', p_sentences);
  end if;
  select jsonb_agg(jsonb_set(x, '{text}', to_jsonb(security.cdesc_scrub_sentence_v1(x->>'text', x->>'quote'))) order by o),
         string_agg(btrim(security.cdesc_scrub_sentence_v1(x->>'text', x->>'quote')), ' ' order by o)
    into v_s, v_t from jsonb_array_elements(p_sentences) with ordinality e(x, o);
  return security.pdesc_machine_text_check_ctx_v1(p_provider, v_t, '{}', v_s);
end $function$
