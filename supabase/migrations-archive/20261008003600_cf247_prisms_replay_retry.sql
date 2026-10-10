-- CF-247 Phase 2 (8 Oct 2026): the PRISMS pre-switch replay stopped on an overlapping call (its adapter save hit the statement limit). With
-- runs now leased to one call (migration 3500, coverage-sweep v0.17.24) its adapter pass is run again; the replay driver is started.
update pipeline.register_replay_runs set error = null, done_at = null, adapter_pos = 0, lease_until = null
 where label = 'PRISMS SA4 December 2025 (before switch-on)' and not adapter_done and error like 'adapter: svc_register_replay_save_v2: canceling statement%';
select cron.schedule('register-replay', '* * * * *', 'select security.register_replay_tick_v1()');
