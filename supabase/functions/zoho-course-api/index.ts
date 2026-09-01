import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type Json = Record<string, unknown>;

const json = (status:number, body:unknown, requestId:string, extra:Record<string,string>={}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
      "x-request-id": requestId,
      ...extra
    }
  });

const cleanText = (value:unknown) => typeof value === "string" ? value.trim() : "";
const integer = (value:unknown, fallback:number) => {
  const n = Number(value);
  return Number.isInteger(n) ? n : fallback;
};
const stringArray = (value:unknown) =>
  Array.isArray(value) ? value.map(cleanText).filter(Boolean).slice(0,50) : null;
const integerArray = (value:unknown) =>
  Array.isArray(value) ? value.map(Number).filter(Number.isInteger).slice(0,50) : null;
const numberOrNull = (value:unknown) => {
  if (value === null || value === undefined || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
};

const safeError = (status:number, code:string, requestId:string, extra:Record<string,string>={}) => json(status, {
  error: {
    code,
    message: ({
      INVALID_JSON:"Malformed JSON request",
      INVALID_ACTION:"Unsupported action",
      INVALID_INPUT:"Invalid request input",
      AUTHENTICATION_REQUIRED:"Authentication required",
      RATE_LIMITED:"Rate limited — retry later",
      NOT_FOUND:"Course not found",
      SERVICE_UNAVAILABLE:"CourseFinder service unavailable"
    } as Record<string,string>)[code] || "Request failed"
  },
  request_id: requestId
}, requestId, extra);

function integrationToken(req:Request) {
  const direct = (req.headers.get("x-cf-token") || "").trim();
  if (direct) return direct;
  const raw = req.headers.get("authorization") || "";
  return raw.match(/^Bearer\s+(.+)$/i)?.[1]?.trim() || "";
}

async function sha256Hex(value:string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2,"0")).join("");
}

