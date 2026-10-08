-- CF-247 Phase 2 (8 Oct 2026): starts the replay driver for the Canadian catalogue replays (migration 3900), after coverage-sweep v0.17.27
-- is deployed. The three CRICOS version 2 replays stopped on their first save of the location sets (a location repeated in the Locations
-- file was saved twice in one statement); v0.17.27 numbers repeated keys, so the three archives are replayed again. Stops itself when done.
insert into pipeline.register_replay_runs(source_id, label, storage_path, zip_hash, keep_fields, created_at)
select r.source_id, replace(r.label, '(v2)', '(v2, again)'), r.storage_path, r.zip_hash, false, now() + make_interval(secs => 600 + x.n)
  from (values ('CRICOS 11 Aug 2026 (v2)', 0), ('CRICOS 26 Sep 2026 (v2)', 1), ('CRICOS 30 Sep 2026 (newest) (v2)', 2)) x(label, n)
  join pipeline.register_replay_runs r on r.label = x.label;
select cron.schedule('register-replay', '* * * * *', 'select security.register_replay_tick_v1()');
