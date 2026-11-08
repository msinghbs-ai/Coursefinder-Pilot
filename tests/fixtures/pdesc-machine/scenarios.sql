-- Guards: F-PDESC (Platform Admin decision 9 Nov 2026, all-provider autonomous description delivery): machine admission (tiers stored and registry_factual), its objective rule, auto-settlement, withdrawal, scope for providers with no type, AU/NZ/CA queues, bounded dispatch and the empty-list setting.
-- Fixture data only (the provider-description-autonomy seed plus fictional register providers). Prints "<scenario>|<result>" lines; every block rolls back. Run by tests/fixtures/pdesc-machine/run.sh.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

-- ---------------------------------------------------------------------------------------------------------------- helpers
-- the worker step, as the real worker does it: lease with the reservation protocol, then record an answer for each leased item (the fixture's own recorded model answer, or an override)
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
create or replace function pg_temp.out(label text, v anyelement) returns void language plpgsql as $f$ begin raise notice '%|%', label, v; end $f$;
create or replace function pg_temp.queue(n int) returns void language plpgsql as $f$
begin
  insert into pipeline.provider_description_reads(provider_id, state) select pg_temp.pid(n), 'queued' on conflict do nothing;
end $f$;
create or replace function pg_temp.desc_of(n int) returns text language sql as $f$ select coalesce(description, '(none)') from catalogue.providers where id = pg_temp.pid(n) $f$;
-- the person who withdraws (the fixture's Platform Admin)
create or replace function pg_temp.wd(p uuid, r text) returns jsonb language sql as $f$ select security.provider_description_machine_withdraw_v1(p, r, '90000000-0000-0000-0000-000000000005'::uuid) $f$;
create or replace function pg_temp.items(n int, st text) returns bigint language sql as $f$ select count(*) from pipeline.layer4_review_items where entity_id = pg_temp.pid(n) and field_code = 'provider_description' and status = st $f$;

create or replace function pg_temp.try(q text) returns text language plpgsql as $f$
begin execute q; return 'ok'; exception when others then return sqlerrm; end $f$;
create or replace function pg_temp.try_as(p_uid uuid, q text) returns text language plpgsql as $f$
begin perform set_config('fx.uid', p_uid::text, true); execute q; return 'ok'; exception when others then return sqlerrm; end $f$;
-- a worker answer whose sentences carry the given words (quote and sentence say the same, so the existing validator passes them)
create or replace function pg_temp.answer(p_a text, p_b text) returns jsonb language sql as $f$
  select jsonb_build_object('about_page', true, 'sentences', jsonb_build_array(jsonb_build_object('text', p_a, 'quote', p_a), jsonb_build_object('text', p_b, 'quote', p_b)))
$f$;

select pg_temp.set_s('pdesc.machine_admit_on', '0');

-- ---------------------------------------------------------------------------------------------------------------- 1. off: the reader is exactly as before
begin;
select pg_temp.queue(1);
select pg_temp.run_worker(3) is not null;
select 'off_proposal_waits|' || pg_temp.items(1, 'pending') || '|' || pg_temp.desc_of(1) || '|' || (select count(*) from pipeline.provider_description_machine_admissions);
select 'off_selection_size_limit|' || pg_temp.try($$select security.provider_description_selection_v1('{"filter":"all","size":11}')$$);
select 'off_fire_sends_one|' || (security.provider_description_fire_v1()->>'sent');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 2. on: tier stored, admitted by the machine rule
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select pg_temp.queue(2);
select 'on_admitted_tally|' || (pg_temp.run_worker(3)->'recorded')::text;
select 'on_description|' || (pg_temp.desc_of(2) like 'Birch Valley University offers education%')::text;
select 'on_item_approved_no_wait|' || pg_temp.items(2, 'approved') || '|' || pg_temp.items(2, 'pending');
select 'on_decision_actor|' || (select d.actor_id::text || '|' || (d.layer2_state->>'machine_rule') || '|' || (d.layer2_state->>'actor_kind') || '|' || (d.reason like 'Auto (pdesc-machine-v1, tier stored)%' and d.reason like '%Not a person%')::text
  from pipeline.layer4_decisions d join pipeline.layer4_review_items li on li.id = d.review_item_id where li.entity_id = pg_temp.pid(2));
select 'on_read_admitted|' || (select r.state || '|' || (r.checks->>'actor_kind') from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(2) order by r.created_at desc limit 1);
select 'on_audit|' || (select a.tier || '|' || a.outcome || '|' || (a.before_description is null)::text || '|' || (a.after_description = pg_temp.desc_of(2))::text || '|' || (a.evidence_id is not null)::text || '|' || (jsonb_array_length(a.facts) = 2)::text
  from pipeline.provider_description_machine_admissions a where a.provider_id = pg_temp.pid(2));
select 'on_refresh_signal|' || (select count(*) from pipeline.search_refresh_signals where entity_id = pg_temp.pid(2));
select 'on_control_event|' || (select count(*) from pipeline.admin_control_events where area = 'layer4' and (detail->>'machine_rule') = 'pdesc-machine-v1' and (detail->>'provider_id')::uuid = pg_temp.pid(2));
-- admitted again: nothing (the description is held, one live admission per provider)
select 'on_second_admit_refused|' || (select (security.provider_description_machine_admit_v1(li.id))->>'rule' from pipeline.layer4_review_items li where li.entity_id = pg_temp.pid(2) limit 1);
-- withdrawal restores the empty description, keeps the audit and holds the provider out
select 'withdraw_no_reason|' || pg_temp.try($$select pg_temp.wd(pg_temp.pid(2), '  ')$$);
select 'withdraw_system_refused|' || pg_temp.try($$select security.provider_description_machine_withdraw_v1(pg_temp.pid(2), 'fixture', 'c0ffee00-0000-4000-8000-000000000150'::uuid)$$);
select 'withdraw|' || (r->>'ok') || '|' || coalesce(r->>'restored', 'null') from (select pg_temp.wd(pg_temp.pid(2), 'fixture rollback check') r) x;
select 'withdraw_result|' || pg_temp.desc_of(2) || '|' || (select withdrawn_reason || '|' || (withdrawn_at is not null)::text from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(2));
select 'withdraw_again|' || (pg_temp.wd(pg_temp.pid(2), 'fixture twice')->>'rule');
select 'withdrawn_gate|' || (security.provider_description_machine_gate_v1(pg_temp.pid(2), 'A harmless sentence about study.', '{}')->>'rule');
select 'withdraw_event|' || (select count(*) from pipeline.admin_control_events where action = 'pdesc_machine_withdraw');
rollback;

-- withdrawal is refused when a person changed the text since
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select pg_temp.queue(3);
select pg_temp.run_worker(3) is not null;
update catalogue.providers set description = 'A person rewrote this description by hand.' where id = pg_temp.pid(3);
select 'withdraw_person_edit|' || (pg_temp.wd(pg_temp.pid(3), 'fixture person edit')->>'rule') || '|' || pg_temp.desc_of(3);
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 3. on: what the machine rule does not admit waits for a person in Layer 4 with the exact reason on the item (while there is room); nothing is published
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select pg_temp.queue(4); select pg_temp.queue(5); select pg_temp.queue(6);
select 'decline_tally|' || ((pg_temp.run_worker(3, jsonb_build_object(
    pg_temp.pid(4)::text, pg_temp.answer('Dune Plains University has a campus in the desert region that teaches botany.', 'Its teaching and learning focus on arid landscapes and ecological restoration for study.'),
    pg_temp.pid(5)::text, pg_temp.answer('Elm Arts University offers music composition and theatre performance to its community.', 'Its programs include more than 40 courses in creative production and dramatic interpretation.'),
    pg_temp.pid(6)::text, pg_temp.answer('Fjord Technical University offers mechanical design and manufacturing systems study.', 'Its teaching and learning focus on industrial projects, with a pathway into mechanical laboratories.'))))->'recorded')::text;
select 'decline_campus|' || (select r.state || '|' || r.rule from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(4)) || '|' || pg_temp.items(4, 'pending') || '|' || pg_temp.desc_of(4);
select 'decline_figure|' || (select r.state || '|' || r.rule from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(5)) || '|' || pg_temp.items(5, 'pending');
select 'decline_extra_word|' || (select r.state || '|' || r.rule from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(6)) || '|' || pg_temp.items(6, 'pending');
select 'decline_proposal_kept|' || (select (r.proposal->>'description' is not null)::text from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(4));
-- a four-digit year is not a figure; a name with a marketing word is not a claim
select 'year_ok|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(4), 'Dune Plains University was founded in 1987 and teaches botany.'), 'clean');
select 'own_name_ok|' || coalesce((select security.pdesc_machine_text_check_v1(id, 'Premier Institute teaches welding.') from catalogue.providers where id = pg_temp.pid(4)), 'clean');
update catalogue.providers set canonical_name = 'Premier Institute' where id = pg_temp.pid(4);
select 'own_name_premier|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(4), 'Premier Institute teaches welding.'), 'clean') || '|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(4), 'It is a premier provider of welding.'), 'clean');
rollback;

