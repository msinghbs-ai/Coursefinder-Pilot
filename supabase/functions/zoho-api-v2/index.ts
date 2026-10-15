// Zoho API v2 (CF-247, 16 Oct 2026). Platform Admin 09:43: "create separate API URL and Key for Zoho V2 API and keep it separate from
// Website API URL, so i can keep the changes independent for each platform with summary and stat collection as well"; 09:55: "a separate URL
// for each API version going forward ... not with contracts calling in the URL".
// This URL is Zoho v2 only: its own keys (one per consumer: Zoho Creator, Zoho CRM sync), its own rate limit, every call logged
// (pipeline.api_requests, summed daily). It calls only the public.zoho_v2_* functions (service role). Within v2 fields and actions are only
// added; a breaking change becomes zoho-api-v3. Zoho v1 (zoho-course-api) is unchanged.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type Json = Record<string, unknown>;
const API_VERSION = "zoho-v2";
const LOGO_BUCKET = "provider-assets";
const ACTIONS = ["reference", "search", "course", "courses", "providers", "provider", "campuses", "contacts", "rankings", "scholarships",
  "scholarship", "statistics", "sync", "export", "report"];
const MESSAGES: Record<string, string> = {
  INVALID_JSON: "Malformed JSON request",
  INVALID_ACTION: "Unsupported action",
  INVALID_INPUT: "Invalid request input",
  AUTHENTICATION_REQUIRED: "Authentication required",
  RATE_LIMITED: "Rate limited — retry later",
  NOT_FOUND: "Not found",
  SERVICE_UNAVAILABLE: "CourseFinder service unavailable",
  METHOD_NOT_ALLOWED: "Use POST",
};

const cleanText = (v: unknown) => typeof v === "string" ? v.trim() : "";
const isInt = (v: unknown) => v === undefined || Number.isInteger(Number(v));
const headers = (requestId: string, extra: Record<string, string> = {}) =>
  ({ "content-type": "application/json", "cache-control": "no-store", "x-request-id": requestId, ...extra });

