-- CF-247 Phase 2 (8 Oct 2026): replays the five stored QILT workbooks again now that qilt-au-etl v0.3.1 stores the upper bound and the
-- reference copy (coverage-sweep v0.17.23) follows it. Starts the replay driver; it stops itself when done.
insert into pipeline.register_replay_runs(source_id, label, storage_path, zip_hash, keep_fields, created_at)
select r.source_id, r.label || ' (after the v0.3.1 fix)', r.storage_path, r.zip_hash, false, now() + make_interval(secs => row_number() over (order by r.created_at)::int)
  from pipeline.register_replay_runs r
 where r.label in ('QILT GOS 2025', 'QILT SES 2024', 'QILT SES 2025', 'QILT GOS-L 2025', 'QILT ESS 2025');
select cron.schedule('register-replay', '* * * * *', 'select security.register_replay_tick_v1()');
