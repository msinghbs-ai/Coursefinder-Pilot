# CourseFinder PIM Admin v2.15.58–v2.15.71 change and recovery history

Date: 7 Sep 2026

Purpose: reconstruct the requested changes/fixes that advanced the visible PIM Admin version after v2.15.57, preserve the related commit/change-control trail, and record the recovery/UAT state. This document is a recovery/audit record; it must not be used to imply that a feature passed UAT unless a passing run is explicitly recorded.

## Release progression

| Version | Requested change / fix that drove the version | Primary evidence / change batch | Recovery / UAT state |
| --- | --- | --- | --- |
| 2.15.57 | Provider/university logos across Provider, Course and Compare; private Provider Asset access; Hotcourses directory reconciliation support. | CF-102; release note commit `2352a86c4672bcc9383c3c931ecefb05bb26767f`. | Historical baseline before the 58–71 recovery window. |
| 2.15.58 | Scholarship acquisition provenance; distinguish live acquisition from downstream Evidence reuse; keep Layer 1→4 operator sequence fixed; continue bounded first-party Scholarship acquisition without automatic publication. | CF-146; `7560f5badb49a210b2636cc35cbf4d7647b24d6a`, `e0eed243646422e785e337889fcdaadf3f47331b`. | Release currentness existed in source. Later recovery required because deployed currentness subsequently drifted. |
| 2.15.59 | QILT 2023 comparison reconciliation: retain SES cohort grain (UG/PGC), retain 2023 observations for Monash/RMIT/La Trobe alongside 2024, and prevent absent confidence/benchmark fields from rendering as false zeroes. | Reconstructed from the v2.15.60 currentness diff; the prior currentness payload was explicitly v2.15.59. | No distinct `release v2.15.59` commit was found. Treat as reconstructed source history, not an independently accepted release. |
| 2.15.60 | Provider-logo hydration/performance correction: de-duplicate signed-asset requests, remove rapid mutation-loop rehydration, coalesce list/drawer hydration, lazy/asynchronous logo image loading, retain authorised upload/replace. | CF-150; `ccf23bf794d96318e6c11c6548b77040634a9eaa`. | Source release reconstructed and retained. Provider-logo regression remains part of recovery coverage. |
| 2.15.61 | International Scholarship selector: international-only backend boundary; University/provider search; Course title/CRICOS/provider search; inventory count and bounded Provider-owned/Provider-neutral scope rules. | CF-151; `5561ca6064d148c03bd7d61be35c0fd2431d50b7`, `b14f14c3bf02231a5712b7ee412b8cde565065de`. | Source release retained; Scholarship recovery/UAT still requires explicit closure. |
| 2.15.62 | Provider-logo retention/cache hardening while Scholarship selector was added: Provider/Course/Compare logos mandatory, bounded bulk resolver, in-flight de-duplication, lazy decoding/session cache, 30-minute signed URL lifetime, permanent logo regression no longer pinned to an old UI version. | Reconstructed from the v2.15.63 currentness diff, which explicitly replaced v2.15.62. | No distinct `release v2.15.62` commit found. Treat as reconstructed source history. |
| 2.15.63 | International Scholarship runtime and queue hardening: Country/University acquisition, international-only detail qualification, Evidence-backed unpublished reconciliation, active-candidate-only execution queue, Evidence reuse, runtime statistics. | Scholarship runtime batch; `a304beebfd89641effa4b60fb33b5837fc7b1588`, `eb7c140bd76a69fbb6d0b3370c0ee5319c117394`. | Source release retained; later queue precision correction followed in 2.15.64. |
| 2.15.64 | Scholarship queue truth and reconciliation precision: remove historical/acquired records from executable counts, reuse captured Evidence, block structural/navigation/support/domestic/filter/support-document pages from canonicalisation, report verified queue truth. | `5c6d853f3d034774c56e59192d63a5a2cfa4699d`. | Source release retained. Scholarship end-to-end recovery remains open until its current targeted acceptance passes. |
| 2.15.65 | Layer 4 mass operations: load the dedicated mass-operations surface into the Admin shell for governed bulk human-resolution work. | CF-205; `e2849b378a4fd78a274347a1a09b960922d283dd`, `d40f5d7bf9a992257b1817ca96b22f564b6ff903`. | Source release retained; must be regression-tested with current H5/H6/Scholarship controls. |
| 2.15.66 | Reusable Layer 4 Scholarship scope rules: persist reviewed accept/reject rules bound to Scholarship/reason/Provider/Evidence; changed Evidence falls back to review; retain actor/audit/use counters; no Publication bypass. | CF-206; `78e5f9d0bc9555bbfef54fe5692e2a0463c66195`, `a2e221f058ce2cff98b40bf99a7bdf7fca15e5ce`. | Last clean visible release before deployment/currentness divergence. |
| 2.15.67–2.15.70 | No independently evidenced release-currentness records were found. Work continued through H5/H6 candidate/publication controls, ranking workbook/Evidence handling, Compare ranking selectors/persistence, Scholarship supporting-document guards/AI controls/platform health, ranking auto-apply/dataset viewer, and deployment recovery. | Representative batches: CF-211, CF-213–CF-218, CF-220–CF-227. | Do **not** invent separate accepted release notes for 67, 68, 69 or 70. These changes existed in commits, but currentness jumped from 2.15.66 to 2.15.71 during recovery. |
| 2.15.71 | Recovery/consolidation release: restore deployed version currentness; expose accepted QS/THE dataset editions and imported-observation viewer; show Layer 1 Ranking ETL history; retain safe Cloudflare native deployment path and GitHub build artifact/smoke evidence. | CF-228; `c9dbbfb0f1bdbe63c28d68a27077357797b2ae84`, `0e1e1e4069945565d74f47aba2261e9cb1885a8d`. | Live v2.15.71 currentness proven. Ranking recovery later passed CF-097. Other post-66 feature gates remain individually recoverable and must not be inferred from version alone. |

