-- CF-247 AER technical recovery selector (Platform Admin mandate 4 Nov 2026 16:32 §4-§6, admin
-- docs/platform/2026-11-04-layer4-simplification-course-link-aer-recovery-mandate-1632.md; IQ-00232, IQ-00279).
-- Why (production, read only, 4 Nov 2026 17:10-17:27 AEDT; admin 2026-11-04-aer-throughput-investigation.md §10):
--   * The observer's "AER technical correction" (security.progress_measure_v1, job first-run-verify) counts work items of lane aer_technical:
--     processed = items whose last_attempt_at is in the window (234), created = items recovered (0), eligible = stage eligible (35 at 16:32, 65 at
--     17:02), parked = 154 / 151 (132 / 129 technical_hold with no next time, 22 duplicates). No corrected read is counted there.
--   * Lane aer_technical is written only by security.aer_technical_recovery_v1 (each aer-scheduled-read run at :13). It never recovers anything:
--     every technically blocked item is reported failed, class technical_hold, whose policy is retry_backoff (a transient class): checked again at
--     10, 20 and 40 minutes, then parked "attempts used up (3)" with no next time and no reason. 94 items a run were re-checked at 17:13. The holds
--     are deterministic: 104 cut at the row limit (none ever re-read), 44 whose corrected read the reader refused on the same stored copy (14 for the
--     row limit), 26 shared pages, 18 matrix runs held by D-R3, 14 course reads with rows a person leaves out (a decision, not a technical hold);
--     only 33 (dropped minimums, never re-read, stored copy present) have a corrected read that could still succeed.
--   * The one automatic re-read, the held step of aer-scheduled-read (security.aer_schedule_held_v1), has run no read since 03:13 (the daily cap
--     aer.schedule_daily_max is full until the 18:13 run) and, once it runs, allows a second read of the same unchanged copy after
--     aer.schedule_held_retry_days. Of 82 scheduled corrected reads in 24 hours, 10 replaced their read; 71 were refused, 69 of them on a copy that had
--     not changed.
--   * The recovery panel (security.layer4_aer_recovery_detail_v1, v2.15.471) recommends Open human input after a refusal on an unchanged copy, and
--     security.layer4_reread_repeat_v1 suggests it as the alternative; Human input needed resumes through security.har_aer_item_resume_v1, which
--     asks the same corrected read of the same copy (security.course_entry_correction_v1), so typed rows would be refused again.
-- What (one shared eligibility rule; no new state table, no cap or spending change, no enqueue):
--   1. security.aer_recovery_rule_v1(item): the recovery class of one waiting AER item from existing records (stored gate, corrected-read history
--      through security.layer4_reread_repeat_v1 and its change keys, interventions, manual locks, the bound page, reads in progress): row_limit
--      (authority: entry.max_rows_by_provider), unchanged_evidence (an identical read is prohibited until the copy, layer4.reader_revision or an
--      entry setting changes), transient (bounded retries), human_assisted (an open or due intervention; identity, a matrix source, a lock),
--      changed_conditions (a parked item whose copy or settings changed: eligible again), reread_eligible (never read again; stored copy of the
--      same page), decision (rows a person leaves out), stale, unchecked, ready. Each with the §5 fields: last attempt and result, evidence used
--      and now, reader revision, settings changed, next action, next time or authority blocker, why an identical retry is prohibited, the
--      intervention, and a condition key (what has to change).
--   2. security.aer_technical_recovery_v1 (md5-guarded replacement): reports each technically blocked item once per condition through the rule:
--      deterministic classes are parked with their blocker and next action (no attempt counted), human ones wait for review with their reference,
--      transient ones keep bounded retries, eligible ones are deferred to the scheduled read; an unchanged condition is not reported again; a
--      changed one is reconsidered automatically. Duplicates and recoveries as before.
--   3. security.aer_schedule_held_v1 and security.aer_e13_recover_v1 (md5-guarded edits) select only reread_eligible and changed_conditions.
--   4. security.har_aer_item_generate_v1 (md5-guarded edit): raises only identity interventions (a person's rows would resume the same refused read).
--   5. security.layer4_aer_recovery_detail_v1 and security.layer4_reread_repeat_v1 (owner: Layer 4 action lifecycle; md5-guarded edits, coordinated
--      with the Integration Controller): after a refusal on an unchanged copy the panel recommends the row-limit decision (row limit) or waiting for a
--      changed copy, reader or setting, not Open human input.
--   6. security.aer_recovery_report_v1(since): the §11 AER measures (corrected reads asked, unique items, replaced, refused, deterministic retries
--      prevented, transient retries, duplicates, human, review-ready, active rows and publication gained, AI spend).
-- Settings (G2): aer.reread_recheck_hours. Policies (rows beside the contract's): aer_row_limit, aer_unchanged_evidence, aer_reread_eligible,
--   aer_human_input, aer_stale.
-- Activation: ON (records and selects; spends nothing new: the held step keeps aer.schedule_daily_max and batch.aer_schedule_held). E13 recovery
--   stays off (aer.e13_recover_on).
-- Before (live, 4 Nov 2026 17:11 AEDT) -> after:
--   security.aer_technical_recovery_v1() 370baa57bfb81fe58df767ad852ca9dd -> 08322eb59fc9081ed7a684bddcfc6b64
--   security.aer_schedule_held_v1(integer) 2a0d51faada02e5e36dafb88749b4707 -> c866167b55d2494c366fd2700a518ff8
--   security.aer_e13_recover_v1(boolean) 1bd8be8be44d5cd6e25a41a337b43f61 -> a81a54b182387249734edda8152d7bc0
--   security.har_aer_item_generate_v1(integer) 22cb0e540469b5f2ed69a85ecacf5aa2 -> b25b89a19d5ee7b1bad9c17d4bbcab2b
--   security.layer4_aer_recovery_detail_v1(text) dbf06336a7ee14fd0a84697d616cb67c -> 5d08d39ed1a9ce82ed8d75c6795e13fe
--   security.layer4_reread_repeat_v1(uuid) 80c53ac44d4309279eeb1835d9f7fc21 -> 19b6d24ec0a676289805f8e3d8b819d2
-- Replaces: security.aer_technical_recovery_v1 (same name: the rule instead of retry_backoff for every hold)
-- Retires: nothing (policy technical_hold stays for items recorded before; nothing new is recorded with it)
-- Nothing is dropped or deleted. No consumer API object, cap, spending limit, admission authority, manual lock, E13 or D-R3 gate changes.

-- 0 guards -------------------------------------------------------------------------------------------------------------------------------------
do $g$
declare r record;
begin
  for r in select * from (values ('security.work_item_report_v1(text,text,text,text,jsonb)', '6a15318c0ecd6644b32f1883463c542e'),
                                 ('security.aer_e13_class_v1(jsonb)', 'be023e0e23074cbdd8ed370b3fc7c000')) v(sig, m) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
  if to_regprocedure('security.aer_route_v1(text,jsonb)') is null or to_regprocedure('security.layer4_aer_recovery_state_v1(uuid)') is null then
    raise exception 'needs the AER review queue (v2.15.470) and Human-assisted recovery (v2.15.463)'; end if;
end $g$;

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

-- 1 settings and policies ------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.reread_recheck_hours', 'Entry requirements: re-check a hold eligible for a corrected read every',
  'A held course read that may still be corrected from its stored copy waits for the scheduled entry reading; its recovery record is looked at again after this long (nothing is read by the look).',
  'number', to_jsonb(24), 1, 168, 'hours', 1468, 'Entry requirements', 'pipeline.work_recovery_policies aer_reread_eligible; security.aer_technical_recovery_v1',
  'Mandate 4 Nov 2026 16:32 §5 (next eligible action and time)')
on conflict (toolset_key, key) do nothing;

insert into pipeline.work_recovery_policies(failure_class, title, action, counts_attempt, max_attempts_key, recheck_key, escalate_as, escalate_when, root_cause, description) values
 ('aer_row_limit', 'An entry read is cut at the row limit', 'park', false, null, null, 'authority', 'never', null,
  'The page has more requirements than the row limit; a read under the same limit is cut again. Waits for a row limit for the university (entry.max_rows_by_provider, Platform Admin); a change to an entry setting reconsiders it.'),
 ('aer_unchanged_evidence', 'A corrected read was refused on an unchanged stored copy', 'park', false, null, null, null, 'never', null,
  'The reader refused the corrected read of this stored copy; the same reader, copy and settings give the same refusal. Reconsidered when the copy, the reader (layer4.reader_revision) or an entry setting changes.'),
 ('aer_reread_eligible', 'A held entry read may still be corrected from its stored copy', 'defer_recheck', false, null, 'aer.reread_recheck_hours', null, 'never', null,
  'Never read again and the stored copy of the same page exists: the scheduled entry reading asks one corrected read within its daily cap.'),
 ('aer_human_input', 'An entry read needs a person or a provider-level source', 'park', false, null, null, 'identity', 'never', null,
  'The course a shared page belongs to, the provider''s matrix source, or a manual lock: a Human input needed item or a person''s decision moves it.'),
 ('aer_stale', 'An entry read no longer describes the course''s page', 'park', false, null, null, null, 'never', null,
  'The course is inactive or bound to another page: a new first read, not a correction; a person rejects the read.')
on conflict (failure_class) do nothing;

-- 2 the shared rule --------------------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_recovery_rule_v1(p_item uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 mandate 16:32 §4-§5: the recovery class of one waiting AER item, from existing records only, with the fields a hold keeps. Read only.
declare r pipeline.layer4_review_items; x pipeline.layer4_item_readiness; rt jsonb; v_cls text; v_rep jsonb; v_pid uuid; v_pg record; v_iv record; v_lock boolean := false;
        v_busy text; v_set_at timestamptz; v_rev numeric := security.pipeline_num_v1('layer4.reader_revision', 1); v_class text; v_next text; v_at timestamptz;
        v_auth text; v_why text; v_last record; v_moved boolean := false; v_active boolean := true; v_tick timestamptz;
begin
  select * into r from pipeline.layer4_review_items where id = p_item;
  if r.id is null or r.status <> 'pending' or r.field_code not in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change') then
    return jsonb_build_object('item', p_item, 'class', 'closed', 'technical', false);
  end if;
  select * into x from pipeline.layer4_item_readiness where item_id = p_item;
  -- every record exists before it is read (a record not yet assigned cannot be referenced)
  select null::text url, null::uuid evidence_id into v_pg;
  select null::uuid id, null::text state, null::text outcome, null::timestamptz requested_at, null::timestamptz closed_at into v_last;
  rt := security.aer_route_v1(r.field_code, x.gate); v_cls := rt->>'class';
  -- the settings that change a read (layer4.reread_change_keys): when the newest of them changed
  select max(t.updated_at) into v_set_at from pipeline.platform_toolset_settings t
   where t.toolset_key = 'pipeline' and exists (select 1 from jsonb_array_elements_text(coalesce((select w.value from pipeline.platform_toolset_settings w
          where w.toolset_key = 'pipeline' and w.key = 'layer4.reread_change_keys'), '["entry.%", "layer4.reader_revision"]'::jsonb)) k where t.key like k);
  v_tick := date_trunc('hour', now()) + interval '13 minutes';  -- fixed: aer-scheduled-read runs at minute 13 (its cron schedule)
  if v_tick <= now() then v_tick := v_tick + interval '1 hour'; end if;  -- fixed: the next hourly run
  if r.field_code = 'course_entry_first_read' then
    select c.provider_id, c.lifecycle_status = 'active' act into v_pid, v_active from catalogue.courses c where c.id = r.entity_id;
    select pg.url, pg.evidence_id into v_pg from pipeline.coverage_course_pages pg where pg.course_id = r.entity_id;
    v_moved := v_pg.url is distinct from r.proposed_value->>'url';
    v_lock := exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = r.entity_id and l.field = 'entry_requirements');
    v_busy := case when exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = p_item and s.state = 'requested') then 'a corrected read of this item is waiting for the reader'
                   when exists (select 1 from pipeline.field_enrich_items f where f.course_id = r.entity_id and f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased'))
                     then 'a read of this course is in progress' end;
    v_rep := security.layer4_reread_repeat_v1(p_item);
    select s.id, s.state, s.outcome, s.requested_at, s.closed_at into v_last from pipeline.aer_read_supersessions s where s.old_item_id = p_item order by s.requested_at desc limit 1;
  else
    v_pid := r.entity_id; v_rep := jsonb_build_object('repeat', false);
  end if;
  select i.id, i.missing_fact, i.status into v_iv from pipeline.layer4_interventions i
   where i.status in ('ai_pending', 'awaiting_input', 'resuming')
     and (i.entity = p_item::text or (r.field_code <> 'course_entry_first_read' and i.provider_id = v_pid and i.lane = 'aer_source' and i.missing_fact = 'aer_read_held'))
   order by i.id desc limit 1;
  v_class := case
    when x.gate is null then 'unchecked'
    when r.field_code = 'course_entry_first_read' and (not coalesce(v_active, true) or v_moved) then 'stale'
    when v_cls = 'complete' then 'ready'
    when rt->>'route' in ('review_except', 'matrix_except') then 'decision'
    when v_lock then 'human_assisted'
    when v_busy is not null then 'transient'
    when v_iv.id is not null then 'human_assisted'
    when rt->>'route' in ('identity', 'matrix_source') then 'human_assisted'
    when v_last.state = 'refused' and coalesce(v_last.outcome, '') ilike '%proof does not admit%' and coalesce((v_rep->>'repeat')::boolean, false) then 'human_assisted'
    when v_cls = 'row_limit' and v_set_at > r.created_at then 'changed_conditions'
    when v_cls = 'row_limit' then 'row_limit'
    when v_cls = 'drops_uncovered' and coalesce((v_rep->>'repeat')::boolean, false) and coalesce((v_rep->>'row_limit')::boolean, false) then 'row_limit'
    when v_cls = 'drops_uncovered' and coalesce((v_rep->>'repeat')::boolean, false) then 'unchanged_evidence'
    when v_cls = 'drops_uncovered' and v_last.state = 'refused' then 'changed_conditions'
    when v_cls = 'drops_uncovered' and v_pg.evidence_id is null then 'human_assisted'
    when v_cls = 'drops_uncovered' then 'reread_eligible'
    else 'human_assisted' end;
  v_auth := case when v_class = 'row_limit' then 'a row limit for this university (entry.max_rows_by_provider, Platform Admin)' end;
  v_why := case v_class
    when 'row_limit' then 'the page has more requirements than the row limit (' || coalesce(security.pipeline_num_v1('entry.max_rows_per_course', 6)::text, '6')
                          || '); a read under the same limit is cut again' || coalesce('; ' || (v_rep->>'why'), '')
    when 'unchanged_evidence' then v_rep->>'why'
    when 'transient' then v_busy
    when 'stale' then case when not coalesce(v_active, true) then 'the course is no longer active' else 'the course is now bound to another page: a new first read, not a correction' end
    when 'human_assisted' then case when v_lock then 'the course''s entry requirements are locked by hand'
                                    when v_iv.id is not null then 'Human input needed item ' || v_iv.id || ' (' || v_iv.missing_fact || ') waits for a person'
                                    when rt->>'route' = 'identity' or coalesce(v_last.outcome, '') ilike '%proof does not admit%' then 'the stored page is not proven to be this course''s own page'
                                    when rt->>'route' = 'matrix_source' then 'the university''s matrix source dropped published rows or values'
                                    else 'the page has no stored copy to read again' end
    else null end;
  v_next := case v_class
    when 'ready' then 'a person decides it in Layer 4'
    when 'decision' then 'a person leaves out the named rows (Approve except) or rejects the read in Layer 4'
    when 'unchecked' then 'job layer4-readiness gates it (never-gated items first)'
    when 'stale' then 'a person rejects the read; the course is read again from its bound page'
    when 'transient' then 'wait for the read in progress; checked again with bounded retries'
    when 'row_limit' then 'the Platform Admin sets a row limit for this university; the item is reconsidered by itself when an entry setting changes'
    when 'unchanged_evidence' then 'none until the stored copy, the reader (layer4.reader_revision) or an entry setting changes; then reconsidered by itself'
    when 'changed_conditions' then 'one corrected read by the scheduled entry reading (aer-scheduled-read), within its daily cap'
    when 'reread_eligible' then 'one corrected read by the scheduled entry reading (aer-scheduled-read), within its daily cap'
    when 'human_assisted' then case when v_lock then 'a Platform Admin lifts the lock, or the read is left'
                                    when v_iv.id is not null then 'answer Human input needed item ' || v_iv.id
                                    when rt->>'route' = 'matrix_source' then 'Human-assisted recovery''s provider-level item for the source (aer_read_held), then the matrix re-read'
                                    when v_pg.evidence_id is null and r.field_code = 'course_entry_first_read' and v_cls = 'drops_uncovered' then 'the course page is read again (a stored copy is kept), then a corrected read'
                                    else 'job layer4-interventions raises one item asking which programme the page belongs to (aer_course_identity)' end end;
  v_at := case when v_class in ('reread_eligible', 'changed_conditions') then v_tick
               when v_class = 'unchecked' then date_trunc('hour', now()) + case when extract(minute from now()) < 22 then interval '22 minutes' when extract(minute from now()) < 52 then interval '52 minutes' else interval '82 minutes' end  -- fixed: layer4-readiness runs at :22 and :52
               when v_class = 'transient' then now() + make_interval(mins => security.work_backoff_minutes_v1(1)::int) end;
  return jsonb_build_object('item', p_item, 'field_code', r.field_code, 'provider_id', v_pid, 'class', v_class, 'gate_class', v_cls, 'route', rt->>'route',
    'technical', v_class not in ('ready', 'decision', 'closed'), 'eligible', v_class in ('reread_eligible', 'changed_conditions'),
    'deterministic', v_class in ('row_limit', 'unchanged_evidence'),
    'last_attempt', case when v_last.id is not null then jsonb_build_object('request', v_last.id, 'state', v_last.state, 'outcome', v_last.outcome,
                         'at', coalesce(v_last.closed_at, v_last.requested_at)) end,
    'evidence_used', v_rep->>'evidence_used', 'evidence_now', coalesce(v_pg.evidence_id::text, v_rep->>'evidence_now'), 'reader_revision', v_rev,
    'settings_changed_at', v_set_at, 'settings_changed', v_rep->'settings_changed', 'next_action', v_next, 'next_at', v_at, 'authority', v_auth,
    'retry_prohibited', case when v_class in ('row_limit', 'unchanged_evidence') then coalesce(v_why, 'deterministic') end, 'why', v_why,
    'intervention', v_iv.id,
    'condition_key', md5(concat_ws('|', v_class, coalesce(v_pg.evidence_id::text, '-'), v_rev::text, coalesce(v_set_at::text, '-'), coalesce(v_iv.id::text, '-'),
                                   coalesce(v_last.id::text || ':' || v_last.state, '-'), coalesce(v_cls, '-'), v_lock::text, coalesce(v_busy, '-'))));
end $function$;
revoke all on function security.aer_recovery_rule_v1(uuid) from public, anon, authenticated;

-- 3 technical recovery through the rule (md5-guarded replacement of the whole definition) --------------------------------------------------------
do $r$
begin
  if md5(pg_get_functiondef('security.aer_technical_recovery_v1()'::regprocedure)) not in ('370baa57bfb81fe58df767ad852ca9dd', '08322eb59fc9081ed7a684bddcfc6b64') then
    raise exception 'live security.aer_technical_recovery_v1() differs from the definition this change replaces (md5 %)', md5(pg_get_functiondef('security.aer_technical_recovery_v1()'::regprocedure));
  end if;
end $r$;
create or replace function security.aer_technical_recovery_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 SS-021 F4, mandate 16:32 §4-§5: Layer 4 entry items that are not decisions are recorded for technical recovery (lane aer_technical)
-- through one rule (security.aer_recovery_rule_v1): deterministic holds (row limit, refused on an unchanged copy) are parked with their blocker,
-- next action and the reason an identical retry is prohibited, and no attempt is counted; human holds wait for review with their reference;
-- transient ones keep bounded retries; holds a corrected read can still fix are deferred to the scheduled entry reading. A hold whose condition
-- has not changed is not reported again; a changed one is reconsidered by itself. Duplicates are parked once; an item that becomes ready, closes or
-- leaves the queue is recovered. Records only: no Layer 4 item, decision, read or value is changed, and nothing is spent.
declare v_n int := security.pipeline_num_v1('wc.tick_batch', 500)::int; r record; v_t int := 0; v_d int := 0; v_ok int := 0; v_e13 jsonb; ru jsonb; v_res jsonb;
        v_same int := 0; v_by jsonb := '{}'::jsonb; v_pol text;
begin
  if security.pipeline_num_v1('wc.on', 1) < 1 then return jsonb_build_object('held', 'wc.on is 0'); end if;
  for r in select i.id, i.entity_id, i.entity_type, i.field_code, c.provider_id, w.stage, w.evidence_version, w.next_eligible_at
             from pipeline.layer4_review_items i join pipeline.layer4_item_readiness x on x.item_id = i.id
             left join catalogue.courses c on i.entity_type = 'course' and c.id = i.entity_id
             join pipeline.work_review_categories rc on rc.category = 'aer'
             left join pipeline.work_items w on w.lane = 'aer_technical' and w.entity = i.id::text and w.work_kind = 'l4_item'
            where i.status = 'pending' and i.field_code = any (rc.field_codes) and x.readiness = 'technical_blocked'
              and coalesce(w.failure_class, '') <> 'duplicate'
            order by i.created_at, i.id limit v_n loop
    ru := security.aer_recovery_rule_v1(r.id);
    -- an unchanged condition is not reported again (it is waiting for something that has not happened); a due retry or recheck is
    if r.evidence_version is not distinct from ru->>'condition_key' and not (r.stage in ('retry_wait', 'deferred', 'eligible') and coalesce(r.next_eligible_at, now()) <= now()) then
      v_same := v_same + 1; continue;
    end if;
    v_pol := case ru->>'class' when 'row_limit' then 'aer_row_limit' when 'unchanged_evidence' then 'aer_unchanged_evidence' when 'reread_eligible' then 'aer_reread_eligible'
                               when 'changed_conditions' then 'aer_reread_eligible' when 'stale' then 'aer_stale' when 'transient' then 'transient' else 'aer_human_input' end;
    if ru->>'class' in ('decision', 'ready') or (ru->>'class' = 'human_assisted' and (ru->>'intervention') is not null) then
      v_res := security.work_item_report_v1('aer_technical', r.id::text, 'l4_item', 'review', jsonb_build_object(
                 'review_ref', case when (ru->>'intervention') is not null then 'intervention:' || (ru->>'intervention') else 'layer4:' || r.id end,
                 'owner', 'aer-scheduled-read', 'field', r.field_code, 'provider_id', coalesce(r.provider_id, case when r.entity_type = 'provider' then r.entity_id end),
                 'evidence_version', ru->>'condition_key'));
    else
      v_res := security.work_item_report_v1('aer_technical', r.id::text, 'l4_item', 'failed', jsonb_build_object(
                 'class', v_pol, 'owner', 'aer-scheduled-read', 'field', r.field_code,
                 'provider_id', coalesce(r.provider_id, case when r.entity_type = 'provider' then r.entity_id end),
                 'message', ru->>'class' || ': ' || coalesce(ru->>'why', ru->>'next_action'), 'evidence', ru - 'condition_key', 'evidence_version', ru->>'condition_key'));
    end if;
    -- §5: the hold keeps its blocker, next action and time, and why an identical retry is prohibited
    update pipeline.work_items w set unresolved_blocker = coalesce(w.unresolved_blocker, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
             'class', ru->>'class', 'next_action', ru->>'next_action', 'next_at', ru->'next_at', 'authority', ru->>'authority',
             'retry_prohibited', ru->>'retry_prohibited', 'intervention', ru->'intervention', 'last_attempt', ru->'last_attempt',
             'evidence_used', ru->>'evidence_used', 'evidence_now', ru->>'evidence_now', 'reader_revision', ru->'reader_revision', 'at', now())),
           evidence_version = ru->>'condition_key', updated_at = now()
     where w.lane = 'aer_technical' and w.entity = r.id::text and w.work_kind = 'l4_item';
    v_by := jsonb_set(v_by, array[ru->>'class'], to_jsonb(coalesce((v_by->>(ru->>'class'))::int, 0) + 1));
    v_t := v_t + 1;
  end loop;
  for r in select z.* from (
             select i.id, i.entity_id, i.entity_type, i.field_code, c.provider_id,
                    first_value(i.id) over (partition by i.entity_id, i.field_code order by i.created_at, i.id) keep,
                    row_number() over (partition by i.entity_id, i.field_code order by i.created_at, i.id) rn
               from pipeline.layer4_review_items i left join catalogue.courses c on i.entity_type = 'course' and c.id = i.entity_id
               join pipeline.work_review_categories rc on rc.category = 'aer'
              where i.status = 'pending' and i.field_code = any (rc.field_codes)) z
            where z.rn > 1 and not exists (select 1 from pipeline.work_items w where w.lane = 'aer_technical' and w.entity = z.id::text and w.work_kind = 'l4_item'
                                                                              and w.failure_class = 'duplicate' and w.stage = 'parked')
            limit v_n loop
    perform security.work_item_report_v1('aer_technical', r.id::text, 'l4_item', 'failed', jsonb_build_object(
              'class', 'duplicate', 'owner', 'aer-scheduled-read', 'field', r.field_code,
              'provider_id', coalesce(r.provider_id, case when r.entity_type = 'provider' then r.entity_id end),
              'message', 'duplicate of the older waiting item', 'evidence', jsonb_build_object('kept_item', r.keep)));
    update pipeline.work_items w set unresolved_blocker = coalesce(w.unresolved_blocker, '{}'::jsonb) || jsonb_build_object('class', 'duplicate',
             'next_action', 'none: the older waiting item ' || r.keep || ' is the one decided', 'retry_prohibited', 'a duplicate is never worked separately')
     where w.lane = 'aer_technical' and w.entity = r.id::text and w.work_kind = 'l4_item';
    v_d := v_d + 1;
  end loop;
  -- duplicates parked before this change get the same next action (IQ-00232)
  update pipeline.work_items w set unresolved_blocker = coalesce(w.unresolved_blocker, '{}'::jsonb) || jsonb_build_object('class', 'duplicate',
           'next_action', 'none: the older waiting item ' || coalesce(w.evidence->-1->'evidence'->>'kept_item', 'of the same course') || ' is the one decided',
           'retry_prohibited', 'a duplicate is never worked separately')
   where w.lane = 'aer_technical' and w.work_kind = 'l4_item' and w.failure_class = 'duplicate' and w.stage = 'parked' and coalesce(w.unresolved_blocker->>'next_action', '') = '';
  for r in select w.entity from pipeline.work_items w
            where w.lane = 'aer_technical' and w.work_kind = 'l4_item' and w.stage <> 'done'
              and not exists (select 1 from pipeline.layer4_review_items i left join pipeline.layer4_item_readiness x on x.item_id = i.id
                               where i.id::text = w.entity and i.status = 'pending'
                                 and (case when w.failure_class = 'duplicate' then true else x.readiness = 'technical_blocked' end))
            limit v_n loop
    perform security.work_item_report_v1('aer_technical', r.entity, 'l4_item', 'succeeded', jsonb_build_object('outcome', 'succeeded_with_result'));
    v_ok := v_ok + 1;
  end loop;
  begin
    v_e13 := security.aer_e13_recover_v1(false);
  exception when others then v_e13 := jsonb_build_object('error', left(sqlerrm, 200));
  end;
  return jsonb_build_object('technical_checked', v_t, 'unchanged', v_same, 'by_class', v_by, 'duplicates_parked', v_d, 'recovered', v_ok, 'e13_recover', v_e13);
