-- Guards: F-PDESC.01-.05 (Platform Admin decision 10 Nov 2026 19:47): a provider-description reading declined by the automatic text rule for only SOME of its sentences is recovered by leaving exactly those sentences out (never reworded, never added to) and running the same validation and the same machine gate again on the rest; a refusal that dropping sentences cannot remove (identity, lock, rejection memory, duplicate, a remainder below the minimums, every sentence refused) leaves the reading declined exactly as before; the proposal, read, Layer 4 item and decision history are kept.
-- Fixture data only (the pdesc-machine harness: fictional providers, no live data). Prints "<scenario>|<result>" lines; every block rolls back. Run by tests/fixtures/pdesc-subset-recovery/run.sh after migration 20261110210000.
\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

-- ---------------------------------------------------------------------------------------------------------------- helpers
create or replace function pg_temp.pid(n int) returns uuid language sql as $f$ select id from catalogue.providers where stable_key = 'fixture:provider:' || case when n = 13 then 'browser' else n::text end $f$;
create or replace function pg_temp.set_s(k text, v jsonb) returns void language sql as $f$ update pipeline.platform_toolset_settings set value = v where toolset_key = 'pipeline' and key = k $f$;
create or replace function pg_temp.queue(n int) returns void language plpgsql as $f$
begin insert into pipeline.provider_description_reads(provider_id, state) select pg_temp.pid(n), 'queued' on conflict do nothing; end $f$;
create or replace function pg_temp.desc_of(n int) returns text language sql as $f$ select coalesce(description, '(none)') from catalogue.providers where id = pg_temp.pid(n) $f$;
create or replace function pg_temp.item(n int) returns uuid language sql as $f$ select id from pipeline.layer4_review_items where entity_id = pg_temp.pid(n) and field_code = 'provider_description' order by created_at desc limit 1 $f$;
create or replace function pg_temp.istatus(n int) returns text language sql as $f$ select status from pipeline.layer4_review_items where id = pg_temp.item(n) $f$;
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
  return jsonb_build_object('leased', jsonb_array_length(coalesce(v_lease->'items', '[]'::jsonb)), 'recorded', case when jsonb_array_length(v_res) > 0 then public.svc_provider_description_record(v_res) end);
