-- CF-247 SS-021 part 2: the shared Work Continuity capability (Platform Admin P0 mandate 3 Nov 2026 21:19, admin
-- docs/platform/nz-enrichment-brief/2026-11-03-p0-work-continuity-mandate-2119.md §2-§5, §7-§9). An extension of workstream A's operations
-- controller (20261104010000, live since v2.15.429), not a new controller: lanes report into one work-item record, the operations report carries
-- its figures, and its blockers reach the controller as integration issues diagnosed and remedied through A's contract.
-- Why (live, read-only, 3 Nov 2026 21:22-21:28 AEDT):
--   * course-relink failed 23 of its last 32 runs (every run from 18:54 to 21:34), each at the 120 s statement time-out inside
--     security.course_relink_provider_v1 (course_relink_slugs_v1, course_relink_url_norm_v1, course_relink_url_seg_v1). Its tick takes the
--     universities with the most refused pages first ("order by count(*) desc"), so the same university heads every run, the run rolls back
--     (the settle updates before it too) and no other university is relinked: head-of-line blocking with no recovery.
--   * 2,508 field values (intakes 738, english 586, duration 263, delivery 228, international 213, campus 185, description 180, deadline 85,
--     others 30) ended "no answer could be recorded after 3 tries" in 3 days: the IQ-00053 lock time-outs, a transient fault turned into a terminal
--     state with no next attempt and no deadline.
--   * Layer 4 waits for AER: course_entry_first_read 532 + entry_matrix_first_run 41 = 573 against aer.schedule_layer4_max 600; nothing records
--     which work waits for a review category and which is independent of it.
--   * provider-identity-check failed 4 of 4 runs (the issue it raises uses root_cause_class 'data', refused by the queue's check): see the
--     interface request below; not edited here (workstream G owns it).
-- What:
--   1 pipeline.work_items: one continuity record per (lane, entity, work kind) with the §2 fields; lanes write it only through
--     security.work_item_report_v1(lane, entity, kind, event, detail). Stages reuse the controller's outcome codes (pipeline.ops_outcome_codes).
--   2 pipeline.work_recovery_policies: the §3 policy by failure class; every threshold is a wc.* setting (G2). No infinite retries: a class's
--     attempts end in parked with the evidence and an escalation. A parked, deferred or waiting item holds no claim.
--   3 forward progress: security.work_fair_pick_v1 (round-robin by provider and field, skips items not yet eligible, defers work whose review
--     category is full), security.work_claim_v1 and security.work_claims_release_v1 (expired claims released safely), and per-item isolation
--     in course-relink (md5-guarded edit of security.course_relink_tick_v1; the fair, isolated run is security.course_relink_fair_run_v1).
--   4 admission-aware scheduling: pipeline.work_review_categories maps Layer 4 kinds to the caps that already exist (aer.schedule_layer4_max,
--     bind.no_page_pending_max, pdesc.pending_max); nothing raises, bypasses or changes a cap, a Layer 4 item or a decision.
--   5 job work-continuity (security.work_continuity_tick_v1): releases expired claims, returns due items to eligible, resumes a paused lane or a
--     deferred review category when there is room, attributes course-relink time-outs to the university that heads its order, records the
--     terminal AI-extraction failures, and escalates each unchanged blocker once (integration issue work_blocked:<lane>:<class>).
--   6 root causes and remedies through A's contract: auto only for retry, park and release-claim; admin for authority, budget, identity or
--     policy blockers.
--   7 security.work_continuity_report_v1(): the §9 lane figures; security.ops_report_v1 carries it as section work_continuity (md5-guarded edit).
-- Activation:
--   ON (they stop waste and record): wc.on (recording, the tick, claim release, parking), wc.escalate_on (one integration issue per blocker),
--     wc.relink_fair_on (course-relink fair order, per-university isolation and the run's time budget; it asks no more searches than before).
--   OFF (they change what is spent or admitted): wc.ai_recovery_on (handing parked AI-extraction items back to the reader through
--     security.work_items_due_v1: AI spend). Nothing here admits data, decides or removes a Layer 4 item, or changes a cap, a budget or a lock.
-- md5 (before = live, read 3 Nov 2026 21:24-21:29 AEDT; after = this edit):
--   security.course_relink_tick_v1(integer) 0cd20104a975c471ed4dd9060569f3b8 -> 656d308b1b12532a7e3e4335cf0f21ea
--   security.ops_report_v1(integer)         ff46a882b695539ca5cb7879a68ee578 -> 5a1e21cc42f8f54cbf0d9f3f7fe81c71
-- Called, not edited (live md5): security.integration_issue_upsert_v1(jsonb,text) c5ce0cb9c431a337789d67bc1878be62,
--   security.ops_root_cause_register_v1(text,jsonb) 591616a6a0bd60d607f65c41c18e2968, security.ops_remedy_register_v1(text,jsonb)
--   cec6cd2f6518b453fbc8ec3137ce39bd, security.lane_paid_hold_v1(text) 99ec517b8b51b0d1305b739e7f1562fb;
--   security.course_relink_provider_v1(uuid,integer) is called through its interface only ({trying, absent}; live md5 776844024ca5ee99011ad73dfd36360b).
-- Interface requests (not edited here): see the report of this change (lane owners adopt security.work_fair_pick_v1 / work_item_report_v1).
-- Replaces: security.course_relink_tick_v1, security.ops_report_v1 (same names; md5-guarded edits)
-- Retires: nothing (the "largest university first" course-relink order stays reachable with wc.relink_fair_on 0 until retired after the 24-hour run)
-- Nothing is dropped or deleted. Consumer API untouched (G3). No Firecrawl or AI spend.

-- 0 the contract and the functions this change calls or edits, as read live ----------------------------------------------------------------
do $g$
declare r record;
begin
  if to_regclass('pipeline.ops_remedies') is null then
    raise exception 'workstream A''s operations contract (migration 20261104010000) must be applied before this change';
  end if;
  for r in select * from (values ('security.integration_issue_upsert_v1(jsonb,text)', 'c5ce0cb9c431a337789d67bc1878be62'),
                                 ('security.ops_root_cause_register_v1(text,jsonb)', '591616a6a0bd60d607f65c41c18e2968'),
                                 ('security.ops_remedy_register_v1(text,jsonb)', 'cec6cd2f6518b453fbc8ec3137ce39bd'),
                                 ('security.lane_paid_hold_v1(text)', '99ec517b8b51b0d1305b739e7f1562fb')) v(sig, m) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
  -- called through its interface only ({trying, absent}); not edited, so its body may change under its owner
  if to_regprocedure('security.course_relink_provider_v1(uuid,integer)') is null then raise exception 'live security.course_relink_provider_v1(uuid,integer) is missing'; end if;
end $g$;

-- an edit applied once, only from the definition it was written against (the 20261103050000 helper)
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

-- 1 settings (G2; Settings > Pipeline settings, section Work continuity) -----------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'wc.on', 'Work continuity: record, park and release',
  'On (1): lanes record their work items, failures are classified and given their next attempt or parked with evidence, expired claims are released and due items return to their lane. Off (0): nothing is recorded or released.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1300, 'Work continuity', 'security.work_item_report_v1; security.work_continuity_tick_v1 (job work-continuity)', 'P0 work continuity mandate 3 Nov 2026 21:19 §2-§4: ships on (records and stops waste only)'),
 ('pipeline', 'wc.tick_batch', 'Work continuity: items handled a run',
  'At most this many items are released, returned to their lane or resumed in one run of the work-continuity job.',
  'number', to_jsonb(500), 50, 5000, 'items', 1301, 'Work continuity', 'security.work_continuity_tick_v1', 'Mandate 21:19 §4'),
 ('pipeline', 'wc.backoff_base_minutes', 'Work continuity: first wait after a transient failure',
  'A transient failure (network, worker, time-out, expired claim) waits this long before its next attempt; each further failure doubles the wait.',
  'number', to_jsonb(10), 1, 240, 'minutes', 1302, 'Work continuity', 'security.work_item_report_v1 (policy retry_backoff)', 'Mandate 21:19 §3 "bounded exponential backoff"'),
 ('pipeline', 'wc.backoff_max_minutes', 'Work continuity: longest wait between attempts',
  'The doubling wait never exceeds this.',
  'number', to_jsonb(720), 10, 10080, 'minutes', 1303, 'Work continuity', 'security.work_item_report_v1 (policy retry_backoff)', 'Mandate 21:19 §3'),
 ('pipeline', 'wc.transient_max_attempts', 'Work continuity: attempts after transient failures',
  'After this many failed attempts in a row an item is parked with its evidence and escalated once; it is not retried again automatically.',
  'number', to_jsonb(5), 1, 20, 'attempts', 1304, 'Work continuity', 'security.work_item_report_v1 (classes transient, lease_expired)', 'Mandate 21:19 §3 "do not create infinite retries"'),
 ('pipeline', 'wc.ai_max_attempts', 'Work continuity: attempts after incomplete AI extraction',
  'An AI read that returned no usable answer is tried again through the approved reader this many times, then parked with its evidence.',
  'number', to_jsonb(3), 1, 10, 'attempts', 1305, 'Work continuity', 'security.work_item_report_v1 (class ai_incomplete)', 'Mandate 21:19 §3 "AI extraction incomplete"'),
 ('pipeline', 'wc.site_recheck_hours', 'Work continuity: re-check an unavailable website after',
  'Work for a provider whose website does not answer is deferred and its availability is checked again after this long.',
  'number', to_jsonb(24), 1, 168, 'hours', 1306, 'Work continuity', 'security.work_item_report_v1 (class site_unavailable)', 'Mandate 21:19 §3 "provider website unavailable"'),
 ('pipeline', 'wc.site_max_rechecks', 'Work continuity: availability re-checks before parking',
  'After this many re-checks with the website still unavailable the work is parked and escalated once.',
  'number', to_jsonb(7), 1, 30, 're-checks', 1307, 'Work continuity', 'security.work_item_report_v1 (class site_unavailable)', 'Mandate 21:19 §3'),
 ('pipeline', 'wc.recover_by_hours', 'Work continuity: automatic recovery deadline',
  'An item still blocked this long after it was first blocked is escalated (once) as overdue for recovery.',
  'number', to_jsonb(48), 1, 720, 'hours', 1308, 'Work continuity', 'security.work_item_report_v1; security.work_continuity_tick_v1', 'Mandate 21:19 §2 "recovery deadline and escalation condition", §9'),
 ('pipeline', 'wc.review_full_recheck_minutes', 'Work continuity: look again at a full review category after',
  'Work held because its Layer 4 category is at its existing limit is looked at again after this long, and returns to its lane as soon as there is room.',
  'number', to_jsonb(60), 10, 1440, 'minutes', 1309, 'Work continuity', 'security.work_continuity_tick_v1; security.work_fair_pick_v1', 'Mandate 21:19 §5 "resume automatically when capacity frees"'),
 ('pipeline', 'wc.budget_recheck_minutes', 'Work continuity: look again at a paused paid lane after',
  'A paid lane paused because its budget is used is looked at again after this long; it resumes when the budget check allows it.',
  'number', to_jsonb(60), 10, 1440, 'minutes', 1310, 'Work continuity', 'security.work_continuity_tick_v1', 'Mandate 21:19 §3 "pause only the affected paid lane"'),
 ('pipeline', 'wc.evidence_keep', 'Work continuity: distinct failures kept per item',
  'The newest this many distinct failures are kept as an item''s evidence; an identical repeat only counts.',
  'number', to_jsonb(5), 1, 20, 'failures', 1311, 'Work continuity', 'security.work_item_report_v1', 'Mandate 21:19 §2, §6 "deduplicated"'),
 ('pipeline', 'wc.escalate_on', 'Work continuity: raise one issue per blocker',
  'On (1): each blocker (a lane and failure class with parked, quarantined, paused or overdue work) is raised once as an integration issue for the operations controller; an unchanged blocker is never raised again. Off (0): blockers are only recorded.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1312, 'Work continuity', 'security.work_continuity_tick_v1', 'Mandate 21:19 §7, §9 "do not repeatedly notify"; ships on (records only)'),
 ('pipeline', 'wc.relink_fair_on', 'Work continuity: course re-linking takes universities in turn',
  'On (1): course-relink takes universities least recently tried first, isolates each university (a failure stops only that university), stops starting new ones at its time budget and skips one waiting for its next attempt. Off (0): largest first, one failure stops the run (as before).',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1313, 'Work continuity', 'security.course_relink_tick_v1; security.course_relink_fair_run_v1', 'Mandate 21:19 §4; course-relink failed 23 of 32 runs (3 Nov 2026 18:54-21:14 AEDT); ships on (asks no more searches than before)'),
 ('pipeline', 'wc.relink_run_seconds', 'Work continuity: course re-linking time budget a run',
  'No new university is started once a run has taken this long (keep it well under the 120-second statement limit).',
  'number', to_jsonb(60), 10, 110, 'seconds', 1314, 'Work continuity', 'security.course_relink_fair_run_v1', 'Mandate 21:19 §4 "continue until worker capacity is exhausted"'),
 ('pipeline', 'wc.reflect_scan_ids', 'Work continuity: field items looked through a run',
  'Each run looks through this many field items (by id, from where the last run stopped) for reads that ended without an answer.',
  'number', to_jsonb(20000), 1000, 200000, 'items', 1315, 'Work continuity', 'security.work_continuity_tick_v1 (lane ai_extraction)', 'Mandate 21:19 §3, §8 item 4'),
 ('pipeline', 'wc.reflect_lookback_items', 'Work continuity: field items looked back at first',
  'On its first run the job starts this many field items before the newest.',
  'number', to_jsonb(200000), 1000, 2000000, 'items', 1316, 'Work continuity', 'security.work_continuity_tick_v1 (lane ai_extraction)', 'Mandate 21:19 §8 item 4'),
 ('pipeline', 'wc.ai_recovery_on', 'Work continuity: hand parked AI reads back to the reader',
  'On (1): AI-extraction items due again are offered to the field reader (security.work_items_due_v1), which spends AI credit within the existing ceilings. Off (0): they are recorded and reported only.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1317, 'Work continuity', 'security.work_items_due_v1', 'Mandate 21:19 §3: AI spend, so it ships off'),
 ('pipeline', 'wc.report_window_hours', 'Work continuity: report window',
  'Completed and recovered work is counted over this many hours.',
  'number', to_jsonb(24), 1, 168, 'hours', 1318, 'Work continuity', 'security.work_continuity_report_v1', 'Mandate 21:19 §9'),
 ('pipeline', 'wc.repeat_min', 'Work continuity: repeats that make a repeated root cause',
  'A failure class seen at least this many times in one lane (repeats included) is listed as a repeated root cause.',
  'number', to_jsonb(3), 2, 100, 'failures', 1319, 'Work continuity', 'security.work_continuity_report_v1', 'Mandate 21:19 §9 "root causes with repeated failures"')
on conflict do nothing;

-- 2 the policy table (§3) -------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.work_recovery_policies (
  failure_class text primary key check (failure_class ~ '^[a-z][a-z0-9_]*$'),
  title text not null,
  action text not null check (action in ('retry_backoff', 'park', 'quarantine', 'defer_recheck', 'layer4_review', 'pause_lane', 'defer_admission', 'hold_lock')),
  counts_attempt boolean not null default true,
  max_attempts_key text,
  recheck_key text,
  escalate_as text check (escalate_as is null or escalate_as in ('release', 'authority', 'budget', 'identity', 'policy')),
  escalate_when text not null default 'exhausted' check (escalate_when in ('never', 'exhausted', 'always')),
  root_cause text,
  description text not null
);
comment on table pipeline.work_recovery_policies is 'CF-247 SS-021 work continuity (mandate 3 Nov 2026 21:19 §3): the automatic action for each failure class: bounded exponential backoff (retry_backoff, wc.backoff_* settings), park with evidence, quarantine (identity conflicts; accepted data is kept), defer with a re-check (unavailable website), Layer 4 review (a human decision), pause only the paid lane (budget), defer for admission (the review category is at its existing limit) and hold for a manual lock. Every threshold is a wc.* setting; no class retries for ever. escalate_as says what kind of blocker reaches the operations controller (as integration issue work_blocked:<lane>:<class>, root_cause). Changed by a release. Never read by the consumer API.';
alter table pipeline.work_recovery_policies enable row level security;
revoke all on pipeline.work_recovery_policies from public, anon, authenticated;
insert into pipeline.work_recovery_policies(failure_class, title, action, counts_attempt, max_attempts_key, recheck_key, escalate_as, escalate_when, root_cause, description) values
 ('transient', 'Transient network, worker or time-out failure', 'retry_backoff', true, 'wc.transient_max_attempts', null, 'release', 'exhausted', 'work_retries_exhausted',
  'Retried after wc.backoff_base_minutes, doubling to wc.backoff_max_minutes, at most wc.transient_max_attempts times; then parked with the evidence.'),
 ('lease_expired', 'A claim expired before the work reported', 'retry_backoff', true, 'wc.transient_max_attempts', null, 'release', 'exhausted', 'work_retries_exhausted',
  'The claim is released (no lease is kept) and the item retried as a transient failure.'),
 ('ai_incomplete', 'AI extraction returned no usable answer', 'retry_backoff', true, 'wc.ai_max_attempts', null, 'release', 'exhausted', 'work_ai_incomplete',
  'Retried through the approved reader strategy at most wc.ai_max_attempts times (handed back to the reader only while wc.ai_recovery_on is 1); then parked with the evidence.'),
 ('page_missing', 'The course page is missing', 'park', true, null, null, null, 'never', null,
  'The lane has already used its verified alternative discovery routes; the item is parked with the evidence and waits for new evidence (no retry).'),
 ('ambiguity', 'Source or qualification ambiguity', 'park', true, null, null, 'policy', 'always', 'work_ambiguous_evidence',
  'Parked with the evidence; the lane proposes a Layer 4 review through its own generator (parking raises no review item).'),
 ('identity_conflict', 'Duplicate or identity conflict', 'quarantine', true, null, null, 'identity', 'always', 'work_identity_conflict',
  'The item is quarantined; the existing accepted data is kept unchanged; a person decides.'),
 ('site_unavailable', 'The provider''s website is unavailable', 'defer_recheck', true, 'wc.site_max_rechecks', 'wc.site_recheck_hours', 'policy', 'exhausted', 'work_site_unavailable',
  'Deferred; identity and availability are checked again after wc.site_recheck_hours, at most wc.site_max_rechecks times; then parked and escalated.'),
 ('human_review', 'A human decision is required', 'layer4_review', false, null, null, null, 'never', null,
  'The item waits for its Layer 4 item (review_ref); other work continues. Waiting is never admission and never removes the item from review.'),
 ('review_full', 'The Layer 4 category is at its existing limit', 'defer_admission', false, null, 'wc.review_full_recheck_minutes', null, 'never', null,
  'Deferred without an attempt and without a review item; returns to its lane as soon as the category has room. The limit is never raised or bypassed.'),
 ('budget_exhausted', 'The paid lane''s budget is used', 'pause_lane', false, null, 'wc.budget_recheck_minutes', 'budget', 'always', 'work_budget_exhausted',
  'Only the affected paid lane pauses; free and stored-evidence lanes continue; the lane resumes when the budget check allows it.'),
 ('manual_lock', 'The value is locked by hand', 'hold_lock', false, null, null, null, 'never', null,
  'Held: a manual lock is never changed or bypassed; the item is skipped until the lock is released by a person.'),
 ('authority', 'Platform Admin authority is required', 'park', false, null, null, 'authority', 'always', 'work_authority_required',
  'Parked with the evidence and the decision required.'),
 ('unknown', 'Unclassified failure', 'retry_backoff', true, 'wc.transient_max_attempts', null, 'release', 'exhausted', 'work_retries_exhausted',
  'Retried with backoff like a transient failure, at most wc.transient_max_attempts times; then parked with the evidence.')
on conflict (failure_class) do nothing;

-- 3 the work-item record (§2) ---------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.work_items (
  id bigserial primary key,
  lane text not null check (lane ~ '^[a-z][a-z0-9_]*$'),
  entity text not null check (length(entity) > 0),
  work_kind text not null check (work_kind ~ '^[a-z*][a-z0-9_:*]*$'),
  provider_id uuid,
  field text,
  owner text not null,
  stage text not null default 'eligible' check (stage in ('eligible', 'active', 'retry_wait', 'deferred', 'parked', 'quarantined', 'awaiting_review', 'lane_paused', 'done')),
  attempts int not null default 0,
  total_attempts int not null default 0,
  failure_class text references pipeline.work_recovery_policies(failure_class),
  failure_fingerprint text,
  repeat_count int not null default 0,
  evidence jsonb not null default '[]'::jsonb,
  first_blocked_at timestamptz,
  last_attempt_at timestamptz,
  next_eligible_at timestamptz,
  recover_by timestamptz,
  lease_until timestamptz,
  escalation jsonb,
  dependency_refs jsonb not null default '[]'::jsonb,
  lock_refs jsonb not null default '[]'::jsonb,
  review_ref text,
  review_category text,
  evidence_version text,
  outcome text references pipeline.ops_outcome_codes(code),
  unresolved_blocker jsonb,
  recovered_at timestamptz,
  last_recovery_minutes numeric,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lane, entity, work_kind)
);
comment on table pipeline.work_items is 'CF-247 SS-021 work continuity (mandate 3 Nov 2026 21:19 §2): one continuity record per lane, entity and work kind: owner and stage, attempts in a row and in total, failure class (pipeline.work_recovery_policies) with deduplicated diagnostic evidence, first blocked, last attempt, next eligible time, recovery deadline (recover_by) and escalation, dependency and manual-lock references, the evidence or source version used, and the outcome (pipeline.ops_outcome_codes) or the unresolved blocker. Written only through security.work_item_report_v1, work_claim_v1, work_claims_release_v1 and job work-continuity. A parked, deferred, quarantined or waiting item holds no claim. Rows with entity ''*lane'' hold a lane''s own state (a paused paid lane, the course-relink attribution cursor). Never read by the consumer API.';
create index if not exists work_items_due_idx on pipeline.work_items (lane, next_eligible_at) where stage in ('retry_wait', 'deferred');
create index if not exists work_items_active_idx on pipeline.work_items (lane, lease_until) where stage = 'active';
create index if not exists work_items_blocked_idx on pipeline.work_items (lane, failure_class) where stage in ('parked', 'quarantined', 'lane_paused', 'retry_wait', 'deferred');
create index if not exists work_items_provider_idx on pipeline.work_items (lane, provider_id);
alter table pipeline.work_items enable row level security;
revoke all on pipeline.work_items from public, anon, authenticated;
revoke all on sequence pipeline.work_items_id_seq from public, anon, authenticated;

-- 4 review categories (§5): Layer 4 kinds and the caps that already exist ---------------------------------------------------------------------
create table if not exists pipeline.work_review_categories (
  category text primary key check (category ~ '^[a-z][a-z0-9_]*$'),
  field_codes text[] not null,
  limit_key text not null,
  in_progress_fields text[] not null default '{}',
  description text not null
);
comment on table pipeline.work_review_categories is 'CF-247 SS-021 work continuity (mandate 3 Nov 2026 21:19 §5): which Layer 4 kinds make up a review category and the existing setting that caps it (read, never changed). security.work_review_room_v1 says how much room a category has; work in a full category is deferred without an attempt or a review item, and independent categories and lanes continue. Never read by the consumer API.';
alter table pipeline.work_review_categories enable row level security;
revoke all on pipeline.work_review_categories from public, anon, authenticated;
insert into pipeline.work_review_categories(category, field_codes, limit_key, in_progress_fields, description) values
 ('aer', array['course_entry_first_read', 'entry_matrix_first_run'], 'aer.schedule_layer4_max', array['entry_requirements'],
  'Academic entry requirements: course reads and matrix runs waiting, plus entry reads in progress (as security.aer_schedule_tick_v1 counts them).'),
 ('no_page', array['no_page_first_run', 'conjoint_rule_first_run'], 'bind.no_page_pending_max', '{}',
  'No page published and conjoint first runs (security.no_page_propose_v1).'),
 ('provider_description', array['provider_description'], 'pdesc.pending_max', '{}',
  'Provider descriptions waiting (public.svc_provider_description_next).')
on conflict (category) do nothing;

-- 5 functions -------------------------------------------------------------------------------------------------------------------------------
create or replace function security.work_failure_class_v1(p_sqlstate text, p_message text) returns text
language sql immutable set search_path to '' as $function$
-- CF-247 SS-021 (§3): an error to its failure class. Time-outs, lock waits, deadlocks, connection and HTTP 5xx/429 answers are transient;
-- a unique violation is an identity conflict; the manual-lock refusal is a lock; budget and credit refusals are budget; anything else unknown.
  select case
    when coalesce(p_message, '') ~* '(set by hand|manual lock|locked by hand)' then 'manual_lock'
    when coalesce(p_message, '') ~* '(budget|credit|ceiling|reserve|quota exhausted)' then 'budget_exhausted'
    when p_sqlstate in ('23505') or coalesce(p_message, '') ~* '(duplicate|identity conflict)' then 'identity_conflict'
    when p_sqlstate in ('57014', '55P03', '40P01', '40001', '08000', '08003', '08006', '53300')
      or coalesce(p_message, '') ~* '(timeout|timed out|deadlock|lock not available|connection|HTTP 5[0-9][0-9]|HTTP 429|rate limit|BOOT_ERROR)' then 'transient'
    when coalesce(p_message, '') ~* '(no answer could be recorded|incomplete read|no usable answer)' then 'ai_incomplete'
    when coalesce(p_message, '') ~* '(site unavailable|DNS|ENOTFOUND|ECONNREFUSED|certificate)' then 'site_unavailable'
    else 'unknown' end
$function$;
revoke all on function security.work_failure_class_v1(text, text) from public, anon, authenticated;

create or replace function security.work_backoff_minutes_v1(p_attempts int) returns numeric
language sql stable set search_path to '' as $function$
-- §3 bounded exponential backoff: base x 2^(attempts-1), never above the maximum (both settings).
  select least(security.pipeline_num_v1('wc.backoff_base_minutes', 10) * power(2, greatest(coalesce(p_attempts, 1), 1) - 1),
               security.pipeline_num_v1('wc.backoff_max_minutes', 720))
$function$;
revoke all on function security.work_backoff_minutes_v1(int) from public, anon, authenticated;

create or replace function security.work_item_report_v1(p_lane text, p_entity text, p_kind text, p_event text, p_detail jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 SS-021 (§2-§5): the one way a lane reports into its work item. Events:
--   claimed (detail.lease_seconds: the lane's own claim timer), succeeded (detail.outcome, default succeeded_with_result), released, failed
--   (detail.class, or classified from detail.sqlstate and detail.message; detail.evidence), review (detail.review_ref: a human decision is
--   pending), decided (the review ended), review_full (detail.category), locked (detail.lock), dependency (detail.ref), budget (detail.purpose).
-- detail may also carry provider_id, field, owner and evidence_version. A failure is handled by its class's policy (pipeline.work_recovery_policies):
-- an identical repeat only counts (repeat_count); attempts end in parked; a parked, deferred or waiting item holds no claim.
declare w pipeline.work_items; pol pipeline.work_recovery_policies; v_d jsonb := coalesce(p_detail, '{}'::jsonb); v_class text; v_fp text; v_max numeric;
        v_keep int := security.pipeline_num_v1('wc.evidence_keep', 5)::int; v_ev jsonb; v_stage text; v_next timestamptz; v_blocker jsonb;
begin
  if security.pipeline_num_v1('wc.on', 1) < 1 then return jsonb_build_object('recorded', false, 'reason', 'wc.on is 0'); end if;
  if p_event not in ('claimed', 'succeeded', 'released', 'failed', 'review', 'decided', 'review_full', 'locked', 'dependency', 'budget') then
    raise exception 'unknown work event %', p_event using errcode = '22023';
  end if;
  insert into pipeline.work_items as x(lane, entity, work_kind, provider_id, field, owner)
  values (p_lane, p_entity, p_kind, nullif(v_d->>'provider_id', '')::uuid, nullif(v_d->>'field', ''), coalesce(nullif(v_d->>'owner', ''), p_lane))
  on conflict (lane, entity, work_kind) do update set provider_id = coalesce(excluded.provider_id, x.provider_id), field = coalesce(excluded.field, x.field)
  returning * into w;
  select * into w from pipeline.work_items where id = w.id for update;

  if p_event = 'claimed' then
    if w.stage in ('parked', 'quarantined', 'awaiting_review', 'lane_paused') or (w.stage in ('retry_wait', 'deferred') and w.next_eligible_at > now())
       or (w.stage = 'active' and w.lease_until > now()) then
      return jsonb_build_object('recorded', false, 'stage', w.stage, 'reason', 'not eligible');
    end if;
    update pipeline.work_items set stage = 'active', last_attempt_at = now(), total_attempts = total_attempts + 1,
           lease_until = now() + make_interval(secs => coalesce((v_d->>'lease_seconds')::int, 300)),  -- fixed: the lane's own claim timer, passed by the lane
           evidence_version = coalesce(v_d->>'evidence_version', evidence_version), updated_at = now() where id = w.id;
    return jsonb_build_object('recorded', true, 'stage', 'active', 'id', w.id);
  elsif p_event = 'succeeded' then
    update pipeline.work_items set stage = 'done', outcome = coalesce(nullif(v_d->>'outcome', ''), 'succeeded_with_result'), attempts = 0, lease_until = null,
           next_eligible_at = null, unresolved_blocker = null, last_attempt_at = coalesce(last_attempt_at, now()),
           total_attempts = total_attempts + case when stage = 'active' then 0 else 1 end,
           recovered_at = case when first_blocked_at is not null then now() end,
           last_recovery_minutes = case when first_blocked_at is not null then round(extract(epoch from now() - first_blocked_at) / 60, 1) else last_recovery_minutes end,
           first_blocked_at = null, recover_by = null, evidence_version = coalesce(v_d->>'evidence_version', evidence_version), updated_at = now() where id = w.id;
    return jsonb_build_object('recorded', true, 'stage', 'done', 'recovered', w.first_blocked_at is not null);
  elsif p_event = 'released' then
    update pipeline.work_items set stage = case when stage = 'active' then 'eligible' else stage end, lease_until = null, updated_at = now() where id = w.id;
    return jsonb_build_object('recorded', true, 'stage', 'eligible');
  elsif p_event = 'decided' then
    update pipeline.work_items set stage = 'eligible', review_ref = null, next_eligible_at = null, updated_at = now() where id = w.id and stage = 'awaiting_review';
    return jsonb_build_object('recorded', true, 'stage', 'eligible');
  elsif p_event = 'dependency' then
    update pipeline.work_items set stage = 'deferred', lease_until = null, dependency_refs = (select coalesce(jsonb_agg(distinct e), '[]'::jsonb) from jsonb_array_elements(dependency_refs || jsonb_build_array(v_d->'ref')) e),
           next_eligible_at = now() + make_interval(mins => security.work_backoff_minutes_v1(1)::int), first_blocked_at = coalesce(first_blocked_at, now()), updated_at = now() where id = w.id;
    return jsonb_build_object('recorded', true, 'stage', 'deferred');
  end if;

  -- a failure or a hold: classify and apply the policy
  v_class := case p_event when 'review' then 'human_review' when 'review_full' then 'review_full' when 'locked' then 'manual_lock' when 'budget' then 'budget_exhausted'
                          else coalesce(nullif(v_d->>'class', ''), security.work_failure_class_v1(v_d->>'sqlstate', v_d->>'message')) end;
  select * into pol from pipeline.work_recovery_policies where failure_class = v_class;
  if not found then v_class := 'unknown'; select * into pol from pipeline.work_recovery_policies where failure_class = 'unknown'; end if;
  v_fp := md5(v_class || '|' || regexp_replace(lower(coalesce(v_d->>'message', v_d->>'reason', '')), '[0-9a-f-]{8,}|[0-9]+', '#', 'g'));
  v_ev := jsonb_build_object('at', now(), 'class', v_class, 'sqlstate', v_d->>'sqlstate', 'message', left(coalesce(v_d->>'message', v_d->>'reason'), 300), 'evidence', v_d->'evidence');
  if w.failure_fingerprint is distinct from v_fp then
    w.evidence := (select coalesce(jsonb_agg(e order by n), '[]'::jsonb) from jsonb_array_elements(w.evidence || jsonb_build_array(v_ev)) with ordinality z(e, n)
                    where n > jsonb_array_length(w.evidence) + 1 - v_keep);
  end if;
  w.attempts := w.attempts + case when pol.counts_attempt then 1 else 0 end;
  v_max := case when pol.max_attempts_key is not null then security.pipeline_num_v1(pol.max_attempts_key, 3) end;
  v_stage := case pol.action
    when 'retry_backoff' then case when w.attempts >= v_max then 'parked' else 'retry_wait' end
    when 'defer_recheck' then case when w.attempts >= v_max then 'parked' else 'deferred' end
    when 'park' then 'parked' when 'hold_lock' then 'parked' when 'quarantine' then 'quarantined' when 'layer4_review' then 'awaiting_review'
    when 'defer_admission' then 'deferred' when 'pause_lane' then 'deferred' end;
  v_next := case
    when v_stage = 'retry_wait' then now() + make_interval(mins => security.work_backoff_minutes_v1(w.attempts)::int)
    when v_stage = 'deferred' and pol.action = 'defer_recheck' then now() + make_interval(hours => security.pipeline_num_v1(pol.recheck_key, 24)::int)
    when v_stage = 'deferred' and pol.action = 'defer_admission' then now() + make_interval(mins => security.pipeline_num_v1(pol.recheck_key, 60)::int)
    else null end;  -- parked, quarantined, awaiting review and a paused lane: no automatic next attempt (a remedy, a person or the lane's resume)
  v_blocker := case when v_stage in ('parked', 'quarantined') then jsonb_build_object('class', v_class, 'title', pol.title, 'action', pol.action,
                 'reason', case when pol.action in ('retry_backoff', 'defer_recheck') then 'attempts used up (' || w.attempts || ')' else pol.description end,
                 'escalate_as', pol.escalate_as, 'at', now()) end;
  update pipeline.work_items set stage = v_stage, attempts = w.attempts, total_attempts = total_attempts + case when stage = 'active' or not pol.counts_attempt then 0 else 1 end,
         failure_class = v_class, failure_fingerprint = v_fp, repeat_count = case when failure_fingerprint = v_fp then repeat_count + 1 else 0 end,
         evidence = w.evidence, first_blocked_at = coalesce(first_blocked_at, now()),
         recover_by = coalesce(recover_by, now() + make_interval(hours => security.pipeline_num_v1('wc.recover_by_hours', 48)::int)),
         last_attempt_at = case when pol.counts_attempt then now() else last_attempt_at end, next_eligible_at = v_next, lease_until = null,
         review_ref = case when p_event = 'review' then coalesce(v_d->>'review_ref', review_ref) else review_ref end,
         review_category = case when p_event = 'review_full' then v_d->>'category' else review_category end,
         lock_refs = case when p_event = 'locked' then (select coalesce(jsonb_agg(distinct e), '[]'::jsonb) from jsonb_array_elements(lock_refs || jsonb_build_array(v_d->'lock')) e) else lock_refs end,
         outcome = case v_stage when 'parked' then 'blocked_evidence' when 'quarantined' then 'blocked_policy' when 'awaiting_review' then 'blocked_policy'
                                when 'retry_wait' then 'failed_retryable' else 'deferred_dependency' end,
         unresolved_blocker = coalesce(v_blocker, unresolved_blocker), evidence_version = coalesce(v_d->>'evidence_version', evidence_version), updated_at = now()
   where id = w.id;
  if pol.action = 'pause_lane' then
    -- §3 budget: only the affected paid lane pauses (its lane row); other lanes and this lane's free work are untouched
    insert into pipeline.work_items as x(lane, entity, work_kind, owner, stage, failure_class, first_blocked_at, next_eligible_at, dependency_refs, unresolved_blocker, outcome)
    values (p_lane, '*lane', 'lane', p_lane, 'lane_paused', 'budget_exhausted', now(),
            now() + make_interval(mins => security.pipeline_num_v1('wc.budget_recheck_minutes', 60)::int),
            jsonb_build_array(jsonb_build_object('purpose', v_d->>'purpose')), jsonb_build_object('class', 'budget_exhausted', 'purpose', v_d->>'purpose', 'at', now()), 'blocked_policy')
    on conflict (lane, entity, work_kind) do update set stage = 'lane_paused', failure_class = 'budget_exhausted', first_blocked_at = coalesce(x.first_blocked_at, now()),
       next_eligible_at = excluded.next_eligible_at, dependency_refs = excluded.dependency_refs, unresolved_blocker = excluded.unresolved_blocker, outcome = 'blocked_policy', updated_at = now();
  end if;
  return jsonb_build_object('recorded', true, 'stage', v_stage, 'class', v_class, 'attempts', w.attempts, 'next_eligible_at', v_next, 'repeat', w.failure_fingerprint = v_fp);
end $function$;
revoke all on function security.work_item_report_v1(text, text, text, text, jsonb) from public, anon, authenticated;
comment on function security.work_item_report_v1(text, text, text, text, jsonb) is 'CF-247 SS-021 work continuity (mandate 21:19 §2): the one function lanes report through (claimed, succeeded, released, failed, review, decided, review_full, locked, dependency, budget).';

create or replace function security.work_lane_paused_v1(p_lane text) returns boolean
language sql stable security definer set search_path to '' as $function$
  select exists (select 1 from pipeline.work_items w where w.lane = p_lane and w.entity = '*lane' and w.work_kind = 'lane' and w.stage = 'lane_paused')
$function$;
revoke all on function security.work_lane_paused_v1(text) from public, anon, authenticated;

create or replace function security.work_item_eligible_v1(p_lane text, p_entity text, p_kind text) returns boolean
language sql stable security definer set search_path to '' as $function$
-- §4: an item with no record, done, eligible, due again, or holding an expired claim is eligible; parked, quarantined, waiting for review, in a
-- paused lane, not yet due, or validly claimed is not.
  select not security.work_lane_paused_v1(p_lane) and coalesce((
    select case when w.stage in ('eligible', 'done') then true
                when w.stage in ('retry_wait', 'deferred') then coalesce(w.next_eligible_at <= now(), false)
                when w.stage = 'active' then coalesce(w.lease_until < now(), true)
                else false end
      from pipeline.work_items w where w.lane = p_lane and w.entity = p_entity and w.work_kind = p_kind), true)
$function$;
revoke all on function security.work_item_eligible_v1(text, text, text) from public, anon, authenticated;

create or replace function security.work_review_room_v1(p_category text) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- §5: room in a review category: its existing cap less the items waiting (and reads in progress where the category counts them). Read only.
-- A category with no cap setting is not limited here (room null).
declare c pipeline.work_review_categories; v_limit numeric; v_wait int; v_prog int := 0;
begin
  select * into c from pipeline.work_review_categories where category = p_category;
  if not found then return jsonb_build_object('category', p_category, 'known', false, 'room', null); end if;
  v_limit := security.pipeline_num_v1(c.limit_key, null);
  select count(*) into v_wait from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code = any (c.field_codes);
  if cardinality(c.in_progress_fields) > 0 then
    select count(*) into v_prog from pipeline.field_enrich_items f where f.field = any (c.in_progress_fields) and f.state in ('queued', 'waiting', 'ai', 'leased');
  end if;
  return jsonb_build_object('category', p_category, 'known', true, 'limit_key', c.limit_key, 'limit', v_limit, 'waiting', v_wait, 'in_progress', v_prog,
                            'room', case when v_limit is null then null else greatest(v_limit - v_wait - v_prog, 0) end);
end $function$;
revoke all on function security.work_review_room_v1(text) from public, anon, authenticated;

create or replace function security.work_fair_pick_v1(p_lane text, p_kind text, p_candidates jsonb, p_limit int)
returns table(entity text, provider_id uuid, field text, category text, pos int)
language plpgsql security definer set search_path to '' as $function$
-- CF-247 SS-021 (§4, §5): the shared fair selection. p_candidates is [{entity, provider_id, field, category, priority}]. Leaves out items not
-- eligible (security.work_item_eligible_v1) and everything in a paused lane; work whose review category has no room is recorded as deferred
-- (review_full: no attempt, no review item) and left out, so independent fields and categories still fill the batch. The rest is ordered
-- round-robin: each provider and field's first item before any second one, least recently served provider first, then priority.
declare v_rooms jsonb := '{}'::jsonb; v_cat text; v_room jsonb; r record;
begin
  if security.pipeline_num_v1('wc.on', 1) < 1 then
    return query select c->>'entity', nullif(c->>'provider_id', '')::uuid, c->>'field', c->>'category', (n)::int
                   from jsonb_array_elements(coalesce(p_candidates, '[]'::jsonb)) with ordinality z(c, n) order by n limit greatest(coalesce(p_limit, 0), 0);
    return;
  end if;
  if security.work_lane_paused_v1(p_lane) then return; end if;
  for v_cat in select distinct c->>'category' from jsonb_array_elements(coalesce(p_candidates, '[]'::jsonb)) c where nullif(c->>'category', '') is not null loop
    v_room := security.work_review_room_v1(v_cat);
    v_rooms := v_rooms || jsonb_build_object(v_cat, v_room->'room');
  end loop;
  -- record the work held by a full category (once per item; an unchanged hold is a repeat, not new evidence)
  for r in select c->>'entity' e, c->>'category' cat, c->>'provider_id' pid, c->>'field' f from jsonb_array_elements(coalesce(p_candidates, '[]'::jsonb)) c
            where nullif(c->>'category', '') is not null and (v_rooms->>(c->>'category')) is not null and (v_rooms->>(c->>'category'))::numeric <= 0
              and security.work_item_eligible_v1(p_lane, c->>'entity', p_kind) loop
    perform security.work_item_report_v1(p_lane, r.e, p_kind, 'review_full', jsonb_build_object('category', r.cat, 'provider_id', r.pid, 'field', r.f,
              'reason', 'review category ' || r.cat || ' is at its limit'));
  end loop;
  return query
  with c as (select x.c->>'entity' e, nullif(x.c->>'provider_id', '')::uuid pid, x.c->>'field' f, nullif(x.c->>'category', '') cat,
                    coalesce((x.c->>'priority')::numeric, 0) pri, x.n
               from jsonb_array_elements(coalesce(p_candidates, '[]'::jsonb)) with ordinality x(c, n)),
       ok as (select c.*, w.last_attempt_at la, w.stage from c left join pipeline.work_items w on w.lane = p_lane and w.entity = c.e and w.work_kind = p_kind
               where security.work_item_eligible_v1(p_lane, c.e, p_kind)
                 and (c.cat is null or (v_rooms->>c.cat) is null or (v_rooms->>c.cat)::numeric > 0)),
       served as (select w.provider_id pid, max(w.last_attempt_at) la from pipeline.work_items w where w.lane = p_lane and w.work_kind = p_kind and w.provider_id is not null group by 1),
       t as (select ok.*, row_number() over (partition by ok.pid, ok.f order by ok.la nulls first, ok.pri desc, ok.n) turn, s.la pla
               from ok left join served s on s.pid = ok.pid),
       u as (select t.*, row_number() over (partition by t.cat order by t.turn, t.pla nulls first, t.pri desc, t.n) cat_turn from t)
  -- a category with room takes at most its room in this batch (the cap is never exceeded by one selection)
  select u.e, u.pid, u.f, u.cat, (row_number() over (order by u.turn, u.pla nulls first, u.pri desc, u.n))::int
    from u where u.cat is null or (v_rooms->>u.cat) is null or u.cat_turn <= (v_rooms->>u.cat)::numeric
   order by u.turn, u.pla nulls first, u.pri desc, u.n limit greatest(coalesce(p_limit, 0), 0);
end $function$;
revoke all on function security.work_fair_pick_v1(text, text, jsonb, int) from public, anon, authenticated;
comment on function security.work_fair_pick_v1(text, text, jsonb, int) is 'CF-247 SS-021 work continuity (mandate 21:19 §4, §5): the shared fair selection (round-robin by provider and field; skips items not yet eligible; defers work whose review category is full without raising a review item).';

create or replace function security.work_claim_v1(p_lane text, p_kind text, p_candidates jsonb, p_limit int, p_lease_seconds int) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- §4: fair selection, then a claim on each chosen item for the lane's own lease time (a technical timer the lane passes).
declare v jsonb := '[]'::jsonb; r record; v_res jsonb;
begin
  for r in select * from security.work_fair_pick_v1(p_lane, p_kind, p_candidates, p_limit) loop
    v_res := security.work_item_report_v1(p_lane, r.entity, p_kind, 'claimed', jsonb_build_object('lease_seconds', p_lease_seconds, 'provider_id', r.provider_id, 'field', r.field));
    if coalesce((v_res->>'recorded')::boolean, false) or security.pipeline_num_v1('wc.on', 1) < 1 then
      v := v || jsonb_build_array(jsonb_build_object('entity', r.entity, 'provider_id', r.provider_id, 'field', r.field, 'category', r.category, 'pos', r.pos));
    end if;
  end loop;
  return v;
end $function$;
revoke all on function security.work_claim_v1(text, text, jsonb, int, int) from public, anon, authenticated;

create or replace function security.work_claims_release_v1(p_lane text default null, p_limit int default null) returns int
language plpgsql security definer set search_path to '' as $function$
-- §4: claims that expired before the lane reported are released safely: the item gets a transient attempt (lease_expired) and its next
-- eligible time, so it neither keeps a dead claim nor is retried at once.
declare r record; v_n int := 0;
begin
  for r in select w.lane, w.entity, w.work_kind from pipeline.work_items w
            where w.stage = 'active' and w.lease_until < now() and (p_lane is null or w.lane = p_lane)
            order by w.lease_until limit coalesce(p_limit, security.pipeline_num_v1('wc.tick_batch', 500)::int) for update skip locked loop
    perform security.work_item_report_v1(r.lane, r.entity, r.work_kind, 'failed', jsonb_build_object('class', 'lease_expired', 'message', 'the claim expired before the work reported'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;
revoke all on function security.work_claims_release_v1(text, int) from public, anon, authenticated;

create or replace function security.work_items_due_v1(p_lane text, p_kind text, p_limit int) returns table(entity text, provider_id uuid, field text, attempts int)
language sql stable security definer set search_path to '' as $function$
-- §3/§4: items of a lane due for their next attempt, in fair order, for the lane's own picker. The AI-extraction lane is offered only while
-- wc.ai_recovery_on is 1 (AI spend; ships off).
  select w.entity, w.provider_id, w.field, w.attempts from (
    select w.*, row_number() over (partition by w.provider_id, w.field order by w.next_eligible_at) turn from pipeline.work_items w
     where w.lane = p_lane and w.work_kind = p_kind and w.stage in ('eligible', 'retry_wait', 'deferred') and coalesce(w.next_eligible_at, now()) <= now()
       and w.entity <> '*lane' and not security.work_lane_paused_v1(p_lane)
       and (p_lane <> 'ai_extraction' or security.pipeline_num_v1('wc.ai_recovery_on', 0) >= 1)) w
   order by w.turn, w.next_eligible_at nulls first limit greatest(coalesce(p_limit, 0), 0)
$function$;
revoke all on function security.work_items_due_v1(text, text, int) from public, anon, authenticated;

-- 6 course-relink: fair order, per-university isolation, time budget (§4) ------------------------------------------------------------------
create or replace function security.course_relink_order_v1() returns table(provider_id uuid, pages bigint, pos int)
language sql stable security definer set search_path to '' as $function$
-- CF-247 SS-021 (§4): the universities course-relink would take, in the order it takes them: the same candidate rule as
-- security.course_relink_tick_v1 (refused pages not yet relinked, unpublished universities left out), less universities not eligible
-- (waiting for their next attempt or parked), least recently tried first, then the most refused pages.
  select z.provider_id, z.pages, (row_number() over (order by z.la nulls first, z.pages desc, z.provider_id))::int from (
    select p.provider_id, count(*) pages, max(w.last_attempt_at) la
      from pipeline.coverage_course_pages p
      left join pipeline.work_items w on w.lane = 'course_relink' and w.entity = p.provider_id::text and w.work_kind = 'relink'
     where p.read_status = any (security.course_relink_statuses_v1()) and not exists (select 1 from pipeline.course_relink x where x.course_id = p.course_id and not (x.state = 'absent' and x.rule < 2 and x.reason like 'no address%') and not security.source_proof_relink_asked_v1(x.course_id, coalesce(x.decided_at, x.started_at)))
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)
     group by 1) z
   where security.work_item_eligible_v1('course_relink', z.provider_id::text, 'relink')
   order by 3
$function$;
revoke all on function security.course_relink_order_v1() from public, anon, authenticated;

create or replace function security.course_relink_fair_run_v1(p_left int) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 SS-021 (§4): course-relink's university loop with continuity. Each university runs in its own block: an error rolls back only that
-- university, is recorded with its class and next attempt, and the run goes on. No new university starts once the run has taken
-- wc.relink_run_seconds. A statement time-out cannot be caught safely inside the run; job work-continuity attributes it afterwards to the
-- university that headed this order (security.work_relink_attribute_v1), so the next run starts with another.
declare v_left int := greatest(1, coalesce(p_left, 1)); v_start timestamptz := clock_timestamp(); v_budget numeric := security.pipeline_num_v1('wc.relink_run_seconds', 60);
        r record; v_r jsonb; v_prov int := 0; v_err int := 0; v_stopped text; v_state text; v_msg text;
begin
  for r in select * from security.course_relink_order_v1() loop
    if v_left <= 0 then v_stopped := 'batch'; exit; end if;
    if extract(epoch from clock_timestamp() - v_start) >= v_budget then v_stopped := 'time_budget'; exit; end if;
    begin
      v_r := security.course_relink_provider_v1(r.provider_id, v_left);
      v_left := v_left - (v_r->>'trying')::int - (v_r->>'absent')::int;
      v_prov := v_prov + 1;
      perform security.work_item_report_v1('course_relink', r.provider_id::text, 'relink', 'succeeded',
                jsonb_build_object('provider_id', r.provider_id, 'owner', 'course-relink',
                                   'outcome', case when coalesce((v_r->>'trying')::int, 0) + coalesce((v_r->>'absent')::int, 0) > 0 then 'succeeded_with_result' else 'succeeded_no_movement' end));
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
      v_err := v_err + 1;
      perform security.work_item_report_v1('course_relink', r.provider_id::text, 'relink', 'failed',
                jsonb_build_object('provider_id', r.provider_id, 'owner', 'course-relink', 'sqlstate', v_state, 'message', v_msg, 'evidence', jsonb_build_object('pages', r.pages)));
    end;
  end loop;
  return jsonb_build_object('providers', v_prov, 'failed', v_err, 'stopped', v_stopped, 'seconds', round(extract(epoch from clock_timestamp() - v_start)::numeric, 1));
end $function$;
revoke all on function security.course_relink_fair_run_v1(int) from public, anon, authenticated;

select pg_temp.edit_once('security.course_relink_tick_v1(integer)', '0cd20104a975c471ed4dd9060569f3b8', '656d308b1b12532a7e3e4335cf0f21ea',
  array[array[$o$  -- next universities with refused pages not yet relinked
$o$, $n$  -- 3 Nov 2026 (SS-021 work continuity §4, wc.relink_fair_on): universities in turn, each isolated, within the run's time budget
  if security.pipeline_num_v1('wc.relink_fair_on', 0) >= 1 then
    return jsonb_build_object('found', v_found, 'absent', v_absent) || security.course_relink_fair_run_v1(v_left);
  end if;
  -- next universities with refused pages not yet relinked
$n$]], array[1]);

create or replace function security.work_relink_attribute_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 SS-021 (§4): a course-relink run stopped by the statement time-out rolls back everything it recorded. Afterwards (job
-- work-continuity, its own transaction) the time-out is recorded once against the university at the head of the fair order, so the next run
-- starts with another and that university waits for its backoff (parked after wc.transient_max_attempts). The cursor is the last scheduler
-- run looked at (lane row course_relink/*lane/attribution, evidence_version).
declare v_cursor bigint; v_max bigint; v_failed int; v_head uuid; v_pages bigint; v_res jsonb;
begin
  select coalesce(max(d.runid), 0) into v_max from cron.job_run_details d;
  select nullif(w.evidence_version, '')::bigint into v_cursor from pipeline.work_items w where w.lane = 'course_relink' and w.entity = '*lane' and w.work_kind = 'attribution';
  v_cursor := coalesce(v_cursor, v_max - security.pipeline_num_v1('ops.runs_scan', 20000)::bigint);
  select count(*) into v_failed from cron.job_run_details d join cron.job j on j.jobid = d.jobid
   where j.jobname = 'course-relink' and d.runid > v_cursor and d.status = 'failed' and d.return_message ~* '(statement timeout|canceling statement)';
  insert into pipeline.work_items as x(lane, entity, work_kind, owner, evidence_version) values ('course_relink', '*lane', 'attribution', 'work-continuity', v_max::text)
  on conflict (lane, entity, work_kind) do update set evidence_version = excluded.evidence_version, updated_at = now();
  if v_failed = 0 then return jsonb_build_object('timeouts', 0); end if;
  select o.provider_id, o.pages into v_head, v_pages from security.course_relink_order_v1() o order by o.pos limit 1;
  if v_head is null then return jsonb_build_object('timeouts', v_failed, 'attributed', null); end if;
  v_res := security.work_item_report_v1('course_relink', v_head::text, 'relink', 'failed', jsonb_build_object('provider_id', v_head, 'owner', 'course-relink',
             'class', 'transient', 'sqlstate', '57014', 'message', 'course-relink run stopped by the statement time-out while this university headed its order',
             'evidence', jsonb_build_object('failed_runs', v_failed, 'pages', v_pages, 'basis', 'head of security.course_relink_order_v1 when attributed')));
  update pipeline.work_items set last_attempt_at = now() where lane = 'course_relink' and entity = v_head::text and work_kind = 'relink';
  return jsonb_build_object('timeouts', v_failed, 'attributed', v_head, 'result', v_res);
end $function$;
revoke all on function security.work_relink_attribute_v1() from public, anon, authenticated;

-- 7 the job's work: release, resume, reflect, escalate (§3-§5, §7) ---------------------------------------------------------------------------
create or replace function security.work_escalate_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 SS-021 (§7, §9): one integration issue per blocker (lane and failure class with parked, quarantined, paused or overdue work, where the
-- class escalates). The blocker's fingerprint is recorded on its items; an unchanged blocker whose issue is still open is never raised again,
-- however many items join it. Authority, budget, identity and policy blockers route to a Platform Admin decision; exhausted retries to the
-- controller's retry remedy.
declare g record; v_fp text; v_res jsonb; v_n int := 0; v_skip int := 0; v_issue bigint;
begin
  if security.pipeline_num_v1('wc.escalate_on', 1) < 1 then return jsonb_build_object('raised', 0, 'held', 'wc.escalate_on is 0'); end if;
  for g in select w.lane, w.failure_class cls, p.escalate_as, p.root_cause, p.title, count(*) n, min(w.first_blocked_at) oldest,
                  count(*) filter (where w.recover_by < now()) overdue,
                  (array_agg(w.entity order by w.first_blocked_at))[1:5] sample, (array_agg(w.evidence->-1 order by w.first_blocked_at))[1] last_ev,
                  array_agg(distinct w.provider_id) filter (where w.provider_id is not null) provs
             from pipeline.work_items w join pipeline.work_recovery_policies p on p.failure_class = w.failure_class
            where p.escalate_as is not null and p.escalate_when <> 'never'
              and (w.stage in ('parked', 'quarantined', 'lane_paused') and (p.escalate_when = 'always' or w.unresolved_blocker is not null)
                   or (w.stage in ('retry_wait', 'deferred', 'eligible') and w.first_blocked_at is not null and w.recover_by < now()))
            group by w.lane, w.failure_class, p.escalate_as, p.root_cause, p.title loop
    v_fp := 'work_blocked:' || g.lane || ':' || g.cls;
    select i.id into v_issue from pipeline.integration_issues i where i.fingerprint = v_fp and i.status <> 'closed';
    if v_issue is not null and not exists (select 1 from pipeline.work_items w where w.lane = g.lane and w.failure_class = g.cls
                                             and coalesce(w.escalation->>'fingerprint', '') = v_fp and (w.escalation->>'issue_id')::bigint = v_issue) then
      v_issue := null;  -- the open issue was not raised by these items (a fresh blocker under an old fingerprint): link them below
    end if;
    if v_issue is null then
      v_res := security.integration_issue_upsert_v1(jsonb_build_object(
        'fingerprint', v_fp, 'severity', 'P2', 'layer', 'Platform', 'subsystem', 'work continuity: ' || g.lane,
        'title', 'Work continuity: ' || g.title || ' in lane ' || g.lane || ' (' || g.n || ' item(s))',
        'failure', g.n || ' item(s) of lane ' || g.lane || ' are blocked by ' || g.cls || ' (' || coalesce(g.escalate_as, '') || ' blocker); oldest since ' || g.oldest || '; ' || g.overdue || ' past their recovery deadline.',
        'expected', 'Blocked work is recovered automatically within wc.recover_by_hours, or the blocker is decided by the authority named.',
        'source', 'work-continuity', 'validation_layer', 'V3',
        'root_cause_class', case g.escalate_as when 'budget' then 'budget' when 'authority' then 'human_decision' when 'policy' then 'human_decision'
                                               when 'identity' then 'data_drift' else 'queue_or_lease' end,
        'provider_ids', to_jsonb(coalesce(g.provs[1:50], '{}'::uuid[])),
        'evidence', jsonb_build_object('lane', g.lane, 'class', g.cls, 'escalate_as', g.escalate_as, 'root_cause', g.root_cause, 'items', g.n, 'oldest', g.oldest,
                                       'overdue', g.overdue, 'sample', to_jsonb(g.sample), 'last_failure', g.last_ev),
        'workstream', 'A10'), 'work-continuity');
      v_issue := (v_res->>'id')::bigint; v_n := v_n + 1;
    else
      v_skip := v_skip + 1;
    end if;
    update pipeline.work_items w set escalation = jsonb_build_object('fingerprint', v_fp, 'issue_id', v_issue, 'as', g.escalate_as, 'at', coalesce(w.escalation->>'at', now()::text))
     where w.lane = g.lane and w.failure_class = g.cls and coalesce(w.escalation->>'fingerprint', '') <> v_fp
       and (w.stage in ('parked', 'quarantined', 'lane_paused') or w.recover_by < now());
  end loop;
  return jsonb_build_object('raised', v_n, 'unchanged', v_skip);
end $function$;
revoke all on function security.work_escalate_v1() from public, anon, authenticated;

create or replace function security.work_continuity_tick_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 SS-021 (job work-continuity): 1 release expired claims; 2 return due items (retry_wait, deferred) to eligible, a review-held item only
-- when its category has room; 3 resume a paused paid lane when its budget check allows it; 4 attribute course-relink time-outs; 5 record
-- AI-extraction reads that ended without an answer (and settle those since filled); 6 escalate each blocker once. Each step is isolated:
-- one that fails is reported and the others still run. Spends nothing and admits nothing.
declare v_out jsonb := jsonb_build_object('at', now()); v_batch int := security.pipeline_num_v1('wc.tick_batch', 500)::int; v_n int; v_rec int;
        r record; v_cursor bigint; v_maxid bigint; v_scan bigint; v_hold text;
begin
  if security.pipeline_num_v1('wc.on', 1) < 1 then return jsonb_build_object('held', 'wc.on is 0'); end if;
  begin
    v_out := v_out || jsonb_build_object('claims_released', security.work_claims_release_v1(null, v_batch));
  exception when others then v_out := v_out || jsonb_build_object('claims_released', jsonb_build_object('error', left(sqlerrm, 200)));
  end;
  begin
    with due as (select w.id from pipeline.work_items w
                  where w.stage in ('retry_wait', 'deferred') and w.next_eligible_at <= now() and w.entity <> '*lane'
                    and (w.failure_class is distinct from 'review_full' or coalesce((security.work_review_room_v1(w.review_category)->>'room')::numeric, 1) > 0)
                    and (w.failure_class is distinct from 'budget_exhausted' or not security.work_lane_paused_v1(w.lane))
                  order by w.next_eligible_at limit v_batch for update skip locked)
    update pipeline.work_items w set stage = 'eligible', updated_at = now() from due where w.id = due.id;
    get diagnostics v_n = row_count;
    -- review-held items whose recheck came and the category is still full wait another recheck (no attempt, no review item)
    update pipeline.work_items w set next_eligible_at = now() + make_interval(mins => security.pipeline_num_v1('wc.review_full_recheck_minutes', 60)::int), updated_at = now()
     where w.stage = 'deferred' and w.failure_class = 'review_full' and w.next_eligible_at <= now();
    v_out := v_out || jsonb_build_object('returned_to_lane', v_n);
  exception when others then v_out := v_out || jsonb_build_object('returned_to_lane', jsonb_build_object('error', left(sqlerrm, 200)));
  end;
  begin
    v_n := 0;
    for r in select w.id, w.lane, w.dependency_refs->0->>'purpose' purpose from pipeline.work_items w
              where w.entity = '*lane' and w.work_kind = 'lane' and w.stage = 'lane_paused' and w.next_eligible_at <= now() loop
      v_hold := case when r.purpose is not null then security.lane_paid_hold_v1(r.purpose) end;
      if v_hold is null then
        update pipeline.work_items set stage = 'done', outcome = 'succeeded_with_result', recovered_at = now(),
               last_recovery_minutes = round(extract(epoch from now() - first_blocked_at) / 60, 1), first_blocked_at = null, unresolved_blocker = null, updated_at = now() where id = r.id;
        update pipeline.work_items set stage = 'eligible', next_eligible_at = null, updated_at = now() where lane = r.lane and stage = 'deferred' and failure_class = 'budget_exhausted';
        v_n := v_n + 1;
      else
        update pipeline.work_items set next_eligible_at = now() + make_interval(mins => security.pipeline_num_v1('wc.budget_recheck_minutes', 60)::int),
               unresolved_blocker = unresolved_blocker || jsonb_build_object('hold', v_hold, 'checked_at', now()), updated_at = now() where id = r.id;
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('lanes_resumed', v_n);
  exception when others then v_out := v_out || jsonb_build_object('lanes_resumed', jsonb_build_object('error', left(sqlerrm, 200)));
  end;
  begin
    v_out := v_out || jsonb_build_object('relink', security.work_relink_attribute_v1());
  exception when others then v_out := v_out || jsonb_build_object('relink', jsonb_build_object('error', left(sqlerrm, 200)));
  end;
  begin
    -- AI extraction (§3, §8 item 4): reads that ended without an answer become parked or retry-due work items; filled later = recovered
    select max(id) into v_maxid from pipeline.field_enrich_items;
    select nullif(w.evidence_version, '')::bigint into v_cursor from pipeline.work_items w where w.lane = 'ai_extraction' and w.entity = '*lane' and w.work_kind = 'reflect';
    v_cursor := coalesce(v_cursor, greatest(coalesce(v_maxid, 0) - security.pipeline_num_v1('wc.reflect_lookback_items', 200000)::bigint, 0));
    v_scan := least(v_cursor + security.pipeline_num_v1('wc.reflect_scan_ids', 20000)::bigint, coalesce(v_maxid, 0));
    v_n := 0;
    for r in select e.id, e.provider_id, e.course_id, e.field, e.reason, e.attempts from pipeline.field_enrich_items e
              where e.id > v_cursor and e.id <= v_scan and e.state = 'failed'
                and coalesce(e.reason, '') ~* '(no answer could be recorded|incomplete|timeout|timed out)' order by e.id loop
      perform security.work_item_report_v1('ai_extraction', coalesce(r.course_id::text, r.provider_id::text) || ':' || r.field, 'field_read', 'failed',
                jsonb_build_object('provider_id', r.provider_id, 'field', r.field, 'owner', 'enrich_fields', 'class', 'ai_incomplete', 'message', r.reason,
                                   'evidence_version', r.id::text, 'evidence', jsonb_build_object('field_item', r.id, 'reader_attempts', r.attempts)));
      v_n := v_n + 1;
    end loop;
    insert into pipeline.work_items as x(lane, entity, work_kind, owner, evidence_version) values ('ai_extraction', '*lane', 'reflect', 'work-continuity', v_scan::text)
    on conflict (lane, entity, work_kind) do update set evidence_version = excluded.evidence_version, updated_at = now();
    -- recovered: the same course and field filled or sent to review by a later item
    with s as (select w.id from pipeline.work_items w
                where w.lane = 'ai_extraction' and w.work_kind = 'field_read' and w.stage <> 'done'
                  and exists (select 1 from pipeline.field_enrich_items e where e.course_id::text = split_part(w.entity, ':', 1) and e.field = w.field
                                and e.state in ('filled', 'review') and e.id > nullif(w.evidence_version, '')::bigint)
                limit v_batch)
    update pipeline.work_items w set stage = 'done', outcome = 'succeeded_with_result', attempts = 0, recovered_at = now(),
           last_recovery_minutes = round(extract(epoch from now() - w.first_blocked_at) / 60, 1), first_blocked_at = null, recover_by = null,
           unresolved_blocker = null, next_eligible_at = null, updated_at = now() from s where w.id = s.id;
    get diagnostics v_rec = row_count;
    v_out := v_out || jsonb_build_object('ai_extraction', jsonb_build_object('recorded', v_n, 'recovered', v_rec, 'cursor', v_scan));
  exception when others then v_out := v_out || jsonb_build_object('ai_extraction', jsonb_build_object('error', left(sqlerrm, 200)));
  end;
  begin
    v_out := v_out || jsonb_build_object('escalation', security.work_escalate_v1());
  exception when others then v_out := v_out || jsonb_build_object('escalation', jsonb_build_object('error', left(sqlerrm, 200)));
  end;
  return v_out;
end $function$;
revoke all on function security.work_continuity_tick_v1() from public, anon, authenticated;

-- 8 the report (§9) -------------------------------------------------------------------------------------------------------------------------
create or replace function security.work_continuity_report_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
-- CF-247 SS-021 (§9): per lane: eligible, completed in the window, active, blocked (retry_wait, deferred, quarantined, lane paused), parked,
-- retry-due and waiting for review counts; the oldest blocked item; recovered items, recovery success % and median time to recovery;
-- repeated root causes; work awaiting Platform Admin authority; review-category room. Read only.
  with p as (select now() - make_interval(hours => security.pipeline_num_v1('wc.report_window_hours', 24)::int) since,
                    security.pipeline_num_v1('wc.repeat_min', 3) rmin),
       w as (select * from pipeline.work_items where entity <> '*lane'),
       lanes as (
    select w.lane,
           count(*) filter (where w.stage = 'eligible' or (w.stage in ('retry_wait', 'deferred') and w.next_eligible_at <= now())) eligible,
           count(*) filter (where w.stage = 'done' and w.updated_at >= p.since) completed,
           count(*) filter (where w.stage = 'active') active,
           count(*) filter (where w.stage in ('retry_wait', 'deferred', 'quarantined', 'lane_paused')) blocked,
           count(*) filter (where w.stage = 'parked') parked,
           count(*) filter (where w.stage = 'retry_wait' and w.next_eligible_at <= now()) retry_due,
           count(*) filter (where w.stage = 'awaiting_review') awaiting_review,
           count(*) filter (where w.stage = 'deferred' and w.failure_class = 'review_full') review_held,
           min(w.first_blocked_at) filter (where w.stage not in ('done', 'eligible', 'active')) oldest_blocked_at,
           count(*) filter (where w.recovered_at >= p.since) recovered,
           count(*) filter (where w.stage = 'parked' and w.updated_at >= p.since) newly_parked,
           percentile_cont(0.5) within group (order by w.last_recovery_minutes) filter (where w.recovered_at >= p.since) median_recovery_minutes,
           count(*) filter (where w.stage in ('parked', 'quarantined') and w.escalation->>'as' in ('authority', 'budget', 'identity', 'policy')) awaiting_authority
      from w, p group by w.lane)
  select jsonb_build_object('generated_at', now(), 'on', security.pipeline_num_v1('wc.on', 1) >= 1, 'window_hours', security.pipeline_num_v1('wc.report_window_hours', 24),
    'lanes', coalesce((select jsonb_agg(jsonb_build_object('lane', l.lane, 'eligible', l.eligible, 'completed', l.completed, 'active', l.active, 'blocked', l.blocked,
               'parked', l.parked, 'retry_due', l.retry_due, 'awaiting_review', l.awaiting_review, 'review_held', l.review_held, 'oldest_blocked_at', l.oldest_blocked_at,
               'oldest_blocked', (select jsonb_build_object('entity', x.entity, 'class', x.failure_class, 'stage', x.stage) from w x
                                   where x.lane = l.lane and x.stage not in ('done', 'eligible', 'active') order by x.first_blocked_at limit 1),
               'recovered', l.recovered, 'recovery_success_pct', case when l.recovered + l.newly_parked > 0 then round(100.0 * l.recovered / (l.recovered + l.newly_parked), 1) end,
               'median_recovery_minutes', round(l.median_recovery_minutes::numeric, 1), 'awaiting_authority', l.awaiting_authority,
               'paused', security.work_lane_paused_v1(l.lane)) order by l.lane) from lanes l), '[]'::jsonb),
    'repeated_root_causes', coalesce((select jsonb_agg(jsonb_build_object('lane', z.lane, 'class', z.failure_class, 'root_cause', z.root_cause, 'items', z.n, 'failures', z.f) order by z.f desc)
               from (select w.lane, w.failure_class, pol.root_cause, count(*) n, sum(w.repeat_count + 1) f from w join pipeline.work_recovery_policies pol on pol.failure_class = w.failure_class
                      where w.stage <> 'done' group by 1, 2, 3) z, p where z.f >= p.rmin), '[]'::jsonb),
    'awaiting_authority', (select count(*) from w where w.stage in ('parked', 'quarantined') and w.escalation->>'as' in ('authority', 'budget', 'identity', 'policy')),
    'escalations_open', (select count(*) from pipeline.integration_issues i where i.fingerprint like 'work\_blocked:%' and i.status <> 'closed'),
    'review_room', (select coalesce(jsonb_agg(security.work_review_room_v1(c.category) order by c.category), '[]'::jsonb) from pipeline.work_review_categories c),
    'paid_lanes_paused', (select coalesce(jsonb_agg(x.lane order by x.lane), '[]'::jsonb) from pipeline.work_items x where x.entity = '*lane' and x.work_kind = 'lane' and x.stage = 'lane_paused'))
$function$;
revoke all on function security.work_continuity_report_v1() from public, anon, authenticated;

select pg_temp.edit_once('security.ops_report_v1(integer)', 'ff46a882b695539ca5cb7879a68ee578', '5a1e21cc42f8f54cbf0d9f3f7fe81c71',
  array[array[$o$  return v_out;
end $o$, $n$  -- work continuity (SS-021, mandate 3 Nov 2026 21:19 §9): lanes, blocked and parked work, recovery and authority (security.work_continuity_report_v1)
  begin
    v_out := v_out || jsonb_build_object('work_continuity', security.work_continuity_report_v1());
  exception when others then v_out := v_out || jsonb_build_object('work_continuity', jsonb_build_object('error', left(sqlerrm, 200)));
  end;
  return v_out;
end $n$]], array[1]);

-- 9 remedies (§7): auto only for retry, park and release-claim -------------------------------------------------------------------------------
create or replace function security.work_issue_lane_v1(p_issue bigint) returns text
language sql stable security definer set search_path to '' as $function$
  select split_part(i.fingerprint, ':', 2) from pipeline.integration_issues i where i.id = p_issue and i.fingerprint like 'work\_%:%:%'
$function$;
revoke all on function security.work_issue_lane_v1(bigint) from public, anon, authenticated;

create or replace function security.work_remedy_retry_parked_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Auto remedy (retry): the lane's items parked by used-up retries of the issue's class get one more bounded cycle: attempts start again and
-- the next attempt waits the first backoff. The controller runs it at most its attempts setting times per issue, so this never loops.
declare v_lane text := security.work_issue_lane_v1(p_issue); v_cls text; v_n int;
begin
  select split_part(i.fingerprint, ':', 3) into v_cls from pipeline.integration_issues i where i.id = p_issue;
  if v_lane is null then return jsonb_build_object('ok', false, 'changed', 0, 'evidence', 'not a work-continuity issue'); end if;
  update pipeline.work_items w set stage = 'retry_wait', attempts = 0, next_eligible_at = now() + make_interval(mins => security.work_backoff_minutes_v1(1)::int),
         recover_by = now() + make_interval(hours => security.pipeline_num_v1('wc.recover_by_hours', 48)::int), lease_until = null,
         unresolved_blocker = unresolved_blocker || jsonb_build_object('retried_by_issue', p_issue, 'retried_at', now()), updated_at = now()
   where w.lane = v_lane and w.failure_class = v_cls and w.stage = 'parked' and w.entity <> '*lane'
     and w.failure_class in (select p.failure_class from pipeline.work_recovery_policies p where p.action in ('retry_backoff', 'defer_recheck'));
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'changed', v_n, 'evidence', jsonb_build_object('lane', v_lane, 'class', v_cls, 'items_rearmed', v_n));
end $function$;
revoke all on function security.work_remedy_retry_parked_v1(bigint) from public, anon, authenticated;

create or replace function security.work_verify_recovered_v1(p_issue bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- Verification (a later controller run): passed when none of the lane's items of the issue's class is parked, quarantined or overdue, and the
-- lane recorded at least one completed item since the action.
declare v_lane text := security.work_issue_lane_v1(p_issue); v_cls text; v_blocked int; v_done int; v_since timestamptz;
begin
  select split_part(i.fingerprint, ':', 3) into v_cls from pipeline.integration_issues i where i.id = p_issue;
  -- since the newest action on the issue (or, with none, since the issue was detected)
  select coalesce(max(u.started_at), (select i.detected_at from pipeline.integration_issues i where i.id = p_issue)) into v_since from pipeline.ops_remedy_runs u where u.issue_id = p_issue;
  select count(*) into v_blocked from pipeline.work_items w where w.lane = v_lane and w.failure_class = v_cls and w.entity <> '*lane'
     and (w.stage in ('parked', 'quarantined', 'lane_paused') or (w.stage <> 'done' and w.recover_by < now()));
  select count(*) into v_done from pipeline.work_items w where w.lane = v_lane and w.stage = 'done' and w.updated_at >= coalesce(v_since, now());
  return jsonb_build_object('passed', v_blocked = 0 and v_done > 0, 'measure', jsonb_build_object('blocked', v_blocked, 'completed_since_action', v_done),
                            'evidence', 'lane ' || coalesce(v_lane, '?') || ', class ' || coalesce(v_cls, '?') || ': ' || v_blocked || ' blocked, ' || v_done || ' completed since the action');
end $function$;
revoke all on function security.work_verify_recovered_v1(bigint) from public, anon, authenticated;

create or replace function security.work_remedy_release_claims_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Auto remedy (release-claim): the lane's expired claims are released safely (transient attempt, next eligible time).
declare v_lane text := security.work_issue_lane_v1(p_issue); v_n int;
begin
  if v_lane is null then return jsonb_build_object('ok', false, 'changed', 0, 'evidence', 'not a work-continuity issue'); end if;
  v_n := security.work_claims_release_v1(v_lane, null);
  return jsonb_build_object('ok', true, 'changed', v_n, 'evidence', jsonb_build_object('lane', v_lane, 'claims_released', v_n));
end $function$;
revoke all on function security.work_remedy_release_claims_v1(bigint) from public, anon, authenticated;

create or replace function security.work_verify_claims_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path to '' as $function$
  select jsonb_build_object('passed', count(*) = 0, 'measure', jsonb_build_object('expired_claims', count(*)), 'evidence', count(*) || ' expired claim(s) left in lane ' || coalesce(security.work_issue_lane_v1(p_issue), '?'))
    from pipeline.work_items w where w.lane = security.work_issue_lane_v1(p_issue) and w.stage = 'active' and w.lease_until < now()
$function$;
revoke all on function security.work_verify_claims_v1(bigint) from public, anon, authenticated;

create or replace function security.work_remedy_park_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Auto remedy (park): items of the issue's lane and class still marked eligible or active although their attempts are used up are parked
-- with their evidence and lose any claim, so they stop taking the lane's capacity.
declare v_lane text := security.work_issue_lane_v1(p_issue); v_cls text; v_n int;
begin
  select split_part(i.fingerprint, ':', 3) into v_cls from pipeline.integration_issues i where i.id = p_issue;
  if v_lane is null then return jsonb_build_object('ok', false, 'changed', 0, 'evidence', 'not a work-continuity issue'); end if;
  update pipeline.work_items w set stage = 'parked', lease_until = null, next_eligible_at = null, outcome = 'blocked_evidence',
         unresolved_blocker = coalesce(unresolved_blocker, '{}'::jsonb) || jsonb_build_object('parked_by_issue', p_issue, 'reason', 'attempts used up', 'at', now()), updated_at = now()
   where w.lane = v_lane and w.failure_class = v_cls and w.stage in ('eligible', 'active', 'retry_wait') and w.entity <> '*lane'
     and w.attempts >= security.pipeline_num_v1(coalesce((select p.max_attempts_key from pipeline.work_recovery_policies p where p.failure_class = v_cls), 'wc.transient_max_attempts'), 5);
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'changed', v_n, 'evidence', jsonb_build_object('lane', v_lane, 'class', v_cls, 'parked', v_n));
end $function$;
revoke all on function security.work_remedy_park_v1(bigint) from public, anon, authenticated;

create or replace function security.work_verify_parked_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path to '' as $function$
  select jsonb_build_object('passed', count(*) filter (where w.stage in ('active', 'eligible')) = 0 and count(*) filter (where w.lease_until is not null and w.stage = 'parked') = 0,
           'measure', jsonb_build_object('unparked_exhausted', count(*) filter (where w.stage in ('active', 'eligible')), 'parked', count(*) filter (where w.stage = 'parked')),
           'evidence', 'exhausted items still taking capacity: ' || count(*) filter (where w.stage in ('active', 'eligible')))
    from pipeline.work_items w join pipeline.integration_issues i on i.id = p_issue
   where w.lane = split_part(i.fingerprint, ':', 2) and w.failure_class = split_part(i.fingerprint, ':', 3) and w.entity <> '*lane'
     and w.attempts >= security.pipeline_num_v1(coalesce((select p.max_attempts_key from pipeline.work_recovery_policies p where p.failure_class = w.failure_class), 'wc.transient_max_attempts'), 5)
$function$;
revoke all on function security.work_verify_parked_v1(bigint) from public, anon, authenticated;

select security.ops_root_cause_register_v1(x.code, x.spec) from (values
 ('work_retries_exhausted', '{"class": "transient", "title": "Work items used up their automatic retries", "description": "Items of one lane failed transiently (network, worker, time-out, expired claim) until their attempts were used up and were parked with evidence (pipeline.work_items). One more bounded cycle is the automatic remedy; a lasting failure needs a release in the lane.", "detect": {"priority": 11, "confidence": 0.85, "any": [{"fingerprint_like": ["work_blocked:%:transient", "work_blocked:%:lease_expired", "work_blocked:%:unknown"]}]}}'::jsonb),
 ('work_ai_incomplete', '{"class": "data", "title": "AI extraction ended without a usable answer", "description": "Reads that ended without an answer (for example the IQ-00053 lock time-outs, recorded as no answer could be recorded after 3 tries) are parked work items; they return to the reader through security.work_items_due_v1 while wc.ai_recovery_on is 1.", "detect": {"priority": 12, "confidence": 0.85, "any": [{"fingerprint_like": ["work_blocked:%:ai_incomplete"]}]}}'::jsonb),
 ('work_site_unavailable', '{"class": "dependency", "title": "A provider website stayed unavailable", "description": "Work deferred for an unavailable website used up its availability re-checks; the provider''s identity and website need a decision.", "detect": {"priority": 13, "confidence": 0.8, "any": [{"fingerprint_like": ["work_blocked:%:site_unavailable"]}], "route": "needs_decision"}}'::jsonb),
 ('work_identity_conflict', '{"class": "policy", "title": "Work quarantined for an identity conflict", "description": "A duplicate or identity conflict quarantined the item; the accepted data is kept; a person decides which identity holds.", "detect": {"priority": 14, "confidence": 0.9, "any": [{"fingerprint_like": ["work_blocked:%:identity_conflict"]}], "route": "needs_decision"}}'::jsonb),
 ('work_budget_exhausted', '{"class": "policy", "title": "A paid lane is paused for its budget", "description": "Only the paid lane is paused; free and stored-evidence work continues. Raising a budget is the Platform Admin''s decision; the lane resumes on its own when the budget check allows it.", "detect": {"priority": 16, "confidence": 0.9, "any": [{"fingerprint_like": ["work_blocked:%:budget_exhausted"]}], "route": "needs_decision"}}'::jsonb),
 ('work_authority_required', '{"class": "policy", "title": "Work waits for Platform Admin authority", "description": "The work is parked with its evidence until the Platform Admin decides.", "detect": {"priority": 17, "confidence": 0.9, "any": [{"fingerprint_like": ["work_blocked:%:authority"]}], "route": "needs_decision"}}'::jsonb),
 ('work_ambiguous_evidence', '{"class": "policy", "title": "Work parked for ambiguous evidence", "description": "Source or qualification ambiguity: parked with evidence; the lane proposes a Layer 4 review through its own generator (parking raises none).", "detect": {"priority": 18, "confidence": 0.8, "any": [{"fingerprint_like": ["work_blocked:%:ambiguity"]}], "route": "needs_decision"}}'::jsonb),
 ('work_claim_stranded', '{"class": "transient", "title": "Expired work claims were left in a lane", "description": "Claims expired before the lane reported and were not yet released.", "detect": {"priority": 19, "confidence": 0.8, "any": [{"fingerprint_like": ["work_stranded:%:lease_expired"]}]}}'::jsonb)
) x(code, spec);

select security.ops_remedy_register_v1(x.code, x.spec) from (values
 ('work_retry_parked', '{"title": "Give parked work one more bounded retry cycle", "treats": ["work_retries_exhausted", "work_ai_incomplete"], "authority": "auto", "action_fn": "security.work_remedy_retry_parked_v1(bigint)", "verify_fn": "security.work_verify_recovered_v1(bigint)", "max_attempts_key": "ops.max_attempts", "cooldown_key": "ops.cooldown_minutes", "notes": "Retry only: attempts start again with the first backoff; the controller runs it at most ops.max_attempts times per issue. AI-extraction items reach the reader only while wc.ai_recovery_on is 1."}'::jsonb),
 ('work_park_exhausted', '{"title": "Park work whose attempts are used up", "treats": ["work_retries_exhausted"], "authority": "auto", "action_fn": "security.work_remedy_park_v1(bigint)", "verify_fn": "security.work_verify_parked_v1(bigint)", "max_attempts_key": "ops.max_attempts", "cooldown_key": "ops.cooldown_minutes", "notes": "Park only: no claim, no capacity; the evidence is kept."}'::jsonb),
 ('work_release_claims', '{"title": "Release expired work claims", "treats": ["work_claim_stranded"], "authority": "auto", "action_fn": "security.work_remedy_release_claims_v1(bigint)", "verify_fn": "security.work_verify_claims_v1(bigint)", "max_attempts_key": "ops.max_attempts", "cooldown_key": "ops.cooldown_minutes", "notes": "Release-claim only."}'::jsonb),
 ('work_lane_release', '{"title": "Fix the lane through a release", "treats": ["work_retries_exhausted", "work_ai_incomplete"], "authority": "release", "notes": "When the automatic cycles are used up the lane owner changes the lane (for example the reader adopts security.work_items_due_v1)."}'::jsonb),
 ('work_blocker_decision', '{"title": "Platform Admin decides the work blocker", "treats": ["work_site_unavailable", "work_identity_conflict", "work_budget_exhausted", "work_authority_required", "work_ambiguous_evidence"], "authority": "admin", "notes": "Authority, budget, identity or policy: never decided by the platform or by AI diagnosis."}'::jsonb)
) x(code, spec);

-- the SS-021 part 1 audit (admin docs/platform/nz-enrichment-brief/2026-11-03-work-continuity-blocking-audit.md §3) registered its root causes
-- (prefix wc_) live without remedies; the ones present are routed to the release that adopts this capability in the lane (never auto: their
-- issues carry the audit's own fingerprints, not a lane and class this change can act on)
do $wc$
declare v_codes jsonb;
begin
  select coalesce(jsonb_agg(c.code order by c.code), '[]'::jsonb) into v_codes from pipeline.ops_root_causes c
   where c.code in ('wc_batch_abort_one_item', 'wc_head_of_line_fixed_order', 'wc_report_write_aborts_run', 'wc_global_backpressure_all_providers',
                    'wc_transient_exhausted_terminal', 'wc_parked_no_recheck', 'wc_dependent_held_by_paid_cap', 'wc_enqueue_without_gate', 'wc_single_flight_lane');
  if jsonb_array_length(v_codes) = 0 then return; end if;
  perform security.ops_remedy_register_v1('work_continuity_adoption', jsonb_build_object(
    'title', 'Adopt the shared work-continuity capability in the lane', 'treats', v_codes, 'authority', 'release',
    'notes', 'The lane reports through security.work_item_report_v1, selects through security.work_fair_pick_v1 or work_claim_v1, isolates each item in its batch (as security.course_relink_fair_run_v1) and takes due items from security.work_items_due_v1 (migration 20261104170000). Released by the lane owner.'));
end $wc$;

-- 10 the job (G1: catalogued first; ships ON: it records, releases, resumes and escalates; it spends and admits nothing) ----------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('work-continuity', 'Platform upkeep', 18, 'Work continuity (release, resume, escalate)',
  'At :08, :18, :28 and :58 (after course-relink at :x4 and before the operations controller at :24 and :54; clear of :35-:42 and :47-:48): releases expired work claims, returns items due again to their lane (review-held items only when the category has room under its existing limit), resumes a paid lane when its budget check allows it, attributes course-relink time-outs to the university heading its order, records AI-extraction reads that ended without an answer, and raises each unchanged blocker once (integration issue work_blocked:<lane>:<class>). Settings wc.*. Spends nothing and admits nothing.',
  6, false, null)
on conflict (jobname) do nothing;
do $c$ begin
  if not exists (select 1 from cron.job where jobname = 'work-continuity') then
    perform cron.schedule('work-continuity', '8,18,28,58 * * * *', $j$select security.work_continuity_tick_v1()$j$);
  end if;
end $c$;

-- 11 component register ---------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.work_items', 'Platform', 'CF-247 SS-021: one continuity record per lane, entity and work kind', 'active', '{}', '20261104170000'),
 ('table', 'pipeline.work_recovery_policies', 'Platform', 'CF-247 SS-021: recovery policy by failure class (settings-governed)', 'active', '{}', '20261104170000'),
 ('table', 'pipeline.work_review_categories', 'Platform', 'CF-247 SS-021: Layer 4 review categories and their existing caps', 'active', '{}', '20261104170000'),
 ('job', 'work-continuity', 'Platform', 'CF-247 SS-021: release, resume, attribute, record and escalate', 'active', '{}', '20261104170000'),
 ('function', 'security.work_item_report_v1', 'Platform', 'CF-247 SS-021: the one lane report into the work-item record', 'active', '{}', '20261104170000'),
 ('function', 'security.work_fair_pick_v1', 'Platform', 'CF-247 SS-021: shared fair, admission-aware selection', 'active', '{}', '20261104170000'),
 ('function', 'security.work_claim_v1', 'Platform', 'CF-247 SS-021: fair selection with claims', 'active', '{}', '20261104170000'),
 ('function', 'security.work_claims_release_v1', 'Platform', 'CF-247 SS-021: release expired claims safely', 'active', '{}', '20261104170000'),
 ('function', 'security.work_items_due_v1', 'Platform', 'CF-247 SS-021: due items for a lane''s picker', 'active', '{}', '20261104170000'),
 ('function', 'security.work_review_room_v1', 'Platform', 'CF-247 SS-021: room in a Layer 4 review category', 'active', '{}', '20261104170000'),
 ('function', 'security.work_continuity_tick_v1', 'Platform', 'CF-247 SS-021: job work-continuity', 'active', '{}', '20261104170000'),
 ('function', 'security.work_continuity_report_v1', 'Platform', 'CF-247 SS-021: the §9 lane metrics (in ops_report_v1)', 'active', '{}', '20261104170000'),
 ('function', 'security.course_relink_fair_run_v1', 'Platform', 'CF-247 SS-021: course-relink in turn, isolated, time-budgeted', 'active', '{security.course_relink_tick_v1 university loop}', '20261104170000'),
 ('function', 'security.course_relink_order_v1', 'Platform', 'CF-247 SS-021: course-relink fair order', 'active', '{}', '20261104170000'),
 ('function', 'security.work_relink_attribute_v1', 'Platform', 'CF-247 SS-021: course-relink time-out attribution', 'active', '{}', '20261104170000'),
 ('function', 'security.work_escalate_v1', 'Platform', 'CF-247 SS-021: one issue per unchanged blocker', 'active', '{}', '20261104170000')
on conflict do nothing;
