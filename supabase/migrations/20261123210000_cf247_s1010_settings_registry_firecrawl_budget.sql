-- CF-247 s1010 (S1-Build; Platform Admin 23 Nov 2026 19:59 AEDT): settings registry for the v1.2 Settings screen, and the Firecrawl daily budget.
-- 1. firecrawl.daily_budget_total changes from 0 to 5 with the Platform Admin's reason ("Standing Authority Charter Section 10 — Tier 1
--    micro-budget cap US$5.00/day"). The setting counts Firecrawl credits a day, so 5 is 5 credits a day, well inside the US$5.00 a day
--    platform cap (budgets.paid_daily_cap_usd, s997). It is changed only if it still holds 0, so a later change made on Settings is never undone.
--    The daily-budget guard (firecrawl.daily_budget_on) stays on; the paused firecrawl-runs job stays paused (no cron change).
-- 2. Every setting gets plain-English help text for the Settings screen: the 33 settings whose help was empty or shorter than 25 characters
--    get one written from their label, unit and the job that reads them. Only empty or short help is filled; no label, value or range changes.
-- The budget-cap flag on admin_boost_queue_read is s997 (budget_cap.firecrawl_budget_cap and dry_lane read this setting live).
-- G1: no job. G2: settings changed with a reason. G3: no consumer object touched (75/48 before and after). Manual locks and active cron jobs
-- checked unchanged. Nothing dropped or deleted.
-- Replaces: nothing.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the settings rows

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1010_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1010_cron on commit drop as select count(*) n from cron.job where active;

-- 1. Firecrawl daily budget (credits a day)
update pipeline.platform_toolset_settings s
   set value = to_jsonb(5), updated_at = now(),
       reason = 'Standing Authority Charter Section 10 — Tier 1 micro-budget cap US$5.00/day (Platform Admin 23 Nov 2026 19:59; CF-247 s1010). This setting counts Firecrawl credits a day: 5 credits, inside the US$5.00 a day platform cap budgets.paid_daily_cap_usd'
 where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_total' and (s.value #>> '{}')::numeric = 0;

