-- CF-247 Layer 4 action lifecycle, timestamps and acknowledgement (Platform Admin decision 4 Nov 2026 12:24, admin
-- docs/platform/ui-audit/2026-11-04-layer4-usability-action-lifecycle-decision-1224.md; first reproducible case IQ-00279).
-- Why (production, read-only, 4 Nov 2026 12:28-12:42 AEDT):
--   * RMIT Diploma of Commerce (review item a7849f66, pending since 29 Oct 12:44 AEDT): "Re-read from stored evidence" at 12:17:46 was recorded
--     (recovery action 1, admin_control_events 28863, corrected-read request d05725e2, job 8fb3173c, enrich item 270218); the reader refused it at
--     12:18:11 ("cut at the row limit (E13)": 9 requirements, limit 6) on stored copy a0ffab81, exactly as the scheduled job's request 3c06308a had
--     on 3 Nov 17:14. (a) The card showed no acknowledgement, state, time or result. (b) The recovery panel still offered and allowed the same read
--     on the unchanged copy, and a second click answered "its result is awaited" although the result was in.
--   * 94 of 106 corrected reads ever asked were refused; no reader or setting had changed between refusals of the same copy.
-- What (no second Layer 4 system, no new state table: the lifecycle is derived from the records that already exist):
--   1 security.layer4_item_lifecycle_v1(kind, ref) and security.layer4_items_lifecycle_v1(items): Requested -> Accepted or refused -> Scheduled ->
--     Executing -> Completed, failed or awaiting input -> Verified -> Resolved, from admin_control_events (inbox_decide), layer4_aer_recovery_actions,
--     aer_read_supersessions, field_enrich_items, work_items, layer4_interventions (and their events) and each kind's own source row; the decision's
--     §3 timestamps in Australian time (AEDT/AEST); the predecessor or successor of a corrected read; the five distinctions of §2 kept apart.
--     public.admin_layer4_lifecycle(args) is the screen's read (Curator and above, like the Inbox).
--   2 security.layer4_action_ack_v1: every reply of public.admin_layer4_inbox('decide') carries ack {outcome: accepted | refused | queued |
--     already_requested | completed | incomplete | human_input, ref, at, reason, alternative, next}. The card shows the same acknowledgement from the
--     persisted records after Refresh (the lifecycle's last_action uses the same normaliser on the audit row).
--   3 security.layer4_reread_repeat_v1(item): a corrected read of the same stored copy that the reader refused is a deterministic repeat until the
--     stored copy, the reader (layer4.reader_revision) or a setting it reads (layer4.reread_change_keys) changes. The recovery panel no longer
--     recommends or allows it and shows the refusal and the alternative; the decide function refuses it with the reason; a second click on the same
--     unchanged problem names the original action and its current state.
--   4 security.layer4_lifecycle_report_v1(): the §10 measures (entering and re-entering, waiting for a person or for technical recovery, actions
--     requested, refused and completed, automatic resumptions, verified admissions, consumer publication, repeated no-yield actions).
-- Edited live functions (md5-guarded, before -> after):
--   security.layer4_aer_recovery_detail_v1(text)                636c1764788b008fb7456365d600b452 -> dbf06336a7ee14fd0a84697d616cb67c
--   security.layer4_aer_recovery_decide_v1(text,text,text,text) 841234cb4826983b3297d39a34cb0978 -> f247220fd13231654f47877ecc72240e
--   public.admin_layer4_inbox(text,jsonb)                       29705b99108e7a0b4d68fea398565d36 -> c0a972a6d6cc0652ce2dcc8f4d9cbbfc
-- Replaces: security.layer4_aer_recovery_detail_v1(text) and security.layer4_aer_recovery_decide_v1(text,text,text,text) (same names and
--   signatures; the repeat guard and the readable last corrected read); public.admin_layer4_inbox (same name and actions; decide replies add ack)
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object changes (G3). No job, no Firecrawl or AI spend. Admission authority, spending limits,
-- manual locks, the E13 and D-R3 gates and role ranks are unchanged. Three indexes are added for the lifecycle's look-ups, and one column with its
-- trigger (pipeline.enrichment_flags.first_flagged_at) so Keep waiting no longer resets a hold's first entry.

-- 0 guards: the live definitions this change edits ---------------------------------------------------------------------------------------------
create or replace function pg_temp.guard(p_sig text, p_before text, p_after text) returns void language plpgsql as $f$
declare v text := md5(pg_get_functiondef(p_sig::regprocedure));
begin
  if v not in (p_before, p_after) then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, v; end if;
end $f$;
select pg_temp.guard('security.layer4_aer_recovery_detail_v1(text)', '636c1764788b008fb7456365d600b452', 'dbf06336a7ee14fd0a84697d616cb67c');
select pg_temp.guard('security.layer4_aer_recovery_decide_v1(text,text,text,text)', '841234cb4826983b3297d39a34cb0978', 'f247220fd13231654f47877ecc72240e');
select pg_temp.guard('public.admin_layer4_inbox(text,jsonb)', '29705b99108e7a0b4d68fea398565d36', 'c0a972a6d6cc0652ce2dcc8f4d9cbbfc');

-- 1 settings (G2; Settings › Pipeline settings, section Layer 4) --------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'layer4.lifecycle_history_max', 'Layer 4 lifecycle: actions shown on a card',
  'How many earlier actions (reviewer and automatic) a Layer 4 card lists under Progress, newest first.',
  'number', to_jsonb(8), 1, 50, 'actions', 334, 'Layer 4', 'security.layer4_lifecycle_one_v1; src/Layer4ItemLifecycle.jsx',
  'Platform Admin 4 Nov 2026 12:24 §6 (previous attempts on every card)'),
 ('pipeline', 'layer4.lifecycle_batch_max', 'Layer 4 lifecycle: cards read at once',
  'The most cards whose lifecycle one read returns (one page of the Inbox).',
  'number', to_jsonb(50), 5, 200, 'cards', 335, 'Layer 4', 'security.layer4_items_lifecycle_v1; public.admin_layer4_lifecycle',
  'Platform Admin 4 Nov 2026 12:24 §9 (production-scale performance)'),
 ('pipeline', 'layer4.reader_revision', 'Layer 4: entry reader revision',
  'Raised by one when the entry reader is corrected. A corrected read the reader refused on an unchanged stored copy is offered again only after this or a setting in "settings that change a read" changes.',
  'number', to_jsonb(1), 1, 100000, 'revision', 336, 'Layer 4', 'security.layer4_reread_repeat_v1',
  'Platform Admin 4 Nov 2026 12:24 §1 "Do not repeat an identical unsuccessful read"'),
 ('pipeline', 'layer4.reread_change_keys', 'Layer 4: settings that change a read',
  'Pipeline settings (patterns, % for any text) whose change since a refused corrected read means the same read may give a different result, so it is offered again.',
  'list', '["entry.%", "layer4.reader_revision"]'::jsonb, null, null, 'setting keys', 337, 'Layer 4', 'security.layer4_reread_repeat_v1',
  'Platform Admin 4 Nov 2026 12:24 §1 (a row limit or reader change is a real change)'),
 ('pipeline', 'layer4.reread_transient_refusals', 'Layer 4: refusals that may clear by themselves',
  'Refusal reasons (patterns) that depend on something else waiting, not on the stored copy, so the same read may be asked again.',
  'list', '["another read of this course waits%"]'::jsonb, null, null, 'reasons', 338, 'Layer 4', 'security.layer4_reread_repeat_v1',
  'Platform Admin 4 Nov 2026 12:24 §1 (only a deterministic repeat is refused)'),
 ('pipeline', 'layer4.lifecycle_report_days', 'Layer 4 lifecycle: report window',
  'The days the Layer 4 lifecycle measures cover (actions requested, refused and completed, resumptions, admissions, repeats).',
  'number', to_jsonb(7), 1, 90, 'days', 339, 'Layer 4', 'security.layer4_lifecycle_report_v1',
  'Platform Admin 4 Nov 2026 12:24 §10'),
 ('pipeline', 'layer4.lifecycle_poll_seconds', 'Layer 4 lifecycle: re-read a running recovery every',
  'While a card''s recovery is queued or running, the card reads its progress again this often, so it updates by itself when the recovery completes.',
  'number', to_jsonb(15), 5, 300, 'seconds', 340, 'Layer 4', 'security.layer4_lifecycle_one_v1; src/Layer4ItemLifecycle.jsx',
  'Platform Admin observation 4 Nov 2026 13:00 §5 (automatic state reconciliation)'),
 ('pipeline', 'layer4.lifecycle_poll_max', 'Layer 4 lifecycle: progress reads of one running recovery at most',
  'A card stops reading its progress by itself after this many reads; Refresh reads it again.',
  'number', to_jsonb(40), 1, 500, 'reads', 341, 'Layer 4', 'security.layer4_lifecycle_one_v1; src/Layer4ItemLifecycle.jsx',
  'Platform Admin observation 4 Nov 2026 13:00 §5 (bounded)')
on conflict do nothing;
-- a setting that has only been created has not changed: its first time is set before any corrected read existed, so creating
-- layer4.reader_revision and layer4.reread_change_keys here does not count as a reader change for earlier refusals
update pipeline.platform_toolset_settings set updated_at = '2026-10-01 00:00:00+10'  -- fixed: the creation is not a change
 where toolset_key = 'pipeline' and key in ('layer4.reader_revision', 'layer4.reread_change_keys', 'layer4.reread_transient_refusals') and updated_by is null and updated_at > '2026-11-04 12:00:00+11';

