-- S670 fixture data (invented; nothing here is live data), added to the aer-qut-shared courses: hand-bound and hand-locked courses on pages other courses were refused for, bound on, or ambiguous on
do $d$
declare p uuid := '00000000-0000-0000-0000-0000000000a3';
begin
  insert into t.named values
   ('H1', t.course(p, 'Certificate IV in Baking', 'bound', 'manual', 'https://x.test/h1', true)), ('J1', t.course(p, 'Certificate III in Baking', 'mismatch', null, 'https://x.test/h1')),
   ('H2', t.course(p, 'Diploma of Tau', 'bound', 'manual', 'https://x.test/h2', true)), ('J2', t.course(p, 'Advanced Diploma of Tau', 'bound', 'cricos_code', 'https://x.test/h2')),
   ('H3', t.course(p, 'Diploma of Upsilon', 'bound', 'manual', 'https://x.test/h3', true)), ('J3', t.course(p, 'Diploma of Phi', 'ambiguous', 'exact_title', 'https://x.test/h3')),
   ('H4', t.course(p, 'Certificate of Chi', 'bound', 'manual', 'https://x.test/h4', true)), ('J4', t.course(p, 'Certificate of Psi', 'mismatch', null, 'https://x.test/h4')),
   ('K4', t.course(p, 'Certificate of Omega', 'mismatch', null, 'https://x.test/h4')),
   ('H5', t.course(p, 'Diploma of Business (Standard)', 'bound', 'cricos_code', 'https://x.test/h5', true)), ('J5', t.course(p, 'Diploma of Business (Accelerated)', 'bound', 'cricos_code', 'https://x.test/h5')),
   ('H6', t.course(p, 'Master of Stigma', 'bound', 'degree_name', 'https://x.test/h6', true)), ('J6', t.course(p, 'Master of Koppa', 'mismatch', null, 'https://x.test/h6'));
end $d$;
create table t.shared_s670_before as select n.name, jsonb_array_length(security.course_entry_shared_page_v1(n.id)) n from t.named n where n.name ~ '^[AHJ][0-9]$';
