# StudySearch – Operator SOP

**Version:** 1.37 (reviewed for platform release v2.15.296)  
**Audience:** Curator (rank 3), Pipeline Operator (rank 4), PIM Admin (rank 5)  
**Change control:** CF-247  
**Rule:** this SOP is reviewed with every release; a change to a screen, an automation or where a person decides changes it, raises its version and is recorded below. The in-app copy is Guides › Operator SOP.

---

## 1. Purpose

How operators keep the data flowing and decide what automation cannot: the review queues, stuck or failing work, and the records that need a person. Each step names the lowest role that does it.

## 2. What you own

- Curator: Layer 4 Review queue, AI could not decide, Websites to find, key dates and reference links, course and provider details, ranking links
- Pipeline Operator: Progress › Running now, failed jobs and worker errors, onboarding follow-up, scholarship links, starting jobs again
- PIM Admin: pacing and pausing automations, the priority queue, testing adapters in the Adapter builder

## 3. How the platform automates, and where a person decides

| Stage | Runs by itself | Scheduled jobs | Where a person decides |
|---|---|---|---|
| 1. Provider in | A university enters the platform from a Layer 1 register (CRICOS, NZQA, Canadian lists, refreshed on their schedule), another database import, or our own search. Every active university with courses and no admitting adapter is queued for onboarding; new ones start by themselves. | Register refresh scheduler (hourly), Register run driver, Register auto-ingest, Onboard universities | Nothing day to day. A Platform Admin adds a country or a new register, and can queue universities not yet in onboarding (Layer 2 › Onboarding). |
| 2. Prepare | Each university's website is found and verified, its contacts and central pages found, its site mapped, and each course's own page found by Firecrawl search (CRICOS code, then title) and read as evidence: directly first, through Firecrawl only when blocked or the page needs a browser (v2.15.261, to save credits). Up to 100 universities are worked at once, every minute. A university whose pages cannot be found moves aside after an hour without a page read, so the next one starts, and carries on by itself when its pages are read. | Onboard universities, Find provider websites, Discover course pages, Search for course pages, Read course pages, Match pages to courses | A website the finder could not verify (Layer 4 › Websites to find); a wrong website; course pages added by hand when none can be found. |
| 3. Create adapter | The pinned AI proposes the adapter from sample pages (twice more if nothing passes); it is saved in testing, applied to every stored page and qualified field by field. Central pages are suggested; when nothing passes, the AI reads the university's English policy and calendar pages for a person to approve. Nothing is admitted by the test. | Onboard universities, Task manager tasks, Read central pages with AI | Universities where nothing passes show "Needs a person" on Layer 2 › Onboarding. |
| 4. Admit | With Admit automatically switched on (since 12 Oct 2026, v2.15.259), the fields that pass the admit rule are admitted by themselves within 10 minutes and logged; otherwise onboarding waits. Fee schedules, English policies and academic calendars are turned into proposals (rule parser, and for policies and calendars a pinned AI model quoting every value). Nothing is written before a person decides. | Find and read fee schedules, English policies and calendars; Find central pages | A Platform Admin spot-checks automatic admits (or admits by hand while the switch is off), undoes a wrong one on Layer 2 › Adapters, and approves or rejects central pages (Adapter builder 1.3, or Layer 2 › Onboarding › Approvals waiting). Universities where nothing passed need a person. |
| 5. Enrich courses | Once admitted, the adapter is applied to the stored pages and writes its values to the courses (intakes, English, fees, delivery), with approved central pages filling courses that have none; admitted adapters and approved rules keep writing every 10 minutes. A value entered by hand is never overwritten. Values sources disagree on go to review. | Adapter values replace older ones, Admit intakes from course pages, Apply approved English policies, Apply provider fee profiles, Review rules (nightly) | Curators decide the Layer 4 Review queue, oldest first. |
| 6. Scholarship adapter | Only after its courses are enriched is the university's scholarship search started: its site mapped, scholarship pages screened and read through the scraper. | Onboard universities (Scholarship search task), Discover scholarships | Nothing day to day. |
| 7. Admit scholarships | Pinned AI models read each scholarship page in order (Qwen3 30B, then GPT-4.1 mini); every fact must be quoted from the page. Passing scholarships are published every hour; a nightly review withdraws any that stop passing. Onboarding is Done when no page waits for the AI or a person (or after 7 days). | Read scholarship pages with AI, Publish scholarships automatically (hourly), Nightly publication review | Curators decide pages no model could settle (Layer 4 › AI could not decide); a Platform Admin spot-checks the automatic publishing and holds anything wrong. |
| Delivery | Search, the website API, Wix and Zoho are refreshed for every changed course and scholarship. | Refresh search for changed courses, Course scholarship attribute, Rebuild API reference data | Nothing, unless a delivery job fails. |

