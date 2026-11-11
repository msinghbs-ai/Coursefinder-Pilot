-- CF-247 F-AER.04 D3 fixture: what attach, check and upload read, beyond tests/fixtures/aer-qualification-first and aer-matrix-machine stubs (shapes as live, fewer columns)
alter table catalogue.providers add column if not exists website text, add column if not exists country_id uuid;
alter table pipeline.entry_matrix_sources add column if not exists title text, add column if not exists rank int default 1, add column if not exists found_via text,
  add column if not exists http_status int, add column if not exists content_hash text, add column if not exists attempts int default 0, add column if not exists read_at timestamptz,
  add column if not exists error text, add column if not exists created_at timestamptz default now(), add column if not exists updated_at timestamptz default now();
alter table pipeline.entry_matrix_sources alter column status set default 'found';
alter table pipeline.entry_matrix_sources add constraint fx_src_unique unique (provider_id, url), add constraint fx_found_via check (found_via in ('search', 'manual')),
  add constraint fx_read_via check (read_via in ('stored', 'direct', 'firecrawl')),
  add constraint fx_status check (status in ('found', 'reading', 'read', 'failed', 'robots_disallowed', 'pdf_step_b', 'inactive'));
alter table pipeline.entry_matrix_runs add column if not exists content_hash text;
create unique index if not exists fx_runs_src_hash on pipeline.entry_matrix_runs (source_id, content_hash);
alter table pipeline.evidence_artifacts add column if not exists content_hash text, add column if not exists source_url text, add column if not exists source_id uuid, add column if not exists mime_type text;
create table pipeline.fx_caller (uid uuid, rank int, role text);
insert into pipeline.fx_caller values ('00000000-0000-0000-0000-0000000000a1', 7, null);
create or replace function auth.uid() returns uuid language sql stable as $$ select uid from pipeline.fx_caller $$;
create or replace function auth.role() returns text language sql stable as $$ select role from pipeline.fx_caller $$;
create or replace function security.current_role_rank() returns int language sql stable as $$ select rank from pipeline.fx_caller $$;
create or replace function security.third_party_host_v1(p text) returns boolean language sql immutable as $$ select p ~* 'directory\.example' $$;
create or replace function security.entry_matrix_enabled_v1(p uuid) returns boolean language sql stable as $$ select true $$;
create or replace function security.coverage_sweep_source(p uuid) returns uuid language sql stable as $$ select '00000000-0000-0000-0000-0000000000cc'::uuid $$;
create or replace function public.svc_coursefacts_register_evidence(p_src uuid, p_url text, p_path text, p_sha text, p_mime text, p_meta jsonb) returns uuid language sql as $$
  insert into pipeline.evidence_artifacts(source_id, source_url, storage_path, content_hash, mime_type) values (p_src, p_url, p_path, p_sha, p_mime) returning id $$;
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values ('pipeline', 'entry.matrix_enabled', '1'), ('pipeline', 'entry.pdf_enabled', '1'), ('pipeline', 'entry.pdf_max_bytes', '1000');
