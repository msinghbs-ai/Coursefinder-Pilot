import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import * as XLSX from "npm:xlsx@0.18.5";
import { parseBomClimate } from "../_shared/cf247-bom-climate.js";
import { anchorWindows, extractFact, firecrawlScrapeBody, headerSample, htmlToText, linkWords, parseOccupationGrid, xlsxLinks } from "../_shared/cf247-page-facts.js";

// CF-247 RM1B (Platform Admin 17 Nov 2026 13:12; approvals A-1 to A-4 of 07:29 and 07:35): ABS population loader for Australian
// destination localities. Reads ABS Regional population 2024-25, Table 2 (estimated resident population by Significant Urban Area),
// stores the file as evidence and hands the SUA rows to public.svc_destination_abs_load_v1, which writes draft localities and figures
// with attribution and maps postcodes from the ASGS Edition 3 shares (workflow destination-abs-shares-load).
// Mode climate (RM1I, Platform Admin 18 Nov 2026 10:31; job destination-climate-load and Run now): reads the Bureau of Meteorology climate
// statistics page of each active station (destination.climate_stations), stores the page as evidence and hands the parsed monthly statistics to
// public.svc_destination_climate_load_v1, which writes nothing while the edition's terms are pending and draft figures once they are approved.
// Run by job destination-abs-load (1st of the month, 05:30 Sydney) and Run now, each with a one-time nonce; a Platform Admin may also
// call it signed in. A new ABS edition is a new approval (design: "Any source beyond A-1 and A-4 needs a new approval"), so the
// edition below changes only with a reviewed code change.
// Mode facts (RM1I / RM1C / RM1H / RM1D, Platform Admin 18 Nov 2026 14:23 and 15:32; job destination-page-facts-load and Run now): reads each
// official page named in destination.page_facts, stores it as evidence, applies each fact's pattern to the page's visible text and returns
// the value with a verbatim quote (or, on a miss, what the page says around the fact's anchor word); then finds the JSA OSCA occupation
// workbook by its link text, stores it and returns the occupation rows its header names. public.svc_destination_page_facts_load_v1 writes
// draft rules and figures with the evidence, the quote and the time read; editions whose terms are restricted are not read at all.
// v1.5.0 (Platform Admin 19 Nov 2026 06:41, s714): a rendered page whose address names a tab ('#HowTo', the Home Affairs Step by step tab) is read whole
// (onlyMainContent false, firecrawlScrapeBody); LIN 19/198 is read directly (static compilation page, no Firecrawl).
// v1.3.0 (Platform Admin 18 Nov 2026 17:55): a page whose read mode is rendered (destination.page_facts.read_mode; the Home Affairs pages,
// whose content the browser builds) is read through Firecrawl /v1/scrape (JS rendering, onlyMainContent): the spend is asked of the database
// first (svc_fc_spend, purpose destination_page_facts, the "other" daily share and the monthly plan limit), every call is logged
// (svc_fc_call_log), and the rendered HTML is stored as the evidence. The JSA Table 1 headings are read over two rows.
// v1.3.1 (18 Nov 2026, third live run): a table cell ends with a bar in the page text, so a quote keeps a row label with its value.
// v1.4.0 (Platform Admin 18 Nov 2026 22:04, s694): every destination source is a Layer 1 Register source (pipeline.sources, source system
// DESTINATION). The standard Layer 1 scheduler (layer1-operations-scheduled) and the register's Run now (layer1-operations-control) call this
// loader with the internal service key, the source's mode and, for the page facts, its scope (pages or workbook); every artifact is stored in
// Supabase Storage and recorded as evidence of that source (security.destination_source_evidence_v1); the response carries the Layer 1
// count and content hash (candidateObservations, fileSha256).
const VERSION = "layer1-destination-geo-loader-v1.6.0";
const FUNCTION_NAME = "layer1-destination-geo-loader";
const EDITION = {
  source_url: "https://www.abs.gov.au/statistics/people/population/regional-population/2024-25/32180DS0004_2001-25.xlsx",
  dataset_edition: "ABS Regional population 2024-25",
  reference_period: "2025-06-30",
  year: "2025",
  sheet: "Table 2",
  boundary_vintage: "ASGS Edition 3 (2021)",
  attribution_text:
    "Source: Australian Bureau of Statistics, Regional population 2024-25 (estimated resident population at 30 June 2025) and Australian Statistical Geography Standard (ASGS) Edition 3, licensed under CC BY 4.0.",
};

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cf-run-nonce",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json", "cache-control": "no-store" } });
const clean = (v: unknown) => String(v ?? "").replace(/\s+/g, " ").trim();