-- 2 indexes for the look-ups (the Inbox audit rows of one item; corrected reads of one item, either side) ---------------------------------------
create index if not exists admin_control_events_layer4_target_idx on pipeline.admin_control_events (target, id desc) where area = 'layer4';
create index if not exists aer_read_supersessions_old_item_idx on pipeline.aer_read_supersessions (old_item_id, requested_at desc);
create index if not exists aer_read_supersessions_new_item_idx on pipeline.aer_read_supersessions (new_item_id) where new_item_id is not null;

-- 2b a hold's first entry is kept (decision 12:24 §3 "do not reset an item's original age"): Keep waiting moves flagged_at forward (asked again
--    after the waiting period), which made the hold look new. A new column beside it keeps the first time; flagged_at keeps its meaning.
alter table pipeline.enrichment_flags add column if not exists first_flagged_at timestamptz;
comment on column pipeline.enrichment_flags.first_flagged_at is 'CF-247 (decision 4 Nov 2026 12:24 §3): when the hold was first raised; kept when flagged_at moves forward (Keep waiting, re-raise). Shown as "first entered Layer 4".';
create or replace function security.enrichment_flags_first_v1() returns trigger
language plpgsql set search_path to '' as $function$
begin
  new.first_flagged_at := case when tg_op = 'INSERT' then coalesce(new.first_flagged_at, new.flagged_at)
                               else coalesce(old.first_flagged_at, new.first_flagged_at, old.flagged_at, new.flagged_at) end;
  return new;
end $function$;
revoke all on function security.enrichment_flags_first_v1() from public, anon, authenticated;
do $t$
begin
  if not exists (select 1 from pg_trigger where tgname = 'enrichment_flags_first' and tgrelid = 'pipeline.enrichment_flags'::regclass) then
    create trigger enrichment_flags_first before insert or update on pipeline.enrichment_flags for each row execute function security.enrichment_flags_first_v1();
  end if;
end $t$;
-- the holds waiting now: the earlier of flagged_at and the first Layer 4 action on them (an earlier Keep waiting already moved some forward)
update pipeline.enrichment_flags f set first_flagged_at = least(f.flagged_at, e.first_at)
  from (select split_part(x.target, ':', 2) id, min(x.created_at) first_at from pipeline.admin_control_events x
         where x.area = 'layer4' and x.action = 'inbox_decide' and x.target ~ '^(pages_not_found|site_down|fee_check|not_offered|not_on_site):[0-9]+$' group by 1) e
 where f.state = 'raised' and f.first_flagged_at is null and f.id::text = e.id;
update pipeline.enrichment_flags f set first_flagged_at = f.flagged_at where f.state = 'raised' and f.first_flagged_at is null;

-- 3 helpers ----------------------------------------------------------------------------------------------------------------------------------
create or replace function security.l4_time_v1(p_at timestamptz) returns jsonb
language sql stable set search_path to ''
set timezone to 'Australia/Sydney'  -- fixed: the decision (§3) fixes Australian time, AEDT or AEST by date
as $function$
  -- a time for a Layer 4 card: the instant and its Australian reading, e.g. "Wed 4 Nov 2026, 12:17 pm AEDT"
  -- and a short one for acknowledgements, e.g. "12:17 AEDT" (observation 13:00 §3)
  select case when p_at is null then null else jsonb_build_object('at', p_at, 'text', to_char(p_at, 'Dy FMDD Mon YYYY, FMHH12:MI am TZ'), 'hm', to_char(p_at, 'HH24:MI TZ')) end
$function$;
revoke all on function security.l4_time_v1(timestamptz) from public, anon, authenticated;

