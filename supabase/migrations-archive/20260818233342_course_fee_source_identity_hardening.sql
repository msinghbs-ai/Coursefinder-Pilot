alter table catalogue.course_fees
  add column if not exists campus_id uuid references catalogue.campuses(id) on delete set null,
  add column if not exists source_fee_key text,
  add column if not exists status text not null default 'active',
  add column if not exists last_verified_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

alter table catalogue.course_fees
  drop constraint if exists course_fees_status_check;
alter table catalogue.course_fees
  add constraint course_fees_status_check check (status in ('active','inactive','superseded','unverified'));

alter table catalogue.course_fees
  drop constraint if exists course_fees_valid_range_check;
alter table catalogue.course_fees
  add constraint course_fees_valid_range_check check (valid_to is null or valid_from is null or valid_to >= valid_from);

create index if not exists course_fees_campus_idx on catalogue.course_fees(campus_id);
create index if not exists course_fees_source_idx on catalogue.course_fees(source_id);
create index if not exists course_fees_evidence_idx on catalogue.course_fees(evidence_id);
create index if not exists course_fees_course_status_idx on catalogue.course_fees(course_id,status);
create unique index if not exists course_fees_source_identity_uidx
  on catalogue.course_fees(course_id,source_id,source_fee_key)
  where source_id is not null and source_fee_key is not null;

comment on column catalogue.course_fees.source_fee_key is 'Stable source-local fee observation key used for Layer 2 replay/idempotency. It is not Course identity.';
comment on column catalogue.course_fees.campus_id is 'Optional campus scope only when the authoritative fee source explicitly differentiates fees by campus/location; null means no such scoped distinction is asserted.';
comment on table catalogue.course_fees is 'Temporal evidence-backed Course fee observations. Layer 1 regulatory ingestion does not fabricate fee facts; authoritative/provider Layer 2 sources populate this relation.';
