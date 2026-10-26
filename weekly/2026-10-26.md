# Deployed weekly run — 26 Oct 2026

| | Count |
|---|---|
| Safe specs run (tests, desktop) | 84 |
| Live-acting specs run (switch on) | 0 |
| Live-acting specs held (switch off) | 10 |

| Viewport | Tests | Passed | Failed | Skipped |
|---|---|---|---|---|
| Desktop | 84 | 42 | 42 | 0 |
| Phone | 84 | 43 | 41 | 0 |

## Failures

- desktop: a12-contextual-insights-deployed.spec.mjs › A12 contextual insights on catalogue detail blades @deployed › RMIT Provider blade relates QILT PRISMS context and Scholarships without flattening granularity
- desktop: a12-contextual-insights-deployed.spec.mjs › A12 contextual insights on catalogue detail blades @deployed › Course blade labels Provider outcomes and Provider-scope Scholarships as context not Course truth
- desktop: a15-provider-contact-intelligence-deployed.spec.mjs › A15 Provider international contact intelligence @deployed › UQ Provider blade shows governed first-party regional manager assignments with Evidence
- desktop: admin-navigation-deployed.spec.mjs › CourseFinder canonical Administration and Operations navigation @deployed › Layer 1 and Layer 2 open as embedded canonical workspaces
- desktop: admin-navigation-deployed.spec.mjs › CourseFinder canonical Administration and Operations navigation @deployed › old Layer 3 address opens Layer 2 › Adapters; Layer 4 is its own route
- desktop: admin-navigation-deployed.spec.mjs › CourseFinder canonical Administration and Operations navigation @deployed › Source profiles are on Scrapers & fetchers, closed until opened, and changes are versioned
- desktop: cf-061-qilt-prisms-comparison-deployed.spec.mjs › CF-061 QILT PRISMS comparison experience @deployed › Course detail keeps QILT as Provider context and opens Course comparison
- desktop: cf-076-ranking-import-ux-deployed.spec.mjs › CF-076 compact ranking import UX @deployed › nested Administration route shows breadcrumbs and compact file-first import
- desktop: cf-076-ranking-import-ux-deployed.spec.mjs › CF-076 compact ranking import UX @deployed › service source derives THE native JSON system/year from file content
- desktop: cf-080-provider-contacts-deployed.spec.mjs › CF-080 Provider Contacts managed Catalogue @deployed › Layer 4 route exposes Provider Contact reconciliation workload
- desktop: cf-092-scheduled-jobs-config-deployed.spec.mjs › CF-092 Scheduled Tasks configuration @deployed › Scheduled Tasks is primary Data Operations navigation before Evidence and Administration has no scheduler footprint
- desktop: cf-097-ranking-workflow-history-deployed.spec.mjs › CF-097/226 ranking workflow, history and datasets @deployed › full THE history remains visible and applied editions no longer require manual review
- desktop: cf-098-ranking-file-bundle-deployed.spec.mjs › CF-098 file-first ranking bundle @deployed › ranking file upload is primary and country files combine before registration
- desktop: cf-100-ranking-country-extension-deployed.spec.mjs › CF-100 multi-country same-edition ranking scope @deployed › source contract shows the automatic validate-and-apply workflow and exposes country scope metadata
- desktop: cf-208-scholarship-pim-maturity-deployed.spec.mjs › CF-208 deployed Scholarship PIM maturity @deployed › Scholarship catalogue is populated and exposes governed operator controls
- desktop: cf-209-scheduler-jobs-operations-deployed.spec.mjs › CF-209 deployed Scheduler and Jobs operations acceptance @deployed › shows governed Scheduling intelligence without generic execution controls
- desktop: cf-209-scheduler-jobs-operations-deployed.spec.mjs › CF-209 deployed Scheduler and Jobs operations acceptance @deployed › keeps Jobs as the server-paged execution and telemetry workspace
- desktop: course-detail-polish-deployed.spec.mjs › CourseFinder deployed Course Detail PIM v2.15.x standardised operator UX @deployed › Federation Bachelor of Arts renders standardised decision layout and Evidence remains responsive
- desktop: course-detail-polish-deployed.spec.mjs › CourseFinder deployed Course Detail PIM v2.15.x standardised operator UX @deployed › Science Honours keeps required gaps visible and hides empty non-required sections
- desktop: data-quality-deployed.spec.mjs › CourseFinder deployed Data Quality acceptance @deployed › governed regulatory-fee states and every exception row page correctly
- desktop: data-quality-deployed.spec.mjs › CourseFinder deployed Data Quality acceptance @deployed › exception opens a canonical Course detail
- desktop: data-quality-deployed.spec.mjs › CourseFinder deployed Data Quality acceptance @deployed › exception opens a real private Evidence Regulatory Snapshot
- desktop: layer2-provider-deployed.spec.mjs › CourseFinder deployed Layer 2 acquisition-provider acceptance @deployed › provider registry is visible without exposing credentials
- desktop: layer2-provider-deployed.spec.mjs › CourseFinder deployed Layer 2 acquisition-provider acceptance @deployed › provider detail preserves the write-only credential boundary for the UAT operator
- desktop: m2-3-intelligence-deployed.spec.mjs › CourseFinder deployed M2.3 intelligence acceptance on canonical routes @deployed › old Layer 3 addresses open Layer 2 › Adapters without exposing credentials
- desktop: m2-3-intelligence-deployed.spec.mjs › CourseFinder deployed M2.3 intelligence acceptance on canonical routes @deployed › Layer 4 review and Scheduled jobs are separate workspaces
- desktop: m2-3-intelligence-deployed.spec.mjs › CourseFinder deployed M2.3 intelligence acceptance on canonical routes @deployed › Key dates and Reference sources are separate Reference data tabs
- desktop: m2-3-intelligence-deployed.spec.mjs › CourseFinder deployed M2.3 intelligence acceptance on canonical routes @deployed › Onboarding sits as a tab under Providers
- desktop: m2-4-4-a21-permanent-layer-navigation-deployed.spec.mjs › A21 permanent Layer navigation @deployed › Layer 2 opens on Adapters with no operator config knobs
- desktop: m2-4-4-a21-permanent-layer-navigation-deployed.spec.mjs › A21 permanent Layer navigation @deployed › old Layer 3 address opens Layer 2; Layer 4 is a separate permanent route
- desktop: m2-4-4-a23-layer2-background-firecrawl-deployed.spec.mjs › A23 quota-aware Layer 2 background execution @deployed › operator Adapters screen has no qualification knobs
- desktop: m2-4-4-a24-unified-layer-headers-deployed.spec.mjs › Layer screens show one title @deployed › each Layer screen has one visible page title and a slim, light Layer header
- desktop: m2-4-4-a26-a28-operator-ux-deployed.spec.mjs › M2.4.4 A26-A28 operator UX @deployed › Administration opens a non-empty default workspace and switches sub-contexts
- desktop: m2-4-4-a26-a28-operator-ux-deployed.spec.mjs › M2.4.4 A26-A28 operator UX @deployed › Layer 2 uses production wording, canonical Jobs/Evidence links and actionable blockers only
- desktop: m2-4-4-a26-a28-operator-ux-deployed.spec.mjs › M2.4.4 A26-A28 operator UX @deployed › old Layer 3 address opens Layer 2 › Adapters; no Layer 3 work screen
- desktop: m2-4-4-layer-status-deployed.spec.mjs › M2.4.4 Dashboard Layer status @deployed › Dashboard loads bounded Layer 1-4 operational status without RPC errors
- desktop: m2-4-navigation-content-audit.spec.mjs › M2.4 navigation/content audit @deployed › capture visible menu, page content, navigation timing and screenshots
- desktop: m2-5-jobs-workspace-deployed.spec.mjs › M2.5 Jobs workspace deployed @deployed › Jobs route shows live governed Pipeline Jobs instead of a manufactured empty list
- desktop: m2-5-pilot-deployment-currentness-deployed.spec.mjs › M2.5 Pilot deployment currentness @deployed › deployed Worker contains CF-053 and CF-054 operator surfaces without executing AI
- desktop: m245-v2-15-74-release-currentness-deployed.spec.mjs › M2.4.5 v2.15.74 release currentness @deployed › accepted Pilot UI reports one synchronized v2.15.74 release
- desktop: performance-deployed.spec.mjs › M1 performance and responsiveness @deployed › core workspaces stay within governed RPC and payload budgets
- desktop: performance-deployed.spec.mjs › M1 performance and responsiveness @deployed › Layer 2 Adapters stay within management-view budgets
- phone: a12-contextual-insights-deployed.spec.mjs › A12 contextual insights on catalogue detail blades @deployed › RMIT Provider blade relates QILT PRISMS context and Scholarships without flattening granularity
- phone: a12-contextual-insights-deployed.spec.mjs › A12 contextual insights on catalogue detail blades @deployed › Course blade labels Provider outcomes and Provider-scope Scholarships as context not Course truth
- phone: a15-provider-contact-intelligence-deployed.spec.mjs › A15 Provider international contact intelligence @deployed › UQ Provider blade shows governed first-party regional manager assignments with Evidence
- phone: admin-navigation-deployed.spec.mjs › CourseFinder canonical Administration and Operations navigation @deployed › Layer 1 and Layer 2 open as embedded canonical workspaces
- phone: admin-navigation-deployed.spec.mjs › CourseFinder canonical Administration and Operations navigation @deployed › old Layer 3 address opens Layer 2 › Adapters; Layer 4 is its own route
- phone: admin-navigation-deployed.spec.mjs › CourseFinder canonical Administration and Operations navigation @deployed › Source profiles are on Scrapers & fetchers, closed until opened, and changes are versioned
- phone: cf-061-qilt-prisms-comparison-deployed.spec.mjs › CF-061 QILT PRISMS comparison experience @deployed › Course detail keeps QILT as Provider context and opens Course comparison
- phone: cf-076-ranking-import-ux-deployed.spec.mjs › CF-076 compact ranking import UX @deployed › nested Administration route shows breadcrumbs and compact file-first import
- phone: cf-076-ranking-import-ux-deployed.spec.mjs › CF-076 compact ranking import UX @deployed › service source derives THE native JSON system/year from file content
- phone: cf-080-provider-contacts-deployed.spec.mjs › CF-080 Provider Contacts managed Catalogue @deployed › Layer 4 route exposes Provider Contact reconciliation workload
- phone: cf-092-scheduled-jobs-config-deployed.spec.mjs › CF-092 Scheduled Tasks configuration @deployed › Scheduled Tasks is primary Data Operations navigation before Evidence and Administration has no scheduler footprint
- phone: cf-097-ranking-workflow-history-deployed.spec.mjs › CF-097/226 ranking workflow, history and datasets @deployed › full THE history remains visible and applied editions no longer require manual review
- phone: cf-098-ranking-file-bundle-deployed.spec.mjs › CF-098 file-first ranking bundle @deployed › ranking file upload is primary and country files combine before registration
- phone: cf-100-ranking-country-extension-deployed.spec.mjs › CF-100 multi-country same-edition ranking scope @deployed › source contract shows the automatic validate-and-apply workflow and exposes country scope metadata
- phone: cf-208-scholarship-pim-maturity-deployed.spec.mjs › CF-208 deployed Scholarship PIM maturity @deployed › Scholarship catalogue is populated and exposes governed operator controls
- phone: cf-209-scheduler-jobs-operations-deployed.spec.mjs › CF-209 deployed Scheduler and Jobs operations acceptance @deployed › shows governed Scheduling intelligence without generic execution controls
- phone: cf-209-scheduler-jobs-operations-deployed.spec.mjs › CF-209 deployed Scheduler and Jobs operations acceptance @deployed › keeps Jobs as the server-paged execution and telemetry workspace
- phone: course-detail-polish-deployed.spec.mjs › CourseFinder deployed Course Detail PIM v2.15.x standardised operator UX @deployed › Federation Bachelor of Arts renders standardised decision layout and Evidence remains responsive
- phone: course-detail-polish-deployed.spec.mjs › CourseFinder deployed Course Detail PIM v2.15.x standardised operator UX @deployed › Science Honours keeps required gaps visible and hides empty non-required sections
- phone: data-quality-deployed.spec.mjs › CourseFinder deployed Data Quality acceptance @deployed › governed regulatory-fee states and every exception row page correctly
- phone: data-quality-deployed.spec.mjs › CourseFinder deployed Data Quality acceptance @deployed › exception opens a canonical Course detail
- phone: data-quality-deployed.spec.mjs › CourseFinder deployed Data Quality acceptance @deployed › exception opens a real private Evidence Regulatory Snapshot
- phone: layer2-provider-deployed.spec.mjs › CourseFinder deployed Layer 2 acquisition-provider acceptance @deployed › provider registry is visible without exposing credentials
- phone: layer2-provider-deployed.spec.mjs › CourseFinder deployed Layer 2 acquisition-provider acceptance @deployed › provider detail preserves the write-only credential boundary for the UAT operator
- phone: m2-3-intelligence-deployed.spec.mjs › CourseFinder deployed M2.3 intelligence acceptance on canonical routes @deployed › old Layer 3 addresses open Layer 2 › Adapters without exposing credentials
- phone: m2-3-intelligence-deployed.spec.mjs › CourseFinder deployed M2.3 intelligence acceptance on canonical routes @deployed › Layer 4 review and Scheduled jobs are separate workspaces
- phone: m2-3-intelligence-deployed.spec.mjs › CourseFinder deployed M2.3 intelligence acceptance on canonical routes @deployed › Key dates and Reference sources are separate Reference data tabs
- phone: m2-3-intelligence-deployed.spec.mjs › CourseFinder deployed M2.3 intelligence acceptance on canonical routes @deployed › Onboarding sits as a tab under Providers
- phone: m2-4-4-a21-permanent-layer-navigation-deployed.spec.mjs › A21 permanent Layer navigation @deployed › Layer 2 opens on Adapters with no operator config knobs
- phone: m2-4-4-a21-permanent-layer-navigation-deployed.spec.mjs › A21 permanent Layer navigation @deployed › old Layer 3 address opens Layer 2; Layer 4 is a separate permanent route
- phone: m2-4-4-a23-layer2-background-firecrawl-deployed.spec.mjs › A23 quota-aware Layer 2 background execution @deployed › operator Adapters screen has no qualification knobs
- phone: m2-4-4-a24-unified-layer-headers-deployed.spec.mjs › Layer screens show one title @deployed › each Layer screen has one visible page title and a slim, light Layer header
- phone: m2-4-4-a26-a28-operator-ux-deployed.spec.mjs › M2.4.4 A26-A28 operator UX @deployed › Administration opens a non-empty default workspace and switches sub-contexts
- phone: m2-4-4-a26-a28-operator-ux-deployed.spec.mjs › M2.4.4 A26-A28 operator UX @deployed › Layer 2 uses production wording, canonical Jobs/Evidence links and actionable blockers only
- phone: m2-4-4-a26-a28-operator-ux-deployed.spec.mjs › M2.4.4 A26-A28 operator UX @deployed › old Layer 3 address opens Layer 2 › Adapters; no Layer 3 work screen
- phone: m2-4-4-layer-status-deployed.spec.mjs › M2.4.4 Dashboard Layer status @deployed › Dashboard loads bounded Layer 1-4 operational status without RPC errors
- phone: m2-4-navigation-content-audit.spec.mjs › M2.4 navigation/content audit @deployed › capture visible menu, page content, navigation timing and screenshots
- phone: m2-5-jobs-workspace-deployed.spec.mjs › M2.5 Jobs workspace deployed @deployed › Jobs route shows live governed Pipeline Jobs instead of a manufactured empty list
- phone: m2-5-pilot-deployment-currentness-deployed.spec.mjs › M2.5 Pilot deployment currentness @deployed › deployed Worker contains CF-053 and CF-054 operator surfaces without executing AI
- phone: m245-v2-15-74-release-currentness-deployed.spec.mjs › M2.4.5 v2.15.74 release currentness @deployed › accepted Pilot UI reports one synchronized v2.15.74 release
- phone: performance-deployed.spec.mjs › M1 performance and responsiveness @deployed › Layer 2 Adapters stay within management-view budgets
