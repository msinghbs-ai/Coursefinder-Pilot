-- CF-247 F-CDESC (Platform Admin decision 10 Nov 2026, "Course descriptions: autonomous AI admission from stored course pages"), slice 2 of 2: the audited machine admission of FIRST course descriptions.
--
-- Everything here is OFF until the Platform Admin sets enrich.course_description_machine_on to 1 through Settings, with a reason (added by 20261110060000, ships 0).
--   1. security.course_description_machine_admit_v1(item): re-proves at write time everything security.course_description_machine_check_v1 checks (course and provider live, description empty under the row lock,
--      no hand lock, hold or earlier rejection, page bound (not ambiguous), unchanged, content-hash lineage, object present, recent; every sentence on the page; the admission policy; no duplicate anywhere in the catalogue),
--      then writes the one description, READS IT BACK from catalogue.courses and from public.website_v2_course (read only, not changed), settles the Layer 4 item as a MACHINE decision under the system
--      automation account (Decision 263) with a layer4_decisions row marked actor_kind machine, an admin_control_events row, a search refresh signal and the ledger row (before and after text, evidence id,
--      content hash, source URL, model, prompt version, rule, recovery). It does not call the human decision procedure (security.layer4_review_decide_impl / layer4_course_description_apply_v1), does not lower
--      enrich.course_description_review_first, and never updates catalogue.courses in bulk: one course, one item, one transaction. A decline leaves the item waiting with the exact reason and next action on it.
--   2. security.course_description_machine_withdraw_v1 (rank 6 through public.admin_course_description_machine_withdraw_v1): puts the empty description back if no person changed it and no lock was added since;
--      proves the row; keeps the audit; holds the course out of further machine admission until a person decides.
--   3. security.course_description_machine_settle_v1: the waiting first course descriptions, as many as a time box and enrich.course_text_items_per_day allow in a run (derived, no new setting); a declined item
--      is looked at again when the policy changed, when its decline was transient, or after gaps.recheck_days. security.course_description_machine_consumer_recheck_v1 follows up Website read-backs that lagged.
--   4. A fresh reading that reaches Layer 4 is admitted at once when the switch is on: an AFTER trigger on pipeline.field_enrich_items (state becomes review). Off, nothing happens and Layer 4 behaves exactly as before;
--      no existing function is edited. The trigger swallows its own errors: the reading stays waiting for a person.
--   5. One catalogued job, course-description-machine (G1), command without a number; it does nothing while the switch is 0.
-- The consumer API (G3) is only called for the read-back, never changed. No setting value changes. Nothing is dropped or deleted.
-- Replaces: nothing (a separate machine route; the human Layer 4 route and its triggers are unchanged)
-- Retires: nothing

