# M1-L2-AU-COURSE-FACTS — QUT Source Qualification UAT

**Date:** 20 August 2026  
**Status:** DEFERRED / ACQUISITION BLOCKED  
**Provider:** Queensland University of Technology  
**Provider CRICOS:** `00213J`  
**Source key:** `au_qut_official_course_pages`  
**Worker:** `coursefacts-au-qut-v0.1.1`

## Scope

Attempt to qualify QUT as a third authoritative Provider-owned AU Course Facts source class using the existing exact-CRICOS relational/evidence contract.

Canonical exact CRICOS Courses were confirmed before runtime acquisition:

- `083019B` — Bachelor of Business - International
- `017323G` — Bachelor of Information Technology (Honours)

No title-only identity path was introduced.

## Source suitability

QUT official Course pages publicly expose the required Course Facts for the bounded sample, including exact CRICOS Course code, 2027 international fee, February/July entry and governed English-test thresholds.

This semantic suitability did not overcome the production acquisition gate.

## Runtime UAT

### Attempt 1

Worker `coursefacts-au-qut-v0.1.0`, request `1909`.

Result: **FAIL CLOSED**

`083019B HTTP 403`

No evidence-derived canonical fact was applied.

### Attempt 2

Worker `coursefacts-au-qut-v0.1.1`, request `1910`.

The retry used normal browser-equivalent request headers and canonical public QUT URLs.

Result: **FAIL CLOSED**

`083019B HTTP 403`

The Provider continued to reject the production Supabase Edge runtime. No challenge bypass, cookie automation, anti-bot circumvention or copied search-engine evidence was attempted.

## Database decision

The source qualification was changed from `bounded` to `deferred`:

- qualification status: `deferred`
- APPLY admitted: false
- Search admitted: false
- runtime status: 403
- runtime attempts: 2
- identity authority: false

No QUT Course link, Provider-current fee, intake or English requirement was admitted into canonical Layer 2 tables.

## Production lineage

- source pre-stage migration: `20260820004729_m1_l2_au_coursefacts_qut_source_v1`
- deferral migration: `20260820004902_m1_l2_au_coursefacts_qut_defer_v1`
- deployed worker version: `coursefacts-au-qut-v0.1.1`
- Edge Function version: 2
- deployment SHA-256: `87a6734145c26c1727c777ab1c57d7bb8dd488756036b4aa27f1f1eb015d82fb`

## Decision

**DEFERRED, not rejected.**

QUT is an authoritative and semantically suitable first-party source, but the current production acquisition path cannot fetch it without encountering HTTP 403. The source must remain non-APPLY until an authorised stable first-party acquisition method is available.

This source-specific blocker does not block the AU Course Facts lane: accepted RMIT/UQ sources may continue to expand independently.