async function rpc(client: any, name: string, args: Record<string, unknown> = {}) {
  const { data, error } = await client.rpc(name, args);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data;
}

async function authorize(req: Request, service: any, url: string, anon: string, key: string) {
  const internal = clean(req.headers.get("x-cf-layer1-service-key"));
  if (internal && internal === key) return "layer1";
  const nonce = clean(req.headers.get("x-cf-run-nonce"));
  if (nonce) {
    if (await rpc(service, "svc_pilot_consume_nonce", { p_function: FUNCTION_NAME, p_nonce: nonce }) !== true) throw new Error("invalid_run_nonce");
    return "nonce";
  }
  const token = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) throw new Error("authentication required");
  const user = createClient(url, anon, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false } });
  const { data: { user: u }, error } = await user.auth.getUser(token);
  if (error || !u) throw new Error("invalid user session");
  if (!await rpc(service, "svc_layer1_authorize_platform_admin", { p_user_id: u.id })) throw new Error("platform_admin required");
  return "platform_admin";
}

async function sha256(bytes: Uint8Array) {
  const d = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(d)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

async function download(url: string) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 60000); // fixed: API time-out
  try {
    const r = await fetch(url, { signal: ctl.signal, redirect: "follow", headers: { "user-agent": `coursefinder-pilot/${VERSION}` } });
    if (!r.ok) throw new Error(`HTTP ${r.status}: ${url}`);
    return new Uint8Array(await r.arrayBuffer());
  } finally {
    clearTimeout(timer);
  }
}

// Table 2: a header row holding "SUA code" and "SUA name"; the year row above it carries the reference year (2025) over the ERP column.
export function parseTable2(rows: unknown[][], year: string) {
  const hi = rows.findIndex((r) => r.some((c) => /^sua code$/i.test(clean(c))) && r.some((c) => /^sua name$/i.test(clean(c))));
  if (hi < 0) throw new Error("Table 2: no SUA code / SUA name header row");
  const head = rows[hi].map(clean);
  const codeCol = head.findIndex((c) => /^sua code$/i.test(c));
  const nameCol = head.findIndex((c) => /^sua name$/i.test(c));
  let valueCol = -1;
  for (let i = hi - 1; i >= 0 && valueCol < 0; i--) valueCol = rows[i].findIndex((c) => clean(c) === year || clean(c).startsWith(`${year}`) && /^\d{4}(\.0+)?$/.test(clean(c)));
  if (valueCol < 0) throw new Error(`Table 2: no ${year} column above the header row`);
  const out: { code: string; name: string; erp: number }[] = [];
  for (let i = hi + 1; i < rows.length; i++) {
    const code = clean(rows[i][codeCol]).replace(/\.0+$/, "");
    const name = clean(rows[i][nameCol]);
    if (!/^\d{4}$/.test(code)) {
      if (out.length && !code && !name) break; // the notes below the table
      continue;
    }
    const raw = rows[i][valueCol];
    const erp = typeof raw === "number" ? raw : Number(clean(raw).replace(/,/g, ""));
    if (!Number.isFinite(erp)) continue;
    out.push({ code, name, erp });
  }
  return { headerRow: hi, valueCol, rows: out };
}

