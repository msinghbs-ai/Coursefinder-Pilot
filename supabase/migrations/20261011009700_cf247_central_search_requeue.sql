-- CF-247 (11 Oct 2026): providers whose central pages were searched by worker v0.19.0 before the targeted maps and the noise rules
-- (their evidence has no "searched" list) are searched again with the improved worker. Only queue state changes; nothing is deleted.
update pipeline.provider_central_search
   set state = 'queued', leased_until = null, attempts = 0, updated_at = now()
 where state = 'done' and not (coalesce(evidence, '{}'::jsonb) ? 'searched');
