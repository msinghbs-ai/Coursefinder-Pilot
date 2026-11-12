-- CF-247 AER v2 step 1 switched on (Decision 276, Platform Admin 12 Nov 2026 17:20: "Approve AER v2 steps 0–1 ... Step 1 runs the new engine in trial alongside the
-- current one, with no change to admissions, for about US$10–20 and no Firecrawl"; 19:09 "Proceed without depending on me").
-- Guards: G1 (job aer-v2-shadow catalogued in #1068), G2 (an existing switch, with a reason), G3 (no consumer API object), Decision 260, Layer 4 authority unchanged:
--   the shadow reader admits nothing, writes no catalogue table and raises no Layer 4 item; it stops at aer.v2_shadow_budget_usd (20) and its daily share.
-- Evidence: #1068 deployed and verified live 12 Nov 2026 21:15 AEDT (trial version aer-v2-course-v1 pinned to openai/gpt-4.1-mini, sha-256 4a51edd2..., job aer-v2-shadow
--   at :08 and :38, catalogued; the switch shipped at 0). The switch-on is the Platform Admin's decision recorded above, not a side effect of a passing check.
-- Replaces: nothing. Retires: nothing.

update pipeline.platform_toolset_settings set value = to_jsonb(1), updated_at = now(),
       reason = 'Decision 276 step 1 (Platform Admin 12 Nov 2026 17:20): shadow trial on stored course pages, no admission change, within the US$20 trial budget'
 where toolset_key = 'pipeline' and key = 'aer.v2_shadow_on' and value = to_jsonb(0);
do $c$ begin if security.pipeline_num_v1('aer.v2_shadow_on', 0) <> 1 then raise exception 'post-check: shadow switch'; end if; end $c$;
