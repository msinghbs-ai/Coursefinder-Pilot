-- CF-247 (2 Oct 2026, ~23:10 AEST). Found while measuring tonight's run: cron job coverage-admit called
-- security.coverage_admission_apply_v1(500) with no extractor, so the function's default ('coverage-sweep-v0.5.4')
-- was used. Every stored page now carries extractor 'coverage-sweep-v0.5.6' (re-extracted when v0.5.5 and v0.5.6
-- were released on 2 Oct 2026), so the admission plan matched no page and nothing was admitted by this job since then:
-- 480 official course links proven by the identity rule were waiting (one admitted by hand as a check at 23:08).
-- The job now names the current extractor. The admission rules themselves (country identities, write only where empty,
-- differences to Layer 4) are unchanged.
select cron.alter_job((select jobid from cron.job where jobname = 'coverage-admit'),
  command := $$select security.coverage_admission_apply_v1(500, 'coverage-sweep-v0.5.6')$$);
