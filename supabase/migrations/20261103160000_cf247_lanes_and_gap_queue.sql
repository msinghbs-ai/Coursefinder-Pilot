-- CF-247 P0 mandate 3 Nov 2026 10:44 §3 Agent C and §6: stored-evidence work is never held by paid acquisition; a bounded, resumable standing gap
-- queue; honest outcomes ("Stored-evidence enrichment must not be blocked merely because external Firecrawl credits are unavailable. Separate
-- stored-evidence processing, new paid source acquisition, AI extraction and Layer 4 admission. Each lane must have independently measurable
-- work, cost and hold reasons. Do not increase spending.").
-- Why (live, read-only, 3 Nov 2026 10:46-11:08 AEDT):
--   * Lane audit (every coverage-sweep mode, its picker and its caller): the worker itself never stops stored work for credits (each paid step is
--     per item: direct read first, Firecrawl only as a fallback, a refused fallback is "needs_render" and keeps its try). Two pickers did couple
--     them: public.svc_scholarship_ai_next leased items with no stored copy ahead of stored ones (ordered by step and id), and each of those
--     was refused by the scholarship credit check, put back as "waiting_scraper" and counted as a try, then closed as "no scraper credit after
--     3 tries" (svc_scholarship_ai_record): a budget hold turned into a permanent failure, and stored copies waited behind it.
--     public.svc_scholarship_recheck_next leased reviews with no stored copy; the worker's read was refused and the review was recorded
--     "unsettled: the page could not be read again" (a budget hold recorded as a re-check result).
--   * Outcomes: pipeline.mode_outcome_ledger.outcome has four values (succeeded, idle, zero_work_error, failed). A call whose every item waited
--     for credits is "zero_work_error"; a paid lane whose picker returns nothing because today's share is spent is "idle"; neither says
--     "held by the budget". public.svc_worker_report_v1 cast "applied" and "done" to int: the scholarship_read answer carries "applied": [], so
--     the cast failed and none of its calls was recorded (24 h: 0 ledger rows; edge log: a call every 5 minutes, HTTP 200, items 0).
--   * Standing gap queue (job field-gap-queue, security.field_gap_queue_tick_v1): one statement over every active course (about 35,700) times
--     every field, with the latest item per course and field found by a DISTINCT ON over all of pipeline.field_enrich_items (about 166,000);
--     2 of its last 4 runs hit the statement time-out in "insert into _gap" (2 Nov 17:23 and 23:23 AEDT) and nothing is kept from a failed run.
--   * Repeated calls with nothing to do (24 h): link_search 1,265 calls, last work 2 Nov 12:21 (today's course-search share spent);
--     discover 1,974 calls, 3 items (jobs coverage-discover and -2 were paused at 01:35 by event #28683, found active, and paused again by
--     10:57); cricos_peo 1,008 (fixed by branch cf247-hidden-failures-country-config); central_find 258, find_site 404, contact_page 407,
--     logo_find 134, flag_check 139 (nothing due: their pickers have no budget gate and nothing is due).
-- What:
--   1 Lanes: pipeline.worker_mode_lanes names the lane of every worker mode (stored_evidence, paid_acquisition, ai_extraction) and the Firecrawl
--     purpose of a paid mode. security.lane_paid_hold_v1(purpose) says why new paid reading is held (the monthly plan reserve, or no room in
--     today's share), or null. Layer 4 admission is measured from pipeline.layer4_review_items.
--   2 Honest outcomes per call: new columns pipeline.mode_outcome_ledger.lane_outcome (done, idle, budget_held, source_limit, failed,
--     switched_off) and hold_reason, set by security.worker_lane_outcome_v1 from svc_worker_report_v1 (md5-guarded edit). The outcome column
--     and security.worker_call_outcome_v1 are unchanged (job_outcomes_v1, worker_outcome_check_v1 and the yield checks keep reading them).
--     The report casts numbers only when they are numbers (security.jsonb_int_v1), so scholarship_read calls are recorded.
--   3 Stored evidence first: with lanes.stored_first_on (1, on), while the scholarship Firecrawl lane is held, svc_scholarship_ai_next and
--     svc_scholarship_recheck_next (md5-guarded edits) lease only items that have a stored copy; the others stay queued with no try used and
--     are counted as held by security.lane_status_v1. Nothing else changes in their order; no credit is spent that was not spent before.
--   4 Gap queue: security.field_gap_scan_v1 fills the tick's _gap from a durable checkpoint (pipeline.field_gap_queue_checkpoint): active
--     courses in id order, gaps.scan_courses_per_slice at a time, the latest item per course and field through the (course_id, field) index,
--     stopping at gaps.items_per_run items or gaps.scan_seconds, and saving where it stopped; the next run resumes there; a cycle that ends
--     with nothing found wraps once so "nothing due" means a full pass found nothing. The selection rules are the tick's own (locks, items in
--     progress, filled-and-emptied, unpublished, recheck days, page read again). field_gap_queue_tick_v1 (md5-guarded, one edit) calls it in
--     place of its single statement. Job field-gap-queue runs security.field_gap_queue_run_v1, which records every run in
--     pipeline.field_gap_queue_runs with its outcome (done, idle, held, switched_off) and hold reason (previous_run_open, scan_continues,
--     queue_off, nothing_due); a run never reports nothing due while the scan has not finished its pass.
--   5 No calls to a switched-off lane: security.worker_lane_call_v1(mode) answers false when the lane is switched off (course-page search:
--     pipeline.course_link_search_settings.enabled), and, only with lanes.skip_held_paid_calls on (0, off), while a paid lane is held by the
--     budget (one ledger row per lanes.hold_note_minutes records the hold instead of a call). Jobs course-link-search-worker, central-find,
--     coverage-discover, coverage-discover-2, scholarship-listing and scholarship-read call the worker only when it answers true; each keeps
--     its schedule and its active state.
--   6 Measures: security.lane_status_v1() (read-only): per lane the eligible work, processed and failed in the last lanes.status_window_minutes,
--     held calls by reason, the live hold, and cost (Firecrawl credits, AI US$) today and in the window; the gap queue's checkpoint and last
--     run. public.admin_pipeline_yield (md5-guarded edit) adds it as lane_status (Platform health › Integration queue › Pipeline yield).
--     security.pipeline_yield_v1 is not edited (branch cf247-hidden-failures-country-config edits it).
-- md5 (before = live v2.15.418, read 3 Nov 2026 10:47-10:55 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/lanes-gap-queue/run.sh):
--   public.svc_worker_report_v1(text,integer,integer,jsonb,text)   6f3b816265f1a517b9d79140041669bb -> b110a648a8149eede42cbc69cce43a77
--   security.field_gap_queue_tick_v1()                              d909e54d6b6de0f8d2893fbb2d8553bd -> 200f3210c75a71e6e5f5f0eceb37ea66
--     (or, after branch cf247-course-description-reader:           387f8edbe3363ea52317e024d96f2369 -> 9bb80b419ee26a049b99a35fb278e272)
--   public.svc_scholarship_ai_next(integer)                         ddef1e3dd794e26f3588f73e9d51e6b5 -> 18e76dbc9984be55370434ca27066c7b
--   public.svc_scholarship_recheck_next(integer)                    f35fa04f98a32d0ca4eb4064ea7db6eb -> ccfaf9a9c6bbba4ce5fde64a3d7738af
--   public.admin_pipeline_yield(jsonb)                              a9d64bbca63b5e1c587edabf4e1fef59 -> a38814324515b163a34129b7a9d01dbd
-- Spend: no Firecrawl or AI value is raised; nothing reads a page or calls a model that did not before.
-- Consumer API (G3): untouched.
-- Replaces: public.svc_worker_report_v1, security.field_gap_queue_tick_v1, public.svc_scholarship_ai_next, public.svc_scholarship_recheck_next, public.admin_pipeline_yield (same names; md5-guarded edits); the commands of jobs field-gap-queue, course-link-search-worker, central-find, coverage-discover, coverage-discover-2, scholarship-listing, scholarship-read
-- Retires: the single-statement gap selection inside security.field_gap_queue_tick_v1 (replaced in the same edit by security.field_gap_scan_v1)
-- Nothing is dropped or deleted. No job is added; every job keeps its schedule and active state. lanes.skip_held_paid_calls ships off.

create or replace function pg_temp.edit_once(p_sig text, p_befores text[], p_afters text[], p_edits text[][], p_times int[]) returns text language plpgsql as $f$
-- one or more known "before" definitions (p_befores[i] becomes p_afters[i]); the edits are the same for each
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; k int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = any (p_afters) then return p_sig || ': already applied'; end if;
  k := array_position(p_befores, md5(v_def));
  if k is null then raise exception 'live % differs from the definitions this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_afters[k] then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_afters[k];
  end if;
  return p_sig || ': applied';
end $f$;

-- 0. the definitions the new code calls are the ones it was written against (not changed here) ----------------------------------------------
do $g$
declare r record;
begin
  for r in select * from (values ('security.fc_budget_left_v1(text)', 'e979d2e3d7319d845a5149e40abe6987'), ('security.fc_month_refusal_v1(numeric)', '8c1419332ff503abd69539ccbad1121d'),
                                 ('security.fc_purpose_group_v1(text)', '348bbb9ec1db966755e532f23e376897'), ('security.worker_call_outcome_v1(integer,jsonb,integer,integer,integer)', '8b256a6f7f9a9350927b4773c8a80304'),
                                 ('security.ai_use_refusal_v1(text)', '60c782e5aec7eb218c1149a3ad85dde2'), ('security.fc_day_start_v1()', 'f5113f936c0c2a473e0d74cca51b5d97')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
end $g$;

-- 1. settings (G2) -------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'lanes.stored_first_on', 'Lanes: stored copies first while paid reading is held',
  'On (1): while new Firecrawl reading for scholarships is held by the budget, the AI reader and the AI re-check take only items whose page is already stored; the others wait, with no try used. Off (0): items are taken in their usual order and an item without a stored copy uses a try when its read is refused.',
  'number', to_jsonb(1), 0, 1, 'on/off', 1010, 'Enrichment lanes', 'public.svc_scholarship_ai_next, public.svc_scholarship_recheck_next', 'Platform Admin P0 mandate 3 Nov 2026 10:44 §6: stored-evidence work is not held by paid acquisition'),
 ('pipeline', 'lanes.skip_held_paid_calls', 'Lanes: do not call a paid reader while its budget is held',
  'On (1): the jobs that only buy new pages (course-page search, central pages, site maps, scholarship listings and reads) do not call the worker while their Firecrawl share or the monthly plan reserve is reached; one row a period records the hold. Off (0): they are called on schedule and answer that they are held.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1011, 'Enrichment lanes', 'security.worker_lane_call_v1 (jobs course-link-search-worker, central-find, coverage-discover, coverage-discover-2, scholarship-listing, scholarship-read)', 'Platform Admin P0 mandate 3 Nov 2026 10:44 §3 Agent C: disabled work is not invoked repeatedly'),
 ('pipeline', 'lanes.hold_note_minutes', 'Lanes: record a held paid reader once every',
  'While a paid reader is not called because its budget is held, one row in the worker ledger records the hold this often.',
  'number', to_jsonb(60), 5, 1440, 'minutes', 1012, 'Enrichment lanes', 'security.worker_lane_call_v1', 'Platform Admin P0 mandate 3 Nov 2026 10:44 §6'),
 ('pipeline', 'lanes.status_window_minutes', 'Lanes: work counted over the last',
  'Lane status (Platform health, Pipeline yield) counts processed, failed and held work over this window.',
  'number', to_jsonb(60), 15, 1440, 'minutes', 1013, 'Enrichment lanes', 'security.lane_status_v1', 'Platform Admin P0 mandate 3 Nov 2026 10:44 §6'),
 ('pipeline', 'gaps.scan_courses_per_slice', 'Gap queue: courses checked per slice',
  'The standing gap queue checks active courses in slices of this many, in id order, and saves where it stopped after each slice.',
  'number', to_jsonb(2000), 100, 20000, 'courses', 1020, 'Gap queue', 'security.field_gap_scan_v1 (job field-gap-queue)', 'Platform Admin P0 mandate 3 Nov 2026 10:44 §3 Agent C: bounded batches, durable checkpoints'),
 ('pipeline', 'gaps.scan_seconds', 'Gap queue: time a run may spend finding gaps',
  'A run stops starting new slices after this many seconds and the next run carries on from where it stopped. Keep it well inside the job time-out.',
  'number', to_jsonb(20), 5, 240, 'seconds', 1021, 'Gap queue', 'security.field_gap_scan_v1 (job field-gap-queue)', 'Platform Admin P0 mandate 3 Nov 2026 10:44 §3 Agent C: resumes after interruptions')
on conflict (toolset_key, key) do nothing;

-- 2. lanes and honest outcomes ----------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.worker_mode_lanes (
  mode text primary key,
  lane text not null check (lane in ('stored_evidence', 'paid_acquisition', 'ai_extraction', 'platform')),
  fc_purpose text,
  label text not null
);
comment on table pipeline.worker_mode_lanes is 'CF-247 P0 mandate 3 Nov 2026 §6: the lane of each coverage-sweep worker mode (stored evidence and direct reads, new paid pages, AI extraction) and the Firecrawl purpose of a paid mode. Read by security.worker_lane_outcome_v1, security.worker_lane_call_v1 and security.lane_status_v1.';
alter table pipeline.worker_mode_lanes enable row level security;
insert into pipeline.worker_mode_lanes(mode, lane, fc_purpose, label) values
 ('read', 'stored_evidence', 'scrape', 'Course pages (direct read; Firecrawl only as a fallback)'),
 ('reextract', 'stored_evidence', null, 'Stored course pages read again'),
 ('reidentify', 'stored_evidence', null, 'Stored course pages identified again'),
 ('adapter_apply', 'stored_evidence', null, 'University adapters on stored pages'),
 ('adapter_preview', 'stored_evidence', null, 'University adapter preview'),
 ('credential_read', 'stored_evidence', null, 'Credentials from stored pages'),
 ('tuition_handoff', 'stored_evidence', null, 'Tuition from stored pages'),
 ('register_replay', 'stored_evidence', null, 'Register files replayed'),
 ('nz_cop', 'stored_evidence', null, 'NZ code of practice files'),
 ('entry_inspect', 'stored_evidence', null, 'Entry pages inspected'),
 ('scholarship_reextract', 'stored_evidence', null, 'Stored scholarship pages read again'),
 ('provider_facts_add_tests', 'stored_evidence', null, 'Provider policy tests'),
 ('provider_facts_inspect', 'stored_evidence', null, 'Provider facts inspected'),
 ('provider_facts_parse', 'stored_evidence', null, 'Provider facts parsed'),
 ('retention_files', 'stored_evidence', null, 'Stored files kept or removed'),
 ('contact_page', 'stored_evidence', null, 'Provider contact pages (direct read)'),
 ('flag_check', 'stored_evidence', null, 'Provider sites checked (direct read)'),
 ('logo_find', 'stored_evidence', null, 'Provider logos (direct read)'),
 ('companion_read', 'stored_evidence', 'companion_read', 'Companion pages (direct read; Firecrawl only as a fallback)'),
 ('course_list_read', 'stored_evidence', 'list_scrape', 'Course lists (direct read; Firecrawl only as a fallback)'),
 ('programme_discover', 'stored_evidence', 'list_scrape', 'Programme lists (direct read; Firecrawl only as a fallback)'),
 ('programme_read', 'stored_evidence', 'list_scrape', 'Programme pages (direct read; Firecrawl only as a fallback)'),
 ('source_find', 'stored_evidence', 'list_scrape', 'University course sources (direct read; Firecrawl only as a fallback)'),
 ('link_search', 'paid_acquisition', 'course_link_search', 'Course-page search (Firecrawl)'),
 ('discover', 'paid_acquisition', 'map', 'Course site maps (Firecrawl)'),
 ('find_site', 'paid_acquisition', 'search', 'Provider websites found (Firecrawl search)'),
 ('central_find', 'paid_acquisition', 'central_map', 'Central pages found (Firecrawl)'),
 ('cricos_peo', 'paid_acquisition', 'peo_scrape', 'CRICOS principal executive (Firecrawl)'),
 ('site_check', 'paid_acquisition', 'site_verify', 'Provider websites verified (Firecrawl)'),
 ('provider_facts', 'paid_acquisition', 'provider_facts_scrape', 'Provider fact pages (Firecrawl)'),
 ('scholarship_discover', 'paid_acquisition', 'sch_map', 'Scholarship discovery (Firecrawl)'),
 ('scholarship_listing', 'paid_acquisition', 'sch_scrape', 'Scholarship listings (Firecrawl)'),
 ('scholarship_read', 'paid_acquisition', 'sch_scrape', 'Scholarship pages read again (Firecrawl)'),
 ('scholarship_inspect', 'paid_acquisition', 'sch_scrape', 'Scholarship page inspected (Firecrawl)'),
 ('fc_run', 'paid_acquisition', 'fc_read', 'Firecrawl runs'),
 ('fc_probe', 'paid_acquisition', 'fc_probe', 'Firecrawl probe'),
 ('adapter_capture', 'paid_acquisition', 'adapter_builder', 'University adapter samples (Firecrawl)'),
 ('enrich_ai', 'ai_extraction', null, 'Enrich fields (AI on stored pages)'),
 ('fee_ai', 'ai_extraction', null, 'Fee reader (AI on stored pages)'),
 ('scholarship_ai', 'ai_extraction', 'sch_scrape', 'Scholarship AI reader (stored copy first)'),
 ('scholarship_recheck', 'ai_extraction', 'sch_scrape', 'Scholarship AI re-check (stored copy first)'),
 ('central_ai', 'ai_extraction', null, 'Central pages (AI)'),
 ('entry_ai', 'ai_extraction', 'provider_facts_scrape', 'Entry requirement tables (AI)'),
 ('provider_description', 'ai_extraction', 'provider_description', 'Provider descriptions (AI on the stored About page)'),
 ('ai_match', 'ai_extraction', null, 'Course page matching (AI)'),
 ('adapter_propose', 'ai_extraction', null, 'University adapter proposals (AI)'),
 ('openrouter_balance', 'platform', null, 'AI account balance')
on conflict (mode) do nothing;

alter table pipeline.mode_outcome_ledger add column if not exists lane_outcome text, add column if not exists hold_reason text;
do $c$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'pipeline.mode_outcome_ledger'::regclass and conname = 'mode_outcome_ledger_lane_outcome_check') then
    alter table pipeline.mode_outcome_ledger add constraint mode_outcome_ledger_lane_outcome_check
      check (lane_outcome in ('done', 'idle', 'budget_held', 'source_limit', 'failed', 'switched_off'));
  end if;
end $c$;
comment on column pipeline.mode_outcome_ledger.lane_outcome is 'CF-247 P0 mandate 3 Nov 2026 §6: what the call did for its lane: done, idle (nothing due), budget_held (Firecrawl share or plan reserve), source_limit (a source or daily pick cap), failed, switched_off. Set by security.worker_lane_outcome_v1.';
comment on column pipeline.mode_outcome_ledger.hold_reason is 'CF-247 P0 mandate 3 Nov 2026 §6: why the call did no work (the hold or the error), in words.';

create or replace function security.jsonb_int_v1(p jsonb) returns integer
language sql immutable set search_path to '' as $function$
  -- a count in a worker answer: a number is read as a number, a list as its length, anything else as nothing
  select case jsonb_typeof(p) when 'number' then (p #>> '{}')::numeric::int when 'array' then jsonb_array_length(p) end
$function$;

create or replace function security.lane_paid_hold_v1(p_purpose text) returns text
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 P0 mandate 3 Nov 2026 10:44 §6: why new paid reading for this Firecrawl purpose is held now, or null. The same rules as the spend
-- check: the monthly plan reserve (security.fc_month_refusal_v1) and today's share for the purpose's group (security.fc_budget_left_v1).
declare v text;
begin
  if p_purpose is null then return null; end if;
  v := security.fc_month_refusal_v1(1);  -- fixed: one credit, the smallest spend
  if v is not null then return 'budget_held: ' || v; end if;
  if security.fc_budget_left_v1(p_purpose) < 1 then  -- fixed: one credit, the smallest spend
    return 'budget_held: no room left in today''s Firecrawl share for ' || security.fc_purpose_group_v1(p_purpose);
  end if;
  return null;
end $function$;

create or replace function security.worker_lane_outcome_v1(p_mode text, p_outcome text, p_body jsonb) returns text[]
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 P0 mandate 3 Nov 2026 10:44 §3 Agent C, §6: what a worker call did for its lane, with the reason when it did no work:
-- {lane_outcome, hold_reason}. A call held by the Firecrawl budget or a source limit is not a failure and not plain idle.
declare v_lane text; v_purpose text; v_t text := coalesce(p_body::text, ''); v_m text[]; v_hold text;
begin
  if p_outcome is null then return array[null, null]::text[]; end if;
  select l.lane, l.fc_purpose into v_lane, v_purpose from pipeline.worker_mode_lanes l where l.mode = p_mode;
  if p_outcome = 'failed' then
    return array['failed', left(coalesce(p_body->>'error', p_body->>'reason', 'the worker answered with an error'), 300)];
  end if;
  if p_outcome = 'succeeded' then return array['done', null]::text[]; end if;
  v_m := regexp_match(v_t, '(credits_reserve|credits_refused|waiting_scraper|scholarship_share|plan_reserve|no scraper credit|target_list_refused)');
  if p_outcome = 'zero_work_error' then
    if v_m is not null and v_t !~* '"(error|errors|last_error)"\s*:\s*"|statement timeout' then
      return array[case when v_m[1] = 'target_list_refused' then 'source_limit' else 'budget_held' end, 'every item waited: ' || v_m[1]];
    end if;
    return array['failed', left(coalesce(p_body->>'error', substring(v_t from '"(?:errors?|last_error)"\s*:\s*"([^"]+)'), 'no work done, with an error in the answer'), 300)];
  end if;
  -- idle: a paid lane whose picker found nothing because its budget is held is held, not idle
  if v_lane = 'paid_acquisition' then
    v_hold := security.lane_paid_hold_v1(v_purpose);
    if v_hold is not null then return array['budget_held', v_hold]; end if;
    if p_mode = 'link_search' and (select count(*) from pipeline.course_link_search s where s.sent_at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'))
                                  >= security.pipeline_num_v1('search.daily_picked_cap', 100) then
      return array['source_limit', 'today''s course-page search cap (search.daily_picked_cap) is reached'];
    end if;
  end if;
  return array['idle', coalesce(nullif(p_body->>'reason', ''), 'nothing due')];
end $function$;
revoke all on function security.worker_lane_outcome_v1(text, text, jsonb) from public, anon, authenticated;
revoke all on function security.lane_paid_hold_v1(text) from public, anon, authenticated;

select pg_temp.edit_once('public.svc_worker_report_v1(text,integer,integer,jsonb,text)', array['6f3b816265f1a517b9d79140041669bb'], array['b110a648a8149eede42cbc69cce43a77'], array[
 [$o$  v_failed := coalesce(nullif(p_body->>'failed', '')::int, nullif(p_body->'tally'->>'failed', '')::int, 0)
            + coalesce(nullif(p_body->'tally'->>'fetch_failed', '')::int, 0) + coalesce(nullif(p_body->'tally'->>'scrape_failed', '')::int, 0)$o$,
  $n$  -- CF-247 lanes (3 Nov 2026): counts are read only when they are numbers (scholarship_read answers "applied": [], and the cast failed, so
  -- none of its calls was recorded)
  v_failed := coalesce(security.jsonb_int_v1(p_body->'failed'), security.jsonb_int_v1(p_body->'tally'->'failed'), 0)
            + coalesce(security.jsonb_int_v1(p_body->'tally'->'fetch_failed'), 0) + coalesce(security.jsonb_int_v1(p_body->'tally'->'scrape_failed'), 0)$n$],
 [$o$  v_ok := greatest(0, coalesce(nullif(p_body->>'done', '')::int, nullif(p_body->>'applied', '')::int, v_items - v_failed));$o$,
  $n$  v_ok := greatest(0, coalesce(security.jsonb_int_v1(p_body->'done'), security.jsonb_int_v1(p_body->'applied'), v_items - v_failed));$n$],
 [$o$  update pipeline.mode_outcome_ledger set outcome = security.worker_call_outcome_v1(coalesce(p_status, 200), p_body, v_items, v_ok, v_failed) where id = v_id;
$o$,
  $n$  update pipeline.mode_outcome_ledger set outcome = security.worker_call_outcome_v1(coalesce(p_status, 200), p_body, v_items, v_ok, v_failed) where id = v_id;
  -- CF-247 P0 mandate 3 Nov 2026 §6: the lane outcome and the hold reason (budget held, source limit, idle, failed, done)
  update pipeline.mode_outcome_ledger l set lane_outcome = x.o[1], hold_reason = x.o[2]
    from (select security.worker_lane_outcome_v1(left(coalesce(p_mode, ''), 60), y.outcome, p_body) o from pipeline.mode_outcome_ledger y where y.id = v_id) x
   where l.id = v_id;
$n$]], array[1, 1, 1]);

-- 3. stored copies first while the scholarship Firecrawl lane is held -------------------------------------------------------------------------
create or replace function security.scholarship_ai_has_copy_v1(p_queue_id bigint) returns boolean
language sql stable security definer set search_path to '' as $function$
  -- CF-247 lanes (3 Nov 2026): the scholarship AI item has a stored copy the worker reads without Firecrawl (the same sources, in the same
  -- order, as public.svc_scholarship_ai_next gives the worker)
  select exists (select 1 from pipeline.scholarship_ai_queue q
                  where q.id = p_queue_id
                    and (q.storage_path is not null
                         or exists (select 1 from pipeline.scholarship_page_candidates c where c.id = q.candidate_id and c.storage_path is not null)
                         or exists (select 1 from pipeline.scholarship_pages sp join pipeline.evidence_artifacts e on e.id = sp.evidence_id where sp.scholarship_id = q.scholarship_id and e.storage_path is not null)
                         or exists (select 1 from scholarship.scholarships s join pipeline.evidence_artifacts e on e.id = s.evidence_id where s.id = q.scholarship_id and e.storage_path is not null)
                         or exists (select 1 from pipeline.scholarship_ai_extractions x where x.url = q.url and x.storage_path is not null and x.error is null
                                       and x.at > now() - make_interval(hours => security.pipeline_num_v1('waste.page_reuse_hours', 24)::int))))
$function$;
revoke all on function security.scholarship_ai_has_copy_v1(bigint) from public, anon, authenticated;

select pg_temp.edit_once('public.svc_scholarship_ai_next(integer)', array['ddef1e3dd794e26f3588f73e9d51e6b5'], array['18e76dbc9984be55370434ca27066c7b'], array[
 [$o$declare v jsonb; v_reuse int := security.pipeline_num_v1('waste.page_reuse_hours', 24)::int;$o$,
  $n$declare v jsonb; v_reuse int := security.pipeline_num_v1('waste.page_reuse_hours', 24)::int;
        -- CF-247 P0 mandate 3 Nov 2026 §6: while the scholarship Firecrawl lane is held, only items with a stored copy are taken
        v_paid boolean := security.pipeline_num_v1('lanes.stored_first_on', 1) < 1 or security.lane_paid_hold_v1('sch_scrape') is null;$n$],
 [$o$
     order by (q.run_kind = 'test') desc, (q.run_kind = 'qualify') desc, q.step desc, q.id
$o$,
  $n$
       and (v_paid or security.scholarship_ai_has_copy_v1(q.id))  -- the others wait, with no try used (they were refused and closed after 3 tries)
     order by (q.run_kind = 'test') desc, (q.run_kind = 'qualify') desc, q.step desc, q.id
$n$]], array[1, 1]);

select pg_temp.edit_once('public.svc_scholarship_recheck_next(integer)', array['f35fa04f98a32d0ca4eb4064ea7db6eb'], array['ccfaf9a9c6bbba4ce5fde64a3d7738af'], array[
 [$o$declare v jsonb; v_model text;$o$,
  $n$declare v jsonb; v_model text;
        -- CF-247 P0 mandate 3 Nov 2026 §6: while the scholarship Firecrawl lane is held, only reviews with a stored copy are re-checked
        v_paid boolean := security.pipeline_num_v1('lanes.stored_first_on', 1) < 1 or security.lane_paid_hold_v1('sch_scrape') is null;$n$],
 [$o$     order by r.id limit greatest(1, least(coalesce(p_limit, 12), 40)) for update skip locked),$o$,
  $n$       and (v_paid or r.storage_path is not null)  -- the others wait (a refused read was recorded as "the page could not be read again")
     order by r.id limit greatest(1, least(coalesce(p_limit, 12), 40)) for update skip locked),$n$]], array[1, 1]);

-- 4. the standing gap queue: bounded slices, a durable checkpoint, every run recorded -------------------------------------------------------
create table if not exists pipeline.field_gap_queue_checkpoint (
  id int primary key default 1 check (id = 1),
  cycle int not null default 0,
  cycle_started_at timestamptz,
  cursor_course_id uuid,
  cycle_scanned bigint not null default 0,
  cycle_found bigint not null default 0,
  last_run_at timestamptz,
  updated_at timestamptz not null default now()
);
comment on table pipeline.field_gap_queue_checkpoint is 'CF-247 P0 mandate 3 Nov 2026 §3 Agent C: where the standing gap queue (security.field_gap_scan_v1, job field-gap-queue) stopped in its pass over the active courses (id order), so the next run resumes there after a time limit or an interruption. One row.';
alter table pipeline.field_gap_queue_checkpoint enable row level security;
insert into pipeline.field_gap_queue_checkpoint(id) values (1) on conflict (id) do nothing;

create table if not exists pipeline.field_gap_queue_runs (
  id bigint generated always as identity primary key,
  run_at timestamptz not null default now(),
  outcome text not null check (outcome in ('done', 'idle', 'held', 'switched_off')),
  hold_reason text,
  items int not null default 0,
  scanned int not null default 0,
  cycle int,
  cursor_from uuid,
  cursor_to uuid,
  cycle_complete boolean,
  job_id uuid,
  ms int,
  detail jsonb not null default '{}'::jsonb
);
comment on table pipeline.field_gap_queue_runs is 'CF-247 P0 mandate 3 Nov 2026 §3 Agent C: every run of the standing gap queue (security.field_gap_queue_run_v1): done (a task created), idle (a full pass found nothing), held (previous task still open, or the pass continues next run) or switched_off, with the courses checked and the checkpoint before and after. Read by security.lane_status_v1.';
alter table pipeline.field_gap_queue_runs enable row level security;
create index if not exists field_gap_queue_runs_run_at_idx on pipeline.field_gap_queue_runs (run_at desc);

create or replace function security.field_gap_scan_v1(p_fields text[], p_days int, p_cap int) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 P0 mandate 3 Nov 2026 10:44 §3 Agent C: the standing gap queue's selection in bounded slices from a durable checkpoint. Fills the
-- caller's temp table _gap(provider_id, course_id, field, pri) with the rules of security.field_gap_queue_tick_v1 (unchanged): not locked by
-- hand, not being worked on or waiting for a person, and never tried, filled and since emptied, skipped while unpublished, older than the
-- recheck days, or the page read again since. Courses are taken in id order (primary key), gaps.scan_courses_per_slice at a time; the latest
-- item per course and field is found through the (course_id, field) index. The run stops at p_cap items or after gaps.scan_seconds and saves
-- where it stopped; a pass that reaches the end with nothing found wraps once, so "nothing found" means a full pass found nothing.
declare k pipeline.field_gap_queue_checkpoint%rowtype; v_t0 timestamptz := clock_timestamp();
        v_slice int := greatest(1, security.pipeline_num_v1('gaps.scan_courses_per_slice', 2000)::int);
        v_secs numeric := security.pipeline_num_v1('gaps.scan_seconds', 20);
        v_cf text[] := array(select x from unnest(p_fields) x where x not in ('provider_address', 'campus_list', 'campus_region'));
        v_from uuid; v_last uuid; v_ids uuid[]; v_have int := 0; v_n int; v_scanned int := 0; v_slices int := 0; v_stop text; v_wrapped boolean := false;
        v_start_cycle boolean;
begin
  insert into pipeline.field_gap_queue_checkpoint(id) values (1) on conflict (id) do nothing;
  select * into k from pipeline.field_gap_queue_checkpoint where id = 1 for update;
  v_from := k.cursor_course_id; v_last := k.cursor_course_id; v_start_cycle := k.cursor_course_id is null;
  loop
    if v_last is null and (v_start_cycle or v_wrapped) then
      -- a new pass: provider-level fields once, at its start (the tick's own rules)
      k.cycle := k.cycle + 1; k.cycle_started_at := now(); k.cycle_scanned := 0; k.cycle_found := 0; v_start_cycle := false;
      insert into _gap
      select m.provider_id, null::uuid, m.field, case when l.state is null then 1 else 2 end
        from (select p.id provider_id, 'provider_address'::text field from catalogue.providers p
               where 'provider_address' = any (p_fields) and nullif(btrim(p.address_line1), '') is null and coalesce(p.lifecycle_status, 'active') = 'active'
                 and exists (select 1 from catalogue.courses c3 where c3.provider_id = p.id and c3.lifecycle_status = 'active')
              union all
              select p.id, 'campus_region' from catalogue.providers p
               where 'campus_region' = any (p_fields) and coalesce(p.lifecycle_status, 'active') = 'active'
                 and exists (select 1 from catalogue.campuses c4 where c4.provider_id = p.id and c4.status = 'active' and c4.subdivision_id is null and nullif(btrim(c4.city), '') is not null)) m
        left join lateral (select e.state, e.updated_at, e.reason from pipeline.field_enrich_items e
                            where e.course_id is null and e.field = m.field and e.provider_id = m.provider_id order by e.id desc limit 1) l on true
       where not exists (select 1 from pipeline.manual_locks lk where lk.entity = 'provider' and lk.entity_id = m.provider_id and lk.field in (m.field, 'all'))
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = m.provider_id)
         and coalesce(l.state, '') not in ('queued', 'waiting', 'ai', 'leased', 'review')
         and (l.state is null or l.state = 'filled' or l.reason = 'provider unpublished' or l.updated_at < now() - make_interval(days => p_days))
       limit greatest(p_cap - v_have, 0);
      get diagnostics v_n = row_count;
      v_have := v_have + v_n; k.cycle_found := k.cycle_found + v_n;
    end if;
    if v_have >= p_cap then v_stop := 'cap'; exit; end if;
    if clock_timestamp() - v_t0 > make_interval(secs => v_secs) then v_stop := 'time'; exit; end if;
    v_ids := array(select c.id from catalogue.courses c where c.lifecycle_status = 'active' and (v_last is null or c.id > v_last) order by c.id limit v_slice);
    if cardinality(v_ids) = 0 then
      v_last := null;
      -- the pass ended; with nothing found in this run, one more pass from the start (once), so nothing found means a whole pass
      if v_have = 0 and not v_wrapped and v_from is not null then v_wrapped := true; continue; end if;
      v_stop := 'end'; exit;
    end if;
    insert into _gap
    select m.provider_id, m.course_id, m.field,
           case when l.state is null then 1
                when exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.course_id and g.read_at > l.updated_at) then 0
                else 2 end
      from (select c2.id course_id, c2.provider_id, f.x field
              from catalogue.courses c2 cross join unnest(v_cf) f(x)
             where c2.id = any (v_ids)
               and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c2.provider_id)  -- unpublished providers wait (the tick's own rule, applied before the cap)
               and case f.x when 'campus' then not exists (select 1 from catalogue.course_campuses x where x.course_id = c2.id)
                            when 'duration' then c2.duration_value is null when 'level' then c2.study_level_id is null
                            when 'delivery' then nullif(btrim(c2.delivery_mode), '') is null when 'field_of_study' then c2.primary_field_id is null
                            when 'international' then c2.open_to_international is null
                            when 'english' then not exists (select 1 from catalogue.course_english_requirements x where x.course_id = c2.id and coalesce(x.status, 'active') = 'active')
                            when 'intakes' then not exists (select 1 from catalogue.course_intakes x where x.course_id = c2.id and x.status = 'active') else false end) m
      left join lateral (select e.state, e.updated_at, e.reason from pipeline.field_enrich_items e
                          where e.course_id = m.course_id and e.field = m.field and e.provider_id = m.provider_id order by e.id desc limit 1) l on true
     where not exists (select 1 from pipeline.manual_locks lk where lk.entity = 'course' and lk.entity_id = m.course_id and lk.field in (m.field, 'all'))
       and coalesce(l.state, '') not in ('queued', 'waiting', 'ai', 'leased', 'review')   -- being worked on, or waiting for a person
       and (l.state is null or l.state = 'filled'                                          -- never tried, or filled and since emptied
            or l.reason = 'provider unpublished'                                           -- skipped while unpublished, published again
            or l.updated_at < now() - make_interval(days => p_days)                        -- not stated: checked again after the set days
            or exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.course_id and g.read_at > l.updated_at))  -- or once the page is read again
     order by m.course_id, m.field
     limit greatest(p_cap - v_have, 0);
    get diagnostics v_n = row_count;
    v_have := v_have + v_n; k.cycle_found := k.cycle_found + v_n; v_scanned := v_scanned + cardinality(v_ids); v_slices := v_slices + 1;
    if v_have >= p_cap then
      -- the cap was reached inside this slice: resume after the last course taken whole (the boundary course is checked again; what was taken
      -- from it is then in progress and is not taken twice)
      v_last := (select x from unnest(v_ids) x where x < (select g.course_id from _gap g where g.course_id = any (v_ids) order by g.course_id desc limit 1) order by x desc limit 1);
      if v_last is null then v_last := k.cursor_course_id; end if;
      k.cycle_scanned := k.cycle_scanned + cardinality(v_ids);
      v_stop := 'cap'; exit;
    end if;
    v_last := v_ids[cardinality(v_ids)];
    k.cycle_scanned := k.cycle_scanned + cardinality(v_ids);
  end loop;
  update pipeline.field_gap_queue_checkpoint set cycle = k.cycle, cycle_started_at = k.cycle_started_at, cursor_course_id = v_last,
         cycle_scanned = k.cycle_scanned, cycle_found = k.cycle_found, last_run_at = now(), updated_at = now()
   where id = 1;
  return jsonb_build_object('cycle', k.cycle, 'cursor_from', v_from, 'cursor_to', v_last, 'scanned', v_scanned, 'slices', v_slices, 'found', v_have,
                            'stopped', v_stop, 'cycle_complete', v_last is null, 'wrapped', v_wrapped,
                            'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);  -- fixed: milliseconds
end $function$;
revoke all on function security.field_gap_scan_v1(text[], integer, integer) from public, anon, authenticated;

select pg_temp.edit_once('security.field_gap_queue_tick_v1()', array['d909e54d6b6de0f8d2893fbb2d8553bd', '387f8edbe3363ea52317e024d96f2369'],
                         array['200f3210c75a71e6e5f5f0eceb37ea66', '9bb80b419ee26a049b99a35fb278e272'], array[
 [$o$  insert into _gap
  with miss as (
    select c2.id course_id, c2.provider_id, f.x field
      from catalogue.courses c2 cross join unnest(v_fields) f(x)
     where c2.lifecycle_status = 'active' and f.x not in ('provider_address', 'campus_list', 'campus_region')
       and case f.x when 'campus' then not exists (select 1 from catalogue.course_campuses x where x.course_id = c2.id)
                    when 'duration' then c2.duration_value is null when 'level' then c2.study_level_id is null
                    when 'delivery' then nullif(btrim(c2.delivery_mode), '') is null when 'field_of_study' then c2.primary_field_id is null
                    when 'international' then c2.open_to_international is null
                    when 'english' then not exists (select 1 from catalogue.course_english_requirements x where x.course_id = c2.id and coalesce(x.status, 'active') = 'active')
                    when 'intakes' then not exists (select 1 from catalogue.course_intakes x where x.course_id = c2.id and x.status = 'active') else false end
    union all
    select null::uuid, p.id, 'provider_address'
      from catalogue.providers p
     where 'provider_address' = any (v_fields) and nullif(btrim(p.address_line1), '') is null and coalesce(p.lifecycle_status, 'active') = 'active'
       and exists (select 1 from catalogue.courses c3 where c3.provider_id = p.id and c3.lifecycle_status = 'active')
    union all
    select null::uuid, p.id, 'campus_region'
      from catalogue.providers p
     where 'campus_region' = any (v_fields) and coalesce(p.lifecycle_status, 'active') = 'active'
       and exists (select 1 from catalogue.campuses k where k.provider_id = p.id and k.status = 'active' and k.subdivision_id is null and nullif(btrim(k.city), '') is not null)),
  last as (
    select distinct on (e.provider_id, e.course_id, e.field) e.provider_id, e.course_id, e.field, e.state, e.updated_at, e.reason
      from pipeline.field_enrich_items e where e.field <> 'campus_list'
     order by e.provider_id, e.course_id, e.field, e.id desc)
  select m.provider_id, m.course_id, m.field,
         case when l.state is null then 1
              when exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.course_id and g.read_at > l.updated_at) then 0
              else 2 end
    from miss m
    left join last l on l.provider_id = m.provider_id and l.course_id is not distinct from m.course_id and l.field = m.field
   where not exists (select 1 from pipeline.manual_locks k where k.entity = case when m.course_id is null then 'provider' else 'course' end
                       and k.entity_id = coalesce(m.course_id, m.provider_id) and k.field in (m.field, 'all'))
     and coalesce(l.state, '') not in ('queued', 'waiting', 'ai', 'leased', 'review')   -- being worked on, or waiting for a person
     and (l.state is null or l.state = 'filled'                                          -- never tried, or filled and since emptied
          or l.reason = 'provider unpublished'                                           -- 22 Oct 2026: skipped while unpublished, published again
          or l.updated_at < now() - make_interval(days => v_days)                        -- not stated: checked again after the set days
          or exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.course_id and g.read_at > l.updated_at))  -- or once the page is read again
   order by 4, m.course_id
   limit v_cap;
$o$,
  $n$  -- CF-247 P0 mandate 3 Nov 2026 §3 Agent C: the same selection in bounded slices from a durable checkpoint (security.field_gap_scan_v1); the
  -- single statement over every course timed out in 2 of 4 runs and kept nothing
  v_x := v_x || jsonb_build_object('scan', security.field_gap_scan_v1(v_fields, v_days, v_cap));
$n$]], array[1]);

