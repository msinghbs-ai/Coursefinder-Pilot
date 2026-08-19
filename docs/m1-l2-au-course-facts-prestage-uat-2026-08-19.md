# M1-L2-AU-COURSE-FACTS — Pre-stage UAT

**Date:** 19 August 2026  
**Status:** HOLD / PRE-STAGED ONLY  
**Authoritative prerequisite:** `M1-L1-AU-CRICOS-COMPLETENESS` must PASS before Layer 2 APPLY.

## Reason for HOLD

The current Admin master plan v1.33 and database architecture v2.10.33 supersede the earlier dependency wording that referred only to `M1-L1-AU-CRICOS-FACTS`. Live validation still shows 2,281 AU Courses without mapped `study_level_id` and 34 AU Courses without canonical campus relationships. The Layer 2 serial gate is therefore not yet authorised.

## Pre-staged implementation

A bounded RMIT first-party collector has been hardened as `coursefacts-au-rmit-v0.2.0`.

The apply contract now:
- resolves Provider and Course only by exact active CRICOS registrations;
- has no title-only identity path;
- requires a source qualification record before dry-run/APPLY;
- stores official Provider Course URLs in `catalogue.course_links` without mutating canonical `catalogue.courses.course_url`;
- stores Provider-current tuition as `fee_type=provider_current_tuition`, separate from CRICOS registered-total-course fee observations;
- preserves fee year, fee basis, source and evidence;
- supports source-keyed intake replay;
- supports source/evidence/validity on English requirements;
- keeps Search admission false.

## Authoritative bounded source verification

RMIT University, CRICOS Provider 00122A:

1. CRICOS 111279A — Associate Degree in Business
   - official Course page verified;
   - 2027 international fee: AUD 37,440, annual basis;
   - February and July intakes;
   - course-specific IELTS / TOEFL iBT / PTE / C1 Advanced thresholds verified.

2. CRICOS 103390B — Advanced Diploma of Electronics and Communications Engineering
   - official Course page verified;
   - 2027 international fee: AUD 49,250, total-indicative basis;
   - Semester 1 / February intake with published 2027 timing;
   - course-specific IELTS / TOEFL iBT / PTE / C1 Advanced thresholds verified.

## Bounded UAT evidence

Dry-run: PASS for both CRICOS-coded Courses.

Temporary APPLY/replay validation: PASS after one intake-key SQL precedence defect was found and corrected.

Post-fix replay cardinality during UAT:
- source records: 2;
- official Course links: 2;
- Provider-current fee rows: 2;
- intake rows: 3;
- English requirement rows: 8;
- canonical `courses.course_url` mutations: 0;
- primary Layer 2 links: 0;
- CRICOS registered-fee collisions/touches: 0.

Ambiguity UAT: PASS. An invalid/mismatched CRICOS Course code was rejected with `course CRICOS not resolved`; no title fallback exists on the apply surface.

## Gate restoration

Because the current serial prerequisite remains open, the temporary catalogue APPLY rows used for UAT were removed after validation.

Current live posture:
- RMIT Layer 2 Course links applied: 0;
- RMIT Provider-current fees applied: 0;
- RMIT intakes applied: 0;
- RMIT English requirements applied: 0;
- source observations retained for evidence/pre-stage;
- RMIT source qualification: `deferred`;
- `apply_admitted=false`;
- `search_admitted=false`;
- Search Documents remain 33,105;
- Search `has_fee=true` remains 0;
- AU identity remains 1,546 Providers / 26,648 active Courses.

## Decision

**HOLD.** Do not run Layer 2 APPLY and do not admit these facts to Search until `M1-L1-AU-CRICOS-COMPLETENESS` is accepted. After that gate passes, reactivate the RMIT qualification, rerun bounded source capture + dry-run/APPLY/replay/idempotency UAT, then expand provider-by-provider under the same CRICOS/evidence contract.