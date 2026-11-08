# English policies waiting for a person: review pack (read only, live project fxcwkweaxjtknorudmwp, 8 Nov 2026 03:34 UTC)

Nothing in this file has been applied, approved or changed. It lists the 29 English policy readings in status `proposed` so the Platform Admin can decide faster.
The funnel counts 398 courses of 21 providers as waiting for a reading to be approved, plus 658 courses of UNSW Sydney (faculty table, needs binding). The "Missing" column below counts every active course of the provider with no English, so its total (1,234) is larger than the funnel's: a provider whose stage is not "reading proposed" (for example one with an earlier approved reading) is classified by that stage first. 20,749 of 35,689 active courses hold English today.

How to read the table: "Looks" is my reading of the page address and the values only. I did not open every page. The one I did open, Thompson Rivers, is a misread (see below).
"Missing" is the number of the provider's active courses with no active English requirement today. An approval of a level default reaches only the levels the reading gives; the rest stay held by the policy.
Approving is a person's act on Settings › Coverage › Attributes › English policies (`public.admin_provider_policy_decide`). The default then flows through the existing job `provider-english-defaults`.

## A. Faculty table: needs approval and binding (Platform Admin only)

| Provider | Missing | Reading | Needs |
|---|---|---|---|
| UNSW Sydney (proposal 8a4a005a-5e9e-466f-a840-8c2d71544687) | 658 of 667 | parser v0.3.0, 14 faculty groups, 61 named exceptions, no university default (filed 7 Nov) | Approve, then bind each group to courses by field of education or title pattern (`public.admin_provider_english_groups_set_v1`; the screen is the same English policies panel). The fixture `tests/fixtures/english-requirements/exceptions-tests.sql` shows the binding form and that excepted courses are never given the faculty score. Binding is never automatic. |

## B. Level defaults that look provider-wide (candidates to approve)

