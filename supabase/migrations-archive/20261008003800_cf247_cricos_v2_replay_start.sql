-- CF-247 Phase 2 (8 Oct 2026): starts the replay driver for the three CRICOS version 2 replays (migration 3700). Stops itself when done.
select cron.schedule('register-replay', '* * * * *', 'select security.register_replay_tick_v1()');
