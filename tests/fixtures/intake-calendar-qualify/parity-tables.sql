-- Guards: F-INT.01/SRC-01 (9 Nov 2026), QA finding on #930: a stub without the production unique keys, CHECKs, foreign keys, NOT NULL sets and triggers hides real failures.
-- Every table the qualification route and its cases read or write is brought to the production shape (read 9 Nov 2026 from fxcwkweaxjtknorudmwp, SELECT only) and then
-- ASSERTED against the production constraint list below, so a drift of the fixture fails the run instead of passing silently.
create schema if not exists pim; create schema if not exists ref;
create table if not exists pim.entity_registry (id uuid primary key);
create table if not exists ref.countries (id uuid primary key default gen_random_uuid());
create table if not exists ref.provider_types (id uuid primary key default gen_random_uuid());

-- catalogue.providers
alter table catalogue.providers add column if not exists subdivision_id uuid, add column if not exists created_at timestamptz, add column if not exists updated_at timestamptz;
insert into pim.entity_registry select id from catalogue.providers on conflict do nothing;
insert into ref.countries(id) select distinct country_id from catalogue.providers where country_id is not null on conflict do nothing;
update catalogue.providers set stable_key = coalesce(stable_key, 'fixture:' || id), canonical_name = coalesce(canonical_name, display_name, 'fixture ' || id), lifecycle_status = coalesce(lifecycle_status, 'active'),
  publication_status = coalesce(publication_status, 'published'), created_at = coalesce(created_at, now()), updated_at = coalesce(updated_at, now());
do $$ declare c uuid; begin
  if exists (select 1 from catalogue.providers where country_id is null) then
    c := gen_random_uuid(); insert into ref.countries(id) values (c); update catalogue.providers set country_id = c where country_id is null; end if; end $$;
alter table catalogue.providers alter column stable_key set not null, alter column canonical_name set not null, alter column country_id set not null,
  alter column lifecycle_status set default 'active', alter column lifecycle_status set not null, alter column publication_status set default 'published', alter column publication_status set not null,
  alter column created_at set default now(), alter column created_at set not null, alter column updated_at set default now(), alter column updated_at set not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'providers_stable_key_key') then alter table catalogue.providers add constraint providers_stable_key_key unique (stable_key); end if;
  if not exists (select 1 from pg_constraint where conname = 'providers_id_fkey') then alter table catalogue.providers add constraint providers_id_fkey foreign key (id) references pim.entity_registry(id) on delete cascade; end if;
  if not exists (select 1 from pg_constraint where conname = 'providers_country_id_fkey') then alter table catalogue.providers add constraint providers_country_id_fkey foreign key (country_id) references ref.countries(id); end if;
  if not exists (select 1 from pg_constraint where conname = 'providers_provider_type_id_fkey') then alter table catalogue.providers add constraint providers_provider_type_id_fkey foreign key (provider_type_id) references ref.provider_types(id); end if;
end $$;

-- pipeline.evidence_artifacts
alter table pipeline.evidence_artifacts add column if not exists evidence_type text, add column if not exists source_url text, add column if not exists storage_path text, add column if not exists content_hash text,
  add column if not exists captured_at timestamptz, add column if not exists metadata jsonb, add column if not exists created_at timestamptz, add column if not exists supersedes_evidence_id uuid;
update pipeline.evidence_artifacts set evidence_type = coalesce(evidence_type, 'page'), captured_at = coalesce(captured_at, now()), metadata = coalesce(metadata, '{}'::jsonb), created_at = coalesce(created_at, now());
alter table pipeline.evidence_artifacts alter column id set default gen_random_uuid(), alter column evidence_type set not null, alter column captured_at set default now(), alter column captured_at set not null,
  alter column metadata set default '{}'::jsonb, alter column metadata set not null, alter column created_at set default now(), alter column created_at set not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'evidence_artifacts_supersedes_evidence_id_fkey') then
    alter table pipeline.evidence_artifacts add constraint evidence_artifacts_supersedes_evidence_id_fkey foreign key (supersedes_evidence_id) references pipeline.evidence_artifacts(id); end if;
end $$;

-- pipeline.provider_fact_sources: columns the route reads
alter table pipeline.provider_fact_sources add column if not exists title text, add column if not exists read_at timestamptz, add column if not exists content_hash text, add column if not exists evidence_id uuid,
  add column if not exists decided_by uuid, add column if not exists decision text;

-- pipeline.provider_policy_proposals
alter table pipeline.provider_policy_proposals add column if not exists style text, add column if not exists evidence_id uuid, add column if not exists content_hash text,
  add column if not exists decided_by uuid, add column if not exists decided_at timestamptz, add column if not exists decision_note text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'provider_policy_proposals_provider_id_fkey') then
    alter table pipeline.provider_policy_proposals add constraint provider_policy_proposals_provider_id_fkey foreign key (provider_id) references catalogue.providers(id); end if;