create or replace function security.layer4_reread_repeat_v1(p_item uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 (decision 12:24 §1, §4; IQ-00279): is another corrected read of this held course read a deterministic repeat? Yes when the latest
-- corrected read of the item was refused by the reader, the refusal is not one that clears by itself (layer4.reread_transient_refusals), the
-- course's stored copy is the one that read used, and no setting that changes a read (layer4.reread_change_keys, incl. layer4.reader_revision)
-- has changed since the refusal. Read only.
declare s pipeline.aer_read_supersessions; v_used uuid; v_now uuid; v_cut timestamptz; v_changed jsonb; v_transient boolean; v_row boolean; v_by text;
        v_same int; v_rep boolean;
begin
  select * into s from pipeline.aer_read_supersessions x where x.old_item_id = p_item order by x.requested_at desc limit 1;
  if s.id is null then return jsonb_build_object('repeat', false, 'request', null); end if;
  select f.evidence_id into v_used from pipeline.field_enrich_items f where f.id = s.enrich_item_id;
  select g.evidence_id into v_now from pipeline.coverage_course_pages g where g.course_id = s.course_id;
  v_cut := coalesce(s.closed_at, s.requested_at);
  select coalesce(jsonb_agg(t.key order by t.key), '[]'::jsonb) into v_changed
    from pipeline.platform_toolset_settings t
   where t.toolset_key = 'pipeline' and t.updated_at > v_cut
     and exists (select 1 from jsonb_array_elements_text(coalesce((select w.value from pipeline.platform_toolset_settings w where w.toolset_key = 'pipeline' and w.key = 'layer4.reread_change_keys'),
                                                                 '["entry.%", "layer4.reader_revision"]'::jsonb)) k where t.key like k);
  v_transient := exists (select 1 from jsonb_array_elements_text(coalesce((select w.value from pipeline.platform_toolset_settings w where w.toolset_key = 'pipeline' and w.key = 'layer4.reread_transient_refusals'),
                                                                         '[]'::jsonb)) k where coalesce(s.outcome, '') ilike k);
  v_row := coalesce(s.outcome, '') ilike '%row limit%';
  v_by := case when exists (select 1 from pipeline.layer4_aer_recovery_actions a where a.review_item_id = p_item and a.result->>'request_id' = s.id::text) then 'a reviewer (Re-read from stored evidence)'
               when s.reason ilike 'Human input needed%' then 'Human input needed'
               when s.reason ilike 'Scheduled%' then 'the scheduled entry reading'
               else 'automatic recovery' end;
  select count(*) into v_same from pipeline.aer_read_supersessions x join pipeline.field_enrich_items f on f.id = x.enrich_item_id
   where x.old_item_id = p_item and x.state = 'refused' and f.evidence_id is not distinct from v_used;
  v_rep := s.state = 'refused' and not v_transient and v_used is not distinct from coalesce(v_now, v_used) and jsonb_array_length(v_changed) = 0;
  return jsonb_build_object('repeat', v_rep, 'request', s.id, 'state', s.state, 'outcome', s.outcome, 'requested_by', v_by,
    'requested', security.l4_time_v1(s.requested_at), 'closed', security.l4_time_v1(s.closed_at), 'job_id', s.job_id, 'enrich_item_id', s.enrich_item_id,
    'evidence_used', v_used, 'evidence_now', v_now, 'evidence_changed', v_used is distinct from coalesce(v_now, v_used), 'settings_changed', v_changed,
    'refused_on_this_copy', v_same, 'row_limit', v_row, 'new_item', s.new_item_id,
    'why', case when v_rep then 'the reader refused the corrected read of this stored copy at ' || coalesce(security.l4_time_v1(s.closed_at)->>'text', 'an earlier time')
                                || ' (' || coalesce(s.outcome, 'refused') || '; ' || v_same || ' refusal' || case when v_same = 1 then '' else 's' end
                                || ' on this copy). The copy, the reader and its settings have not changed since, so the same read would be refused again' end,
    'alternative', case when s.state <> 'refused' then null
                        when v_row then 'Open human input with the dropped requirements, or ask the Platform Admin for a row limit for this university (Settings › Pipeline settings, entry.max_rows_by_provider)'
                        else 'Open human input with the dropped requirements, or Request official evidence' end);
end $function$;
revoke all on function security.layer4_reread_repeat_v1(uuid) from public, anon, authenticated;

create or replace function security.layer4_recovery_headline_v1(p_state text, p_outcome text, p_at timestamptz) returns text
language sql stable set search_path to '' as $function$
  -- the Platform Admin's wording (observation 4 Nov 2026 13:00 §3) for one corrected read, from its record: queued, deferred, completed and still
  -- held under E13, completed with a replacement read, or completed and not used (with the reason)
  select case
    when p_state = 'requested' then 'Recovery queued — ' || (security.l4_time_v1(p_at)->>'hm')
    when p_state = 'superseded' then 'Recovery completed — replacement read ready for review'
    when p_state = 'refused' and coalesce(p_outcome, '') ~* '(daily (cap|limit)|limit reached|back-pressure|AI limits|budget)' and coalesce(p_outcome, '') !~* 'row limit'
      then 'Recovery deferred — ' || case when p_outcome ~* 'daily' then 'daily limit reached' else p_outcome end
    when p_state = 'refused' and coalesce(p_outcome, '') ~* '(E13|row limit|still drops|has no row|not entry requirements)' then 'Recovery completed — still held under E13'
    when p_state = 'refused' then 'Recovery completed — not used: ' || coalesce(p_outcome, 'refused')
    else null end
$function$;
revoke all on function security.layer4_recovery_headline_v1(text, text, timestamptz) from public, anon, authenticated;

create or replace function security.layer4_ack_normalise_v1(p_kind text, p_choice text, p_ok boolean, p_result jsonb, p_request text, p_outcome jsonb) returns jsonb
language sql immutable set search_path to '' as $function$
  -- the normalised result of one Layer 4 action, from the reply or from its audit row (p_ok null: read from the result):
  -- accepted | refused | deferred | queued | already_requested | completed | incomplete | human_input, with the reason and the permitted alternative
  with x as (select coalesce(p_result, '{}'::jsonb) r, coalesce(p_result->'detail', p_result, '{}'::jsonb) d),
       o as (select case
         when x.r ? 'repeat' or x.d ? 'repeat' then 'already_requested'
         when (x.d ? 'refused' or x.d ? 'held' or p_ok is false) and coalesce(p_request, x.d->>'refused', x.d->>'held', '') ~* '(daily (cap|limit)|limit reached|back-pressure|AI limits|budget)'
              and coalesce(p_request, x.d->>'refused', '') !~* 'row limit' then 'deferred'
         when p_ok is false and (x.d ? 'refused' or x.d ? 'held') then 'refused'
         when p_ok is null and (x.d ? 'refused' or x.d ? 'held') then 'refused'
         when p_kind = 'intervention' and coalesce(x.r->>'ok', '') = 'false' then 'incomplete'
         when p_ok is false then 'refused'
         when p_kind = 'intervention' and x.r->>'status' = 'resuming' then 'queued'
         when p_kind = 'intervention' and x.r->>'status' in ('not_published', 'returned_technical') then 'completed'
         when p_kind = 'intervention' then 'accepted'
         when nullif(x.r->>'intervention_id', '') is not null or (x.d ? 'raised' and nullif(x.d->>'id', '') is not null) then 'human_input'
         when x.d ? 'request_id' or x.d ? 'job_id' or x.d ? 'enrich_item_id' then 'queued'
         when p_choice = 'wait' or p_outcome->>'class' = 'deferred' then 'accepted'
         when p_outcome->>'class' in ('admitted', 'applied', 'reconciled') then 'completed'
         when p_outcome->>'class' = 'downstream' then 'queued'
         when p_choice in ('rebuild', 'retry', 'website', 'search_again', 'add_page') then 'queued'
         when p_choice in ('approve', 'approve_except', 'reject', 'keep', 'use', 'enter', 'refuse', 'publish', 'not_international', 'not_scholarship', 'duplicate',
                           'archive', 'archive_course', 'closed', 'merged', 'reviewed', 'report_fixed', 'report_not_changed', 'has_page', 'parent', 'no_page', 'cricos_only', 'release') then 'completed'
         else 'accepted' end k from x)
  select jsonb_build_object('outcome', o.k,
    'reason', coalesce(p_request, x.d->>'refused', x.d->>'held', case when o.k = 'already_requested' then 'already requested' end),
    'alternative', case when o.k in ('refused', 'deferred', 'already_requested', 'incomplete') then
                     case when p_kind = 'aer_review' then coalesce(x.d->>'alternative', 'Open human input with the dropped requirements, or Request official evidence')
                          when p_kind = 'intervention' then 'Correct the input as asked, or Return to technical recovery'
                          else 'Choose another permitted action, or leave the item pending with its reason' end end,
    'intervention_id', coalesce(x.r->'intervention_id', case when x.d ? 'raised' then x.d->'id' end))
    from x, o
$function$;
revoke all on function security.layer4_ack_normalise_v1(text, text, boolean, jsonb, text, jsonb) from public, anon, authenticated;

-- 4 the lifecycle of one item (§2, §3, §6) -----------------------------------------------------------------------------------------------------
create or replace function security.layer4_lifecycle_one_v1(p_kind text, p_ref text, p_full boolean) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 (decision 12:24 §2, §3, §6): what happened to one Layer 4 item and what happens next, derived from the existing records only (no state
-- table). p_full adds the admission and publication checks (one card opened, or a decided item). The five distinctions are separate fields:
-- requested, executed (the operation ran), valid (the extraction passed its gates), approved (the Layer 4 decision), admitted, published.
declare v_n int := security.pipeline_num_v1('layer4.lifecycle_history_max', 8)::int;
        r pipeline.layer4_review_items; s pipeline.aer_read_supersessions; f pipeline.field_enrich_items; w pipeline.work_items; iv pipeline.layer4_interventions;
        fl pipeline.enrichment_flags; ob pipeline.provider_onboarding; e record; v_hist jsonb := '[]'; v_last jsonb; v_rep jsonb; v_pred jsonb; v_succ jsonb;
        v_first timestamptz; v_created timestamptz; v_upd timestamptz; v_rev timestamptz; v_auto timestamptz; v_entered timestamptz; v_next timestamptz; v_next_text text;
        v_decided timestamptz; v_admitted timestamptz; v_published timestamptz; v_status text; v_stage text; v_why text; v_owner text; v_entries int := 1;
        v_requested text := 'no'; v_executed text := 'not applicable'; v_valid text := 'not applicable'; v_approved text := 'not yet'; v_adm text := 'not yet'; v_pub text := 'not yet';
        v_rows int; v_pid uuid; v_open boolean := true; v_first_ev timestamptz; v_att record; v_recovery jsonb; v_course uuid; v_poll jsonb;
begin
  -- the Inbox's own audit rows for the item (every reviewer action, accepted or refused), newest first
  for e in select x.id, x.created_at, x.actor, x.detail from pipeline.admin_control_events x
            where x.area = 'layer4' and x.target = p_kind || ':' || p_ref and x.action = 'inbox_decide' order by x.id desc limit v_n loop
    v_hist := v_hist || jsonb_build_array(jsonb_build_object('at', security.l4_time_v1(e.created_at), 'by', 'reviewer', 'action', e.detail->>'choice', 'ref', 'audit #' || e.id,
                'event_id', e.id, 'reason', e.detail->>'reason',
                'result', security.layer4_ack_normalise_v1(p_kind, e.detail->>'choice', null, e.detail->'result', null, null)
                          || jsonb_build_object('headline', security.layer4_ack_headline_v1(e.detail->>'choice',
                               security.layer4_ack_normalise_v1(p_kind, e.detail->>'choice', null, e.detail->'result', null, null),
                               coalesce(e.detail->'result'->'detail', e.detail->'result', '{}'::jsonb), e.created_at))));
    v_rev := greatest(v_rev, e.created_at);
  end loop;
  select min(x.created_at) into v_first_ev from pipeline.admin_control_events x where x.area = 'layer4' and x.target = p_kind || ':' || p_ref and x.action = 'inbox_decide';
  v_last := v_hist->0;
  if v_last is not null then v_requested := 'yes'; end if;

  if p_kind in ('course_link', 'aer_review', 'provider_description', 'no_page_first_run', 'conjoint_first_run') then
    select * into r from pipeline.layer4_review_items where id = p_ref::uuid;
    if r.id is null then return jsonb_build_object('kind', p_kind, 'ref', p_ref, 'found', false); end if;
    v_created := r.created_at; v_entered := r.created_at; v_status := r.status; v_decided := r.decided_at; v_open := r.status = 'pending';
    v_course := case when r.entity_type = 'course' then r.entity_id end;
    v_pid := coalesce((select c.provider_id from catalogue.courses c where c.id = v_course), case when r.entity_type = 'provider' then r.entity_id end);
    v_approved := case when r.status in ('approved', 'edited_approved') then 'yes' when r.status = 'pending' then 'not yet' else 'no (' || r.status || ')' end;
    -- first entered Layer 4: the earliest item of the same record and field, and up the chain of corrected reads (never reset by a re-read)
    select min(x.created_at), count(*) into v_first, v_entries from pipeline.layer4_review_items x where x.entity_id = r.entity_id and x.field_code = r.field_code;
    v_first := least(v_first, (with recursive ch(id, d) as (select r.id, 0 union all
                                  select s2.old_item_id, ch.d + 1 from ch join pipeline.aer_read_supersessions s2 on s2.new_item_id = ch.id where ch.d < 50)  -- fixed: cycle guard
                               select min(x.created_at) from ch join pipeline.layer4_review_items x on x.id = ch.id));
    select jsonb_build_object('ref', x.old_item_id, 'relation', 'this read replaced it (superseded)', 'at', security.l4_time_v1(x.closed_at), 'request', x.id)
      into v_pred from pipeline.aer_read_supersessions x where x.new_item_id = r.id order by x.requested_at desc limit 1;
    if r.field_code = 'course_entry_first_read' then
      v_executed := 'not asked'; v_valid := 'not asked';
      -- corrected reads asked for this item (the reviewer's, the scheduled job's and recovery's)
      -- observation 13:00 §2: each corrected read with its attempt number, operation (request and enrich item), reader times, the original and
      -- replacement reads and when the replacement entered Layer 4
      for v_att in select x.*, row_number() over (order by x.requested_at) n, f2.created_at f_start, f2.updated_at f_end, f2.state f_state, f2.reason f_reason,
                          f2.evidence_id f_ev, f2.cost_usd f_cost, nr.created_at new_at
                     from pipeline.aer_read_supersessions x left join pipeline.field_enrich_items f2 on f2.id = x.enrich_item_id
                     left join pipeline.layer4_review_items nr on nr.id = x.new_item_id
                    where x.old_item_id = r.id order by x.requested_at desc limit v_n loop
        v_hist := v_hist || jsonb_build_array(jsonb_build_object('at', security.l4_time_v1(v_att.requested_at),
                    'by', case when v_att.reason ilike 'Layer 4 recovery%' then 'reviewer' when v_att.reason ilike 'Human input needed%' then 'human input' else 'automatic' end,
                    'action', 'corrected read', 'attempt', v_att.n, 'ref', 'request ' || left(v_att.id::text, 8), 'reason', v_att.reason,
                    'operation', jsonb_build_object('request', v_att.id, 'enrich_item', v_att.enrich_item_id, 'job', v_att.job_id),
                    'reader', jsonb_strip_nulls(jsonb_build_object('started', security.l4_time_v1(v_att.f_start),
                                'completed', case when v_att.state <> 'requested' then security.l4_time_v1(coalesce(v_att.closed_at, v_att.f_end)) end,
                                'state', v_att.f_state, 'detail', v_att.f_reason, 'stored_copy', v_att.f_ev, 'cost_usd', v_att.f_cost)),
                    'original_read', v_att.old_item_id, 'replacement_read', v_att.new_item_id, 're_entered', security.l4_time_v1(v_att.new_at),
                    'result', jsonb_build_object('outcome', case v_att.state when 'requested' then 'queued' when 'superseded' then 'completed' else 'failed' end,
                                                 'headline', security.layer4_recovery_headline_v1(v_att.state, v_att.outcome, v_att.requested_at),
                                                 'reason', coalesce(v_att.outcome, case v_att.state when 'superseded' then 'complete: a new read replaced this one' else 'waiting for the reader' end),
                                                 'at', security.l4_time_v1(v_att.closed_at))));
        if v_recovery is null then v_recovery := v_hist->-1; end if;
        if v_att.reason not ilike 'Layer 4 recovery%' then v_auto := greatest(v_auto, v_att.requested_at, v_att.closed_at); end if;
        v_upd := greatest(v_upd, v_att.requested_at, v_att.closed_at);
      end loop;
      select * into s from pipeline.aer_read_supersessions x where x.old_item_id = r.id order by x.requested_at desc limit 1;
      if s.id is not null then
        v_requested := 'yes';
        select * into f from pipeline.field_enrich_items x where x.id = s.enrich_item_id;
        v_executed := case when s.state <> 'requested' then 'yes, ' || coalesce(security.l4_time_v1(s.closed_at)->>'text', '') when f.state in ('leased', 'ai') then 'running' else 'waiting for the reader' end;
        v_valid := case s.state when 'superseded' then 'yes (complete)' when 'refused' then 'no: ' || coalesce(s.outcome, 'refused') else 'not yet' end;
        v_stage := case when s.state = 'requested' and f.state in ('leased', 'ai') then 'executing' when s.state = 'requested' then 'scheduled'
                        when s.state = 'refused' then 'failed' else 'completed' end;
        if s.state = 'superseded' then
          v_succ := (select jsonb_build_object('ref', s.new_item_id, 'relation', 'replaced by a corrected read', 'status', x.status, 'at', security.l4_time_v1(s.closed_at),
                                               're_entered', security.l4_time_v1(x.created_at),
                                               'complete', case when p_full then (security.course_entry_gate_v1(x.id, '{}'::uuid[])->>'complete')::boolean end)
                       from pipeline.layer4_review_items x where x.id = s.new_item_id);
        end if;
      end if;
      v_rep := security.layer4_reread_repeat_v1(r.id);
      select * into w from pipeline.work_items x where x.lane = 'aer_technical' and x.entity = p_ref and x.work_kind = 'l4_item';
      if w.id is not null then
        v_auto := greatest(v_auto, w.last_attempt_at); v_upd := greatest(v_upd, w.updated_at); v_next := w.next_eligible_at;
        if w.next_eligible_at is not null and w.next_eligible_at > now() then v_next_text := 'technical recovery tries again (' || coalesce(w.failure_class, w.stage) || ')'; end if;
      end if;
      select * into iv from pipeline.layer4_interventions x where x.lane = 'aer_item' and x.entity = p_ref and x.status in ('ai_pending', 'awaiting_input', 'resuming')
       order by x.id desc limit 1;
      if iv.id is null then
        select i.* into iv from pipeline.layer4_aer_recovery_actions a join pipeline.layer4_interventions i on i.id = a.intervention_id
         where a.review_item_id = r.id and i.status in ('ai_pending', 'awaiting_input', 'resuming') order by a.id desc limit 1;
      end if;
      if (p_full or not v_open) then
        select count(*), max(x.updated_at) into v_rows, v_admitted from catalogue.course_entry_requirements x
         where x.course_id = r.entity_id and x.provenance->>'review_item_id' = r.id::text and x.status = 'active';
        v_adm := case when v_rows > 0 then 'yes: ' || v_rows || ' row' || case when v_rows = 1 then '' else 's' end || ' active' when v_open then 'not yet' else 'no row active' end;
        select c.provider_id into v_pid from catalogue.courses c where c.id = r.entity_id;
        if v_rows > 0 and exists (select 1 from catalogue.courses c join catalogue.providers p on p.id = c.provider_id
                                    where c.id = r.entity_id and c.lifecycle_status = 'active' and p.publication_status = 'published') then
          v_pub := 'yes: course and university published'; v_published := v_admitted;
        elsif v_rows > 0 then v_pub := 'no: the course or its university is not published';
        end if;
      end if;
    elsif r.field_code in ('entry_matrix_first_run', 'entry_matrix_change') then
      select x.updated_at into v_auto from pipeline.entry_matrix_runs x where x.review_item_id = r.id order by x.created_at desc limit 1;
    elsif p_kind = 'course_link' and not v_open then
      v_adm := case when exists (select 1 from catalogue.course_links l where l.course_id = r.entity_id and l.link_type = 'official_course' and l.status = 'active')
                    then 'yes: the course''s official page is active' else 'no active official page' end;
    end if;
  elsif p_kind = 'held_scholarship' then
    for e in select x.created_at, x.status, x.decided_at, s2.publication_status from pipeline.scholarship_ai_reviews x left join scholarship.scholarships s2 on s2.id = x.scholarship_id
              where x.id = p_ref::bigint loop
      v_created := e.created_at; v_first := e.created_at; v_entered := e.created_at; v_status := e.status; v_decided := e.decided_at; v_open := e.status = 'pending';
      v_approved := case when e.status = 'pending' then 'not yet' else e.status end;
      v_pub := case when e.publication_status = 'published' then 'yes' when v_open then 'not yet' else 'no (' || coalesce(e.publication_status, 'no scholarship') || ')' end;
    end loop;
  elsif p_kind in ('website_needed', 'too_few_pages', 'nothing_ready', 'central_to_approve', 'onboarding_failed') then
    select * into ob from pipeline.provider_onboarding x where x.id = p_ref::uuid;
    v_created := ob.created_at; v_entered := ob.updated_at; v_status := ob.status; v_pid := ob.provider_id; v_auto := ob.updated_at; v_open := ob.status = 'stopped';
    select min(x.created_at), count(*) into v_first, v_entries from pipeline.provider_onboarding x where x.provider_id = ob.provider_id and x.status = 'stopped' and x.stop_reason = ob.stop_reason;
    -- what the decision started: the university's newer onboarding run
    for e in select x.id, x.status, x.created_at, x.updated_at, x.stop_reason from pipeline.provider_onboarding x
              where x.provider_id = ob.provider_id and x.created_at > ob.created_at order by x.created_at desc limit 1 loop
      v_stage := case when e.status = 'stopped' then 'failed' when e.status in ('done', 'completed', 'finished') then 'completed' else 'executing' end;
      v_auto := greatest(v_auto, e.updated_at); v_executed := e.status;
      v_why := case when e.status = 'stopped' then 'The new onboarding run stopped again: ' || coalesce(e.stop_reason, 'unknown') end;
    end loop;
  elsif p_kind in ('pages_not_found', 'site_down', 'fee_check', 'not_offered', 'not_on_site') then
    select * into fl from pipeline.enrichment_flags x where x.id = p_ref::bigint;
    -- Keep waiting moves flagged_at forward (asked again later); the first entry is the earliest of it and the first action on the item
    v_created := fl.flagged_at; v_entered := fl.flagged_at; v_status := fl.state; v_decided := fl.released_at; v_open := fl.state = 'raised';
    v_first := least(coalesce(fl.first_flagged_at, fl.flagged_at), v_first_ev); v_next := fl.next_check_at; v_auto := fl.updated_at; v_pid := fl.provider_id;
    if v_open and fl.next_check_at is not null then v_next_text := 'checked again automatically'; end if;
    if p_kind = 'site_down' and v_open then v_next_text := 'the site is checked again automatically; asked again after the waiting period'; end if;
  elsif p_kind = 'course_page_needed' then
    for e in select * from pipeline.course_page_needed x where x.course_id = p_ref::uuid loop
      v_created := e.created_at; v_first := e.created_at; v_entered := coalesce(e.last_refused_at, e.created_at); v_status := e.state; v_decided := e.decided_at;
      v_open := e.state = 'open'; v_auto := e.last_refused_at; v_upd := e.updated_at; v_pid := e.provider_id;
      if e.searches_requested > 0 and v_open then v_stage := 'scheduled'; v_next_text := 'the course-link search looks for the page again'; end if;
    end loop;
  elsif p_kind = 'counsellor_report' then
    for e in select * from pipeline.data_flags x where x.id = p_ref::uuid loop
      v_created := e.created_at; v_first := e.created_at; v_entered := e.created_at; v_status := e.status; v_decided := e.resolved_at; v_open := e.status = 'open';
    end loop;
  elsif p_kind = 'provider_departure' then
    for e in select * from pipeline.layer1_provider_departures x where x.id = p_ref::bigint loop
      v_created := e.created_at; v_first := e.created_at; v_entered := e.created_at; v_status := e.status; v_decided := e.reviewed_at; v_open := e.status = 'needs_review';
    end loop;
  elsif p_kind = 'intervention' then
    select * into iv from pipeline.layer4_interventions x where x.id = p_ref::bigint;
    v_created := iv.created_at; v_first := iv.created_at; v_entered := iv.created_at; v_status := iv.status; v_decided := iv.input_at; v_upd := iv.updated_at;
    v_open := iv.status in ('ai_pending', 'awaiting_input', 'resuming'); v_admitted := iv.admitted_at; v_published := iv.published_at;
    v_adm := case when iv.admitted_at is not null then 'yes' when v_open then 'not yet' else 'no' end;
    v_pub := case when iv.published_at is not null then 'yes' when v_open then 'not yet' else 'no' end;
    v_executed := case when iv.resumed_at is not null then 'yes, resumed' else 'not yet' end;
    v_valid := case when iv.verified_at is not null then 'yes: ' || coalesce(iv.verified_outcome, 'verified') else 'not yet' end;
    for e in select x.at, x.actor, x.action, x.status_before, x.status_after, x.result from pipeline.layer4_intervention_events x
              where x.intervention_id = iv.id and x.actor is null order by x.id desc limit v_n loop
      v_hist := v_hist || jsonb_build_array(jsonb_build_object('at', security.l4_time_v1(e.at), 'by', 'automatic', 'action', e.action,
                  'result', jsonb_build_object('outcome', coalesce(e.status_after, 'recorded'), 'reason', coalesce(e.result->>'request', e.result->>'state', e.result->>'reason'))));
      v_auto := greatest(v_auto, e.at);
    end loop;
  else
    return jsonb_build_object('kind', p_kind, 'ref', p_ref, 'found', false);
  end if;

  -- where the item stands (the shared lifecycle)
  if iv.id is not null and (p_kind = 'intervention' or v_open) and iv.status in ('ai_pending', 'awaiting_input', 'resuming') then
    v_stage := case iv.status when 'awaiting_input' then 'awaiting_input' else 'executing' end;
    v_owner := iv.assigned_to; v_next := coalesce(iv.next_action_at, v_next);
    v_next_text := case iv.status when 'awaiting_input' then 'Human input needed item ' || iv.id || ' waits for a person; the work resumes by itself when the input checks out'
                                  when 'ai_pending' then 'the stronger model analyses the failure once, then a person is asked'
                                  else 'the work resumes and is verified automatically' end;
  elsif p_kind = 'intervention' then
    v_stage := case when iv.verified_at is not null then 'verified' else 'resolved' end;
  end if;
  if not v_open then
    v_stage := case when v_status = 'superseded' then 'superseded' when v_stage in ('verified') then v_stage else 'resolved' end;
  elsif v_stage is null then
    v_stage := case v_last->'result'->>'outcome' when 'refused' then 'refused' when 'queued' then 'scheduled' when 'human_input' then 'awaiting_input'
                    when 'completed' then 'completed' when 'accepted' then 'accepted' when 'incomplete' then 'awaiting_input' else 'awaiting_decision' end;
  end if;
  v_why := coalesce(v_why, case
    when not v_open then null
    when v_stage = 'failed' and s.id is not null then 'The last corrected read was refused by the reader: ' || coalesce(s.outcome, 'refused') || '. The original read stays pending'
    when v_stage = 'awaiting_input' then 'Waiting for human input' || coalesce(' (item ' || iv.id || ')', '')
    when v_stage in ('scheduled', 'executing') then 'Waiting for the operation that was asked for'
    when v_stage = 'refused' then 'The last action was refused: ' || coalesce(v_last->'result'->>'reason', 'see the reason')
    else 'No reviewer action yet' end);
  if coalesce((v_rep->>'repeat')::boolean, false) and v_open then v_next_text := v_rep->>'alternative'; v_next := null; end if;
  if v_open and v_next_text is null then
    v_next := null;
    v_next_text := case
      when v_stage = 'scheduled' and s.id is not null then 'the entry reader reads the stored copy (job ' || left(s.job_id::text, 8) || ')'
      when v_stage = 'executing' then 'running now'
      when v_last->'result'->>'alternative' is not null and v_stage in ('refused', 'awaiting_input') then v_last->'result'->>'alternative'
      else 'a reviewer decides' end;
  end if;
  v_owner := coalesce(v_owner, case when v_stage in ('scheduled', 'executing') then 'the platform (automatic)' when v_open then 'Layer 4 reviewer' end);
  v_upd := greatest(v_upd, v_created, v_rev, v_auto, v_decided, v_entered);
  if v_open and v_stage in ('scheduled', 'executing') then
    v_poll := jsonb_build_object('every_seconds', security.pipeline_num_v1('layer4.lifecycle_poll_seconds', 15), 'max', security.pipeline_num_v1('layer4.lifecycle_poll_max', 40));
  end if;
  return jsonb_build_object('kind', p_kind, 'ref', p_ref, 'found', true, 'status', v_status, 'open', v_open, 'provider_id', v_pid, 'course_id', v_course,
    'recovery', v_recovery, 'poll', v_poll,
    'waiting', case when v_open then jsonb_build_object('hours', round(extract(epoch from now() - coalesce(v_first, v_created)) / 3600, 1),
                     'text', case when now() - coalesce(v_first, v_created) >= make_interval(days => 1)
                                  then extract(day from now() - coalesce(v_first, v_created))::int || ' d ' || extract(hour from now() - coalesce(v_first, v_created))::int || ' h'
                                  else extract(hour from now() - coalesce(v_first, v_created))::int || ' h ' || extract(minute from now() - coalesce(v_first, v_created))::int || ' min' end) end,
    'stage', v_stage,
    'stage_label', case v_stage when 'awaiting_decision' then 'Waiting for a reviewer' when 'accepted' then 'Accepted' when 'refused' then 'Refused'
                     when 'scheduled' then 'Scheduled' when 'executing' then 'Running' when 'completed' then 'Completed' when 'failed' then 'Failed: still pending'
                     when 'awaiting_input' then 'Waiting for human input' when 'verified' then 'Verified' when 'superseded' then 'Superseded' else 'Resolved' end,
    'why_pending', v_why, 'owner', v_owner,
    'next', case when v_open then jsonb_build_object('text', v_next_text, 'at', security.l4_time_v1(v_next)) end,
    'times', jsonb_strip_nulls(jsonb_build_object('first_entered', security.l4_time_v1(coalesce(v_first, v_created)), 'item_created', security.l4_time_v1(v_created),
      'last_updated', security.l4_time_v1(v_upd), 'last_reviewer_action', security.l4_time_v1(v_rev), 'last_automated_attempt', security.l4_time_v1(v_auto),
      'last_entered', security.l4_time_v1(v_entered), 'next_action', security.l4_time_v1(case when v_open then v_next end), 'decided', security.l4_time_v1(v_decided),
      'admitted', security.l4_time_v1(v_admitted), 'published', security.l4_time_v1(v_published))),
    'entries', v_entries,
    'steps', jsonb_build_object('requested', v_requested, 'executed', v_executed, 'valid', v_valid, 'approved', v_approved, 'admitted', v_adm, 'published', v_pub),
    'predecessor', v_pred, 'successor', v_succ,
    'repeat_guard', case when coalesce((v_rep->>'repeat')::boolean, false) then jsonb_build_object('action', 'reread_stored', 'why', v_rep->>'why', 'alternative', v_rep->>'alternative') end,
    'last_action', v_last,
    'history', (select coalesce(jsonb_agg(h order by (h->'at'->>'at')::timestamptz desc), '[]'::jsonb) from (select h from jsonb_array_elements(v_hist) h order by (h->'at'->>'at')::timestamptz desc limit v_n) z));
end $function$;
revoke all on function security.layer4_lifecycle_one_v1(text, text, boolean) from public, anon, authenticated;

create or replace function security.layer4_item_lifecycle_v1(p_kind text, p_ref text) returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- one card, with its admission and publication checks (decision 12:24 §2)
  select security.layer4_lifecycle_one_v1(p_kind, p_ref, true)
$function$;
revoke all on function security.layer4_item_lifecycle_v1(text, text) from public, anon, authenticated;

create or replace function security.layer4_items_lifecycle_v1(p_items jsonb) returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- one page of cards ([{kind, ref}]), keyed 'kind:ref'; at most layer4.lifecycle_batch_max
  select coalesce(jsonb_object_agg(z.kind || ':' || z.ref, security.layer4_lifecycle_one_v1(z.kind, z.ref, false)), '{}'::jsonb)
    from (select distinct x->>'kind' kind, x->>'ref' ref from jsonb_array_elements(case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end) x
           where x ? 'kind' and x ? 'ref' limit security.pipeline_num_v1('layer4.lifecycle_batch_max', 50)::int) z
$function$;
revoke all on function security.layer4_items_lifecycle_v1(jsonb) from public, anon, authenticated;

create or replace function security.layer4_ack_headline_v1(p_choice text, p_n jsonb, p_d jsonb, p_at timestamptz) returns text
language sql stable set search_path to '' as $function$
  -- observation 4 Nov 2026 13:00 §3: the Platform Admin's wording for one action, chosen from what the server did (never before it confirmed
  -- it); the same words on the reply (security.layer4_action_ack_v1) and, after Refresh, on the card (security.layer4_lifecycle_one_v1)
  with z as (select security.l4_time_v1(p_at)->>'hm' v_hm)
  select case
    when p_n->>'outcome' = 'already_requested' and p_d ? 'existing' then 'Already queued — existing request retained'
    when p_n->>'outcome' in ('refused', 'already_requested') and (p_d ? 'repeat_of' or coalesce((p_d->>'unchanged')::boolean, false)) then 'Recovery refused — unchanged evidence and reader'
    when p_n->>'outcome' = 'deferred' then 'Recovery deferred — ' || case when coalesce(p_n->>'reason', '') ~* 'daily' then 'daily limit reached' else coalesce(p_n->>'reason', 'a limit is reached') end
    when p_n->>'outcome' = 'queued' and p_choice = 'reread_stored' then 'Recovery queued — ' || v_hm
    when p_n->>'outcome' = 'already_requested' then 'Already requested — ' || coalesce(p_d->>'current_state', 'recorded')
    when p_n->>'outcome' = 'human_input' then 'Human input needed' || coalesce(' — item ' || (p_n->>'intervention_id'), '') || ' — ' || v_hm
    when p_n->>'outcome' = 'queued' then 'Queued — ' || v_hm
    when p_n->>'outcome' = 'completed' then 'Done — ' || v_hm
    when p_n->>'outcome' = 'refused' then 'Refused — ' || coalesce(p_n->>'reason', 'see the reason')
    when p_n->>'outcome' = 'incomplete' then 'Still incomplete — ' || coalesce(p_n->>'reason', 'more input is needed')
    else 'Accepted — ' || v_hm end
    from z
$function$;
revoke all on function security.layer4_ack_headline_v1(text, jsonb, jsonb, timestamptz) from public, anon, authenticated;

-- 5 the acknowledgement on every decision (§4) ----------------------------------------------------------------------------------------------------
create or replace function security.layer4_action_ack_v1(p_kind text, p_ref text, p_reply jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
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
end $function$;
revoke all on function security.layer4_action_ack_v1(text, text, jsonb) from public, anon, authenticated;

-- 6 the screen's read ---------------------------------------------------------------------------------------------------------------------------
create or replace function public.admin_layer4_lifecycle(p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- Layer 4 › Inbox and Review cards: the lifecycle of the cards on screen ({items: [{kind, ref}]}) or of one card ({kind, ref}); Curator and above
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_args ? 'items' then return jsonb_build_object('items', security.layer4_items_lifecycle_v1(p_args->'items')); end if;
  if p_args ? 'kind' and p_args ? 'ref' then return security.layer4_item_lifecycle_v1(p_args->>'kind', p_args->>'ref'); end if;
  if p_args->>'report' = 'true' then return security.layer4_lifecycle_report_v1(); end if;
  raise exception 'give items, or kind and ref';
end $function$;
revoke all on function public.admin_layer4_lifecycle(jsonb) from public, anon;
grant execute on function public.admin_layer4_lifecycle(jsonb) to authenticated;

-- 7 the measures (§10) ------------------------------------------------------------------------------------------------------------------------
create or replace function security.layer4_lifecycle_report_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- CF-247 (decision 12:24 §10): Layer 4 lifecycle measures over layer4.lifecycle_report_days, from the existing records
  with p as (select make_interval(days => security.pipeline_num_v1('layer4.lifecycle_report_days', 7)::int) d),
       ev as (select x.detail->>'kind' kind, security.layer4_ack_normalise_v1(x.detail->>'kind', x.detail->>'choice', null, x.detail->'result', null, null)->>'outcome' o
                from pipeline.admin_control_events x, p where x.area = 'layer4' and x.action = 'inbox_decide' and x.created_at > now() - p.d),
       ri as (select x.id, x.status, x.created_at, x.entity_id, x.field_code from pipeline.layer4_review_items x, p where x.created_at > now() - p.d),
       sup as (select x.*, f.evidence_id ev from pipeline.aer_read_supersessions x left join pipeline.field_enrich_items f on f.id = x.enrich_item_id, p where x.requested_at > now() - p.d)
  select jsonb_build_object('days', security.pipeline_num_v1('layer4.lifecycle_report_days', 7),
    'entered', (select count(*) from ri),
    're_entered', (select count(*) from ri where exists (select 1 from pipeline.layer4_review_items y where y.entity_id = ri.entity_id and y.field_code = ri.field_code and y.created_at < ri.created_at)),
    'waiting_human_hours', (select round(avg(extract(epoch from now() - x.created_at)) / 3600, 1) from pipeline.layer4_review_items x where x.status = 'pending'
                              and not exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = x.id and s.state = 'requested')),
    'waiting_technical', (select count(*) from pipeline.aer_read_supersessions s where s.state = 'requested'),
    'interventions_waiting', (select count(*) from pipeline.layer4_interventions i where i.status = 'awaiting_input'),
    'actions', (select coalesce(jsonb_object_agg(o, n), '{}'::jsonb) from (select o, count(*) n from ev group by 1) z),
    'actions_by_kind', (select coalesce(jsonb_object_agg(kind, n), '{}'::jsonb) from (select kind, count(*) n from ev group by 1) z),
    'automatic_resumptions', (select count(*) from pipeline.layer4_interventions i, p where i.resumed_at > now() - p.d),
    'corrected_reads', jsonb_build_object('asked', (select count(*) from sup), 'superseded', (select count(*) from sup where state = 'superseded'),
                                           'refused', (select count(*) from sup where state = 'refused'),
                                           'repeated_no_yield', (select count(*) from sup where state = 'refused' and exists (
                                              select 1 from pipeline.aer_read_supersessions y join pipeline.field_enrich_items g on g.id = y.enrich_item_id
                                               where y.old_item_id = sup.old_item_id and y.state = 'refused' and y.requested_at < sup.requested_at and g.evidence_id is not distinct from sup.ev))),
    'verified_admissions', (select count(*) from ri where ri.status in ('approved', 'edited_approved')),
    'interventions_admitted', (select count(*) from pipeline.layer4_interventions i, p where i.admitted_at > now() - p.d),
    'interventions_published', (select count(*) from pipeline.layer4_interventions i, p where i.published_at > now() - p.d))
$function$;
revoke all on function security.layer4_lifecycle_report_v1() from public, anon, authenticated;

-- 8 the recovery panel: no deterministic repeat, and the last corrected read readable (§1, §4; owner of this function for this change) -----------
create or replace function security.layer4_aer_recovery_detail_v1(p_ref text) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- the recovery state on an E13 or D-R3 card (decision 06:58 §3; paging contract §2a, shape {sections, actions}): the gate's counts and reasons,
-- the recommended recovery, whether a person is needed, the owner, the next automatic attempt, the last attempt and its status, and the case
-- the read belongs to (other held reads of the same university failing the same way). The E13 facts themselves stay on the built-in card.
-- CF-247 action lifecycle (decision 12:24 §1, §4; IQ-00279): a corrected read of the same stored copy that the reader refused is neither
-- recommended nor allowed until the copy, the reader or a setting it reads changes (security.layer4_reread_repeat_v1); the card shows that
-- refusal and the alternative, and the last corrected read in Australian time.
declare st jsonb := security.layer4_aer_recovery_state_v1(p_ref::uuid); v_last record; v_iv pipeline.layer4_interventions; v_rec text; v_case jsonb; v_ai boolean;
        v_busy text; v_rep jsonb; v_repeat boolean;
begin
  if st is null then return jsonb_build_object('sections', '[]'::jsonb, 'actions', '[]'::jsonb); end if;
  select * into v_last from pipeline.layer4_aer_recovery_actions a where a.review_item_id = p_ref::uuid order by a.id desc limit 1;
  select * into v_iv from pipeline.layer4_interventions i where i.lane = 'aer_item' and i.status in ('ai_pending', 'awaiting_input', 'resuming')
     and (i.entity = p_ref or i.entity = (st->>'provider_id') || '|case:' || (st->>'case_key')) order by i.id desc limit 1;
  v_ai := security.pipeline_num_v1('har.ai_escalate_on', 0) >= 1 and security.pipeline_num_v1('ops.ai_diagnosis_on', 0) >= 1 and security.har_text_v1('har.ai_escalation_model', '') <> '';
  v_busy := case when st->'corrected_read'->>'state' = 'requested' then 'a corrected read of this item is already asked for'
                 when exists (select 1 from pipeline.field_enrich_items f where f.course_id = (st->>'course_id')::uuid and f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased'))
                   then 'a read of this course is in progress' end;
  v_rep := case when st->>'field_code' = 'course_entry_first_read' then security.layer4_reread_repeat_v1(p_ref::uuid) else jsonb_build_object('repeat', false) end;
  v_repeat := coalesce((v_rep->>'repeat')::boolean, false);
  v_rec := case when (st->>'complete')::boolean then 'none: the read is complete'
                when v_iv.id is not null then 'answer the open Human input needed item (ref ' || v_iv.id || ')'
                when v_busy is not null then 'wait: ' || v_busy
                when v_repeat then 'open_intervention'
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
        'Recommended recovery', v_rec, 'Or decide', case when v_repeat and (v_rep->>'row_limit')::boolean then 'a row limit for this university (Platform Admin, entry.max_rows_by_provider)' end,
        'Human input needed', case when v_rec in ('open_intervention', 'request_evidence') or v_iv.id is not null then 'yes' else 'not yet' end,
        'Owner', case when v_iv.id is not null then v_iv.assigned_to when v_rec = 'reread_stored' then 'the entry reader (automatic)' else 'Layer 4 reviewer' end,
        'Next automatic attempt', case when v_busy is not null then 'the requested read' when v_iv.id is not null then coalesce(security.l4_time_v1(v_iv.next_action_at)->>'text', 'when the input is given') else 'none until a recovery is chosen' end,
        'Last attempt', case when v_last.id is not null then v_last.choice || ' at ' || (security.l4_time_v1(v_last.at)->>'text') || ': ' || coalesce(v_last.next_operation, '') end,
        'Last attempt status', coalesce(st->'corrected_read'->>'state', v_last.work_item_status)))),
      jsonb_build_object('key', 'corrected_read', 'title', 'Last corrected read', 'body', jsonb_strip_nulls(jsonb_build_object(
        'Requested', v_rep->'requested'->>'text', 'Requested by', v_rep->>'requested_by', 'Reader result', case v_rep->>'state' when 'requested' then 'waiting for the reader'
                                                                                                            when 'superseded' then 'complete: a new read replaced this one' else v_rep->>'outcome' end,
        'Result at', v_rep->'closed'->>'text', 'Stored copy read', v_rep->>'evidence_used', 'Refusals on this copy', v_rep->'refused_on_this_copy',
        'Same read again', case when v_repeat then 'not offered: ' || (v_rep->>'why') end, 'Instead', case when v_repeat then v_rep->>'alternative' end))),
      jsonb_build_object('key', 'case', 'title', 'Recovery case', 'body', jsonb_build_object('Case', st->>'case_label', 'Other waiting reads of this university and kind', v_case))),
    'actions', jsonb_build_array(
      jsonb_build_object('key', 'reread_stored', 'allowed', v_busy is null and not (st->>'complete')::boolean and not v_repeat,
                         'why', coalesce(v_busy, case when v_repeat then (v_rep->>'why') || '. ' || (v_rep->>'alternative') end)),
      jsonb_build_object('key', 'request_evidence', 'allowed', v_iv.id is null, 'why', case when v_iv.id is not null then 'a Human input needed item is already open (ref ' || v_iv.id || ')' end),
      jsonb_build_object('key', 'ai_analyse', 'allowed', v_ai and v_iv.id is null,
                         'why', case when not v_ai then 'the stronger-model step is off (har.ai_escalate_on, ops.ai_diagnosis_on or no pinned model)'
                                     when v_iv.id is not null then 'a Human input needed item is already open (ref ' || v_iv.id || ')' end),
      jsonb_build_object('key', 'open_intervention', 'allowed', v_iv.id is null, 'recommended', v_rec = 'open_intervention',
                         'why', case when v_iv.id is not null then 'a Human input needed item is already open (ref ' || v_iv.id || ')' end)));
