-- CF-247 (19 Oct 2026). Platform Admin 20:33: "refresh plan for evidence, plan and execute the next steps" (step: remove evidence files
-- that no record uses).
-- pipeline.orphan_files lists, once, the files in the evidence bucket saved before 19 Oct 2026 that no record names: course-page files
-- (layer2/<country>/coverage), adapter-builder captures whose draft is gone (layer2/<country>/adapters) and scholarship page files
-- (layer2/<country>/scholarships). "Names" means any of the 19 file-path columns, the register replay path lists, or a kept copy in the
-- dedupe log. Working out that list inside one query took longer than the time limit, so it is worked out here once, in steps; the
-- archive export reads this list, and the paste file that removes the files checks every one again first.
-- Replaces: nothing
-- Retires: nothing (the table is marked retiring once the files are removed)
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

create table if not exists pipeline.orphan_files (
  name text primary key,
  object_id uuid not null,
  kind text not null check (kind in ('course_page', 'adapter_capture', 'scholarship_page')),
  bytes bigint,
  saved_at timestamptz,
  listed_at timestamptz not null default now()
);
comment on table pipeline.orphan_files is 'CF-247 (19 Oct 2026): evidence-bucket files no record names (course pages, adapter captures of drafts that are gone, scholarship pages), listed once for archive and removal by paste file.';
alter table pipeline.orphan_files enable row level security;

set local statement_timeout = '10min';  -- fixed: one-off listing of 194,000 Storage records against 21 path lists
create temp table used_paths on commit drop as
select storage_path p from pipeline.evidence_artifacts where storage_path is not null
union select storage_path from catalogue.provider_assets union select storage_path from pipeline.admin_job_items union select storage_path from pipeline.course_companion_pages
union select storage_path from pipeline.coverage_identity_cases union select storage_path from pipeline.directory_pages union select storage_path from pipeline.evidence_lineage_reconciliations
union select keeper_path from pipeline.evidence_storage_dedupe_log where status <> 'deleted' union select storage_path from pipeline.field_enrich_items
union select storage_path from pipeline.provider_contact_import_batches union select storage_path from pipeline.reference_institutions union select storage_path from pipeline.register_replay_runs
union select unnest(paths) from pipeline.register_replay_runs union select storage_path from pipeline.rule6_page_checks union select storage_path from pipeline.scholarship_ai_extractions
union select storage_path from pipeline.scholarship_ai_queue union select storage_path from pipeline.scholarship_ai_reviews union select storage_path from pipeline.scholarship_page_candidates
union select storage_path from ranking.manual_imports union select storage_path from workflow.export_jobs union select storage_path from workflow.import_jobs;
create index on used_paths (p);
analyze used_paths;

insert into pipeline.orphan_files(name, object_id, kind, bytes, saved_at)
select o.name, o.id, case split_part(o.name, '/', 3) when 'coverage' then 'course_page' when 'adapters' then 'adapter_capture' else 'scholarship_page' end,
       (o.metadata->>'size')::bigint, o.created_at
  from storage.objects o left join used_paths u on u.p = o.name
 where o.bucket_id = 'evidence' and o.created_at < timestamptz '2026-10-19 00:00:00+00' and u.p is null
   and split_part(o.name, '/', 1) = 'layer2' and split_part(o.name, '/', 3) in ('coverage', 'adapters', 'scholarships')
   and not (split_part(o.name, '/', 3) = 'adapters' and exists (select 1 from pipeline.uni_adapter_drafts d where d.id::text = split_part(o.name, '/', 5)))
on conflict (name) do nothing;

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.orphan_files', 'Operations', 'Evidence files no record names, listed once for archive and removal', 'active', '20261019090000')
on conflict (kind, name) do nothing;

do $post$
begin
  if (select count(*) from pipeline.orphan_files) < 20000 then raise exception 'post-check: fewer files listed than measured (about 28,800)'; end if;  -- fixed: the measured size
end $post$;
