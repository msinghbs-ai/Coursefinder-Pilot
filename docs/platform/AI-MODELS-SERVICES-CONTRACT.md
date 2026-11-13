# AI models and services: page contract

For the agent building the Models & services page. Backend: migration `20261113380000_cf247_ai_models_services.sql` (Platform Admin 13 Nov 2026 19:14, 19:15 and 19:23). The page needs three calls of its own and one existing call for settings. All are `supabase.rpc(...)` as a signed-in user.

| Call | Who | What |
|---|---|---|
| `admin_ai_overview_v1()` | Pipeline Operator and above (rank 4) | everything the page shows |
| `admin_ai_model_set_v1(p_code, p_status, p_reason)` | PIM Operator and above (rank 5) | allow or disallow a model |
| `admin_ai_route_set_v1(p_service, p_cascade, p_daily_usd_cap, p_daily_calls_cap, p_enabled, p_reason)` | rank 5 | save one service's cascade, caps and switch |
| `admin_toolsets_write('setting', {toolset, key, value, reason})` (existing) | as today | save a setting shown under a service. This is the existing audited write `src/Toolsets.jsx` uses; there is no second save path |

Both writes return the same object as `admin_ai_overview_v1()`, so the page can replace its state from the answer. `can_control` is true from rank 5.

Errors are raised as exceptions (`error.message`): `Pipeline Operator role or above required` / `PIM Operator role or above required` (code 42501), `give a reason (kept in the log)` (a reason has at least 4 characters), `status must be allowed or not_allowed`, `model <code> is not in the list`, `service <code> is not in the list`, `the cascade is empty: name at least one allowed model`, `a cascade holds 4 models at most`, `the cascade names a model twice`, `unknown model in the cascade: <codes>`, `not an allowed model: <codes> (Models & services › Models)`, `a cap cannot be negative (leave it empty for no cap)`.

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
    daily_usd_cap: number | null, daily_calls_cap: number | null,   // null = no cap
    enabled: boolean,
    spent_today: { usd, calls },
    held: boolean, held_kind: "off" | "limit" | null, held_reason: string | null,
             // off: switched off or no allowed model. limit: the daily ceiling or a cap; on-demand work of an open request is not held by a limit
    resolver: string, wired: boolean,          // wired = (resolver is "route"): the service's reader asks the route. See section 4
    model_in_effect: string | null,            // the OpenRouter id actually used today (from the route, or from where the reader still reads it)
    prompt: { source, version, text },         // text is the first 4000 characters, or null when the prompt lives in worker code or a function
    settings: Setting[],                       // the settings that belong to this service
    note, reason, changed_at, changed_by       // changed_by is an email or null
  }],
  legacy_controls: {                           // read-only here; each names its existing write
    central_ai_settings: { enabled, calls_at_once, model_code, model_identifier, reason, changed_at, write: "public.admin_ai_config" },
    scholarship_chain: { chain: [code], reason, changed_at, write: "public.admin_scholarship_ai" }
  },
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
- A service with `wired: false` can still be saved; show `model_in_effect` and `note` so it is clear where its model really comes from today.
- Save a setting with `admin_toolsets_write('setting', {toolset: s.toolset, key: s.key, value, reason})`, then reload the overview. Text settings (`kind: "text"`) include the two old model keys (`entry.matrix_model`, `ops.ai_diagnosis_model`); they are no longer read, so show them read-only or leave them out.

### Example (from the test fixture, shortened: 2 of 18 models, 2 of 14 services)

