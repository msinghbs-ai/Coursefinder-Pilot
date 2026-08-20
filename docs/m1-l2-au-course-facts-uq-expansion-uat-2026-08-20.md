# M1-L2-AU-COURSE-FACTS — UQ Coverage Expansion UAT

**Date:** 20 August 2026  
**Status:** PASS / QUALIFIED SOURCE COVERAGE EXPANDED  
**Provider:** The University of Queensland  
**Provider CRICOS:** `00025B`  
**Source key:** `au_uq_official_program_pages`  
**Worker:** `coursefacts-au-uq-v0.2.0`

## Purpose

Prove that the already-qualified UQ Provider-owned program-page source class can expand beyond its original two-Course acceptance sample without changing the accepted relational model, identity contract or Search boundary.

## Existing qualified sample retained

- `102784C` — Bachelor of Computer Science (Honours)
- `082960F` — Bachelor of Nursing (Honours)

## New bounded Courses

### `045401M` — Bachelor of Commerce/Bachelor of Information Technology

Official UQ program page:
`https://study.uq.edu.au/study-options/programs/bachelors-commerce-information-technology-2572?year=2027`

Source-proven facts retained:

- CRICOS: `045401M`
- international 2027 indicative annual fee: AUD 60,952
- Semester 1 start: 22 February 2027
- Semester 2 start: 26 July 2027
- UQ-direct international closing dates: 30 November 2026 and 31 May 2027
- IELTS: 6.5 overall, all components 6.0
- TOEFL iBT: 87 overall, L19/R19/W21/S19
- PTE Academic: 64 overall, all sub-bands 60

### `013827E` — Bachelor of Science/Bachelor of Arts

Official UQ program page:
`https://study.uq.edu.au/study-options/programs/bachelors-science-arts-2478?year=2027`

Source-proven facts retained:

- CRICOS: `013827E`
- international 2027 indicative annual fee: AUD 56,800
- Semester 1 start: 22 February 2027
- Semester 2 start: 26 July 2027
- UQ-direct international closing dates: 30 November 2026 and 31 May 2027
- IELTS: 6.5 overall, all components 6.0
- TOEFL iBT: 87 overall, L19/R19/W21/S19
- PTE Academic: 64 overall, all sub-bands 60

Provider-published BE/CES alternatives remain outside `catalogue.course_english_requirements` until a governed `ref.english_tests` identity is accepted for those schemes.

## Identity preflight

Both new CRICOS codes resolved exactly under Provider `00025B` before APPLY:

- `course:cricos:00025b:045401m`
- `course:cricos:00025b:013827e`

No title-only identity path was used or added.

## Worker delta

`coursefacts-au-uq-v0.2.0` expands the bounded record set from two to four exact CRICOS Courses. The worker contract is otherwise unchanged:

- current official UQ HTML fetched at runtime;
- source proof tokens must be present;
- private evidence snapshot persisted;
- SHA-256 content hash retained;
- exact Provider CRICOS + Course CRICOS resolution;
- `provider_current_tuition` fee semantics;
- Search admission false;
- one-time Pilot nonce execution control.

Live deployed Edge Function version: 2.  
Deployment SHA-256: `913bbe1d0aa35435e5561d67b75ef5025f7cfd07c0483e408df76ed928df12a3`.

## Dry-run

Request `1906` — PASS.

All four UQ records passed source proof and exact canonical resolution.

New Courses predicted:

| CRICOS | Link | Fee | Intakes | English |
|---|---:|---:|---:|---:|
| 045401M | 1 | 1 | 2 | 3 |
| 013827E | 1 | 1 | 2 | 3 |

Existing two accepted records also remained resolvable with unchanged predicted cardinality.

## APPLY

Request `1907` — PASS.

New canonical Layer 2 facts applied for the two expansion Courses while existing UQ facts remained stable.

## Replay / idempotency

Request `1908` — PASS.

The four page hashes were unchanged between APPLY and replay. Source-record IDs were reused and canonical counts did not increase on replay.

Post-replay UQ totals:

- official Course links: 4
- provider-current fees: 4
- intakes: 7
- governed English requirements: 12

No canonical `catalogue.courses.course_url` mutation occurred.

## Aggregate accepted AU Course Facts state

Across qualified RMIT + UQ sources after this expansion:

- qualified Provider source classes: 2
- bounded exact CRICOS Courses: 6
- official Course links: 6
- provider-current fee observations: 6
- intake observations: 10
- governed English requirement observations: 20

## Search isolation

Verified after APPLY/replay:

- Search Course Documents: 33,105
- Search rows with fee/intake/English enrichment: 0

The expansion does not admit Provider-current facts into Search.

## Production lineage

- Edge worker: `coursefacts-au-uq-v0.2.0`
- migration: `20260820004354_m1_l2_au_coursefacts_uq_coverage_v2`

## Decision

**PASS.**

The qualified UQ source class is proven beyond its original two-Course acceptance sample. Coverage may continue to expand under the same source class without another architecture gate while the page structure, exact CRICOS mapping, fact semantics and evidence contract remain unchanged. Any new Provider site/source class still requires its own bounded qualification UAT.
