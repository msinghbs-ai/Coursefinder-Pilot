-- CF-247 v2.15.252 (Platform Admin, 12 Oct 2026 08:15): "Stop Layer 3 from working on intakes, English and fees and clean up UI and
-- scripts. That was requested when the adapter was designed: stop any redundant UI and scripts when the adapter merged Layers 2 and 3."
-- Decisions: stop everywhere (universities without an adapter keep the university-wide calendar and English defaults); pause now and
-- delete by a paste file later; close the pending Layer 4 items for intakes, English and fees.
-- In the 24 hours before this, 93% of Layer 3 intake and English work was for universities whose adapter already admits that field,
-- and the resulting Layer 4 items were closed on arrival (5,533 overnight).
-- Nothing is dropped or deleted: the 10 jobs are paused (cron.alter_job active false) and stay listed until the paste file removes them.

do $l3$
declare v record; v_n int := 0;
begin
  for v in select j.jobid, j.jobname from cron.job j
            where j.jobname in ('layer3-intake-route', 'layer3-english-route', 'layer3-fact-admit', 'layer3-tuition-dispatch', 'layer3-tuition-admission',
                                'layer3-tuition-assumed-annual', 'coverage-tuition-handoff', 'layer4-tuition-settle', 'layer3-route-guard', 'layer3-operations-housekeeping')
  loop
    perform cron.alter_job(v.jobid, active := false);
    v_n := v_n + 1;
  end loop;
  if v_n <> 10 then raise exception 'expected 10 Layer 3 jobs, found %', v_n; end if;
end $l3$;

update pipeline.automation_catalogue
   set description = 'Retired 12 Oct 2026 (v2.15.252): Layer 3 no longer reads intakes, English or fees; university adapters admit them. Paused until removed. ' || coalesce(description, '')
 where jobname in ('layer3-intake-route', 'layer3-english-route', 'layer3-fact-admit', 'layer3-tuition-dispatch', 'layer3-tuition-admission',
                   'layer3-tuition-assumed-annual', 'coverage-tuition-handoff', 'layer4-tuition-settle', 'layer3-route-guard', 'layer3-operations-housekeeping')
   and coalesce(description, '') not like 'Retired 12 Oct 2026%';

-- The pending Layer 4 items for intakes, English and fees (Layer 3 proposals at universities without an admitting adapter)
update pipeline.layer4_review_items
   set status = 'superseded', decided_at = now(),
       change_control_ref = coalesce(change_control_ref || '; ', '') || 'CF-247 v2.15.252: Layer 3 retired; the university needs an adapter for this field'
 where status = 'pending' and entity_type = 'course' and field_code in ('course_intake', 'course_english', 'provider_current_tuition_validation');
