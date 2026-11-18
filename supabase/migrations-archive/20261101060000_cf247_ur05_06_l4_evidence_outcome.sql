-- CF-247 StudySearch usability remediation UR-05 and UR-06 (Platform Admin mandate 1 Nov 2026 11:48, Tranche B; review
-- admin docs/platform/nz-enrichment-brief/2026-11-01-role-guides-usability-operability-review.md; record §36).
-- Why: review cards for course links and AER carried no stored copy, capture date or record link (80 of 118 course-link cards had no evidence
--   link), and "Done" showed only the choice's generic text, so a card leaving the list was taken as proof. Measured on the decision history:
--   2 of 32 course-link "Use the new page" decisions (30 Oct, Waikato /int/ pages) are saved but the page is not the course's active link.
-- What:
--   * security.layer4_inbox_items_v1 (md5-guarded): review items carry evidence_id, captured_at, source_url and newer_copy (a newer stored
--     copy of the same page exists); 1,112 of 1,172 review items have a stored copy; the list read takes about 0.5 s longer (736 -> 1,219 ms).
--   * security.layer4_decision_outcome_v1(kind, choice, result): reads the destination back after a decision and classifies it: admitted,
--     applied, reconciled (closed without admitting a value), downstream, deferred or pending_check (saved, destination does not show it).
--     AER: row counts (active, excluded, superseded, waiting) from public.layer4_aer_review_read. Course link: whether the page is now the
--     course's active official link.
--   * public.admin_layer4_inbox decide (md5-guarded): returns ref, event_id (pipeline.admin_control_events) and outcome.
-- No decision rule, admission or consumer change.
-- Rollback: re-apply md5 3f2b49d5 and the v2.15.391 inbox (48a52717); the new function can stay (paste file to drop).
-- Replaces: security.layer4_inbox_items_v1, public.admin_layer4_inbox (same names; md5-guarded edits)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API untouched (G3).

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 1. the cards' stored copy
select pg_temp.edit_once('security.layer4_inbox_items_v1()', '3f2b49d511ff60b7b00b69c702c7b615', 'c1a133c3260c3c160397151bd0664957', array[
 array[$o$jsonb_build_object('field_code', r.field_code, 'course_id', c.id, 'course_code', c.course_code, 'before', r.before_value, 'proposed', r.proposed_value)$o$,
       $n$jsonb_build_object('field_code', r.field_code, 'course_id', c.id, 'course_code', c.course_code, 'before', r.before_value, 'proposed', r.proposed_value,
                            -- UR-05 (1 Nov 2026): the stored copy behind the item, when it was captured, and whether a newer copy of the same page exists
                            'evidence_id', r.evidence_id, 'captured_at', ev.captured_at, 'source_url', ev.source_url,
                            'newer_copy', ev.id is not null and exists (select 1 from pipeline.evidence_artifacts n where lower(n.source_url) = lower(ev.source_url) and n.captured_at > ev.captured_at))$n$],
 array[$o$    left join scholarship.scholarships s on r.entity_type = 'scholarship' and s.id = r.entity_id
   where r.status = 'pending'$o$,
       $n$    left join scholarship.scholarships s on r.entity_type = 'scholarship' and s.id = r.entity_id
    left join pipeline.evidence_artifacts ev on ev.id = r.evidence_id
   where r.status = 'pending'$n$]],
 array[1, 1]);

