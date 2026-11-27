// studysearch-reader-burst gateway and ReaderContainer (CF-247 s1320, S1-Build, 27 Nov 2026). PREPARED, NOT DEPLOYED: HELD:DEPLOYMENT_APPROVAL.
// M3 Cloudflare Containers runbook v1.0 §4, §5.2 and §7.
//   - The gateway checks a signed request before anything starts: HMAC-SHA256 over method, path, request id, time, slot and body hash,
//     with the shared key READER_BURST_SIGNING_KEY (a Worker secret, set at deployment; the trusted caller in Supabase keeps the other copy).
//     A wrong signature, an old time, a reused request id, an unknown slot or an oversize body is refused and no container is started.
//   - The slot is one of the named slots in READER_SLOTS (reader-01; reader-02 only after approval). The caller reserves the slot under the
//     platform's existing lease; this Worker never derives a name from a provider or request id, and never queues or schedules work.
//   - The container has no internet access. The caller streams the stored copy's bytes; the container proves the hash and returns the
//     existing readers' result (supabase/functions/coverage-sweep/pdf.ts and entry-pdf-scope.ts). It writes nothing anywhere.
//   - Durable Object SQLite state holds only replay ids for this instance, never platform work.
import { DurableObject } from "cloudflare:workers";

type Env = { READER_CONTAINER: DurableObjectNamespace<ReaderContainer>; READER_BURST_SIGNING_KEY: string; READER_SLOTS: string; IDLE_MS: string; MAX_BODY_BYTES: string; MAX_PAGES: string; SIG_SKEW_S: string };

const PORT = 8080;            // fixed: the container's internal server port
const READY_TRIES = 30;       // fixed: readiness polls after start (each 1 s), a start guard, not an operational value
const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
const refuse = (code: number, error: string, rid = "") => Response.json({ ok: false, error, request_id: rid }, { status: code });

async function hmac(key: string, msg: string): Promise<string> {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return hex(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(msg)));
}
function same(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    if (req.method !== "POST" || url.pathname !== "/process") return refuse(404, "NOT_FOUND");
    const rid = req.headers.get("x-ss-request-id") || "", ts = Number(req.headers.get("x-ss-ts") || 0), slot = req.headers.get("x-ss-slot") || "";
    const bodySha = (req.headers.get("x-ss-body-sha256") || "").toLowerCase(), sig = (req.headers.get("x-ss-signature") || "").toLowerCase();
    if (!env.READER_BURST_SIGNING_KEY) return refuse(503, "NOT_CONFIGURED", rid);
    if (!/^[0-9a-f-]{36}$/.test(rid) || !/^[0-9a-f]{64}$/.test(bodySha) || !/^[0-9a-f]{64}$/.test(sig)) return refuse(401, "UNAUTHENTICATED", rid);
    if (!Number.isFinite(ts) || Math.abs(Date.now() / 1000 - ts) > Number(env.SIG_SKEW_S)) return refuse(401, "UNAUTHENTICATED", rid);
    if (!env.READER_SLOTS.split(",").map((s) => s.trim()).includes(slot)) return refuse(403, "SLOT_NOT_PERMITTED", rid);
    const want = await hmac(env.READER_BURST_SIGNING_KEY, ["POST", url.pathname, rid, String(ts), slot, bodySha].join("\n"));
    if (!same(want, sig)) return refuse(401, "UNAUTHENTICATED", rid);
    const len = Number(req.headers.get("content-length") || 0);
    if (!len || len > Number(env.MAX_BODY_BYTES)) return refuse(413, "BODY_SIZE", rid);
    const body = await req.arrayBuffer();
    if (body.byteLength !== len || hex(await crypto.subtle.digest("SHA-256", body)) !== bodySha) return refuse(400, "BODY_HASH", rid);
    // only now is the slot's Durable Object (and so its container) reached
    return env.READER_CONTAINER.getByName(slot).process(rid, body, req.headers.get("x-ss-source-sha256") || "", Number(env.MAX_PAGES), Number(env.IDLE_MS));
  },
};

export class ReaderContainer extends DurableObject<Env> {
  private starting: Promise<void> | null = null;
  private busy = false;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => { ctx.storage.sql.exec("create table if not exists seen (rid text primary key, at integer not null)") });
  }

  private async ready(idleMs: number): Promise<void> {
    const c = this.ctx.container!;
    if (!c.running) c.start({ image: c.images.reader, instance: "standard-3", enableInternet: false } as any);
    await c.setInactivityTimeout(idleMs);
    for (let i = 0; i < READY_TRIES; i++) {
      try { const r = await c.getTcpPort(PORT).fetch("http://reader/health"); if (r.ok) return } catch { /* not listening yet */ }
      await new Promise((r) => setTimeout(r, 1000));
    }
    throw new Error("CONTAINER_NOT_READY");
  }

  async process(rid: string, body: ArrayBuffer, sourceSha: string, maxPages: number, idleMs: number): Promise<Response> {
    if (!/^[0-9a-f]{64}$/.test(sourceSha)) return refuse(400, "SOURCE_HASH", rid);
    const seen = this.ctx.storage.sql.exec("select 1 from seen where rid = ?", rid).toArray();
    if (seen.length) return refuse(409, "REPLAYED", rid);
    if (this.busy) return refuse(409, "SLOT_BUSY", rid);          // one active job per slot; the caller's lease decides what waits
    this.ctx.storage.sql.exec("insert into seen (rid, at) values (?, ?)", rid, Date.now());
    this.ctx.storage.sql.exec("delete from seen where at < ?", Date.now() - 86_400_000);  // fixed: replay ids kept one day, instance state only
    this.busy = true;
    try {
      this.starting ??= this.ready(idleMs).finally(() => { this.starting = null });
      await this.starting;
      const r = await this.ctx.container!.getTcpPort(PORT).fetch("http://reader/process", {
        method: "POST", body, headers: { "x-ss-request-id": rid, "x-ss-source-sha256": sourceSha, "x-ss-max-pages": String(maxPages) },
      });
      return new Response(r.body, { status: r.status, headers: { "content-type": "application/json" } });
    } catch (e) {
      return refuse(502, String((e as Error).message || "CONTAINER_ERROR").slice(0, 80), rid);
    } finally {
      this.busy = false;
    }
  }
}
