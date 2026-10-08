-- CF-247 Phase 2 (8 Oct 2026): the CRICOS version 2 adapter pass of the 11 Aug archive stopped at its last slice (records and both
-- location sets in one call ran out of worker resources; nothing from that call was saved). coverage-sweep v0.17.31 reads each set in a
-- call of its own after the records, so the run carries on from the same position.
update pipeline.register_replay_runs set error = null, done_at = null, lease_until = null, attempts = 0, attempt_at = null
 where label = 'CRICOS 11 Aug 2026 (v2, again)' and not adapter_done and adapter_pos = 24000
   and error = 'adapter: stopped after three calls ended without saving at position 24000 (probably the worker resource limit)';
select cron.schedule('register-replay', '* * * * *', 'select security.register_replay_tick_v1()');