## Post-v2.15.66 requested feature batches that were carried into the v2.15.71 recovery state

These are material requested changes/fixes present in commit history even though versions 2.15.67–2.15.70 were not independently preserved as accepted release-currentness records:

- H5 manual PIM source-backed candidate workflow and H6 publication controls, including canonical Layer 4 detail placement and candidate decision controls (CF-211).
- QS official workbook parsing, indicator rank semantics, governed Evidence/XLSX handling and publisher URL experiments (CF-213), followed by THE equivalent Evidence/workbook handling (CF-214).
- Independent QS/THE ranking-year selectors in Compare, persistent Compare selection and sticky provider comparison headers (CF-215–CF-217).
- Ranking Evidence service RPCs, stable publisher IDs, versioned capture and retained-history selector corrections (CF-218).
- Scholarship supporting-document terminal guard (CF-220).
- Scholarship AI run/benchmark controls plus role-aware platform-health dashboard (CF-221).
- Statistics ranking edition availability/selectors, auto-apply workflow, imported ranking dataset viewer and retry-storm correction (CF-223–CF-226).
- Pilot deployment/currentness recovery and safe artifact retention/rollback of the attempted duplicate Worker deployment path (CF-227–CF-228).
- Ranking viewer deterministic-open fixes and QS workbook canonical indicator-field promotion (CF-228/CF-229).
- Later Evidence-only ranking direction and historical QS/THE completeness recovery (CF-230/CF-231) are post-2.15.71 implementation work and must be tracked separately from the 2.15.71 release itself.

## UAT recovery record

### Ranking recovery

CF-097 recovery ultimately passed on the live deployment for:

- THE retained historical editions;
- Layer 1 Ranking ETL visibility;
- QS/THE Statistics edition selectors;
- imported ranking dataset viewer;
- QS 2025 observation count 1,503 and QS 2024 count 1,498.

This closes the ranking-dataset recovery gate only; it does not imply other post-66 modules passed.

### Compare recovery — current failure

The first Compare marker rerun did not actually resolve to Compare and therefore was not accepted as evidence. A later integration attempt selected 38 suites / 91+ desktop tests, produced many mixed stale-contract and genuine failures, exceeded the 30-minute job window and was cancelled before mobile. It is not a valid Compare acceptance result.

The exact Compare targeted recovery was then corrected for current version authority and triggered at commit `42f921cced54f7f80728310eff54cc9279b95547`. GitHub Actions run `34067484617` completed **FAILURE**. The governed desktop validation step failed; the mobile gate was skipped. Therefore Compare remains **OPEN** and must be fixed from exact failure evidence before re-running.

## Governance rule from this recovery

From this point, every visible PIM Admin version change must be accompanied in the same change batch by:

1. a maintained release-history entry describing the user-requested change/fix;
2. exact Change Control / change-batch reference and implementation commit(s);
3. the visible version authority updated consistently across source title/currentness metadata;
4. a permanent targeted UAT route that actually selects the intended feature suite;
5. recorded deployed UAT result (PASS/FAIL/CANCELLED) with run ID; and
6. no promotion of a failed/cancelled/unrun feature gate to accepted merely because a later version number is visible.

Where a version number was skipped or cannot be evidenced, the repository must say so explicitly rather than reconstructing an invented accepted release.
