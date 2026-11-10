-- Guards: F-PDESC P0 (Platform Admin directive, 9 Nov 2026: unique, source-backed university descriptions): an admitted register-fact (basic) description does not take the provider out of source-backed enrichment; it is upgraded by the machine rule only from verified richer official evidence, and a lock, an earlier rejection, a withdrawal or a text changed by hand keeps the provider out; the prior version is kept.
-- Fixture data only (the provider-description-autonomy seed plus fictional register providers). Prints "<scenario>|<result>" lines; every block rolls back. Run by tests/fixtures/pdesc-basic-upgrade/run.sh.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

-- ---------------------------------------------------------------------------------------------------------------- helpers
create or replace function pg_temp.run_worker(p_limit int, p_override jsonb default '{}'::jsonb) returns jsonb language plpgsql as $f$
declare v_lease jsonb; it jsonb; v_res jsonb := '[]'; d record; v_ans jsonb;
begin
  v_lease := public.svc_provider_description_lease_v1(p_limit, null, 'provider-description-reserve-v1');
  for it in select * from jsonb_array_elements(v_lease->'items') loop
    select * into d from fixture.documents where provider_id = (it->>'provider_id')::uuid;
    v_ans := coalesce(p_override->(it->>'provider_id'), d.model_answer);
    v_ans := jsonb_set(v_ans, '{sentences}', (select jsonb_agg(s || '{"on_page":true}'::jsonb) from jsonb_array_elements(v_ans->'sentences') s));
    v_res := v_res || jsonb_build_array(jsonb_build_object('item_id', it->>'item_id', 'stored_evidence_id', d.evidence_id, 'model', v_lease->>'model', 'prompt_version', 'provider-description-v2', 'worker', 'fixture',
              'cost', 0.0001, 'cost_known', true, 'ai_call_started', true, 'identity_check', jsonb_build_object('ok', true), 'answer', v_ans));
  end loop;
  return jsonb_build_object('leased', jsonb_array_length(coalesce(v_lease->'items', '[]'::jsonb)), 'idle', v_lease->>'reason', 'recorded', case when jsonb_array_length(v_res) > 0 then public.svc_provider_description_record(v_res) end);
end $f$;
create or replace function pg_temp.pid(n int) returns uuid language sql as $f$ select id from catalogue.providers where stable_key = 'fixture:provider:' || case when n = 13 then 'browser' else n::text end $f$;
create or replace function pg_temp.set_s(k text, v jsonb) returns void language sql as $f$ update pipeline.platform_toolset_settings set value = v where toolset_key = 'pipeline' and key = k $f$;
create or replace function pg_temp.desc_of(n int) returns text language sql as $f$ select coalesce(description, '(none)') from catalogue.providers where id = pg_temp.pid(n) $f$;
create or replace function pg_temp.wd(p uuid, r text) returns jsonb language sql as $f$ select security.provider_description_machine_withdraw_v1(p, r, '90000000-0000-0000-0000-000000000005'::uuid) $f$;
create or replace function pg_temp.items(n int, st text) returns bigint language sql as $f$ select count(*) from pipeline.layer4_review_items where entity_id = pg_temp.pid(n) and field_code = 'provider_description' and status = st $f$;
create or replace function pg_temp.answer(p_a text, p_b text) returns jsonb language sql as $f$
  select jsonb_build_object('about_page', true, 'sentences', jsonb_build_array(jsonb_build_object('text', p_a, 'quote', p_a), jsonb_build_object('text', p_b, 'quote', p_b)))
$f$;
-- the upgrade lane's selection for one provider (automatic queue, stored mode)
create or replace function pg_temp.upg_sel(n int) returns text language sql as $f$
  select coalesce((select (x->>'eligibility_reason') || '/' || (x->>'eligible') from jsonb_array_elements(security.provider_description_selection_v1(jsonb_build_object('filter','all','size',60,'prefilter',true,'upgrade',true,'mode','stored'))->'providers') x
                    where (x->>'provider_id')::uuid = pg_temp.pid(n)), 'not_listed')
