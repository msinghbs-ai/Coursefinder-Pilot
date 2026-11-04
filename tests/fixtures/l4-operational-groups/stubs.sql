-- CF-247 Layer 4 operational groups fixtures: the readiness table as live (20261104120000 §4; columns read live 4 Nov 2026 17:11 AEDT)
create table if not exists pipeline.layer4_item_readiness (
  item_id uuid primary key references pipeline.layer4_review_items(id),
  entity_type text not null,
  entity_id uuid not null,
  field_code text not null,
  item_created_at timestamptz not null,
  item_status text not null,
  readiness text not null check (readiness in ('judgement_ready', 'technical_blocked', 'resolvable', 'closed')),
  reasons text[] not null default '{}',
  route text not null,
  resolution jsonb,
  blockers jsonb not null default '[]'::jsonb,
  est_minutes numeric,
  gate jsonb,
  gate_checked_at timestamptz,
  classified_at timestamptz not null default now(),
  rule text not null default 'L4R-1'
);
