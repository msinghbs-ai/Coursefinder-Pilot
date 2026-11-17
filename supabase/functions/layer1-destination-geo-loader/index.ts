import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import * as XLSX from "npm:xlsx@0.18.5";

// CF-247 RM1B (Platform Admin 17 Nov 2026 13:12; approvals A-1 to A-4 of 07:29 and 07:35): ABS population loader for Australian
// destination localities. Reads ABS Regional population 2024-25, Table 2 (estimated resident population by Significant Urban Area),
// stores the file as evidence and hands the SUA rows to public.svc_destination_abs_load_v1, which writes draft localities and figures
// with attribution and maps postcodes from the ASGS Edition 3 shares (workflow destination-abs-shares-load).
// Run by job destination-abs-load (1st of the month, 05:30 Sydney) and Run now, each with a one-time nonce; a Platform Admin may also
// call it signed in. A new ABS edition is a new approval (design: "Any source beyond A-1 and A-4 needs a new approval"), so the
// edition below changes only with a reviewed code change.
const VERSION = "layer1-destination-geo-loader-v1.0.0";
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

async function authorize(req: Request, service: any, url: string, anon: string) {
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "POST required" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!, anon = Deno.env.get("SUPABASE_ANON_KEY")!, key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const service = createClient(url, key, { auth: { persistSession: false } });
  let body: any = {};
  try { body = await req.json(); } catch { body = {}; }
  const runId = clean(body.run_id) || null, trigger = clean(body.trigger) || "manual";
  try {
    await authorize(req, service, url, anon);
  } catch (e) {
    return json({ ok: false, error: e instanceof Error ? e.message : String(e) }, 401);
  }
  const started = Date.now();
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
      ms: Date.now() - started, result });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    try { await rpc(service, "svc_destination_abs_load_v1", { p_payload: { error: `${VERSION}: ${message}`, run_id: runId, trigger } }); } catch { /* recorded below */ }
    return json({ ok: false, version: VERSION, error: message }, 500);
  }
});