end $f$;
-- a worker answer from sentence texts; each quote is the official passage the sentence paraphrases (the same words, with the page's own lead-in), so it is on the page and supports the sentence
create or replace function pg_temp.ans(p_texts text[]) returns jsonb language sql as $f$
  select jsonb_build_object('about_page', true, 'sentences', (select jsonb_agg(jsonb_build_object('text', t, 'quote', 'Our About page says: ' || t || ' Read more about us.') order by o) from unnest(p_texts) with ordinality u(t, o)))
$f$;
create or replace function pg_temp.c1() returns text language sql as $f$ select 'Dune Plains University teaches botany and arid landscape ecology to learners from many regions.'::text $f$;
create or replace function pg_temp.c3() returns text language sql as $f$ select 'The university offers study in plant science, soil science and environmental management.'::text $f$;
create or replace function pg_temp.b_campus() returns text language sql as $f$ select 'The university began with a single campus in the desert region and has grown since.'::text $f$;
create or replace function pg_temp.b_figure() returns text language sql as $f$ select 'It has taught botany for over 35 years in the desert region.'::text $f$;
create or replace function pg_temp.b_accred() returns text language sql as $f$ select 'All of its programs are accredited by the national botanical society.'::text $f$;
-- one reading proposed and left for a person (the automatic admission is off while it is recorded)
create or replace function pg_temp.propose(n int, p_texts text[]) returns void language plpgsql as $f$
begin
  perform pg_temp.set_s('pdesc.machine_admit_on', '0');
  perform pg_temp.queue(n);
  perform pg_temp.run_worker(3, jsonb_build_object(pg_temp.pid(n)::text, pg_temp.ans(p_texts)));
end $f$;
create or replace function pg_temp.ledger(n int, o text) returns bigint language sql as $f$ select count(*) from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(n) and outcome = o $f$;
create or replace function pg_temp.try_code(n int) returns text language sql as $f$
  select coalesce(checks->'subset_recovery'->>'result', 'none') from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(n) and outcome = 'declined' $f$;

create or replace function pg_temp.cohort_for(n int) returns table(m jsonb) language plpgsql as $f$
declare v_c uuid; v_u uuid;
begin
  select id into v_u from auth.users limit 1;
  if v_u is null then insert into auth.users (id) values (gen_random_uuid()) returning id into v_u; end if;
  insert into pipeline.provider_description_cohorts (requested_by, state, selection, snapshot, expires_at) values (v_u, 'prepared', '{}'::jsonb, '{}'::jsonb, now() + interval '1 day') returning id into v_c;
  insert into pipeline.provider_description_cohort_members (cohort_id, provider_id, read_id, pick, snapshot)
  select v_c, pg_temp.pid(n), r.id, 1, '{}'::jsonb from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(n) and r.state in ('admitted', 'verified') order by r.created_at desc limit 1;
  return query select e from jsonb_array_elements(security.provider_description_run_result_v1(v_c)->'providers') e;
end $f$;
-- ---------------------------------------------------------------------------------------------------------------- 1. the shape: one new function, read only, not granted
select 'function|' || (select (prosecdef and provolatile = 's')::text from pg_proc where oid = 'security.provider_description_subset_v1(uuid,jsonb)'::regprocedure)
  || '|' || (not has_function_privilege('anon', 'security.provider_description_subset_v1(uuid,jsonb)', 'execute') and not has_function_privilege('authenticated', 'security.provider_description_subset_v1(uuid,jsonb)', 'execute'))::text;

-- ---------------------------------------------------------------------------------------------------------------- 2. the Monash shape: sentence 2 holds a word and a figure; sentences 1 and 3 are recovered by the hourly settlement
begin;
select pg_temp.propose(4, array[pg_temp.c1(), 'The university began with a single campus of fewer than 400 students in the desert region.', pg_temp.c3()]);
select 'monash_proposed|' || pg_temp.istatus(4) || '|' || pg_temp.desc_of(4) || '|' || (select count(*) from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(4));
select pg_temp.set_s('pdesc.machine_admit_on', '1');
-- the ledger row the earlier admission wrote for this item (live has one for each of its waiting items): the whole reading declined for the word
insert into pipeline.provider_description_machine_admissions (provider_id, review_item_id, read_id, tier, rule, outcome, reason, evidence_id, source_url, source_hash, facts, actor, created_at)
select r.provider_id, r.review_item_id, r.id, 'stored', 'pdesc-machine-v1', 'declined', 'The description has a word, figure or markup the automatic rule does not admit (refused_word:campus); it is not published automatically.', r.evidence_id, r.source_url, r.content_hash, '[]', 'c0ffee00-0000-4000-8000-000000000150', now() - interval '2 hours'
  from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(4) and r.state = 'proposed';
select 'monash_whole_check|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(4), pg_temp.c1() || ' ' || 'The university began with a single campus of fewer than 400 students in the desert region.' || ' ' || pg_temp.c3()), 'clean')
  || '|' || coalesce(security.pdesc_machine_text_check_v1(pg_temp.pid(4), pg_temp.c1() || ' ' || pg_temp.c3()), 'clean');
select 'monash_settled|' || (security.provider_description_machine_settle_pending_v1()->>'admitted');
select 'monash_description|' || (pg_temp.desc_of(4) = pg_temp.c1() || ' ' || pg_temp.c3())::text || '|' || pg_temp.istatus(4);
select 'monash_ledger|declined ' || pg_temp.ledger(4, 'declined') || ' admitted ' || pg_temp.ledger(4, 'admitted') || '|' || (select (reason like 'subset_of_reading: Auto (pdesc-machine-v1, tier stored)%')::text || '|' || (reason like '%2 of 3 sentences kept, 1 left out%')::text || '|' || rule || '|' || (actor = 'c0ffee00-0000-4000-8000-000000000150')::text
  from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(4) and outcome = 'admitted');
select 'monash_dropped|' || (select (checks->'subset_of_reading'->'dropped'->0->>'index') || '|' || (checks->'subset_of_reading'->'dropped'->0->>'code') || '|' || (checks->'subset_of_reading'->'dropped'->0->>'text' like '%single campus%')::text
  || '|' || (checks->'subset_of_reading'->>'kept_sentences') || '|' || (checks->'subset_of_reading'->>'given_sentences') || '|' || (checks->'subset_of_reading'->>'original_read_id' = read_id::text)::text || '|' || (checks->'subset_of_reading'->>'original_evidence_id' = evidence_id::text)::text
  from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(4) and outcome = 'admitted');
select 'monash_declined_kept|' || (select (reason like '%refused_word:campus%')::text from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(4) and outcome = 'declined');
-- the item and the read now hold the description the catalogue holds (the kept sentences); the original proposal (every sentence) stays in the decision row, the item's layer2_state and the ledger
select 'monash_proposal_kept|' || (select jsonb_array_length(proposed_value->'sentences') || '|' || (proposed_value->>'description' = pg_temp.desc_of(4))::text || '|' || (layer2_state->'subset_of_reading'->>'original_text' like '%single campus%')::text || '|' || jsonb_array_length(layer2_state->'subset_of_reading'->'original_sentences') from pipeline.layer4_review_items where id = pg_temp.item(4))
  || '|' || (select (jsonb_array_length(proposal->'sentences') = 2 and proposal->>'description' = pg_temp.desc_of(4))::text from pipeline.provider_description_reads where provider_id = pg_temp.pid(4) and state = 'admitted')
  || '|' || (select (checks->'subset_of_reading'->>'original_text' like '%single campus%')::text from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(4) and outcome = 'admitted');
-- B1 (QA 10 Nov): the read-back finds the recovered description. The approved lineage is not null, the consumer read-back accepts the row, a run that includes it no longer says awaiting_admission, and the selection does not call it a manual description
select 'monash_lineage|' || (security.provider_description_approved_lineage_v1(pg_temp.pid(4), pg_temp.desc_of(4)) = pg_temp.item(4))::text;
select 'monash_selection|' || coalesce((select x->>'eligibility_reason' || '/' || (x->>'eligible') from jsonb_array_elements(security.provider_description_selection_v1(jsonb_build_object('filter', 'all', 'size', 50, 'prefilter', false, 'provider_id', pg_temp.pid(4)))->'providers') x), 'not_listed');
select 'monash_publication_check|' || security.provider_description_publication_check_v1();
select 'monash_run_result|' || coalesce((select (m->'publication'->'website'->>'status') || '|' || (m->'publication'->'zoho'->>'status') || '|' || (m->'publication'->'catalogue'->>'status') from pg_temp.cohort_for(4) m), 'no_member');
select 'monash_decision|' || (select d.action || '|' || (d.proposed_value->>'description' like '%single campus%')::text || '|' || jsonb_array_length(d.proposed_value->'sentences') || '|' || (d.final_value->>'description' = pg_temp.c1() || ' ' || pg_temp.c3())::text || '|' || jsonb_array_length(d.final_value->'sentences')
    || '|' || (d.layer2_state->>'subset_of_reading') || '|' || (d.actor_id = 'c0ffee00-0000-4000-8000-000000000150')::text || '|' || (d.reason like '%Not a person%')::text
  from pipeline.layer4_decisions d where d.review_item_id = pg_temp.item(4));
select 'monash_event|' || (select (detail->>'subset_of_reading') || '|' || (detail->>'auto') from pipeline.admin_control_events where target = pg_temp.item(4)::text and action = 'inbox_decide');
-- settled once: a second pass changes nothing
select 'monash_again|' || (security.provider_description_machine_admit_v1(pg_temp.item(4))->>'rule') || '|' || pg_temp.ledger(4, 'admitted');
-- the Fill fields status read says what the machine rule decided (and shows the sentences left out without their quotes)
select 'monash_status|' || (select (m->>'outcome') || '|' || (m->>'current_reading') || '|' || (m->'subset'->>'kept_sentences') || '/' || (m->'subset'->>'given_sentences') || '|' || (m->'subset'->'dropped'->0->>'code') || '|' || ((m->'subset'->'dropped'->0) ? 'quote')::text || '|' || (m->>'review_item_id' = pg_temp.item(4)::text)::text
   from (select security.provider_description_fill_status_v1(array[pg_temp.pid(4)], false, null)->'providers'->0->'machine' m) z);
-- Data Delivery counts it
select 'monash_dd|' || (security.data_delivery_pdesc_v1()->'subset_recovery'->>'recovered') || '|' || (security.data_delivery_pdesc_v1()->'subset_recovery'->>'sentences_left_out') || '|' || (security.data_delivery_pdesc_v1() ? 'upgrade')::text;
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 3. recovered when the reading is recorded (the automatic admission is on); a figure alone is also removable
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.queue(5);
select pg_temp.run_worker(3, jsonb_build_object(pg_temp.pid(5)::text, pg_temp.ans(array[pg_temp.c1(), pg_temp.b_figure(), pg_temp.c3()])));
select 'record_figure|' || (pg_temp.desc_of(5) = pg_temp.c1() || ' ' || pg_temp.c3())::text || '|' || pg_temp.istatus(5) || '|' || (select checks->'subset_of_reading'->'dropped'->0->>'code' from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(5) and outcome = 'admitted') || '|' || pg_temp.ledger(5, 'declined');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 4. the whole reading is clean: nothing is dropped, the admission is the one it always was
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.queue(6);
select pg_temp.run_worker(3, jsonb_build_object(pg_temp.pid(6)::text, pg_temp.ans(array[pg_temp.c1(), pg_temp.c3()])));
select 'clean_reading|' || (pg_temp.desc_of(6) = pg_temp.c1() || ' ' || pg_temp.c3())::text || '|' || (select (not (checks ? 'subset_of_reading'))::text || '|' || (reason like 'Auto (%')::text from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(6) and outcome = 'admitted');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 5. not recovered: a remainder below the minimum, every sentence refused, no sentence the rule refuses on its own
begin;
select pg_temp.propose(4, array[pg_temp.c1(), pg_temp.b_campus(), pg_temp.b_accred()]);
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select 'below_minimum|' || (security.provider_description_machine_admit_v1(pg_temp.item(4))->>'rule') || '|' || pg_temp.try_code(4) || '|' || pg_temp.istatus(4) || '|' || pg_temp.desc_of(4) || '|' || pg_temp.ledger(4, 'admitted');
select 'below_minimum_audit|' || (select (checks->'subset_recovery'->>'kept_sentences') || '|' || jsonb_array_length(checks->'subset_recovery'->'dropped') || '|' || (checks->'subset_recovery'->>'refusal') from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(4) and outcome = 'declined');
select 'below_minimum_status|' || (select (m->>'outcome') || '|' || (m->>'current_reading') || '|' || (m->>'subset_result') || '|' || (m->'subset' is null)::text || '|' || (reader ? 'ai_calls')::text || '|' || (reader ? 'source_captured_at')::text
   from (select p->'machine' m, p->'reader' reader from (select security.provider_description_fill_status_v1(array[pg_temp.pid(4)], false, null)->'providers'->0 p) y) z);
rollback;
begin;
select pg_temp.propose(5, array[pg_temp.b_campus(), pg_temp.b_accred()]);
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select 'all_refused|' || (security.provider_description_machine_admit_v1(pg_temp.item(5))->>'rule') || '|' || pg_temp.try_code(5) || '|' || pg_temp.istatus(5) || '|' || pg_temp.desc_of(5);
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 6. not recovered: the refusal is not a sentence (identity finding, manual lock, earlier rejection, held description)
begin;
select pg_temp.propose(4, array[pg_temp.c1(), pg_temp.b_campus(), pg_temp.c3()]);
insert into pipeline.provider_identity_findings(provider_id, check_code, reason) values (pg_temp.pid(4), 'identity_unconfirmed', 'fixture');
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select 'identity_finding|' || (security.provider_description_machine_admit_v1(pg_temp.item(4))->>'rule') || '|' || pg_temp.try_code(4) || '|' || pg_temp.istatus(4) || '|' || pg_temp.desc_of(4);
rollback;
begin;
select pg_temp.propose(4, array[pg_temp.c1(), pg_temp.b_campus(), pg_temp.c3()]);
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('provider', pg_temp.pid(4), 'description', 'value');
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select 'manual_lock|' || (security.provider_description_machine_admit_v1(pg_temp.item(4))->>'rule') || '|' || pg_temp.try_code(4) || '|' || pg_temp.istatus(4) || '|' || pg_temp.desc_of(4);
rollback;
begin;
select pg_temp.propose(4, array[pg_temp.c1(), pg_temp.b_campus(), pg_temp.c3()]);
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, proposed_value, before_value) values ('provider', pg_temp.pid(4), 'provider_description', 'rejected', '{"description":"x"}', '{"description":null}');
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select 'rejection_memory|' || (security.provider_description_machine_admit_v1((select id from pipeline.layer4_review_items where entity_id = pg_temp.pid(4) and status = 'pending'))->>'rule') || '|' || pg_temp.desc_of(4);
rollback;
begin;
select pg_temp.propose(4, array[pg_temp.c1(), pg_temp.b_campus(), pg_temp.c3()]);
update catalogue.providers set description = 'A description already held by hand for this provider.' where id = pg_temp.pid(4);
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select 'description_held|' || (security.provider_description_machine_admit_v1(pg_temp.item(4))->>'rule') || '|' || pg_temp.desc_of(4);
rollback;
begin;
select pg_temp.propose(4, array[pg_temp.c1(), pg_temp.b_campus(), pg_temp.c3()]);
select pg_temp.set_s('pdesc.machine_admit_on', '0');
select 'switch_off|' || (security.provider_description_machine_admit_v1(pg_temp.item(4))->>'rule') || '|' || pg_temp.desc_of(4) || '|' || pg_temp.istatus(4);
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 7. not recovered: the remainder is the same as another provider's description (duplicate guard)
begin;
select pg_temp.propose(4, array[pg_temp.c1(), pg_temp.b_campus(), pg_temp.c3()]);
update catalogue.providers set description = pg_temp.c1() || ' ' || pg_temp.c3() where id = pg_temp.pid(6);
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select 'duplicate_remainder|' || (security.provider_description_machine_admit_v1(pg_temp.item(4))->>'rule') || '|' || pg_temp.try_code(4) || '|' || pg_temp.desc_of(4);
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 8. a human decision is never overridden: an item a person settled is not offered again
begin;
select pg_temp.propose(4, array[pg_temp.c1(), pg_temp.b_campus(), pg_temp.c3()]);
update pipeline.layer4_review_items set status = 'edited_approved', decided_at = now() where id = pg_temp.item(4);
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select 'person_settled|' || (security.provider_description_machine_admit_v1(pg_temp.item(4))->>'rule') || '|' || pg_temp.desc_of(4) || '|' || pg_temp.ledger(4, 'admitted');
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 9. a reading without an identity snapshot must still name the provider in a quote that is kept
begin;
select pg_temp.propose(4, array[pg_temp.c1(), pg_temp.b_campus(), pg_temp.c3()]);
update pipeline.provider_description_reads set checks = checks - 'identity_snapshot' where provider_id = pg_temp.pid(4) and state = 'proposed';
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select 'legacy_name_kept|' || (security.provider_description_machine_admit_v1(pg_temp.item(4))->>'ok') || '|' || (pg_temp.desc_of(4) = pg_temp.c1() || ' ' || pg_temp.c3())::text;
rollback;
begin;
select pg_temp.propose(5, array['Elm Arts University has a campus in the creative quarter of the city for its learners.', pg_temp.c1(), pg_temp.c3()]);
update pipeline.provider_description_reads set checks = checks - 'identity_snapshot' where provider_id = pg_temp.pid(5) and state = 'proposed';
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select 'legacy_name_dropped|' || (security.provider_description_machine_admit_v1(pg_temp.item(5))->>'rule') || '|' || pg_temp.try_code(5) || '|' || pg_temp.desc_of(5);
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 10. Data Delivery: the readings still declined, by cause
begin;
select pg_temp.propose(4, array[pg_temp.c1(), pg_temp.b_campus(), pg_temp.b_accred()]);
select pg_temp.propose(5, array[pg_temp.b_campus(), pg_temp.b_accred()]);
select pg_temp.set_s('pdesc.machine_admit_on', '1');
select security.provider_description_machine_settle_pending_v1();
select 'dd_counts|' || (security.data_delivery_pdesc_v1()->'subset_recovery'->>'recovered') || '|' || (security.data_delivery_pdesc_v1()->'subset_recovery'->>'waiting_items') || '|' || (security.data_delivery_pdesc_v1()->'subset_recovery'->>'still_declined') || '|' || (security.data_delivery_pdesc_v1()->'subset_recovery'->>'causes');
select 'dd_causes|' || (select string_agg((c->>'cause') || '=' || (c->>'n'), ',' order by c->>'cause') from jsonb_array_elements(security.data_delivery_pdesc_v1()->'subset_recovery'->'still_declined_by_cause') c);
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 10a. the promotional sentence (supersedes the retired pdesc-claim-context results record_tally, record_declined, waiting_promotional_settle, waiting_promotional): ONE promotional sentence among clean ones is left out, the clean sentences are admitted
begin;
select pg_temp.set_s('pdesc.machine_admit_on', '1'); select pg_temp.queue(6);
select pg_temp.run_worker(3, jsonb_build_object(pg_temp.pid(6)::text, pg_temp.ans(array[pg_temp.c1(), 'Its students are taught by the best staff, with a long record of teaching in many fields.', pg_temp.c3()])));
select 'promotional_record|' || (pg_temp.desc_of(6) = pg_temp.c1() || ' ' || pg_temp.c3())::text || '|' || pg_temp.istatus(6) || '|' || (select (checks->'subset_of_reading'->'dropped'->0->>'code') || '|' || (checks->'subset_of_reading'->>'kept_sentences') || '/' || (checks->'subset_of_reading'->>'given_sentences')
    from pipeline.provider_description_machine_admissions where provider_id = pg_temp.pid(6) and outcome = 'admitted')
  || '|' || (security.provider_description_approved_lineage_v1(pg_temp.pid(6), pg_temp.desc_of(6)) = pg_temp.item(6))::text;
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 10b. attempts (Operating Model v1.7, evidence-backed absence): a budget refusal is NOT an attempt; a failed fetch is a retryable attempt; a real read with nothing usable is tried, not found
create or replace function pg_temp.lease_one(n int) returns uuid language plpgsql as $f$
declare v_lease jsonb;
begin
  update pipeline.provider_description_reads set next_try_at = now() - interval '1 minute' where provider_id = pg_temp.pid(n);
  v_lease := public.svc_provider_description_lease_v1(3, null, 'provider-description-reserve-v1');
  return (select (i->>'item_id')::uuid from jsonb_array_elements(v_lease->'items') i where (i->>'provider_id')::uuid = pg_temp.pid(n) limit 1);
