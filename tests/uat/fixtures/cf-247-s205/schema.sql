-- CF-247 UR-18 slice 1: isolated fixture schema (local Postgres only; never run against a Supabase project).
-- Stand-ins for the live tables the bulk review reads and writes, with the same column names, checks and keys. The live definitions of
-- the manual-lock guards, the Layer 4 arrival reroute trigger, the role rank, the settings readers and the postcode rule are copied as they
-- are on project fxcwkweaxjtknorudmwp (1-2 Nov 2026). The two functions the migration edits are loaded from their *.before.sql files.
create extension if not exists pgcrypto;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
end $$;
create schema auth; create schema security; create schema pipeline; create schema catalogue; create schema ref; create schema search;

create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

create table security.roles (code text primary key, rank smallint not null, status text not null default 'active');
create table security.user_roles (user_id uuid not null, role_code text not null references security.roles(code), expires_at timestamptz);
insert into security.roles values ('viewer', 1, 'active'), ('counsellor', 2, 'active'), ('curator', 3, 'active'), ('pipeline_operator', 4, 'active'),
  ('pim_admin', 5, 'active'), ('platform_admin', 6, 'active');
CREATE OR REPLACE FUNCTION security.current_role_rank()
 RETURNS smallint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'security', 'auth'
AS $function$
select coalesce(max(r.rank),0)::smallint
from security.user_roles ur join security.roles r on r.code=ur.role_code
where ur.user_id=auth.uid() and (ur.expires_at is null or ur.expires_at>now()) and r.status='active'
$function$;

create table pipeline.platform_toolsets (key text primary key);
insert into pipeline.platform_toolsets values ('pipeline');
create table pipeline.platform_toolset_settings (
  toolset_key text not null references pipeline.platform_toolsets(key), key text not null, label text not null, help text not null default '',
  kind text not null check (kind in ('number', 'text', 'boolean', 'list')), value jsonb not null, min_value numeric, max_value numeric, unit text,
  sort integer not null default 100, reason text, updated_by uuid, updated_at timestamptz not null default now(), section text not null default 'Notices',
  used_by text, primary key (toolset_key, key));
