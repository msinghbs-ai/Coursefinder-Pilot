CREATE OR REPLACE FUNCTION security.cdesc_learner_word_ok_v1(p_word text, p_text text, p_quote text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w text := lower(btrim(coalesce(p_word, ''))); v_t text := lower(coalesce(p_text, '')); v_q text := lower(coalesce(p_quote, '')); v_verb text;
begin
  if w = '' or w !~ '^[a-z]+$' then return false; end if; -- fixed: a plain word only, so it can sit inside the pattern below
  if not exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_learner_words'), '[]'::jsonb)) x where lower(btrim(x)) = w) then return false; end if;
  if not security.pdesc_has_term_v1(p_text, w) or security.pdesc_has_term_v1(p_quote, w) then return false; end if;
  -- the quote must speak to the reader: a second-person pronoun, or a clause that opens with the verb the sentence gives the word ("Learn about ..." for "Students learn about ...")
  v_verb := substring(v_t from ('\m' || w || '\s+(?:(?:will|can|may|could|should|also|then)\s+)*([a-z]{3,})\M'));
  if v_verb in ('for', 'the', 'and', 'who', 'are', 'from', 'with', 'into', 'that', 'their', 'have', 'has', 'was', 'were', 'not') then v_verb := null; end if; -- fixed: function words are not a verb
  if v_q !~ '\myou(r|rs|rself)?\M' and (v_verb is null or v_q !~ ('(^|[.:;!?]\s*)' || v_verb || '\M')) then return false; end if;
  -- a population statement is not a stand-in for "you"
  return v_t !~ ('([0-9][0-9,.]*\s+([a-z-]+\s+)?' || w || '|' || w || '\s+(from\s+(over|more|across|around)|come|choose|rate|say|report|achieve|graduate|who|are|have|often|typically|usually|consistently|regularly)|(international|former|past|successful|our|alumni|graduate|all|many|most|other|some|top|best|brightest|talented|gifted|enrolled|current)\s+' || w
                 || '|of\s+' || w || '|' || w || '''?s?\s+(satisfaction|outcomes|success))');
end $function$
