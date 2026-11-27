// Reader container server (CF-247 s1320, S1-Build, 27 Nov 2026). PREPARED, NOT DEPLOYED: HELD:DEPLOYMENT_APPROVAL.
// Reached only from the gateway's Durable Object on the internal port; the container has no internet access.
// It runs the existing stored-PDF read of the coverage-sweep worker (index.ts storedText, PDF branch, s1253 scope retry) with the same
// modules, copied into the image from supabase/functions/coverage-sweep at build time, never rewritten: pdf.ts (ruled-cells-v1) and
// entry-pdf-scope.ts. It returns the proven tables and positioned pages; the trusted caller runs the existing readers, verifier and
// admission writer on them. It fetches nothing, writes nothing and holds no credential.
import { getDocumentProxy, getResolvedPDFJS } from "npm:unpdf@0.12.1";
import { pdfPages, pdfTables, PDF_METHOD } from "./reader/pdf.ts";
import { clipRunningFooter, entryTablePageScope } from "./reader/entry-pdf-scope.ts";

const MAX_RAW = 200 * 1024 * 1024;  // fixed: decompression guard (a stored copy that inflates past this is refused)
const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
const out = (status: number, o: Record<string, unknown>) => Response.json(o, { status });

async function gunzipCapped(b: Uint8Array): Promise<Uint8Array> {
  const r = new Blob([b]).stream().pipeThrough(new DecompressionStream("gzip")).getReader();
  const parts: Uint8Array[] = []; let n = 0;
  for (;;) { const { done, value } = await r.read(); if (done) break; n += value.length; if (n > MAX_RAW) { await r.cancel(); throw new Error("INFLATED_SIZE") } parts.push(value) }
  const all = new Uint8Array(n); let o = 0; for (const p of parts) { all.set(p, o); o += p.length }
  return all;
}

Deno.serve({ port: 8080 }, async (req) => {
  const url = new URL(req.url);
  if (req.method === "GET" && url.pathname === "/health") return out(200, { ok: true, method: PDF_METHOD });
  if (req.method !== "POST" || url.pathname !== "/process") return out(404, { ok: false, error: "NOT_FOUND" });
  const rid = req.headers.get("x-ss-request-id") || "", want = req.headers.get("x-ss-source-sha256") || "", maxPages = Number(req.headers.get("x-ss-max-pages") || 0);
  const t0 = performance.now();
  try {
    const b = new Uint8Array(await req.arrayBuffer());
    const raw = b[0] === 0x1f && b[1] === 0x8b ? await gunzipCapped(b) : b;
    const sha = hex(await crypto.subtle.digest("SHA-256", raw));
    if (sha !== want) return out(400, { ok: false, error: "SOURCE_HASH_MISMATCH", request_id: rid });
    if (!(raw[0] === 0x25 && raw[1] === 0x50 && raw[2] === 0x44 && raw[3] === 0x46)) return out(415, { ok: false, error: "NOT_PDF", request_id: rid });
    const rawBytes = raw.length;  // read before pdf.js takes the buffer
    const doc = await getDocumentProxy(raw); const { OPS } = await getResolvedPDFJS();
    let pages = await pdfPages(doc, OPS, maxPages), t = pdfTables(pages);
    // the s1253 scope retry, exactly as coverage-sweep index.ts storedText
    if (t.status !== "ok") { const sc = entryTablePageScope(pages); if (sc && (sc.first > pages[0].p || sc.last < pages[pages.length - 1].p)) { let sp = pages.filter((q) => q.p >= sc.first && q.p <= sc.last), st = pdfTables(sp); if (st.status !== "ok") { const cp = clipRunningFooter(sp); if (cp !== sp) { sp = cp; st = pdfTables(sp) } } if (st.status === "ok") { pages = sp; t = { ...st, reason: `scoped to pages ${sc.first}-${sc.last}` } } } }
    const mem = Deno.memoryUsage();
    return out(200, {
      ok: true, request_id: rid, method: PDF_METHOD, source_sha256: sha, raw_bytes: rawBytes, doc_pages: doc.numPages, read_pages: pages.length,
      pdf: t, pdfPages: pages,
      measured: { wall_ms: Math.round(performance.now() - t0), rss_bytes: mem.rss, heap_used_bytes: mem.heapUsed },
    });
  } catch (e) {
    return out(422, { ok: false, error: String((e as Error).message || "READ_FAILED").slice(0, 120), request_id: rid, wall_ms: Math.round(performance.now() - t0) });
  }
});
