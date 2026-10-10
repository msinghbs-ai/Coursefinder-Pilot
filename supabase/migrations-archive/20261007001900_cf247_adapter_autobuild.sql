-- CF-247, 7 Oct 2026 (Platform Admin 20:28 and decisions): build an adapter automatically.
-- Decisions: automatic admission with checks (a field is admitted when it passes the admit rule AND the adapter's readings agree with
-- values already held on at least 3 courses at 90% or more, read on at least 5 pages); up to 150 Firecrawl credits a build; at most 25
-- builds a day. This amends the rule that a passing check never switches anything on by itself, for automatic builds only; every step
-- is logged and admission can be switched off at once. The builder's AI allowance is raised to US$1.50 and 60 proposals a day to fit.
-- Steps (one cron tick every 2 minutes): find course pages with Firecrawl when fewer than 3 are read -> capture sample pages -> the
-- pinned OpenRouter model proposes the settings -> save (switched on, testing) and apply to stored pages -> Qualify -> admit the fields
-- that pass the checks -> attach central pages found among the provider's stored links. Each step calls the existing admin
-- functions as the Platform Admin who asked, so their own checks and logs apply.

-- Part 1 of 3: builder allowance and the automatic-build settings.

update pipeline.platform_toolset_settings set value = to_jsonb(1.5), reason = 'CF-247 7 Oct 2026: automatic builds, up to 25 a day', updated_at = now()
 where toolset_key = 'firecrawl' and key = 'builder_ai_daily_usd';
update pipeline.platform_toolset_settings set value = to_jsonb(60), reason = 'CF-247 7 Oct 2026: automatic builds, up to 25 a day', updated_at = now()
 where toolset_key = 'firecrawl' and key = 'builder_proposals_per_day';
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, reason, updated_at) values
 ('firecrawl', 'autobuild_per_day', 'Automatic builds a day', 'The most automatic adapter builds that may start in a day (Melbourne time).', 'number', to_jsonb(25), 0, 200, 'builds', 550, 'Adapter builder', 'CF-247 7 Oct 2026', now()),
 ('firecrawl', 'autobuild_credits', 'Firecrawl credits a build', 'The most Firecrawl credits one automatic build may use (finding and reading pages, and the sample pages).', 'number', to_jsonb(150), 10, 1000, 'credits', 560, 'Adapter builder', 'CF-247 7 Oct 2026', now())
on conflict (toolset_key, key) do nothing;