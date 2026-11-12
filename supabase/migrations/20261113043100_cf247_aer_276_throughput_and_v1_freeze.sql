-- CF-247 Decision 276 (Platform Admin 12 Nov 2026 17:20): AER admission throughput and course-page reading capacity.
-- Guards: G1 (no job), G2 (two existing settings changed with a reason, within their ranges), G3 (no consumer API object), Decision 260, Layer 4 authority unchanged.
-- What:
--   1. aer.machine_daily_max 300 -> 1,000 (decision 2: "Approve increasing aer.machine_daily_max from 300 to 1,000 ... Preserve the current verified automatic-admission
--      eligibility rules. Retain the 5% Layer 4 random audit and withdrawal controls ... Review observed throughput and audit findings after seven days").
--      Evidence: the course rule reached 300 within about 8 hours on 11 Nov with about 500 passing reads waiting.
--   2. aer.schedule_daily_max 200 -> 600 (decision 4, workstream B: "Continue discovering entry-requirement sources for missing providers ... Use the current approved
--      Firecrawl and AI budgets"). Evidence (live, 12 Nov 2026 17:10 AEDT): the discovery campaign recorded "course pages found" (no country table) for Canterbury,
--      Murdoch, La Trobe, ACU, JCU, Southern Cross and Sunshine Coast (1,372 courses, 1,050 course pages bound); their requirements are read course by course by the
--      scheduled reader, capped at 200 a day across all providers (the hourly batch of 20 then binds at about 480 a day). Spend stays bounded by the existing guards, unchanged: the OpenRouter credit floor, AI limits,
--      aer.schedule_layer4_max (600, back-pressure), aer.schedule_per_provider (5) and the course-read cost estimate (entry.course_read_cost_usd 0.005).
-- Replaces: nothing (two values). Retires: nothing.
-- Reversal without code: either setting back to its earlier value.

update pipeline.platform_toolset_settings set value = to_jsonb(1000), updated_at = now(),
       reason = 'Decision 276 (Platform Admin 12 Nov 2026 17:20): 300 to 1,000; eligibility, 5% audit and withdrawal unchanged; review after seven days'
 where toolset_key = 'pipeline' and key = 'aer.machine_daily_max' and value = to_jsonb(300);
update pipeline.platform_toolset_settings set value = to_jsonb(600), updated_at = now(),
       reason = 'Decision 276 workstream B (12 Nov 2026): course-page reading for universities that publish on course pages only; existing spend and Layer 4 guards unchanged'
 where toolset_key = 'pipeline' and key = 'aer.schedule_daily_max' and value = to_jsonb(200);

do $c$
begin
  if security.pipeline_num_v1('aer.machine_daily_max', 0) <> 1000 or security.pipeline_num_v1('aer.schedule_daily_max', 0) <> 600 then
    raise exception 'post-check: settings not applied';
  end if;
end $c$;
