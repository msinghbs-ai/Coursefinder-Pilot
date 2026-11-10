-- Guards: Platform Admin order 10 Nov 2026 12:07 (Data Delivery shows the provider-description AI cost, remaining allowance and the Basic -> Enriched outcome): security.data_delivery_pdesc_v1 counts the lane's AI spend, reservations and remaining allowance, the estimated settlements, the descriptions admitted by the AI from an official page (first descriptions and upgrades), by the registry-fact route and by a person, and the upgrade (upgraded, queued upgrade reads, held upgrade reads by rule), exactly and read only; and the worker's identity.seen reaches the stored read (Task B).
-- Fixture data only (the pdesc-sentence-filter harness: fictional providers, no live data). Prints "<scenario>|<result>" lines; every block rolls back. Run by tests/fixtures/pdesc-dd-ai/run.sh.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

create or replace function pg_temp.pid(n int) returns uuid language sql as $f$ select id from catalogue.providers where stable_key = 'fixture:provider:' || n::text $f$;
create or replace function pg_temp.set_s(k text, v jsonb) returns void language sql as $f$
  insert into pipeline.platform_toolset_settings(toolset_key, key, value) values ('pipeline', k, v) on conflict (toolset_key, key) do update set value = excluded.value $f$;
-- a read of fixture provider n (cost 0: a cost would write a ledger row through ai_spend_capture; ledger rows are written by pg_temp.led)
create or replace function pg_temp.rd(n int, p_state text, p_rule text default null, p_ago interval default '0', p_reserved numeric default 0, p_checks jsonb default '{}', p_reason text default null, p_worker text default null) returns uuid language sql as $f$
  insert into pipeline.provider_description_reads(provider_id, state, rule, reason, reserved_usd, checks, worker, created_at, updated_at)
  values (pg_temp.pid(n), p_state, p_rule, p_reason, p_reserved, p_checks, p_worker, now() - p_ago, now() - p_ago) returning id $f$;
create or replace function pg_temp.l4(n int, p_status text) returns uuid language sql as $f$
  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, before_value, proposed_value, decided_at) values ('provider', pg_temp.pid(n), 'provider_description', p_status, '{"description":null}'::jsonb, '{"description":"x"}'::jsonb, now()) returning id $f$;
create or replace function pg_temp.adm(n int, p_tier text, p_outcome text, p_read uuid, p_l4 uuid, p_ago interval default '0', p_withdrawn boolean default false, p_text text default 'fixture text') returns uuid language sql as $f$
  insert into pipeline.provider_description_machine_admissions(provider_id, review_item_id, read_id, tier, rule, outcome, after_description, actor, created_at, withdrawn_at)
  values (pg_temp.pid(n), p_l4, p_read, p_tier, 'pdesc-machine-v1', p_outcome, p_text, '00000000-0000-0000-0000-0000000000a1', now() - p_ago, case when p_withdrawn then now() - p_ago / 2 end) returning id $f$;
create or replace function pg_temp.led(p_lane text, p_source text, p_cost numeric, p_ago interval default '0') returns void language sql as $f$
  insert into pipeline.ai_spend_ledger(at, lane, source, source_id, cost_usd, calls) values (now() - p_ago, p_lane, p_source, 'fixture', p_cost, 1) $f$;