-- 2. plain-English help for the Settings screen (only where help is empty or short)
update pipeline.platform_toolset_settings s set help = h.help, updated_at = now()
  from (values
  ('firecrawl', 'map_limit_central', 'The most links one site map may return when the platform looks for a provider''s central pages (fees, English, calendars). A bigger number finds more pages but costs more Firecrawl credits.'),
  ('firecrawl', 'map_limit_central_search', 'The most links one site map search may return when it looks for a single central page by its words. Kept small because the page sought is usually near the top.'),
  ('firecrawl', 'map_limit_scholarships', 'The most links one site map may return when the platform looks for a provider''s scholarship pages. A bigger number finds more pages but costs more Firecrawl credits.'),
  ('firecrawl', 'search_results_cricos', 'How many web search results are checked when the platform looks up a provider by its CRICOS code. More results find more matches but cost more credits.'),
  ('firecrawl', 'search_results_register', 'How many web search results are checked when the platform looks for a provider''s page on a government register.'),
  ('firecrawl', 'search_results_scholarship_discover', 'How many web search results are checked when the platform first looks for a provider''s scholarship pages.'),
  ('firecrawl', 'search_results_scholarship_search', 'How many web search results are checked when the platform searches for one named scholarship.'),
  ('firecrawl', 'search_results_website', 'How many web search results are checked when the platform looks for a provider''s official website.'),
  ('pipeline', 'batch.evidence_dedupe', 'How many stored evidence files the daily clean-up checks for exact duplicates. A duplicate is pointed at the copy already held; nothing that a record uses is lost.'),
  ('pipeline', 'batch.provider_contact_page', 'How many providers one run of the contact-page job checks for a public phone number and email. The job runs every 3 minutes.'),
  ('pipeline', 'batch.provider_facts_search', 'How many web searches one run of the provider-facts job makes for fee schedules, English policies and academic calendars. The job runs every 10 minutes.'),
  ('pipeline', 'onboarding.course_search_wait_hours', 'When a new university is set up, how long the platform waits for the course pages it found to be read before it moves the university on and reports what is missing.'),
  ('pipeline', 'onboarding.proposal_attempts', 'How many times the platform proposes a reader (adapter) for a new university before it stops and asks a person to look at it.'),
  ('pipeline', 'onboarding.sample_courses', 'How many of a new university''s courses are searched for their course pages in one go during set-up.'),
  ('pipeline', 'onboarding.waiting_check_minutes', 'How often the platform checks universities that are waiting to admit or fill in course details, so a ready one moves on without waiting a day.'),
  ('pipeline', 'onboarding.waiting_courses_check_hours', 'How often the platform checks universities that are still waiting for course pages to be found.'),
  ('pipeline', 'recheck.cricos_contact_days', 'How long the platform waits before it reads a provider''s CRICOS contact details again, to pick up changes.'),
  ('pipeline', 'remap.site_days', 'How long the platform waits before it maps a university''s website again to find new or moved course pages.'),
  ('pipeline', 'reread.scholarship_ai_days', 'How long the platform waits before it reads a scholarship page with AI again. A longer wait saves AI spend; a shorter one picks up changes sooner.'),
  ('pipeline', 'reread.scholarship_candidate_days', 'How long the platform waits before it checks again whether a possible scholarship page really is one.'),
  ('pipeline', 'reread.scholarship_listing_days', 'How long the platform waits before it reads a scholarship listing page again to find new or closed awards.'),
  ('pipeline', 'retry.course_page_failed_hours', 'How long the platform waits before it tries again to read a course page whose last read failed.'),
  ('pipeline', 'retry.course_page_http_failed_days', 'How long the platform waits before it tries a course page again after the site answered with an error (for example 404 or 500).'),
  ('pipeline', 'retry.no_website_days', 'How long the platform waits before it looks again for the website of a provider where none was found.'),
  ('pipeline', 'retry.provider_facts_attempts', 'How many times the platform tries to find a provider''s fee schedule, English policy or academic calendar before it stops and lists it as not found.'),
  ('pipeline', 'retry.scholarship_blocked_days', 'How long the platform waits before it tries again to read a scholarship page that the site blocked. A block is never bypassed.'),
  ('pipeline', 'retry.scholarship_candidate_failed_hours', 'How long the platform waits before it tries again to check a possible scholarship page whose last check failed.'),
  ('pipeline', 'retry.scholarship_failed_hours', 'How long the platform waits before it tries again to read a scholarship page whose last read failed.'),
  ('pipeline', 'retry.scholarship_listing_failed_days', 'How long the platform waits before it tries again to read a scholarship listing page whose last read failed.'),
  ('pipeline', 'retry.scholarship_name_mismatch_days', 'How long the platform waits before it reads again a scholarship page whose name did not match the scholarship expected there.'),
  ('pipeline', 'retry.scholarship_waiting_scraper_hours', 'How long the platform waits before it tries again a scholarship page that was waiting for the page reader to be free.'),
  ('pipeline', 'retry.site_map_failed_hours', 'How long the platform waits before it tries again to map a website whose last site map failed.'),
  ('pipeline', 'retry.website_after_budget_days', 'How long the platform waits before it looks again for a provider''s website when the last search stopped because the search budget had run out.')
  ) h(toolset_key, key, help)
 where s.toolset_key = h.toolset_key and s.key = h.key and length(coalesce(btrim(s.help), '')) < 25;

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1010_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1010_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'firecrawl' and key = 'daily_budget_total') not between 0 and 5 then
    raise exception 'post-check: the Firecrawl daily budget is outside 0 to 5 credits';
  end if;
  if (select (value #>> '{}')::boolean from pipeline.platform_toolset_settings where toolset_key = 'firecrawl' and key = 'daily_budget_on') is not true then
    raise exception 'post-check: the Firecrawl daily-budget guard is off';
  end if;
  if exists (select 1 from pipeline.platform_toolset_settings where nullif(btrim(label), '') is null or length(coalesce(btrim(help), '')) < 25) then
    raise exception 'post-check: a setting still has no label or plain-English help';
  end if;
end $post$;