end $$;

-- pipeline.platform_toolset_settings
update pipeline.platform_toolset_settings set label = coalesce(label, key), help = coalesce(help, ''), kind = coalesce(kind, 'number'), value = coalesce(value, 'null'::jsonb), sort = coalesce(sort, 0),
  updated_at = coalesce(updated_at, now()), section = coalesce(section, 'Other');
alter table pipeline.platform_toolset_settings alter column label set not null, alter column help set not null, alter column kind set not null, alter column value set not null,
  alter column sort set not null, alter column updated_at set default now(), alter column updated_at set not null, alter column section set not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'platform_toolset_settings_kind_check') then
    alter table pipeline.platform_toolset_settings add constraint platform_toolset_settings_kind_check check (kind = any (array['number','text','boolean','list'])); end if;
end $$;

-- pipeline.admin_control_events: actor is a uuid
alter table pipeline.admin_control_events add column if not exists actor uuid;

-- pipeline.component_register: primary key (kind, name)
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'component_register_pkey') then
    alter table pipeline.component_register drop constraint if exists component_register_kind_name_key;
    alter table pipeline.component_register add constraint component_register_pkey primary key (kind, name); end if;
end $$;

-- pipeline.provider_extra_domains (production shape; empty)
create table if not exists pipeline.provider_extra_domains (provider_id uuid, domain text, state text, reason text, added_by uuid, added_at timestamptz, mapped_at timestamptz);
alter table pipeline.provider_extra_domains add column if not exists provider_id uuid, add column if not exists domain text, add column if not exists state text, add column if not exists reason text,
  add column if not exists added_by uuid, add column if not exists added_at timestamptz, add column if not exists mapped_at timestamptz;
