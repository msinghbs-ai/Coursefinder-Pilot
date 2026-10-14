CREATE OR REPLACE FUNCTION public.admin_provider_policy_decide(p_id uuid, p_action text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare x pipeline.provider_policy_proposals%rowtype; v jsonb := '{}'::jsonb; v_ag int := 0; v_df int := 0; v_sum jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if p_action not in ('approve', 'reject') then raise exception 'action must be approve or reject'; end if;
  select * into x from pipeline.provider_policy_proposals where id = p_id for update;
  if x.id is null then raise exception 'proposal not found'; end if;
  if x.status <> 'proposed' then raise exception 'already decided or not a proposal (%)', x.status; end if;
  if p_action = 'approve' and x.kind = 'english_policy' then
    v_sum := security.provider_policy_refresh_one_v1(p_id);
    v_ag := coalesce((v_sum->>'agrees')::int, 0); v_df := coalesce((v_sum->>'differs')::int, 0);
    if v_ag + v_df >= 10 and v_df > v_ag then
      raise exception 'This default does not match most course pages (% agree, % differ), so it cannot be approved', v_ag, v_df;
    end if;
  end if;
  update pipeline.provider_policy_proposals set status = case when p_action = 'approve' then 'approved' else 'rejected' end,
         decided_by = auth.uid(), decided_at = now(), decision_note = left(p_note, 500), updated_at = now() where id = p_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('policies', p_action, x.kind || ': ' || x.url, jsonb_build_object('decision', 'Decision 227', 'proposal_id', x.id, 'provider_id', x.provider_id), auth.uid());
  -- one approved document per university and kind: its other waiting documents are closed
  if p_action = 'approve' then
    update pipeline.provider_policy_proposals
       set status = 'superseded', decided_at = now(), updated_at = now(),
           decision_note = 'Closed: another document for this university was approved (' || x.url || ')'
     where provider_id = x.provider_id and kind = x.kind and status = 'proposed' and id <> x.id;
  end if;
  if p_action = 'approve' and x.kind = 'english_policy' then v := jsonb_build_object('to_fill', coalesce((v_sum->>'write')::int, 0)); end if;
  if p_action = 'approve' and x.kind = 'intake_calendar' then
    v := jsonb_build_object('to_answer', (select count(*) from security.semester_intake_plan_v1(x.provider_id) r where r.outcome = 'answer'));
  end if;
  return jsonb_build_object('status', case when p_action = 'approve' then 'approved' else 'rejected' end) || v;
end $function$
