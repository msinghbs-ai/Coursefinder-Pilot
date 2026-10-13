# StudySearch – Platform Admin SOP

**Version:** 1.13 (reviewed for platform release v2.15.270)  
**Audience:** Platform Admin (role rank 6)  
**Change control:** CF-247  
**Rule:** this SOP is reviewed with every release; a change to a screen, an automation or where a person decides changes it, raises its version and is recorded below. The in-app copy is Guides › Platform Admin SOP.

---

## 1. Purpose

How the Platform Admin runs StudySearch day to day: the approvals only you can give, the budgets and models you own, and the checks that keep automatic admission trustworthy.

## 2. What you own

- Admitting university adapters (Layer 2 › Adapters)
- Approving central pages: fee schedules, English policies, academic calendars
- AI models, their order, AI admission and the AI allowances
- Firecrawl and OpenRouter budgets and service keys
- Onboarding settings, Retry and Stop
- Users and roles; new countries; go-live

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

### Start of day (about 20 minutes)

| # | Who | Do | Why | Done when |
|---|---|---|---|---|
| 1 | Platform Admin | Coverage & completeness › Progress › Overview: read Needs attention, then pick the pilot and the top 50 and compare the hourly rows with yesterday. Open Journeys for any stage that has not moved. _(Coverage & completeness › Progress)_ | One place shows how far every university has got and what holds it up. | Each item in Needs attention is fixed or noted. |
| 2 | Platform Admin | Read the credit and limit bar under the page title, if one shows. Red means a toolset has stopped: fix it first. _(Models & services)_ | Firecrawl, OpenRouter, the adapter AI allowance and the scholarship scraper cap stop work when used up. | No red bar. |
| 3 | Platform Admin | Models & services › Firecrawl credits by university: read Today (each purpose against its share and the billed total), then tick Flagged only. For Search stopped, check the website on the Adapter builder (1.1) and press Search again with a reason; for Mostly wrong pages or No pages, note the university for its adapter or website. _(Models & services)_ | Firecrawl may bill 15,000 credits a day; credits spent without correct pages are waste. | No university is flagged without a note, and no share was used up before the afternoon. |
| 4 | Platform Admin | Same card, Refused today, by university: a university held by the scholarship cap, or with Search held (an adapter check, for example Victoria University and Adelaide University), needs its adapter or website checked; then press Search again with a reason. Directory site and fewer than 30 courses are the platform keeping credits off waste, not faults. _(Models & services)_ | Refusals show where credits would have gone; a held top-50 university is lost coverage. | No top-50 university is held without a note. |
| 5 | Platform Admin | Platform health › Health checks: clear every Critical; read each Warning and fix it or note why it can wait. _(Platform health › Health checks)_ | The checks run every 10 minutes over jobs, queues, budgets and the database. | No Critical open. |
| 6 | Platform Admin | Scheduled jobs › Automations: "Failed in the last 24 hours". Open each failed job and read its last error (Platform guide › Signal → action). _(Scheduled jobs › Automations)_ | A job failing every run means its stage has stopped. | Every repeated failure is fixed, paused with a note, or raised with the platform engineer. |
| 7 | Platform Admin | Dashboard › Waiting for you: note universities ready to admit, onboarding stopped or needing a person, review items and scholarships to link. _(Dashboard)_ | One list of everything waiting for a person. | You know today's queue. |

### Morning: decisions only you can make

| # | Who | Do | Why | Done when |
|---|---|---|---|---|
| 1 | Platform Admin | Layer 2 › Onboarding: with Admit automatically on, open three or four universities marked "Admitted automatically", compare a few admitted values on Courses with their pages, and switch Admit off on Layer 2 › Adapters for any that are wrong (with a reason). With it off, admit the Ready to admit fields yourself. Check the pilot and the top 50 on Coverage & completeness › Progress against yesterday. _(Layer 2 Discovery & reading › Onboarding)_ | Automatic admits are the control point for everything after stage 4; your spot-check keeps them honest. | Spot-check noted; wrong admits undone with a reason. |
| 2 | Platform Admin | Layer 2 › Onboarding › Approvals waiting (or Adapter builder 1.3 for one university): for each fee schedule, English policy and calendar, open the document, compare three or four values, then approve or reject with a reason. Proposals marked ai:gpt-4.1-mini were read by the AI; check each quoted value against the page. _(Layer 2 Discovery & reading › Onboarding)_ | Approval writes values to every course of that university that has none. | Approvals waiting falls; rejected ones carry a reason. |
| 3 | Platform Admin | Layer 2 › Onboarding › Stopped: read each row's reason and What to do, fix it, tick the rows and choose Retry selected. _(Layer 2 Discovery & reading › Onboarding)_ | A stopped university gets no adapter until someone acts. | Only rows that truly need outside help remain stopped. |
| 4 | Platform Admin | Scholarships › Coverage: open three or four scholarships from the latest automatic publishing; compare the value and who it is for with the page; Hold anything wrong, with a reason. _(Scholarships › Coverage)_ | Publishing is automatic every hour; your spot-check is the control on it. | Spot-check recorded; holds explained. |

