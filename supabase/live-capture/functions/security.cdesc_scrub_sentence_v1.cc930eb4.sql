CREATE OR REPLACE FUNCTION security.cdesc_scrub_sentence_v1(p_text text, p_quote text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t text := coalesce(p_text, ''); w text;
begin
  -- "leading" as a verb or direction is not a ranking
  t := regexp_replace(t, '\mleading\s+(to|into|towards?|teams?|people|others|(a|the)\s+teams?|and\s+(managing|supervising|motivating))\M', ' ', 'gi');
  t := regexp_replace(t, '\mteam[- ]leading\M', ' ', 'gi');
  -- programme structure, not a claim: points, paper codes, levels, years of study
  t := regexp_replace(t, '\m[0-9]+(\s*-\s*|\s+)(credit\s+)?points?\M', ' ', 'gi');
  -- a paper code of 4 or 5 letters (CHHE 701) only in a sentence that names a paper, course, unit, subject or module and holds no money: never a currency code beside an amount (AUD 250)
  if t ~* '\m(papers?|courses?|units?|subjects?|modules?)\M'
     and t !~* '(\$|\m(fees?|costs?|costing|prices?|priced|tuition|dollars?|payable|charges?|scholarships?)\M|\m(aud|usd|nzd|eur|gbp|cad|sgd|cny|jpy|inr|hkd|chf)\s?[0-9])' then
    t := regexp_replace(t, '\m[A-Z]{4,5}\s?[0-9]{3}\M', ' ', 'g'); -- fixed: an ISO currency code is always 3 letters, so a paper code is 4 or 5 letters and a 3-letter prefix is never set aside
  end if;
  t := regexp_replace(t, '\m[0-9]{3}-level\M', ' ', 'gi');
  t := regexp_replace(t, '\m(year|level)\s+[0-9]\M', ' ', 'gi');
  -- a word the course may keep when the sentence's own on-page quote holds it
  for w in select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_supported_words'), '[]'::jsonb)) loop
    if w ~ '^[A-Za-z]+$' and security.pdesc_has_term_v1(p_quote, w) then t := regexp_replace(t, '\m' || w || '\M', ' ', 'gi'); end if;
  end loop;
  -- the learner word
  for w in select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_learner_words'), '[]'::jsonb)) loop
    if security.cdesc_learner_word_ok_v1(w, p_text, p_quote) then t := regexp_replace(t, '\m' || lower(w) || '\M', ' ', 'gi'); end if;
  end loop;
  return t;
end $function$
