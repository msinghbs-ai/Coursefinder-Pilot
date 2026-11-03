-- CF-247 IQ-00111: the 2 Nov 2026 defects reproduced on the live definitions (before the migration).
\set ON_ERROR_STOP 1
select fx.reset();
-- Murdoch 096011C: 37,800 for the 1-year course, read as 24 points of an 8-unit year -> 12,600 admitted
select fx.read('00000000-0000-0000-0000-000000000c01', '[{"amount_min": 37800, "amount_max": 37800, "currency": "AUD", "unit": "per_course", "units_covered": 24, "fee_year": 2027,
  "quote": "Full course fee (international) An estimate of the total tuition fees for the entire course, based on standard full-time study. 2027 $37,800"}]');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c01') = 12600, 'before: Murdoch 37,800 one-year course admitted as 12,600 (the defect)');
-- WSU 121432C: the fee check hold is raised, the page fee is admitted anyway
select fx.read('00000000-0000-0000-0000-000000000c11', '[{"amount_min": 37141, "currency": "AUD", "unit": "per_year", "fee_year": 2027, "quote": "2027 annual fee $37,141"}]');
select fx.ok(fx.fee('00000000-0000-0000-0000-000000000c11') = 37141, 'before: WSU page fee admitted while its fee check hold is raised (the defect)');