do $g$
declare r record;
begin
  for r in select * from (values ('security.course_description_machine_check_v1(uuid)'), ('security.course_description_machine_policy_stamp_v1()'), ('security.cdesc_machine_fail_v1(text,text,text,boolean)'),
                                 ('public.website_v2_course(text)'), ('security.current_role_rank()'), ('security.course_description_review_trg_v1()')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing (apply 20261110060000 first)', r.sig; end if;
  end loop;
  if to_regclass('pipeline.course_description_machine_admissions') is null then raise exception 'apply 20261110060000 first'; end if;
end $g$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the admission
create or replace function security.course_description_machine_admit_v1(p_item uuid, p_via text default 'settle') returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare i pipeline.layer4_review_items%rowtype; c catalogue.courses%rowtype; v jsonb; v_text text; v_after text; v_pub jsonb; v_shown text; v_cc text; v_dec uuid; v_reason text; v_msg text; v_stamp text; v_next text; v_tr boolean;
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150'; -- fixed: the system automation account that records Decision 263 rule decisions
        v_rule constant text := 'cdesc-machine-v1'; v_ref constant text := 'CF-247 F-CDESC; Platform Admin decision 10 Nov 2026 (course descriptions: source-verified machine admission)';
        v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int; -- derived: a decline is looked at again after the days the queue reads a course again
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('ok', false, 'rule', 'machine_admission_off'); end if;
  select * into i from pipeline.layer4_review_items where id = p_item for update;
  if i.id is null or i.entity_type <> 'course' or i.field_code <> 'course_description_first_read' then return jsonb_build_object('ok', false, 'rule', 'not_a_course_description_item'); end if;
  if i.status <> 'pending' then return jsonb_build_object('ok', false, 'rule', 'item_not_pending', 'status', i.status); end if;
  select * into c from catalogue.courses where id = i.entity_id for update;
  v_stamp := security.course_description_machine_policy_stamp_v1();
  v := security.course_description_machine_check_v1(p_item);
  if coalesce((v->>'ok')::boolean, false) then
    v_text := v->>'text';
    begin
      -- the one write, proved on the row: a guard that put the old text back (a hand lock) must stop the admission, not leave an audit that says it was published
      update catalogue.courses set description = v_text, updated_at = now() where id = c.id and nullif(btrim(description), '') is null;
      select nullif(btrim(x.description), '') into v_after from catalogue.courses x where x.id = c.id;
      if v_after is distinct from v_text then raise exception 'cdesc:description_not_written:the catalogue kept the earlier text (a lock or guard put it back)'; end if;
      -- the consumer read-back (read only): what the website function returns for this course now
      begin v_pub := public.website_v2_course(c.stable_key); exception when others then v_pub := null; end;
      v_shown := v_pub->'item'->>'description';
      v_cc := case when v_pub is null then 'error' when v_pub ? 'error' then 'not_in_feed' when v_shown = v_text then 'matched' when nullif(btrim(v_shown), '') is null then 'lag' else 'mismatch' end;
      if v_cc = 'mismatch' then raise exception 'cdesc:consumer_mismatch:the website function shows different text for this course after the write'; end if;
      update pipeline.layer4_review_items set status = 'approved', decided_at = now() where id = i.id and status = 'pending';
      v_reason := format('Auto (%s, %s): description read from the course''s own stored page %s (content hash %s); right course and page, every sentence''s quote and the wording policy proved again at admission. Not a person''s decision.',
                         v_rule, coalesce(p_via, 'settle'), coalesce(v->>'source_url', ''), left(coalesce(v->>'content_hash', ''), 12)); -- fixed: a short hash prefix is shown for reading, the full hash is stored
      insert into pipeline.layer4_decisions (review_item_id, action, actor_id, reason, before_value, proposed_value, final_value, evidence_id, layer2_state, layer3_state, change_control_ref)
      values (i.id, 'approve', v_sys, v_reason, i.before_value, i.proposed_value, i.proposed_value, i.evidence_id,
              coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('machine_rule', v_rule, 'actor_kind', 'machine', 'via', coalesce(p_via, 'settle')), coalesce(i.layer3_state, '{}'::jsonb), v_ref) returning id into v_dec;
      insert into pipeline.admin_control_events (area, action, target, detail, actor)
      values ('layer4', 'inbox_decide', i.id::text, jsonb_build_object('kind', 'course_description', 'ref', i.id::text, 'choice', 'approve', 'reason', v_reason, 'course_id', c.id, 'provider_id', c.provider_id,
              'auto', true, 'machine_rule', v_rule, 'actor_kind', 'machine', 'decision_id', v_dec, 'field_code', i.field_code, 'consumer_check', v_cc), v_sys);
      insert into pipeline.search_refresh_signals (entity_type, entity_id, review_decision_id, reason, change_control_ref)
      values ('course', c.id, v_dec, 'Accepted machine-rule Layer 4 canonical change: ' || v_reason, v_ref);
      insert into pipeline.course_description_machine_admissions (course_id, provider_id, review_item_id, reading_item_id, rule, outcome, reason_code, reason, policy_stamp, before_description, after_description, text_md5,
             evidence_id, content_hash, source_url, storage_path, model, prompt_version, worker, checks, recovery, consumer_check, consumer_checked_at, actor)
      values (c.id, c.provider_id, i.id, (v->>'reading_item_id')::bigint, v_rule, 'admitted', 'admitted', v_reason, v_stamp, null, v_text, v->>'text_md5',
              i.evidence_id, v->>'content_hash', v->>'source_url', v->>'storage_path', v->>'model', v->>'prompt_version', v->>'worker',
              coalesce(v->'checks', '{}'::jsonb) || jsonb_build_object('decision_id', v_dec, 'via', coalesce(p_via, 'settle'), 'source_recheck', v->>'source_recheck', 'captured_at', v->>'captured_at'),
              'Withdraw with public.admin_course_description_machine_withdraw_v1(course, reason) (Platform Admin): puts the empty description back if no person changed it and no lock was added since.',
              v_cc, now(), v_sys);
      return jsonb_build_object('ok', true, 'rule', v_rule, 'course_id', c.id, 'decision_id', v_dec, 'description_chars', length(v_text), 'consumer_check', v_cc);
    exception when others then
      get stacked diagnostics v_msg = message_text;
      v := security.cdesc_machine_fail_v1(case when v_msg like 'cdesc:%' then split_part(v_msg, ':', 2) else 'admission_error' end,
                                          case when v_msg like 'cdesc:%' then split_part(v_msg, ':', 3) else left(v_msg, 300) end, -- fixed: display width of the stored reason text
                                          'Nothing was written; the item still waits. A person decides in Layer 4, or the next run tries again.', v_msg not like 'cdesc:%' or v_msg like 'cdesc:consumer_mismatch:%'); -- a feed that disagrees is read again after an hour
    end;
  end if;
  -- declined: the item stays waiting with the exact reason on it; recorded once for the item and refreshed
  v_next := coalesce(v->>'next_action', 'A person decides in Layer 4.'); v_tr := coalesce((v->>'transient')::boolean, false);
  v_reason := coalesce(v->>'reason', 'The machine rule did not admit this.');
  insert into pipeline.course_description_machine_admissions (course_id, provider_id, review_item_id, reading_item_id, rule, outcome, reason_code, reason, next_action, transient, retry_after, policy_stamp, text_md5, evidence_id, actor)
  values (c.id, c.provider_id, i.id, case when coalesce(i.proposed_value->>'item_id', '') ~ '^\d+$' then (i.proposed_value->>'item_id')::bigint end, v_rule, 'declined', v->>'rule', v_reason, v_next, v_tr,
          now() + case when v_tr then make_interval(hours => 1) else make_interval(days => v_days) end, -- fixed: a transient decline is looked at again after an hour
          v_stamp, md5(coalesce(i.proposed_value->>'description', '')), i.evidence_id, v_sys)
  on conflict (review_item_id) where outcome = 'declined' do update set reason_code = excluded.reason_code, reason = excluded.reason, next_action = excluded.next_action, transient = excluded.transient,
         retry_after = excluded.retry_after, policy_stamp = excluded.policy_stamp, text_md5 = excluded.text_md5, evidence_id = excluded.evidence_id, created_at = now();
  update pipeline.layer4_review_items set escalation_reason = left('Machine rule ' || v_rule || ' did not admit this: ' || (v->>'rule') || '. ' || regexp_replace(coalesce(escalation_reason, ''), '^Machine rule [^:]*: [a-z0-9_]+\. ', ''), 1000) -- fixed: the item's reason column shows its first 1000 characters
   where id = i.id and coalesce(escalation_reason, '') not like 'Machine rule ' || v_rule || ' did not admit this: ' || (v->>'rule') || '.%';
  return jsonb_build_object('ok', false, 'rule', v->>'rule', 'reason', v_reason, 'next_action', v_next);
end $f$;
comment on function security.course_description_machine_admit_v1(uuid, text) is 'CF-247 F-CDESC machine admission of one first course description (rule cdesc-machine-v1): needs the switch on; re-proves the safe class under the row locks, writes the one description, reads it back from the catalogue and from the website function, settles the Layer 4 item as a machine decision under the system automation account and records the ledger row. Declines (item stays waiting, exact reason and next action on it and in the ledger) rather than guess. Never calls the human decision procedure.';
revoke all on function security.course_description_machine_admit_v1(uuid, text) from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- withdrawal and rollback
create or replace function security.course_description_machine_withdraw_v1(p_course uuid, p_reason text, p_actor uuid) returns jsonb
language plpgsql security definer set search_path to '' as $f$
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
end $f$;
comment on function security.course_description_machine_withdraw_v1(uuid, text, uuid) is 'CF-247 F-CDESC rollback of one machine-admitted course description: restores the earlier (empty) text if no person changed it since and no hand lock was added, proves the row changed, records the named person and why, queues the search refresh again on the admission''s own decision, and holds the course out of further automatic admission until a person decides. One course at a time. Not callable from the app; use public.admin_course_description_machine_withdraw_v1.';
revoke all on function security.course_description_machine_withdraw_v1(uuid, text, uuid) from public, anon, authenticated;

create or replace function public.admin_course_description_machine_withdraw_v1(p_course uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $f$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) is needed to withdraw a machine description' using errcode = '42501'; end if; -- fixed: rank 6 is the Platform Admin role
  return security.course_description_machine_withdraw_v1(p_course, p_reason, auth.uid());
end $f$;
comment on function public.admin_course_description_machine_withdraw_v1(uuid, text) is 'CF-247 F-CDESC: withdraw one machine-admitted course description (restore the empty text, keep the audit, record who and why). Platform Admin (rank 6) only; the person is recorded, not the system account.';
revoke all on function public.admin_course_description_machine_withdraw_v1(uuid, text) from public, anon;
grant execute on function public.admin_course_description_machine_withdraw_v1(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- settlement of the items already waiting
create or replace function security.course_description_machine_settle_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
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
end $f$;
comment on function security.course_description_machine_settle_v1() is 'CF-247 F-CDESC: checks the waiting first course descriptions against the machine rule, undecided items first, as many as a 40 second time box and enrich.course_text_items_per_day allow; those that pass are admitted and settled as machine decisions, the rest stay for a person with the reason on the item. A declined item is looked at again when the policy changed, when the decline was transient, or after gaps.recheck_days.';
revoke all on function security.course_description_machine_settle_v1() from public, anon, authenticated;

create or replace function security.course_description_machine_consumer_recheck_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
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
end $f$;
comment on function security.course_description_machine_consumer_recheck_v1() is 'CF-247 F-CDESC: reads the website function again for machine-admitted descriptions whose read-back was a lag, an error or not in the feed, and records what it shows (matched, lag, mismatch, not_in_feed, error). Read only against the consumer API.';
revoke all on function security.course_description_machine_consumer_recheck_v1() from public, anon, authenticated;

create or replace function security.course_description_machine_run_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare v_a jsonb; v_b jsonb;
begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  -- one failure never stops the run: each part reports its own error
  begin v_a := security.course_description_machine_settle_v1(); exception when others then v_a := jsonb_build_object('error', sqlerrm); end;
  begin v_b := security.course_description_machine_consumer_recheck_v1(); exception when others then v_b := jsonb_build_object('error', sqlerrm); end;
  return jsonb_build_object('on', true, 'settle', v_a, 'consumer', v_b);
end $f$;
comment on function security.course_description_machine_run_v1() is 'CF-247 F-CDESC: one run of the catalogued job course-description-machine: settle the waiting first course descriptions, then follow up the Website read-backs that lagged. Does nothing while enrich.course_description_machine_on is 0.';
revoke all on function security.course_description_machine_run_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- a fresh reading is admitted as it arrives
create or replace function security.course_description_machine_trg_v1() returns trigger language plpgsql security definer set search_path to '' as $f$
declare v_item uuid;
begin
  if pg_trigger_depth() > 5 then return null; end if; -- fixed: a bound on nested trigger chains (promote-held inside an admission); the job takes the rest
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return null; end if;
  v_item := case when coalesce(new.value->>'review_item_id', '') ~ '^[0-9a-f-]{36}$' then (new.value->>'review_item_id')::uuid end;
  if v_item is null then return null; end if;
  begin perform security.course_description_machine_admit_v1(v_item, 'fresh_reading');
  exception when others then null; -- the reading stays waiting for a person (or the next run); recording it never fails
  end;
  return null;
end $f$;
comment on function security.course_description_machine_trg_v1() is 'CF-247 F-CDESC: after a course description reading reaches Layer 4 (state review), admits it at once under the machine rule while enrich.course_description_machine_on is 1. Off: does nothing. Errors are swallowed; the reading stays waiting.';
revoke all on function security.course_description_machine_trg_v1() from public, anon, authenticated;

create or replace trigger field_enrich_items_cdesc_machine after update of state on pipeline.field_enrich_items for each row
  when (new.state = 'review' and old.state is distinct from 'review' and new.field = 'description') execute function security.course_description_machine_trg_v1();

-- ----------------------------------------------------------------------------------------------------------------------------------------- scoreboard (read only)
create or replace function security.course_description_machine_report_v1() returns jsonb
language sql stable security definer set search_path to '' as $f$
  select jsonb_build_object('contract', 'course-description-machine-report-v1', 'as_at', now(), 'switch_on', security.pipeline_num_v1('enrich.course_description_machine_on', 0) >= 1,
    'admitted', (select count(*) from pipeline.course_description_machine_admissions where outcome = 'admitted' and withdrawn_at is null),
    'admitted_24h', (select count(*) from pipeline.course_description_machine_admissions where outcome = 'admitted' and withdrawn_at is null and created_at > now() - make_interval(hours => 24)), -- fixed: report window
    'admitted_7d', (select count(*) from pipeline.course_description_machine_admissions where outcome = 'admitted' and withdrawn_at is null and created_at > now() - make_interval(days => 7)), -- fixed: report window
    'withdrawn', (select count(*) from pipeline.course_description_machine_admissions where outcome = 'admitted' and withdrawn_at is not null),
    'admitted_by_provider', (select count(distinct provider_id) from pipeline.course_description_machine_admissions where outcome = 'admitted' and withdrawn_at is null),
    'website', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select coalesce(consumer_check, 'unchecked') k, count(*) n from pipeline.course_description_machine_admissions where outcome = 'admitted' and withdrawn_at is null group by 1) z),
    'declined_by_reason', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select d.reason_code k, count(*) n from pipeline.course_description_machine_admissions d
                             join pipeline.layer4_review_items li on li.id = d.review_item_id and li.status = 'pending' where d.outcome = 'declined' group by 1) z),
    'waiting_items', (select count(*) from pipeline.layer4_review_items where field_code = 'course_description_first_read' and entity_type = 'course' and status = 'pending'))
