-- CF-247 Phase 2 (8 Oct 2026): before NZQA and PRISMS are switched on, their newest stored capture is replayed once more with the
-- deployed engine (moved to _shared, NZQA records now built by htmlAdapterRows), so the switch gate rests on the code that will run.
insert into pipeline.register_replay_runs(source_id, label, storage_path, paths, zip_hash, keep_fields, created_at)
select r.source_id, r.label || ' (before switch-on)', r.storage_path, r.paths, r.zip_hash, false, now() + make_interval(secs => x.n)
  from (values ('NZQA 8 Oct 2026 07:34 (newest)', 0), ('PRISMS SA4 December 2025', 1)) x(label, n)
  join pipeline.register_replay_runs r on r.label = x.label;
select cron.schedule('register-replay', '* * * * *', 'select security.register_replay_tick_v1()');
