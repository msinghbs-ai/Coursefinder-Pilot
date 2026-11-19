CREATE OR REPLACE FUNCTION security.scholarship_eligibility_fire_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- F-SCH.01, job scholarship-eligibility (every 10 minutes): queue, act on finished reads (shadow or live), and call the worker while reads are due
-- and the AI guards allow it. Nothing runs while sch_elig.on is 0.
declare v_q int; v_a jsonb; v_f boolean := false; v_due int;
begin
  if security.pipeline_num_v1('sch_elig.on', 0) < 1 then return jsonb_build_object('on', false); end if;
  v_q := security.scholarship_eligibility_enqueue_v1(null);
  v_a := security.scholarship_eligibility_apply_v1(null);
  select count(*) into v_due from pipeline.scholarship_eligibility_reads e
   where (e.state = 'queued' and coalesce(e.next_try_at, '-infinity') <= now()) or (e.state = 'leased' and e.leased_until < now());
  if v_due > 0 and security.ai_use_allowed_v1('scholarship_ai') then
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'scholarship_eligibility', 'limit', security.pipeline_num_v1('batch.sch_eligibility_read', 20)::int));
    v_f := true;
  end if;
  return jsonb_build_object('on', true, 'queued', v_q, 'applied', v_a, 'due', v_due, 'fired', v_f);
end $function$
