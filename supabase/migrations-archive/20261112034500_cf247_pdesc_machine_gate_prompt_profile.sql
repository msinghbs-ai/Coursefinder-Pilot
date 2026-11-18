-- CF-247 F-PDESC follow-up (Platform Admin 11 Nov 2026 17:39 AEDT "deliver according to plan"; Operating Model §3.3.1: with the prompt, the
-- wording is the prompt's job and only the checks a machine applies reliably stay as rules).
--
-- Finding (live, 11 Nov 2026 18:50 AEDT): 175 descriptions that passed every check wait for a person; in three hours the automatic admission
-- (pdesc-machine-v1) admitted 68 and declined 187. Its text check (security.pdesc_machine_text_check_ctx_v1) still applies the two word lists
-- 20261112010000 marked "built-in prompt only" (pdesc.claim_words: students, staff, facilities, employment ...; pdesc.evidence_claim_words:
-- campus ...), so a sentence the prompt asks for ("campuses in Melbourne and Sydney") was declined; and it applies the French list
-- (pdesc.machine_refused_words_fr: campus, excellence, unique ...) to English text.
--
-- What this does: while pdesc.prompt_on is 1 the automatic admission's word lists are pdesc.prompt_refused_words (rankings, awards, outcomes,
-- promotion, fees, visas), pdesc.superlatives (marketing wording still goes to a person) and pdesc.machine_refused_words (visa, fees, funding,
-- scholarships, accredited ...), plus pdesc.machine_refused_words_fr only for a French text (three or more distinct French function words).
-- pdesc.machine_numbers_allowed 0 -> 1 (figures are proved in their quotes by the validation). Page markup and every lineage, identity
-- and validation check are unchanged. With pdesc.prompt_on 0 the
-- lists are exactly as before. Declined items are checked again by the existing hourly settle (provider_description_machine_settle_pending_v1).
-- Consumer API (G3): not touched. Nothing is dropped or deleted. No description is written by applying this migration.
-- Forward recovery: pdesc.machine_numbers_allowed 0 on Settings; pdesc.prompt_on 0 restores the earlier lists (and the built-in prompt).
-- Replaces: the automatic admission's built-in-prompt word lists while the prompt is on.
-- Retires: nothing.

do $g$
begin
  if md5(pg_get_functiondef('security.pdesc_machine_text_check_ctx_v1(uuid,text,text[],jsonb)'::regprocedure)) <> '97dc630f1a12238ef9889873e2338a35' then raise exception 'pdesc_machine_text_check_ctx_v1 is not the reviewed body'; end if;
end $g$;

create or replace function pg_temp.pdesc_swap(p_fn regprocedure, p_old text, p_new text) returns void language plpgsql as $s$
declare d text := pg_get_functiondef(p_fn);
begin
  if (length(d) - length(replace(d, p_old, ''))) / length(p_old) <> 1 then raise exception '%: anchor not found exactly once: %', p_fn, left(p_old, 80); end if;
  execute replace(d, p_old, p_new);
end $s$;

select pg_temp.pdesc_swap('security.pdesc_machine_text_check_ctx_v1(uuid,text,text[],jsonb)'::regprocedure,
  $o$v_lists text[] := array['pdesc.claim_words', 'pdesc.superlatives', 'pdesc.evidence_claim_words', 'pdesc.machine_refused_words', 'pdesc.machine_refused_words_fr']; l text;$o$,
  $n$v_lists text[] := case when security.pipeline_num_v1('pdesc.prompt_on', 0) >= 1  /* 20261112034500: the prompt profile (Operating Model 3.3.1) */
          then array['pdesc.prompt_refused_words', 'pdesc.superlatives', 'pdesc.machine_refused_words']
               || case when (select count(distinct fw.word) from regexp_split_to_table(lower(coalesce(p_text, '')), '[^a-zà-ÿ]+') fw(word)
                              where fw.word in ('les', 'des', 'est', 'une', 'et', 'du', 'pour', 'dans', 'sur', 'aux', 'au', 'qui')) >= 3  -- fixed: a French text has three or more distinct French function words
                       then array['pdesc.machine_refused_words_fr'] else '{}'::text[] end
          else array['pdesc.claim_words', 'pdesc.superlatives', 'pdesc.evidence_claim_words', 'pdesc.machine_refused_words', 'pdesc.machine_refused_words_fr'] end; l text;$n$);

-- the superlatives list is used again with the prompt (the automatic admission's marketing check), so it leaves the "built-in prompt only" section
update pipeline.platform_toolset_settings set section = 'Provider descriptions', updated_at = now(),
       used_by = case when position('pdesc_machine_text_check_ctx_v1' in coalesce(used_by, '')) > 0 then used_by else concat_ws('; ', nullif(used_by, ''), 'security.pdesc_machine_text_check_ctx_v1') end,
       reason = 'CF-247 F-PDESC 20261112034500: with the prompt on, the automatic admission still sends marketing wording to a person'
 where toolset_key = 'pipeline' and key = 'pdesc.superlatives';
update pipeline.platform_toolset_settings set updated_at = now(),
       used_by = case when position('pdesc_machine_text_check_ctx_v1' in coalesce(used_by, '')) > 0 then used_by else concat_ws('; ', nullif(used_by, ''), 'security.pdesc_machine_text_check_ctx_v1') end
 where toolset_key = 'pipeline' and key = 'pdesc.prompt_refused_words';

-- figures: with the prompt profile the validation proves every number of a sentence in its quote on the provider's own page (unchanged), so
-- the blanket figure ban of the automatic admission is a duplicate; it is switched off here as a recorded settings change (reversible on
-- Settings › Pipeline settings). "accredited" and the visa, fee and funding words stay with a person.
update pipeline.platform_toolset_settings set value = '1'::jsonb, updated_at = now(),
       reason = 'CF-247 F-PDESC 20261112034500 (Platform Admin 11 Nov 2026 17:39 "deliver according to plan"): figures are proved in their quotes by the validation; 74 of 175 waiting descriptions were held only for a figure'
 where toolset_key = 'pipeline' and key = 'pdesc.machine_numbers_allowed' and value = '0'::jsonb;

-- post-checks
do $post$
begin
  if position('pdesc.prompt_refused_words' in pg_get_functiondef('security.pdesc_machine_text_check_ctx_v1(uuid,text,text[],jsonb)'::regprocedure)) = 0 then raise exception 'post-check: lists'; end if;
  if security.pipeline_num_v1('pdesc.prompt_on', 0) >= 1 then
    if security.pdesc_machine_text_check_ctx_v1(null, 'Example College has campuses in Melbourne and Sydney and teaches business to students.', '{}', '[]') is not null then raise exception 'post-check: campus and students pass with the prompt'; end if;
    if security.pdesc_machine_text_check_ctx_v1(null, 'Example College is a world-class and innovative college.', '{}', '[]') is null then raise exception 'post-check: marketing still goes to a person'; end if;
    if security.pdesc_machine_text_check_ctx_v1(null, 'Example College helps students with visas.', '{}', '[]') is null then raise exception 'post-check: visas still go to a person'; end if;
    if security.pdesc_machine_text_check_ctx_v1(null, 'Le collège est situé à Montréal et offre des programmes pour les étudiants sur le campus.', '{}', '[]') is null then raise exception 'post-check: French list for a French text'; end if;
  end if;
end $post$;
