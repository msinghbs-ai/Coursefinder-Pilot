// CF-247 s1350 (S1-Build; Platform Admin 28 Nov 2026 13:05 AEDT; SS-Programme-Control PC-20261128-DOT-AUTH-REVIEW): DOT's private connector to the
// data-intake drop-off. It is an MCP tool server (JSON-RPC 2.0 over HTTP POST: initialize, tools/list, tools/call, ping) and also answers plain
// JSON ({"tool": "...", "arguments": {...}}), with three tools: upload_original, finalise_package, package_status.
// Sign-in: DOT's own connector key (Authorization: Bearer <key> or x-api-key), registered as API version dot v1 (key dot_intake_connector_v1,
// issued once on Settings > API usage, kept only as its SHA-256, switched off or rotated there). Every call is logged with this version and key.
// Behind the key: the connector finds the one DOT user (an active dot_submitter whose expiry is set and bounded, decided again by the dot-intake
// gate), opens a short-lived session for it server-side (no password exists or is stored), calls the deployed dot-intake function with that
// session and signs it out. The session token is never returned. Storage, the gate, structured intake and admission are those of dot-intake.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION = "dot-intake-connector-v1.0.0";
const PROTOCOL = "2025-06-18";
const noSession = { persistSession: false, autoRefreshToken: false };
const enc = new TextEncoder();
const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
const sha256Hex = async (b: Uint8Array) => hex(await crypto.subtle.digest("SHA-256", b));
const http = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const EXT: Record<string, string> = { "application/pdf": "pdf", "text/html": "html", "application/json": "json", "application/x-ndjson": "jsonl", "text/plain": "txt" };

const IDENT = {
  country: { type: "string", description: "Two-letter country code of the provider, for example AU." },
  provider_id: { type: "string", description: "StudySearch provider id (uuid) the package belongs to." },
  package: { type: "string", description: "Package name: 3 to 81 lower-case letters, digits, dot, dash or underscore. One package per READY subset." },
};
const TOOLS = [
  {
    name: "upload_original",
    description: "Upload one original source file (PDF, HTML, JSON, JSONL or text) into a StudySearch intake package. The server checks the SHA-256, type and size, stores it once (never overwritten) and records it. Upload every original before finalising.",
    inputSchema: { type: "object", additionalProperties: false, required: ["country", "provider_id", "package", "mime_type", "content_base64", "sha256"], properties: {
      ...IDENT,
      mime_type: { type: "string", enum: Object.keys(EXT), description: "The file's type." },
      content_base64: { type: "string", description: "The file's exact bytes, base64-encoded." },
      sha256: { type: "string", description: "SHA-256 of the exact bytes (64 lower-case hex characters); must equal the server's." },
      source_url: { type: "string", description: "The https address the original was read from." },
    } },
  },
  {
    name: "finalise_package",
    description: "Finalise a package with its READY manifest, last: {files: [{sha256}], items: [structured intake candidates]}. Every listed original must already be uploaded and every candidate must name the package's provider; otherwise it is held and nothing is stored. Returns the intake receipt; the same manifest again returns the same receipt.",
    inputSchema: { type: "object", additionalProperties: false, required: ["country", "provider_id", "package"], properties: {
      ...IDENT,
      manifest: { type: "object", description: "The READY manifest object." },
      manifest_json: { type: "string", description: "Or the manifest as exact JSON text (use this to replay byte-for-byte)." },
    } },
  },
  {
    name: "package_status",
    description: "Read a package's state (none, uploading, received or refused), its number of files, attempts and its intake receipt.",
    inputSchema: { type: "object", additionalProperties: false, required: ["country", "provider_id", "package"], properties: { ...IDENT } },
  },
];

class Refused extends Error { constructor(public code: string, public status = 400, public detail?: unknown) { super(code) } }

