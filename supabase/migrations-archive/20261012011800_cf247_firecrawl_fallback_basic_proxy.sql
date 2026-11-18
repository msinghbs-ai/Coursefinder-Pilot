-- CF-247 v2.15.261 (Platform Admin, 12 Oct 2026 21:21, Firecrawl credits): "Read found pages directly first, and use Firecrawl only when
-- the direct read is blocked or needs a browser. Also switch Firecrawl to its basic proxy, and turn the second reader off."
-- In the hour after v2.15.260 Firecrawl billed about 23,500 credits (about 7 a page; 76% of found pages were the wrong page).
--   1 Firecrawl page reads use the basic proxy (setting firecrawl.read_proxy, used by Firecrawl runs; the worker v0.21.3 sends
--     proxy "basic" on every scrape).
--   2 The second course-page reader (coverage-read-2) is switched off (paused, not removed; it stays in the automation catalogue and
--     can be resumed on Scheduled jobs › Automations).
-- The direct-first reading itself is in worker coverage-sweep v0.21.3. Nothing is dropped or deleted.

update pipeline.platform_toolset_settings set value = '"basic"'::jsonb, updated_at = now(),
       reason = 'Platform Admin, 12 Oct 2026 21:21: switch Firecrawl to its basic proxy (credits: about 7 a page with auto)'
 where toolset_key = 'firecrawl' and key = 'read_proxy';

select cron.alter_job(j.jobid, active := false) from cron.job j where j.jobname = 'coverage-read-2';

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('automations', 'pause', 'coverage-read-2',
        jsonb_build_object('reason', 'Platform Admin, 12 Oct 2026 21:21: turn the second reader off (Firecrawl credits)', 'change', 'CF-247 v2.15.261'),
        '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

do $chk$ begin
  if (select value #>> '{}' from pipeline.platform_toolset_settings where toolset_key = 'firecrawl' and key = 'read_proxy') <> 'basic' then
    raise exception 'v2.15.261 post-check: read_proxy is not basic'; end if;
  if (select active from cron.job where jobname = 'coverage-read-2') then raise exception 'v2.15.261 post-check: coverage-read-2 still active'; end if;
end $chk$;
