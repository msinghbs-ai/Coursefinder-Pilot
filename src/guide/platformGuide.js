// Platform guide (Decision 209): how operators and Platform Admins run CourseFinder, shown in the app under
// Help › Platform guide. This file is the single source of the guide's words.
//
// KEEP IT CURRENT. Every release must review this guide:
//   * GUIDE_REVIEWED_FOR must equal UI_VERSION in src/release-manifest.js (the contract test fails otherwise);
//   * every page in src/nav-map.js must have an entry in SCREENS (the contract test fails otherwise);
//   * a release that changes what a screen shows, a role can do, a job, a budget or an alert updates the matching
//     entry below in the same pull request.
// Plain Australian English; no numbers that go stale (counts and amounts live on the screens themselves).

export const GUIDE_REVIEWED_FOR = '2.15.137'

export const ROLES = [
  { role: 'Viewer', rank: 1, who: 'Stakeholder, auditor', can: 'Read every screen they can open; change nothing.' },
  { role: 'Counsellor', rank: 2, who: 'Student adviser', can: 'Shortlists and notes.' },
  { role: 'Curator', rank: 3, who: 'Content editor', can: 'Course and provider details, course links, Layer 4 decisions, linking ranked universities to providers.' },
  { role: 'Pipeline Operator', rank: 4, who: 'Data operations', can: 'Pause, resume and pace automations; link refresh schedules and portals; who-can-apply settings; send review items back to the AI.' },
  { role: 'PIM Admin', rank: 5, who: 'Catalogue owner', can: 'Reference data, rules and bulk catalogue actions.' },
  { role: 'Platform Admin', rank: 6, who: 'Platform owner', can: 'Approvals that write data in bulk (fee schedules, fee rules), AI models and budgets, service keys, users and roles, new countries.' },
]

export const RULES = [
  'A value entered by hand is never overwritten by automation; release it on the record to let automation update it again.',
  'A passing test never switches anything on by itself. A Platform Admin switches it on as a separate step.',
  'AI models are pinned to models that passed their test for that task; nothing routes to an unqualified model.',
]

export const DAILY_ROUTINE = [
  { title: 'Dashboard › Waiting for you', page: 'dashboard', text: 'Note review items, flagged records and scholarships waiting. A number that does not fall over two days means reviewers are behind.' },
  { title: 'Platform health › Needs attention', page: 'health', text: 'Clear every Critical item today. Read each Warning: fix it, or note why it can wait.' },
  { title: 'Scheduled jobs › Automations', page: 'jobs', tab: 'automations', text: 'Check "Failed in the last 24 hours". Open any failed automation and read its last error (see Signal → action).' },
  { title: 'Layer 3 AI validation › Control', page: 'layer3', text: 'Check spend today against each task\'s daily limit and the OpenRouter credit. "Stopped for today" means the limit was reached; it restarts tomorrow.' },
  { title: 'Coverage & completeness', page: 'coverage', text: 'Course links, English, intakes and tuition counts should rise. Flat for a day means a job is stuck or out of budget.' },
  { title: 'Layer 4 Review', page: 'layer4', text: 'Work the oldest items first: approve, correct, or send back to the AI with a reason.' },
  { title: 'Approvals (Platform Admin)', page: 'coverage', tab: 'attributes', text: 'Fee schedules waiting for approval, and ranking links waiting for a person (Rankings › QS or THE › Link: Not linked).' },
]