create or replace function security.field_gap_queue_run_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 P0 mandate 3 Nov 2026 10:44 §3 Agent C: job field-gap-queue. Runs security.field_gap_queue_tick_v1 and records the run with an honest
-- outcome: done (a task with items), held (the previous standing task is still open, or the pass continues next run), idle (a full pass found
-- nothing), switched_off (the queue is off). A run never says "nothing due" while its pass is unfinished.
declare v jsonb; v_t0 timestamptz := clock_timestamp(); v_scan jsonb; v_out text; v_hold text; v_q text;
begin
  v := security.field_gap_queue_tick_v1();
  v_scan := v->'scan'; v_q := v->>'queue';
  v_out := case when v_q = 'started' then 'done' when v_q = 'off' then 'switched_off' when v_q = 'previous run still open' then 'held'
                when v_scan is not null and not coalesce((v_scan->>'cycle_complete')::boolean, true) then 'held'
                else 'idle' end;
  v_hold := case when v_q = 'previous run still open' then 'previous_run_open' when v_q = 'off' then 'queue_off'
                 when v_out = 'held' then 'scan_continues' when v_out = 'idle' then 'nothing_due' end;
  insert into pipeline.field_gap_queue_runs(outcome, hold_reason, items, scanned, cycle, cursor_from, cursor_to, cycle_complete, job_id, ms, detail)
  values (v_out, v_hold, coalesce((v->>'items')::int, 0), coalesce((v_scan->>'scanned')::int, 0), (v_scan->>'cycle')::int,
          (v_scan->>'cursor_from')::uuid, (v_scan->>'cursor_to')::uuid, (v_scan->>'cycle_complete')::boolean, (v->>'job_id')::uuid,
          (extract(epoch from clock_timestamp() - v_t0) * 1000)::int, v - 'crosscheck');  -- fixed: milliseconds
  return v || jsonb_build_object('outcome', v_out, 'hold_reason', v_hold);
