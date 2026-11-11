-- CF-247 F-AER.04 AER machine admission for country tables and qualification rows: rule aer-matrix-machine-v1 (Platform Admin decision D1, 11 Nov 2026 20:17 AEDT, SS-017,
-- Operating Model v1.12: "a source-verified, narrowly defined machine-admission class for both country-specific AER tables and international/national qualification rows ...
-- Do not infer academic equivalencies, country applicability, course eligibility or missing scores. Keep unsupported, ambiguous or conflicting rows in Layer 4. Do not convert
-- historical human-held decisions into machine approvals or count machine decisions towards human trust thresholds ... through the existing admission framework, with mandatory
-- QA, CI, audited activation and actual canonical results").
-- Guards: G1 (no job added: the existing aer-machine-admission job runs the class), G2 (every threshold is a setting), G3 (no consumer API object changed), Decision 260,
--   "a passing qualification never switches anything on by itself" (ships in shadow, aer.matrix_machine_mode 1; admission needs mode 2 AND a passing validation of its own).
-- Evidence (production, read only, 11 Nov 2026 20:20 AEDT): 56 entry_matrix_first_run and 5 entry_matrix_change items wait for a person; 43 earlier human decisions on matrix
--   items (approve 35, edit_and_approve 6, reject 2). Matrix items are decided by security.entry_matrix_review_apply_v1 (approve called directly; the status trigger handles the
--   other outcomes). The course-read machine (aer-machine-v1) records its shadow results in pipeline.aer_machine_admissions and its validation re-checks every shadow row there,
--   so this class has its own ledger and validations: a matrix shadow row must never count in, or fail, the course validation.
-- The class admits an entry_matrix_first_run item only when ALL of these hold (each failure keeps the item in Layer 4 with the reason):
--   pending, not claimed or assigned, never decided; no manual lock on the provider's entry requirements; no earlier rejected or returned matrix item for the same source (protected
--   rejection); the read's stored copy exists and is the source's current copy; the source is on the provider's own website host (or its subdomain) and no other active provider
--   uses that host; the D-R3 gate and the completeness guard pass; every proposed row (country rows and qualification rows) has confidence >= aer.matrix_machine_min_confidence,
--   a quote of at least aer.machine_min_quote_chars, a mapped destination study level, and a published minimum (a value with its scale, or a grade printed in the quote); no two
--   rows share an identity and no row has the identity of an active row from another source; every qualification row has explicit applicability (global or listed countries:
--   unresolved stays with a person). Changes to admitted tables (entry_matrix_change) stay with a person. aer.matrix_machine_audit_pct of passing items go to a person as samples.
-- Admission uses the same apply a person's approval uses, then the same records (Layer 4 decision by the system actor, control event, search refresh signal) and its own
--   ledger row; the decision is marked actor_kind machine (never counted as a human decision). security.aer_matrix_machine_withdraw_v1 reverses an admission.
-- Live definitions this change edits (pg_proc.prosrc md5, read 11 Nov 2026 20:25 AEDT by Database function snapshot run 42994367041), before -> after:
--   security.aer_machine_run_v1() ad143b44722ba6fbc0129cd38386661c -> f88ab3f16833dec601786af5c7cdbbcc
-- Replaces: security.aer_machine_run_v1 (same name; md5-guarded text edits: the run also steps the matrix class, isolated from the course result, also when course admission is off); taken back by
--   supabase/held/aer_matrix_machine_admission_forward_recovery.sql
-- Retires: nothing.
-- Reversal without code: aer.matrix_machine_mode 0 (nothing checked) or 1 (shadow); an admitted item is reversed by security.aer_matrix_machine_withdraw_v1.

