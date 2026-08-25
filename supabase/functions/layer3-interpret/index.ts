import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });

function parseJsonContent(content: unknown): unknown {
  if (typeof content === "object" && content !== null) return content;
  if (typeof content !== "string") throw new Error("model response content is not JSON text");
  const cleaned = content.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
  return JSON.parse(cleaned);
}

function validateCandidate(taskClass: string, result: any, validators: any) {
  const errors: string[] = [];
  if (!result || typeof result !== "object" || Array.isArray(result)) errors.push("result must be an object");
  const confidence = Number(result?.confidence);
  const min = Number(validators?.confidence_min ?? 0);
  const max = Number(validators?.confidence_max ?? 1);
  if (!Number.isFinite(confidence) || confidence < min || confidence > max) errors.push("confidence outside allowed range");
  if (typeof result?.rationale !== "string" || result.rationale.trim().length === 0) errors.push("rationale is required");
  if (typeof result?.rationale === "string" && result.rationale.length > Number(validators?.max_rationale_chars ?? 1600)) errors.push("rationale too long");
  if (!Array.isArray(result?.evidence_quotes)) errors.push("evidence_quotes must be an array");
  const quotes = Array.isArray(result?.evidence_quotes) ? result.evidence_quotes : [];
  if (quotes.length > Number(validators?.max_quotes ?? 4)) errors.push("too many evidence quotes");
  for (const q of quotes) if (typeof q !== "string" || q.length > Number(validators?.max_quote_chars ?? 600)) errors.push("invalid evidence quote");

  const candidate = result?.candidate_value;
  if (candidate !== null && candidate !== undefined) {
    if (taskClass === "course_description" || taskClass === "delivery_mode") {
      if (typeof candidate !== "string" || candidate.trim().length === 0) errors.push("candidate must be a non-empty string");
    } else if (taskClass === "official_course_url") {
      if (typeof candidate !== "string" || !/^https?:\/\/\S+$/i.test(candidate)) errors.push("candidate must be an http/https URL");
    } else if (taskClass === "duration") {
      if (!candidate || typeof candidate !== "object" || !(Number(candidate.value) > 0) || typeof candidate.unit !== "string" || !candidate.unit.trim()) errors.push("duration requires positive value and unit");
    } else errors.push("unsupported task class");
  }
  return { valid: errors.length === 0, errors, confidence: Number.isFinite(confidence) ? confidence : null };
}

