-- CF-247 (19 Oct 2026). Platform Admin 06:34, evidence retention: "Archive, then remove (Recommended)".
-- Older course-page snapshots (evidence type source_snapshot, layer2/<country>/coverage/<provider>/<course>/...) that a newer snapshot of
-- the same course page has replaced: about 68,900 of 104,700. This change only PREPARES their removal; nothing is removed here.
-- 1 pipeline.evidence_purge lists each candidate (the newest snapshot of every course page is never a candidate).
-- 2 Job evidence-purge-prepare checks the candidates in batches (setting batch.evidence_purge_check) against every column in the database
--   that refers to evidence (any uuid column named *evidence_id*, *evidence_artifact_id* or source_artifact_id): a candidate referred to
--   anywhere is kept; the rest are marked checked.
-- 3 When every candidate is checked, the checked rows are exported to the Storage archive (count and row hash) and the Platform Admin
--   removes them with a paste file; their files in the evidence bucket follow through the Storage API.
-- Replaces: nothing
-- Retires: nothing (the job is marked retiring once the removal is done)
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'batch.evidence_purge_check', 'Evidence checked per run (removal of replaced snapshots)', 'Each run of evidence-purge-prepare checks this many candidate snapshots against every column that refers to evidence.', 'number', '3000', 200, 20000, 'snapshots', 321, 'CF-247, Platform Admin 19 Oct 2026 06:34 "Archive, then remove"', 'Storage & retention', 'job evidence-purge-prepare')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.evidence_purge (
  evidence_id uuid primary key,
  storage_path text,
  evidence_type text,
  captured_at timestamptz,
  course_key text,
  state text not null default 'candidate' check (state in ('candidate', 'checked', 'kept')),
  kept_by text,
  checked_at timestamptz,
  added_at timestamptz not null default now()
);
comment on table pipeline.evidence_purge is 'CF-247 (19 Oct 2026): course-page snapshots replaced by a newer snapshot of the same page; candidate, checked (referred to nowhere, ready to archive and remove) or kept (referred to by another table).';
create index if not exists evidence_purge_state_idx on pipeline.evidence_purge (state);
alter table pipeline.evidence_purge enable row level security;

CREATE OR REPLACE FUNCTION security.evidence_purge_prepare_v1(p_batch integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ids uuid[]; r record; v_hit uuid[]; v_seeded int := 0; v_kept int := 0; v_checked int := 0;
begin
  if not exists (select 1 from pipeline.evidence_purge) then
    insert into pipeline.evidence_purge(evidence_id, storage_path, evidence_type, captured_at, course_key)
    select s.id, s.storage_path, s.evidence_type, s.captured_at, s.course
      from (select e.id, e.storage_path, e.evidence_type, e.captured_at, split_part(e.storage_path, '/', 5) course,
                   row_number() over (partition by split_part(e.storage_path, '/', 5) order by e.captured_at desc nulls last, e.id) rn
              from pipeline.evidence_artifacts e
             where e.evidence_type = 'source_snapshot' and e.storage_path like 'layer2/%/coverage/%') s
     where s.rn > 1 and s.course <> ''
    on conflict (evidence_id) do nothing;
    get diagnostics v_seeded = row_count;
    return jsonb_build_object('seeded', v_seeded);
  end if;
  v_ids := array(select p.evidence_id from pipeline.evidence_purge p where p.state = 'candidate' order by p.evidence_id limit greatest(1, coalesce(p_batch, 3000)));
  if cardinality(v_ids) = 0 then return jsonb_build_object('done', true); end if;
  for r in select c.table_schema sch, c.table_name tbl, c.column_name col
             from information_schema.columns c join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
            where c.data_type = 'uuid' and (c.column_name ilike '%evidence_id%' or c.column_name ilike '%evidence_artifact_id%' or c.column_name = 'source_artifact_id')
              and c.table_schema not in ('information_schema', 'pg_catalog')
              and not (c.table_schema = 'pipeline' and c.table_name = 'evidence_purge') loop
    execute format('select array_agg(distinct %I) from %I.%I where %I = any($1)', r.col, r.sch, r.tbl, r.col) into v_hit using v_ids;
    if coalesce(cardinality(v_hit), 0) > 0 then
      update pipeline.evidence_purge set state = 'kept', kept_by = r.sch || '.' || r.tbl || '.' || r.col, checked_at = now()
       where evidence_id = any(v_hit) and state = 'candidate';
      v_ids := array(select x from unnest(v_ids) x where x <> all(v_hit));
    end if;
  end loop;
  update pipeline.evidence_purge set state = 'checked', checked_at = now() where evidence_id = any(v_ids) and state = 'candidate';
  get diagnostics v_checked = row_count;
  return jsonb_build_object('checked', v_checked, 'left', (select count(*) from pipeline.evidence_purge where state = 'candidate'));
end $function$;
revoke execute on function security.evidence_purge_prepare_v1(integer) from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('evidence-purge-prepare', 'Storage & retention', 62, 'Prepare removal of replaced snapshots', 'Every 5 minutes until done: checks replaced course-page snapshots against every column that refers to evidence; nothing is removed by the job.', 5, true)
on conflict (jobname) do nothing;
select cron.schedule('evidence-purge-prepare', '*/5 * * * *', $$select security.evidence_purge_prepare_v1(security.pipeline_num_v1('batch.evidence_purge_check', 3000)::int)$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.evidence_purge', 'Operations', 'Replaced course-page snapshots: candidate, checked or kept, before archive and removal', 'active', '20261019020000'),
 ('job', 'evidence-purge-prepare', 'Operations', 'Checks replaced snapshots for references, in batches', 'active', '20261019020000'),
 ('function', 'security.evidence_purge_prepare_v1', 'Operations', 'Seeds and checks evidence removal candidates', 'active', '20261019020000')
on conflict (kind, name) do nothing;

do $post$
begin
  if not exists (select 1 from cron.job where jobname = 'evidence-purge-prepare') then raise exception 'post-check: job'; end if;
end $post$;
