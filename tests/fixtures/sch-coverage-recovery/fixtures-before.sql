-- The defects on the live definitions (run in one transaction and rolled back by run.sh's seed state being unchanged: every case only reads,
-- except the read_next call, which is rolled back below).
do $$
begin
  -- D1: Torrens, a TEQSA-registered Australian University, is refused by the name rule
  if security.scholarship_university('10000000-0000-0000-0000-000000000001') then raise exception 'before D1: expected Torrens to be refused'; end if;
  if security.scholarship_admission_provider_ok_v1('10000000-0000-0000-0000-000000000001') then raise exception 'before D1: admission eligibility expected false'; end if;
  raise notice 'before D1: Torrens University Australia is not a university to the admission rule (joined trading names)';
  -- D5: TAFE SA, refused by the admission policy, is reported as zero scholarships
  if (select disposition from security.scholarship_coverage_v1(array['10000000-0000-0000-0000-000000000002'::uuid])) is distinct from 'zero' then
    raise exception 'before D5: expected TAFE SA reported as zero, got %', (select disposition from security.scholarship_coverage_v1(array['10000000-0000-0000-0000-000000000002'::uuid]));
  end if;
  raise notice 'before D5: TAFE SA (admission policy) is reported as zero';
end $$;
-- D7: "Read again" does not read: the requested Macquarie page is not due until its next_read_at
savepoint d7;
do $$
declare v jsonb := public.svc_scholarship_read_next(10);
begin
  if v @> '[{"scholarship_id": "30000000-0000-0000-0000-000000000001"}]' then raise exception 'before D7: expected the requested page not to be picked'; end if;
  raise notice 'before D7: a page asked for with Read again is not picked (% picked)', jsonb_array_length(v);
end $$;
rollback to savepoint d7;