create or replace function pg_temp.dd() returns jsonb language sql as $f$ select security.data_delivery_pdesc_v1() $f$;
create or replace function pg_temp.num(j jsonb) returns text language sql as $f$ select case when j is null or jsonb_typeof(j) = 'null' then 'null' else (j #>> '{}')::numeric(12,5)::text end $f$;
-- the AI block: ceiling|spent|calls|reserved|reserved reads|remaining|today|daily guard|daily remaining|settled reads|settled usd
create or replace function pg_temp.ai() returns text language sql as $f$
  select concat_ws('|', 'ceiling=' || pg_temp.num(a->'ceiling_usd'), 'spent=' || pg_temp.num(a->'spent_usd'), 'calls=' || (a->>'calls'), 'reserved=' || pg_temp.num(a->'reserved_usd'), 'reads=' || (a->>'reserved_reads'),
                    'remaining=' || pg_temp.num(a->'remaining_usd'), 'today=' || pg_temp.num(a->'today_usd'), 'guard=' || pg_temp.num(a->'daily_guard_usd'), 'daily_remaining=' || pg_temp.num(a->'daily_remaining_usd'),
                    'settled_reads=' || (a->>'settled_estimated_reads'), 'settled_usd=' || pg_temp.num(a->'settled_estimated_usd'))
    from (select pg_temp.dd()->'ai' a) z $f$;
-- the admitted block: ai first|ai upgrade|registry fact|person|withdrawn
create or replace function pg_temp.adms() returns text language sql as $f$
  select concat_ws('|', 'ai_first=' || (a->>'ai_first_description'), 'ai_upgrade=' || (a->>'ai_upgrade'), 'registry=' || (a->>'registry_fact'), 'person=' || (a->>'by_person'), 'withdrawn=' || (a->>'withdrawn'))
    from (select pg_temp.dd()->'admitted' a) z $f$;
-- the upgrade block: lane on|upgraded|basic held|queued reads|held reads|top rules
create or replace function pg_temp.upg() returns text language sql as $f$
  select concat_ws('|', 'on=' || (u->>'lane_on'), 'upgraded=' || (u->>'admitted'), 'basic_held=' || (u->>'basic_profiles_held'), 'queued=' || (u->>'queued_reads'), 'held=' || (u->>'held_reads'),
                    'top=' || coalesce((select string_agg((t->>'rule') || ':' || (t->>'n'), ',' order by o) from jsonb_array_elements(u->'top_hold_rules') with ordinality e(t, o)), '-'))
    from (select pg_temp.dd()->'upgrade' u) z $f$;
-- a register-fact profile of provider n, as the upgrade lane reads it (basic_profile_v1 is not null): the text is the provider's description, its read is the register-fact read
create or replace function pg_temp.profile(n int, p_ago interval) returns void language plpgsql as $f$
declare v_read uuid; v_l4 uuid;
begin
  update catalogue.providers set description = 'Profile text of provider ' || n::text where id = pg_temp.pid(n);
  v_read := pg_temp.rd(n, 'admitted', 'registry_factual', p_ago, 0, '{}', null, 'registry-factual-v1');
  v_l4 := pg_temp.l4(n, 'approved');
  perform pg_temp.adm(n, 'registry_factual', 'admitted', v_read, v_l4, p_ago, false, 'Profile text of provider ' || n::text);
end $f$;

-- ---------------------------------------------------------------------------------------------------------------- 1. nothing yet: every figure is a counted zero, the shape is complete
begin;
select pg_temp.set_s('pdesc.ai_usd_max', '0.75'); select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
select 'empty_known|' || (pg_temp.dd()->>'known') || '|' || (pg_temp.dd()->>'unit');
select 'empty_ai|' || pg_temp.ai();
select 'empty_admitted|' || pg_temp.adms();
select 'empty_upgrade|' || pg_temp.upg();
select 'empty_keys|' || (select string_agg(k, ',' order by k) from jsonb_object_keys(pg_temp.dd()) k) || ' / ' || (select string_agg(k, ',' order by k) from jsonb_object_keys(pg_temp.dd()->'ai') k)
  || ' / ' || (select string_agg(k, ',' order by k) from jsonb_object_keys(pg_temp.dd()->'admitted') k) || ' / ' || (select string_agg(k, ',' order by k) from jsonb_object_keys(pg_temp.dd()->'upgrade') k);
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 2. AI spend: the lane's ledger rows (not 'opening', not another lane), reservations, the remaining allowance, floored at 0
begin;
select pg_temp.set_s('pdesc.ai_usd_max', '0.75');
select pg_temp.led('provider_description', 'provider_description_reads', 0.10); select pg_temp.led('provider_description', 'provider_description_reads', 0.05, '3 days');
select pg_temp.led('provider_description', 'opening', 0.50);               -- the opening balance row is not spend
select pg_temp.led('course_description', 'course_reads', 0.30);             -- another lane
select pg_temp.rd(1, 'reading', null, '0', 0.02); select pg_temp.rd(2, 'held', 'existing_cost_reservation_uncertain', '0', 0.03); select pg_temp.rd(3, 'queued', null, '0', 0);
select 'spend_and_reservations|' || pg_temp.ai();
select pg_temp.set_s('pdesc.ai_usd_max', '0.15');
select 'allowance_floored_at_zero|' || pg_temp.ai();
select pg_temp.set_s('pdesc.ai_usd_max', '0.30');
select 'allowance_exact_to_the_cent|' || (pg_temp.dd()->'ai'->>'remaining_usd')::numeric(10,5);
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 3. the daily guard: today's spend (UTC day) and the reservations against the guard; a guard that is not held is null
begin;
select pg_temp.set_s('pdesc.ai_usd_max', '5');
select pg_temp.led('provider_description', 'provider_description_reads', 0.20); select pg_temp.led('provider_description', 'provider_description_reads', 0.40, '2 days');
select pg_temp.rd(1, 'held', 'existing_cost_reservation_uncertain', '0', 0.05);
select 'daily_guard_1|' || pg_temp.ai();
update pipeline.platform_toolset_settings set value = '0.2' where toolset_key = 'openrouter' and key = 'guard_provider_description';
select 'daily_guard_below_today_plus_reserved|' || pg_temp.ai();
delete from pipeline.platform_toolset_settings where toolset_key = 'openrouter' and key = 'guard_provider_description';
select 'daily_guard_not_held|' || pg_temp.ai();
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 4. estimated settlements (checks.reservation_settlement): counted apart, with the settled amount
begin;
select pg_temp.rd(1, 'queued', 'existing_cost_reservation_uncertain', '0', 0, '{"reservation_settlement":{"basis":"abandoned_reservation_assumed_called","settled_usd":0.003}}');
select pg_temp.rd(2, 'held', 'existing_cost_reservation_uncertain', '1 day', 0, '{"reservation_settlement":{"basis":"abandoned_reservation_assumed_called","settled_usd":0.0045}}');
select pg_temp.rd(3, 'admitted', 'missing', '0', 0, '{"reservation_settlement":{"basis":"abandoned_reservation_assumed_called","settled_usd":0.003}}');
select pg_temp.rd(4, 'held', 'not_stated', '0', 0, '{"identity":{"ok":true}}');
select 'settled_estimated|' || pg_temp.ai();
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 5. admitted, by route: AI first, AI upgrade, registry fact, person; a withdrawal is not an upgrade
begin;
select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
-- 1 first description written by the AI from an official page (tier direct), 2 the same by Firecrawl, 3 an upgrade (the profile admission is closed, a direct admission replaces it)
select pg_temp.adm(1, 'direct', 'admitted', pg_temp.rd(1, 'admitted', 'missing'), pg_temp.l4(1, 'approved'));
select pg_temp.adm(2, 'firecrawl', 'admitted', pg_temp.rd(2, 'admitted', 'missing'), pg_temp.l4(2, 'approved'));
select pg_temp.profile(3, '5 days');
update pipeline.provider_description_machine_admissions set withdrawn_at = now() - interval '1 day', withdrawn_reason = 'Upgraded' where provider_id = pg_temp.pid(3) and tier = 'registry_factual';
update pipeline.provider_description_reads set state = 'superseded' where provider_id = pg_temp.pid(3) and state = 'admitted';
select pg_temp.adm(3, 'direct', 'admitted', pg_temp.rd(3, 'admitted', 'missing', '1 day'), pg_temp.l4(3, 'approved'), '1 day');
-- 4 and 5 hold a register-fact profile
select pg_temp.profile(4, '4 days'); select pg_temp.profile(5, '4 days');
-- 6 a person approved the item (no machine admission on it); 7 a person edited and approved; 8 an item with a machine decline row and then a person approval; 9 approved by the machine (not a person)
select pg_temp.l4(6, 'approved'); select pg_temp.l4(7, 'edited_approved');
select pg_temp.adm(8, 'direct', 'declined', null, pg_temp.l4(8, 'approved'));
select pg_temp.adm(9, 'direct', 'admitted', pg_temp.rd(9, 'admitted', 'missing'), pg_temp.l4(9, 'approved'));
-- a pending item and a rejected item are nobody's admission
select pg_temp.l4(10, 'pending'); select pg_temp.l4(11, 'rejected');
-- 12 an admission the machine made and later withdrew, no live admission now (a withdrawal)
select pg_temp.adm(12, 'direct', 'admitted', pg_temp.rd(12, 'superseded', 'missing'), pg_temp.l4(12, 'approved'), '2 days', true);
select 'routes|' || pg_temp.adms();
select 'upgrade_count|' || pg_temp.upg();
rollback;
begin;
-- a live direct admission whose read is held (not admitted with rule missing) is not counted as admitted by the AI from a page
select pg_temp.adm(1, 'direct', 'admitted', pg_temp.rd(1, 'held', 'not_stated'), pg_temp.l4(1, 'approved'));
select 'admission_without_admitted_read|' || pg_temp.adms();
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 6. the upgrade lane: queued upgrade reads (the lane's own test), held upgrade reads after the profile, by rule
begin;
select pg_temp.set_s('pdesc.registry_upgrade_on', '1'); select pg_temp.set_s('data_delivery.reasons_shown', '2');
select pg_temp.profile(1, '4 days'); select pg_temp.profile(2, '4 days'); select pg_temp.profile(3, '4 days');
-- provider 1: a held read BEFORE the profile (history that led to it) and two after; provider 2: a queued upgrade read and an older held one; provider 3: three holds after the profile
select pg_temp.rd(1, 'held', 'insufficient_verified_facts', '6 days', 0, '{}', 'before the profile');
select pg_temp.rd(1, 'held', 'provider_name_not_proved', '2 days', 0, '{}', 'first not proved');
select pg_temp.rd(1, 'held', 'provider_name_not_proved', '1 day', 0, '{}', 'latest not proved');
select pg_temp.rd(2, 'held', 'no_about_page', '3 days', 0, '{}', 'no about');
select pg_temp.rd(2, 'queued', null, '0');
select pg_temp.rd(3, 'held', 'no_about_page', '1 day', 0, '{}', 'no about again');
select pg_temp.rd(3, 'held', 'not_stated', '2 days', 0, '{}', 'not stated');
select pg_temp.rd(3, 'held', 'provider_name_not_proved', '3 days', 0, '{}', 'third not proved');
-- a provider with no profile: its queued read and its holds are not upgrade reads
select pg_temp.rd(4, 'queued', null, '0'); select pg_temp.rd(5, 'held', 'wrong_host', '1 day');
select 'upgrade_reads_top_two|' || pg_temp.upg();
select 'upgrade_top_example|' || (pg_temp.dd()->'upgrade'->'top_hold_rules'->0->>'example');
select pg_temp.set_s('data_delivery.reasons_shown', '3');
select 'upgrade_top_three|' || pg_temp.upg();
-- the switch off: the lane's own test (basic_profile_v1) returns null, so no read is an upgrade read to queue; the screen is told the lane is off
select pg_temp.set_s('pdesc.registry_upgrade_on', '0');
select 'lane_off|' || pg_temp.upg();
select pg_temp.set_s('pdesc.registry_upgrade_on', '1');
-- the provider's text is changed by a person: the profile is no longer the provider's text, the queued read is not an upgrade read
update catalogue.providers set description = 'Edited by a person' where id = pg_temp.pid(2);
select 'text_edited_queued_not_counted|' || pg_temp.upg();
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 7. a count that cannot be made is shown as such, never as 0
begin;
alter table pipeline.ai_spend_ledger rename column cost_usd to cost_usd_gone;
select 'cannot_count|' || (pg_temp.dd()->>'known') || '|' || left(pg_temp.dd()->>'reason', 60) || '|' || (not (pg_temp.dd() ? 'ai'))::text;
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 8. nothing is written
begin;
create or replace function pg_temp.counts() returns text language sql as $f$
  select concat_ws('|', (select count(*) from pipeline.provider_description_reads), (select count(*) from pipeline.ai_spend_ledger), (select count(*) from pipeline.provider_description_machine_admissions), (select count(*) from pipeline.layer4_review_items),
                   (select md5(string_agg(s::text, '|' order by s.toolset_key, s.key)) from pipeline.platform_toolset_settings s), (select md5(string_agg(r::text, '|' order by r.id)) from pipeline.provider_description_reads r)) $f$;
select pg_temp.profile(1, '4 days'); select pg_temp.rd(1, 'held', 'no_about_page', '0');
create temp table mid_counts as select pg_temp.counts() c;
select security.data_delivery_pdesc_v1() is not null;
select 'read_only|' || ((select c from mid_counts) = pg_temp.counts())::text;
select 'stable_and_definer|' || (select concat_ws('|', p.provolatile, p.prosecdef::text, coalesce(p.proconfig::text, '-')) from pg_proc p where p.oid = 'security.data_delivery_pdesc_v1()'::regprocedure);
select 'not_for_anon_or_authenticated|' || (not has_function_privilege('anon', 'security.data_delivery_pdesc_v1()', 'execute'))::text || '|' || (not has_function_privilege('authenticated', 'security.data_delivery_pdesc_v1()', 'execute'))::text;
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 9. at the live size the statement stays far inside the 8 s time-out (1,100 admissions, 2,600 reads, 30,000 ledger rows)
begin;
insert into pipeline.ai_spend_ledger(at, lane, source, source_id, cost_usd, calls) select now() - make_interval(secs => g), case when g % 160 = 0 then 'provider_description' else 'course_description' end, 'bulk', g::text, 0.001, 1 from generate_series(1, 30000) g;
insert into pipeline.provider_description_reads(provider_id, state, rule, created_at, updated_at) select pg_temp.pid(1 + g % 12), case g % 3 when 0 then 'held' when 1 then 'queued' else 'superseded' end, case when g % 3 = 0 then 'provider_name_not_proved' end, now() - make_interval(secs => g), now() - make_interval(secs => g)
  from generate_series(1, 2600) g where g % 3 <> 1 or g < 12;
select 'scaled_known|' || (pg_temp.dd()->>'known');
create temp table t0 as select clock_timestamp() t;
select count(*) from (select pg_temp.dd() from generate_series(1, 5)) x;
select 'scaled_five_runs_under_two_seconds|' || ((select clock_timestamp() - t from t0) < interval '2 seconds')::text;
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 10. Task B: the worker's identity.seen reaches the stored read, and nothing else treats it as an error
create or replace function pg_temp.queue(n int) returns void language plpgsql as $f$
begin insert into pipeline.provider_description_reads(provider_id, state) select pg_temp.pid(n), 'queued' on conflict do nothing; end $f$;
create or replace function pg_temp.record_identity(p_n int, p_identity jsonb) returns text language plpgsql as $f$
declare v_lease jsonb; it jsonb; v_tally jsonb;
begin
  perform pg_temp.queue(p_n);
  v_lease := public.svc_provider_description_lease_v1(3, null, 'provider-description-reserve-v1');
  for it in select * from jsonb_array_elements(v_lease->'items') loop
    continue when (it->>'provider_id')::uuid <> pg_temp.pid(p_n);
    v_tally := public.svc_provider_description_record(jsonb_build_array(jsonb_build_object('item_id', it->>'item_id', 'model', v_lease->>'model', 'prompt_version', 'provider-description-v2', 'worker', 'fixture',
      'identity_check', p_identity, 'rule', p_identity->>'rule', 'reason', 'The page does not prove the provider''s current full institutional identity; no AI call was made.')));
    return v_tally::text;
  end loop;
  return 'not leased';
end $f$;
begin;
select 'seen_tally|' || pg_temp.record_identity(1, jsonb_build_object('ok', false, 'rule', 'provider_name_not_proved', 'reader_behavior_version', 'provider-description-source-guard-v4',
  'seen', jsonb_build_object('title', 'Welcome', 'h1', jsonb_build_array('Study with us'), 'og_site_name', '', 'html_chars', 1200, 'text_chars', 90, 'has_script_shell', true)));
select 'seen_stored|' || (select concat_ws('|', r.state, r.rule, c->>'ok', c->>'rule', c->'seen'->>'title', c->'seen'->'h1'->>0, '[' || (c->'seen'->>'og_site_name') || ']', c->'seen'->>'html_chars', c->'seen'->>'text_chars', c->'seen'->>'has_script_shell')
  from pipeline.provider_description_reads r, lateral (select r.checks->'identity' c) z where r.provider_id = pg_temp.pid(1) order by r.created_at desc limit 1);
rollback;
begin;
-- a failed proof recorded without seen (the worker before v0.62.0) is stored as it is: nothing requires the key
select 'passed_tally|' || pg_temp.record_identity(2, jsonb_build_object('ok', false, 'rule', 'provider_name_conflict', 'reader_behavior_version', 'provider-description-source-guard-v4'));
select 'no_seen_stored|' || (select concat_ws('|', r.state, r.rule, (r.checks->'identity' ? 'seen')::text, r.checks->'identity'->>'rule') from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(2) order by r.created_at desc limit 1);
rollback;