## 4. Rules that never change

1. A value entered by hand is never overwritten by automation. Release it on the record to let automation update it again.
2. A passing test switches nothing on by itself. Approving a central page, activating an AI model or adding it to the order is a separate step a person takes, with a reason. Admitting an adapter's passing fields is automatic only while a Platform Admin has switched on Admit automatically (Layer 2 › Onboarding settings, with a reason); a field that did not pass is never admitted.
3. AI models are pinned and qualified for each task; nothing routes to an untested model. An AI answer counts only where its quote is on the stored page.
4. AI spending is watched, not capped, while OpenRouter limits are set to Observe: Models & services › OpenRouter shows the balance, today's spend for each AI use against its daily guard and the credit floor, and a notice appears when one is passed. Nothing stops until a Platform Admin switches the limits to stop.
5. Every background job is a scheduled job in the automation catalogue or a task in Task manager, with its controls. Something running that you cannot see there is a fault: report it.
6. Work oldest first, give a reason for every decision, and never decide from memory: open the stored page or document.

## 5. Daily routine

### Start of day (about 15 minutes)

| # | Who | Do | Why | Done when |
|---|---|---|---|---|
| 1 | Pipeline Operator | Coverage & completeness › Progress › Running now: note any job Failing or Paused and any Workers sending back errors; open a job to see the universities it is working on; mark errors you have dealt with as seen. _(Coverage & completeness › Progress)_ | The fastest view of a stopped stage (Live activity was retired in v2.15.266). | Nothing Failing without a note. |
| 2 | Curator | Dashboard › Waiting for you: review items, scholarships to link, onboarding stopped or needing a person, reference sites not reachable, key dates coming up. _(Dashboard)_ | Today's queue for people. | You know what to work first. |
| 3 | Pipeline Operator | Scheduled jobs › Automations: "Failed in the last 24 hours". Read each last error; act from Platform guide › Signal → action (for example lower "per run" by a third when a run hit the time limit). _(Scheduled jobs › Automations)_ | A failing job stops its stage. | Each failure fixed, or raised with the Platform Admin. |

### Morning: review queues

| # | Who | Do | Why | Done when |
|---|---|---|---|---|
| 1 | Curator | Layer 4 Review › Review queue: oldest first. Open the stored page or document, then approve, correct or reject with a reason. _(Layer 4 Review › Review queue)_ | These are values automation would not decide: sources disagree, only an unofficial source, a fee year that does not match. | The count falls day on day. |
| 2 | Curator | Layer 4 › AI could not decide: for each page compare every model's answer and quote with the stored copy; Admit the right answer, or Refuse with a reason. Your decision is kept for that page copy. _(Layer 4 Review › AI could not decide)_ | Scholarship pages no model could prove; admitted answers still pass the hourly publishing checks. | Oldest items cleared first. |
| 3 | Curator | Layer 4 › Websites to find: enter the official website for each university listed and Save. _(Layer 4 Review › Websites to find)_ | Onboarding cannot start without a website; it carries on by itself once one is saved. | List shorter; nothing guessed. |
| 4 | Pipeline Operator | Coverage & completeness › Counsellor reports: oldest first. Check what the counsellor reported against the source link or the provider's page; correct the value where it is held, then close the report as Fixed, or Not changed with the reason. Zoho shows the outcome to the counsellor. _(Coverage & completeness › Counsellor reports)_ | Counsellors in Zoho Creator and CRM see the data with students and report missing or wrong values on courses, institutes, campuses and contacts. | No report older than two working days. |