function token(req: Request, body: Json) {
  const bearer = (req.headers.get("authorization") || "").match(/^Bearer\s+(.+)$/i)?.[1]?.trim() || "";
  if (bearer) return bearer;
  const direct = (req.headers.get("x-cf-token") || "").trim();
  if (direct) return direct;
  return cleanText(body.integration_token);
}
async function sha256Hex(value: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Logos are kept in a private bucket: every logo object in an answer gets a signed link (valid zoho.logo_link_days).
function collectLogos(node: unknown, out: Json[]) {
  if (Array.isArray(node)) { for (const x of node) collectLogos(x, out); return; }
  if (node && typeof node === "object") {
    const o = node as Json;
    if (typeof o.storage_path === "string" && "terms_status" in o) out.push(o);
    for (const k of Object.keys(o)) collectLogos(o[k], out);
  }
}
async function signLogos(svc: any, data: unknown, days: number) {
  const logos: Json[] = []; collectLogos(data, logos);
  if (logos.length === 0) return;
  const ttl = Math.round(days * 86400); // fixed: seconds in a day
  const expiresAt = new Date(Date.now() + ttl * 1000).toISOString();
  const signed = new Map<string, string>();
  try {
    const paths = [...new Set(logos.map((l) => l.storage_path as string))];
    const { data: urls } = await svc.storage.from(LOGO_BUCKET).createSignedUrls(paths, ttl);
    for (const u of (urls || [])) if (u && u.path && u.signedUrl && !u.error) signed.set(u.path, u.signedUrl);
  } catch { /* a signing failure leaves url null, never fails the request */ }
  for (const l of logos) {
    const u = signed.get(l.storage_path as string) || null;
    l.url = u; l.url_expires_at = u ? expiresAt : null;
    delete l.storage_path;
  }
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const started = performance.now();
  const url = Deno.env.get("SUPABASE_URL"); const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const svc = url && service ? createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } }) : null;
  let keyName: string | null = null; let action: string | null = null;

  // every answer goes through here, so every call is logged
  const finish = async (status: number, body: unknown, extra: Record<string, string> = {}, raw?: string) => {
    const text = raw ?? JSON.stringify(body);
    const o = (body && typeof body === "object") ? body as Json : {};
    const items = Array.isArray(o.items) ? (o.items as unknown[]).length : (o.item ? 1 : (typeof o.rows === "number" ? o.rows as number : 0));
    const code = (o.error && typeof o.error === "object") ? String((o.error as Json).code || "") : null;
    if (svc) {
      try {
        await svc.rpc("zoho_v2_log", { p_key_name: keyName, p_action: action, p_status: status, p_elapsed_ms: Math.round(performance.now() - started),
          p_items: items, p_bytes: text.length, p_error_code: code || null, p_request_id: requestId });
      } catch { /* logging never fails a request */ }
    }
    return new Response(text, { status, headers: raw !== undefined ? { "cache-control": "no-store", "x-request-id": requestId, ...extra } : headers(requestId, extra) });
  };
  const fail = (status: number, code: string, extra: Record<string, string> = {}, detail?: string) =>
    finish(status, { api_version: API_VERSION, error: { code, message: MESSAGES[code] || "Request failed", ...(detail ? { detail } : {}) }, request_id: requestId }, extra);

  if (req.method !== "POST") return fail(405, "METHOD_NOT_ALLOWED");
  if (!svc) return fail(503, "SERVICE_UNAVAILABLE");
  let body: Json;
  try { body = await req.json(); } catch { return fail(400, "INVALID_JSON"); }
  if (!body || typeof body !== "object" || Array.isArray(body)) return fail(400, "INVALID_JSON");

  const supplied = token(req, body);
  if (!supplied || supplied.length > 512) return fail(401, "AUTHENTICATION_REQUIRED");
  const { data: who, error: authError } = await svc.rpc("zoho_v2_auth", { p_token_sha256: await sha256Hex(supplied) });
  if (authError) return fail(503, "SERVICE_UNAVAILABLE");
  if (!who || typeof who !== "object") return fail(401, "AUTHENTICATION_REQUIRED");
  const id = who as Json;
  keyName = String(id.key_name);
  delete body.integration_token;

  action = cleanText(body.action) || null;
  if (!action || !ACTIONS.includes(action)) return fail(400, "INVALID_ACTION");

  const { data: rate, error: rateError } = await svc.rpc("zoho_v2_rate", { p_key_name: keyName, p_limit: Number(id.rate_per_minute) || 1 });
  if (rateError) return fail(503, "SERVICE_UNAVAILABLE");
  const rs = (rate && typeof rate === "object") ? rate as Json : {};
  if (rs.allowed !== true) return fail(429, "RATE_LIMITED", { "retry-after": String(Math.max(Number(rs.retry_after_seconds) || 1, 1)) });

  const rawFilters = body.filters;
  if (rawFilters !== undefined && (rawFilters === null || typeof rawFilters !== "object" || Array.isArray(rawFilters))) return fail(400, "INVALID_INPUT", {}, "filters must be an object");
  if (!isInt(body.page) || !isInt(body.page_size)) return fail(400, "INVALID_INPUT", {}, "page and page_size must be whole numbers");
  const filters = (rawFilters as Json) || {};
  const page = body.page === undefined ? 1 : Number(body.page);
  const pageSize = body.page_size === undefined ? 20 : Number(body.page_size);
  const sort = cleanText(body.sort) || null;

  let fn = ""; let args: Json = {};
  switch (action) {
    case "reference": fn = "zoho_v2_reference"; break;
    case "search": fn = "zoho_v2_course_search"; args = { p_filters: filters, p_page: page, p_page_size: pageSize, p_sort: sort }; break;
    case "course": {
      const c = cleanText(body.course_id) || cleanText(body.cricos_course_code) || cleanText(body.identifier);
      if (!c || c.length > 200) return fail(400, "INVALID_INPUT", {}, "course_id or cricos_course_code required");
      fn = "zoho_v2_course"; args = { p_identifier: c }; break;
    }
    case "courses": {
      const ids = body.identifiers;
      if (!Array.isArray(ids) || ids.some((x) => typeof x !== "string" || !x.trim() || x.length > 200)) return fail(400, "INVALID_INPUT", {}, "identifiers must be a list of course ids or CRICOS codes");
      fn = "zoho_v2_courses"; args = { p_identifiers: ids.map((x) => (x as string).trim()) }; break;
    }
    case "providers": fn = "zoho_v2_providers"; args = { p_filters: filters, p_page: page, p_page_size: pageSize, p_sort: sort }; break;
    case "provider": {
      const p = cleanText(body.provider_id) || cleanText(body.cricos_provider_code);
      if (!p || p.length > 200) return fail(400, "INVALID_INPUT", {}, "provider_id or cricos_provider_code required");
      fn = "zoho_v2_provider"; args = { p_identifier: p }; break;
    }
    case "campuses": fn = "zoho_v2_list"; args = { p_entity: "campus", p_filters: filters, p_page: page, p_page_size: pageSize }; break;
    case "contacts": fn = "zoho_v2_list"; args = { p_entity: "contact", p_filters: filters, p_page: page, p_page_size: pageSize }; break;
    case "statistics": fn = "zoho_v2_statistics"; args = { p_kind: cleanText(body.kind), p_filters: filters, p_page: page, p_page_size: pageSize }; break;
    case "rankings": case "scholarships":
      fn = "zoho_v2_passthrough"; args = { p_action: action, p_filters: filters, p_page: page, p_page_size: pageSize, p_id: null, p_body: null }; break;
    case "scholarship": {
      const s = cleanText(body.scholarship_id);
      if (!s) return fail(400, "INVALID_INPUT", {}, "scholarship_id required");
      fn = "zoho_v2_passthrough"; args = { p_action: action, p_filters: null, p_page: null, p_page_size: null, p_id: s, p_body: null }; break;
    }
    case "report": {
      const c = cleanText(body.course_id) || cleanText(body.cricos_course_code);
      const note = typeof body.note === "string" ? body.note.trim().slice(0, 1000) : "";
      if (!c || note.length < 3) return fail(400, "INVALID_INPUT", {}, "course_id and a note of at least 3 characters required");
      const rep = (body.reporter && typeof body.reporter === "object") ? body.reporter as Json : {};
      fn = "zoho_v2_passthrough";
      args = { p_action: "report", p_filters: null, p_page: null, p_page_size: null, p_id: c, p_body: { field: cleanText(body.field) || "other", note,
        reporter: { name: cleanText(rep.name).slice(0, 120), email: cleanText(rep.email).slice(0, 160), ref: cleanText(rep.ref).slice(0, 120) } } };
      break;
    }
    case "sync": {
      if (body.cursor !== undefined && body.cursor !== null && typeof body.cursor !== "string") return fail(400, "INVALID_INPUT", {}, "cursor must be text");
      if (body.full_load !== undefined && typeof body.full_load !== "boolean") return fail(400, "INVALID_INPUT", {}, "full_load must be true or false");
      if (body.entities !== undefined && (!Array.isArray(body.entities) || body.entities.some((x) => typeof x !== "string"))) return fail(400, "INVALID_INPUT", {}, "entities must be a list");
      fn = "zoho_v2_sync";
      args = { p_cursor: cleanText(body.cursor) || null, p_full: body.full_load === true, p_entities: Array.isArray(body.entities) ? body.entities : null,
        p_page_size: body.page_size !== undefined ? pageSize : null };
      break;
    }
    case "export": {
      const e = cleanText(body.entity);
      if (!["provider", "campus", "contact", "course"].includes(e)) return fail(400, "INVALID_INPUT", {}, "entity must be provider, campus, contact or course");
      fn = "zoho_v2_export"; args = { p_entity: e }; break;
    }
  }

  const { data, error } = await svc.rpc(fn, args);
  if (error) {
    const m = String(error.message || "");
    if (error.code === "22023" || m.includes("INVALID_INPUT")) return fail(400, "INVALID_INPUT", {}, m.replace(/^.*INVALID_INPUT:\s*/, "").slice(0, 200) || undefined);
    console.error(JSON.stringify({ event: "zoho_api_v2_error", request_id: requestId, action, error_code: error.code || null }));
    return fail(503, "SERVICE_UNAVAILABLE");
  }
  const obj = (data && typeof data === "object") ? data as Json : {};
  const e = obj.error as Json | undefined;
  if (e && e.code === "NOT_FOUND") return fail(404, "NOT_FOUND");
  if (e && e.code === "INVALID_INPUT") return fail(400, "INVALID_INPUT", {}, typeof e.detail === "string" ? e.detail : undefined);

  // export: the CSV itself (format "json" returns it inside JSON)
  if (action === "export" && cleanText(body.format) !== "json") {
    const name = `coursefinder-${obj.entity}-${new Date().toISOString().slice(0, 10)}.csv`;
    return finish(200, obj, { "content-type": "text/csv; charset=utf-8", "content-disposition": `attachment; filename="${name}"`,
      "x-rows": String(obj.rows ?? 0), "x-complete": String(obj.complete ?? false), "x-sync-cursor": String(obj.sync_cursor ?? "") }, String(obj.csv ?? ""));
  }
  await signLogos(svc, obj, Number(id.logo_link_days) || 1);
  return finish(200, { ...obj, api_version: API_VERSION, request_id: requestId });
});
