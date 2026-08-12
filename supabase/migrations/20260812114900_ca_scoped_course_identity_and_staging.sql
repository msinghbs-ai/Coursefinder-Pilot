create table if not exists catalogue.course_identifiers (
  id uuid primary key default extensions.gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  scheme text not null,
  identifier text not null,
  country_id uuid references ref.countries(id),
  issuing_authority text,
  is_primary boolean not null default false,
  source_id uuid references pipeline.sources(id),
  evidence_id uuid references pipeline.evidence_artifacts(id),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  unique (provider_id, scheme, identifier)
);
create index if not exists idx_course_identifiers_course on catalogue.course_identifiers(course_id);
create index if not exists idx_course_identifiers_lookup on catalogue.course_identifiers(provider_id, lower(scheme), upper(identifier));
create or replace function catalogue.enforce_course_identifier_provider()
returns trigger language plpgsql security invoker set search_path='catalogue' as $$
begin
  if not exists (select 1 from catalogue.courses c where c.id=new.course_id and c.provider_id=new.provider_id) then
    raise exception 'course identifier provider does not match course provider';
  end if;
  return new;
end $$;
drop trigger if exists trg_course_identifier_provider on catalogue.course_identifiers;
create trigger trg_course_identifier_provider before insert or update on catalogue.course_identifiers
for each row execute function catalogue.enforce_course_identifier_provider();
create table if not exists pipeline.source_record_staging (
  id bigint generated always as identity primary key,
  country_id uuid not null references ref.countries(id),
  source_id uuid not null references pipeline.sources(id),
  provider_id uuid references catalogue.providers(id),
  source_record_id text not null,
  raw_payload jsonb not null,
  content_hash text not null,
  status text not null default 'pending',
  ingested_at timestamptz not null default now(),
  processed_at timestamptz,
  error_text text,
  unique (source_id, source_record_id, content_hash)
);
create index if not exists idx_source_record_staging_pending on pipeline.source_record_staging(source_id,status,id);
create index if not exists idx_source_record_staging_payload_gin on pipeline.source_record_staging using gin(raw_payload);
revoke all on catalogue.course_identifiers from public, anon, authenticated;
revoke all on pipeline.source_record_staging from public, anon, authenticated;
grant select,insert,update,delete on catalogue.course_identifiers to service_role;
grant select,insert,update,delete on pipeline.source_record_staging to service_role;