function evidenceToText(bytes: Uint8Array, mime: string | null, maxChars: number) {
  const allowed = ["text/", "application/json", "application/xml", "application/xhtml+xml"];
  if (mime && !allowed.some((x) => mime.startsWith(x))) throw new Error(`evidence MIME type ${mime} is not supported for direct Layer 3 text interpretation`);
  let text = new TextDecoder("utf-8", { fatal: false }).decode(bytes);
  if (mime?.includes("html") || /<html|<body|<div|<p[ >]/i.test(text.slice(0, 1000))) {
    text = text.replace(/<script[\s\S]*?<\/script>/gi, " ").replace(/<style[\s\S]*?<\/style>/gi, " ").replace(/<[^>]+>/g, " ").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&");
  }
  return text.replace(/\s+/g, " ").trim().slice(0, maxChars);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || (() => {
    try { return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}").default || ""; } catch { return ""; }
  })();
  if (!url || !serviceKey) return json({ error: "server configuration unavailable" }, 500);

  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "authentication required" }, 401);

  const svc = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await svc.auth.getUser(token);
  if (userError || !userData?.user?.id) return json({ error: "invalid user token" }, 401);

  let interpretationId: string | null = null;
  try {
    const body = await req.json();
    const evidenceId = String(body?.evidence_id || "");
    const entityType = String(body?.entity_type || "").toLowerCase();
    const entityId = String(body?.entity_id || "");
    const taskClass = String(body?.task_class || "");
    const profileId = String(body?.profile_id || "");
    if (!evidenceId || !entityType || !entityId || !taskClass || !profileId) return json({ error: "evidence_id, entity_type, entity_id, task_class and profile_id are required" }, 400);

    const { data: reservation, error: reserveError } = await svc.rpc("layer3_reserve_interpretation_service", {
      p_actor: userData.user.id,
      p_evidence_id: evidenceId,
      p_entity_type: entityType,
      p_entity_id: entityId,
      p_task_class: taskClass,
      p_profile_id: profileId,
      p_layer2_state: body?.layer2_state || {},
      p_revalidation_ref: body?.revalidation_ref || null,
    });
    if (reserveError) {
      const msg = reserveError.message || "reservation failed";
      const status = /role required|actor required/i.test(msg) ? 403 : /not executable|not allowed/i.test(msg) ? 409 : 400;
      return json({ error: msg }, status);
    }
    if (!reservation?.call_required) return json({ ok: true, call_required: false, reason: reservation?.reason, prior_interpretation_id: reservation?.prior_interpretation_id, evidence_hash: reservation?.evidence_hash });

    interpretationId = String(reservation.interpretation_id);
    const profile = reservation.profile || {};
    const { data: usage, error: usageError } = await svc.rpc("layer3_usage_window_service", { p_profile_id: profile.id });
    if (usageError) throw new Error(`usage check failed: ${usageError.message}`);
    if (Number(usage?.minute_calls || 0) > Number(profile.requests_per_minute || 1)) throw new Error("profile requests/minute ceiling reached");
    if (Number(usage?.day_calls || 0) > Number(profile.requests_per_day || 1)) throw new Error("profile requests/day ceiling reached");

    const secretName = String(profile.secret_env_key || "");
    const aggregatorKey = secretName ? Deno.env.get(secretName) : undefined;
    if (!aggregatorKey) throw new Error(`server-side aggregator credential ${secretName || "<unset>"} is not configured`);

    const { data: ev, error: evError } = await svc.schema("pipeline").from("evidence_artifacts").select("id,storage_path,mime_type,content_hash,source_url").eq("id", evidenceId).single();
    if (evError || !ev) throw new Error(`evidence lookup failed: ${evError?.message || "not found"}`);
    if (!ev.storage_path) throw new Error("evidence has no retained storage object");
    const { data: blob, error: storageError } = await svc.storage.from("evidence").download(ev.storage_path);
    if (storageError || !blob) throw new Error(`evidence download failed: ${storageError?.message || "not found"}`);
    const bytes = new Uint8Array(await blob.arrayBuffer());
    const maxChars = Math.min(Number(profile.max_input_tokens || 12000) * 4, 120000);
    const evidenceText = evidenceToText(bytes, ev.mime_type, maxChars);
    if (evidenceText.length < 20) throw new Error("evidence text is too short to interpret");

    const prompt = [
      `Task class: ${taskClass}`,
      `Entity type: ${entityType}`,
      `Governed evidence source: ${ev.source_url || "retained evidence"}`,
      "Return exactly one JSON object with keys candidate_value, confidence, rationale, evidence_quotes.",
      "Use null candidate_value if the evidence does not support a reliable candidate. Do not infer regulatory identity.",
      `Evidence:\n${evidenceText}`,
    ].join("\n\n");

    const attempts = Math.max(1, Math.min(Number(profile.retry_ceiling || 0) + 1, 4));
    let providerResult: any = null;
    let lastError: unknown = null;
    for (let attempt = 0; attempt < attempts; attempt++) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), Number(profile.timeout_ms || 30000));
      try {
        const response = await fetch(`${String(profile.base_url).replace(/\/$/, "")}/chat/completions`, {
          method: "POST",
          signal: controller.signal,
          headers: {
            "Authorization": `Bearer ${aggregatorKey}`,
            "Content-Type": "application/json",
            "HTTP-Referer": "https://coursefinder.app",
            "X-Title": "CourseFinder Layer 3 Evidence Interpretation",
          },
          body: JSON.stringify({
            model: profile.model_identifier,
            temperature: 0,
            max_tokens: Number(profile.max_output_tokens || 1200),
            response_format: { type: "json_object" },
            messages: [
              { role: "system", content: profile.prompt_system },
              { role: "user", content: prompt },
            ],
          }),
        });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(`aggregator ${response.status}: ${JSON.stringify(payload).slice(0, 800)}`);
        providerResult = payload;
        break;
      } catch (e) { lastError = e; }
      finally { clearTimeout(timeout); }
    }
    if (!providerResult) throw lastError instanceof Error ? lastError : new Error("aggregator call failed");

    const rawContent = providerResult?.choices?.[0]?.message?.content;
    let parsed: any;
    try { parsed = parseJsonContent(rawContent); }
    catch (e) {
      const validatorResult = { valid: false, errors: [e instanceof Error ? e.message : String(e)] };
      const { error: completeError } = await svc.rpc("layer3_complete_interpretation_service", {
        p_interpretation_id: interpretationId, p_raw_result: providerResult, p_candidate_value: null, p_confidence: null, p_rationale: "Malformed structured output", p_evidence_quotes: [], p_validator_result: validatorResult, p_valid: false,
        p_response_model: providerResult?.model || null, p_input_tokens: providerResult?.usage?.prompt_tokens || null, p_output_tokens: providerResult?.usage?.completion_tokens || null, p_estimated_cost_usd: Number(providerResult?.usage?.cost || 0), p_expiry: null,
      });
      if (completeError) throw new Error(`validation rejection persistence failed: ${completeError.message}`);
      return json({ ok: false, call_required: true, interpretation_id: interpretationId, status: "rejected_validation", validator_result: validatorResult }, 422);
    }

    const validation = validateCandidate(taskClass, parsed, profile.validators || {});
    const cost = Number(providerResult?.usage?.cost || 0);
    if (Number(profile.cost_ceiling_usd) >= 0 && cost > Number(profile.cost_ceiling_usd)) {
      validation.valid = false;
      validation.errors.push("response exceeded configured cost ceiling");
    }
    const expiryDays = Math.min(Math.max(Number(body?.interpretation_freshness_days || 30), 1), 365);
    const expiry = new Date(Date.now() + expiryDays * 86400000).toISOString();
    const { data: completed, error: completeError } = await svc.rpc("layer3_complete_interpretation_service", {
      p_interpretation_id: interpretationId,
      p_raw_result: providerResult,
      p_candidate_value: parsed?.candidate_value ?? null,
      p_confidence: validation.confidence,
      p_rationale: typeof parsed?.rationale === "string" ? parsed.rationale : "Structured output validation failed",
      p_evidence_quotes: Array.isArray(parsed?.evidence_quotes) ? parsed.evidence_quotes : [],
      p_validator_result: validation,
      p_valid: validation.valid,
      p_response_model: providerResult?.model || null,
      p_input_tokens: providerResult?.usage?.prompt_tokens || null,
      p_output_tokens: providerResult?.usage?.completion_tokens || null,
      p_estimated_cost_usd: cost,
      p_expiry: validation.valid ? expiry : null,
    });
    if (completeError) throw new Error(`completion persistence failed: ${completeError.message}`);
    if (!validation.valid) return json({ ok: false, call_required: true, interpretation_id: interpretationId, status: "rejected_validation", validator_result: validation }, 422);
    return json({ ok: true, call_required: true, interpretation_id: interpretationId, review_item_id: completed?.review_item_id || null, status: parsed?.candidate_value == null ? "no_candidate" : "validated", model: providerResult?.model || profile.model_identifier, validator_result: validation, estimated_cost_usd: cost });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    if (interpretationId) await svc.rpc("layer3_fail_interpretation_service", { p_interpretation_id: interpretationId, p_error: message }).catch(() => undefined);
    return json({ error: message, interpretation_id: interpretationId }, /credential|ceiling reached|not configured/i.test(message) ? 409 : 500);
  }
});
