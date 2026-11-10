CREATE OR REPLACE FUNCTION security.layer4_aer_review_detail_v1(p_ref text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- the AER card detail (extend hook; paging contract shape {sections, actions}): the review packet first, then Human-assisted recovery's own
-- detail and actions unchanged (called by name; a failure there leaves the packet). Decisions stay the Inbox's (one item, one audit event).
declare p jsonb; h jsonb; v_sec jsonb;
begin
  p := security.aer_review_packet_v1(p_ref::uuid);
  if p is null then return jsonb_build_object('sections', '[]'::jsonb, 'actions', '[]'::jsonb); end if;
  begin
    h := security.layer4_aer_recovery_detail_v1(p_ref);
  exception when others then
    h := jsonb_build_object('sections', jsonb_build_array(jsonb_build_object('key', 'recovery', 'title', 'Recovery', 'body', jsonb_build_object('Not available', left(sqlerrm, 200)))),
                            'actions', '[]'::jsonb);
  end;
  v_sec := jsonb_build_array(
    -- direction 12:16 §7: a readable summary first: what this item is, why, and the next action
    jsonb_build_object('key', 'summary', 'title', 'Summary', 'body', jsonb_strip_nulls(jsonb_build_object(
      'Class', case p->'settlement'->>'settlement' when 'ready' then 'Ready for a decision' when 'recoverable' then 'Technically held: an automatic recovery remains'
                                                 when 'needs_input' then 'Needs evidence, input or a decision' when 'stale' then 'Stale: no longer a valid read' end,
      'Failure', case when p->'settlement'->>'settlement' <> 'ready' then p->'settlement'->>'why' end,
      'Next action', p->'settlement'->>'next_action',
      'Corrected reads so far', nullif((p->'settlement'->>'tries')::int, 0)))),
    jsonb_build_object('key', 'review', 'title', 'Review', 'body', jsonb_strip_nulls(jsonb_build_object(
      'University', p->>'provider', 'Course', p->'course'->>'title', 'Course code', p->'course'->>'code', 'Qualification', p->'course'->>'qualification',
      'Country', p->'course'->>'country', 'Source', p->'source'->>'url', 'Audience', p->'audiences', 'Stored copy', p->'evidence',
      'Recommended decision', p->>'recommended', 'If approved', p->'consequences'->>'approve', 'If rejected', p->'consequences'->>'reject',
      'Owner', case when jsonb_array_length(p->'owner') = 0 then 'no one has claimed this university and kind' else (p->'owner')::text end,
      'Queue', case when (p->'queue'->>'position') is not null then (p->'queue'->>'position') || ' of ' || (p->'queue'->>'ready_at_university') || ' ready at this university'
                    else 'not reviewer-ready: ' || (p->'route'->>'route') || ' (' || (p->'queue'->>'ready_at_university') || ' ready at this university)' end,
      'Next ready item', p->'queue'->>'next_ready'))),
    jsonb_build_object('key', 'checks', 'title', 'Completeness and conflicts', 'body', jsonb_strip_nulls(jsonb_build_object(
      'Gate', case when (p->'gate'->>'complete')::boolean then 'complete' else 'held' end, 'Checked', p->'gate'->>'source', 'Reasons', p->'gate'->'reasons',
      'Conflicts', nullif(p->'conflicts', '{}'::jsonb), 'Rows to leave out', nullif(p->'exclude_row_ids', '[]'::jsonb),
      'Route', p->'route'->>'route', 'Remedy', p->'route'->>'remedy'))),
    jsonb_build_object('key', 'rows', 'title', 'Proposed rows (' || (p->'proposed'->>'count') || ')', 'body', p->'proposed'->'rows'),
    jsonb_build_object('key', 'active', 'title', 'Active rows (' || (p->'active'->>'count') || ')', 'body', p->'active'->'rows'));
  if jsonb_array_length(p->'locks') > 0 then v_sec := v_sec || jsonb_build_array(jsonb_build_object('key', 'locks', 'title', 'Manual locks', 'body', p->'locks')); end if;
  return jsonb_build_object('sections', v_sec || coalesce(h->'sections', '[]'::jsonb), 'actions', coalesce(h->'actions', '[]'::jsonb), 'packet', p);
end $function$