### Afternoon

| # | Who | Do | Why | Done when |
|---|---|---|---|---|
| 1 | Platform Admin | Layer 4 › AI could not decide: if the waiting count is large after a rule or model change, use Read the waiting pages again (with a reason) before people work through it. _(Layer 4 Review › AI could not decide)_ | Pages are re-read on their stored copy without scraper credit. | Only pages no model can settle wait for Curators. |
| 2 | Platform Admin | Scheduled jobs › Task manager: anything you started is finished or still moving. _(Scheduled jobs › Task manager)_ | Every background task shows here with its controls. | No task stuck for hours. |

## 6. Weekly

- Models & services › AI & OpenRouter: OpenRouter balance (read every 15 minutes) and each AI use against its daily guard (change a guard there); Models & services › Toolsets & limits: Firecrawl balance against the month and the spend by day; the adapter AI allowance (proposals and US$ a day). Top up or adjust a guard before the balance reaches the credit floor. _(Models & services)_
- Scholarships › Extraction: cost today, the model order, and any model waiting to be qualified or added. A model joins the order only after it qualifies, and only when you add it. _(Scholarships › Extraction)_
- Coverage & completeness: intakes, English, tuition and course links should rise week on week; a flat field means a stage is stuck. _(Coverage & completeness)_
- Users & roles: lowest role that does the job; expiry dates for contractors. _(Users & roles)_
- Layer 2 › Onboarding: the stage counts, the pace and the estimate for the queue. Adjust "How many at once" (100 now) in Onboarding settings if credits run low or the queue is slow; queue universities not yet in onboarding when new ones appear. _(Layer 2 Discovery & reading › Onboarding)_

## 7. Where a person intervenes

| When you see | Do | Where |
|---|---|---|
| Ready to admit (stage 4) or "Admitted automatically" | With Admit automatically on, spot-check and undo a wrong admit on Layer 2 › Adapters (Admit off, with a reason); with it off, admit the passing fields yourself. Enriching its courses and finding its scholarships then run by themselves. | Layer 2 › Onboarding; Layer 2 › Adapters |
| Approve central pages / Approvals waiting | Open the document, check values against it, approve or reject with a reason. | Adapter builder 1.3; Layer 2 › Onboarding › Approvals waiting |
| Needs a person (nothing passed after the AI attempts) | Open the Adapter builder: mark the values on the sample pages, add a better course page, or approve the central pages; then Retry. Admitting by hand, or approving its central pages, moves it on to Enrich courses. | Layer 2 › Adapter builder |
| A notice on a layer page marked Action needed or Optional | Do the one thing it says: press Go to for the exact card or setting, or act inside the notice (Search again for a held or stopped course search; enter a website for a provider with none). Notices marked Nothing to do are on Toolsets and limits and clear by themselves. | The layer page; Models & services › Toolsets & limits |
| OpenRouter notice: low balance, credit floor, or an AI use past its daily guard | Look at the spend by use on Models & services › OpenRouter; top up, or raise the guard if the spend is expected. With limits on Observe nothing has stopped. | Models & services › OpenRouter |
| Credit or limit bar (amber or red) | Top up the account named, or raise the allowance in Models & services; then check the stopped work resumes. | Models & services |
| A new AI model or new AI instructions | Qualify on the sample, compare scores, then make active or add to the order as a separate step with a reason. A new instructions version switches AI admission off until the models are qualified again. | Scholarships › Extraction |
| A wrong website for a provider | Enter the official website in the Adapter builder (1.1); a different website replaces the course-page search. Then Retry onboarding. | Layer 2 › Adapter builder |
| A paste file from a change (anything that drops or deletes) | Read it, run it in the Supabase SQL editor for project fxcwkweaxjtknorudmwp, check the expected counts it states. | Supabase SQL editor |

## 8. What to pay attention to

- The credit and limit bar on every page.
- Universities stopped or needing a person on Layer 2 › Onboarding, and how long they have waited; the pace of the queue.
- OpenRouter balance against the credit floor, and any AI use past its daily guard.
- Approvals waiting: a growing list means universities get no values from their central pages.
- AI could not decide: a sudden rise after a rule or model change.
- The same automation failing three or more runs in a row.
- Scholarships withdrawn by the nightly review: a jump means a rule changed or a site moved its pages.

