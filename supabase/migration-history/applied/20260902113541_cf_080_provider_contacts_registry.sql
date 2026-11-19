-- CF-CHG-20260902-080 / A30 Provider Contacts managed registry
-- Additive private schema above A15 source observations. No Search/Website/Zoho admission.

create table if not exists pipeline.provider_contact_provider_mappings(
  id uuid primary key default extensions.gen_random_uuid(),
  country_code text not null,
  source_label text not null,
  normalized_label text not null,
  provider_id uuid not null references catalogue.providers(id) on delete restrict,
  mapping_reason text not null,
  status text not null default 'accepted' check(status in ('accepted','retired')),
  created_by uuid,
  created_at timestamptz not null default now(),
  unique(country_code,normalized_label,status)
);

create table if not exists pipeline.provider_contacts(
  id uuid primary key default extensions.gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id) on delete restrict,
  record_type text not null check(record_type in ('named_staff','team_contact')),
  lifecycle_status text not null default 'active' check(lifecycle_status in ('active','inactive','deleted')),
  identity_key text,
  current_version_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  deleted_at timestamptz,
  deleted_by uuid,
  delete_reason text,
  restored_at timestamptz,
  restored_by uuid,
  metadata jsonb not null default '{}'::jsonb
);
create unique index if not exists provider_contacts_provider_identity_uidx
  on pipeline.provider_contacts(provider_id,identity_key) where identity_key is not null;
create index if not exists provider_contacts_provider_status_idx
  on pipeline.provider_contacts(provider_id,lifecycle_status,updated_at desc);

create table if not exists pipeline.provider_contact_import_batches(
  id uuid primary key default extensions.gen_random_uuid(),
  country_code text not null default 'AU',
  evidence_artifact_id uuid references pipeline.evidence_artifacts(id) on delete restrict,
  original_filename text not null,
  mime_type text not null,
  byte_size bigint not null check(byte_size>=0),
  content_hash text not null,
  storage_path text not null,
  parser_version text not null default 'provider-contact-csv-v1',
  status text not null default 'uploaded' check(status in ('uploaded','validated','applied','partial','failed')),
  uploaded_by uuid not null,
  uploaded_at timestamptz not null default now(),
  validated_at timestamptz,
  applied_at timestamptz,
  dry_run_summary jsonb not null default '{}'::jsonb,
  apply_summary jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  unique(content_hash)
);

create table if not exists pipeline.provider_contact_versions(
  id uuid primary key default extensions.gen_random_uuid(),
  contact_id uuid not null references pipeline.provider_contacts(id) on delete restrict,
  version_no integer not null check(version_no>0),
  full_name text,
  team_name text,
  job_title text,
  functional_area text,
  region_scope text,
  countries_or_markets text,
  work_email text,
  work_phone text,
  staff_location text,
  verification_state text,
  verified_on date,
  source_class text not null,
  source_authority text not null,
  source_url text,
  source_page_title text,
  source_notes text,
  source_observation_id uuid references pipeline.provider_contact_observations(id) on delete set null,
  evidence_id uuid references pipeline.evidence_artifacts(id) on delete set null,
  import_batch_id uuid references pipeline.provider_contact_import_batches(id) on delete set null,
  import_row_id uuid,
  content_hash text not null,
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  superseded_by uuid,
  change_reason text,
  created_at timestamptz not null default now(),
  created_by uuid,
  metadata jsonb not null default '{}'::jsonb,
  unique(contact_id,version_no)
);

create table if not exists pipeline.provider_contact_import_rows(
  id uuid primary key default extensions.gen_random_uuid(),
  batch_id uuid not null references pipeline.provider_contact_import_batches(id) on delete restrict,
  row_number integer not null check(row_number>0),
  row_hash text not null,
  logical_key text,
  source_payload jsonb not null,
  normalized_payload jsonb not null,
  source_institution_name text,
  current_institution_name text,
  mapped_provider_id uuid references catalogue.providers(id) on delete restrict,
  mapping_state text not null,
  matched_contact_id uuid references pipeline.provider_contacts(id) on delete set null,
  proposed_action text not null,
  applied_action text,
  validation_errors jsonb not null default '[]'::jsonb,
  conflict_detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  applied_at timestamptz,
  unique(batch_id,row_number)
);

