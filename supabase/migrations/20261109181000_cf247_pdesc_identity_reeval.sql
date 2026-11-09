-- CF-247 F-PDESC Directive 3 (Platform Admin, 9 Nov 2026: "Continue fixing the provider-description declines, identity conflicts ... autonomously"): provider-identity holds made by an earlier reader are read again by the current reader.
--
-- Live evidence (read 9 Nov 2026 08:30 UTC, project fxcwkweaxjtknorudmwp, SELECT only): 41 providers are held for provider identity (provider_name_conflict 39, provider_subunit_source 2). 30 of the 39 conflicts were judged by
-- reader provider-description-source-guard-v1, BEFORE worker v0.59.13 (deployed 9 Nov 05:56 UTC; its reads carry provider-description-source-guard-v2) added the registry-evidence proof (own verified host, catalogue name or registry abbreviation in a heading,
-- no other institution named). They include at least 14 universities, polytechnics and TAFEs (Australian National University, The University of Sydney, University of Technology Sydney (UTS), Edith Cowan University, University of Canberra, University of Canterbury,
-- University of Auckland, Auckland University of Technology, University of Waikato, Massey University, The Open Polytechnic of New Zealand, Waikato Institute of Technology, Eastern Institute of Technology, TAFE Queensland). The other 11 identity holds
-- were judged by v2 and stay held with that evidence.
-- Cause: the selection function parks a held read for the same stored page (rule 'unchanged_unsuitable_evidence'), and the recovery-knowledge check (ops_learning_retry_check_v1) refuses the same signature that already failed. All 41 have the same
-- page hash as their read (same_hash true) and the check returns allowed=false, so the 30 are never offered to the current reader although nothing about their page changed: the READER changed. The signature (hash, model, prompt, validation function,
-- word lists) did not include the reader.
-- What this changes:
--   1 security.pdesc_reader_behaviour_v1(): the newest reader behaviour version stamped on any read's identity check (checks.identity.reader_behavior_version, written by the worker).
--   2 The signature of a read now includes it (security.provider_description_signature_v1). A reader that changes how it judges a page is "changed evidence" for the retry check, as a changed validation function or word list already is.
--   3 The picker (security.provider_description_selection_v1) no longer parks a HELD read on an identity rule (setting pdesc.identity_reeval_rules, default provider_name_conflict, provider_name_not_proved, provider_subunit_source) when that
--     read's identity check was made by another reader behaviour than the current one: it is offered again (unchanged_unsuitable_evidence and retry_wait are skipped for it, once). Every later check is unchanged: scope, manual locks, open identity findings,
--     provider_description_identity_v1, recovery knowledge, the budget. The re-read uses the stored official copy (no Firecrawl and no new page fetch) and an AI call only when the current identity proof passes. After the re-read the hold carries the
--     current behaviour version and is parked as before; a hold the current reader still refuses stays held with the evidence. Nothing relaxes the identity proof itself (worker), Layer 4, claim validation, the AI ceiling (pdesc.ai_usd_max) or the Firecrawl ceiling.
-- A later reader release re-offers identity holds once the same way (the version stamp changes), with no migration.
-- Live definitions this change edits (pg_proc.prosrc md5, read 9 Nov 2026), before -> after:
--   security.provider_description_signature_v1(text,text,text) b48bbd5b345f2e7b9a1fc6df9958163b -> 4b5cfc16584807c1c4d4179268dee4ad
--   security.provider_description_selection_v1(jsonb) c8dd7882a5a6c5b174a829972d475d40 -> b51801e562a1569940c88c8413596cc4
-- Replaces: the reader-blind signature of security.provider_description_signature_v1 and the identity-hold branches of the 'unchanged_unsuitable_evidence' and 'retry_wait' parking in security.provider_description_selection_v1 (both edited in place; no function is dropped)
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object is touched (G3).

