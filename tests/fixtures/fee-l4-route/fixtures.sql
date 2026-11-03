-- CF-247 IQ-00111 D12: every case after the migration (fees.recheck_keep_withdraws_on 1 as shipped).
\set ON_ERROR_STOP 1
create function fx.ok(p_cond boolean, p_what text) returns void language plpgsql as $f$
begin if p_cond is not true then raise exception 'FAIL: %', p_what; end if; raise notice 'ok: %', p_what; end $f$;
insert into catalogue.providers values ('00000000-0000-0000-0000-0000000000b1', 'UTas', null);
insert into catalogue.courses values
 ('00000000-0000-0000-0000-000000000c01', '00000000-0000-0000-0000-0000000000b1', 'Master of Health Service Management', null, '114382M'),
 ('00000000-0000-0000-0000-000000000c02', '00000000-0000-0000-0000-0000000000b1', 'Locked course', null, 'LOCK001'),
 ('00000000-0000-0000-0000-000000000c03', '00000000-0000-0000-0000-0000000000b1', 'Confirmed course', null, 'CONF001'),
 ('00000000-0000-0000-0000-000000000c04', '00000000-0000-0000-0000-0000000000b1', 'Adapter fee course', null, 'ADAP001'),
 ('00000000-0000-0000-0000-000000000c05', '00000000-0000-0000-0000-0000000000b1', 'Held course', null, 'HELD001');
insert into pipeline.evidence_artifacts values ('00000000-0000-0000-0000-00000000e001', 'https://www.utas.edu.au/c7u', 'p', '2026-10-05'),
                                               ('00000000-0000-0000-0000-00000000e005', 'https://example.edu/held', 'p', '2026-11-02');
