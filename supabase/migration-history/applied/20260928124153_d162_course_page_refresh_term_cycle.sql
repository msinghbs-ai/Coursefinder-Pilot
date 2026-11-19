-- CF-247 Decision 162 (interim cadence): provider course pages are refreshed once a term (90 days, class term-cycle), not weekly. Tuition,
-- English requirements and descriptions change about once a year; intakes about twice a year. Until the
-- page change check (Decision 162, step 3) is live, a quarterly full refresh is the interim for UQ and RMIT.
-- Next run is 90 days after the last one. The RMIT run already queued today is unaffected.
do $u$
declare v_n int;
begin
  update pipeline.refresh_policies
     set cadence_interval=interval '90 days', freshness_class='term-cycle',
         next_due_at=case id when '0a3f5388-93e2-49f9-88f2-88c9f8a6aabc' then timestamptz '2026-09-24 01:30:00+00' + interval '90 days'
                             else timestamptz '2026-09-28 12:36:00+00' + interval '90 days' end,
         change_control_ref='CF-CHG-20260915-247', updated_at=now()
   where id in ('0a3f5388-93e2-49f9-88f2-88c9f8a6aabc','fb417692-1c59-43ca-a5c4-924b5034b437')
     and layer=2 and cadence_interval=interval '168 hours';
  get diagnostics v_n=row_count;
  if v_n<>2 then raise exception 'expected the two weekly course-page policies (UQ, RMIT); found %; nothing changed', v_n; end if;
end $u$;