CREATE OR REPLACE FUNCTION security.pipeline_num_v1(p_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default)
$function$;
CREATE OR REPLACE FUNCTION security.toolset_setting(p_toolset text, p_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select s.value from pipeline.platform_toolset_settings s where s.toolset_key = p_toolset and s.key = p_key
$function$;
CREATE OR REPLACE FUNCTION security.au_state_from_postcode_v1(p_postcode text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when p_postcode !~ '^\d{4}$' then null
              when p_postcode ~ '^(26[0-1]\d|29[0-2]\d|02\d\d)$' then 'ACT'
              when p_postcode ~ '^(1|2)' then 'NSW' when p_postcode ~ '^(3|8)' then 'VIC' when p_postcode ~ '^(4|9)' then 'QLD'
              when p_postcode ~ '^5' then 'SA' when p_postcode ~ '^6' then 'WA' when p_postcode ~ '^7' then 'TAS' when p_postcode ~ '^0[89]' then 'NT' end
$function$;
CREATE OR REPLACE FUNCTION security.aer_review_kinds_v1()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select array['entry_matrix_first_run', 'entry_matrix_change', 'course_entry_first_read']::text[]
$function$;
-- stand-in: the Inbox kinds (read by admin_layer4_inbox's declare section)
create function security.layer4_inbox_kinds_v1() returns jsonb language sql as $$ select '{}'::jsonb $$;

create table pipeline.sources (id uuid primary key default gen_random_uuid(), source_type text not null, created_at timestamptz not null default now());
create table pipeline.evidence_artifacts (id uuid primary key default gen_random_uuid(), source_id uuid, evidence_type text not null, source_url text, storage_path text,
  captured_at timestamptz not null default now(), supersedes_evidence_id uuid, metadata jsonb not null default '{}'::jsonb);
create table ref.countries (id uuid primary key default gen_random_uuid(), iso_alpha2 character(2) not null unique, name text not null);
create table ref.subdivisions (id uuid primary key default gen_random_uuid(), country_id uuid not null references ref.countries(id), code text not null, name text not null);
create table ref.study_levels (id uuid primary key default gen_random_uuid(), code text, name text not null);
create table catalogue.providers (id uuid primary key, canonical_name text not null, display_name text, country_id uuid not null references ref.countries(id));
create table catalogue.campuses (id uuid primary key default gen_random_uuid(), provider_id uuid not null references catalogue.providers(id), name text not null, campus_code text,
  country_id uuid not null references ref.countries(id), subdivision_id uuid references ref.subdivisions(id), city text, address_line1 text, postcode text,
  status text not null default 'active', source_id uuid, evidence_id uuid references pipeline.evidence_artifacts(id), updated_at timestamptz not null default now());
create table catalogue.courses (id uuid primary key, provider_id uuid not null references catalogue.providers(id), canonical_title text not null, display_title text,
  course_code text, study_level_id uuid references ref.study_levels(id), delivery_mode text, lifecycle_status text not null default 'active',
  updated_at timestamptz not null default now());
create table catalogue.course_campuses (course_id uuid not null references catalogue.courses(id), campus_id uuid not null references catalogue.campuses(id),
  delivery_mode text not null default '', is_primary boolean not null default false, source_id uuid, evidence_id uuid, primary key (course_id, campus_id, delivery_mode));

create table pipeline.manual_locks (entity text not null check (entity in ('course', 'provider', 'campus', 'scholarship')), entity_id uuid not null, field text not null,
  mode text not null check (mode in ('value', 'removed')), set_by uuid, set_at timestamptz not null default now(), primary key (entity, entity_id, field));
CREATE OR REPLACE FUNCTION security.manual_field_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_new jsonb; v_old jsonb; f text; v_entity text := case TG_TABLE_NAME when 'courses' then 'course' else 'provider' end;
begin
  if coalesce(current_setting('cf.manual_edit', true), '') = 'on' then return NEW; end if;
  if not exists (select 1 from pipeline.manual_locks l where l.entity = v_entity and l.entity_id = OLD.id) then return NEW; end if;
  v_new := to_jsonb(NEW); v_old := to_jsonb(OLD);
  for f in select l.field from pipeline.manual_locks l where l.entity = v_entity and l.entity_id = OLD.id loop
    if v_old ? f then v_new := jsonb_set(v_new, array[f], v_old->f); end if;
  end loop;
  NEW := jsonb_populate_record(NEW, v_new);
  return NEW;
end $function$;
CREATE OR REPLACE FUNCTION security.manual_column_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_new jsonb; v_old jsonb; f text; v_entity text := TG_ARGV[0];
begin
  if coalesce(current_setting('cf.manual_edit', true), '') = 'on' then return NEW; end if;
  if not exists (select 1 from pipeline.manual_locks l where l.entity = v_entity and l.entity_id = OLD.id) then return NEW; end if;
  v_new := to_jsonb(NEW); v_old := to_jsonb(OLD);
  for f in select l.field from pipeline.manual_locks l where l.entity = v_entity and l.entity_id = OLD.id loop
    if v_old ? f then v_new := jsonb_set(v_new, array[f], v_old->f); end if;
  end loop;
  NEW := jsonb_populate_record(NEW, v_new);
  return NEW;
end $function$;
create trigger manual_lock_guard before update on catalogue.campuses for each row execute function security.manual_column_guard('campus');
create trigger manual_lock_guard before update on catalogue.courses for each row execute function security.manual_field_guard();

create table pipeline.coverage_course_pages (course_id uuid primary key, provider_id uuid, url text, status text, evidence_id uuid, next_read_at timestamptz, leased_until timestamptz, read_attempts int);
create table pipeline.uni_adapter_results (id bigserial primary key, provider_id uuid, course_id uuid, fields jsonb, at timestamptz not null default now());
create table pipeline.uni_adapter_exclusions (course_id uuid not null, field text not null, provider_id uuid, active boolean, reason text, primary key (course_id, field));
create table pipeline.uni_adapter_delivery_exclusions (course_id uuid primary key, provider_id uuid, active boolean, reason text);
create table pipeline.uni_adapters (provider_id uuid primary key, enabled boolean, admit boolean, admit_fields text[]);
create table pipeline.layer4_override_decisions (id uuid primary key default gen_random_uuid(), entity_type text, entity_id uuid, field_code text);
create table pipeline.campus_region_cleared (campus_id uuid primary key, subdivision_id uuid, reason text, cleared_at timestamptz default now());

create table pipeline.layer4_review_items (id uuid primary key default gen_random_uuid(), entity_type text not null, entity_id uuid not null, field_code text not null,
  evidence_id uuid references pipeline.evidence_artifacts(id), layer3_interpretation_id uuid, before_value jsonb, proposed_value jsonb,
  layer2_state jsonb not null default '{}'::jsonb, layer3_state jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending', 'approved', 'edited_approved', 'rejected', 'more_evidence', 'returned_layer2', 'returned_layer3', 'superseded')),
  assigned_to uuid, escalation_reason text, change_control_ref text not null default 'CF-CHG-20260825-038', created_at timestamptz not null default now(),
  decided_at timestamptz, claimed_at timestamptz);
create table pipeline.layer4_reroutes (item_id uuid, entity_type text, entity_id uuid, field_code text, route text, note text);
CREATE OR REPLACE FUNCTION security.layer4_adapter_field_v1(p_field_code text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case p_field_code when 'course_intake' then 'intakes' when 'course_english' then 'english' when 'provider_current_tuition_validation' then 'fee' end
$function$;
CREATE OR REPLACE FUNCTION security.layer4_reroute_course_v1(p_course uuid, p_field_code text, p_apply boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_f text := security.layer4_adapter_field_v1(p_field_code); v_ok boolean;
begin
  if v_f is null then return false; end if;
  select true into v_ok from catalogue.courses c join pipeline.uni_adapters a on a.provider_id = c.provider_id
   where c.id = p_course and a.enabled and coalesce(a.admit, false) and (a.admit_fields is null or v_f = any (a.admit_fields))
     and exists (select 1 from pipeline.coverage_course_pages pg where pg.course_id = c.id and pg.status in ('bound', 'ambiguous'));
  if not coalesce(v_ok, false) then return false; end if;
  if p_apply then
    update pipeline.coverage_course_pages set next_read_at = now(), leased_until = null, read_attempts = 0 where course_id = p_course and status in ('bound', 'ambiguous');
  end if;
  return true;
end $function$;
CREATE OR REPLACE FUNCTION security.layer4_reroute_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.entity_type = 'course' and new.status = 'pending' and security.layer4_reroute_course_v1(new.entity_id, new.field_code, true) then
    new.status := 'superseded'; new.decided_at := now();
    new.change_control_ref := coalesce(new.change_control_ref || '; ', '') || 'CF-247 v2.15.250: rerouted to the university adapter';
    insert into pipeline.layer4_reroutes(item_id, entity_type, entity_id, field_code, route, note) values (new.id, 'course', new.entity_id, new.field_code, 'adapter', 'on arrival');
  end if;
  return new;
end $function$;
create trigger layer4_review_items_reroute before insert on pipeline.layer4_review_items for each row execute function security.layer4_reroute_trg_v1();

create table pipeline.layer4_decisions (id uuid primary key default gen_random_uuid(), review_item_id uuid not null references pipeline.layer4_review_items(id),
  action text not null check (action in ('approve', 'edit_and_approve', 'reject', 'request_more_evidence', 'return_layer2', 'return_layer3', 'merge_existing',
  'accept_incoming', 'keep_existing', 'keep_separate', 'map_provider_apply', 'reject_import')), actor_id uuid not null, reason text not null, before_value jsonb,
  proposed_value jsonb, final_value jsonb, evidence_id uuid references pipeline.evidence_artifacts(id), layer2_state jsonb not null default '{}'::jsonb,
  layer3_state jsonb not null default '{}'::jsonb, scalar_resolution_id uuid, change_control_ref text not null, created_at timestamptz not null default now());
create table pipeline.search_refresh_signals (id uuid primary key default gen_random_uuid(), entity_type text not null, entity_id uuid not null,
  review_decision_id uuid not null unique references pipeline.layer4_decisions(id), reason text not null,
  status text not null default 'queued' check (status in ('queued', 'processing', 'completed', 'cancelled', 'blocked')),
  change_control_ref text not null default 'CF-CHG-20260825-038', created_at timestamptz not null default now(), completed_at timestamptz);
create table pipeline.refresh_requests (id uuid primary key default gen_random_uuid());
create table pipeline.admin_control_events (id bigserial primary key, area text not null, action text not null, target text, detail jsonb not null default '{}'::jsonb,
  actor uuid, created_at timestamptz not null default now());
create table pipeline.component_register (kind text not null check (kind in ('job', 'table', 'view', 'edge_function', 'screen', 'function')), name text not null,
  layer text not null, area text, purpose text, status text not null default 'active' check (status in ('active', 'retiring', 'retired')),
  replaces text[] not null default '{}', replaced_by text, introduced_in text, retire_after date, note text, primary key (kind, name));

-- stand-in: the search refresh records what it was asked to refresh
create table search.refresh_calls (id bigserial primary key, course_ids uuid[], at timestamptz default now());
create function search.refresh_course_enrichment_scoped_v1(p_ids uuid[], p_force boolean) returns jsonb language sql as $$
  insert into search.refresh_calls(course_ids) values (p_ids) returning jsonb_build_object('refreshed', cardinality(p_ids)) $$;
