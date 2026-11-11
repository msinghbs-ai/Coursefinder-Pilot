-- HELD (not a migration): forward recovery for 20261112080000 (job course-description-machine bounded by its statement, CF-247 F-CDESC F1). It restores security.course_description_machine_settle_v1() and
-- security.course_description_machine_consumer_recheck_v1() byte for byte to the bodies read live on 11 Nov 2026 19:15 AEDT. Run only if the Platform Admin decides to take the change back; while it is in force a run with a backlog can
-- again pass its 120 s limit and lose every decision of the run. Guarded by the md5 of what is live now; a body that is neither stops it. Nothing is dropped or deleted.

do $g$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_settle_v1()'::regprocedure);
begin
  if md5(v_src) = '4c40d655a7ff674ce184b598056d835f' then raise notice 'security.course_description_machine_settle_v1(): already the original'; return; end if;
  if md5(v_src) <> '5fa17251727adbb49cb718be889fce54' then raise exception 'live security.course_description_machine_settle_v1() differs from both texts this recovery knows (body md5 %)', md5(v_src); end if;
  execute $ddl$
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
$ddl$;
end $g$;

do $g$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_consumer_recheck_v1()'::regprocedure);
begin
  if md5(v_src) = 'a6138e39a1ba4a3d1b04cc01994d2848' then raise notice 'security.course_description_machine_consumer_recheck_v1(): already the original'; return; end if;
  if md5(v_src) <> 'f4b6bc3e45866782c5f694046d07131f' then raise exception 'live security.course_description_machine_consumer_recheck_v1() differs from both texts this recovery knows (body md5 %)', md5(v_src); end if;
  execute $ddl$
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
$ddl$;
end $g$;
