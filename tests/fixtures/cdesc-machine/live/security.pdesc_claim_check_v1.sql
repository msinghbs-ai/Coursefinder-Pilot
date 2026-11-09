CREATE OR REPLACE FUNCTION security.pdesc_claim_check_v1(p_sentence text, p_quote text, p_term text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  with t as (select btrim(regexp_replace(lower(coalesce(p_term,'')),'[^a-z0-9#%]+',' ','g')) term),
  f as (select case when t.term ~ ' ' then array[t.term] else array[t.term, t.term||'s', t.term||'es', t.term||'d', t.term||'ed'] end forms from t where t.term<>''),
  hit as (select exists(select 1 from f, unnest(f.forms) x where security.pdesc_has_term_v1(p_sentence,x)) in_sentence,
                 exists(select 1 from f, unnest(f.forms) x where security.pdesc_has_term_v1(p_quote,x)) in_quote,
                 exists(select 1 from f, unnest(f.forms) x where lower(coalesce(p_quote,'')) ~ ('(\m(no(?!\s+matter)|not(?!\s+(only|just))|never|cannot|without|nor|none|neither)\M|n''t)(\W+\w+){0,2}\W+'||x||'\M')) negated_quote,
                 exists(select 1 from f, unnest(f.forms) x where lower(coalesce(p_sentence,'')) ~ ('(\m(no(?!\s+matter)|not(?!\s+(only|just))|never|cannot|without|nor|none|neither)\M|n''t)(\W+\w+){0,2}\W+'||x||'\M')) negated_sentence)
  select case when not hit.in_sentence then null
              when not hit.in_quote then 'unsupported_claim'
              when hit.negated_quote and not hit.negated_sentence then 'claim_negated_in_source'
              end from hit
$function$;