end $function$;
do $r$
begin
  if md5(pg_get_functiondef('security.aer_technical_recovery_v1()'::regprocedure)) <> '08322eb59fc9081ed7a684bddcfc6b64' then
    raise exception 'security.aer_technical_recovery_v1() after the change has md5 %, expected 08322eb59fc9081ed7a684bddcfc6b64', md5(pg_get_functiondef('security.aer_technical_recovery_v1()'::regprocedure));
  end if;
end $r$;

-- 4 the scheduled held step and the E13 pilot select only what the rule makes eligible ---------------------------------------------------------
select pg_temp.edit_once('security.aer_schedule_held_v1(integer)', '2a0d51faada02e5e36dafb88749b4707', 'c866167b55d2494c366fd2700a518ff8', array[
  [$e$    else
      v_chk := security.course_entry_correction_check_v1(r.id, r.entity_id, r.url);$e$,
   $e$    -- 4 Nov 2026 (mandate 16:32 §4-§5): only a read the shared rule makes eligible is read again (never a refusal on an unchanged copy or a
    -- row-limit cut under the same limit); the others are recorded with their class
    elsif not coalesce((security.aer_recovery_rule_v1(r.id)->>'eligible')::boolean, false) then
      outcome := left('held, not read again: ' || coalesce(security.aer_recovery_rule_v1(r.id)->>'class', '?') || ' (' || coalesce(security.aer_recovery_rule_v1(r.id)->>'next_action', '') || ')', 300);
    else
      v_chk := security.course_entry_correction_check_v1(r.id, r.entity_id, r.url);$e$],
  [$e$              and not exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = i.id and (s.state = 'requested' or s.requested_at > now() - v_retry))
              and (select count(*) from pipeline.aer_read_supersessions s where s.old_item_id = i.id) < v_tries$e$,
   $e$              and not exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = i.id and (s.state = 'requested' or s.requested_at > now() - v_retry))
              and (select count(*) from pipeline.aer_read_supersessions s where s.old_item_id = i.id) < v_tries
              and not exists (select 1 from pipeline.work_items w where w.lane = 'aer_technical' and w.entity = i.id::text and w.work_kind = 'l4_item'
                                and w.failure_class in ('aer_row_limit', 'aer_unchanged_evidence', 'aer_human_input', 'aer_stale', 'duplicate') and w.stage in ('parked', 'awaiting_review'))$e$]],
  array[1, 1]);

