-- CF-247 Layer 4 action lifecycle fixtures: the production columns the lifecycle reads that the earlier fixture stubs left out (live
-- information_schema read 4 Nov 2026 12:29-12:30 AEDT). Nothing else changes.
alter table pipeline.admin_control_events add column if not exists created_at timestamptz not null default now();
alter table pipeline.aer_read_supersessions add column if not exists closed_at timestamptz;
alter table pipeline.field_enrich_items add column if not exists evidence_id uuid, add column if not exists reason text,
  add column if not exists created_at timestamptz not null default now(), add column if not exists attempts int not null default 0, add column if not exists source text;
alter table pipeline.enrichment_flags add column if not exists released_at timestamptz, add column if not exists next_check_at timestamptz,
  add column if not exists updated_at timestamptz not null default now(), add column if not exists cleared_at timestamptz;
alter table pipeline.provider_onboarding add column if not exists finished_at timestamptz, add column if not exists attempts int not null default 0;
alter table pipeline.data_flags add column if not exists resolved_at timestamptz, add column if not exists resolution jsonb;
alter table pipeline.layer1_provider_departures add column if not exists reviewed_at timestamptz, add column if not exists reviewed_by uuid;
alter table catalogue.course_entry_requirements add column if not exists source_url text;
-- the live D-R2 close (20261103070000): a row moves once from requested to superseded or refused, with its time
create or replace function security.aer_read_supersession_close_v1(p_id uuid, p_state text, p_why text, p_new_item uuid, p_diff jsonb) returns void
language sql security definer set search_path to '' as $f$
  update pipeline.aer_read_supersessions set state = p_state, outcome = left(p_why, 500), new_item_id = p_new_item, closed_at = now() where id = p_id and state = 'requested'
$f$;
