# M1-L2-AU-COURSE-FACTS — UQ Coverage Expansion v3 UAT

**Date:** 20 August 2026  
**Status:** PASS / QUALIFIED SOURCE COVERAGE EXPANDED  
**Provider:** The University of Queensland  
**Provider CRICOS:** `00025B`  
**Source key:** `au_uq_official_program_pages`  
**Worker:** `coursefacts-au-uq-v0.3.0`

## Purpose

Continue controlled Course coverage under the already-qualified UQ first-party program-page source class, expanding from four to eight exact CRICOS Courses without changing identity authority, relational grain, fee semantics or Search admission.

## Existing bounded Courses retained

- `102784C` — Bachelor of Computer Science (Honours)
- `082960F` — Bachelor of Nursing (Honours)
- `045401M` — Bachelor of Commerce/Bachelor of Information Technology
- `013827E` — Bachelor of Science/Bachelor of Arts

## New bounded Courses

- `019886A` — Bachelor of Business Management
- `001942A` — Bachelor of Arts
- `080734K` — Bachelor of Engineering (Honours)
- `092454G` — Master of Data Science

All four new Courses already existed canonically under Provider CRICOS `00025B` and resolved by exact Course CRICOS code.

## Source facts retained

For each new Course, the UQ official 2027 program page was fetched at runtime and proved the published CRICOS code, 2027 international indicative annual fee, Semester 1 / Semester 2 start dates and standard UQ English thresholds.

New Provider-current fees:

- `019886A`: AUD 56,800 / 2027 / indicative annual
- `001942A`: AUD 48,080 / 2027 / indicative annual
- `080734K`: AUD 60,952 / 2027 / indicative annual
- `092454G`: AUD 60,952 / 2027 / indicative annual

New intake facts retain 22 February 2027 and 26 July 2027 starts without manufacturing application deadlines where this worker version did not explicitly persist one.

Standard governed English rows retained per new Course:

- IELTS Academic: 6.5 overall, each component 6.0
- TOEFL iBT: 87 overall, L19 / R19 / W21 / S19
- PTE Academic: 64 overall, all sub-bands 60

Provider-published alternatives without an accepted canonical test identity remain uncoerced.

## Worker delta

`coursefacts-au-uq-v0.3.0` expands the qualified UQ bounded set from four to eight exact CRICOS Courses and factors common standard English/intake construction internally. The canonical contract is unchanged.

Live Edge Function:

- version: 3
- deployment SHA-256: `3ee7aade7fca8f075d49b8e1755a166bdf64ed55fe434bf12d2afca8eb156b94`

## Dry-run

Request `1912` — **PASS**.

All eight official pages passed runtime source proof and exact canonical resolution.

For each of the four new Courses the dry-run predicted:

- official link: 1
- Provider-current fee: 1
- intakes: 2
- governed English requirements: 3

## APPLY

Request `1913` — **PASS**.

All eight records resolved and applied through the existing governed RPC. The four prior UQ rows remained stable while the four new Courses were admitted.

## Replay / idempotency

Request `1914` — **PASS**.

The same source-record identifiers were returned for all eight Courses. Canonical row cardinality remained unchanged by replay.

Post-replay UQ state:

- official Course links: 8
- Provider-current fees: 8
- intakes: 15
- governed English requirements: 24

## Aggregate accepted AU Course Facts state

Across qualified RMIT + UQ sources:

- qualified source classes: 2
- exact bounded CRICOS Courses: 10
- official Course links: 10
- Provider-current fee observations: 10
- intake observations: 18
- governed English requirement observations: 32

## Search isolation

Verified after APPLY/replay:

- Search Course Documents: 33,105
- rows with fee/intake/English enrichment admitted: 0

No Search projection rebuild or enrichment admission occurred.

## Production lineage

- worker: `coursefacts-au-uq-v0.3.0`
- migration: `20260820005253_m1_l2_au_coursefacts_uq_coverage_v3`

## Decision

**PASS.**

The qualified UQ source class now has eight bounded exact CRICOS Courses under replay-safe production ingestion. This is a coverage expansion, not a new architecture contract. Additional UQ Courses may continue under the same controls while source structure and semantics remain compatible.
