-- Guards: F-PDESC Directive 3 (Platform Admin, 9 Nov 2026): a register-fact profile is not declined for the catalogue's own course labels ("Employment Skills Programmes", "Non AQF Award"), outcome and award claims are still refused, a city that lost a character is not stated, and a machine-text hold made under another text rule is looked at again once.
-- Fixture data only (the pdesc-machine harness: fictional providers, no live data; the two labels are the live reference-table labels). Prints "<scenario>|<result>" lines; every block rolls back. Run by tests/fixtures/pdesc-registry-labels/run.sh after migration 20261109180000.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

create or replace function pg_temp.pid(n int) returns uuid language sql as $f$ select id from catalogue.providers where stable_key = 'fixture:provider:' || case when n = 13 then 'browser' else n::text end $f$;
create or replace function pg_temp.set_s(k text, v jsonb) returns void language sql as $f$ update pipeline.platform_toolset_settings set value = v where toolset_key = 'pipeline' and key = k $f$;
create or replace function pg_temp.desc_of(n int) returns text language sql as $f$ select coalesce(description, '(none)') from catalogue.providers where id = pg_temp.pid(n) $f$;
create or replace function pg_temp.items(n int, st text) returns bigint language sql as $f$ select count(*) from pipeline.layer4_review_items where entity_id = pg_temp.pid(n) and field_code = 'provider_description' and status = st $f$;
-- the gate on a register-fact text with the codes the old profile returned (register sentence and code only) and the codes the new profile returns
create or replace function pg_temp.gate(p_n int, p_text text, p_codes jsonb) returns text language sql as $f$
  select coalesce(g->>'ok', '') || '|' || coalesce(substring(g->>'reason' from '\(([^)]*)\)'), '')
    from (select security.provider_description_machine_gate_v1(pg_temp.pid(p_n), p_text, jsonb_build_object('tier', 'registry_factual', 'codes', p_codes)) g) z $f$;
-- the live labels on a provider's active courses (levels and fields), a Victorian city and a register listing with stored evidence
create or replace function pg_temp.reg_setup(p_field text, p_level text, p_city text) returns void language plpgsql as $f$
declare v_sub uuid := gen_random_uuid(); v_l1 uuid := gen_random_uuid(); v_f1 uuid := gen_random_uuid();
begin
  insert into ref.subdivisions(id, country_id, code, name, status) values (v_sub, '00000000-0000-0000-0000-0000000000a1', 'FX-VIC', 'Victoria', 'active');
  insert into ref.study_levels(code, name, id) values ('fx_lab', p_level, v_l1);
  insert into ref.fields_of_study(id, name) values (v_f1, p_field);
  update catalogue.providers set primary_city = p_city, subdivision_id = v_sub, website = null where id = pg_temp.pid(14);
  update catalogue.provider_registrations set evidence_id = (select evidence_id from catalogue.provider_registrations where provider_id = pg_temp.pid(2)), status = 'active' where provider_id = pg_temp.pid(14);
  update catalogue.courses set study_level_id = v_l1, primary_field_id = v_f1 where id in (select id from catalogue.courses where provider_id = pg_temp.pid(14) and lifecycle_status = 'active');
  insert into catalogue.courses(provider_id, canonical_title, lifecycle_status, study_level_id, primary_field_id) select pg_temp.pid(14), 'Fixture course', 'active', v_l1, v_f1 where not exists (select 1 from catalogue.courses where provider_id = pg_temp.pid(14) and lifecycle_status = 'active');
end $f$;

-- the three settings these scenarios switch are put back at the end
create temp table saved_settings as select key, value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('pdesc.machine_admit_on', 'pdesc.registry_factual_on', 'pdesc.registry_after_rules');
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select pg_temp.set_s('pdesc.registry_factual_on', '1');
select pg_temp.set_s('pdesc.registry_after_rules', '["no_about_page"]');

