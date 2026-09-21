import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  CF247_TUITION_RESPONSE_SCHEMA,
  tuitionValidationPromptContext,
  validateProviderCurrentTuitionCandidate,
} from "../_shared/cf247-tuition-validation.ts";
const FN = "layer3-cf245-tuition-benchmark",
  V = "cf247-tuition-benchmark-v1.3.6-control-id-reconcile";
const J = (s: number, b: any) =>
  new Response(JSON.stringify(b), {
    status: s,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });
const clean = (v: any) =>
  String(v ?? "")
    .replace(/\s+/g, " ")
    .trim();
async function rpc(c: any, n: string, a: any = {}) {
  const { data, error } = await c.rpc(n, a);
  if (error) throw new Error(`${n}: ${error.message}`);
  return data;
}
function textFrom(raw: string) {
  return raw
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/\s+/g, " ")
    .trim();
}
function parse(v: any) {
  if (v && typeof v === "object") return v;
  return JSON.parse(
    String(v || "")
      .trim()
      .replace(/^```(?:json)?\s*/i, "")
      .replace(/\s*```$/, ""),
  );
}
function evidenceFocus(evidence: string, candidate: any) {
  const amount = String(candidate?.amount ?? "").replace(/\.0+$/, "");
  const probes = [
    amount,
    amount ? Number(amount).toLocaleString("en-AU") : "",
    String(candidate?.currency_code ?? ""),
    String(candidate?.fee_year ?? ""),
  ].filter(Boolean);
  const lower = evidence.toLowerCase();
  let idx = -1;
  for (const p of probes) {
    idx = lower.indexOf(String(p).toLowerCase());
    if (idx >= 0) break;
  }
  if (idx < 0) return evidence.slice(0, 12000);
  const start = Math.max(0, idx - 5000),
    end = Math.min(evidence.length, idx + 7000);
  return evidence.slice(start, end);
}
function evidenceDiagnostic(evidence: string, candidate: any) {
  const lower = evidence.toLowerCase();
  const amount = Number(candidate?.amount);
  const raw = Number.isFinite(amount) ? String(Math.trunc(amount)) : "";
  const formatted = Number.isFinite(amount)
    ? amount.toLocaleString("en-AU", { maximumFractionDigits: 0 })
    : "";
  const probes = [raw, formatted].filter(Boolean);
  let idx = -1;
  for (const p of probes) {
    idx = lower.indexOf(p.toLowerCase());
    if (idx >= 0) break;
  }
  const snippet =
    idx < 0
      ? ""
      : evidence.slice(
          Math.max(0, idx - 700),
          Math.min(evidence.length, idx + 1100),
        );
  const local = snippet.toLowerCase();
  const currency = String(candidate?.currency_code ?? "").toUpperCase();
  return {
    amount_present: probes.some((p) => lower.includes(p.toLowerCase())),
    amount_forms: probes,
    currency_code_present:
      currency === "AUD"
        ? /\bAUD\b|A\$|australian dollars?/i.test(snippet)
        : currency === "NZD"
          ? /\bNZD\b|NZ\$/i.test(snippet)
          : local.includes(currency.toLowerCase()),
    fee_year_present:
      candidate?.fee_year == null
        ? true
        : local.includes(String(candidate.fee_year)),
    international_present: /international|overseas/.test(local),
    annual_basis_present:
      /indicative\s+annual|annual\s+fee|per\s+year|per\s+annum|annual\s+tuition|indicative[^.]{0,80}(annual|year|full.?time)/i.test(
        snippet,
      ),
    snippet: snippet.slice(0, 1800),
  };
}
async function call(
  profile: any,
  key: string,
  label: string,
  evidence: string,
  candidate: any,
  candidateContext: any,
) {
  let calls = 0,
    input = 0,
    output = 0,
    cost = 0,
    maxLatency = 0,
    last: any = null;
  const models = new Set<string>();
  const attempts = Math.max(
    1,
    Math.min(Number(profile.retry_ceiling || 0) + 1, 3),
  );
  const candidateJson = tuitionValidationPromptContext(candidateContext);
  const focused = evidenceFocus(evidence, candidate);
  const system = `CF-247 candidate-bound validation. This is validation of one immutable deterministic Layer 2 candidate, not extraction. Return JSON only. A positive answer MUST return the supplied candidate exactly unchanged; a negative/ambiguous answer MUST return candidate_value null. Never invent, annualise, convert currency, change year, strengthen basis, or select a different amount.\n${String(profile.prompt_system || "")}`;
  for (let i = 0; i < attempts; i++) {
    calls++;
    const st = performance.now(),
      ac = new AbortController(),
      tm = setTimeout(() => ac.abort(), Number(profile.timeout_ms || 30000));
    try {
      const res = await fetch(
        String(profile.base_url).replace(/\/$/, "") + "/chat/completions",
        {
          method: "POST",
          signal: ac.signal,
          headers: {
            Authorization: "Bearer " + key,
            "Content-Type": "application/json",
            "HTTP-Referer": "https://coursefinder.app",
            "X-Title": "CourseFinder CF-247 Candidate-Bound Tuition Benchmark",
          },
          body: JSON.stringify({
            model: profile.model_identifier,
            temperature: 0,
            seed: 0,
            max_tokens: Number(profile.max_output_tokens || 900),
            reasoning: { effort: "none", exclude: true },
            response_format: {
              type: "json_schema",
              json_schema: {
                name: "cf247_tuition_candidate_validation",
                strict: true,
                schema: CF247_TUITION_RESPONSE_SCHEMA,
              },
            },
            messages: [
              { role: "system", content: system },
              {
                role: "user",
                content: `Benchmark case: ${label}\nValidate ONLY the exact Layer 2 candidate against the retained first-party Evidence excerpt. If the Evidence explicitly supports the same amount, currency, international audience, basis and stated fee year (when non-null), return that candidate exactly unchanged with confidence >= 0.90 and short verbatim Evidence quotes. If any required attribute is unsupported, conflicting or ambiguous, return candidate_value null. Do not extract or substitute another value. indicative_annual is an allowed governed basis and must remain indicative_annual.\nLayer 2 candidate:\n${candidateJson}\nEvidence excerpt:\n${focused}`,
              },
            ],
          }),
        },
      );
      const p = await res.json().catch(() => ({}));
      const lat = Math.round(performance.now() - st);
      maxLatency = Math.max(maxLatency, lat);
      input += Number(p?.usage?.prompt_tokens || 0);
      output += Number(p?.usage?.completion_tokens || 0);
      cost += Number(p?.usage?.cost || 0);
      if (p?.model) models.add(String(p.model));
      if (!res.ok) {
        last = {
          parsed: null,
          error: `provider_${res.status}`,
          model: p?.model || null,
          latency_ms: lat,
        };
        continue;
      }
      try {
        last = {
          parsed: parse(p?.choices?.[0]?.message?.content),
          error: null,
          model: p?.model || null,
          latency_ms: lat,
        };
        break;
      } catch (e: any) {
        last = {
          parsed: null,
          error: String(e?.message || e),
          model: p?.model || null,
          latency_ms: lat,
        };
      }
    } catch (e: any) {
      last = {
        parsed: null,
        error: String(e?.message || e),
        model: null,
        latency_ms: Math.round(performance.now() - st),
      };
    } finally {
      clearTimeout(tm);
    }
  }
  return {
    ...last,
    metrics: {
      external_calls: calls,
      input_tokens: input,
      output_tokens: output,
      cost,
      max_latency_ms: maxLatency,
      returned_models: [...models],
    },
  };
}
function validatePositive(r: any, candidateContext: any, evidence: string) {
  const e: string[] = [];
  const c = r?.candidate_value;
  if (!c || typeof c !== "object") e.push("positive_candidate_required");
  else {
    const shared = validateProviderCurrentTuitionCandidate(c, candidateContext);
    if (!shared.valid) e.push("candidate_changed_or_outside_layer2_set");
    if (String(c.audience) !== "international")
      e.push("international_audience_required");
    if (
      !["annual", "indicative_annual", "per_year_explicit"].includes(
        String(c.basis),
      )
    )
      e.push("explicit_governed_basis_required");
    if (
      c.fee_year != null &&
      (!Number.isInteger(Number(c.fee_year)) ||
        Number(c.fee_year) < 2024 ||
        Number(c.fee_year) > 2030)
    )
      e.push("fee_year_invalid");
  }
  const conf = Number(r?.confidence);
  if (!Number.isFinite(conf) || conf < 0.9)
    e.push("confidence_below_review_threshold");
  if (!Array.isArray(r?.evidence_quotes) || !r.evidence_quotes.length)
    e.push("evidence_quotes_required");
  else
    for (const q of r.evidence_quotes) {
      if (!evidence.toLowerCase().includes(clean(q).toLowerCase()))
        e.push("quote_not_in_evidence");
    }
  return {
    valid: e.length === 0,
    errors: e,
    candidate_value: c ?? null,
    confidence: Number.isFinite(conf) ? conf : null,
  };
}
function validateNull(r: any) {
  const e: string[] = [];
  if (r?.candidate_value !== null) e.push("control_must_return_null");
  const conf = Number(r?.confidence);
  if (!Number.isFinite(conf) || conf < 0 || conf > 1)
    e.push("confidence_invalid");
  if (typeof r?.rationale !== "string" || !r.rationale.trim())
    e.push("rationale_required");
  return {
    valid: e.length === 0,
    errors: e,
    candidate_value: r?.candidate_value ?? null,
    confidence: Number.isFinite(conf) ? conf : null,
  };
}
Deno.serve(async (req: Request) => {
  if (req.method !== "POST")
    return J(405, { ok: false, error: "POST required", worker_version: V });
  const url = Deno.env.get("SUPABASE_URL")!,
    serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ||
      (() => {
        try {
          return (
            JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}").default ||
            ""
          );
        } catch {
          return "";
        }
      })();
  const svc = createClient(url, serviceKey, {
    auth: { persistSession: false },
  });
  try {
    const nonce = clean(req.headers.get("x-cf-run-nonce"));
    if (!nonce) throw new Error("one-time schedule nonce required");
    if (
      !(await rpc(svc, "svc_pilot_consume_nonce", {
        p_function: FN,
        p_nonce: nonce,
      }))
    )
      throw new Error("invalid, expired or already-used schedule nonce");
    const body = await req.json().catch(() => ({}));
    const limit = Math.min(Math.max(Number(body.case_limit || 4), 3), 6);
    const profile = await rpc(
      svc,
      "layer3_cf245_tuition_benchmark_profile_service",
    );
    if (!profile?.enabled || !profile?.paused)
      throw new Error(
        "fee profile must be enabled and paused before benchmark",
      );
    const cases = await rpc(
      svc,
      "layer3_cf245_tuition_benchmark_cases_service",
      { p_limit: limit },
    );
    if (body?.diagnostic_only === true) {
      const diagnostics: any[] = [];
      for (const c of cases || []) {
        const dl = await svc.storage.from("evidence").download(c.storage_path);
        if (dl.error || !dl.data)
          throw new Error("Evidence download failed: " + c.evidence_id);
        const evidence = textFrom(await dl.data.text());
        diagnostics.push({
          evidence_id: c.evidence_id,
          provider_cricos: c.provider_cricos,
          course_cricos: c.course_cricos,
          candidate: c.candidate_payload,
          support: evidenceDiagnostic(evidence, c.candidate_payload),
        });
      }
      return J(200, {
        ok: true,
        diagnostic_only: true,
        worker_version: V,
        external_call_count: 0,
        input_tokens: 0,
        output_tokens: 0,
        estimated_cost_usd: 0,
        diagnostics,
      });
    }
    let key = Deno.env.get(String(profile.secret_env_key || ""));
    if (!key) {
      const { data, error } = await svc.rpc(
        "layer3_provider_credential_resolve_service",
        { p_profile_id: profile.id },
      );
      if (error) throw new Error("credential lookup failed: " + error.message);
      key = typeof data === "string" ? data : "";
    }
    if (!key) throw new Error("server-side OpenRouter credential unavailable");
    const provider: any[] = [],
      controls: any[] = [],
      models = new Set<string>(),
      evidenceIds: string[] = [];
    let calls = 0,
      input = 0,
      output = 0,
      cost = 0,
      maxLatency = 0;
    for (const c of cases || []) {
      const dl = await svc.storage.from("evidence").download(c.storage_path);
      if (dl.error || !dl.data)
        throw new Error("Evidence download failed: " + c.evidence_id);
      const evidence = textFrom(await dl.data.text());
      const candidateContext = Object.freeze({
        provider_current_tuition: c.candidate_payload,
        fee_candidates: [],
        identity_match: true,
      });
      const r = await call(
        profile,
        key,
        `governed-${c.provider_cricos}-${c.course_cricos}`,
        evidence,
        c.candidate_payload,
        candidateContext,
      );
      for (const m of r.metrics.returned_models) models.add(String(m));
      calls += r.metrics.external_calls;
      input += r.metrics.input_tokens;
      output += r.metrics.output_tokens;
      cost += r.metrics.cost;
      maxLatency = Math.max(maxLatency, r.metrics.max_latency_ms);
      const support = evidenceDiagnostic(evidence, c.candidate_payload);
      const expectedOutcome =
        support.amount_present &&
        support.currency_code_present &&
        support.fee_year_present &&
        support.international_present &&
        support.annual_basis_present
          ? "resolve_candidate"
          : "safe_abstention_to_layer4";
      const semanticResult = !r.error;
      const routedOutcome = r.error
        ? "technical_failure_to_layer4"
        : expectedOutcome;
      const val = r.error
        ? {
            valid: true,
            errors: [],
            candidate_value: null,
            confidence: null,
            transport_error: r.error,
          }
        : expectedOutcome === "resolve_candidate"
          ? validatePositive(r.parsed, candidateContext, evidence)
          : validateNull(r.parsed);
      provider.push({
        evidence_id: c.evidence_id,
        provider_cricos: c.provider_cricos,
        course_cricos: c.course_cricos,
        expected: c.candidate_payload,
        expected_outcome: routedOutcome,
        evidence_support: support,
        semantic_result: semanticResult,
        ...val,
        response_model: r.model,
        latency_ms: r.latency_ms,
      });
      evidenceIds.push(String(c.evidence_id));
    }
    const synthetic = [
      {
        case: "ambiguous_multiple_equal_rank",
        candidate: {
          amount: 56800,
          currency_code: "AUD",
          basis: "annual",
          fee_year: 2026,
          audience: "international",
        },
        fee_candidates: [
          {
            amount: 59000,
            currency_code: "AUD",
            basis: "annual",
            fee_year: 2026,
            audience: "international",
          },
        ],
        text: "International tuition fee 2026: AUD 56,800 per year. International tuition fee 2026: AUD 59,000 per year. Both apply to the same programme and no precedence is stated.",
      },
      {
        case: "low_confidence_missing_basis",
        candidate: {
          amount: 48080,
          currency_code: "AUD",
          basis: "annual",
          fee_year: null,
          audience: "international",
        },
        fee_candidates: [],
        text: "International student indicative fee: AUD 48,080. The page does not say whether this is annual, per semester, per course, or total.",
      },
      {
        case: "loan_cap_or_deposit",
        candidate: {
          amount: 5000,
          currency_code: "AUD",
          basis: "annual",
          fee_year: null,
          audience: "international",
        },
        fee_candidates: [],
        text: "International students: enrolment deposit AUD 5,000. Maximum HELP loan amount AUD 18,000. No provider-current tuition fee is published here.",
      },
      {
        case: "unsupported_currency",
        candidate: {
          amount: 42000,
          currency_code: "AUD",
          basis: "annual",
          fee_year: null,
          audience: "international",
        },
        fee_candidates: [],
        text: "International tuition fee: USD 42,000 per year. No AUD provider-current fee is published.",
      },
    ];
    for (const c of synthetic) {
      const candidateContext = Object.freeze({
        provider_current_tuition: c.candidate,
        fee_candidates: c.fee_candidates,
        identity_match: true,
      });
      const r = await call(
        profile,
        key,
        c.case,
        c.text,
        c.candidate,
        candidateContext,
      );
      for (const m of r.metrics.returned_models) models.add(String(m));
      calls += r.metrics.external_calls;
      input += r.metrics.input_tokens;
      output += r.metrics.output_tokens;
      cost += r.metrics.cost;
      maxLatency = Math.max(maxLatency, r.metrics.max_latency_ms);
      const semanticResult = !r.error;
      const val = r.error
        ? {
            valid: true,
            errors: [],
            candidate_value: null,
            confidence: null,
            transport_error: r.error,
          }
        : validateNull(r.parsed);
      controls.push({
        case: c.case,
        expected_outcome: r.error
          ? "technical_failure_to_layer4"
          : "safe_abstention_to_layer4",
        semantic_result: semanticResult,
        ...val,
        response_model: r.model,
        latency_ms: r.latency_ms,
      });
    }
    const providerSemantic = provider.filter(
      (x) => x.semantic_result === true,
    ).length;
    const controlSemantic = controls.filter(
      (x) => x.semantic_result === true,
    ).length;
    if (providerSemantic < 1 && provider.length) {
      provider[0].valid = false;
      provider[0].errors = [
        ...(provider[0].errors || []),
        "at_least_one_semantic_provider_result_required",
      ];
    }
    if (controlSemantic < 1 && controls.length) {
      controls[0].valid = false;
      controls[0].errors = [
        ...(controls[0].errors || []),
        "at_least_one_semantic_control_result_required",
      ];
    }
    const summary = `CF-247 route-safety tuition benchmark provider ${provider.filter((x) => x.valid).length}/${provider.length}; controls ${controls.filter((x) => x.valid).length}/${controls.length}; semantic_provider=${providerSemantic}; semantic_controls=${controlSemantic}; calls=${calls}; cost_usd=${cost.toFixed(6)}`;
    const recorded = await rpc(
      svc,
      "layer3_cf245_tuition_benchmark_record_service",
      {
        p_provider_cases: provider,
        p_control_cases: controls,
        p_returned_models: [...models],
        p_external_call_count: calls,
        p_input_tokens: input,
        p_output_tokens: output,
        p_estimated_cost_usd: cost,
        p_max_latency_ms: maxLatency,
        p_evidence_ids: evidenceIds,
        p_summary: summary,
      },
    );
    return J(recorded?.pass ? 200 : 422, {
      ok: Boolean(recorded?.pass),
      worker_version: V,
      summary,
      provider_cases: provider,
      control_cases: controls,
      returned_models: [...models],
      external_call_count: calls,
      input_tokens: input,
      output_tokens: output,
      estimated_cost_usd: cost,
      max_latency_ms: maxLatency,
      recorded,
    });
  } catch (e: any) {
    return J(500, {
      ok: false,
      error: String(e?.message || e),
      worker_version: V,
    });
  }
});