do $g$
declare r record;
begin
  for r in select * from (values ('security.aer_machine_run_v1()'), ('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)'), ('security.entry_matrix_gate_v1(uuid,uuid[])'),
                                 ('security.entry_completeness_required_v1(uuid)'), ('security.site_host_v1(text)'), ('security.system_actor_id()'), ('security.pipeline_num_v1(text,numeric)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if to_regclass('catalogue.provider_qualification_requirements') is null or to_regclass('pipeline.layer4_decisions') is null or to_regclass('pipeline.search_refresh_signals') is null
     or to_regclass('pipeline.manual_locks') is null then raise exception 'a table this change reads is missing'; end if;
end $g$;

-- ledger and validations of this class -------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.aer_matrix_machine_admissions (
  id bigserial primary key,
  review_item_id uuid not null,
  provider_id uuid,
  run_id uuid,
  mode text not null check (mode in ('shadow', 'admit')),
  outcome text not null check (outcome in ('would_admit', 'admitted', 'declined', 'audit_sample', 'withdrawn')),
  rule text not null default 'aer-matrix-machine-v1',
  reason_code text,
  reason text,
  checks jsonb not null default '{}'::jsonb,
  rows_admitted int,
  decision_id uuid,
  actor uuid,
  withdrawn_at timestamptz,
  withdrawn_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists aer_matrix_machine_admissions_shadow_uq on pipeline.aer_matrix_machine_admissions (review_item_id) where mode = 'shadow';
create index if not exists aer_matrix_machine_admissions_item_idx on pipeline.aer_matrix_machine_admissions (review_item_id, mode, outcome);
comment on table pipeline.aer_matrix_machine_admissions is 'CF-247 F-AER.04 (decision D1): ledger of rule aer-matrix-machine-v1 on entry-matrix Layer 4 items (country tables and qualification rows): shadow results, admissions with their decision, declines and audit samples with the reason, withdrawals. Kept apart from pipeline.aer_machine_admissions (course reads) so neither class counts in the other''s validation.';

create table if not exists pipeline.aer_matrix_machine_validations (
  id bigserial primary key,
  validated_at timestamptz not null default now(),
  passed boolean not null,
  detail jsonb not null default '{}'::jsonb,
  validated_by uuid
);
comment on table pipeline.aer_matrix_machine_validations is 'CF-247 F-AER.04 (decision D1): validations of rule aer-matrix-machine-v1 (shadow results, re-check of every would-admit item, agreement with past human matrix decisions). Admission needs a passing one from the last 7 days and aer.matrix_machine_mode 2; a pass switches nothing on by itself.';

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.matrix_machine_mode', 'Entry requirements: machine admission of country tables and qualification rows',
  '0 off; 1 shadow (each waiting first read of a country table is checked and the result recorded, nothing admitted); 2 admit (only with a passing validation from the last 7 days). Rule aer-matrix-machine-v1.',
  'number', to_jsonb(1), 0, 2, 'mode', 1520, 'Entry requirements', 'security.aer_matrix_machine_admit_v1; job aer-machine-admission',
  'Platform Admin decision D1, 11 Nov 2026 20:17: implement in shadow, validate, audited activation'),
 ('pipeline', 'aer.matrix_machine_min_confidence', 'Entry requirements: machine admission of country tables, least confidence of every row',
  'Every proposed row of the read (country and qualification rows) must have at least this reader confidence.', 'number', to_jsonb(0.9), 0.5, 1, 'confidence', 1521, 'Entry requirements',
  'security.aer_matrix_machine_check_v1', 'Platform Admin decision D1: narrowly defined class'),
 ('pipeline', 'aer.matrix_machine_audit_pct', 'Entry requirements: machine admission of country tables, audit sample',
  'Per cent of passing items sent to a person instead of admitted (a fixed sample by item).', 'number', to_jsonb(5), 0, 100, 'per cent', 1522, 'Entry requirements',
  'security.aer_matrix_machine_check_v1', 'Platform Admin decision D1: auditable class'),
 ('pipeline', 'aer.matrix_machine_daily_max', 'Entry requirements: machine admission of country tables, items a day at most',
  'Most entry-matrix items the rule admits in any 24 hours.', 'number', to_jsonb(40), 0, 1000, 'items', 1523, 'Entry requirements', 'security.aer_matrix_machine_run_v1',
  'Platform Admin decision D1'),
 ('pipeline', 'batch.aer_matrix_machine', 'Entry requirements: machine admission of country tables, items a run',
  'Most entry-matrix items one run of aer-machine-admission checks.', 'number', to_jsonb(20), 0, 200, 'items', 1524, 'Job sizes', 'security.aer_matrix_machine_run_v1',
  'Platform Admin decision D1'),
 ('pipeline', 'aer.matrix_machine_min_shadow', 'Entry requirements: machine admission of country tables, shadow results needed to validate',
  'Least number of items the rule must have checked in shadow before a validation can pass.', 'number', to_jsonb(20), 1, 1000, 'items', 1525, 'Entry requirements',
  'security.aer_matrix_machine_validate_v1', 'Platform Admin decision D1')
on conflict (toolset_key, key) do nothing;

-- the rule --------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_matrix_machine_check_v1(p_item uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare i pipeline.layer4_review_items%rowtype; r pipeline.entry_matrix_runs%rowtype; f pipeline.entry_matrix_sources%rowtype; v_web text; v_sh text; v_ph text; g jsonb;
        v_conf numeric := security.pipeline_num_v1('aer.matrix_machine_min_confidence', 0.9); v_qmin int := security.pipeline_num_v1('aer.machine_min_quote_chars', 8)::int;
        v_pct numeric := security.pipeline_num_v1('aer.matrix_machine_audit_pct', 5); v_nm int; v_nq int; v_bad text; v_checks jsonb;
        decline constant text := 'A person decides this in Layer 4 (Approve, Approve except or Reject).';
begin
  select * into i from pipeline.layer4_review_items where id = p_item;
  if i.id is null or i.status <> 'pending' then return jsonb_build_object('ok', false, 'rule', 'item_not_pending', 'reason', 'The item is no longer waiting.'); end if;
  if i.field_code = 'entry_matrix_change' then return jsonb_build_object('ok', false, 'rule', 'change_of_admitted_table', 'reason', 'A change to an admitted table stays with a person.', 'next_action', decline); end if;
  if i.field_code <> 'entry_matrix_first_run' or i.entity_type <> 'provider' then return jsonb_build_object('ok', false, 'rule', 'not_this_class', 'reason', 'Not an entry-matrix first read.'); end if;
  if i.claimed_at is not null or i.assigned_to is not null then return jsonb_build_object('ok', false, 'rule', 'claimed_by_person', 'reason', 'A person has taken this item.'); end if;
  if exists (select 1 from pipeline.layer4_decisions d where d.review_item_id = i.id) then return jsonb_build_object('ok', false, 'rule', 'decided', 'reason', 'The item already has a decision.'); end if;
  select * into r from pipeline.entry_matrix_runs where review_item_id = i.id;
  if r.id is null then return jsonb_build_object('ok', false, 'rule', 'no_run', 'reason', 'No read is linked to this item.', 'next_action', decline); end if;
  select * into f from pipeline.entry_matrix_sources where id = r.source_id;
  v_checks := jsonb_build_object('run_id', r.id, 'source_id', f.id, 'source_url', f.url, 'content_hash', r.content_hash, 'evidence_id', f.evidence_id);
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = i.entity_id and l.field in ('entry_requirements', 'all')) then
    return jsonb_build_object('ok', false, 'rule', 'manual_lock', 'reason', 'The provider''s entry requirements are locked by a person.', 'next_action', decline, 'checks', v_checks); end if;
  -- protected rejection: a person rejected or returned an earlier read of THIS source (a provider that publishes one page per country keeps its other pages on their merits)
  if exists (select 1 from pipeline.layer4_review_items o where o.entity_id = i.entity_id and o.field_code like 'entry_matrix%' and o.id <> i.id
               and o.status in ('rejected', 'more_evidence', 'returned_layer2', 'returned_layer3')
               and (o.layer2_state->>'entry_matrix_source_id' = f.id::text or o.proposed_value->>'url' = f.url)) then
    return jsonb_build_object('ok', false, 'rule', 'earlier_rejection', 'reason', 'A person rejected or returned an earlier entry-matrix read of this source.', 'next_action', decline, 'checks', v_checks); end if;
  if f.evidence_id is null or not exists (select 1 from pipeline.evidence_artifacts e where e.id = f.evidence_id and e.storage_path is not null) then
    return jsonb_build_object('ok', false, 'rule', 'evidence_missing', 'reason', 'The stored copy of the source is missing.', 'next_action', decline, 'checks', v_checks); end if;
  if r.content_hash is distinct from f.content_hash then
    return jsonb_build_object('ok', false, 'rule', 'stale_copy', 'reason', 'The read is not of the source''s current stored copy.', 'next_action', decline, 'checks', v_checks); end if;
  select p.website into v_web from catalogue.providers p where p.id = i.entity_id;
  v_sh := security.site_host_v1(f.url); v_ph := security.site_host_v1(v_web);
  if v_sh is null or v_ph is null or not (v_sh = v_ph or v_sh like '%.' || v_ph) then
    return jsonb_build_object('ok', false, 'rule', 'source_not_official_host', 'reason', format('The source host %s is not the provider''s own website host %s.', coalesce(v_sh, '?'), coalesce(v_ph, '?')),
                              'next_action', decline, 'checks', v_checks); end if;
  if exists (select 1 from catalogue.providers o where o.id <> i.entity_id and o.lifecycle_status = 'active' and security.site_host_v1(o.website) = v_ph) then
    return jsonb_build_object('ok', false, 'rule', 'host_shared', 'reason', 'Another active provider uses the same website host.', 'next_action', decline, 'checks', v_checks); end if;
  g := security.entry_matrix_gate_v1(r.id, '{}'::uuid[]);
  if g is not null and not coalesce((g->>'complete')::boolean, true) then
    return jsonb_build_object('ok', false, 'rule', 'gate_incomplete', 'reason', 'The read cannot be shown complete (D-R3).', 'next_action', decline, 'checks', v_checks || jsonb_build_object('gate', g)); end if;
  if coalesce(r.result->'completeness'->>'status', 'missing') in ('incomplete', 'unparsed')
     or (security.entry_completeness_required_v1(i.entity_id) and coalesce(r.result->'completeness'->>'status', 'missing') <> 'complete') then
    return jsonb_build_object('ok', false, 'rule', 'completeness', 'reason', 'The read has not passed the completeness guard.', 'next_action', decline, 'checks', v_checks); end if;
  select count(*) into v_nm from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed';
  select count(*) into v_nq from catalogue.provider_qualification_requirements q where q.run_id = r.id and q.status = 'proposed';
  if v_nm + v_nq = 0 then return jsonb_build_object('ok', false, 'rule', 'no_rows', 'reason', 'The read proposes no row.', 'next_action', decline, 'checks', v_checks); end if;
  -- every row: confidence, quote, destination level, a published minimum (never inferred)
  select x.why into v_bad from (
    select case when coalesce(m.confidence, 0) < v_conf then 'low_confidence' when length(btrim(coalesce(m.quote, ''))) < v_qmin then 'short_quote'
                when m.study_level_id is null then 'level_unmapped'
                when not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null) then 'no_minimum' end why
      from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed'
    union all
    select case when q.applicability = 'unresolved' then 'applicability_unresolved' when coalesce(q.confidence, 0) < v_conf then 'low_confidence'
                when length(btrim(coalesce(q.quote, ''))) < v_qmin then 'short_quote' when q.study_level_id is null then 'level_unmapped'
                when not ((q.min_value is not null and coalesce(q.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(q.min_grade, '')), '') is not null) then 'no_minimum' end
      from catalogue.provider_qualification_requirements q where q.run_id = r.id and q.status = 'proposed') x
   where x.why is not null limit 1;
  if v_bad is not null then return jsonb_build_object('ok', false, 'rule', 'row_' || v_bad, 'reason', 'At least one proposed row fails ' || v_bad || '.', 'next_action', decline,
                                                       'checks', v_checks || jsonb_build_object('rows', v_nm, 'qualification_rows', v_nq)); end if;
  if exists (select 1 from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed' group by m.row_hash having count(*) > 1)
     or exists (select 1 from catalogue.provider_qualification_requirements q where q.run_id = r.id and q.status = 'proposed' group by q.qualification_code, q.level_label having count(*) > 1) then
    return jsonb_build_object('ok', false, 'rule', 'duplicate_identity', 'reason', 'Two proposed rows share one identity.', 'next_action', decline, 'checks', v_checks); end if;
  if exists (select 1 from catalogue.provider_entry_matrix p join catalogue.provider_entry_matrix a on a.row_hash = p.row_hash and a.status = 'active' and a.id <> p.id
              where p.run_id = r.id and p.status = 'proposed' and a.source_id is distinct from r.source_id)
     or exists (select 1 from catalogue.provider_qualification_requirements p join catalogue.provider_qualification_requirements a
                  on a.provider_id = p.provider_id and a.qualification_code = p.qualification_code and a.level_label is not distinct from p.level_label and a.status = 'active'
              where p.run_id = r.id and p.status = 'proposed' and a.source_id is distinct from r.source_id) then
    return jsonb_build_object('ok', false, 'rule', 'conflicting_active', 'reason', 'A proposed row has the identity of an active row from another source.', 'next_action', decline, 'checks', v_checks); end if;
  v_checks := v_checks || jsonb_build_object('rows', v_nm, 'qualification_rows', v_nq, 'host', v_sh, 'min_confidence', v_conf);
  if abs(hashtext(i.id::text)) % 100 < v_pct then  -- fixed: a per cent sample
    return jsonb_build_object('ok', false, 'audit', true, 'rule', 'audit_sample', 'reason', 'Chosen for the audit sample: a person checks this passing item.', 'next_action', decline, 'checks', v_checks); end if;
  return jsonb_build_object('ok', true, 'rule', 'aer-matrix-machine-v1', 'checks', v_checks);
end $f$;
comment on function security.aer_matrix_machine_check_v1(uuid) is 'CF-247 F-AER.04 (decision D1): rule aer-matrix-machine-v1 for one entry-matrix Layer 4 item: ok only for a never-decided first read of the provider''s own official source whose every row is source-proved with a published minimum, mapped level and explicit applicability; otherwise the reason it stays with a person. Read only.';

create or replace function security.aer_matrix_machine_effective_v1() returns int
language sql stable security definer set search_path = '' as $f$
  -- 2 only with mode 2, a passing validation from the last 7 days, and neither suspension switch on; otherwise the mode, at most 1
  select case when security.pipeline_num_v1('aer.matrix_machine_mode', 0) >= 2
               and exists (select 1 from pipeline.aer_matrix_machine_validations x where x.passed and x.validated_at > now() - interval '7 days')  -- fixed: a validation is valid for 7 days
               and security.pipeline_num_v1('aer.machine_suspended', 0) < 1 then 2
              else least(security.pipeline_num_v1('aer.matrix_machine_mode', 0)::int, 1) end
$f$;

create or replace function security.aer_matrix_machine_admit_v1(p_item uuid, p_via text default 'run') returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare i pipeline.layer4_review_items%rowtype; v jsonb; v_mode int := security.aer_matrix_machine_effective_v1(); v_res jsonb; v_dec uuid; v_reason text; v_out text;
        v_sys uuid := security.system_actor_id(); v_run uuid; v_after int;
        v_ref constant text := 'CF-247 F-AER.04; Platform Admin decision D1 11 Nov 2026 (machine admission of source-verified country tables and qualification rows)';
begin
  if v_mode < 1 then return jsonb_build_object('ok', false, 'rule', 'matrix_machine_off'); end if;
  if v_mode >= 2 then
    select * into i from pipeline.layer4_review_items where id = p_item for update skip locked;
    if i.id is null then return jsonb_build_object('ok', false, 'rule', 'item_locked'); end if;
  else
    select * into i from pipeline.layer4_review_items where id = p_item;
  end if;
  v := security.aer_matrix_machine_check_v1(p_item);
  v_run := nullif(v->'checks'->>'run_id', '')::uuid;
  v_out := case when coalesce((v->>'ok')::boolean, false) then (case when v_mode >= 2 then 'admitted' else 'would_admit' end)
                when coalesce((v->>'audit')::boolean, false) then 'audit_sample' else 'declined' end;
  if v_mode < 2 then
    insert into pipeline.aer_matrix_machine_admissions (review_item_id, provider_id, run_id, mode, outcome, reason_code, reason, checks, actor)
    values (p_item, i.entity_id, v_run, 'shadow', v_out, v->>'rule', v->>'reason', coalesce(v->'checks', '{}'::jsonb), v_sys)
    on conflict (review_item_id) where mode = 'shadow' do update set outcome = excluded.outcome, reason_code = excluded.reason_code, reason = excluded.reason,
           checks = excluded.checks, run_id = excluded.run_id, updated_at = now();
    return jsonb_build_object('ok', true, 'mode', 'shadow', 'outcome', v_out, 'rule', v->>'rule');
  end if;
  if v_out <> 'admitted' then
    if v->>'rule' not in ('item_not_pending', 'not_this_class', 'claimed_by_person', 'decided') then
      update pipeline.layer4_review_items set escalation_reason = left('Machine rule aer-matrix-machine-v1 did not admit this: ' || (v->>'rule') || '. '
               || regexp_replace(coalesce(escalation_reason, ''), '^Machine rule aer-matrix-machine-v1[^:]*: [a-z0-9_]+\. ', ''), 1000)  -- fixed: the column shows 1000 characters
       where id = p_item and status = 'pending' and coalesce(escalation_reason, '') not like 'Machine rule aer-matrix-machine-v1 did not admit this: ' || (v->>'rule') || '.%';
    end if;
    if not exists (select 1 from pipeline.aer_matrix_machine_admissions m where m.review_item_id = p_item and m.mode = 'admit' and m.outcome = v_out and m.reason_code is not distinct from v->>'rule') then
      insert into pipeline.aer_matrix_machine_admissions (review_item_id, provider_id, run_id, mode, outcome, reason_code, reason, checks, actor)
      values (p_item, i.entity_id, v_run, 'admit', v_out, v->>'rule', v->>'reason', coalesce(v->'checks', '{}'::jsonb), v_sys);
    end if;
    return jsonb_build_object('ok', false, 'mode', 'admit', 'outcome', v_out, 'rule', v->>'rule');
  end if;
  -- admit: the same apply a person's approval uses (D-R3, D4 and the completeness guard run again inside it), then the same records
  v_reason := format('Auto (aer-matrix-machine-v1, %s): first read of the provider''s own source %s (host %s, content hash %s), %s country rows and %s qualification rows, each with an exact quote, a published minimum, a mapped level and confidence at least %s; qualification applicability explicit. Not a person''s decision.',
                     coalesce(p_via, 'run'), coalesce(v->'checks'->>'source_url', ''), v->'checks'->>'host', left(coalesce(v->'checks'->>'content_hash', ''), 12),
                     v->'checks'->>'rows', v->'checks'->>'qualification_rows', v->'checks'->>'min_confidence');  -- fixed: a short hash prefix for reading; the full hash is in the ledger
  v_res := security.entry_matrix_review_apply_v1(p_item, 'approve', jsonb_build_object('reviewer', 'aer-matrix-machine-v1'), v_reason);
  select (select count(*) from catalogue.provider_entry_matrix m where m.run_id = v_run and m.status = 'active')
       + (select count(*) from catalogue.provider_qualification_requirements q where q.run_id = v_run and q.status = 'active') into v_after;
  if v_after = 0 or v_after <> coalesce((v_res->>'admitted')::int, 0) + coalesce((v_res->>'qualification_admitted')::int, 0) then
    raise exception 'aer-matrix-machine: read-back found % active rows, apply reported %', v_after, v_res; end if;
  update pipeline.layer4_review_items set status = 'approved', decided_at = now() where id = p_item and status = 'pending';
  insert into pipeline.layer4_decisions (review_item_id, action, actor_id, reason, before_value, proposed_value, final_value, evidence_id, layer2_state, layer3_state, change_control_ref)
  values (i.id, 'approve', v_sys, v_reason, i.before_value, i.proposed_value, i.proposed_value, i.evidence_id,
          coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('machine_rule', 'aer-matrix-machine-v1', 'actor_kind', 'machine', 'via', coalesce(p_via, 'run')), coalesce(i.layer3_state, '{}'::jsonb), v_ref)
  returning id into v_dec;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'aer_approve', 'pipeline.layer4_review_items', jsonb_build_object('review_item_id', i.id, 'decision_id', v_dec, 'kind', i.field_code, 'reason', v_reason,
          'result', v_res, 'auto', true, 'machine_rule', 'aer-matrix-machine-v1', 'actor_kind', 'machine'), v_sys);
  insert into pipeline.search_refresh_signals(entity_type, entity_id, review_decision_id, reason, change_control_ref)
  values ('provider', i.entity_id, v_dec, 'Accepted machine-rule Layer 4 canonical change: ' || v_reason, v_ref);
  insert into pipeline.aer_matrix_machine_admissions (review_item_id, provider_id, run_id, mode, outcome, reason_code, reason, checks, rows_admitted, decision_id, actor)
  values (i.id, i.entity_id, v_run, 'admit', 'admitted', 'aer-matrix-machine-v1', v_reason, coalesce(v->'checks', '{}'::jsonb) || jsonb_build_object('apply', v_res, 'via', coalesce(p_via, 'run')),
          v_after, v_dec, v_sys);
  return jsonb_build_object('ok', true, 'mode', 'admit', 'outcome', 'admitted', 'decision_id', v_dec, 'rows', v_after);
end $f$;
comment on function security.aer_matrix_machine_admit_v1(uuid, text) is 'CF-247 F-AER.04 (decision D1): rule aer-matrix-machine-v1 on one entry-matrix item: in shadow records what it would do; in admit mode (mode 2 with a passing validation) admits through security.entry_matrix_review_apply_v1 with the Layer 4 decision by the system actor (actor_kind machine), control event, search refresh signal and ledger row, or records why the item stays with a person.';

create or replace function security.aer_matrix_machine_run_v1() returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_mode int; v_batch int; v_cap int; v_used int; v_t0 timestamptz := clock_timestamp(); r record; v jsonb; v_n int := 0;
        v_out jsonb := '{}'::jsonb; v_err int := 0;
begin
  -- settings are read inside the block, so an unreadable value is returned as an error like any other, never raised into the calling course run
  v_mode := security.aer_matrix_machine_effective_v1();
  v_batch := security.pipeline_num_v1('batch.aer_matrix_machine', 20)::int;
  v_cap := security.pipeline_num_v1('aer.matrix_machine_daily_max', 40)::int;
  if v_mode < 1 then return jsonb_build_object('mode', 0); end if;
  select count(*) into v_used from pipeline.aer_matrix_machine_admissions where mode = 'admit' and outcome = 'admitted' and created_at > now() - interval '24 hours';  -- fixed: the cap counts the last 24 hours
  for r in select i.id from pipeline.layer4_review_items i
             left join pipeline.aer_matrix_machine_admissions s on s.review_item_id = i.id and s.mode = 'shadow'
            where i.status = 'pending' and i.field_code in ('entry_matrix_first_run', 'entry_matrix_change')
              and (v_mode >= 2 or s.id is null or s.updated_at < now() - interval '6 hours')  -- fixed: an unchanged item is looked at again after 6 hours in shadow
              and not (v_mode >= 2 and exists (select 1 from pipeline.aer_matrix_machine_admissions a where a.review_item_id = i.id and a.mode = 'admit' and a.created_at > now() - interval '6 hours'))
            order by (s.id is null) desc, i.created_at
            limit v_batch loop
    exit when clock_timestamp() - v_t0 > interval '40 seconds';  -- fixed: a run stays inside the job's time
    exit when v_mode >= 2 and v_used >= v_cap;
    begin
      v := security.aer_matrix_machine_admit_v1(r.id, 'run');
      v_n := v_n + 1;
      v_out := jsonb_set(v_out, array[coalesce(v->>'outcome', v->>'rule', 'unknown')], to_jsonb(coalesce((v_out->>coalesce(v->>'outcome', v->>'rule', 'unknown'))::int, 0) + 1));
      if v->>'outcome' = 'admitted' then v_used := v_used + 1; end if;
    exception when others then v_err := v_err + 1;
    end;
  end loop;
  return jsonb_build_object('mode', v_mode, 'checked', v_n, 'outcomes', v_out, 'errors', v_err, 'admitted_24h', v_used, 'cap', v_cap);
exception when others then
  return jsonb_build_object('error', left(sqlerrm, 300));  -- isolated: the matrix class never breaks the course run that calls it
end $f$;
comment on function security.aer_matrix_machine_run_v1() is 'CF-247 F-AER.04 (decision D1): one step of rule aer-matrix-machine-v1 over the waiting entry-matrix items (batch.aer_matrix_machine a run, aer.matrix_machine_daily_max a day), called by security.aer_machine_run_v1 (job aer-machine-admission); errors are returned, never raised.';

create or replace function security.aer_matrix_machine_validate_v1() returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_min int := security.pipeline_num_v1('aer.matrix_machine_min_shadow', 20)::int; v_conf numeric := security.pipeline_num_v1('aer.matrix_machine_min_confidence', 0.9);
        v_qmin int := security.pipeline_num_v1('aer.machine_min_quote_chars', 8)::int; v_n int; v_would int; v_regress int := 0; r record; v_c jsonb; v_hist jsonb; v_pass boolean; v_detail jsonb;
begin
  select count(*), count(*) filter (where outcome = 'would_admit') into v_n, v_would from pipeline.aer_matrix_machine_admissions where mode = 'shadow';
  -- independent re-check of every current would-admit item
  for r in select m.review_item_id from pipeline.aer_matrix_machine_admissions m join pipeline.layer4_review_items i on i.id = m.review_item_id and i.status = 'pending'
            where m.mode = 'shadow' and m.outcome = 'would_admit' loop
    v_c := security.aer_matrix_machine_check_v1(r.review_item_id);
    if not coalesce((v_c->>'ok')::boolean, false) and coalesce(v_c->>'rule', '') not in ('audit_sample', 'claimed_by_person', 'item_not_pending') then v_regress := v_regress + 1; end if;
  end loop;
  -- agreement with past human matrix decisions: would the row rules have admitted the read a person decided, and did the person approve it unchanged?
  with h as (select i.id, d.action, emr.id run_id from pipeline.layer4_decisions d join pipeline.layer4_review_items i on i.id = d.review_item_id
              join pipeline.entry_matrix_runs emr on emr.review_item_id = i.id
             where i.field_code = 'entry_matrix_first_run' and d.actor_id is distinct from security.system_actor_id()),
  x as (select h.id, h.action,
               not exists (select 1 from catalogue.provider_entry_matrix m where m.run_id = h.run_id
                             and (coalesce(m.confidence, 0) < v_conf or length(btrim(coalesce(m.quote, ''))) < v_qmin or m.study_level_id is null
                                  or not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null)))
               and exists (select 1 from catalogue.provider_entry_matrix m where m.run_id = h.run_id) would
          from h)
  select jsonb_build_object('human_decisions', count(*), 'rule_would_admit', count(*) filter (where would),
           'rule_would_admit_and_human_approved', count(*) filter (where would and action = 'approve'),
           'rule_would_admit_but_human_edited_or_refused', count(*) filter (where would and action <> 'approve'),
           'disagreements', coalesce(jsonb_agg(jsonb_build_object('item', id, 'action', action)) filter (where would and action <> 'approve'), '[]'::jsonb)) into v_hist from x;
  v_pass := v_n >= v_min and v_regress = 0
            and coalesce((v_hist->>'rule_would_admit_but_human_edited_or_refused')::int, 1) <= greatest(0, ((v_hist->>'rule_would_admit')::int) / 50);  -- fixed: at most 2% disagreement, none on a small history
  v_detail := jsonb_build_object('shadow_results', v_n, 'shadow_would_admit', v_would, 'shadow_min', v_min, 'regressions_on_recheck', v_regress, 'history', v_hist);
  insert into pipeline.aer_matrix_machine_validations(passed, detail, validated_by) values (v_pass, v_detail, auth.uid());
  return v_detail || jsonb_build_object('passed', v_pass, 'note', 'A pass does not switch admission on. A person (or the Integration Controller under the Platform Admin decision) sets aer.matrix_machine_mode to 2 with a reason.');
