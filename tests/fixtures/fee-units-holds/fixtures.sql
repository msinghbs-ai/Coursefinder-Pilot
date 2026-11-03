-- CF-247 IQ-00111: every case after the migration (settings as shipped: fees.units_load_fix_on 1, fees.respect_holds_on 1, fees.respect_all_exclusions_on 0).
\set ON_ERROR_STOP 1
select fx.reset();
-- 1 Murdoch: whole-course fee over a 1-year course (the model says credit points, which are not AU units) -> 37,800 admitted by course length
select fx.read('00000000-0000-0000-0000-000000000c01', '[{"amount_min": 37800, "amount_max": 37800, "currency": "AUD", "unit": "per_course", "units_covered": 24, "fee_year": 2027,
  "units_kind": "credit_points", "full_time_load": null, "course_years": 1, "whole_course": true,
  "quote": "Full course fee (international) An estimate of the total tuition fees for the entire course, based on standard full-time study. 2027 $37,800"}]');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c01') = 37800, 'Murdoch: 37,800 admitted (whole fee of a 1-year course)');
select fx.ok((select yearly_method = 'course_length' and units_kind = 'credit_points' from pipeline.fee_reader_rows where course_id = '00000000-0000-0000-0000-000000000c01'), 'Murdoch: made by course length; credit points recorded');
select fx.ok((select notes like 'yearly figure from 37800 for the whole course over 1.00 years; AI fee reader%' from catalogue.course_fees where course_id = '00000000-0000-0000-0000-000000000c01'), 'Murdoch: the note says how the figure was made');
-- 1b the same row with the setting off reproduces the earlier rule (the switch really switches)
update pipeline.platform_toolset_settings set value = '0' where key = 'fees.units_load_fix_on';
select fx.reset();
select fx.read('00000000-0000-0000-0000-000000000c01', '[{"amount_min": 37800, "currency": "AUD", "unit": "per_course", "units_covered": 24, "fee_year": 2027, "units_kind": "credit_points",
  "full_time_load": null, "course_years": 1, "whole_course": true, "quote": "Full course fee (international) An estimate of the total tuition fees for the entire course. 2027 $37,800"}]');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c01') = 12600, 'switch off: the earlier rule (count / country load) runs as before');
update pipeline.platform_toolset_settings set value = '1' where key = 'fees.units_load_fix_on';
select fx.reset();
-- 2 UNSW: whole fee of a 34-week course, 24 points, no load on the page -> not clear: Layer 4, nothing admitted
select fx.read('00000000-0000-0000-0000-000000000c02', '[{"amount_min": 31000, "amount_max": 31500, "currency": "AUD", "unit": "per_course", "units_covered": 24, "fee_year": 2026,
  "units_kind": null, "full_time_load": null, "course_years": null, "whole_course": null,
  "quote": "2026 Indicative First Year Fee $31,000* 2026 Indicative Fee to Complete Degree $31,500*"}]');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c02') is null, 'UNSW: nothing admitted (course shorter than a year, no load on the page)');
select fx.ok((select escalation_reason = 'Fee reader: the per-year figure is not clear' and (proposed_value->>'amount')::numeric = 31000 and layer2_state->>'note' like '%per-year figure not clear: 31000 is the whole fee of a course of 0.65 years%'
              from pipeline.layer4_review_items where entity_id = '00000000-0000-0000-0000-000000000c02'), 'UNSW: one Layer 4 item, the published figure and the reason');
-- 3 UNSW with the page's own load (48 units of credit a year) -> 62,000 a year admitted from the page load
select fx.read('00000000-0000-0000-0000-000000000c03', '[{"amount_min": 31500, "currency": "AUD", "unit": "per_course", "units_covered": 24, "fee_year": 2026,
  "units_kind": "credit_points", "full_time_load": 48, "course_years": null, "whole_course": true, "quote": "2026 Indicative Fee to Complete Degree $31,500*"}]');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c03') = 63000, 'UNSW with a stated load of 48: 31,500 for 24 points is 63,000 a full-time year');
-- 4 HELI: 49,200 for 12 units of a 2-year course: 8 units a year gives 1.5 years -> held, proposed 24,600 by course length
select fx.read('00000000-0000-0000-0000-000000000c04', '[{"amount_min": 49200, "currency": "AUD", "unit": "per_course", "units_covered": 12, "fee_year": 2026,
  "units_kind": "units", "full_time_load": null, "course_years": null, "whole_course": null, "quote": "Master of eLearning | $3,000 | $36,000 | $4,100 | $49,200"}]');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c04') is null, 'HELI: not admitted (12 units at 8 a year is 1.5 years, the course is 2)');
