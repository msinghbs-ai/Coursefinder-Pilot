# CourseFinder PIM Admin v2.15.72 — Compare recovery candidate

Date: 7 Sep 2026
Status: **CANDIDATE — NOT RELEASED / NOT ACCEPTED**

This record documents the requested fixes intended to become v2.15.72 only after exact deployed Compare UAT passes. The visible application version remains v2.15.71 while this candidate is under acceptance.

## Triggering failed evidence

Exact deployed Compare run `34068278250` at commit `f11cbefcf81bfb1da24e198e10cf1ce190bd3bd0` completed **FAILURE**.

Observed results:

- Provider comparison: FAIL — selected Provider cards rendered, but no `.cf-compare-value` metric cells were present.
- Provider-first Course comparison: PASS.
- Course detail QILT Provider context → Course comparison: FAIL — UAT required a National benchmark label based on an item outside the five QILT cards actually rendered.
- Retry also observed HTTP 500 responses from `dashboard` and `layer_status_summary`; the backend functions were subsequently rechecked directly under a rank-1-compatible session and now execute successfully.

## Root causes

### 1. Compare opened an impossible default QILT category/year combination

The Compare workspace defaults to `Current student experience`, but the QILT year selector is derived globally across every outcome category. The newest global year is 2025, while the available Current student experience observations for the selected recovery Providers are 2024. The initial state therefore rendered the correct empty-state message rather than metric cells.

CF-233 adds a bounded recovery that moves from the global-newest year to the next retained year only when:

- the route is Compare;
- governed entities have already been selected;
- the active QILT comparison contains no aligned rows;
- the selected year is still the first/global-newest option.

It does not invent statistics, change canonical data, or override an operator's later explicit historical-year choice.

Implementation commits:

- `73101f14fc433c2ea6f53cd4c2f2305b5ad8ddf5` — add bounded category/year Compare recovery.
- `af02ac31fdd74078601b6b9d6d556ef397445b3c` — load the Compare recovery module in the Pilot shell.

### 2. Benchmark UAT inspected more rows than the UI renders

`ContextualInsights` intentionally renders the first five governed QILT outcome cards. The prior test checked `national_benchmark` across the complete returned outcome list, which could require a benchmark label for an observation that was not rendered.

The corrected acceptance contract now checks benchmark presence against the same first five visible outcome items and still rejects fabricated `National benchmark 0` output.

Implementation commit:

- `259d0b774047644ec8ba189be967cc77b591ff7e` — align deployed UAT with the visible governed QILT cards.

### 3. Layer Status 500 correction

`security.admin_layer_status_summary()` previously called a curator-only Layer 3 helper while the summary itself is authorised for lower-ranked assigned operators. The nested helper was replaced by an aggregate that preserves the summary boundary without exposing curator detail.

Runtime migration and repository record:

- `44a96c1ac94fbb61d8960ef310f41ad19e6b661f` — role-safe Layer Status summary correction.

Direct post-fix database execution confirmed both `security.admin_layer_status_summary()` and `security.admin_dashboard_maturity()` execute successfully under an assigned rank-compatible session. This does not substitute for deployed browser UAT; the exact rerun must still show no HTTP 5xx responses.

## Acceptance required before v2.15.72 promotion

The exact deployed CF-061 Compare suite must pass all three tests with no unexpected HTTP 5xx responses:

1. Provider comparison with aligned QILT rows, PRISMS context, theme and responsive behaviour.
2. Provider-first Course comparison across governed universities.
3. Course detail QILT Provider context opening Course comparison without fabricated benchmark semantics.

Only after this gate passes should the visible release authority be advanced from v2.15.71 to v2.15.72 and the final deployed PASS run ID be added to this record.