```json
{
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
        "hour": "2026-11-13T08:00:00+00:00",
        "lane": "enrich_fields",
        "calls": 1,
        "model": "qwen/qwen3-30b-a3b-instruct-2507",
        "service_code": "course_description"
      },
      {
        "usd": 0.3,
        "hour": "2026-11-13T08:00:00+00:00",
        "lane": "enrich_fields",
        "calls": 1,
        "model": null,
        "service_code": "course_entry_requirements"
      }
    ]
  },
  "events": [
    {
      "at": "2026-11-13T08:48:38.531156+00:00",
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
          "daily_usd_cap": null,
          "daily_calls_cap": null
        },
        "reason": "fixture: cheaper first",
        "resolver": "route"
      },
      "target": "course_entry_requirements"
    },
    {
      "at": "2026-11-13T08:48:38.531156+00:00",
      "by": "admin@example.test",
      "action": "route_set",
      "detail": {
        "after": {
          "cascade": [
            "mistral-small-3.2",
            "qwen3-30b"
          ],
          "enabled": true,
          "daily_usd_cap": 5,
          "daily_calls_cap": null
        },
        "before": {
          "cascade": [
            "qwen3-30b"
          ],
          "enabled": true,
          "daily_usd_cap": 5,
          "daily_calls_cap": null
        },
        "reason": "fixture: central model",
        "resolver": "pipeline.central_ai_settings"
      },
      "target": "fee_reader"
    }
  ],
  "models": [
    {
      "code": "qwen3-30b",
      "note": "In use: course fields, central pages, fees, scholarships, course-page matching, adapter proposals",
      "label": "Qwen3 30B A3B Instruct (2507)",
      "family": "qwen3",
      "reason": "fixture: on again",
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
        "adapter_builder",
        "ops_diagnosis"
      ],
      "changed_at": "2026-11-13T08:48:38.531156+00:00",
      "context_tokens": 262144,
      "model_identifier": "qwen/qwen3-30b-a3b-instruct-2507",
      "price_checked_at": "2026-11-13T08:48:37.662912+00:00",
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
      "changed_at": "2026-11-13T08:48:37.662912+00:00",
      "context_tokens": 1047576,
      "model_identifier": "openai/gpt-4.1-mini",
      "price_checked_at": "2026-11-13T08:48:37.662912+00:00",
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
      "changed_at": "2026-11-13T08:48:38.531156+00:00",
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
      "note": "Shares one model with the other central readers until its reader asks the route.",
      "field": null,
      "label": "Provider description",
      "wired": false,
      "models": [
        {
          "code": "qwen3-30b",
          "model_identifier": "qwen/qwen3-30b-a3b-instruct-2507"
        },
        {
          "code": "mistral-small-3.2",
          "model_identifier": "mistralai/mistral-small-3.2-24b-instruct"
        }
      ],
      "prompt": {
        "text": "You write a provider description.",
        "source": "pipeline.provider_description_prompts",
        "version": "4"
      },
      "reason": "old card",
      "cascade": [
        "qwen3-30b",
        "mistral-small-3.2"
      ],
      "enabled": true,
      "resolver": "pipeline.central_ai_settings",
      "settings": [],
      "held_kind": null,
      "changed_at": "2026-11-13T08:48:38.531156+00:00",
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
        },
        {
          "code": "mistral-small-3.2",
          "label": "Mistral Small 3.2 24B",
          "status": "allowed",
          "model_identifier": "mistralai/mistral-small-3.2-24b-instruct"
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
    "spent_today_usd": 1.602,
    "daily_ceiling_usd": 14,
    "total_credits_usd": 100,
    "balance_observed_at": "2026-11-13T08:48:35.969786+00:00"
  },
  "can_control": true,
  "legacy_controls": {
    "scholarship_chain": {
      "chain": [
        "qwen3-30b"
      ],
      "write": "public.admin_scholarship_ai",
      "reason": "Platform Admin 13 Nov 2026 19:23: GPT-4.1 mini is not used any more (migration 20261113380000)",
      "changed_at": "2026-11-13T08:48:37.662912+00:00"
    },
    "central_ai_settings": {
      "write": "public.admin_ai_config",
      "reason": "Models & services: the central readers route",
      "enabled": true,
      "changed_at": "2026-11-13T08:48:38.531156+00:00",
      "model_code": "qwen3-30b",
      "calls_at_once": 2,
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

Saves the route whole: send the full cascade and both caps every time (`null` cap = no cap). `p_enabled: null` keeps the switch as it is.

```js
const { data, error } = await supabase.rpc('admin_ai_route_set_v1', {
  p_service: 'course_entry_requirements', p_cascade: ['qwen3-30b', 'mistral-small-3.2'],
  p_daily_usd_cap: 5, p_daily_calls_cap: null, p_enabled: true, p_reason: 'cap the entry requirements read at US$5 a day' })
```

## 4. What a route controls today

| resolver | Services | Effect of saving the route |
|---|---|---|
| `route` | course_description, course_entry_requirements, course_other_fields, entry_matrices, ops_diagnosis | Model, caps and switch take effect on the next reader call. The deployed worker uses the first model only (the cascade is handed to it as `models` for a later worker change). The description and the other course fields share one model in the deployed worker: the description route's first model while that route flows |
| `pipeline.central_ai_settings` | provider_description, calendar_reading, central_english_policy, fee_reader | These four readers still read one shared model. Saving one of them copies its cascade to the other three and sets the shared model to the first allowed one. Their caps and switch are stored but not yet enforced by their readers |
| `pipeline.scholarship_ai_extract_settings` | scholarship_extraction, scholarship_eligibility | Stored only. The reader follows its own chain (`legacy_controls.scholarship_chain`) |
| `firecrawl.builder_model` | adapter_builder | Stored only. The model is the setting `firecrawl.builder_model`, shown under the service's settings |
| `pipeline.aer_prompt_versions` | entry_requirements_v2_shadow | Stored only. The model is pinned on the prompt version |
| `worker code` | course_matching | Stored only. The model is fixed in the worker |

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
