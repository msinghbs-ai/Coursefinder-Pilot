CREATE OR REPLACE FUNCTION security.layer4_decide_guard_v1(p_kind text, p_ref text, p_choice text, p_pid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- null when the decision may go ahead; otherwise the reply: {repeat, existing} for the same decision on the same item inside
-- layer4.duplicate_decision_seconds (unless the first was not applied), or {refused, repeat_of, alternative} for a choice in
-- layer4.once_only_choices already taken on the same university's same stop with nothing about the university changed since
declare e record; v_upd timestamptz;
begin
  select x.id, x.created_at into e from pipeline.admin_control_events x
   where x.area = 'layer4' and x.action = 'inbox_decide' and x.target = p_kind || ':' || p_ref and x.detail->>'choice' = p_choice
     and x.created_at > now() - make_interval(secs => security.pipeline_num_v1('layer4.duplicate_decision_seconds', 120)::int)
     and coalesce(x.detail->'result'->>'still_waiting', 'false') <> 'true'
   order by x.id desc limit 1;
  if e.id is not null then
    return jsonb_build_object('repeat', true, 'existing', jsonb_build_object('event', e.id, 'at', e.created_at),
      'request', 'Already sent: the same decision was recorded at ' || (security.l4_time_v1(e.created_at)->>'text') || ' (audit #' || e.id || '); it was not taken again.');
  end if;
  if p_choice = any (security.pipeline_list_v1('layer4.once_only_choices', '["retry", "rebuild", "release"]'::jsonb)) and p_pid is not null then
    select x.id, x.created_at into e from pipeline.admin_control_events x
     where x.area = 'layer4' and x.action = 'inbox_decide' and x.detail->>'kind' = p_kind and x.detail->>'choice' = p_choice and x.detail->>'provider_id' = p_pid::text
     order by x.id desc limit 1;
    select p.updated_at into v_upd from catalogue.providers p where p.id = p_pid;
    if e.id is not null and (v_upd is null or v_upd <= e.created_at) then
      return jsonb_build_object('refused', 'already tried on this stop', 'repeat_of', e.id,
        'request', 'Not tried again: ' || replace(p_choice, '_', ' ') || ' was already taken for this university at ' || (security.l4_time_v1(e.created_at)->>'text') || ' (audit #' || e.id
                   || ') and it stopped the same way; nothing about the university has changed since. It is tried at most once.',
        'alternative', case p_kind when 'nothing_ready' then 'Open the adapter in the builder to correct its patterns and qualify again, or CRICOS data only'
                                   when 'onboarding_failed' then 'Build by hand in the adapter builder'
                                   when 'pages_not_found' then 'Add page addresses in the builder, or change the website'
                                   else 'Choose another action, or leave the item with its reason' end);
    end if;
  end if;
  return null;
end $function$