// RM1I: one page per station, read in turn (eight pages); a station that fails is reported and the others still load
async function climate(service: any, runId: string | null, trigger: string, started: number) {
  try {
    const cfg = await rpc(service, "svc_destination_climate_stations_v1");
    const stations: any[] = Array.isArray(cfg?.stations) ? cfg.stations : [];
    if (!stations.length) throw new Error("no active climate station");
    const out: any[] = [];
    for (const st of stations) {
      try {
        const bytes = await download(st.page_url);
        const hash = await sha256(bytes);
        const html = new TextDecoder("utf-8").decode(bytes);
        const parsed = parseBomClimate(html);
        if (parsed.station && parsed.station !== st.station_id) throw new Error(`page is station ${parsed.station}, expected ${st.station_id}`);
        const path = `destination/bom/climate/${st.station_id}/${hash}.html`;
        const up = await service.storage.from("evidence").upload(path, bytes, { contentType: "text/html", upsert: true });
        out.push({ station_id: st.station_id, page_url: st.page_url, sha256: hash, storage_path: up.error ? null : path, prepared: parsed.prepared,
          statistics: parsed.statistics, missing: parsed.missing });
      } catch (e) {
        out.push({ station_id: st.station_id, page_url: st.page_url, error: e instanceof Error ? e.message : String(e) });
      }
    }
    const result = await rpc(service, "svc_destination_climate_load_v1", { p_payload: { run_id: runId, trigger, stations: out } });
    const l1 = await layer1Summary(out.reduce((n, o) => n + (o.statistics ? Object.keys(o.statistics).length : 0), 0), out.map((o) => o.sha256));
    return json({ ok: true, version: VERSION, mode: "climate", trigger, run_id: runId, ms: Date.now() - started, result, ...l1 });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    try { await rpc(service, "svc_destination_climate_load_v1", { p_payload: { error: `${VERSION}: ${message}`, run_id: runId, trigger } }); } catch { /* recorded below */ }
    return json({ ok: false, version: VERSION, mode: "climate", error: message }, 500);
  }
}

// the Layer 1 count and content hash of a run: the hash of the artifacts' hashes, in order
async function layer1Summary(count: number, hashes: string[]) {
  const joined = hashes.filter(Boolean).join("|");
  return { candidateObservations: count, observationsSeen: count, fileSha256: joined ? await sha256(new TextEncoder().encode(joined)) : "", workerVersion: VERSION };
}

// RM1C/RM1H/RM1I: one rendered read through Firecrawl, spent and logged through the database like every other Firecrawl call
async function renderedRead(service: any, pageUrl: string, runId: string | null) {
  if (!await rpc(service, "svc_fc_spend", { p_units: 1, p_purpose: "destination_page_facts", p_provider_id: null, p_url: pageUrl })) {
    throw new Error("Firecrawl spend refused (daily share, monthly plan limit or a cost breaker)");
  }
  const fc = await rpc(service, "svc_coverage_firecrawl", {});
  if (!fc?.secret) throw new Error("no Firecrawl key");
  const body = firecrawlScrapeBody(pageUrl);
  const started = Date.now();
  let http: number | null = null, d: any = null, err: string | null = null;
  try {
    const r = await fetch("https://api.firecrawl.dev/v1/scrape", {
      method: "POST", headers: { Authorization: `Bearer ${fc.secret}`, "content-type": "application/json" }, body: JSON.stringify(body),
      signal: AbortSignal.timeout(90000), // fixed: API time-out
    });
    http = r.status; d = await r.json().catch(() => null);
  } catch (e) { err = e instanceof Error ? `${e.name}: ${e.message}` : String(e); }
  const m = d?.data?.metadata || {};
  const html = String(d?.data?.html || "");
  const markdown = String(d?.data?.markdown || "");
  const pageStatus = Number.isFinite(Number(m.statusCode)) ? Number(m.statusCode) : null;
  const error = err || (d && d.success === false ? String(d.error || "success false") : null) || (http !== null && http >= 400 ? `HTTP ${http}` : null)
    || (pageStatus !== null && pageStatus >= 400 ? `page status ${pageStatus}` : null);
  try {
    await rpc(service, "svc_fc_call_log", { p: { run_id: runId, use_case: "destination_page_facts", endpoint: "v1/scrape", url: pageUrl,
      request: { formats: body.formats, onlyMainContent: body.onlyMainContent }, http, success: !error, error, scrape_id: m.scrapeId ?? null,
      credits_used: m.creditsUsed ?? d?.creditsUsed ?? null, proxy_used: m.proxyUsed ?? null, page_status: pageStatus, duration_ms: Date.now() - started,
      outcome: error ? "fc_error" : (html || markdown) ? "read" : "no_content", meta: { cacheState: m.cacheState ?? null } } });
  } catch { /* logging never stops the read */ }
  if (error) throw new Error(`Firecrawl: ${error}`);
  if (!html && !markdown) throw new Error("Firecrawl returned no content");
  return { html: html || markdown, credits: m.creditsUsed ?? d?.creditsUsed ?? null };
}

