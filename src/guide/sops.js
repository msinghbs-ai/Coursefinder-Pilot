// Guides › Platform Admin SOP and Operator SOP (v2.15.257; reviewed v2.15.258, Platform Admin 12 Oct 2026: "SOPs for Platform Admin and operators to manage
// the platform, as separate guides: their daily tasks, how the platform automates, what to pay attention to and where a person needs to
// intervene; kept up to date with every iteration of the UI and the data admission mechanism; under Guides in the UI and as versioned docs").
//
// One source for both: the app renders these objects (src/Sops.jsx) and scripts/export-sops.mjs writes the same words to docs/sops/*.md,
// which are copied to the admin repo (coursefinder-admin docs/sops/) as the versioned documents. Contract tests: SOP_REVIEWED_FOR equals the
// UI version (every release reviews the SOPs), every step opens a real screen, and docs/sops/*.md equal what this file generates.
// When a release changes a screen, an automation or where a person decides: change the steps here, raise the SOP's version, add a line
// to its changes, run `node scripts/export-sops.mjs`, and copy docs/sops/ to the admin repo with the change-control entry.

export const SOP_REVIEWED_FOR = '2.15.266'

// The data admission mechanism in one table: what runs by itself, and where a person decides. Shared by both SOPs.
export const AUTOMATION = [
  // v2.15.258 (Platform Admin bug 12/10-01): the stages follow the onboarding journey shown on Layer 2 › Onboarding (stages 1 to 7), then delivery
  { stage: '1. Provider in', runs: 'A university enters the platform from a Layer 1 register (CRICOS, NZQA, Canadian lists, refreshed on their schedule), another database import, or our own search. Every active university with courses and no admitting adapter is queued for onboarding; new ones start by themselves.',
    jobs: 'Register refresh scheduler (hourly), Register run driver, Register auto-ingest, Onboard universities', person: 'Nothing day to day. A Platform Admin adds a country or a new register, and can queue universities not yet in onboarding (Layer 2 › Onboarding).' },
  { stage: '2. Prepare', runs: 'Each university\'s website is found and verified, its contacts and central pages found, its site mapped, and each course\'s own page found by Firecrawl search (CRICOS code, then title) and read as evidence: directly first, through Firecrawl only when blocked or the page needs a browser (v2.15.261, to save credits). Up to 100 universities are worked at once, every minute. A university whose pages cannot be found moves aside after an hour without a page read, so the next one starts, and carries on by itself when its pages are read.',
    jobs: 'Onboard universities, Find provider websites, Discover course pages, Search for course pages, Read course pages, Match pages to courses', person: 'A website the finder could not verify (Layer 4 › Websites to find); a wrong website; course pages added by hand when none can be found.' },
  { stage: '3. Create adapter', runs: 'The pinned AI proposes the adapter from sample pages (twice more if nothing passes); it is saved in testing, applied to every stored page and qualified field by field. Central pages are suggested; when nothing passes, the AI reads the university\'s English policy and calendar pages for a person to approve. Nothing is admitted by the test.',
    jobs: 'Onboard universities, Task manager tasks, Read central pages with AI', person: 'Universities where nothing passes show "Needs a person" on Layer 2 › Onboarding.' },
  { stage: '4. Admit', runs: 'With Admit automatically switched on (since 12 Oct 2026, v2.15.259), the fields that pass the admit rule are admitted by themselves within 10 minutes and logged; otherwise onboarding waits. Fee schedules, English policies and academic calendars are turned into proposals (rule parser, and for policies and calendars a pinned AI model quoting every value). Nothing is written before a person decides.',
    jobs: 'Find and read fee schedules, English policies and calendars; Find central pages', person: 'A Platform Admin spot-checks automatic admits (or admits by hand while the switch is off), undoes a wrong one on Layer 2 › Adapters, and approves or rejects central pages (Adapter builder 1.3, or Layer 2 › Onboarding › Approvals waiting). Universities where nothing passed need a person.' },
  { stage: '5. Enrich courses', runs: 'Once admitted, the adapter is applied to the stored pages and writes its values to the courses (intakes, English, fees, delivery), with approved central pages filling courses that have none; admitted adapters and approved rules keep writing every 10 minutes. A value entered by hand is never overwritten. Values sources disagree on go to review.',
    jobs: 'Adapter values replace older ones, Admit intakes from course pages, Apply approved English policies, Apply provider fee profiles, Review rules (nightly)', person: 'Curators decide the Layer 4 Review queue, oldest first.' },
  { stage: '6. Scholarship adapter', runs: 'Only after its courses are enriched is the university\'s scholarship search started: its site mapped, scholarship pages screened and read through the scraper.',
    jobs: 'Onboard universities (Scholarship search task), Discover scholarships', person: 'Nothing day to day.' },
  { stage: '7. Admit scholarships', runs: 'Pinned AI models read each scholarship page in order (Qwen3 30B, then GPT-4.1 mini); every fact must be quoted from the page. Passing scholarships are published every hour; a nightly review withdraws any that stop passing. Onboarding is Done when no page waits for the AI or a person (or after 7 days).',
    jobs: 'Read scholarship pages with AI, Publish scholarships automatically (hourly), Nightly publication review', person: 'Curators decide pages no model could settle (Layer 4 › AI could not decide); a Platform Admin spot-checks the automatic publishing and holds anything wrong.' },
  { stage: 'Delivery', runs: 'Search, the website API, Wix and Zoho are refreshed for every changed course and scholarship.',
    jobs: 'Refresh search for changed courses, Course scholarship attribute, Rebuild API reference data', person: 'Nothing, unless a delivery job fails.' },
]

