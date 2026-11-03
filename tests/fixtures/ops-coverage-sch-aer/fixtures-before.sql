-- The defects, reproduced on the live definitions before the migration.
do $$
declare n int; s record;
begin
  -- 1. the AER coverage reader counts no course: every course is 'unpublished' (as live), so courses_eligible and course requirement counts are 0
  select * into s from security.aer_provider_states_v1() x where x.provider_id = 'd0000000-0000-0000-0000-000000000002';
  perform fx.ok(s.courses_eligible = 0, 'before: Harbour University has 40 active courses but the AER reader counts ' || s.courses_eligible);
  select * into s from security.aer_provider_states_v1() x where x.provider_id = 'd0000000-0000-0000-0000-000000000009';
  perform fx.ok(s.course_req_proposed = 0 and s.disposition <> 'course_only', 'before: River University''s 10 proposed course rows are invisible');
  raise notice 'before 1: aer_provider_states_v1 counts 0 courses and 0 course requirements (defect reproduced)';
  -- 2. discovery rows of refused providers sit as pending with no outcome; the refill counts them as waiting work
  select count(*) into n from pipeline.scholarship_discovery_providers d where d.status = 'pending' and not security.fc_sch_eligible_v1(d.provider_id);
  perform fx.ok(n = 4, 'before: 4 pending rows of refused providers, found ' || n);
  perform fx.ok((select count(*) from pipeline.scholarship_discovery_providers where status in ('pending', 'deferred')) = 4, 'before: the refill counts 4 waiting rows');
  perform fx.ok(not exists (select 1 from pipeline.scholarship_discovery_providers where status = 'not_eligible'), 'before: no outcome status exists');
  raise notice 'before 2: 4 refused discovery rows wait as pending with no outcome, counted by the refill as waiting work (defect reproduced)';
end $$;