-- 1. the profile returns the labels it printed with its fixed wording; the gate admits it; the old codes (register wording and code only) would have refused it
begin;
select pg_temp.reg_setup('Employment Skills Programmes', 'Non AQF Award', 'Melbourne');
select 'profile_ok|' || (p->>'ok') || '|' || (p->>'text') from (select security.provider_description_registry_profile_v1(pg_temp.pid(14)) p) x;
select 'profile_codes|' || (select string_agg(c, ' ; ' order by o) from jsonb_array_elements_text(security.provider_description_registry_profile_v1(pg_temp.pid(14))->'codes') with ordinality e(c, o) where o > 2);
select 'gate_old_codes|' || pg_temp.gate(14, security.provider_description_registry_profile_v1(pg_temp.pid(14))->>'text', (security.provider_description_registry_profile_v1(pg_temp.pid(14))->'codes') - 2 - 2);
select 'gate_new_codes|' || pg_temp.gate(14, security.provider_description_registry_profile_v1(pg_temp.pid(14))->>'text', security.provider_description_registry_profile_v1(pg_temp.pid(14))->'codes');
-- negative: the labels are removed only as whole labels. An outcome, award or ranking claim in the same text is still refused, whatever the codes
select 'neg_outcome|' || pg_temp.gate(14, 'Fixture College is a private college. Its listed courses are in fields including Employment Skills Programmes. Graduates enjoy strong employment outcomes.', security.provider_description_registry_profile_v1(pg_temp.pid(14))->'codes');
select 'neg_employability|' || pg_temp.gate(14, 'Fixture College is a private college. Its listed courses are in fields including Employment Skills Programmes and it improves employability.', security.provider_description_registry_profile_v1(pg_temp.pid(14))->'codes');
select 'neg_award|' || pg_temp.gate(14, 'Fixture College is a private college. Its listed courses are at Non AQF Award levels. It is an award-winning college.', security.provider_description_registry_profile_v1(pg_temp.pid(14))->'codes');
select 'neg_ranking|' || pg_temp.gate(14, 'Fixture College is a private college. Its listed courses are at Non AQF Award levels. It is ranked first for Employment Skills Programmes.', security.provider_description_registry_profile_v1(pg_temp.pid(14))->'codes');
select 'neg_label_alone_lower|' || pg_temp.gate(14, 'Fixture College is a private college that places graduates into employment.', security.provider_description_registry_profile_v1(pg_temp.pid(14))->'codes');
-- the tiers that carry provider-written sentences pass no codes: the word still refuses there
select 'neg_stored_tier|' || coalesce((security.provider_description_machine_gate_v1(pg_temp.pid(14), 'Fixture College helps students into employment.', '{"tier":"stored"}'::jsonb))->>'rule', '');
rollback;

-- 2. the codes carry exactly the labels the text prints, as whole labels: a claim word outside the label is still refused even when the label itself holds the same word
begin;
select pg_temp.reg_setup('Ranked Programmes', 'Certificate', 'Melbourne');
select 'label_whole|' || (p->>'ok') || '|' || pg_temp.gate(14, p->>'text', p->'codes') from (select security.provider_description_registry_profile_v1(pg_temp.pid(14)) p) x;
select 'label_plus_claim|' || (p->>'ok') || '|' || pg_temp.gate(14, (p->>'text') || ' It is ranked first in Victoria.', p->'codes') from (select security.provider_description_registry_profile_v1(pg_temp.pid(14)) p) x;
rollback;

-- 3. a city that lost a character is not stated as a place (live: "Whang?rei")
begin;
select pg_temp.reg_setup('Business', 'Certificate', 'Whang?rei');
select 'city_question|' || (p->>'text') from (select security.provider_description_registry_profile_v1(pg_temp.pid(14)) p) x;
update catalogue.providers set primary_city = 'Whang' || chr(65533) || 'rei' where id = pg_temp.pid(14);
select 'city_replacement|' || (p->>'text') from (select security.provider_description_registry_profile_v1(pg_temp.pid(14)) p) x;
update catalogue.providers set primary_city = 'Whangārei' where id = pg_temp.pid(14);
select 'city_macron_kept|' || (p->>'text') from (select security.provider_description_registry_profile_v1(pg_temp.pid(14)) p) x;
rollback;