-- the gate's other conditions
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('provider', pg_temp.pid(7), 'description', 'value');
select 'gate_lock|' || (security.provider_description_machine_gate_v1(pg_temp.pid(7), 'Study here.', '{}')->>'rule');
update catalogue.providers set description = 'A person wrote this.' where id = pg_temp.pid(8);
select 'gate_has_description|' || (security.provider_description_machine_gate_v1(pg_temp.pid(8), 'Study here.', '{}')->>'rule');
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, proposed_value, before_value) values ('provider', pg_temp.pid(9), 'provider_description', 'rejected', '{"description":"x"}', '{"description":null}');
select 'gate_human_rejection|' || (security.provider_description_machine_gate_v1(pg_temp.pid(9), 'Study here.', '{}')->>'rule');
insert into pipeline.provider_identity_findings(provider_id, check_code, state, reason) values (pg_temp.pid(10), 'identity_unconfirmed', 'open', 'fixture');
select 'gate_identity_finding|' || (security.provider_description_machine_gate_v1(pg_temp.pid(10), 'Study here.', '{}')->>'rule');
update catalogue.providers set publication_status = 'draft' where id = pg_temp.pid(11);
select 'gate_unpublished|' || (security.provider_description_machine_gate_v1(pg_temp.pid(11), 'Study here.', '{}')->>'rule');
select 'gate_clean|' || (security.provider_description_machine_gate_v1(pg_temp.pid(12), 'Study here.', '{}')->>'rule');
select pg_temp.set_s('pdesc.machine_admit_on', '0');
select 'gate_off|' || (security.provider_description_machine_gate_v1(pg_temp.pid(12), 'Study here.', '{}')->>'rule');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 4. the items already waiting are settled under the machine rule; the rest stay for a person
begin;
select pg_temp.queue(13); select pg_temp.queue(9);
select pg_temp.run_worker(3, jsonb_build_object(
    pg_temp.pid(13)::text, pg_temp.answer('Browser Cedar University teaches botanical science and plant conservation.', 'Its teaching and learning focus on garden research and ecological education for all fields.'))) is not null;
select 'waiting_before|' || pg_temp.items(13, 'pending') || '|' || pg_temp.items(9, 'pending');
-- provider 9's waiting item carries a word the rule does not pass, so it must stay for a person
update pipeline.layer4_review_items set proposed_value = jsonb_set(proposed_value, '{description}', to_jsonb('Inland Languages University offers scholarships in language study and its teaching focuses on archival research.'::text)) where entity_id = pg_temp.pid(9);
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select 'settle|' || (security.provider_description_machine_settle_pending_v1())::text;
select 'settle_13|' || pg_temp.items(13, 'approved') || '|' || (pg_temp.desc_of(13) like 'Browser Cedar University teaches%')::text || '|' || (select d.actor_id::text from pipeline.layer4_decisions d join pipeline.layer4_review_items li on li.id = d.review_item_id where li.entity_id = pg_temp.pid(13));
select 'settle_9|' || pg_temp.items(9, 'pending') || '|' || pg_temp.desc_of(9) || '|' || (select left(escalation_reason, 60) from pipeline.layer4_review_items where entity_id = pg_temp.pid(9)) || '|'
   || (select a.outcome || '|' || a.rule from pipeline.provider_description_machine_admissions a where a.provider_id = pg_temp.pid(9));
