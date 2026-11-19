create table workflow.review_queue (
  id uuid primary key default extensions.gen_random_uuid(),
  entity_id uuid not null references pim.entity_registry(id) on delete cascade,
  domain text not null,
  field_code text,
  candidate_claim_id uuid references pipeline.claims(id),
  previous_review_id uuid references workflow.review_queue(id),
  reopen_reason text,
  priority smallint not null default 50,
  status text not null default 'open' check (status in ('open','in_review','approved','rejected','superseded','closed')),
  assigned_to uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz
);
create index review_queue_status_idx on workflow.review_queue(status,priority desc,created_at);
create index review_queue_entity_idx on workflow.review_queue(entity_id,domain);

create table workflow.review_actions (
  id uuid primary key default extensions.gen_random_uuid(),
  review_id uuid not null references workflow.review_queue(id) on delete cascade,
  action text not null check (action in ('open','assign','approve','reject','edit','reclassify','reopen','supersede','close','comment')),
  actor_id uuid references auth.users(id),
  before_value jsonb,
  after_value jsonb,
  reason text,
  evidence_id uuid references pipeline.evidence_artifacts(id),
  created_at timestamptz not null default now()
);
create index review_actions_review_idx on workflow.review_actions(review_id,created_at);

create table workflow.suggestions (
  id uuid primary key default extensions.gen_random_uuid(),
  entity_id uuid references pim.entity_registry(id),
  submitted_by uuid references auth.users(id),
  source_channel text not null default 'admin',
  suggestion_type text not null,
  payload jsonb not null,
  status text not null default 'submitted',
  review_id uuid references workflow.review_queue(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index suggestions_status_idx on workflow.suggestions(status,created_at);

revoke all on all tables in schema workflow from anon, authenticated;
revoke usage on schema workflow from anon, authenticated;
grant usage on schema workflow to service_role;
grant all on all tables in schema workflow to service_role;
