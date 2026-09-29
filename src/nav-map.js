// CourseFinder admin menu (v2.15.107): one place for every page, its tabs, who may open it,
// and where old addresses now lead. The shell (mature-main.jsx) draws the menu, the page
// header and the tabs from this map; nothing else adds or reorders menu entries.
//
// A page is visible when the user may open at least one of its tabs. A tab's `min` is the
// lowest role rank that may open it (1 Viewer ... 6 Platform Admin), unchanged from the
// screen it came from.

export const PAGES = {
  dashboard: { label: 'Dashboard', slug: 'dashboard', icon: 'dashboard', min: 1, title: 'Dashboard', subtitle: 'What needs attention today, and recent activity.' },

  courses: { label: 'Courses', slug: 'courses', icon: 'course', min: 1, subtitle: 'Every course, with its sources and evidence.' },
  providers: { label: 'Providers', slug: 'providers', icon: 'provider', subtitle: 'Providers, their campuses and their logos.', tabs: [
    { key: 'providers', label: 'Providers', min: 1 },
    { key: 'campuses', label: 'Campuses', min: 1 },
    { key: 'assets', label: 'Logos & assets', min: 4 },
  ] },
  scholarships: { label: 'Scholarships', slug: 'scholarships', icon: 'scholarship', min: 1, subtitle: 'Scholarships and where each value came from.' },
  rankings: { label: 'Rankings & statistics', slug: 'statistics-rankings', icon: 'chart', subtitle: 'QILT, PRISMS, QS and THE data, and side-by-side comparison.', tabs: [
    { key: 'overview', label: 'Overview', min: 1 },
    { key: 'compare', label: 'Compare', min: 1 },
    { key: 'qilt', label: 'Outcomes (QILT)', min: 1 },
    { key: 'prisms', label: 'Student flow (PRISMS)', min: 1 },
    { key: 'datasets', label: 'Datasets', min: 4 },
  ] },

  coverage: { label: 'Coverage & completeness', slug: 'coverage', icon: 'check', subtitle: 'How complete each course is, attribute by attribute.', tabs: [
    { key: 'courses', label: 'Course coverage', min: 1 },
    { key: 'domains', label: 'Readiness by area', min: 1 },
  ] },
  layer1: { label: 'Layer 1 Register', slug: 'layer-1-register', icon: 'database', subtitle: 'Official registers (CRICOS and others), rankings files and key dates.', tabs: [
    { key: 'operations', label: 'Runs', min: 4 },
    { key: 'imports', label: 'Ranking imports', min: 4 },
    { key: 'sources', label: 'Sources', min: 4 },
    { key: 'settings', label: 'Source settings', min: 6 },
    { key: 'onboarding', label: 'Onboarding', min: 3 },
    { key: 'dates', label: 'Key dates', min: 3 },
    { key: 'links', label: 'Key links', min: 3 },
  ] },
  layer2: { label: 'Layer 2 Discovery & reading', slug: 'layer-2-discovery', icon: 'activity', subtitle: 'Finding provider pages and reading the facts on them.', tabs: [
    { key: 'operations', label: 'Runs', min: 4 },
    { key: 'profiles', label: 'Source profiles', min: 4 },
  ] },
  layer3: { label: 'Layer 3 AI validation', slug: 'layer-3-ai', icon: 'ai', subtitle: 'Run or pause each task, set its daily limit and choose the model cascade.', tabs: [
    { key: 'routing', label: 'Control', min: 3 },
    { key: 'models', label: 'Models', min: 3 },
    { key: 'work', label: 'Work queue', min: 3 },
  ] },
  layer4: { label: 'Layer 4 Review', slug: 'layer-4-review', icon: 'review', min: 3, subtitle: 'Decisions that need a person, with an audit trail.' },

  health: { label: 'Platform health', slug: 'platform-health', icon: 'health', subtitle: 'Automatic checks across jobs, queues, budgets and the database.', tabs: [
    { key: 'checks', label: 'Health checks', min: 3 },
    { key: 'readiness', label: 'Readiness & capacity', min: 6 },
  ] },
  jobs: { label: 'Scheduled jobs', slug: 'scheduled-jobs', icon: 'workflow', subtitle: 'Job history and the schedules that start them.', tabs: [
    { key: 'jobs', label: 'Jobs', min: 4 },
    { key: 'schedules', label: 'Schedules', min: 4 },
  ] },
  evidence: { label: 'Evidence', slug: 'evidence', icon: 'book', min: 3, subtitle: 'Saved source pages and files, and what they changed.' },

  environment: { label: 'Environment & integrations', slug: 'environment', icon: 'plug', min: 6, subtitle: 'External services, keys (names only) and usage against budgets.' },
  scrapers: { label: 'Scrapers & fetchers', slug: 'scrapers', icon: 'sliders', min: 4, subtitle: 'How pages are fetched: providers, limits and routing.' },
  regulatory: { label: 'Regulatory settings', slug: 'regulatory-settings', icon: 'shield', min: 6, subtitle: 'Regulator source registry and bounded ingestion controls.' },
  migration: { label: 'Environment migration', slug: 'environment-migration', icon: 'shield', min: 6, subtitle: 'What must be set up when moving to Production.' },
  dataModel: { label: 'Data model', slug: 'data-model', icon: 'tags', min: 5, subtitle: 'Attributes, families, groups and options.' },

  users: { label: 'Users & roles', slug: 'users-roles', icon: 'users', min: 6, subtitle: 'Who can sign in and what each person may do.' },
  contacts: { label: 'Provider contacts', slug: 'provider-contacts', icon: 'users', min: 1, subtitle: 'International recruitment contacts for each provider.' },
}

