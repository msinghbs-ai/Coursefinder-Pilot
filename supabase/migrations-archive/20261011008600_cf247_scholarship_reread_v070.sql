-- CF-247 (11 Oct 2026): the 38 scholarship pages read by reader v0.7.0 in the minutes before v0.7.1 was deployed are read again
-- now (v0.7.0 could read courses named after "excluding" as eligible courses). Nothing is dropped or deleted.
update pipeline.scholarship_pages set next_read_at = now(), attempts = 0, leased_until = null
 where facts->>'extractor' = 'scholarship-sweep-v0.7.0';
