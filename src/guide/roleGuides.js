// Guides › Role guides (v2.16.35; Platform Admin 18 Nov 2026 10:31 and 10:33, chat S1-RM-Design: "Role Guides & SOPs tailored strictly to each
// role's permissions and limitations, accessible directly from the in-app Help/Guides menu and mirrored in docs/platform/").
//
// One source for the app and the documents: src/RoleGuides.jsx renders these objects and scripts/export-role-guides.mjs writes the same words to
// docs/role-guides/*.md, mirrored to the admin repository's docs/platform/role-guides/ (never edited there by hand). The pages a role can open are
// not written here: they are worked out from the menu (src/nav-map.js, each page's and tab's lowest rank), so a guide cannot promise a page the
// role cannot open. What a role can and cannot do follows the server's checks (security.current_role_rank in each admin function).
// When a release changes what a role can do: change the guide here, raise its version, add a line to its changes, run
// `node scripts/export-role-guides.mjs` and mirror it with `--write-mirror <coursefinder-admin>/docs/platform/role-guides`.
import { PAGES, canOpen, shownTabs } from '../nav-map.js'
import { UI_VERSION } from '../release-manifest.js'

// The guides are reviewed against the live route map in every release: tests/uat/cf-247-s1046 fails the build when a guide names a page or tab absent from docs/UI-MAP.md
export const ROLE_GUIDES_REVIEWED_FOR = UI_VERSION