-- checked again at most hourly: the declined item is not tried twice in the hour and keeps one audit row
select 'settle_again|' || (security.provider_description_machine_settle_pending_v1())::text || '|' || (select count(*) from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(9));
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 5. tier registry_factual: a deterministic profile from the verified register listing, the provider record and the active courses
create or replace function pg_temp.reg_setup() returns void language plpgsql as $f$
declare v_sub uuid := gen_random_uuid(); v_l1 uuid := gen_random_uuid(); v_l2 uuid := gen_random_uuid(); v_f1 uuid := gen_random_uuid(); v_f2 uuid := gen_random_uuid(); v_ca uuid := gen_random_uuid();
begin
  insert into ref.subdivisions(id, country_id, code, name, status) values (v_sub, '00000000-0000-0000-0000-0000000000a1', 'FX-VIC', 'Victoria', 'active');
  insert into ref.subdivisions(id, country_id, code, name, status) values (v_ca, '00000000-0000-0000-0000-0000000000a3', 'FX-ON', 'Ontario', 'active');
  insert into ref.study_levels(code, name, id) values ('fx_bach', 'Bachelor', v_l1), ('fx_mast', 'Masters', v_l2);
  insert into ref.fields_of_study(id, name) values (v_f1, 'Business'), (v_f2, 'Engineering');
  update catalogue.providers set primary_city = 'MELBOURNE', subdivision_id = v_sub where id in (pg_temp.pid(1), pg_temp.pid(14));
  update catalogue.providers set primary_city = 'Toronto', subdivision_id = v_ca where id = pg_temp.pid(12);
  update catalogue.courses set study_level_id = v_l1, primary_field_id = v_f1 where id in (select id from catalogue.courses where provider_id = pg_temp.pid(1) and lifecycle_status = 'active' order by id limit 5);
  update catalogue.courses set study_level_id = v_l2, primary_field_id = v_f2 where id in (select id from catalogue.courses where provider_id = pg_temp.pid(1) and lifecycle_status = 'active' and study_level_id is null order by id limit 5);
end $f$;

begin;
select pg_temp.reg_setup();
select 'reg_profile|' || (p->>'ok') || '|' || (p->>'rule') || '|' || (p->>'text') from (select security.provider_description_registry_profile_v1(pg_temp.pid(1)) p) x;
select 'reg_profile_sources|' || (select string_agg(distinct f->>'source', ',' order by f->>'source') from jsonb_array_elements(security.provider_description_registry_profile_v1(pg_temp.pid(1))->'facts') f) || '|'
  || (select count(*) from jsonb_array_elements(security.provider_description_registry_profile_v1(pg_temp.pid(1))->'sentences') s where jsonb_array_length(s->'facts') > 0) || '|'
  || (security.provider_description_registry_profile_v1(pg_temp.pid(1))->>'source_url' is not null)::text;
-- too thin: type and register only
select 'reg_thin|' || (p->>'ok') || '|' || (p->>'rule') || '|' || (p->>'reason') from (select security.provider_description_registry_profile_v1(pg_temp.pid(11)) p) x;
select pg_temp.set_s('pdesc.registry_min_facts', '2');
select 'reg_thin_min2|' || (p->>'ok') || '|' || (p->>'text') from (select security.provider_description_registry_profile_v1(pg_temp.pid(11)) p) x;
select pg_temp.set_s('pdesc.registry_min_facts', '3');
-- a Canadian provider with no type: the scheme wording exists, the type fact does not, the location does
update ref.provider_types set code = code where false;
update catalogue.providers set provider_type_id = null where id = pg_temp.pid(12);
update catalogue.provider_registrations set registration_scheme = 'ircc_dli' where provider_id = pg_temp.pid(12);
select 'reg_ca_untyped|' || (p->>'ok') || '|' || (p->>'rule') || '|' || coalesce(p->>'reason', '') from (select security.provider_description_registry_profile_v1(pg_temp.pid(12)) p) x;
select pg_temp.set_s('pdesc.registry_min_facts', '2');
select 'reg_ca_untyped_min2|' || (p->>'ok') || '|' || (p->>'text') from (select security.provider_description_registry_profile_v1(pg_temp.pid(12)) p) x;
-- a junk city (a refused word) is not stated as a place
update catalogue.providers set primary_city = 'Campus Road' where id = pg_temp.pid(12);
select 'reg_junk_city|' || (p->>'ok') || '|' || coalesce(p->>'reason', p->>'text') from (select security.provider_description_registry_profile_v1(pg_temp.pid(12)) p) x;
-- no wording for the scheme, no register listing
update catalogue.provider_registrations set registration_scheme = 'fixture_ca' where provider_id = pg_temp.pid(12);
select 'reg_no_wording|' || (security.provider_description_registry_profile_v1(pg_temp.pid(12))->>'reason');
update catalogue.provider_registrations set status = 'inactive' where provider_id = pg_temp.pid(11);
select 'reg_no_listing|' || (security.provider_description_registry_profile_v1(pg_temp.pid(11))->>'reason');
rollback;