select fx.ok((select (proposed_value->>'amount')::numeric = 24600 from pipeline.layer4_review_items where entity_id = '00000000-0000-0000-0000-000000000c04'), 'HELI: Layer 4 proposes 24,600 (49,200 over 2 years)');
-- 5 Reach 106655B: 27,000 for 12 units of competency, 2-year course -> held, proposed 13,500
select fx.read('00000000-0000-0000-0000-000000000c06', '[{"amount_min": 27000, "amount_max": 29000, "currency": "AUD", "unit": "per_course", "units_covered": 12, "fee_year": 2026,
  "units_kind": "units", "full_time_load": null, "course_years": 2, "whole_course": true, "quote": "Course Pricing Offshore Fee $29,000* Onshore Fee $27,000* *Non-Tuition fees not included"}]');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c06') is null and (select (proposed_value->>'amount')::numeric = 13500 from pipeline.layer4_review_items where entity_id = '00000000-0000-0000-0000-000000000c06'),
             'Reach: not admitted; Layer 4 proposes 13,500');
-- 6 Barton: 56,000 for 16 units, 2-year course -> 28,000 (units agree with the length)
select fx.read('00000000-0000-0000-0000-000000000c05', '[{"amount_min": 56000, "currency": "AUD", "unit": "per_course", "units_covered": 16, "fee_year": 2026,
  "units_kind": "units", "full_time_load": null, "course_years": null, "whole_course": true, "quote": "Total Course Fees | AUD $56,000 (16 units in 1 year) | AUD $56,000 (16 units in 1 year)"}]');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c05') = 28000, 'Barton: 28,000 admitted (16 units over a 2-year course)');
-- 7 VIT: 51,000 for 24 units of a 3-year course -> 17,000
select fx.read('00000000-0000-0000-0000-000000000c07', '[{"amount_min": 51000, "currency": "AUD", "unit": "per_course", "units_covered": 24, "fee_year": 2026,
  "units_kind": "units", "full_time_load": null, "course_years": 3, "whole_course": true, "quote": "Bachelor of Information Technology and Systems | 3 Years (Full-Time), 2 Years (Fast-Track) | 24 | $51,000"}]');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c07') = 17000, 'VIT: 17,000 admitted (24 units over 3 years)');
-- 8 NZ (all countries): 60 points of a 120-point year -> 39,859.68; 120 points -> annual 27,300 (unchanged behaviour)
select fx.read('00000000-0000-0000-0000-000000000c21', '[{"amount_min": 19929.84, "currency": "NZD", "unit": "per_course", "units_covered": 60, "fee_year": 2026,
  "units_kind": null, "full_time_load": null, "course_years": null, "whole_course": null, "quote": "International $19,929.84 (for 60 points)"}]');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c21') = 39859.68, 'NZ: 60 points of a 120-point year, 39,859.68 a year (as before)');
select fx.read('00000000-0000-0000-0000-000000000c22', '[{"amount_min": 27300, "currency": "NZD", "unit": "per_year", "units_covered": 120, "fee_year": 2026,
  "units_kind": "credit_points", "full_time_load": null, "course_years": 3, "whole_course": false, "quote": "Annual fee $27,300 (120 points)"}]');
select fx.ok((select amount = 27300 and basis = 'annual' from catalogue.course_fees where course_id = '00000000-0000-0000-0000-000000000c22'), 'NZ: 120 points is a full-time year, 27,300 annual (as before)');
-- 9 holds: WSU raised hold -> held, nothing admitted, no new Layer 4 item
select fx.read('00000000-0000-0000-0000-000000000c11', '[{"amount_min": 37141, "currency": "AUD", "unit": "per_year", "fee_year": 2027, "units_kind": null, "full_time_load": null,
  "course_years": null, "whole_course": null, "quote": "2027 annual fee $37,141"}]');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c11') is null, 'WSU: raised fee check hold, page fee not admitted');
select fx.ok((select outcome = 'held' and note like '%not admitted: a fee check hold is raised%' from pipeline.fee_reader_rows where course_id = '00000000-0000-0000-0000-000000000c11'), 'WSU: recorded as held with the reason');
select fx.ok(not exists (select 1 from pipeline.layer4_review_items where entity_id = '00000000-0000-0000-0000-000000000c11'), 'WSU: no second Layer 4 question');
-- 10 088407E: hold released ("keep the CRICOS total"), exclusion active -> page fee 44,300 not admitted
select fx.read('00000000-0000-0000-0000-000000000c12', '[{"amount_min": 44300, "currency": "AUD", "unit": "per_year", "fee_year": 2026, "units_kind": null, "full_time_load": null,
  "course_years": null, "whole_course": null, "quote": "Annual fee $44,300"}]');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c12') is null, '088407E: fee check decision keeps the 44,300 page fee out');
