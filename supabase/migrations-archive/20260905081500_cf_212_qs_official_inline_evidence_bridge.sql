create table if not exists pipeline.ranking_inline_evidence_payloads (
  evidence_id uuid primary key references pipeline.evidence_artifacts(id) on delete cascade,
  original_filename text not null,
  mime_type text not null,
  byte_size bigint not null check (byte_size > 0),
  content_hash text not null,
  payload bytea not null,
  created_at timestamptz not null default now(),
  constraint ranking_inline_evidence_hash_chk check (length(content_hash)=64)
);
alter table pipeline.ranking_inline_evidence_payloads enable row level security;
revoke all on pipeline.ranking_inline_evidence_payloads from public, anon, authenticated;
comment on table pipeline.ranking_inline_evidence_payloads is 'Private exact-byte Evidence bridge for authorised ranking files supplied through a control plane that cannot write directly to Storage. Migrate to private Evidence Storage when an upload-capable service route is available; never exposed to browser roles.';
