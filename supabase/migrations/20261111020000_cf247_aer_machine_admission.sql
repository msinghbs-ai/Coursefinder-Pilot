-- CF-247 F-AER.04 machine admission of complete, source-proved first course entry reads (rule aer-machine-v1).
-- Authority: Platform Admin decision 10 Nov 2026 ~23:45 AEDT, AER recovery pack decision 1: "Build, shadow 24 hours, then enable conditionally", with the controls:
--   E13 and D-R3 checks, source identity, completeness, provenance and an exact supporting quote for every admitted requirement; a 24-hour shadow run against
--   historical human-reviewed records and current pending records; independent validation before activation; a daily cap, a random 5% Layer 4 audit and immediate
--   suspension on critical defects; ambiguous, conflicting, incomplete or unsupported evidence to Layer 4; full audit history and rollback.
-- Evidence for the rule (production, read only, 10 Nov 2026 23:2x AEDT): 498 human AER course-read decisions to date (31 Oct - 1 Nov), 497 approve, 1 edit_and_approve, 0 reject;
--   no AER decision since 1 Nov 19:47; 708 AER items pending (659 course reads, 49 matrix runs); 266 course reads are gate-complete (E13 + D-R3).
-- Guards: G1 (one job, catalogued first), G2 (every operational value is a setting; constants are technical and marked -- fixed:), G3 (no consumer API object is changed;
--   publication follows the existing search refresh signal exactly as a person's approval), "a passing qualification never switches anything on by itself": the mode
--   setting ships at 1 (shadow: records what it would do, changes nothing); mode 2 (admit) is refused by the code unless security.aer_machine_validate_v1() has recorded a
--   passing validation after at least aer.machine_shadow_min_hours of shadow; moving to 2 is a separate, deliberate Settings change with a reason.
-- Scope: course_entry_first_read only. Entry matrix runs (entry_matrix_first_run) stay with a person.
-- What:
--   1. Settings (Entry requirements section): aer.machine_mode 1, aer.machine_daily_max 300, aer.machine_audit_pct 5, aer.machine_min_confidence 0.8,
--      aer.machine_min_quote_chars 8, aer.machine_shadow_min_hours 24, batch.aer_machine 60, aer.machine_suspended 0.
--   2. pipeline.aer_machine_admissions (ledger: one row per item per outcome; shadow rows refreshed in place) and pipeline.aer_machine_validations.
--   3. security.aer_machine_check_v1(item) (stable): every check, in order; the first failure names the rule, the reason and the next action.
--   4. security.aer_machine_admit_v1(item, via): shadow -> ledger only; admit -> re-checks under the row lock, admits through the SAME apply function a person's approval uses
--      (security.course_entry_review_apply_v1: E13 re-run inside, active rows superseded, proposed rows activated, reading settled), settles the item, writes the decision under the
--      system automation account with layer2_state.actor_kind = machine, the A1 lineage event, the search refresh signal and the ledger row, then reads the rows back.
--   5. security.aer_machine_run_v1() (job aer-machine-admission): suspension check, then up to batch.aer_machine items (time box), within the daily cap.
--   6. Suspension: a person's reject / request_more_evidence / return on a random audit sample that the rule would have admitted, or a withdrawal, sets aer.machine_suspended = 1
--      (admission stops; shadow continues) and records an admin_control_events row. Only a person sets it back to 0.
--   7. security.aer_machine_withdraw_v1(item, reason, actor) and public.admin_aer_machine_withdraw_v1(item, reason) (Platform Admin): rows back to proposed, the item back to
--      pending for a person, decision and ledger kept.
--   8. security.aer_machine_history_v1() (read only): the row-level rules over the 498 historical human decisions (agreement measure for validation).
--   9. security.aer_machine_validate_v1() and security.aer_machine_report_v1().
-- Replaces: nothing (a separate machine route; the human Layer 4 route, its functions and triggers are unchanged)
-- Retires: nothing.
-- Reversal: aer.machine_mode = 0 (nothing runs); withdraw admitted items with public.admin_aer_machine_withdraw_v1.

do $g$
declare r record;
begin
  for r in select * from (values ('security.course_entry_gate_v1(uuid,uuid[])'), ('security.course_entry_review_apply_v1(uuid,text,jsonb,text)'), ('security.aer_review_lineage_v1(uuid)'),
                                 ('security.coverage_identity_allowed(uuid,text,text)'), ('security.course_entry_read_check_v1(jsonb,jsonb)'), ('security.system_actor_id()'),
                                 ('security.pipeline_num_v1(text,numeric)'), ('security.current_role_rank()')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if md5(pg_get_functiondef('security.course_entry_review_apply_v1(uuid,text,jsonb,text)'::regprocedure)) <> '4be9267d8419dee7d9f80cb96ff4098b' then
    raise exception 'security.course_entry_review_apply_v1 differs from the definition this rule was written against (4be9267d...): review before applying';
  end if;
  if md5(pg_get_functiondef('security.course_entry_gate_v1(uuid,uuid[])'::regprocedure)) <> '4fc06c081e451f2d0fb0a504a4fbe10f' then
    raise exception 'security.course_entry_gate_v1 differs from the definition this rule was written against (4fc06c08...): review before applying';
  end if;
end $g$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.machine_mode', 'Entry requirements: automatic admission of complete course reads',
  '0 off. 1 shadow: records what rule aer-machine-v1 would admit and changes nothing. 2 admit: admits complete, source-proved first course reads as machine decisions; refused by the code unless a passing validation (security.aer_machine_validate_v1) is recorded after the shadow period. Everything the rule does not admit stays in Layer 4 for a person.',
  'number', to_jsonb(1), 0, 2, 'mode', 1490, 'Entry requirements', 'security.aer_machine_run_v1; job aer-machine-admission',
  'Platform Admin decision 10 Nov 2026 (AER recovery pack, decision 1): build, shadow 24 hours, then enable conditionally after independent validation'),
 ('pipeline', 'aer.machine_daily_max', 'Entry requirements: automatic admissions a day', 'The most course reads rule aer-machine-v1 admits in any 24 hours.',
  'number', to_jsonb(300), 0, 5000, 'reads', 1491, 'Entry requirements', 'security.aer_machine_run_v1', 'Platform Admin decision 10 Nov 2026: daily admission cap'),
 ('pipeline', 'aer.machine_audit_pct', 'Entry requirements: random audit share', 'The share (per cent) of reads that pass the rule but are left in Layer 4 for a person as a random audit sample.',
  'number', to_jsonb(5), 0, 100, 'per cent', 1492, 'Entry requirements', 'security.aer_machine_check_v1', 'Platform Admin decision 10 Nov 2026: random 5% Layer 4 audit'),
 ('pipeline', 'aer.machine_min_confidence', 'Entry requirements: lowest reader confidence for automatic admission', 'Every waiting row of the read must have at least this confidence.',
  'number', to_jsonb(0.8), 0, 1, 'confidence', 1493, 'Entry requirements', 'security.aer_machine_check_v1', 'Platform Admin decision 10 Nov 2026: unsupported evidence goes to Layer 4'),
 ('pipeline', 'aer.machine_min_quote_chars', 'Entry requirements: shortest supporting quote for automatic admission', 'Every waiting row must carry an exact quote of at least this many characters.',
  'number', to_jsonb(8), 1, 300, 'characters', 1494, 'Entry requirements', 'security.aer_machine_check_v1', 'Platform Admin decision 10 Nov 2026: an exact supporting quote for every admitted requirement'),
 ('pipeline', 'aer.machine_shadow_min_hours', 'Entry requirements: shadow period before automatic admission', 'Hours of shadow results needed before a validation can pass.',
  'number', to_jsonb(24), 1, 720, 'hours', 1495, 'Entry requirements', 'security.aer_machine_validate_v1', 'Platform Admin decision 10 Nov 2026: shadow 24 hours'),
 ('pipeline', 'batch.aer_machine', 'Entry requirements: reads checked a run (automatic admission)', 'The most waiting course reads one run of job aer-machine-admission checks.',
  'number', to_jsonb(60), 1, 500, 'reads', 1496, 'Entry requirements', 'security.aer_machine_run_v1', 'Platform Admin decision 10 Nov 2026'),
 ('pipeline', 'aer.machine_suspended', 'Entry requirements: automatic admission suspended', '1 stops automatic admission (shadow continues). Set to 1 by the rule itself when a person rejects or returns a random audit sample the rule would have admitted, or a machine admission is withdrawn. Only a person sets it back to 0, with a reason.',
  'number', to_jsonb(0), 0, 1, 'switch', 1497, 'Entry requirements', 'security.aer_machine_run_v1', 'Platform Admin decision 10 Nov 2026: immediate suspension on critical defects')
on conflict (toolset_key, key) do nothing;

-- ----------------------------------------------------------------------------------------------------------------------------------------- ledger
create table if not exists pipeline.aer_machine_admissions (
  id bigint generated always as identity primary key,
  review_item_id uuid not null,
  course_id uuid,
  provider_id uuid,
  mode text not null check (mode in ('shadow', 'admit')),
  outcome text not null check (outcome in ('would_admit', 'admitted', 'declined', 'audit_sample', 'withdrawn')),
  rule text not null default 'aer-machine-v1',
  reason_code text,
  reason text,
  next_action text,
  checks jsonb not null default '{}'::jsonb,
  rows_admitted int,
  decision_id uuid,
  evidence_id uuid,
  content_hash text,
  source_url text,
  actor uuid,
  withdrawn_at timestamptz,
  withdrawn_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists aer_machine_admissions_shadow_uq on pipeline.aer_machine_admissions(review_item_id) where mode = 'shadow';
create unique index if not exists aer_machine_admissions_admit_uq on pipeline.aer_machine_admissions(review_item_id) where mode = 'admit' and outcome = 'admitted';
create index if not exists aer_machine_admissions_created_idx on pipeline.aer_machine_admissions(created_at);
comment on table pipeline.aer_machine_admissions is 'CF-247 F-AER.04 rule aer-machine-v1 ledger: shadow results (one row per item, refreshed), admissions (one per item), declines in admit mode, audit samples and withdrawals. Kept for audit; nothing deletes it.';
alter table pipeline.aer_machine_admissions enable row level security;
revoke all on pipeline.aer_machine_admissions from public, anon, authenticated;

create table if not exists pipeline.aer_machine_validations (
  id bigint generated always as identity primary key,
  validated_at timestamptz not null default now(),
  passed boolean not null,
  detail jsonb not null,
  validated_by uuid
);
comment on table pipeline.aer_machine_validations is 'CF-247 F-AER.04: each run of security.aer_machine_validate_v1, with its figures. aer.machine_mode 2 is refused without a passing row in the last 7 days.';
alter table pipeline.aer_machine_validations enable row level security;
revoke all on pipeline.aer_machine_validations from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the check (read only)
create or replace function security.aer_machine_check_v1(p_item uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $f$
declare i pipeline.layer4_review_items%rowtype; c catalogue.courses%rowtype; g pipeline.coverage_course_pages%rowtype; v_gate jsonb; v_ev pipeline.evidence_artifacts%rowtype; v_bev pipeline.evidence_artifacts%rowtype;
        v_conf numeric := security.pipeline_num_v1('aer.machine_min_confidence', 0.8); v_qmin int := security.pipeline_num_v1('aer.machine_min_quote_chars', 8)::int;
        v_audit numeric := security.pipeline_num_v1('aer.machine_audit_pct', 5); v_n int; v_bad int; v_bucket int; v_checks jsonb := '{}'::jsonb;
  function_fail constant text := 'A person decides in Layer 4.';
begin
  select * into i from pipeline.layer4_review_items where id = p_item;
  if i.id is null or i.entity_type <> 'course' or i.field_code <> 'course_entry_first_read' then
    return jsonb_build_object('ok', false, 'rule', 'not_a_course_entry_read', 'reason', 'Only first course entry reads are in scope.', 'next_action', function_fail);
  end if;
  if i.status <> 'pending' then return jsonb_build_object('ok', false, 'rule', 'item_not_pending', 'reason', 'The item is ' || i.status || '.', 'next_action', 'Nothing to do.'); end if;
  if i.claimed_at is not null and i.claimed_at > now() - make_interval(mins => 60) then -- fixed: a person who opened the item in the last hour keeps it
    return jsonb_build_object('ok', false, 'rule', 'claimed_by_person', 'reason', 'A person opened this item in the last hour.', 'next_action', 'The person decides; the rule looks again later.', 'transient', true);
  end if;
  select * into c from catalogue.courses where id = i.entity_id;
  if c.id is null or c.lifecycle_status <> 'active' then return jsonb_build_object('ok', false, 'rule', 'course_not_active', 'reason', 'The course is not active.', 'next_action', function_fail); end if;
  if exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id) then
    return jsonb_build_object('ok', false, 'rule', 'provider_hidden', 'reason', 'The provider is hidden.', 'next_action', function_fail);
  end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field in ('entry_requirements', 'all')) then
    return jsonb_build_object('ok', false, 'rule', 'manual_lock', 'reason', 'The course''s entry requirements are locked by a person.', 'next_action', function_fail);
  end if;
  -- no earlier person's rejection or return of an entry read for this course (conflicting evidence goes to a person)
  if exists (select 1 from pipeline.layer4_review_items o where o.entity_id = c.id and o.field_code = 'course_entry_first_read' and o.id <> i.id
               and o.status in ('rejected', 'more_evidence', 'returned_layer2', 'returned_layer3')) then
    return jsonb_build_object('ok', false, 'rule', 'earlier_rejection', 'reason', 'A person rejected or returned an earlier entry read of this course.', 'next_action', function_fail);
  end if;
  if exists (select 1 from pipeline.layer4_review_items o where o.entity_id = c.id and o.field_code = 'course_entry_first_read' and o.status = 'pending' and o.id <> i.id) then
    return jsonb_build_object('ok', false, 'rule', 'duplicate_waiting', 'reason', 'Another entry read of this course is also waiting.', 'next_action', function_fail);
  end if;
  if exists (select 1 from catalogue.course_entry_requirements x where x.course_id = c.id and x.status = 'active') then
    return jsonb_build_object('ok', false, 'rule', 'active_rows_exist', 'reason', 'The course already has active entry requirements; replacing them is a person''s decision.', 'next_action', function_fail);
  end if;
  if exists (select 1 from pipeline.aer_machine_admissions m where m.course_id = c.id and m.outcome = 'withdrawn') then
    return jsonb_build_object('ok', false, 'rule', 'withdrawn_awaiting_person', 'reason', 'A machine admission of this course was withdrawn.', 'next_action', function_fail);
  end if;
  -- source identity and provenance: the course's current bound page, an identity basis admitted for entry requirements, and the read taken from that page's content
  select * into g from pipeline.coverage_course_pages p where p.course_id = c.id and p.status = 'bound' order by p.bound_at desc nulls last limit 1;
  if g.course_id is null then return jsonb_build_object('ok', false, 'rule', 'no_bound_page', 'reason', 'The course has no bound course page now.', 'next_action', function_fail); end if;
  if not security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements') then
    return jsonb_build_object('ok', false, 'rule', 'identity_not_admitted', 'reason', format('The page is matched to the course by %s, which is not admitted for entry requirements.', coalesce(g.identity_basis, 'no basis')), 'next_action', function_fail);
  end if;
  select * into v_ev from pipeline.evidence_artifacts where id = i.evidence_id;
  select * into v_bev from pipeline.evidence_artifacts where id = g.evidence_id;
  if v_ev.id is null or v_ev.storage_path is null then return jsonb_build_object('ok', false, 'rule', 'evidence_missing', 'reason', 'The stored page the read came from is missing.', 'next_action', function_fail); end if;
  if i.evidence_id is distinct from g.evidence_id and (v_ev.content_hash is null or v_ev.content_hash is distinct from v_bev.content_hash) then
    return jsonb_build_object('ok', false, 'rule', 'page_changed_since_read', 'reason', 'The course''s bound page changed after this read was taken.', 'next_action', 'A person decides, or the read is replaced by a read of the current page.');
  end if;
  v_checks := v_checks || jsonb_build_object('identity_basis', g.identity_basis, 'source_url', v_ev.source_url, 'content_hash', v_ev.content_hash, 'evidence_id', v_ev.id);
  -- the rows: at least one, each with an exact quote (verified on the page by the reader), enough confidence, from this item's evidence
  select count(*), count(*) filter (where coalesce(length(btrim(x.quote)), 0) < v_qmin or coalesce(x.confidence, 0) < v_conf or x.evidence_id is distinct from i.evidence_id)
    into v_n, v_bad
    from catalogue.course_entry_requirements x where x.provenance->>'review_item_id' = i.id::text and x.status = 'proposed';
  if v_n = 0 then return jsonb_build_object('ok', false, 'rule', 'no_rows', 'reason', 'The read has no waiting rows.', 'next_action', function_fail); end if;
  if v_bad > 0 then
    return jsonb_build_object('ok', false, 'rule', 'row_unsupported', 'reason', format('%s of %s waiting rows lack an exact quote of %s characters, confidence %s or this read''s evidence.', v_bad, v_n, v_qmin, v_conf), 'next_action', function_fail, 'checks', v_checks);
  end if;
  -- completeness: E13 + D-R3 (the same gate a person's approval runs)
  v_gate := security.course_entry_gate_v1(i.id, '{}'::uuid[]);
  if v_gate is null or not coalesce((v_gate->>'complete')::boolean, false) then
    return jsonb_build_object('ok', false, 'rule', 'gate_incomplete', 'reason', coalesce((select string_agg(w, '; ') from jsonb_array_elements_text(v_gate->'reasons') w), 'The completeness gate did not pass.'),
                              'next_action', 'Technical recovery (aer-replay, corrected reads) or a person in Layer 4.', 'checks', v_checks);
  end if;
  v_checks := v_checks || jsonb_build_object('rows', v_n, 'gate', 'E13 complete', 'min_confidence', v_conf, 'min_quote_chars', v_qmin);
  -- random audit sample: deterministic per item, so a re-run gives the same answer
  v_bucket := (('x' || substr(md5(i.id::text || ':aer-machine-v1'), 1, 8))::bit(32)::bigint % 100)::int; -- fixed: 100 buckets for a per-cent share
  if v_bucket < v_audit then
    return jsonb_build_object('ok', false, 'rule', 'audit_sample', 'audit', true, 'reason', format('Random audit sample (%s%%): the rule would admit this read; a person checks it.', v_audit), 'next_action', function_fail, 'checks', v_checks);
  end if;
  return jsonb_build_object('ok', true, 'rule', 'aer-machine-v1', 'course_id', c.id, 'provider_id', c.provider_id, 'checks', v_checks);
end $f$;
comment on function security.aer_machine_check_v1(uuid) is 'CF-247 F-AER.04 rule aer-machine-v1 (read only): whether a waiting first course entry read is complete and source-proved enough for machine admission. The first failing check names the rule, the reason and the next action. A random audit sample (aer.machine_audit_pct) is returned as audit_sample.';
revoke all on function security.aer_machine_check_v1(uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- admission of one item
create or replace function security.aer_machine_admit_v1(p_item uuid, p_via text default 'run') returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare i pipeline.layer4_review_items%rowtype; v jsonb; v_mode int := security.pipeline_num_v1('aer.machine_mode', 0)::int; v_res jsonb; v_dec uuid; v_reason text; v_aer jsonb;
        v_sys uuid := security.system_actor_id(); v_after int; v_course uuid; v_prov uuid; v_out text;
        v_ref constant text := 'CF-247 F-AER.04; Platform Admin decision 10 Nov 2026 (AER recovery pack decision 1: machine admission of complete, source-proved course reads)';
begin
  if v_mode < 1 then return jsonb_build_object('ok', false, 'rule', 'machine_mode_off'); end if;
  if v_mode >= 2 and not exists (select 1 from pipeline.aer_machine_validations x where x.passed and x.validated_at > now() - make_interval(days => 7)) then -- fixed: a validation is valid for 7 days
    v_mode := 1; -- admit mode without a passing validation runs as shadow (a passing check never switches admission on by itself)
  end if;
  if v_mode >= 2 and security.pipeline_num_v1('aer.machine_suspended', 0) >= 1 then v_mode := 1; end if;
  if v_mode >= 2 then
    select * into i from pipeline.layer4_review_items where id = p_item for update skip locked;
    if i.id is null then return jsonb_build_object('ok', false, 'rule', 'item_locked'); end if;
  end if;
  v := security.aer_machine_check_v1(p_item);
  select c.id, c.provider_id into v_course, v_prov from pipeline.layer4_review_items li join catalogue.courses c on c.id = li.entity_id where li.id = p_item;
  v_out := case when coalesce((v->>'ok')::boolean, false) then (case when v_mode >= 2 then 'admitted' else 'would_admit' end)
                when coalesce((v->>'audit')::boolean, false) then 'audit_sample' else 'declined' end;
  if v_mode < 2 then
    insert into pipeline.aer_machine_admissions (review_item_id, course_id, provider_id, mode, outcome, reason_code, reason, next_action, checks, evidence_id, content_hash, source_url, actor)
    values (p_item, v_course, v_prov, 'shadow', v_out, v->>'rule', v->>'reason', v->>'next_action', coalesce(v->'checks', '{}'::jsonb),
            nullif(v->'checks'->>'evidence_id', '')::uuid, v->'checks'->>'content_hash', v->'checks'->>'source_url', v_sys)
    on conflict (review_item_id) where mode = 'shadow' do update set outcome = excluded.outcome, reason_code = excluded.reason_code, reason = excluded.reason, next_action = excluded.next_action,
           checks = excluded.checks, evidence_id = excluded.evidence_id, content_hash = excluded.content_hash, source_url = excluded.source_url, updated_at = now();
    return jsonb_build_object('ok', true, 'mode', 'shadow', 'outcome', v_out, 'rule', v->>'rule');
  end if;
  if v_out <> 'admitted' then
    if v_out = 'audit_sample' or coalesce((v->>'transient')::boolean, false) is false then
      update pipeline.layer4_review_items set escalation_reason = left('Machine rule aer-machine-v1 did not admit this: ' || (v->>'rule') || '. ' || regexp_replace(coalesce(escalation_reason, ''), '^Machine rule aer-machine-v1[^:]*: [a-z0-9_]+\. ', ''), 1000) -- fixed: the column shows 1000 characters
       where id = p_item and status = 'pending' and coalesce(escalation_reason, '') not like 'Machine rule aer-machine-v1 did not admit this: ' || (v->>'rule') || '.%';
    end if;
    if not exists (select 1 from pipeline.aer_machine_admissions m where m.review_item_id = p_item and m.mode = 'admit' and m.outcome = v_out and m.reason_code is not distinct from v->>'rule') then
      insert into pipeline.aer_machine_admissions (review_item_id, course_id, provider_id, mode, outcome, reason_code, reason, next_action, checks, actor)
      values (p_item, v_course, v_prov, 'admit', v_out, v->>'rule', v->>'reason', v->>'next_action', coalesce(v->'checks', '{}'::jsonb), v_sys);
    end if;
    return jsonb_build_object('ok', false, 'mode', 'admit', 'outcome', v_out, 'rule', v->>'rule', 'reason', v->>'reason');
  end if;
  -- admit: the same apply a person's approval uses (E13 runs again inside it), then the same records
  v_aer := security.aer_review_lineage_v1(p_item);
  v_reason := format('Auto (aer-machine-v1, %s): complete first read (E13 and D-R3 passed), %s rows each with an exact quote on the stored page %s (content hash %s), page bound to the course by %s, confidence at least %s. Not a person''s decision.',
                     coalesce(p_via, 'run'), v->'checks'->>'rows', coalesce(v->'checks'->>'source_url', ''), left(coalesce(v->'checks'->>'content_hash', ''), 12), v->'checks'->>'identity_basis', v->'checks'->>'min_confidence'); -- fixed: a short hash prefix for reading; the full hash is in the ledger
  v_res := security.course_entry_review_apply_v1(p_item, 'approve', i.proposed_value - 'exclude_row_ids', v_reason);
  select count(*) into v_after from catalogue.course_entry_requirements x where x.provenance->>'review_item_id' = p_item::text and x.status = 'active';
  if v_after = 0 or v_after <> coalesce((v_res->>'admitted')::int, -1) then raise exception 'aer-machine: read-back found % active rows, apply reported %', v_after, v_res->>'admitted'; end if;
  update pipeline.layer4_review_items set status = 'approved', decided_at = now() where id = p_item and status = 'pending';
  insert into pipeline.layer4_decisions (review_item_id, action, actor_id, reason, before_value, proposed_value, final_value, evidence_id, layer2_state, layer3_state, change_control_ref)
  values (i.id, 'approve', v_sys, v_reason, i.before_value, i.proposed_value, i.proposed_value - 'exclude_row_ids', i.evidence_id,
          coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('machine_rule', 'aer-machine-v1', 'actor_kind', 'machine', 'via', coalesce(p_via, 'run')), coalesce(i.layer3_state, '{}'::jsonb), v_ref)
  returning id into v_dec;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'aer_approve', 'pipeline.layer4_review_items', jsonb_build_object('review_item_id', i.id, 'decision_id', v_dec, 'kind', i.field_code, 'reason', v_reason, 'lineage', v_aer,
          'excluded_row_ids', '[]'::jsonb, 'result', v_res, 'auto', true, 'machine_rule', 'aer-machine-v1', 'actor_kind', 'machine'), v_sys);
  insert into pipeline.search_refresh_signals(entity_type, entity_id, review_decision_id, reason, change_control_ref)
  values ('course', i.entity_id, v_dec, 'Accepted machine-rule Layer 4 canonical change: ' || v_reason, v_ref);
  insert into pipeline.aer_machine_admissions (review_item_id, course_id, provider_id, mode, outcome, reason_code, reason, checks, rows_admitted, decision_id, evidence_id, content_hash, source_url, actor)
  values (i.id, v_course, v_prov, 'admit', 'admitted', 'aer-machine-v1', v_reason, coalesce(v->'checks', '{}'::jsonb) || jsonb_build_object('apply', v_res, 'via', coalesce(p_via, 'run')),
          v_after, v_dec, i.evidence_id, v->'checks'->>'content_hash', v->'checks'->>'source_url', v_sys);
  return jsonb_build_object('ok', true, 'mode', 'admit', 'outcome', 'admitted', 'decision_id', v_dec, 'rows', v_after);
end $f$;
comment on function security.aer_machine_admit_v1(uuid, text) is 'CF-247 F-AER.04 rule aer-machine-v1 for one waiting first course entry read. Mode 1 (or 2 without a passing validation, or while suspended): records the shadow result only. Mode 2: admits through security.course_entry_review_apply_v1 (the apply a person''s approval uses), settles the item as a machine decision under the system automation account and records the A1 lineage event, the search refresh signal and the ledger; anything else stays waiting with the exact reason.';
revoke all on function security.aer_machine_admit_v1(uuid, text) from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- suspension on a critical defect
create or replace function security.aer_machine_suspend_check_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare v_bad record; v_sys uuid := security.system_actor_id();
begin
  if security.pipeline_num_v1('aer.machine_suspended', 0) >= 1 then return jsonb_build_object('suspended', true, 'already', true); end if;
  -- a person's non-approval of a read the rule would have admitted (audit sample or shadow would_admit), or a withdrawal
  select d.review_item_id item, d.action, d.created_at, m.outcome into v_bad
    from pipeline.layer4_decisions d
    join pipeline.aer_machine_admissions m on m.review_item_id = d.review_item_id and m.outcome in ('audit_sample', 'would_admit')
   where d.actor_id is distinct from v_sys and d.action in ('reject', 'request_more_evidence', 'return_layer2', 'return_layer3') and d.created_at > m.created_at
   order by d.created_at desc limit 1;
  if v_bad.item is null then
    select m.review_item_id item, 'withdrawn' action, m.withdrawn_at created_at, m.outcome into v_bad from pipeline.aer_machine_admissions m where m.outcome = 'withdrawn' order by m.withdrawn_at desc limit 1;
  end if;
  if v_bad.item is null then return jsonb_build_object('suspended', false); end if;
  if exists (select 1 from pipeline.admin_control_events e where e.area = 'pipeline' and e.action = 'aer_machine_suspended' and e.detail->>'review_item_id' = v_bad.item::text) then
    return jsonb_build_object('suspended', false, 'note', 'the defect on item ' || v_bad.item || ' was already acted on and a person resumed the rule');
  end if;
  update pipeline.platform_toolset_settings set value = to_jsonb(1), updated_at = now(),
         reason = format('Suspended by rule aer-machine-v1: a person %s item %s that the rule would have admitted (%s). A person reviews and sets this back to 0 with a reason.', v_bad.action, v_bad.item, v_bad.outcome)
   where toolset_key = 'pipeline' and key = 'aer.machine_suspended';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('pipeline', 'aer_machine_suspended', 'aer.machine_suspended', jsonb_build_object('review_item_id', v_bad.item, 'person_action', v_bad.action, 'at', v_bad.created_at, 'ledger_outcome', v_bad.outcome), v_sys);
  return jsonb_build_object('suspended', true, 'item', v_bad.item, 'action', v_bad.action);
end $f$;
comment on function security.aer_machine_suspend_check_v1() is 'CF-247 F-AER.04: sets aer.machine_suspended = 1 (admission stops, shadow continues) when a person rejects or returns a read the rule would have admitted, or a machine admission is withdrawn. Each defect suspends once; only a person resumes.';
revoke all on function security.aer_machine_suspend_check_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the job's run
create or replace function security.aer_machine_run_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare v_mode int := security.pipeline_num_v1('aer.machine_mode', 0)::int; v_batch int := security.pipeline_num_v1('batch.aer_machine', 60)::int;
        v_cap int := security.pipeline_num_v1('aer.machine_daily_max', 300)::int; v_used int; v_t0 timestamptz := clock_timestamp(); v_susp jsonb; r record; v jsonb;
        v_n int := 0; v_out jsonb := '{}'::jsonb; v_err int := 0;
begin
  if v_mode < 1 then return jsonb_build_object('mode', 0); end if;
  begin v_susp := security.aer_machine_suspend_check_v1(); exception when others then v_susp := jsonb_build_object('error', sqlerrm); end;
  select count(*) into v_used from pipeline.aer_machine_admissions where mode = 'admit' and outcome = 'admitted' and created_at > now() - make_interval(hours => 24); -- fixed: the cap counts the last 24 hours
  -- gate-complete items first (the readiness job's record), then the rest that were never looked at by the rule, oldest first
  for r in select i.id from pipeline.layer4_review_items i
             left join pipeline.layer4_item_readiness k on k.item_id = i.id
             left join pipeline.aer_machine_admissions s on s.review_item_id = i.id and s.mode = 'shadow'
            where i.status = 'pending' and i.field_code = 'course_entry_first_read' and i.entity_type = 'course'
              and (s.id is null or s.updated_at < now() - make_interval(hours => 6) or coalesce(k.gate_checked_at, '-infinity') > s.updated_at) -- fixed: an unchanged item is looked at again after 6 hours
            order by coalesce((k.gate->>'complete')::boolean, false) desc, (s.id is null) desc, i.created_at
            limit v_batch loop
    exit when clock_timestamp() - v_t0 > make_interval(secs => 45); -- fixed: a run stays inside the job's time
    exit when v_mode >= 2 and v_used >= v_cap;
    begin
      v := security.aer_machine_admit_v1(r.id, 'run');
      v_n := v_n + 1;
      v_out := jsonb_set(v_out, array[coalesce(v->>'outcome', v->>'rule', 'unknown')], to_jsonb(coalesce((v_out->>coalesce(v->>'outcome', v->>'rule', 'unknown'))::int, 0) + 1));
      if v->>'outcome' = 'admitted' then v_used := v_used + 1; end if;
    exception when others then v_err := v_err + 1;
    end;
  end loop;
  return jsonb_build_object('mode', v_mode, 'effective', case when v_mode >= 2 and security.pipeline_num_v1('aer.machine_suspended', 0) < 1
                              and exists (select 1 from pipeline.aer_machine_validations x where x.passed and x.validated_at > now() - make_interval(days => 7)) then 'admit' else 'shadow' end,
                            'checked', v_n, 'outcomes', v_out, 'errors', v_err, 'admitted_24h', v_used, 'cap', v_cap, 'suspension', v_susp);
end $f$;
comment on function security.aer_machine_run_v1() is 'CF-247 F-AER.04: one run of the catalogued job aer-machine-admission: the suspension check, then up to batch.aer_machine waiting course reads through rule aer-machine-v1 (gate-complete first), within aer.machine_daily_max in admit mode. Does nothing while aer.machine_mode is 0.';
revoke all on function security.aer_machine_run_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- withdrawal (rollback of one admission)
create or replace function security.aer_machine_withdraw_v1(p_item uuid, p_reason text, p_actor uuid) returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare m pipeline.aer_machine_admissions%rowtype; v_n int;
begin
  if length(btrim(coalesce(p_reason, ''))) < 5 then raise exception 'a reason is required'; end if;
  select * into m from pipeline.aer_machine_admissions where review_item_id = p_item and mode = 'admit' and outcome = 'admitted' and withdrawn_at is null for update;
  if m.id is null then raise exception 'no machine admission to withdraw for item %', p_item; end if;
  if exists (select 1 from pipeline.layer4_decisions d where d.review_item_id = p_item and d.actor_id is distinct from security.system_actor_id()) then
    raise exception 'a person has decided this item since; withdraw through Layer 4';
  end if;
  update catalogue.course_entry_requirements x set status = 'proposed', status_reason = 'machine admission withdrawn: ' || btrim(p_reason), updated_at = now()
   where x.provenance->>'review_item_id' = p_item::text and x.status = 'active';
  get diagnostics v_n = row_count;
  update pipeline.layer4_review_items set status = 'pending', decided_at = null,
         escalation_reason = left('Machine admission (aer-machine-v1) withdrawn: ' || btrim(p_reason) || '. A person decides.', 1000) where id = p_item; -- fixed: column display width
  update pipeline.aer_machine_admissions set withdrawn_at = now(), withdrawn_reason = btrim(p_reason), updated_at = now() where id = m.id;
  insert into pipeline.aer_machine_admissions (review_item_id, course_id, provider_id, mode, outcome, reason_code, reason, rows_admitted, decision_id, actor)
  values (p_item, m.course_id, m.provider_id, 'admit', 'withdrawn', 'withdrawn', btrim(p_reason), v_n, m.decision_id, p_actor);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'aer_machine_withdraw', 'pipeline.layer4_review_items', jsonb_build_object('review_item_id', p_item, 'rows_back_to_proposed', v_n, 'reason', btrim(p_reason), 'decision_id', m.decision_id), p_actor);
  insert into pipeline.search_refresh_signals(entity_type, entity_id, review_decision_id, reason, change_control_ref)
  values ('course', m.course_id, m.decision_id, 'Machine admission withdrawn: ' || btrim(p_reason), 'CF-247 F-AER.04');
  return jsonb_build_object('ok', true, 'rows_back_to_proposed', v_n, 'item', p_item);
end $f$;
comment on function security.aer_machine_withdraw_v1(uuid, text, uuid) is 'CF-247 F-AER.04: rollback of one machine admission: its rows back to proposed, the item back to pending for a person, ledger and decision kept, and the rule suspended by the next run.';
revoke all on function security.aer_machine_withdraw_v1(uuid, text, uuid) from public, anon, authenticated;

create or replace function public.admin_aer_machine_withdraw_v1(p_item uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $f$
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if; -- fixed: rank 6 is the Platform Admin
  return security.aer_machine_withdraw_v1(p_item, p_reason, auth.uid());
end $f$;
revoke all on function public.admin_aer_machine_withdraw_v1(uuid, text) from public, anon;
grant execute on function public.admin_aer_machine_withdraw_v1(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- historical agreement (read only)
create or replace function security.aer_machine_history_v1() returns jsonb
language sql stable security definer set search_path to '' as $f$
  with s as (select security.pipeline_num_v1('aer.machine_min_confidence', 0.8) conf, security.pipeline_num_v1('aer.machine_min_quote_chars', 8)::int qmin),
  h as (select i.id, d.action, i.proposed_value
          from pipeline.layer4_review_items i join pipeline.layer4_decisions d on d.review_item_id = i.id
         where i.field_code = 'course_entry_first_read' and d.actor_id is distinct from security.system_actor_id()),
  x as (select h.id, h.action,
               (select count(*) from catalogue.course_entry_requirements r where r.provenance->>'review_item_id' = h.id::text) nrows,
               (select count(*) from catalogue.course_entry_requirements r cross join s where r.provenance->>'review_item_id' = h.id::text
                  and (coalesce(length(btrim(r.quote)), 0) < s.qmin or coalesce(r.confidence, 0) < s.conf)) bad,
               security.course_entry_read_check_v1(
                 (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'audience', r.audience, 'quote', r.quote)), '[]'::jsonb)
                    from catalogue.course_entry_requirements r where r.provenance->>'review_item_id' = h.id::text and r.status in ('active', 'superseded')),
                 coalesce(h.proposed_value->'dropped', '[]'::jsonb)) chk
          from h),
  y as (select x.*, (nrows > 0 and bad = 0 and jsonb_array_length(coalesce(chk->'drops_uncovered', '[]')) = 0 and jsonb_array_length(coalesce(chk->'not_requirement', '[]')) = 0
                     and jsonb_array_length(coalesce(chk->'audience', '[]')) = 0) would from x)
  select jsonb_build_object('contract', 'aer-machine-history-v1', 'as_at', now(), 'human_decisions', count(*),
           'human_approved', count(*) filter (where action in ('approve', 'edit_and_approve')),
           'human_not_approved', count(*) filter (where action not in ('approve', 'edit_and_approve')),
           'rule_would_admit', count(*) filter (where would),
           'rule_would_admit_and_human_approved', count(*) filter (where would and action = 'approve'),
           'rule_would_admit_but_human_edited_or_refused', count(*) filter (where would and action <> 'approve'),
           'rule_would_hold_human_approved', count(*) filter (where not would and action in ('approve', 'edit_and_approve')),
           'disagreements', coalesce(jsonb_agg(jsonb_build_object('item', id, 'action', action)) filter (where would and action <> 'approve'), '[]'::jsonb),
           'note', 'Row-level rules (quote, confidence, read check E13 drops / not-a-requirement / audience) over rows as recorded; identity and page-change rules use the binding at decision time, which is not kept, so they are not part of this measure.')
    from y
$f$;
comment on function security.aer_machine_history_v1() is 'CF-247 F-AER.04 (read only): how rule aer-machine-v1''s row-level checks agree with the human decisions already made on first course entry reads.';
revoke all on function security.aer_machine_history_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- validation (records; never switches anything)
create or replace function security.aer_machine_validate_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
declare v_hist jsonb := security.aer_machine_history_v1(); v_min_h numeric := security.pipeline_num_v1('aer.machine_shadow_min_hours', 24);
        v_first timestamptz; v_hours numeric; v_n int; v_would int; v_regress int := 0; v_human_bad int; r record; v_c jsonb; v_pass boolean; v_detail jsonb;
begin
  select min(created_at), count(*), count(*) filter (where outcome = 'would_admit') into v_first, v_n, v_would from pipeline.aer_machine_admissions where mode = 'shadow';
  v_hours := extract(epoch from (now() - coalesce(v_first, now()))) / 3600.0;
  -- independent re-check: every current would_admit item is checked again now; one that no longer passes (other than now decided or claimed) is a regression
  for r in select m.review_item_id from pipeline.aer_machine_admissions m join pipeline.layer4_review_items i on i.id = m.review_item_id and i.status = 'pending'
            where m.mode = 'shadow' and m.outcome = 'would_admit' loop
    v_c := security.aer_machine_check_v1(r.review_item_id);
    if not coalesce((v_c->>'ok')::boolean, false) and coalesce(v_c->>'rule', '') not in ('audit_sample', 'claimed_by_person', 'item_not_pending') then v_regress := v_regress + 1; end if;
  end loop;
  select count(*) into v_human_bad from pipeline.layer4_decisions d join pipeline.aer_machine_admissions m on m.review_item_id = d.review_item_id and m.outcome in ('would_admit', 'audit_sample')
   where d.actor_id is distinct from security.system_actor_id() and d.action <> 'approve';
  v_pass := v_hours >= v_min_h and v_n >= 50 and v_regress = 0 and v_human_bad = 0 -- fixed: at least 50 shadow results
            and coalesce((v_hist->>'rule_would_admit_but_human_edited_or_refused')::int, 1) <= greatest(1, ((v_hist->>'rule_would_admit')::int) / 50); -- fixed: at most 2% disagreement with past human decisions
  v_detail := jsonb_build_object('shadow_hours', round(v_hours, 1), 'shadow_min_hours', v_min_h, 'shadow_results', v_n, 'shadow_would_admit', v_would, 'regressions_on_recheck', v_regress,
                                 'human_non_approvals_of_rule_admits', v_human_bad, 'history', v_hist - 'disagreements', 'history_disagreements', v_hist->'disagreements');
  insert into pipeline.aer_machine_validations(passed, detail, validated_by) values (v_pass, v_detail, auth.uid());
  return v_detail || jsonb_build_object('passed', v_pass, 'note', 'A pass does not switch admission on. A person (or the Integration Controller under the Platform Admin decision) sets aer.machine_mode to 2 with a reason.');
end $f$;
comment on function security.aer_machine_validate_v1() is 'CF-247 F-AER.04: records whether rule aer-machine-v1 may be switched to admit: shadow period, at least 50 shadow results, every would-admit re-checked now with no regression, no person refused a read the rule would admit, and agreement with past human decisions. Never changes a setting.';
revoke all on function security.aer_machine_validate_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- scoreboard (read only)
create or replace function security.aer_machine_report_v1() returns jsonb
language sql stable security definer set search_path to '' as $f$
  select jsonb_build_object('contract', 'aer-machine-report-v1', 'as_at', now(),
    'mode', security.pipeline_num_v1('aer.machine_mode', 0), 'suspended', security.pipeline_num_v1('aer.machine_suspended', 0) >= 1,
    'validated', (select jsonb_build_object('passed', x.passed, 'at', x.validated_at) from pipeline.aer_machine_validations x order by x.validated_at desc limit 1),
    'shadow', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select m.outcome k, count(*) n from pipeline.aer_machine_admissions m join pipeline.layer4_review_items i on i.id = m.review_item_id and i.status = 'pending' where m.mode = 'shadow' group by 1) z),
    'shadow_declined_by_rule', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select m.reason_code k, count(*) n from pipeline.aer_machine_admissions m join pipeline.layer4_review_items i on i.id = m.review_item_id and i.status = 'pending' where m.mode = 'shadow' and m.outcome = 'declined' group by 1) z),
    'admitted', (select count(*) from pipeline.aer_machine_admissions where mode = 'admit' and outcome = 'admitted' and withdrawn_at is null),
    'admitted_24h', (select count(*) from pipeline.aer_machine_admissions where mode = 'admit' and outcome = 'admitted' and withdrawn_at is null and created_at > now() - make_interval(hours => 24)), -- fixed: report window
    'rows_admitted', (select coalesce(sum(rows_admitted), 0) from pipeline.aer_machine_admissions where mode = 'admit' and outcome = 'admitted' and withdrawn_at is null),
    'withdrawn', (select count(*) from pipeline.aer_machine_admissions where outcome = 'withdrawn'),
    'courses_with_active_aer', (select count(distinct course_id) from catalogue.course_entry_requirements where status = 'active'),
    'waiting_course_reads', (select count(*) from pipeline.layer4_review_items where field_code = 'course_entry_first_read' and status = 'pending'))
