# AI models and services: page contract

## Changes for the UI (round 4)

Backend head after the Platform Admin's review of 13 Nov 2026 22:10. Not approved to merge; nothing is applied to live. Additive unless marked **changed**. The key names are the ones the UI branch (`cf247-ai-models-services-ui` @ 7d137e5a) already uses; where this backend differs it says **differs**.

### Who can do what

| Call | Rank | Notes |
|---|---|---|
| `admin_ai_overview_v1()` | 3 and above (**changed**, was 4) | read-only. Below rank 4, `openrouter.key` is `{ present }` only (no secret name, profile or sharing details). Refusal: `assigned StudySearch role required`. |
| `admin_scholarship_ai('read')` | 3 and above (as it is on live today: `Curator role or above required` below 3) | not changed by this PR; its other actions stay rank 6 (`review_decide` excepted, as today). |
| `admin_ai_route_set_v1(...)` | 5 | cascade, caps, switch of one service. |
| `admin_ai_model_set_v1(p_code, p_status, p_reason)` | 6 (**changed**, was 5) | the allow-list. Refusal: `Platform Admin required`. |
| `admin_ai_qualification_set_v1(p_service, p_code, p_evidence, p_reason, p_status default 'qualified')` | 6 | new. `p_status` is `qualified`, `unqualified` or `pending`. `qualified` needs evidence of at least 10 characters (`say what the qualification rests on (the evidence)`); a reason of at least 4 characters always. Logged as `route_qualification`. Returns the overview. It switches nothing on. |
| `admin_toolsets_write('setting', ...)` (existing) | 6 | the daily ceiling, the credit floor, `openrouter.balance_max_age_minutes`. |
| key replace / verify (existing `admin_ai_config`) | 6 | unchanged. |

