CREATE OR REPLACE FUNCTION security.cdesc_points_back_v1(p_text text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  -- fixed: a structural test of the grammar (a sentence that opens with a pronoun, a connecting word, "the program" or a quote or bracket), not a tunable limit
  select btrim(coalesce(p_text, '')) ~* '^\s*(((this|these|that|those|it|its|they|their|them|he|she|his|her|such|both|also|however|therefore|thus|moreover|furthermore|additionally|in addition|as a result|another|alternatively|further|and|which|here|each|but|or|so|yet|then|instead|otherwise|similarly|likewise|meanwhile|for example|for instance|in particular|the (program|programme|course|degree|qualification|major))\M)|["''“‘(\[«])'
      -- 13 Nov 2026 (QA of this change): openers the first list misses, and "<subject> then ..."
      or btrim(coalesce(p_text, '')) ~* '^\s*((as such|building on|finally|afterwards|afterward|subsequently|in turn|lastly|secondly|thirdly)\M|\S+\s+then\M)'
$function$
