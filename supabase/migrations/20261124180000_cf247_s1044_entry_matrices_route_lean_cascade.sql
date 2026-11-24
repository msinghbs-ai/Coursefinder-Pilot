-- CF-247 s1044 (S1-AER-Claude, Platform Admin brief 24 Nov 2026 15:15 AEDT): switch the entry_matrices route on with the lean-model cascade.
-- Why: the route has been off since 16 Nov 2026 16:52 (Qwen3 30B 2/50 on the AER v1 prompt), so coverage-sweep holds every table that no $0 reader proves
--      as held_unparsed (ACU layout PDF, UOW bare-point table). Platform Admin 24 Nov 15:15: enable the lean models, GPT-4.1 mini on escalation.
-- Honesty: each model is recorded as qualified = provisional (Platform Admin decision, not a benchmark pass). Admission rules, the strict-proof rule
--          (no printed scale, no value), the machine check and Layer 4 are unchanged; nothing is admitted because of this change alone.
-- Order: mistral-small-3.2 first (pinned alone on the v2 shadow, round 2 source integrity 83.3%), then qwen3-30b, then gpt-4.1-mini on escalation.
-- Caps: the route's own daily cap (pipeline.ai_service_routes.daily_usd_cap, a setting shown on Settings) is unchanged.
-- Replaces: the 16 Nov 2026 16:52 route hold on entry_matrices (enabled = false, cascade qwen3-30b only).
-- Retires: nothing.
-- Consumer API change approved: none; this change touches no consumer API object.

do $g$
begin
  if not exists (select 1 from pipeline.ai_service_routes where service_code = 'entry_matrices') then raise exception 'entry_matrices route missing; nothing applied'; end if;
  if (select count(*) from pipeline.ai_model_catalogue where code in ('mistral-small-3.2', 'qwen3-30b', 'gpt-4.1-mini') and status = 'allowed') <> 3 then raise exception 'a cascade model is not allowed in the catalogue; nothing applied'; end if;
end $g$;

-- 1 ------------------------------------------------------------------------------------------------------------ allow GPT-4.1 mini on this route
update pipeline.ai_model_catalogue
   set note = 'Allowed for provider descriptions (Platform Admin 19 Nov 2026 07:39) and as the escalation model of the entry_matrices route (Platform Admin 24 Nov 2026 15:15).',
       changed_at = now(), reason = 'Platform Admin 24 Nov 2026 15:15: escalation model on the entry_matrices route'
 where code = 'gpt-4.1-mini';

-- 2 -------------------------------------------------------------------------------------------------------------------- provisional qualifications
insert into pipeline.ai_route_qualifications (service_code, model_code, prompt_version, status, provisional, evidence, evidence_detail, qualified_at, changed_at)
select 'entry_matrices', m.code, 'entry-matrix-v0.1.4', 'qualified', true,
       'Platform Admin decision 24 Nov 2026 15:15 AEDT (enable the lean models on entry_matrices; GPT-4.1 mini on escalation). Provisional: not a benchmark pass on entry-matrix-v0.1.4.',
       m.detail, now(), now()
  from (values ('mistral-small-3.2', '{"basis":"v2 shadow pin, round 2 source integrity 83.3%, gate 100%"}'::jsonb),
               ('gpt-4.1-mini',      '{"basis":"previous model of this route (setting entry.matrix_model)"}'::jsonb)) m(code, detail)
 where not exists (select 1 from pipeline.ai_route_qualifications q where q.service_code = 'entry_matrices' and q.model_code = m.code);

update pipeline.ai_route_qualifications
   set status = 'qualified', provisional = true, qualified_at = now(), changed_at = now(),
       note = 'Platform Admin 24 Nov 2026 15:15: back on the entry_matrices cascade as second model. Provisional. Benchmark round 2 (Admin #519) was 2/50 right with 18 timeouts; admission rules and Layer 4 checks catch what it gets wrong.',
       evidence = 'Platform Admin decision 24 Nov 2026 15:15 AEDT; earlier result 2/50 right (Admin #519) stays on record in evidence_detail',
       evidence_detail = jsonb_build_object('round2_right', 2, 'round2_cases', 50, 'round2_timeouts', 18, 'earlier_decision', 'Platform Admin 16 Nov 2026 16:52')
 where service_code = 'entry_matrices' and model_code = 'qwen3-30b';

-- 3 ------------------------------------------------------------------------------------------------------------------------------- the route
update pipeline.ai_service_routes
   set enabled = true, cascade = array['mistral-small-3.2', 'qwen3-30b', 'gpt-4.1-mini'], previous_model = 'qwen/qwen3-30b-a3b-instruct-2507', changed_at = now(),
       note = 'Provisional cascade: Mistral Small 3.2, then Qwen3 30B, then GPT-4.1 mini on escalation. Deterministic readers (PDF cells, ruled grid, HTML table) run first at $0.',
       reason = 'Platform Admin 24 Nov 2026 15:15: enable the lean-model cascade on entry_matrices so tables no deterministic reader proves are no longer held as no-qualified-model'
 where service_code = 'entry_matrices';
