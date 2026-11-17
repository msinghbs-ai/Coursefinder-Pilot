-- CF-247 P0 Autonomous AI Operations: Layer 4 technical readiness and admission throughput (engineering agent L4; Platform Admin priority
-- 3 Nov 2026 18:14 AEDT "Prioritise Layer 4 admission throughput"; mandate 15:37 §10, acceptance mandate 15:52 §16; admin
-- docs/platform/LAYER4-INBOX-DESIGN.md, nz-enrichment-brief/2026-11-02-aer-layer4-admission-review-and-playbook.md and
-- 2026-11-02-aer-layer4-readiness-assessment.md). Codes against workstream A's operations contract (20261104010000, live in v2.15.429).
-- Why (live, read-only, 3 Nov 2026 18:16-18:28 AEDT):
--   * 4,314 items wait in Layer 4: official_course_url 3,178, course_entry_first_read 510, course_description_first_read 381,
--     provider_current_tuition_validation 135, no_page_first_run 55, entry_matrix_first_run 40, others 15. Decisions in the last 7 days:
--     27 Oct 198, 28 Oct 5, 29 Oct 0, 30 Oct 135, 31 Oct 119, 1 Nov 513, 2 Nov 17, 3 Nov 1, against 1,055 new items in the last day.
--   * Nothing tells a reviewer which items are ready for judgement. 81 official-link items propose an address the apply refuses (not a full
--     https:// address), 5 are on courses whose page was set by hand (the apply refuses them), 28 are on courses or providers no longer active
--     (IQ-00061); the AER reads held by the E13/D-R3 gates look the same as ready ones.
--   * Items come back after a decision (IQ-00039, IQ-00040): 51 tuition checks re-propose the exact fee rejected on 27 Oct, 1 official link
--     re-proposes a page approved on 18 Oct and 2 re-propose pages returned on 12 Oct. The generators compare raw values (or nothing), so the
--     same question is asked again. IQ-00038 is not a duplicate: its 24 items are 24 different entry-matrix sources of 2 providers (the check
--     keys on entity and field only); no true duplicate is pending today.
--   * Nothing checks an approval after it is saved. Of 191 official-link approvals in 30 days, 19 (all 17-30 Oct, before E15) never reached
--     the catalogue: the course's page had been set by hand and the pre-E15 apply skipped the row silently while the decision was recorded.
-- What (one mechanism per gap, each a platform behaviour the operations controller runs; nothing decides a Layer 4 item, admission rules are
-- unchanged and manual locks are never touched):
--   1 Identity: security.layer4_url_key_v1, layer4_value_key_v1, layer4_scope_key_v1 (what makes two items the same question).
--   2 Resolution: security.layer4_resolution_for_v1 / layer4_resolution_v1: an item the platform can settle without a person (duplicate of a
--     waiting item, already decided with no new evidence, already the active value, its course or provider retired). Supersede only, with the
--     reason and the item or decision that covers it (pipeline.layer4_supersessions); reversible by the Platform Admin.
--   3 Generator guard: trigger layer4_review_items_zz_arrival (BEFORE INSERT, after the existing reroute trigger) applies 2 to every generator
--     at once for the kinds in layer4.platform_kinds. Ships OFF (layer4.arrival_guard_on 0).
--   4 Technical blockers: security.layer4_blockers_v1 classifies what the apply would refuse or the gates hold (manual lock, invalid link,
--     missing or stale evidence, value moved, completeness gate, nothing left to admit), so reviewers see judgement-ready items first and the
--     rest go to repair (pipeline.layer4_item_readiness). Ships ON (classifies and records only).
--   5 Post-decision verification: security.layer4_admission_check_v1 checks every approval: the value is in the catalogue and in the search
--     projection (pipeline.layer4_admission_checks). Failures open one integration issue per kind and reason. Ships ON (records only).
--   6 Job layer4-readiness (:22 and :52, before the controller at :24 and :54): 4, 5, and 2 when layer4.reconcile_supersede_on (OFF).
--   7 Root causes and remedies through workstream A's contract; auto remedies only supersede, re-verify or record; the supersede remedy is
--     registered inactive and is activated with its switch.
--   8 security.layer4_throughput_v1: the reviewer-throughput view (judgement-ready items by kind, reviewer minutes per item measured from the
--     decision pace, what the platform resolved without a person, admission results).
-- Replaces: nothing (new identity, readiness, verification and report functions beside the existing generators; no live function is edited)
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object changes (G3): search.course_documents and catalogue tables are read only. No Firecrawl or
-- AI spend.

-- 0 the contract this change codes against (workstream A lands first) and the functions it calls, unchanged since they were read live --------
do $g$
declare r record;
begin
  if to_regclass('pipeline.ops_remedies') is null then
    raise exception 'workstream A''s operations contract (migration 20261104010000) must be applied before this change';
  end if;
  for r in select * from (values ('security.integration_issue_upsert_v1(jsonb,text)', 'c5ce0cb9c431a337789d67bc1878be62')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
end $g$;

-- 1 settings (G2; Settings > Pipeline settings, section Layer 4 readiness) -----------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'layer4.readiness_on', 'Layer 4 readiness: classify waiting items',
  'On (1): every waiting Layer 4 item is classified as ready for judgement, technically blocked (with the blocker and where it is repaired) or settled by the platform. It records only; no item is decided.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1200, 'Layer 4 readiness', 'security.layer4_readiness_tick_v1 (job layer4-readiness)', 'Platform Admin 3 Nov 2026 18:14 "Prioritise Layer 4 admission throughput"; mandate 15:37 §10: ships on (classifies and records only)'),
 ('pipeline', 'layer4.readiness_batch', 'Layer 4 readiness: items classified a run',
  'At most this many waiting items are classified in one run (never classified first, then the oldest classification).',
  'number', to_jsonb(1000), 50, 10000, 'items', 1201, 'Layer 4 readiness', 'security.layer4_readiness_tick_v1', 'Mandate 15:37 §10'),
 ('pipeline', 'layer4.readiness_recheck_minutes', 'Layer 4 readiness: classify an item again after',
  'A waiting item is classified again when its classification is older than this (locks, links and evidence change).',
  'number', to_jsonb(120), 30, 1440, 'minutes', 1202, 'Layer 4 readiness', 'security.layer4_readiness_tick_v1', 'Mandate 15:37 §10'),
 ('pipeline', 'layer4.gate_batch', 'Layer 4 readiness: completeness gates checked a run',
  'At most this many entry-requirement items have their completeness gate (E13, D-R3) evaluated in one run; each takes about a second.',
  'number', to_jsonb(20), 0, 500, 'items', 1203, 'Layer 4 readiness', 'security.layer4_readiness_tick_v1; security.layer4_blockers_v1', 'Readiness assessment 2 Nov 2026 §3 G6 (the gate takes about 0.7 s an item)'),
 ('pipeline', 'layer4.verify_on', 'Layer 4: check every approval reached the catalogue and the website',
  'On (1): after every approval the platform checks the value is in the catalogue and in the search projection, and opens an integration issue for each kind and reason that did not. Records only.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1204, 'Layer 4 readiness', 'security.layer4_readiness_tick_v1; security.layer4_admission_check_v1', 'Mandate 15:37 §10 "verify admission results after authorised decisions": ships on (records only)'),
 ('pipeline', 'layer4.verify_batch', 'Layer 4: approvals checked a run',
  'At most this many approvals are checked in one run (new decisions first, then rechecks).',
  'number', to_jsonb(300), 10, 5000, 'decisions', 1205, 'Layer 4 readiness', 'security.layer4_readiness_tick_v1', 'Mandate 15:37 §10'),
 ('pipeline', 'layer4.verify_lookback_days', 'Layer 4: approvals checked back to',
  'Approvals saved in this many days are checked (and rechecked until they pass).',
  'number', to_jsonb(30), 1, 365, 'days', 1206, 'Layer 4 readiness', 'security.layer4_readiness_tick_v1', 'Mandate 15:37 §10'),
 ('pipeline', 'layer4.verify_recheck_hours', 'Layer 4: recheck an approval that has not passed after',
  'An approval whose value is not (yet) in the catalogue or projection is checked again after this long.',
  'number', to_jsonb(6), 1, 168, 'hours', 1207, 'Layer 4 readiness', 'security.layer4_readiness_tick_v1', 'Mandate 15:37 §13'),
 ('pipeline', 'layer4.verify_wait_minutes', 'Layer 4: wait before checking the website projection',
  'An approval younger than this is not yet expected in the search projection (the projection refreshes on its own schedule).',
  'number', to_jsonb(90), 0, 1440, 'minutes', 1208, 'Layer 4 readiness', 'security.layer4_admission_check_v1', 'Mandate 15:37 §12 "admissions that did not publish"'),
 ('pipeline', 'layer4.arrival_guard_on', 'Layer 4: do not raise a question already settled',
  'On (1): a new item of a kind listed below that repeats a waiting item, an item already decided with no new evidence, or the value already active, arrives settled (superseded, with the reason and the item it repeats) instead of waiting for a person. Off (0): every item waits.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1209, 'Layer 4 readiness', 'trigger layer4_review_items_zz_arrival (security.layer4_arrival_guard_trg_v1)', 'Mandate 15:37 §10; Decision 263 (a decided proposal is not raised again). Removes work from the queue, so it ships off'),
 ('pipeline', 'layer4.reconcile_supersede_on', 'Layer 4: settle waiting items the platform can settle',
  'On (1): waiting items of a kind listed below that the platform can settle (a repeat, already decided with no new evidence, already the active value, course or provider retired) are superseded with the reason and the item or decision that covers them. Never approves or rejects. Off (0): they are only classified.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1210, 'Layer 4 readiness', 'security.layer4_reconcile_v1 (job layer4-readiness; remedy layer4_supersede_resolvable)', 'Mandate 15:37 §10, §15 (deduplication); removes work from the queue, so it ships off'),
 ('pipeline', 'layer4.reconcile_batch', 'Layer 4: items settled a run',
  'At most this many waiting items are superseded in one run.',
  'number', to_jsonb(200), 1, 5000, 'items', 1211, 'Layer 4 readiness', 'security.layer4_reconcile_v1', 'Mandate 15:37 §10'),
 ('pipeline', 'layer4.platform_kinds', 'Layer 4: kinds the platform may settle',
  'Item kinds whose repeats, already-decided and already-active items the platform may supersede. Entry-requirement reads (D-R2) and descriptions (their reader keeps a link to the item) are left out.',
  'list', '["official_course_url", "provider_current_tuition_validation", "provider_current_tuition", "course_english"]'::jsonb, null, null, 'field codes', 1212, 'Layer 4 readiness',
  'security.layer4_arrival_guard_trg_v1; security.layer4_reconcile_v1; security.layer4_readiness_tick_v1', 'Mandate 15:37 §10; AER pending reads are replaced through D-R2 only'),
 ('pipeline', 'layer4.same_page_new_copy_settles', 'Layer 4: a newer copy of the same page is not new evidence',
  'On (1): a proposal already approved or rejected, raised again from a newer stored copy of the same page address with the same value, counts as already decided (settled when settling is on). Off (0): any newer copy goes to a person.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1219, 'Layer 4 readiness', 'security.layer4_resolution_for_v1', 'Live 3 Nov 2026: the 51 tuition checks of IQ-00040 re-propose the rejected fee from a newer copy (new content hash) of the same page; whether that is new evidence is the Platform Admin''s decision, so it ships off'),
 ('pipeline', 'layer4.pace_min_gap_seconds', 'Layer 4: shortest gap counted as one item reviewed',
  'Decisions closer together than this are bulk actions (several items decided at once) and are not counted as one item''s review time.',
  'number', to_jsonb(20), 0, 600, 'seconds', 1220, 'Layer 4 readiness', 'security.layer4_pace_v1', 'Live 3 Nov 2026: in 30 days 949 decisions followed the same reviewer''s previous one within 20 seconds (bulk), 104 were single reviews'),
 ('pipeline', 'layer4.pace_window_days', 'Layer 4: decisions read for the reviewer pace',
  'Reviewer minutes per item are measured from the decisions saved in this many days.',
  'number', to_jsonb(30), 1, 180, 'days', 1213, 'Layer 4 readiness', 'security.layer4_pace_v1', 'Mandate 15:52 §17 (Layer 4 scorecard)'),
 ('pipeline', 'layer4.pace_gap_minutes', 'Layer 4: longest pause counted as reviewing',
  'Two decisions by the same reviewer this close together count as one item''s review time; a longer gap is a break and is not counted.',
  'number', to_jsonb(15), 1, 120, 'minutes', 1214, 'Layer 4 readiness', 'security.layer4_pace_v1', 'Mandate 15:52 §17'),
 ('pipeline', 'layer4.pace_min_decisions', 'Layer 4: decisions needed to measure a kind''s pace',
  'A kind with fewer measured decisions uses the default minutes below.',
  'number', to_jsonb(5), 1, 100, 'decisions', 1215, 'Layer 4 readiness', 'security.layer4_pace_v1', 'Mandate 15:52 §17'),
 ('pipeline', 'layer4.pace_default_minutes', 'Layer 4: reviewer minutes per item when not measured',
  'Used for a kind with too few measured decisions.',
  'number', to_jsonb(3), 0.1, 60, 'minutes', 1216, 'Layer 4 readiness', 'security.layer4_pace_v1', 'Mandate 15:52 §17'),
 ('pipeline', 'layer4.remedy_max_attempts', 'Layer 4: attempts of a Layer 4 remedy',
  'A Layer 4 remedy (re-verify or settle) runs at most this many times for one issue; then the issue needs a release.',
  'number', to_jsonb(2), 1, 10, 'attempts', 1217, 'Layer 4 readiness', 'remedies layer4_admission_recheck, layer4_supersede_resolvable', 'Mandate 15:37 §3 (no infinite retries)'),
 ('pipeline', 'layer4.remedy_cooldown_minutes', 'Layer 4: wait before verifying a Layer 4 remedy',
  'A Layer 4 remedy is verified no sooner than this after its action (and never in the same controller run).',
  'number', to_jsonb(60), 30, 1440, 'minutes', 1218, 'Layer 4 readiness', 'remedies layer4_admission_recheck, layer4_supersede_resolvable', 'Mandate 15:37 §13')
on conflict do nothing;

-- 2 tables ------------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.layer4_item_readiness (
  item_id uuid primary key references pipeline.layer4_review_items(id),
  entity_type text not null,
  entity_id uuid not null,
  field_code text not null,
  item_created_at timestamptz not null,
  item_status text not null,
  readiness text not null check (readiness in ('judgement_ready', 'technical_blocked', 'resolvable', 'closed')),
  reasons text[] not null default '{}',
  route text not null,
  resolution jsonb,
  blockers jsonb not null default '[]'::jsonb,
  est_minutes numeric,
  gate jsonb,
  gate_checked_at timestamptz,
  classified_at timestamptz not null default now(),
  rule text not null default 'L4R-1'
);
comment on table pipeline.layer4_item_readiness is 'CF-247 P0 Layer 4 readiness (Platform Admin 3 Nov 2026 18:14; mandate 15:37 §10): one row per Layer 4 item, written by job layer4-readiness (security.layer4_readiness_tick_v1). readiness: judgement_ready (a person can decide it now), technical_blocked (the apply would refuse it or a completeness gate holds it: blockers name why and route names where it is repaired), resolvable (the platform can settle it without a person: resolution names the reason and the covering item or decision; acted on only while layer4.reconcile_supersede_on is 1 and the kind is in layer4.platform_kinds) or closed (no longer waiting). est_minutes is the measured reviewer minutes per item for the kind (security.layer4_pace_v1). Classification only: no item is decided here. Never read by the consumer API.';
create index if not exists layer4_item_readiness_open_idx on pipeline.layer4_item_readiness (readiness, field_code) where readiness <> 'closed';
create index if not exists layer4_item_readiness_classified_idx on pipeline.layer4_item_readiness (classified_at) where readiness <> 'closed';
alter table pipeline.layer4_item_readiness enable row level security;
revoke all on pipeline.layer4_item_readiness from public, anon, authenticated;

create table if not exists pipeline.layer4_supersessions (
  id bigserial primary key,
  item_id uuid not null,
  field_code text not null,
  entity_type text not null,
  entity_id uuid not null,
  reason text not null check (reason in ('duplicate_pending', 'decided_before', 'covered_by_active', 'entity_retired')),
  covered_by_item uuid,
  evidence jsonb not null default '{}'::jsonb,
  mode text not null check (mode in ('arrival', 'reconcile')),
  at timestamptz not null default now(),
  reversed_at timestamptz,
  reversed_by uuid,
  reversed_note text
);
comment on table pipeline.layer4_supersessions is 'CF-247 P0 Layer 4 readiness (mandate 15:37 §10 "reconcile duplicate proposals, detect superseded work, identify existing approvals"): every Layer 4 item the platform superseded instead of asking a person, with the reason (duplicate_pending, decided_before, covered_by_active, entity_retired), the item or decision that covers it (covered_by_item) and the evidence. mode arrival: settled as it arrived (trigger layer4_review_items_zz_arrival); reconcile: settled while waiting (security.layer4_reconcile_v1). Nothing is deleted; a supersession is reversed by the Platform Admin (security.layer4_supersession_reverse_v1), which puts the item back to waiting. item_id has no foreign key because an arrival is recorded before its item row exists. Never read by the consumer API.';
create index if not exists layer4_supersessions_item_idx on pipeline.layer4_supersessions (item_id);
create index if not exists layer4_supersessions_at_idx on pipeline.layer4_supersessions (at desc);
alter table pipeline.layer4_supersessions enable row level security;
revoke all on pipeline.layer4_supersessions from public, anon, authenticated;
revoke all on sequence pipeline.layer4_supersessions_id_seq from public, anon, authenticated;

create table if not exists pipeline.layer4_admission_checks (
  decision_id uuid primary key references pipeline.layer4_decisions(id),
  review_item_id uuid not null,
  field_code text not null,
  entity_type text not null,
  entity_id uuid not null,
  decided_at timestamptz not null,
  result text not null check (result in ('admitted_published', 'admitted', 'admitted_not_published', 'not_admitted', 'superseded_later', 'not_applicable', 'not_checked', 'waiting')),
  reason text,
  admitted boolean,
  published boolean,
  lag_seconds numeric,
  detail jsonb not null default '{}'::jsonb,
  first_checked_at timestamptz not null default now(),
  checked_at timestamptz not null default now(),
  checks int not null default 1
);
comment on table pipeline.layer4_admission_checks is 'CF-247 P0 Layer 4 readiness (mandate 15:37 §10 "verify admission results after authorised decisions", §12 "admissions that did not publish"): the check of every Layer 4 approval, by job layer4-readiness (security.layer4_admission_check_v1): admitted (the approved value is in the catalogue), published (it is in the search projection the website reads), result and reason (for example not_admitted manual_lock_kept: the course''s page set by hand won, so the approval never took effect). lag_seconds: from the decision to the catalogue write. Rechecked until it passes (layer4.verify_recheck_hours). Records only. Never read by the consumer API.';
create index if not exists layer4_admission_checks_result_idx on pipeline.layer4_admission_checks (result, field_code);
create index if not exists layer4_admission_checks_decided_idx on pipeline.layer4_admission_checks (decided_at desc);
alter table pipeline.layer4_admission_checks enable row level security;
revoke all on pipeline.layer4_admission_checks from public, anon, authenticated;

create table if not exists pipeline.layer4_readiness_runs (
  id bigserial primary key,
  at timestamptz not null default now(),
  ms int,
  result jsonb not null
);
comment on table pipeline.layer4_readiness_runs is 'CF-247 P0 Layer 4 readiness: one row per run of job layer4-readiness (classified, gates checked, approvals checked, issues raised, items superseded, switches). Read by security.layer4_throughput_v1. Never read by the consumer API.';
create index if not exists layer4_readiness_runs_at_idx on pipeline.layer4_readiness_runs (at desc);
alter table pipeline.layer4_readiness_runs enable row level security;
revoke all on pipeline.layer4_readiness_runs from public, anon, authenticated;
revoke all on sequence pipeline.layer4_readiness_runs_id_seq from public, anon, authenticated;

-- 3 identity: what makes two items the same question --------------------------------------------------------------------------------------
create or replace function security.layer4_url_key_v1(p_url text) returns text
language sql immutable set search_path to '' as $function$
-- The same page however it is written: case, http or https, a leading www., a fragment and trailing slashes do not make a different page.
  select nullif(regexp_replace(regexp_replace(regexp_replace(lower(btrim(coalesce(p_url, ''))), '^https?://(www\.)?', ''), '#.*$', ''), '/+$', ''), '')
$function$;
revoke all on function security.layer4_url_key_v1(text) from public, anon, authenticated;

create or replace function security.layer4_value_key_v1(p_field text, p_value jsonb) returns text
language sql immutable set search_path to '' as $function$
-- The proposed value of an item, keyed so that the same proposal gives the same key: the page for a course link, the fee for a tuition check,
-- the run for an entry matrix, the text for a description, otherwise the proposal without its bookkeeping keys.
  select case
    when p_field = 'official_course_url' then security.layer4_url_key_v1(case jsonb_typeof(p_value) when 'string' then p_value #>> '{}'
                                                                               when 'object' then coalesce(p_value->>'course_url', p_value->>'url') end)
    when p_field in ('provider_current_tuition_validation', 'provider_current_tuition') and jsonb_typeof(p_value) = 'object' then
      concat_ws('|', coalesce(nullif(p_value->>'amount', '')::numeric(14, 2)::text, ''), coalesce(upper(coalesce(p_value->>'currency_code', p_value->>'currency')), ''),
                coalesce(lower(p_value->>'basis'), ''), coalesce(p_value->>'fee_year', ''), lower(coalesce(p_value->>'audience', 'international')))
    when p_field in ('entry_matrix_first_run', 'entry_matrix_change') then p_value->>'run_id'
    when p_field in ('course_description_first_read', 'provider_description') and jsonb_typeof(p_value->'sentences') = 'array' then
      md5((select string_agg(s->>'text', ' ' order by n) from jsonb_array_elements(p_value->'sentences') with ordinality x(s, n)))
    when jsonb_typeof(p_value) = 'object' then md5((p_value - 'checks' - 'item_id' - 'read_id' - 'supersedes')::text)
    else md5(coalesce(p_value::text, 'null')) end
$function$;
revoke all on function security.layer4_value_key_v1(text, jsonb) from public, anon, authenticated;

create or replace function security.layer4_scope_key_v1(p_field text, p_l2 jsonb, p_value jsonb) returns text
language sql immutable set search_path to '' as $function$
-- Within one entity and kind, items about different sources are different questions: an entry matrix item is one source of the provider
-- (ANU has 22 qualification sources, each its own review). Every other kind has one question per entity and kind.
  select case when p_field in ('entry_matrix_first_run', 'entry_matrix_change')
              then coalesce(p_l2->>'entry_matrix_source_id', p_value->>'source_id', p_value->>'run_id', '') else '' end
$function$;
revoke all on function security.layer4_scope_key_v1(text, jsonb, jsonb) from public, anon, authenticated;

-- 4 resolution: an item the platform can settle without a person --------------------------------------------------------------------------
create or replace function security.layer4_resolution_for_v1(p_id uuid, p_entity_type text, p_entity_id uuid, p_field text, p_value jsonb, p_l2 jsonb,
                                                             p_evidence uuid, p_created timestamptz) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- {reason, covered_by_item, evidence} when the platform can settle the item without asking a person, otherwise null. In order:
--   entity_retired     its course (or the course's provider, or the provider) is missing or not active (the integration check's orphan rule);
--   duplicate_pending  an earlier waiting item asks the same question (same entity, kind, source and proposal);
--   decided_before     the same proposal was approved or rejected before this item was raised, and this item brings no new evidence
--                      (no stored page, or the same stored page or content; or, while layer4.same_page_new_copy_settles is 1, a newer copy
--                      of the same page address); a re-raise with new evidence stays for a person;
--   covered_by_active  the proposal is already the active value (the course's active official page; its active fee; its description).
-- An item whose supersession the Platform Admin reversed is never settled again.
declare v_key text := security.layer4_value_key_v1(p_field, p_value); v_scope text := security.layer4_scope_key_v1(p_field, p_l2, p_value);
        v_prov uuid; v_life text; v_plife text; v_hit record; v_hash text; v_url text; v_txt text;
        v_copy boolean := security.pipeline_num_v1('layer4.same_page_new_copy_settles', 0) >= 1;
begin
  -- the Platform Admin put this item back to waiting: it is asked, never settled again by the platform
  if p_id is not null and exists (select 1 from pipeline.layer4_supersessions s where s.item_id = p_id and s.reversed_at is not null) then return null; end if;
  if p_entity_type = 'course' then
    select c.provider_id, c.lifecycle_status into v_prov, v_life from catalogue.courses c where c.id = p_entity_id;
    select p.lifecycle_status into v_plife from catalogue.providers p where p.id = v_prov;
    if v_prov is null or v_life is distinct from 'active' or v_plife is distinct from 'active' then
      return jsonb_build_object('reason', 'entity_retired', 'evidence', jsonb_build_object('course_status', coalesce(v_life, 'missing'), 'provider_status', coalesce(v_plife, 'missing')));
    end if;
  elsif p_entity_type = 'provider' then
    select p.lifecycle_status into v_plife from catalogue.providers p where p.id = p_entity_id;
    if v_plife is distinct from 'active' then
      return jsonb_build_object('reason', 'entity_retired', 'evidence', jsonb_build_object('provider_status', coalesce(v_plife, 'missing')));
    end if;
  end if;
  select i.id, i.created_at into v_hit from pipeline.layer4_review_items i
   where i.entity_id = p_entity_id and i.field_code = p_field and i.status = 'pending' and i.entity_type = p_entity_type and i.id <> coalesce(p_id, '00000000-0000-0000-0000-000000000000'::uuid)
     and (i.created_at, i.id) < (coalesce(p_created, now()), coalesce(p_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid))
     and security.layer4_scope_key_v1(i.field_code, i.layer2_state, i.proposed_value) = v_scope
     and security.layer4_value_key_v1(i.field_code, i.proposed_value) is not distinct from v_key
   order by i.created_at, i.id limit 1;
  if v_hit.id is not null then
    return jsonb_build_object('reason', 'duplicate_pending', 'covered_by_item', v_hit.id, 'evidence', jsonb_build_object('waiting_since', v_hit.created_at, 'value_key', v_key));
  end if;
  select e.content_hash, e.source_url into v_hash, v_url from pipeline.evidence_artifacts e where e.id = p_evidence;
  select i.id, i.status, i.decided_at, i.evidence_id into v_hit from pipeline.layer4_review_items i
   where i.entity_id = p_entity_id and i.field_code = p_field and i.entity_type = p_entity_type and i.status in ('approved', 'edited_approved', 'rejected')
     and i.decided_at is not null and i.decided_at < coalesce(p_created, now())
     and security.layer4_scope_key_v1(i.field_code, i.layer2_state, i.proposed_value) = v_scope
     and security.layer4_value_key_v1(i.field_code, i.proposed_value) is not distinct from v_key
     and (p_evidence is null or i.evidence_id = p_evidence
          or (v_hash is not null and v_hash = (select e.content_hash from pipeline.evidence_artifacts e where e.id = i.evidence_id))
          or (v_copy and v_url is not null and v_url = (select e.source_url from pipeline.evidence_artifacts e where e.id = i.evidence_id)))
   order by i.decided_at desc limit 1;
  if v_hit.id is not null then
    return jsonb_build_object('reason', 'decided_before', 'covered_by_item', v_hit.id,
      'evidence', jsonb_build_object('decision', v_hit.status, 'decided_at', v_hit.decided_at, 'value_key', v_key,
                                     'same_evidence', case when p_evidence is null then 'no stored page on the new item' when v_hit.evidence_id = p_evidence then 'same stored page'
                                                           when v_hash = (select e.content_hash from pipeline.evidence_artifacts e where e.id = v_hit.evidence_id) then 'same page content'
                                                           else 'same page address, newer copy' end));
  end if;
  if p_field = 'official_course_url' and v_key is not null then
    select l.id, l.url, l.is_primary into v_hit from catalogue.course_links l
     where l.course_id = p_entity_id and l.link_type = 'official_course' and l.status = 'active' and security.layer4_url_key_v1(l.url) = v_key
     order by l.is_primary desc limit 1;
    if v_hit.id is not null then
      return jsonb_build_object('reason', 'covered_by_active', 'evidence', jsonb_build_object('course_link_id', v_hit.id, 'url', v_hit.url, 'primary', v_hit.is_primary));
    end if;
  elsif p_field in ('provider_current_tuition_validation', 'provider_current_tuition') and jsonb_typeof(p_value) = 'object' then
    select f.id, f.amount into v_hit from catalogue.course_fees f
     where f.course_id = p_entity_id and f.status = 'active' and f.fee_type = 'provider_current_tuition'
       and concat_ws('|', coalesce(f.amount::numeric(14, 2)::text, ''), coalesce(upper(f.currency_code), ''), coalesce(lower(f.basis), ''), coalesce(f.fee_year::text, ''),
                     lower(coalesce(f.audience, 'international'))) = v_key
     limit 1;
    if v_hit.id is not null then
      return jsonb_build_object('reason', 'covered_by_active', 'evidence', jsonb_build_object('course_fee_id', v_hit.id, 'value_key', v_key));
    end if;
  elsif p_field = 'course_description_first_read' then
    select nullif(btrim(c.description), '') into v_txt from catalogue.courses c where c.id = p_entity_id;
    if v_txt is not null and v_txt = nullif(btrim(p_value->>'description'), '') then
      return jsonb_build_object('reason', 'covered_by_active', 'evidence', jsonb_build_object('description_chars', length(v_txt)));
    end if;
  end if;
  return null;
end $function$;
revoke all on function security.layer4_resolution_for_v1(uuid, text, uuid, text, jsonb, jsonb, uuid, timestamptz) from public, anon, authenticated;

create or replace function security.layer4_resolution_v1(p_item uuid) returns jsonb
language sql stable security definer set search_path to '' as $function$
  select security.layer4_resolution_for_v1(i.id, i.entity_type, i.entity_id, i.field_code, i.proposed_value, i.layer2_state, i.evidence_id, i.created_at)
    from pipeline.layer4_review_items i where i.id = p_item
$function$;
revoke all on function security.layer4_resolution_v1(uuid) from public, anon, authenticated;

-- 5 technical blockers: what the apply would refuse or a completeness gate holds -----------------------------------------------------------
create or replace function security.layer4_blockers_v1(p_item uuid, p_gate boolean) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- {blockers: [{code, why, repair}], route, gate}. Each blocker mirrors a refusal of the existing apply path or a gate, so an item with one cannot
-- be approved as it stands and is routed to repair instead of to a reviewer:
--   manual_lock        the value was set by hand on the record (the apply refuses; the lock is never touched here)
--   invalid_link       the proposed page is not a full https:// address, or its site is a search, social or listing site (the apply refuses)
--   evidence_missing   the kind's apply needs the stored page and there is none
--   evidence_stale     the stored page has been replaced by a newer copy, or is past its validity
--   value_moved        the value changed since the item was raised (the apply refuses)
--   completeness_gate  E13 or D-R3 holds the read (evaluated only when p_gate; otherwise the last result is kept by the caller)
--   nothing_to_admit   an entry read with no waiting row left
declare i pipeline.layer4_review_items; v_b jsonb := '[]'::jsonb; v_url text; v_ev pipeline.evidence_artifacts; v_gate jsonb; v_n int; v_now text; v_route text;
        v_aer boolean;
begin
  select * into i from pipeline.layer4_review_items where id = p_item;
  if i.id is null then return null; end if;
  v_aer := i.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change');
  if i.field_code = 'official_course_url' then
    v_url := btrim(coalesce(case jsonb_typeof(i.proposed_value) when 'string' then i.proposed_value #>> '{}' when 'object' then coalesce(i.proposed_value->>'url', i.proposed_value->>'course_url') end, ''));
    if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.entity_id and l.field in ('official_url', 'course_url')) then
      v_b := v_b || jsonb_build_object('code', 'manual_lock', 'why', 'the course''s page was set by hand on the course record', 'repair', 'course record (a person changes the page there, or keeps it)');
    end if;
    if v_url !~* '^https://[a-z0-9.-]+\.[a-z]{2,}(/[^\s]*)?$' then
      v_b := v_b || jsonb_build_object('code', 'invalid_link', 'why', 'the proposed page is not a full https:// address', 'repair', 'link repair (course page relink)', 'url', v_url);
    elsif to_regprocedure('security.reference_url_has_use(text,text)') is not null and security.reference_url_has_use(v_url, 'not_course_page') then
      v_b := v_b || jsonb_build_object('code', 'invalid_link', 'why', 'the proposed page is on a search, social or course-listing site', 'repair', 'link repair (course page relink)', 'url', v_url);
    end if;
  elsif i.field_code = 'course_description_first_read' then
    if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.entity_id and l.field in ('description', 'course_description', 'all')) then
      v_b := v_b || jsonb_build_object('code', 'manual_lock', 'why', 'the description was set by hand', 'repair', 'course record');
    end if;
    select nullif(btrim(c.description), '') into v_now from catalogue.courses c where c.id = i.entity_id;
    if v_now is distinct from nullif(btrim(i.before_value->>'description'), '') then
      v_b := v_b || jsonb_build_object('code', 'value_moved', 'why', 'the description changed since this was proposed', 'repair', 'course description reader (read again)');
    end if;
  elsif i.field_code = 'provider_description' then
    if exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = i.entity_id and l.field in ('description', 'p_description', 'all')) then
      v_b := v_b || jsonb_build_object('code', 'manual_lock', 'why', 'the description was set by hand', 'repair', 'provider record');
    end if;
  end if;
  if i.field_code in ('provider_current_tuition_validation', 'course_description_first_read', 'course_entry_first_read', 'entry_matrix_first_run', 'provider_description') then
    if i.evidence_id is null or not exists (select 1 from pipeline.evidence_artifacts e where e.id = i.evidence_id and (i.field_code <> 'provider_current_tuition_validation' or e.source_id is not null)) then
      v_b := v_b || jsonb_build_object('code', 'evidence_missing', 'why', 'there is no stored page (with its source) for this proposal', 'repair', 'the reader of this kind (read again)');
    end if;
  end if;
  if i.evidence_id is not null then
    select * into v_ev from pipeline.evidence_artifacts e where e.id = i.evidence_id;
    if v_ev.valid_to < now() or exists (select 1 from pipeline.evidence_artifacts n where n.supersedes_evidence_id = i.evidence_id) then
      v_b := v_b || jsonb_build_object('code', 'evidence_stale', 'why', 'a newer copy of the page is stored, or this copy is past its validity', 'repair', 'the reader of this kind (read the newer copy)');
    end if;
  end if;
  if i.field_code = 'course_entry_first_read' then
    select count(*) into v_n from catalogue.course_entry_requirements x
     where x.course_id = i.entity_id and x.status = 'proposed' and x.provenance->>'review_item_id' = i.id::text;
    if v_n = 0 then
      v_b := v_b || jsonb_build_object('code', 'nothing_to_admit', 'why', 'no waiting row is left on this read', 'repair', 'course entry reader (D-R2 replacement read)');
    end if;
    if p_gate and to_regprocedure('security.course_entry_gate_v1(uuid,uuid[])') is not null then
      v_gate := security.course_entry_gate_v1(i.id, '{}'::uuid[]);
    end if;
  elsif i.field_code in ('entry_matrix_first_run', 'entry_matrix_change') then
    if p_gate and to_regprocedure('security.entry_matrix_gate_v1(uuid,uuid[])') is not null and nullif(i.proposed_value->>'run_id', '') is not null then
      v_gate := security.entry_matrix_gate_v1((i.proposed_value->>'run_id')::uuid, '{}'::uuid[]);
    end if;
  end if;
  if v_gate is not null and not coalesce((v_gate->>'complete')::boolean, true) then
    v_b := v_b || jsonb_build_object('code', 'completeness_gate', 'why', coalesce(v_gate->'reasons'->>0, 'the completeness gate holds this read'),
                                     'repair', case when i.field_code = 'course_entry_first_read' then 'course entry reader (D-R2 replacement read)' else 'entry matrix reader (re-read)' end,
                                     'rule', v_gate->>'rule');
  end if;
  v_route := case when jsonb_array_length(v_b) > 0 then 'repair:' || (v_b->0->>'code')
                  when v_aer then 'review:platform_admin' else 'review:curator' end;
  return jsonb_build_object('blockers', v_b, 'route', v_route, 'gate', v_gate);
end $function$;
revoke all on function security.layer4_blockers_v1(uuid, boolean) from public, anon, authenticated;

-- 6 reviewer pace: minutes per item, measured from saved decisions -------------------------------------------------------------------------
create or replace function security.layer4_pace_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
-- Per kind: the median minutes between consecutive decisions of one reviewer, counting only gaps above layer4.pace_min_gap_seconds (closer ones
-- are bulk actions) and up to layer4.pace_gap_minutes (longer gaps are breaks); kinds with fewer than layer4.pace_min_decisions measured decisions use layer4.pace_default_minutes. {kind: {minutes, measured, basis}}.
  with d as (select r.field_code, extract(epoch from x.created_at - lag(x.created_at) over (partition by x.actor_id order by x.created_at)) / 60.0 gap
               from pipeline.layer4_decisions x join pipeline.layer4_review_items r on r.id = x.review_item_id
              where x.created_at > now() - make_interval(days => security.pipeline_num_v1('layer4.pace_window_days', 30)::int) and x.actor_id is not null),
       k as (select d.field_code, count(*) n, percentile_cont(0.5) within group (order by d.gap) p50 from d
              where d.gap > security.pipeline_num_v1('layer4.pace_min_gap_seconds', 20) / 60.0 and d.gap <= security.pipeline_num_v1('layer4.pace_gap_minutes', 15) group by d.field_code)
  select coalesce(jsonb_object_agg(k.field_code, jsonb_build_object(
           'minutes', case when k.n >= security.pipeline_num_v1('layer4.pace_min_decisions', 5) then round(k.p50::numeric, 2) else security.pipeline_num_v1('layer4.pace_default_minutes', 3) end,
           'measured', k.n, 'basis', case when k.n >= security.pipeline_num_v1('layer4.pace_min_decisions', 5) then 'measured' else 'default' end)), '{}'::jsonb)
    from k
$function$;
revoke all on function security.layer4_pace_v1() from public, anon, authenticated;

-- 7 settle (supersede) what the platform can settle: arrival guard and reconciliation ----------------------------------------------------------
create or replace function security.layer4_arrival_guard_trg_v1() returns trigger
language plpgsql security definer set search_path to '' as $function$
-- Trigger layer4_review_items_zz_arrival (BEFORE INSERT; after layer4_review_items_reroute, before ops_guard_layer4). While layer4.arrival_guard_on
-- is 1, a new waiting item of a kind in layer4.platform_kinds that the platform can settle (security.layer4_resolution_for_v1) arrives superseded,
-- with the reason recorded in pipeline.layer4_supersessions. It never approves, rejects or changes any other row. Every generator passes here.
declare v_res jsonb;
begin
  if new.status is distinct from 'pending' or security.pipeline_num_v1('layer4.arrival_guard_on', 0) < 1
     or not (new.field_code = any (security.pipeline_list_v1('layer4.platform_kinds', '[]'::jsonb))) then
    return new;
  end if;
  new.id := coalesce(new.id, gen_random_uuid());
  v_res := security.layer4_resolution_for_v1(new.id, new.entity_type, new.entity_id, new.field_code, new.proposed_value, new.layer2_state, new.evidence_id, coalesce(new.created_at, now()));
  if v_res is null then return new; end if;
  new.status := 'superseded';
  new.decided_at := now();
  new.change_control_ref := coalesce(new.change_control_ref || '; ', '') || 'CF-247 L4 readiness: settled on arrival (' || (v_res->>'reason') || ')';
  insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)
  values (new.id, new.field_code, new.entity_type, new.entity_id, v_res->>'reason', nullif(v_res->>'covered_by_item', '')::uuid, coalesce(v_res->'evidence', '{}'::jsonb), 'arrival');
  return new;
end $function$;
revoke all on function security.layer4_arrival_guard_trg_v1() from public, anon, authenticated;
do $t$ begin
  if not exists (select 1 from pg_trigger where tgname = 'layer4_review_items_zz_arrival' and tgrelid = 'pipeline.layer4_review_items'::regclass) then
    create trigger layer4_review_items_zz_arrival before insert on pipeline.layer4_review_items for each row execute function security.layer4_arrival_guard_trg_v1();
  end if;
end $t$;

create or replace function security.layer4_reconcile_v1(p_kind text, p_limit int) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- While layer4.reconcile_supersede_on is 1: waiting items of p_kind (or of every kind in layer4.platform_kinds when null) that the platform can
-- settle are superseded (status superseded, decided_at, the reason on change_control_ref; pipeline.layer4_supersessions holds the reason, the
-- covering item and the evidence). Never approves or rejects; never touches a lock. Off: counts only. {on, examined, superseded, by_reason}.
declare r record; v_res jsonb; v_on boolean := security.pipeline_num_v1('layer4.reconcile_supersede_on', 0) >= 1; v_n int := 0; v_ex int := 0;
        v_by jsonb := '{}'::jsonb; v_kinds text[] := security.pipeline_list_v1('layer4.platform_kinds', '[]'::jsonb);
begin
  for r in select i.id, i.field_code, i.entity_type, i.entity_id from pipeline.layer4_review_items i
            where i.status = 'pending' and i.field_code = any (v_kinds) and (p_kind is null or i.field_code = p_kind)
            order by i.created_at, i.id limit greatest(coalesce(p_limit, 0), 0) loop
    v_ex := v_ex + 1;
    v_res := security.layer4_resolution_v1(r.id);
    continue when v_res is null;
    v_by := jsonb_set(v_by, array[v_res->>'reason'], to_jsonb(coalesce((v_by->>(v_res->>'reason'))::int, 0) + 1));
    continue when not v_on;
    update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
           change_control_ref = coalesce(change_control_ref || '; ', '') || 'CF-247 L4 readiness: settled by the platform (' || (v_res->>'reason') || ')'
     where id = r.id and status = 'pending';
    continue when not found;
    insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)
    values (r.id, r.field_code, r.entity_type, r.entity_id, v_res->>'reason', nullif(v_res->>'covered_by_item', '')::uuid, coalesce(v_res->'evidence', '{}'::jsonb), 'reconcile');
    update pipeline.layer4_item_readiness set item_status = 'superseded', readiness = 'closed', classified_at = now() where item_id = r.id;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('on', v_on, 'kind', p_kind, 'examined', v_ex, 'resolvable', v_by, 'superseded', v_n);
end $function$;
revoke all on function security.layer4_reconcile_v1(text, int) from public, anon, authenticated;

create or replace function security.layer4_supersession_reverse_v1(p_supersession bigint, p_note text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- The Platform Admin puts an item the platform superseded back to waiting (the supersession row is kept, marked reversed). Not a decision.
declare s pipeline.layer4_supersessions;
begin
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_note, ''))) < 5 then raise exception 'give a reason' using errcode = '22023'; end if;
  select * into s from pipeline.layer4_supersessions where id = p_supersession for update;
  if s.id is null or s.reversed_at is not null then raise exception 'no supersession % to reverse', p_supersession using errcode = 'P0002'; end if;
  update pipeline.layer4_review_items set status = 'pending', decided_at = null where id = s.item_id and status = 'superseded';
  if not found then raise exception 'the item is no longer superseded' using errcode = '22023'; end if;
  update pipeline.layer4_supersessions set reversed_at = now(), reversed_by = auth.uid(), reversed_note = btrim(p_note) where id = s.id;
  update pipeline.layer4_item_readiness set item_status = 'pending', readiness = 'judgement_ready', classified_at = '-infinity' where item_id = s.item_id;
  return jsonb_build_object('item', s.item_id, 'reversed', true);
end $function$;
revoke all on function security.layer4_supersession_reverse_v1(bigint, text) from public, anon, authenticated;

-- 8 post-decision verification ---------------------------------------------------------------------------------------------------------------
create or replace function security.layer4_admission_check_v1(p_decision uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- One approval: is the approved value in the catalogue (admitted) and in the search projection the website reads (published)?
-- {result, reason, admitted, published, lag_seconds, detail}. result: admitted_published, admitted (the kind is not projected),
-- admitted_not_published, not_admitted, superseded_later (a later approval or value replaced it), not_applicable (not an approval, or the
-- course is retired), not_checked (no check for this kind), waiting (too young for the projection: layer4.verify_wait_minutes).
declare d pipeline.layer4_decisions; i pipeline.layer4_review_items; v_key text; v_link record; v_doc record; v_n int; v_m int; v_txt text;
        v_lock boolean; v_life text; v_young boolean;
begin
  select * into d from pipeline.layer4_decisions where id = p_decision;
  select * into i from pipeline.layer4_review_items where id = d.review_item_id;
  if d.id is null or i.id is null or d.action not in ('approve', 'edit_and_approve') then
    return jsonb_build_object('result', 'not_applicable', 'reason', 'not an approval');
  end if;
  v_young := d.created_at > now() - make_interval(mins => security.pipeline_num_v1('layer4.verify_wait_minutes', 90)::int);
  -- a later approval of the same question replaced this one
  if exists (select 1 from pipeline.layer4_decisions x join pipeline.layer4_review_items y on y.id = x.review_item_id
              where y.entity_id = i.entity_id and y.field_code = i.field_code and x.action in ('approve', 'edit_and_approve') and x.created_at > d.created_at
                and security.layer4_scope_key_v1(y.field_code, y.layer2_state, y.proposed_value) = security.layer4_scope_key_v1(i.field_code, i.layer2_state, i.proposed_value)) then
    return jsonb_build_object('result', 'superseded_later', 'reason', 'a later approval of the same question');
  end if;
  if i.entity_type = 'course' then
    select c.lifecycle_status into v_life from catalogue.courses c where c.id = i.entity_id;
    if v_life is distinct from 'active' then return jsonb_build_object('result', 'not_applicable', 'reason', 'course ' || coalesce(v_life, 'missing')); end if;
    select s.official_course_url, s.description, s.has_provider_current_tuition, s.generated_at into v_doc from search.course_documents s where s.course_id = i.entity_id;
  end if;
  if i.field_code = 'official_course_url' then
    v_key := security.layer4_url_key_v1(coalesce(case jsonb_typeof(d.final_value) when 'string' then d.final_value #>> '{}' when 'object' then coalesce(d.final_value->>'url', d.final_value->>'course_url') end,
                                                 case jsonb_typeof(i.proposed_value) when 'string' then i.proposed_value #>> '{}' when 'object' then coalesce(i.proposed_value->>'url', i.proposed_value->>'course_url') end));
    select l.id, l.status, l.is_primary, l.created_at, l.updated_at into v_link from catalogue.course_links l
     where l.course_id = i.entity_id and l.link_type = 'official_course' and security.layer4_url_key_v1(l.url) = v_key order by (l.status = 'active') desc, l.updated_at desc limit 1;
    v_lock := exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.entity_id and l.field in ('official_url', 'course_url'));
    if v_link.id is null or v_link.status <> 'active' then
      return jsonb_build_object('result', 'not_admitted', 'admitted', false,
        'reason', case when v_lock then 'manual_lock_kept' when v_link.id is null then 'link_missing' else 'link_' || v_link.status end,
        'detail', jsonb_build_object('url_key', v_key, 'manual_lock', v_lock, 'link_status', v_link.status, 'shown_url', v_doc.official_course_url));
    end if;
    if v_doc.generated_at is null then
      return jsonb_build_object('result', case when v_young then 'waiting' else 'admitted_not_published' end, 'admitted', true, 'published', false, 'reason', 'no_projection_row',
                                'lag_seconds', round(extract(epoch from v_link.updated_at - d.created_at)));
    end if;
    if security.layer4_url_key_v1(v_doc.official_course_url) is distinct from v_key then
      return jsonb_build_object('result', case when v_young then 'waiting' else 'admitted_not_published' end, 'admitted', true, 'published', false,
        'reason', case when v_lock then 'manual_lock_shown' else 'projection_shows_another_page' end, 'lag_seconds', round(extract(epoch from v_link.updated_at - d.created_at)),
        'detail', jsonb_build_object('shown_url', v_doc.official_course_url, 'primary', v_link.is_primary, 'projection_at', v_doc.generated_at));
    end if;
    return jsonb_build_object('result', 'admitted_published', 'admitted', true, 'published', true, 'lag_seconds', round(extract(epoch from v_link.updated_at - d.created_at)),
                              'detail', jsonb_build_object('primary', v_link.is_primary));
  elsif i.field_code = 'provider_current_tuition_validation' then
    -- security.layer4_tuition_apply_impl names the item in the fee's notes (provider_current_tuition goes through the scalar path: not checked here)
    select count(*) filter (where f.status = 'active'), count(*) into v_n, v_m from catalogue.course_fees f
     where f.course_id = i.entity_id and position(i.id::text in coalesce(f.notes, '')) > 0;
    if v_n = 0 then
      return jsonb_build_object('result', case when v_m > 0 then 'superseded_later' else 'not_admitted' end, 'admitted', false,
                                'reason', case when v_m > 0 then 'fee_replaced' else 'fee_missing' end);
    end if;
    if not coalesce(v_doc.has_provider_current_tuition, false) then
      return jsonb_build_object('result', case when v_young then 'waiting' else 'admitted_not_published' end, 'admitted', true, 'published', false, 'reason', 'projection_has_no_fee');
    end if;
    return jsonb_build_object('result', 'admitted_published', 'admitted', true, 'published', true);
  elsif i.field_code = 'course_entry_first_read' then
    -- rows later replaced (superseded) or withdrawn by a later decision (inactive, not quarantined: E14 withdrew 105 rows on 2 Nov 2026)
    select count(*) filter (where x.status = 'active'),
           count(*) filter (where x.status = 'superseded' or (x.status = 'inactive' and coalesce(x.status_reason, '') not like 'quarantined%' and coalesce(x.status_reason, '') not like 'excluded by the reviewer%'))
      into v_n, v_m from catalogue.course_entry_requirements x
     where x.course_id = i.entity_id and x.provenance->>'review_item_id' = i.id::text;
    return case when v_n > 0 then jsonb_build_object('result', 'admitted', 'admitted', true, 'reason', 'not projected (read by the entry resolver)', 'detail', jsonb_build_object('active_rows', v_n))
                when v_m > 0 then jsonb_build_object('result', 'superseded_later', 'admitted', false, 'reason', 'rows_replaced_or_withdrawn', 'detail', jsonb_build_object('rows', v_m))
                else jsonb_build_object('result', 'not_admitted', 'admitted', false, 'reason', 'no_active_row') end;
  elsif i.field_code in ('entry_matrix_first_run', 'entry_matrix_change') then
    select count(*) filter (where m.status = 'active'),
           count(*) filter (where m.status = 'superseded' or (m.status = 'inactive' and coalesce(m.status_reason, '') not like 'quarantined%' and coalesce(m.status_reason, '') not like 'excluded by the reviewer%'))
      into v_n, v_m from catalogue.provider_entry_matrix m
     where m.provider_id = i.entity_id and m.run_id = nullif(i.proposed_value->>'run_id', '')::uuid;
    return case when v_n > 0 then jsonb_build_object('result', 'admitted', 'admitted', true, 'reason', 'not projected (read by the entry resolver)', 'detail', jsonb_build_object('active_rows', v_n))
                when v_m > 0 then jsonb_build_object('result', 'superseded_later', 'admitted', false, 'reason', 'rows_replaced_or_withdrawn')
                else jsonb_build_object('result', 'not_admitted', 'admitted', false, 'reason', 'no_active_row') end;
  elsif i.field_code = 'course_description_first_read' then
    select nullif(btrim(c.description), '') into v_txt from catalogue.courses c where c.id = i.entity_id;
    if v_txt is distinct from nullif(btrim(i.proposed_value->>'description'), '') then
      return jsonb_build_object('result', 'not_admitted', 'admitted', false, 'reason', case when v_txt is null then 'description_missing' else 'description_differs' end);
    end if;
    if nullif(btrim(v_doc.description), '') is distinct from v_txt then
      return jsonb_build_object('result', case when v_young then 'waiting' else 'admitted_not_published' end, 'admitted', true, 'published', false, 'reason', 'projection_shows_other_text');
    end if;
    return jsonb_build_object('result', 'admitted_published', 'admitted', true, 'published', true);
  elsif i.field_code = 'provider_description' then
    select nullif(btrim(p.description), '') into v_txt from catalogue.providers p where p.id = i.entity_id;
    return case when v_txt is not null and exists (select 1 from pipeline.provider_description_reads r where r.review_item_id = i.id and r.state = 'admitted')
                then jsonb_build_object('result', 'admitted', 'admitted', true, 'reason', 'read by the provider endpoint directly')
                else jsonb_build_object('result', 'not_admitted', 'admitted', false, 'reason', 'description_not_admitted') end;
  elsif i.field_code in ('no_page_first_run', 'conjoint_rule_first_run') then
    return case when exists (select 1 from pipeline.no_page_trust t where t.review_item_id = i.id and t.decided_at is not null)
                then jsonb_build_object('result', 'admitted', 'admitted', true, 'reason', 'provider rule recorded')
                else jsonb_build_object('result', 'not_admitted', 'admitted', false, 'reason', 'rule_not_recorded') end;
  end if;
  return jsonb_build_object('result', 'not_checked', 'reason', 'no admission check for ' || i.field_code);
end $function$;
revoke all on function security.layer4_admission_check_v1(uuid) from public, anon, authenticated;

create or replace function security.layer4_admission_record_v1(p_decision uuid) returns text
language plpgsql security definer set search_path to '' as $function$
-- Runs the check for one decision and keeps its latest result (pipeline.layer4_admission_checks).
declare v jsonb := security.layer4_admission_check_v1(p_decision); d record;
begin
  select x.id, x.created_at, r.id rid, r.field_code, r.entity_type, r.entity_id into d
    from pipeline.layer4_decisions x join pipeline.layer4_review_items r on r.id = x.review_item_id where x.id = p_decision;
  if d.id is null then return null; end if;
  insert into pipeline.layer4_admission_checks as c(decision_id, review_item_id, field_code, entity_type, entity_id, decided_at, result, reason, admitted, published, lag_seconds, detail)
  values (d.id, d.rid, d.field_code, d.entity_type, d.entity_id, d.created_at, v->>'result', v->>'reason', (v->>'admitted')::boolean, (v->>'published')::boolean,
          (v->>'lag_seconds')::numeric, coalesce(v->'detail', '{}'::jsonb))
  on conflict (decision_id) do update set result = excluded.result, reason = excluded.reason, admitted = excluded.admitted, published = excluded.published,
     lag_seconds = coalesce(excluded.lag_seconds, c.lag_seconds), detail = excluded.detail, checked_at = now(), checks = c.checks + 1;
  return v->>'result';
end $function$;
revoke all on function security.layer4_admission_record_v1(uuid) from public, anon, authenticated;

-- 9 the job ----------------------------------------------------------------------------------------------------------------------------------
create or replace function security.layer4_readiness_tick_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 P0 Layer 4 readiness (job layer4-readiness). One run:
--   1 Classify waiting items (layer4.readiness_batch; never classified first, then the oldest): resolvable / technical_blocked / judgement_ready,
--     with blockers, route and the kind's measured reviewer minutes; entry-requirement gates for at most layer4.gate_batch items. Items no
--     longer waiting are closed.
--   2 Settle (supersede) what the platform can settle, only while layer4.reconcile_supersede_on is 1 (security.layer4_reconcile_v1).
--   3 Check approvals (layer4.verify_batch): new decisions first, then those not yet passed after layer4.verify_recheck_hours.
--   4 One integration issue per kind and reason of approvals that did not reach the catalogue or the projection (l4_not_admitted:<kind>:<reason>,
--     l4_not_published:<kind>:<reason>); an issue no longer seen is marked condition-cleared (the controller closes it after verification).
declare v_t0 timestamptz := clock_timestamp(); r record; v_res jsonb; v_blk jsonb; v_pace jsonb := security.layer4_pace_v1(); v_kinds text[] := security.pipeline_list_v1('layer4.platform_kinds', '[]'::jsonb);
        v_gates int := security.pipeline_num_v1('layer4.gate_batch', 20)::int; v_g int := 0; v_cls int := 0; v_closed int := 0; v_chk int := 0; v_iss int := 0;
        v_rec jsonb; v_gate jsonb; v_gate_at timestamptz; v_ready text; v_reasons text[]; v_route text; v_seen text[] := '{}'; v_fp text; v_out jsonb; v_use_gate boolean;
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247:layer4-readiness')) then return jsonb_build_object('busy', true); end if;  -- fixed: one run at a time
  if security.pipeline_num_v1('layer4.readiness_on', 1) >= 1 then
    -- items that stopped waiting
    update pipeline.layer4_item_readiness x set readiness = 'closed', item_status = i.status, classified_at = now()
      from pipeline.layer4_review_items i where i.id = x.item_id and x.readiness <> 'closed' and i.status <> 'pending';
    get diagnostics v_closed = row_count;
    for r in select i.id, i.entity_type, i.entity_id, i.field_code, i.created_at, x.gate, x.gate_checked_at
               from pipeline.layer4_review_items i left join pipeline.layer4_item_readiness x on x.item_id = i.id
              where i.status = 'pending'
                and (x.item_id is null or x.classified_at < now() - make_interval(mins => security.pipeline_num_v1('layer4.readiness_recheck_minutes', 120)::int))
              order by x.classified_at nulls first, i.created_at
              limit security.pipeline_num_v1('layer4.readiness_batch', 1000)::int loop
      v_res := security.layer4_resolution_v1(r.id);
      v_use_gate := r.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change') and v_g < v_gates
                    and (r.gate_checked_at is null or r.gate_checked_at < now() - make_interval(mins => security.pipeline_num_v1('layer4.readiness_recheck_minutes', 120)::int));
      v_blk := security.layer4_blockers_v1(r.id, v_use_gate);
      if v_use_gate then v_g := v_g + 1; v_gate := v_blk->'gate'; v_gate_at := now();
      else
        v_gate := r.gate; v_gate_at := r.gate_checked_at;
        -- an earlier gate result that held the read still holds it until it is evaluated again
        if v_gate is not null and not coalesce((v_gate->>'complete')::boolean, true) then
          v_blk := jsonb_set(v_blk, '{blockers}', (v_blk->'blockers') || jsonb_build_object('code', 'completeness_gate', 'why', coalesce(v_gate->'reasons'->>0, 'the completeness gate holds this read'),
                             'repair', 'the reader of this kind (D-R2 replacement read)', 'rule', v_gate->>'rule', 'as_at', r.gate_checked_at));
          v_blk := jsonb_set(v_blk, '{route}', to_jsonb('repair:' || (v_blk->'blockers'->0->>'code')));
        end if;
      end if;
      if v_res is not null and r.field_code = any (v_kinds) then
        v_ready := 'resolvable'; v_reasons := array[v_res->>'reason']; v_route := 'platform:' || (v_res->>'reason');
      elsif jsonb_array_length(v_blk->'blockers') > 0 then
        v_ready := 'technical_blocked'; v_reasons := (select array_agg(distinct b->>'code') from jsonb_array_elements(v_blk->'blockers') b); v_route := v_blk->>'route';
      else
        v_ready := 'judgement_ready'; v_reasons := '{}'; v_route := v_blk->>'route';
      end if;
      insert into pipeline.layer4_item_readiness as x(item_id, entity_type, entity_id, field_code, item_created_at, item_status, readiness, reasons, route, resolution, blockers,
                                                      est_minutes, gate, gate_checked_at, classified_at)
      values (r.id, r.entity_type, r.entity_id, r.field_code, r.created_at, 'pending', v_ready, v_reasons, v_route, v_res, v_blk->'blockers',
              coalesce((v_pace->r.field_code->>'minutes')::numeric, security.pipeline_num_v1('layer4.pace_default_minutes', 3)), v_gate, v_gate_at, now())
      on conflict (item_id) do update set item_status = 'pending', readiness = excluded.readiness, reasons = excluded.reasons, route = excluded.route,
         resolution = excluded.resolution, blockers = excluded.blockers, est_minutes = excluded.est_minutes, gate = excluded.gate, gate_checked_at = excluded.gate_checked_at,
         classified_at = now();
      v_cls := v_cls + 1;
    end loop;
  end if;
  v_rec := security.layer4_reconcile_v1(null, case when security.pipeline_num_v1('layer4.reconcile_supersede_on', 0) >= 1
                                                   then security.pipeline_num_v1('layer4.reconcile_batch', 200)::int else 0 end);
  if security.pipeline_num_v1('layer4.verify_on', 1) >= 1 then
    for r in select x.id from pipeline.layer4_decisions x
               left join pipeline.layer4_admission_checks c on c.decision_id = x.id
              where x.action in ('approve', 'edit_and_approve')
                and x.created_at > now() - make_interval(days => security.pipeline_num_v1('layer4.verify_lookback_days', 30)::int)
                and (c.decision_id is null
                     or (c.result in ('not_admitted', 'admitted_not_published', 'waiting')
                         and c.checked_at < now() - make_interval(hours => security.pipeline_num_v1('layer4.verify_recheck_hours', 6)::int))
                     or (c.result = 'waiting' and c.checked_at < now() - make_interval(mins => security.pipeline_num_v1('layer4.verify_wait_minutes', 90)::int)))
              order by (c.decision_id is null) desc, x.created_at desc
              limit security.pipeline_num_v1('layer4.verify_batch', 300)::int loop
      perform security.layer4_admission_record_v1(r.id);
      v_chk := v_chk + 1;
    end loop;
    -- one issue per kind and reason (the latest result of approvals in the window)
    for r in select c.field_code, c.result, coalesce(c.reason, 'unknown') reason, count(*) n, array_agg(c.entity_id order by c.decided_at desc) ents,
                    array_agg(c.decision_id order by c.decided_at desc) decs, min(c.decided_at) first_at, max(c.decided_at) last_at
               from pipeline.layer4_admission_checks c
              where c.result in ('not_admitted', 'admitted_not_published')
                and c.decided_at > now() - make_interval(days => security.pipeline_num_v1('layer4.verify_lookback_days', 30)::int)
              group by 1, 2, 3 loop
      v_fp := case when r.result = 'not_admitted' then 'l4_not_admitted:' else 'l4_not_published:' end || r.field_code || ':' || r.reason;
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', v_fp,
        'title', case when r.result = 'not_admitted' then 'Layer 4 approvals that did not reach the catalogue (' else 'Layer 4 approvals in the catalogue but not on the website projection (' end
                 || r.field_code || ', ' || r.reason || ')',
        'layer', 'Layer 4', 'subsystem', 'pipeline.layer4_admission_checks',
        'failure', r.n || ' approval(s) saved ' || to_char(r.first_at at time zone 'Australia/Melbourne', 'DD Mon') || ' to ' || to_char(r.last_at at time zone 'Australia/Melbourne', 'DD Mon')
                   || ' are ' || replace(r.result, '_', ' ') || ' (' || r.reason || ')',
        'expected', 'An approved value is in the catalogue and in the search projection the website reads (mandate 15:37 §10, §12)',
        'source', 'layer4-readiness', 'validation_layer', 'V4',
        'course_ids', case when r.field_code not in ('entry_matrix_first_run', 'entry_matrix_change', 'no_page_first_run', 'conjoint_rule_first_run', 'provider_description') then to_jsonb(r.ents[1:500]) else '[]'::jsonb end,
        'provider_ids', case when r.field_code in ('entry_matrix_first_run', 'entry_matrix_change', 'no_page_first_run', 'conjoint_rule_first_run', 'provider_description') then to_jsonb(r.ents[1:500]) else '[]'::jsonb end,
        'evidence', jsonb_build_object('approvals', r.n, 'decisions', to_jsonb(r.decs[1:20]), 'first_decided', r.first_at, 'last_decided', r.last_at, 'result', r.result, 'reason', r.reason),
        'severity', case when r.reason = 'manual_lock_kept' then 'P2' else 'P1' end,
        'root_cause_class', case when r.reason = 'manual_lock_kept' then 'human_decision' else 'code_defect' end, 'workstream', 'A4'), 'layer4-readiness');
      v_seen := v_seen || v_fp; v_iss := v_iss + 1;
    end loop;
    for r in select x.id, x.status from pipeline.integration_issues x
              where (x.fingerprint like 'l4\_not\_admitted:%' or x.fingerprint like 'l4\_not\_published:%') and x.status <> 'closed' and x.condition_cleared_at is null
                and not (x.fingerprint = any (v_seen)) loop
      update pipeline.integration_issues set condition_cleared_at = now() where id = r.id;
      insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note)
      values (r.id, 'not_observed', r.status, r.status, 'layer4-readiness', 'condition no longer observed; closes after verification');
    end loop;
  end if;
  v_out := jsonb_build_object('classified', v_cls, 'gates', v_g, 'closed', v_closed, 'reconcile', v_rec, 'approvals_checked', v_chk, 'issues', v_iss,
                              'switches', jsonb_build_object('readiness_on', security.pipeline_num_v1('layer4.readiness_on', 1), 'verify_on', security.pipeline_num_v1('layer4.verify_on', 1),
                                                             'arrival_guard_on', security.pipeline_num_v1('layer4.arrival_guard_on', 0), 'reconcile_supersede_on', security.pipeline_num_v1('layer4.reconcile_supersede_on', 0)),
                              'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  insert into pipeline.layer4_readiness_runs(ms, result) values ((v_out->>'ms')::int, v_out);
  return v_out;
end $function$;
revoke all on function security.layer4_readiness_tick_v1() from public, anon, authenticated;

-- 10 the reviewer-throughput view ------------------------------------------------------------------------------------------------------------
create or replace function security.layer4_throughput_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
-- Mandate 15:52 §17 (Layer 4 scorecard) and the 18:14 priority: what a reviewer can decide now, how long it takes, what the platform settles
-- without a person, and whether approvals reached the catalogue and the website.
  with w as (select x.* from pipeline.layer4_item_readiness x join pipeline.layer4_review_items i on i.id = x.item_id where x.readiness <> 'closed' and i.status = 'pending'),
       pace as (select security.layer4_pace_v1() p)
  select jsonb_build_object(
    'at', now(),
    'pending', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending'),
    'classified', (select count(*) from w),
    'judgement_ready', (select coalesce(jsonb_object_agg(k.field_code, jsonb_build_object('items', k.n, 'minutes_per_item', k.m, 'reviewer_minutes', round(k.n * coalesce(k.m, 0), 1),
                                                                                         'oldest', k.oldest, 'route', k.route)), '{}'::jsonb)
                          from (select w.field_code, count(*) n, max(w.est_minutes) m, min(w.item_created_at) oldest, min(w.route) route from w where w.readiness = 'judgement_ready' group by 1) k),
    'judgement_ready_reviewer_hours', (select round(coalesce(sum(coalesce(w.est_minutes, 0)), 0) / 60.0, 1) from w where w.readiness = 'judgement_ready'),
    'technical_blocked', (select coalesce(jsonb_object_agg(k.field_code, k.b), '{}'::jsonb) from (
                            select z.field_code, jsonb_object_agg(z.code, z.n) b from (
                              select w.field_code, r.code, count(*) n from w cross join lateral unnest(w.reasons) r(code) where w.readiness = 'technical_blocked' group by 1, 2) z group by 1) k),
    'resolvable_by_platform', (select coalesce(jsonb_object_agg(k.field_code, k.b), '{}'::jsonb) from (
                                 select z.field_code, jsonb_object_agg(z.code, z.n) b from (
                                   select w.field_code, w.reasons[1] code, count(*) n from w where w.readiness = 'resolvable' group by 1, 2) z group by 1) k),
    'resolved_by_platform', jsonb_build_object(
       'last_24h', (select coalesce(jsonb_object_agg(z.k, z.n), '{}'::jsonb) from (select s.field_code || ':' || s.reason || ':' || s.mode k, count(*) n from pipeline.layer4_supersessions s
                                                                                   where s.at > now() - interval '24 hours' and s.reversed_at is null group by 1) z),  -- fixed: the report's day
       'last_7d', (select coalesce(jsonb_object_agg(z.k, z.n), '{}'::jsonb) from (select s.field_code || ':' || s.reason k, count(*) n from pipeline.layer4_supersessions s
                                                                                  where s.at > now() - interval '7 days' and s.reversed_at is null group by 1) z),  -- fixed: the report's week
       'reversed', (select count(*) from pipeline.layer4_supersessions s where s.reversed_at is not null)),
    'admission', (select coalesce(jsonb_object_agg(z.field_code, z.r), '{}'::jsonb) from (
                    select y.field_code, jsonb_object_agg(y.k, y.n) r from (
                      select c.field_code, c.result || coalesce(':' || c.reason, '') k, count(*) n from pipeline.layer4_admission_checks c group by 1, 2) y group by 1) z),
    'admission_lag_seconds_p50', (select percentile_cont(0.5) within group (order by c.lag_seconds) from pipeline.layer4_admission_checks c where c.lag_seconds is not null),
    'pace', (select p from pace),
    'decisions_per_day', (select coalesce(jsonb_object_agg(z.d, z.n), '{}'::jsonb) from (
                            select to_char(x.created_at at time zone 'Australia/Melbourne', 'YYYY-MM-DD') d, count(*) n from pipeline.layer4_decisions x
                             where x.created_at > now() - make_interval(days => security.pipeline_num_v1('layer4.pace_window_days', 30)::int) group by 1) z),
    'switches', jsonb_build_object('readiness_on', security.pipeline_num_v1('layer4.readiness_on', 1), 'verify_on', security.pipeline_num_v1('layer4.verify_on', 1),
                                   'arrival_guard_on', security.pipeline_num_v1('layer4.arrival_guard_on', 0), 'reconcile_supersede_on', security.pipeline_num_v1('layer4.reconcile_supersede_on', 0),
                                   'platform_kinds', to_jsonb(security.pipeline_list_v1('layer4.platform_kinds', '[]'::jsonb))),
    'last_run', (select to_jsonb(r) from pipeline.layer4_readiness_runs r order by r.id desc limit 1))
$function$;
revoke all on function security.layer4_throughput_v1() from public, anon, authenticated;

create or replace function security.layer4_review_order_v1(p_kind text, p_limit int) returns table(item_id uuid, field_code text, entity_id uuid, readiness text, route text,
                                                                                                    reasons text[], est_minutes numeric, item_created_at timestamptz)
language sql stable security definer set search_path to '' as $function$
-- The order a reviewer works in: judgement-ready items first (oldest first), then technically blocked ones with their repair route; items the
-- platform can settle are not offered. For the Layer 4 screen (interface for the UI owner; nothing on the screen changes in this release).
  select x.item_id, x.field_code, x.entity_id, x.readiness, x.route, x.reasons, x.est_minutes, x.item_created_at
    from pipeline.layer4_item_readiness x join pipeline.layer4_review_items i on i.id = x.item_id and i.status = 'pending'
   where x.readiness in ('judgement_ready', 'technical_blocked') and (p_kind is null or x.field_code = p_kind)
   order by (x.readiness = 'judgement_ready') desc, x.item_created_at, x.item_id
   limit greatest(coalesce(p_limit, 0), 0)
$function$;
revoke all on function security.layer4_review_order_v1(text, int) from public, anon, authenticated;

-- 11 remedies for the operations controller ((p_issue bigint) returns jsonb; they supersede, re-verify or record, never decide) ------------
create or replace function security.layer4_issue_kind_v1(p_issue bigint) returns text
language sql stable security definer set search_path to '' as $function$
  select split_part(i.fingerprint, ':', 2) from pipeline.integration_issues i where i.id = p_issue
$function$;
revoke all on function security.layer4_issue_kind_v1(bigint) from public, anon, authenticated;

create or replace function security.layer4_remedy_settle_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Action of remedy layer4_supersede_resolvable: settles the issue's kind (security.layer4_reconcile_v1). With the switch off it refuses and says so.
declare v_kind text := security.layer4_issue_kind_v1(p_issue); v jsonb;
begin
  if security.pipeline_num_v1('layer4.reconcile_supersede_on', 0) < 1 then
    return jsonb_build_object('ok', false, 'changed', false, 'evidence', jsonb_build_object('reason', 'layer4.reconcile_supersede_on is 0: the Platform Admin decides', 'kind', v_kind));
  end if;
  if not (v_kind = any (security.pipeline_list_v1('layer4.platform_kinds', '[]'::jsonb))) then
    return jsonb_build_object('ok', false, 'changed', false, 'evidence', jsonb_build_object('reason', v_kind || ' is not a kind the platform may settle (layer4.platform_kinds)'));
  end if;
  v := security.layer4_reconcile_v1(v_kind, security.pipeline_num_v1('layer4.reconcile_batch', 200)::int);
  return jsonb_build_object('ok', true, 'changed', (v->>'superseded')::int > 0, 'evidence', v);
end $function$;
revoke all on function security.layer4_remedy_settle_v1(bigint) from public, anon, authenticated;

create or replace function security.layer4_remedy_settle_verify_v1(p_issue bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- Verification of layer4_supersede_resolvable (a later controller run): passed when no waiting item of the kind is still one the platform can
-- settle, and the issue's own check has not seen it since.
declare v_kind text := security.layer4_issue_kind_v1(p_issue); v_left int; i pipeline.integration_issues;
begin
  select * into i from pipeline.integration_issues where id = p_issue;
  select count(*) into v_left from pipeline.layer4_review_items x
   where x.status = 'pending' and x.field_code = v_kind and security.layer4_resolution_v1(x.id) is not null;
  return jsonb_build_object('passed', v_left = 0,
    'measure', jsonb_build_object('condition_cleared', v_left = 0 and (i.condition_cleared_at is not null and i.last_observed_at <= i.condition_cleared_at),
                                  'waiting', v_left = 0 and not (i.condition_cleared_at is not null and i.last_observed_at <= i.condition_cleared_at),
                                  'resolvable_left', v_left, 'kind', v_kind),
    'evidence', format('%s waiting %s item(s) the platform can still settle; issue check last saw it %s', v_left, v_kind, i.last_observed_at));
end $function$;
revoke all on function security.layer4_remedy_settle_verify_v1(bigint) from public, anon, authenticated;

create or replace function security.layer4_remedy_recheck_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Action of remedy layer4_admission_recheck: checks again every approval of the issue's kind that has not passed (a projection that had not yet
-- refreshed passes now). Records only.
declare v_kind text := security.layer4_issue_kind_v1(p_issue); r record; v_n int := 0; v_by jsonb := '{}'::jsonb; v_res text;
begin
  for r in select c.decision_id from pipeline.layer4_admission_checks c where c.field_code = v_kind and c.result in ('not_admitted', 'admitted_not_published', 'waiting') loop
    v_res := security.layer4_admission_record_v1(r.decision_id);
    v_by := jsonb_set(v_by, array[v_res], to_jsonb(coalesce((v_by->>v_res)::int, 0) + 1));
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'changed', false, 'evidence', jsonb_build_object('kind', v_kind, 'rechecked', v_n, 'results', v_by));
end $function$;
revoke all on function security.layer4_remedy_recheck_v1(bigint) from public, anon, authenticated;

create or replace function security.layer4_remedy_recheck_verify_v1(p_issue bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- Verification of layer4_admission_recheck: passed when no approval behind the issue (its kind and reason) still fails its check.
declare i pipeline.integration_issues; v_kind text; v_reason text; v_res text; v_left int;
begin
  select * into i from pipeline.integration_issues where id = p_issue;
  v_kind := split_part(i.fingerprint, ':', 2); v_reason := split_part(i.fingerprint, ':', 3);
  v_res := case when i.fingerprint like 'l4\_not\_admitted:%' then 'not_admitted' else 'admitted_not_published' end;
  select count(*) into v_left from pipeline.layer4_admission_checks c where c.field_code = v_kind and c.result = v_res and coalesce(c.reason, 'unknown') = v_reason;
  return jsonb_build_object('passed', v_left = 0, 'measure', jsonb_build_object('condition_cleared', v_left = 0, 'failing_left', v_left, 'kind', v_kind, 'reason', v_reason),
                            'evidence', format('%s approval(s) of %s still %s (%s)', v_left, v_kind, v_res, v_reason));
end $function$;
revoke all on function security.layer4_remedy_recheck_verify_v1(bigint) from public, anon, authenticated;

-- root causes (priorities before workstream A's generic layer4_generator_defect 55 and lifecycle_leak 56, so the specific cause wins)
select security.ops_root_cause_register_v1(x.code, x.spec) from (values
 ('layer4_approval_lock_conflict', jsonb_build_object('class', 'policy', 'title', 'An approval did not take effect because the value was set by hand',
   'description', 'Layer 4 approved a value for a record whose value is locked by hand (pipeline.manual_locks); before E15 (1 Nov 2026) the apply skipped the row silently and the decision was recorded as approved. Live 3 Nov 2026: 19 official-link approvals of 17-30 Oct never reached the catalogue; the hand-set page is what the website shows. A person keeps the hand-set value (and the approval is recorded as not taking effect) or changes it on the course record; the platform never touches the lock.',
   'detect', jsonb_build_object('priority', 48, 'confidence', 0.9, 'any', jsonb_build_array(jsonb_build_object('fingerprint_like', jsonb_build_array('l4\_not\_admitted:%:manual\_lock\_kept'))),
                                'route', 'needs_decision', 'recommend', 'Keep the page set by hand (record the approval as not taking effect) or change the page on the course record; never remove the lock automatically.'))),
 ('layer4_approval_not_admitted', jsonb_build_object('class', 'rule', 'title', 'An approval did not reach the catalogue',
   'description', 'A Layer 4 approval was saved but its value is not in the catalogue (security.layer4_admission_check_v1). The apply path of that kind lost or skipped it.',
   'detect', jsonb_build_object('priority', 49, 'confidence', 0.8, 'any', jsonb_build_array(jsonb_build_object('fingerprint_like', jsonb_build_array('l4\_not\_admitted:%')))))),
 ('layer4_approval_not_published', jsonb_build_object('class', 'dependency', 'title', 'An approval is in the catalogue but not on the website projection',
   'description', 'The approved value is in the catalogue but the search projection the website reads shows another value or none. Usually the projection has not refreshed yet (rechecked); if it stays, the projection rule needs a release.',
   'detect', jsonb_build_object('priority', 50, 'confidence', 0.7, 'any', jsonb_build_array(jsonb_build_object('fingerprint_like', jsonb_build_array('l4\_not\_published:%')))))),
 ('layer4_duplicate_distinct_sources', jsonb_build_object('class', 'rule', 'title', 'Layer 4 duplicate check counts different sources of one provider as duplicates',
   'description', 'The integration check l4_duplicate keys on entity and field only. Entry-matrix items are one per source of a provider (ANU 22 qualification sources, Melbourne 2), so they are different questions, not duplicates (live 3 Nov 2026: IQ-00038, 24 items in 2 groups, 0 true duplicates by security.layer4_scope_key_v1 and layer4_value_key_v1).',
   'detect', jsonb_build_object('priority', 51, 'confidence', 0.9, 'any', jsonb_build_array(jsonb_build_object('fingerprint_like', jsonb_build_array('l4\_duplicate:entry\_matrix%'))),
                                'route', 'needs_release', 'recommend', 'Key the l4_duplicate check on security.layer4_scope_key_v1 and layer4_value_key_v1 (interface request to workstream A).'))),
 ('layer4_regenerated_after_decision', jsonb_build_object('class', 'rule', 'title', 'A Layer 4 question is raised again after it was decided',
   'description', 'Generators compare raw values (or nothing) before raising an item, so a proposal already approved or rejected comes back with no new evidence (Decision 263). Live 3 Nov 2026: 51 tuition checks re-propose the exact fee rejected on 27 Oct (IQ-00040), 1 official link re-proposes a page approved on 18 Oct and 2 pages returned on 12 Oct (IQ-00039). The arrival guard (trigger layer4_review_items_zz_arrival) prevents it at every generator; the reconciler settles the ones waiting.',
   'detect', jsonb_build_object('priority', 52, 'confidence', 0.85, 'any', jsonb_build_array(jsonb_build_object('fingerprint_like', jsonb_build_array('l4\_regenerated:%')))))),
 ('layer4_orphan_pending', jsonb_build_object('class', 'data', 'title', 'Layer 4 items wait on a retired course or provider',
   'description', 'Items stay waiting after their course or provider left active (IQ-00061: 28 official-link items, 3 Nov 2026). The platform settles them as entity_retired (superseded with the evidence), never by a decision.',
   'detect', jsonb_build_object('priority', 53, 'confidence', 0.85, 'any', jsonb_build_array(jsonb_build_object('fingerprint_like', jsonb_build_array('l4\_orphan:%')))))),
 ('layer4_duplicate_pending', jsonb_build_object('class', 'rule', 'title', 'The same Layer 4 question waits twice',
   'description', 'Two waiting items ask the same question (same entity, kind, source and proposal). The arrival guard prevents it; the reconciler supersedes the later one.',
   'detect', jsonb_build_object('priority', 54, 'confidence', 0.8, 'any', jsonb_build_array(jsonb_build_object('fingerprint_like', jsonb_build_array('l4\_duplicate:%'))))))
) x(code, spec);

select security.ops_remedy_register_v1(x.code, x.spec) from (values
 ('layer4_admission_recheck', jsonb_build_object('title', 'Check the approvals again (the projection may have refreshed), then verify none still fails',
   'treats', jsonb_build_array('layer4_approval_not_admitted', 'layer4_approval_not_published'), 'authority', 'auto',
   'action_fn', 'security.layer4_remedy_recheck_v1(bigint)', 'verify_fn', 'security.layer4_remedy_recheck_verify_v1(bigint)',
   'max_attempts_key', 'layer4.remedy_max_attempts', 'cooldown_key', 'layer4.remedy_cooldown_minutes',
   'notes', 'Records only (pipeline.layer4_admission_checks). After its attempts the issue needs a release in the kind''s apply path or the projection.')),
 ('layer4_admission_fix_release', jsonb_build_object('title', 'Fix the apply path or projection of the kind through a release',
   'treats', jsonb_build_array('layer4_approval_not_admitted', 'layer4_approval_not_published'), 'authority', 'release')),
 ('layer4_lock_conflict_decision', jsonb_build_object('title', 'A person keeps the value set by hand or changes it on the record',
   'treats', jsonb_build_array('layer4_approval_lock_conflict'), 'authority', 'admin',
   'notes', 'Manual locks are removed or changed only by a person (mandate 15:37 §15).')),
 ('layer4_duplicate_key_release', jsonb_build_object('title', 'Key the integration duplicate check on the item identity (workstream A)',
   'treats', jsonb_build_array('layer4_duplicate_distinct_sources'), 'authority', 'release')),
 ('layer4_supersede_resolvable', jsonb_build_object('title', 'Supersede the waiting items the platform can settle (repeat, already decided, already active, retired entity)',
   'treats', jsonb_build_array('layer4_regenerated_after_decision', 'layer4_orphan_pending', 'layer4_duplicate_pending'), 'authority', 'auto',
   'action_fn', 'security.layer4_remedy_settle_v1(bigint)', 'verify_fn', 'security.layer4_remedy_settle_verify_v1(bigint)',
   'max_attempts_key', 'layer4.remedy_max_attempts', 'cooldown_key', 'layer4.remedy_cooldown_minutes', 'active', false,
   'notes', 'Supersede only, with the reason and the covering item (pipeline.layer4_supersessions); never approves or rejects. Registered inactive: activated by release together with layer4.reconcile_supersede_on and layer4.arrival_guard_on, once the Platform Admin turns them on.')),
 ('layer4_settle_switch_decision', jsonb_build_object('title', 'Platform Admin: let the platform settle repeated, already-decided and retired-entity items',
   'treats', jsonb_build_array('layer4_regenerated_after_decision', 'layer4_orphan_pending', 'layer4_duplicate_pending'), 'authority', 'admin',
   'notes', 'Turn on layer4.arrival_guard_on and layer4.reconcile_supersede_on (Settings > Pipeline settings > Layer 4 readiness); the remedy layer4_supersede_resolvable is then activated by release.'))
) x(code, spec);

-- 12 the job (G1: catalogued first; ships ON: it classifies, verifies and records; settling stays off behind its switch) ------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('layer4-readiness', 'Platform upkeep', 18, 'Layer 4 readiness and admission checks',
  'At :22 and :52 (before the operations controller at :24 and :54; clear of :x3, :x5, :x9, :35-:42 and :47-:48): classifies every waiting Layer 4 item as ready for judgement, technically blocked (manual lock, invalid link, missing or stale evidence, value moved, completeness gate, nothing to admit; with the repair route) or settled by the platform (a repeat, already decided with no new evidence, already the active value, retired course or provider); checks every approval reached the catalogue and the website projection and opens one integration issue per kind and reason that did not; supersedes the items the platform can settle only while layer4.reconcile_supersede_on is on (off). Never approves or rejects; never touches a lock. Settings layer4.*.',
  6, false, null)
on conflict (jobname) do nothing;
do $c$ begin
  if not exists (select 1 from cron.job where jobname = 'layer4-readiness') then
    perform cron.schedule('layer4-readiness', '22,52 * * * *', $j$select security.layer4_readiness_tick_v1()$j$);
  end if;
end $c$;

-- 13 component register (Integration Controller 3 Nov 2026: the first deploy refused kind 'trigger' by component_register_kind_check; the trigger is registered through its function) -----------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.layer4_item_readiness', 'Layer 4', 'CF-247 P0 L4: readiness of every Layer 4 item (judgement-ready, technically blocked, resolvable)', 'active', '{}', '20261104120000'),
 ('table', 'pipeline.layer4_supersessions', 'Layer 4', 'CF-247 P0 L4: items the platform superseded instead of asking a person, with reason and cover', 'active', '{}', '20261104120000'),
 ('table', 'pipeline.layer4_admission_checks', 'Layer 4', 'CF-247 P0 L4: post-decision check that each approval reached the catalogue and the projection', 'active', '{}', '20261104120000'),
 ('table', 'pipeline.layer4_readiness_runs', 'Layer 4', 'CF-247 P0 L4: runs of job layer4-readiness', 'active', '{}', '20261104120000'),
 ('job', 'layer4-readiness', 'Layer 4', 'CF-247 P0 L4: classify, verify admissions, settle (switch)', 'active', '{}', '20261104120000'),
 ('function', 'security.layer4_arrival_guard_trg_v1', 'Layer 4', 'CF-247 P0 L4: generator guard on every Layer 4 insert, trigger layer4_review_items_zz_arrival (switch, off)', 'active', '{}', '20261104120000'),
 ('function', 'security.layer4_readiness_tick_v1', 'Layer 4', 'CF-247 P0 L4: job layer4-readiness', 'active', '{}', '20261104120000'),
 ('function', 'security.layer4_resolution_for_v1', 'Layer 4', 'CF-247 P0 L4: can the platform settle an item without a person', 'active', '{}', '20261104120000'),
 ('function', 'security.layer4_blockers_v1', 'Layer 4', 'CF-247 P0 L4: technical blockers of an item', 'active', '{}', '20261104120000'),
 ('function', 'security.layer4_admission_check_v1', 'Layer 4', 'CF-247 P0 L4: did an approval reach the catalogue and the projection', 'active', '{}', '20261104120000'),
 ('function', 'security.layer4_reconcile_v1', 'Layer 4', 'CF-247 P0 L4: supersede what the platform can settle (switch, off)', 'active', '{}', '20261104120000'),
 ('function', 'security.layer4_throughput_v1', 'Layer 4', 'CF-247 P0 L4: the reviewer-throughput view', 'active', '{}', '20261104120000'),
 ('function', 'security.layer4_review_order_v1', 'Layer 4', 'CF-247 P0 L4: judgement-ready first order for the Layer 4 screen', 'active', '{}', '20261104120000')
on conflict do nothing;
