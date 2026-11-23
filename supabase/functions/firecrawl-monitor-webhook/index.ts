// firecrawl-monitor-webhook (CF-247 s1027, S1-Build; Platform Admin 24 Nov 2026 06:03, 06:10, 06:27 and 09:06 AEDT; UI-UX plan v1.2 slice 8).
// 1. Firecrawl Monitor deliveries (POST with X-Firecrawl-Signature): the signature is checked first (HMAC-SHA256 of the raw body with the
//    account's webhook secret FIRECRAWL_WEBHOOK_SECRET, constant-time compare); a missing or wrong signature is refused with 401 and nothing is
//    read. Each page is recorded once (public.svc_monitor_event_v1) and the call is answered at once (Firecrawl needs a 2xx within 10 s).
//    In the background, a changed or new page is fetched from the check, archived to storage evidence/aer-artifacts/<provider>/monitor/
//    <sha256>.json.gz with its SHA-256, and only then routed (public.svc_monitor_route_v1): locked fields to Locked Field Update, other
//    changed fees, intakes and English to Layer 4 with their gate result. Nothing is admitted by the machine (Platform Admin 24 Nov 2026).
//    A completed check over the weekly credit cap pauses the monitors (HELD:BUDGET_GATE).
// 2. Platform calls (POST with a one-time x-cf-run-nonce from pipeline.svc_pilot_submit_nonce): {"action": "register" | "status" | "pause"}.
//    register plans the watchlist within the cap (public.svc_monitor_watchlist_v1) and creates or updates one monitor per university (and its
//    search monitor), recording Firecrawl's monthly estimate.
// Errors to callers carry fixed codes only.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const VERSION = "firecrawl-monitor-webhook-v1.0.0";
const FC = "https://api.firecrawl.dev/v2";
const FC_TIMEOUT_MS = 20000;   // fixed: Firecrawl API time-out
const CHECK_PAGES = 5;         // fixed: pages of a check's results read to find one URL

// What a watched page is read for (Firecrawl's JSON change tracking). Values feed Layer 4 proposals only.
export const SCHEMA = {
  type: "object",
  properties: {
    tuition_fees: { type: "array", items: { type: "object", properties: {
      fee_year: { type: "integer", description: "The year the fee applies to, as the page states it" },
      audience: { type: "string", enum: ["international", "domestic"] },
      amount: { type: "number" }, currency: { type: "string" },
      basis: { type: "string", enum: ["annual", "per_course", "per_unit", "per_semester", "per_credit_point"] } } } },
    intakes: { type: "array", items: { type: "object", properties: {
      intake_year: { type: "integer" }, intake_label: { type: "string", description: "The intake as the page names it, for example February or Semester 1" },
      start_date: { type: "string", description: "YYYY-MM-DD only when the page states the full date" } } } },
    english: { type: "array", items: { type: "object", properties: {
      test: { type: "string", enum: ["IELTS", "PTE", "TOEFL_IBT"] }, overall: { type: "number" },
      listening: { type: "number" }, reading: { type: "number" }, writing: { type: "number" }, speaking: { type: "number" } } } },
  },
};
export const PROMPT = "Record only what this course page states for international students: the tuition fee with its year, the intakes, and the English test scores (overall and each band). Leave out anything the page does not state; never estimate a year, a date or a score.";

const j = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { "content-type": "application/json" } });
const svc = () => createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");

export function safeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}
export async function signatureOk(raw: Uint8Array, header: string | null, secret: string | undefined) {
  if (!secret || !header) return false;
  const [alg, sig] = header.trim().split("=", 2);
  if (alg !== "sha256" || !/^[0-9a-f]{64}$/i.test(sig || "")) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return safeEqual(hex(await crypto.subtle.sign("HMAC", key, raw)), sig.toLowerCase());
}
async function gzip(b: Uint8Array) {
  const cs = new CompressionStream("gzip"); const w = cs.writable.getWriter(); w.write(b); w.close();
  return new Uint8Array(await new Response(cs.readable).arrayBuffer());
}