$f$;
create or replace function pg_temp.reg_setup() returns void language plpgsql as $f$
declare v_sub uuid := gen_random_uuid(); v_l1 uuid := gen_random_uuid(); v_l2 uuid := gen_random_uuid(); v_f1 uuid := gen_random_uuid(); v_f2 uuid := gen_random_uuid();
begin
  insert into ref.subdivisions(id, country_id, code, name, status) values (v_sub, '00000000-0000-0000-0000-0000000000a1', 'FX-VIC', 'Victoria', 'active');
  insert into ref.study_levels(code, name, id) values ('fx_bach', 'Bachelor', v_l1), ('fx_mast', 'Masters', v_l2);
  insert into ref.fields_of_study(id, name) values (v_f1, 'Business'), (v_f2, 'Engineering');
  update catalogue.providers set primary_city = 'MELBOURNE', subdivision_id = v_sub where id in (pg_temp.pid(1), pg_temp.pid(14));
  update catalogue.courses set study_level_id = v_l1, primary_field_id = v_f1 where id in (select id from catalogue.courses where provider_id = pg_temp.pid(1) and lifecycle_status = 'active' order by id limit 5);
  update catalogue.courses set study_level_id = v_l2, primary_field_id = v_f2 where id in (select id from catalogue.courses where provider_id = pg_temp.pid(1) and lifecycle_status = 'active' and study_level_id is null order by id limit 5);
end $f$;
-- provider 1 holds an admitted register-fact profile (made by the register-fact tier, as live), after an older read that found no About page
create or replace function pg_temp.mkprofile() returns void language plpgsql as $f$
begin
  perform pg_temp.reg_setup();
  perform pg_temp.set_s('pdesc.machine_admit_on', '1'); perform pg_temp.set_s('pdesc.registry_factual_on', '1'); perform pg_temp.set_s('pdesc.registry_after_rules', '["no_about_page"]'); perform pg_temp.set_s('pdesc.acquire_direct', '0'); perform pg_temp.set_s('batch.provider_description', '10');
  insert into pipeline.provider_description_reads(provider_id, state, rule, reason, created_at, updated_at) values (pg_temp.pid(1), 'held', 'no_about_page', 'fixture', now() - interval '4 days', now() - interval '4 days');
  if (security.provider_description_registry_tier_v1()->>'admitted')::int <> 1 then raise exception 'the fixture profile was not admitted'; end if;
  -- the profile was admitted two days ago (the fixture runs in one transaction, so every row would otherwise carry the same time)
  update pipeline.provider_description_reads set created_at = now() - interval '2 days', updated_at = now() - interval '2 days', last_verified_at = now() - interval '2 days' where provider_id = pg_temp.pid(1) and rule = 'registry_factual';
  update pipeline.provider_description_machine_admissions set created_at = now() - interval '2 days' where provider_id = pg_temp.pid(1) and tier = 'registry_factual';
end $f$;

-- ---------------------------------------------------------------------------------------------------------------- 1. the settings
select 'settings|' || (select string_agg(key || '=' || value::text || '/' || min_value || '-' || max_value || '/' || unit || '/' || (label is not null and used_by is not null and help is not null)::text, ',' order by key)
  from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'pdesc.registry_upgrade%');