-- 11 an exclusion for another reason (no fee check) stays readable unless the Platform Admin turns fees.respect_all_exclusions_on on
select fx.read('00000000-0000-0000-0000-000000000c13', '[{"amount_min": 30000, "currency": "AUD", "unit": "per_year", "fee_year": 2026, "units_kind": null, "full_time_load": null,
  "course_years": null, "whole_course": null, "quote": "Annual fee $30,000"}]');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c13') = 30000, 'other exclusion: AI second reading admitted as designed (switch off)');
update pipeline.platform_toolset_settings set value = '1' where key = 'fees.respect_all_exclusions_on';
select fx.ok(security.fee_reader_hold_v1('00000000-0000-0000-0000-000000000c13') = 'the page fee is excluded for this course', 'switch on: every fee exclusion keeps the page fee out');
update pipeline.platform_toolset_settings set value = '0' where key = 'fees.respect_all_exclusions_on';
-- 12 holds off reproduces the bypass (the switch really switches)
update pipeline.platform_toolset_settings set value = '0' where key = 'fees.respect_holds_on';
select fx.read('00000000-0000-0000-0000-000000000c11', '[{"amount_min": 37141, "currency": "AUD", "unit": "per_year", "fee_year": 2027, "quote": "2027 annual fee $37,141"}]');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c11') = 37141, 'switch off: the hold is not looked at (as before)');
update catalogue.course_fees set status = 'inactive' where course_id = '00000000-0000-0000-0000-000000000c11';
update pipeline.platform_toolset_settings set value = '1' where key = 'fees.respect_holds_on';
-- 13 the queue: a held course is not queued (path b) and its request closes as held (path a); an ordinary course is queued
insert into pipeline.evidence_artifacts values ('00000000-0000-0000-0000-00000000e012', 'https://example.edu/c12', 'p', 'h12'), ('00000000-0000-0000-0000-00000000e013', 'https://example.edu/c13', 'p', 'h13'),
                                               ('00000000-0000-0000-0000-00000000e011', 'https://example.edu/c11', 'p', 'h11');
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_status, read_at, identity_basis, evidence_id, candidates) values
 ('00000000-0000-0000-0000-000000000c12', '00000000-0000-0000-0000-0000000000b1', 'https://example.edu/c12', 'bound', 'read', now(), 'cricos_code', '00000000-0000-0000-0000-00000000e012', '{"fee_by": "adapter", "fee": {"value": "44300"}}'),
 ('00000000-0000-0000-0000-000000000c13', '00000000-0000-0000-0000-0000000000b1', 'https://example.edu/c13', 'bound', 'read', now(), 'cricos_code', '00000000-0000-0000-0000-00000000e013', '{"fee_by": "adapter", "fee": {"value": "15000"}}'),
 ('00000000-0000-0000-0000-000000000c11', '00000000-0000-0000-0000-0000000000b1', 'https://example.edu/c11', 'bound', 'read', now(), 'cricos_code', '00000000-0000-0000-0000-00000000e011', '{}');
delete from catalogue.course_fees where course_id = '00000000-0000-0000-0000-000000000c13';
insert into pipeline.fee_course_requests(course_id, requested_at) values ('00000000-0000-0000-0000-000000000c11', now() - interval '1 hour');
select security.fee_course_pages_enqueue_v1();
select fx.ok(not exists (select 1 from pipeline.fee_reader_queue where course_id = '00000000-0000-0000-0000-000000000c12' and content_hash = 'h12'), 'queue: 088407E (fee check decision) not queued for an AI read');
select fx.ok(exists (select 1 from pipeline.fee_reader_queue where course_id = '00000000-0000-0000-0000-000000000c13' and content_hash = 'h13'), 'queue: an ordinary adapter-excluded course is still queued (designed second reading)');
select fx.ok((select outcome = 'held' and queued_at is not null from pipeline.fee_course_requests where course_id = '00000000-0000-0000-0000-000000000c11'), 'queue: an Enrich fields request for a held course closes as held, not read');
-- 14 the verification remedy measures (records only)
select fx.ok((security.fee_integrity_verify_v1(111)->>'passed')::boolean, 'verify: no AI fee active on a held course, none made by the old division since the release');
insert into catalogue.course_fees(course_id, fee_year, fee_type, amount, basis, notes, created_at) values ('00000000-0000-0000-0000-000000000c11', 2027, 'provider_current_tuition', 37141, 'annual', 'AI fee reader (https://x)', now());
select fx.ok(not (security.fee_integrity_verify_v1(111)->>'passed')::boolean and (security.fee_integrity_measure_v1()->>'ai_active_on_held')::int = 1, 'verify: an AI fee active on a raised hold fails the check');
select fx.ok((security.fee_integrity_recheck_v1(111)->>'changed') = 'false', 'remedy action changes nothing');
