-- CF-247 FEE lane: every case after both migrations (settings as shipped: fees.guard_on 1, fees.respect_decisions_on 0).
\set ON_ERROR_STOP 1
select fx.reset();
-- courses from the IQ-00111 seed: c01 52 weeks, c07 156 weeks, c11 has a raised fee_crosscheck hold; AU provider b1
-- ===== plausibility guard =====
insert into catalogue.course_fees(id, course_id, fee_year, fee_type, amount, currency_code, basis, notes, status, audience) values
 ('00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-000000000c21', 2027, 'provider_current_tuition', 2027, 'NZD', 'annual', 'University adapter reading of the course page (international annual fee)', 'active', 'international'),   -- a year read as a fee
 ('00000000-0000-0000-0000-00000000f002', '00000000-0000-0000-0000-000000000c22', 2026, 'provider_current_tuition', 31500, 'NZD', 'annual', 'AI fee reader (https://x.example/fees)', 'active', 'international'),                                 -- ordinary fee
 ('00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-000000000c05', 2020, 'provider_current_tuition', 38000, 'AUD', 'annual', 'University adapter reading of the course page', 'active', 'international'),                              -- old fee year
 ('00000000-0000-0000-0000-00000000f004', '00000000-0000-0000-0000-000000000c11', 2027, 'provider_current_tuition', 37141, 'AUD', 'annual', 'AI fee reader (https://x.example/m)', 'active', 'international'),                                     -- AI fee on a raised hold
 ('00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-000000000c07', 2026, 'provider_current_tuition', 48000, 'AUD', 'annual', 'CF-247 Layer 3 admission; period not stated', 'active', 'international'),                              -- annual = whole-course total of a 3-year course
 ('00000000-0000-0000-0000-00000000f006', '00000000-0000-0000-0000-000000000c01', 2027, 'provider_current_tuition', 37800, 'AUD', 'annual', 'Manual entry', 'active', 'international'),                                                          -- 1-year course whose annual equals the total: fine
 ('00000000-0000-0000-0000-00000000f007', '00000000-0000-0000-0000-000000000c12', 2026, 'provider_current_tuition', 2026, 'AUD', 'annual', 'University adapter reading', 'inactive', 'international');                                         -- year-like but not active: ignored
insert into catalogue.course_fees(course_id, fee_year, fee_type, amount, currency_code, basis, status, audience) values
 ('00000000-0000-0000-0000-000000000c07', 2026, 'tuition', 48000, 'AUD', 'registered_total_course', 'active', 'international'),
 ('00000000-0000-0000-0000-000000000c01', 2026, 'tuition', 37800, 'AUD', 'registered_total_course', 'active', 'international');
create temp table _before as select md5(string_agg(f::text, '|' order by f.id::text)) m from catalogue.course_fees f;
select security.fee_plausibility_check_v1() r \gset
select fx.ok(:'r'::jsonb->'counts'->'fee_amount_is_a_year'->>'count' = '1', 'a fee equal to its year is found (one), the inactive one is ignored');
select fx.ok(:'r'::jsonb->'counts'->'fee_year_out_of_range'->>'count' = '1', 'a fee year of 2020 is found');
select fx.ok(:'r'::jsonb->'counts'->'fee_ai_on_held_course'->>'count' = '1', 'an AI fee on a course with a raised fee check hold is found');
select fx.ok(:'r'::jsonb->'counts'->'fee_annual_equals_registered_total'->>'count' = '1', 'an annual fee equal to the registered total of a 3-year course is found; the 1-year course is not');
select fx.ok((select count(*) from pipeline.enrichment_flags where entity = 'fees' and state = 'raised' and kind = 'hard') = 2 and (select count(*) from pipeline.enrichment_flags where entity = 'fees' and state = 'raised' and kind = 'soft') = 2,
             'two hard and two soft flags raised, one per reason');
select fx.ok((select evidence->'sample'->0->>'fee' = '00000000-0000-0000-0000-00000000f001' from pipeline.enrichment_flags where entity = 'fees' and reason_code = 'fee_amount_is_a_year'), 'the flag lists the row keys (fee id and course id)');
select fx.ok((select md5(string_agg(f::text, '|' order by f.id::text)) from catalogue.course_fees f) = (select m from _before), 'the guard changed no fee row');
select fx.ok((select (security.fee_integrity_measure_v1()->>'ai_active_on_held')::int) = 1, 'the guard agrees with the IQ-00111 measure on AI fees on held courses');
-- a second run does not duplicate the flags
select security.fee_plausibility_check_v1();
select fx.ok((select count(*) from pipeline.enrichment_flags where entity = 'fees') = 4, 'a second run keeps four flags (one per reason)');
-- the wrong fee is withdrawn by a person: the flag is released by the next run
update catalogue.course_fees set status = 'inactive' where id = '00000000-0000-0000-0000-00000000f001';
select security.fee_plausibility_check_v1();
select fx.ok((select state = 'released' from pipeline.enrichment_flags where entity = 'fees' and reason_code = 'fee_amount_is_a_year'), 'after the withdrawal the year-like flag is released');
-- settings: the range is a setting, the switch switches
update pipeline.platform_toolset_settings set value = '2100' where key = 'fees.guard_year_min';
update catalogue.course_fees set status = 'active' where id = '00000000-0000-0000-0000-00000000f001';
select fx.ok((security.fee_plausibility_check_v1()->'counts'->'fee_amount_is_a_year') is null, 'a narrowed year range (setting) stops the year-like match');
update pipeline.platform_toolset_settings set value = '1990' where key = 'fees.guard_year_min';
update pipeline.platform_toolset_settings set value = '0' where key = 'fees.guard_on';
select fx.ok(security.fee_plausibility_check_v1()->>'skipped' is not null, 'fees.guard_on 0: the guard does not run');
update pipeline.platform_toolset_settings set value = '1' where key = 'fees.guard_on';
select fx.ok((select count(*) from cron.job where jobname = 'fee-plausibility-guard' and replace(command, '_v1', '') !~ '[0-9]') = 1, 'the job command carries no number (G2) and the job is scheduled');
select fx.ok(exists (select 1 from pipeline.automation_catalogue where jobname = 'fee-plausibility-guard'), 'the job is catalogued (G1)');