end $function$;
revoke all on function security.field_gap_queue_run_v1() from public, anon, authenticated;

-- 5. no calls to a switched-off lane (and, with lanes.skip_held_paid_calls on, none while its budget is held) ------------------------------
create or replace function security.worker_lane_call_v1(p_mode text) returns boolean
language plpgsql security definer set search_path to '' as $function$
-- CF-247 P0 mandate 3 Nov 2026 10:44 §3 Agent C ("does not repeatedly invoke disabled jobs"): whether a job should call the worker for this
-- mode now. A lane switched off is not called. With lanes.skip_held_paid_calls on, a paid lane held by its Firecrawl share or the plan reserve
-- is not called either; one ledger row per lanes.hold_note_minutes records the hold (lane_outcome budget_held) so it stays visible.
declare v_purpose text; v_hold text;
begin
  if p_mode = 'link_search' and not coalesce((select s.enabled from pipeline.course_link_search_settings s where s.id = 1), false) then return false; end if;
  if security.pipeline_num_v1('lanes.skip_held_paid_calls', 0) < 1 then return true; end if;
  select l.fc_purpose into v_purpose from pipeline.worker_mode_lanes l where l.mode = p_mode and l.lane = 'paid_acquisition';
  v_hold := security.lane_paid_hold_v1(v_purpose);
  if v_hold is null then return true; end if;
  if not exists (select 1 from pipeline.mode_outcome_ledger y where y.mode = p_mode and y.worker = 'lane-guard'
                    and y.run_at > now() - make_interval(mins => security.pipeline_num_v1('lanes.hold_note_minutes', 60)::int)) then
    insert into pipeline.mode_outcome_ledger(mode, status, ms, items, ok, failed, landed, worker, detail, outcome, lane_outcome, hold_reason)
    values (p_mode, 200, 0, 0, 0, 0, '{}'::jsonb, 'lane-guard', jsonb_build_object('skipped', 'the worker was not called'), 'idle', 'budget_held', v_hold);  -- fixed: HTTP 200, no call made
  end if;
  return false;
