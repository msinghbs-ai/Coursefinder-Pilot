-- Guards: F-PDESC (Platform Admin decision 9 Nov 2026): the production-shaped columns the register-fact profile reads, added to the scratch database's minimal stubs
-- (read from the live schema 9 Nov 2026: ref.countries.name, ref.study_levels.id, ref.fields_of_study, catalogue.courses.study_level_id and primary_field_id). Scratch database only.
alter table ref.countries add column if not exists name text;
alter table ref.study_levels add column if not exists id uuid default gen_random_uuid();
create table if not exists ref.fields_of_study (id uuid primary key default gen_random_uuid(), name text not null);
alter table catalogue.courses add column if not exists study_level_id uuid;
alter table catalogue.courses add column if not exists primary_field_id uuid;
create table if not exists pipeline.platform_toolsets(key text primary key, enforcement text, reason text, updated_by uuid, updated_at timestamptz);
create table if not exists pipeline.platform_job_layers(jobname text primary key, layer int, updated_at timestamptz);
create table if not exists pipeline.platform_notice_acks(notice_key text primary key, acknowledged_at timestamptz, acknowledged_by uuid, reason text);
update ref.countries set name = case iso_alpha2 when 'AU' then 'Australia' when 'NZ' then 'New Zealand' when 'CA' then 'Canada' end where name is null;

-- production shape of the manual-lock guard on providers (read 9 Nov 2026): a locked field is silently put back to its old value by the trigger, the update itself succeeds
create or replace function security.manual_field_guard() returns trigger language plpgsql security definer set search_path to '' as $f$
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
end $f$;
drop trigger if exists manual_lock_guard on catalogue.providers;
create trigger manual_lock_guard before update on catalogue.providers for each row execute function security.manual_field_guard();