// RM1I / RM1C / RM1H / RM1D: official pages read in turn; a page or workbook that fails is reported and the others still load
async function facts(service: any, runId: string | null, trigger: string, started: number, scope = "") {
  try {
    const cfg = await rpc(service, "svc_destination_page_facts_v1");
    const specs: any[] = Array.isArray(cfg?.facts) ? cfg.facts : [];
    const byPage = new Map<string, any[]>();
    for (const f of specs) byPage.set(f.page_url, [...(byPage.get(f.page_url) || []), f]);
    const pages: any[] = [];
    for (const [pageUrl, list] of (scope === "workbook" ? new Map<string, any[]>() : byPage)) {
      // v1.6.0 (s960, 21 Nov 2026): scope "static" reads only the pages read directly; a page any fact reads rendered (Firecrawl) is skipped, so a static read costs $0
      if (scope === "static" && list.some((f) => f.read_mode === "rendered")) continue;
      try {
        const rendered = list.some((f) => f.read_mode === "rendered");
        const got = rendered ? await renderedRead(service, pageUrl, runId) : null;
        const bytes = got ? new TextEncoder().encode(got.html) : await download(pageUrl);
        const hash = await sha256(bytes);
        const text = htmlToText(new TextDecoder("utf-8").decode(bytes));
        const host = new URL(pageUrl).host;
        const path = `destination/page-facts/${host}/${hash}${rendered ? ".rendered" : ""}.html`;
        const up = await service.storage.from("evidence").upload(path, bytes, { contentType: "text/html", upsert: true });
        pages.push({ page_url: pageUrl, sha256: hash, storage_path: up.error ? null : path, read_at: new Date().toISOString(), bytes: bytes.length, text_length: text.length,
          read_via: rendered ? "firecrawl" : "direct", fc_credits: got?.credits ?? null,
          facts: list.map((f) => {
            const r = extractFact(text, f);
            return r.found ? { id: f.id, ...r } : { id: f.id, found: false, reason: r.reason, windows: anchorWindows(text, f.anchor) };
          }) });
      } catch (e) {
        pages.push({ page_url: pageUrl, error: e instanceof Error ? e.message : String(e), facts: list.map((f) => ({ id: f.id, found: false, reason: "page not read" })) });
      }
    }
    let jsa: any = null;
    if (cfg?.jsa?.page_url && scope !== "pages" && scope !== "static") {
      try {
        const html = new TextDecoder("utf-8").decode(await download(cfg.jsa.page_url));
        const re = new RegExp(cfg.jsa.link_pattern, "i");
        const links = xlsxLinks(html, cfg.jsa.page_url);
        const link = links.find((l) => re.test(linkWords(l)));
        if (!link) {
          throw new Error(`no workbook link matching /${cfg.jsa.link_pattern}/ on ${cfg.jsa.page_url} (${links.length} workbook links: ${
            links.slice(0, 8).map((l) => l.text || l.href).join(" | ")})`);
        }
        const bytes = await download(link.href);
        const hash = await sha256(bytes);
        const path = `destination/jsa/osca-occupations/${hash}.xlsx`;
        const up = await service.storage.from("evidence").upload(path, bytes, {
          contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", upsert: true,
        });
        const wb = XLSX.read(bytes, { type: "array" });
        const sheets: any[] = [];
        let best: any = null;
        for (const name of wb.SheetNames) {
          const grid = XLSX.utils.sheet_to_json(wb.Sheets[name], { header: 1, raw: true, defval: "" }) as unknown[][];
          const parsed = parseOccupationGrid(grid);
          sheets.push({ name, rows: parsed.rows.length, header: parsed.header, first: parsed.header ? null : headerSample(grid) });
          if (parsed.rows.length && (!best || parsed.rows.length > best.rows.length)) best = { name, ...parsed };
        }
        jsa = { page_url: cfg.jsa.page_url, file_url: link.href, link_text: link.text, sha256: hash, storage_path: up.error ? null : path,
          read_at: new Date().toISOString(), sheets, sheet: best?.name ?? null, header: best?.header ?? null, rows: best?.rows ?? [] };
      } catch (e) {
        jsa = { page_url: cfg.jsa.page_url, error: e instanceof Error ? e.message : String(e) };
      }
    }
    const result = await rpc(service, "svc_destination_page_facts_load_v1", { p_payload: { run_id: runId, trigger, pages, jsa } });
    const found = pages.reduce((n, p) => n + (p.facts || []).filter((f: any) => f.found).length, 0) + (jsa?.rows?.length || 0);
    const l1 = await layer1Summary(found, [...pages.map((p) => p.sha256), jsa?.sha256]);
    return json({ ok: true, version: VERSION, mode: "facts", scope: scope || "all", trigger, run_id: runId, ms: Date.now() - started, result, ...l1 });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    try { await rpc(service, "svc_destination_page_facts_load_v1", { p_payload: { error: `${VERSION}: ${message}`, run_id: runId, trigger } }); } catch { /* recorded below */ }
    return json({ ok: false, version: VERSION, mode: "facts", error: message }, 500);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "POST required" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!, anon = Deno.env.get("SUPABASE_ANON_KEY")!, key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const service = createClient(url, key, { auth: { persistSession: false } });
  let body: any = {};
  try { body = await req.json(); } catch { body = {}; }
  const runId = clean(body.run_id) || null, trigger = clean(body.trigger) || "manual";
  try {
    await authorize(req, service, url, anon, key);
  } catch (e) {
    return json({ ok: false, error: e instanceof Error ? e.message : String(e) }, 401);
  }
  const started = Date.now();
  if (clean(body.mode) === "climate") return await climate(service, runId, trigger, started);
  if (clean(body.mode) === "facts") return await facts(service, runId, trigger, started, clean(body.scope));
  try {
    const bytes = await download(EDITION.source_url);
    const hash = await sha256(bytes);
    const path = `destination/abs/regional-population-2024-25/${hash}.xlsx`;
    const up = await service.storage.from("evidence").upload(path, bytes, {
      contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", upsert: true,
    });
    const wb = XLSX.read(bytes, { type: "array", sheets: [EDITION.sheet] });
    const ws = wb.Sheets[EDITION.sheet];
    if (!ws) throw new Error(`sheet "${EDITION.sheet}" not found (sheets: ${wb.SheetNames.join(", ")})`);
    const grid = XLSX.utils.sheet_to_json(ws, { header: 1, raw: true, defval: "" }) as unknown[][];
    const parsed = parseTable2(grid, EDITION.year);
    if (!parsed.rows.length) throw new Error("Table 2: no SUA rows");
    const result = await rpc(service, "svc_destination_abs_load_v1", {
      p_payload: {
        ...EDITION, sha256: hash, bytes: bytes.length, storage_path: up.error ? null : path, run_id: runId, trigger,
        sheet: { name: EDITION.sheet, header_row: parsed.headerRow, value_column: parsed.valueCol }, rows: parsed.rows,
      },
    });
    return json({ ok: true, version: VERSION, trigger, run_id: runId, sha256: hash, storage: up.error ? `not stored: ${up.error.message}` : path,
      ms: Date.now() - started, result, candidateObservations: parsed.rows.length, observationsSeen: parsed.rows.length, fileSha256: hash, workerVersion: VERSION });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    try { await rpc(service, "svc_destination_abs_load_v1", { p_payload: { error: `${VERSION}: ${message}`, run_id: runId, trigger } }); } catch { /* recorded below */ }
    return json({ ok: false, version: VERSION, error: message }, 500);
  }
});