update pipeline.provider_extra_domains set state = coalesce(state, 'approved'), reason = coalesce(reason, 'fixture'), added_at = coalesce(added_at, now());
alter table pipeline.provider_extra_domains alter column provider_id set not null, alter column domain set not null, alter column state set default 'approved', alter column state set not null,
  alter column reason set not null, alter column added_at set default now(), alter column added_at set not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'provider_extra_domains_pkey') then alter table pipeline.provider_extra_domains add constraint provider_extra_domains_pkey primary key (provider_id, domain); end if;
  if not exists (select 1 from pg_constraint where conname = 'provider_extra_domains_domain_check') then alter table pipeline.provider_extra_domains add constraint provider_extra_domains_domain_check check (domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'); end if;
  if not exists (select 1 from pg_constraint where conname = 'provider_extra_domains_state_check') then alter table pipeline.provider_extra_domains add constraint provider_extra_domains_state_check check (state in ('approved', 'withdrawn')); end if;
  if not exists (select 1 from pg_constraint where conname = 'provider_extra_domains_provider_id_fkey') then alter table pipeline.provider_extra_domains add constraint provider_extra_domains_provider_id_fkey foreign key (provider_id) references catalogue.providers(id); end if;
  if not exists (select 1 from pg_constraint where conname = 'manual_locks_entity_check') then alter table pipeline.manual_locks add constraint manual_locks_entity_check check (entity = any (array['course', 'provider', 'campus', 'scholarship'])); end if;
end $$;

-- pipeline.course_intake_date_events and pipeline.intake_date_rejections: columns the route reads
alter table pipeline.course_intake_date_events add column if not exists before_value jsonb, add column if not exists after_value jsonb;
alter table pipeline.intake_date_rejections add column if not exists quote text, add column if not exists year int, add column if not exists start_date date, add column if not exists proposal_id uuid;

-- production defaults of the columns the route and the cases leave to the table
alter table pipeline.manual_locks alter column set_at set default now();
alter table pipeline.course_intake_date_events alter column run_at set default now(), alter column bounded set default false;
alter table pipeline.intake_date_rejections alter column rejected_at set default now();
alter table pipeline.calendar_refresh_requests alter column requested_at set default now(), alter column status set default 'requested';
alter table pipeline.admin_control_events alter column created_at set default now(), alter column detail set default '{}'::jsonb;
alter table pipeline.provider_policy_proposals alter column status set default 'proposed', alter column created_at set default now(), alter column updated_at set default now(), alter column id set default gen_random_uuid();
alter table pipeline.provider_fact_sources alter column attempts set default 0, alter column created_at set default now(), alter column updated_at set default now(), alter column id set default gen_random_uuid();

-- assertion: the constraint and NOT NULL sets equal production (read 9 Nov 2026)
do $$
declare t text; got text; want text; bad text := '';
begin
  for t, want in select * from (values
    ('pipeline.provider_policy_proposals', 'provider_policy_proposals_fact_source_id_fkey|provider_policy_proposals_key|provider_policy_proposals_kind_check|provider_policy_proposals_pkey|provider_policy_proposals_provider_id_fkey|provider_policy_proposals_status_check'),
    ('pipeline.provider_fact_sources', 'provider_fact_sources_decision_check|provider_fact_sources_evidence_id_fkey|provider_fact_sources_found_via_check|provider_fact_sources_key|provider_fact_sources_kind_check|provider_fact_sources_linked_from_fkey|provider_fact_sources_pkey|provider_fact_sources_provider_id_fkey|provider_fact_sources_status_check'),
    ('pipeline.calendar_refresh_requests', 'calendar_refresh_requests_fact_source_id_fkey|calendar_refresh_requests_pkey|calendar_refresh_requests_status_check|calendar_refresh_requests_yield_check'),
    ('pipeline.manual_locks', 'manual_locks_entity_check|manual_locks_mode_check|manual_locks_pkey'),
    ('pipeline.intake_date_rejections', 'intake_date_rejections_pkey'),
    ('pipeline.course_intake_date_events', 'course_intake_date_events_pkey'),
    ('pipeline.admin_control_events', 'admin_control_events_pkey'),
    ('pipeline.platform_toolset_settings', 'platform_toolset_settings_kind_check|platform_toolset_settings_pkey'),
    ('pipeline.component_register', 'component_register_kind_check|component_register_pkey|component_register_status_check'),
    ('pipeline.evidence_artifacts', 'evidence_artifacts_pkey|evidence_artifacts_supersedes_evidence_id_fkey'),
    ('pipeline.provider_extra_domains', 'provider_extra_domains_domain_check|provider_extra_domains_pkey|provider_extra_domains_provider_id_fkey|provider_extra_domains_state_check')) v(t, want) loop
    select string_agg(c.conname, '|' order by c.conname) into got from pg_constraint c where c.conrelid = t::regclass and c.contype in ('p', 'u', 'c', 'f');
    -- the fixture may carry extra constraints of its own (other fixtures); every production constraint must be present
    if exists (select 1 from unnest(string_to_array(want, '|')) w where w <> all (string_to_array(coalesce(got, ''), '|'))) then bad := bad || t || ' lacks ' || want || ' (has ' || coalesce(got, '') || E')\n'; end if;
  end loop;
  for t, want in select * from (values
    ('pipeline.provider_policy_proposals', 'id,provider_id,fact_source_id,kind,parser,url,proposal,status,created_at,updated_at'),
    ('pipeline.provider_fact_sources', 'id,provider_id,kind,url,rank,found_via,status,attempts,created_at,updated_at'),
    ('pipeline.calendar_refresh_requests', 'id,fact_source_id,provider_id,url,reason,credit_estimate,requested_at,status'),
    ('pipeline.manual_locks', 'entity,entity_id,field,mode,set_at'),
    ('pipeline.intake_date_rejections', 'id,provider_id,reason,rejected_at'),
    ('pipeline.course_intake_date_events', 'id,intake_id,course_id,provider_id,run_at,outcome,bounded'),
    ('pipeline.admin_control_events', 'id,area,action,detail,created_at'),
    ('pipeline.platform_toolset_settings', 'toolset_key,key,label,help,kind,value,sort,updated_at,section'),
    ('pipeline.evidence_artifacts', 'id,evidence_type,captured_at,metadata,created_at'),
    ('catalogue.providers', 'id,stable_key,canonical_name,country_id,lifecycle_status,publication_status,created_at,updated_at')) v(t, want) loop
    select string_agg(a.attname, ',' order by a.attname) into got from pg_attribute a where a.attrelid = t::regclass and a.attnum > 0 and not a.attisdropped and a.attnotnull;
    if exists (select 1 from unnest(string_to_array(want, ',')) w where w <> all (string_to_array(coalesce(got, ''), ','))) then bad := bad || t || ' NOT NULL lacks some of ' || want || ' (has ' || coalesce(got, '') || E')\n'; end if;
  end loop;
  -- the production triggers the cases must run through
  if not exists (select 1 from pg_trigger where tgrelid = 'pipeline.course_intake_date_events'::regclass and tgname = 'intake_failure_class') then bad := bad || 'trigger intake_failure_class missing on events' || E'\n'; end if;
  if bad <> '' then raise exception 'fixture drifts from production shape: %', bad; end if;
  raise notice 'PASS parity: written tables carry the production unique keys, CHECKs, foreign keys, NOT NULL sets and triggers (asserted)';
end $$;
