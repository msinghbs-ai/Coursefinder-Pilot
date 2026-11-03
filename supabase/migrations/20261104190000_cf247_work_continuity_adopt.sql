-- CF-247 SS-021 part 3: lanes adopt the shared work-continuity capability (20261104170000, v2.15.443) in the lanes the blocking audit ranked
-- worst after course-relink (admin docs/platform/nz-enrichment-brief/2026-11-03-work-continuity-blocking-audit.md F4, F3, F9, F2; overnight
-- mandate 2026-11-03-overnight-autonomous-execution-mandate-2159.md §2 P0 work continuity, P1 AER, §3 acceptance).
-- Why (live, read-only, 3 Nov 2026 21:21-22:10 AEDT):
--   * F4 (IQ-00128): security.aer_schedule_tick_v1 stops new course reads and due matrix refreshes for every provider when pending entry items
--     plus reads in progress reach aer.schedule_layer4_max (600). 573 were counted; 41 matrix items cover 19 entities (22 duplicates) and 18
--     are technical_blocked: they are not decisions a person can make, yet they hold the room for everyone.
--   * F3 (IQ-00130): 11 Find course pages tasks (admin_jobs kind course_page_find) are running, held up to 18.5 hours behind the course search
--     day cap while reporting waiting_turn (security.link_search_block_v1 lets a task with course ids past the day cap, the picker does not),
--     and each keeps its enrichment plan open (19 automatic plans running). Task 9433d1c4 is for a skip-listed university (held
--     skipped_provider, 231 courses) and can never run, yet it waits for its 24-hour end.
--   * F9 (IQ-00134): security.fee_reader_tick_v1 calls the fee worker only when no lease is live anywhere; security.course_link_search_tick_v1
--     re-sends an unanswered search every 20 minutes with no attempt cap, and one bad response body or bind refusal rolls back the harvest, the
--     move-on and the send for every university.
--   * F2 (IQ-00077): provider-identity-check failed 4 of 4 runs because security.integration_issue_upsert_v1 inserts root_cause_class 'data' and
--     workstream 'G', which the queue's checks refuse; every failed run also used up an issue number. The check's own values are fixed by the
--     Integration Controller in security.provider_identity_check_v1 (not edited here); this makes the governed writer tolerant instead.
-- What:
--   1 F4: pipeline.work_review_categories gains count_rule and count_switch_key (new columns beside the contract's). Category aer counts
--     distinct review-ready decisions (pending items not technical_blocked or resolvable, one per entity and kind) and distinct reads in
--     progress against the unchanged aer.schedule_layer4_max while wc.aer_fair_on is 1 (security.work_review_ready_v1, md5-guarded edit of
--     security.work_review_room_v1). security.aer_schedule_tick_v1 (md5-guarded edit) then takes its back-pressure from that room and its new
--     course reads through security.aer_fair_courses_v1: security.work_fair_pick_v1 with category aer (round-robin by university, never more
--     than the category's room), each university at most wc.aer_provider_share_pct of the limit, and the last wc.aer_new_provider_reserve_pct of
--     the room kept for universities with nothing waiting. Due matrix refreshes are not gated by the count unless their university has a
--     matrix item waiting (a refresh that could raise or duplicate a review item). Technically held and duplicate entry items are recorded for
--     bounded technical recovery (security.aer_technical_recovery_v1, lane aer_technical; classes technical_hold and duplicate), not counted as
--     decisions and never sent to Layer 4 by this change. Nothing approves, rejects or decides an entry requirement.
--   2 F3: security.page_find_continuity_v1 (job work-continuity-lanes): a running Find course pages task held while the course search cap is
--     reached (security.course_search_paid_cap_v1: the month cap, the Firecrawl hold of security.lane_paid_hold_v1, or the day's picked-courses
--     cap) is parked through security.work_item_report_v1 (budget, lane page_find) with its next eligible time at the cap reset; with
--     wc.page_find_release_on it is ended (failed, outcome deferred_dependency, the courses stay queued for the search lane) so its enrichment
--     plan gives back its slot and the plan's governed retry re-plans it. A task that can never run (held code in wc.page_find_never_codes, e.g.
--     skipped_provider) ends at once, failed with a recorded authority blocker (outcome blocked_policy).
--   3 F9: security.fee_reader_tick_v1 (md5-guarded edit) calls the worker while fewer than wc.fee_live_leases_max pages are leased
--     (wc.fee_item_claims_on; the worker already leases each page on its own, skip locked). security.course_link_search_tick_v1 (md5-guarded
--     edit): each harvested search and each move-on runs in its own block (a bad body or bind refusal sets back only that course, recorded with
--     its class); an unanswered search waits wc.link_search_resend_minutes, is recorded once per send (class search_unanswered) and re-sent
--     only when its work item is due again, and ends in error after wc.link_search_max_attempts sends (wc.link_search_continuity_on).
--   4 F2: security.integration_issue_upsert_v1 (md5-guarded edit) maps a root_cause_class, workstream or validation_layer that the queue's
--     check does not allow to unclassified, A10 or manual, keeps the value sent in evidence.unmapped, and no longer raises
--     (security.integration_issue_allowed_v1 reads the allowed values from the check itself).
-- Activation:
--   ON (record, park, release or schedule fairly; spend and admit nothing): wc.page_find_park_on, wc.page_find_never_end_on (ends a task that
--     can never run; it would end failed at tasks.lane_hold_max_hours anyway), wc.link_search_continuity_on (isolation and a send cap only cut
--     waste), the technical recovery record, the F2 mapping (always on: it only stops a report write aborting its run).
--   OFF (they change admission or spend): wc.aer_fair_on (more entry reads and matrix refreshes start while the raw count is at 600: AI and
--     Firecrawl spend, more Layer 4 items), wc.page_find_release_on (a freed plan slot lets the automatic planner open another plan),
--     wc.fee_item_claims_on (overlapping fee worker calls: AI spend sooner).
-- md5 (before = live, read 3 Nov 2026 22:01-22:10 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/continuity-adopt/run.sh):
--   security.integration_issue_upsert_v1(jsonb,text)  c5ce0cb9c431a337789d67bc1878be62 -> b0a1a64982680ae5d588c2d73b779e4e
--   security.work_review_room_v1(text)                a7542c70665220ba53a1d6e5bed05a1b -> 55413845185727480e5be78eb762d47c
--   security.aer_schedule_tick_v1(boolean)            bc28099db02a26344fae2527b624a8c7 -> 5b6a4f8a78f27ccc238a8d2824f11097
--   security.fee_reader_tick_v1()                     0c93b20de02d1714cd6672c259fddb20 -> 8116602b00bd4bb3972e16bd682d4c17
--   security.course_link_search_tick_v1(integer)      ffc9fb647925f689678a035cdd64b3e1 -> 71bf3bc46df97b90870a8bcf238a8a4a
-- Called, not edited (live md5): security.work_item_report_v1(text,text,text,text,jsonb) 6a15318c0ecd6644b32f1883463c542e,
--   security.work_fair_pick_v1(text,text,jsonb,integer) c1e63976b1ff6be67f5a4477baa09588, security.work_item_eligible_v1(text,text,text)
--   3d7b00a65efca566a464919c5aa3be6d, security.lane_paid_hold_v1(text) 99ec517b8b51b0d1305b739e7f1562fb.
-- Not edited: security.provider_identity_check_v1 (the Integration Controller ships its value fix), security.admin_job_watch_v1,
--   security.enrich_plan_tick_v1, security.enrich_plan_auto_v1, public.svc_course_link_search_next, public.svc_fee_ai_next.
-- Later migrations that md5-guard security.integration_issue_upsert_v1 must move to its new md5 (20261104120000 and 20261104170000 guard
--   c5ce0cb9 as a dependency; both are applied, so only a re-run or a new guard copying them is affected).
-- Consumer API (G3): untouched. No Firecrawl or AI spend while the OFF switches stay off.
-- Replaces: security.integration_issue_upsert_v1, security.work_review_room_v1, security.aer_schedule_tick_v1, security.fee_reader_tick_v1,
--   security.course_link_search_tick_v1 (same names; md5-guarded edits)
-- Retires: nothing (the previous AER count, fee single-flight and uncapped re-send stay reachable with their switches at 0 until retired after
--   the 24-hour production observation)
-- Nothing is dropped or deleted.

-- 0 the contract and the functions this change calls or edits, as read live ------------------------------------------------------------------
do $g$
declare r record;
begin
  if to_regclass('pipeline.work_items') is null or to_regprocedure('security.work_fair_pick_v1(text,text,jsonb,integer)') is null then
    raise exception 'the SS-021 work continuity contract (migration 20261104170000) must be applied before this change';
  end if;
  for r in select * from (values ('security.work_item_report_v1(text,text,text,text,jsonb)', '6a15318c0ecd6644b32f1883463c542e'),
                                 ('security.work_fair_pick_v1(text,text,jsonb,integer)', 'c1e63976b1ff6be67f5a4477baa09588'),
                                 ('security.work_item_eligible_v1(text,text,text)', '3d7b00a65efca566a464919c5aa3be6d'),
                                 ('security.lane_paid_hold_v1(text)', '99ec517b8b51b0d1305b739e7f1562fb')) v(sig, m) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
  -- called through their interfaces only (not edited here; their owners may change their bodies)
  for r in select * from (values ('security.aer_schedule_courses_v1(integer,boolean)'), ('security.admin_job_close_v1(uuid)'),
                                 ('security.job_outcome_set_v1(uuid,text,jsonb)'), ('security.pipeline_list_v1(text,jsonb)'),
                                 ('security.ops_root_cause_register_v1(text,jsonb)'), ('security.ops_remedy_register_v1(text,jsonb)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
  end loop;
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
 ('pipeline', 'wc.aer_fair_on', 'Work continuity: AER counts review-ready decisions and takes universities in turn',
  'On (1): scheduled entry reading counts distinct review-ready decisions (and distinct reads in progress) against the unchanged Layer 4 limit (aer.schedule_layer4_max), takes new course reads university by university within each university''s share and the new-university reserve, and refreshes due matrices unless their university has a matrix item waiting. Off (0): every waiting item counts and a full queue stops all reads and refreshes (as before).',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1320, 'Work continuity', 'security.aer_schedule_tick_v1; security.work_review_room_v1 (category aer)', 'SS-021 F4 (IQ-00128): more reads start while the raw count is at the limit (AI spend), so it ships off'),
 ('pipeline', 'wc.aer_provider_share_pct', 'Work continuity: one university''s share of the AER limit',
  'A university with this share of the Layer 4 entry limit already waiting or being read gets no new course read until some are decided.',
  'number', to_jsonb(10), 1, 100, '% of the limit', 1321, 'Work continuity', 'security.aer_fair_courses_v1', 'SS-021 F4: one university cannot take the room'),
 ('pipeline', 'wc.aer_new_provider_reserve_pct', 'Work continuity: AER room kept for universities with nothing waiting',
  'When the room left under the Layer 4 entry limit is this share of the limit or less, only universities with nothing waiting or being read get new course reads.',
  'number', to_jsonb(10), 0, 50, '% of the limit', 1322, 'Work continuity', 'security.aer_fair_courses_v1', 'SS-021 F4: keep room for newly discovered universities'),
 ('pipeline', 'wc.aer_candidate_factor', 'Work continuity: AER candidates looked at per course read',
  'The fair selection looks at this many eligible courses for each course read it may start, so it can take universities in turn.',
  'number', to_jsonb(5), 2, 20, 'courses per read', 1323, 'Work continuity', 'security.aer_fair_courses_v1', 'SS-021 F4'),
 ('pipeline', 'wc.aer_tech_max_attempts', 'Work continuity: re-checks of a technically held entry item',
  'A Layer 4 entry item held for a technical reason is checked again at each backoff; after this many checks still held it is parked and raised once for a release.',
  'number', to_jsonb(3), 1, 10, 'checks', 1324, 'Work continuity', 'security.aer_technical_recovery_v1 (class technical_hold)', 'SS-021 F4 "bounded technical recovery"'),
 ('pipeline', 'wc.page_find_park_on', 'Work continuity: park Find course pages behind the search cap',
  'On (1): a Find course pages task held while the course search cap is reached is recorded as parked until the cap resets (lane page_find). Off (0): not recorded.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1325, 'Work continuity', 'security.page_find_continuity_v1 (job work-continuity-lanes)', 'SS-021 F3 (IQ-00130): records only, ships on'),
 ('pipeline', 'wc.page_find_release_on', 'Work continuity: parked Find course pages give back their plan',
  'On (1): a parked Find course pages task is ended (its courses stay queued for the search lane) so its enrichment plan gives back its slot and the plan''s retry re-plans it after the reset. Off (0): the task stays running until the cap resets or its hold ends.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1326, 'Work continuity', 'security.page_find_continuity_v1 (job work-continuity-lanes)', 'SS-021 F3: a freed slot lets the planner open another plan (admission), so it ships off'),
 ('pipeline', 'wc.page_find_never_end_on', 'Work continuity: end Find course pages that can never run',
  'On (1): a Find course pages task held for a reason listed in wc.page_find_never_codes ends at once, failed, with the blocker recorded for a decision. Off (0): it waits for its hold to end.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1327, 'Work continuity', 'security.page_find_continuity_v1 (job work-continuity-lanes)', 'SS-021 F3: the task would end failed at tasks.lane_hold_max_hours anyway; ships on'),
 ('pipeline', 'wc.page_find_never_codes', 'Work continuity: Find course pages holds that can never clear by themselves',
  'Hold codes (security.link_search_block_v1) that only a person''s change can clear; a task held for one of them ends at once with the blocker recorded.',
  'list', '["skipped_provider", "directory_site"]'::jsonb, null, null, 'hold codes', 1328, 'Work continuity', 'security.page_find_continuity_v1', 'SS-021 F3'),
 ('pipeline', 'wc.fee_item_claims_on', 'Work continuity: fee reader works page by page',
  'On (1): the fee worker is called while pages are due and fewer than wc.fee_live_leases_max pages are leased (each page is claimed on its own). Off (0): only when no page is leased anywhere (as before).',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1329, 'Work continuity', 'security.fee_reader_tick_v1', 'SS-021 F9 (IQ-00134): overlapping worker calls spend AI sooner, so it ships off'),
 ('pipeline', 'wc.fee_live_leases_max', 'Work continuity: fee pages leased at once',
  'With wc.fee_item_claims_on, the fee worker is called again only while fewer than this many pages are leased.',
  'number', to_jsonb(6), 1, 50, 'pages', 1330, 'Work continuity', 'security.fee_reader_tick_v1', 'SS-021 F9'),
 ('pipeline', 'wc.link_search_continuity_on', 'Work continuity: course page searches isolated and capped',
  'On (1): each harvested course page search and each move-on runs on its own (a bad answer sets back only that course), and an unanswered search is re-sent only when its next attempt is due, at most wc.link_search_max_attempts times. Off (0): one failure rolls back the run and unanswered searches are re-sent without a cap (as before).',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1331, 'Work continuity', 'security.course_link_search_tick_v1', 'SS-021 F9: isolation and a cap only cut waste; ships on'),
 ('pipeline', 'wc.link_search_max_attempts', 'Work continuity: sends of one course page search',
  'A course page search that has failed or gone unanswered this many times ends in error and is parked with its evidence.',
  'number', to_jsonb(3), 1, 10, 'sends', 1332, 'Work continuity', 'security.course_link_search_tick_v1 (class search_unanswered)', 'SS-021 F9 "attempt cap"'),
 ('pipeline', 'wc.link_search_resend_minutes', 'Work continuity: wait for a course page search answer',
  'A search with no answer after this long counts as unanswered.',
  'number', to_jsonb(20), 5, 240, 'minutes', 1333, 'Work continuity', 'security.course_link_search_tick_v1', 'SS-021 F9: was 20 minutes in code')
on conflict do nothing;

-- 2 recovery policies for the adopted lanes (rows beside the contract's) ------------------------------------------------------------------
insert into pipeline.work_recovery_policies(failure_class, title, action, counts_attempt, max_attempts_key, recheck_key, escalate_as, escalate_when, root_cause, description) values
 ('technical_hold', 'A Layer 4 item is held for a technical reason', 'retry_backoff', true, 'wc.aer_tech_max_attempts', null, 'release', 'exhausted', 'work_technical_hold',
  'Checked again after each backoff (wc.backoff_* settings) while its readiness stays technical_blocked; repaired on the route its readiness names, never decided by a person; parked and raised once after wc.aer_tech_max_attempts checks.'),
 ('duplicate', 'A Layer 4 item duplicates an older waiting item', 'park', false, null, null, 'policy', 'always', 'work_duplicate_review',
  'The older item stays the decision; the duplicate is parked with the evidence and is not counted as a decision. Settling it is the Layer 4 reconciliation (layer4.reconcile_supersede_on), never this lane.'),
 ('search_unanswered', 'A course page search failed or went unanswered', 'retry_backoff', true, 'wc.link_search_max_attempts', null, 'release', 'exhausted', 'work_search_unanswered',
  'Re-sent only when its next attempt is due (wc.backoff_* settings), at most wc.link_search_max_attempts times; then the search ends in error and is parked with the evidence.')
on conflict (failure_class) do nothing;

-- 3 review categories: how a category counts (new columns beside the contract's) ---------------------------------------------------------
alter table pipeline.work_review_categories add column if not exists count_rule text not null default 'raw';
alter table pipeline.work_review_categories add column if not exists count_switch_key text;
do $k$ begin
  if not exists (select 1 from pg_constraint where conname = 'work_review_categories_count_rule_check') then
    alter table pipeline.work_review_categories add constraint work_review_categories_count_rule_check check (count_rule in ('raw', 'distinct_ready'));
  end if;
end $k$;
comment on column pipeline.work_review_categories.count_rule is 'CF-247 SS-021 F4: raw (every waiting item and read in progress counts) or distinct_ready (while count_switch_key is 1: distinct review-ready decisions, one per entity and kind, not technical_blocked or resolvable, plus distinct reads in progress). The limit itself is never changed.';
comment on column pipeline.work_review_categories.count_switch_key is 'CF-247 SS-021 F4: the setting that switches count_rule distinct_ready on (raw while it is 0).';
update pipeline.work_review_categories set count_rule = 'distinct_ready', count_switch_key = 'wc.aer_fair_on'
 where category = 'aer' and count_rule = 'raw' and count_switch_key is null;

-- 4 functions ---------------------------------------------------------------------------------------------------------------------------
create or replace function security.integration_issue_allowed_v1(p_check text, p_value text) returns boolean
language sql stable security definer set search_path to '' as $function$
-- CF-247 SS-021 F2: whether a value is one the named check on pipeline.integration_issues allows (its quoted literals). A check that does not
-- exist does not restrict the value.
  select coalesce((select p_value = any (array(select m[1] from regexp_matches(pg_get_constraintdef(c.oid), '''([^'']*)''', 'g') m))
                     from pg_constraint c where c.conrelid = 'pipeline.integration_issues'::regclass and c.conname = p_check), true)
$function$;
revoke all on function security.integration_issue_allowed_v1(text, text) from public, anon, authenticated;

create or replace function security.work_review_ready_v1(p_category text) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- CF-247 SS-021 F4: a review category's waiting items by readiness (pipeline.layer4_item_readiness; an item not yet classified counts as
-- ready): distinct review-ready decisions (one per entity and kind), technically held, resolvable and duplicate items, and distinct reads in
-- progress. Read only.
  with c as (select * from pipeline.work_review_categories where category = p_category),
       w as (select i.id, i.entity_id, i.field_code, x.readiness,
                    row_number() over (partition by i.entity_id, i.field_code order by i.created_at, i.id) rn
               from pipeline.layer4_review_items i left join pipeline.layer4_item_readiness x on x.item_id = i.id, c
              where i.status = 'pending' and i.field_code = any (c.field_codes))
  select jsonb_build_object('category', p_category,
    'raw_waiting', (select count(*) from w),
    'ready_waiting', (select count(*) from w where w.rn = 1 and coalesce(w.readiness, 'judgement_ready') not in ('technical_blocked', 'resolvable', 'closed')),
    'technical', (select count(*) from w where w.readiness = 'technical_blocked'),
    'resolvable', (select count(*) from w where w.readiness = 'resolvable'),
    'duplicates', (select count(*) from w where w.rn > 1),
    'in_progress', (select count(distinct coalesce(f.course_id, f.provider_id)) from pipeline.field_enrich_items f, c
                     where cardinality(c.in_progress_fields) > 0 and f.field = any (c.in_progress_fields) and f.state in ('queued', 'waiting', 'ai', 'leased')))
$function$;
revoke all on function security.work_review_ready_v1(text) from public, anon, authenticated;

create or replace function security.aer_provider_load_v1() returns table(provider_id uuid, waiting bigint)
language sql stable security definer set search_path to '' as $function$
-- CF-247 SS-021 F4: each university's distinct review-ready AER decisions waiting plus distinct entry reads in progress (the share check).
  select z.pid, count(distinct z.k) from (
    select coalesce(c.provider_id, case when i.entity_type = 'provider' then i.entity_id end) pid, i.field_code || ':' || i.entity_id k
      from pipeline.layer4_review_items i left join pipeline.layer4_item_readiness x on x.item_id = i.id
      left join catalogue.courses c on i.entity_type = 'course' and c.id = i.entity_id
      join pipeline.work_review_categories rc on rc.category = 'aer'
     where i.status = 'pending' and i.field_code = any (rc.field_codes) and coalesce(x.readiness, 'judgement_ready') not in ('technical_blocked', 'resolvable', 'closed')
    union all
    select f.provider_id, 'read:' || coalesce(f.course_id, f.provider_id)
      from pipeline.field_enrich_items f join pipeline.work_review_categories rc on rc.category = 'aer'
     where f.field = any (rc.in_progress_fields) and f.state in ('queued', 'waiting', 'ai', 'leased')) z
   where z.pid is not null group by z.pid
$function$;
revoke all on function security.aer_provider_load_v1() from public, anon, authenticated;

create or replace function security.aer_fair_courses_v1(p_room int)
returns table(course_id uuid, provider_id uuid, country text, provider_name text, tier integer, turn bigint)
language plpgsql security definer set search_path to '' as $function$
-- CF-247 SS-021 F4 (wc.aer_fair_on): the courses security.aer_schedule_tick_v1 reads next, taken fairly: the eligible courses of
-- security.aer_schedule_courses_v1, less universities at their share of the limit (wc.aer_provider_share_pct) and, once the room is down to
-- the reserve (wc.aer_new_provider_reserve_pct), less every university with something waiting; then security.work_fair_pick_v1 with category
-- aer (round-robin by university, least recently served first, never more than the category's room). Twice p_room are returned so courses the
-- item gate holds can be passed over (the tick stops at p_room).
declare v_lim numeric := security.pipeline_num_v1('aer.schedule_layer4_max', 600);
        v_share int := greatest(1, ceil(v_lim * security.pipeline_num_v1('wc.aer_provider_share_pct', 10) / 100.0))::int;
        v_reserve numeric := ceil(v_lim * security.pipeline_num_v1('wc.aer_new_provider_reserve_pct', 10) / 100.0);
        v_room numeric := coalesce((security.work_review_room_v1('aer')->>'room')::numeric, 0);
        v_cands jsonb;
begin
  if coalesce(p_room, 0) <= 0 or v_room <= 0 then return; end if;
  create temp table if not exists aer_fair_cands (course_id uuid, provider_id uuid, country text, provider_name text, tier integer, turn bigint, n bigint) on commit drop;
  truncate aer_fair_cands;
  insert into aer_fair_cands
  select c.course_id, c.provider_id, c.country, c.provider_name, c.tier, c.turn, row_number() over ()
    from security.aer_schedule_courses_v1((p_room * security.pipeline_num_v1('wc.aer_candidate_factor', 5))::int) c;
  select jsonb_agg(jsonb_build_object('entity', e.course_id::text, 'provider_id', e.provider_id, 'field', 'entry_requirements', 'category', 'aer', 'priority', -e.n) order by e.n)
    into v_cands
    from (select a.*, row_number() over (partition by a.provider_id order by a.n) k, coalesce(l.waiting, 0) waiting
            from aer_fair_cands a left join security.aer_provider_load_v1() l on l.provider_id = a.provider_id) e
   where e.waiting + e.k <= v_share and (v_room > v_reserve or e.waiting = 0);
  return query
    select a.course_id, a.provider_id, a.country, a.provider_name, a.tier, a.turn
      from security.work_fair_pick_v1('aer', 'entry_read', coalesce(v_cands, '[]'::jsonb), p_room * 2) p  -- fixed: twice the room, as the tick's own selection
      join aer_fair_cands a on a.course_id::text = p.entity
     order by p.pos;
end $function$;
revoke all on function security.aer_fair_courses_v1(int) from public, anon, authenticated;

create or replace function security.aer_technical_recovery_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 SS-021 F4: Layer 4 entry items that are not decisions are recorded for bounded technical recovery (lane aer_technical), not counted
-- and not sent anywhere: technically held items (readiness technical_blocked) are checked again at each backoff and parked after
-- wc.aer_tech_max_attempts; duplicates (a later waiting item for the same entity and kind) are parked once; an item that becomes ready, closes
-- or leaves the queue is recovered. Records only: no Layer 4 item, decision or value is changed.
declare v_n int := security.pipeline_num_v1('wc.tick_batch', 500)::int; r record; v_t int := 0; v_d int := 0; v_ok int := 0;
begin
  if security.pipeline_num_v1('wc.on', 1) < 1 then return jsonb_build_object('held', 'wc.on is 0'); end if;
  for r in select i.id, i.entity_id, i.entity_type, i.field_code, x.reasons, x.route, x.blockers, c.provider_id
             from pipeline.layer4_review_items i join pipeline.layer4_item_readiness x on x.item_id = i.id
             left join catalogue.courses c on i.entity_type = 'course' and c.id = i.entity_id
             join pipeline.work_review_categories rc on rc.category = 'aer'
            where i.status = 'pending' and i.field_code = any (rc.field_codes) and x.readiness = 'technical_blocked'
              and security.work_item_eligible_v1('aer_technical', i.id::text, 'l4_item')
            order by i.created_at, i.id limit v_n loop
    perform security.work_item_report_v1('aer_technical', r.id::text, 'l4_item', 'failed', jsonb_build_object(
              'class', 'technical_hold', 'owner', 'aer-scheduled-read', 'field', r.field_code,
              'provider_id', coalesce(r.provider_id, case when r.entity_type = 'provider' then r.entity_id end),
              'message', 'technically held: ' || coalesce(array_to_string(r.reasons, ', '), 'no reason'),
              'evidence', jsonb_build_object('route', r.route, 'blockers', r.blockers)));
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
    v_d := v_d + 1;
  end loop;
  for r in select w.entity from pipeline.work_items w
            where w.lane = 'aer_technical' and w.work_kind = 'l4_item' and w.stage <> 'done'
              and not exists (select 1 from pipeline.layer4_review_items i left join pipeline.layer4_item_readiness x on x.item_id = i.id
                               where i.id::text = w.entity and i.status = 'pending'
                                 and (case when w.failure_class = 'duplicate' then true else x.readiness = 'technical_blocked' end))
            limit v_n loop
    perform security.work_item_report_v1('aer_technical', r.entity, 'l4_item', 'succeeded', jsonb_build_object('outcome', 'succeeded_with_result'));
    v_ok := v_ok + 1;
  end loop;
  return jsonb_build_object('technical_checked', v_t, 'duplicates_parked', v_d, 'recovered', v_ok);
end $function$;
revoke all on function security.aer_technical_recovery_v1() from public, anon, authenticated;

create or replace function security.course_search_paid_cap_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 SS-021 F3: why the course page search lane can pick nothing now, by the picker's own caps (public.svc_course_link_search_next): the
-- month cap, the Firecrawl hold (security.lane_paid_hold_v1: month reserve or today's share) and today's picked-courses cap
-- (search.daily_picked_cap, UTC day); null when none holds. resumes_at is when the cap resets. Read only.
declare v_cap numeric; v_used numeric; v_hold text; v_picked bigint;
        v_day timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
        v_month timestamptz := date_trunc('month', now()) + interval '1 month';  -- fixed: the month roll-over
begin
  select s.monthly_credit_cap into v_cap from pipeline.course_link_search_settings s where s.id = 1;
  select coalesce(sum(u.units), 0) into v_used from pipeline.coverage_vendor_usage u where u.purpose = 'course_link_search' and u.at >= date_trunc('month', now());
  if v_cap is not null and v_used + 2 > v_cap then  -- fixed: one search's credits, as the picker counts them
    return jsonb_build_object('code', 'month_cap', 'words', 'this month''s course search credits are used', 'resumes_at', v_month);
  end if;
  v_hold := security.lane_paid_hold_v1('course_link_search');
  if v_hold is not null then
    return jsonb_build_object('code', 'paid_hold', 'words', v_hold, 'resumes_at', case when v_hold ~* 'month|reserve' then v_month else v_day + interval '1 day' end);  -- fixed: the day roll-over
  end if;
  select count(*) into v_picked from pipeline.course_link_search s where s.sent_at >= v_day;
  if v_picked >= security.pipeline_num_v1('search.daily_picked_cap', 100) then
    return jsonb_build_object('code', 'daily_cap', 'words', 'today''s course search cap (' || security.pipeline_num_v1('search.daily_picked_cap', 100)::int || ' courses) is reached',
                              'picked', v_picked, 'resumes_at', v_day + interval '1 day');  -- fixed: the UTC day roll-over of the cap
  end if;
  return null;
end $function$;
revoke all on function security.course_search_paid_cap_v1() from public, anon, authenticated;

create or replace function security.link_search_park_v1(p_course uuid, p_sends int) returns void
language plpgsql security definer set search_path to '' as $function$
-- CF-247 SS-021 F9: a course page search whose row reached wc.link_search_max_attempts sends (counted on the search row, including sends made
-- before the lane reported its work) ends in error: its work item is parked with the evidence so the blocker is raised once (class
-- search_unanswered, escalated for a release) and nothing re-sends it.
begin
  update pipeline.work_items w set stage = 'parked', next_eligible_at = null, lease_until = null, outcome = 'blocked_evidence',
         unresolved_blocker = jsonb_build_object('class', w.failure_class, 'title', 'A course page search failed or went unanswered',
                                                 'reason', 'send cap reached (' || p_sends || ' sends)', 'escalate_as', 'release', 'at', now()),
         updated_at = now()
   where w.lane = 'course_link_search' and w.entity = p_course::text and w.work_kind = 'search' and w.stage in ('retry_wait', 'eligible', 'deferred');
end $function$;
revoke all on function security.link_search_park_v1(uuid, int) from public, anon, authenticated;

create or replace function security.page_find_continuity_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 SS-021 F3 (job work-continuity-lanes): running Find course pages tasks (admin_jobs kind course_page_find), each in its own block.
--   * held for a reason in wc.page_find_never_codes (wc.page_find_never_end_on): ended at once, failed, with the blocker recorded (lane
--     page_find, class authority) and outcome blocked_policy;
--   * held while the course search cap is reached (wc.page_find_park_on): parked through security.work_item_report_v1 (budget, lane
--     page_find) with its next eligible time at the cap reset, once per cap period; with wc.page_find_release_on also ended (failed, outcome
--     deferred_dependency) so its plan gives back its slot; its courses stay queued for the search lane;
--   * moving again after a park: recovered.
-- Spends nothing; it never queues, sends or removes a search.
declare v_cap jsonb := security.course_search_paid_cap_v1();
        v_never text[] := security.pipeline_list_v1('wc.page_find_never_codes', '["skipped_provider", "directory_site"]'::jsonb);
        r record; v_code text; v_words text; v_at timestamptz; v_note text; v_end int := 0; v_park int := 0; v_rel int := 0; v_rec int := 0; v_err jsonb := '[]'::jsonb;
begin
  if security.pipeline_num_v1('wc.on', 1) < 1 then return jsonb_build_object('held', 'wc.on is 0'); end if;
  v_at := (v_cap->>'resumes_at')::timestamptz;
  for r in select j.id, nullif(j.args->>'provider_id', '')::uuid pid, j.result->'held' held, j.result->'blocked' blocked,
                  coalesce((j.result->>'unprocessed')::int, 0) n_left
             from pipeline.admin_jobs j where j.kind = 'course_page_find' and j.state = 'running'
            order by j.started_at nulls last, j.id limit security.pipeline_num_v1('wc.tick_batch', 500)::int loop
    begin
      v_code := coalesce(r.blocked->>'code', r.held->>'code');
      if r.pid is null then continue; end if;
      if r.held is not null and v_code = any (v_never) and security.pipeline_num_v1('wc.page_find_never_end_on', 1) >= 1 then
        v_words := coalesce(r.blocked->>'words', r.held->>'reason', v_code);
        perform security.work_item_report_v1('page_find', r.pid::text, 'find', 'failed', jsonb_build_object('class', 'authority', 'provider_id', r.pid,
                  'owner', 'course-page-find', 'message', 'cannot run: ' || v_words,
                  'evidence', jsonb_build_object('task', r.id, 'code', v_code, 'fix', r.blocked->>'fix', 'unprocessed', r.n_left)));
        v_note := left('Cannot run: ' || v_words || '. ' || coalesce(r.blocked->>'fix', '') || ' (' || r.n_left || ' course(s) not searched; recorded for a decision)', 500);
        update pipeline.admin_jobs set state = 'failed', error = v_note, finished_at = now(), updated_at = now(),
               result = coalesce(result, '{}'::jsonb) || jsonb_build_object('end_state', 'failed', 'note', v_note, 'blocker', jsonb_build_object('code', v_code, 'words', v_words, 'fix', r.blocked->>'fix'))
         where id = r.id and state = 'running';
        insert into pipeline.admin_job_events(job_id, note) values (r.id, v_note);
        perform security.admin_job_close_v1(r.id);
        perform security.job_outcome_set_v1(r.id, 'blocked_policy', jsonb_build_object('reason', 'cannot run', 'code', v_code, 'by', 'work-continuity-lanes'));
        v_end := v_end + 1;
      elsif r.held is not null and v_cap is not null and security.pipeline_num_v1('wc.page_find_park_on', 1) >= 1 then
        if not exists (select 1 from pipeline.work_items w where w.lane = 'page_find' and w.entity = r.pid::text and w.work_kind = 'find'
                         and w.stage = 'deferred' and w.failure_class = 'budget_exhausted' and w.next_eligible_at = v_at) then
          perform security.work_item_report_v1('page_find', r.pid::text, 'find', 'budget', jsonb_build_object('purpose', 'course_link_search', 'provider_id', r.pid,
                    'owner', 'course-page-find', 'message', 'held behind the course search cap: ' || (v_cap->>'words'),
                    'evidence', jsonb_build_object('task', r.id, 'cap', v_cap, 'held_as', v_code, 'unprocessed', r.n_left)));
          update pipeline.work_items w set next_eligible_at = v_at, updated_at = now()
           where w.lane = 'page_find' and ((w.entity = r.pid::text and w.work_kind = 'find') or (w.entity = '*lane' and w.work_kind = 'lane'))
             and w.stage in ('deferred', 'lane_paused');
          v_park := v_park + 1;
        end if;
        if security.pipeline_num_v1('wc.page_find_release_on', 0) >= 1 then
          v_note := left('Parked: ' || (v_cap->>'words') || '; resumes ' || to_char(v_at at time zone 'Australia/Melbourne', 'DD Mon HH24:MI')
                         || '. ' || r.n_left || ' course(s) stay queued for the search lane; the plan''s retry starts it again', 500);
          update pipeline.admin_jobs set state = 'failed', error = v_note, finished_at = now(), updated_at = now(),
                 result = coalesce(result, '{}'::jsonb) || jsonb_build_object('end_state', 'failed', 'note', v_note, 'parked', jsonb_build_object('cap', v_cap, 'resumes_at', v_at))
           where id = r.id and state = 'running';
          insert into pipeline.admin_job_events(job_id, note) values (r.id, v_note);
          perform security.admin_job_close_v1(r.id);
          perform security.job_outcome_set_v1(r.id, 'deferred_dependency', jsonb_build_object('reason', 'paid cap', 'cap', v_cap, 'by', 'work-continuity-lanes'));
          v_rel := v_rel + 1;
        end if;
      elsif r.held is null and exists (select 1 from pipeline.work_items w where w.lane = 'page_find' and w.entity = r.pid::text and w.work_kind = 'find'
                                         and w.failure_class = 'budget_exhausted' and w.stage <> 'done') then
        perform security.work_item_report_v1('page_find', r.pid::text, 'find', 'succeeded', jsonb_build_object('outcome', 'succeeded_with_result', 'provider_id', r.pid));
        v_rec := v_rec + 1;
      end if;
    exception when others then
      v_err := v_err || jsonb_build_object('task', r.id, 'error', left(sqlerrm, 200));
    end;
  end loop;
  return jsonb_build_object('cap', v_cap, 'ended_cannot_run', v_end, 'parked', v_park, 'released', v_rel, 'recovered', v_rec, 'errors', v_err);
end $function$;
revoke all on function security.page_find_continuity_v1() from public, anon, authenticated;

-- 5 md5-guarded edits ---------------------------------------------------------------------------------------------------------------------
-- 5.1 F2: the governed issue writer maps values its checks refuse
select pg_temp.edit_once('security.integration_issue_upsert_v1(jsonb,text)', 'c5ce0cb9c431a337789d67bc1878be62', 'b0a1a64982680ae5d588c2d73b779e4e',
  array[array[$o$        r pipeline.integration_issues; v_new_prov uuid[]; v_new_course uuid[]; v_more boolean; v_action text; v_status text;
$o$, $n$        r pipeline.integration_issues; v_new_prov uuid[]; v_new_course uuid[]; v_more boolean; v_action text; v_status text;
        v_rcc text; v_ws text; v_vl text; v_unmapped jsonb := '{}'::jsonb;
$n$],
        array[$o$    if v_status not in ('detected', 'triaged', 'assigned', 'in_progress') then raise exception 'a new issue starts as detected, triaged, assigned or in_progress' using errcode = '22023'; end if;
$o$, $n$    if v_status not in ('detected', 'triaged', 'assigned', 'in_progress') then raise exception 'a new issue starts as detected, triaged, assigned or in_progress' using errcode = '22023'; end if;
    -- 4 Nov 2026 (SS-021 F2, IQ-00077): a root cause class, workstream or validation layer the queue's checks refuse is mapped (unclassified, A10,
    -- manual) and the value sent is kept in evidence.unmapped, so a reporting job's own issue write never aborts its run
    v_rcc := coalesce(nullif(p->>'root_cause_class', ''), 'unclassified');
    v_ws := coalesce(nullif(p->>'workstream', ''), 'A10');
    v_vl := coalesce(nullif(p->>'validation_layer', ''), 'manual');
    if not security.integration_issue_allowed_v1('integration_issues_root_cause_class_check', v_rcc) then
      v_unmapped := v_unmapped || jsonb_build_object('root_cause_class', v_rcc); v_rcc := 'unclassified'; end if;
    if not security.integration_issue_allowed_v1('integration_issues_workstream_check', v_ws) then
      v_unmapped := v_unmapped || jsonb_build_object('workstream', v_ws); v_ws := 'A10'; end if;
    if not security.integration_issue_allowed_v1('integration_issues_validation_layer_check', v_vl) then
      v_unmapped := v_unmapped || jsonb_build_object('validation_layer', v_vl); v_vl := 'manual'; end if;
    if v_unmapped <> '{}'::jsonb then v_unmapped := jsonb_build_object('unmapped', v_unmapped); end if;
$n$],
        array[$o$coalesce(nullif(p->>'validation_layer', ''), 'manual'), coalesce(p->'evidence', '{}'::jsonb), v_refs,
           coalesce(nullif(p->>'root_cause_class', ''), 'unclassified'), v_sev, p->>'impact', coalesce(nullif(p->>'workstream', ''), 'A10'), v_blk, v_deps,$o$,
              $n$v_vl, coalesce(p->'evidence', '{}'::jsonb) || v_unmapped, v_refs,
           v_rcc, v_sev, p->>'impact', v_ws, v_blk, v_deps,$n$]], array[1, 1, 1]);

-- 5.2 F4: a review category counts by its rule
select pg_temp.edit_once('security.work_review_room_v1(text)', 'a7542c70665220ba53a1d6e5bed05a1b', '55413845185727480e5be78eb762d47c',
  array[array[$o$declare c pipeline.work_review_categories; v_limit numeric; v_wait int; v_prog int := 0;
$o$, $n$declare c pipeline.work_review_categories; v_limit numeric; v_wait int; v_prog int := 0; v_rdy jsonb;
$n$],
        array[$o$  return jsonb_build_object('category', p_category, 'known', true, 'limit_key', c.limit_key, 'limit', v_limit, 'waiting', v_wait, 'in_progress', v_prog,
$o$, $n$  -- 4 Nov 2026 (SS-021 F4): a category whose count rule is distinct_ready, while its switch is on, counts distinct review-ready decisions and
  -- distinct reads in progress against the same limit; technically held, resolvable and duplicate items are reported, not counted
  if c.count_rule = 'distinct_ready' and c.count_switch_key is not null and security.pipeline_num_v1(c.count_switch_key, 0) >= 1 then
    v_rdy := security.work_review_ready_v1(p_category);
    return jsonb_build_object('category', p_category, 'known', true, 'limit_key', c.limit_key, 'limit', v_limit, 'count_rule', 'distinct_ready',
                              'waiting', (v_rdy->>'ready_waiting')::int, 'in_progress', (v_rdy->>'in_progress')::int, 'raw_waiting', v_wait, 'raw_in_progress', v_prog,
                              'technical', (v_rdy->>'technical')::int, 'resolvable', (v_rdy->>'resolvable')::int, 'duplicates', (v_rdy->>'duplicates')::int,
                              'room', case when v_limit is null then null else greatest(v_limit - (v_rdy->>'ready_waiting')::int - (v_rdy->>'in_progress')::int, 0) end);
  end if;
  return jsonb_build_object('category', p_category, 'known', true, 'limit_key', c.limit_key, 'limit', v_limit, 'waiting', v_wait, 'in_progress', v_prog,
$n$]], array[1, 1]);

-- 5.3 F4: scheduled entry reading by readiness, in turn, with refreshes not gated by the count
select pg_temp.edit_once('security.aer_schedule_tick_v1(boolean)', 'bc28099db02a26344fae2527b624a8c7', '5b6a4f8a78f27ccc238a8d2824f11097',
  array[array[$o$        v_checked jsonb := '[]'::jsonb; v_nh int := 0; v_nn int := 0; v_nm int := 0; v_fc int := 0; v_est numeric;
$o$, $n$        v_checked jsonb := '[]'::jsonb; v_nh int := 0; v_nn int := 0; v_nm int := 0; v_fc int := 0; v_est numeric;
        v_fair boolean := security.pipeline_num_v1('wc.aer_fair_on', 0) >= 1; v_rr jsonb; v_tech jsonb;
$n$],
        array[$o$  v_bp := v_l4 + v_prog >= v_l4max;
$o$, $n$  v_bp := v_l4 + v_prog >= v_l4max;
  -- 4 Nov 2026 (SS-021 F4, IQ-00128; wc.aer_fair_on): the same limit (aer.schedule_layer4_max, never raised or bypassed) counts distinct
  -- review-ready decisions and distinct reads in progress (security.work_review_room_v1, category aer); technically held and duplicate items
  -- are recorded for bounded technical recovery below, not counted
  if v_fair then
    v_rr := security.work_review_room_v1('aer');
    v_bp := coalesce((v_rr->>'room')::numeric, 0) <= 0;
  end if;
$n$],
        array[$o$      for r in select * from security.aer_schedule_courses_v1((v_room - v_nh) * 2) loop  -- fixed: twice the room, so courses the item gate holds can be passed over
$o$, $n$      -- 4 Nov 2026 (SS-021 F4, wc.aer_fair_on): university by university within its share and the new-university reserve (security.aer_fair_courses_v1)
      for r in select * from security.aer_schedule_courses_v1((v_room - v_nh) * 2) where not v_fair  -- fixed: twice the room, so courses the item gate holds can be passed over
               union all select * from security.aer_fair_courses_v1(v_room - v_nh) where v_fair loop
$n$],
        array[$o$          v_nn := v_nn + 1;
        exception when others then
          v_skip := v_skip || jsonb_build_object('course_id', r.course_id, 'why', left(sqlerrm, 300));
$o$, $n$          v_nn := v_nn + 1;
          if v_fair then
            perform security.work_item_report_v1('aer', r.course_id::text, 'entry_read', 'claimed', jsonb_build_object('provider_id', r.provider_id, 'field', 'entry_requirements', 'owner', 'aer-scheduled-read'));
            perform security.work_item_report_v1('aer', r.course_id::text, 'entry_read', 'succeeded', jsonb_build_object('provider_id', r.provider_id, 'field', 'entry_requirements', 'outcome', 'succeeded_with_result'));
          end if;
        exception when others then
          v_skip := v_skip || jsonb_build_object('course_id', r.course_id, 'why', left(sqlerrm, 300));
$n$],
        array[$o$  if not v_bp and v_aim is null and v_mxmax > 0 then
    for r in select s.id, s.provider_id, s.read_via from pipeline.entry_matrix_sources s
              where s.status = 'read' and s.read_via <> 'stored'
$o$, $n$  -- 4 Nov 2026 (SS-021 F4, wc.aer_fair_on): a refresh is gated by the count only when its university has a matrix item waiting (a refresh that
  -- could raise or duplicate a review item); other due refreshes go ahead within batch.aer_schedule_matrix and the AI guard
  if (not v_bp or v_fair) and v_aim is null and v_mxmax > 0 then
    for r in select s.id, s.provider_id, s.read_via from pipeline.entry_matrix_sources s
              where s.status = 'read' and s.read_via <> 'stored'
                and (not v_bp or not exists (select 1 from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code = 'entry_matrix_first_run'
                                                                                          and i.entity_id = s.provider_id))
$n$],
        array[$o$  v_est := round((v_nh + v_nn) * v_cost, 4);
$o$, $n$  v_est := round((v_nh + v_nn) * v_cost, 4);
  -- 4 Nov 2026 (SS-021 F4): technically held and duplicate entry items are recorded for bounded technical recovery (records only; isolated)
  if not p_preview then
    begin
      v_tech := security.aer_technical_recovery_v1();
    exception when others then v_tech := jsonb_build_object('error', left(sqlerrm, 200));
    end;
  end if;
$n$],
        array[$o$            jsonb_build_object('held', v_held, 'new', v_new, 'matrix', v_mx, 'skipped', v_skip, 'checked', jsonb_array_length(v_checked)));
$o$, $n$            jsonb_build_object('held', v_held, 'new', v_new, 'matrix', v_mx, 'skipped', v_skip, 'checked', jsonb_array_length(v_checked),
                               'fair', v_fair, 'room_ready', v_rr, 'technical', v_tech));
$n$],
        array[$o$    'checked', v_checked, 'held', v_held, 'new', v_new, 'matrix', v_mx, 'skipped', v_skip);
$o$, $n$    'checked', v_checked, 'held', v_held, 'new', v_new, 'matrix', v_mx, 'skipped', v_skip)
    || jsonb_build_object('fair', v_fair, 'room_ready', v_rr, 'technical', v_tech);
$n$]], array[1, 1, 1, 1, 1, 1, 1, 1]);

-- 5.4 F9: the fee reader works page by page
select pg_temp.edit_once('security.fee_reader_tick_v1()', '0c93b20de02d1714cd6672c259fddb20', '8116602b00bd4bb3972e16bd682d4c17',
  array[array[$o$     and not exists (select 1 from pipeline.fee_reader_queue q where q.state = 'leased' and q.leased_until > now())
$o$, $n$     -- 4 Nov 2026 (SS-021 F9, IQ-00134; wc.fee_item_claims_on): each page is claimed on its own (public.svc_fee_ai_next leases per page, skip
     -- locked), so the worker is called while fewer than wc.fee_live_leases_max pages are leased, not only when no lease is live anywhere
     and (case when security.pipeline_num_v1('wc.fee_item_claims_on', 0) >= 1
               then (select count(*) from pipeline.fee_reader_queue q where q.state = 'leased' and q.leased_until > now()) < security.pipeline_num_v1('wc.fee_live_leases_max', 6)
               else not exists (select 1 from pipeline.fee_reader_queue q where q.state = 'leased' and q.leased_until > now()) end)
$n$]], array[1]);

-- 5.5 F9: course page searches isolated, re-sent when due, capped
select pg_temp.edit_once('security.course_link_search_tick_v1(integer)', 'ffc9fb647925f689678a035cdd64b3e1', '71bf3bc46df97b90870a8bcf238a8a4a',
  array[array[$o$        n_harvest int := 0; n_found int := 0; n_moved int := 0; n_sent int := 0; v_next text;
$o$, $n$        n_harvest int := 0; n_found int := 0; n_moved int := 0; n_sent int := 0; v_next text;
        -- 4 Nov 2026 (SS-021 F9, IQ-00134; wc.link_search_continuity_on): per-search isolation, re-send when due, a send cap
        v_wc_on boolean := security.pipeline_num_v1('wc.link_search_continuity_on', 1) >= 1; v_wc_max int := security.pipeline_num_v1('wc.link_search_max_attempts', 3)::int;
        v_wc jsonb; v_wc_state text; v_wc_msg text; n_failed int := 0; n_resent int := 0; n_capped int := 0;
$n$],
        array[$o$    n_harvest := n_harvest + 1;
    if r.status_code = 200 and left(r.content, 1) = '{' then
$o$, $n$    n_harvest := n_harvest + 1;
    begin
    if r.status_code = 200 and left(r.content, 1) = '{' then
$n$],
        array[$o$      update pipeline.course_link_search set attempts = attempts + 1, state = case when attempts + 1 >= 3 then 'error' else 'queued' end,
             results = jsonb_build_object('http_status', r.status_code, 'body', left(r.content, 300)) where course_id = r.course_id;
    end if;
  end loop;
  -- searches with no response after 20 minutes are sent again
  update pipeline.course_link_search set state = 'queued', attempts = attempts + 1
   where state = 'sent' and sent_at < now() - interval '20 minutes' and not exists (select 1 from net._http_response h where h.id = req_id);
$o$, $n$      update pipeline.course_link_search set attempts = attempts + 1, state = case when attempts + 1 >= v_wc_max then 'error' else 'queued' end,
             results = jsonb_build_object('http_status', r.status_code, 'body', left(r.content, 300)) where course_id = r.course_id;
    end if;
    if v_wc_on and exists (select 1 from pipeline.work_items w where w.lane = 'course_link_search' and w.entity = r.course_id::text and w.work_kind = 'search' and w.stage <> 'done') then
      perform security.work_item_report_v1('course_link_search', r.course_id::text, 'search', 'succeeded', jsonb_build_object('provider_id', r.provider_id, 'outcome', 'succeeded_with_result'));
    end if;
    exception when others then
      -- one bad answer body or bind refusal sets back only this search (recorded with its class); off: the run stops as before
      if not v_wc_on then raise; end if;
      get stacked diagnostics v_wc_state = returned_sqlstate, v_wc_msg = message_text;
      perform security.work_item_report_v1('course_link_search', r.course_id::text, 'search', 'failed', jsonb_build_object('provider_id', r.provider_id,
                'owner', 'course-link-search', 'sqlstate', v_wc_state, 'message', v_wc_msg, 'evidence', jsonb_build_object('step', 'harvest', 'http_status', r.status_code)));
      update pipeline.course_link_search set attempts = attempts + 1, state = case when attempts + 1 >= v_wc_max then 'error' else 'queued' end,
             results = jsonb_build_object('error', left(v_wc_msg, 300), 'http_status', r.status_code) where course_id = r.course_id;
      if r.attempts + 1 >= v_wc_max then perform security.link_search_park_v1(r.course_id, r.attempts + 1); n_capped := n_capped + 1; end if;
      n_failed := n_failed + 1;
    end;
  end loop;
  if not v_wc_on then
  -- searches with no response after 20 minutes are sent again
  update pipeline.course_link_search set state = 'queued', attempts = attempts + 1
   where state = 'sent' and sent_at < now() - interval '20 minutes' and not exists (select 1 from net._http_response h where h.id = req_id);
  else
    -- 4 Nov 2026 (SS-021 F9): an unanswered search is recorded once per send (class search_unanswered), re-sent only when its work item is due
    -- again, and ends in error after wc.link_search_max_attempts sends
    for r in select s.course_id, s.provider_id, s.attempts, s.sent_at, w.last_attempt_at wla
               from pipeline.course_link_search s
               left join pipeline.work_items w on w.lane = 'course_link_search' and w.entity = s.course_id::text and w.work_kind = 'search'
              where s.state = 'sent' and s.sent_at < now() - make_interval(mins => security.pipeline_num_v1('wc.link_search_resend_minutes', 20)::int)
                and not exists (select 1 from net._http_response h where h.id = s.req_id)
              order by s.sent_at limit security.pipeline_num_v1('wc.tick_batch', 500)::int loop
      begin
        if r.wla is null or r.sent_at > r.wla then
          v_wc := security.work_item_report_v1('course_link_search', r.course_id::text, 'search', 'failed', jsonb_build_object('provider_id', r.provider_id,
                    'owner', 'course-link-search', 'class', 'search_unanswered', 'message', 'no search answer within the wait',
                    'evidence', jsonb_build_object('sent_at', r.sent_at, 'sends', r.attempts + 1)));
          update pipeline.course_link_search set attempts = attempts + 1,
                 state = case when r.attempts + 1 >= v_wc_max then 'error' when not coalesce((v_wc->>'recorded')::boolean, false) then 'queued' else state end,
                 results = case when r.attempts + 1 >= v_wc_max then jsonb_build_object('error', 'no search answer after ' || (r.attempts + 1) || ' send(s)') else results end
           where course_id = r.course_id and state = 'sent';
          if r.attempts + 1 >= v_wc_max then perform security.link_search_park_v1(r.course_id, r.attempts + 1); n_capped := n_capped + 1; end if;
        elsif security.work_item_eligible_v1('course_link_search', r.course_id::text, 'search') then
          update pipeline.course_link_search set state = 'queued' where course_id = r.course_id and state = 'sent';
          n_resent := n_resent + 1;
        end if;
      exception when others then n_failed := n_failed + 1;
      end;
    end loop;
  end if;
$n$],
        array[$o$    if r.cand_idx < jsonb_array_length(r.candidates) then
$o$, $n$    begin
    if r.cand_idx < jsonb_array_length(r.candidates) then
$n$],
        array[$o$    n_moved := n_moved + 1;
  end loop;
$o$, $n$    n_moved := n_moved + 1;
    exception when others then
      if not v_wc_on then raise; end if;
      get stacked diagnostics v_wc_state = returned_sqlstate, v_wc_msg = message_text;
      perform security.work_item_report_v1('course_link_search', r.course_id::text, 'search', 'failed', jsonb_build_object('provider_id', r.provider_id,
                'owner', 'course-link-search', 'sqlstate', v_wc_state, 'message', v_wc_msg, 'evidence', jsonb_build_object('step', 'move_on', 'bound_url', r.bound_url)));
      n_failed := n_failed + 1;
    end;
  end loop;
$n$],
        array[$o$                where s.state = 'queued' and not security.course_held_v1(s.course_id)$o$,
              $n$                where s.state = 'queued' and not security.course_held_v1(s.course_id)
                  and (not v_wc_on or security.work_item_eligible_v1('course_link_search', s.course_id::text, 'search'))$n$],
        array[$o$  return jsonb_build_object('collected', n_harvest, 'found', n_found, 'moved_on', n_moved, 'sent', n_sent, 'credits_this_month', v_used, 'cap', v_cap);
$o$, $n$  return jsonb_build_object('collected', n_harvest, 'found', n_found, 'moved_on', n_moved, 'sent', n_sent, 'credits_this_month', v_used, 'cap', v_cap,
                            'failed', n_failed, 'resent', n_resent, 'capped', n_capped);
$n$]], array[1, 1, 1, 1, 1, 1, 1]);

-- 6 root causes and remedies through workstream A's contract ---------------------------------------------------------------------------
select security.ops_root_cause_register_v1(x.code, x.spec) from (values
 ('work_technical_hold', '{"class": "transient", "title": "Layer 4 items stay technically held", "description": "Entry items whose readiness stays technical_blocked used up their technical re-checks (lane aer_technical). They are not decisions: the repair is on the route their readiness names; one more bounded cycle is the automatic remedy.", "detect": {"priority": 20, "confidence": 0.85, "any": [{"fingerprint_like": ["work_blocked:%:technical_hold"]}]}}'::jsonb),
 ('work_duplicate_review', '{"class": "data", "title": "Duplicate Layer 4 items wait", "description": "A later waiting item duplicates an older one for the same entity and kind; the older stays the decision. Settling duplicates is the Layer 4 reconciliation (layer4.reconcile_supersede_on), a Platform Admin switch.", "detect": {"priority": 21, "confidence": 0.9, "any": [{"fingerprint_like": ["work_blocked:%:duplicate"]}], "route": "needs_decision"}}'::jsonb),
 ('work_search_unanswered', '{"class": "transient", "title": "Course page searches used up their sends", "description": "Searches failed or went unanswered wc.link_search_max_attempts times and ended in error (lane course_link_search). A lasting failure needs a release in the search lane.", "detect": {"priority": 22, "confidence": 0.85, "any": [{"fingerprint_like": ["work_blocked:%:search_unanswered"]}]}}'::jsonb)
) x(code, spec);

select security.ops_remedy_register_v1(x.code, x.spec) from (values
 ('work_retry_technical', '{"title": "Give technically held items one more bounded check cycle", "treats": ["work_technical_hold"], "authority": "auto", "action_fn": "security.work_remedy_retry_parked_v1(bigint)", "verify_fn": "security.work_verify_recovered_v1(bigint)", "max_attempts_key": "ops.max_attempts", "cooldown_key": "ops.cooldown_minutes", "notes": "Re-arms the work items only; nothing is read, decided or sent to Layer 4."}'::jsonb),
 ('work_duplicate_decision', '{"title": "Platform Admin settles duplicate Layer 4 items", "treats": ["work_duplicate_review"], "authority": "admin", "notes": "Through the audited Layer 4 reconciliation; never decided by the platform or by AI diagnosis."}'::jsonb),
 ('work_search_release', '{"title": "Fix the course page search lane through a release", "treats": ["work_search_unanswered"], "authority": "release", "notes": "Searches that end in error are not re-sent automatically (paid)."}'::jsonb)
) x(code, spec);

-- 7 the job (G1: catalogued first; ships ON: it records, parks and ends tasks that can never run; release and spend switches ship off) ------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('work-continuity-lanes', 'Platform upkeep', 19, 'Work continuity in the lanes (Find course pages park and release)',
  'At :03, :13, :23, :33, :43 and :53: running Find course pages tasks held while the course search cap is reached are parked until the cap resets (wc.page_find_park_on) and, with wc.page_find_release_on, ended so their plan gives back its slot (their courses stay queued); a task that can never run (wc.page_find_never_codes) ends at once with its blocker recorded; a task moving again after a park is recovered. Settings wc.page_find_*. Spends nothing; never queues, sends or removes a search.',
  6, false, null)
on conflict (jobname) do nothing;
do $c$ begin
  if not exists (select 1 from cron.job where jobname = 'work-continuity-lanes') then
    perform cron.schedule('work-continuity-lanes', '3,13,23,33,43,53 * * * *', $j$select security.page_find_continuity_v1()$j$);
  end if;
end $c$;

-- 8 component register --------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('job', 'work-continuity-lanes', 'Platform', 'CF-247 SS-021 F3: Find course pages parked behind the paid cap; tasks that can never run ended', 'active', '{}', '20261104190000'),
 ('function', 'security.page_find_continuity_v1', 'Platform', 'CF-247 SS-021 F3: job work-continuity-lanes', 'active', '{}', '20261104190000'),
 ('function', 'security.course_search_paid_cap_v1', 'Platform', 'CF-247 SS-021 F3: the course search caps and their reset', 'active', '{}', '20261104190000'),
 ('function', 'security.link_search_park_v1', 'Platform', 'CF-247 SS-021 F9: a course page search at its send cap is parked', 'active', '{}', '20261104190000'),
 ('function', 'security.aer_fair_courses_v1', 'Platform', 'CF-247 SS-021 F4: AER course reads in turn, within shares and the reserve', 'active', '{}', '20261104190000'),
 ('function', 'security.aer_provider_load_v1', 'Platform', 'CF-247 SS-021 F4: each university''s AER decisions waiting and reads in progress', 'active', '{}', '20261104190000'),
 ('function', 'security.aer_technical_recovery_v1', 'Platform', 'CF-247 SS-021 F4: technically held and duplicate entry items recorded for recovery', 'active', '{}', '20261104190000'),
 ('function', 'security.work_review_ready_v1', 'Platform', 'CF-247 SS-021 F4: review category waiting items by readiness', 'active', '{}', '20261104190000'),
 ('function', 'security.integration_issue_allowed_v1', 'Platform', 'CF-247 SS-021 F2: values the issue queue''s checks allow', 'active', '{}', '20261104190000')
on conflict do nothing;