// One entry per menu page (src/nav-map.js). `answers` = the question the screen answers; `read` = what to look at;
// `act` = what a person does there.
export const SCREENS = {
  dashboard: { answers: 'What is waiting for a person today?', read: ['Waiting for you: review items, flagged records and scholarships, each opening its list.', 'Platform health bar: green, amber or red summary.', 'Layers panel: what each layer handled in the last 24 hours; zero for a day means a stuck job.'], act: ['Click a card to go straight to the work.'] },
  courses: { answers: 'What do we hold for each course, and where did each value come from?', read: ['Filters include "International students" (open to international, domestic only, both, not known).', 'Each value shows its source and evidence; a value changed by hand shows "set by hand".'], act: ['Edit a course (Curator and above). Your change is locked against automation until you release it.', 'Course links: official page, handbook, international page, how to apply, admission centre, regulator listing.'] },
  providers: { answers: 'Who are the providers, and what do we know about each?', read: ['Provider record: details, who can apply, World rankings (QS and THE by edition), outcomes and scholarships.', 'Campuses, Logos & assets and Onboarding tabs.'], act: ['Edit provider details and "Enrols international students" (Pipeline Operator and above).'] },
  contacts: { answers: 'Who are the international recruitment contacts for each provider?', read: ['Contacts with their source and when they were last checked.'], act: ['Correct or add a contact.'] },
  scholarships: { answers: 'Which scholarships exist, and which are published?', read: ['Scholarships, their course links and their publishing state.'], act: ['Link scholarships to courses; publish or hold back.'] },
  rankings: { answers: 'How does each university rank, and how do providers compare?', read: ['QS and THE: filter by country, state, provider and whether a university is linked to a provider.', 'A linked provider name opens its provider record.', 'Compare, QILT outcomes and PRISMS student flow tabs.'], act: ['Link a ranked university with no provider (Curator and above): pick a suggestion or search; the link covers every edition.', 'Universities are linked automatically every hour when the names agree in the same country; close matches wait for a person.'] },
  reference: { answers: 'Which reference files, dates and outside sites does the platform use?', read: ['Ranking imports, key dates and reference sources.'], act: ['Import a new ranking edition; add a key date; register a reference source.'] },
  coverage: { answers: 'How complete is the catalogue?', read: ['Courses tab: courses with an official page, English requirements, intakes and a current fee, by country and provider.', 'Link refresh: how often each kind of course link is checked again, and which portals supply links.', 'Attributes tab: the same by attribute, and Fee schedules (Pipeline Operator and above).'], act: ['Change a link refresh schedule or switch a portal on (Pipeline Operator and above).', 'Approve or reject a university\'s fee schedule (Platform Admin): approval adds a fee only to courses with none, settles flagged fees it answers, and lists (does not change) a different fee on record.'] },
  layer1: { answers: 'Are the official registers (CRICOS, NZQA) loaded and current?', read: ['Runs, source settings and manual batch runs.'], act: ['Start or re-run a register load (Pipeline Operator; settings Platform Admin).'] },
  layer2: { answers: 'Are provider pages being found and read?', read: ['Overview, Fetch an area, History and Source profiles.', 'Course-page search, page reading and the fee schedule reader run as automations (Scheduled jobs).'], act: ['Fetch an area; adjust a source profile.'] },
  layer3: { answers: 'Is the AI step working, within budget?', read: ['Spend today against each task\'s daily limit, and the OpenRouter credit (read every few minutes).', 'Each task (intakes, English, tuition) runs a cascade of tested models, cheapest first; Last 24 hours shows admitted, not stated on the page, sent to review and retrying.'], act: ['Pause or run a task; set its daily limit; reorder or switch a model step (Platform Admin).', 'All tasks stop when the credit reaches the floor; top up OpenRouter before then.'] },
  layer4: { answers: 'What needs a person\'s judgement?', read: ['Review queue, flagged values, send back to AI, fee rules and blocks.'], act: ['Approve, correct, or send back to the AI with a reason. Oldest first.', 'Flagged values: an approved fee schedule settles the flags it answers (same fee, or a per-year fee close to it). For the rest the schedule\'s fee is shown beside the flagged fee; use it, confirm, correct or remove.', 'Fee rules: for universities without a fee schedule. Preview first, then approve; values entered by hand are never changed.'] },
  health: { answers: 'Is anything broken or about to run out?', read: ['Needs attention: Critical, Warning and Info.', 'Checks table, including budgets: Firecrawl balance (as Firecrawl reports it) and OpenRouter spend against the AI task limits.'], act: ['Critical: act today. Warning: act this week or record why not.'] },
  jobs: { answers: 'Is every automation running?', read: ['Top cards: running, paused, runs and failures in 24 hours.', 'Each automation: what it does, how often, last run and its reason when it failed.'], act: ['Pause, resume, run now, change how often and how many per run (Pipeline Operator and above).'] },
  evidence: { answers: 'Which saved page or file supports a value?', read: ['Saved source pages and files, and what they changed.'], act: ['Open the evidence behind any value.'] },
  sources: { answers: 'Is every source the pipeline reads healthy?', read: ['Every source across all layers, with its health and history.'], act: ['Pause or re-check a source.'] },
  environment: { answers: 'Are the outside services set up, and within budget?', read: ['Keys for outside services (never shown) and usage against budgets.'], act: ['Rotate a key (Platform Admin). Never paste keys into notes or tickets.'] },
  scrapers: { answers: 'How are pages fetched?', read: ['Fetching providers, limits and routing.'], act: ['Change limits or routing (Pipeline Operator and above).'] },
  services: { answers: 'Which AI models and page services are switched on?', read: ['Models and services, and whether each passed its test.'], act: ['Switch a model on only after it passes its test (Platform Admin); anything off is offered nowhere else.'] },
  dataModel: { answers: 'Which attributes, families, groups and options exist?', read: ['The catalogue\'s attribute definitions.'], act: ['Read only. Changes are made as reviewed database changes.'] },
  migration: { answers: 'What must pass before Production is switched on?', read: ['The go-live checklist.'], act: ['Platform Admin works the checklist.'] },
  users: { answers: 'Who can sign in, and what may each person do?', read: ['People, roles and expiry dates.'], act: ['Give each person the lowest role that lets them do their job; use an expiry date for contractors (Platform Admin).'] },
}

