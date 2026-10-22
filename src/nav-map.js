// StudySearch admin menu (v2.15.107): one place for every page, its tabs, who may open it,
// and where old addresses now lead. The shell (mature-main.jsx) draws the menu, the page
// header and the tabs from this map; nothing else adds or reorders menu entries.
//
// A page is visible when the user may open at least one of its tabs. A tab's `min` is the
// lowest role rank that may open it (1 Viewer ... 6 Platform Admin), unchanged from the
// screen it came from.

export const PAGES = {
  dashboard: { label: 'Dashboard', slug: 'dashboard', icon: 'dashboard', min: 1, title: 'Dashboard', subtitle: 'What needs attention today, and recent activity.' },
  // v2.15.141 (Decision 214): what is running at each layer right now, refreshed every 20 seconds.
  // v2.15.266 (Platform Admin, 13 Oct 2026): the Live activity page is retired; Coverage & completeness › Progress › Running now replaces
  // it (every job by journey stage, the universities each works on, pause, resume and run now). Old addresses redirect (LEGACY).

  courses: { label: 'Courses', slug: 'courses', icon: 'course', min: 1, subtitle: 'Every course, with its sources and evidence.' },
  providers: { label: 'Providers', slug: 'providers', icon: 'provider', subtitle: 'Providers, their campuses and their logos.', tabs: [
    { key: 'providers', label: 'Providers', min: 1 },
    { key: 'campuses', label: 'Campuses', min: 1 },
    { key: 'assets', label: 'Logos & assets', min: 4 },
    // v2.15.258 (Platform Admin bug 12/10-01): Onboarding moved to Layer 2 › Onboarding; the old address redirects (resolveTarget)
    // v2.15.238 (R5, Feature 6): archived providers and courses that are not active, with why, and Restore
    { key: 'archived', label: 'Archived', min: 3 },
  ] },
  scholarships: { label: 'Scholarships', slug: 'scholarships', icon: 'scholarship', subtitle: 'Scholarships, where each value came from, and what is published.', tabs: [
    { key: 'list', label: 'Scholarships', min: 1 },
    // v2.15.240 (Platform Admin, 11 Oct 2026): each provider measured against its own scholarship listing page
    { key: 'coverage', label: 'Coverage', min: 3 },
    // v2.15.249 (Platform Admin bugs 11/10-6): AI reads each stored scholarship page; models, qualification, instructions, answers.
    // v2.15.301 (Platform Admin, 20 Oct 2026, "Move to Models & services › AI"): Extraction is on Models & services › AI (old address redirects).
    // v2.15.174 (Platform Admin, 4 Oct 2026 01:57): Course links retired — links come from each scholarship's page (Layer 2)
    // v2.15.169 (Decision 249): Publishing moved to Layer 4 Review; v2.15.253: that tab retired, publishing is on Coverage
  ] },
  rankings: { label: 'Rankings & statistics', slug: 'statistics-rankings', icon: 'chart', subtitle: 'QILT, PRISMS, QS and THE data, and side-by-side comparison.', tabs: [
    { key: 'overview', label: 'Overview', min: 1 },
    { key: 'compare', label: 'Compare', min: 1 },
    { key: 'qilt', label: 'Outcomes (QILT)', min: 1 },
    { key: 'prisms', label: 'Student flow (PRISMS)', min: 1 },
    { key: 'datasets', label: 'Datasets', min: 4 },
  ] },

  coverage: { label: 'Coverage & completeness', slug: 'coverage', icon: 'check', subtitle: 'How complete each course is, and each attribute across all courses.', tabs: [
    { key: 'courses', label: 'Courses', min: 1 },
    { key: 'attributes', label: 'Attributes', min: 1 },
    // v2.15.266 (Platform Admin, 13 Oct 2026): how the platform is progressing, what is running and where to tweak it
    // v2.15.301 (Platform Admin, 20 Oct 2026): Progress keeps Overview and Journeys; Running now and Levers retired (Running now is
    // Scheduled jobs › Task manager and Layer 2/3 › Operations; the pace settings are on Settings)
    { key: 'progress', label: 'Progress', min: 3 },
    // v2.15.282 (15 Oct 2026) Flags: v2.15.301 moved to Layer 2/3 › Flags (old address redirects)
    // v2.15.292 (19 Oct 2026) Counsellor reports: v2.15.300 retired as a tab; each report is an Inbox kind (Layer 4 › Inbox, Counsellor report)
  ] },
  // v2.15.246 (Platform Admin bugs 11/10-3, Feature 2): Runs and Source settings are one Sources list (expandable rows, settings
  // edited in place, + Add source); Manual batch runs is retired (each source has Run now, recorded as one job).
  // v2.15.301 (Platform Admin, 20 Oct 2026, "Merge into one Sources page"): Layer 1 is the one Sources page with a layer filter. It opens on
  // the official registers (run, schedule, settings, + Add source); "All layers" lists every source the pipeline reads (the old Sources
  // page, whose address now opens this page on All layers). Layer 1 › Scholarships moved to Layer 2/3 › Scholarships.
  layer1: { label: 'Layer 1 Register', slug: 'layer-1-register', icon: 'database', min: 4, subtitle: 'Every source the pipeline reads. Registers (such as CRICOS) first: each with its health, schedule and settings; choose All layers for every other source.' },
  // v2.15.112 (Platform Admin, 30 Sep 2026): reference data that is not a register run moved out of Layer 1.
  // v2.15.301 (Platform Admin, 20 Oct 2026, "One list with a type filter"): Key dates and Reference sources are one list with a type
  // filter (?type=dates|links); Ranking imports moved to Rankings & statistics › Datasets. Old tab addresses redirect.
  reference: { label: 'Reference data', slug: 'reference-data', icon: 'book', min: 3, subtitle: 'Key dates and the third-party sites the platform refers to, in one list with a type filter.' },
  // v2.15.200 (Decision 254, Platform Admin 6 Oct 15:31 and 15:38): Layer 2 is the adapters and their whole lifecycle, plus
  // scholarships. Overview, Fetch an area, History and Source profiles retired (unused for 30 days); their old addresses
  // and Coverage › Universities open Adapters.
  // v2.15.300 (Platform Admin, 20 Oct 2026 10:35: "Rework layer 2 into layer 2/3 so its cleared it has combined operations ... Only actionable
  // and operation relative information and items should be retained"; choice "Operations first"): Layer 2/3 Build & enrich. Operations
  // (each stage: working, waiting, stopped for a person, its jobs) first; Universities joins Onboarding and Adapters (one row per university:
  // its journey stage, adapter, Inbox items); the Adapter builder opens from a university row (hidden tab, its address still works).
  layer2: { label: 'Layer 2/3 Build & enrich', slug: 'layer-2-discovery', icon: 'activity', subtitle: 'Find each university\'s pages, build and admit its adapter, enrich its courses and check its scholarships: what is working, waiting or stopped, and the jobs behind it.', tabs: [
    { key: 'operations', label: 'Operations', min: 3 },
    // v2.15.301 (Platform Admin, 20 Oct 2026): Flags moved here from Coverage & completeness, beside Operations
    { key: 'flags', label: 'Flags', min: 3 },
    { key: 'universities', label: 'Universities', min: 3 },
    // v2.15.306 (Platform Admin, 21 Oct 2026: "end to end data enrichment for universities"): each university's plan from its gaps, Run now
    // from the on-demand allowance, automatic plans most missing first within the toolset shares
    { key: 'plan', label: 'Enrichment plan', min: 3 },
    // v2.15.287 (Decision 267, Platform Admin 18 Oct 11:58 "Keep Adapter builder too"): one click per university, eight fields measured
    { key: 'build', label: 'Build adapter', min: 3 },
    // v2.15.318 (Platform Admin 22 Oct 2026 19:05, "accommodate manual actions ... complete the process in manual mode"): the Adapter builder is
    // back in the tabs; every step can be done by hand there (pages, samples, settings, save, qualify, admit)
    { key: 'builder', label: 'Adapter builder', min: 5 },
    // v2.15.273 (Platform Admin, 14 Oct 2026 10:41): a task that fills chosen missing fields for countries or universities
    { key: 'enrich', label: 'Enrich fields', min: 3 },
    // v2.15.301 (Platform Admin, 20 Oct 2026, "One tab on Layer 2/3"): finding (was Layer 1 › Scholarships) and reading scholarships, one tab
    { key: 'scholarships', label: 'Scholarships', min: 4 },
  ] },
  // v2.15.252 (Platform Admin, 12 Oct 2026): Layer 3 AI validation retired. University adapters (Layer 2) admit intakes,
  // English requirements and fees, so the AI check is no longer needed; its old addresses open Layer 2 › Adapters.
  layer4: { label: 'Layer 4 Review', slug: 'layer-4-review', icon: 'review', subtitle: 'Decisions that need a person, with an audit trail.', tabs: [
    // v2.15.298 (Platform Admin, 20 Oct 2026: "anything that needs attention or intervention should come to Layer 4"): one inbox, by university
    { key: 'inbox', label: 'Inbox', min: 3 },
    // v2.15.300 (Platform Admin, 20 Oct 2026, "Old Layer 4 tabs now"): Review queue, AI could not decide and Websites to find retired; each
    // is a kind in the Inbox, and their addresses open the Inbox on that kind (resolveTarget). Decisions taken are under Inbox › Decided.
    // v2.15.252: the AI send-back tab retired with Layer 3. v2.15.253: Flagged values, Fee rules, Attributes, Scholarship publishing and Blocks retired.
  ] },

  // v2.15.301 (Platform Admin, 20 Oct 2026): Capacity moved to the Go-live checklist; Storage & retention is a tab here (Platform Admin only)
  health: { label: 'Platform health', slug: 'platform-health', icon: 'health', subtitle: 'Automatic checks across jobs, queues, budgets and the database; what takes space and purging it.', tabs: [
    { key: 'checks', label: 'Health checks', min: 3 },
    // v2.15.319 (Platform Admin 22 Oct 2026 19:53, "Watchdog" first): each enrichment queue's state, alerts and self-fixes
    { key: 'queues', label: 'Work queues', min: 3 },
    { key: 'storage', label: 'Storage & retention', min: 6 },
  ] },
  jobs: { label: 'Scheduled jobs', slug: 'scheduled-jobs', icon: 'workflow', subtitle: 'Every automation the platform runs, the order work is taken in, job history and refresh schedules.', tabs: [
    { key: 'automations', label: 'Automations', min: 4 },
    // v2.15.300 (Platform Admin, 20 Oct 2026, "Priority queue"): retired (no use in 7 days; the focus list and Build adapter waves order the
    // work). The course-page search cap moved to Models & services › Toolsets & limits.
    { key: 'jobs', label: 'Jobs', min: 4 },
    // v2.15.197 (Decision 254, job system Phase A): long-running admin actions as tasks with progress, pause and cancel
    { key: 'tasks', label: 'Task manager', min: 4 },
  ] },
  evidence: { label: 'Evidence', slug: 'evidence', icon: 'book', min: 3, subtitle: 'Saved source pages and files, and what they changed.' },
  // v2.15.124 (screen review): the cross-layer source list moved out of Layer 1 to Operations; v2.15.301: it is Layer 1's "All layers" filter.
  // CF-247 (16 Oct 2026) API usage: v2.15.301 (Platform Admin, 20 Oct 2026, "Move API usage to Settings") is Settings › API usage.

  // v2.15.301: two tabs. Settings (Platform Admin) and API usage (Pipeline Operator and above, as before the move).
  environment: { label: 'Settings', slug: 'environment', icon: 'plug', subtitle: 'Every pipeline setting in one place, by step: throughput, reading, page identity and budgets; keys for outside services (never shown); calls to the consumer APIs.', tabs: [
    { key: 'settings', label: 'Settings', min: 6 },
    // CF-247 (16 Oct 2026, Platform Admin: "summary and stat collection"): calls to the API version URLs by key and action
    { key: 'api', label: 'API usage', min: 4 },
    // v2.15.310 (Platform Admin, 22 Oct 2026 07:41): daily backup of the provider Published switch and setting values, restore (Platform Admin)
    { key: 'backup', label: 'Backup & restore', min: 6 },
  ] },
  // v2.15.300 (Platform Admin, 20 Oct 2026): Scrapers & fetchers is the Fetchers tab of Models & services (old addresses redirect).
  // v2.15.264 (Platform Admin, 13 Oct 2026 00:09): three tabs; the AI configuration Layer 3 used to hold is back as AI & OpenRouter.
  services: { label: 'Models & services', slug: 'models-services', icon: 'ai', min: 4, subtitle: 'Switch AI models and page-fetching services on or off; configure the AI that runs now and OpenRouter; and the limits each layer depends on.', tabs: [
    { key: 'services', label: 'Services', min: 4 },
    // v2.15.301: Scholarship extraction (was Scholarships › Extraction, Curator and above) is on this tab; the AI configuration stays Operator and above
    { key: 'ai', label: 'AI & OpenRouter', min: 3 },
    { key: 'limits', label: 'Toolsets & limits', min: 4 },
    { key: 'fetchers', label: 'Fetchers', min: 4 },
  ] },
  // v2.15.301 (Platform Admin, 20 Oct 2026): Capacity (was Platform health › Capacity) is part of the checklist
  migration: { label: 'Go-live checklist', slug: 'environment-migration', icon: 'shield', min: 6, subtitle: 'What must be set up and pass before Production is switched on, and the capacity it needs.' },
  // v2.15.301 (Platform Admin, 20 Oct 2026, "Retire the page"): Data model retired (read only, no use); the attribute data stays.
  // Its address opens Coverage & completeness › Attributes. v2.15.219 Storage & retention is Platform health › Storage & retention.

  users: { label: 'Users & roles', slug: 'users-roles', icon: 'users', min: 6, subtitle: 'Who can sign in and what each person may do.' },
  contacts: { label: 'Provider contacts', slug: 'provider-contacts', icon: 'users', min: 1, subtitle: 'International recruitment contacts for each provider.' },
  // v2.15.136 (Decision 209): the operator and Platform Admin walkthrough, reviewed every release.
  // v2.15.257 (Platform Admin, 12 Oct 2026): Guides: the Platform guide and the two SOPs (Platform Admin, Operator), versioned
  guide: { label: 'Guides', slug: 'platform-guide', icon: 'guide', subtitle: 'How to run the platform: the Platform guide, and the standard operating procedures for Platform Admins and operators.', tabs: [
    { key: 'guide', label: 'Platform guide', min: 1 },
    { key: 'admin-sop', label: 'Platform Admin SOP', min: 3 },
    { key: 'operator-sop', label: 'Operator SOP', min: 3 },
  ] },
}

