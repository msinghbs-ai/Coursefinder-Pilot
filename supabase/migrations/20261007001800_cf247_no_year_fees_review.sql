-- CF-247, 7 Oct 2026 (Platform Admin: tuition with no fee year). Active international current-tuition rows with no fee year:
-- 1. Newcastle rows read from its 2026 undergraduate schedule take the schedule's year (2026), unless the course already holds a 2026 fee;
--    where it does and the amounts are equal, the year-less copy is retired.
-- 2. Every other active year-less row (mainly Layer 3 admissions where the page gives no period and per year was assumed under the 29 Sep rule,
--    plus a 2021 schedule and two August Layer 2 rows) is sent to Layer 4 review with its reason. The value stays shown until a person decides.
do $p$
declare v_stamp int; v_dupe int; v_queue int; v_ev uuid := 'e1346225-4aa8-47cb-8855-cce6a117c8ad';
begin
  update catalogue.course_fees f set fee_year = 2026, source_fee_key = replace(f.source_fee_key, ':current:', ':2026:'), updated_at = now()
   where f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.fee_year is null and f.evidence_id = v_ev
     and not exists (select 1 from catalogue.course_fees g where g.course_id = f.course_id and g.id <> f.id and g.status = 'active' and g.fee_type = f.fee_type and g.audience = f.audience and g.fee_year = 2026)
     and not exists (select 1 from catalogue.course_fees g where g.id <> f.id and g.source_fee_key = replace(f.source_fee_key, ':current:', ':2026:') and g.source_id is not distinct from f.source_id);
  get diagnostics v_stamp = row_count;
  update catalogue.course_fees f set status = 'superseded', updated_at = now()
   where f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.fee_year is null and f.evidence_id = v_ev
     and exists (select 1 from catalogue.course_fees g where g.course_id = f.course_id and g.id <> f.id and g.status = 'active' and g.fee_type = f.fee_type and g.audience = f.audience and g.fee_year = 2026 and g.amount = f.amount);
  get diagnostics v_dupe = row_count;
  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, escalation_reason, change_control_ref)
  select 'course', f.course_id, 'provider_current_tuition_validation', f.evidence_id,
         jsonb_build_object('amount', f.amount, 'currency_code', f.currency_code, 'basis', f.basis, 'fee_year', null, 'audience', f.audience, 'notes', f.notes),
         null, 'pending',
         'No fee year on record' || case when f.notes like 'CF-247 Layer 3 admission; period not stated%' then ' and the page gives no period (per year was assumed under the 29 Sep rule)' else '' end
           || '. Confirm the year and that the amount is one year''s international tuition; the value stays shown until decided. Platform Admin, 7 Oct 2026.',
         'CF-CHG-20260915-247'
    from catalogue.course_fees f
   where f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.fee_year is null
     and not exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'course' and r.entity_id = f.course_id and r.field_code = 'provider_current_tuition_validation' and r.status = 'pending');
  get diagnostics v_queue = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fees', 'no_year_fees_review', 'provider current tuition with no fee year',
          jsonb_build_object('stamped_2026', v_stamp, 'retired_duplicates', v_dupe, 'queued_for_review', v_queue, 'decision', 'Platform Admin 7 Oct 2026'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
end $p$;