select pg_temp.edit_once('security.aer_e13_recover_v1(boolean)', '1bd8be8be44d5cd6e25a41a337b43f61', 'a81a54b182387249734edda8152d7bc0', array[
  [$e$         and not exists (select 1 from pipeline.aer_read_supersessions s left join pipeline.field_enrich_items fe on fe.id = s.enrich_item_id
                          where s.old_item_id = i.id and s.state = 'refused' and (fe.evidence_id is null or fe.evidence_id = pg.evidence_id))$e$,
   $e$         -- mandate 16:32 §4: the shared rule (an unchanged copy, reader and settings never read again; a change makes it eligible)
         and coalesce((security.aer_recovery_rule_v1(i.id)->>'eligible')::boolean, false)$e$]], array[1]);

-- 5 interventions: only what a person's answer can move (identity); a person's rows would resume the same refused read --------------------------
select pg_temp.edit_once('security.har_aer_item_generate_v1(integer)', '22cb0e540469b5f2ed69a85ecacf5aa2', 'b25b89a19d5ee7b1bad9c17d4bbcab2b', array[
  [$e$        from h where h.rt->>'route' = 'identity'
          or (h.rt->>'route' in ('missing_scale', 'quote_association', 'low_confidence') and (not coalesce(h.stored, false) or h.refused_same or h.tries >= v_tries)$e$,
   $e$        from h where h.rt->>'route' = 'identity'
          -- mandate 16:32 §4: rows from a person resume the same corrected read of the same copy (security.har_aer_item_resume_v1), which the
          -- reader refuses again; these holds wait for a changed copy, reader or setting (security.aer_recovery_rule_v1) instead
          or (false and h.rt->>'route' in ('missing_scale', 'quote_association', 'low_confidence') and (not coalesce(h.stored, false) or h.refused_same or h.tries >= v_tries)$e$]],
  array[1]);

-- 6 the recovery panel and the repeat explanation agree with the rule (owner: Layer 4 action lifecycle; coordinated) ------------------------------
select pg_temp.edit_once('security.layer4_reread_repeat_v1(uuid)', '80c53ac44d4309279eeb1835d9f7fc21', '19b6d24ec0a676289805f8e3d8b819d2', array[
  [$e$                        when v_row then 'Open human input with the dropped requirements, or ask the Platform Admin for a row limit for this university (Settings › Pipeline settings, entry.max_rows_by_provider)'
                        else 'Open human input with the dropped requirements, or Request official evidence' end);$e$,
   $e$                        when v_row then 'Ask the Platform Admin for a row limit for this university (Settings › Pipeline settings, entry.max_rows_by_provider); the item is reconsidered by itself when it changes. Typed rows would resume the same refused read'
                        else 'None until the stored copy, the reader (layer4.reader_revision) or an entry setting changes; the item is reconsidered by itself then. Typed rows would resume the same refused read' end);$e$]],
  array[1]);

