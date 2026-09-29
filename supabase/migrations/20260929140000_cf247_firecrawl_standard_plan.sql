-- CF-247 complete coverage (Platform Admin, 29 Sep 2026 09:33 IST): Firecrawl upgraded to 100,000 credits a month
-- (up to 50,000 searches or 100,000 pages) with 25 concurrent requests.
--  * budget guard: limit 100,000 units a month, stop at 2,000 remaining (2%); concurrency 20 (5 kept spare);
--  * course pages held for the 1 October reset (script-rendered pages and Firecrawl pages without stored evidence)
--    are released for reading now;
--  * discovery raised from 6 to 8 providers per 2-minute call (the worker maximum).
update pipeline.layer2_acquisition_providers
   set billing_config = billing_config || jsonb_build_object(
         'monthly_vendor_units_limit', 100000,
         'stop_at_vendor_units_remaining', 2000,
         'safety_reserve_percent', 2,
         'plan_tier', 'standard_100k',
         'entitlement_basis', 'user_confirmed_subscription',
         'plan_confirmed_at', '2026-09-29T04:03:00Z',
         'plan_note', '100,000 credits a month (up to 50,000 searches or 100,000 pages), 25 concurrent requests'),
       concurrency = 20,
       change_control_ref = 'CF-247',
       updated_at = now()
 where provider_key = 'firecrawl';

update pipeline.coverage_course_pages
   set next_read_at = now()
 where next_read_at > now() + interval '1 day'
   and (read_status = 'needs_render' or read_status is null);

select cron.alter_job((select jobid from cron.job where jobname='coverage-discover'),
  command => $$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"discover","limit":8}'::jsonb)$$);