-- ---------------------------------------------------------------------------------------------------------------- 2. switch off (the default): a register-fact profile is a description held, exactly as before
begin;
select pg_temp.mkprofile();
select 'off_profile_held|' || coalesce(security.provider_description_basic_profile_v1(pg_temp.pid(1))::text, 'null') || '|' || (security.provider_description_machine_blocked_v1(pg_temp.pid(1))->>'rule');
select 'off_selection|' || pg_temp.upg_sel(1);
select 'off_enqueue_ran|' || (security.provider_description_enqueue_v1() is not null)::text;
select 'off_enqueue_provider1|' || (select count(*) from pipeline.provider_description_reads where provider_id = pg_temp.pid(1) and state = 'queued');
insert into pipeline.provider_description_reads(provider_id, state) values (pg_temp.pid(1), 'queued');
select 'off_lease_ran|' || (pg_temp.run_worker(3) is not null)::text;
select 'off_lease_provider1|' || (select state || '/' || coalesce(rule, '-') from pipeline.provider_description_reads where provider_id = pg_temp.pid(1) and state not in ('admitted', 'held') or (provider_id = pg_temp.pid(1) and rule like 'machine_declined%') limit 1)
  || '|' || (pg_temp.desc_of(1) like 'Aurora Maritime University is a university%')::text;
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 3. switch on: the profile is upgraded from the verified official page; the prior version is kept
begin;
select pg_temp.mkprofile();
select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
create temp table prof as select pg_temp.desc_of(1) t;
select 'on_profile|' || (security.provider_description_basic_profile_v1(pg_temp.pid(1))->>'text' = (select t from prof))::text || '|' || coalesce(security.provider_description_machine_blocked_v1(pg_temp.pid(1))->>'rule', 'not_blocked');
select 'on_selection|' || pg_temp.upg_sel(1);
-- the automatic queue adds the upgrade read (and the missing-description providers as before)
select 'on_enqueue_ran|' || (security.provider_description_enqueue_v1() > 0)::text;
select 'on_enqueue_provider1|' || (select count(*) from pipeline.provider_description_reads where provider_id = pg_temp.pid(1) and state = 'queued');
select 'on_worker_ran|' || (pg_temp.run_worker(10) is not null)::text;
select 'on_worker_provider1|' || (select string_agg(state || '/' || coalesce(rule, '-'), ',' order by created_at, state) from pipeline.provider_description_reads where provider_id = pg_temp.pid(1) and state in ('admitted', 'superseded', 'proposed', 'held') and rule is distinct from 'no_about_page');
select 'on_description_changed|' || (pg_temp.desc_of(1) <> (select t from prof))::text || '|' || (pg_temp.desc_of(1) like 'Aurora Maritime University offers education in marine navigation%')::text;
select 'on_admissions|' || (select string_agg(tier || '/' || (withdrawn_at is not null)::text || '/' || coalesce(withdrawn_reason like 'Upgraded to a source-verified description%', false)::text, ',' order by created_at, tier) from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(1));
select 'on_prior_version_kept|' || (select (a.after_description = (select t from prof))::text from pipeline.provider_description_machine_admissions a where a.provider_id = pg_temp.pid(1) and a.tier = 'registry_factual')
  || '|' || (select (a.before_description = (select t from prof))::text || '|' || (a.checks->'upgrade'->>'from_tier') || '|' || (a.checks->'upgrade'->>'source_url' is not null)::text || '|' || (a.checks->'upgrade'->>'sentences')
       || '|' || (a.checks->'upgrade'->>'prior_admission_id' = (select b.id::text from pipeline.provider_description_machine_admissions b where b.provider_id = pg_temp.pid(1) and b.tier = 'registry_factual'))::text
       from pipeline.provider_description_machine_admissions a where a.provider_id = pg_temp.pid(1) and a.tier <> 'registry_factual');
select 'on_reads|' || (select string_agg(state || '/' || coalesce(rule, '-'), ',' order by created_at, state) from pipeline.provider_description_reads where provider_id = pg_temp.pid(1) and state in ('admitted', 'superseded'));
select 'on_layer4|' || pg_temp.items(1, 'approved') || '|' || pg_temp.items(1, 'pending') || '|' || (select (d.layer2_state->>'machine_rule') || '|' || (d.reason like '%Not a person%')::text from pipeline.layer4_decisions d join pipeline.layer4_review_items li on li.id = d.review_item_id
  where li.entity_id = pg_temp.pid(1) and li.before_value->>'description' is not null);