end $function$;
revoke all on function security.layer4_aer_recovery_detail_v1(text) from public, anon, authenticated;

-- 9 the recovery decision: refuses a deterministic repeat; a duplicate names the original action and its current state ---------------------------
create or replace function security.layer4_aer_recovery_decide_v1(p_ref text, p_choice text, p_value text, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- The four recovery choices on a held AER read (decision 06:58 §1). Approval is never reached from here: the E13 and D-R3 gates are untouched.
--   reread_stored     the existing corrected read: security.course_entry_correction_v1 (course reads, D-R2; scraper off, the stored page) or
--                     security.aer_reread_v1 (matrix runs, the stored copy); refused by their own rules when a read is already waiting, and
--                     (CF-247 decision 12:24 §1, IQ-00279) refused here when the reader refused the same read of the same unchanged copy
--   request_evidence  one aer_read_evidence intervention for the recovery case (all held reads of the university failing the same way)
--   ai_analyse        the aer_read_rows_missing intervention, sent first to the stronger model (only while har.ai_escalate_on is 1)
--   open_intervention the aer_read_rows_missing intervention for this read, for a person
-- Every call is recorded (pipeline.layer4_aer_recovery_actions and the Inbox decision row); the same choice on an unchanged problem returns the
-- recorded operation and its current state instead of starting another.
declare st jsonb; v_reason text := btrim(coalesce(p_reason, '')); a pipeline.layer4_aer_recovery_actions; v_res jsonb; v_iv jsonb; v_next text; v_ws text;
        v_ok boolean := true; v_req text; v_ev bigint; v_id bigint; v_wi jsonb; v_class text; v_ent text; v_ai boolean; v_rep jsonb; v_now text; v_outcome text;
        v_osup pipeline.aer_read_supersessions; v_oiv pipeline.layer4_interventions; v_ofe pipeline.field_enrich_items;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 4 then raise exception 'your role cannot take this action (it needs rank 4)' using errcode = '42501'; end if;
  if p_choice not in ('reread_stored', 'request_evidence', 'ai_analyse', 'open_intervention') then raise exception 'unknown recovery choice %', p_choice using errcode = '22023'; end if;
  if length(v_reason) < 5 then raise exception 'give a reason (kept with the recovery)'; end if;
  st := security.layer4_aer_recovery_state_v1(p_ref::uuid);
  if st is null or not exists (select 1 from pipeline.layer4_review_items r where r.id = p_ref::uuid and r.status = 'pending') then
    raise exception 'this item is no longer waiting (someone may have decided it)'; end if;
  v_rep := case when p_choice = 'reread_stored' and st->>'field_code' = 'course_entry_first_read' then security.layer4_reread_repeat_v1(p_ref::uuid) end;
  select * into a from pipeline.layer4_aer_recovery_actions x where x.review_item_id = p_ref::uuid and x.choice = p_choice and x.problem_fingerprint = st->>'problem_fingerprint';
  -- observation 13:00 §6: a repeated click while the operation is queued or running returns that operation, whoever asked for it (a reviewer,
  -- the scheduled reading or human input), and starts nothing
  if p_choice = 'reread_stored' then
    select * into v_osup from pipeline.aer_read_supersessions x where x.old_item_id = p_ref::uuid and x.state = 'requested' order by x.requested_at desc limit 1;
    if v_osup.id is null then
      select * into v_ofe from pipeline.field_enrich_items f where f.course_id = (st->>'course_id')::uuid and f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased')
       order by f.id desc limit 1;
    else
      select * into v_ofe from pipeline.field_enrich_items f where f.id = v_osup.enrich_item_id;
    end if;
  else
    select * into v_oiv from pipeline.layer4_interventions i where i.lane = 'aer_item' and i.status in ('ai_pending', 'awaiting_input', 'resuming')
       and (i.entity = p_ref or i.entity = (st->>'provider_id') || '|case:' || (st->>'case_key')) order by i.id desc limit 1;
  end if;
  if v_osup.id is not null or v_ofe.id is not null or v_oiv.id is not null then
    v_outcome := 'already_requested'; v_ok := false;
    v_res := jsonb_build_object('repeat', true, 'existing', jsonb_strip_nulls(jsonb_build_object('request', v_osup.id, 'enrich_item', v_ofe.id, 'job', coalesce(v_osup.job_id, v_ofe.job_id),
                                  'intervention_id', v_oiv.id, 'asked_at', coalesce(v_osup.requested_at, v_ofe.created_at, v_oiv.created_at),
                                  'state', coalesce(case when v_ofe.state in ('leased', 'ai') then 'running' when v_ofe.id is not null then 'queued' end, v_oiv.status))),
                                'recorded', a.id, 'intervention_id', v_oiv.id);
    v_req := 'Already queued — existing request retained: ' ||
             case when v_oiv.id is not null then 'Human input needed item ' || v_oiv.id || ' (' || replace(v_oiv.status, '_', ' ') || ', opened ' || (security.l4_time_v1(v_oiv.created_at)->>'text') || ')'
                  else coalesce('request ' || left(v_osup.id::text, 8) || ', ', '') || 'enrich item ' || v_ofe.id || ' (' ||
                       case when v_ofe.state in ('leased', 'ai') then 'running' else 'queued' end || ', asked ' || (security.l4_time_v1(coalesce(v_osup.requested_at, v_ofe.created_at))->>'text') || ')' end || '.';
  elsif a.id is not null then
    -- already requested: the original action and where it stands now
    v_now := case when p_choice = 'reread_stored' then
                    (select case s.state when 'requested' then 'waiting for the reader'
                                         when 'superseded' then 'complete: a new read replaced this one'
                                         else 'the reader refused it at ' || coalesce(security.l4_time_v1(s.closed_at)->>'text', '?') || ': ' || coalesce(s.outcome, 'refused') end
                       from pipeline.aer_read_supersessions s where s.id::text = a.result->>'request_id')
                  else (select 'Human input needed item ' || i.id || ' is ' || replace(i.status, '_', ' ') from pipeline.layer4_interventions i where i.id = a.intervention_id) end;
    v_outcome := 'already_requested';
    v_res := jsonb_build_object('repeat', true, 'recorded', a.id, 'recorded_at', a.at, 'next_operation', a.next_operation, 'intervention_id', a.intervention_id,
                                'current_state', v_now, 'alternative', v_rep->>'alternative', 'unchanged', coalesce((v_rep->>'repeat')::boolean, false));
    v_ok := false;
    v_req := 'Already requested: recovery action ' || a.id || ' at ' || (security.l4_time_v1(a.at)->>'text') || '. Now: ' || coalesce(v_now, a.next_operation, 'recorded') || '.'
             || case when coalesce((v_rep->>'repeat')::boolean, false) then ' Reading the same stored copy again would be refused the same way. Instead: ' || (v_rep->>'alternative') || '.' else '' end;
  else
    v_wi := jsonb_build_object('lane', 'aer_technical', 'entity', p_ref, 'kind', 'l4_item');
    if coalesce((v_rep->>'repeat')::boolean, false) then
      -- a deterministic repeat: nothing is read, the refusal is recorded with its reason and the permitted alternative
      v_ok := false; v_outcome := 'refused';
      v_req := 'Not read again: ' || (v_rep->>'why') || '. Instead: ' || (v_rep->>'alternative') || '.';
      v_res := jsonb_build_object('refused', 'deterministic repeat of corrected read ' || (v_rep->>'request'), 'repeat_of', v_rep->>'request', 'alternative', v_rep->>'alternative');
    elsif p_choice = 'reread_stored' then
      begin
        if st->>'field_code' = 'course_entry_first_read' then
          v_res := security.course_entry_correction_v1(p_ref::uuid, auth.uid(), 'Layer 4 recovery: ' || v_reason);
        else
          v_res := security.aer_reread_v1((st->>'source_id')::uuid, 'Layer 4 recovery: ' || v_reason, auth.uid());
        end if;
        v_next := 'the existing reader reads the stored page again; the new read replaces this one only through the same gates';
      exception when others then
        v_ok := false; v_req := sqlerrm || '. Choose Request official evidence or Open human input instead.'; v_res := jsonb_build_object('refused', sqlerrm);
      end;
    else
      v_ai := p_choice = 'ai_analyse';
      if v_ai and not (security.pipeline_num_v1('har.ai_escalate_on', 0) >= 1 and security.pipeline_num_v1('ops.ai_diagnosis_on', 0) >= 1 and security.har_text_v1('har.ai_escalation_model', '') <> '') then
        v_ok := false; v_req := 'The stronger-model step is switched off (har.ai_escalate_on, ops.ai_diagnosis_on, har.ai_escalation_model). Choose Open human input instead.';
        v_res := jsonb_build_object('held', 'AI step off');
      else
        v_class := case p_choice when 'request_evidence' then 'aer_read_evidence' else 'aer_read_rows_missing' end;
        v_ent := case p_choice when 'request_evidence' then (st->>'provider_id') || '|case:' || (st->>'case_key') else p_ref end;
        v_iv := security.layer4_intervention_raise_v1(jsonb_build_object('class', v_class, 'entity', v_ent, 'provider_id', st->>'provider_id', 'course_id', st->>'course_id',
                  'subject', coalesce((select coalesce(c.display_title, c.canonical_title) from catalogue.courses c where c.id = (st->>'course_id')::uuid), 'Entry requirements') || ': ' ||
                             case v_class when 'aer_read_evidence' then 'official evidence needed' else 'dropped requirements to enter' end,
                  'attempts', 99, 'signature', case v_class when 'aer_read_evidence' then st->>'case_key' else st->>'problem_fingerprint' end,
                  'issue', jsonb_build_object('summary', 'The read is held: ' || (st->>'case_label'), 'attempted', jsonb_build_array('AI course read', 'completeness gate'),
                                              'why_stopped', st->'reasons'->>0, 'impact', 'the course''s accurate rows cannot be admitted while the read is incomplete'),
                  'evidence', jsonb_build_object('stored_copies', case when st->>'evidence_id' is not null then jsonb_build_array(st->>'evidence_id') else '[]'::jsonb end,
                                                 'quotes', st->'missing_quotes', 'attempts', jsonb_build_array(jsonb_build_object('corrected_read', st->'corrected_read')),
                                                 'conflicts', st->'reasons'),
                  'resume_target', jsonb_build_object('operation', 'corrected read of the course by the existing reader (D-R2)', 'work_item', v_wi),
                  'review_item', p_ref));
        v_id := (v_iv->>'id')::bigint;
        if v_id is null then v_ok := false; v_req := 'No Human input needed item could be opened: ' || coalesce(v_iv->>'reason', 'refused'); end if;
        -- ai_analyse sends the new item to the stronger model first; open_intervention and request_evidence go straight to a person
        update pipeline.layer4_interventions set status = case when v_ai then 'ai_pending' else 'awaiting_input' end,
               resume_target = resume_target || jsonb_build_object('review_item', p_ref) where id = v_id and status in ('ai_pending', 'awaiting_input');
        v_next := case when v_id is null then null when v_ai then 'the stronger model analyses the failure once, then the item waits for a person'
                       else 'Human input needed item ' || v_id || ' waits for a person; the course is read again by itself when the input checks out' end;
        v_res := v_iv;
      end if;
    end if;
    select w.stage into v_ws from pipeline.work_items w where w.lane = 'aer_technical' and w.entity = p_ref and w.work_kind = 'l4_item';
    insert into pipeline.layer4_aer_recovery_actions(review_item_id, case_key, choice, problem_fingerprint, reason, affected_rows, missing_quotes, previous_evidence, reviewer,
                work_item_status, next_operation, intervention_id, result)
    select p_ref::uuid, st->>'case_key', p_choice, case when v_ok then st->>'problem_fingerprint' else st->>'problem_fingerprint' || ':refused:' || md5(coalesce(v_req, '')) || ':' || now() end,
           v_reason, st->'waiting_rows', st->'missing_quotes',
           jsonb_build_object('evidence_id', st->>'evidence_id', 'corrected_read', st->'corrected_read', 'reasons', st->'reasons'), auth.uid(), coalesce(v_ws, 'none'),
           coalesce(v_next, v_req), v_id, coalesce(v_res, '{}'::jsonb)
    returning * into a;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', 'aer_review:' || p_ref, jsonb_build_object('kind', 'aer_review', 'ref', p_ref, 'choice', p_choice, 'value', p_value, 'reason', v_reason,
          'provider_id', st->>'provider_id', 'recovery_action', a.id, 'result', v_res), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', v_ok, 'kind', 'aer_review', 'choice', p_choice, 'ref', p_ref, 'event_id', v_ev, 'request', v_req,
    'returns', case when v_ok then v_next end, 'result', jsonb_build_object('recovery_action', a.id, 'next_operation', a.next_operation, 'work_item_status', a.work_item_status,
                                                                          'intervention_id', a.intervention_id, 'detail', v_res));