export const SECTIONS = [
  { label: '', pages: ['dashboard'] },
  { label: 'Catalogue', pages: ['courses', 'providers', 'scholarships', 'rankings'] },
  { label: 'Data pipeline', pages: ['coverage', 'layer1', 'layer2', 'layer3', 'layer4'] },
  { label: 'Operations', pages: ['health', 'jobs', 'evidence'] },
  { label: 'Platform settings', pages: ['environment', 'scrapers', 'regulatory', 'migration', 'dataModel'] },
  { label: 'Administration', pages: ['users', 'contacts'] },
]

for (const [key, p] of Object.entries(PAGES)) { p.key = key; if (p.tabs) p.min = Math.min(...p.tabs.map(t => t.min)); p.title = p.title || p.label }
export const SECTION_OF = Object.fromEntries(SECTIONS.flatMap(s => s.pages.map(k => [k, s.label])))

export function slugify(v) { return String(v).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') }

// Old addresses (and the old menu labels, which were turned into addresses the same way) → new page and tab.
// Every old menu entry, hidden route, alias and Administration section is listed, so old links keep working.
export const LEGACY = {
  'campuses': { page: 'providers', tab: 'campuses' },
  'provider-contacts': { page: 'contacts' },
  'completeness': { page: 'coverage', tab: 'domains' },
  'data-quality-readiness': { page: 'coverage', tab: 'domains' },
  'course-coverage': { page: 'coverage', tab: 'courses' },
  'compare': { page: 'rankings', tab: 'compare' },
  'outcomes-qilt': { page: 'rankings', tab: 'qilt' },
  'student-flow-prisms': { page: 'rankings', tab: 'prisms' },
  'layer-1-operations': { page: 'layer1', tab: 'operations' },
  'layer-1-regulatory': { page: 'layer1', tab: 'operations' },
  'layer-1-authority': { page: 'layer1', tab: 'operations' },
  'sources': { page: 'layer1', tab: 'sources' },
  'onboarding': { page: 'layer1', tab: 'onboarding' },
  'important-dates': { page: 'layer1', tab: 'dates' },
  'important-links': { page: 'layer1', tab: 'links' },
  'layer-2-enrichment': { page: 'layer2', tab: 'operations' },
  'layer-2-operations': { page: 'layer2', tab: 'operations' },
  'layer-3-ai-interpretation': { page: 'layer3' },
  'layer-4-human-resolution': { page: 'layer4' },
  'review-queue': { page: 'layer4' },
  'jobs-schedules': { page: 'jobs' },
  'jobs': { page: 'jobs', tab: 'jobs' },
  'scheduled-tasks': { page: 'jobs', tab: 'schedules' },
  'refresh-scheduling': { page: 'jobs', tab: 'schedules' },
  'attributes': { page: 'dataModel' },
  // The old '#settings' address opened Administration > Platform (readiness), not the regulatory page.
  'settings': { page: 'health', tab: 'readiness' },
  'statistics-rankings': { page: 'rankings' },
  'administration': { page: 'scrapers' },
}

// Old Administration sections (#administration?section=...) → new page and tab.
export const LEGACY_ADMIN_SECTIONS = {
  'overview': { page: 'scrapers' },
  'sources-imports': { page: 'layer1', tab: 'imports' },
  'layer1-sources': { page: 'layer1', tab: 'settings' },
  'layer2-providers': { page: 'scrapers' },
  'provider-assets': { page: 'providers', tab: 'assets' },
  'layer2-sources': { page: 'layer2', tab: 'profiles' },
  'onboarding': { page: 'layer1', tab: 'onboarding' },
  'pim': { page: 'dataModel' },
  'users-roles': { page: 'users' },
  'environment-migration': { page: 'environment' },
  'platform': { page: 'health', tab: 'readiness' },
  'statistics-datasets': { page: 'rankings', tab: 'datasets' },
}

const BY_SLUG = Object.fromEntries(Object.values(PAGES).map(p => [p.slug, p.key]))
const BY_LABEL = Object.fromEntries(Object.values(PAGES).map(p => [slugify(p.label), p.key]))

export function allowedTabs(page, rank) { return (page?.tabs || []).filter(t => rank >= t.min) }
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
  return { page: hit.page, tab, params: p }
}

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
