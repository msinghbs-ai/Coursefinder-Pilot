-- CF-247 Phase 2 (8 Oct 2026): starts the side-by-side replay driver again for the three NZQA runs (it stopped itself after the CRICOS
-- runs). Applied only after worker v0.17.21 is deployed, so no older worker reads a run that lists files. Stops itself when done.
select cron.schedule('register-replay', '* * * * *', 'select security.register_replay_tick_v1()');
