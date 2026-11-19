CREATE OR REPLACE FUNCTION security.provider_description_machine_settle_pending_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_res jsonb; v_ok int := 0; v_no int := 0; v_err int := 0;
begin
  if security.pipeline_num_v1('pdesc.machine_admit_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  for r in select li.id from pipeline.layer4_review_items li where li.field_code = 'provider_description' and li.entity_type = 'provider' and li.status = 'pending'
            and not exists (select 1 from pipeline.provider_description_machine_admissions a where a.review_item_id = li.id and a.outcome = 'declined' and a.created_at > now() - make_interval(hours => 1)) -- fixed: a declined item is checked again at most hourly
            order by li.created_at limit security.pipeline_num_v1('pdesc.machine_settle_per_run', 10)::int loop
    begin
      v_res := security.provider_description_machine_admit_v1(r.id);
      if (v_res->>'ok')::boolean then v_ok := v_ok + 1; else v_no := v_no + 1; end if;
    exception when others then v_err := v_err + 1;
    end;
  end loop;
  return jsonb_build_object('on', true, 'admitted', v_ok, 'left_for_a_person', v_no, 'errors', v_err);
end $function$
