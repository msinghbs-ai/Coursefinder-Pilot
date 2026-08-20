# M1-L2-AU-COURSE-FACTS — RMIT First-Source UAT

**Date:** 20 August 2026  
**Result:** PASS / FIRST SOURCE ACCEPTED  
**Layer 1 prerequisite:** `layer1-au-depth-v1.6.0` / PASS  
**Worker:** `coursefacts-au-rmit-v0.2.0`

## Scope

Bounded authoritative Provider-owned enrichment against accepted AU CRICOS Course identity. The first accepted source is RMIT University official Course pages. This gate does not broaden Search/API/Website admission.

## Identity contract

- Provider: RMIT University, CRICOS `00122A`.
- Courses: CRICOS `111279A` and `103390B`.
- Resolution is exact Provider CRICOS + Course CRICOS only.
- Title-only matching is not implemented.
- Negative ambiguity UAT with an invalid Course code failed closed with `course CRICOS not resolved`.

## Fresh-source dry-run

PASS for both records.

- `111279A`: official URL + provider-current fee + 2 intakes + 4 English tests predicted.
- `103390B`: official URL + provider-current fee + 1 intake + 4 English tests predicted.
- Fresh HTML evidence captured with SHA-256 and private evidence storage.

## APPLY result

Applied canonical Layer 2 observations:

- official Course links: 2
- provider-current international tuition fees: 2
- intakes: 3
- English requirements: 8
- canonical `courses.course_url` mutations: 0
- Layer 2 primary-link promotions: 0
- CRICOS registered fee collisions: 0

Fee semantics:

- `111279A`: AUD 37,440, 2027, `annual`, `provider_current_tuition`.
- `103390B`: AUD 49,250, 2027, `total_indicative`, `provider_current_tuition`.

## Replay / idempotency

A second fresh APPLY captured new source bytes because the RMIT pages contain dynamic HTML, producing new evidence/content hashes. Parsed payload hashes for each Course remained unchanged between the two fresh APPLY runs.

Canonical Layer 2 row counts remained exactly:

- links: 2
- fees: 2
- intakes: 3
- English requirements: 8

This is accepted evidence-versioning behaviour: changed source bytes create a new observation version, while unchanged parsed facts do not duplicate canonical observations.

## Search isolation

Verified after APPLY/replay:

- Search Documents: 33,105
- `has_fee=true`: 0
- `has_intake=true`: 0
- `has_english=true`: 0

No Search enrichment admission occurred.

## Decision

PASS / FIRST SOURCE ACCEPTED.

`au_rmit_official_course_pages` is qualified for bounded Layer 2 operation with APPLY admitted and Search admission false. Expansion to additional RMIT Courses or additional Providers must preserve exact governed identity mapping, evidence/versioning and the same dry-run/APPLY/replay/ambiguity controls.
