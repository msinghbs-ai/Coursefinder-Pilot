# M1-SEARCH-ENRICHMENT — Governed Course-Fact Search Admission UAT

**Date:** 23 August 2026  
**Change Control:** `CF-CHG-20260823-023`  
**Target:** CourseFinder Pilot Supabase `fxcwkweaxjtknorudmwp`  
**Result:** PASS for governed Course-Fact admission to FTS projection; vector/hybrid remain NOT ADMITTED under the existing M1-SEARCH-VECTOR rejection.

## Governing outcome

The accepted Search projection is advanced from `course-v2` to `course-v3` without changing Provider/Course identity or publication state.

Search admission remains source/domain gated. Canonical relational presence alone is insufficient.

## Search semantics

| Domain | Search representation | Filter | Sort | Display | Decision |
| --- | --- | --- | --- | --- | --- |
| CRICOS registered tuition | `regulatory_tuition_state/amount/currency/basis` | state/amount capable | amount | yes | admitted as Layer 1 registered-total-course fact; never labelled Provider-current/annual |
| Provider-current tuition | `has_provider_current_tuition`, structured `provider_tuition_options`, comparable annual scalar only for `annual`/`indicative_annual` basis | presence / annual max | annual scalar only | full options | admitted only for Search-approved qualified first-party sources |
| Official Course URL | `official_course_url` | presence | no | yes | admitted only from Search-approved first-party source |
| Intake | repeating `intake_options`, `earliest_intake_date`, `has_intake` | presence | earliest future intake | full options | repeating/campus grain preserved |
| English requirement | repeating `english_requirement_options`, `has_english` | presence | no | full options | no cross-test scalar sort because tests/components are not equivalent |
| Scholarship | repeating `scholarship_options`, `has_scholarship` | presence | no | full options | existing scholarship gate retained; unpublished canonical Scholarships do not enter Search |
| QILT | none | no | no | no | blocked: no accepted live outcome observations and provider/study-area grain is not coerced to Course grain |
| PRISMS | none | no | no | no | blocked: no accepted live flow observations and cohort/flow grain is not coerced to Course grain |

Legacy `has_fee` now means **Search-admitted Provider-current tuition presence**. It no longer conflates CRICOS regulatory fee rows with Provider-current tuition.

## Source admission

Search source gates were approved only for the already-qualified first-party Course Facts sources:

- `au_rmit_official_course_pages`;
- `au_uq_official_program_pages`.

The deferred QUT source is not admitted.

## Coverage after APPLY

- Search Course Documents: **33,105**;
- CRICOS registered tuition `present`: **26,326**;
- CRICOS registered tuition `zero`: **131**;
- CRICOS registered tuition `source_null`: **191**;
- CRICOS registered tuition `not_applicable` (NZ): **6,457**;
- Provider-current tuition: **10 Courses**;
- comparable annual/indicative-annual Provider tuition scalar: **9 Courses**;
- official Course URL: **10 Courses**;
- Intake: **10 Courses / 18 intake observations**;
- English: **10 Courses / 32 requirement observations**;
- admitted Scholarships: **0** because current canonical Scholarship rows remain unpublished;
- QILT active observations: **0**;
- PRISMS active observations: **0**.

The RMIT `103390B` Provider tuition is retained as `total_indicative` in structured options but deliberately has no annual-sort scalar.

## Deterministic projection UAT

Initial dry-run:

- rows: 33,105;
- changed: 33,105;
- stage hash: `fb0585a82e9fe5bc43e9d34bb0f55968846fefba3cf5cc7a41cd0523814bfd3d`.

APPLY:

- rows: 33,105;
- same coverage;
- same stage hash.

Immediate replay dry-run:

- changed: **0**;
- unchanged: **33,105**;
- stage hash unchanged.

Invalidation test:

- derived enrichment hash for CRICOS `001942A` was deliberately replaced with a UAT-invalid value;
- next dry-run detected exactly **1 changed / 33,104 unchanged**;
- APPLY repaired the row;
- canonical Layer 1/Layer 2 facts were not modified.

## Semantic-hash stability UAT

The first implementation attempt changed every semantic hash due to a hash-envelope shape change. This was rejected during UAT and corrected before closure.

Final result:

- Courses with new searchable enrichment semantic text: **10**;
- semantic hashes changed: **10**;
- semantic hashes retained exactly: **33,095**.

This proves vector freshness invalidation is scoped to genuinely changed semantic content rather than projection-version churn.

## FTS / vector / hybrid behaviour

Post-enrichment GIN/FTS benchmark on full 33,105-document projection:

- `nursing`: 416 matches; top-20 execution approximately **11 ms**;
- `IELTS`: 164 matches; top-20 execution approximately **3.6 ms**.

The vector gate remains unchanged from `docs/coursefinder-m1-search-vector-uat-v1.0.md`:

- accepted embeddings: **0**;
- active embedding jobs: **0**;
- query embedding cache rows: **0**;
- keyword request returns keyword candidates;
- hybrid request without an admitted vector corpus returns `fts_fallback`;
- vector-only request returns zero candidates.

No new embeddings were generated because the previous vector candidate was explicitly rejected. No production vector/hybrid latency or relevance claim is made.

## Consumer contracts

### Website

A versioned `api.website_course_search_v2` contract was added. It exposes separate regulatory and Provider-current tuition objects plus admitted Course URL/intake/English/Scholarship structures and governed filters/sorts.

Current Search publication state remains **33,105 unpublished**. Website v2 therefore returns zero published items, proving Search admission did not broaden Website publication.

Website v1 remains intact.

### Zoho

No Zoho business DTO was changed. Existing Zoho contract v1.3 already states that Search admission is not canonical presence/publication authority. There is no genuine current consumer requirement that justifies adding these Search fields to Zoho.

## Security / performance

New Search admission relations/functions are private/service-role surfaces with explicit revoke/grant controls. No browser direct CRUD surface was opened.

Supabase security advisor shows no new warning attributable to this work. Existing programme-wide RLS informational findings and the known leaked-password-protection Pilot exception remain outside this lane.

Performance advisor identified the new source-gate FK as initially uncovered; `enrichment_source_gates_source_idx` was added before closure.

## Live migrations

- `20260823015526_m1_search_enrichment_admission`;
- `20260823015929_m1_search_enrichment_semantic_hash_stability`;
- `20260823020120_m1_search_enrichment_source_admission_metadata`;
- `20260823020800_m1_search_enrichment_source_gate_fk_index`.

## Final gate

**PASS — governed Course-Fact Search admission to `course-v3` FTS projection.**

Semantic/vector/hybrid Search remains a separate rejected/not-admitted gate and was not silently reopened by this change.