$f$;
comment on function security.aer_machine_report_v1() is 'CF-247 F-AER.04 scoreboard (read only): mode, suspension, last validation, shadow outcomes and decline rules on waiting items, admissions (total, 24 hours, rows), withdrawals, courses with active AER and waiting reads.';
revoke all on function security.aer_machine_report_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the job (G1)
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('aer-machine-admission', 'Enrichment', 31, 'Entry requirements: automatic admission of complete course reads',
  'At :24 and :54 (after the readiness check): rule aer-machine-v1 looks at the waiting first course entry reads (complete ones first). Mode 1 (shadow) records what it would admit and changes nothing. Mode 2, after a passing validation, admits complete, source-proved reads as machine decisions (same apply as a person''s approval), within the daily cap, leaves a random 5% audit sample and everything else for a person in Layer 4 with the exact reason, and suspends itself if a person refuses a read it would admit. Settings > Pipeline settings > Entry requirements.',
  6, false, null)
on conflict (jobname) do nothing;
do $c$ begin
  if not exists (select 1 from cron.job where jobname = 'aer-machine-admission') then
    perform cron.schedule('aer-machine-admission', '24,54 * * * *', $j$select security.aer_machine_run_v1()$j$);
  end if;
end $c$;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.aer_machine_check_v1', 'Layer 4', 'Rule aer-machine-v1: is a first course entry read complete and source-proved', 'active', '{}', '20261111020000'),
 ('function', 'security.aer_machine_admit_v1', 'Layer 4', 'Shadow or machine admission of one first course entry read', 'active', '{}', '20261111020000'),
 ('function', 'security.aer_machine_run_v1', 'Layer 4', 'Job aer-machine-admission run', 'active', '{}', '20261111020000'),
 ('function', 'security.aer_machine_suspend_check_v1', 'Layer 4', 'Suspends rule aer-machine-v1 on a critical defect', 'active', '{}', '20261111020000'),
 ('function', 'security.aer_machine_withdraw_v1', 'Layer 4', 'Rollback of one machine AER admission', 'active', '{}', '20261111020000'),
 ('function', 'public.admin_aer_machine_withdraw_v1', 'Layer 4', 'Platform Admin withdrawal of one machine AER admission', 'active', '{}', '20261111020000'),
 ('function', 'security.aer_machine_history_v1', 'Layer 4', 'Agreement of rule aer-machine-v1 with past human decisions', 'active', '{}', '20261111020000'),
 ('function', 'security.aer_machine_validate_v1', 'Layer 4', 'Records whether rule aer-machine-v1 may be switched to admit', 'active', '{}', '20261111020000'),
 ('function', 'security.aer_machine_report_v1', 'Layer 4', 'Scoreboard of rule aer-machine-v1', 'active', '{}', '20261111020000'),
 ('table', 'pipeline.aer_machine_admissions', 'Layer 4', 'Ledger of rule aer-machine-v1', 'active', '{}', '20261111020000'),
 ('table', 'pipeline.aer_machine_validations', 'Layer 4', 'Validations of rule aer-machine-v1', 'active', '{}', '20261111020000'),
 ('job', 'aer-machine-admission', 'Layer 4', 'Runs rule aer-machine-v1', 'active', '{}', '20261111020000')
on conflict do nothing;

do $p$
begin
  if security.pipeline_num_v1('aer.machine_mode', -1) <> 1 then raise exception 'post-check: aer.machine_mode must ship at 1 (shadow)'; end if;
  if not exists (select 1 from cron.job where jobname = 'aer-machine-admission') then raise exception 'post-check: job missing'; end if;
end $p$;