begin;
select pg_temp.reg_setup();
update catalogue.provider_registrations set evidence_id = (select evidence_id from catalogue.provider_registrations where provider_id = pg_temp.pid(2)), status = 'active' where provider_id = pg_temp.pid(14);
-- off: the tier does nothing
select 'tier_off|' || (security.provider_description_registry_tier_v1())::text;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select 'tier_off_registry_switch|' || (security.provider_description_registry_tier_v1())::text;
select pg_temp.set_s('pdesc.registry_factual_on', '1');
-- 14 has no website and no stored page (qualifies); 10 held on an unreadable page (qualifies, too thin); 2 has a website and a stored page (does not qualify)
update catalogue.providers set website = null where id = pg_temp.pid(14);
insert into pipeline.provider_description_reads(provider_id, state, rule, reason) values (pg_temp.pid(10), 'held', 'no_about_page', 'fixture: no about page');
select pg_temp.set_s('pdesc.registry_after_rules', '["no_about_page"]');
select 'tier_run|' || (security.provider_description_registry_tier_v1())::text;
select 'tier_admitted|' || pg_temp.desc_of(14) || '|' || pg_temp.items(14, 'approved');
select 'tier_audit|' || (select a.tier || '|' || a.rule || '|' || a.outcome || '|' || (a.actor = 'c0ffee00-0000-4000-8000-000000000150')::text || '|' || (a.evidence_id is not null)::text from pipeline.provider_description_machine_admissions a where a.provider_id = pg_temp.pid(14));
select 'tier_decision|' || (select d.layer2_state->>'machine_rule' || '|' || (d.layer2_state->>'tier') || '|' || (d.reason like '%Not a person%')::text from pipeline.layer4_decisions d join pipeline.layer4_review_items li on li.id = d.review_item_id where li.entity_id = pg_temp.pid(14));
select 'tier_thin_held|' || (select string_agg(r.state || '/' || r.rule, ',' order by r.rule) from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(10)) || '|' || pg_temp.desc_of(10) || '|' || pg_temp.items(10, 'pending');
select 'tier_not_touched|' || pg_temp.desc_of(2) || '|' || (select count(*) from pipeline.provider_description_reads where provider_id = pg_temp.pid(2));
-- idempotent: a second run finds nothing to do (14 has its description, 10 was held for the recheck window)
select 'tier_again|' || (security.provider_description_registry_tier_v1())::text;
-- the withdrawal of a registry description works the same way
select 'tier_withdraw|' || (pg_temp.wd(pg_temp.pid(14), 'fixture withdraw registry')->>'ok') || '|' || pg_temp.desc_of(14);
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 6. scope: an empty type list is every type, a provider with no type is "unclassified"
begin;
update catalogue.providers set provider_type_id = null where id = pg_temp.pid(12);
select 'scope_default|' || security.provider_description_scope_v1(pg_temp.pid(11))::text || '|' || security.provider_description_scope_v1(pg_temp.pid(12))::text;
select pg_temp.set_s('pdesc.provider_types', '["unclassified"]');
select 'scope_unclassified|' || security.provider_description_scope_v1(pg_temp.pid(11))::text || '|' || security.provider_description_scope_v1(pg_temp.pid(12))::text;
select pg_temp.set_s('pdesc.provider_types', '["university", "unclassified"]');
select 'scope_both|' || security.provider_description_scope_v1(pg_temp.pid(11))::text || '|' || security.provider_description_scope_v1(pg_temp.pid(12))::text;
select pg_temp.set_s('pdesc.provider_types', '[]');
select 'scope_empty_all|' || security.provider_description_scope_v1(pg_temp.pid(11))::text || '|' || security.provider_description_scope_v1(pg_temp.pid(12))::text || '|' || security.pdesc_type_in_scope_v1(null)::text || '|' || security.pdesc_type_in_scope_v1('tafe')::text;
select pg_temp.set_s('pdesc.provider_keys', '[]');
select 'scope_empty_keys_all|' || (select count(*) from catalogue.providers p where security.provider_description_scope_v1(p.id)) || '|' || (select count(*) from catalogue.providers p where p.lifecycle_status = 'active' and p.publication_status = 'published');
select pg_temp.set_s('pdesc.countries', '["NZ"]');
select 'scope_country|' || (select count(*) from catalogue.providers p where security.provider_description_scope_v1(p.id));
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 7. list settings: empty is allowed where the setting says so
begin;
select 'set_empty_keys|' || pg_temp.try_as('90000000-0000-0000-0000-000000000005', $$select public.admin_toolsets_write('setting', '{"toolset":"pipeline","key":"pdesc.provider_keys","value":[],"reason":"fixture check"}')$$);
select 'set_empty_keys_now|' || (select value::text from pipeline.platform_toolset_settings where key = 'pdesc.provider_keys');
select 'set_empty_types|' || pg_temp.try_as('90000000-0000-0000-0000-000000000005', $$select public.admin_toolsets_write('setting', '{"toolset":"pipeline","key":"pdesc.provider_types","value":[],"reason":"fixture check"}')$$);
select 'set_empty_types_now|' || (select value::text from pipeline.platform_toolset_settings where key = 'pdesc.provider_types');
select 'set_empty_countries|' || pg_temp.try_as('90000000-0000-0000-0000-000000000005', $$select public.admin_toolsets_write('setting', '{"toolset":"pipeline","key":"pdesc.countries","value":[],"reason":"fixture check"}')$$);
select 'set_countries_ok|' || pg_temp.try_as('90000000-0000-0000-0000-000000000005', $$select public.admin_toolsets_write('setting', '{"toolset":"pipeline","key":"pdesc.countries","value":["AU","NZ","CA"],"reason":"fixture check"}')$$);
select 'set_not_a_person|' || pg_temp.try_as('90000000-0000-0000-0000-000000000003', $$select public.admin_toolsets_write('setting', '{"toolset":"pipeline","key":"pdesc.provider_keys","value":[],"reason":"fixture check"}')$$);
-- a list setting with no minimum is untouched by the new rule
select 'set_other_list|' || pg_temp.try_as('90000000-0000-0000-0000-000000000005', $$select public.admin_toolsets_write('setting', '{"toolset":"pipeline","key":"pdesc.machine_refused_words","value":[],"reason":"fixture check"}')$$);
select 'set_audit|' || (select count(*) from pipeline.admin_control_events where area = 'toolsets' and action = 'setting');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 8. queues: one bounded queue a country, sized from what is left
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.set_s('pdesc.provider_keys', '[]'); select pg_temp.set_s('pdesc.target_hours', '1');
select 'tp_shape|' || (t->>'remaining_total') || '|' || (select string_agg(k || '=' || (t->'remaining_by_country'->>k), ',' order by k) from jsonb_object_keys(t->'remaining_by_country') k) || '|' || (t->>'enqueue_size') || '|' || (t->>'runs_in_target')
  from (select security.provider_description_throughput_v1() t) x;
