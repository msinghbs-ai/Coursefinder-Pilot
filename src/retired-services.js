// SS-020 step 1 (Decision 269, Platform Admin 3 Nov 2026 22:05 "Approve all, build in order"): services retired from the admin screens.
// Firecrawl is the only page service (4 Oct 2026) and the acquisition providers below were dropped for go-live (29 Sep 2026).
// Their rows, keys and history stay in the database (pipeline.layer2_acquisition_providers, pipeline.platform_toolsets and their settings);
// the functions, tables and edge function that only served them are marked retiring in pipeline.component_register
// (migration 20261104340000) and leave by a Platform Admin paste file after hygiene.retire_after_days. Nothing here is an operational value.

// Toolsets whose cards left Models & services › Toolsets & limits (with the Search pass and Sample runs cards that only served them)
export const RETIRED_TOOLSETS = new Set(['serper', 'scrapingbee'])

// Acquisition providers no longer shown on Fetchers, the Go-live checklist or Settings (dropped 29 Sep; Serper and ScrapingBee 4 Oct)
export const RETIRED_FETCHERS = new Set(['scraperapi', 'scrape-do', 'zenrows', 'serper', 'scrapingbee'])

export const isRetiredFetcher = (p) => RETIRED_FETCHERS.has(String(p?.provider_key || p?.provider_name || '').toLowerCase())
