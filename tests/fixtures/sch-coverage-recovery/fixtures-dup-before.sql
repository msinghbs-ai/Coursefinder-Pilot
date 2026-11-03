-- The v2.15.460 defect on the released definition: a listing lists the same address twice, so the case appears twice in one insert and the run
-- fails (as live at 06:29 AEDT 4 Nov 2026). Rolled back: nothing is kept.
do $$
begin
  begin
    perform security.scholarship_coverage_classify_v1(array['10000000-0000-0000-0000-000000000001']::uuid[]);
    raise exception 'before fix: expected the duplicate listing item to fail the run';
  exception when cardinality_violation then
    raise notice 'before fix: % (the duplicate listing item fails the run)', split_part(sqlerrm, E'\n', 1);
  end;
  if exists (select 1 from pipeline.scholarship_coverage_items) then raise exception 'before fix: nothing should be kept'; end if;
end $$;
