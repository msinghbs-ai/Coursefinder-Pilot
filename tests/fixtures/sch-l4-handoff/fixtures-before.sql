-- The IQ-00264 defects on the released definitions (v2.15.461/463), in one transaction rolled back at the end.
begin;
do $$
declare v jsonb;
begin
  perform security.scholarship_coverage_classify_v1(array['40000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000003']::uuid[]);
  v := security.layer4_interventions_tick_v1();
  if (select state from pipeline.scholarship_coverage_items where item_key = 'sch:50000000-0000-0000-0000-000000000001') <> 'admitted_not_published' then raise exception 'before: S1 state'; end if;
  if exists (select 1 from pipeline.layer4_interventions where entity like '%50000000-0000-0000-0000-000000000001') then raise exception 'before: expected no work for S1'; end if;
  raise notice 'before: an admitted scholarship held only by its award value (S1) gets no review, intervention or recovery (reason "%")',
    (select reason from pipeline.scholarship_coverage_items where item_key = 'sch:50000000-0000-0000-0000-000000000001');
  if (select state from pipeline.scholarship_coverage_items where item_key = 'sch:50000000-0000-0000-0000-000000000002') <> 'admitted_not_published' then raise exception 'before: S2 state'; end if;
  raise notice 'before: a scholarship a person refused in Layer 4 (S2) is counted as unresolved admitted-not-published work';
end $$;
rollback;