create table if not exists pipeline.provider_contact_audit_events(
  id uuid primary key default extensions.gen_random_uuid(),
  contact_id uuid references pipeline.provider_contacts(id) on delete restrict,
  batch_id uuid references pipeline.provider_contact_import_batches(id) on delete set null,
  event_type text not null,
  actor_id uuid,
  reason text,
  before_version_id uuid references pipeline.provider_contact_versions(id) on delete set null,
  after_version_id uuid references pipeline.provider_contact_versions(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

do $$ begin
 if not exists(select 1 from pg_constraint where conname='provider_contact_versions_superseded_fk') then
  alter table pipeline.provider_contact_versions add constraint provider_contact_versions_superseded_fk
   foreign key(superseded_by) references pipeline.provider_contact_versions(id) on delete set null;
 end if;
 if not exists(select 1 from pg_constraint where conname='provider_contacts_current_version_fk') then
  alter table pipeline.provider_contacts add constraint provider_contacts_current_version_fk
   foreign key(current_version_id) references pipeline.provider_contact_versions(id) on delete set null;
 end if;
 if not exists(select 1 from pg_constraint where conname='provider_contact_versions_import_row_fk') then
  alter table pipeline.provider_contact_versions add constraint provider_contact_versions_import_row_fk
   foreign key(import_row_id) references pipeline.provider_contact_import_rows(id) on delete set null;
 end if;
end $$;

create index if not exists provider_contact_versions_contact_idx on pipeline.provider_contact_versions(contact_id,version_no desc);
create index if not exists provider_contact_versions_email_idx on pipeline.provider_contact_versions(lower(work_email)) where work_email is not null;
create index if not exists provider_contact_versions_verified_idx on pipeline.provider_contact_versions(verified_on desc);
create index if not exists provider_contact_versions_source_idx on pipeline.provider_contact_versions(source_authority,verification_state);
create unique index if not exists provider_contact_versions_source_observation_uidx on pipeline.provider_contact_versions(source_observation_id) where source_observation_id is not null;
create index if not exists provider_contact_import_rows_batch_action_idx on pipeline.provider_contact_import_rows(batch_id,proposed_action,row_number);
create index if not exists provider_contact_import_rows_logical_idx on pipeline.provider_contact_import_rows(batch_id,logical_key) where logical_key is not null;
create index if not exists provider_contact_audit_contact_idx on pipeline.provider_contact_audit_events(contact_id,created_at desc);
create index if not exists provider_contact_audit_batch_idx on pipeline.provider_contact_audit_events(batch_id,created_at desc);

alter table pipeline.provider_contact_observations
  add column if not exists managed_contact_id uuid references pipeline.provider_contacts(id) on delete set null;
create index if not exists provider_contact_observations_managed_idx
  on pipeline.provider_contact_observations(managed_contact_id) where managed_contact_id is not null;

alter table pipeline.provider_contact_provider_mappings enable row level security;
alter table pipeline.provider_contacts enable row level security;
alter table pipeline.provider_contact_versions enable row level security;
alter table pipeline.provider_contact_import_batches enable row level security;
alter table pipeline.provider_contact_import_rows enable row level security;
alter table pipeline.provider_contact_audit_events enable row level security;

revoke all on pipeline.provider_contact_provider_mappings from public,anon,authenticated;
revoke all on pipeline.provider_contacts from public,anon,authenticated;
revoke all on pipeline.provider_contact_versions from public,anon,authenticated;
revoke all on pipeline.provider_contact_import_batches from public,anon,authenticated;
revoke all on pipeline.provider_contact_import_rows from public,anon,authenticated;
revoke all on pipeline.provider_contact_audit_events from public,anon,authenticated;
grant select,insert,update,delete on pipeline.provider_contact_provider_mappings to service_role;
grant select,insert,update,delete on pipeline.provider_contacts to service_role;
grant select,insert,update,delete on pipeline.provider_contact_versions to service_role;
grant select,insert,update,delete on pipeline.provider_contact_import_batches to service_role;
grant select,insert,update,delete on pipeline.provider_contact_import_rows to service_role;
grant select,insert,update,delete on pipeline.provider_contact_audit_events to service_role;

create or replace function security.provider_contact_normalise(p_value text)
returns text language sql immutable set search_path=''
as $$
 select lower(regexp_replace(
   regexp_replace(regexp_replace(btrim(coalesce(p_value,'')),'^the[[:space:]]+','','i'),'\([^)]*\)',' ','g'),
   '[^a-zA-Z0-9]+','','g'
 ))
$$;

create or replace function security.provider_contact_identity_key(
 p_record_type text,p_full_name text,p_job_title text,p_region_scope text,p_work_email text,p_source_url text
) returns text language sql immutable set search_path=''
as $$
 select case
  when nullif(lower(btrim(coalesce(p_work_email,''))),'') is not null then 'email:'||lower(btrim(p_work_email))
  when p_record_type='named_staff' and nullif(security.provider_contact_normalise(p_full_name),'') is not null
    then 'person:'||security.provider_contact_normalise(p_full_name)||':'||security.provider_contact_normalise(p_job_title)||':'||security.provider_contact_normalise(p_region_scope)
  when p_record_type='team_contact'
    then 'team:'||md5(security.provider_contact_normalise(p_source_url)||'|'||security.provider_contact_normalise(p_job_title)||'|'||security.provider_contact_normalise(p_region_scope))
  else null
 end
$$;

create or replace function security.provider_contact_payload_hash(p_payload jsonb)
returns text language sql immutable set search_path=''
as $$
 select md5(concat_ws('|',
  security.provider_contact_normalise(p_payload->>'full_name'),
  security.provider_contact_normalise(p_payload->>'team_name'),
  security.provider_contact_normalise(p_payload->>'job_title'),
  security.provider_contact_normalise(p_payload->>'functional_area'),
  security.provider_contact_normalise(p_payload->>'region_scope'),
  security.provider_contact_normalise(p_payload->>'countries_or_markets'),
  lower(btrim(coalesce(p_payload->>'work_email',''))),
  regexp_replace(coalesce(p_payload->>'work_phone',''),'[[:space:]]+','','g'),
  security.provider_contact_normalise(p_payload->>'staff_location'),
  lower(btrim(coalesce(p_payload->>'verification_state',''))),
  coalesce(p_payload->>'verified_on',''),
  lower(btrim(coalesce(p_payload->>'source_authority',''))),
  lower(btrim(coalesce(p_payload->>'source_url','')))
 ))
$$;

create or replace function security.provider_contact_core_hash(p_payload jsonb)
returns text language sql immutable set search_path=''
as $$
 select md5(concat_ws('|',
  security.provider_contact_normalise(p_payload->>'full_name'),
  security.provider_contact_normalise(p_payload->>'team_name'),
  security.provider_contact_normalise(p_payload->>'job_title'),
  security.provider_contact_normalise(p_payload->>'functional_area'),
  security.provider_contact_normalise(p_payload->>'region_scope'),
  security.provider_contact_normalise(p_payload->>'countries_or_markets'),
  lower(btrim(coalesce(p_payload->>'work_email',''))),
  regexp_replace(coalesce(p_payload->>'work_phone',''),'[[:space:]]+','','g'),
  security.provider_contact_normalise(p_payload->>'staff_location'),
  lower(btrim(coalesce(p_payload->>'verification_state',''))),
  coalesce(p_payload->>'verified_on',''),
  lower(btrim(coalesce(p_payload->>'source_url','')))
 ))
$$;

create or replace function security.provider_contact_provider_map(p_country_code text,p_label text)
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','ref'
as $$
declare v_norm text:=security.provider_contact_normalise(p_label);v_ids uuid[];v_count int:=0;v_provider_id uuid;v_provider_name text;v_stable_key text;v_reason text;
begin
 if v_norm='' then return jsonb_build_object('state','unmatched','reason','blank_provider_label'); end if;
 select array_agg(distinct m.provider_id) into v_ids from pipeline.provider_contact_provider_mappings m
 where m.country_code=upper(coalesce(p_country_code,'')) and m.normalized_label=v_norm and m.status='accepted';
 v_count:=coalesce(cardinality(v_ids),0);
 if v_count=1 then v_provider_id:=v_ids[1];v_reason:='contact_mapping';
 elsif v_count>1 then return jsonb_build_object('state','ambiguous','reason','contact_mapping_multiple','candidate_provider_ids',to_jsonb(v_ids));
 else
  with candidates as (
   select p.id from catalogue.providers p join ref.countries c on c.id=p.country_id
   where upper(c.iso_alpha2)=upper(coalesce(p_country_code,'')) and (
    security.provider_contact_normalise(p.canonical_name)=v_norm or security.provider_contact_normalise(p.display_name)=v_norm)
   union
   select a.provider_id from catalogue.provider_aliases a join catalogue.providers p on p.id=a.provider_id
   join ref.countries c on c.id=p.country_id
   where upper(c.iso_alpha2)=upper(coalesce(p_country_code,'')) and security.provider_contact_normalise(a.alias)=v_norm
  )
  select array_agg(distinct id) into v_ids from candidates;
  v_count:=coalesce(cardinality(v_ids),0);
  if v_count=0 then return jsonb_build_object('state','unmatched','reason','no_provider_match','normalized_label',v_norm);
  elsif v_count>1 then return jsonb_build_object('state','ambiguous','reason','multiple_provider_matches','normalized_label',v_norm,'candidate_provider_ids',to_jsonb(v_ids));
  end if;
  v_provider_id:=v_ids[1];v_reason:='catalogue_or_alias';
 end if;
 select p.canonical_name,p.stable_key into v_provider_name,v_stable_key from catalogue.providers p where p.id=v_provider_id;
 return jsonb_build_object('state','mapped','provider_id',v_provider_id,'provider_name',v_provider_name,'stable_key',v_stable_key,'reason',v_reason,'normalized_label',v_norm);
end $$;
revoke all on function security.provider_contact_provider_map(text,text) from public,anon,authenticated;
grant execute on function security.provider_contact_provider_map(text,text) to service_role;

insert into pipeline.provider_contact_provider_mappings(country_code,source_label,normalized_label,provider_id,mapping_reason,status)
select 'AU','CQUniversity Australia',security.provider_contact_normalise('CQUniversity Australia'),p.id,'contact_csv_v1_cqu_brand_to_cricos','accepted'
from catalogue.providers p where p.stable_key='provider:cricos:00219c'
on conflict(country_code,normalized_label,status) do update set provider_id=excluded.provider_id,source_label=excluded.source_label,mapping_reason=excluded.mapping_reason;

insert into pipeline.provider_contact_provider_mappings(country_code,source_label,normalized_label,provider_id,mapping_reason,status)
select 'AU','Torrens University Australia',security.provider_contact_normalise('Torrens University Australia'),p.id,'contact_csv_v1_torrens_short_name_to_cricos','accepted'
from catalogue.providers p where p.stable_key='provider:cricos:03389e'
on conflict(country_code,normalized_label,status) do update set provider_id=excluded.provider_id,source_label=excluded.source_label,mapping_reason=excluded.mapping_reason;

-- Idempotent A15 current-observation backfill into managed logical contacts.
with src as (
 select o.*,case when nullif(btrim(coalesce(o.full_name,'')),'') is not null then 'named_staff' else 'team_contact' end record_type,
 security.provider_contact_identity_key(case when nullif(btrim(coalesce(o.full_name,'')),'') is not null then 'named_staff' else 'team_contact' end,o.full_name,o.job_title,o.territory_text,o.work_email,o.source_url) identity_key
 from pipeline.provider_contact_observations o where o.is_current=true and o.verification_state<>'rejected'
)
insert into pipeline.provider_contacts(provider_id,record_type,lifecycle_status,identity_key,created_at,updated_at,metadata)
select distinct provider_id,record_type,'active',identity_key,least(observed_at,last_verified_at),greatest(observed_at,last_verified_at),
 jsonb_build_object('origin','a15_backfill','change_control','CF-CHG-20260902-080')
from src on conflict(provider_id,identity_key) where identity_key is not null do nothing;

with src as (
 select o.*,case when nullif(btrim(coalesce(o.full_name,'')),'') is not null then 'named_staff' else 'team_contact' end record_type,
 security.provider_contact_identity_key(case when nullif(btrim(coalesce(o.full_name,'')),'') is not null then 'named_staff' else 'team_contact' end,o.full_name,o.job_title,o.territory_text,o.work_email,o.source_url) identity_key
 from pipeline.provider_contact_observations o where o.is_current=true and o.verification_state<>'rejected'
), rows_to_version as (
 select s.*,c.id contact_id from src s join pipeline.provider_contacts c on c.provider_id=s.provider_id and c.identity_key=s.identity_key
 where not exists(select 1 from pipeline.provider_contact_versions v where v.source_observation_id=s.id)
)
insert into pipeline.provider_contact_versions(contact_id,version_no,full_name,team_name,job_title,functional_area,region_scope,countries_or_markets,work_email,work_phone,verification_state,verified_on,source_class,source_authority,source_url,source_observation_id,evidence_id,content_hash,effective_from,change_reason,created_at,metadata)
select r.contact_id,coalesce((select max(v.version_no) from pipeline.provider_contact_versions v where v.contact_id=r.contact_id),0)+1,
 r.full_name,r.team_name,r.job_title,r.team_name,r.territory_text,null,r.work_email,r.work_phone,r.verification_state,r.last_verified_at::date,
 'a15_observation',r.source_class,r.source_url,r.id,r.evidence_id,
 security.provider_contact_payload_hash(jsonb_build_object('full_name',r.full_name,'team_name',r.team_name,'job_title',r.job_title,'functional_area',r.team_name,'region_scope',r.territory_text,'work_email',r.work_email,'work_phone',r.work_phone,'verification_state',r.verification_state,'verified_on',r.last_verified_at::date::text,'source_authority',r.source_class,'source_url',r.source_url)),
 r.observed_at,'A15 accepted observation backfill',r.created_at,
 jsonb_strip_nulls(jsonb_build_object('source_provider',r.source_provider,'territory_codes',r.territory_codes,'professional_profile_url',r.professional_profile_url,'confidence',r.confidence,'change_control','CF-CHG-20260902-080'))
from rows_to_version r;

update pipeline.provider_contacts c set current_version_id=(select vv.id from pipeline.provider_contact_versions vv where vv.contact_id=c.id order by vv.version_no desc,vv.created_at desc limit 1),
 updated_at=greatest(c.updated_at,coalesce((select vv.created_at from pipeline.provider_contact_versions vv where vv.contact_id=c.id order by vv.version_no desc,vv.created_at desc limit 1),c.updated_at))
where exists(select 1 from pipeline.provider_contact_versions vv where vv.contact_id=c.id)
and c.current_version_id is distinct from (select vv.id from pipeline.provider_contact_versions vv where vv.contact_id=c.id order by vv.version_no desc,vv.created_at desc limit 1);

update pipeline.provider_contact_observations o set managed_contact_id=c.id
from pipeline.provider_contacts c
where o.is_current=true and o.verification_state<>'rejected' and c.provider_id=o.provider_id
and c.identity_key=security.provider_contact_identity_key(case when nullif(btrim(coalesce(o.full_name,'')),'') is not null then 'named_staff' else 'team_contact' end,o.full_name,o.job_title,o.territory_text,o.work_email,o.source_url)
and o.managed_contact_id is distinct from c.id;

insert into pipeline.provider_contact_audit_events(contact_id,event_type,reason,after_version_id,metadata,created_at)
select c.id,'backfill','A15 accepted observation migrated to managed registry',c.current_version_id,
 jsonb_build_object('change_control','CF-CHG-20260902-080','origin','a15_backfill'),c.created_at
from pipeline.provider_contacts c
where c.metadata->>'origin'='a15_backfill'
and not exists(select 1 from pipeline.provider_contact_audit_events a where a.contact_id=c.id and a.event_type='backfill');

update pipeline.provider_contacts set metadata=jsonb_set(metadata,'{change_control}','"CF-CHG-20260902-080"'::jsonb,true)
where metadata->>'change_control' in ('CF-CHG-20260902-076','CF-CHG-20260902-077');
update pipeline.provider_contact_versions set metadata=jsonb_set(metadata,'{change_control}','"CF-CHG-20260902-080"'::jsonb,true)
where metadata->>'change_control' in ('CF-CHG-20260902-076','CF-CHG-20260902-077');
update pipeline.provider_contact_audit_events set metadata=jsonb_set(metadata,'{change_control}','"CF-CHG-20260902-080"'::jsonb,true)
where metadata->>'change_control' in ('CF-CHG-20260902-076','CF-CHG-20260902-077');
