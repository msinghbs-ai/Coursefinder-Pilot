# StudySearch – Platform Admin SOP

**Version:** 1.0 (reviewed for platform release v2.15.257)  
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
| 1. Register | Layer 1 refreshes the official provider and course registers (CRICOS, NZQA, Canadian lists) on their schedule; new providers start onboarding by themselves. | Register refresh scheduler (hourly), Register run driver, Register auto-ingest | Nothing day to day. A Platform Admin adds a country or a new register. |
| 2. Website and course pages | Each provider's website is found and verified, its site mapped, and each course's own page found (CRICOS code, then title) and read as evidence. Onboarding moves each university without an admitting adapter through these steps every minute. | Onboard universities, Find provider websites, Discover course pages, Search for course pages, Read course pages, Match pages to courses | A website the finder could not verify (Layer 4 › Websites to find); a wrong website; course pages added by hand when none can be found. |
| 3. University adapter | The AI proposes an adapter from sample pages (twice more if nothing passes); it is saved in testing, applied to every stored page and qualified field by field. A passing field is ready to admit; nothing is admitted by the test. | Onboard universities, Task manager tasks | A Platform Admin admits the ready fields on Layer 2 › Adapters. Universities where nothing passes show "Needs a person". |
| 4. Central pages | Fee schedules, English language policies and academic calendars are found and read; the rule parser, and for English policies and calendars a pinned AI model (GPT-4.1 mini, every value quoted), turn them into proposals. | Find and read fee schedules, English policies and calendars; Find central pages; Read central pages with AI | A Platform Admin approves or rejects each proposal (Adapter builder 1.3, or Providers › Onboarding › Approvals waiting). Nothing is written before approval. |
| 5. Admission | Admitted adapters and approved rules write values to courses every 10 minutes: intakes, English, fees, delivery. A value entered by hand is never overwritten. Values that sources disagree on, or that only an unofficial source gives, go to review. | Adapter values replace older ones, Admit intakes from course pages, Apply approved English policies, Apply provider fee profiles, Review rules (nightly) | Curators decide the Layer 4 Review queue, oldest first. |
| 6. Scholarships | Scholarship pages are found on each university's site, read through the scraper and read by pinned AI models in order (Qwen3 30B, then GPT-4.1 mini); every fact must be quoted from the page. Passing scholarships are published every hour; a nightly review withdraws any that stop passing. | Discover scholarships, Read scholarship pages with AI, Publish scholarships automatically (hourly), Nightly publication review | Curators decide pages no model could settle (Layer 4 › AI could not decide); a Platform Admin spot-checks the automatic publishing and holds anything wrong. |
| 7. Delivery | Search, the website API, Wix and Zoho are refreshed for every changed course and scholarship. | Refresh search for changed courses, Course scholarship attribute, Rebuild API reference data | Nothing, unless a delivery job fails. |

## 4. Rules that never change

1. A value entered by hand is never overwritten by automation. Release it on the record to let automation update it again.
2. A passing test never switches anything on. Admitting an adapter, approving a central page, activating an AI model or adding it to the order is a separate step a person takes, with a reason.
3. AI models are pinned and qualified for each task; nothing routes to an untested model. An AI answer counts only where its quote is on the stored page.
4. Every background job is a scheduled job in the automation catalogue or a task in Task manager, with its controls. Something running that you cannot see there is a fault: report it.
5. Work oldest first, give a reason for every decision, and never decide from memory: open the stored page or document.

## 5. Daily routine

### Start of day (about 20 minutes)

| # | Who | Do | Why | Done when |
|---|---|---|---|---|
| 1 | Platform Admin | Read the credit and limit bar under the page title, if one shows. Red means a toolset has stopped: fix it first. _(Models & services)_ | Firecrawl, OpenRouter, the adapter AI allowance and the scholarship scraper cap stop work when used up. | No red bar. |
| 2 | Platform Admin | Platform health › Health checks: clear every Critical; read each Warning and fix it or note why it can wait. _(Platform health › Health checks)_ | The checks run every 10 minutes over jobs, queues, budgets and the database. | No Critical open. |
| 3 | Platform Admin | Scheduled jobs › Automations: "Failed in the last 24 hours". Open each failed job and read its last error (Platform guide › Signal → action). _(Scheduled jobs › Automations)_ | A job failing every run means its stage has stopped. | Every repeated failure is fixed, paused with a note, or raised with the platform engineer. |
| 4 | Platform Admin | Dashboard › Waiting for you: note universities ready to admit, onboarding stopped or needing a person, review items and scholarships to link. _(Dashboard)_ | One list of everything waiting for a person. | You know today's queue. |

