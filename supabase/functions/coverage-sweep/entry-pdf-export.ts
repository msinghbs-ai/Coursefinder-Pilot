// CF-247 s1049 (S1-AER-Claude, Platform Admin 24 Nov 2026 16:15 AEDT: "retrieve the archived ACU PDF ... authorised mechanism"): the read-only export that entry_inspect returns
// for a stored PDF: each page's size, count of drawn rules and positioned text items, from the same pdfPages the readers use. Stored copy only: no AI, no fetch, no write.
import { pdfPages, pdfTables } from "./pdf.ts";
import { clipRunningFooter, entryProvenPageRuns, entryTablePageScope } from "./entry-pdf-scope.ts";

export const isPdfCopy = (mime: string | null | undefined, path: string): boolean => /pdf/i.test(String(mime || "")) || /\.pdf(\.gz)?$/i.test(path);

export async function entryPdfExport(r: { source_id: string; url: string; storage_path: string; content_hash: string | null }, b: Uint8Array, doc: (raw: Uint8Array) => Promise<any>, ops: () => Promise<any>, sha256: (u: Uint8Array) => Promise<string>, opt: { from?: number; to?: number; scopeCheck?: boolean; geometry?: boolean } = {}) {
  const raw = b[0] === 0x1f && b[1] === 0x8b ? new Uint8Array(await new Response(new Blob([b]).stream().pipeThrough(new DecompressionStream("gzip"))).arrayBuffer()) : b;
  const pg = await pdfPages(await doc(raw), (await ops()).OPS, 60);  // fixed: diagnostic page cap
  // s1253: a page range (the stored copy is verified whole; only the pages returned are limited) and, when asked, what the reader makes of the whole copy and of its table pages
  let read: unknown;
  if (opt.scopeCheck) {
    const w = pdfTables(pg), sc = entryTablePageScope(pg);
    // the same two steps as entry_ai: the scoped pages, then (only if they still hold) the scoped pages without their running footer
    const sq = sc ? pg.filter((q) => q.p >= sc.first && q.p <= sc.last) : [], cq = sc ? clipRunningFooter(sq) : sq;
    let sp = sc ? pdfTables(sq) : null, clipped = false;
    if (sp && sp.status !== "ok" && cq !== sq) { const c2 = pdfTables(cq); if (c2.status === "ok") { sp = c2; clipped = true } }
    // s1253: which pages of the scope the reader proves one at a time (a page's first failing text is named), to see where a scoped read holds
    const per = sc ? pg.filter((q) => q.p >= sc.first && q.p <= sc.last).map((q) => { const r = pdfTables([q]); return { p: q.p, status: r.status, reason: r.reason.slice(0, 160) } }) : null;
    // s1372: the untitled-document page selection the worker would try next, and what the same reader makes of those pages together (read only)
    const pr = w.status === "ok" ? null : entryProvenPageRuns(pg, pdfTables), pq = pr ? pdfTables(pg.filter((q) => pr.pages.includes(q.p))) : null;
    read = { proven_runs: pr ? { ...pr, status: pq!.status, reason: pq!.reason.slice(0, 300), tables: pq!.tables.length } : null, per_page: per, whole: { status: w.status, reason: w.reason.slice(0, 300), tables: w.tables.length }, scope: sc, scoped: sp ? { clipped_footer: clipped, status: sp.status, reason: sp.reason.slice(0, 300), tables: sp.tables.length, headers: sp.tables.map((t) => ({ page: t.page, columns: t.columns, rows: t.rows })) } : null };
  }
  const shown = pg.filter((q) => q.p >= (opt.from ?? 1) && q.p <= (opt.to ?? Infinity));
  return { source_id: r.source_id, url: r.url, content_hash: r.content_hash, storage_path: r.storage_path, sha256: await sha256(raw), pdf_pages: pg.length, read,
    pages: shown.map((q) => ({ p: q.p, w: Math.round(q.width), h: Math.round(q.height), rules: q.rules.length,
      // s1253: the drawn rules themselves (orientation, position, extent), for at most three pages and 600 rules a page, only when asked; items then carry their height
      ...(opt.geometry && shown.length <= 3 ? { rule_list: q.rules.slice(0, 600).map((r) => [r.o, Math.round((r.o === "h" ? r.y! : r.x!) * 10) / 10, Math.round(r.a * 10) / 10, Math.round(r.b * 10) / 10, r.box ? 1 : 0]) } : {}), items: q.items.map((i) => opt.geometry && shown.length <= 3 ? [Math.round(i.x * 10) / 10, Math.round(i.y * 10) / 10, Math.round(i.w * 10) / 10, i.s, Math.round(i.h * 10) / 10] : [Math.round(i.x * 10) / 10, Math.round(i.y * 10) / 10, Math.round(i.w * 10) / 10, i.s]) })) };
}
