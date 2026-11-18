CREATE OR REPLACE FUNCTION security.course_description_machine_withdraw_v1(p_course uuid, p_reason text, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a pipeline.course_description_machine_admissions%rowtype; v_now text; v_after text; v_dec uuid;
begin
  if p_actor is null or p_actor = 'c0ffee00-0000-4000-8000-000000000150'::uuid then raise exception 'the person who withdraws must be named'; end if; -- fixed: the system automation account (Decision 263) is not a person
  if nullif(btrim(p_reason), '') is null then raise exception 'give a reason (kept in the log)'; end if;
  select * into a from pipeline.course_description_machine_admissions where course_id = p_course and outcome = 'admitted' and withdrawn_at is null for update;
  if a.id is null then return jsonb_build_object('ok', false, 'rule', 'no_live_machine_admission'); end if;
  select nullif(btrim(c.description), '') into v_now from catalogue.courses c where c.id = p_course for update;
  if v_now is distinct from a.after_description then return jsonb_build_object('ok', false, 'rule', 'description_changed_since_admission', 'reason', 'A person changed the description since the machine admitted it; it is kept.'); end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = p_course and l.field in ('description', 'course_description', 'all')) then
    return jsonb_build_object('ok', false, 'rule', 'manual_lock', 'reason', 'The description has been locked by hand since the machine admitted it; it is kept. Release the lock first.'); end if;
  v_dec := nullif(a.checks->>'decision_id', '')::uuid;
  if v_dec is null then raise exception 'the admission has no decision to point the search refresh at'; end if;
  update catalogue.courses set description = a.before_description, updated_at = now() where id = p_course;
  select nullif(btrim(c.description), '') into v_after from catalogue.courses c where c.id = p_course;
  if v_after is distinct from nullif(btrim(a.before_description), '') then raise exception 'withdraw_not_applied: the catalogue kept the description; nothing was changed'; end if;
  update pipeline.course_description_machine_admissions set withdrawn_at = now(), withdrawn_by = p_actor, withdrawn_reason = btrim(p_reason) where id = a.id;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('layer4', 'cdesc_machine_withdraw', p_course::text, jsonb_build_object('admission_id', a.id, 'review_item_id', a.review_item_id, 'rule', a.rule, 'before', a.before_description, 'after', a.after_description, 'reason', btrim(p_reason), 'withdrawn_by', p_actor), p_actor);
  -- production keeps ONE search refresh signal for each decision (UNIQUE review_decision_id): the signal the admission queued is queued again for the same decision
  insert into pipeline.search_refresh_signals as s (entity_type, entity_id, review_decision_id, reason, change_control_ref)
  values ('course', p_course, v_dec, 'Machine course description withdrawn: ' || btrim(p_reason), 'CF-247 F-CDESC withdrawal')
  on conflict (review_decision_id) do update set status = case when s.status = 'processing' then s.status else 'queued' end, completed_at = null, reason = excluded.reason, change_control_ref = excluded.change_control_ref;
  return jsonb_build_object('ok', true, 'course_id', p_course, 'admission_id', a.id, 'restored', a.before_description, 'withdrawn_by', p_actor);
end $function$