## 9. Escalation

- A job that fails the same way after a fix, a worker refusing work ("invalid key", "nonce"), or data written where it should not be: pause the job, note what you saw, raise it with the platform engineer with the change-control reference (CF-247).

## 10. Version history

| Version | Date | Release | Change |
|---|---|---|---|
| 1.0 | 12 Oct 2026 | v2.15.257 | First issue: daily, weekly and as-needed duties; automation and where a person decides; what to watch; escalation. |
| 1.1 | 12 Oct 2026 | v2.15.258 | Onboarding moved to Layer 2 › Onboarding with seven journey stages (scholarships are found only after admitting and enriching); OpenRouter balance, daily guards and credit floor on Models & services (Observe); 100 universities at once. |
| 1.2 | 12 Oct 2026 | v2.15.259 | Admit automatically (platform-wide, switched on 12 Oct 2026): the daily step becomes a spot-check of automatic admits, undone on Layer 2 › Adapters when wrong; the onboarding pilot (60 AU / 25 NZ / 15 CA) is followed on its Pilot panel. |
| 1.3 | 12 Oct 2026 | v2.15.260 | Found course pages are read through Firecrawl; "Too few course pages" and "AI allowance used" carry on by themselves, so Retry is needed only for other stops. |
| 1.4 | 12 Oct 2026 | v2.15.261 | Found course pages are read directly first and through Firecrawl (basic proxy) only when blocked or needing a browser; watch the Firecrawl credits used per hour on the credit bar and Models & services. |
| 1.5 | 12 Oct 2026 | v2.15.262 | Firecrawl daily budget (15,000 a day, shared by purpose) and per-university caps; new start-of-day step to read Firecrawl credits by university and resume stopped searches; top 50 Australian providers by CRICOS courses onboarded first. |
| 1.6 | 12 Oct 2026 | v2.15.263 | Firecrawl reads only course pages found by their CRICOS code, listed on the university's own site or entered by a person; a page found by a title search that needs a browser waits for its next candidate or a page entered by hand. |
| 1.7 | 13 Oct 2026 | v2.15.264 | Models & services in three tabs; AI & OpenRouter holds the OpenRouter key, mode, floor, each AI use's model and daily guard, the central pages model, the scholarship AI models and the model profiles (the settings Layer 3 used to hold). |
| 1.8 | 13 Oct 2026 | v2.15.265 | Firecrawl is never spent on directory sites; search order is top 50, Australian providers with 30+ courses, overseas, then small providers; scholarships are searched for Australian providers with 30+ courses (and overseas universities); the scholarship cap counts from when a university joined onboarding. New start-of-day check: Refused today, by university, and universities whose search is held for an adapter check. Websites are found on training.gov.au and TEQSA first. |
| 1.9 | 13 Oct 2026 | v2.15.266 | New first step: Coverage & completeness › Progress › Overview (Needs attention, the pilot and the top 50 hour by hour). The Pilot panel on Layer 2 › Onboarding, Live activity, the Dashboard health strip, Layers and Recent activity, and Task manager › Running now are retired; Progress replaces them. |
| 1.10 | 13 Oct 2026 | v2.15.267 | Progress › Journeys: filter by what holds a university up (needs a person, course pages, scholarship credits, search stopped, AI reading) or tick Only held up; the Next step button opens the university's steps and its run-on-demand actions (Find scholarships now, read the scholarship pages with AI again, read course pages again, Qualify adapter, Retry, Search again). |
| 1.11 | 13 Oct 2026 | v2.15.268 | Notices on the layer pages show only what needs a person and say so (Action needed, Action outside StudySearch, Optional); Go to opens the exact card or setting; held or stopped course searches are released with Search again, and a missing website entered, inside the notice. Information-only notices (for example a daily share used up, which carries on after midnight) are on Toolsets and limits. |
| 1.12 | 13 Oct 2026 | v2.15.269 | Every job size, re-read and retry time and onboarding rule is a setting on Settings › Pipeline settings (with what uses it); the Firecrawl proxy, site map sizes and search result counts are on Toolsets › Firecrawl; capacity, evidence storage, retention and provider fee rule policies are changed on Pipeline settings. Each change needs a reason and is logged. The controls check on Pipeline settings should always show that every running job reads its sizes from settings. |
| 1.13 | 14 Oct 2026 | v2.15.270 | Filters work for every country in the catalogue: Courses › Region (NZ) and Province / territory (Canada) list regions (a course without a campus region takes its university's region); Delivery reads the course's own mode; an empty filter says why; Data Quality, Key dates, Regulatory sources and the fee currency include Canada. |
