CREATE OR REPLACE FUNCTION security.course_description_retire_stale_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_on boolean := security.pipeline_num_v1('enrich.course_description_stale_supersede_on', 0) >= 1; r record; v_n int := 0; v_ex int := 0; v_by jsonb := '{}'::jsonb; v_reason text;
        v_max int := security.pipeline_num_v1('layer4.reconcile_batch', 200)::int;
begin
  -- 15 Nov 2026 (job governance quick win 1): the two classes this job retires, read directly with the rules of the course description
  -- reconcile (a course no longer active first, then a course that already has a description). Reading them through the reconcile also ran
  -- the full course description check on every waiting proposal, which this job never uses.
  for r in select i.id item_id, c.id course_id,
                  case when c.lifecycle_status is distinct from 'active' then 'course_inactive' else 'already_filled' end class,
                  i.field_code, i.entity_type, i.entity_id, i.evidence_id
             from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id
            where i.status = 'pending' and i.entity_type = 'course' and i.field_code = 'course_description_first_read'
              and (c.lifecycle_status is distinct from 'active' or nullif(btrim(c.description), '') is not null)
            order by i.created_at limit v_max loop
    v_ex := v_ex + 1;
    v_reason := case r.class when 'course_inactive' then 'entity_retired' else 'covered_by_active' end;
    v_by := v_by || jsonb_build_object(v_reason, coalesce((v_by ->> v_reason)::int, 0) + 1);
    continue when not v_on;
    update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
           change_control_ref = left(coalesce(change_control_ref, '') || ' | superseded: ' || v_reason || ' (course description proposal can no longer be approved)', 400)
     where id = r.item_id and status = 'pending';
    continue when not found;
    insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)
    values (r.item_id, r.field_code, r.entity_type, r.entity_id, v_reason, null,
            jsonb_build_object('class', r.class, 'evidence_id', r.evidence_id, 'by', 'course-description-stale-retire'), 'reconcile');
    if to_regclass('pipeline.layer4_item_readiness') is not null then
      execute 'update pipeline.layer4_item_readiness set item_status = ''superseded'', readiness = ''closed'', classified_at = now() where item_id = $1' using r.item_id;
    end if;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('on', v_on, 'examined', v_ex, 'superseded', v_n, 'by_reason', v_by);
end $function$
