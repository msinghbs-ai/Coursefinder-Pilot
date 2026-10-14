import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

// CF-247 v2.15.276 (14 Oct 2026) Decision 258: Layer 1 reader for provider register facts.
// Reads one CSV resource of a data.gov.au CKAN package, named in the source metadata (TEQSA National Register providers,
// CRICOS Institutions), keeps the file as evidence, and writes the named columns as facts against each provider found by its
// CRICOS code. After an apply it runs the institution type rules (security.provider_type_classify_v1).
// Source metadata: discovery_url (CKAN package_show), resource_url_regex or resource_name_regex, key_column, key_pattern,
// scheme, facts {fact_code: column}. Called by layer1-operations-control and -scheduled (service key) or with a one-time nonce.
// v1.1.0 (same day): format "nzqa_type_listing" reads the NZQA provider search once per organisation type named in the source
// metadata (types, listing_url with {type}) and records each provider's type as fact nzqa_org_type.
// v1.2.0: the search links providers by an internal number, not the NZQA organisation number, so each row also sends the
// provider name as listed; the facts writer matches on it when the number matches nothing.
// v1.3.0: the search number is the NZQA organisation number followed by a five-digit site number (415 of 415 checked
// against the stored register, 14 Oct 2026). The source metadata code_from_id (a pattern whose first group is the code)
// turns it into the organisation number, so rows match exactly; the name stays a fallback only.
const VERSION = "layer1-provider-facts-v1.3.0";
const FN = "layer1-provider-facts";
const FETCH_MS = 90000; // fixed: API time-out

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
const clean = (v: unknown) => String(v ?? "").replace(/\u00a0/g, " ").trim();
const nk = (v: unknown) => clean(v).replace(/^\uFEFF/, "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

async function rpc(client: any, name: string, args: Record<string, unknown> = {}) {
  const { data, error } = await client.rpc(name, args);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data;
}

async function sha(bytes: Uint8Array) {
  const d = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(d)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

function hostAllowed(raw: string, domains: string[]) {
  let u: URL;
  try { u = new URL(raw); } catch { throw new Error("source URL is malformed"); }
  if (u.protocol !== "https:") throw new Error("register source must use HTTPS");
  const host = u.hostname.toLowerCase();
  if (!domains.some((d) => host === d || host.endsWith(`.${d}`))) throw new Error(`source authority mismatch: ${host} is not an approved authority domain`);
  return u;
}

async function fetchT(url: string) {
  const ctl = new AbortController(), timer = setTimeout(() => ctl.abort(), FETCH_MS);
  try {
    const r = await fetch(url, { signal: ctl.signal, redirect: "follow", headers: { "user-agent": "studysearch-layer1-provider-facts/1.0", accept: "*/*" } });
    if (!r.ok) throw new Error(`HTTP ${r.status} from ${new URL(url).hostname}`);
    return r;
  } finally { clearTimeout(timer); }
}

// RFC 4180 rows (quoted fields, doubled quotes, CR/LF), byte order mark removed.
export function csvRows(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [], field = "", quoted = false;
  const s = text.replace(/^\uFEFF/, "");
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (quoted) {
      if (c === '"') { if (s[i + 1] === '"') { field += '"'; i++; } else quoted = false; } else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n") { row.push(field); rows.push(row); row = []; field = ""; }
    else if (c !== "\r") field += c;
  }
  if (field.length || row.length) { row.push(field); rows.push(row); }
  return rows.filter((r) => r.some((x) => clean(x)));
}

// One entry per register code. A code listed on several rows keeps the row whose status fact reads Active.
export function extractFacts(text: string, keyColumn: string, keyPattern: string, facts: Record<string, string>) {
  const rows = csvRows(text);
  const headerAt = rows.findIndex((r) => r.some((x) => nk(x) === nk(keyColumn)));
  if (headerAt < 0) throw new Error(`key column "${keyColumn}" not found`);
  const header = rows[headerAt].map(nk), col = (name: string) => header.indexOf(nk(name));
  const keyIdx = col(keyColumn);
  const missing = Object.values(facts).filter((c) => col(c) < 0);
  if (missing.length) throw new Error(`columns not found: ${missing.join(", ")}`);
  const re = new RegExp(keyPattern, "g");
  const byCode = new Map<string, Record<string, string>>();
  let dataRows = 0, rowsWithoutCode = 0;
  const isActive = (f: Record<string, string>) => Object.entries(f).some(([k, v]) => /_status$/.test(k) && /^active$/i.test(v));
  for (const r of rows.slice(headerAt + 1)) {
    dataRows++;
    const codes = [...new Set((clean(r[keyIdx]).match(re) || []).map((x) => x.toUpperCase()))];
    if (!codes.length) { rowsWithoutCode++; continue; }
    const f: Record<string, string> = {};
    for (const [fact, c] of Object.entries(facts)) f[fact] = clean(r[col(c)]);
    for (const code of codes) {
      const prior = byCode.get(code);
      if (!prior || (!isActive(prior) && isActive(f))) byCode.set(code, f);
    }
  }
  return { dataRows, rowsWithoutCode, entries: [...byCode.entries()].map(([code, f]) => ({ codes: [code], facts: f })) };
}

async function pickResource(meta: any, domains: string[]) {
  const discovery = clean(meta.discovery_url);
  if (!discovery) throw new Error("source metadata has no discovery_url");
  hostAllowed(discovery, domains);
  const pkg = await (await fetchT(discovery)).json();
  if (!pkg?.success || !Array.isArray(pkg?.result?.resources)) throw new Error("CKAN package response malformed");
  const byUrl = meta.resource_url_regex ? new RegExp(meta.resource_url_regex, "i") : null;
  const byName = meta.resource_name_regex ? new RegExp(meta.resource_name_regex, "i") : null;
  if (!byUrl && !byName) throw new Error("source metadata names no resource");
  const found = pkg.result.resources
    .filter((r: any) => (byUrl ? byUrl.test(clean(r.url)) : true) && (byName ? byName.test(clean(r.name)) : true))
    .sort((a: any, b: any) => clean(b.last_modified || b.created).localeCompare(clean(a.last_modified || a.created)));
  if (!found.length) throw new Error("named resource not found in the CKAN package");
  const res = found[0];
  hostAllowed(clean(res.url), domains);
  return { id: res.id, name: clean(res.name), url: clean(res.url), lastModified: clean(res.last_modified || res.created) || null, packageId: pkg.result.id };
}

// NZQA provider search results: one page per organisation type; each provider row has the name in its first cell and links to
// details.do?providerId=<search number>.
const decodeHtml = (v: string) => v.replace(/<[^>]+>/g, " ").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&#39;|&apos;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, " ").trim();
export function nzqaListing(pages: { type: string; html: string }[], fact: string, codeFromId: RegExp | null = null) {
  const byCode = new Map<string, { name: string; facts: Record<string, string> }>();
  for (const p of pages) for (const m of p.html.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/gi)) {
    const id = m[1].match(/href=["']\/providers\/details\.do\?providerId=([0-9]+)["']/i)?.[1];
    const name = decodeHtml(m[1].match(/<td[^>]*>([\s\S]*?)<\/td>/i)?.[1] || "");
    const code = id && codeFromId ? (id.match(codeFromId)?.[1] || id) : id;
    if (code && !byCode.has(code)) byCode.set(code, { name, facts: { [fact]: p.type } });
  }
  return [...byCode.entries()].map(([code, v]) => ({ codes: [code], names: v.name ? [v.name] : [], facts: v.facts }));
}

async function readNzqa(meta: any, domains: string[]) {
  const types: string[] = Array.isArray(meta.types) ? meta.types.map(clean).filter(Boolean) : [];
  const template = clean(meta.listing_url);
  if (!types.length || !template.includes("{type}")) throw new Error("source metadata needs types and a listing_url with {type}");
  const pages = [];
  for (const type of types) {
    const u = template.replace("{type}", encodeURIComponent(type));
    hostAllowed(u, domains);
    pages.push({ type, url: u, html: await (await fetchT(u)).text() });
  }
  const bytes = new TextEncoder().encode(JSON.stringify(pages));
  const fact = Object.keys(meta.facts || {})[0] || "nzqa_org_type";
  const codeFromId = clean(meta.code_from_id) ? new RegExp(clean(meta.code_from_id)) : null;
  return { bytes, entries: nzqaListing(pages, fact, codeFromId), res: { id: null, name: "nzqa-provider-types.json", url: template, lastModified: null, packageId: null }, dataRows: pages.length, rowsWithoutCode: 0 };
}

async function storeEvidence(service: any, sourceId: string, url: string, name: string, bytes: Uint8Array, hash: string, metadata: unknown, mime = "text/csv") {
  const existing = await rpc(service, "svc_layer1_evidence_by_hash", { p_source_id: sourceId, p_hash: hash });
  if (existing) return existing;
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const path = `regulatory/provider-facts/${sourceId}/${stamp}-${name.replace(/[^A-Za-z0-9._-]+/g, "_") || "resource"}`;
  const up = await service.storage.from("evidence").upload(path, bytes, { contentType: mime, upsert: true });
  if (up.error) throw new Error(up.error.message);
  return await rpc(service, "svc_layer1_record_evidence", {
    p_source_id: sourceId, p_job_id: null, p_source_url: url, p_storage_path: path, p_content_hash: hash, p_mime_type: mime, p_metadata: metadata,
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ ok: false, error: "POST required", workerVersion: VERSION }, 405);
  const url = Deno.env.get("SUPABASE_URL")!, serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const service = createClient(url, serviceKey, { auth: { persistSession: false } });
  try {
    const internal = clean(req.headers.get("x-cf-layer1-service-key"));
    const bearer = clean(req.headers.get("authorization")).replace(/^Bearer\s+/i, "");
    const nonce = clean(req.headers.get("x-cf-run-nonce"));
    const allowed = (internal && internal === serviceKey) || bearer === serviceKey ||
      (nonce && await rpc(service, "svc_pilot_consume_nonce", { p_function: FN, p_nonce: nonce }));
    if (!allowed) return json({ ok: false, error: "internal service key or one-time nonce required", workerVersion: VERSION }, 403);

    const body = await req.json().catch(() => ({}));
    const sourceId = clean(body.source_id), apply = clean(body.mode).toLowerCase() === "apply";
    if (!sourceId) throw new Error("source_id required");
    const ctx = await rpc(service, "svc_layer1_operation_context", { p_source_id: sourceId });
    const meta = ctx?.source?.metadata || {};
    if (clean(meta.source_system).toUpperCase() !== "PROVIDER_FACTS") throw new Error("source is not a provider facts register");
    const domains = (ctx?.profile?.authority_domains || []).map((d: unknown) => clean(d).toLowerCase()).filter(Boolean);
    if (!domains.length) throw new Error("source has no approved authority domains");
    hostAllowed(clean(ctx.source.url), domains);
    const facts = meta.facts || {};
    if (!Object.keys(facts).length) throw new Error("source metadata names no facts");

    const nz = clean(meta.format) === "nzqa_type_listing";
    let res: any, bytes: Uint8Array, parsed: { dataRows: number; rowsWithoutCode: number; entries: any[] };
    if (nz) {
      const r = await readNzqa(meta, domains);
      res = r.res; bytes = r.bytes; parsed = { dataRows: r.dataRows, rowsWithoutCode: 0, entries: r.entries };
    } else {
      res = await pickResource(meta, domains);
      bytes = new Uint8Array(await (await fetchT(res.url)).arrayBuffer());
      parsed = extractFacts(new TextDecoder().decode(bytes), clean(meta.key_column), clean(meta.key_pattern) || "[0-9]{5}[A-Za-z]", facts);
    }
    const fileSha256 = await sha(bytes);
    if (!parsed.entries.length) throw new Error("no register codes found");
    const out: Record<string, unknown> = {
      ok: true, workerVersion: VERSION, mode: apply ? "apply" : "dry_run", sourceId, resourceName: res.name, resourceUrl: res.url,
      lastModified: res.lastModified, fileSha256, dataRows: parsed.dataRows, rowsWithoutCode: parsed.rowsWithoutCode,
      candidateObservations: parsed.entries.length, facts: Object.keys(facts),
    };
    if (!apply) return json(out);

    const evidenceId = await storeEvidence(service, sourceId, res.url, res.name, bytes, fileSha256, {
      resource_id: res.id, resource_name: res.name, last_modified: res.lastModified, package_id: res.packageId, byte_size: bytes.length, worker_version: VERSION,
    }, nz ? "application/json" : "text/csv");
    const put = await rpc(service, "svc_provider_register_facts_put", { p_source_id: sourceId, p_evidence_id: evidenceId, p_scheme: clean(meta.scheme) || "cricos", p_rows: parsed.entries });
    const classify = await rpc(service, "svc_provider_type_classify", {});
    return json({
      ...out, evidenceId, put, classify,
      observationsSeen: parsed.entries.length,
      observationsChanged: Number(put?.providers_matched ?? 0),
      unmatchedOrAmbiguous: Number(put?.codes_unmatched ?? 0),
      reconciliation: { updated: Number(put?.providers_matched ?? 0), rejected: Number(put?.codes_unmatched ?? 0) },
    });
  } catch (e) {
    return json({ ok: false, error: e instanceof Error ? e.message : String(e), workerVersion: VERSION }, 500);
  }
});
