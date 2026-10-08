-- CF-247 Phase 2 (8 Oct 2026): four Canadian replays ran before coverage-sweep v0.17.28 read fields in dependency order (Conestoga read 0
-- records, Sheridan and two IRCC DLI copies read a field before the one it depends on). They are replayed again; the diagnosis run added
-- for Conestoga is closed as no longer needed. The driver is (re)started; it stops itself when done.
update pipeline.register_replay_runs set error = 'closed: diagnosis no longer needed (field order fixed in coverage-sweep v0.17.28)', done_at = now()
 where label = 'ca_conestoga 13 Aug 2026 14:44 (fields kept, diagnosis)' and done_at is null;
insert into pipeline.register_replay_runs(source_id, label, storage_path, zip_hash, keep_fields, created_at)
select r.source_id, r.label || ' (after the field-order fix)', r.storage_path, r.zip_hash, false, now() + make_interval(secs => (row_number() over (order by r.created_at))::int)
  from pipeline.register_replay_runs r
 where r.label in ('ca_conestoga 13 Aug 2026 14:44', 'ca_sheridan 14 Aug 2026 09:34', 'ca_ircc_dli 13 Aug 2026 09:46', 'ca_ircc_dli 13 Aug 2026 12:21');
select cron.schedule('register-replay', '* * * * *', 'select security.register_replay_tick_v1()');