select 'on_refresh_signals|' || (select count(*) from pipeline.search_refresh_signals where entity_id = pg_temp.pid(1));
-- upgraded once: no longer a profile, no second upgrade, no further read
select 'on_after|' || coalesce(security.provider_description_basic_profile_v1(pg_temp.pid(1))::text, 'null') || '|' || (security.provider_description_machine_blocked_v1(pg_temp.pid(1))->>'rule') || '|' || pg_temp.upg_sel(1);
-- withdrawing the upgrade restores the profile text (the prior version) and keeps the audit
select 'on_withdraw|' || (pg_temp.wd(pg_temp.pid(1), 'fixture withdraw upgrade')->>'ok') || '|' || (pg_temp.desc_of(1) = (select t from prof))::text;
select 'on_withdraw_then|' || (select count(*) from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(1)) || '|' || coalesce(security.provider_description_basic_profile_v1(pg_temp.pid(1))::text, 'null') || '|' || (security.provider_description_machine_blocked_v1(pg_temp.pid(1))->>'rule');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 4. nothing that protects a description is bypassed
-- 4a manual lock
begin;
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('provider', pg_temp.pid(1), 'description', 'value');
select 'lock_blocked|' || (security.provider_description_machine_blocked_v1(pg_temp.pid(1))->>'rule') || '|' || pg_temp.upg_sel(1);
select 'lock_enqueue_ran|' || (security.provider_description_enqueue_v1() is not null)::text;
select 'lock_enqueue_provider1|' || (select count(*) from pipeline.provider_description_reads where provider_id = pg_temp.pid(1) and state = 'queued');
insert into pipeline.provider_description_reads(provider_id, state) values (pg_temp.pid(1), 'queued');
select 'lock_lease_ran|' || (pg_temp.run_worker(3) is not null)::text;
select 'lock_lease_provider1|' || (select string_agg(state || '/' || coalesce(rule, '-'), ',') from pipeline.provider_description_reads where provider_id = pg_temp.pid(1) and state in ('held', 'queued', 'reading') and rule is distinct from 'no_about_page')
  || '|' || (pg_temp.desc_of(1) like 'Aurora Maritime University is a university%')::text;
rollback;
-- 4b an earlier human rejection
begin;
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, proposed_value, before_value) values ('provider', pg_temp.pid(1), 'provider_description', 'rejected', '{"description":"x"}', '{"description":null}');
select 'rejected_blocked|' || (security.provider_description_machine_blocked_v1(pg_temp.pid(1))->>'rule') || '|' || pg_temp.upg_sel(1);
insert into pipeline.provider_description_reads(provider_id, state) values (pg_temp.pid(1), 'queued');
select 'rejected_lease|' || (pg_temp.run_worker(3)->>'leased') || '|' || (pg_temp.desc_of(1) like 'Aurora Maritime University is a university%')::text;
rollback;
-- 4c the description was changed by a person (the text is no longer the admitted profile)
begin;
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
update catalogue.providers set description = 'A person wrote this description after the profile was admitted, and it must be kept as written by that person.' where id = pg_temp.pid(1);
select 'edited_profile|' || coalesce(security.provider_description_basic_profile_v1(pg_temp.pid(1))::text, 'null') || '|' || (security.provider_description_machine_blocked_v1(pg_temp.pid(1))->>'rule') || '|' || pg_temp.upg_sel(1);
insert into pipeline.provider_description_reads(provider_id, state) values (pg_temp.pid(1), 'queued');
select 'edited_lease|' || (pg_temp.run_worker(3)->>'leased') || '|' || (pg_temp.desc_of(1) like 'A person wrote this description%')::text;
rollback;
-- 4d the profile was withdrawn by a person
begin;
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
select 'withdrawn_ok|' || (pg_temp.wd(pg_temp.pid(1), 'fixture withdraw profile')->>'ok');
select 'withdrawn_blocked|' || coalesce(security.provider_description_basic_profile_v1(pg_temp.pid(1))::text, 'null') || '|' || (security.provider_description_machine_blocked_v1(pg_temp.pid(1))->>'rule') || '|' || pg_temp.desc_of(1);
rollback;
-- 4e the lease race: the description was edited after the read was leased (the existing guard still holds the proposal)
begin;
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
insert into pipeline.provider_description_reads(provider_id, state) values (pg_temp.pid(1), 'queued');
create temp table lease1 as select public.svc_provider_description_lease_v1(3, null, 'provider-description-reserve-v1') j;
update catalogue.providers set description = 'Edited by a person while the read was in progress, so the read must not replace it.' where id = pg_temp.pid(1);
select 'race_leased|' || (select jsonb_array_length(j->'items') from lease1);
select 'race_record|' || (public.svc_provider_description_record((select jsonb_agg(jsonb_build_object('item_id', it->>'item_id', 'stored_evidence_id', d.evidence_id, 'model', 'm', 'prompt_version', 'provider-description-v2', 'worker', 'fixture', 'cost', 0.0001, 'cost_known', true, 'ai_call_started', true,
   'identity_check', jsonb_build_object('ok', true), 'answer', jsonb_set(d.model_answer, '{sentences}', (select jsonb_agg(s || '{"on_page":true}'::jsonb) from jsonb_array_elements(d.model_answer->'sentences') s))))
   from lease1, jsonb_array_elements(j->'items') it join fixture.documents d on d.provider_id = (it->>'provider_id')::uuid))::text) || '|' || (pg_temp.desc_of(1) like 'Edited by a person%')::text;