Deno.serve(async (req:Request) => {
  const requestId = crypto.randomUUID();
  const started = performance.now();

  if (req.method !== "POST") return safeError(405, "INVALID_ACTION", requestId);

  const url = Deno.env.get("SUPABASE_URL");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !service) return safeError(503, "SERVICE_UNAVAILABLE", requestId);

  const svc = createClient(url, service, {
    auth:{ persistSession:false, autoRefreshToken:false }
  });

  let body:Json;
  try { body = await req.json(); }
  catch { return safeError(400, "INVALID_JSON", requestId); }

  const bodyToken = cleanText(body.integration_token);
  const headerToken = integrationToken(req);
  const token = bodyToken || headerToken;
  if (!token || token.length > 512) return safeError(401, "AUTHENTICATION_REQUIRED", requestId);

  const tokenHash = await sha256Hex(token);
  const { data: authOk, error: authError } = await svc
    .rpc("zoho_edge_auth_v1", { p_token_sha256: tokenHash });

  if (authError || authOk !== true) {
    return safeError(401, "AUTHENTICATION_REQUIRED", requestId);
  }

  delete body.integration_token;

  const action = cleanText(body.action);
  if (!["search","lookup","provider_options","filter_options","reference_bundle"].includes(action)) {
    return safeError(400, "INVALID_ACTION", requestId);
  }

  const { data: rate, error: rateError } = await svc
    .rpc("zoho_edge_rate_check_v1", {
      p_identity:"coursefinder_zoho_pilot_v1",
      p_resource:action,
      p_limit:120,
      p_window_seconds:60
    });

  if (rateError) return safeError(503, "SERVICE_UNAVAILABLE", requestId);
  const rateState = (rate && typeof rate === "object") ? rate as Record<string,unknown> : {};
  if (rateState.allowed !== true) {
    const retry = Math.max(Number(rateState.retry_after_seconds) || 1, 1);
    return safeError(429, "RATE_LIMITED", requestId, {"retry-after":String(retry)});
  }

  try {
    let data:unknown = null;
    let error:any = null;

    if (action === "search") {
      const limit = Math.min(Math.max(integer(body.limit, 10), 1), 50);
      const offset = Math.max(integer(body.offset, 0), 0);

      ({data,error} = await svc.rpc("zoho_edge_course_search_v2", {
        p_query: cleanText(body.query) || null,
        p_country_codes: stringArray(body.country_codes),
        p_provider_ids: stringArray(body.provider_ids),
        p_subdivision_codes: stringArray(body.subdivision_codes),
        p_study_level_codes: stringArray(body.study_level_codes),
        p_primary_field_codes: stringArray(body.primary_field_codes),
        p_delivery_modes: stringArray(body.delivery_modes),
        p_has_scholarship: typeof body.has_scholarship === "boolean" ? body.has_scholarship : null,
        p_has_intake: typeof body.has_intake === "boolean" ? body.has_intake : null,
        p_has_english: typeof body.has_english === "boolean" ? body.has_english : null,
        p_has_provider_current_tuition: typeof body.has_provider_current_tuition === "boolean" ? body.has_provider_current_tuition : null,
        p_has_regulatory_tuition: typeof body.has_regulatory_tuition === "boolean" ? body.has_regulatory_tuition : null,
        p_has_link: typeof body.has_link === "boolean" ? body.has_link : null,
        p_intake_years: integerArray(body.intake_years),
        p_intake_labels: stringArray(body.intake_labels),
        p_english_test_codes: stringArray(body.english_test_codes),
        p_min_provider_annual_tuition: numberOrNull(body.min_provider_annual_tuition),
        p_max_provider_annual_tuition: numberOrNull(body.max_provider_annual_tuition),
        p_min_regulatory_total_tuition: numberOrNull(body.min_regulatory_total_tuition),
        p_max_regulatory_total_tuition: numberOrNull(body.max_regulatory_total_tuition),
        p_publication_statuses: stringArray(body.publication_statuses),
        p_changed_since: null,
        p_limit: limit,
        p_offset: offset
      }));
    } else if (action === "lookup") {
      const identifier = cleanText(body.identifier);
      if (!identifier || identifier.length > 200) return safeError(400, "INVALID_INPUT", requestId);

      ({data,error} = await svc.rpc("zoho_edge_course_lookup_v1", {
        p_identifier: identifier
      }));
    } else if (action === "provider_options") {
      const limit = Math.min(Math.max(integer(body.limit, 10), 1), 50);
      const offset = Math.max(integer(body.offset, 0), 0);

      ({data,error} = await svc.rpc("zoho_edge_provider_search_v1", {
        p_query: cleanText(body.query) || null,
        p_country_code: cleanText(body.country_code) || null,
        p_changed_since: null,
        p_limit: limit,
        p_offset: offset
      }));
    } else if (action === "filter_options") {
      const kind = cleanText(body.kind).toLowerCase();
      if (!["country","subdivision"].includes(kind)) return safeError(400, "INVALID_INPUT", requestId);

      const limit = Math.min(Math.max(integer(body.limit, 10), 1), 50);
      const offset = Math.max(integer(body.offset, 0), 0);

      ({data,error} = await svc.rpc("zoho_edge_filter_options_v1", {
        p_kind: kind,
        p_country_code: cleanText(body.country_code) || null,
        p_query: cleanText(body.query) || null,
        p_limit: limit,
        p_offset: offset
      }));
    } else if (action === "reference_bundle") {
      ({data,error} = await svc.rpc("zoho_edge_reference_bundle_v1"));
    }

    if (error) {
      console.error(JSON.stringify({
        event:"zoho_course_api_error",
        request_id:requestId,
        action,
        error_code:error?.code || null,
        elapsed_ms:Math.round(performance.now()-started)
      }));
      return safeError(503, "SERVICE_UNAVAILABLE", requestId);
    }

    const object = (data && typeof data === "object") ? data as Record<string,unknown> : {};

    if (action === "lookup" && (object.error === "NOT_FOUND" || object.code === "NOT_FOUND")) {
      return safeError(404, "NOT_FOUND", requestId);
    }

    console.log(JSON.stringify({
      event:"zoho_course_api_request",
      request_id:requestId,
      action,
      outcome:"ok",
      elapsed_ms:Math.round(performance.now()-started)
    }));

    return json(200, { ...object, request_id:requestId }, requestId);
  } catch {
    return safeError(503, "SERVICE_UNAVAILABLE", requestId);
  }
});