-- CF-247: keep AI reading until the OpenRouter credit runs out (Platform Admin 12 Nov 2026 21:47: "Keep using ai until credit runs out").
-- Guards: G2 (the floor stays a setting, changed here with the Platform Admin's reason), G3 (no consumer API object), Decision 260.
-- Evidence (12 Nov 2026 21:45 AEDT): balance about US$19.69, floor US$5. The AI enforcement mode is observe, so security.ai_use_refusal_v1 refuses
--   nothing, but the AER schedule, the course entry batch and programme, AER read now, E13 recovery and the Layer 3 fact claim each stop at the floor
--   themselves. At US$5 they would stop with about US$5 unspent.
-- What: openrouter.credit_floor_usd 5 -> 0.50. Not 0: a call that starts with less than the cost of one read fails at OpenRouter and spends a try
--   (an item can then be marked failed); US$0.50 is about 300 course reads at today's cost, so almost all the credit is used.
-- Reversal without code: set the floor back on Models & services › Toolsets & limits, with a reason.
-- Replaces: nothing. Retires: nothing.

update pipeline.platform_toolset_settings
   set value = to_jsonb(0.5), updated_at = now(),
       reason = 'Platform Admin 12 Nov 2026 21:47: "Keep using ai until credit runs out" (floor 5 -> 0.50; 0.50 keeps the last call from failing at OpenRouter)'
 where toolset_key = 'openrouter' and key = 'credit_floor_usd' and (value #>> '{}')::numeric = 5;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('toolsets', 'setting_change', 'openrouter.credit_floor_usd',
        jsonb_build_object('from', 5, 'to', 0.5, 'reason', 'Platform Admin 12 Nov 2026 21:47: Keep using ai until credit runs out'), null);