select 'race_read|' || (select state || '/' || rule from pipeline.provider_description_reads where provider_id = pg_temp.pid(1) order by created_at desc, id desc limit 1);
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 5. text the machine rule declines waits for a person; the profile stays until then
begin;
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
insert into pipeline.provider_description_reads(provider_id, state) values (pg_temp.pid(1), 'queued');
select 'declined_tally|' || (pg_temp.run_worker(3, jsonb_build_object(pg_temp.pid(1)::text, pg_temp.answer('Aurora Maritime University offers education in marine navigation and coastal engineering.', 'Aurora Maritime University runs a unique program in ocean research.')))->'recorded')::text;
select 'declined_waits|' || pg_temp.items(1, 'pending') || '|' || (pg_temp.desc_of(1) like 'Aurora Maritime University is a university%')::text || '|' || (select count(*) from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(1) and outcome = 'declined')
  || '|' || (select (before_value->>'description' like 'Aurora Maritime University is a university%')::text from pipeline.layer4_review_items where entity_id = pg_temp.pid(1) and status = 'pending');
select 'declined_profile_live|' || (select count(*) from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(1) and outcome = 'admitted' and withdrawn_at is null and tier = 'registry_factual');
-- a person approves the waiting upgrade in Layer 4: the existing route replaces the profile and supersedes the profile's read (the profile text stays in its admission record)
select 'declined_person_approves|' || (security.layer4_provider_description_apply_impl('90000000-0000-0000-0000-000000000005', li.id, li.proposed_value, 'fixture person approves')->>'published')
  from pipeline.layer4_review_items li where li.entity_id = pg_temp.pid(1) and li.status = 'pending';
select 'declined_person_result|' || (pg_temp.desc_of(1) like 'Aurora Maritime University offers education in marine navigation%')::text || '|' || (select string_agg(state || '/' || coalesce(rule, '-'), ',' order by state) from pipeline.provider_description_reads where provider_id = pg_temp.pid(1) and state in ('admitted', 'superseded'))
  || '|' || (select (a.after_description like 'Aurora Maritime University is a university%')::text from pipeline.provider_description_machine_admissions a where a.provider_id = pg_temp.pid(1) and a.tier = 'registry_factual');
-- known and stated (PR note): a person's approval does not close the profile admission row; the profile rule gives nothing from here on because the text differs
select 'declined_person_profile_row|' || (select count(*) from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(1) and outcome = 'admitted' and withdrawn_at is null and tier = 'registry_factual') || '|' || coalesce(security.provider_description_basic_profile_v1(pg_temp.pid(1))::text, 'null');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 6. revisit rate, and which providers are listed
begin;
select pg_temp.mkprofile(); select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
-- the revisit is the existing one (no new setting): an upgrade read that was held on a stored page is not made again for the same page, and is made again when the stored page changed
insert into pipeline.provider_description_reads(provider_id, state, rule, reason, content_hash, created_at, updated_at)
  select pg_temp.pid(1), 'held', 'verbatim_passage', 'fixture', coalesce(a.content_hash, a.id::text), now() - interval '1 day', now() - interval '1 day' from pipeline.evidence_artifacts a where a.id = security.provider_description_stored_v1(pg_temp.pid(1));