Top level: `rank` (the caller's), `can_control` (rank 5 and above), `can_admin` (rank 6).

### Mode: Observe only or Stop at limits

1. Top-level `mode` and `openrouter.mode` are the existing OpenRouter mode (`observe` or `stop`, `pipeline.platform_toolsets.enforcement`). The migrations do not change the mode, the ceiling or any cap. Live is `observe` today.
2. Per service: `enforcing` (boolean: the limits are enforced, i.e. the mode is `stop`), `would_hold_now`, `would_hold_kind`, `would_hold_reason` (what would hold the service if limits were enforced; equal to `held*` in `stop`).
3. The daily ceiling and the service caps follow the mode: in `observe` they are reported through `would_hold_*` and stop nothing (`held` false); in `stop` they hold (`held_kind` `ceiling` or `cap`, `on_demand_exempt` true).
4. **Always enforced, in both modes, on-demand included** (`on_demand_exempt` false): `off`, `no_model`, `no_qualified_model`, `balance_unknown`, `balance_stale`, `credit_floor`.
5. **changed: `held_kind`** is now one of `cap`, `ceiling`, `credit_floor`, `off`, `no_model`, `no_qualified_model`, `balance_unknown`, `balance_stale` or null.

### Balance: fail closed (**changed**; round 3 said an unknown balance does not hold)

6. With no OpenRouter balance reading, every service is held (`balance_unknown`). With a reading older than `openrouter.balance_max_age_minutes` (new setting, default 90, range 15 to 1440, shown with the OpenRouter settings) every service is held (`balance_stale`; `held_reason` gives the age). `openrouter.balance_max_age_minutes` and `openrouter.balance_observed_at` are in the read; `openrouter.balance_note` is set when there is no reading. The balance job runs every 15 minutes; the longest gap in the last 14 days was 44.7 minutes.

### Qualification

7. Per service `qualification: [{ code, qualified, status, provisional, prompt_version, evidence, at, by, note }]` (`status`: `qualified`, `unqualified`, `pending`; `by` is a user id or null for a seed). Only a model that is allowed **and** qualified for the service is handed out.
8. Per service `skipped: [{ code, why }]`: cascade entries that are not handed out (`not in the list`, `not allowed`, `not qualified for this service`). `models` holds only what is handed out.
9. Seeds: Qwen3 30B is qualified for the ten services that run today (six of them `provisional: true` on the Platform Admin's decision of 13 Nov 19:09, "regression qualification pending"). Nothing is qualified for `course_entry_requirements`, `entry_matrices`, `entry_requirements_v2_shadow`, `ops_diagnosis` and `page_identity`: they are held `no_qualified_model` until the Platform Admin qualifies a model.

### One model or a cascade

10. Per service `migration_state`: `routed` (the cascade is executed), `routed_single` (the route chooses the model; the call uses one model) or `not_migrated` (`page_identity`: no call). For `routed_single` and `not_migrated`, `models` holds one model at most and `admin_ai_route_set_v1` refuses a second: `this service uses one model: a fallback is not available for it yet`.
11. Per service `previous_model`: the model identifier the service ran on before this release (`openai/gpt-4.1-mini` for ten services, Qwen3 30B for four, null for `page_identity`), for a "Was on" line. Data only.

### Calls and usage

12. Per service `last_call: { at, model, outcome, error, attempt_no }` or null (`outcome`: `answered` or `failed`; `error`: `http`, `timeout`, `empty`, `cut`, `non_json`, `refused` or null).
13. Per service `recovery_state`: `held` (nothing is handed out), `failing` (the last call failed), `fallback` (the last answer came from a later model of the cascade), `ok`, or `no_calls` (no call on record yet). **differs** if the UI meant something else by this key: this is the definition served.
14. `usage.by_model_24h: [{ service_code, model, attempts, answered, failures, fallbacks, tokens_in, tokens_out, usd, evidence_href }]` from the per-call record (`pipeline.ai_invocations`, written by worker v0.86.0). `fallbacks` counts attempts made on a later model. `evidence_href` is always null today (no per-call evidence link exists). **differs:** `usage.by_day_14d` and `usage.by_hour_24h` come from the spend ledger and keep `usd` and `calls` only; they do not carry tokens, failures or fallbacks.
15. `usage.fallbacks_24h: [{ at, service_code, model, attempt_no, failure_kind }]`: the last 100 failed attempts.
16. Rows appear only after the worker v0.86.0 is deployed; until then these lists are empty and `last_call` is null.

### Prompts (complete)

17. Per service `prompt: { source, version, text, text_ref, sha256 }`. For a prompt held in the database (provider descriptions, scholarship extraction, entry requirements v2) `text` is the **complete** text and `sha256` its hash (**changed:** the phase 1 read cut it at 4,000 characters). For a prompt written in the worker, `text` is null and `text_ref` is `ai-prompts.json#<service_code>`.
18. `docs/platform/ai-prompts.json` is generated from the worker source by `node scripts/ai-prompts-export.mjs` and checked in; a test fails when it is stale. Shape: `{ worker, services: { <service_code>: { sha256, prompts: [{ name, where, version, text, sha256, complete, note? }] } } }`. Import it in the page to show the complete text. `complete: false` marks the two course-field instructions that go on with data of the request (shown as `<data of the request>`). **differs:** there is no `admin_ai_prompt_v1` RPC, because the database does not hold the worker's text; the file is the source.
19. Scholarship configuration is read here: for `scholarship_extraction`, `config: { write: "public.admin_scholarship_ai", ai_admission, prompts: [{ version, text, sha256, current }] }`. `admin_scholarship_ai` stays the one write path.

### Settings

20. `home` / `home_group` (round 3) stay as they are. The existing `control_class` column is not reused for this: its check allows only `human`, `automatic`, `retiring`, and widening it means dropping a constraint. `docs/platform/SETTINGS-INVENTORY-2026-11-13.md` section 7 proposes a home per section; nothing is hidden or retired by this PR.

## Changes for the UI (round 3)

Backend head after independent QA and the page's own gaps (13 Nov 2026). Everything below is additive unless marked **changed**.

1. **Settings reads return `home` and `home_group`.** `admin_settings_register_read()` and `admin_toolsets_read()` now carry both keys on every setting, so the Settings page can hide rows with `home === 'models_services'` without calling the overview.
2. **`openrouter.key`** is `{ secret, profile_id, profile_code, shared_by_profiles }`, the same object `admin_ai_config_read()` gives under `openrouter.key`. Replace and Verify can use `openrouter.key.profile_id`; `admin_ai_config_read` still works.
3. **Scholarship admission.** In `admin_scholarship_ai('read')` the first model of the `scholarship_extraction` route is the one with status `active`; every other allowed model is `candidate`. This is kept in step by the route (saving the route, or allowing or disallowing a model). It is a copy of the route: it switches nothing on, AI admission keeps its own switch.
4. **Settings rows carry `not_read` and `read_only`** (both true for `pipeline.entry.matrix_model`, `pipeline.ops.ai_diagnosis_model` and `firecrawl.builder_model`: kept with their values, replaced by the routes). Show them read-only or leave them out.
5. **Families.** OpenAI and Claude models have family `other` in the data, as this contract said. **changed:** `admin_ai_model_set_v1` refuses to allow a model of family `other`: `this model is not in a family the Platform Admin allows (Qwen3, MiMo, Mistral Small, Kimi K2, Gemini, Llama, DeepSeek); adding a family is a release`.
6. **changed: `held_kind`** is one of `cap`, `ceiling`, `credit_floor`, `off`, `no_model` or null (it was `off` / `limit`). `on_demand_exempt` (boolean) says whether an open on-demand request is let through (`cap` and `ceiling` only). `held_reason` for the credit floor is exactly `credit_floor`. **changed: `area`** uses these names: Courses, Entry requirements, Providers, Scholarships, Fees, Matching and identity, Operations.
7. **Ceiling against caps:** top-level `ceiling_usd`, `caps_total_usd` (sum of the caps of the services that are switched on) and `caps_exceed_ceiling`; per service `would_hold_now` (the service would hand out no scheduled work right now). At apply, every scheduled AI service is held until the next UTC day unless the ceiling is raised first: show it.
8. **Credit floor:** when the last observed OpenRouter balance is at or below `openrouter.floor_usd`, every service is held, on-demand included. `openrouter.balance_known` is false when there is no balance reading; the floor then holds nothing (`openrouter.balance_note` says so).
9. **On-demand** is waived per purpose group: each service has `purpose_group` (`reads`, `central`, `scholarships`, `pdesc`, `course_search`, `other`), and an open request lets through only the services of the groups it covers.
10. **Seeds changed:** `entry_matrices` and `ops_diagnosis` start with one model (their calls use the first model only). Every service has a daily US$ cap from the first migration.
11. **Retiring:** `public.admin_ai_config` (its `central_model` action is refused; nothing on the page calls it). `public.admin_services_control` is still called by `src/ModelsServices.jsx` with kind `service` on the UI branch, so it is not marked.

For the agent building the Models & services page. Backend: migrations `20261113380000` (phase 1) and `20261113390000` (phase 2: the route is the only place a model is chosen). Platform Admin 13 Nov 2026 19:14, 19:15 and 19:23. The page needs three calls of its own and one existing call for settings. All are `supabase.rpc(...)` as a signed-in user.

**Changed in phase 2:** every service is enforced (`enforced: true`, `resolver: "route"`); each service row has `model` (its first model); the daily US$ cap is required on every route; there is a 15th service, `page_identity`; `legacy.layer3` and `guard` are new; `legacy_controls` are read-only copies now (`write: null`). `wired` and `model_in_effect` are kept so a page built on the first issue keeps working; they now always equal `enforced` and `model`.

| Call | Who | What |
|---|---|---|
| `admin_ai_overview_v1()` | rank 3 and above (round 4; key details from rank 4) | everything the page shows |
| `admin_ai_model_set_v1(p_code, p_status, p_reason)` | Platform Admin (rank 6, round 4) | allow or disallow a model |
| `admin_ai_qualification_set_v1(p_service, p_code, p_evidence, p_reason, p_status)` | Platform Admin (rank 6) | record a model as qualified (or not) for a service |
| `admin_ai_route_set_v1(p_service, p_cascade, p_daily_usd_cap, p_daily_calls_cap, p_enabled, p_reason)` | rank 5 | save one service's cascade, caps and switch |
| `admin_toolsets_write('setting', {toolset, key, value, reason})` (existing) | **Platform Admin (rank 6)** | save a setting shown under a service. This is the existing audited write `src/Toolsets.jsx` uses; there is no second save path |

`admin_toolsets_write` **accepts text settings** (`kind: "text"`): the value is trimmed and must not be empty. Numbers are checked against `min` and `max`, booleans are cast, lists must be arrays. It needs rank 6, one rank above the two route writes, so show a service's settings read-only to a rank 5 user (`can_control` is true from rank 5; the overview does not say whether the user is rank 6, so let the call's error decide: `Platform Admin required`).

Both route writes return the same object as `admin_ai_overview_v1()`, so the page can replace its state from the answer.

Errors are raised as exceptions (`error.message`): `Pipeline Operator role or above required` / `PIM Operator role or above required` (code 42501), `give a reason (kept in the log)` (a reason has at least 4 characters), `status must be allowed or not_allowed`, `model <code> is not in the list`, `service <code> is not in the list`, `the cascade is empty: name at least one allowed model`, `a cascade holds 4 models at most`, `the cascade names a model twice`, `unknown model in the cascade: <codes>`, `not an allowed model: <codes> (Models & services › Models)`, `give a daily US$ cap (every service has one)`, `a cap cannot be negative (leave it empty for no cap)` (the calls cap may be empty).

## 1. `admin_ai_overview_v1()` returns

```
{
  can_control: boolean,
  ceiling_usd: number, caps_total_usd: number, caps_exceed_ceiling: boolean,   // the daily ceiling against the sum of the caps of services that are on
  day_start: timestamptz,            // start of the UTC day the spend figures count from
  openrouter: {
    key_present: boolean,            // true when a balance was read inside openrouter.balance_stale_minutes; the key itself is an edge function secret and is never returned
    key_secret_name: "OPENROUTER_API_KEY",
    key: { secret, profile_id, profile_code, shared_by_profiles },   // as admin_ai_config_read gives it; profile_id is what Replace and Verify need
    balance_known: boolean, balance_note: string | null,          // no balance reading: the credit floor holds nothing (unknown is not zero)
    mode: "observe" | "stop",        // the OpenRouter toolset mode (existing guards). Routes hold whatever this is
    balance_usd: number | null, balance_observed_at: timestamptz | null, total_credits_usd: number | null,
    floor_usd: number,               // openrouter.credit_floor_usd
    low_warn_usd: number,            // openrouter.low_balance_warn_usd
    daily_ceiling_usd: number,       // pipeline budgets.ai_daily_ceiling_usd: every route is held once the day's total reaches it
    spent_today_usd: number,         // every service together, UTC day
    settings: Setting[]              // the OpenRouter and ceiling settings (see Setting)
  },
  models: [{ code, family, label, model_identifier, input_usd_per_mtok, output_usd_per_mtok, price_checked_at, context_tokens,
             status: "allowed" | "not_allowed", note, reason, changed_at, used_by: [service_code] }],
             // family is one of qwen3, mimo, mistral_small, kimi_k2, gemini, llama, deepseek, other. Allowed models come first
  services: [{
    service_code, label, area, field,          // area: Courses | Entry requirements | Providers | Scholarships | Fees | Matching and identity | Operations
    purpose_group,                             // the on-demand purpose group whose open requests are not held by this service's cap or the ceiling
    lane, ledger_match,                        // where its spend is counted (for information)
    cascade: [code],                           // as saved, 1 to 4 codes, first is tried first
    cascade_detail: [{ code, label, model_identifier, status }],
    models: [{ code, model_identifier }],      // the cascade with models that are not allowed left out: what the reader is given
    daily_usd_cap: number, daily_calls_cap: number | null,          // the US$ cap is required; a null calls cap = none
    enabled: boolean,
    spent_today: { usd, calls },
    held: boolean, held_kind: "cap" | "ceiling" | "credit_floor" | "off" | "no_model" | null, held_reason: string | null,
    would_hold_now: boolean,                   // no scheduled work would be handed out right now (the same as held)
    on_demand_exempt: boolean,                 // true for cap and ceiling: an open on-demand request of the purpose group is still let through
    enforced: true,                            // every service's reader asks its route (phase 2). resolver is "route" for all
    model: string | null,                      // the OpenRouter id of the first allowed model of the cascade: the model in use
    resolver: "route", wired: true, model_in_effect: string | null,   // kept from the first issue; equal to enforced and model
    prompt: { source, version, text },         // text is the first 4000 characters, or null when the prompt lives in worker code or a function
    settings: Setting[],                       // the settings that belong to this service
    note, reason, changed_at, changed_by       // changed_by is an email or null
  }],
  legacy_controls: {                           // read-only copies kept for the older screens; nothing chooses a model from them
    central_ai_settings: { enabled, calls_at_once, model_code, model_identifier, reason, changed_at, write: null, copy_of: "route calendar_reading" },
    scholarship_chain: { chain: [code], reason, changed_at, write: null, copy_of: "route scholarship_extraction" }
  },
  legacy: { layer3: {                          // Layer 3 was retired on 12 Oct 2026 and is not wired to the routes: shown so nothing is hidden
    note, last_call_at, jobs: [jobname],       // jobs = active scheduled jobs whose command names layer3 (none on live)
    profiles_switched_on: [{ code, model_identifier, tasks, in_active_tier, catalogue_status }] } },
  guard: number,                               // how many places name a model that is not allowed outside the routes (security.ai_route_guard_v1); 0 is clean
  usage: {
    by_day_14d:  [{ day, service_code, lane, model, usd, calls }],    // UTC days, today and the 13 before, newest first
    by_hour_24h: [{ hour, service_code, lane, model, usd, calls }]    // the current hour and the 23 before
  },
  events: [{ at, action, target, detail, by }]                        // the last 20 changes made through the two writes (area ai_models)
}

Setting = { toolset, key, label, help, value, kind: "number" | "text" | "boolean" | "list", min, max, unit, not_read: boolean, read_only: boolean }
```

Notes for the page:

- `model` in usage rows is null for spend recorded before the migration, and `service_code` is filled for all rows. Group nulls as "not recorded".
- Every service is enforced. `note` carries a plain remark where one helps (for example the scholarship cascade is its chain).
- Save a setting with `admin_toolsets_write('setting', {toolset: s.toolset, key: s.key, value, reason})`, then reload the overview. Text settings (`kind: "text"`) include the two old model keys (`entry.matrix_model`, `ops.ai_diagnosis_model`); they are no longer read, so show them read-only or leave them out.

### Example (from the test fixture, shortened: 2 of 18 models, 2 of 15 services)

```json
{
  "guard": 3,
  "usage": {
    "by_day_14d": [
      {
        "day": "2026-11-13",
        "usd": 0.9,
        "lane": "enrich_fields",
        "calls": 1,
        "model": "qwen/qwen3-30b-a3b-instruct-2507",
        "service_code": "course_description"
      },
      {
        "day": "2026-11-13",
        "usd": 0.3,
        "lane": "enrich_fields",
        "calls": 1,
        "model": null,
        "service_code": "course_entry_requirements"
      },
      {
        "day": "2026-11-13",
        "usd": 0.2,
        "lane": "enrich_fields",
        "calls": 1,
        "model": null,
        "service_code": "course_description"
      }
    ],
    "by_hour_24h": [
      {
        "usd": 0.9,
        "hour": "2026-11-13T10:00:00+00:00",
        "lane": "enrich_fields",
        "calls": 1,
        "model": "qwen/qwen3-30b-a3b-instruct-2507",
        "service_code": "course_description"
      },
      {
        "usd": 0.3,
        "hour": "2026-11-13T10:00:00+00:00",
        "lane": "enrich_fields",
        "calls": 1,
        "model": null,
        "service_code": "course_entry_requirements"
      }
    ]
  },
  "events": [
    {
      "at": "2026-11-13T10:06:08.587793+00:00",
      "by": "admin@example.test",
      "action": "route_set",
      "detail": {
        "after": {
          "cascade": [
            "qwen3-30b"
          ],
          "enabled": true,
          "daily_usd_cap": 5,
          "daily_calls_cap": null
        },
        "before": {
          "cascade": [
            "mistral-small-3.2",
            "qwen3-30b"
          ],
          "enabled": true,
          "daily_usd_cap": 5,
          "daily_calls_cap": null
        },
        "reason": "fixture: back",
        "resolver": "route"
      },
      "target": "fee_reader"
    },
    {
      "at": "2026-11-13T10:06:08.587793+00:00",
      "by": "admin@example.test",
      "action": "route_set",
      "detail": {
        "after": {
          "cascade": [
            "deepseek-v3.2",
            "qwen3-30b"
          ],
          "enabled": true,
          "daily_usd_cap": 3,
          "daily_calls_cap": 500
        },
        "before": {
          "cascade": [
            "qwen3-30b",
            "mistral-small-3.2"
          ],
          "enabled": true,
          "daily_usd_cap": 5,
          "daily_calls_cap": null
        },
        "reason": "fixture: cheaper first",
        "resolver": "route"
      },
      "target": "course_entry_requirements"
    }
  ],
  "legacy": {
    "layer3": {
      "jobs": [],
      "note": "Layer 3 was retired on 12 Oct 2026 and is not wired to the routes. A profile listed here is switched on in its own table; in_active_tier says whether a Layer 3 step would still use it.",
      "last_call_at": "2026-10-11T21:55:27+00:00",
      "profiles_switched_on": [
        {
          "code": "openrouter-intake-l3c-qwen3-30b-a3b-2507-v1",
          "tasks": [
            "provider_intake_validation"
          ],
          "in_active_tier": true,
          "catalogue_status": "allowed",
          "model_identifier": "qwen/qwen3-30b-a3b-instruct-2507"
        },
        {
          "code": "openrouter-intake-l3r-claude-haiku-4-5-v1",
          "tasks": [
            "provider_intake_validation"
          ],
          "in_active_tier": false,
          "catalogue_status": "not_allowed",
          "model_identifier": "anthropic/claude-haiku-4.5"
        }
      ]
    }
  },
  "models": [
    {
      "code": "qwen3-30b",
      "note": "In use: course fields, central pages, fees, scholarships, course-page matching, adapter proposals",
      "label": "Qwen3 30B A3B Instruct (2507)",
      "family": "qwen3",
      "reason": "seed 13 Nov 2026",
      "status": "allowed",
      "used_by": [
        "course_description",
        "course_entry_requirements",
        "course_other_fields",
        "entry_matrices",
        "entry_requirements_v2_shadow",
        "scholarship_extraction",
        "scholarship_eligibility",
        "provider_description",
        "calendar_reading",
        "central_english_policy",
        "fee_reader",
        "course_matching",
        "page_identity",
        "adapter_builder",
        "ops_diagnosis"
      ],
      "changed_at": "2026-11-13T10:06:06.258646+00:00",
      "context_tokens": 262144,
      "model_identifier": "qwen/qwen3-30b-a3b-instruct-2507",
      "price_checked_at": "2026-11-13T10:06:06.258646+00:00",
      "input_usd_per_mtok": 0.1,
      "output_usd_per_mtok": 0.3
    },
    {
      "code": "gpt-4.1-mini",
      "note": "Platform Admin 13 Nov 2026 19:14: too expensive, it exhausted the AI credit. Kept so history resolves",
      "label": "GPT-4.1 mini",
      "family": "other",
      "reason": "Platform Admin 13 Nov 2026 19:14",
      "status": "not_allowed",
      "used_by": [],
      "changed_at": "2026-11-13T10:06:06.258646+00:00",
      "context_tokens": 1047576,
      "model_identifier": "openai/gpt-4.1-mini",
      "price_checked_at": "2026-11-13T10:06:06.258646+00:00",
      "input_usd_per_mtok": 0.4,
      "output_usd_per_mtok": 1.6
    }
  ],
  "services": [
    {
      "area": "Entry requirements",
      "held": false,
      "lane": "entry_matrix",
      "note": "Was GPT-4.1 mini (setting entry.matrix_model). qwen3-30b has not been qualified on this prompt.",
      "field": null,
      "label": "Entry requirement matrices (provider pages)",
      "model": "qwen/qwen3-30b-a3b-instruct-2507",
      "wired": true,
      "models": [
        {
          "code": "qwen3-30b",
          "model_identifier": "qwen/qwen3-30b-a3b-instruct-2507"
        }
      ],
      "prompt": {
        "text": null,
        "source": "worker code",
        "version": "entry-matrix-v0.1.4"
      },
      "reason": "seed 13 Nov 2026 (Platform Admin 19:14)",
      "cascade": [
        "qwen3-30b"
      ],
      "enabled": true,
      "enforced": true,
      "resolver": "route",
      "settings": [
        {
          "key": "entry.matrix_enabled",
          "max": 1,
          "min": 0,
          "help": null,
          "kind": "number",
          "unit": null,
          "label": "Entry matrices: on",
          "value": 1,
          "toolset": "pipeline",
          "not_read": false,
          "read_only": false
        },
        {
          "key": "entry.matrix_model",
          "max": null,
          "min": null,
          "help": null,
          "kind": "text",
          "unit": null,
          "label": "Entry matrices: pinned model",
          "value": "openai/gpt-4.1-mini",
          "toolset": "pipeline",
          "not_read": true,
          "read_only": true
        }
      ],
      "held_kind": null,
      "changed_at": "2026-11-13T10:06:06.258646+00:00",
      "changed_by": null,
      "held_reason": null,
      "spent_today": {
        "usd": 0.02,
        "calls": 1
      },
      "ledger_match": {
        "source": [
          "entry_matrix_runs"
        ]
      },
      "service_code": "entry_matrices",
      "daily_usd_cap": 20,
      "purpose_group": "central",
      "cascade_detail": [
        {
          "code": "qwen3-30b",
          "label": "Qwen3 30B A3B Instruct (2507)",
          "status": "allowed",
          "model_identifier": "qwen/qwen3-30b-a3b-instruct-2507"
        }
      ],
      "would_hold_now": false,
      "daily_calls_cap": null,
      "model_in_effect": "qwen/qwen3-30b-a3b-instruct-2507",
      "on_demand_exempt": false
    },
    {
      "area": "Providers",
      "held": false,
      "lane": "provider_description",
      "note": null,
      "field": null,
      "label": "Provider description",
      "model": "qwen/qwen3-30b-a3b-instruct-2507",
      "wired": true,
      "models": [
        {
          "code": "qwen3-30b",
          "model_identifier": "qwen/qwen3-30b-a3b-instruct-2507"
        }
      ],
      "prompt": {
        "text": "You write a provider description.",
        "source": "pipeline.provider_description_prompts",
        "version": "4"
      },
      "reason": "seed 13 Nov 2026 (Platform Admin 19:14)",
      "cascade": [
        "qwen3-30b"
      ],
      "enabled": true,
      "enforced": true,
      "resolver": "route",
      "settings": [],
      "held_kind": null,
      "changed_at": "2026-11-13T10:06:06.258646+00:00",
      "changed_by": null,
      "held_reason": null,
      "spent_today": {
        "usd": 0.0,
        "calls": 0
      },
      "ledger_match": null,
      "service_code": "provider_description",
      "daily_usd_cap": 1,
      "purpose_group": "pdesc",
      "cascade_detail": [
        {
          "code": "qwen3-30b",
          "label": "Qwen3 30B A3B Instruct (2507)",
          "status": "allowed",
          "model_identifier": "qwen/qwen3-30b-a3b-instruct-2507"
        }
      ],
      "would_hold_now": false,
      "daily_calls_cap": null,
      "model_in_effect": "qwen/qwen3-30b-a3b-instruct-2507",
      "on_demand_exempt": false
    }
  ],
  "day_start": "2026-11-13T00:00:00+00:00",
  "openrouter": {
    "key": {
      "secret": "OPENROUTER_API_KEY",
      "profile_id": "8ded0bb7-3994-432c-a5a1-2bd9c1716264",
      "profile_code": "openrouter-intake-l3c-qwen3-30b-a3b-2507-v1",
      "shared_by_profiles": 4
    },
    "mode": "observe",
    "settings": [
      {
        "key": "balance_stale_minutes",
        "max": 1440,
        "min": 5,
        "help": null,
        "kind": "number",
        "unit": "minutes",
        "label": "Warn when the balance has not been read for",
        "value": 30,
        "toolset": "openrouter",
        "not_read": false,
        "read_only": false
      },
      {
        "key": "credit_floor_usd",
        "max": 500,
        "min": 0,
        "help": null,
        "kind": "number",
        "unit": "US$",
        "label": "Credit floor",
        "value": 0.5,
        "toolset": "openrouter",
        "not_read": false,
        "read_only": false
      }
    ],
    "floor_usd": 0.5,
    "balance_usd": null,
    "key_present": true,
    "balance_note": "No balance reading yet: the credit floor cannot hold anything until one is recorded (unknown is not zero).",
    "low_warn_usd": 10,
    "balance_known": false,
    "key_secret_name": "OPENROUTER_API_KEY",
    "spent_today_usd": 1.607,
    "daily_ceiling_usd": 14,
    "total_credits_usd": null,
    "balance_observed_at": "2026-11-13T10:06:09.785064+00:00"
  },
  "can_control": true,
  "ceiling_usd": 14,
  "caps_total_usd": 181.5,
  "legacy_controls": {
    "scholarship_chain": {
      "chain": [
        "qwen3-30b"
      ],
      "write": null,
      "reason": "copy of the scholarship route (Models & services)",
      "copy_of": "route scholarship_extraction",
      "changed_at": "2026-11-13T10:06:08.77921+00:00"
    },
    "central_ai_settings": {
      "write": null,
      "reason": "copy of the intake calendar route (Models & services)",
      "copy_of": "route calendar_reading",
      "enabled": true,
      "changed_at": "2026-11-13T10:06:08.587793+00:00",
      "model_code": "qwen3-30b",
      "calls_at_once": 3,
      "model_identifier": "qwen/qwen3-30b-a3b-instruct-2507"
    }
  },
  "caps_exceed_ceiling": true
}
```

## 2. `admin_ai_model_set_v1(p_code text, p_status text, p_reason text)`

`p_status` is `allowed` or `not_allowed`. A model that is switched to not allowed stays in the cascades that name it and is skipped; a service whose cascade then has no allowed model shows `held: true, held_kind: "no_model", held_reason: "no allowed model in the cascade"`. The log row carries the services that name the model.

```js
const { data, error } = await supabase.rpc('admin_ai_model_set_v1', { p_code: 'kimi-k2-0905', p_status: 'not_allowed', p_reason: 'costs more than the others' })
```

## 3. `admin_ai_route_set_v1(p_service text, p_cascade text[], p_daily_usd_cap numeric, p_daily_calls_cap integer, p_enabled boolean, p_reason text)`

Saves the route whole: send the full cascade and both caps every time. The daily US$ cap is required; a `null` calls cap means none. `p_enabled: null` keeps the switch as it is.

```js
const { data, error } = await supabase.rpc('admin_ai_route_set_v1', {
  p_service: 'course_entry_requirements', p_cascade: ['qwen3-30b', 'mistral-small-3.2'],
  p_daily_usd_cap: 5, p_daily_calls_cap: null, p_enabled: true, p_reason: 'cap the entry requirements read at US$5 a day' })
```

## 4. What a route controls

Every service's reader asks `security.ai_route_v1(service)` before it hands out work, so a saved route takes effect on the next reader call: the model, the switch, the daily US$ cap, the calls cap and the daily ceiling. A cap or the ceiling (`held_kind` `cap` or `ceiling`) does not hold work of a provider with an open on-demand request that covers the service's purpose group. A switch (`off`), a cascade with no allowed model (`no_model`) and the account's credit floor (`credit_floor`) hold everything, on-demand included.

| Service | Reader | The cascade beyond the first model |
|---|---|---|
| course_description, course_entry_requirements, course_other_fields | `svc_enrich_ai_next` | the worker tries the next model on a technical failure |
| fee_reader | `svc_fee_ai_next` | the worker tries the next model on a technical failure |
| calendar_reading, central_english_policy | `svc_central_ai_next` (each kind of page has its own route) | the worker tries the next model on a technical failure |
| course_matching | `svc_coverage_ai_match_next` | the worker tries the next model on a technical failure |
| entry_requirements_v2_shadow | `aer_v2_shadow_hold_v1` (the prompt version keeps its text and sha) | the worker tries the next model on a technical failure |
| scholarship_extraction | `svc_scholarship_ai_next`, re-check `svc_scholarship_recheck_next` | the cascade is the chain: an unproven fact goes to the next model, then to a person. The re-check also tries the next model on a technical failure |
| scholarship_eligibility | `svc_scholarship_eligibility_next` | first model only |
| provider_description | `svc_provider_description_next` | first model only (each read reserves a price for one model) |
| adapter_builder | `adapter_builder_model_for_v1`, `adapter_builder_budget` | first model only; a provider's own model is used only when the cascade names it |
| entry_matrices | `svc_entry_matrix_next` | first model only (seeded with one model) |
| ops_diagnosis | `svc_ops_diagnosis_next` | first model only (seeded with one model) |
| page_identity | none scheduled | qualification only |

The worker moves to the next model only on a technical failure (an HTTP error, a time-out, an unreadable, empty, cut or non-JSON answer). It never moves on because of what a model answered, and it asks a later model only while the call's time budget lasts. Usage rows name the model that answered.

## 5. What a reader gets: `security.ai_route_v1(service)` (not callable from the page)

```json
{
  "cap": {
    "usd": 3,
    "calls": 500
  },
  "held": false,
  "model": "deepseek/deepseek-v3.2",
  "models": [
    {
      "code": "deepseek-v3.2",
      "model_identifier": "deepseek/deepseek-v3.2"
    },
    {
      "code": "qwen3-30b",
      "model_identifier": "qwen/qwen3-30b-a3b-instruct-2507"
    }
  ],
  "balance": {
    "usd": 53,
    "known": true,
    "floor_usd": 0.5
  },
  "service": "course_entry_requirements",
  "held_kind": null,
  "held_reason": null,
  "spent_today": {
    "usd": 0.301,
    "calls": 2
  },
  "on_demand_exempt": false
}
```