$f$;
comment on function security.course_description_machine_report_v1() is 'CF-247 F-CDESC scoreboard (read only): machine-admitted course descriptions (total, 24 hours, 7 days, providers, withdrawn), their Website read-back state, why waiting items were declined, and how many items wait.';
revoke all on function security.course_description_machine_report_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the job (G1: catalogued first; ships on, does nothing while its switch is 0)
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('course-description-machine', 'Enrichment', 30, 'Course descriptions: automatic admission of first descriptions',
  'Every 10 minutes (not at :35 to :42 or :47 to :48): while Settings > Pipeline settings > Course descriptions: automatic admission is on, checks the waiting first course descriptions against the machine rule cdesc-machine-v1 (right course and page, quotes, wording policy, no duplicates, no lock or earlier rejection), admits those that pass as machine decisions with the reason recorded, leaves the rest for a person in Layer 4 with the exact reason on the item, and follows up Website read-backs that lagged. Does nothing while the switch is 0.',
  6, false, null)
on conflict (jobname) do nothing;
do $c$ begin
  if not exists (select 1 from cron.job where jobname = 'course-description-machine') then
    perform cron.schedule('course-description-machine', '3,13,23,33,43,53 * * * *', $j$select security.course_description_machine_run_v1()$j$);
  end if;