end $function$;
revoke all on function security.layer4_aer_recovery_decide_v1(text, text, text, text) from public, anon, authenticated;

-- 10 every Inbox decision replies with its acknowledgement (§4): the two replies of public.admin_layer4_inbox('decide') pass through
--    security.layer4_action_ack_v1; nothing else in the function changes
do $e$
declare v_def text := pg_get_functiondef('public.admin_layer4_inbox(text,jsonb)'::regprocedure); v_new text;
        o1 text := $o$    return jsonb_build_object('ok', coalesce((v_r->>'ok')::boolean, false), 'kind', v_kind, 'choice', v_choice, 'returns', coalesce(v_r->>'returns', v_c->>'returns'),
                              'result', v_r->'result', 'ref', v_ref, 'event_id', v_r->'event_id', 'request', v_r->'request', 'outcome', v_r->'outcome', 'hook', v_c->>'hook');$o$;
        n1 text := $n$    -- CF-247 decision 12:24 §4: the reply carries its normalised acknowledgement, read from the records just written
    return security.layer4_action_ack_v1(v_kind, v_ref, jsonb_build_object('ok', coalesce((v_r->>'ok')::boolean, false), 'kind', v_kind, 'choice', v_choice, 'returns', coalesce(v_r->>'returns', v_c->>'returns'),
                              'result', v_r->'result', 'ref', v_ref, 'event_id', v_r->'event_id', 'request', v_r->'request', 'outcome', v_r->'outcome', 'hook', v_c->>'hook'));$n$;
        o2 text := $o$  return jsonb_build_object('ok', true, 'kind', v_kind, 'choice', v_choice, 'returns', v_c->>'returns', 'result', v_r, 'ref', v_ref, 'event_id', v_event,
                            'outcome', security.layer4_decision_outcome_v1(v_kind, v_choice, v_r));$o$;
        n2 text := $n$  return security.layer4_action_ack_v1(v_kind, v_ref, jsonb_build_object('ok', true, 'kind', v_kind, 'choice', v_choice, 'returns', v_c->>'returns', 'result', v_r, 'ref', v_ref, 'event_id', v_event,
                            'outcome', security.layer4_decision_outcome_v1(v_kind, v_choice, v_r)));$n$;
