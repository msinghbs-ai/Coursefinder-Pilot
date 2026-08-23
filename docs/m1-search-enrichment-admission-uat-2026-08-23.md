# M1-SEARCH-ENRICHMENT — Governed Course-Fact Search Admission UAT

**Date:** 23 August 2026  
**Change Control:** `CF-CHG-20260823-023`  
**Target:** CourseFinder Pilot Supabase `fxcwkweaxjtknorudmwp`  
**Result:** **PASS** for governed Course-Fact admission to the FTS projection. Vector/hybrid remains **NOT ADMITTED** under the existing M1-SEARCH-VECTOR rejection.

## Accepted semantics

- CRICOS registered tuition is a separate Layer 1 `registered_total_course` fact and is never represented as Provider-current/annual tuition.
- Provider-current tuition is admitted only from Search-approved qualified first-party sources; structured options preserve year/basis/scope. Only `annual`/`indicative_annual` basis participates in the comparable annual scalar.
- Official Course URL, Intake and English requirements are source-gated. Intake/English retain repeating structures.
- Scholarships remain separately gated; current canonical Scholarships are unpublished, so admitted Search count is 0.
- QILT and PRISMS remain excluded from Course-grain Search; provider/study-area/flow/cohort grain is not coerced to Course grain.
- Legacy `has_fee` means Search-admitted Provider-current tuition presence only.

Search-approved Course Facts sources:

- `au_rmit_official_course_pages`;
- `au_uq_official_program_pages`.

Deferred QUT remains outside Search admission.

## Coverage after APPLY

- Search Course Documents: **33,105**;
- CRICOS tuition: **26,326 present / 131 zero / 191 source-null / 6,457 not-applicable**;
- Provider-current tuition: **10 Courses**;
- comparable annual/indicative-annual Provider tuition: **9 Courses**;
- official Course URL: **10 Courses**;
- Intake: **10 Courses / 18 observations**;
- English: **10 Courses / 32 observations**;
- admitted Scholarships: **0**;
- QILT active observations: **0**;
- PRISMS active observations: **0**.

RMIT `103390B` retains `total_indicative` tuition in structured options but deliberately has no annual-sort scalar.

## Determinism / invalidation

Accepted stage hash:

`fb0585a82e9fe5bc43e9d34bb0f55968846fefba3cf5cc7a41cd0523814bfd3d`

- initial dry-run: 33,105 changed;
- APPLY: same stage hash/coverage;
- replay: **0 changed / 33,105 unchanged**;
- controlled derived-hash invalidation on CRICOS `001942A`: exactly **1 changed / 33,104 unchanged**;
- repair APPLY restored idempotency without mutating canonical Layer 1/Layer 2 facts.

An initial hash-envelope implementation caused all-row semantic hash churn and was rejected during UAT. Final stability result:

- searchable enrichment semantic text: **10 Courses**;
- semantic hashes changed: **10**;
- prior semantic hashes retained exactly: **33,095**.

## FTS / vector / hybrid

Representative full-projection FTS:

- `nursing`: 416 matches; top-20 execution ~**11 ms**;
- `IELTS`: 164 matches; top-20 execution ~**3.6 ms**.

Existing vector gate remains unchanged:

- embeddings: **0**;
- active embedding jobs: **0**;
- query embedding cache: **0**;
- hybrid without a vector corpus: `fts_fallback`;
- vector-only: 0 candidates.

No new embeddings were generated and no vector/hybrid production latency/relevance claim is made.

## Consumer / publication isolation

`api.website_course_search_v2` is versioned and exposes regulatory tuition separately from Provider-current tuition plus governed enrichment filters/sorts. Website v1 remains intact.

All **33,105** Search documents remain `unpublished`; Website v2 therefore returns 0 public items in Pilot. Search admission did not broaden publication.

Zoho Consumer Contract v1.3 remains unchanged because no genuine consumer requirement justified new fields and Search state is not canonical presence/publication authority.

## Security / performance

New Search admission relations/functions are private/service-role surfaces with explicit ACLs. The security advisor shows no new warning attributable to this work. The known leaked-password Pilot exception remains separate.

The new source-gate FK advisor finding was resolved with `enrichment_source_gates_source_idx` before closure.

## Live migration ledger

- `20260823015526_m1_search_enrichment_admission`;
- `20260823015929_m1_search_enrichment_semantic_hash_stability`;
- `20260823020120_m1_search_enrichment_source_admission_metadata`;
- `20260823020239_m1_search_enrichment_source_gate_fk_index`.

## Final gate

**PASS — governed Course-Fact Search admission to `course-v3` FTS projection.**

Semantic/vector/hybrid Search remains a separate rejected/not-admitted gate and was not reopened by this change.
