CREATE OR REPLACE FUNCTION security.pdesc_machine_text_check_ctx_v1(p_provider uuid, p_text text, p_codes text[] DEFAULT '{}'::text[], p_sentences jsonb DEFAULT '[]'::jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_t text := lower(coalesce(p_text, '')); v_ok text[] := security.pdesc_machine_neutral_supported_v1(p_text, p_sentences); n text; w text; m text[]; v_year int := extract(year from now())::int; v_ymin int := security.pipeline_num_v1('pdesc.founded_year_min', 1800)::int;
        v_lists text[] := array['pdesc.claim_words', 'pdesc.superlatives', 'pdesc.evidence_claim_words', 'pdesc.machine_refused_words', 'pdesc.machine_refused_words_fr']; l text;
begin
  -- web-page markup left in the text (&#039; &amp; &nbsp;) is never admitted: the wording was not read cleanly
  if coalesce(p_text, '') ~* '&#?[a-z0-9]{1,8};' then return 'entity_encoded:page markup'; end if;
  -- the provider's own names, the verified register codes and the register's own fixed wording (which names the register, e.g. "... for Overseas Students") are not claims ("Premier Institute", "provider code 00002J")
  for n in select nm from (select p.canonical_name nm from catalogue.providers p where p.id = p_provider union all select p.display_name from catalogue.providers p where p.id = p_provider
                           union all select p.short_name from catalogue.providers p where p.id = p_provider) z where nullif(btrim(nm), '') is not null order by length(nm) desc loop
    v_t := replace(v_t, lower(n), ' ');
  end loop;
  foreach n in array coalesce(p_codes, '{}') loop
    if nullif(btrim(n), '') is not null then v_t := replace(v_t, lower(n), ' '); end if;
  end loop;
  foreach l in array v_lists loop
    for w in select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', l), '[]'::jsonb)) loop
      -- a neutral population word whose every sentence is supported by its exact official quote is not a claim here; every other list, and every other word in these two, still refuses
      if l in ('pdesc.claim_words', 'pdesc.machine_refused_words_fr') and lower(w) = any(v_ok) then continue; end if;
      if security.pdesc_has_term_v1(v_t, w) then return 'refused_word:' || w; end if;
    end loop;
  end loop;
  if security.pipeline_num_v1('pdesc.machine_numbers_allowed', 0) < 1 then
    for m in select regexp_matches(v_t, '[0-9][0-9,.]*[0-9]|[0-9]', 'g') loop
      if not (m[1] ~ '^[0-9]{4}$' and m[1]::int between v_ymin and v_year) then return 'figure:' || m[1]; end if;
    end loop;
    if v_t ~ '[0-9]\s*(%|per\s*cent|percent)' then return 'figure:percentage'; end if;
  end if;
  return null;
end
$function$;
