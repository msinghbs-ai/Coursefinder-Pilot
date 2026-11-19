CREATE OR REPLACE FUNCTION security.layer4_action_ack_v1(p_kind text, p_ref text, p_reply jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- the reply of an Inbox decision with its normalised acknowledgement: {outcome, ref, at, reason, alternative, next, stage}. Built only after
-- the server has done the work and written its audit row (never before), from the same records the card reads after Refresh.
declare v_n jsonb; v_at timestamptz; v_lc jsonb; v_d jsonb := coalesce(p_reply->'result'->'detail', p_reply->'result', '{}'::jsonb); v_hm text; v_head text;
begin
  v_n := security.layer4_ack_normalise_v1(p_kind, p_reply->>'choice', (p_reply->>'ok')::boolean, p_reply->'result', p_reply->>'request', p_reply->'outcome');
  select x.created_at into v_at from pipeline.admin_control_events x where x.id = nullif(p_reply->>'event_id', '')::bigint;
  v_lc := security.layer4_lifecycle_one_v1(p_kind, p_ref, false);
  v_hm := security.l4_time_v1(coalesce(v_at, now()))->>'hm';
  v_head := security.layer4_ack_headline_v1(p_reply->>'choice', v_n, v_d, coalesce(v_at, now()));
  return p_reply || jsonb_build_object('ack', v_n || jsonb_build_object('headline', v_head, 'ref', case when p_reply ? 'event_id' then 'audit #' || (p_reply->>'event_id') end,
    'at', security.l4_time_v1(coalesce(v_at, now())), 'returns', p_reply->>'returns',
    'next', coalesce(v_lc->'next'->>'text', case when v_lc->>'open' = 'false' then 'nothing: the item is ' || lower(v_lc->>'stage_label') end),
    'stage', v_lc->>'stage', 'stage_label', v_lc->>'stage_label'));
end $function$
