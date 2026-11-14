# AI call paths (13 November 2026)

Platform Admin review 13 Nov 2026 22:10, item 5. This lists every place the platform calls a model, where the model comes from, and what is left
outside the routes. Line numbers are for worker `coverage-sweep-worker-v0.98.0` (CF-247 R7, branch `cf-247-r7-firecrawl-one-client`; first written for v0.86.0 on branch
`cf247-ai-models-services`); the test `cf-247-ai-models-services-contract` fails if a worker call is not listed here at its line.

## 1. Who calls OpenRouter

Two edge functions call a model (searched: every `.ts` file under `supabase/functions` for `openrouter.ai/api`, `chat/completions` and `base_url`):

- `coverage-sweep`, the worker: every reading call (section 2). The other files of the worker that mention OpenRouter (`aer-v2.ts`, `answer.ts`,
  `course-entry.ts`, `course-text.ts`, `description.ts`, `entry.ts`, `ops-diagnose.ts`) build or read requests; the call itself is always made in
  `index.ts`, through `cascade.ts`.
- `layer3-provider-control`, action `verify_credential` (Platform Admin only): the key check sends one 8-token call ("Reply with exactly OK.") with
  the model of the chosen Layer 3 profile, to the profile's `base_url`. Round 2 of this document said only the worker calls a model; that was
  wrong. From round 5 the function asks `public.svc_ai_model_allowed_v1` first and refuses a profile whose model is not on the allowed list
  (`model_not_allowed`), names no model itself, and records the call in `pipeline.ai_invocations` under service `key_verify` (it has no route,
  no cap and no cascade: one call for each press of Verify).

Two calls are not model calls: the balance read (`index.ts:748`, `GET /credits`, job `openrouter-balance`, every 15 minutes) and the price list
(`index.ts:3037`, `GET /models`, used to reserve a price for a provider description).

## 2. Every model call in the worker

All sixteen go through `cascadeFetch` (`cascade.ts`), which keeps one row per attempt in `pipeline.ai_invocations`. The model is never named in the
worker: each reader hands it out from `security.ai_route_v1(<service>)`.