insert into pipeline.coverage_course_pages values ('00000000-0000-0000-0000-000000000c05', '00000000-0000-0000-0000-00000000e005'), ('00000000-0000-0000-0000-000000000c01', '00000000-0000-0000-0000-00000000e001');
insert into catalogue.course_fees(id, course_id, fee_year, fee_type, amount, currency_code, basis, notes, evidence_id) values
 ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-000000000c01', 2027, 'provider_current_tuition', 27338, 'AUD', 'annual', 'AI fee reader (https://www.utas.edu.au/c7u)', '00000000-0000-0000-0000-00000000e001'),
 ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-000000000c02', 2027, 'provider_current_tuition', 30000, 'AUD', 'annual', 'AI fee reader (https://x)', null),
 ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-000000000c03', 2027, 'provider_current_tuition', 31000, 'AUD', 'annual', 'AI fee reader (https://y)', null),
 ('00000000-0000-0000-0000-0000000000f4', '00000000-0000-0000-0000-000000000c04', 2026, 'provider_current_tuition', 24000, 'AUD', 'annual', 'University adapter reading of the course page', null),
 ('00000000-0000-0000-0000-0000000000f9', '00000000-0000-0000-0000-000000000c01', null, 'tuition', 74722.5, 'AUD', 'registered_total_course', 'CRICOS', null);
insert into pipeline.fee_reader_rows(course_id, quote, outcome) values ('00000000-0000-0000-0000-000000000c01', '2027 annual fee $27,338', 'admitted');
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', '00000000-0000-0000-0000-000000000c02', 'tuition', 'value');
insert into pipeline.uni_adapter_exclusions(course_id, field, reason) values ('00000000-0000-0000-0000-000000000c01', 'fee', 'automatic: held back for review');
insert into pipeline.enrichment_flags(id, entity, entity_key, field, reason_code, reason, state, released_at, released_by, release_kind, release_reason) values
 (19713, 'course', '00000000-0000-0000-0000-000000000c01', 'fee', 'fee_crosscheck', 'automatic: more than 25% from the CRICOS total', 'released', '2026-10-18 08:24', 'msingh', 'person',
  'Platform Admin 18 Oct 2026 18:53 "Split by group": the page figure is not an annual fee');
insert into pipeline.enrichment_flags(id, entity, entity_key, field, reason_code, reason, state) values
 (19800, 'course', '00000000-0000-0000-0000-000000000c05', 'fee', 'fee_crosscheck', 'automatic: more than 25% from the CRICOS total', 'raised');
create table fx.before as select md5(f::text) m from pipeline.enrichment_flags f where id = 19713;

-- 1 raise: one new item, the decided flag untouched, evidence and earlier decisions attached
select fx.ok((security.fee_admitted_recheck_v1('00000000-0000-0000-0000-0000000000f1', 'IQ-00111 D12: admitted after the fee check decision', 'Platform Admin (paste)')->>'raised')::boolean, 'raise: the AI fee goes to Layer 4');
select fx.ok((select md5(f::text) from pipeline.enrichment_flags f where id = 19713) = (select m from fx.before), 'raise: the decided item is not changed');
select fx.ok((select evidence->>'evidence_id' = '00000000-0000-0000-0000-00000000e001' and evidence->>'quote' = '2027 annual fee $27,338' and (evidence->>'cricos_total')::numeric = 74722.5
               and jsonb_array_length(evidence->'earlier_decisions') = 1 and evidence->'earlier_decisions'->0->>'release_reason' like '%not an annual fee'
               and evidence->'exclusion'->>'reason' like 'automatic%' and raised_by_kind = 'person' and state = 'raised'
              from pipeline.enrichment_flags where field = 'fee_ai_recheck' and entity_key = '00000000-0000-0000-0000-000000000c01'), 'raise: fee, stored copy, quote, CRICOS total, exclusion and earlier decision attached');
select fx.ok((select count(*) = 1 from pipeline.enrichment_flag_events e join pipeline.enrichment_flags f on f.id = e.flag_id where f.field = 'fee_ai_recheck' and e.action = 'raised' and e.actor_kind = 'person'), 'raise: one history event, by a person');
-- 2 refusals
select fx.ok((security.fee_admitted_recheck_v1('00000000-0000-0000-0000-0000000000f1', 'IQ-00111 D12: second time', 'x')->>'raised')::boolean = false, 'refused: a course already re-checked');
select fx.ok((security.fee_admitted_recheck_v1('00000000-0000-0000-0000-0000000000f2', 'IQ-00111 D12: locked course', 'x')->>'why') like 'the course has a manual value%', 'refused: a manual value is never touched');
select fx.ok((security.fee_admitted_recheck_v1('00000000-0000-0000-0000-0000000000f4', 'IQ-00111 D12: adapter fee', 'x')->>'raised')::boolean = false, 'refused: not an AI fee reader value');
select fx.ok((select count(*) from pipeline.enrichment_flags where field = 'fee_ai_recheck') = 1, 'refusals raise nothing');
-- 3 the card (the Layer 4 owner's inbox, 4fc05d14): "Fee fails the check", stored copy of the bound page linked, earlier decision in the reason; decided items not listed
select fx.ok((select kind = 'fee_check' and detail->>'evidence_id' = '00000000-0000-0000-0000-00000000e001' and detail->>'flag_id' is not null
               and why like 'Re-check an admitted AI fee: AUD 27,338.00 for 2027 is active, but a person decided earlier: Platform Admin 18 Oct 2026%'
              from security.layer4_inbox_items_v1() where detail->>'course_id' = '00000000-0000-0000-0000-000000000c01'), 'card: Fee fails the check, stored copy linked, earlier decision in the reason');
select fx.ok(not exists (select 1 from security.layer4_inbox_items_v1() where ref = '19713'), 'card: the decided item is not listed again');
-- 4 "Keep the CRICOS total" (the card releases the item as a person) withdraws the AI fee
select security.flag_release_v1((select id from pipeline.enrichment_flags where field = 'fee_ai_recheck'), 'msingh', 'person', 'Layer 4: keep the CRICOS total', '{}', false);
select fx.ok((select status = 'inactive' and valid_to = current_date and notes like '%Layer 4 re-check item % kept the CRICOS total (msingh)' from catalogue.course_fees where id = '00000000-0000-0000-0000-0000000000f1'),
             'keep: the AI fee is withdrawn with the decision in its note');
select fx.ok((select status = 'active' from catalogue.course_fees where id = '00000000-0000-0000-0000-0000000000f9'), 'keep: the CRICOS row is untouched');
select fx.ok(exists (select 1 from fx.refreshed where course_id = '00000000-0000-0000-0000-000000000c01') and exists (select 1 from search.refresh_requests), 'keep: savings recomputed, website refresh asked');
select fx.ok((select (detail->>'withdrawn')::int = 1 from pipeline.admin_control_events where action = 'recheck_keep'), 'keep: recorded');
-- 5 the fee was confirmed on the course first ("Open the course"): keep withdraws nothing
select security.fee_admitted_recheck_v1('00000000-0000-0000-0000-0000000000f3', 'IQ-00111 D12: confirm case', 'x');
update catalogue.course_fees set status = 'superseded' where id = '00000000-0000-0000-0000-0000000000f3';
insert into catalogue.course_fees(course_id, fee_year, fee_type, amount, basis, notes) values ('00000000-0000-0000-0000-000000000c03', 2027, 'provider_current_tuition', 31000, 'annual', 'Manual entry');
select security.flag_release_v1((select id from pipeline.enrichment_flags where field = 'fee_ai_recheck' and entity_key = '00000000-0000-0000-0000-000000000c03'), 'msingh', 'person', 'Layer 4: keep', '{}', false);
select fx.ok((select count(*) = 1 from catalogue.course_fees where course_id = '00000000-0000-0000-0000-000000000c03' and status = 'active' and notes = 'Manual entry'), 'confirmed on the course: the hand-entered fee stays');
-- 6 an automatic release, or the switch off, withdraws nothing
update catalogue.course_fees set status = 'active' where id = '00000000-0000-0000-0000-0000000000f1';
update pipeline.enrichment_flags set state = 'raised', field = 'fee_ai_recheck' where field = 'fee_ai_recheck' and entity_key = '00000000-0000-0000-0000-000000000c01';
update pipeline.platform_toolset_settings set value = '0' where key = 'fees.recheck_keep_withdraws_on';
select security.flag_release_v1((select id from pipeline.enrichment_flags where field = 'fee_ai_recheck' and entity_key = '00000000-0000-0000-0000-000000000c01'), 'msingh', 'person', 'Layer 4: keep', '{}', false);
select fx.ok((select status = 'active' from catalogue.course_fees where id = '00000000-0000-0000-0000-0000000000f1'), 'switch off: the item is released and the AI fee stays');
update pipeline.platform_toolset_settings set value = '1' where key = 'fees.recheck_keep_withdraws_on';
update pipeline.enrichment_flags set state = 'raised' where field = 'fee_ai_recheck' and entity_key = '00000000-0000-0000-0000-000000000c01';
select security.flag_release_v1((select id from pipeline.enrichment_flags where field = 'fee_ai_recheck' and entity_key = '00000000-0000-0000-0000-000000000c01'), 'controller', 'auto', 'automatic', '{}', false);
select fx.ok((select status = 'active' from catalogue.course_fees where id = '00000000-0000-0000-0000-0000000000f1'), 'automatic release: nothing withdrawn (only a person decides)');
