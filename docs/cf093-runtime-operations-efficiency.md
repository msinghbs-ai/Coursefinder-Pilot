# CF-093 follow-on — Scheduled Tasks runtime operations and efficiency

Canonical work item: Coursefinder-Pilot #74

This follow-on starts after merged PR #72. PR #72 and all applied migration identities remain immutable. This work does not reopen or rewrite accepted migration history.

## Objective

Move Scheduled Tasks from functional acceptance into measurable operational maturity. The platform must show how scheduled and on-demand work behaves at runtime, collect enough evidence to identify bottlenecks, and permit tuning only from observed governed data.

## Required runtime measures

For the most recent governed jobs and, where available, per policy/provider/scope:

- queue wait: created/queued to started
- execution duration: started to completed/failed/cancelled
- processed item count and effective items/minute
- accepted/applied, rejected/failed and unresolved counts
- discovery workload versus already-queueable deterministic Layer 2 workload
- retry/attempt count and retry exhaustion
- same-token/recent-dispatch dedupe rate
- completion/failure class distribution
- Evidence produced per job and accepted Evidence yield where exposed by governed contracts
- bounded target size and profile/provider identity
- operator-visible last success, last failure and current active request

Metrics are observational. Missing values must remain unknown; do not infer or manufacture runtime values.

## Operator experience

Scheduled Jobs remains the primary run-control surface. Runtime maturity should add:

1. a compact health summary derived from real recent Jobs/Evidence;
2. per-task recent run status and duration/throughput where data exists;
3. direct Jobs and Evidence cross-links for diagnosis;
4. clear failure/retry/dedupe classifications;
5. a distinction between scheduler delay, acquisition/discovery time and deterministic Layer 2 processing time when the runtime exposes those phases;
6. safe filters/search for policy, country, provider, layer, state and failure class;
7. no automatic tuning action from the UI without the existing governed edit/run authority.

## Efficiency tuning rules

Tuning is evidence-led and forward-only.

Permitted candidates, only when already exposed by governed configuration and supported by acceptance evidence:

- bounded worker chunk/batch size
- provider/profile concurrency
- retry interval/attempt bounds
- dispatch cadence/freshness scheduling
- query/index improvements for Jobs/Evidence/policy reads
- dedupe windows where replay evidence proves a safe adjustment

Do not invent routes, source profiles, execution policies, URLs, provider capabilities or runtime credentials to improve a metric.

Every material tuning change must record before/after measurements on comparable bounded targets. Prefer UQ and RMIT only when they are currently policy-qualified and executable; otherwise choose another genuinely governed target.

## Governance boundaries

Preserve:

- Layer 1 identity/regulatory authority
- deterministic, Evidence-preserving Layer 2
- exact Preview/binding/token/fingerprint/identity provenance
- Layer 3 Evidence/profile/model/revalidation governance
- Layer 4 human resolution
- Search/Publication separation
- rank/ACL/private-helper/service-role boundaries
- fail-closed generic async discovery outside specifically governed Preview-bound continuations

No generic Layer 3/4 execution or implicit Search/Publication side effect may be introduced by runtime optimisation.

## Acceptance sequence

### Gate A — Baseline

- capture recent scheduler/Jobs runtime measurements without changing behaviour
- identify missing observability fields separately from performance defects
- establish at least one bounded policy-qualified Layer 2 target for repeatable comparison

### Gate B — Operational visibility

- Scheduled Jobs shows real recent job health/duration/result information
- Jobs/Evidence remain the detailed truth surfaces
- missing metrics fail closed to `unknown`, never synthetic values

### Gate C — Measured tuning

For each proposed tuning change:

1. record baseline target, scope and measurements;
2. apply the smallest governed forward-only change;
3. run targeted tests;
4. run the same or equivalent bounded target;
5. compare latency, throughput, retries, dedupe and Evidence yield;
6. retain the change only when governance and operational evidence support it.

### Gate D — Closure continuity

The outstanding CF-CHG-20260910-093 closure remains distinct from this performance work. Replacement UQ then RMIT consequential acceptance is still required if those targets remain legitimately governed. Codex review is a deferred assurance item; Gitar is the active PR reviewer until Codex usage becomes available again.

## First implementation increment

Start with read-only observability using data already returned by governed Jobs/policy/Evidence interfaces. Do not add database writes or tune concurrency/batch/retry values in the first increment. This gives a trustworthy baseline before optimisation.
