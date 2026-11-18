-- CF-247 F-INT Rule B operability (Decision 271; Operating Model v1.11 "Switching on a gated rule"): the Platform Admin stops Rule B for a provider by removing
-- it from intake_dates.nearest_start_providers, and stops it for all by emptying the list. Settings > Pipeline settings refuses an empty list unless the setting's
-- range minimum is 0 (src/lib/settings-list.js), so the list could be filled on the screen but not emptied. Minimum 0 makes the stop possible on the screen.
-- The value is not changed (it stays []); nothing is switched on.
-- Guards: G2 (the range is part of the setting), G3 (no consumer API object), G4 (cf-247-s531).
-- Replaces: nothing.
-- Retires: nothing.
update pipeline.platform_toolset_settings
   set min_value = 0,
       reason = 'Decision 271 (11 Nov 2026): the list may be emptied on Settings > Pipeline settings, which stops Rule B for every provider (20261111140000)',
       updated_at = now()
 where toolset_key = 'pipeline' and key = 'intake_dates.nearest_start_providers';

do $p$
begin
  if (select min_value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.nearest_start_providers') <> 0 then
    raise exception 'post-check: intake_dates.nearest_start_providers minimum is not 0'; end if;
end $p$;
