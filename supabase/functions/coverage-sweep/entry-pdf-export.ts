// CF-247 s1049 (S1-AER-Claude, Platform Admin 24 Nov 2026 16:15 AEDT: "retrieve the archived ACU PDF ... authorised mechanism"): the read-only export that entry_inspect returns
// for a stored PDF: each page's size, count of drawn rules and positioned text items, from the same pdfPages the readers use. Stored copy only: no AI, no fetch, no write.
import { pdfPages } from "./pdf.ts";

export const isPdfCopy = (mime: string | null | undefined, path: string): boolean => /pdf/i.test(String(mime || "")) || /\.pdf(\.gz)?$/i.test(path);

export async function entryPdfExport(r: { source_id: string; url: string; storage_path: string; content_hash: string | null }, b: Uint8Array, doc: (raw: Uint8Array) => Promise<any>, ops: () => Promise<any>, sha256: (u: Uint8Array) => Promise<string>) {
  const raw = b[0] === 0x1f && b[1] === 0x8b ? new Uint8Array(await new Response(new Blob([b]).stream().pipeThrough(new DecompressionStream("gzip"))).arrayBuffer()) : b;
  const pg = await pdfPages(await doc(raw), (await ops()).OPS, 60);  // fixed: diagnostic page cap
  return { source_id: r.source_id, url: r.url, content_hash: r.content_hash, storage_path: r.storage_path, sha256: await sha256(raw), pdf_pages: pg.length,
    pages: pg.map((q) => ({ p: q.p, w: Math.round(q.width), h: Math.round(q.height), rules: q.rules.length, items: q.items.map((i) => [Math.round(i.x * 10) / 10, Math.round(i.y * 10) / 10, Math.round(i.w * 10) / 10, i.s]) })) };
}
