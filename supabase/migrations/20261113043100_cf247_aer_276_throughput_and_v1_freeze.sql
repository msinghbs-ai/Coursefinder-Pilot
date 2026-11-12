-- CF-247 Decision 276 (Platform Admin 12 Nov 2026 17:20): AER admission throughput.
-- Guards: G1 (no job), G2 (an existing setting changed with a reason, within its range), G3 (no consumer API object), Decision 260, Layer 4 authority unchanged.
-- What:
--   1. aer.machine_daily_max 300 -> 1,000 (decision 2: "Approve increasing aer.machine_daily_max from 300 to 1,000 ... Preserve the current verified automatic-admission
--      eligibility rules. Retain the 5% Layer 4 random audit and withdrawal controls ... Review observed throughput and audit findings after seven days").
--      Evidence: the course rule reached 300 within about 8 hours on 11 Nov with about 500 passing reads waiting.
--   Not changed: aer.schedule_daily_max (200). Measured before merge (12 Nov 2026 17:40 AEDT): active course-page rows are mostly domestic or general (ATAR cut-offs,
--   "an Australian bachelor's degree", prerequisites, work experience; none names an applicant country, 45 are international minimum grades), so more course-page
--   reads under v1 would spend AI without moving the resolver's coverage. Course pages are read for applicant countries under v2 (Decision 276).
-- Replaces: nothing (one value). Retires: nothing.
-- Reversal without code: the setting back to 300.

update pipeline.platform_toolset_settings set value = to_jsonb(1000), updated_at = now(),
       reason = 'Decision 276 (Platform Admin 12 Nov 2026 17:20): 300 to 1,000; eligibility, 5% audit and withdrawal unchanged; review after seven days'
 where toolset_key = 'pipeline' and key = 'aer.machine_daily_max' and value = to_jsonb(300);
do $c$
begin
  if security.pipeline_num_v1('aer.machine_daily_max', 0) <> 1000 then
    raise exception 'post-check: settings not applied';
  end if;
end $c$;
