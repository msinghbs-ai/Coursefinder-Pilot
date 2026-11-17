import { createClient } from "npm:@supabase/supabase-js@2.57.4";

// CF-247 Boost bulk ingestion (Platform Admin 17 Nov 2026 16:15; migration 20261117163500_cf247_boost_bulk_ingest).
// Called by the job worker-boost-bulk-ingest (one-time nonce) inside the overnight window. Reads the Boost Worker's result files from Storage
// staging-boost/inbound/ (NDJSON, one result per line), claims each new file once, loads its rows into pipeline.boost_inbound_staging and
// settles each loaded batch with security.boost_promote_v1 (qualified study load only; everything else shadow, proposed or refused).
// Before each file it asks security.boost_ingest_gate_v1 again: it stops when the window, the squash blackout, housekeeping-daily or the switch
// say so, and it waits (briefly) while a PR 1, PR 2 or PR 3 tick holds its lock. Sizes come from the gate (settings boost.ingest_*).

const VERSION = "worker-boost-bulk-ingest-v1.0.0";
const FN = "worker-boost-bulk-ingest";
const BUCKET = "staging-boost";
const PREFIX = "inbound";
const TIME_BUDGET_MS = 100_000; // fixed: stays inside the edge function wall time and the caller's 120 s request time-out
const LOCK_WAIT_MS = 5_000;     // fixed: a dispatcher tick lasts about a second; wait and look again
const LOCK_TRIES = 6;           // fixed: give up for this run after about 30 s of busy ticks

const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
async function rpc(c: any, n: string, a: Record<string, unknown> = {}) {
  const { data, error } = await c.rpc(n, a);
  if (error) throw new Error(`${n}: ${error.message}`);
  return data;
}

// the gate, waiting while a dispatcher tick holds its lock
async function gate(svc: any): Promise<any> {
  let g: any = null;
  for (let i = 0; i < LOCK_TRIES; i++) {
    g = await rpc(svc, "svc_boost_ingest_gate");
    if (g?.ok || g?.reason !== "a dispatcher tick is running") return g;
    await sleep(LOCK_WAIT_MS);
  }
  return g;
}

async function listInbound(svc: any): Promise<string[]> {
  const out: string[] = [];
  for (let offset = 0; offset < 5000; offset += 100) { // fixed: listing page size and a bound
    const { data, error } = await svc.storage.from(BUCKET).list(PREFIX, { limit: 100, offset, sortBy: { column: "name", order: "asc" } });
    if (error) throw new Error(`list ${BUCKET}/${PREFIX}: ${error.message}`);
    for (const f of data || []) if (f?.name && /\.(ndjson|jsonl)$/i.test(f.name)) out.push(`${PREFIX}/${f.name}`);
    if (!data || data.length < 100) break;
  }
  return out;
}

export function parseLines(text: string): { rows: any[]; lines: number; bad: number } {
  const rows: any[] = []; let lines = 0, bad = 0;
  for (const raw of text.split("\n")) {
    const line = raw.trim();
    if (!line) continue;
    lines++;
    try {
      const j = JSON.parse(line);
      if (j && j.kind === "result" && typeof j.batch_id === "string" && typeof j.item_key === "string") rows.push(j); else bad++;
    } catch { bad++; }
  }
  return { rows, lines, bad };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, error: "POST required" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!, serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const svc = createClient(url, serviceKey, { auth: { persistSession: false } });
  const started = Date.now();
  try {
    const nonce = (req.headers.get("x-cf-run-nonce") || "").trim(), bearer = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
    if (nonce) { if (!await rpc(svc, "svc_pilot_consume_nonce", { p_function: FN, p_nonce: nonce })) throw new Error("invalid, expired or already-used nonce"); }
    else if (bearer !== serviceKey) throw new Error("service authorisation required");

    let g = await gate(svc);
    if (!g?.ok) return json({ ok: true, version: VERSION, skipped: g?.reason || "gate closed", gate: g });
    const filesPerRun = Math.max(1, Number(g.settings?.files_per_run) || 1);
    const rowsPerCall = Math.max(50, Number(g.settings?.rows_per_call) || 50);

    const listed = await listInbound(svc);
    const done: any[] = [];
    let stopped: string | null = null;
    for (const path of listed) {
      if (done.length >= filesPerRun) break;
      if (Date.now() - started > TIME_BUDGET_MS) { stopped = "time budget"; break; }
      if (done.length > 0) { g = await gate(svc); if (!g?.ok) { stopped = g?.reason || "gate closed"; break; } }
      const claimed: string[] = await rpc(svc, "svc_boost_ingest_claim", { p_paths: [path] }) || [];
      if (!claimed.includes(path)) continue; // loaded before, failed before, or another run has it
      let lines = 0, loaded = 0; const batches = new Set<string>(); const promoted: Record<string, unknown> = {};
      try {
        const { data, error } = await svc.storage.from(BUCKET).download(path);
        if (error || !data) throw new Error(`download ${path}: ${error?.message || "not found"}`);
        const parsed = parseLines(await data.text());
        lines = parsed.lines;
        for (let i = 0; i < parsed.rows.length; i += rowsPerCall) {
          const chunk = parsed.rows.slice(i, i + rowsPerCall);
          const r = await rpc(svc, "svc_boost_inbound_load", { p_rows: chunk });
          loaded += Number(r?.loaded) || 0;
          for (const x of chunk) batches.add(x.batch_id);
        }
        for (const b of batches) promoted[b] = await rpc(svc, "svc_boost_promote", { p_batch: b });
        await rpc(svc, "svc_boost_ingest_done", { p_path: path, p_lines: lines, p_loaded: loaded, p_batches: [...batches], p_promoted: promoted, p_error: null });
        done.push({ path, lines, loaded, bad_lines: parsed.bad, batches: [...batches], promoted });
      } catch (e) {
        const msg = String((e as Error)?.message || e).slice(0, 500);
        await rpc(svc, "svc_boost_ingest_done", { p_path: path, p_lines: lines, p_loaded: loaded, p_batches: [...batches], p_promoted: promoted, p_error: msg }).catch(() => {});
        done.push({ path, error: msg });
      }
    }
    return json({ ok: true, version: VERSION, listed: listed.length, files: done, stopped, ms: Date.now() - started });
  } catch (e) {
    return json({ ok: false, version: VERSION, error: String((e as Error)?.message || e) }, 500);
  }
});
