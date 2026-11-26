// CF-247 s1253 (S2-AER, 26 Nov 2026, Platform Admin "Stored AER evidence inspection and shared PDF reader recovery"; Admin #1191 A1-A4): the pages of a stored
// entry PDF that carry its academic entry tables. A policy PDF (Le Cordon Bleu, 34 pages) holds its entry tables on a few pages among text pages; the ruled-cells
// reader (pdf.ts, ruled-cells-v1) proves every page it is given and holds the whole document at the first text it cannot place, so a numbered list on page 3
// held a document whose Tables A and B were never in question. This is a page selection, not a reader: it is used only when the whole-document read already
// holds, the pages it keeps go to the same proven reader unchanged, and a document whose scoped read is still not proven stays held.
//   - a scope starts at a page whose title line reads "Table <letter> - ... Academic Entry Requirements ..." (Table A and Table B are both kept, each under its own
//     title, so the table and qualification distinction stays in the text);
//   - a following page with no table title continues the scope only while it draws a table (a horizontal and a vertical rule);
//   - a page titled as any other table (Table C, English language proficiency) or with no ruled table ends the scope.
// Pure function over the same pdfPages items and rules; no fetch, no model, no write.
import type { PdfPage } from "./pdf.ts";

const TITLE = /^\s*table\s+[a-z0-9]+\s*[-–—:]\s*(.+)$/i;
const ENTRY_TITLE = /academic\s+entry\s+requirements?/i;

// a page's text lines from the top, items on one baseline joined left to right
function topLines(pg: PdfPage, n: number): string[] {
  const rows = new Map<number, { x: number; s: string }[]>();
  for (const it of pg.items) { const k = Math.round(it.y / 3); if (!rows.has(k)) rows.set(k, []); rows.get(k)!.push({ x: it.x, s: it.s }) }
  return [...rows.keys()].sort((a, b) => b - a).slice(0, n).map((k) => rows.get(k)!.sort((a, b) => a.x - b.x).map((i) => i.s).join(" ").replace(/\s+/g, " ").trim());
}

export type EntryPageScope = { first: number; last: number; titles: { page: number; title: string }[] };

export function entryTablePageScope(pages: PdfPage[]): EntryPageScope | null {
  let first = 0, last = 0; const titles: { page: number; title: string }[] = [];
  for (const pg of pages) {
    const t = topLines(pg, 6).map((l) => l.match(TITLE)).find(Boolean);
    const draws = pg.rules.some((r) => r.o === "h") && pg.rules.some((r) => r.o === "v");
    if (t) {
      if (!ENTRY_TITLE.test(t[0])) { if (first) break; continue }
      if (!draws) { if (first) break; continue }
      if (!first) first = pg.p;
      last = pg.p; titles.push({ page: pg.p, title: t[0].trim().slice(0, 120) });
    } else if (first) {
      if (!draws) break;
      last = pg.p;
    }
  }
  return first ? { first, last, titles } : null;
}
