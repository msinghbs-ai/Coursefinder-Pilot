CREATE OR REPLACE FUNCTION security.adapter_overwrite_gated_v1(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m pipeline.job_input_marks%rowtype; v_in timestamptz := security.admit_input_mark_v1(); v jsonb; v_more boolean;
        v_full int := security.pipeline_num_v1('waste.admit_full_check_hours', 6)::int;
begin
  insert into pipeline.job_input_marks(job_key) values ('adapter-overwrite') on conflict do nothing;
  select * into m from pipeline.job_input_marks where job_key = 'adapter-overwrite' for update;
  if not coalesce((m.last_result->>'more')::boolean, true) and m.last_input_at is not null and v_in <= m.last_input_at
     and m.last_full_at > now() - make_interval(hours => v_full) then
    update pipeline.job_input_marks set runs_skipped = runs_skipped + 1, last_run_at = now() where job_key = 'adapter-overwrite';
    return jsonb_build_object('skipped', 'no new input');
  end if;
  perform security.fee_crosscheck_guard_v1();  -- CF-247 15 Oct: a fee far from the registered course total is held back first
  v := security.adapter_overwrite_v1(p_limit);
  v_more := coalesce((v->>'replaced')::int, 0) >= p_limit;
  update pipeline.job_input_marks set last_input_at = v_in, last_full_at = now(), last_run_at = now(), last_result = v || jsonb_build_object('more', v_more),
         runs_done = runs_done + 1 where job_key = 'adapter-overwrite';
  return v;
end $function$
