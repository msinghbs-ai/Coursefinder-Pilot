-- CF-247 / Decision 149: country-neutral identity.
-- Every country's official register identifiers are recorded as typed, country-scoped identifiers in
-- catalogue.provider_identifiers and catalogue.course_identifiers. Canada already did this; Australia
-- (CRICOS provider and course codes) and New Zealand (NZQA provider and course numbers) were held only
-- in the registration tables. No shared table gains a country-specific column: each scheme is one row
-- in ref.identifier_schemes, and a new country adds rows, not columns.
-- The registration tables stay the write path for register ingestion; triggers keep the identifier
-- tables in step (insert, code change, delete), writing only when something changes (Decision 152).
-- course_code stays the display code. Consumer API: not touched.

create table if not exists ref.identifier_schemes(
  scheme text not null,
  entity_type text not null check (entity_type in ('provider','course')),
  country_id uuid not null references ref.countries(id),
  name text not null,
  issuing_authority text not null,
  official boolean not null default true,
  mirror_registrations boolean not null default false,
  status text not null default 'active' check (status in ('active','retired')),
  created_at timestamptz not null default now(),
  primary key (scheme, entity_type));
alter table ref.identifier_schemes enable row level security;
revoke all on ref.identifier_schemes from anon;
grant select on ref.identifier_schemes to authenticated, service_role;
drop policy if exists identifier_schemes_read on ref.identifier_schemes;
create policy identifier_schemes_read on ref.identifier_schemes for select to authenticated using (true);

insert into ref.identifier_schemes(scheme,entity_type,country_id,name,issuing_authority,official,mirror_registrations)
select v.scheme, v.entity_type, c.id, v.name, v.authority, true, v.mirror
  from (values
    ('cricos','provider','AU','CRICOS provider code','Australian Government Department of Education (CRICOS)',true),
    ('cricos','course','AU','CRICOS course code','Australian Government Department of Education (CRICOS)',true),
    ('nzqa','provider','NZ','NZQA provider number','New Zealand Qualifications Authority',true),
    ('nzqa','course','NZ','NZQA qualification or programme number','New Zealand Qualifications Authority',true),
    ('ircc_dli','provider','CA','Designated learning institution number','IRCC',true)
  ) v(scheme,entity_type,iso,name,authority,mirror)
  join ref.countries c on c.iso_alpha2=v.iso
on conflict (scheme, entity_type) do nothing;

-- Course registrations -> course identifiers
create or replace function catalogue.mirror_course_registration_identifier()
returns trigger language plpgsql security definer set search_path to 'pg_catalog','catalogue','ref','pipeline' as $f$
declare s ref.identifier_schemes; v_provider uuid; v_ev uuid;
begin
  if tg_op in ('UPDATE','DELETE') then
    if tg_op='UPDATE' and new.course_id=old.course_id and new.scheme=old.scheme and new.registration_code=old.registration_code
       and new.evidence_id is not distinct from old.evidence_id and new.source_id is not distinct from old.source_id then
      return new;  -- nothing identifying changed (status and dates stay on the registration)
    end if;
    select * into s from ref.identifier_schemes where scheme=old.scheme and entity_type='course' and mirror_registrations and status='active';
    if found then
      delete from catalogue.course_identifiers i where i.course_id=old.course_id and i.scheme=old.scheme and i.identifier=old.registration_code
        and not exists (select 1 from catalogue.course_registrations r where r.course_id=old.course_id and r.scheme=old.scheme
                         and r.registration_code=old.registration_code and (tg_op='DELETE' or r.id<>old.id));
    end if;
    if tg_op='DELETE' then return old; end if;
  end if;
  select * into s from ref.identifier_schemes where scheme=new.scheme and entity_type='course' and mirror_registrations and status='active';
  if not found then return new; end if;
  select c.provider_id into v_provider from catalogue.courses c where c.id=new.course_id;
  select e.id into v_ev from pipeline.evidence_artifacts e where e.id=new.evidence_id;
  insert into catalogue.course_identifiers(course_id,provider_id,scheme,identifier,country_id,issuing_authority,is_primary,source_id,evidence_id,verified_at)
  values(new.course_id,v_provider,new.scheme,new.registration_code,coalesce(new.country_id,s.country_id),s.issuing_authority,true,new.source_id,v_ev,now())
  on conflict (provider_id, scheme, identifier) do update
    set course_id=excluded.course_id, country_id=excluded.country_id, source_id=excluded.source_id, evidence_id=excluded.evidence_id, verified_at=excluded.verified_at
    where (catalogue.course_identifiers.course_id, catalogue.course_identifiers.country_id, catalogue.course_identifiers.source_id, catalogue.course_identifiers.evidence_id)
          is distinct from (excluded.course_id, excluded.country_id, excluded.source_id, excluded.evidence_id);
  return new;
