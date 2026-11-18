-- CF-247 F-SCH.01 shadow review: an international proof must name international students or applicants as who may apply (worker coverage-sweep v0.76.0)
-- Decision: Platform Admin 12 Nov 2026 11:50 AEDT, decision 2: act on evidence-proven cases through the existing admission policy after validation succeeds.
-- Shadow review (live, 12 Nov 2026 12:45 AEDT; first 200 reads, US$0.037): 194 silent, 6 proven. Of 5 international proofs, 3 are right (the
--   "(international)" eligibility tag twice; "or an International student") and 2 are course names ("Master of International Business"; "an
--   international business honours program"). One domestic proof is right. Validation did not pass, so sch_elig.apply_on stays 0.
-- What: the 5 international proofs read so far are read again (stored copies, no Firecrawl) by worker v0.76.0, whose eligibility proof requires
--   "international" to describe who may apply. Nothing else changes; the reader stays in shadow.
-- Guards: G1 (no job), G2 (no new value; the re-read delay below is a deploy-order safety value), G3 (no consumer API object), Decision 260.
-- Replaces: nothing. Retires: nothing.
do $r$
declare v_n int;
begin
  update pipeline.scholarship_eligibility_reads
     set state = 'queued', outcome = null, result = null, applied = null, tries = 0, queued_at = now(), updated_at = now(),
         next_try_at = now() + interval '20 minutes'  -- fixed: after deploy-on-merge has deployed worker v0.76.0, so the new proof reads them
   where outcome = 'proven' and result->>'audience' in ('international', 'both') and (applied is null or applied->>'mode' = 'shadow');
  get diagnostics v_n = row_count;
  raise notice 'international proofs queued to be read again: %', v_n;
  if security.pipeline_num_v1('sch_elig.apply_on', -1) <> 0 then raise exception 'post-check: the reader stays in shadow'; end if;
end $r$;