export const SIGNALS = [
  { see: 'Automation failed: "took too long and was stopped by the database time limit"', where: 'Scheduled jobs', means: 'One run tried too much work', act: 'Lower "per run" by about a third; check the next run succeeds', who: 'Operator' },
  { see: 'The same automation failed 3 or more runs in a row with the same reason', where: 'Scheduled jobs', means: 'A real fault, not load', act: 'Pause it, note the reason, raise it with the platform engineer', who: 'Operator' },
  { see: '"Stopped for today" on a Layer 3 task', where: 'Layer 3', means: 'Its daily limit was reached', act: 'Nothing; it restarts tomorrow. Raise the limit only if the credit allows', who: 'Platform Admin' },
  { see: 'OpenRouter credit approaching the floor', where: 'Layer 3, Platform health', means: 'The AI step will stop at the floor', act: 'Top up the OpenRouter account the platform\'s key uses', who: 'Platform Admin' },
  { see: 'Firecrawl balance near the reserve', where: 'Platform health › budgets', means: 'Searches and reads stop to protect the reserve', act: 'Lower search pace, add credits, or wait for the monthly refresh', who: 'Platform Admin' },
  { see: '"Retrying" keeps rising on a Layer 3 task', where: 'Layer 3', means: 'Model calls are failing or timing out', act: 'Check the model in Models & services; pause the task if errors persist', who: 'Operator' },
  { see: 'Layer 4 waiting count rises for 2 or more days', where: 'Dashboard, Layer 4', means: 'Reviewers are behind', act: 'Work oldest first; send repeat cases back to the AI with a reason', who: 'Curator' },
  { see: 'A coverage count flat for a day', where: 'Coverage', means: 'Its job is paused, failing or out of budget', act: 'Check that job in Scheduled jobs and the budgets check', who: 'Operator' },
  { see: 'A course link shown as gone', where: 'Course record, Link refresh', means: 'The provider page returns "not found"', act: 'It is searched for again automatically; fix by hand if the course has moved', who: 'Curator' },
  { see: 'A fee schedule waiting for approval', where: 'Coverage › Attributes › Fee schedules', means: 'Parsed fees are ready to add', act: 'Open the rows, check a few against the document, approve or reject', who: 'Platform Admin' },
  { see: 'Ranked universities not linked in a country we hold', where: 'Rankings › QS or THE (Link: Not linked)', means: 'The names did not agree closely enough to link automatically', act: 'Link from the suggestions or a search, or mark "Not this one"', who: 'Curator' },
]

export const ADMIN_DUTIES = [
  { title: 'Approvals (daily)', items: ['Fee schedules: compare three or four rows against the provider\'s document, then approve.', 'Fee rules and other rules: preview first, then approve.', 'New AI models: switched on only after they pass the task\'s test.'] },
  { title: 'Budgets and keys (weekly)', items: ['Firecrawl: monthly plan; the guard follows the balance Firecrawl reports and stops at the reserve.', 'OpenRouter: prepaid credit; each AI task has a daily limit and all stop at the floor.', 'Supabase: project plan; screens stop a call after 8 seconds.', 'Keys live in Environment & keys and Models & services.'] },
  { title: 'Users (as needed)', items: ['Lowest role that does the job; expiry dates for contractors.'] },
  { title: 'Adding a country', items: ['Load its register in Layer 1.', 'Set its admission rule (which identities are accepted for links, English and intakes, and its currency).', 'Add a link refresh schedule only if it needs a different pace.', 'Switch on its portal in Link refresh, if one exists.', 'Ranked universities in the new country link automatically within the hour.', 'Watch Coverage for two days before announcing it.'] },
]

export const ALERTS = {
  status: 'Planned: alert emails through Mailgun (sending subdomain, DNS records and recipients to be confirmed). Until then, alerts are on screen only.',
  rows: [
    { alert: 'Health check Critical', when: 'On first detection, then daily while open', to: 'Operators and Platform Admin' },
    { alert: 'Automation failed 3 runs in a row', when: 'Once per automation per day', to: 'Operators' },
    { alert: 'OpenRouter credit low', when: 'Once a day', to: 'Platform Admin' },
    { alert: 'Firecrawl balance low', when: 'Once a day', to: 'Platform Admin' },
    { alert: 'Daily summary: approvals waiting, Layer 4 backlog, coverage change', when: '8 am Melbourne', to: 'Operators and Platform Admin' },
  ],
}
