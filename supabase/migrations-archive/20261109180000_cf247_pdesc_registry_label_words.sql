-- CF-247 F-PDESC Directive 3 (Platform Admin, 9 Nov 2026: "Continue fixing the provider-description declines ... autonomously"): register-fact profiles are no longer declined for the catalogue's own course labels.
--
-- Live evidence (read 9 Nov 2026 08:30 UTC, project fxcwkweaxjtknorudmwp, SELECT only): 20 providers (19 NZ, 1 AU) hold a register-fact profile that the machine text rule declined (machine_declined_machine_text_refused_word):
--   19 with refused_word:employment, 1 with refused_word:award. The word is never a claim by the provider. It is the name of a catalogue label the profile prints verbatim in its third sentence
--   ("Its listed courses are at ... levels, in fields including ..."): the field of study "Employment Skills Programmes" (ref.fields_of_study, 68 providers use it) and the study level "Non AQF Award" (ref.study_levels, 495 providers use it).
--   Of every label in ref.fields_of_study, ref.study_levels and ref.provider_types, exactly these two contain a word of any machine refusal list (claim words, superlatives, evidence words, extra machine words, French words).
-- Cause: security.provider_description_registry_profile_v1 builds the sentence from the labels and security.pdesc_machine_text_check_ctx_v1 then reads the label as prose. The profile already tells the rule which of its own wording is fixed
--   (the register sentence and the register code, the 'codes' it returns); the labels it prints are fixed wording of the same kind: exact values of the catalogue's reference tables, not text a provider wrote.
-- What this changes:
--   1 The profile returns the exact level and field labels it printed in its 'codes' (after the register sentence and code). The rule ignores listed codes exactly as before; nothing else in the rule changes. A claim word anywhere else in the text still refuses
--     ("strong employment outcomes", "award-winning", rankings, facilities, accreditation, superlatives, visa, fees, figures): the labels are removed only as whole labels, so a sentence that merely contains the word is still refused. Nothing in a provider-written text (stored/direct/firecrawl tiers) is affected: those tiers pass no codes.
--   2 A city that holds a question mark or the Unicode replacement character is not stated as a place (live: "Whang?rei", a lost macron, 1 provider). The profile then uses the region and country, as it does for any unusable city.
--   3 Re-evaluation (no new job, no bypass): a register-fact hold made by the machine text rule is looked at again, once, when the text rule changed since the hold was made. security.pdesc_text_rule_fingerprint_v1 is the md5 of the text rule, the profile builder, the neutral-word helper and the word-list settings;
--     the tier records it on every machine-text hold it makes and selects a hold with another fingerprint (or none: the 20 live holds) again. The profile is rebuilt from the verified record, passes the same machine gate and the same admission (security.provider_description_machine_admit_v1, which re-proves the text, the register listing and the evidence)
--     and is written only by that admission. A hold at the current fingerprint still waits pdesc.recheck_days. No setting, ceiling, switch, job, schedule, AI or Firecrawl read, Layer 4 item or consumer API object is changed here (G3).
-- Live definitions this change edits (pg_proc.prosrc md5, read 9 Nov 2026), before -> after:
--   security.provider_description_registry_profile_v1(uuid) 53f35748344bb1bc74b621979724e1b5 -> 73d492c257ac3c961dc89aec27fe7561
--   security.provider_description_registry_tier_v1() 1f9cbb77a59ab392a2e59b6aff317adb -> b5adf0031da10995cd85a0fdad06608b
-- Replaces: the register-fact profile's 'codes' list and city rule, and the registry tier's recent-hold exclusion and retry selection for machine-text holds (both edited in place; no function is dropped)
-- Retires: nothing
-- Nothing is dropped or deleted.