end $f$;
revoke all on function catalogue.mirror_course_registration_identifier() from public, anon, authenticated;
drop trigger if exists trg_mirror_course_registration_identifier on catalogue.course_registrations;
create trigger trg_mirror_course_registration_identifier after insert or update or delete on catalogue.course_registrations
  for each row execute function catalogue.mirror_course_registration_identifier();

-- Provider registrations -> provider identifiers
create or replace function catalogue.mirror_provider_registration_identifier()
returns trigger language plpgsql security definer set search_path to 'pg_catalog','catalogue','ref','pipeline' as $f$
declare s ref.identifier_schemes; v_ev uuid;
begin
  if tg_op in ('UPDATE','DELETE') then
    if tg_op='UPDATE' and new.provider_id=old.provider_id and new.registration_scheme=old.registration_scheme and new.registration_code=old.registration_code
       and new.valid_from is not distinct from old.valid_from and new.valid_to is not distinct from old.valid_to
       and new.evidence_id is not distinct from old.evidence_id and new.source_id is not distinct from old.source_id then
      return new;
    end if;
    select * into s from ref.identifier_schemes where scheme=old.registration_scheme and entity_type='provider' and mirror_registrations and status='active';
    if found and (tg_op='DELETE' or new.provider_id<>old.provider_id or new.registration_scheme<>old.registration_scheme or new.registration_code<>old.registration_code) then
      delete from catalogue.provider_identifiers i where i.provider_id=old.provider_id and i.scheme=old.registration_scheme and i.identifier=old.registration_code;
    end if;
    if tg_op='DELETE' then return old; end if;
  end if;
  select * into s from ref.identifier_schemes where scheme=new.registration_scheme and entity_type='provider' and mirror_registrations and status='active';
  if not found then return new; end if;
  select e.id into v_ev from pipeline.evidence_artifacts e where e.id=new.evidence_id;
  insert into catalogue.provider_identifiers(provider_id,scheme,identifier,country_id,issuing_authority,is_primary,valid_from,valid_to,source_id,evidence_id,verified_at)
  values(new.provider_id,new.registration_scheme,new.registration_code,s.country_id,s.issuing_authority,true,new.valid_from,new.valid_to,new.source_id,v_ev,coalesce(new.checked_at,now()))
  on conflict (provider_id, scheme, identifier) do update
    set valid_from=excluded.valid_from, valid_to=excluded.valid_to, source_id=excluded.source_id, evidence_id=excluded.evidence_id, verified_at=excluded.verified_at
    where (catalogue.provider_identifiers.valid_from, catalogue.provider_identifiers.valid_to, catalogue.provider_identifiers.source_id, catalogue.provider_identifiers.evidence_id)
          is distinct from (excluded.valid_from, excluded.valid_to, excluded.source_id, excluded.evidence_id);
  return new;
end $f$;
revoke all on function catalogue.mirror_provider_registration_identifier() from public, anon, authenticated;
drop trigger if exists trg_mirror_provider_registration_identifier on catalogue.provider_registrations;
create trigger trg_mirror_provider_registration_identifier after insert or update or delete on catalogue.provider_registrations
  for each row execute function catalogue.mirror_provider_registration_identifier();

-- Backfill (idempotent). Existing IRCC DLI identifiers are left as they are.
insert into catalogue.provider_identifiers(provider_id,scheme,identifier,country_id,issuing_authority,is_primary,valid_from,valid_to,source_id,evidence_id,verified_at)
select r.provider_id, r.registration_scheme, r.registration_code, s.country_id, s.issuing_authority, true, r.valid_from, r.valid_to, r.source_id,
       (select e.id from pipeline.evidence_artifacts e where e.id=r.evidence_id), coalesce(r.checked_at, now())
  from catalogue.provider_registrations r
  join ref.identifier_schemes s on s.scheme=r.registration_scheme and s.entity_type='provider' and s.mirror_registrations
on conflict (provider_id, scheme, identifier) do nothing;

insert into catalogue.course_identifiers(course_id,provider_id,scheme,identifier,country_id,issuing_authority,is_primary,source_id,evidence_id,verified_at)
select r.course_id, c.provider_id, r.scheme, r.registration_code, coalesce(r.country_id, s.country_id), s.issuing_authority, true, r.source_id,
       (select e.id from pipeline.evidence_artifacts e where e.id=r.evidence_id), now()
  from catalogue.course_registrations r
  join catalogue.courses c on c.id=r.course_id
  join ref.identifier_schemes s on s.scheme=r.scheme and s.entity_type='course' and s.mirror_registrations
on conflict (provider_id, scheme, identifier) do nothing;