end $function$;
revoke all on function security.worker_lane_call_v1(text) from public, anon, authenticated;

-- 6. measures: one row per lane --------------------------------------------------------------------------------------------------------------
create or replace function security.lane_status_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 P0 mandate 3 Nov 2026 10:44 §6 ("Each lane must have independently measurable work, cost and hold reasons"): per lane, the eligible
-- work now, what was processed, failed and held over the last lanes.status_window_minutes (worker ledger, by lane), the live hold, and the cost
-- today and in the window. Read-only. Shown on Platform health › Integration queue › Pipeline yield (public.admin_pipeline_yield).
declare v_since timestamptz := now() - make_interval(mins => security.pipeline_num_v1('lanes.status_window_minutes', 60)::int);
        v_day timestamptz := security.fc_day_start_v1(); v jsonb := '[]'::jsonb; r record; v_led jsonb; k pipeline.field_gap_queue_checkpoint%rowtype;
        v_last pipeline.field_gap_queue_runs%rowtype;
begin
  for r in select * from (values ('stored_evidence', 'Stored evidence and direct reads', 1), ('paid_acquisition', 'New paid pages (Firecrawl)', 2),
                                 ('ai_extraction', 'AI extraction', 3)) x(lane, label, sort) loop
    select jsonb_build_object('calls', count(*), 'processed', coalesce(sum(y.ok) filter (where y.lane_outcome = 'done'), 0),
             'failed', count(*) filter (where y.lane_outcome = 'failed'),
             'held', coalesce((select jsonb_object_agg(z.o, z.n) from (select y2.lane_outcome o, count(*) n from pipeline.mode_outcome_ledger y2 join pipeline.worker_mode_lanes l2 on l2.mode = y2.mode
                                                                     where l2.lane = r.lane and y2.run_at > v_since and y2.lane_outcome in ('budget_held', 'source_limit', 'switched_off') group by 1) z), '{}'::jsonb),
             'hold_reasons', coalesce((select jsonb_agg(distinct left(y3.hold_reason, 160)) from pipeline.mode_outcome_ledger y3 join pipeline.worker_mode_lanes l3 on l3.mode = y3.mode
                                        where l3.lane = r.lane and y3.run_at > v_since and y3.lane_outcome in ('budget_held', 'source_limit', 'switched_off', 'failed')), '[]'::jsonb),
             'idle', count(*) filter (where y.lane_outcome = 'idle'))
      into v_led
      from pipeline.mode_outcome_ledger y join pipeline.worker_mode_lanes l on l.mode = y.mode
     where l.lane = r.lane and y.run_at > v_since;
    v := v || (jsonb_build_object('lane', r.lane, 'label', r.label, 'window_since', v_since) || v_led || case r.lane
      when 'stored_evidence' then jsonb_build_object(
        'eligible', jsonb_build_object(
          'course_pages_due', (select count(*) from pipeline.coverage_course_pages p where p.status in ('bound', 'ambiguous') and coalesce(p.next_read_at, now()) <= now() and p.read_attempts < 3)),  -- fixed: the read picker's own try limit
        'live_hold', null, 'cost', jsonb_build_object('firecrawl_credits_today', 0, 'ai_usd_today', 0))
      when 'paid_acquisition' then jsonb_build_object(
        'eligible', jsonb_build_object(
          'course_searches_queued', (select count(*) from pipeline.course_link_search s where s.state = 'queued'),
          'central_searches_queued', (select count(*) from pipeline.provider_central_search s where s.state = 'queued'),
          'scholarship_listings_due', (select count(*) from pipeline.scholarship_listing_pages s where s.active and s.source <> 'suggested' and coalesce(s.next_read_at, now()) <= now()),
          'scholarship_items_waiting_for_a_page', (select count(*) from pipeline.scholarship_ai_queue q where q.state = 'queued' and q.next_try_at <= now() and q.attempts < 3  -- fixed: the AI reader's own try limit
                                                     and not security.scholarship_ai_has_copy_v1(q.id))),
        'live_hold', (select jsonb_object_agg(p.purpose, security.lane_paid_hold_v1(p.purpose)) from (values ('scrape'), ('course_link_search'), ('central_map'), ('map'), ('sch_scrape')) p(purpose)),
        'cost', jsonb_build_object('firecrawl_credits_today', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.at >= v_day),
                                   'firecrawl_credits_window', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.at > v_since)))
      else jsonb_build_object(
        'eligible', jsonb_build_object(
          'enrich_items_waiting', (select count(*) from pipeline.field_enrich_items e where e.state = 'ai'),
          'scholarship_items_due', (select count(*) from pipeline.scholarship_ai_queue q where q.state = 'queued' and q.next_try_at <= now() and q.attempts < 3),  -- fixed: the AI reader's own try limit
          'fee_pages_queued', (select count(*) from pipeline.fee_reader_queue q where q.state = 'queued'),
          'central_pages_queued', (select count(*) from pipeline.central_ai_queue q where q.state = 'queued'),
          'provider_descriptions_queued', (select count(*) from pipeline.provider_description_reads d where d.state = 'queued')),
        'live_hold', (select jsonb_object_agg(a.use, security.ai_use_refusal_v1(a.use)) from (values ('enrich_fields'), ('fee_ai'), ('scholarship_ai'), ('central_ai'), ('provider_description')) a(use)),
        'cost', jsonb_build_object('ai_usd_today', (select coalesce(round(sum(a.cost_usd), 4), 0) from pipeline.ai_spend_ledger a where a.at >= v_day),
                                   'ai_usd_window', (select coalesce(round(sum(a.cost_usd), 4), 0) from pipeline.ai_spend_ledger a where a.at > v_since))) end);
  end loop;
  -- Layer 4 admission: waiting for a person, decided in the window
  v := v || jsonb_build_object('lane', 'layer4_admission', 'label', 'Layer 4 admission', 'window_since', v_since,
          'eligible', jsonb_build_object('pending', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending')),
          'processed', (select count(*) from pipeline.layer4_review_items i where i.decided_at > v_since),
          'failed', 0, 'held', '{}'::jsonb, 'live_hold', null, 'cost', jsonb_build_object('firecrawl_credits_today', 0, 'ai_usd_today', 0));
  -- the standing gap queue: its checkpoint and its runs
  select * into k from pipeline.field_gap_queue_checkpoint where id = 1;
  select * into v_last from pipeline.field_gap_queue_runs order by run_at desc, id desc limit 1;
  v := v || jsonb_build_object('lane', 'gap_queue', 'label', 'Standing gap queue', 'window_since', v_since,
          'eligible', jsonb_build_object('pass', k.cycle, 'pass_started_at', k.cycle_started_at, 'courses_checked_in_pass', k.cycle_scanned,
                                         'gaps_found_in_pass', k.cycle_found, 'pass_complete', k.cursor_course_id is null),
          'processed', (select coalesce(sum(g.items), 0) from pipeline.field_gap_queue_runs g where g.run_at > v_since),
          'failed', 0,
          'held', coalesce((select jsonb_object_agg(z.h, z.n) from (select g.hold_reason h, count(*) n from pipeline.field_gap_queue_runs g where g.run_at > v_since and g.outcome = 'held' group by 1) z), '{}'::jsonb),
          'last_run', case when v_last.id is not null then jsonb_build_object('at', v_last.run_at, 'outcome', v_last.outcome, 'hold_reason', v_last.hold_reason,
                                                                               'items', v_last.items, 'scanned', v_last.scanned, 'ms', v_last.ms) end,
          'live_hold', null, 'cost', jsonb_build_object('firecrawl_credits_today', 0, 'ai_usd_today', 0));
  return jsonb_build_object('at', now(), 'lanes', v);
end $function$;
revoke all on function security.lane_status_v1() from public, anon, authenticated;

select pg_temp.edit_once('public.admin_pipeline_yield(jsonb)', array['a9d64bbca63b5e1c587edabf4e1fef59'], array['a38814324515b163a34129b7a9d01dbd'], array[
 [$o$  return security.pipeline_yield_v1(nullif(p_args->>'hours', '')::int);$o$,
  $n$  -- CF-247 P0 mandate 3 Nov 2026 §6: each lane's work, holds and cost beside the stage yield
  return security.pipeline_yield_v1(nullif(p_args->>'hours', '')::int) || jsonb_build_object('lane_status', security.lane_status_v1());$n$]], array[1]);

-- 7. job commands (G2: no number; each job keeps its schedule and active state) ---------------------------------------------------------------
do $j$
declare r record; v_id bigint; v_cmd text;
begin
  for r in select * from (values
    ('field-gap-queue', $c$select security.field_gap_queue_tick_v1()$c$, $c$select security.field_gap_queue_run_v1()$c$),
    ('course-link-search-worker', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'link_search', 'limit', security.pipeline_num_v1('batch.link_search_worker', 120)::int))$c$,
                                  $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'link_search', 'limit', security.pipeline_num_v1('batch.link_search_worker', 120)::int)) where security.worker_lane_call_v1('link_search')$c$),
    ('central-find', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'central_find', 'limit', security.pipeline_num_v1('batch.central_find', 4)::int))$c$,
                     $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'central_find', 'limit', security.pipeline_num_v1('batch.central_find', 4)::int)) where security.worker_lane_call_v1('central_find')$c$),
    ('coverage-discover', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'discover', 'limit', security.pipeline_num_v1('batch.coverage_discover', 20)::int))$c$,
                          $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'discover', 'limit', security.pipeline_num_v1('batch.coverage_discover', 20)::int)) where security.worker_lane_call_v1('discover')$c$),
    ('coverage-discover-2', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'discover', 'limit', security.pipeline_num_v1('batch.coverage_discover_2', 8)::int))$c$,
                            $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'discover', 'limit', security.pipeline_num_v1('batch.coverage_discover_2', 8)::int)) where security.worker_lane_call_v1('discover')$c$),
    ('scholarship-listing', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode','scholarship_listing','limit',security.scholarship_setting('listing_limit',6)::int))$c$,
                            $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode','scholarship_listing','limit',security.scholarship_setting('listing_limit',6)::int)) where security.worker_lane_call_v1('scholarship_listing')$c$),
    ('scholarship-read', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode','scholarship_read','limit',security.scholarship_setting('read_limit',20)::int))$c$,
                         $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode','scholarship_read','limit',security.scholarship_setting('read_limit',20)::int)) where security.worker_lane_call_v1('scholarship_read')$c$)
  ) x(jobname, old_cmd, new_cmd) loop
    select j.jobid, j.command into v_id, v_cmd from cron.job j where j.jobname = r.jobname;
    if v_id is null then raise exception 'lanes: job % not found', r.jobname; end if;
    if v_cmd = r.new_cmd then continue; end if;
    if v_cmd <> r.old_cmd then raise exception 'lanes: job % runs a command this change was not written against: %', r.jobname, v_cmd; end if;
    perform cron.alter_job(v_id, command := r.new_cmd);
  end loop;
end $j$;

update pipeline.automation_catalogue set description = description || ' Runs through security.field_gap_queue_run_v1: the gaps are found in bounded slices from a saved checkpoint (gaps.scan_courses_per_slice, gaps.scan_seconds), the next run resumes where one stopped, and every run is recorded with its outcome and hold reason (pipeline.field_gap_queue_runs).'
 where jobname = 'field-gap-queue' and description not like '%field_gap_queue_run_v1%';
update pipeline.automation_catalogue set description = description || ' Calls the worker only when security.worker_lane_call_v1 allows it: never while the lane is switched off, and, with lanes.skip_held_paid_calls on, not while its Firecrawl budget is held (the hold is recorded instead).'
 where jobname in ('course-link-search-worker', 'central-find', 'coverage-discover', 'coverage-discover-2', 'scholarship-listing', 'scholarship-read') and description not like '%worker_lane_call_v1%';

-- 8. component register -------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.worker_mode_lanes', 'Platform', 'Platform upkeep', 'The lane of each worker mode (stored evidence, paid pages, AI) and its Firecrawl purpose', 'active', '{}', '20261103160000'),
 ('table', 'pipeline.field_gap_queue_checkpoint', 'Layer 2', 'Enrichment', 'Where the standing gap queue stopped in its pass', 'active', '{}', '20261103160000'),
 ('table', 'pipeline.field_gap_queue_runs', 'Layer 2', 'Enrichment', 'Every standing gap queue run with its outcome and hold reason', 'active', '{}', '20261103160000'),
 ('function', 'security.field_gap_scan_v1', 'Layer 2', 'Enrichment', 'Standing gap queue: bounded slices from the checkpoint', 'active', '{}', '20261103160000'),
 ('function', 'security.field_gap_queue_run_v1', 'Layer 2', 'Enrichment', 'Job field-gap-queue: the tick and its recorded outcome', 'active', '{}', '20261103160000'),
 ('function', 'security.worker_lane_outcome_v1', 'Platform', 'Platform upkeep', 'Lane outcome and hold reason of each worker call', 'active', '{}', '20261103160000'),
 ('function', 'security.lane_paid_hold_v1', 'Platform', 'Platform upkeep', 'Why new paid reading is held (plan reserve, daily share)', 'active', '{}', '20261103160000'),
 ('function', 'security.worker_lane_call_v1', 'Platform', 'Platform upkeep', 'Whether a job calls a worker lane now (switched off, held)', 'active', '{}', '20261103160000'),
 ('function', 'security.lane_status_v1', 'Platform', 'Platform upkeep', 'Per-lane work, holds and cost (Pipeline yield)', 'active', '{}', '20261103160000'),
 ('function', 'security.scholarship_ai_has_copy_v1', 'Layer 2', 'Scholarships', 'Scholarship AI item has a stored copy', 'active', '{}', '20261103160000'),
 ('function', 'security.jsonb_int_v1', 'Platform', 'Platform upkeep', 'A count in a worker answer, read safely', 'active', '{}', '20261103160000')
on conflict do nothing;

-- 9. post-check ------------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('lanes.stored_first_on', 'lanes.skip_held_paid_calls',
        'lanes.hold_note_minutes', 'lanes.status_window_minutes', 'gaps.scan_courses_per_slice', 'gaps.scan_seconds')) <> 6 then
    raise exception 'lanes post-check: a setting is missing'; end if;
  if exists (select 1 from cron.job where jobname in ('field-gap-queue', 'course-link-search-worker', 'central-find', 'coverage-discover', 'coverage-discover-2', 'scholarship-listing', 'scholarship-read')
              and jobname <> 'field-gap-queue' and command not like '%worker_lane_call_v1(%') then
    raise exception 'lanes post-check: a guarded job still calls the worker without the lane check'; end if;
  if (select command from cron.job where jobname = 'field-gap-queue') <> 'select security.field_gap_queue_run_v1()' then
    raise exception 'lanes post-check: field-gap-queue does not run the recorded wrapper'; end if;
  if (select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'lanes.skip_held_paid_calls') <> 0 then
    raise exception 'lanes post-check: lanes.skip_held_paid_calls must ship off'; end if;
end $$;
