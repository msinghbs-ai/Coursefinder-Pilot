-- CF-247 hotfix: Layer 4 AER recovery panel time-out (Platform Admin report 4 Nov 2026 11:13, UNSW Bachelor of Actuarial Studies card).
-- Cause (production, read-only 11:15): security.layer4_aer_recovery_detail_v1 listed "other held reads in this case" by calling
-- security.layer4_aer_recovery_state_v1 (the full completeness gate, 0.83 s) for every pending item of the same field; the card's detail hit the
-- statement time-out, so the recovery choices (re-read from stored evidence, request evidence, open human input) never loaded and only
-- Reject the read was usable. Fix: the list counts and names the other waiting reads of the same university and kind without running the gate.
-- The case key, deduplication, the decide function, the E13 and D-R3 gates and the 600 limit are unchanged. No time-out is raised.
-- Live before -> after: security.layer4_aer_recovery_detail_v1(text) a83f37a2a63c11cab82d66a124256c6e (guarded) -> 636c1764788b008fb7456365d600b452 (PG16 fixture).
-- Replaces: security.layer4_aer_recovery_detail_v1(text) (same name; the case list only)
-- Retires: nothing

do $$
begin
  if md5(pg_get_functiondef('security.layer4_aer_recovery_detail_v1(text)'::regprocedure)) not in ('a83f37a2a63c11cab82d66a124256c6e') then
    -- fixed: guard against editing a definition other than the one this hotfix was written against
    if position('Other waiting reads of this university and kind' in pg_get_functiondef('security.layer4_aer_recovery_detail_v1(text)'::regprocedure)) = 0 then
      raise exception 'live security.layer4_aer_recovery_detail_v1 differs from the definition this hotfix edits (md5 %)',
        md5(pg_get_functiondef('security.layer4_aer_recovery_detail_v1(text)'::regprocedure));
    end if;
  end if;
end $$;

create or replace function security.layer4_aer_recovery_detail_v1(p_ref text) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- the recovery state on an E13 or D-R3 card (decision 06:58 §3; paging contract §2a, shape {sections, actions}): the gate's counts and reasons,
-- the recommended recovery, whether a person is needed, the owner, the next automatic attempt, the last attempt and its status, and the case
-- the read belongs to (other held reads of the same university failing the same way). The E13 facts themselves stay on the built-in card.
declare st jsonb := security.layer4_aer_recovery_state_v1(p_ref::uuid); v_last record; v_iv pipeline.layer4_interventions; v_rec text; v_case jsonb; v_ai boolean;
        v_busy text;