select 'revisit_same_page|' || pg_temp.upg_sel(1);
update pipeline.provider_description_reads set content_hash = 'an-earlier-copy-of-the-page' where provider_id = pg_temp.pid(1) and state = 'held' and rule = 'verbatim_passage';
select 'revisit_page_changed|' || pg_temp.upg_sel(1);
delete from pipeline.provider_description_reads where provider_id = pg_temp.pid(1) and state = 'held' and rule = 'verbatim_passage';
-- (the scenario here that the upgrade lane waits while the queue is full was retired with 20261110141000: the lane is now gated on its own queue, see tests/fixtures/pdesc-reservation-settlement/gate-scenarios.sql)
-- a provider with a first (not register-fact) admission is never listed or upgraded
insert into pipeline.provider_description_reads(provider_id, state) values (pg_temp.pid(2), 'queued');
select 'first_admission|' || (pg_temp.run_worker(10)->'recorded')::text;
select 'first_admission_after|' || coalesce(security.provider_description_basic_profile_v1(pg_temp.pid(2))::text, 'null') || '|' || (security.provider_description_machine_blocked_v1(pg_temp.pid(2))->>'rule') || '|' || pg_temp.upg_sel(2)
  || '|' || (select a.tier || '/' || coalesce(a.before_description, 'null') from pipeline.provider_description_machine_admissions a where a.provider_id = pg_temp.pid(2));
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 7. queued reads that cannot pass the identity test are held (the queue fault), not skipped for ever
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.set_s('pdesc.acquire_direct', '1');
update catalogue.providers set website = null where id = pg_temp.pid(14);
insert into pipeline.provider_description_reads(provider_id, state, created_at, next_try_at) values (pg_temp.pid(14), 'queued', now() - interval '9 hours', now() - interval '9 hours');
select 'idhold_before|' || (select state from pipeline.provider_description_reads where provider_id = pg_temp.pid(14));
select 'idhold_lease|' || (pg_temp.run_worker(3)->>'leased');
select 'idhold_after|' || (select state || '/' || rule || '/' || (reason is not null)::text from pipeline.provider_description_reads where provider_id = pg_temp.pid(14));
-- a draft provider is not tested: its queued read is skipped as before (the earlier lease scenarios)
update pipeline.provider_description_reads set state = 'queued', rule = null, reason = null where provider_id = pg_temp.pid(14);
update catalogue.providers set publication_status = 'draft', website = null where id = pg_temp.pid(14);
select 'idhold_draft_ran|' || (pg_temp.run_worker(3) is not null)::text;
select 'idhold_draft|' || (select state from pipeline.provider_description_reads where provider_id = pg_temp.pid(14));
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 8. the identity hold takes only wrong_host and provider_host_conflict; a held read is offered again once the provider passes
-- the selection of the automatic queue for one provider (approved mode, as set in the blocks below)
create or replace function pg_temp.sel_missing(n int) returns text language sql as $f$
  select coalesce((select (x->>'eligibility_reason') || '/' || (x->>'eligible') from jsonb_array_elements(security.provider_description_selection_v1(jsonb_build_object('filter','all','size',60,'prefilter',true,'mode','approved'))->'providers') x
                    where (x->>'provider_id')::uuid = pg_temp.pid(n)), 'not_listed')
$f$;
create or replace function pg_temp.read_of(n int) returns text language sql as $f$
  select coalesce((select state || '/' || coalesce(rule, '-') || '/' || coalesce(checks->>'identity_hold', 'none') || '/' || coalesce(checks ? 'identity_checked_at', false)::text
                     from pipeline.provider_description_reads where provider_id = pg_temp.pid(n) order by created_at desc, id desc limit 1), 'no_read')
$f$;

-- 8a. no website: held with the mark; parked while the website is missing; offered again as soon as the website is corrected (no waiting for pdesc.recheck_days)
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.set_s('pdesc.acquire_direct', '1'); select pg_temp.set_s('pdesc.retry_minutes', '360'); -- the live value: a read held less than six hours ago is not retried on a changed page
update catalogue.providers set website = null where id = pg_temp.pid(14);
insert into pipeline.provider_description_reads(provider_id, state, created_at, next_try_at) values (pg_temp.pid(14), 'queued', now() - interval '9 hours', now() - interval '9 hours');
select 'reoffer_lease_ran|' || (pg_temp.run_worker(3) is not null)::text;
select 'reoffer_held|' || pg_temp.read_of(14);
select 'reoffer_no_website|' || pg_temp.sel_missing(14);
update catalogue.providers set website = 'https://p14.example.edu' where id = pg_temp.pid(14);
select 'reoffer_corrected|' || pg_temp.sel_missing(14);
-- the queue run takes what the selection lists, so the provider is read again at once
insert into pipeline.provider_description_reads(provider_id) values (pg_temp.pid(14));
select 'reoffer_read_again|' || (pg_temp.run_worker(3)->>'leased');
rollback;

