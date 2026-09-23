import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  tuitionQuoteSupports,
  tuitionQuoteSupportsBasis,
  tuitionValidationPromptContext,
  validateProviderCurrentTuitionCandidate,
} from "../_shared/cf247-tuition-validation.ts";
import { CF247_TUITION_BINDING_SOURCE_MANIFEST } from "../_shared/cf247-tuition-binding-source-manifest.ts";
import { tuitionBenchmarkRuntimeBindingHash } from "../_shared/cf247-tuition-benchmark-binding.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
const parseJson = (value: unknown) => {
  if (value && typeof value === "object")
    return value as Record<string, unknown>;
  if (typeof value !== "string")
    throw new Error("model response content is not JSON text");
  return JSON.parse(
    value
      .trim()
      .replace(/^```(?:json)?\s*/i, "")
      .replace(/\s*```$/, ""),
  );
};
const evidenceText = (
  bytes: Uint8Array,
  mime: string | null,
  maxChars: number,
) => {
  const allowed = [
    "text/",
    "application/json",
    "application/xml",
    "application/xhtml+xml",
  ];
  if (mime && !allowed.some((x) => mime.startsWith(x)))
    throw new Error(`evidence MIME type ${mime} is not supported`);
  let text = new TextDecoder("utf-8", { fatal: false }).decode(bytes);
  if (
    mime?.includes("html") ||
    /<html|<body|<div|<p[ >]/i.test(text.slice(0, 1000))
  )
    text = text
      .replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<[^>]+>/g, " ")
      .replace(/&nbsp;/g, " ")
      .replace(/&amp;/g, "&");
  return text.replace(/\s+/g, " ").trim().slice(0, maxChars);
};