-- ===== decision memory (IQ-00040) =====
-- a read of c01 that ends in review (old fee year 2020) for 25,000 a year
create function fx.read_old(p_course uuid, p_amount numeric) returns jsonb language sql as $f$
  select fx.read(p_course, jsonb_build_array(jsonb_build_object('amount_min', p_amount, 'currency', 'AUD', 'unit', 'per_year', 'fee_year', 2020, 'quote', 'Fee per year $' || p_amount::text))) $f$;
create function fx.decide(p_course uuid, p_amount numeric, p_status text, p_days int) returns void language sql as $f$
  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, proposed_value, status, decided_at, created_at)
  values ('course', p_course, 'provider_current_tuition_validation', jsonb_build_object('amount', p_amount), p_status, now() - make_interval(days => p_days), now() - make_interval(days => p_days + 1)) $f$;
create function fx.pending(p_course uuid) returns bigint language sql as $f$
  select count(*) from pipeline.layer4_review_items where entity_id = p_course and status = 'pending' $f$;
select fx.reset();
delete from catalogue.course_fees;
select fx.decide('00000000-0000-0000-0000-000000000c01', 25000, 'rejected', 10);
select fx.read_old('00000000-0000-0000-0000-000000000c01', 25000);
select fx.ok(fx.pending('00000000-0000-0000-0000-000000000c01') = 1, 'switch off (as shipped): the repeat is raised again, as before');
select fx.reset(); delete from catalogue.course_fees;
update pipeline.platform_toolset_settings set value = '1' where key = 'fees.respect_decisions_on';
select fx.decide('00000000-0000-0000-0000-000000000c01', 25000, 'rejected', 10);
select fx.read_old('00000000-0000-0000-0000-000000000c01', 25000);
select fx.ok(fx.pending('00000000-0000-0000-0000-000000000c01') = 0, 'switch on: the same figure a person rejected is not raised again');
select fx.ok((select outcome = 'review' and note like '%a person already ruled on this figure (rejected%not raised again%' from pipeline.fee_reader_rows where course_id = '00000000-0000-0000-0000-000000000c01'), 'the read is kept as review with the reason in its note');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c01') is null, 'nothing is admitted');
select fx.reset(); delete from catalogue.course_fees;
select fx.decide('00000000-0000-0000-0000-000000000c01', 25000, 'rejected', 10);
select fx.read_old('00000000-0000-0000-0000-000000000c01', 26000);
select fx.ok(fx.pending('00000000-0000-0000-0000-000000000c01') = 1, 'a different amount is asked about');
select fx.reset(); delete from catalogue.course_fees;
select fx.decide('00000000-0000-0000-0000-000000000c01', 25000, 'rejected', 200);
select fx.read_old('00000000-0000-0000-0000-000000000c01', 25000);
select fx.ok(fx.pending('00000000-0000-0000-0000-000000000c01') = 1, 'a ruling older than fees.decision_memory_days is asked about again');
select fx.reset(); delete from catalogue.course_fees;
select fx.decide('00000000-0000-0000-0000-000000000c01', 25000, 'edited_approved', 3);
select fx.read_old('00000000-0000-0000-0000-000000000c01', 25000.50);
select fx.ok(fx.pending('00000000-0000-0000-0000-000000000c01') = 0, 'an edited approval counts as a ruling; rounding within the setting is the same figure');
select fx.reset(); delete from catalogue.course_fees;
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, proposed_value, status) values ('course', '00000000-0000-0000-0000-000000000c01', 'provider_current_tuition_validation', '{"amount": 25000}', 'pending');
select fx.read_old('00000000-0000-0000-0000-000000000c01', 25000);
select fx.ok(fx.pending('00000000-0000-0000-0000-000000000c01') = 1, 'a pending item is not a ruling and is not duplicated');
select fx.ok(not exists (select 1 from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected') and decided_at is null), 'no item was decided by the platform');
