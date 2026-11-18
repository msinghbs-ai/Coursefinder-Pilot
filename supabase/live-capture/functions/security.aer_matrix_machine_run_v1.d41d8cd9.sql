CREATE OR REPLACE FUNCTION security.aer_matrix_machine_run_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_mode int; v_batch int; v_cap int; v_used int; v_t0 timestamptz := clock_timestamp(); r record; v jsonb; v_n int := 0;
        v_out jsonb := '{}'::jsonb; v_err int := 0;
begin
  -- settings are read inside the block, so an unreadable value is returned as an error like any other, never raised into the calling course run
  v_mode := security.aer_matrix_machine_effective_v1();
  v_batch := security.pipeline_num_v1('batch.aer_matrix_machine', 20)::int;
  v_cap := security.pipeline_num_v1('aer.matrix_machine_daily_max', 40)::int;
  if v_mode < 1 then return jsonb_build_object('mode', 0); end if;
  select count(*) into v_used from pipeline.aer_matrix_machine_admissions where mode = 'admit' and outcome = 'admitted' and created_at > now() - interval '24 hours';  -- fixed: the cap counts the last 24 hours
  for r in select i.id from pipeline.layer4_review_items i
             left join pipeline.aer_matrix_machine_admissions s on s.review_item_id = i.id and s.mode = 'shadow'
            where i.status = 'pending' and i.field_code in ('entry_matrix_first_run', 'entry_matrix_change')
              and (v_mode >= 2 or s.id is null or s.updated_at < now() - interval '6 hours')  -- fixed: an unchanged item is looked at again after 6 hours in shadow
              and not (v_mode >= 2 and exists (select 1 from pipeline.aer_matrix_machine_admissions a where a.review_item_id = i.id and a.mode = 'admit' and a.created_at > now() - interval '6 hours'))
            order by (s.id is null) desc, i.created_at
            limit v_batch loop
    exit when clock_timestamp() - v_t0 > interval '40 seconds';  -- fixed: a run stays inside the job's time
    exit when v_mode >= 2 and v_used >= v_cap;
    begin
      v := security.aer_matrix_machine_admit_v1(r.id, 'run');
      v_n := v_n + 1;
      v_out := jsonb_set(v_out, array[coalesce(v->>'outcome', v->>'rule', 'unknown')], to_jsonb(coalesce((v_out->>coalesce(v->>'outcome', v->>'rule', 'unknown'))::int, 0) + 1));
      if v->>'outcome' = 'admitted' then v_used := v_used + 1; end if;
    exception when others then v_err := v_err + 1;
    end;
  end loop;
  return jsonb_build_object('mode', v_mode, 'checked', v_n, 'outcomes', v_out, 'errors', v_err, 'admitted_24h', v_used, 'cap', v_cap);
exception when others then
  return jsonb_build_object('error', left(sqlerrm, 300));  -- isolated: the matrix class never breaks the course run that calls it
end $function$