-- 4. re-evaluation: a machine-text hold made before the fix (no text_rule in its checks) is looked at again by the existing tier and admitted by the existing machine admission
begin;
select pg_temp.reg_setup('Employment Skills Programmes', 'Certificate', 'Melbourne');
insert into pipeline.provider_description_reads(provider_id, state, rule, reason, worker, prompt_version, checks, tries)
values (pg_temp.pid(14), 'held', 'machine_declined_machine_text_refused_word', 'fixture: refused_word:employment', 'registry-factual-v1', 'registry-profile-v1', '{"tier":"registry_factual","tier_hold":true}'::jsonb, 0);
select 'reeval_before|' || pg_temp.desc_of(14) || '|' || pg_temp.items(14, 'approved');
select 'reeval_run|' || (security.provider_description_registry_tier_v1())::text;
select 'reeval_admitted|' || (pg_temp.desc_of(14) like '%Employment Skills Programmes%')::text || '|' || pg_temp.items(14, 'approved');
select 'reeval_audit|' || (select a.tier || '|' || a.rule || '|' || a.outcome || '|' || (a.actor = 'c0ffee00-0000-4000-8000-000000000150')::text from pipeline.provider_description_machine_admissions a where a.provider_id = pg_temp.pid(14) order by a.created_at desc limit 1);
select 'reeval_again|' || (security.provider_description_registry_tier_v1())::text;
rollback;

-- 5. negative: a machine-text hold made under the current text rule is not looked at again (waits pdesc.recheck_days); the tier stamps the rule on every such hold it makes
begin;
select pg_temp.reg_setup('Business', 'Certificate', 'Melbourne');
select pg_temp.set_s('pdesc.claim_words', ((select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.claim_words') || '["university"]'::jsonb)); -- the fixture's type label is now a refused word
insert into pipeline.provider_description_reads(provider_id, state, rule, reason, worker, prompt_version, checks, tries)
values (pg_temp.pid(14), 'held', 'machine_declined_machine_text_refused_word', 'fixture: refused_word:university', 'registry-factual-v1', 'registry-profile-v1', '{"tier":"registry_factual","tier_hold":true}'::jsonb, 0);
select pg_temp.set_s('pdesc.superlatives', ((select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.superlatives') || '["fixture-edit"]'::jsonb)); -- an older hold: the rule has changed since it was made
select 'stale_run|' || (security.provider_description_registry_tier_v1())::text || '|' || pg_temp.desc_of(14);
select 'stamped|' || (select count(*) filter (where checks->>'text_rule' = security.pdesc_text_rule_fingerprint_v1() and rule = 'machine_declined_machine_text_refused_word' and reason like 'The description has a word%') from pipeline.provider_description_reads where provider_id = pg_temp.pid(14)) || '|' || (select count(*) from pipeline.provider_description_reads where provider_id = pg_temp.pid(14) and checks->>'text_rule' is null);
select 'current_again|' || (security.provider_description_registry_tier_v1())::text || '|' || (select count(*) from pipeline.provider_description_reads where provider_id = pg_temp.pid(14));
-- the text rule changes again (the word list is corrected): the hold is looked at once more and admitted
select pg_temp.set_s('pdesc.claim_words', ((select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'pdesc.claim_words') - 'university'));
select 'rule_changed|' || (security.provider_description_registry_tier_v1())::text || '|' || (pg_temp.desc_of(14) like 'No Source University is a university%')::text;
rollback;

-- 6. the fingerprint is stable, changes with a word list, and the function is not callable by the public roles
select 'fingerprint_stable|' || (security.pdesc_text_rule_fingerprint_v1() = security.pdesc_text_rule_fingerprint_v1())::text;
begin;
select pg_temp.set_s('pdesc.superlatives', '["best"]'::jsonb);
select 'fingerprint_setting|' || (security.pdesc_text_rule_fingerprint_v1() <> (select md5('x')))::text;
rollback;
select 'fingerprint_grants|' || has_function_privilege('anon', 'security.pdesc_text_rule_fingerprint_v1()'::regprocedure, 'execute')::text || '|' || has_function_privilege('authenticated', 'security.pdesc_text_rule_fingerprint_v1()'::regprocedure, 'execute')::text;

-- put the settings back
update pipeline.platform_toolset_settings s set value = v.value from saved_settings v where s.toolset_key = 'pipeline' and s.key = v.key;
