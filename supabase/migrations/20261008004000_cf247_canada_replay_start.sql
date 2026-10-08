-- CF-247 Phase 2 (8 Oct 2026): starts the replay driver for the Canadian catalogue replays (migration 3900), after coverage-sweep v0.17.26
-- is deployed. Stops itself when done.
select cron.schedule('register-replay', '* * * * *', 'select security.register_replay_tick_v1()');
