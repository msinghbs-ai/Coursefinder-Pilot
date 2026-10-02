-- CF-247 (2 Oct 2026, ~23:00 AEST). The OpenRouter key works again (the Layer 3 router's latest run validated 18 pages
-- after the weekly-limit refusals). The link matcher's schedule is switched back on; refusals now return items to the
-- queue without using an attempt (migration 20261002185100).
select cron.alter_job((select jobid from cron.job where jobname = 'coverage-ai-match'), active := true);