begin
  if md5(v_def) = 'c0a972a6d6cc0652ce2dcc8f4d9cbbfc' then raise notice 'public.admin_layer4_inbox(text,jsonb): already applied'; return; end if;
  if (length(v_def) - length(replace(v_def, o1, ''))) / length(o1) <> 1 or (length(v_def) - length(replace(v_def, o2, ''))) / length(o2) <> 1 then
    raise exception 'public.admin_layer4_inbox: the two decision replies were not found once each';
  end if;
  v_new := replace(replace(v_def, o1, n1), o2, n2);
  execute v_new;
  if md5(pg_get_functiondef('public.admin_layer4_inbox(text,jsonb)'::regprocedure)) <> 'c0a972a6d6cc0652ce2dcc8f4d9cbbfc' then
    raise exception 'public.admin_layer4_inbox after the change has md5 %, expected c0a972a6d6cc0652ce2dcc8f4d9cbbfc', md5(pg_get_functiondef('public.admin_layer4_inbox(text,jsonb)'::regprocedure));
  end if;
  raise notice 'public.admin_layer4_inbox(text,jsonb): applied';
end $e$;

-- 11 component register ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.layer4_lifecycle_one_v1', 'Layer 4', 'Layer 4 review', 'The action lifecycle of one Layer 4 item from existing records (decision 12:24 §2, §3)', 'active', '{}', '20261104540000'),
 ('function', 'security.layer4_item_lifecycle_v1', 'Layer 4', 'Layer 4 review', 'One card''s lifecycle with admission and publication checks', 'active', '{}', '20261104540000'),
 ('function', 'security.layer4_items_lifecycle_v1', 'Layer 4', 'Layer 4 review', 'A page of cards'' lifecycles', 'active', '{}', '20261104540000'),
 ('function', 'security.layer4_action_ack_v1', 'Layer 4', 'Layer 4 review', 'The normalised acknowledgement on every Inbox decision (decision 12:24 §4)', 'active', '{}', '20261104540000'),
 ('function', 'security.layer4_ack_normalise_v1', 'Layer 4', 'Layer 4 review', 'Normalises a Layer 4 action result (reply or audit row)', 'active', '{}', '20261104540000'),
 ('function', 'security.layer4_reread_repeat_v1', 'Layer 4', 'Entry requirements', 'Whether a corrected read would be a deterministic repeat (IQ-00279)', 'active', '{}', '20261104540000'),
 ('function', 'security.layer4_lifecycle_report_v1', 'Layer 4', 'Layer 4 review', 'Layer 4 lifecycle measures (decision 12:24 §10)', 'active', '{}', '20261104540000'),
 ('function', 'security.l4_time_v1', 'Layer 4', 'Layer 4 review', 'A Layer 4 time in Australian format (AEDT/AEST)', 'active', '{}', '20261104540000'),
 ('function', 'public.admin_layer4_lifecycle', 'Layer 4', 'Layer 4 review', 'The screen''s read of card lifecycles', 'active', '{}', '20261104540000')
on conflict do nothing;

-- 12 post-check -------------------------------------------------------------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select * from (values ('security.layer4_aer_recovery_detail_v1(text)', 'dbf06336a7ee14fd0a84697d616cb67c'),
                                 ('security.layer4_aer_recovery_decide_v1(text,text,text,text)', 'f247220fd13231654f47877ecc72240e'),
                                 ('public.admin_layer4_inbox(text,jsonb)', 'c0a972a6d6cc0652ce2dcc8f4d9cbbfc')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'post-check: % has md5 %', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
end $$;