### Morning: decisions only you can make

| # | Who | Do | Why | Done when |
|---|---|---|---|---|
| 1 | Platform Admin | Providers › Onboarding › Ready to admit: open each university's journey, check the fields marked Passes, then admit those fields on Layer 2 › Adapters. _(Providers › Onboarding)_ | Onboarding stops at Ready to admit; nothing is admitted without you. | Ready to admit is empty or each remaining row has a note why it waits. |
| 2 | Platform Admin | Providers › Onboarding › Approvals waiting (or Adapter builder 1.3 for one university): for each fee schedule, English policy and calendar, open the document, compare three or four values, then approve or reject with a reason. Proposals marked ai:gpt-4.1-mini were read by the AI; check each quoted value against the page. _(Providers › Onboarding)_ | Approval writes values to every course of that university that has none. | Approvals waiting falls; rejected ones carry a reason. |
| 3 | Platform Admin | Providers › Onboarding › Stopped: read each row's reason and What to do, fix it, tick the rows and choose Retry selected. _(Providers › Onboarding)_ | A stopped university gets no adapter until someone acts. | Only rows that truly need outside help remain stopped. |
| 4 | Platform Admin | Scholarships › Coverage: open three or four scholarships from the latest automatic publishing; compare the value and who it is for with the page; Hold anything wrong, with a reason. _(Scholarships › Coverage)_ | Publishing is automatic every hour; your spot-check is the control on it. | Spot-check recorded; holds explained. |

### Afternoon

| # | Who | Do | Why | Done when |
|---|---|---|---|---|
| 1 | Platform Admin | Layer 4 › AI could not decide: if the waiting count is large after a rule or model change, use Read the waiting pages again (with a reason) before people work through it. _(Layer 4 Review › AI could not decide)_ | Pages are re-read on their stored copy without scraper credit. | Only pages no model can settle wait for Curators. |
| 2 | Platform Admin | Scheduled jobs › Task manager: anything you started is finished or still moving. _(Scheduled jobs › Task manager)_ | Every background task shows here with its controls. | No task stuck for hours. |

## 6. Weekly

- Models & services: Firecrawl balance against the month, OpenRouter credit, adapter AI allowance (proposals and US$ a day). Top up or adjust before the bar turns amber. _(Models & services)_
- Scholarships › Extraction: cost today, the model order, and any model waiting to be qualified or added. A model joins the order only after it qualifies, and only when you add it. _(Scholarships › Extraction)_
- Coverage & completeness: intakes, English, tuition and course links should rise week on week; a flat field means a stage is stuck. _(Coverage & completeness)_
- Users & roles: lowest role that does the job; expiry dates for contractors. _(Users & roles)_
- Providers › Onboarding: Waiting (queued), Ready to admit and Done. Adjust "How many at once" in Onboarding settings if credits run low or the queue is slow. _(Providers › Onboarding)_

## 7. Where a person intervenes

| When you see | Do | Where |
|---|---|---|
| Ready to admit | Check the passing fields in the journey and admit them on Layer 2 › Adapters. | Providers › Onboarding; Layer 2 › Adapters |
| Approve central pages / Approvals waiting | Open the document, check values against it, approve or reject with a reason. | Adapter builder 1.3; Providers › Onboarding › Approvals waiting |
| Needs a person (nothing passed after the AI attempts) | Open the Adapter builder: mark the values on the sample pages, add a better course page, or approve the central pages; then Retry. Admitting by hand also finishes onboarding. | Layer 2 › Adapter builder |
| Credit or limit bar (amber or red) | Top up the account named, or raise the allowance in Models & services; then check the stopped work resumes. | Models & services |
| A new AI model or new AI instructions | Qualify on the sample, compare scores, then make active or add to the order as a separate step with a reason. A new instructions version switches AI admission off until the models are qualified again. | Scholarships › Extraction |
| A wrong website for a provider | Enter the official website in the Adapter builder (1.1); a different website replaces the course-page search. Then Retry onboarding. | Layer 2 › Adapter builder |
| A paste file from a change (anything that drops or deletes) | Read it, run it in the Supabase SQL editor for project fxcwkweaxjtknorudmwp, check the expected counts it states. | Supabase SQL editor |

## 8. What to pay attention to

- The credit and limit bar on every page.
- Universities stopped or needing a person on Providers › Onboarding, and how long they have waited.
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
