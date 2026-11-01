// Operating words shared by the Platform guide, the SOPs and the screens (SS-016, Platform Admin 1 Nov 2026 22:01). Re-exported by
// src/guide/platformGuide.js; contract: tests/uat/cf-247-s206-guide-operational-truth-contract.spec.mjs. Plain Australian English, no values
// that drift (each gate names the screen that shows its live value).

// SS-016 UR-08 (Platform Admin 1 Nov 2026 22:01): one set of words for who changes an automation and who admits its values, used by this
// guide, the SOPs and Scheduled jobs › Automations. Live: security.admin_automation_control_v1 refuses below rank 5, then checks the
// automation's control_rank (default 6), so the effective owner is the higher of the two; a control_rank of 4 still needs a PIM Admin.
export const CONTROL_ROLE = { 5: 'PIM Admin', 6: 'Platform Admin' }
export const controlOwner = (controlRank) => CONTROL_ROLE[Math.min(6, Math.max(5, Number(controlRank) || 6))]
// How a value gets in. Each automatic path names its switch and where a person decides instead; the switches are not changed here.
export const ADMISSION_WORDS = {
  proposed: 'Proposed: a person decides',
  auto: 'Automatic while its switch is on',
  person: 'A person decides',
  reads: 'Reads only: admits nothing',
}
export const ADMISSION_PATHS = [
  { job: 'provider-onboarding', what: 'Adapter fields that pass the admit rule (onboarding stage 4)', path: 'auto',
    switch: 'Admit automatically (Layer 2 › Onboarding › Onboarding settings; Platform Admin, with a reason)',
    person: 'Switch off: a Platform Admin admits the Ready to admit fields on Layer 2 › Adapters. Switch on: a Platform Admin spot-checks "Admitted automatically" and undoes a wrong one there. A field that did not pass is never admitted.' },
  { job: 'policy-auto-approve', what: 'AI readings of English policies and academic calendars', path: 'auto',
    switch: 'Pipeline settings: "Approve AI readings of central pages automatically (focus providers)" and "Central pages: approve English rules for every university"',
    person: 'A reading with a value not quoted on the page, or whose English default most course pages disagree with, is flagged and waits in Approvals waiting for a Platform Admin.' },
  { job: 'central-ai', what: 'English policy and calendar pages read by the pinned AI', path: 'proposed',
    switch: 'None: it only proposes',
    person: 'Approved by policy-auto-approve while its switches are on; otherwise a Platform Admin in Approvals waiting or the Adapter builder (1.3).' },
  { job: 'provider-facts', what: 'Fee schedules, English policies and calendars found on a university\'s site', path: 'proposed',
    switch: 'None for fee schedules: they always wait',
    person: 'A Platform Admin approves each fee schedule. English policies and calendars follow central-ai and policy-auto-approve.' },
  { job: 'fee-reader', what: 'Fees read from fee pages by the AI', path: 'auto',
    switch: 'Fee reader: admit automatically at match confidence (Pipeline settings › Enrichment)',
    person: 'A row below the confidence setting goes to Layer 4 for a person.' },
  { job: 'layer4-auto-admit', what: 'Layer 4 first runs with a shape a person has already approved', path: 'auto',
    switch: 'Auto-admit first runs: on (Pipeline settings)',
    person: 'New shapes, and one in each audit sample, stay in Layer 4 for a person; automatic ones show in Decided as "Auto: <reason>".' },
  { job: 'entry-matrix-read', what: 'Entry requirement (AER) rows', path: 'proposed',
    switch: 'Entry matrices: reader on (Pipeline settings); it reads, it never admits',
    person: 'The Platform Admin decides each item in Layer 4, one at a time.' },
]

