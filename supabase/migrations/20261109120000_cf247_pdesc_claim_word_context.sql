-- CF-247 F-PDESC Directive 3, Blocker A (Platform Admin, 9 Nov 2026): the machine admission rule (pdesc-machine-v1) is context-sensitive for neutral population words.
--
-- Problem (live evidence 9 Nov 2026): security.pdesc_machine_text_check_v1 refused every description that held a word of pdesc.claim_words, even a neutral, source-backed sentence. Machine decisions were
-- declined with refused_word:students (UNSW Sydney, Monash University) and refused_word:alumni (Charles Darwin University). "students", "staff" and "alumni" are in pdesc.claim_words because a claim ABOUT students
-- (student numbers, student outcomes, student satisfaction) must be proved; a sentence that only names who a university is made of ("The university's essence is found in its students, staff, alumni and donors")
-- states no such claim, and its exact official quote says so.
--
-- What this changes (the machine rule only; with pdesc.machine_admit_on = 0 nothing behaves differently):
--   1. A new list setting, pdesc.machine_neutral_words (toolset pipeline), seeded with ["students", "staff", "alumni"]. A word in it is NOT a claim in a machine-admitted description when, and only when, EVERY
--      sentence that uses it is supported by its own exact verbatim quote from the stored official page: the quote contains the same word and does not negate it (security.pdesc_claim_check_v1, the
--      evidence check the campus, scholarship and guarantee validation already uses), the sentence is marked on_page (the existing quote-on-page proof), and the description text is exactly those sentences.
--      Without sentences and quotes (the register-fact profile, tier 4, and any caller that gives none) the strict rule applies as before.
--   2. The exemption reaches only pdesc.claim_words and the French list pdesc.machine_refused_words_fr, and only for the words in pdesc.machine_neutral_words. Everything else still refuses, in the same text:
--      ranking, rating, outcome (employment, employability, salary, graduate outcomes), accreditation, award and facility words (the rest of pdesc.claim_words), every superlative (pdesc.superlatives),
--      finance, visa and availability words (pdesc.machine_refused_words), campus, scholarship and guarantee words (pdesc.evidence_claim_words) and the French refused words. Figures stay governed by
--      pdesc.machine_numbers_allowed (0: any number other than a year in range is refused; not loosened here). Page markup is still refused.
--   3. The sentences travel to the gate in its context (security.provider_description_machine_gate_v1, p_ctx->'sentences'): from the reader when it records a proposal (public.svc_provider_description_record) and
--      from the admission of a waiting Layer 4 item (security.provider_description_machine_admit_v1, which also records the neutral words it relied on in the audit row's checks). The audit row keeps the
--      source URL, source hash, evidence id and every sentence with its quote, as before.
--   4. Anything the machine rule still declines waits for a person in Layer 4 (or is held with the whole proposal and the reason), exactly as before. Validation (security.provider_description_validate_v1) is not changed: it
--      already lets a claim word through only when the sentence's own quote contains it.
-- Re-evaluation of what was declined: security.provider_description_machine_settle_pending_v1 (run by security.provider_description_machine_step_v1 on every fire of the provider-description-read job while
-- pdesc.machine_admit_on is 1) offers each waiting Layer 4 provider-description item to security.provider_description_machine_admit_v1 again, at most pdesc.machine_settle_per_run items a run and an item that was
-- declined at most hourly. The waiting items therefore meet the new rule on the next fires without any row being written here. This migration writes no row of Layer 4, reads, admissions or descriptions.
-- The worker (supabase/functions/coverage-sweep/description.ts descriptionClaimCheck) checks only long copied passages and does not read these word lists: it is not changed.
-- The consumer API (G3) is not touched: no website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_*, api.* or edge function is read for shape or changed.
--
-- Live definitions this change edits (read 9 Nov 2026, project fxcwkweaxjtknorudmwp), md5 of the function body (pg_proc.prosrc) before -> after. The body md5 is the same on PostgreSQL 16 (the test database) and 17 (live); the live bodies were compared to the test database's:
--   security.pdesc_machine_text_check_v1(uuid,text,text[]) d432bc25734a4e6cab634f4b709ad8e5 -> bafcb58c2ac586829ce4f1b1d2780a44
--   security.provider_description_machine_gate_v1(uuid,text,jsonb) 60cb6d649d95f63e99b6e6a90db62810 -> 06726bf8bf50a0baeda1f486cfc0d603
--   security.provider_description_machine_admit_v1(uuid) 3a13bb31181106c9b128c4c905f7b874 -> 5decbd99c8ecd5e0b072d22ed6f68962
--   public.svc_provider_description_record(jsonb) 3114f845b25fc31ed97eaab0f56ee297 -> f7c3debc11b67d6de7b2c6d47c8c9b9c
-- Replaces: the strict word test of security.pdesc_machine_text_check_v1 (it becomes a call of the new security.pdesc_machine_text_check_ctx_v1 without sentences, so the register-fact profile behaves as before) and the gate and admission calls that now pass the sentences (edited in place; no function is dropped)
-- Retires: nothing
-- Nothing is dropped or deleted.

do $g$
declare r record;
begin
  for r in select * from (values ('security.pdesc_machine_text_check_v1(uuid,text,text[])'), ('security.provider_description_machine_gate_v1(uuid,text,jsonb)'), ('security.provider_description_machine_admit_v1(uuid)'),
                                 ('public.svc_provider_description_record(jsonb)'), ('security.provider_description_machine_settle_pending_v1()'), ('security.provider_description_machine_step_v1()'),
                                 ('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'), ('security.pdesc_claim_check_v1(text,text,text)'), ('security.pdesc_has_term_v1(text,text)'),
                                 ('security.toolset_setting(text,text)'), ('security.pipeline_num_v1(text,numeric)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing (apply 20261109020000 and 20261109030000 first)', r.sig; end if;
  end loop;
end $g$;

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17; the header lines pg_get_functiondef prints can differ between versions
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then
    raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- setting (G2: the neutral words are a setting, changed on Settings with a reason)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'pdesc.machine_neutral_words', 'Provider descriptions: neutral population words allowed in an automatic description',
  'Words that name who a provider is made of (students, staff, alumni). They are in the claim words, which stop automatic admission, but a sentence that only names them states no claim. A word in this list is allowed in an automatically admitted description only when EVERY sentence that uses it is supported by its exact quote from the stored official page: the quote contains the same word and does not negate it. A ranking, rating, outcome (employment, employability, salary, graduate outcomes), accreditation, award, facility, superlative, finance, visa, availability, campus, scholarship or guarantee word, or a figure, still stops automatic admission wherever it appears. A person can still decide a declined description in Layer 4. Empty: every claim word stops automatic admission, as before. Reaches the claim words and the French refused words only.',
  'list', '["students", "staff", "alumni"]'::jsonb, 0, null, 'words', 1022, 'Provider descriptions', 'security.pdesc_machine_text_check_ctx_v1, security.pdesc_machine_neutral_supported_v1',
  'CF-247 F-PDESC Directive 3 Blocker A (Platform Admin, 9 Nov 2026): neutral, source-backed population words are not claims; context-sensitive validation, not a disabled word list')
on conflict (toolset_key, key) do nothing;

-- ----------------------------------------------------------------------------------------------------------------------------------------- which neutral words the quotes support
create or replace function security.pdesc_machine_neutral_supported_v1(p_text text, p_sentences jsonb) returns text[]
language plpgsql stable security definer set search_path to '' as $f$
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
end $f$;
comment on function security.pdesc_machine_neutral_supported_v1(text, jsonb) is 'CF-247 F-PDESC Directive 3 Blocker A: the words of pdesc.machine_neutral_words that the description text uses and whose every sentence is supported by its exact official quote (the quote holds the same word, does not negate it, the sentence is on_page, and the text is exactly the sentences). Empty when there are no sentences. Read only.';
revoke all on function security.pdesc_machine_neutral_supported_v1(text, jsonb) from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the objective text rule with context
create or replace function security.pdesc_machine_text_check_ctx_v1(p_provider uuid, p_text text, p_codes text[] default '{}', p_sentences jsonb default '[]'::jsonb) returns text
language plpgsql stable security definer set search_path to '' as $f$
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
$f$;
comment on function security.pdesc_machine_text_check_ctx_v1(uuid, text, text[], jsonb) is 'CF-247 F-PDESC machine rule pdesc-machine-v1 with context: null when the description is free of page markup, claim, marketing, campus/scholarship/guarantee and the extra machine words (English and French lists) and (unless allowed) of figures other than a year in range; otherwise the first refusal. A word of pdesc.machine_neutral_words (students, staff, alumni) is not a claim when every sentence that uses it is supported by its exact official quote (security.pdesc_machine_neutral_supported_v1); with no sentences the strict rule applies. The provider''s own names and listed register codes are ignored.';
revoke all on function security.pdesc_machine_text_check_ctx_v1(uuid, text, text[], jsonb) from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- guarded edits of the live definitions
select pg_temp.edit_all('security.pdesc_machine_text_check_v1(uuid,text,text[])', 'd432bc25734a4e6cab634f4b709ad8e5', 'bafcb58c2ac586829ce4f1b1d2780a44',
array[
$old$declare v_t text := lower(coalesce(p_text, '')); n text; w text; m text[]; v_year int := extract(year from now())::int; v_ymin int := security.pipeline_num_v1('pdesc.founded_year_min', 1800)::int;
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
end$old$],
array[
$new$begin
  -- no sentences = no quotes to check: the strict rule, as before (the register-fact profile, tier 4, has none)
  return security.pdesc_machine_text_check_ctx_v1(p_provider, p_text, p_codes, '[]'::jsonb);
end$new$]);
comment on function security.pdesc_machine_text_check_v1(uuid, text, text[]) is 'CF-247 F-PDESC machine rule pdesc-machine-v1, strict form (no sentences, so no neutral word is allowed): see security.pdesc_machine_text_check_ctx_v1. Used by the register-fact profile.';

select pg_temp.edit_all('security.provider_description_machine_gate_v1(uuid,text,jsonb)', '60cb6d649d95f63e99b6e6a90db62810', '06726bf8bf50a0baeda1f486cfc0d603',
array[
$old$  v_bad := security.pdesc_machine_text_check_v1(p.id, p_text, v_codes);
$old$],
array[
$new$  v_bad := security.pdesc_machine_text_check_ctx_v1(p.id, p_text, v_codes, coalesce(p_ctx->'sentences', '[]'::jsonb));
$new$]);

select pg_temp.edit_all('security.provider_description_machine_admit_v1(uuid)', '3a13bb31181106c9b128c4c905f7b874', '5decbd99c8ecd5e0b072d22ed6f68962',
array[
$old$jsonb_build_object('tier', v_tier, 'codes', v_codes));
$old$,
$old$'validation', coalesce(v_check->'checks', v_prof->'facts')),$old$],
array[
$new$jsonb_build_object('tier', v_tier, 'codes', v_codes, 'sentences', case when v_tier = 'registry_factual' then '[]'::jsonb else coalesce(i.proposed_value->'sentences', '[]'::jsonb) end));
$new$,
$new$'validation', coalesce(v_check->'checks', v_prof->'facts'),
          'neutral_words', to_jsonb(security.pdesc_machine_neutral_supported_v1(v_text, case when v_tier = 'registry_factual' then '[]'::jsonb else coalesce(i.proposed_value->'sentences', '[]'::jsonb) end))),$new$]);

select pg_temp.edit_all('public.svc_provider_description_record(jsonb)', '3114f845b25fc31ed97eaab0f56ee297', 'f7c3debc11b67d6de7b2c6d47c8c9b9c',
array[
$old$jsonb_build_object('tier',r.read_via));
$old$],
array[
$new$jsonb_build_object('tier',r.read_via,'sentences',x->'answer'->'sentences'));
$new$]);