end $f$;
comment on function security.aer_matrix_machine_validate_v1() is 'CF-247 F-AER.04 (decision D1): validates rule aer-matrix-machine-v1 (enough shadow results, every would-admit item re-checked, agreement with past human matrix decisions: at most 2%, none on a history under 50 rule admits) and records it. A pass switches nothing on.';

create or replace function security.aer_matrix_machine_withdraw_v1(p_item uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare a pipeline.aer_matrix_machine_admissions%rowtype; v_off int; v_back int; v_qoff int; v_qback int;
begin
  if length(btrim(coalesce(p_reason, ''))) < 5 then raise exception 'reason required'; end if;
  select * into a from pipeline.aer_matrix_machine_admissions where review_item_id = p_item and mode = 'admit' and outcome = 'admitted' and withdrawn_at is null order by id desc limit 1 for update;
  if a.id is null then return jsonb_build_object('ok', false, 'why', 'no machine admission to withdraw'); end if;
  update catalogue.provider_entry_matrix set status = 'inactive', status_reason = 'machine admission withdrawn: ' || p_reason, updated_at = now() where run_id = a.run_id and status = 'active';
  get diagnostics v_off = row_count;
  update catalogue.provider_entry_matrix set status = 'active', status_reason = null, updated_at = now() where status = 'superseded' and status_reason = 'replaced by run ' || a.run_id;
  get diagnostics v_back = row_count;
  update catalogue.provider_qualification_requirements set status = 'inactive', status_reason = 'machine admission withdrawn: ' || p_reason, updated_at = now() where run_id = a.run_id and status = 'active';
  get diagnostics v_qoff = row_count;
  update catalogue.provider_qualification_requirements set status = 'active', status_reason = null, updated_at = now() where status = 'superseded' and status_reason = 'replaced by run ' || a.run_id;
  get diagnostics v_qback = row_count;
  update pipeline.aer_matrix_machine_admissions set withdrawn_at = now(), withdrawn_reason = p_reason, updated_at = now() where id = a.id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'aer_machine_withdraw', 'pipeline.layer4_review_items', jsonb_build_object('review_item_id', p_item, 'rule', 'aer-matrix-machine-v1', 'reason', p_reason,
          'rows_withdrawn', v_off + v_qoff, 'rows_restored', v_back + v_qback), auth.uid());
  insert into pipeline.search_refresh_signals(entity_type, entity_id, review_decision_id, reason, change_control_ref)
  values ('provider', a.provider_id, a.decision_id, 'Machine admission withdrawn: ' || p_reason, 'CF-247 F-AER.04');
  return jsonb_build_object('ok', true, 'rows_withdrawn', v_off + v_qoff, 'rows_restored', v_back + v_qback);