export const SECTIONS = [
  { label: '', pages: ['dashboard'] },
  { label: 'Catalogue', pages: ['courses', 'providers', 'contacts', 'scholarships', 'rankings', 'reference'] },
  { label: 'Data pipeline', pages: ['coverage', 'layer1', 'layer2', 'layer4'] },
  { label: 'Operations', pages: ['health', 'jobs', 'evidence'] },
  { label: 'Platform settings', pages: ['environment', 'services', 'migration'] },
  { label: 'Administration', pages: ['users'] },
  { label: 'Guides', pages: ['guide'] },
]

for (const [key, p] of Object.entries(PAGES)) { p.key = key; if (p.tabs) p.min = Math.min(...p.tabs.map(t => t.min)); p.title = p.title || p.label }
export const SECTION_OF = Object.fromEntries(SECTIONS.flatMap(s => s.pages.map(k => [k, s.label])))

export function slugify(v) { return String(v).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') }

// Old addresses (and the old menu labels, which were turned into addresses the same way) → new page and tab.
// Every old menu entry, hidden route, alias and Administration section is listed, so old links keep working.
export const LEGACY = {
  'campuses': { page: 'providers', tab: 'campuses' },
  'provider-contacts': { page: 'contacts' },
  'completeness': { page: 'coverage', tab: 'attributes' },
  'data-quality-readiness': { page: 'coverage', tab: 'attributes' },
  'course-coverage': { page: 'coverage', tab: 'courses' },
  // v2.15.266: Live activity retired → Progress › Running now
  // v2.15.301: Progress › Running now retired → Scheduled jobs › Task manager (the same board)
  'live-activity': { page: 'jobs', tab: 'tasks' },
  'activity': { page: 'jobs', tab: 'tasks' },
  'compare': { page: 'rankings', tab: 'compare' },
  'outcomes-qilt': { page: 'rankings', tab: 'qilt' },
  'student-flow-prisms': { page: 'rankings', tab: 'prisms' },
  'layer-1-operations': { page: 'layer1', tab: 'operations' },
  'layer-1-regulatory': { page: 'layer1', tab: 'operations' },
  // v2.15.123: Regulatory settings merged into Layer 1 (Manual batch runs); v2.15.246: that tab is retired, so it opens Sources.
  'regulatory-settings': { page: 'layer1', tab: 'operations' },
  'layer-1-authority': { page: 'layer1', tab: 'operations' },
  // v2.15.301: the separate Sources page is Layer 1's All layers filter
  'sources': { page: 'layer1', set: { layer: 'all' } },
  'pipeline-sources': { page: 'layer1', set: { layer: 'all' } },
  // v2.15.301: API usage, Storage & retention and Data model left the menu
  'api-usage': { page: 'environment', tab: 'api' },
  'storage-retention': { page: 'health', tab: 'storage' },
  'data-model': { page: 'coverage', tab: 'attributes' },
  'onboarding': { page: 'layer2', tab: 'universities' },
  'important-dates': { page: 'reference', set: { type: 'dates' } },
  'important-links': { page: 'reference', set: { type: 'links' } },
  'layer-2-enrichment': { page: 'layer2', tab: 'universities' },
  'layer-2-operations': { page: 'layer2', tab: 'operations' },
  // v2.15.300: Scrapers & fetchers is Models & services › Fetchers
  'scrapers': { page: 'services', tab: 'fetchers' },
  'scrapers-fetchers': { page: 'services', tab: 'fetchers' },
  // v2.15.252: Layer 3 retired; every old Layer 3 address opens Layer 2 › Adapters (see resolveTarget).
  'layer-3-ai-interpretation': { page: 'layer2', tab: 'universities', legacyL3: true },
  'layer-3-ai': { page: 'layer2', tab: 'universities', legacyL3: true },
  'layer-3-ai-validation': { page: 'layer2', tab: 'universities', legacyL3: true },
  'layer-4-human-resolution': { page: 'layer4' },
  'review-queue': { page: 'layer4' },
  'jobs-schedules': { page: 'jobs' },
  'jobs': { page: 'jobs', tab: 'jobs' },
  // v2.15.124: Schedules folded into Automations (refresh schedules and one-off runs) and Jobs (history).
  'scheduled-tasks': { page: 'jobs', tab: 'automations' },
  'refresh-scheduling': { page: 'jobs', tab: 'automations' },
  'attributes': { page: 'coverage', tab: 'attributes' },
  // The old '#settings' address opened Administration > Platform (readiness), not the regulatory page; v2.15.301 Capacity is on the Go-live checklist.
  'settings': { page: 'migration' },
  'statistics-rankings': { page: 'rankings' },
  'administration': { page: 'services', tab: 'fetchers' },
}

// Old Administration sections (#administration?section=...) → new page and tab.
export const LEGACY_ADMIN_SECTIONS = {
  'overview': { page: 'services', tab: 'fetchers' },
  'sources-imports': { page: 'rankings', tab: 'datasets' },
  'layer1-sources': { page: 'layer1', tab: 'operations' },
  'layer2-providers': { page: 'services', tab: 'fetchers' },
  'provider-assets': { page: 'providers', tab: 'assets' },
  'layer2-sources': { page: 'layer2', tab: 'universities' },
  'onboarding': { page: 'layer2', tab: 'universities' },
  'pim': { page: 'coverage', tab: 'attributes' },
  'users-roles': { page: 'users' },
  'environment-migration': { page: 'environment' },
  'platform': { page: 'migration' },
  'statistics-datasets': { page: 'rankings', tab: 'datasets' },
}

const MOVED_L1 = { imports: { page: 'rankings', tab: 'datasets' }, dates: { page: 'reference', tab: '', set: { type: 'dates' } }, links: { page: 'reference', tab: '', set: { type: 'links' } }, onboarding: { page: 'layer2', tab: 'universities' }, scholarships: { page: 'layer2', tab: 'scholarships' } }

const BY_SLUG = Object.fromEntries(Object.values(PAGES).map(p => [p.slug, p.key]))
const BY_LABEL = Object.fromEntries(Object.values(PAGES).map(p => [slugify(p.label), p.key]))

export function allowedTabs(page, rank) { return (page?.tabs || []).filter(t => rank >= t.min) }
// v2.15.300: a hidden tab (Layer 2/3 › Adapter builder) opens by its address (from a university row) and is drawn only while it is open
export function shownTabs(page, rank, active = '') { return allowedTabs(page, rank).filter(t => !t.hidden || t.key === active) }
export function canOpen(pageKey, rank) { const p = PAGES[pageKey]; return Boolean(p) && rank >= p.min }

/**
 * Resolve an address or a page name to {page, tab, params}.
 * Accepts a new page key, a new slug, a new label, an old slug, or an old label
 * (for example 'Layer 4 — Human Resolution' or 'Statistics & Rankings').
 */
export function resolveTarget(target, params = new URLSearchParams()) {
  const p = new URLSearchParams(params)
  const raw = String(target || '')
  let hit = null
  if (PAGES[raw]) hit = { page: raw }
  else if (raw === 'layer3') hit = { page: 'layer2', tab: 'adapters', legacyL3: true }
  else {
    const s = slugify(raw)
    if (s === 'administration' && p.get('section')) { hit = LEGACY_ADMIN_SECTIONS[p.get('section')] || LEGACY.administration; p.delete('section') }
    else if (LEGACY[s]) hit = LEGACY[s]
    else if (BY_SLUG[s]) hit = { page: BY_SLUG[s] }
    else if (BY_LABEL[s]) hit = { page: BY_LABEL[s] }
  }
  if (!hit) return { page: 'dashboard', tab: '', params: new URLSearchParams(), unknown: Boolean(raw) }
  const tab = p.get('tab') || hit.tab || ''
  p.delete('tab')
  if (hit.view && !p.get('view')) p.set('view', hit.view)
  for (const [k, v] of Object.entries(hit.set || {})) if (!p.get(k)) p.set(k, v)
  // Layer 1 tabs moved in v2.15.112 (and v2.15.301): old links keep working.
  if (hit.page === 'layer1' && MOVED_L1[tab]) { const m = MOVED_L1[tab]; for (const [k, v] of Object.entries(m.set || {})) if (!p.get(k)) p.set(k, v); return { page: m.page, tab: m.tab, params: p } }
  // v2.15.301 (Platform Admin, 20 Oct 2026): the menu decisions. Every moved or retired tab opens its new place.
  if (hit.page === 'layer1') return { page: 'layer1', tab: '', params: p }
  if (hit.page === 'reference' && tab === 'imports') return { page: 'rankings', tab: 'datasets', params: p }
  if (hit.page === 'reference' && ['dates', 'links'].includes(tab)) { if (!p.get('type')) p.set('type', tab); return { page: 'reference', tab: '', params: p } }
  if (hit.page === 'scholarships' && tab === 'extraction') return { page: 'services', tab: 'ai', params: p }
  if (hit.page === 'coverage' && tab === 'flags') return { page: 'layer2', tab: 'flags', params: p }
  if (hit.page === 'coverage' && tab === 'progress' && p.get('view') === 'running') { p.delete('view'); return { page: 'jobs', tab: 'tasks', params: p } }
  if (hit.page === 'coverage' && tab === 'progress' && p.get('view') === 'levers') { p.delete('view'); return { page: 'environment', tab: 'settings', params: p } }
  if (hit.page === 'health' && tab === 'readiness') return { page: 'migration', tab: '', params: p }
  // v2.15.124: Readiness by area is part of Attributes; Layer 1 › Sources is Operations › Sources.
  if (hit.page === 'jobs' && tab === 'schedules') return { page: 'jobs', tab: 'automations', params: p }
  if (hit.page === 'coverage' && tab === 'domains') return { page: 'coverage', tab: 'attributes', params: p }
  // v2.15.200 (Decision 254): Coverage › Universities and the retired Layer 2 tabs open Layer 2 › Adapters.
  if (hit.page === 'coverage' && tab === 'universities') return { page: 'layer2', tab: 'universities', params: p }
  if (hit.page === 'layer2' && ['start', 'history', 'profiles'].includes(tab)) return { page: 'layer2', tab: 'universities', params: p }
  // v2.15.300: Layer 2 › Adapters and Onboarding are Layer 2/3 › Universities
  if (hit.page === 'layer2' && ['adapters', 'onboarding'].includes(tab)) return { page: 'layer2', tab: 'universities', params: p }
  // v2.15.300: Counsellor reports, Priority queue and Scrapers & fetchers retired
  if (hit.page === 'coverage' && tab === 'reports') return inboxOf('counsellor_report', p)
  if (hit.page === 'jobs' && tab === 'priority') return { page: 'layer2', tab: 'build', params: p }
  // v2.15.246: Source settings and Manual batch runs are part of Layer 1 › Sources.
  // v2.15.122: the Layer 3 Models list is Platform settings › Models & services (still true after Layer 3 retired).
  // v2.15.252 (Platform Admin, 12 Oct 2026): every other Layer 3 address (Control, Work queue, ...) opens Layer 2 › Adapters.
  if (hit.legacyL3 && tab === 'models') return { page: 'services', tab: '', params: p }
  if (hit.legacyL3) return { page: 'layer2', tab: 'universities', params: p }
  // v2.15.252: the Layer 4 AI send-back tab retired with Layer 3; the old address opens the Review queue.
  if (hit.page === 'layer4' && tab === 'sendback') return inboxOf('course_link', p)
  // v2.15.300 (Platform Admin, 20 Oct 2026): the old Layer 4 tabs open the Inbox on their kind
  if (hit.page === 'layer4' && tab === 'review') return inboxOf('course_link', p)
  if (hit.page === 'layer4' && tab === 'aireview') return inboxOf('held_scholarship', p)
  if (hit.page === 'layer4' && tab === 'websites') return inboxOf('website_needed', p)
  // v2.15.253 (Platform Admin, 12 Oct 2026): retired Layer 4 tabs. Flagged values, Fee rules and Blocks open the Review queue;
  // Attributes (central page approvals) opens Layer 2 › Onboarding (v2.15.258); Scholarship publishing opens Scholarships › Coverage.
  if (hit.page === 'layer4' && ['flags', 'rules', 'blocks'].includes(tab)) return inboxOf('course_link', p)
  if (hit.page === 'layer4' && tab === 'attributes') return inboxOf('central_to_approve', p)
  // v2.15.258 (bug 12/10-01): Providers › Onboarding moved to Layer 2 › Onboarding (v2.15.300: Layer 2/3 › Universities)
  if (hit.page === 'providers' && tab === 'onboarding') return { page: 'layer2', tab: 'universities', params: p }
  if (hit.page === 'layer4' && tab === 'publishing') return { page: 'scholarships', tab: 'coverage', params: p }
  // v2.15.169 (Decision 249) moved Scholarships › Publishing to Layer 4; v2.15.253 retired that tab, so it opens Scholarships › Coverage.
  if (hit.page === 'scholarships' && tab === 'publishing') return { page: 'scholarships', tab: 'coverage', params: p }
  // v2.15.174: Scholarships › Course links retired; the old address opens the list
  if (hit.page === 'scholarships' && tab === 'links') return { page: 'scholarships', tab: 'list', params: p }
  return { page: hit.page, tab, params: p }
}

function inboxOf(kind, p) { if (!p.get('kind')) p.set('kind', kind); return { page: 'layer4', tab: 'inbox', params: p } }

/** The canonical address for a page, tab and extra parameters. */
export function hrefFor(pageKey, tab = '', params = {}) {
  const page = PAGES[pageKey] || PAGES.dashboard
  const q = new URLSearchParams()
  const first = page.tabs?.[0]?.key
  if (tab && tab !== first) q.set('tab', tab)
  for (const [k, v] of Object.entries(params || {})) if (v !== '' && v != null && k !== 'tab') q.set(k, String(v))
  const s = q.toString()
  return `#${page.slug}${s ? `?${s}` : ''}`
}

/** The tab to show: the requested one if the user may open it, else the first they may open. */
export function effectiveTab(pageKey, requested, rank) {
  const tabs = allowedTabs(PAGES[pageKey], rank)
  if (!tabs.length) return ''
  return tabs.some(t => t.key === requested) ? requested : tabs[0].key
}