// SS-016 UR-10 (Platform Admin 1 Nov 2026 22:01): which gate stopped work, its effective mode and who may change it. Values are not repeated
// here (they drift); each gate names the screen that shows the live value. Live 1 Nov 2026: OpenRouter mode observe; Firecrawl daily budget on.
// `notices` are the toolset:kind pairs of security.platform_notices_v1 that this gate raises; Models & services shows the gate beside them.
export const BUDGET_GATES = [
  { key: 'openrouter-guard', gate: 'StudySearch AI guard (daily guard per AI use, credit floor)', notices: ['openrouter:over_guard', 'openrouter:low_balance'],
    mode: 'Observe only: notices only, nothing stops. Stop at limits: an AI use stops at its daily guard until the UTC day changes, and the AI stops below the credit floor. The mode is shown on Models & services › AI & OpenRouter.',
    where: 'Models & services › AI & OpenRouter (mode, credit floor, Daily guards)', who: 'Change: Platform Admin' },
  { key: 'openrouter-refused', gate: 'Refused by OpenRouter (outside StudySearch)', notices: ['openrouter:refused'],
    mode: 'In either mode: out of credit, the key\'s own spending limit, a rate limit or a key not accepted. The refused pages are read again later.',
    where: 'The OpenRouter account (Workspaces › Keys); the key on Models & services', who: 'Platform Admin (top up or change the key\'s limit at OpenRouter)' },
  { key: 'adapter-allowance', gate: 'Adapter AI allowance (proposals and US$ a day)', notices: [],
    mode: 'Always applies, whatever the OpenRouter mode: adapter proposals stop for the Melbourne day when either allowance is used.',
    where: 'Models & services › Toolsets & limits (adapter AI allowance)', who: 'Change: Platform Admin' },
  { key: 'firecrawl-daily', gate: 'StudySearch Firecrawl daily budget (billed total and a share per purpose)', notices: ['firecrawl:daily_budget'],
    mode: 'While "Keep to the daily budget" is on, work whose share is used up waits until midnight, Melbourne time; on-demand plan runs have their own allowance. Off: nothing stops.',
    where: 'Models & services › Toolsets & limits › Firecrawl › Daily budget', who: 'Change: Platform Admin, with a reason' },
  { key: 'firecrawl-balance', gate: 'Firecrawl account balance (outside StudySearch)', notices: ['firecrawl:low_balance'],
    mode: 'Firecrawl refuses work when the month\'s credits are gone; the platform warns below its warning level.',
    where: 'Models & services › Toolsets & limits › Firecrawl credits', who: 'Platform Admin (top up at Firecrawl)' },
  { key: 'firecrawl-caps', gate: 'StudySearch caps: course-page search a month; scholarship credits per university', notices: ['firecrawl:cap_reached'],
    mode: 'Always applies: the work waits for the next month or the next 30-day window.',
    where: 'Models & services › Toolsets & limits › Course-page search budget; Layer 2 › Scholarships (scholarship credits)', who: 'Change: Platform Admin' },
  { key: 'aer-gates', gate: 'Entry requirement (AER) programme gates', notices: [],
    mode: 'The reader runs only while "Entry matrices: reader on" is set; course-level reading runs one bounded batch a Platform Admin asks for. The AER daily AI guard follows the OpenRouter mode like every AI use.',
    where: 'Catalogue › Entry requirements › Course-level reading; Pipeline settings', who: 'Platform Admin' },
]
export const gateFor = (toolset, kind) => BUDGET_GATES.find((g) => g.notices.includes(`${toolset}:${kind}`)) || null

// SS-016 UR-11 (Platform Admin 1 Nov 2026 22:01): how a figure says when it was measured. Two capture windows are never one baseline, and
// a figure with no measurement is "No result yet", never OK.
export const FRESHNESS_WORDS = {
  current: 'This run',
  earlier: 'From an earlier run',
  missing: 'No result yet',
  report: 'At report time',
}

// SS-016 UR-11 (Platform Admin 1 Nov 2026 22:01): each check says which run measured it. The newest checked_at is this run; a check with
// an older time (a slow 3-hourly check, a daily one, or one that stopped) is from an earlier run and says when; a check with no time has
// no result and is never shown as OK. No threshold: the run times themselves tell the windows apart.
export function checkFreshness(checks) {
  const t=c=>c?.checked_at?Date.parse(c.checked_at):NaN,latest=Math.max(...(checks||[]).map(t).filter(Number.isFinite))
  return (c) => !Number.isFinite(t(c))?'missing':t(c)===latest?'current':'earlier'
}

// SS-016 UR-12 (Platform Admin 1 Nov 2026 22:01): low use alone never retires anything. Shown on Screen use and beside a retiring automation.
export const RETIREMENT_CRITERIA = [
  'Purpose: what it is for, and whether that responsibility still exists.',
  'Unique coverage: nothing else shows or does the same; recovery, audit and role controls stay however rarely they are opened.',
  'Dependencies and replacement: what reads it or calls it, and the named replacement (or an approved removal of the responsibility).',
  'Consumers: people, jobs, the website and Zoho that use it; the consumer API is never retired this way.',
  'Walk-through: the replacement is walked through in isolation before the old one is switched off; saved links and history keep working.',
]