-- 8b. a hold made by the worker (no mark) keeps its existing parking: only a read held by the identity hold is offered again
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.set_s('pdesc.acquire_direct', '1'); select pg_temp.set_s('pdesc.retry_minutes', '360');
insert into pipeline.provider_description_reads(provider_id, state, rule, reason) values (pg_temp.pid(14), 'held', 'wrong_host', 'fixture worker hold');
select 'worker_hold_parked|' || pg_temp.sel_missing(14);
rollback;

-- 8c. another provider holds the host: held (waits for a person to resolve the duplicate); offered again only when the host is resolved
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.set_s('pdesc.acquire_direct', '1'); select pg_temp.set_s('pdesc.retry_minutes', '360');
update catalogue.providers set website = (select website from catalogue.providers where id = pg_temp.pid(15)) where id = pg_temp.pid(14);
insert into pipeline.provider_description_reads(provider_id, state, created_at, next_try_at) values (pg_temp.pid(14), 'queued', now() - interval '9 hours', now() - interval '9 hours');
select 'conflict_lease_ran|' || (pg_temp.run_worker(3) is not null)::text;
select 'conflict_held|' || pg_temp.read_of(14);
select 'conflict_parked|' || pg_temp.sel_missing(14);
update catalogue.providers set website = 'https://p14.example.edu' where id = pg_temp.pid(14);
select 'conflict_resolved|' || pg_temp.sel_missing(14);
rollback;

-- 8d. every other identity outcome leaves the read queued: a provider whose lifecycle is held (provider_inactive)
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.set_s('pdesc.acquire_direct', '1');
insert into pipeline.provider_lifecycle_events(id, scope, provider_id, transition, effective_date, source, state) values (990001, 'provider', pg_temp.pid(14), 'temporarily_unavailable', current_date, 'fixture', 'executed');
insert into pipeline.provider_description_reads(provider_id, state, created_at, next_try_at) values (pg_temp.pid(14), 'queued', now() - interval '9 hours', now() - interval '9 hours');
select 'inactive_lease_ran|' || (pg_temp.run_worker(3) is not null)::text;
select 'inactive_kept|' || pg_temp.read_of(14);
rollback;

-- 8e. an open identity finding is not taken by the identity hold (the machine block, which has always held it, is unchanged)
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.set_s('pdesc.acquire_direct', '1');
insert into pipeline.provider_identity_findings(provider_id, check_code, reason) values (pg_temp.pid(14), 'identity_unconfirmed', 'fixture');
insert into pipeline.provider_description_reads(provider_id, state, created_at, next_try_at) values (pg_temp.pid(14), 'queued', now() - interval '9 hours', now() - interval '9 hours');
select 'finding_lease_ran|' || (pg_temp.run_worker(3) is not null)::text;
select 'finding_read|' || pg_temp.read_of(14);
rollback;

-- 8f. the reads tested longest ago go first: the oldest read, which passes and cannot be leased, is not tested on every call (batch.provider_description 1)
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.set_s('pdesc.acquire_direct', '1'); select pg_temp.set_s('batch.provider_description', '1');
update catalogue.providers set website = null where id = pg_temp.pid(14);
insert into pipeline.provider_description_reads(provider_id, state, tries, created_at, next_try_at) values (pg_temp.pid(15), 'queued', 3, now() - interval '10 hours', now() - interval '10 hours');
insert into pipeline.provider_description_reads(provider_id, state, created_at, next_try_at) values (pg_temp.pid(14), 'queued', now() - interval '9 hours', now() - interval '9 hours');
select 'rotate_call1|' || (pg_temp.run_worker(1)->>'leased') || '|' || pg_temp.read_of(15) || '|' || pg_temp.read_of(14);
select 'rotate_call2|' || (pg_temp.run_worker(1)->>'leased') || '|' || pg_temp.read_of(15) || '|' || pg_temp.read_of(14);
rollback;