export const RULES = [
  'A value entered by hand is never overwritten by automation. Release it on the record to let automation update it again.',
  'A passing test switches nothing on by itself. Approving a central page, activating an AI model or adding it to the order is a separate step a person takes, with a reason. Admitting an adapter\'s passing fields is automatic only while a Platform Admin has switched on Admit automatically (Layer 2 › Onboarding settings, with a reason); a field that did not pass is never admitted.',
  'AI models are pinned and qualified for each task; nothing routes to an untested model. An AI answer counts only where its quote is on the stored page.',
  'AI spending is watched, not capped, while OpenRouter limits are set to Observe: Models & services › OpenRouter shows the balance, today\'s spend for each AI use against its daily guard and the credit floor, and a notice appears when one is passed. Nothing stops until a Platform Admin switches the limits to stop.',
  'Every background job is a scheduled job in the automation catalogue or a task in Task manager, with its controls. Something running that you cannot see there is a fault: report it.',
  'Work oldest first, give a reason for every decision, and never decide from memory: open the stored page or document.',
]

const step = (o) => o

export const SOPS = [
  {
    id: 'admin-sop', title: 'Platform Admin SOP', version: '1.9', audience: 'Platform Admin (role rank 6)',
    purpose: 'How the Platform Admin runs StudySearch day to day: the approvals only you can give, the budgets and models you own, and the checks that keep automatic admission trustworthy.',
    owns: ['Admitting university adapters (Layer 2 › Adapters)', 'Approving central pages: fee schedules, English policies, academic calendars', 'AI models, their order, AI admission and the AI allowances', 'Firecrawl and OpenRouter budgets and service keys', 'Onboarding settings, Retry and Stop', 'Users and roles; new countries; go-live'],
    schedule: [
      { when: 'Start of day (about 20 minutes)', steps: [
        step({ do: 'Coverage & completeness › Progress › Overview: read Needs attention, then pick the pilot and the top 50 and compare the hourly rows with yesterday. Open Journeys for any stage that has not moved.', page: 'coverage', tab: 'progress', why: 'One place shows how far every university has got and what holds it up.', done: 'Each item in Needs attention is fixed or noted.' }),
        step({ do: 'Read the credit and limit bar under the page title, if one shows. Red means a toolset has stopped: fix it first.', page: 'services', why: 'Firecrawl, OpenRouter, the adapter AI allowance and the scholarship scraper cap stop work when used up.', done: 'No red bar.' }),
        step({ do: 'Models & services › Firecrawl credits by university: read Today (each purpose against its share and the billed total), then tick Flagged only. For Search stopped, check the website on the Adapter builder (1.1) and press Search again with a reason; for Mostly wrong pages or No pages, note the university for its adapter or website.', page: 'services', why: 'Firecrawl may bill 15,000 credits a day; credits spent without correct pages are waste.', done: 'No university is flagged without a note, and no share was used up before the afternoon.' }),
        step({ do: 'Same card, Refused today, by university: a university held by the scholarship cap, or with Search held (an adapter check, for example Victoria University and Adelaide University), needs its adapter or website checked; then press Search again with a reason. Directory site and fewer than 30 courses are the platform keeping credits off waste, not faults.', page: 'services', why: 'Refusals show where credits would have gone; a held top-50 university is lost coverage.', done: 'No top-50 university is held without a note.' }),
        step({ do: 'Platform health › Health checks: clear every Critical; read each Warning and fix it or note why it can wait.', page: 'health', tab: 'checks', why: 'The checks run every 10 minutes over jobs, queues, budgets and the database.', done: 'No Critical open.' }),
        step({ do: 'Scheduled jobs › Automations: "Failed in the last 24 hours". Open each failed job and read its last error (Platform guide › Signal → action).', page: 'jobs', tab: 'automations', why: 'A job failing every run means its stage has stopped.', done: 'Every repeated failure is fixed, paused with a note, or raised with the platform engineer.' }),
        step({ do: 'Dashboard › Waiting for you: note universities ready to admit, onboarding stopped or needing a person, review items and scholarships to link.', page: 'dashboard', why: 'One list of everything waiting for a person.', done: 'You know today\'s queue.' }),
      ] },
      { when: 'Morning: decisions only you can make', steps: [
        step({ do: 'Layer 2 › Onboarding: with Admit automatically on, open three or four universities marked "Admitted automatically", compare a few admitted values on Courses with their pages, and switch Admit off on Layer 2 › Adapters for any that are wrong (with a reason). With it off, admit the Ready to admit fields yourself. Check the pilot and the top 50 on Coverage & completeness › Progress against yesterday.', page: 'layer2', tab: 'onboarding', why: 'Automatic admits are the control point for everything after stage 4; your spot-check keeps them honest.', done: 'Spot-check noted; wrong admits undone with a reason.' }),
        step({ do: 'Layer 2 › Onboarding › Approvals waiting (or Adapter builder 1.3 for one university): for each fee schedule, English policy and calendar, open the document, compare three or four values, then approve or reject with a reason. Proposals marked ai:gpt-4.1-mini were read by the AI; check each quoted value against the page.', page: 'layer2', tab: 'onboarding', why: 'Approval writes values to every course of that university that has none.', done: 'Approvals waiting falls; rejected ones carry a reason.' }),
        step({ do: 'Layer 2 › Onboarding › Stopped: read each row\'s reason and What to do, fix it, tick the rows and choose Retry selected.', page: 'layer2', tab: 'onboarding', why: 'A stopped university gets no adapter until someone acts.', done: 'Only rows that truly need outside help remain stopped.' }),
        step({ do: 'Scholarships › Coverage: open three or four scholarships from the latest automatic publishing; compare the value and who it is for with the page; Hold anything wrong, with a reason.', page: 'scholarships', tab: 'coverage', why: 'Publishing is automatic every hour; your spot-check is the control on it.', done: 'Spot-check recorded; holds explained.' }),
      ] },
      { when: 'Afternoon', steps: [
        step({ do: 'Layer 4 › AI could not decide: if the waiting count is large after a rule or model change, use Read the waiting pages again (with a reason) before people work through it.', page: 'layer4', tab: 'aireview', why: 'Pages are re-read on their stored copy without scraper credit.', done: 'Only pages no model can settle wait for Curators.' }),
        step({ do: 'Scheduled jobs › Task manager: anything you started is finished or still moving.', page: 'jobs', tab: 'tasks', why: 'Every background task shows here with its controls.', done: 'No task stuck for hours.' }),
      ] },
    ],
    weekly: [
      step({ do: 'Models & services › AI & OpenRouter: OpenRouter balance (read every 15 minutes) and each AI use against its daily guard (change a guard there); Models & services › Toolsets & limits: Firecrawl balance against the month and the spend by day; the adapter AI allowance (proposals and US$ a day). Top up or adjust a guard before the balance reaches the credit floor.', page: 'services' }),
      step({ do: 'Scholarships › Extraction: cost today, the model order, and any model waiting to be qualified or added. A model joins the order only after it qualifies, and only when you add it.', page: 'scholarships', tab: 'extraction' }),
      step({ do: 'Coverage & completeness: intakes, English, tuition and course links should rise week on week; a flat field means a stage is stuck.', page: 'coverage' }),
      step({ do: 'Users & roles: lowest role that does the job; expiry dates for contractors.', page: 'users' }),
      step({ do: 'Layer 2 › Onboarding: the stage counts, the pace and the estimate for the queue. Adjust "How many at once" (100 now) in Onboarding settings if credits run low or the queue is slow; queue universities not yet in onboarding when new ones appear.', page: 'layer2', tab: 'onboarding' }),
    ],
    interventions: [
      { trigger: 'Ready to admit (stage 4) or "Admitted automatically"', action: 'With Admit automatically on, spot-check and undo a wrong admit on Layer 2 › Adapters (Admit off, with a reason); with it off, admit the passing fields yourself. Enriching its courses and finding its scholarships then run by themselves.', where: 'Layer 2 › Onboarding; Layer 2 › Adapters' },
      { trigger: 'Approve central pages / Approvals waiting', action: 'Open the document, check values against it, approve or reject with a reason.', where: 'Adapter builder 1.3; Layer 2 › Onboarding › Approvals waiting' },
      { trigger: 'Needs a person (nothing passed after the AI attempts)', action: 'Open the Adapter builder: mark the values on the sample pages, add a better course page, or approve the central pages; then Retry. Admitting by hand, or approving its central pages, moves it on to Enrich courses.', where: 'Layer 2 › Adapter builder' },
      { trigger: 'OpenRouter notice: low balance, credit floor, or an AI use past its daily guard', action: 'Look at the spend by use on Models & services › OpenRouter; top up, or raise the guard if the spend is expected. With limits on Observe nothing has stopped.', where: 'Models & services › OpenRouter' },
      { trigger: 'Credit or limit bar (amber or red)', action: 'Top up the account named, or raise the allowance in Models & services; then check the stopped work resumes.', where: 'Models & services' },
      { trigger: 'A new AI model or new AI instructions', action: 'Qualify on the sample, compare scores, then make active or add to the order as a separate step with a reason. A new instructions version switches AI admission off until the models are qualified again.', where: 'Scholarships › Extraction' },
      { trigger: 'A wrong website for a provider', action: 'Enter the official website in the Adapter builder (1.1); a different website replaces the course-page search. Then Retry onboarding.', where: 'Layer 2 › Adapter builder' },
      { trigger: 'A paste file from a change (anything that drops or deletes)', action: 'Read it, run it in the Supabase SQL editor for project fxcwkweaxjtknorudmwp, check the expected counts it states.', where: 'Supabase SQL editor' },
    ],
    watch: [
      'The credit and limit bar on every page.',
      'Universities stopped or needing a person on Layer 2 › Onboarding, and how long they have waited; the pace of the queue.',
      'OpenRouter balance against the credit floor, and any AI use past its daily guard.',
      'Approvals waiting: a growing list means universities get no values from their central pages.',
      'AI could not decide: a sudden rise after a rule or model change.',
      'The same automation failing three or more runs in a row.',
      'Scholarships withdrawn by the nightly review: a jump means a rule changed or a site moved its pages.',
    ],
    escalate: ['A job that fails the same way after a fix, a worker refusing work ("invalid key", "nonce"), or data written where it should not be: pause the job, note what you saw, raise it with the platform engineer with the change-control reference (CF-247).'],
    changes: [{ version: '1.0', date: '12 Oct 2026', release: '2.15.257', change: 'First issue: daily, weekly and as-needed duties; automation and where a person decides; what to watch; escalation.' },
      { version: '1.1', date: '12 Oct 2026', release: '2.15.258', change: 'Onboarding moved to Layer 2 › Onboarding with seven journey stages (scholarships are found only after admitting and enriching); OpenRouter balance, daily guards and credit floor on Models & services (Observe); 100 universities at once.' },
      { version: '1.2', date: '12 Oct 2026', release: '2.15.259', change: 'Admit automatically (platform-wide, switched on 12 Oct 2026): the daily step becomes a spot-check of automatic admits, undone on Layer 2 › Adapters when wrong; the onboarding pilot (60 AU / 25 NZ / 15 CA) is followed on its Pilot panel.' },
      { version: '1.3', date: '12 Oct 2026', release: '2.15.260', change: 'Found course pages are read through Firecrawl; "Too few course pages" and "AI allowance used" carry on by themselves, so Retry is needed only for other stops.' },
      { version: '1.4', date: '12 Oct 2026', release: '2.15.261', change: 'Found course pages are read directly first and through Firecrawl (basic proxy) only when blocked or needing a browser; watch the Firecrawl credits used per hour on the credit bar and Models & services.' },
      { version: '1.5', date: '12 Oct 2026', release: '2.15.262', change: 'Firecrawl daily budget (15,000 a day, shared by purpose) and per-university caps; new start-of-day step to read Firecrawl credits by university and resume stopped searches; top 50 Australian providers by CRICOS courses onboarded first.' },
      { version: '1.6', date: '12 Oct 2026', release: '2.15.263', change: 'Firecrawl reads only course pages found by their CRICOS code, listed on the university\'s own site or entered by a person; a page found by a title search that needs a browser waits for its next candidate or a page entered by hand.' },
      { version: '1.7', date: '13 Oct 2026', release: '2.15.264', change: 'Models & services in three tabs; AI & OpenRouter holds the OpenRouter key, mode, floor, each AI use\'s model and daily guard, the central pages model, the scholarship AI models and the model profiles (the settings Layer 3 used to hold).' },
      { version: '1.8', date: '13 Oct 2026', release: '2.15.265', change: 'Firecrawl is never spent on directory sites; search order is top 50, Australian providers with 30+ courses, overseas, then small providers; scholarships are searched for Australian providers with 30+ courses (and overseas universities); the scholarship cap counts from when a university joined onboarding. New start-of-day check: Refused today, by university, and universities whose search is held for an adapter check. Websites are found on training.gov.au and TEQSA first.' },
      { version: '1.9', date: '13 Oct 2026', release: '2.15.266', change: 'New first step: Coverage & completeness › Progress › Overview (Needs attention, the pilot and the top 50 hour by hour). The Pilot panel on Layer 2 › Onboarding, Live activity, the Dashboard health strip, Layers and Recent activity, and Task manager › Running now are retired; Progress replaces them.' }],
  },
  {
    id: 'operator-sop', title: 'Operator SOP', version: '1.9', audience: 'Curator (rank 3), Pipeline Operator (rank 4), PIM Admin (rank 5)',
    purpose: 'How operators keep the data flowing and decide what automation cannot: the review queues, stuck or failing work, and the records that need a person. Each step names the lowest role that does it.',
    owns: ['Curator: Layer 4 Review queue, AI could not decide, Websites to find, key dates and reference links, course and provider details, ranking links', 'Pipeline Operator: Progress › Running now, failed jobs and worker errors, onboarding follow-up, scholarship links, starting jobs again', 'PIM Admin: pacing and pausing automations, the priority queue, testing adapters in the Adapter builder'],
    schedule: [
      { when: 'Start of day (about 15 minutes)', steps: [
        step({ role: 'Pipeline Operator', do: 'Coverage & completeness › Progress › Running now: note any job Failing or Paused and any Workers sending back errors; open a job to see the universities it is working on; mark errors you have dealt with as seen.', page: 'coverage', tab: 'progress', why: 'The fastest view of a stopped stage (Live activity was retired in v2.15.266).', done: 'Nothing Failing without a note.' }),
        step({ role: 'Curator', do: 'Dashboard › Waiting for you: review items, scholarships to link, onboarding stopped or needing a person, reference sites not reachable, key dates coming up.', page: 'dashboard', why: 'Today\'s queue for people.', done: 'You know what to work first.' }),
        step({ role: 'Pipeline Operator', do: 'Scheduled jobs › Automations: "Failed in the last 24 hours". Read each last error; act from Platform guide › Signal → action (for example lower "per run" by a third when a run hit the time limit).', page: 'jobs', tab: 'automations', why: 'A failing job stops its stage.', done: 'Each failure fixed, or raised with the Platform Admin.' }),
      ] },
      { when: 'Morning: review queues', steps: [
        step({ role: 'Curator', do: 'Layer 4 Review › Review queue: oldest first. Open the stored page or document, then approve, correct or reject with a reason.', page: 'layer4', tab: 'review', why: 'These are values automation would not decide: sources disagree, only an unofficial source, a fee year that does not match.', done: 'The count falls day on day.' }),
        step({ role: 'Curator', do: 'Layer 4 › AI could not decide: for each page compare every model\'s answer and quote with the stored copy; Admit the right answer, or Refuse with a reason. Your decision is kept for that page copy.', page: 'layer4', tab: 'aireview', why: 'Scholarship pages no model could prove; admitted answers still pass the hourly publishing checks.', done: 'Oldest items cleared first.' }),
        step({ role: 'Curator', do: 'Layer 4 › Websites to find: enter the official website for each university listed and Save.', page: 'layer4', tab: 'websites', why: 'Onboarding cannot start without a website; it carries on by itself once one is saved.', done: 'List shorter; nothing guessed.' }),
      ] },
      { when: 'Afternoon: follow-up', steps: [
        step({ role: 'Pipeline Operator', do: 'Layer 2 › Onboarding › Stopped: read each reason. Fix what you can (website, course pages) and tell the Platform Admin which rows need Retry, approvals or admitting. Rows at Enrich courses or Admit scholarships move on by themselves.', page: 'layer2', tab: 'onboarding', why: 'Onboarding stops for a person; it never guesses.', done: 'Each stopped row has an owner.' }),
        step({ role: 'Pipeline Operator', do: 'Scholarships to link to courses (Dashboard › Scholarships to link opens the list): on each scholarship, decide the suggested course links from the evidence.', page: 'scholarships', tab: 'list', why: 'A scholarship shows on a course only when linked.', done: 'Links decided.' }),
        step({ role: 'PIM Admin', do: 'Scheduled jobs › Priority queue and Automations: move stuck work; pace or pause what is behind or failing, with a reason.', page: 'jobs', tab: 'priority', why: 'Pacing keeps work inside credits and time limits.', done: 'Nothing waits for hours without a reason.' }),
        step({ role: 'Curator', do: 'Reference data › Key dates and Reference sources: dates coming up and sites not reachable.', page: 'reference', tab: 'dates', why: 'Key dates and sources feed the website.', done: 'Current.' }),
      ] },
    ],
    weekly: [
      step({ role: 'Pipeline Operator', do: 'Coverage & completeness: course links, English, intakes and tuition counts; a field flat for a day means its job is stuck or out of budget.', page: 'coverage' }),
      step({ role: 'Curator', do: 'Rankings & statistics: ranked universities not linked in a country we hold; link from the suggestions or mark "Not this one".', page: 'rankings' }),
      step({ role: 'PIM Admin', do: 'Layer 2 › Adapter builder: for universities needing a person, test the adapter on sample pages and mark values, so the Platform Admin can admit.', page: 'layer2', tab: 'builder' }),
      step({ role: 'Pipeline Operator', do: 'Layer 1 Register › Sources: the latest register runs completed.', page: 'layer1', tab: 'operations' }),
    ],
    interventions: [
      { trigger: 'Layer 4 Review item', action: 'Decide from the stored evidence, with a reason; correct the value if the page shows another.', where: 'Layer 4 › Review queue' },
      { trigger: 'Scholarship page in AI could not decide', action: 'Admit the right answer or Refuse with a reason; never admit a scholarship that does not say it is open to international students.', where: 'Layer 4 › AI could not decide' },
      { trigger: 'Website to find', action: 'Search the official site, confirm the university\'s name on its home page, enter and save it.', where: 'Layer 4 › Websites to find' },
      { trigger: 'Automation failing three runs in a row', action: 'Pause it with a note and raise it with the Platform Admin (Pipeline Operator and above).', where: 'Scheduled jobs › Automations' },
      { trigger: 'A value on a record is wrong', action: 'Correct it on the record: it is kept as entered by hand and automation will not overwrite it until released.', where: 'Courses or Providers record' },
      { trigger: 'An admitted value that looks wrong on a course (Admitted automatically)', action: 'Correct it on the course record (kept as entered by hand) and tell the Platform Admin the university, field and course, so the adapter can be fixed or its Admit switched off.', where: 'Courses record; Layer 2 › Onboarding' },
      { trigger: 'Onboarding stopped: no website, too few course pages', action: 'Enter the website, or add course pages in the Adapter builder (2.1); onboarding carries on or the Platform Admin retries.', where: 'Layer 2 › Onboarding; Layer 2 › Adapter builder' },
    ],
    watch: [
      'Progress › Running now: a job Failing, or a worker repeating the same error.',
      'Layer 4 waiting counts rising two days running: reviewers are behind.',
      'A coverage count flat for a day.',
      'Reference sites not reachable and key dates coming up.',
      'Values marked as estimates (savings from CRICOS cost): quote them to students as estimates.',
    ],
    escalate: ['Tell the Platform Admin about anything needing approval, admitting, budgets, models, keys, users, or a fault that repeats after your fix. Write what you saw, where, and when.'],
    changes: [{ version: '1.0', date: '12 Oct 2026', release: '2.15.257', change: 'First issue: daily routine by role, review queues, follow-up, weekly checks, interventions and escalation.' },
      { version: '1.1', date: '12 Oct 2026', release: '2.15.258', change: 'Onboarding moved to Layer 2 › Onboarding with seven journey stages; scholarships are found only after a university is admitted and its courses enriched.' },
      { version: '1.2', date: '12 Oct 2026', release: '2.15.259', change: 'Admit is automatic for the fields that pass; universities move on to enriching and scholarships by themselves. Tell the Platform Admin about any admitted value that looks wrong.' },
      { version: '1.3', date: '12 Oct 2026', release: '2.15.260', change: 'Too few course pages and AI allowance used carry on by themselves; work stopped rows with other reasons.' },
      { version: '1.4', date: '12 Oct 2026', release: '2.15.261', change: 'Found course pages are read directly first; Firecrawl only when blocked or needing a browser.' },
      { version: '1.5', date: '12 Oct 2026', release: '2.15.262', change: 'Firecrawl work now keeps to a daily budget; a purpose that used its share waits until midnight (not a fault).' },
      { version: '1.6', date: '12 Oct 2026', release: '2.15.263', change: 'A course page found by a title search is read directly only; if it needs a browser, enter the right page by hand (Adapter builder 2.1) and Firecrawl may read it.' },
      { version: '1.7', date: '13 Oct 2026', release: '2.15.264', change: 'Models & services has three tabs: Services, AI & OpenRouter, Toolsets & limits (notices and Firecrawl credits are on Toolsets & limits).' },
      { version: '1.8', date: '13 Oct 2026', release: '2.15.265', change: 'A university refused for "directory site", "fewer than 30 courses" or "scholarship cap" is expected, not a fault; Toolsets & limits › Firecrawl credits by university lists today\'s refusals by university.' },
      { version: '1.9', date: '13 Oct 2026', release: '2.15.266', change: 'Live activity is retired: the start-of-day check is Coverage & completeness › Progress › Running now (jobs by journey stage, worker errors with Mark as seen, and the universities each job works on).' }],
  },
]