// CF-247: Layer 4 reviewers see a plain-English reason (what happened, what to
// check). The technical detail stays in validator_result for engineers.
const feeLabel = (amount: unknown, currency: unknown) => {
  const n = Number(amount);
  if (!Number.isFinite(n) || n <= 0) return "the fee";
  const c = String(currency ?? "").trim().toUpperCase();
  const prefix = c === "AUD" ? "A$" : c === "NZD" ? "NZ$" : c ? `${c} ` : "";
  return prefix + n.toLocaleString("en-AU", { maximumFractionDigits: 2 });
};
function plainLayer4Reason(
  errors: string[],
  status: string,
  candidate: any,
  target: any,
): string {
  const fee = feeLabel(target?.amount ?? candidate?.amount, target?.currency_code ?? candidate?.currency_code);
  const has = (s: string) => errors.some((e) => String(e).includes(s));
  if (has("evidence quote not present") || has("invalid evidence quote"))
    return `The AI quoted text that isn't on the saved page, so its answer can't be trusted. Please check the page and confirm ${fee}.`;
  if (has("identity_match"))
    return `We couldn't confirm this page belongs to this course. Please check it's the right page before confirming ${fee}.`;
  if (has("resolved fee year"))
    return `The AI gave the year ${candidate?.fee_year ?? "shown"}, but the page doesn't show that year next to ${fee}. Please confirm the fee year.`;
  if (has("resolved tuition basis"))
    return `The page doesn't clearly say ${fee} is charged per year. Please confirm whether it is an annual fee.`;
  if (has("does not match the sole governed"))
    return `The AI's answer didn't match the fee Layer 2 found (${fee}), so it wasn't accepted automatically. Please confirm the fee on the page.`;
  if (has("cost ceiling"))
    return `This check cost more than the allowed limit and was stopped. Please review ${fee} manually.`;
  if (status === "low_confidence" || has("confidence outside"))
    return `The AI wasn't confident enough (below 90%) that ${fee} is the annual international tuition fee. Please check the page.`;
  if (status === "no_candidate" || candidate == null)
    return `The page doesn't clearly show ${fee} as an annual tuition fee for international students. Please check the page and confirm the fee, or mark it as not available.`;
  return `The AI's answer for ${fee} couldn't be accepted automatically. Please check the page and confirm the fee.`;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL") || "";
  const serviceKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ||
    (() => {
      try {
        return (
          JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}").default || ""
        );
      } catch {
        return "";
      }
    })();
  if (!url || !serviceKey)
    return json({ error: "server configuration unavailable" }, 500);
  const token = (req.headers.get("Authorization") || "").replace(
    /^Bearer\s+/i,
    "",
  );
  if (!token || token !== serviceKey)
    return json({ error: "service role required" }, 403);
  const svc = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  let workItemId = "";
  let interpretationId = "";
  let externalCallCount = 0;
  let workAttemptCount = 0;
  let startedMs: number | null = null;
  let reviewFee = "the fee";
  try {
    const body = await req.json();
    workItemId = String(body?.work_item_id || "");
    const worker = String(body?.worker || "").trim();
    if (!workItemId || !worker)
      return json({ error: "work_item_id and worker are required" }, 400);

    const { data: reservation, error: reserveError } = await svc.rpc(
      "layer3_reserve_work_interpretation_service",
      { p_work_item_id: workItemId, p_worker: worker },
    );
    if (reserveError)
      return json(
        {
          error:
            reserveError.message || "work interpretation reservation failed",
        },
        409,
      );
    interpretationId = String(reservation?.interpretation_id || "");
    const evidenceId = String(reservation?.evidence_id || "");
    workAttemptCount = Number(reservation?.attempt_count || 0);
    const taskClass = String(reservation?.task_class || "");
    const candidateContext = reservation?.candidate_context || null;
    const evidence = reservation?.evidence || {};
    const profile = reservation?.profile || {};
    reviewFee = feeLabel(
      candidateContext?.provider_current_tuition?.amount,
      candidateContext?.provider_current_tuition?.currency_code,
    );
    if (!interpretationId || !evidenceId || !profile?.id)
      throw new Error("reserved work interpretation context incomplete");
    if (taskClass !== "provider_current_tuition_validation")
      throw new Error(
        "service worker currently permits only provider_current_tuition_validation",
      );
    const qualifiedBindingHash = String(
      profile?.quality_benchmark?.binding_hash || "",
    );
    if (!qualifiedBindingHash)
      throw new Error(
        "profile has no qualified binding hash on record; execution refused",
      );
    const currentBindingHash = await tuitionBenchmarkRuntimeBindingHash(
      CF247_TUITION_BINDING_SOURCE_MANIFEST,
      profile,
    );
    if (currentBindingHash !== qualifiedBindingHash)
      throw new Error(
        "current source/profile binding hash does not match the qualified benchmark; execution refused",
      );

    const { data: usage, error: usageError } = await svc.rpc(
      "layer3_usage_window_service",
      { p_profile_id: profile.id },
    );
    if (usageError)
      throw new Error(`usage check failed: ${usageError.message}`);
    if (
      Number(usage?.minute_calls || 0) >=
      Number(profile.requests_per_minute || 1)
    )
      throw new Error("profile requests/minute ceiling reached");
    if (Number(usage?.day_calls || 0) >= Number(profile.requests_per_day || 1))
      throw new Error("profile requests/day ceiling reached");

    if (
      !evidence?.storage_path ||
      !evidence?.content_hash ||
      String(evidence?.id || "") !== evidenceId
    )
      throw new Error("reserved governed Evidence context incomplete");
    const { data: blob, error: storageError } = await svc.storage
      .from("evidence")
      .download(String(evidence.storage_path));
    if (storageError || !blob)
      throw new Error(
        `Evidence download failed: ${storageError?.message || "not found"}`,
      );
    const text = evidenceText(
      new Uint8Array(await blob.arrayBuffer()),
      evidence?.mime_type || null,
      Math.min(Number(profile.max_input_tokens || 12000) * 4, 120000),
    );
    if (text.length < 20)
      throw new Error("Evidence text is too short to interpret");

    const prompt = [
      "Task class: provider_current_tuition_validation",
      `Governed Evidence source: ${evidence?.source_url || "retained Evidence"}`,
      tuitionValidationPromptContext(candidateContext),
      "Return exactly one JSON object with keys candidate_value, confidence, rationale, evidence_quotes. candidate_value must be null or one supplied tuition candidate with amount, currency_code, basis, fee_year and audience. Evidence must explicitly support any basis resolution; otherwise return null.",
      `Evidence:\n${text}`,
    ].join("\n\n");

    let providerKey = String(profile.secret_env_key || "")
      ? Deno.env.get(String(profile.secret_env_key))
      : undefined;
    if (!providerKey) {
      const { data: resolved, error: credentialError } = await svc.rpc(
        "layer3_provider_credential_resolve_service",
        { p_profile_id: profile.id },
      );
      if (credentialError)
        throw new Error(
          `provider credential lookup failed: ${credentialError.message}`,
        );
      providerKey = typeof resolved === "string" ? resolved : undefined;
    }
    if (!providerKey)
      throw new Error("server-side provider credential unavailable");

    startedMs = performance.now();
    externalCallCount = 1;
    const controller = new AbortController();
    const timeout = setTimeout(
      () => controller.abort(),
      Number(profile.timeout_ms || 30000),
    );
    let response: Response;
    try {
      response = await fetch(
        `${String(profile.base_url).replace(/\/$/, "")}/chat/completions`,
        {
          method: "POST",
          signal: controller.signal,
          headers: {
            Authorization: `Bearer ${providerKey}`,
            "Content-Type": "application/json",
            "HTTP-Referer": "https://coursefinder.app",
            "X-Title": "CourseFinder CF-247 Layer 3 Tuition Validation",
          },
          body: JSON.stringify({
            model: profile.model_identifier,
            temperature: 0,
            seed: 0,
            max_tokens: Number(profile.max_output_tokens || 1200),
            provider: { require_parameters: true },
            response_format: { type: "json_object" },
            messages: [
              { role: "system", content: profile.prompt_system },
              { role: "user", content: prompt },
            ],
          }),
        },
      );
    } finally {
      clearTimeout(timeout);
    }
    const payload: any = await response.json().catch(() => ({}));
    const latencyMs = Math.round(performance.now() - startedMs);
    const inputTokens = Number(payload?.usage?.prompt_tokens || 0);
    const outputTokens = Number(payload?.usage?.completion_tokens || 0);
    const cost = Number(payload?.usage?.cost || 0);
    if (!response.ok)
      throw new Error(
        `provider ${response.status}: ${JSON.stringify(payload).slice(0, 600)}`,
      );

    const parsed: any = parseJson(payload?.choices?.[0]?.message?.content);
    const confidence = Number(parsed?.confidence);
    const errors: string[] = [];
    const min = Number(profile?.validators?.confidence_min ?? 0);
    const max = Number(profile?.validators?.confidence_max ?? 1);
    if (!Number.isFinite(confidence) || confidence < min || confidence > max)
      errors.push("confidence outside allowed range");
    if (typeof parsed?.rationale !== "string" || !parsed.rationale.trim())
      errors.push("rationale is required");
    const quotes = Array.isArray(parsed?.evidence_quotes)
      ? parsed.evidence_quotes
      : [];
    if (!Array.isArray(parsed?.evidence_quotes))
      errors.push("evidence_quotes must be an array");
    if (quotes.length > Number(profile?.validators?.max_quotes ?? 4))
      errors.push("too many evidence quotes");
    // CF-247: compare quotes ignoring whitespace (HTML-to-text spacing), while
    // characters must still match exactly and in order.
    const haystack = text.replace(/\s+/g, "").toLowerCase();
    for (const quote of quotes) {
      if (
        typeof quote !== "string" ||
        quote.length > Number(profile?.validators?.max_quote_chars ?? 600)
      )
        errors.push("invalid evidence quote");
      else if (
        quote.trim() &&
        !haystack.includes(quote.replace(/\s+/g, "").toLowerCase())
      )
        errors.push("evidence quote not present in governed Evidence");
    }
    const tuition = validateProviderCurrentTuitionCandidate(
      parsed?.candidate_value ?? null,
      candidateContext,
    );
    errors.push(...tuition.errors);
    if (tuition.basis_resolution && parsed?.candidate_value) {
      const explicitBasisSupport = tuitionQuoteSupportsBasis(
        quotes,
        parsed.candidate_value.amount,
        parsed.candidate_value.basis,
      );
      if (!explicitBasisSupport)
        errors.push(
          "Evidence quote does not explicitly support the resolved tuition basis",
        );
    }
    // CF-247 option A: a fee year supplied by Layer 3 (target had none) must be
    // stated in a returned Evidence quote together with the amount.
    if (tuition.year_resolution && parsed?.candidate_value) {
      if (
        !tuitionQuoteSupports(
          quotes,
          parsed.candidate_value.amount,
          parsed.candidate_value.fee_year,
        )
      )
        errors.push(
          "Evidence quote does not state the resolved fee year together with the amount",
        );
    }
    if (
      Number(profile.cost_ceiling_usd) >= 0 &&
      cost > Number(profile.cost_ceiling_usd)
    )
      errors.push("response exceeded configured cost ceiling");
    const valid = errors.length === 0;
    const validatorResult = {
      valid,
      errors,
      candidate_bound: tuition.valid,
      matched_candidate: tuition.matched_candidate,
      basis_resolution: tuition.basis_resolution,
    };
    const expiry = valid
      ? new Date(Date.now() + 30 * 86400000).toISOString()
      : null;
    const { data: completed, error: completeError } = await svc.rpc(
      "layer3_complete_interpretation_service",
      {
        p_interpretation_id: interpretationId,
        p_raw_result: payload,
        p_candidate_value: parsed?.candidate_value ?? null,
        p_confidence: Number.isFinite(confidence) ? confidence : null,
        p_rationale:
          typeof parsed?.rationale === "string"
            ? parsed.rationale
            : "Structured output validation failed",
        p_evidence_quotes: quotes,
        p_validator_result: validatorResult,
        p_valid: valid,
        p_response_model: payload?.model || null,
        p_input_tokens: inputTokens || null,
        p_output_tokens: outputTokens || null,
        p_estimated_cost_usd: cost,
        p_expiry: expiry,
        p_external_call_count: externalCallCount,
        p_call_latency_ms: latencyMs,
      },
    );
    if (completeError)
      throw new Error(
        `completion persistence failed: ${completeError.message}`,
      );
    const interpretationStatus = String(
      completed?.status ||
        (valid
          ? parsed?.candidate_value == null
            ? "no_candidate"
            : "validated"
          : "rejected_validation"),
    );
    if (
      !valid ||
      parsed?.candidate_value == null ||
      interpretationStatus === "no_candidate" ||
      interpretationStatus === "low_confidence" ||
      interpretationStatus === "rejected_validation"
    ) {
      const routeReason = plainLayer4Reason(
        errors,
        interpretationStatus,
        parsed?.candidate_value ?? null,
        candidateContext?.provider_current_tuition ?? null,
      );
      const { data: routed, error: routeError } = await svc.rpc(
        "layer3_route_work_item_layer4_service",
        {
          p_work_item_id: workItemId,
          p_interpretation_id: interpretationId,
          p_reason: routeReason,
        },
      );
      if (routeError || !routed?.ok)
        throw new Error(
          `Layer 4 routing failed: ${routeError?.message || "not applied"}`,
        );
      return json({
        ok: true,
        work_item_id: workItemId,
        interpretation_id: interpretationId,
        interpretation_status: interpretationStatus,
        status: "layer4_required",
        validator_result: validatorResult,
        review_item_id:
          routed?.review_item_id || completed?.review_item_id || null,
        input_tokens: inputTokens,
        output_tokens: outputTokens,
        estimated_cost_usd: cost,
        call_latency_ms: latencyMs,
      });
    }

    const { data: transition, error: transitionError } = await svc.rpc(
      "layer3_work_item_transition_service",
      {
        p_work_item_id: workItemId,
        p_from_status: "interpreting",
        p_to_status: "validated",
        p_interpretation_id: interpretationId,
        p_error: null,
        p_retry_after_seconds: null,
      },
    );
    if (transitionError || !transition?.ok)
      throw new Error(
        `work item completion transition failed: ${transitionError?.message || "not applied"}`,
      );
    return json({
      ok: true,
      work_item_id: workItemId,
      interpretation_id: interpretationId,
      status: "validated",
      validator_result: validatorResult,
      review_item_id: completed?.review_item_id || null,
      input_tokens: inputTokens,
      output_tokens: outputTokens,
      estimated_cost_usd: cost,
      call_latency_ms: latencyMs,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (interpretationId) {
      try {
        await svc.rpc("layer3_fail_interpretation_service", {
          p_interpretation_id: interpretationId,
          p_error: message,
          p_external_call_count: externalCallCount,
          p_call_latency_ms:
            startedMs == null
              ? null
              : Math.round(performance.now() - startedMs),
        });
      } catch {
        /* preserve original failure; work-item transition below remains authoritative */
      }
    }
    if (workItemId) {
      const attempts = workAttemptCount;
      if (interpretationId && attempts >= 5) {
        const { data: routed, error: routeError } = await svc.rpc(
          "layer3_route_work_item_layer4_service",
          {
            p_work_item_id: workItemId,
            p_interpretation_id: interpretationId,
            p_reason: `The AI service couldn't be reached after ${attempts} attempts, so ${reviewFee} couldn't be checked automatically. Please check the page and confirm the fee.`,
          },
        );
        if (!routeError && routed?.ok) {
          return json({
            ok: true,
            work_item_id: workItemId,
            interpretation_id: interpretationId,
            status: "layer4_required",
            review_item_id: routed?.review_item_id || null,
            exhausted_attempts: attempts,
            provider_error: message,
          });
        }
      }
      try {
        await svc.rpc("layer3_work_item_transition_service", {
          p_work_item_id: workItemId,
          p_from_status: "interpreting",
          p_to_status: "failed",
          p_interpretation_id: interpretationId || null,
          p_error: message,
          p_retry_after_seconds: 60,
        });
      } catch {
        /* return original interpreter failure below */
      }
    }
    return json(
      {
        error: message,
        work_item_id: workItemId || null,
        interpretation_id: interpretationId || null,
      },
      /ceiling|credential|not executable/i.test(message) ? 409 : 500,
    );
  }
});
