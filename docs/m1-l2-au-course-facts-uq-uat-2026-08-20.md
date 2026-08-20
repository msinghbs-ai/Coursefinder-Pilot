# M1-L2-AU-COURSE-FACTS — UQ Source UAT

**Date:** 20 August 2026  
**Status:** PASS / SOURCE QUALIFIED  
**Provider:** The University of Queensland  
**Provider CRICOS:** `00025B`  
**Source key:** `au_uq_official_program_pages`  
**Worker:** `coursefacts-au-uq-v0.1.0`

## Scope

Qualify a second authoritative AU Provider-owned Course Facts source against the accepted `layer1-au-depth-v1.6.0` CRICOS substrate. The source may enrich accepted Courses only; it cannot redefine Provider/Course identity and it cannot publish directly to Search.

## Authoritative source proof

UQ official Study program pages publish the Provider-owned facts required by this bounded gate.

### CRICOS `102784C` — Bachelor of Computer Science (Honours)

Source: `https://study.uq.edu.au/study-options/programs/bachelor-computer-science-honours-2452?year=2027`

Verified source facts:

- CRICOS code: `102784C`
- location: St Lucia
- international 2027 indicative annual fee: AUD 60,952
- international starts: 22 February 2027 and 26 July 2027
- international application closing dates: 30 November 2026 for Semester 1 and 31 May 2027 for Semester 2
- IELTS: overall 6.5; each component 6.0
- TOEFL iBT: overall 87; listening 19; reading 19; writing 21; speaking 19
- PTE Academic: overall 64; all sub-bands 60

### CRICOS `082960F` — Bachelor of Nursing (Honours)

Source: `https://study.uq.edu.au/study-options/programs/bachelor-nursing-honours-2243?year=2027`

Verified source facts:

- CRICOS code: `082960F`
- location: St Lucia
- international 2027 indicative annual fee: AUD 48,080
- international start: 22 February 2027
- international application closing date: 30 November 2026
- IELTS: overall 7.0; each component 7.0
- TOEFL iBT: overall 100; listening 25; reading 25; writing 27; speaking 23
- PTE Academic: overall 72; all sub-bands 72

UQ also publishes BE/CES alternatives. They were not inserted because this gate only persists English tests already governed in `ref.english_tests`; no unsupported equivalence was manufactured.

## Identity UAT

Canonical exact matches existed before Layer 2 APPLY:

- `course:cricos:00025b:102784c`
- `course:cricos:00025b:082960f`

The worker resolves Provider CRICOS `00025B` plus exact Course CRICOS code through `svc_coursefacts_apply_record(...)`.

Negative ambiguity test with `102784Z` returned the expected failure:

`course CRICOS not resolved`

No title-only fallback exists.

## Dry-run

Fresh-source dry-run request: `1903`.

Result:

| CRICOS | Resolved | Link | Fee | Intakes | English |
|---|---:|---:|---:|---:|---:|
| 102784C | PASS | 1 | 1 | 2 | 3 |
| 082960F | PASS | 1 | 1 | 1 | 3 |

Source proof and private evidence snapshot registration passed for both pages.

## APPLY

Production APPLY request: `1904`.

Applied canonical Layer 2 rows:

- official Course links: 2
- provider-current international fees: 2
- intakes: 3
- English requirements: 6

Fee semantics:

- `102784C`: AUD 60,952 / 2027 / `indicative_annual`
- `082960F`: AUD 48,080 / 2027 / `indicative_annual`
- fee type: `provider_current_tuition`

No CRICOS registered-total-course fee was overwritten or reinterpreted.

## Replay / idempotency

Fresh replay request: `1905`.

Result:

- same source-record IDs reused for unchanged page hashes;
- canonical links remained 2;
- canonical fees remained 2;
- canonical intakes remained 3;
- canonical English rows remained 6;
- parsed payload variants remained 1 per source record;
- canonical `catalogue.courses.course_url` mutations remained 0.

This proves both source-record and canonical-row idempotency for the UQ page class under unchanged source bytes.

## Search isolation

After APPLY and replay:

- Search documents: 33,105
- `has_fee=true`: 0
- `has_intake=true`: 0
- `has_english=true`: 0

No Search projection rebuild or Layer 2 admission occurred.

## Security / execution control

`coursefacts-au-uq` uses the existing one-time Pilot nonce model. The submit service is service-role only and the new worker is explicitly allowlisted. The Edge Function keeps `verify_jwt=false` only because the function implements the existing custom one-time nonce authentication contract.

## Decision

**PASS / SOURCE QUALIFIED.**

`au_uq_official_program_pages` is accepted as the second AU Provider-owned Course Facts source class. Controlled expansion may continue under the same exact-CRICOS identity, evidence, fee-basis, intake-scope, English-test governance, replay and Search-isolation rules.
