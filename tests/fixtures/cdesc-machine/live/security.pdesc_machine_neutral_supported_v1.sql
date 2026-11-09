CREATE OR REPLACE FUNCTION security.pdesc_machine_neutral_supported_v1(p_text text, p_sentences jsonb)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w text; s jsonb; v_out text[] := '{}'; v_seen boolean; v_bad boolean;
        v_norm text := regexp_replace(lower(btrim(coalesce(p_text, ''))), '\s+', ' ', 'g');
begin
  if jsonb_typeof(p_sentences) is distinct from 'array' or jsonb_array_length(p_sentences) = 0 then return v_out; end if;
  -- the text must be exactly the sentences that carry the quotes; otherwise no quote speaks for it
  if v_norm is distinct from (select regexp_replace(lower(string_agg(btrim(x->>'text'), ' ' order by o)), '\s+', ' ', 'g') from jsonb_array_elements(p_sentences) with ordinality e(x, o)) then return v_out; end if;
  for w in select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.machine_neutral_words'), '[]'::jsonb)) loop
    v_seen := false; v_bad := false;
    for s in select x from jsonb_array_elements(p_sentences) x loop
      if security.pdesc_has_term_v1(s->>'text', w) then
        v_seen := true;
        -- the quote is the sentence's own passage, proved on the stored official page (on_page); it must hold the same word and must not negate it
        if coalesce((s->>'on_page')::boolean, false) is false or nullif(btrim(coalesce(s->>'quote', '')), '') is null
           or not security.pdesc_has_term_v1(s->>'quote', w) or security.pdesc_claim_check_v1(s->>'text', s->>'quote', w) is not null then v_bad := true; end if;
      end if;
    end loop;
    if v_seen and not v_bad then v_out := v_out || lower(w); end if;
  end loop;
  return v_out;
end $function$;
