-- Guards: Provider Description actual role attributes and manual lock key constraints.
alter role anon inherit nologin nobypassrls;
alter role authenticated inherit nologin nobypassrls;
alter role service_role inherit nologin bypassrls;
do $p$ begin if not exists(select 1 from pg_constraint where conrelid='pipeline.manual_locks'::regclass and conname='manual_locks_entity_check') then alter table pipeline.manual_locks add constraint manual_locks_entity_check CHECK (entity = ANY (ARRAY['course'::text, 'provider'::text, 'campus'::text, 'scholarship'::text])); end if; end $p$;
do $p$ begin if not exists(select 1 from pg_constraint where conrelid='pipeline.manual_locks'::regclass and conname='manual_locks_mode_check') then alter table pipeline.manual_locks add constraint manual_locks_mode_check CHECK (mode = ANY (ARRAY['value'::text, 'removed'::text])); end if; end $p$;
do $p$ begin if not exists(select 1 from pg_constraint where conrelid='pipeline.manual_locks'::regclass and conname='manual_locks_pkey') then alter table pipeline.manual_locks add constraint manual_locks_pkey PRIMARY KEY (entity, entity_id, field); end if; end $p$;
