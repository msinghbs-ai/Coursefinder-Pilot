-- Guards: Platform Admin direction 5 Nov 2026 15:50 §6 (production-equivalent database): production shape of pipeline.manual_locks
-- (read 5 Nov 2026 16:10: entity, entity_id, field, mode not null check value|removed, set_by, set_at; primary key entity, entity_id, field).
alter table pipeline.manual_locks add column if not exists mode text, add column if not exists set_by uuid, add column if not exists set_at timestamptz;
update pipeline.manual_locks set mode = 'value' where mode is null;
alter table pipeline.manual_locks alter column mode set not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'pipeline.manual_locks'::regclass and pg_get_constraintdef(oid) like '%mode%') then
    alter table pipeline.manual_locks add constraint manual_locks_mode_check check (mode in ('value', 'removed'));
  end if;
end $$;
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'pipeline.manual_locks'::regclass and contype = 'p') then
    alter table pipeline.manual_locks add primary key (entity, entity_id, field);
  end if;
end $$;
