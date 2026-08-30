import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const ORIGIN = "https://coursefinder-pilot.techm.workers.dev";
function cors(req: Request) {
  const origin = req.headers.get("origin") || "";
  return {
    "Access-Control-Allow-Origin": origin === ORIGIN || origin.startsWith("http://localhost") ? origin : ORIGIN,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
    "Vary": "Origin",
  };
}
const json = (req: Request, body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors(req) });

function parseJsonContent(content: unknown): unknown {
  if (typeof content === "object" && content !== null) return content;
  if (typeof content !== "string") throw new Error("model response content is not JSON text");
  const cleaned = content.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
  return JSON.parse(cleaned);
}

function validateCandidate(taskClass: string, result: any, validators: any, evidenceText = "", sourceUrl = "") {
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
    } else if (taskClass === "international_contact") {
      if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) errors.push("international contact candidate must be an object or null");
      else {
        const disposition = String(candidate.disposition || "");
        if (!["published_contact_found","not_publicly_published","not_found_in_qualified_evidence"].includes(disposition)) errors.push("invalid international contact disposition");
        for (const key of ["international_students_url","contact_team_url"]) {
          const value = candidate[key];
          if (value != null && (typeof value !== "string" || !/^https?:\/\/\S+$/i.test(value))) errors.push(`${key} must be an http/https URL or null`);
        }
        if (candidate.general_email != null && (typeof candidate.general_email !== "string" || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(candidate.general_email))) errors.push("general_email must be an institutional email or null");
        if (!Array.isArray(candidate.contacts)) errors.push("contacts must be an array");
        else if (candidate.contacts.length > Number(validators?.max_contacts ?? 12)) errors.push("too many contacts");
        else for (const contact of candidate.contacts) {
          if (!contact || typeof contact !== "object" || Array.isArray(contact)) { errors.push("invalid contact object"); continue; }
          if (contact.email != null && (typeof contact.email !== "string" || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contact.email))) errors.push("invalid contact email");
          if (contact.source_url != null && (typeof contact.source_url !== "string" || !/^https?:\/\/\S+$/i.test(contact.source_url))) errors.push("invalid contact source_url");
          if (contact.territory != null && typeof contact.territory !== "string") errors.push("invalid contact territory");
        }
        if (disposition !== "published_contact_found" && ((Array.isArray(candidate.contacts) && candidate.contacts.length) || candidate.general_email)) errors.push("non-found disposition cannot include published contact values");
        const haystack = evidenceText.toLowerCase();
        const occurs = (v: unknown) => v == null || v === "" || haystack.includes(String(v).trim().toLowerCase());
        for (const key of ["general_email"] as const) if (!occurs(candidate[key])) errors.push(`${key} not present in governed Evidence`);
        for (const contact of Array.isArray(candidate.contacts) ? candidate.contacts : []) for (const key of ["name","title","email","phone","territory"] as const) if (!occurs(contact?.[key])) errors.push(`contact ${key} not present in governed Evidence`);
        for (const key of ["international_students_url","contact_team_url"] as const) {
          const v = candidate[key]; if (v != null && v !== sourceUrl && !occurs(v)) errors.push(`${key} not present in governed Evidence`);
        }
      }
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

