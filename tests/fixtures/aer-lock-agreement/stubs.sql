-- CF-247 AER lock agreement fixture: the settings D-R2 and the scheduled reading read, as live (read 9 Nov 2026). The D-R2 migration (20261103070000) is not
-- replayed in the fixture (its function is loaded from the live capture), so its setting is inserted here with the live value and time (2 Nov 2026 22:07 UTC).
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, unit, used_by, updated_at)
values ('pipeline', 'entry.supersede_lock_fields', 'Entry requirements: course locks that stop a corrected read', 'list',
        '["entry_requirements", "course_url", "official_url"]'::jsonb, 'fields', 'security.course_entry_correction_check_v1', '2026-11-02 22:07:09.670112+00')
on conflict (toolset_key, key) do nothing;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, unit, used_by, updated_at)
values ('pipeline', 'aer.schedule_lock_fields', 'Entry reading: course locks that stop a read', 'list', '["entry_requirements"]'::jsonb, 'fields',
        'security.aer_course_population_v1', '2026-11-03 05:18:01.36822+00')
on conflict (toolset_key, key) do nothing;
-- the lock table as live (the earlier fixtures carry entity, entity_id, field, mode and set_at; live also records who set it)
alter table pipeline.manual_locks add column if not exists set_by uuid;
create schema if not exists fxl;
create or replace function fxl.ok(p_ok boolean, p_what text) returns void language plpgsql as $$
begin if not coalesce(p_ok, false) then raise exception 'FAILED: %', p_what; end if; raise notice 'ok: %', p_what; end $$;
