-- CF-247 (2 Oct 2026), follow-up to the UQ review (Platform Admin, 15:02). The same UQ course was sent to a person again
-- at 12:31 by "layer3-tuition-enqueue", which still fed the retired Layer 2 pipeline's August page snapshots to the AI fee
-- check. The course-page sweep now hands its own freshly read pages to that check (svc_coverage_tuition_handoff_next),
-- so the old feed is paused like the rest of that pipeline (switched off, not removed).
-- Eleven waiting reviews from that feed ask about a course whose recorded international fee is the same amount the
-- current reader reads from the same page today; they are closed as superseded (kept, with the reason). Nothing in the
-- catalogue changes.
select cron.alter_job(j.jobid, active := false) from cron.job j where j.jobname = 'layer3-tuition-enqueue' and j.active;

update pipeline.layer4_review_items r
   set status = 'superseded', decided_at = now(),
       layer3_state = coalesce(r.layer3_state, '{}'::jsonb) || jsonb_build_object('superseded', jsonb_build_object(
         'reason', 'Already answered: the recorded international fee is the amount the current reader reads from this course''s page (retired pipeline feed).',
         'recorded_amount', f.amount, 'at', now(), 'ref', 'CF-247 2 Oct 2026 15:02'))
  from pipeline.layer3_interpretations i
  join pipeline.layer3_work_items w on w.interpretation_id = i.id,
       lateral (select cf.amount from catalogue.course_fees cf
                  join pipeline.coverage_course_pages g on g.course_id = cf.course_id and g.read_status = 'read'
                                                       and (g.candidates->'fee'->>'value')::numeric = cf.amount
                 where cf.course_id = w.entity_id and cf.fee_type = 'provider_current_tuition' and cf.status = 'active' limit 1) f
 where i.id = r.layer3_interpretation_id and r.status = 'pending' and r.field_code = 'provider_current_tuition_validation'
   and w.layer2_run_item_id is not null
   and not exists (select 1 from pipeline.coverage_course_pages g2 where g2.l3_work_item_id = w.id);