// security.roles ranks 1 to 6 (the same names the menu and Users & roles show)
export const ROLE_GUIDES = [
  {
    id: 'viewer', role: 'Viewer', rank: 1, version: '1.0',
    purpose: 'Read and search the catalogue: courses, providers, campuses, scholarships, entry requirements, rankings and how complete each record is.',
    can: ['Search and filter every course, provider, campus and scholarship list, and open any record with its sources.',
      'Read entry requirements by country of prior education, and rankings and statistics side by side.',
      'Export a list you are looking at as CSV.',
      'Pick up a search or page you left from Dashboard › Continue where you left off.'],
    cannot: ['Change any value, status or setting. Nothing you do changes data.',
      'Open Layer 1 to Layer 4, Destination data, Reference data, Platform health, Scheduled jobs, Settings or Users & roles.'],
    start: ['Dashboard: type what you are looking for in Search the catalogue, or open Courses, Providers or Scholarships.',
      'Courses: filter by study level, field, city or provider; open a course to see its fees, intakes, English and entry requirements and where each came from.'],
    tasks: [{ task: 'Find a course', steps: ['Open Courses.', 'Type part of the title, or filter by study level, field of study, city or provider.', 'Open the course: each value shows the page it was read from.'] },
      { task: 'Compare providers', steps: ['Open Rankings & statistics › Compare.', 'Choose the providers; QS, THE, QILT and PRISMS figures sit side by side with their edition.'] }],
    ask: 'Ask a Platform Admin when you need to correct a value or need more access: your role is changed on Users & roles.',
    changes: [{ version: '1.0', date: '18 Nov 2026', release: '2.16.35', change: 'First issue.' }],
  },
  {
    id: 'counsellor', role: 'Counsellor', rank: 2, version: '1.2',
    purpose: 'Find the right course and scholarship for a student, and check what they need to get in: English, academic entry and study load.',
    can: ['Everything a Viewer can.',
      'Use course search for a student: study level, field, city, fees, intakes, study load (full-time, part-time or both) and English requirement.',
      'Read entry requirements for the student\'s country of prior education, and the scholarships open to international students.',
      'Pick up the searches you were working on from Dashboard › Continue where you left off.',
      'Report a wrong or missing value from a course (Report a data issue) and follow its outcome under My reports; you see only your own reports.',
      'Read how complete each record is: a bar and a percentage on every course and provider row, and Missing field pills (Fee, Intake, English, Scholarship, Description, Study load on Courses) that narrow the list to records lacking those fields.'],
    cannot: ['Change any value, status or setting.',
      'Decide review items, approve, publish or run jobs. Those are Curator, operator and Platform Admin work.'],
    start: ['Dashboard: Search the catalogue, then narrow the list with the filters on Courses.',
      'A course\'s study load and empty reason say what the provider states and why a value is missing; a missing value is never guessed.'],
    tasks: [{ task: 'Shortlist courses for a student', steps: ['Open Courses and filter by study level, field of study and city.', 'Add Study load from Columns to see full-time or part-time.', 'Open each course to check fees, intakes, English and entry requirements for the student\'s country.'] },
      { task: 'Find scholarships', steps: ['Open Scholarships.', 'Filter to international students and the study level; each scholarship links to the provider\'s own page.'] },
      { task: 'See which courses are incomplete', steps: ['Open Courses and choose one or more Missing field pills, for example Fee and Intake.', 'The list keeps courses lacking every pill you chose; the Completeness bar shows how much of each course is held.'] }],
    ask: 'Spotted a wrong value? Tell a Curator or Platform Admin with the course and what the provider\'s page says.',
    changes: [{ version: '1.0', date: '18 Nov 2026', release: '2.16.35', change: 'First issue.' }, { version: '1.1', date: '20 Nov 2026', release: '2.16.61', change: 'Completeness bars and Missing field pills on Courses and Providers.' }, { version: '1.2', date: '24 Nov 2026', release: '2.16.86', change: 'Report a data issue on a course and My reports in the app.' }],
  },
  {
    id: 'curator', role: 'Curator', rank: 3, version: '1.1',
    purpose: 'Keep the catalogue right: decide what waits for a person, correct records by hand, and prepare new sources and reference data for a Platform Admin to approve.',
    can: ['Everything a Counsellor can.',
      'Open Layer 4 Review › Inbox, read every item, and decide the kinds open to your role (an item whose decision needs a higher role says so and its buttons are greyed); correct course, provider, campus and scholarship values by hand (a value entered by hand is never overwritten by automation).',
      'Open Layer 1 Register and prepare + Add source drafts (country, record type, field mapping); edit key dates and reference site details.',
      'Read Destination data, Reference data, Platform health and Evidence.',
      'Find incomplete records in one click: Missing field pills on Courses and Providers, a Completeness bar on every row, and in a provider\'s drawer a Completeness and provenance panel (the description\'s source reads Register, AI verified or Human input · Locked). Tick providers to get a bar with Fill fields, Queue to Intake Run & Validate, Flag primary campus (Platform Admin), Export selected (CSV) and Clear. A Human Locked pill marks any tracked field a person has locked, in the provider and course drawers.',
      'Layer 2/3 Build & enrich › Operations › Intake Run & Validate: pick approved Australian universities or hand-picked courses and read the stages, evidence and before / after intake values.',
      'Layer 1 Register › + Add source is where a new country is prepared (country, record type, field mapping).'],
    cannot: ['Activate a source, approve or publish destination data, change settings, run or pause jobs, or manage users. Those buttons are greyed for you, and the server refuses them too.',
      'Re-infer a parser or send work back to the AI (Pipeline Operator and above).'],
    start: ['Layer 4 Review › Inbox, Review by rule: choose the queue and the largest rule group; work one card at a time.',
      'Layer 1 Register › + Add source › Continue a draft: finish the mapping, then tell a Platform Admin it is ready to activate.'],
    tasks: [{ task: 'Work the Inbox', steps: ['Open Layer 4 Review (Review by rule opens first).', 'Pick a queue and a rule group; read the quote and the source page; decide it, or correct the record, where your role allows.', 'The decision is kept with who, when and why.'] },
      { task: 'Fix the incomplete providers in a country', steps: ['Open Providers, choose the country, then the Missing field pills you care about (for example Website).', 'Tick the providers to work on; the bar offers Fill fields (description only), Queue to Intake Run & Validate, Flag primary campus (Platform Admin) and Export selected (CSV).', 'Open a provider: the Completeness and provenance panel shows what is held, what is missing and where the description came from.'] },
      { task: 'Prepare a new source for a country', steps: ['Open Layer 1 Register › + Add source.', 'Choose the country and the record type, map the fields, note the licence terms.', 'Save the draft. A Platform Admin activates it after a dry run.'] }],
    ask: 'Anything that needs approving, activating or publishing goes to a Platform Admin; a job that looks stuck goes to a Pipeline Operator.',
    changes: [{ version: '1.0', date: '18 Nov 2026', release: '2.16.35', change: 'First issue.' }, { version: '1.1', date: '20 Nov 2026', release: '2.16.61', change: 'Completeness, Missing field pills, bulk bar and provenance panel; Intake Run & Validate and Layer 1 country preparation named.' }],
  },
  {
    id: 'pipeline-operator', role: 'Pipeline Operator', rank: 4, version: '1.0',
    purpose: 'Keep the data pipeline moving: watch jobs and queues, run and pause them, and send work back to the AI.',
    can: ['Everything a Curator can.', 'Run, pause and resume scheduled jobs; read API usage and services and limits; re-infer a Layer 1 parser.'],
    cannot: ['Activate sources, approve or publish, change settings or manage users (Platform Admin).'],
    start: ['Follow the Operator SOP (Guides › Operator SOP): it is your daily routine.'],
    tasks: [], ask: 'Escalate anything that needs approval to a Platform Admin.',
    changes: [{ version: '1.0', date: '18 Nov 2026', release: '2.16.35', change: 'First issue.' }],
  },
  {
    id: 'pim-operator', role: 'PIM Operator', rank: 5, version: '1.0',
    purpose: 'Manage records: add and archive providers and courses, approve fee rules, build adapters and publish providers.',
    can: ['Everything a Pipeline Operator can.', 'Add and archive records, approve fee rules, use Adapter builder and the integration queue, publish a provider.'],
    cannot: ['Change settings, models, keys or users; approve destination data; activate a Layer 1 source (Platform Admin).'],
    start: ['Follow the Operator SOP (Guides › Operator SOP).'],
    tasks: [], ask: 'Escalate settings, keys and activations to a Platform Admin.',
    changes: [{ version: '1.0', date: '18 Nov 2026', release: '2.16.35', change: 'First issue.' }],
  },
  {
    id: 'platform-admin', role: 'Platform Admin', rank: 6, version: '1.1',
    purpose: 'Own the platform: approve and publish, activate sources, set limits and settings, manage users, and keep the go-live checklist.',
    can: ['Everything every other role can.',
      'Approve and publish destination data (Bulk Approve Drafts, Publish edition), activate Layer 1 sources after a dry run, approve central pages and fee schedules.',
      'Change settings, models, services and limits; manage users and roles; edit the Links & Email Templates and the email delivery provider.',
      'Everything a Curator does with completeness and provenance. The Missing field filter for Providers is the `missing` argument of the providers read (one list of fields); nothing in it writes to the catalogue.'],
    cannot: ['Nothing is closed to you, but every approval, activation and setting change needs a reason and is kept in the control log; a passing test never switches anything on by itself.'],
    start: ['Dashboard: the five cards and Active failures, then Layer 1 Register and Layer 4 Review for what only you can do.',
      'Follow the Platform Admin SOP (Guides › Platform Admin SOP) for the daily routine.'],
    tasks: [{ task: 'Invite a person', steps: ['Open Users & roles and choose Create user.', 'Enter the email and name, choose one role (its permissions are shown), choose Send invitation.', 'Review and create: the person gets an email whose link opens the admin sign-in.'] },
      { task: 'Publish a destination edition', steps: ['Approve its localities and figures (Bulk Approve Drafts on each tab).', 'Record the edition terms, then Publish edition on Overview & editions with a reason.'] }],
    ask: 'Changes to the consumer API need your recorded approval (G3); drops and deletes go out as a paste file, never a migration.',
    changes: [{ version: '1.0', date: '18 Nov 2026', release: '2.16.35', change: 'First issue.' }, { version: '1.1', date: '20 Nov 2026', release: '2.16.61', change: 'Completeness and provenance workflows added.' }],
  },
]

