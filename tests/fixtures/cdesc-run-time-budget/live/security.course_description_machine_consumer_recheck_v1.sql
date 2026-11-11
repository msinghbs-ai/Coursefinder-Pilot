-- The LIVE definition of security.course_description_machine_consumer_recheck_v1() as pg_get_functiondef returned it on project fxcwkweaxjtknorudmwp, 11 Nov 2026 19:15 AEDT (body md5 a6138e39a1ba4a3d1b04cc01994d2848). Loaded by run.sh, md5 checked.
CREATE OR REPLACE FUNCTION security.course_description_machine_consumer_recheck_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_pub jsonb; v_shown text; v_cc text; v_n int := 0; v_ok int := 0; v_t0 timestamptz := clock_timestamp();
        v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int; -- derived
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  for r in select a.id, a.after_description, c.stable_key from pipeline.course_description_machine_admissions a join catalogue.courses c on c.id = a.course_id
            where a.outcome = 'admitted' and a.withdrawn_at is null and a.consumer_check is distinct from 'matched'
              and (a.consumer_checked_at is null or a.consumer_checked_at < now() - case when a.consumer_check = 'not_in_feed' then make_interval(days => v_days) else make_interval(hours => 1) end) -- fixed: a lag is read again after an hour
            order by a.consumer_checked_at nulls first limit v_cap loop
    exit when clock_timestamp() - v_t0 > make_interval(secs => 15); -- fixed: a follow-up, not the main work of the run
    begin v_pub := public.website_v2_course(r.stable_key); exception when others then v_pub := null; end;
    v_shown := v_pub->'item'->>'description';
    v_cc := case when v_pub is null then 'error' when v_pub ? 'error' then 'not_in_feed' when v_shown = r.after_description then 'matched' when nullif(btrim(v_shown), '') is null then 'lag' else 'mismatch' end;
    update pipeline.course_description_machine_admissions set consumer_check = v_cc, consumer_checked_at = now() where id = r.id;
    v_n := v_n + 1; if v_cc = 'matched' then v_ok := v_ok + 1; end if;
  end loop;
  return jsonb_build_object('on', true, 'rechecked', v_n, 'matched', v_ok);
end $function$
;