async function fcKey(c: ReturnType<typeof svc>) {
  const { data } = await c.rpc("svc_coverage_firecrawl", {});
  return (data as any)?.secret as string | undefined;
}
async function fc(key: string, method: string, path: string, body?: unknown) {
  const r = await fetch(FC + path, { method, headers: { authorization: `Bearer ${key}`, "content-type": "application/json" }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(FC_TIMEOUT_MS) });
  const d = await r.json().catch(() => ({}));
  return { ok: r.ok && (d as any)?.success !== false, status: r.status, d: d as any };
}

// The page's entry in its check (with snapshot.json), read from at most CHECK_PAGES pages of results.
async function checkPage(key: string, monitorId: string, checkId: string, url: string, status: string) {
  let path: string | null = `/monitor/${encodeURIComponent(monitorId)}/checks/${encodeURIComponent(checkId)}?status=${encodeURIComponent(status)}`;
  for (let i = 0; path && i < CHECK_PAGES; i++) {
    const r = await fc(key, "GET", path);
    if (!r.ok) return null;
    const pages: any[] = r.d?.data?.pages || r.d?.data?.results || r.d?.pages || [];
    const hit = pages.find((p) => String(p?.url || "").replace(/\/+$/, "") === url.replace(/\/+$/, ""));
    if (hit) return hit;
    const next = r.d?.next || r.d?.data?.next;
    path = next ? String(next).replace(/^https:\/\/api\.firecrawl\.dev\/v2/, "") : null;
  }
  return null;
}

async function archiveAndRoute(c: ReturnType<typeof svc>, ev: { id: number; provider_id: string | null }, item: any, envelope: any) {
  let evidence: Record<string, unknown> = {}; let snapshot: unknown = item?.snapshot?.json ?? null;
  try {
    const key = await fcKey(c);
    const page = key ? await checkPage(key, String(item.monitorId), String(item.checkId), String(item.url), String(item.status)) : null;
    snapshot = page?.snapshot?.json ?? page?.json ?? snapshot;
    const content = new TextEncoder().encode(JSON.stringify({ captured_at: new Date().toISOString(), capture: VERSION, webhook_id: envelope?.webhookId, monitor_id: item.monitorId,
      check_id: item.checkId, url: item.url, page_status: item.status, item, check_page: page }));
    const sha = hex(await crypto.subtle.digest("SHA-256", content));
    const path = `aer-artifacts/${ev.provider_id || "unknown"}/monitor/${sha}.json.gz`;
    const up = await c.storage.from("evidence").upload(path, await gzip(content), { contentType: "application/gzip", upsert: true });
    evidence = up.error ? { error: "storage_upload_failed" } : { storage_path: path, sha256: sha, bytes: content.length };
  } catch { evidence = { error: "archive_failed" } }
  await c.rpc("svc_monitor_route_v1", { p_event_id: ev.id, p_evidence: evidence, p_snapshot: snapshot });
}

async function pauseAll(c: ReturnType<typeof svc>, ids: string[]) {
  const key = await fcKey(c); if (!key) return;
  for (const id of ids) {
    const r = await fc(key, "PATCH", `/monitor/${encodeURIComponent(id)}`, { status: "paused" });
    if (r.ok) await c.rpc("svc_monitor_registered_v1", { p: { monitor_id: id, status: "paused", note: "HELD:BUDGET_GATE: the week's credits passed firecrawl.monitor_weekly_credits" } });
  }
}

