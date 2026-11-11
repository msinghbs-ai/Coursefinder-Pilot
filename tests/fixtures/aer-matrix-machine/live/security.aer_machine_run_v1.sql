CREATE OR REPLACE FUNCTION security.aer_machine_run_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_mode int := security.pipeline_num_v1('aer.machine_mode', 0)::int; v_batch int := security.pipeline_num_v1('batch.aer_machine', 60)::int;
        v_cap int := security.pipeline_num_v1('aer.machine_daily_max', 300)::int; v_used int; v_t0 timestamptz := clock_timestamp(); v_susp jsonb; r record; v jsonb;
        v_n int := 0; v_out jsonb := '{}'::jsonb; v_err int := 0;
begin
  if v_mode < 1 then return jsonb_build_object('mode', 0); end if;
  begin v_susp := security.aer_machine_suspend_check_v1(); exception when others then v_susp := jsonb_build_object('error', sqlerrm); end;
  select count(*) into v_used from pipeline.aer_machine_admissions where mode = 'admit' and outcome = 'admitted' and created_at > now() - make_interval(hours => 24); -- fixed: the cap counts the last 24 hours
  -- gate-complete items first (the readiness job's record), then the rest that were never looked at by the rule, oldest first
  for r in select i.id from pipeline.layer4_review_items i
             left join pipeline.layer4_item_readiness k on k.item_id = i.id
             left join pipeline.aer_machine_admissions s on s.review_item_id = i.id and s.mode = 'shadow'
            where i.status = 'pending' and i.field_code = 'course_entry_first_read' and i.entity_type = 'course'
              and (s.id is null or s.updated_at < now() - make_interval(hours => 6) or coalesce(k.gate_checked_at, '-infinity') > s.updated_at) -- fixed: an unchanged item is looked at again after 6 hours
            order by coalesce((k.gate->>'complete')::boolean, false) desc, (s.id is null) desc, i.created_at
            limit v_batch loop
    exit when clock_timestamp() - v_t0 > make_interval(secs => 45); -- fixed: a run stays inside the job's time
    exit when v_mode >= 2 and v_used >= v_cap;
    begin
      v := security.aer_machine_admit_v1(r.id, 'run');
      v_n := v_n + 1;
      v_out := jsonb_set(v_out, array[coalesce(v->>'outcome', v->>'rule', 'unknown')], to_jsonb(coalesce((v_out->>coalesce(v->>'outcome', v->>'rule', 'unknown'))::int, 0) + 1));
      if v->>'outcome' = 'admitted' then v_used := v_used + 1; end if;
    exception when others then v_err := v_err + 1;
    end;
  end loop;
  return jsonb_build_object('mode', v_mode, 'effective', case when v_mode >= 2 and security.pipeline_num_v1('aer.machine_suspended', 0) < 1
                              and exists (select 1 from pipeline.aer_machine_validations x where x.passed and x.validated_at > now() - make_interval(days => 7)) then 'admit' else 'shadow' end,
                            'checked', v_n, 'outcomes', v_out, 'errors', v_err, 'admitted_24h', v_used, 'cap', v_cap, 'suspension', v_susp);
end $function$