end $f$;
comment on function security.aer_matrix_machine_withdraw_v1(uuid, text) is 'CF-247 F-AER.04 (decision D1): reverses an aer-matrix-machine-v1 admission: the read''s active rows become inactive, rows it replaced become active again, the ledger and a control event record it.';

revoke all on function security.aer_matrix_machine_check_v1(uuid), security.aer_matrix_machine_effective_v1(), security.aer_matrix_machine_admit_v1(uuid, text),
                       security.aer_matrix_machine_run_v1(), security.aer_matrix_machine_validate_v1(), security.aer_matrix_machine_withdraw_v1(uuid, text) from public, anon, authenticated;

-- the existing job steps the class ------------------------------------------------------------------------------------------------------------
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.aer_machine_run_v1()', 'ad143b44722ba6fbc0129cd38386661c', 'f88ab3f16833dec601786af5c7cdbbcc',
     array[$o$  if v_mode < 1 then return jsonb_build_object('mode', 0); end if;$o$,
           $o$                            'checked', v_n, 'outcomes', v_out, 'errors', v_err, 'admitted_24h', v_used, 'cap', v_cap, 'suspension', v_susp);$o$],
     array[$n$  -- 12 Nov 2026 (F-AER.04, decision D1): with course admission off the job still steps the matrix class, which has its own switch (aer.matrix_machine_mode)
  if v_mode < 1 then return jsonb_build_object('mode', 0, 'matrix', security.aer_matrix_machine_run_v1()); end if;$n$,
           $n$                            'checked', v_n, 'outcomes', v_out, 'errors', v_err, 'admitted_24h', v_used, 'cap', v_cap, 'suspension', v_susp)
         -- 12 Nov 2026 (F-AER.04, decision D1): the same job steps rule aer-matrix-machine-v1 (country tables and qualification rows); its own ledger, errors returned, never raised
         || jsonb_build_object('matrix', security.aer_matrix_machine_run_v1());$n$])
  ) v(sig, md5_before, md5_after, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then raise notice '%: already applied', r.sig; continue; end if;
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
    raise notice '%: applied', r.sig;
  end loop;
end $m$;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.aer_matrix_machine_admissions', 'Layer 4', 'Ledger of rule aer-matrix-machine-v1 (country tables and qualification rows): shadow, admissions, declines, audit samples, withdrawals', 'active', '{}', '20261112093700'),
 ('table', 'pipeline.aer_matrix_machine_validations', 'Layer 4', 'Validations of rule aer-matrix-machine-v1', 'active', '{}', '20261112093700'),
 ('function', 'security.aer_matrix_machine_check_v1', 'Layer 4', 'Rule aer-matrix-machine-v1 for one entry-matrix item (read only)', 'active', '{}', '20261112093700'),
 ('function', 'security.aer_matrix_machine_admit_v1', 'Layer 4', 'Shadow or admit one entry-matrix item through the person''s apply, with the machine records', 'active', '{}', '20261112093700'),
 ('function', 'security.aer_matrix_machine_withdraw_v1', 'Layer 4', 'Reverse an aer-matrix-machine-v1 admission', 'active', '{}', '20261112093700')
on conflict do nothing;

do $post$ begin
  if position('aer_matrix_machine_run_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_machine_run_v1()'::regprocedure)) = 0 then raise exception 'post-check: the job does not step the class'; end if;
  if security.aer_matrix_machine_effective_v1() >= 2 then raise exception 'post-check: the class must ship in shadow'; end if;
end $post$;