begin
  if st is null then return jsonb_build_object('sections', '[]'::jsonb, 'actions', '[]'::jsonb); end if;
  select * into v_last from pipeline.layer4_aer_recovery_actions a where a.review_item_id = p_ref::uuid order by a.id desc limit 1;
  select * into v_iv from pipeline.layer4_interventions i where i.lane = 'aer_item' and i.status in ('ai_pending', 'awaiting_input', 'resuming')
     and (i.entity = p_ref or i.entity = (st->>'provider_id') || '|case:' || (st->>'case_key')) order by i.id desc limit 1;
  v_ai := security.pipeline_num_v1('har.ai_escalate_on', 0) >= 1 and security.pipeline_num_v1('ops.ai_diagnosis_on', 0) >= 1 and security.har_text_v1('har.ai_escalation_model', '') <> '';
  v_busy := case when st->'corrected_read'->>'state' = 'requested' then 'a corrected read of this item is already asked for'
                 when exists (select 1 from pipeline.field_enrich_items f where f.course_id = (st->>'course_id')::uuid and f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased'))
                   then 'a read of this course is in progress' end;
  v_rec := case when (st->>'complete')::boolean then 'none: the read is complete'
                when v_iv.id is not null then 'answer the open Human input needed item (ref ' || v_iv.id || ')'
                when v_busy is not null then 'wait: ' || v_busy
                when coalesce((st->>'stored_copy')::boolean, false) and coalesce(st->'corrected_read'->>'state', '') <> 'superseded'
                     and not exists (select 1 from pipeline.layer4_aer_recovery_actions a where a.review_item_id = p_ref::uuid and a.choice = 'reread_stored') then 'reread_stored'
                when not coalesce((st->>'stored_copy')::boolean, false) then 'request_evidence'
                else 'open_intervention' end;
  -- CF-247 hotfix (Platform Admin report 4 Nov 11:13): the case list no longer runs the completeness gate for every waiting read of the
  -- university (0.8 s each; RMIT has 303, so the card's detail timed out and its recovery choices never loaded). The card names the other
  -- waiting reads of the same university and kind, cheaply; the case itself is still formed by its key when Request official evidence is chosen.
  select jsonb_build_object('count', count(*), 'first', coalesce(jsonb_agg(jsonb_build_object('ref', z.id, 'subject', z.subject) order by z.created_at)
           filter (where z.rn <= security.pipeline_num_v1('har.aer_case_items_max', 20)), '[]'::jsonb)) into v_case
    from (select li.id, li.created_at, coalesce(c.display_title, c.canonical_title) subject, row_number() over (order by li.created_at) rn
            from pipeline.layer4_review_items li join catalogue.courses c on c.id = li.entity_id
           where li.status = 'pending' and li.field_code = st->>'field_code' and li.id <> p_ref::uuid
             and (st->>'course_id') is not null and c.provider_id = (st->>'provider_id')::uuid) z;
  return jsonb_build_object('sections', jsonb_build_array(
      jsonb_build_object('key', 'recovery', 'title', 'Recovery', 'body', jsonb_strip_nulls(jsonb_build_object(
        'Waiting rows', jsonb_array_length(st->'waiting_rows'), 'Dropped requirements', jsonb_array_length(st->'dropped'),
        'Dropped without a row (quotations)', jsonb_array_length(st->'missing_quotes'), 'Why the read is held', st->'reasons',
        'Recommended recovery', v_rec, 'Human input needed', case when v_rec in ('open_intervention', 'request_evidence') or v_iv.id is not null then 'yes' else 'not yet' end,
        'Owner', case when v_iv.id is not null then v_iv.assigned_to when v_rec = 'reread_stored' then 'the entry reader (automatic)' else 'Layer 4 reviewer' end,
        'Next automatic attempt', case when v_busy is not null then 'the requested read' when v_iv.id is not null then coalesce(v_iv.next_action_at::text, 'when the input is given') else 'none until a recovery is chosen' end,
        'Last attempt', case when v_last.id is not null then v_last.choice || ' at ' || v_last.at || ': ' || coalesce(v_last.next_operation, '') end,
        'Last attempt status', coalesce(st->'corrected_read'->>'state', v_last.work_item_status)))),
      jsonb_build_object('key', 'case', 'title', 'Recovery case', 'body', jsonb_build_object('Case', st->>'case_label', 'Other waiting reads of this university and kind', v_case))),
    'actions', jsonb_build_array(
      jsonb_build_object('key', 'reread_stored', 'allowed', v_busy is null and not (st->>'complete')::boolean, 'why', v_busy),
      jsonb_build_object('key', 'request_evidence', 'allowed', v_iv.id is null, 'why', case when v_iv.id is not null then 'a Human input needed item is already open (ref ' || v_iv.id || ')' end),
      jsonb_build_object('key', 'ai_analyse', 'allowed', v_ai and v_iv.id is null,
                         'why', case when not v_ai then 'the stronger-model step is off (har.ai_escalate_on, ops.ai_diagnosis_on or no pinned model)'
                                     when v_iv.id is not null then 'a Human input needed item is already open (ref ' || v_iv.id || ')' end),
      jsonb_build_object('key', 'open_intervention', 'allowed', v_iv.id is null, 'why', case when v_iv.id is not null then 'a Human input needed item is already open (ref ' || v_iv.id || ')' end)));
end $function$;
revoke all on function security.layer4_aer_recovery_detail_v1(text) from public, anon, authenticated;
