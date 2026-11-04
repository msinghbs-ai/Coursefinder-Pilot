# Course intake Run & Validate — integration handoff

Feature branch: `codex/intake-run-validate-ui`, based on Pilot main `f7e2719e` (v2.15.476). Release integrator: Claude. No release version change, migration, deployment or production action is included.

## Authority and scope

Read [Pilot CLAUDE.md](../CLAUDE.md), the canonical [operating model](https://github.com/msinghbs-ai/coursefinder-admin/blob/main/docs/platform/DATA-PIPELINE-OPERATING-MODEL.md), and [Course Intake Pilot Authority, 4 Nov 20:05](https://github.com/msinghbs-ai/coursefinder-admin/blob/main/docs/platform/2026-11-04-course-intake-pilot-authority-2005.md). Selection remains the existing intake plan: eligible stored official evidence plus approved calendars, most missing fields first, spread over providers and evidence patterns. The browser never ranks or supplies course IDs. It never calls the reader, scheduler or AI controller.

The interface is inside the existing Layer 2/3 Operations screen, using shared UI components, formats and tokens. No new navigation destination is created. The automatic screen inventory retains the existing Operations identity. The integrator should include this purpose in that screen's component-register evidence, using the existing register workflow.

## Backend dependencies — required before operational acceptance

**v2.15.476 alone cannot support this full browser workflow.** Its cohort creator and verifier are private `security` functions, revoked from authenticated users. `public.admin_job_run_now_v1` is the only browser entry. Its creator has neither university scope nor a requested size argument. This PR deliberately does not edit Claude-owned migrations, workers or backend functions. The proposed browser names below are dependencies, not claims that approved/deployed endpoints already exist. The UI fails closed when the bridge is absent or its contract is different.

Reuse the canonical existing plan and fixed cohort tables behind these small bridges; do not build another selector. The backend owner must approve and implement scope/size support alongside the current selection contract. If that extension is not approved, return `blocked_reason` and `next_action`; never pretend a browser filter constrains execution. Do not change the existing global pilot cap from the UI.

### Read bridge

Add an operation to existing `public.admin_read`:

```
p_operation: "intake_run_validate"
p_args: { view: "capabilities" | "preview" | "verify" | "diagnostic", ... }
```

All views require the existing Operations read permission, with server-side cohort visibility checks. No direct grants on pipeline tables or private security functions.

- `capabilities`: `{ contract: "intake-run-validate-v1", can_run: boolean, control_rank: number, min_size: number, max_size: number, default_size: number, scopes: [{id, label}], blocked_reason?: string, next_action?: string, diagnostic?: {approved, read_only, model} }`. Bounds/defaults come from governed settings and current allowance. `max_size` cannot exceed `run_now.pilot_cap`. Scopes come from approved provider identities/groups, including the approved top Australian university scope and individual universities. Do not invent a ranking or hard-code university IDs. `can_run` reflects the caller, catalogue rank, allowlist, pause, switch and current controls; Run Now must still enforce them transactionally.
- `preview`, args `{scope, size}`: read-only plan, same canonical selection rule within approved scope and cap. Return `{token, as_at, expires_at, rule, eligible_courses, courses}`. `courses` uses verifier-compatible shape: `{course_id, provider_id, course_title?, provider_name?, pattern, fills, at_selection: [...]}`. Evidence includes intake ID, before/planned values, course-page quote and URL, calendar ID/URL and start/deadline quotes. Token binds caller, scope, size, plan/evidence snapshot and expiry. It must not be interchangeable across callers. No cohort write, vendor fetch or AI call during preview.
- `verify`, args `{cohort_id}`: read-only wrapper of `security.run_now_cohort_verify_v1(uuid)`, with access check. Preserve its exact `courses`, `totals`, `runs` fields; add `as_at`, optionally `verdict` and `next_action`. No inferred success when Website or Zoho is absent/unsupported. Do not equate `zoho_checked` with matching intake values. Existing verifier counts are intake rows, not necessarily distinct newly filled scalar fields; final pilot acceptance belongs to the backend/integrator and is not computed by this UI. Verification covers values since cohort creation, so scheduled processing may also contribute; it is not proof that every change came from a particular Run Now.
- `diagnostic`, args `{cohort_id}`: optional. Advertise only for an already approved pinned model with an existing read-only diagnostic backend and authorised caller. Read existing diagnostic output, honour normal visibility/spend controls, return model/evidence/findings. Never route to a model or controller from this UI. Without all three capability flags (`approved`, `read_only`, `model`) the button is absent. No diagnostic backend was found in the base contract; disabled by default.

### Audited fixed-cohort preparation bridge

Proposed `public.admin_intake_cohort_prepare_v1(p_scope text, p_size integer, p_reason text, p_preview_token text) returns jsonb`.

Require authenticated caller, catalogue control rank, nonempty reason, server-side bounds and approved scope. Verify token ownership, expiry and unchanged selection/evidence. Delegate to the canonical cohort mechanism; no arbitrary course IDs or SQL. Repeated preparation with the same valid token must return the same cohort. Return `{cohort_id, preview_token}`. If data changed, refuse and require a new preview, rather than replacing the operator's preview silently. Record requester/reason/rule/denominator/evidence using the existing audit/cohort mechanism. Preparation fixes selection only; no intake, admission or publication write.

### Existing Run Now (unchanged)

```
public.admin_job_run_now_v1(
  p_job: "intake-dates-apply",
  p_reason: <fixed audited reason>,
  p_args: { cohort_id, idempotency_key }
)
```

Server retains rank, catalogue, allowlist, pause, switch, cap, lock, idempotency, spending and audit authority. No direct per-course SQL. This is synchronous in v2.15.476: UI shows an indeterminate wait and reported final counts/timestamps; it does not fabricate a progress percentage or promise cancellation. A failed HTTP response can mean the transaction committed: recovery retains the same key, cohort and reason. No automatic resubmission or retry loop. After navigation, operators can reopen verification with the cohort UUID. Request-key recovery is only within the mounted page; after navigation verify the existing cohort/audit first, never create a replacement run to discover its outcome.

## Validation and UI evidence

Focused local browser tests use an injected fixture client with synthetic data, never a production session. They exercise size bounds, selection invalidation, fixed cohort and reason, one run, read-only role, unavailable bridge, absent AI option, unknown-result key reuse, refusals, evidence/read-back and phone layout. Screenshots are fixture evidence, not production proof. The adapter contract test intercepts local example Supabase HTTP and checks the exact governed RPC payload. Test register is regenerated under `docs/platform/TEST-REGISTER.md` for integration into the canonical Admin register.

Local results, 4 Nov 2026: **16 tests passed** (6 UI/adapter tests including phone, 4 existing intake backend source contracts, 6 existing test-governance guards). Commands:

```
npx playwright test tests/uat/intake-run-validate-ui.spec.mjs tests/uat/cf-247-s286-intake-pilot-run-now-contract.spec.mjs tests/uat/cf-247-s120-test-governance-contract.spec.mjs --reporter=list
npm run build
npm run ui:tokens
node scripts/test-register.mjs > docs/platform/TEST-REGISTER.md
git diff --check
```

Build (including unchanged v2.15.476 release contract), token guard, register generation and whitespace checks passed. Build reports the repository's existing shared static/dynamic Supabase import warning. No live/backend execution or production verification was performed. Screenshots: `docs/ui-evidence/intake-desktop.png`, `docs/ui-evidence/intake-phone.png`.

## Manual acceptance after backend integration

1. Open Layer 2/3 → Operations as a read-only operator: inspect preview/evidence; prepare and Run Now remain disabled. Confirm the server also denies unauthorised RPC calls.
2. As an authorised operator, select the approved top Australian scope or an individual university and a size within server bounds. Preview: confirm course identity, official stored page/calendar quotes, before/planned values, denominator and rule. Change scope/size and confirm a fresh preview is required.
3. Give a reason and fix the previewed cohort. Confirm server rejects expired/changed/cross-user tokens, and repeated preparation is idempotent. Record cohort ID. Confirm scope/size/reason cannot change after fixation.
4. On an authorised nonproduction environment, Run Now once. Confirm job identity and existing rank/pause/switch/cap/lock/budget controls, requester/reason/run ID/timestamps and processed/admitted/skipped/failed counts in the existing audit/task record. Test paused and duplicate-in-flight refusals. No vendor call should be triggered by the stored-evidence job.
5. Verify: compare fixed selection, new values, current catalogue, official quotes, Website v2 read-back and Zoho where supported. Treat null, missing, error and mismatch as unverified. Do not manufacture the target by replacing courses. Integrator records PASS/FAIL/BLOCKED against the exact denominator.
6. Simulate a dropped response: verify cohort/audit first, then recover only the same request key if necessary. Reload and read an existing cohort by UUID. Check failed/refused reasons and permitted follow-up through existing controls.
7. Repeat on a phone: form controls, actions and before/after values remain usable without horizontal page scrolling. Confirm AI option is absent without an approved read-only capability.

## Risks and expected production outcome

The UI is integration-ready with a hard backend dependency, not production-qualified. Until bridges exist, Operations shows a clear blocked message and starts no job. Once the backend owner supplies the approved bridges, operators can preview and fix a bounded automatically selected cohort, execute the existing governed job, and inspect evidence-backed catalogue and publication results. No extraction, scheduler, controller, consumer API or release behaviour is changed. Operational risks are stale preview/evidence, synchronous request timeout, unavailable/lagging publication, and scheduled activity during verification; server checks and explicit unknown/blocked states retain those distinctions.
