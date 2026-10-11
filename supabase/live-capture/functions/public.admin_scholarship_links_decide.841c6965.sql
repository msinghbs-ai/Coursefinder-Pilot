CREATE OR REPLACE FUNCTION public.admin_scholarship_links_decide(p_scholarship_id uuid, p_decision text, p_filter jsonb DEFAULT '{}'::jsonb, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_res jsonb; v_before jsonb; v_f jsonb := coalesce(p_filter, '{}'::jsonb);
begin
  if auth.uid() is null or security.current_role_rank() < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
  if p_decision not in ('all','filter','none') then raise exception 'choose all courses, only matching courses, or no courses'; end if;
  if p_decision = 'filter' and jsonb_array_length(coalesce(v_f->'levels', '[]'::jsonb)) = 0 and jsonb_array_length(coalesce(v_f->'fields', '[]'::jsonb)) = 0
     and nullif(btrim(coalesce(v_f->>'title', '')), '') is null and jsonb_array_length(coalesce(v_f->'courses', '[]'::jsonb)) = 0 then
    raise exception 'choose at least one study level, field, title word or course';
  end if;
  if not exists (select 1 from scholarship.course_mapping_candidates where scholarship_id = p_scholarship_id) then raise exception 'this scholarship has no proposed course links'; end if;
  select to_jsonb(d) into v_before from pipeline.scholarship_scope_decisions d where scholarship_id = p_scholarship_id;
  insert into pipeline.scholarship_scope_decisions(scholarship_id, decision, filter, reason, decided_by, decided_at)
  values (p_scholarship_id, p_decision, case when p_decision = 'filter' then v_f else '{}'::jsonb end, nullif(btrim(coalesce(p_reason, '')), ''), auth.uid(), now())
  on conflict (scholarship_id) do update set decision = excluded.decision, filter = excluded.filter, reason = excluded.reason,
         decided_by = excluded.decided_by, decided_at = now();
  v_res := security.scholarship_scope_apply_v1(p_scholarship_id, auth.uid());
  insert into pipeline.layer4_mass_operations(target_kind, action, actor_id, group_key, reason, before_count, affected_count, result, change_control_ref)
  values ('scholarship_course_scope', 'scope_decision_' || p_decision, auth.uid(), jsonb_build_object('scholarship_id', p_scholarship_id, 'filter', v_f, 'previous', v_before),
          coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Scholarship course links decided on the Course links screen'),
          coalesce((v_res->>'accepted')::int, 0) + coalesce((v_res->>'rejected')::int, 0), coalesce((v_res->>'accepted')::int, 0), v_res, 'CF-CHG-20260915-247');
  return public.admin_scholarship_links_detail(p_scholarship_id) || jsonb_build_object('result', v_res);
end $function$