select 'enqueue_on|' || security.provider_description_enqueue_v1();
select 'queued_by_country|' || (select string_agg(k.iso_alpha2 || '=' || n, ',' order by k.iso_alpha2) from (select p.country_id, count(*) n from pipeline.provider_description_reads r join catalogue.providers p on p.id = r.provider_id where r.state = 'queued' group by p.country_id) q join ref.countries k on k.id = q.country_id);
select 'enqueue_again|' || security.provider_description_enqueue_v1();
rollback;
begin;
-- the size follows target_hours: spread over twelve hourly runs, a run adds a twelfth, and never more than the cap
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.set_s('pdesc.provider_keys', '[]'); select pg_temp.set_s('pdesc.target_hours', '12');
select 'tp_spread|' || (t->>'runs_in_target') || '|' || (t->>'enqueue_size') || '|' || (t->>'queue_target') from (select security.provider_description_throughput_v1() t) x;
select pg_temp.set_s('pdesc.queue_cap', '1'); select pg_temp.set_s('pdesc.target_hours', '1');
select 'tp_cap|' || (t->>'enqueue_size') from (select security.provider_description_throughput_v1() t) x;
rollback;
begin;
-- OFF: the old single queue (queue_per_run) is what enqueue adds
select pg_temp.set_s('pdesc.provider_keys', '[]'); select pg_temp.set_s('pdesc.queue_per_run', '2');
select 'enqueue_off|' || security.provider_description_enqueue_v1();
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 9. the lease: work in progress bounded by concurrency and spend; the quietest country first
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select pg_temp.queue(1); select pg_temp.queue(2); select pg_temp.queue(3); select pg_temp.queue(11); select pg_temp.queue(12);
select pg_temp.set_s('pdesc.concurrency_max', '1');
select 'lease_concurrency|' || jsonb_array_length(public.svc_provider_description_lease_v1(3, null, 'provider-description-reserve-v1')->'items');
select 'lease_concurrency_full|' || coalesce(public.svc_provider_description_lease_v1(3, null, 'provider-description-reserve-v1')->>'reason', 'leased');
rollback;
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select pg_temp.queue(1); select pg_temp.queue(11);
select pg_temp.set_s('pdesc.ai_usd_max', '0.002');
select 'lease_spend|' || coalesce(public.svc_provider_description_lease_v1(3, null, 'provider-description-reserve-v1')->>'reason', 'leased');
rollback;
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
-- Australia has just been read; New Zealand and Canada have not: the lease starts with them
insert into pipeline.provider_description_reads(provider_id, state, rule) values (pg_temp.pid(4), 'held', 'fixture_recent');
select pg_temp.queue(1); select pg_temp.queue(11);
select 'lease_fair|' || (public.svc_provider_description_lease_v1(1, null, 'provider-description-reserve-v1')->'items'->0->>'country');
rollback;
begin;
-- OFF: the Layer 4 waiting cap still holds the reader back
select pg_temp.queue(1);
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, proposed_value, before_value)
  select 'provider', pg_temp.pid(n), 'provider_description', 'pending', '{"description":"x"}', '{"description":null}' from generate_series(5, 8) n;
select pg_temp.set_s('pdesc.pending_max', '3');
select 'lease_off_waiting_cap|' || coalesce(public.svc_provider_description_lease_v1(3, null, 'provider-description-reserve-v1')->>'reason', 'leased');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 10. dispatch: as many worker calls as the due reads need, up to pdesc.dispatch_max (one when off)
create or replace function pg_temp.fire_case(p_on int, p_queued int, p_dispatch int) returns text language plpgsql as $f$
declare v_keys jsonb; v jsonb; v_n int;
begin
  select jsonb_agg('fixture:provider:' || g) into v_keys from generate_series(1, p_queued) g;
  perform pg_temp.set_s('pdesc.provider_keys', v_keys);
  perform pg_temp.set_s('pdesc.machine_admit_on', p_on::text::jsonb);
  perform pg_temp.set_s('pdesc.dispatch_max', p_dispatch::text::jsonb);
  perform pg_temp.queue(g) from generate_series(1, p_queued) g;
  v := security.provider_description_fire_v1();
  select count(*) into v_n from fixture.worker_dispatches;
  return (v->>'due') || '|' || (v->>'sent') || '|' || v_n;
end $f$;
begin; select 'fire_on_7_max2|' || pg_temp.fire_case(1, 7, 2); rollback;
begin; select 'fire_on_7_max3|' || pg_temp.fire_case(1, 7, 3); rollback;
begin; select 'fire_on_2_max3|' || pg_temp.fire_case(1, 2, 3); rollback;
begin; select 'fire_off_7_max3|' || pg_temp.fire_case(0, 7, 3); rollback;
begin;
-- the hourly floor still holds: a second run inside pdesc.every_minutes sends nothing
select 'fire_first|' || pg_temp.fire_case(1, 4, 3);
select 'fire_second|' || (security.provider_description_fire_v1()->>'sent');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 11. consumer parity: the existing read-back of the Website and Zoho sees the machine-admitted description
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select pg_temp.queue(2);
select pg_temp.run_worker(3) is not null;
select 'parity_before|' || (select coalesce(consumer_checks::text, 'not checked') from pipeline.provider_description_reads where provider_id = pg_temp.pid(2));
select 'parity_check_ran|' || security.provider_description_publication_check_v1();
select 'parity_after|' || (select (consumer_checks->>'website_verified') || '|' || (consumer_checks->>'zoho_verified') || '|' || (published_at is not null)::text || '|' || (zoho_published_at is not null)::text from pipeline.provider_description_reads where provider_id = pg_temp.pid(2));
select 'parity_website_text|' || (public.website_v2_provider('fixture:provider:2')->'item'->>'description' = pg_temp.desc_of(2))::text;
select 'report_parity|' || (r->'parity'->>'admitted') || '|' || (r->'parity'->>'website_verified') || '|' || (r->'parity'->>'zoho_verified') || '|' || (r->'parity'->>'not_yet_checked') || '|' || jsonb_array_length(r->'parity'->'mismatched')
  from (select security.provider_description_machine_report_v1() r) x;
select 'report_tiers|' || (r->'tiers')::text || '|' || (r->'providers'->'AU'->>'machine_admitted') || '|' || (r->'providers'->'AU'->>'described') from (select security.provider_description_machine_report_v1() r) x;
-- withdrawn: the description leaves the Website read and the parity count
select pg_temp.wd(pg_temp.pid(2), 'fixture parity withdraw') is not null;
select 'parity_withdrawn|' || coalesce(public.website_v2_provider('fixture:provider:2')->'item'->>'description', 'null') || '|' || (security.provider_description_machine_report_v1()->'parity'->>'admitted');
rollback;
begin;
-- a text the Website does not show is reported as a mismatch, never as verified
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select pg_temp.queue(3); select pg_temp.run_worker(3) is not null;
select security.provider_description_publication_check_v1() is not null;
update pipeline.provider_description_reads set consumer_checks = jsonb_set(consumer_checks, '{website_verified}', 'false') where provider_id = pg_temp.pid(3);
select 'report_mismatch|' || jsonb_array_length(security.provider_description_machine_report_v1()->'parity'->'mismatched');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 12. QA B1: withdrawal against the production constraints (one refresh signal for each decision, hand locks, guards)
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select pg_temp.queue(2); select pg_temp.run_worker(3) is not null;
-- the signal the admission queued has been worked off; production allows ONE signal for each decision, so the withdrawal queues that same signal again
update pipeline.search_refresh_signals set status = 'completed', completed_at = now() where entity_id = pg_temp.pid(2);
select 'b1_signal_before|' || (select count(*) || '|' || min(status) from pipeline.search_refresh_signals where entity_id = pg_temp.pid(2));
select 'b1_withdraw|' || (pg_temp.wd(pg_temp.pid(2), 'fixture production shape')->>'ok') || '|' || pg_temp.desc_of(2);
select 'b1_signal_after|' || (select count(*) || '|' || min(status) || '|' || (min(completed_at) is null)::text || '|' || (min(reason) like 'Machine description withdrawn:%')::text from pipeline.search_refresh_signals where entity_id = pg_temp.pid(2));
select 'b1_actor|' || (select (withdrawn_by = '90000000-0000-0000-0000-000000000005'::uuid)::text from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(2))
   || '|' || (select (actor = '90000000-0000-0000-0000-000000000005'::uuid)::text from pipeline.admin_control_events where action = 'pdesc_machine_withdraw');