select pg_temp.edit_once('security.layer4_aer_recovery_detail_v1(text)', 'dbf06336a7ee14fd0a84697d616cb67c', '5d08d39ed1a9ce82ed8d75c6795e13fe', array[
  [$e$                when v_repeat then 'open_intervention'$e$,
   $e$                -- mandate 16:32 §4, §7: after an identical refusal the honest next step is the row-limit decision or a changed copy, reader or setting
                when v_repeat and coalesce((v_rep->>'row_limit')::boolean, false) then 'row_limit_decision'
                when v_repeat then 'wait_for_change'$e$],
  [$e$        'Human input needed', case when v_rec in ('open_intervention', 'request_evidence') or v_iv.id is not null then 'yes' else 'not yet' end,$e$,
   $e$        'Human input needed', case when v_rec in ('open_intervention', 'request_evidence') or v_iv.id is not null then 'yes'
                                   when v_rec = 'row_limit_decision' then 'no: the Platform Admin decides a row limit for this university (entry.max_rows_by_provider)'
                                   when v_rec = 'wait_for_change' then 'no: typed rows would resume the same refused read' else 'not yet' end,$e$],
  [$e$        'Owner', case when v_iv.id is not null then v_iv.assigned_to when v_rec = 'reread_stored' then 'the entry reader (automatic)' else 'Layer 4 reviewer' end,$e$,
   $e$        'Owner', case when v_iv.id is not null then v_iv.assigned_to when v_rec = 'reread_stored' then 'the entry reader (automatic)'
                      when v_rec = 'row_limit_decision' then 'Platform Admin' when v_rec = 'wait_for_change' then 'the platform (reconsidered when the copy, reader or setting changes)' else 'Layer 4 reviewer' end,$e$],
  [$e$      jsonb_build_object('key', 'open_intervention', 'allowed', v_iv.id is null, 'recommended', v_rec = 'open_intervention',$e$,
   $e$      jsonb_build_object('key', 'open_intervention', 'allowed', v_iv.id is null and not v_repeat, 'recommended', v_rec = 'open_intervention',$e$],
  [$e$                         'why', case when v_iv.id is not null then 'a Human input needed item is already open (ref ' || v_iv.id || ')' end)));$e$,
   $e$                         'why', case when v_iv.id is not null then 'a Human input needed item is already open (ref ' || v_iv.id || ')'
                                     when v_repeat then 'typed rows would resume the same corrected read of the same copy, which the reader refuses: ' || (v_rep->>'alternative') end)));$e$]],
  array[1, 1, 1, 1, 1]);