| Call | Worker mode | Database reader that hands out the model | Service (route) | State | How the model is used |
|---|---|---|---|---|---|
| `index.ts:2160` | `scholarship_ai` | `public.svc_scholarship_ai_next` | scholarship_extraction | `routed` | the database escalation chain (the route's cascade); the call names one model. From v0.97.0 each read is first judged by the pre-AI admission gate, in shadow (section 2a), and each attempt names its queue item in `pipeline.ai_invocations` |
| `index.ts:2276` | `scholarship_recheck` | `public.svc_scholarship_recheck_next` | scholarship_extraction | `routed` | worker cascade |
| `index.ts:2318` | `scholarship_eligibility` | `public.svc_scholarship_eligibility_next` | scholarship_eligibility | `routed_single` | one model |
| `index.ts:2376` | `ops_diagnose` | `public.svc_ops_diagnosis_next` | ops_diagnosis | `routed_single` | one model (pinned on the request at lease) |
| `index.ts:2429` | `aer_v3_eval` (entry requirements v3 benchmark, v0.93.0; failed-quote diagnostic v0.94.0; each wait bounded by the time left, v0.96.0) | `public.svc_aer_v3_eval_next_v1` (the candidate instruction version of an opened `pipeline.ai_eval_runs` run) | entry_requirements_v2_shadow (the route the candidates are measured for; spend capped by `ai_eval.aer_v3_max_usd`) | `evaluation` | one pinned candidate model with its provider pins, never the cascade: the benchmark is how a model earns a qualification on the route, so the model comes from the candidate version, not from `security.ai_route_v1`; behind `ai_eval.offline_runs_on` and `ai_eval.aer_v3_runs_on`; no job fires it |
| `index.ts:2490` | `ops_diagnose (entry requirements v2 trial)` | `public.svc_aer_v2_shadow_next, security.aer_v2_shadow_hold_v1` | entry_requirements_v2_shadow | `routed` | worker cascade; one model only when the version pins its providers (v0.89.0, #1137 routing) |
| `index.ts:2551` | `lean_qualify` (Lean AI Input 1b-3 fees and intakes qualification, v0.95.0; ships off, US$2.00 ceiling, nothing admitted) | `public.svc_lean_qualify_next_v1` | fee_reader (fees), course_other_fields (intakes) | `routed` | worker cascade |
| `index.ts:2624` | `central_ai (calendar, sliced read)` | `public.svc_central_ai_next` | calendar_reading (kind intake_calendar) | `routed` | worker cascade |
| `index.ts:2640` | `central_ai` | `public.svc_central_ai_next` | central_english_policy or calendar_reading, by the item's kind | `routed` | worker cascade |
| `index.ts:2924` | `entry_ai` | `public.svc_entry_matrix_next` | entry_matrices | `routed_single` | one model |
| `index.ts:2990` | `fee_ai` | `public.svc_fee_ai_next` | fee_reader | `routed` | worker cascade |
| `index.ts:3139` | `provider_description` | `public.svc_provider_description_lease_v1, public.svc_provider_description_next, public.svc_provider_description_reserve_v1` | provider_description | `routed_single` | one model (a price is reserved for that model) |
| `index.ts:3193` | `enrich_ai (course fields: ask)` | `public.svc_enrich_ai_next` | course_other_fields | `routed` | worker cascade |
| `index.ts:3217` | `enrich_ai (description and deadline: askText)` | `public.svc_enrich_ai_next` | course_description (description), course_other_fields (deadline) | `routed` | worker cascade |
| `index.ts:3245` | `enrich_ai (entry requirements)` | `public.svc_enrich_ai_next` | course_entry_requirements | `routed` | worker cascade |
| `index.ts:3543` | `ai_match` | `public.svc_coverage_ai_match_next` | course_matching | `routed` | worker cascade |
| `index.ts:3680` | `adapter_propose` | `security.adapter_builder_model_for_v1 (through public.svc_adapter_draft_get)` | adapter_builder | `routed_single` | one model |

State: `routed` means the route's cascade is executed (a later model is asked only on a technical failure). `routed_single` means the route
chooses the model but the call uses one model; Models & services shows one model and refuses a second one for these. `not_migrated` is
`page_identity` only: it has a route and a prompt (`pageid.ts`) but the worker makes no call for it (qualification only; no job).

## 2a. The pre-AI admission gate in front of `scholarship_ai` (shadow, v0.97.0)

Decision 278 (Platform Admin 14 Nov 2026 16:10); design admin `docs/audits/studysearch-pre-ai-admission-gate-design.md`; module
`supabase/functions/coverage-sweep/admission-gate.ts` (`pre-ai-admission-v1`); migration `20261114101500_cf247_pre_ai_admission_shadow.sql`.

- **Where it sits.** In mode `scholarship_ai`, after the page (stored copy or a fresh read) and its linked eligibility page (a direct read, no
  credit) are in hand and before the paid call at `index.ts:2160`. It never fetches anything, never calls a model and changes no request. An error
  inside the gate is counted (`gate_error`) and the read goes ahead.
- **Switches.** It runs only while `admission.gate_on` is 1 (ships 0). A reason stops a read only while its `admission.enforce.<reason>` is 1
  (eleven switches, all ship 0). `scholarship_low_signal` has no switch and is never enforced (Decision 278 D2: measured only). A park
  (`duplicate_input`, `over_budget_split`) is never enforced in this lane: there is no route for parked items yet, so an enforced park would be a
  silent drop. With the shipped settings the call is exactly as before. A read stopped by an enforced reason records the error
  `rejected_admission: <codes>` naming only the enforced reject codes: never a shadow (measurement) code and never a park code.
- **What it records.** One row per judged read in `pipeline.pre_ai_admission_decisions` (through `public.svc_pre_ai_admission_record_v1`, once at
  the end of the worker call; a failure to record never fails the call): the decision, what it would do with every reason enforced, the reason
  codes, the estimated tokens a rejection would save, the input hash and the fingerprint. Report: `security.pre_ai_admission_report_v1(hours)`.
- **Fingerprint.** `input_sha256` covers the stored copy's content hash (taken over its decompressed bytes, before decoding), the text the gate
  selected, the linked eligibility page's hash (the answer's `bundle.linked_sha256`) or `none`, and the request context (provider, country,
  currency, a recovery item's award name and section). The fingerprint adds the gate version, lane, prompt version and prompt-text hash, model and
  answer shape. A changed, added or removed linked page is a different input, so it never counts as `duplicate_input`.
  `public.svc_pre_ai_admission_seen_v1` says which fingerprints already have a recorded answer.
- **Cost of a paid answer whose record failed (R5).** Every attempt of this call names its queue item (`source` = `scholarship_ai_queue`,
  `source_id` = the queue id) in `pipeline.ai_invocations`, which the worker writes once at the end of the call through
  `public.svc_ai_model_answered_v1`, outside the queue and extraction tables. The fallback record (`errorCost(e) || spent`) goes to the same
  `svc_scholarship_ai_record`, which locks the same queue row, so it can fail again for the same reason; it is then counted as `record_failed` and
  never fails the batch, and the cost is still in `pipeline.ai_invocations`.
- **Not in front of any other call yet.** `enrich_ai` and `aer_v2_shadow` come after the Lean AI Phase 1 observations (design section 8 step 4),
  each a separate approval.

## 3. The two old model settings

Readers found on the live database by searching every function's text (13 Nov 2026):

| Setting | Read before this change | Read after this change |
|---|---|---|
| `pipeline` / `entry.matrix_model` | `public.svc_enrich_ai_next`, `public.svc_entry_matrix_next` | none |
| `pipeline` / `ops.ai_diagnosis_model` | `public.svc_ops_diagnosis_next`, `public.admin_provider_description_run_v1` | none |

Two screens showed a model from the old places without choosing one (display only); from round 5 both show the route's model: `public.admin_adapter_autobuild` (it showed the setting `firecrawl.builder_model`; now the `adapter_builder` route) and `public.admin_enrich_fields` (it showed `pipeline.central_ai_settings`; now the `course_other_fields` route).

`public.admin_provider_description_run_v1` was found in round 4 (it was not in the earlier list). It asked the setting whether a diagnosis model
exists and wrote the setting's value on a queued diagnosis request; the reader replaced that value at lease, so no call used it. It now asks the
route (`security.ai_route_v1('ops_diagnosis')`), and its "model" for provider descriptions is the provider description route's. The check after
the change was made on a copy of the live schema with the five migrations applied: the only function whose text still holds either key is
`security.ai_settings_not_read_v1`, which lists them as not read. Both settings keep their rows and values; nothing is deleted.

The worker does not read either setting (searched `supabase/functions` for `matrix_model` and `ai_diagnosis_model`: comments only).

## 4. Layer 3

Layer 3 (routing profiles, `pipeline.layer3_model_profiles`) made its last model call on 11 October 2026 and has no scheduled job. It is reported
on Models & services (`legacy.layer3`) and is not wired to the routes. The worker still asks `layer3_routing_profile_service` and
`layer3_provider_credential_resolve_service` for the OpenRouter credential (the key), not for a model.

## 5. Not verified

- The worker was bundled and its cascade and attempt record were run with a scripted fetch; it was not type-checked with Deno and not deployed.
- `layer3-provider-control` was bundled for syntax only; its new check and record were not run and it was not deployed. It must be deployed after migration 20261113390000 (it calls `svc_ai_model_allowed_v1`).
- The "after" column of section 3 was verified on a copy of the live schema, not on live: nothing has been applied to live.
