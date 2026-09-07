# CourseFinder PIM Admin v2.15.72 — Compare recovery

Date: 7 Sep 2026  
Status: **ACCEPTED / RELEASE PROMOTED**

This release closes the Compare recovery after exact deployed targeted acceptance passed and then promotes the visible Pilot currentness from v2.15.71 to v2.15.72.

## Triggering failed evidence

Exact deployed Compare run `34068278250` at commit `f11cbefcf81bfb1da24e198e10cf1ce190bd3bd0` completed **FAILURE**.

Observed results:

- Provider comparison: FAIL — selected Provider cards rendered, but no `.cf-compare-value` metric cells were present.
- Provider-first Course comparison: PASS.
- Course detail QILT Provider context → Course comparison: FAIL — UAT required a National benchmark label based on an item outside the five QILT cards actually rendered.
- Retry also observed HTTP 500 responses from `dashboard` and `layer_status_summary`.

## Root causes and accepted fixes

### 1. Compare default QILT category/year alignment

The Compare workspace defaults to `Current student experience`, but the QILT year selector is derived globally across every outcome category. The newest global year was 2025, while the available Current student experience observations for the selected recovery Providers were 2024. The initial state therefore rendered a valid empty state rather than metric cells.

CF-233 adds a bounded recovery that moves from the global-newest year to the next retained year only when:

- the route is Compare;
- governed entities have already been selected;
- the active QILT comparison contains no aligned rows;
- the selected year is still the first/global-newest option.

It does not invent statistics, change canonical data, or override an operator's later explicit historical-year choice.

Implementation commits:

- `73101f14fc433c2ea6f53cd4c2f2305b5ad8ddf5` — bounded category/year Compare recovery.
- `af02ac31fdd74078601b6b9d6d556ef397445b3c` — load the Compare recovery module in the Pilot shell.

### 2. Benchmark UAT inspected more rows than the UI renders

`ContextualInsights` intentionally renders the first five governed QILT outcome cards. The prior test checked `national_benchmark` across the complete returned outcome list, which could require a benchmark label for an observation that was not rendered.

The corrected acceptance contract checks benchmark presence against the same first five visible outcome items and still rejects fabricated `National benchmark 0` output.

Implementation commit:

- `259d0b774047644ec8ba189be967cc77b591ff7e` — align deployed UAT with the visible governed QILT cards.

### 3. Layer Status 500 correction

`security.admin_layer_status_summary()` previously called a curator-only Layer 3 helper while the summary itself is authorised for lower-ranked assigned operators. The nested helper was replaced by an aggregate that preserves the summary boundary without exposing curator detail.

Runtime migration and repository record:

- `44a96c1ac94fbb61d8960ef310f41ad19e6b661f` — role-safe Layer Status summary correction.

Direct post-fix database execution confirmed both `security.admin_layer_status_summary()` and `security.admin_dashboard_maturity()` execute successfully under an assigned rank-compatible session.

## Exact acceptance evidence

Exact deployed Compare recovery run:

- Run: `34068759607`
- Commit: `7c3022e72df0fcd6fcb0d312d106bb9349d3f6c2`
- Workflow: `CourseFinder Deployed UAT`
- Tier: targeted
- Result: **SUCCESS**
- Suite: `tests/uat/cf-061-qilt-prisms-comparison-deployed.spec.mjs`
- Result: **3 passed in 25.6s**

Passing tests:

1. Provider comparison aligns QILT cards for two selected universities — PASS.
2. Course comparison can select any university before choosing courses — PASS.
3. Course detail keeps QILT as Provider context and opens Course comparison — PASS.

The run retained UAT evidence artifact `coursefinder-targeted-34068759607-1` / artifact ID `9999790915`.

Mobile workflow execution was skipped because this was the targeted tier. The provider comparison test itself includes an explicit 390×844 responsive viewport assertion, but this does not substitute for a later nominated mobile acceptance tier.

## v2.15.72 promotion

After the functional Compare gate passed, CF-234 promoted the visible release currentness:

- `51c50d161705ab079b2d7204eb502826ecaf2597` — release currentness authority to v2.15.72 with accepted Compare release notes.
- `2551bc883c16c4f043145cb1961566c3c78bed64` — browser title to v2.15.72.
- `e205bc693c565f84f091de7745a613a09d00170a` — exact Compare deployed test now requires v2.15.72 currentness for the promotion proof.

`src/release-currentness-entry.js` remains the deployed visible-currentness reconciler for browser title, release badge, login/version labels and release-note insertion. `src/mature-main.jsx` still contains the older bootstrap `UI_VERSION` constant and is overridden by the reconciler after shell render; this remaining bootstrap-version duplication is recorded as technical debt and must be normalised in a later bounded refactor rather than hidden.

## Semantic boundary

This release does **not** change:

- Layer 1 identity or source authority;
- QILT/PRISMS source grain;
- ranking canonical semantics;
- Publication/Search admission;
- Website or Zoho contracts;
- private Evidence/Storage boundaries.

## Rollback

If promotion currentness must be reverted, revert the v2.15.72 currentness/title/test-promotion commits while retaining the accepted CF-233 functional fixes unless a separate regression proves those fixes defective.
