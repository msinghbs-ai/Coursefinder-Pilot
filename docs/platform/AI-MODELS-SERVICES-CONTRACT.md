# AI models and services: page contract

For the agent building the Models & services page. Backend: migrations `20261113380000` (phase 1) and `20261113390000` (phase 2: the route is the only place a model is chosen). Platform Admin 13 Nov 2026 19:14, 19:15 and 19:23. The page needs three calls of its own and one existing call for settings. All are `supabase.rpc(...)` as a signed-in user.

**Changed in phase 2 (this issue of the contract):** every service is enforced (`enforced: true`, `resolver: "route"`); each service row has `model` (its first model); the daily US$ cap is required on every route; there is a 15th service, `page_identity`; `legacy.layer3` and `guard` are new; `legacy_controls` are read-only copies now (`write: null`). `wired` and `model_in_effect` are kept so a page built on the first issue keeps working; they now always equal `enforced` and `model`.

| Call | Who | What |
|---|---|---|
| `admin_ai_overview_v1()` | Pipeline Operator and above (rank 4) | everything the page shows |
| `admin_ai_model_set_v1(p_code, p_status, p_reason)` | PIM Operator and above (rank 5) | allow or disallow a model |
| `admin_ai_route_set_v1(p_service, p_cascade, p_daily_usd_cap, p_daily_calls_cap, p_enabled, p_reason)` | rank 5 | save one service's cascade, caps and switch |
| `admin_toolsets_write('setting', {toolset, key, value, reason})` (existing) | **Platform Admin (rank 6)** | save a setting shown under a service. This is the existing audited write `src/Toolsets.jsx` uses; there is no second save path |

`admin_toolsets_write` **accepts text settings** (`kind: "text"`): the value is trimmed and must not be empty. Numbers are checked against `min` and `max`, booleans are cast, lists must be arrays. It needs rank 6, one rank above the two route writes, so show a service's settings read-only to a rank 5 user (`can_control` is true from rank 5; the overview does not say whether the user is rank 6, so let the call's error decide: `Platform Admin required`).

Both route writes return the same object as `admin_ai_overview_v1()`, so the page can replace its state from the answer.

Errors are raised as exceptions (`error.message`): `Pipeline Operator role or above required` / `PIM Operator role or above required` (code 42501), `give a reason (kept in the log)` (a reason has at least 4 characters), `status must be allowed or not_allowed`, `model <code> is not in the list`, `service <code> is not in the list`, `the cascade is empty: name at least one allowed model`, `a cascade holds 4 models at most`, `the cascade names a model twice`, `unknown model in the cascade: <codes>`, `not an allowed model: <codes> (Models & services › Models)`, `give a daily US$ cap (every service has one)`, `a cap cannot be negative (leave it empty for no cap)` (the calls cap may be empty).

## 1. `admin_ai_overview_v1()` returns

