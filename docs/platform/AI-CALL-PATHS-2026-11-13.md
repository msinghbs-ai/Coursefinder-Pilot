# AI call paths (13 November 2026)

Platform Admin review 13 Nov 2026 22:10, item 5. This lists every place the platform calls a model, where the model comes from, and what is left
outside the routes. Line numbers are for worker `coverage-sweep-worker-v0.86.0` on branch `cf247-ai-models-services`; the test
`cf-247-ai-models-services-contract` fails if a worker call is not listed here at its line.

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

Two calls are not model calls: the balance read (`index.ts:738`, `GET /credits`, job `openrouter-balance`, every 15 minutes) and the price list
(`index.ts:2853`, `GET /models`, used to reserve a price for a provider description).

## 2. Every model call in the worker

All fifteen go through `cascadeFetch` (`cascade.ts`), which keeps one row per attempt in `pipeline.ai_invocations`. The model is never named in the
worker: each reader hands it out from `security.ai_route_v1(<service>)`.

| Call | Worker mode | Database reader that hands out the model | Service (route) | State | How the model is used |
|---|---|---|---|---|---|
| `index.ts:2120` | `scholarship_ai` | `public.svc_scholarship_ai_next` | scholarship_extraction | `routed` | the database escalation chain (the route's cascade); the call names one model |
| `index.ts:2230` | `scholarship_recheck` | `public.svc_scholarship_recheck_next` | scholarship_extraction | `routed` | worker cascade |
| `index.ts:2272` | `scholarship_eligibility` | `public.svc_scholarship_eligibility_next` | scholarship_eligibility | `routed_single` | one model |
| `index.ts:2330` | `ops_diagnose` | `public.svc_ops_diagnosis_next` | ops_diagnosis | `routed_single` | one model (pinned on the request at lease) |
| `index.ts:2378` | `ops_diagnose (entry requirements v2 trial)` | `public.svc_aer_v2_shadow_next, security.aer_v2_shadow_hold_v1` | entry_requirements_v2_shadow | `routed` | worker cascade; one model only when the version pins its providers (v0.89.0, #1137 routing) |
| `index.ts:2453` | `central_ai (calendar, sliced read)` | `public.svc_central_ai_next` | calendar_reading (kind intake_calendar) | `routed` | worker cascade |
| `index.ts:2469` | `central_ai` | `public.svc_central_ai_next` | central_english_policy or calendar_reading, by the item's kind | `routed` | worker cascade |
| `index.ts:2747` | `entry_ai` | `public.svc_entry_matrix_next` | entry_matrices | `routed_single` | one model |
| `index.ts:2813` | `fee_ai` | `public.svc_fee_ai_next` | fee_reader | `routed` | worker cascade |
| `index.ts:2960` | `provider_description` | `public.svc_provider_description_lease_v1, public.svc_provider_description_next, public.svc_provider_description_reserve_v1` | provider_description | `routed_single` | one model (a price is reserved for that model) |
| `index.ts:3014` | `enrich_ai (course fields: ask)` | `public.svc_enrich_ai_next` | course_other_fields | `routed` | worker cascade |
| `index.ts:3038` | `enrich_ai (description and deadline: askText)` | `public.svc_enrich_ai_next` | course_description (description), course_other_fields (deadline) | `routed` | worker cascade |
| `index.ts:3066` | `enrich_ai (entry requirements)` | `public.svc_enrich_ai_next` | course_entry_requirements | `routed` | worker cascade |
| `index.ts:3364` | `ai_match` | `public.svc_coverage_ai_match_next` | course_matching | `routed` | worker cascade |
| `index.ts:3504` | `adapter_propose` | `security.adapter_builder_model_for_v1 (through public.svc_adapter_draft_get)` | adapter_builder | `routed_single` | one model |

State: `routed` means the route's cascade is executed (a later model is asked only on a technical failure). `routed_single` means the route
chooses the model but the call uses one model; Models & services shows one model and refuses a second one for these. `not_migrated` is
`page_identity` only: it has a route and a prompt (`pageid.ts`) but the worker makes no call for it (qualification only; no job).

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
