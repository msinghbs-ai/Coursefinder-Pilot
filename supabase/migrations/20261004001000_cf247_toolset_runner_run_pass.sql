-- CF-247 Decision 252 (4 Oct 2026, 15:10 AEDT). Platform Admin, 14:54: "Proceed with next step."
-- The sample-run worker (toolset-runner) can be started inside the database with a one-time run pass, like every other
-- worker, for a run the Platform Admin has already started with a reason. The worker still accepts the Platform Admin's
-- own sign-in for Continue on the screen. Nothing here changes any admitted value.
insert into pipeline.pilot_nonce_functions(function_name, note) values ('toolset-runner', 'Decision 252: sample runs started by the Platform Admin')
on conflict (function_name) do nothing;