```
{
  can_control: boolean,
  day_start: timestamptz,            // start of the UTC day the spend figures count from
  openrouter: {
    key_present: boolean,            // true when a balance was read inside openrouter.balance_stale_minutes; the key itself is an edge function secret and is never returned
    key_secret_name: "OPENROUTER_API_KEY",
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
    service_code, label, area, field,          // field is set for the three course field groups, else null
    lane, ledger_match,                        // where its spend is counted (for information)
    cascade: [code],                           // as saved, 1 to 4 codes, first is tried first
    cascade_detail: [{ code, label, model_identifier, status }],
    models: [{ code, model_identifier }],      // the cascade with models that are not allowed left out: what the reader is given
    daily_usd_cap: number, daily_calls_cap: number | null,          // the US$ cap is required; a null calls cap = none
    enabled: boolean,
    spent_today: { usd, calls },
    held: boolean, held_kind: "off" | "limit" | null, held_reason: string | null,
             // off: switched off or no allowed model. limit: the daily ceiling or a cap; on-demand work of an open request is not held by a limit
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

Setting = { toolset, key, label, help, value, kind: "number" | "text" | "boolean" | "list", min, max, unit }
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
        "hour": "2026-11-13T09:00:00+00:00",
        "lane": "enrich_fields",
        "calls": 1,
        "model": "qwen/qwen3-30b-a3b-instruct-2507",
        "service_code": "course_description"
      },
      {
        "usd": 0.3,
        "hour": "2026-11-13T09:00:00+00:00",
        "lane": "enrich_fields",
        "calls": 1,
        "model": null,
        "service_code": "course_entry_requirements"
      }
    ]
  },
  "events": [
    {
      "at": "2026-11-13T09:17:54.4449+00:00",
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
      "at": "2026-11-13T09:17:54.4449+00:00",
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
      "changed_at": "2026-11-13T09:17:51.966414+00:00",
      "context_tokens": 262144,
      "model_identifier": "qwen/qwen3-30b-a3b-instruct-2507",
      "price_checked_at": "2026-11-13T09:17:51.966414+00:00",
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
      "changed_at": "2026-11-13T09:17:51.966414+00:00",
      "context_tokens": 1047576,
      "model_identifier": "openai/gpt-4.1-mini",
      "price_checked_at": "2026-11-13T09:17:51.966414+00:00",
      "input_usd_per_mtok": 0.4,
      "output_usd_per_mtok": 1.6
    }
  ],
  "services": [
    {
      "area": "Course fields",
      "held": false,
      "lane": "enrich_fields",
      "note": "Was GPT-4.1 mini (setting entry.matrix_model). qwen3-30b has not been qualified on this prompt.",
      "field": "course_entry_requirements",
      "label": "Course entry requirements",
      "model": "deepseek/deepseek-v3.2",
      "wired": true,
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
      "prompt": {
        "text": null,
        "source": "worker code",
        "version": "course-entry-v1"
      },
      "reason": "fixture: cheaper first",
      "cascade": [
        "deepseek-v3.2",
        "qwen3-30b"
      ],
      "enabled": true,
      "enforced": true,
      "resolver": "route",
      "settings": [
        {
          "key": "entry.course_page_chars",
          "max": 400000,
          "min": 1000,
          "help": null,
          "kind": "number",
          "unit": "characters",
          "label": "Course entry requirements: page characters",
          "value": 100000,
          "toolset": "pipeline"
        }
      ],
      "held_kind": null,
      "changed_at": "2026-11-13T09:17:54.4449+00:00",
      "changed_by": "admin@example.test",
      "held_reason": null,
      "spent_today": {
        "usd": 0.301,
        "calls": 2
      },
      "ledger_match": {
        "where": {
          "field": [
            "entry_requirements"
          ]
        }
      },
      "service_code": "course_entry_requirements",
      "daily_usd_cap": 3,
      "cascade_detail": [
        {
          "code": "deepseek-v3.2",
          "label": "DeepSeek V3.2",
          "status": "allowed",
          "model_identifier": "deepseek/deepseek-v3.2"
        },
        {
          "code": "qwen3-30b",
          "label": "Qwen3 30B A3B Instruct (2507)",
          "status": "allowed",
          "model_identifier": "qwen/qwen3-30b-a3b-instruct-2507"
        }
      ],
      "daily_calls_cap": 500,
      "model_in_effect": "deepseek/deepseek-v3.2"
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
      "changed_at": "2026-11-13T09:17:51.966414+00:00",
      "changed_by": null,
      "held_reason": null,
      "spent_today": {
        "usd": 0.0,
        "calls": 0
      },
      "ledger_match": null,
      "service_code": "provider_description",
      "daily_usd_cap": 1,
      "cascade_detail": [
        {
          "code": "qwen3-30b",
          "label": "Qwen3 30B A3B Instruct (2507)",
          "status": "allowed",
          "model_identifier": "qwen/qwen3-30b-a3b-instruct-2507"
        }
      ],
      "daily_calls_cap": null,
      "model_in_effect": "qwen/qwen3-30b-a3b-instruct-2507"
    }
  ],
  "day_start": "2026-11-13T00:00:00+00:00",
  "openrouter": {
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
        "toolset": "openrouter"
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
        "toolset": "openrouter"
      }
    ],
    "floor_usd": 0.5,
    "balance_usd": 53.0,
    "key_present": true,
    "low_warn_usd": 10,
    "key_secret_name": "OPENROUTER_API_KEY",
    "spent_today_usd": 1.607,
    "daily_ceiling_usd": 14,
    "total_credits_usd": 100,
    "balance_observed_at": "2026-11-13T09:17:46.231413+00:00"
  },
  "can_control": true,
  "legacy_controls": {
    "scholarship_chain": {
      "chain": [
        "qwen3-30b"
      ],
      "write": null,
      "reason": "copy of the scholarship route (Models & services)",
      "copy_of": "route scholarship_extraction",
      "changed_at": "2026-11-13T09:17:54.584335+00:00"
    },
    "central_ai_settings": {
      "write": null,
      "reason": "copy of the intake calendar route (Models & services)",
      "copy_of": "route calendar_reading",
      "enabled": true,
      "changed_at": "2026-11-13T09:17:54.4449+00:00",
      "model_code": "qwen3-30b",
      "calls_at_once": 3,
      "model_identifier": "qwen/qwen3-30b-a3b-instruct-2507"
    }
  }
}
```

## 2. `admin_ai_model_set_v1(p_code text, p_status text, p_reason text)`

`p_status` is `allowed` or `not_allowed`. A model that is switched to not allowed stays in the cascades that name it and is skipped; a service whose cascade then has no allowed model shows `held: true, held_kind: "off", held_reason: "no allowed model in the cascade"`. The log row carries the services that name the model.

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

Every service's reader asks `security.ai_route_v1(service)` before it hands out work, so a saved route takes effect on the next reader call: the model, the switch, the daily US$ cap, the calls cap and the daily ceiling. A cap or the ceiling (`held_kind: "limit"`) does not hold work of a provider with an open on-demand request; a switch or a cascade with no allowed model (`held_kind: "off"`) holds everything.

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
| entry_matrices | `svc_entry_matrix_next` | first model only |
| ops_diagnosis | `svc_ops_diagnosis_next` | first model only |
| page_identity | none scheduled | qualification only |

The worker moves to the next model only on a technical failure (an HTTP error, a time-out, an unreadable, empty, cut or non-JSON answer). It never moves on because of what a model answered. Usage rows name the model that answered.

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
  "service": "course_entry_requirements",
  "held_kind": null,
  "held_reason": null,
  "spent_today": {
    "usd": 0.301,
    "calls": 2
  }
}
```