Deno.serve(async (req: Request) => {
  const started = performance.now(), requestId = crypto.randomUUID();
  const url = Deno.env.get("SUPABASE_URL"), anon = Deno.env.get("SUPABASE_ANON_KEY"), service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return http(500, { error: "service_configuration_error" });
  const svc = createClient(url, service, { auth: noSession });
  let keyName: string | null = null, action = "unknown", items = 0;
  const log = async (status: number, code: string | null) => {
    try { await svc.rpc("api_request_log_v1", { p_platform: "dot", p_version: "v1", p_key_name: keyName, p_action: action, p_status: status,
      p_elapsed_ms: Math.round(performance.now() - started), p_items: items, p_bytes: null, p_error_code: code, p_request_id: requestId }) } catch { /* logging never fails the call */ }
  };
  if (req.method !== "POST") { await log(405, "method_not_allowed"); return http(405, { error: "method_not_allowed" }) }

  // 1. the connector key (its own API version and key; the key itself is never stored)
  const supplied = (req.headers.get("authorization") || "").match(/^Bearer\s+(.+)$/i)?.[1]?.trim() || (req.headers.get("x-api-key") || "").trim();
  if (supplied) {
    const { data: who } = await svc.rpc("api_key_auth_v1", { p_platform: "dot", p_version: "v1", p_token_sha256: await sha256Hex(enc.encode(supplied)) });
    keyName = who?.key_name ?? null;
  }
  if (!keyName) { action = "auth"; await log(401, "invalid_key"); return http(401, { error: "invalid_or_missing_key" }) }

  let body: any;
  try { body = await req.json() } catch { await log(400, "json_required"); return http(400, { error: "json_body_required" }) }
  const isRpc = body && body.jsonrpc === "2.0";
  const rpcReply = (id: unknown, result: unknown) => http(200, { jsonrpc: "2.0", id, result });
  const rpcError = (id: unknown, code: number, message: string) => http(200, { jsonrpc: "2.0", id, error: { code, message } });

  if (isRpc) {
    action = String(body.method || "unknown").slice(0, 40);
    if (body.id === undefined || body.id === null) { await log(202, null); return new Response(null, { status: 202 }) }  // a notification
    if (body.method === "initialize") {
      await log(200, null);
      return rpcReply(body.id, { protocolVersion: String(body.params?.protocolVersion || PROTOCOL), capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "studysearch-dot-intake", version: VERSION },
        instructions: "StudySearch DOT intake: upload every original of a READY subset with upload_original, then finalise_package with its manifest, then read package_status. A receipt is not acceptance; proof and admission run on the platform." });
    }
    if (body.method === "ping") { await log(200, null); return rpcReply(body.id, {}) }
    if (body.method === "tools/list") { await log(200, null); return rpcReply(body.id, { tools: TOOLS }) }
    if (body.method !== "tools/call") { await log(200, "method_not_found"); return rpcError(body.id, -32601, "method not found") }
  }
  const tool = String(isRpc ? body.params?.name : body.tool || ""), args = (isRpc ? body.params?.arguments : body.arguments) || {};
  action = tool.slice(0, 40) || "unknown";

  let session: { access_token: string } | null = null;
  try {
    if (!TOOLS.some((t) => t.name === tool)) throw new Refused("unknown_tool");
    // 2. the one DOT user (database: active dot_submitter with a set, bounded expiry); the dot-intake gate decides again on the call
    const { data: idn, error: iErr } = await svc.rpc("svc_data_intake_identity_v1", { p_producer: "dot" });
    if (iErr) throw new Refused("identity_lookup_failed", 500);
    if (!idn?.ok) throw new Refused(String(idn?.held || "HELD:NO_DOT_IDENTITY"), idn?.held === "HELD:AMBIGUOUS_DOT_IDENTITY" ? 409 : 403);
    const users = [String(idn.user_id)];
    const { data: u, error: uErr } = await svc.auth.admin.getUserById(users[0]);
    if (uErr || !u?.user?.email || (u.user as any).banned_until && new Date((u.user as any).banned_until) > new Date()) throw new Refused("HELD:DOT_IDENTITY_DISABLED", 403);
    // 3. a short-lived session for that user, made server-side (no password); never returned
    const { data: link, error: lErr } = await svc.auth.admin.generateLink({ type: "magiclink", email: u.user.email });
    if (lErr || !link?.properties?.hashed_token) throw new Refused("session_failed", 500);
    const pub = createClient(url, anon, { auth: noSession });
    const { data: ses, error: sErr } = await pub.auth.verifyOtp({ type: "magiclink", token_hash: link.properties.hashed_token });
    if (sErr || !ses?.session?.access_token) throw new Refused("session_failed", 500);
    session = ses.session;

    // 4. the deployed dot-intake function, exactly as DOT would call it
    const form = new FormData();
    for (const k of ["country", "provider_id", "package"]) form.set(k, String(args[k] ?? ""));
    if (tool === "package_status") form.set("action", "status");
    else if (tool === "upload_original") {
      const mime = String(args.mime_type || ""), ext = EXT[mime];
      if (!ext) throw new Refused("unsupported_type", 415);
      let bytes: Uint8Array;
      try { bytes = Uint8Array.from(atob(String(args.content_base64 || "")), (c) => c.charCodeAt(0)) } catch { throw new Refused("content_base64_invalid") }
      form.set("action", "upload"); form.set("sha256", String(args.sha256 || "").toLowerCase()); form.set("ext", ext);
      if (args.source_url) form.set("source_url", String(args.source_url));
      form.set("file", new File([bytes], `original.${ext}`, { type: mime }));
      items = 1;
    } else {
      const text = typeof args.manifest_json === "string" ? args.manifest_json : args.manifest ? JSON.stringify(args.manifest) : "";
      if (!text) throw new Refused("manifest_required");
      const bytes = enc.encode(text);
      form.set("action", "finalise"); form.set("sha256", await sha256Hex(bytes));
      form.set("file", new File([bytes], "manifest.json", { type: "application/json" }));
      try { items = (JSON.parse(text)?.items || []).length } catch { /* dot-intake answers it */ }
    }
    const r = await fetch(`${url}/functions/v1/dot-intake`, { method: "POST", headers: { authorization: `Bearer ${session.access_token}`, apikey: anon }, body: form });
    const out = await r.json().catch(() => ({ error: "intake_reply_unreadable" }));
    await log(r.status, r.ok ? null : String(out?.held || out?.error || "refused").slice(0, 40));
    const result = { status: r.status, ...out };
    return isRpc ? rpcReply(body.id, { content: [{ type: "text", text: JSON.stringify(result) }], structuredContent: result, isError: !r.ok }) : http(r.status, result);
  } catch (e) {
    const code = e instanceof Refused ? e.code : "request_failed", status = e instanceof Refused ? e.status : 500;
    await log(status, code);
    const result = { status, error: code };
    return isRpc ? rpcReply(body.id, { content: [{ type: "text", text: JSON.stringify(result) }], structuredContent: result, isError: true }) : http(status, result);
  } finally {
    if (session) { try { await svc.auth.admin.signOut(session.access_token, "local") } catch { /* the session also expires on its own */ } }
  }
});
