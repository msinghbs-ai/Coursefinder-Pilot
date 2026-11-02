-- D-R2/D-R3 fixtures (CF-247, Platform Admin direction 2 Nov 2026 23:24): what the E13 fixture database (../e13-completeness-gate/stubs.sql)
-- lacks for the matrix gate, the matrix approval and the supersession path: the columns and tables they read, as live has them. Run on a
-- scratch PostgreSQL only (never on a Supabase project): see run.sh. Nothing here is a copy of live data.
alter table pipeline.layer4_review_items add column if not exists assigned_to uuid, add column if not exists claimed_at timestamptz, add column if not exists decided_at timestamptz;
alter table pipeline.entry_matrix_runs add column if not exists provider_id uuid, add column if not exists source_id uuid, add column if not exists content_hash text,
  add column if not exists state text default 'done', add column if not exists rows_admitted int, add column if not exists rows_dropped int, add column if not exists result jsonb default '{}'::jsonb;
alter table catalogue.provider_entry_matrix add column if not exists provider_id uuid, add column if not exists source_id uuid, add column if not exists row_hash text,
  add column if not exists min_value numeric, add column if not exists course_label text, add column if not exists updated_at timestamptz default now();
create table pipeline.entry_matrix_sources(id uuid primary key, provider_id uuid, url text, content_hash text, status text default 'read');
create table pipeline.manual_locks(entity text, entity_id uuid, field text);
create table pipeline.admin_jobs(id uuid primary key default gen_random_uuid());
-- live helpers the edited matrix approval calls (their behaviour, not their code: they are not changed by this migration)
create function security.entry_completeness_required_v1(p_provider uuid) returns boolean language sql stable as
  $f$ select coalesce(security.toolset_setting('pipeline', 'entry.completeness_providers'), '[]'::jsonb) ? p_provider::text $f$;
-- the stored-page read request (security.course_entry_read_enqueue_v1): one task with one queued entry_requirements item
create function security.course_entry_read_enqueue_v1(p_course uuid, p_by uuid, p_reason text) returns uuid language plpgsql as $f$
declare v_job uuid := gen_random_uuid();
begin
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state) select v_job, c.provider_id, c.id, 'entry_requirements', 'queued' from catalogue.courses c where c.id = p_course;
  return v_job;
end $f$;
-- the course decision trigger, from 20261028001000 unchanged (run.sh checks its md5 against live)
create or replace function security.course_entry_review_trg_v1() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
  if new.status in ('rejected', 'more_evidence', 'returned_layer2', 'returned_layer3', 'superseded') then
    perform security.course_entry_review_apply_v1(new.id, new.status, null, 'Layer 4 ' || new.status);
  end if;
  return new;
end $$;
create trigger layer4_review_items_course_entry after update of status on pipeline.layer4_review_items
  for each row when (old.status = 'pending' and new.status <> 'pending' and new.field_code = 'course_entry_first_read')
  execute function security.course_entry_review_trg_v1();
