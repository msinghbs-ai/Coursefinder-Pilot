-- The LIVE definition of security.course_description_machine_settle_v1() as pg_get_functiondef returned it on project fxcwkweaxjtknorudmwp, 11 Nov 2026 19:15 AEDT (body md5 4c40d655a7ff674ce184b598056d835f). Loaded by run.sh, md5 checked.
CREATE OR REPLACE FUNCTION security.course_description_machine_settle_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_res jsonb; v_ok int := 0; v_no int := 0; v_err int := 0; v_t0 timestamptz := clock_timestamp(); v_stamp text := security.course_description_machine_policy_stamp_v1();
        v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; -- derived: never more in a run than the platform reads in a day
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  for r in select li.id from pipeline.layer4_review_items li
             left join pipeline.course_description_machine_admissions d on d.review_item_id = li.id and d.outcome = 'declined'
            where li.field_code = 'course_description_first_read' and li.entity_type = 'course' and li.status = 'pending'
              and (d.id is null or d.policy_stamp is distinct from v_stamp or d.retry_after <= now())
            order by (d.id is not null), li.created_at, li.id limit v_cap loop
    exit when clock_timestamp() - v_t0 > make_interval(secs => 40); -- fixed: stays well inside the 120 s statement time-out of a job; the rest is taken next run
    begin
      v_res := security.course_description_machine_admit_v1(r.id, 'settle');
      if coalesce((v_res->>'ok')::boolean, false) then v_ok := v_ok + 1; else v_no := v_no + 1; end if;
    exception when others then v_err := v_err + 1;
    end;
  end loop;
  return jsonb_build_object('on', true, 'admitted', v_ok, 'left_for_a_person', v_no, 'errors', v_err);
end $function$
;