end $f$;
create or replace function pg_temp.rd(n int) returns text language sql as $f$
  select state || '/' || tries || '/' || coalesce(rule, '-') || '/' || (next_try_at > now())::text || '/' || ai_calls || '/' || cost_usd from pipeline.provider_description_reads where provider_id = pg_temp.pid(n) $f$;
-- the worker's answer for the leased read of provider n, recorded as the live record function takes it; the tally it returns is what the worker sees
create or replace function pg_temp.record_for(n int, p_result jsonb) returns jsonb language sql as $f$
  select public.svc_provider_description_record(jsonb_build_array(jsonb_build_object('item_id', r.id) || p_result)) from pipeline.provider_description_reads r where r.provider_id = pg_temp.pid(n) $f$;
begin;
select pg_temp.queue(5);
select 'attempt_leased|' || (pg_temp.lease_one(5) is not null)::text || '|' || pg_temp.rd(5);
-- the worker is refused by the governed AI budget before any call: nothing was tried
select 'attempt_budget_refused|' || (pg_temp.record_for(5, jsonb_build_object('rule', 'ai_budget_refused', 'reason', 'The existing governed AI budget refused the conservative per-call reservation; no AI call was made.'))->>'parked_policy') || '|' || pg_temp.rd(5);
select 'attempt_budget_ceiling|' || (pg_temp.lease_one(5) is not null)::text || '|' || (pg_temp.record_for(5, jsonb_build_object('rule', 'ai_ceiling', 'reason', 'ceiling'))->>'parked_policy') || '|' || pg_temp.rd(5);
-- a fetch that failed (timeout, blocked, fetch_failed) is a real attempt and is tried again later
select 'attempt_fetch_failed|' || (pg_temp.lease_one(5) is not null)::text || '|' || (pg_temp.record_for(5, jsonb_build_object('error', 'fetch_failed: timeout'))->>'queued') || '|' || pg_temp.rd(5);
-- a real read that found no usable description is tried, not found: held with its rule, one more attempt counted
select 'attempt_not_found|' || (pg_temp.lease_one(5) is not null)::text || '|' || (pg_temp.record_for(5, jsonb_build_object('rule', 'no_about_page', 'reason', 'no About page found on the provider''s own website'))->>'held') || '|' || pg_temp.rd(5);
rollback;

-- ---------------------------------------------------------------------------------------------------------------- 11. nothing is left behind
select 'clean|' || (select count(*) from pipeline.provider_description_machine_admissions where checks ? 'subset_of_reading' or checks ? 'subset_recovery') || '|' || (select count(*) from pipeline.layer4_review_items where field_code = 'provider_description');