// The same words as a versioned Markdown document (docs/sops/<id>.md; copied to the admin repo)
export function sopMarkdown(s, pageLabel = (p, t) => [p, t].filter(Boolean).join(' › ')) {
  const L = []
  const cell = (x) => String(x ?? '').replace(/\|/g, '\\|').replace(/\n/g, ' ')
  const where = (x) => x.page ? ` _(${pageLabel(x.page, x.tab)})_` : ''
  L.push(`# StudySearch – ${s.title}`, '', `**Version:** ${s.version} (reviewed for platform release v${SOP_REVIEWED_FOR})  `, `**Audience:** ${s.audience}  `,
    '**Change control:** CF-247  ', '**Rule:** this SOP is reviewed with every release; a change to a screen, an automation or where a person decides changes it, raises its version and is recorded below. The in-app copy is Guides › ' + s.title + '.', '', '---', '',
    '## 1. Purpose', '', s.purpose, '', '## 2. What you own', '', ...s.owns.map((o) => `- ${o}`), '',
    '## 3. How the platform automates, and where a person decides', '', '| Stage | Runs by itself | Scheduled jobs | Where a person decides |', '|---|---|---|---|',
    ...AUTOMATION.map((a) => `| ${cell(a.stage)} | ${cell(a.runs)} | ${cell(a.jobs)} | ${cell(a.person)} |`), '',
    '## 4. Rules that never change', '', ...RULES.map((r, i) => `${i + 1}. ${r}`), '', '## 5. Daily routine', '')
  for (const b of s.schedule) {
    L.push(`### ${b.when}`, '', '| # | Who | Do | Why | Done when |', '|---|---|---|---|---|')
    b.steps.forEach((x, i) => L.push(`| ${i + 1} | ${cell(x.role || 'Platform Admin')} | ${cell(x.do)}${cell(where(x))} | ${cell(x.why)} | ${cell(x.done)} |`))
    L.push('')
  }
  L.push('## 6. Weekly', '', ...s.weekly.map((x) => `- ${x.role ? `**${x.role}:** ` : ''}${x.do}${where(x)}`), '',
    '## 7. Where a person intervenes', '', '| When you see | Do | Where |', '|---|---|---|', ...s.interventions.map((x) => `| ${cell(x.trigger)} | ${cell(x.action)} | ${cell(x.where)} |`), '',
    '## 8. What to pay attention to', '', ...s.watch.map((w) => `- ${w}`), '', '## 9. Escalation', '', ...s.escalate.map((e) => `- ${e}`), '',
    '## 10. Version history', '', '| Version | Date | Release | Change |', '|---|---|---|---|', ...s.changes.map((c) => `| ${c.version} | ${c.date} | v${c.release} | ${cell(c.change)} |`), '')
  return L.join('\n')
}
