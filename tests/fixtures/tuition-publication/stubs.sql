-- IQ-00116 tuition publication: isolated fixture database (CF-247, mandate 4 Nov 2026 05:08 §7). Loaded on top of the E16 fixture database
-- (tests/fixtures/e16-binding-validation), whose projection builder is the live one. Adds the columns and tables the Layer 4 tuition apply, the
-- fee rule and the admission check use, with live names. Run on a scratch PostgreSQL only (never on a Supabase project): see run.sh.
-- Nothing here is a copy of live data. Helper functions not under test are simple stand-ins.

-- catalogue (live column names)
alter table catalogue.course_fees add column if not exists notes text, add column if not exists evidence_id uuid, add column if not exists confidence numeric,
  add column if not exists source_fee_key text, add column if not exists source_snapshot_at timestamptz, add column if not exists created_at timestamptz default now();
alter table catalogue.course_fees alter column id set default gen_random_uuid(), alter column updated_at set default now();
create unique index if not exists course_fees_source_key on catalogue.course_fees (course_id, source_id, source_fee_key) where source_id is not null and source_fee_key is not null;
alter table catalogue.courses add column if not exists duration_value numeric, add column if not exists duration_unit text;
alter table pipeline.evidence_artifacts add column if not exists source_id uuid;
alter table pipeline.layer4_review_items add column if not exists layer3_interpretation_id uuid;

-- the search projection (the columns the live builder writes)
alter table search.enrichment_source_gates add column if not exists approval_ref text, add column if not exists approved_at timestamptz,
  add column if not exists created_at timestamptz default now(), add column if not exists updated_at timestamptz default now();
alter table search.enrichment_source_gates add primary key (projection_code, domain_code, source_id);
alter table search.enrichment_source_gates add constraint enrichment_source_gates_gate_status_check check (gate_status in ('approved', 'blocked'));
alter table search.course_documents
  add column if not exists regulatory_tuition_state text, add column if not exists has_regulatory_tuition boolean, add column if not exists regulatory_tuition_amount numeric,
  add column if not exists regulatory_tuition_currency text, add column if not exists regulatory_tuition_basis text, add column if not exists has_provider_current_tuition boolean,
  add column if not exists has_fee boolean, add column if not exists provider_annual_tuition_amount numeric, add column if not exists provider_annual_tuition_currency text,
  add column if not exists provider_tuition_options jsonb not null default '[]', add column if not exists has_link boolean,
  add column if not exists intake_options jsonb not null default '[]', add column if not exists earliest_intake_date date, add column if not exists has_intake boolean,
  add column if not exists english_requirement_options jsonb not null default '[]', add column if not exists has_english boolean,
  add column if not exists scholarship_options jsonb not null default '[]', add column if not exists has_scholarship boolean, add column if not exists enrichment_semantic_text text,
  add column if not exists search_text text, add column if not exists search_tsv tsvector, add column if not exists semantic_content_hash text, add column if not exists projection_version text,
  add column if not exists generated_at timestamptz, add column if not exists updated_at timestamptz, add column if not exists course_title text, add column if not exists provider_name text,
  add column if not exists course_code text, add column if not exists study_level_code text, add column if not exists primary_field_name text, add column if not exists primary_field_code text,
  add column if not exists collection_names text[], add column if not exists academic_option_names text[], add column if not exists description text, add column if not exists course_stable_key text;

-- Layer 4 (live names)
create table pipeline.layer4_decisions(id uuid primary key default gen_random_uuid(), review_item_id uuid, action text, final_value jsonb, created_at timestamptz default now());
create table pipeline.layer4_admission_checks(decision_id uuid primary key, review_item_id uuid, field_code text, entity_type text, entity_id uuid, decided_at timestamptz, result text,
  reason text, admitted boolean, published boolean, lag_seconds numeric, detail jsonb, checked_at timestamptz default now(), checks int default 1);
create function security.layer4_scope_key_v1(p_kind text, p_state jsonb, p_value jsonb) returns text language sql immutable as $f$ select p_kind $f$;
create function security.layer4_url_key_v1(p text) returns text language sql immutable as $f$ select lower(p) $f$;
create function security.fee_evidence_own_site_v1(p_evidence uuid, p_course uuid) returns boolean language sql stable as $f$ select true $f$;

-- workstream A's operations contract: the names this change codes against (stand-in, as common brief "stub-ops-contract")
create table pipeline.ops_root_causes(code text primary key, class text, title text, description text, detect jsonb, created_at timestamptz default now());
create table pipeline.ops_remedies(code text primary key, title text, treats text[], authority text, action_fn regprocedure, verify_fn regprocedure, max_attempts_key text,
  cooldown_key text, active boolean default true, notes text);
create function security.ops_root_cause_register_v1(p_code text, p_spec jsonb) returns jsonb language sql as $f$
  insert into pipeline.ops_root_causes(code, class, title, description, detect) values (p_code, p_spec->>'class', p_spec->>'title', p_spec->>'description', p_spec->'detect')
  on conflict (code) do update set class = excluded.class, title = excluded.title, description = excluded.description, detect = excluded.detect
  returning jsonb_build_object('code', code) $f$;
create function security.ops_remedy_register_v1(p_code text, p_spec jsonb) returns jsonb language sql as $f$
  insert into pipeline.ops_remedies(code, title, treats, authority, action_fn, verify_fn, max_attempts_key, cooldown_key, active, notes)
  values (p_code, p_spec->>'title', array(select jsonb_array_elements_text(p_spec->'treats')), p_spec->>'authority', (p_spec->>'action_fn')::regprocedure,
          (p_spec->>'verify_fn')::regprocedure, p_spec->>'max_attempts_key', p_spec->>'cooldown_key', coalesce((p_spec->>'active')::boolean, true), p_spec->>'notes')
  on conflict (code) do update set title = excluded.title, treats = excluded.treats, authority = excluded.authority, action_fn = excluded.action_fn, verify_fn = excluded.verify_fn,
     max_attempts_key = excluded.max_attempts_key, cooldown_key = excluded.cooldown_key, active = excluded.active, notes = excluded.notes
  returning jsonb_build_object('code', code) $f$;

-- the global gates as live (provider fee and regulatory tuition approved)
insert into search.enrichment_gates values ('courses', 'provider_current_tuition', 'approved'), ('courses', 'regulatory_tuition', 'approved');
