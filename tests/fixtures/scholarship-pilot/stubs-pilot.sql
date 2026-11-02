-- CF-247 scholarships beyond universities: what the pilot functions read in addition to the scholarship-recovery stubs (live columns,
-- information_schema on fxcwkweaxjtknorudmwp, read 3 Nov 2026 08:49-09:08 AEDT). No live data.
alter table pipeline.scholarship_admission_log add column if not exists id bigserial;
alter table pipeline.scholarship_admission_log add column if not exists at timestamptz not null default now();
create table pipeline.scholarship_ai_extractions(id bigserial primary key, candidate_id bigint, scholarship_id uuid, provider_id uuid, url text, cost_usd numeric, at timestamptz not null default now());
create table pipeline.layer4_block_decisions(id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, block_scope text, event_type text, reason_code text,
  comment text, created_at timestamptz default now());
create table pipeline.layer4_publication_decisions(id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, target_scope text, event_type text, reason_code text,
  comment text, created_at timestamptz default now());
insert into pipeline.platform_toolsets values ('openrouter') on conflict do nothing;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values
  ('openrouter', 'guard_scholarship_ai', 'Scholarship AI a day', 'number', '20'),   -- live 3 Nov 2026
  ('pipeline', 'reread.scholarship_candidate_days', 'Candidate re-read', 'number', '90')
on conflict do nothing;