do $g$
declare r record;
begin
  for r in select * from (values ('security.provider_description_registry_profile_v1(uuid)'), ('security.provider_description_registry_tier_v1()'), ('security.pdesc_machine_text_check_ctx_v1(uuid,text,text[],jsonb)'),
                                 ('security.pdesc_machine_neutral_supported_v1(text,jsonb)'), ('security.toolset_setting(text,text)'), ('security.pipeline_num_v1(text,numeric)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing (apply 20261109020000, 20261109120000 and 20261109140000 first)', r.sig; end if;
  end loop;
end $g$;

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
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
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the fingerprint of the text rule (read only)
create or replace function security.pdesc_text_rule_fingerprint_v1() returns text
language sql stable security definer set search_path to '' as $f$
  select md5(coalesce((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.pdesc_machine_text_check_ctx_v1(uuid,text,text[],jsonb)')), '')
          || '|' || coalesce((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.pdesc_machine_neutral_supported_v1(text,jsonb)')), '')
          || '|' || coalesce((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.provider_description_registry_profile_v1(uuid)')), '')
          || '|' || coalesce((select jsonb_object_agg(s.key, s.value order by s.key)::text from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline'
                               and s.key in ('pdesc.claim_words', 'pdesc.superlatives', 'pdesc.evidence_claim_words', 'pdesc.machine_refused_words', 'pdesc.machine_refused_words_fr', 'pdesc.machine_neutral_words', 'pdesc.machine_numbers_allowed', 'pdesc.founded_year_min')), ''))
$f$;
comment on function security.pdesc_text_rule_fingerprint_v1() is 'CF-247 F-PDESC: md5 of the machine text rule (security.pdesc_machine_text_check_ctx_v1 and its neutral-word helper), the register-fact profile builder and the word-list settings it reads. The register-fact tier records it on a machine-text hold and looks at the hold again when it changes. Read only.';
revoke all on function security.pdesc_text_rule_fingerprint_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- guarded edits of the live definitions
select pg_temp.edit_all('security.provider_description_registry_profile_v1(uuid)', '53f35748344bb1bc74b621979724e1b5', '73d492c257ac3c961dc89aec27fe7561',
array[
$old$  if v_city is not null and security.pdesc_machine_text_check_v1(p.id, v_city) is not null then v_city := null; end if; -- a "campus" or other refused word is not a city
$old$,
$old$'codes', jsonb_build_array(s2, reg.registration_code), 'profile_version'$old$],
array[
$new$  if v_city is not null and security.pdesc_machine_text_check_v1(p.id, v_city) is not null then v_city := null; end if; -- a "campus" or other refused word is not a city
  if v_city is not null and (position('?' in v_city) > 0 or position(chr(65533) in v_city) > 0) then v_city := null; end if; -- a city that lost a character ("Whang?rei") is not stated as a place
$new$,
$new$'codes', jsonb_build_array(s2, reg.registration_code) || to_jsonb(coalesce(v_levels, '{}'::text[])) || to_jsonb(coalesce(v_fields, '{}'::text[])), 'profile_version'$new$]);

select pg_temp.edit_all('security.provider_description_registry_tier_v1()', '1f9cbb77a59ab392a2e59b6aff317adb', 'b5adf0031da10995cd85a0fdad06608b',
array[
$old$v_msg text; v_rule text;
$old$,
$old$h.checks->>'tier' = 'registry_factual' and coalesce(case when (h.checks->>'facts_needed') ~ '^[0-9]+$' then (h.checks->>'facts_needed')::numeric end, 0) <= security.pipeline_num_v1('pdesc.registry_min_facts', 3) and h.updated_at >$old$,
$old$(lr.state = 'held' and (v_rules ? lr.rule or (lr.rule = 'insufficient_verified_facts'$old$,
$old$'machine_declined_' || (v_gate->>'rule'), left(v_gate->>'reason', 400), 'registry-factual-v1', 'registry-profile-v1', jsonb_build_object('tier', 'registry_factual', 'tier_hold', true), 0);$old$,
$old$                jsonb_build_object('tier', 'registry_factual', 'tier_hold', true), 0);
      exception when others then null;$old$],
array[
$new$v_msg text; v_rule text; v_fp text := security.pdesc_text_rule_fingerprint_v1();
$new$,
$new$h.checks->>'tier' = 'registry_factual' and coalesce(case when (h.checks->>'facts_needed') ~ '^[0-9]+$' then (h.checks->>'facts_needed')::numeric end, 0) <= security.pipeline_num_v1('pdesc.registry_min_facts', 3) and not (h.rule like 'machine_declined_machine_text%' and h.checks->>'text_rule' is distinct from v_fp) and h.updated_at >$new$,
$new$(lr.state = 'held' and (v_rules ? lr.rule or (lr.rule like 'machine_declined_machine_text%' and lr.checks->>'tier' = 'registry_factual' and lr.checks->>'text_rule' is distinct from v_fp) or (lr.rule = 'insufficient_verified_facts'$new$,
$new$'machine_declined_' || (v_gate->>'rule'), left(v_gate->>'reason', 400), 'registry-factual-v1', 'registry-profile-v1', jsonb_build_object('tier', 'registry_factual', 'tier_hold', true, 'text_rule', v_fp), 0);$new$,
$new$                jsonb_build_object('tier', 'registry_factual', 'tier_hold', true, 'text_rule', v_fp), 0);
      exception when others then null;$new$]);

comment on function security.provider_description_registry_profile_v1(uuid) is 'CF-247 F-PDESC tier 4 (registry_factual): a short factual profile built only from the provider record, its active register listing (stored evidence) and its active catalogue courses, each sentence tied to its facts; or insufficient_verified_facts. The exact level and field labels it prints are returned with the register wording in codes (they are reference-table values, not claims); a city that lost a character is not stated. Deterministic, read only, no AI and no page read.';
comment on function security.provider_description_registry_tier_v1() is 'CF-247 F-PDESC tier 4 (registry_factual): runs the register-fact profile for providers with no page to read; a hold made at a higher facts requirement, or a machine-text hold made under another text rule (security.pdesc_text_rule_fingerprint_v1), is looked at again; every profile still passes the machine gate and the machine admission.';
