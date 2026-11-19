create unique index if not exists evidence_standard_group_hash_uq on pipeline.evidence_artifacts (evidence_group_key, content_hash) where retention_class = 'standard_365' and evidence_group_key is not null and content_hash is not null;
create index if not exists layer2_run_batches_status_created_idx on pipeline.layer2_run_batches(status, created_at desc);
create index if not exists layer2_run_items_batch_status_idx on pipeline.layer2_run_items(batch_id, status);
create table if not exists pipeline.evidence_capacity_policy (
  id boolean primary key default true check (id),
  planning_capacity_bytes bigint not null check (planning_capacity_bytes > 0),
  warn_pct numeric not null default 60 check (warn_pct > 0 and warn_pct < 100),
  high_pct numeric not null default 75 check (high_pct > warn_pct and high_pct < 100),
  critical_pct numeric not null default 90 check (critical_pct > high_pct and critical_pct <= 100),
  capacity_basis text not null,
  change_control_ref text not null,
  updated_at timestamptz not null default now()
);
insert into pipeline.evidence_capacity_policy(id, planning_capacity_bytes, warn_pct, high_pct, critical_pct, capacity_basis, change_control_ref)
values (true, 64424509440, 60, 75, 90, 'M2 planning envelope 60 GiB; operational planning threshold, not vendor hard quota', 'CF-CHG-20260825-036')
on conflict (id) do update set planning_capacity_bytes=excluded.planning_capacity_bytes,warn_pct=excluded.warn_pct,high_pct=excluded.high_pct,critical_pct=excluded.critical_pct,capacity_basis=excluded.capacity_basis,change_control_ref=excluded.change_control_ref,updated_at=now();