-- 2. what a decision actually did
create or replace function security.layer4_decision_outcome_v1(p_kind text, p_choice text, p_result jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- UR-06 (1 Nov 2026): what a Layer 4 decision actually did, read back from its destination after the decision. Classes: admitted (values
-- now active), applied (the correction is in place), reconciled (closed without admitting a value), downstream (queued: the result follows
-- later), deferred (asked again later), pending_check (saved, but the destination does not show it yet). A card leaving the list is not proof.
declare v_status text := p_result->>'status'; v_rows jsonb; v_aer jsonb; v_entity uuid; v_url text; v_ok boolean;
begin
  if p_kind = 'aer_review' and p_result ? 'review_item_id' then
    v_aer := public.layer4_aer_review_read((p_result->>'review_item_id')::uuid);
    select jsonb_object_agg(s, n) into v_rows
      from (select case when x->>'status' = 'inactive' and coalesce(x->>'status_reason', '') like 'excluded by %' then 'excluded' else x->>'status' end s, count(*) n
              from jsonb_array_elements(coalesce(v_aer->'rows', '[]'::jsonb)) x group by 1) q;
    v_rows := coalesce(v_rows, '{}'::jsonb);
    return jsonb_build_object('class', case when v_status = 'rejected' then 'reconciled' when coalesce((v_rows->>'active')::int, 0) > 0 then 'admitted'
                                            when coalesce((v_rows->>'proposed')::int, 0) > 0 then 'downstream' else 'pending_check' end,
                              'status', v_status, 'decision_id', p_result->>'decision_id', 'rows', v_rows, 'destination', 'entry_requirements');
  elsif p_result ? 'decision_id' then
    if v_status = 'rejected' then
      return jsonb_build_object('class', 'reconciled', 'status', v_status, 'decision_id', p_result->>'decision_id');
    elsif p_kind = 'course_link' then
      v_url := case jsonb_typeof(p_result->'final_value') when 'string' then p_result->>'final_value' else p_result->'final_value'->>'course_url' end;
      select r.entity_id into v_entity from pipeline.layer4_review_items r where r.id = (p_result->>'review_item_id')::uuid and r.entity_type = 'course';
      v_ok := v_url is not null and exists (select 1 from catalogue.course_links l where l.course_id = v_entity and l.link_type = 'official_course' and l.status = 'active'
                                                  and lower(rtrim(l.url, '/')) = lower(rtrim(v_url, '/')));
      return jsonb_build_object('class', case when v_ok then 'applied' else 'pending_check' end, 'verified', v_ok, 'status', v_status,
                                'decision_id', p_result->>'decision_id', 'value', v_url, 'course_id', v_entity, 'destination', 'course');
    end if;
    return jsonb_build_object('class', 'applied', 'status', v_status, 'decision_id', p_result->>'decision_id');
  elsif p_kind = 'course_link' then  -- a held fee: the page entered is read again; the fee is re-admitted only after that read
    return jsonb_build_object('class', 'downstream', 'note', 'the page is read again; its fee is admitted only after that read');
  elsif p_choice = 'wait' then
    return jsonb_build_object('class', 'deferred');
  elsif p_choice in ('rebuild', 'retry', 'cricos_only', 'website') then
    return jsonb_build_object('class', 'downstream');
  elsif p_choice in ('archive', 'archive_course') then
    return jsonb_build_object('class', 'applied');
  elsif p_kind = 'held_scholarship' then
    return jsonb_build_object('class', case when p_choice = 'publish' then 'admitted' else 'reconciled' end);
  elsif p_choice in ('release', 'keep') then
    return jsonb_build_object('class', 'reconciled', 'note', p_result->>'requeued');
  end if;
  return jsonb_build_object('class', 'reconciled');
end $function$;
revoke all on function security.layer4_decision_outcome_v1(text, text, jsonb) from public, anon, authenticated;
comment on function security.layer4_decision_outcome_v1(text, text, jsonb) is 'UR-06 (1 Nov 2026): what a Layer 4 decision actually did, read back from its destination: admitted, applied, reconciled, downstream, deferred or pending_check; AER row counts; course link verified active.';
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.layer4_decision_outcome_v1', 'Layer 4', 'Layer 4 review', 'UR-06: the verified outcome of a Layer 4 decision', 'active', '{}', '20261101060000')
on conflict do nothing;

-- 3. the decision reply carries the audit event and the outcome
select pg_temp.edit_once('public.admin_layer4_inbox(text,jsonb)', '48a52717d398c14de6920f18667068a0', 'c6b83e211ba5172d16a5b3b7e7399ef5', array[
 array[$o$v_out jsonb; v_ids uuid[];
begin$o$,
       $n$v_out jsonb; v_ids uuid[]; v_event bigint;
begin$n$],
 array[$o$'reason', v_reason, 'provider_id', v_pid, 'result', v_r), auth.uid());
  return jsonb_build_object('ok', true, 'kind', v_kind, 'choice', v_choice, 'returns', v_c->>'returns', 'result', v_r);$o$,
       $n$'reason', v_reason, 'provider_id', v_pid, 'result', v_r), auth.uid())
  returning id into v_event;
  -- UR-06 (1 Nov 2026): the reply names the audit event and what the decision actually did, read back from its destination
  return jsonb_build_object('ok', true, 'kind', v_kind, 'choice', v_choice, 'returns', v_c->>'returns', 'result', v_r, 'ref', v_ref, 'event_id', v_event,
                            'outcome', security.layer4_decision_outcome_v1(v_kind, v_choice, v_r));$n$]],
 array[1, 1]);