### Afternoon: follow-up

| # | Who | Do | Why | Done when |
|---|---|---|---|---|
| 1 | Pipeline Operator | Layer 2 › Onboarding › Stopped: read each reason. Fix what you can (website, course pages) and tell the Platform Admin which rows need Retry, approvals or admitting. Rows at Enrich courses or Admit scholarships move on by themselves. _(Layer 2 Discovery & reading › Onboarding)_ | Onboarding stops for a person; it never guesses. | Each stopped row has an owner. |
| 2 | Pipeline Operator | Scholarships to link to courses (Dashboard › Scholarships to link opens the list): on each scholarship, decide the suggested course links from the evidence. _(Scholarships › Scholarships)_ | A scholarship shows on a course only when linked. | Links decided. |
| 3 | PIM Admin | Scheduled jobs › Priority queue and Automations: move stuck work; pace or pause what is behind or failing, with a reason. _(Scheduled jobs › Priority queue)_ | Pacing keeps work inside credits and time limits. | Nothing waits for hours without a reason. |
| 4 | Curator | Reference data › Key dates and Reference sources: dates coming up and sites not reachable. _(Reference data › Key dates)_ | Key dates and sources feed the website. | Current. |

## 6. Weekly

- **Pipeline Operator:** Coverage & completeness: course links, English, intakes and tuition counts; a field flat for a day means its job is stuck or out of budget. _(Coverage & completeness)_
- **Curator:** Rankings & statistics: ranked universities not linked in a country we hold; link from the suggestions or mark "Not this one". _(Rankings & statistics)_
- **PIM Admin:** Layer 2 › Adapter builder: for universities needing a person, test the adapter on sample pages and mark values, so the Platform Admin can admit. _(Layer 2 Discovery & reading › Adapter builder)_
- **Pipeline Operator:** Layer 1 Register › Sources: the latest register runs completed. _(Layer 1 Register › Sources)_

## 7. Where a person intervenes

| When you see | Do | Where |
|---|---|---|
| Layer 4 Review item | Decide from the stored evidence, with a reason; correct the value if the page shows another. | Layer 4 › Review queue |
| Scholarship page in AI could not decide | Admit the right answer or Refuse with a reason; never admit a scholarship that does not say it is open to international students. | Layer 4 › AI could not decide |
| Website to find | Search the official site, confirm the university's name on its home page, enter and save it. | Layer 4 › Websites to find |
| Automation failing three runs in a row | Pause it with a note and raise it with the Platform Admin (Pipeline Operator and above). | Scheduled jobs › Automations |
| A value on a record is wrong | Correct it on the record: it is kept as entered by hand and automation will not overwrite it until released. | Courses or Providers record |
| An admitted value that looks wrong on a course (Admitted automatically) | Correct it on the course record (kept as entered by hand) and tell the Platform Admin the university, field and course, so the adapter can be fixed or its Admit switched off. | Courses record; Layer 2 › Onboarding |
| Onboarding stopped: no website, too few course pages | Enter the website, or add course pages in the Adapter builder (2.1); onboarding carries on or the Platform Admin retries. | Layer 2 › Onboarding; Layer 2 › Adapter builder |

## 8. What to pay attention to

- Progress › Running now: a job Failing, or a worker repeating the same error.
- Layer 4 waiting counts rising two days running: reviewers are behind.
- A coverage count flat for a day.
- Reference sites not reachable and key dates coming up.
- Values marked as estimates (savings from CRICOS cost): quote them to students as estimates.

## 9. Escalation

- Tell the Platform Admin about anything needing approval, admitting, budgets, models, keys, users, or a fault that repeats after your fix. Write what you saw, where, and when.