-- 7 the §11 measures -------------------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_recovery_report_v1(p_since timestamptz) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- CF-247 mandate 16:32 §6, §11: AER technical recovery as transitions, from existing records (read only): corrected reads asked and their result,
-- unique items, repeats on an unchanged copy, holds by class with their next action, duplicates, human items, review-ready, active rows and
-- consumer publication gained, and the AI cost of corrected reads
  with s as (select s.*, fe.cost_usd, fe.evidence_id ev from pipeline.aer_read_supersessions s left join pipeline.field_enrich_items fe on fe.id = s.enrich_item_id where s.requested_at >= p_since),
       rep as (select s.id from s where s.state = 'refused' and exists (select 1 from pipeline.aer_read_supersessions p left join pipeline.field_enrich_items pf on pf.id = p.enrich_item_id
                 where p.old_item_id = s.old_item_id and p.state = 'refused' and p.requested_at < s.requested_at and pf.evidence_id is not distinct from s.ev)),
       w as (select * from pipeline.work_items where lane = 'aer_technical' and work_kind = 'l4_item')
  select jsonb_build_object('since', p_since,
    'corrected_reads_asked', (select count(*) from s), 'unique_items', (select count(distinct old_item_id) from s),
    'replaced', (select count(*) from s where s.state = 'superseded'), 'refused', (select count(*) from s where s.state = 'refused'),
    'waiting', (select count(*) from s where s.state = 'requested'), 'repeats_on_unchanged_copy', (select count(*) from rep),
    'ai_cost_usd', (select round(coalesce(sum(s.cost_usd), 0), 4) from s),
    'holds_by_class', (select jsonb_object_agg(k, n) from (select coalesce(w.unresolved_blocker->>'class', w.failure_class) k, count(*) n from w where w.stage <> 'done' group by 1) z),
    'holds_without_next', (select count(*) from w where w.stage in ('parked', 'retry_wait', 'deferred', 'quarantined') and coalesce(w.unresolved_blocker->>'next_action', '') = ''),
    'duplicates', (select count(*) from w where w.failure_class = 'duplicate' and w.stage = 'parked'),
    'human', (select count(*) from w where w.stage = 'awaiting_review' or w.failure_class = 'aer_human_input'),
    'deterministic_parked', (select count(*) from w where w.failure_class in ('aer_row_limit', 'aer_unchanged_evidence') and w.stage = 'parked'),
    'eligible_for_a_read', (select count(*) from w where w.failure_class = 'aer_reread_eligible' and w.stage <> 'done'),
    'recovered', (select count(*) from w where w.recovered_at >= p_since),
    'review_ready_replacements', (select count(*) from s join pipeline.layer4_review_items n on n.id = s.new_item_id where n.status = 'pending'),
    'active_rows_gained', (select count(*) from catalogue.course_entry_requirements x where x.status = 'active' and x.updated_at >= p_since
                            and x.provenance->>'review_item_id' in (select s.new_item_id::text from s where s.new_item_id is not null)),
    'published_courses_gained', (select count(distinct x.course_id) from catalogue.course_entry_requirements x join search.course_documents d on d.course_id = x.course_id
                                  where x.status = 'active' and x.updated_at >= p_since and x.provenance->>'review_item_id' in (select s.new_item_id::text from s where s.new_item_id is not null)))
$function$;
revoke all on function security.aer_recovery_report_v1(timestamptz) from public, anon, authenticated;

-- 8 component register and post-check ---------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.aer_recovery_rule_v1', 'Platform', 'CF-247 AER: the shared recovery eligibility rule (mandate 16:32 §4-§5)', 'active', '{}', '20261104550000'),
 ('function', 'security.aer_recovery_report_v1', 'Platform', 'CF-247 AER: technical recovery measures as transitions (mandate 16:32 §6, §11)', 'active', '{}', '20261104550000')
on conflict do nothing;
do $p$
begin
  if (select count(*) from pipeline.work_recovery_policies where failure_class in ('aer_row_limit', 'aer_unchanged_evidence', 'aer_reread_eligible', 'aer_human_input', 'aer_stale')) <> 5 then
    raise exception 'post-check: the AER recovery policies are missing';
  end if;
  if exists (select 1 from pipeline.work_recovery_policies where failure_class in ('aer_row_limit', 'aer_unchanged_evidence') and (action <> 'park' or counts_attempt)) then
    raise exception 'post-check: a deterministic AER hold would be retried or counted as an attempt';
  end if;
end $p$;
