-- CF-247 S2 - BOOST (Platform Admin directive Thu 19 Nov 2026 05:40, item 3: s723, s724 and s726, REQ-61, REQ-69, REQ-70): the Boost multi-field
-- prompt is boost-fields-v2 (worker coverage-sweep v1.0.25). Intakes are every start month the course page announces, not only the next one;
-- an application_deadlines field (date, the intake it belongs to, and the verbatim quote) is checked by page check boost-fields-check-v3.
-- This change is records only:
--   (1) the route qualification row of boost_fields_extract (Qwen3 30B, provisional) names the prompt it now runs. ai_route_v1 checks the
--       service and model, not the prompt version, so the route keeps running; every result stays shadow and each field's owner rule
--       decides admission.
--   (2) the help of setting boost.fields_lanes lists application_deadlines as a field that can be asked. The setting's value is unchanged,
--       so live reading does not ask for deadlines; the offline replay (workflow boost-fields-replay.yml) asks for them. Asking them live
--       and admitting them is a separate recorded step once the replay shows the qualification bar (s725).
-- A passing replay never switches anything on by itself. No table, function, job or setting is added (G3 stays at 75 functions, 48 tables).
-- Numbered 20261119081500: above the highest migration on main (20261119080000, Pilot #1345) and clear of the numbers held by open PRs (20261119060000 in #1335,
-- 20261119070000 in #1331).
-- Replaces: the boost_fields_extract qualification record of prompt boost-fields-v1 with boost-fields-v2
-- Retires: nothing

set local lock_timeout = '5s';

do $g$
begin
  if (select count(*) from pipeline.ai_route_qualifications where service_code = 'boost_fields_extract') <> 1
     or not exists (select 1 from pipeline.ai_route_qualifications where service_code = 'boost_fields_extract' and model_code = 'qwen3-30b' and prompt_version = 'boost-fields-v1') then
    raise exception 'guard: the boost_fields_extract qualification is not the one Qwen3 30B row on boost-fields-v1';
  end if;
end $g$;

update pipeline.ai_route_qualifications
   set prompt_version = 'boost-fields-v2', changed_at = now(),
       note = 'S2 - BOOST 19 Nov 2026 (s723, s726): prompt boost-fields-v2 (every announced intake month; application deadlines with their intake, asked only where boost.fields_lanes names them). Every result is shadow; each field''s owner rule decides admission. v1: 18 Nov 2026'
 where service_code = 'boost_fields_extract' and model_code = 'qwen3-30b' and prompt_version = 'boost-fields-v1';

update pipeline.platform_toolset_settings
   set help = 'The gap fields asked for in one pass per stored page. Any of: course_description, delivery_mode, intakes, course_fees, aer_entry, application_deadlines (application_deadlines is asked offline by the replay until its admission is decided).',
       updated_at = now(), reason = 'CF-247 S2 - BOOST, 19 Nov 2026 (s726): application_deadlines can be asked; the value is unchanged'
 where toolset_key = 'pipeline' and key = 'boost.fields_lanes';

do $c$
begin
  if not exists (select 1 from pipeline.ai_route_qualifications where service_code = 'boost_fields_extract' and model_code = 'qwen3-30b' and prompt_version = 'boost-fields-v2' and status = 'qualified' and provisional) then
    raise exception 'post-check: the boost_fields_extract qualification is not Qwen3 30B on boost-fields-v2, qualified and provisional';
  end if;
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'boost.fields_lanes')
     <> '["course_description","delivery_mode","intakes","course_fees","aer_entry"]'::jsonb then
    raise exception 'post-check: the value of boost.fields_lanes changed';
  end if;
end $c$;