## 10. Version history

| Version | Date | Release | Change |
|---|---|---|---|
| 1.0 | 12 Oct 2026 | v2.15.257 | First issue: daily routine by role, review queues, follow-up, weekly checks, interventions and escalation. |
| 1.1 | 12 Oct 2026 | v2.15.258 | Onboarding moved to Layer 2 › Onboarding with seven journey stages; scholarships are found only after a university is admitted and its courses enriched. |
| 1.2 | 12 Oct 2026 | v2.15.259 | Admit is automatic for the fields that pass; universities move on to enriching and scholarships by themselves. Tell the Platform Admin about any admitted value that looks wrong. |
| 1.3 | 12 Oct 2026 | v2.15.260 | Too few course pages and AI allowance used carry on by themselves; work stopped rows with other reasons. |
| 1.4 | 12 Oct 2026 | v2.15.261 | Found course pages are read directly first; Firecrawl only when blocked or needing a browser. |
| 1.5 | 12 Oct 2026 | v2.15.262 | Firecrawl work now keeps to a daily budget; a purpose that used its share waits until midnight (not a fault). |
| 1.6 | 12 Oct 2026 | v2.15.263 | A course page found by a title search is read directly only; if it needs a browser, enter the right page by hand (Adapter builder 2.1) and Firecrawl may read it. |
| 1.7 | 13 Oct 2026 | v2.15.264 | Models & services has three tabs: Services, AI & OpenRouter, Toolsets & limits (notices and Firecrawl credits are on Toolsets & limits). |
| 1.8 | 13 Oct 2026 | v2.15.265 | A university refused for "directory site", "fewer than 30 courses" or "scholarship cap" is expected, not a fault; Toolsets & limits › Firecrawl credits by university lists today's refusals by university. |
| 1.9 | 13 Oct 2026 | v2.15.266 | Live activity is retired: the start-of-day check is Coverage & completeness › Progress › Running now (jobs by journey stage, worker errors with Mark as seen, and the universities each job works on). |
| 1.10 | 13 Oct 2026 | v2.15.267 | Running now shows schedules in words; a job that touched no particular university in the last hour lists the universities now at its stage. |
| 1.11 | 13 Oct 2026 | v2.15.268 | Notices on the layer pages show only what needs a person and say so (Action needed, Action outside StudySearch, Optional); Go to opens the exact card or setting; held or stopped course searches are released with Search again, and a missing website entered, inside the notice. Information-only notices (for example a daily share used up, which carries on after midnight) are on Toolsets and limits. |
| 1.12 | 13 Oct 2026 | v2.15.269 | Every job size, re-read and retry time and onboarding rule is a setting on Settings › Pipeline settings (with what uses it); the Firecrawl proxy, site map sizes and search result counts are on Toolsets › Firecrawl; capacity, evidence storage, retention and provider fee rule policies are changed on Pipeline settings. Each change needs a reason and is logged. The controls check on Pipeline settings should always show that every running job reads its sizes from settings. |
| 1.13 | 14 Oct 2026 | v2.15.270 | Filters work for every country in the catalogue: Courses › Region (NZ) and Province / territory (Canada) list regions (a course without a campus region takes its university's region); Delivery reads the course's own mode; an empty filter says why; Data Quality, Key dates, Regulatory sources and the fee currency include Canada. |
| 1.14 | 14 Oct 2026 | v2.15.271 | Courses with no code printed by the university or regulator show a StudySearch code (university, level, number, marked SS), and search finds it. Providers show a Scholarship search flag: Off automatically when the only website known is a directory site; a Pipeline Operator turns it on in the provider panel with the provider's own website and a reason. |
| 1.15 | 14 Oct 2026 | v2.15.273 | Layer 2 › Enrich fields: choose countries or universities and fields (campus, duration, level, delivery, field of study, international, provider address), preview what is missing, and start a task with a reason (Pipeline Operator and above). It fills only missing values from stored pages, rules and AI, and from a new read only when allowed; results show each value with the words it was read from. Field sources (which sources fill a field, per country) are changed there by a Platform Admin. |
| 1.16 | 14 Oct 2026 | v2.15.275 | Layer 2 › Enrich fields › Coverage and telemetry: the share of active courses with each field by country, how it moved since the first snapshot and in the last 24 hours, what the job did (settled, filled, AI calls and failures, AI spend, scraper credits) and the limits in force with where each is changed. How much page text the AI reads and titles per AI call are settings on Pipeline settings. |
| 1.17 | 14 Oct 2026 | v2.15.276 | Providers show a Type column: the institution type set by the register rules (TEQSA National Register, CRICOS institution type, NZQA organisation type and the provider's courses), or Needs type with the reason no rule matched. PIM Admin and above can set a type by hand (it is kept) or return it to Auto, with no reason asked. Settings › Pipeline settings › Institution type rules: the Platform Admin changes a rule's type, order or switch and runs the rules. Two new Layer 1 sources (TEQSA National Register, CRICOS Institutions) are read through data.gov.au. |
| 1.18 | 14 Oct 2026 | v2.15.277 | Settings › Pipeline settings › Website API: whether rankings and logos may be displayed on the website (Yes or No, changed with a reason), how long a logo link given to the website lasts (365 days), how soon before it ends a logo is sent again, and the most items in one sync reply. The website can now load everything once and then ask only for what changed (the sync action); the job website-sync-check (Search and API) looks for changes every minute. |
| 1.19 | 15 Oct 2026 | v2.15.278 | Settings › Pipeline settings › Waste rules: a job that produces nothing pauses itself and switches on again when work arrives; the admit jobs run when new input arrives; AI course-page matching stops after the attempts that still find pages; a value two automatic jobs keep changing is frozen for review; a stored scholarship page is not read again; course-page search runs only for the top Australian providers by gaps. What is stopped is recorded and flagged; paused jobs and frozen values show as notices. |
| 1.20 | 15 Oct 2026 | v2.15.279 | Settings › Pipeline settings › Admission checks: an adapter fee is admitted only when it is within the set share of the CRICOS registered course total (others are held back and flagged); AI readings of the top providers' English policies and academic calendars are approved automatically when every value is quoted on the page and course pages do not mostly disagree (others wait for a person, as before). Double degrees whose parts are at the same level take that level's English default; research degrees take a research default only where the policy states one. |
| 1.21 | 15 Oct 2026 | v2.15.280 | Housekeeping (Decision 260): every job, table, view, edge function and screen is in the component register with its layer, purpose and status. A weekly hygiene check lists what is unused, insecure, unregistered or ready to drop, and shows as a notice. Settings › Pipeline settings › Housekeeping sets when something counts as unused (14 days) and how long a retired component is kept (14 days). |
| 1.22 | 15 Oct 2026 | v2.15.281 | Logos: click a provider's logo (provider panel, providers list, Logos list) to upload one, give an image address, or ask the logo finder to look on the provider's website. The logo finder (job logo-find, every 10 minutes) also works through providers with no logo and attaches the logo from their own home page; it never replaces a logo a person added, and a provider with no logo found is flagged and tried again after 30 days. Settings › Pipeline settings › Logos sets who may change logos (Platform Admin), the run size, the retry wait and the smallest logo accepted. |
| 1.23 | 15 Oct 2026 | v2.15.282 | Flags: work that keeps failing is held instead of tried again (Coverage & completeness › Flags). Providers whose website does not answer, course fields whose page gives no value (after 2 tries; a second try only on new input), central pages not yet due, and worker jobs that run empty are held. Each is released automatically when its input changes, its website answers a free check (3, 7, 14, then 30 days) or its date comes, and goes back in its queue. A Platform Admin can release or hold any item with a reason; every change is kept in its history with the evidence. Settings › Pipeline settings › Flags. |
| 1.24 | 16 Oct 2026 | v2.15.283 | Operations › API usage: statistics for Zoho API v2 and Website API v2 (calls, success and failure, last call, bandwidth, reply sizes, full loads and deltas), refreshed daily or with Refresh statistics now; the Platform Admin rotates a key (shown once; the old key works for the overlap), ends an old key early, or switches a key off and on. |
| 1.25 | 16 Oct 2026 | v2.15.284 | Users & roles: Delete (Platform Admin; never a Platform Admin, your own account or the system account; type the email to confirm). Platform health: held work is shown apart from stalls; scholarship pages asked to be read again are no longer held by the per-university cap. |
| 1.26 | 16 Oct 2026 | v2.15.285 | Scheduled jobs › Task manager shows Background jobs again (every scheduled job and worker using the platform, with Pause, Resume and Run now) under the tasks people start. |
| 1.27 | 16 Oct 2026 | v2.15.286 | Settings › Storage & retention starts with Storage sizes: database, schema, table and bucket sizes recorded daily, with Measure now for the Platform Admin. |
| 1.28 | 18 Oct 2026 | v2.15.287 | Layer 2 › Build adapter: universities with the readiness of eight fields (Ready, Review, Not ready) and what they would add; a university's page admits its Ready fields with one click (Platform Admin, with a reason); build selected universities into a wave. An unused settings screen and seven unused worker modes retired. |
| 1.29 | 18 Oct 2026 | v2.15.288 | Adapter builder 1.1 Website: Check website (reads the home page now: answers, not a third-party site, CRICOS code or name on it, or the register-listed site; Verified, Likely or Failed) and Change website (Platform Admin; checked first, saved only when Verified or Likely; searches, contacts and central pages start again; a second site is kept as an extra source). |
| 1.30 | 18 Oct 2026 | v2.15.289 | Adapter builder: follow the guide at the top. It shows each step (Done, Running by itself, Your turn, Optional, Later) and the one next thing to press, with Go to step. Contacts, central pages and course-page search run by themselves after a website change; nothing to press while they run. |
| 1.31 | 18 Oct 2026 | v2.15.290 | Course-page searches you ask for (Find course pages, a website change) run for any university and go first. The Adapter builder guide shows them as running only when they will run, and otherwise says why. |
| 1.32 | 19 Oct 2026 | v2.15.291 | Reviewed, no steps changed: the version pill, release notes, Rankings & statistics cards and the Evidence acquisition box are now drawn with the page instead of added after it. They look and work as before; the QS and THE cards show one edition picker. |
| 1.33 | 19 Oct 2026 | v2.15.292 | Coverage & completeness › Counsellor reports: reports from counsellors in Zoho on a course, institute, campus or contact (missing, wrong or out of date, with a suggested value and source link). Close each as Fixed or Not changed with a reason; Zoho shows the outcome. Operator SOP: a morning step to work the reports. |
| 1.34 | 19 Oct 2026 | v2.15.293 | Reviewed, no steps changed: the Evidence panel shows one screen: the course, the page address and when it was read, whether it was accepted as the course's page and is in use now, the values it supplied, and its earlier and later copies. View page and Download as before; the hash, file and job are under Technical details. |
| 1.35 | 19 Oct 2026 | v2.15.294 | Reviewed, no steps changed: Evidence rows say what they are (copy 1 of 2, in use, older copy whose values are in use, provider facts page, register file). View page opens the saved page in StudySearch; Download saves an ordinary .html or .md file. |
| 1.36 | 19 Oct 2026 | v2.15.295 | Reviewed, no steps changed: Live activity shows Pages kept once today. In Layer 4 › AI could not decide each held scholarship shows the AI re-check and its recommendation; the person still admits or refuses. |
| 1.37 | 20 Oct 2026 | v2.15.296 | Reviewed, no steps changed: Flags has a new reason, Course pages not found, which keeps a university out of page search and Build adapter. A Pipeline Operator or above may release it with a reason once a website or page list is fixed; onboarding then starts again. |
