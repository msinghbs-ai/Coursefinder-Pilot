import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { getDocumentProxy } from "npm:unpdf@0.12.1";

// CF-247 Decision 162 step 2: provider international fee schedules (one document per provider per fee year).
// v0.1.0: inspect mode only — fetch a schedule from an allow-listed university host and return its text laid out
// as rows (grouped by line, ordered left to right), so each provider's parser rule is written against the real
// document. Nothing is written. Invoked only with a one-time Pilot nonce.
const VERSION = "fee-schedule-etl-v0.1.0";
const HOSTS = ["federation.edu.au", "westernsydney.edu.au", "cdu.edu.au", "csu.edu.au", "rmit.edu.au", "swinburne.edu.au", "uow.edu.au"];
const j = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });
const t = (v: unknown) => String(v ?? "").trim();
const CRICOS = /\b\d{6}[0-9A-Z]\b/g;
const MONEY = /\$\s?\d{1,3}(,\d{3})+(\.\d{2})?/g;

function allowed(u: URL) {
  return u.protocol === "https:" && HOSTS.some((h) => u.hostname === h || u.hostname.endsWith("." + h));
}

async function pdfRows(bytes: Uint8Array, maxPages: number) {
  const pdf = await getDocumentProxy(bytes);
  const pages: { page: number; rows: string[] }[] = [];
  for (let p = 1; p <= Math.min(pdf.numPages, maxPages); p++) {
    const page = await pdf.getPage(p);
    const tc = await page.getTextContent();
    const lines = new Map<number, { x: number; s: string }[]>();
    for (const it of tc.items as any[]) {
      const s = t(it.str);
      if (!s) continue;
      const y = Math.round(it.transform[5] / 2) * 2; // rows within 2 units share a line
      if (!lines.has(y)) lines.set(y, []);
      lines.get(y)!.push({ x: it.transform[4], s });
    }
    const rows = [...lines.entries()].sort((a, b) => b[0] - a[0]).map(([, xs]) => xs.sort((a, b) => a.x - b.x).map((x) => x.s).join(" | "));
    pages.push({ page: p, rows });
  }
  return { numPages: pdf.numPages, pages };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return j({ error: "POST required", workerVersion: VERSION }, 405);
  const c = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  try {
    const nonce = t(req.headers.get("x-cf-run-nonce"));
    const { data: ok } = nonce ? await c.rpc("svc_pilot_consume_nonce", { p_function: "fee-schedule-etl", p_nonce: nonce }) : { data: false };
    if (!ok) return j({ error: "valid one-time Pilot nonce required", workerVersion: VERSION }, 401);
    const body = await req.json().catch(() => ({}));
    const mode = t(body.mode || "inspect");
    if (mode !== "inspect") throw Error("v0.1.0 supports inspect only");
    const u = new URL(t(body.url));
    if (!allowed(u)) throw Error("address must be https on an allow-listed university host");
    const r = await fetch(u, { redirect: "follow", headers: { "user-agent": "CourseFinder-Pilot/fee-schedule-0.1" } });
    if (!r.ok) throw Error(`HTTP ${r.status}`);
    const type = t(r.headers.get("content-type")).toLowerCase();
    const bytes = new Uint8Array(await r.arrayBuffer());
    const hashBuf = await crypto.subtle.digest("SHA-256", bytes);
    const sha256 = [...new Uint8Array(hashBuf)].map((x) => x.toString(16).padStart(2, "0")).join("");
    if (type.includes("pdf") || u.pathname.toLowerCase().endsWith(".pdf")) {
      const d = await pdfRows(bytes, Number(body.max_pages || 3));
      const all = d.pages.flatMap((p) => p.rows).join("\n");
      return j({ ok: true, mode, kind: "pdf", url: u.toString(), bytes: bytes.length, sha256, numPages: d.numPages,
        cricosLikeOnInspectedPages: (all.match(CRICOS) || []).length, moneyOnInspectedPages: (all.match(MONEY) || []).length,
        pages: d.pages.map((p) => ({ page: p.page, rows: p.rows.slice(0, Number(body.max_rows || 45)) })), workerVersion: VERSION });
    }
    const html = new TextDecoder().decode(bytes);
    const links = [...html.matchAll(/href=["']([^"']+\.(?:pdf|xlsx|csv))["']/gi)].map((m) => new URL(m[1], u).toString());
    return j({ ok: true, mode, kind: "html", url: u.toString(), bytes: bytes.length, sha256,
      documentLinks: [...new Set(links)].filter((l) => /fee|tuition|intl|international/i.test(l)).slice(0, 60),
      cricosLike: (html.match(CRICOS) || []).length, workerVersion: VERSION });
  } catch (e) {
    return j({ ok: false, error: e instanceof Error ? e.message : String(e), workerVersion: VERSION }, 422);
  }
});