| Provider | Missing / active | Reading (default by level) | Parser | Looks |
|---|---|---|---|---|
| Victoria University (08c42200-626b-428c-b51d-babd1cdf0cee) | 38 / 279 | UG IELTS 6, PG IELTS 6.5 | v0.3.0 | The institution's English requirements PDF. |
| Adelaide University (2dd9fe80-b1d8-4b27-8efb-84212b219c09) | 34 / 498 | UG 6.5, PG 6.5 | v0.3.0 | Entry requirements page. A single value for both levels; the page may carry course-specific higher scores (those courses keep their own reading). |
| Charles Sturt University (af62d48d-4738-4853-bcfd-c4b177f2b0a4) | 13 / 67 | research 6.5, PG 6, UG 6 | ai | Course entry requirements page. |
| Edith Cowan University (583ef052-894e-4491-8ccb-15b96094ad65) | 7 / 171 | UG 6, PG 6 | ai | English proficiency bands page. |
| Deakin University (19b3df33-2479-4a05-ac89-40c3e6270643) | 7 / 252 | research 6, PG 6, UG 5.5 | ai | The page is the DUELI (Deakin's own English programme) route; check that 5.5 is the university-wide entry level before approving. |
| Excelsia University College (fc68fe15-81ad-42f4-ab8a-e0e61b770217) | 6 / 48 | UG 6, PG 6 | ai | "Future students" landing page; confirm the quoted text. |
| TAFE International Western Australia (b21994c4-0a38-4e4d-b7bf-3ded9da4baaa) | 14 / 101 | UG 6, PG 6 | v0.3.0 | The page is titled "learn English"; confirm it states the entry requirement for courses. |
| Alberta University of the Arts (6bf0ea88-b07c-4a1b-94f6-0fe46471bf9b) | 5 / 5 | IELTS 6.5, TOEFL iBT 83, PTE 56, DET 120, CAE 176 | v0.2.5 | Bachelor's degree application page; multi-test row looks complete. |
| Royal Roads University (55602cfd-f2c9-4706-993d-28ad1683ac76) | 31 / 31 | UG only: IELTS 6.5, TOEFL iBT 88, PTE 60, DET 120 | v0.2.5 | Reading has no postgraduate default, so any graduate courses stay held. |
| Olds College (3e109692-b1dd-4ab7-b3c6-47a0c23aff36) | 1 / 1 | IELTS 6, PTE 55, DET 110 | v0.2.5 | International admissions page. |
| The New Zealand Chiropractic Education Trust Board (37750352-7443-4f1f-b1de-ef0afa44e42b) | 1 / 1 | IELTS 7.5 | v0.2.5 | The provider's international page. |
| Vigil International College (a3192aa7-9aed-477e-972b-6a23caf757c1) | 3 / 18 | UG 5, PG 5 | v0.2.5 | The address is a 2023 enrolment notice; confirm it is current. |

## C. Page may be narrower than the whole provider (check before approving)

| Provider | Missing / active | Reading | Why check |
|---|---|---|---|
| Whitireia and WelTec (01d457be-ba69-481a-bfa8-9159e36a9bdf) | 65 / 116 | research 6.5, PG 6, UG 5.5 | The source is the NZQA rules table, not the provider's own page. |
| Toi Ohomai Institute of Technology (f55a6c52-c498-46b5-bf1f-034b77e62e40) | 63 / 156 | PG 7, UG 6 | The page is an early childhood education (ECE) English requirement; 7 and 6 are likely that programme's values, not the institute's. |
| British Columbia Institute of Technology (77e95e3e-bcd7-4740-b7ad-ed158421b329) | 29 / 30 | UG and PG both IELTS 6, TOEFL iBT 82, PTE 52, DET 105 | The page is for part-time courses. |
| Silverline College (819ad441-f83f-4f8a-a6bc-cd69a5e8eb25) | 17 / 17 | UG 6, PG 6 | Small college; same value for both levels. |
| Adelaide Institute of Health (28772b1d-713e-41eb-9049-e7ec60fd24e1) | 5 / 24 | IELTS 4.5, PTE 30, TOEFL iBT 32, CAE 147, DET 65 | The page is an equivalency table; 4.5 and PTE 30 look low for health courses. |

## D. Likely a misread (my advice is to reject or re-read; the decision is yours)

| Provider | Missing / active | Reading | Why |
|---|---|---|---|
| Thompson Rivers University (70e19f28-d877-42a6-a50e-b550ac3f6347) | 74 / 76 | UG IELTS 5, PG IELTS 5 | Opened: the quoted 5 comes from the placement text for the university's own English course (FCE), not the entry requirement. Approving would give 74 courses a wrong score. |
| Algonquin College (fb0fd396-9351-49f5-81f0-004094cbf5f5) | 11 / 59 | UG 9, PG 9 | The page is an IELTS test centre; IELTS 9 is the top of the scale, not an entry level. |
| Lexis English Perth (31fd9b60-cabf-43f3-95d7-4b89aa4c9acd) and Lexis English Brisbane (fca6fea0-99c5-48b6-9250-b11c5f61fcc4) | 9 / 9 and 8 / 8 | IELTS 4 | English-language schools; the page describes an IELTS or Cambridge preparation course, not an entry requirement to the college's courses. |
| Flinders International College (d841c35c-3802-4cfc-8122-7779a472a2de) | 10 / 11 | IELTS 6 | Page is the "IELTS Foundation course". |
| Australian Institute of Language (aaad99e2-c5a4-4e50-9d1b-e023054642fe) | 5 / 8 | IELTS 5 | Page is an IELTS course page. |
| Englishwise Global (c27f3d28-32a6-4d08-b333-e0a70deb3068) | 2 / 3 | IELTS 4.5 | Page is a PTE and IELTS exam preparation course. |

## E. Named courses only (no default; each named course gets its own value)

SIT (8fd76b8c-698c-47ff-a0eb-d8c73349958a, 112 missing, 3 exceptions), Taylors College Sydney (eed0d521-5a7b-4f65-8eaa-fbeb66305f52, 1 missing, 142 exceptions),
St Maroun's College (5721b536-1fb1-4ec4-875a-11d7a049a541, 3 missing, 2 exceptions), New Zealand Aviation Academy (7e3c9d20-b11c-4df8-85f1-47abb43c72b6, 2 missing, 1 exception).
Approving these reaches only the courses the page names; the other courses of the provider stay without English (the funnel reports them as `policy_held:named_in_policy`).

## What approval does and does not do

- Approving a level default makes the provider's courses at that level eligible for the default. The job `provider-english-defaults` writes it (confidence 0.6 when the policy says some courses need more), never over a course's own reading, a manual lock, or a Layer 4 item in review.
- Rejecting records the decision; the provider returns to "read, no usable rule" and is not re-read until the page changes.
- Counts of the 29 proposals (missing courses): A 1 provider (658), B 12 (160), C 5 (179), D 7 (119), E 4 (118).
