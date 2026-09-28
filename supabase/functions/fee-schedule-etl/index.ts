import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { getDocumentProxy } from "npm:unpdf@0.12.1";

// CF-247 Decision 162 step 2: provider international fee schedules (one document per provider per fee year).
// v0.1.0: inspect mode only — fetch a schedule from an allow-listed university host and return its text laid out
// as rows (grouped by line, ordered left to right), so each provider's parser rule is written against the real
// document. Nothing is written. Invoked only with a one-time Pilot nonce.
const VERSION = "fee-schedule-etl-v0.3.0";
// v0.3.0: apply — the schedule file is stored as evidence and svc_fee_schedule_apply writes each bound row through
// the governed course-facts path (Decision 162 step 2).
// v0.2.0: dry_run — parse a registered schedule and compare it with the catalogue (svc_fee_schedule_preview).
// Parser rule (all registered schedules): a row holding exactly one CRICOS course code; the fee is the first
// whole-dollar amount after that code (the annual fee for one full-time year); the title is the first cell.
const SCHEDULES: Record<string, { provider_cricos: string; url: string; fee_year: number; basis: string; label: string }> = {
  federation_2026_commencing: { provider_cricos: "00103D", fee_year: 2026, basis: "annual",
    url: "https://federation.edu.au/__data/assets/pdf_file/0006/630951/2026_HEd_Intl_Tuition_Fee_Schedule_Commencing.pdf",
    label: "Federation University 2026 commencing international tuition fee schedule (annual fee, 1 EFTSL)" },
  wsu_ug_2027: { provider_cricos: "00917K", fee_year: 2027, basis: "annual",
    url: "https://www.westernsydney.edu.au/content/dam/digital/pdf/international/ug-intl-fees-2027.pdf",
    label: "Western Sydney University 2027 undergraduate international tuition fees (annual)" },
  wsu_pg_2027: { provider_cricos: "00917K", fee_year: 2027, basis: "annual",
    url: "https://www.westernsydney.edu.au/content/dam/digital/pdf/international/pg-intl-fees-2027.pdf",
    label: "Western Sydney University 2027 postgraduate international tuition fees (annual)" },
};
const CODE_CELL = /^\d{6}[0-9A-Z]$/;
const FEE_CELL = /^\$\s?(\d{1,3}(?:,\d{3})+|\d{4,6})(?:\.00)?$/;
function parseRows(rows: string[]) {
  const out: { course_cricos: string; title: string; amount: number; raw: string }[] = [];
  const rejected: string[] = [];
  for (const raw of rows) {
    const cells = raw.split(" | ").map((x) => x.trim()).filter(Boolean);
    const idx = cells.map((c, i) => (CODE_CELL.test(c) ? i : -1)).filter((i) => i >= 0);
    if (idx.length === 0) continue;
    if (idx.length > 1) { rejected.push(raw); continue; }
    const fee = cells.slice(idx[0] + 1).find((c) => FEE_CELL.test(c));
    if (!fee) { rejected.push(raw); continue; }
    const amount = Number(fee.replace(/[^0-9.]/g, ""));
    if (!(amount >= 5000 && amount <= 150000)) { rejected.push(raw); continue; }
    out.push({ course_cricos: cells[idx[0]], title: cells[0], amount, raw });
  }
  return { rows: out, rejected };
}
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
    if (mode === "dry_run" || mode === "apply") {
      const sc = SCHEDULES[t(body.schedule)];
      if (!sc) throw Error("unknown schedule; registered: " + Object.keys(SCHEDULES).join(", "));
      const su = new URL(sc.url);
      const rr = await fetch(su, { redirect: "follow", headers: { "user-agent": "CourseFinder-Pilot/fee-schedule-0.2" } });
      if (!rr.ok) throw Error(`HTTP ${rr.status}`);
      const b = new Uint8Array(await rr.arrayBuffer());
      const hb = await crypto.subtle.digest("SHA-256", b);
      const sha = [...new Uint8Array(hb)].map((x) => x.toString(16).padStart(2, "0")).join("");
      const d = await pdfRows(b, 400);
      const parsed = parseRows(d.pages.flatMap((p) => p.rows));
      const { data: preview, error } = await c.rpc("svc_fee_schedule_preview", { p_provider_cricos: sc.provider_cricos, p_fee_year: sc.fee_year,
        p_rows: parsed.rows.map(({ raw, ...x }) => x) });
      if (error) throw Error(error.message);
      if (mode === "apply") {
        if (parsed.rows.length < 10) throw Error("too few rows parsed; apply refused");
        const path = `layer2/AU/fee-schedules/${sc.provider_cricos}/${sc.fee_year}/${sha}.pdf`;
        const up = await c.storage.from("evidence").upload(path, b, { contentType: "application/pdf", upsert: true });
        if (up.error) throw Error("evidence upload failed: " + up.error.message);
        const { data: applied, error: ae } = await c.rpc("svc_fee_schedule_apply", { p_provider_cricos: sc.provider_cricos, p_fee_year: sc.fee_year,
          p_storage_path: path, p_url: sc.url, p_sha256: sha, p_schedule: t(body.schedule), p_rows: parsed.rows.map(({ raw, ...x }) => x) });
        if (ae) throw Error(ae.message);
        return j({ ok: true, mode, schedule: t(body.schedule), url: sc.url, sha256: sha, parsedRows: parsed.rows.length, rejectedRows: parsed.rejected.length,
          preview: { actions: preview?.actions, bound: preview?.bound }, applied, workerVersion: VERSION });
      }
      return j({ ok: true, mode, schedule: t(body.schedule), label: sc.label, url: sc.url, sha256: sha, bytes: b.length, numPages: d.numPages,
        parsedRows: parsed.rows.length, rejectedRows: parsed.rejected.length, rejectedSample: parsed.rejected.slice(0, 8), preview, workerVersion: VERSION });
    }
    if (mode !== "inspect") throw Error("supported modes: inspect, dry_run, apply");
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