-- a signal a worker is processing stays processing
rollback;
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select pg_temp.queue(2); select pg_temp.run_worker(3) is not null;
update pipeline.search_refresh_signals set status = 'processing' where entity_id = pg_temp.pid(2);
select pg_temp.wd(pg_temp.pid(2), 'fixture processing') is not null;
select 'b1_signal_processing|' || (select count(*) || '|' || min(status) from pipeline.search_refresh_signals where entity_id = pg_temp.pid(2));
rollback;
-- a hand lock added after the admission: refused, nothing logged as restored
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select pg_temp.queue(2); select pg_temp.run_worker(3) is not null;
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('provider', pg_temp.pid(2), 'description', 'value');
select 'b1_lock|' || (pg_temp.wd(pg_temp.pid(2), 'fixture lock after admission')->>'rule') || '|' || (pg_temp.desc_of(2) like 'Birch Valley University offers education%')::text
   || '|' || (select (withdrawn_at is null)::text from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(2))
   || '|' || (select count(*) from pipeline.admin_control_events where action = 'pdesc_machine_withdraw')
   || '|' || (select count(*) from pipeline.search_refresh_signals where entity_id = pg_temp.pid(2));
rollback;
-- a lock on another field does not stop the withdrawal
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select pg_temp.queue(2); select pg_temp.run_worker(3) is not null;
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('provider', pg_temp.pid(2), 'website', 'value');
select 'b1_other_lock|' || (pg_temp.wd(pg_temp.pid(2), 'fixture other lock')->>'ok') || '|' || pg_temp.desc_of(2);
rollback;
-- a guard (a trigger) that puts the earlier text back without a lock: the withdrawal stops and changes nothing, it does not log "restored"
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select pg_temp.queue(2); select pg_temp.run_worker(3) is not null;
create function pg_temp.keep_desc() returns trigger language plpgsql as $f$ begin NEW.description := OLD.description; return NEW; end $f$;
create trigger zz_keep_desc before update on catalogue.providers for each row execute function pg_temp.keep_desc();
select 'b1_guard|' || pg_temp.try($$select pg_temp.wd(pg_temp.pid(2), 'fixture guard')$$) || '|' || (pg_temp.desc_of(2) like 'Birch Valley University offers education%')::text
   || '|' || (select (withdrawn_at is null)::text from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(2))
   || '|' || (select count(*) from pipeline.admin_control_events where action = 'pdesc_machine_withdraw');
rollback;
-- the same guard on admission: the item waits, no audit row says it was published
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
create function pg_temp.keep_desc() returns trigger language plpgsql as $f$ begin NEW.description := OLD.description; return NEW; end $f$;
create trigger zz_keep_desc before update on catalogue.providers for each row execute function pg_temp.keep_desc();
select pg_temp.queue(2); select pg_temp.run_worker(3) is not null;
select 'b1_admit_guard|' || pg_temp.items(2, 'pending') || '|' || pg_temp.desc_of(2) || '|' || (select count(*) from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(2) and outcome = 'admitted')
   || '|' || (select state from pipeline.provider_description_reads where provider_id = pg_temp.pid(2));
rollback;
-- the app function: Platform Admin only, the person is recorded
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select pg_temp.queue(2); select pg_temp.run_worker(3) is not null;
select 'b1_wrapper_not_admin|' || pg_temp.try_as('90000000-0000-0000-0000-000000000003', $$select public.admin_provider_description_machine_withdraw_v1(pg_temp.pid(2), 'fixture not admin')$$);
select 'b1_wrapper_anon|' || pg_temp.try_as(null, $$select public.admin_provider_description_machine_withdraw_v1(pg_temp.pid(2), 'fixture anon')$$);
create temp table wrap_res as select pg_temp.try_as('90000000-0000-0000-0000-000000000005', $$select public.admin_provider_description_machine_withdraw_v1(pg_temp.pid(2), 'fixture admin')$$) as r; -- its own statement: the read-back below must see the withdrawal
select 'b1_wrapper|' || (select r from wrap_res) || '|' || pg_temp.desc_of(2)
   || '|' || coalesce((select (withdrawn_by = '90000000-0000-0000-0000-000000000005'::uuid)::text from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(2)), '(no row)');
drop table wrap_res;
rollback;
select 'b1_grants|' || has_function_privilege('anon', 'public.admin_provider_description_machine_withdraw_v1(uuid,text)', 'execute')::text || '|' || has_function_privilege('authenticated', 'public.admin_provider_description_machine_withdraw_v1(uuid,text)', 'execute')::text
   || '|' || has_function_privilege('authenticated', 'security.provider_description_machine_withdraw_v1(uuid,text,uuid)', 'execute')::text || '|' || has_function_privilege('anon', 'security.provider_description_machine_withdraw_v1(uuid,text,uuid)', 'execute')::text;

-- ---------------------------------------------------------------------------------------------------------------- 13. QA N6/N3: what the text rule refuses waits for a person (bounded); anything else is held with the proposal
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select pg_temp.queue(4); select pg_temp.queue(5);
select 'n6_tally|' || ((pg_temp.run_worker(3, jsonb_build_object(
    pg_temp.pid(4)::text, pg_temp.answer('Dune Plains University has a campus in the desert region that teaches botany.', 'Its teaching and learning focus on arid landscapes and ecological restoration for study.'),
    pg_temp.pid(5)::text, pg_temp.answer('Elm Arts University offers music composition and theatre performance to its community.', 'Its programs include more than 40 courses in creative production and dramatic interpretation.'))))->'recorded')::text;
