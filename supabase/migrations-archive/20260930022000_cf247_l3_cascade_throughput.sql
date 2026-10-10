-- CF-247 cost-first cascade: with tier-1 pages at about US$0.0002 each, the same daily guards (intake US$4, English
-- US$4) cover far more pages, so each 2-minute route run claims up to 25 pages (was 8) with 6 in parallel (was 4).
-- Guards, credit floor and admission are unchanged.
select cron.schedule('layer3-intake-route','*/2 * * * *',$$select pipeline.svc_pilot_submit_nonce('layer3-model-routing','{"mode":"work","task":"intake","limit":25,"concurrency":6}'::jsonb)$$);
select cron.schedule('layer3-english-route','1-59/2 * * * *',$$select pipeline.svc_pilot_submit_nonce('layer3-model-routing','{"mode":"work","task":"english","limit":25,"concurrency":6}'::jsonb)$$);
