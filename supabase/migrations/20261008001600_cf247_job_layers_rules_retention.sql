-- CF-247, 8 Oct 2026: the scheduled jobs added today were not listed in pipeline.platform_job_layers, so the scheduled-task screens
-- could not place them by layer. Layer 4 review rules: l4-rule-unofficial-source (Rule 1), l4-rule-fee-year-align (Rule 3),
-- l4-rule-low-agreement (Rule 4). Platform: retention-worker (Storage & retention). Existing rows are left as they are.
insert into pipeline.platform_job_layers(jobname, layer, updated_at) values
  ('l4-rule-unofficial-source', 4, now()), ('l4-rule-fee-year-align', 4, now()), ('l4-rule-low-agreement', 4, now()), ('retention-worker', 0, now())
on conflict (jobname) do nothing;