select 'n6_waits|' || (select r.state || '|' || r.rule from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(4)) || '|' || pg_temp.items(4, 'pending') || '|' || pg_temp.desc_of(4);
select 'n6_item_reason|' || (select left(escalation_reason, 80) from pipeline.layer4_review_items where entity_id = pg_temp.pid(4) and status = 'pending');
select 'n6_audit|' || (select a.outcome || '|' || a.rule || '|' || (a.reason like '%word, figure or markup%')::text from pipeline.provider_description_machine_admissions a where a.provider_id = pg_temp.pid(4));
select 'n6_both_wait|' || pg_temp.items(5, 'pending');
rollback;
begin;
-- N3: the waiting places are bounded; beyond them the proposal is held whole, with the reason, and nothing is dropped
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.set_s('pdesc.machine_pending_max', '1');
select pg_temp.queue(4); select pg_temp.queue(5);
select pg_temp.run_worker(3, jsonb_build_object(
    pg_temp.pid(4)::text, pg_temp.answer('Dune Plains University has a campus in the desert region that teaches botany.', 'Its teaching and learning focus on arid landscapes and ecological restoration for study.'),
    pg_temp.pid(5)::text, pg_temp.answer('Elm Arts University offers music composition and theatre performance to its community.', 'Its programs include more than 40 courses in creative production and dramatic interpretation.'))) is not null;
select 'n3_cap|' || (select count(*) from pipeline.layer4_review_items where field_code = 'provider_description' and status = 'pending' and entity_id in (pg_temp.pid(4), pg_temp.pid(5)))
   || '|' || (select string_agg(r.state || '/' || r.rule, ',' order by r.state) from pipeline.provider_description_reads r where r.provider_id in (pg_temp.pid(4), pg_temp.pid(5)))
   || '|' || (select count(*) from pipeline.provider_description_reads r where r.provider_id in (pg_temp.pid(4), pg_temp.pid(5)) and r.state = 'held' and r.proposal->>'description' is not null and r.reason like '%pdesc.machine_pending_max%');
rollback;
begin;
-- the old waiting cap (pdesc.pending_max = 10) does not stop an automatic run once more than ten wait
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.set_s('pdesc.pending_max', '1');
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, proposed_value, before_value)
  select 'provider', pg_temp.pid(n), 'provider_description', 'pending', '{"description":"x"}', '{"description":null}' from generate_series(5, 8) n;
select pg_temp.queue(2);
select 'n3_old_cap_ignored|' || jsonb_array_length(public.svc_provider_description_lease_v1(3, null, 'provider-description-reserve-v1')->'items');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 14. QA N6/N7/N11: a provider the rule must not describe is held before any AI call
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
-- locked by hand; an earlier human rejection; a description already held; a description cleared by hand after a machine admission
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('provider', pg_temp.pid(7), 'description', 'value');
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, proposed_value, before_value) values ('provider', pg_temp.pid(9), 'provider_description', 'rejected', '{"description":"x"}', '{"description":null}');
update catalogue.providers set description = 'A person wrote this description.' where id = pg_temp.pid(8);
select pg_temp.queue(2); select pg_temp.run_worker(3) is not null;
update catalogue.providers set description = null where id = pg_temp.pid(2);
select pg_temp.queue(2); select pg_temp.queue(7); select pg_temp.queue(8); select pg_temp.queue(9); select pg_temp.queue(12);
select 'n6_lease|' || jsonb_array_length(public.svc_provider_description_lease_v1(5, null, 'provider-description-reserve-v1')->'items');
select 'n6_held|' || (select string_agg(pg_temp_n.n || '=' || r.state || '/' || r.rule, ',' order by pg_temp_n.n) from (values (2), (7), (8), (9), (12)) pg_temp_n(n)
   join pipeline.provider_description_reads r on r.provider_id = pg_temp.pid(pg_temp_n.n) and r.state = 'held');
select 'n6_no_ai|' || (select coalesce(sum(ai_calls), 0) from pipeline.provider_description_reads where provider_id in (pg_temp.pid(7), pg_temp.pid(8), pg_temp.pid(9)));
-- the same providers are listed with the reason by the reader's selection and are never queued
select 'n6_selection|' || (select string_agg(x->>'eligibility_reason', ',' order by x->>'name') from jsonb_array_elements(security.provider_description_selection_v1(jsonb_build_object('filter', 'all', 'size', 50, 'prefilter', true, 'provider_id', pg_temp.pid(7)))->'providers') x);
rollback;
begin;
-- a described provider is not selected for a read again (N11) once the reader is automatic, though the older rule re-read it after pdesc.recheck_days
update catalogue.providers set description = 'A person wrote this description.' where id = pg_temp.pid(8);
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select 'n11_prefilter|' || (select count(*) from jsonb_array_elements(security.provider_description_selection_v1('{"filter":"all","size":60,"prefilter":true}')->'providers') x where x->>'current_description' is not null)
   || '|' || (select count(*) from jsonb_array_elements(security.provider_description_selection_v1('{"filter":"all","size":60,"prefilter":false}')->'providers') x where x->>'current_description' is not null);
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 15. QA N8/N1: names, markup, French pages, the year limits
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1');
update catalogue.providers set canonical_name = 'N/A', display_name = null where id = pg_temp.pid(4);
update catalogue.providers set canonical_name = 'NA' where id = pg_temp.pid(5);
update catalogue.providers set canonical_name = 'St Mary&#039;s College' where id = pg_temp.pid(6);
update catalogue.providers set display_name = 'TBC' where id = pg_temp.pid(8);
select 'n8_names|' || (security.provider_description_machine_gate_v1(pg_temp.pid(4), 'Study here with us.', '{}')->>'rule') || '|' || (security.provider_description_machine_gate_v1(pg_temp.pid(5), 'Study here with us.', '{}')->>'rule')
   || '|' || (security.provider_description_machine_gate_v1(pg_temp.pid(6), 'Study here with us.', '{}')->>'rule') || '|' || (security.provider_description_machine_gate_v1(pg_temp.pid(8), 'Study here with us.', '{}')->>'rule')
   || '|' || (security.provider_description_machine_gate_v1(pg_temp.pid(12), 'Study here with us.', '{}')->>'rule');