end $c$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- register
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.course_description_machine_admit_v1', 'Layer 4', 'Machine admission of one first course description (switch off by default)', 'active', '{}', '20261110060100'),
 ('function', 'security.course_description_machine_withdraw_v1', 'Layer 4', 'Rollback of one machine-admitted course description', 'active', '{}', '20261110060100'),
 ('function', 'security.course_description_machine_settle_v1', 'Layer 4', 'Settle the waiting first course descriptions under the machine rule', 'active', '{}', '20261110060100'),
 ('function', 'security.course_description_machine_run_v1', 'Layer 4', 'One run of the job course-description-machine', 'active', '{}', '20261110060100'),
 ('function', 'security.course_description_machine_report_v1', 'Layer 4', 'Scoreboard of machine-admitted course descriptions (read only)', 'active', '{}', '20261110060100'),
 ('job', 'course-description-machine', 'Layer 4', 'CF-247 F-CDESC: automatic admission of first course descriptions (does nothing while its switch is 0)', 'active', '{}', '20261110060100')
on conflict do nothing;

-- ----------------------------------------------------------------------------------------------------------------------------------------- post-check
do $post$ begin
  if security.pipeline_num_v1('enrich.course_description_machine_on', -1) <> 0 then raise exception 'post-check: the machine switch must be 0'; end if;
  if security.pipeline_num_v1('enrich.course_description_review_first', 0) < 1 then raise exception 'post-check: review_first must be untouched'; end if;
  if not exists (select 1 from pg_trigger where tgname = 'field_enrich_items_cdesc_machine' and tgrelid = 'pipeline.field_enrich_items'::regclass) then raise exception 'post-check: the reading trigger is missing'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'course-description-machine') then raise exception 'post-check: the job is not catalogued'; end if;
end $post$;