do $g$
declare r record;
begin
  for r in select * from (values ('security.provider_description_signature_v1(text,text,text)'), ('security.provider_description_selection_v1(jsonb)'), ('security.ops_learning_retry_check_v1(text,text,text)'),
                                 ('security.toolset_setting(text,text)'), ('security.pipeline_num_v1(text,numeric)'), ('security.provider_description_identity_v1(uuid,text)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
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

-- ----------------------------------------------------------------------------------------------------------------------------------------- setting (G2: the identity rules that are re-offered are a setting, changed on Settings with a reason)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'pdesc.identity_reeval_rules', 'Provider descriptions: identity holds read again when the reader changes',
  'Hold rules (provider_name_conflict, provider_name_not_proved, provider_subunit_source) that come from the reader''s identity proof of an official page. When the reader that made such a hold is not the current reader (its behaviour version differs), the provider is offered to the current reader once more, using the stored official page. A hold the current reader still refuses stays held. Empty: identity holds are never offered again before the recheck period.',
  'list', '["provider_name_conflict", "provider_name_not_proved", "provider_subunit_source"]'::jsonb, 0, null, 'rules', 1023, 'Provider descriptions', 'security.provider_description_selection_v1',
  'CF-247 F-PDESC Directive 3 (Platform Admin, 9 Nov 2026): identity holds made by an earlier reader are read again by the current reader, with the stored page and the same governed checks')
on conflict (toolset_key, key) do nothing;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the reader behaviour (read only)
create index if not exists provider_description_reads_reader_version_idx on pipeline.provider_description_reads ((checks->'identity'->>'reader_behavior_version')) where checks ? 'identity';
create or replace function security.pdesc_reader_behaviour_v1() returns text
language sql stable security definer set search_path to '' as $f$
  -- the highest version label (longer label = larger number within one prefix, then text order): the newest reader that has judged any page
  select z.s from (select distinct x.checks->'identity'->>'reader_behavior_version' s from pipeline.provider_description_reads x where x.checks ? 'identity') z where z.s is not null order by length(z.s) desc, z.s desc limit 1
$f$;
comment on function security.pdesc_reader_behaviour_v1() is 'CF-247 F-PDESC: the newest reader behaviour version (checks.identity.reader_behavior_version) stamped on any provider-description read, i.e. the reader that is running now. Part of the evidence signature and of the re-offer of identity holds. Read only.';
revoke all on function security.pdesc_reader_behaviour_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- guarded edits of the live definitions
select pg_temp.edit_all('security.provider_description_signature_v1(text,text,text)', 'b48bbd5b345f2e7b9a1fc6df9958163b', '4b5cfc16584807c1c4d4179268dee4ad',
array[
$old$||md5(pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure))||'|'||$old$],
array[
$new$||md5(pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure))||'|'||coalesce(security.pdesc_reader_behaviour_v1(),'')||'|'||$new$]);

select pg_temp.edit_all('security.provider_description_selection_v1(jsonb)', 'c8dd7882a5a6c5b174a829972d475d40', 'b51801e562a1569940c88c8413596cc4',
array[
$old$v_pat text[]:=security.pdesc_about_like_patterns_v1();$old$,
$old$when r.state in ('held','rejected') and r.content_hash is not null and r.content_hash=coalesce(a.content_hash,a.id::text) then 'unchanged_unsuitable_evidence'$old$,
$old$(r.state='held' or (r.source_url is not null and not coalesce((security.provider_description_page_v1(p.id,r.source_url)->>'ok')::boolean,true)))) then 'retry_wait'$old$],
array[
$new$v_pat text[]:=security.pdesc_about_like_patterns_v1(); v_cur text:=security.pdesc_reader_behaviour_v1(); v_idr jsonb:=coalesce(security.toolset_setting('pipeline','pdesc.identity_reeval_rules'),'[]'::jsonb);$new$,
$new$when r.state in ('held','rejected') and r.content_hash is not null and r.content_hash=coalesce(a.content_hash,a.id::text) and not (r.state='held' and v_idr ? r.rule and coalesce(r.checks->'identity'->>'reader_behavior_version','') is distinct from coalesce(v_cur,'')) then 'unchanged_unsuitable_evidence'$new$,
$new$(r.state='held' or (r.source_url is not null and not coalesce((security.provider_description_page_v1(p.id,r.source_url)->>'ok')::boolean,true)))) and not (r.state='held' and v_idr ? r.rule and coalesce(r.checks->'identity'->>'reader_behavior_version','') is distinct from coalesce(v_cur,'')) then 'retry_wait'$new$]);

comment on function security.provider_description_signature_v1(text, text, text) is 'CF-247 provider descriptions: the evidence signature of a read (stored copy hash, model, prompt, validation function, word lists and the reader behaviour version). The same signature that already failed is not retried; a changed reader is changed evidence.';