select 'n8_clean_name|' || coalesce(security.pdesc_clean_name_v1('N/A'), 'null') || '|' || coalesce(security.pdesc_clean_name_v1('Na'), 'null') || '|' || coalesce(security.pdesc_clean_name_v1('Nanyang Institute'), 'null') || '|' || coalesce(security.pdesc_clean_name_v1('A&amp;B College'), 'null') || '|' || coalesce(security.pdesc_clean_name_v1('Ab'), 'null');
select 'n8_text_markup|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(12), 'The college teaches carpentry and it was founded by St Mary&#039;s Trust.'), 'clean');
select 'n8_french_claim|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(12), 'Ce collège est classé parmi les meilleures écoles de la région.'), 'clean');
select 'n8_french_accent|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(12), 'Les étudiants y apprennent la menuiserie et la plomberie.'), 'clean') || '|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(12), 'Les etudiants y apprennent la menuiserie.'), 'clean');
select 'n8_french_clean|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(12), 'Le collège enseigne la menuiserie et la plomberie à Toronto.'), 'clean');
select 'n8_french_fees|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(12), 'Les frais de scolarité sont publiés sur le site du collège.'), 'clean');
select 'n1_year|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(12), 'The school opened in 1700 and teaches carpentry.'), 'clean') || '|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(12), 'The school opened in 1987 and teaches carpentry.'), 'clean')
;
select pg_temp.set_s('pdesc.founded_year_min', '1600');
select 'n1_year_setting|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(12), 'The school opened in 1700 and teaches carpentry.'), 'clean');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 16. QA N10: a register-fact profile obeys the description limits
begin;
select pg_temp.reg_setup();
select pg_temp.set_s('pdesc.registry_min_facts', '2');
select 'n10_default|' || (p->>'ok') || '|' || length(p->>'text') from (select security.provider_description_registry_profile_v1(pg_temp.pid(11)) p) x;
select pg_temp.set_s('pdesc.min_chars', '200');
select 'n10_min_chars|' || (p->>'ok') || '|' || (p->>'rule') || '|' || (p->>'reason') from (select security.provider_description_registry_profile_v1(pg_temp.pid(11)) p) x;
select pg_temp.set_s('pdesc.min_chars', '100');
select pg_temp.set_s('pdesc.min_sentences', '3');
select 'n10_min_sentences|' || (p->>'ok') || '|' || (p->>'reason') from (select security.provider_description_registry_profile_v1(pg_temp.pid(11)) p) x;
select pg_temp.set_s('pdesc.min_sentences', '2'); select pg_temp.set_s('pdesc.max_sentences', '1');
select 'n10_max_sentences|' || (p->>'ok') || '|' || (p->>'reason') from (select security.provider_description_registry_profile_v1(pg_temp.pid(11)) p) x;
-- a placeholder name leaves no profile
select pg_temp.set_s('pdesc.max_sentences', '5');
update catalogue.providers set canonical_name = 'N/A', display_name = 'TBC' where id = pg_temp.pid(11);
select 'n10_no_name|' || (p->>'ok') || '|' || (p->>'reason') from (select security.provider_description_registry_profile_v1(pg_temp.pid(11)) p) x;
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 17. QA N4: Firecrawl reads held by calls in flight are not granted again
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.set_s('pdesc.acquire_direct', '1'); select pg_temp.set_s('pdesc.acquire_firecrawl', '1');
select pg_temp.set_s('pdesc.firecrawl_reads_max', '8'); select pg_temp.set_s('pdesc.firecrawl_per_call', '5');
select pg_temp.queue(1); select pg_temp.queue(2); select pg_temp.queue(3); select pg_temp.queue(11); select pg_temp.queue(12); select pg_temp.queue(14);
select 'n4_grants|' || (public.svc_provider_description_lease_v1(2, null, 'provider-description-reserve-v1')->>'firecrawl_left') || ',' || (public.svc_provider_description_lease_v1(2, null, 'provider-description-reserve-v1')->>'firecrawl_left')
   || ',' || (public.svc_provider_description_lease_v1(2, null, 'provider-description-reserve-v1')->>'firecrawl_left');
select 'n4_reserved|' || (select coalesce(sum((checks->>'firecrawl_reserved')::int), 0) from pipeline.provider_description_reads where state = 'reading');
rollback;
begin;
-- off: the older rule, every call is told what the ceiling still allows
select pg_temp.set_s('pdesc.acquire_direct', '1'); select pg_temp.set_s('pdesc.acquire_firecrawl', '1'); select pg_temp.set_s('pdesc.firecrawl_reads_max', '8');
select pg_temp.queue(1); select pg_temp.queue(2);
select 'n4_off|' || (public.svc_provider_description_lease_v1(1, null, 'provider-description-reserve-v1')->>'firecrawl_left') || ',' || (public.svc_provider_description_lease_v1(1, null, 'provider-description-reserve-v1')->>'firecrawl_left');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 18. QA B2: the reader looks at a bounded slice and rotates
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.set_s('pdesc.provider_keys', '[]'); select pg_temp.set_s('pdesc.target_hours', '1'); select pg_temp.set_s('pdesc.scan_factor', '1'); select pg_temp.set_s('pdesc.acquire_direct', '1');
select 'b2_slice_one|' || (security.provider_description_selection_v1('{"filter":"all","size":1,"prefilter":true,"mode":"approved","country":"AU"}')->>'size') || '|'
   || coalesce(jsonb_array_length(security.provider_description_selection_v1('{"filter":"all","size":1,"prefilter":true,"mode":"approved","country":"AU"}')->'providers')::text, 'null');
select 'b2_enqueue|' || security.provider_description_enqueue_v1();
select 'b2_marks|' || (select (count(*) > 0)::text from pipeline.provider_description_scan_marks);
-- the providers just looked at go to the back: a second slice starts with providers not yet looked at
select 'b2_rotation|' || (select (min(m.scanned_at) is null)::text from (select (x->>'provider_id')::uuid pid from jsonb_array_elements(security.provider_description_selection_v1('{"filter":"all","size":1,"prefilter":true,"mode":"approved","country":"AU"}')->'providers') x) s left join pipeline.provider_description_scan_marks m on m.provider_id = s.pid);
rollback;
begin;
-- the funnel counts from the register in one pass above pdesc.funnel_detail_max, with the same answer here
select pg_temp.set_s('pdesc.provider_keys', '[]');
select set_config('fx.uid', '90000000-0000-0000-0000-000000000005', true) is not null;
select 'b2_funnel_exact|' || (select string_agg((s->>'key') || '=' || (s->>'n'), ',' order by s->>'key') from jsonb_array_elements(public.admin_provider_description_funnel_v1()->'stages') s where s->>'key' in ('identity_clear', 'stored_page', 'run_scope', 'policy_scope'));
select pg_temp.set_s('pdesc.funnel_detail_max', '10');
select 'b2_funnel_counted|' || (select string_agg((s->>'key') || '=' || (s->>'n'), ',' order by s->>'key') from jsonb_array_elements(public.admin_provider_description_funnel_v1()->'stages') s where s->>'key' in ('identity_clear', 'stored_page', 'run_scope', 'policy_scope'));
rollback;