async function register(c: ReturnType<typeof svc>) {
  const { data, error } = await c.rpc("svc_monitor_watchlist_v1", {});
  if (error) return { ok: false, error: "WATCHLIST_READ_FAILED" };
  const key = await fcKey(c); if (!key) return { ok: false, error: "NO_FIRECRAWL_KEY" };
  const s = (data as any).settings, hook = `${Deno.env.get("SUPABASE_URL")}/functions/v1/firecrawl-monitor-webhook`;
  const out: unknown[] = [];
  for (const p of (data as any).providers as any[]) {
    const jobs: [string, any, string | null][] = [];
    if (p.scrape?.urls?.length) jobs.push(["scrape", { type: "scrape", urls: p.scrape.urls, scrapeOptions: { formats: [{ type: "changeTracking", modes: ["json"], schema: SCHEMA, prompt: PROMPT }] } }, p.scrape.monitor_id]);
    if (p.search?.queries?.length) jobs.push(["search", { type: "search", queries: p.search.queries, maxResults: Number(s.search_results), searchWindow: "7d", ...(p.search.domain ? { includeDomains: [p.search.domain] } : {}) }, p.search.monitor_id]);
    for (const [kind, target, existing] of jobs) {
      const body = { name: `StudySearch ${p.name} (${kind === "scrape" ? "fees, intakes, English" : "search"})`.slice(0, 250), schedule: { cron: String(s.cron), timezone: "UTC" },
        judgeEnabled: false, targets: [target], retentionDays: Number(s.retention_days),
        webhook: { url: hook, events: ["monitor.page", "monitor.check.completed"], metadata: { provider_id: p.provider_id, target: kind } } };
      const r = existing ? await fc(key, "PATCH", `/monitor/${encodeURIComponent(existing)}`, { ...body, status: "active" }) : await fc(key, "POST", "/monitor", body);
      const id = r.d?.data?.id || existing || null, est = r.d?.data?.estimatedCreditsPerMonth ?? null;
      await c.rpc("svc_monitor_registered_v1", { p: { provider_id: p.provider_id, target_type: kind, monitor_id: id, est_month_credits: est,
        status: r.ok ? "registered" : "error", note: r.ok ? null : `Firecrawl HTTP ${r.status}: ${String(r.d?.error || r.d?.message || "").slice(0, 300)}` } });
      out.push({ provider: p.name, target: kind, ok: r.ok, http: r.status, monitor_id: id, est_month_credits: est });
    }
  }
  return { ok: true, plan: (data as any).plan, weekly_cap: s.weekly_cap, monitors: out };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return j({ error: "METHOD_NOT_ALLOWED" }, 405);
  const c = svc();
  const nonce = (req.headers.get("x-cf-run-nonce") || "").trim();
  if (nonce) {
    const { data: ok } = await c.rpc("svc_pilot_consume_nonce", { p_function: "firecrawl-monitor-webhook", p_nonce: nonce });
    if (!ok) return j({ error: "UNAUTHORISED" }, 401);
    const b = await req.json().catch(() => ({}));
    if (b?.action === "register") return j({ ...(await register(c)), version: VERSION });
    if (b?.action === "status") { const { data } = await c.rpc("svc_monitor_watchlist_v1", {}); return j({ ok: true, version: VERSION, watchlist: data }) }
    if (b?.action === "pause") {
      const { data } = await c.rpc("svc_monitor_watchlist_v1", {});
      const ids = (((data as any)?.providers || []) as any[]).flatMap((p) => [p.scrape?.monitor_id, p.search?.monitor_id]).filter(Boolean) as string[];
      await pauseAll(c, ids); return j({ ok: true, version: VERSION, paused: ids });
    }
    return j({ error: "UNKNOWN_ACTION" }, 400);
  }
  const raw = new Uint8Array(await req.arrayBuffer());
  if (!(await signatureOk(raw, req.headers.get("x-firecrawl-signature"), Deno.env.get("FIRECRAWL_WEBHOOK_SECRET")))) return j({ error: "UNAUTHORISED" }, 401);
  let env: any; try { env = JSON.parse(new TextDecoder().decode(raw)) } catch { return j({ error: "INVALID_INPUT" }, 400) }
  const type = String(env?.type || ""), meta = env?.metadata || {}, items: any[] = Array.isArray(env?.data) ? env.data : [];
  const work: Promise<unknown>[] = [];
  for (const it of items) {
    const { data } = await c.rpc("svc_monitor_event_v1", { p: { webhook_id: String(env?.webhookId || env?.id || ""), event_type: type, monitor_id: it?.monitorId, check_id: it?.checkId,
      provider_id: meta?.provider_id || null, url: it?.url || null, page_status: it?.status || null, is_meaningful: it?.isMeaningful ?? null, diff: it?.diff ?? null,
      summary: it?.summary ?? null, payload: { ...it, diff: undefined } } });
    const d = data as any;
    if (!d || d.duplicate) continue;
    if (d.route) work.push(archiveAndRoute(c, { id: d.id, provider_id: d.provider_id }, it, env));
    if (d.over_cap) work.push(pauseAll(c, (d.monitor_ids || []) as string[]));
  }
  if (work.length) EdgeRuntime.waitUntil(Promise.allSettled(work));
  return j({ ok: true });
});
