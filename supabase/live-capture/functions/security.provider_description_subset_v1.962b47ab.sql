CREATE OR REPLACE FUNCTION security.provider_description_subset_v1(p_provider uuid, p_sentences jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-subset-v1
declare s jsonb; v_o int := 0; v_bad text; v_kept jsonb := '[]'::jsonb; v_drop jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_sentences) is distinct from 'array' then return null; end if;
  for s in select x from jsonb_array_elements(p_sentences) x loop
    v_o := v_o + 1;
    -- the SAME machine text check the whole description goes through, on this sentence alone with its own official quote (a neutral population word is allowed only when the quote holds it and does not negate it, as for the whole text)
    v_bad := security.pdesc_machine_text_check_ctx_v1(p_provider, s->>'text', '{}'::text[], jsonb_build_array(s));
    if v_bad is null then v_kept := v_kept || jsonb_build_array(s);
    else v_drop := v_drop || jsonb_build_array(jsonb_build_object('index', v_o, 'code', v_bad, 'text', s->>'text', 'quote', left(coalesce(s->>'quote', ''), 600))); -- fixed: the audit shows the first 600 characters of the quote; the full quote stays in the proposal
    end if;
  end loop;
  return jsonb_build_object('kept', v_kept, 'dropped', v_drop);
end $function$