async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(req) });
  if (req.method !== "POST") return json(req, { error: "method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || (() => {
    try { return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}").default || ""; } catch { return ""; }
  })();
  if (!url || !serviceKey) return json(req, { error: "server configuration unavailable" }, 500);
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json(req, { error: "authentication required" }, 401);
  const svc = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await svc.auth.getUser(token);
  if (userError || !userData?.user?.id) return json(req, { error: "invalid user token" }, 401);

  let interpretationId: string | null = null;
  let externalCallCount = 0;
  let callStartedMs: number | null = null;
  try {
    const body = await req.json();
    const evidenceId = String(body?.evidence_id || "");
    const entityType = String(body?.entity_type || "").toLowerCase();
    const entityId = String(body?.entity_id || "");
    const taskClass = String(body?.task_class || "");
    const profileId = String(body?.profile_id || "");
    if (!evidenceId || !entityType || !entityId || !taskClass || !profileId) return json(req, { error: "evidence_id, entity_type, entity_id, task_class and profile_id are required" }, 400);

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
      return json(req, { error: msg }, status);
    }
    if (!reservation?.call_required) return json(req, { ok: true, call_required: false, reason: reservation?.reason, prior_interpretation_id: reservation?.prior_interpretation_id, evidence_hash: reservation?.evidence_hash });

    interpretationId = String(reservation.interpretation_id);
    const profile = reservation.profile || {};
    const { data: usage, error: usageError } = await svc.rpc("layer3_usage_window_service", { p_profile_id: profile.id });
    if (usageError) throw new Error(`usage check failed: ${usageError.message}`);
    if (Number(usage?.minute_calls || 0) > Number(profile.requests_per_minute || 1)) throw new Error("profile requests/minute ceiling reached");
    if (Number(usage?.day_calls || 0) > Number(profile.requests_per_day || 1)) throw new Error("profile requests/day ceiling reached");

    const secretName = String(profile.secret_env_key || "");
    let aggregatorKey = secretName ? Deno.env.get(secretName) : undefined;
    if (!aggregatorKey) {
      const { data: vaultKey, error: vaultError } = await svc.rpc("layer3_provider_credential_resolve_service", { p_profile_id: profile.id });
      if (vaultError) throw new Error(`provider credential lookup failed: ${vaultError.message}`);
      aggregatorKey = typeof vaultKey === "string" ? vaultKey : undefined;
    }
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
      taskClass === "international_contact"
        ? "For international_contact, candidate_value must be an object with disposition, international_students_url, contact_team_url, general_email and contacts. Use only contact details explicitly present in the supplied first-party Evidence. If no qualifying contact is published, return an explicit not_publicly_published or not_found_in_qualified_evidence disposition. Never manufacture a person, email, phone, territory or URL."
        : "Use null candidate_value if the evidence does not support a reliable candidate. Do not infer regulatory identity.",
      `Evidence:\n${evidenceText}`,
    ].join("\n\n");
    const promptHash = await sha256Hex(prompt);
    const profileSnapshot = {
      profile_id: profile.id,
      aggregator_provider: profile.aggregator_provider,
      model_identifier: profile.model_identifier,
      prompt_profile_version: profile.prompt_profile_version,
      prompt_system: profile.prompt_system,
      structured_output_schema: profile.schema || null,
      validators: profile.validators || {},
      max_input_tokens: profile.max_input_tokens,
      max_output_tokens: profile.max_output_tokens,
      retry_ceiling: profile.retry_ceiling,
      timeout_ms: profile.timeout_ms,
      cost_ceiling_usd: profile.cost_ceiling_usd,
      response_format: "json_object",
      temperature: 0,
      prompt_contract_version: taskClass === "international_contact" ? "m2.4.4-a16-contact-interpretation-v1" : "m2.4.3-evidence-interpretation-v1",
      evidence_id: ev.id,
      evidence_hash: ev.content_hash,
      evidence_source_url: ev.source_url || null,
      evidence_mime_type: ev.mime_type || null,
    };
    const { error: provenanceError } = await svc.rpc("layer3_execution_provenance_service", {
      p_interpretation_id: interpretationId,
      p_profile_snapshot: profileSnapshot,
      p_prompt_hash: promptHash,
      p_prompt_input_chars: prompt.length,
    });
    if (provenanceError) throw new Error(`execution provenance persistence failed: ${provenanceError.message}`);

    let providerResult: any = null;
    let parsedDuringCall: any = null;
    let totalInputTokens = 0, totalOutputTokens = 0, totalCostUsd = 0;
    const executionTrace: any[] = [];
    let fallbackProfileIdUsed: string | null = null;
    callStartedMs = performance.now();
    const resolveCredential = async (p: any) => {const secretName=String(p.secret_env_key||"");let key=secretName?Deno.env.get(secretName):undefined;if(!key){const{data:vaultKey,error:vaultError}=await svc.rpc("layer3_provider_credential_resolve_service",{p_profile_id:p.id});if(vaultError)throw new Error(`provider credential lookup failed: ${vaultError.message}`);key=typeof vaultKey==="string"?vaultKey:undefined}if(!key)throw new Error(`server-side aggregator credential ${secretName||"<unset>"} is not configured`);return key};
    const executeProfile=async(p:any,key:string,route:"primary"|"fallback")=>{const attempts=Math.max(1,Math.min(Number(p.retry_ceiling||0)+1,4));let lastError:unknown=null;for(let attempt=0;attempt<attempts;attempt++){const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),Number(p.timeout_ms||30000)),started=performance.now();try{externalCallCount+=1;const response=await fetch(`${String(p.base_url).replace(/\/$/,"")}/chat/completions`,{method:"POST",signal:controller.signal,headers:{"Authorization":`Bearer ${key}`,"Content-Type":"application/json","HTTP-Referer":"https://coursefinder.app","X-Title":"CourseFinder Layer 3 Evidence Interpretation"},body:JSON.stringify({model:p.model_identifier,temperature:0,max_tokens:Number(p.max_output_tokens||1200),response_format:{type:"json_object"},messages:[{role:"system",content:p.prompt_system},{role:"user",content:prompt}]})});const payload=await response.json().catch(()=>({})),latencyMs=Math.round(performance.now()-started);totalInputTokens+=Number(payload?.usage?.prompt_tokens||0);totalOutputTokens+=Number(payload?.usage?.completion_tokens||0);totalCostUsd+=Number(payload?.usage?.cost||0);if(!response.ok){executionTrace.push({route,profile_id:p.id,model:p.model_identifier,attempt:attempt+1,http_status:response.status,latency_ms:latencyMs,outcome:"provider_error"});lastError=new Error(`aggregator ${response.status}: ${JSON.stringify(payload).slice(0,800)}`);continue}try{const parsed=parseJsonContent(payload?.choices?.[0]?.message?.content);executionTrace.push({route,profile_id:p.id,model:p.model_identifier,response_model:payload?.model||null,attempt:attempt+1,http_status:response.status,latency_ms:latencyMs,outcome:"structured_output"});return{payload,parsed}}catch(parseError){executionTrace.push({route,profile_id:p.id,model:p.model_identifier,response_model:payload?.model||null,attempt:attempt+1,http_status:response.status,latency_ms:latencyMs,outcome:"malformed_output"});lastError=parseError}}catch(err){const latencyMs=Math.round(performance.now()-started);executionTrace.push({route,profile_id:p.id,model:p.model_identifier,attempt:attempt+1,http_status:null,latency_ms:latencyMs,outcome:err instanceof DOMException&&err.name==="AbortError"?"timeout":"network_error"});lastError=err}finally{clearTimeout(timeout)}}throw lastError instanceof Error?lastError:new Error(`${route} model route exhausted`)};
    let primaryError:unknown=null;try{const primary=await executeProfile(profile,aggregatorKey,"primary");providerResult=primary.payload;parsedDuringCall=primary.parsed}catch(err){primaryError=err;const{data:fallback,error:fallbackError}=await svc.rpc("layer3_fallback_profile_service",{p_profile_id:profile.id,p_task_class:taskClass});if(fallbackError)throw new Error(`fallback resolution failed: ${fallbackError.message}`);if(fallback?.id){fallbackProfileIdUsed=String(fallback.id);const fallbackKey=await resolveCredential(fallback),fallbackResult=await executeProfile(fallback,fallbackKey,"fallback");providerResult=fallbackResult.payload;parsedDuringCall=fallbackResult.parsed}else throw primaryError instanceof Error?primaryError:new Error("primary model route exhausted and no qualified fallback is configured")}
    const callLatencyMs=callStartedMs==null?null:Math.round(performance.now()-callStartedMs);
    providerResult={...providerResult,_coursefinder_trace:executionTrace,_coursefinder_meta:{primary_profile_id:profile.id,fallback_profile_id:fallbackProfileIdUsed,prompt_profile_version:profile.prompt_profile_version}};

    const rawContent = providerResult?.choices?.[0]?.message?.content;
    let parsed: any;
    try { parsed = parsedDuringCall ?? parseJsonContent(rawContent); }
    catch (e) {
      const validatorResult = { valid: false, errors: [e instanceof Error ? e.message : String(e)] };
      const { error: completeError } = await svc.rpc("layer3_complete_interpretation_service", {
        p_interpretation_id: interpretationId, p_raw_result: providerResult, p_candidate_value: null, p_confidence: null, p_rationale: "Malformed structured output", p_evidence_quotes: [], p_validator_result: validatorResult, p_valid: false,
        p_response_model: providerResult?.model || null, p_input_tokens: totalInputTokens || null, p_output_tokens: totalOutputTokens || null, p_estimated_cost_usd: totalCostUsd, p_expiry: null, p_external_call_count: externalCallCount, p_call_latency_ms: callLatencyMs,
      });
      if (completeError) throw new Error(`validation rejection persistence failed: ${completeError.message}`);
      return json(req, { ok: false, call_required: true, interpretation_id: interpretationId, status: "rejected_validation", validator_result: validatorResult }, 422);
    }

    if (taskClass === "international_contact" && parsed?.candidate_value && typeof parsed.candidate_value === "object") {
      const hasPublished = Boolean(parsed.candidate_value.general_email) || (Array.isArray(parsed.candidate_value.contacts) && parsed.candidate_value.contacts.length > 0);
      parsed.candidate_value.disposition = hasPublished ? "published_contact_found" : (parsed.candidate_value.disposition === "not_publicly_published" ? "not_publicly_published" : "not_found_in_qualified_evidence");
    }
    const validation = validateCandidate(taskClass, parsed, profile.validators || {}, evidenceText, ev.source_url || "");
    const cost = totalCostUsd;
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
      p_input_tokens: totalInputTokens || null,
      p_output_tokens: totalOutputTokens || null,
      p_estimated_cost_usd: cost,
      p_expiry: validation.valid ? expiry : null,
      p_external_call_count: externalCallCount,
      p_call_latency_ms: callLatencyMs,
    });
    if (completeError) throw new Error(`completion persistence failed: ${completeError.message}`);
    if (!validation.valid) return json(req, { ok: false, call_required: true, interpretation_id: interpretationId, status: "rejected_validation", validator_result: validation }, 422);
    return json(req, { ok: true, call_required: true, interpretation_id: interpretationId, review_item_id: completed?.review_item_id || null, status: completed?.status || (parsed?.candidate_value == null ? "no_candidate" : "validated"), model: providerResult?.model || profile.model_identifier, validator_result: validation, estimated_cost_usd: cost, external_call_count: externalCallCount, call_latency_ms: callLatencyMs });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    if (interpretationId) await svc.rpc("layer3_fail_interpretation_service", { p_interpretation_id: interpretationId, p_error: message, p_external_call_count: externalCallCount, p_call_latency_ms: callStartedMs == null ? null : Math.round(performance.now() - callStartedMs) }).catch(() => undefined);
    return json(req, { error: message, interpretation_id: interpretationId }, /credential|ceiling reached|not configured/i.test(message) ? 409 : 500);
  }
});