// a role guide for the role rank given (the highest guide at or below it)
export const guideForRank = (rank) => [...ROLE_GUIDES].reverse().find((g) => g.rank <= Number(rank || 0)) || ROLE_GUIDES[0]

// the pages and tabs a role can open, from the menu itself
export function pagesFor(rank) {
  const r = Number(rank || 0)
  // the menu's own rule (canOpen) decides the page; shownTabs decides its tabs
  return Object.entries(PAGES).filter(([k]) => k !== 'dashboard' && canOpen(k, r))
    .map(([k, p]) => ({ key: k, label: p.label, tabs: (p.tabs || []).length ? shownTabs(p, r).map((t) => t.label) : [] }))
}

export function roleGuideMarkdown(g) {
  const L = [`# StudySearch – ${g.role} guide`, '', `**Version:** ${g.version} (reviewed for platform release v${ROLE_GUIDES_REVIEWED_FOR})  `, `**Role:** ${g.role} (rank ${g.rank})  `,
    '**Change control:** CF-247  ', '**Source:** generated from the Pilot `src/guide/roleGuides.js` and the menu; never edited by hand.', '',
    '## 1. What this role is for', '', g.purpose, '', '## 2. What you can do', '', ...g.can.map((x) => `- ${x}`), '',
    '## 3. What you cannot do', '', ...g.cannot.map((x) => `- ${x}`), '', '## 4. Pages you can open', '',
    ...pagesFor(g.rank).map((p) => `- **${p.label}**${p.tabs.length ? `: ${p.tabs.join(', ')}` : ''}`), '', '## 5. Where to start', '', ...g.start.map((x) => `- ${x}`), '']
  if (g.tasks.length) {
    L.push('## 6. Common tasks', '')
    for (const t of g.tasks) L.push(`### ${t.task}`, '', ...t.steps.map((s, i) => `${i + 1}. ${s}`), '')
  }
  L.push(`## ${g.tasks.length ? 7 : 6}. When to ask someone`, '', g.ask, '', `## ${g.tasks.length ? 8 : 7}. Version history`, '', '| Version | Date | Release | Change |', '|---|---|---|---|',
    ...g.changes.map((c) => `| ${c.version} | ${c.date} | v${c.release} | ${c.change} |`), '')
  return L.join('\n')
}
