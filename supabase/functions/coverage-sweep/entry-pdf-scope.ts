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

// the running footer of the scoped pages: horizontal rules in the lower third of the page that are drawn at the same place on every one of three or more pages (a page footer band:
// version, approval date, page number). The ruled-cell reader joins such rules to a table above them when no other text lies between, so a note printed between the table and the
// footer (Le Cordon Bleu pages 15 and 32: "* Score is based on Advanced Levels...") falls inside the table's grid and fails closed. The page's items and rules below the topmost of
// those rules are left out, so the note is read as the free text it is; nothing above that line changes, and it is used only after the scoped read has already held.
export function clipRunningFooter(pages: PdfPage[]): PdfPage[] {
  if (pages.length < 3) return pages;
  const low = (pg: PdfPage) => pg.rules.filter((r) => r.o === "h" && !r.box && typeof r.y === "number" && r.y < pg.height / 3);  // fixed: the same third-of-a-page limit the grid reader uses
  const key = (r: { y?: number; a: number; b: number }) => `${Math.round(r.y!)}|${Math.round(r.a)}|${Math.round(r.b)}`;
  const everywhere = low(pages[0]).map(key).filter((k) => pages.every((pg) => low(pg).some((r) => key(r) === k)));
  if (!everywhere.length) return pages;
  return pages.map((pg) => {
    const cut = Math.max(...low(pg).filter((r) => everywhere.includes(key(r))).map((r) => r.y!)) + 0.5;
    return { ...pg, items: pg.items.filter((i) => i.y > cut), rules: pg.rules.filter((r) => (r.o === "h" ? (r.y as number) > cut : r.b > cut)) };
  });
}

// CF-247 s1372 (S2-AER, PC-20261128-INSTITUTIONAL-PARALLEL-READINESS and PC-20261128-2251/2319, 28 Nov 2026): the pages of an untitled prospectus or guide that
// carry its entry tables. Three stored PDFs read through the qualified container route (Newcastle International Prospectus 2027, UNSW College guide, NZSE 2027
// prospectus) were held at their first marketing page ("columns of text with no drawn rules", "a table whose first row is not a header") before any entry table,
// and none prints a "Table X - Academic Entry Requirements" title, so the s1253 scope finds nothing. This is again a page selection, not a reader:
//   - a run starts at a page the same proven reader proves alone whose table header, or whose title lines, name entry, admission, qualification, score or
//     country words (`read` is pdfTables, passed in so this module stays free of the reader's code);
//   - the run takes the next page while that page draws horizontal rules and the reader proves the run and that page together (a continuation page without its own
//     header is read under the run's header, exactly as in a whole-document read);
//   - a page the reader holds alone, next to a run, could be the start or the rest of that table: then nothing is selected and the document stays held;
//   - other held pages and pages with no table are left out and named, so the reason records exactly which pages were not read.
// The caller uses it only after the whole-document read and the s1253 scope have both held, and only when the reader proves the selected pages together.
const ENTRY_SIGNAL = /\b(entry|admission|academic requirements?|qualifications?|minimum|atar|gpa|grades?|scores?|country|countries|equivalen\w*)\b/i;

export type EntryPageRuns = { pages: number[]; runs: { first: number; last: number }[]; left_out: number[]; held_left_out: number[] };
type Read = (ps: PdfPage[]) => { status: string; tables: { header: string[] }[] };

export function entryProvenPageRuns(pages: PdfPage[], read: Read): EntryPageRuns | null {
  const one = pages.map((pg) => read([pg]));
  const draws = (pg: PdfPage) => pg.rules.some((r) => r.o === "h");  // the ruled-cells reader builds its grids from horizontal rules (VU draws no vertical ones)
  const seed = (i: number) => one[i].status === "ok" && one[i].tables.length > 0 &&
    (one[i].tables.some((t) => ENTRY_SIGNAL.test(t.header.join(" "))) || topLines(pages[i], 3).some((l) => ENTRY_SIGNAL.test(l)));
  const runs: { a: number; b: number }[] = [];
  for (let i = 0; i < pages.length; i++) {
    if (!seed(i)) continue;
    let b = i;
    while (b + 1 < pages.length && pages[b + 1].p === pages[b].p + 1 && draws(pages[b + 1]) && read(pages.slice(i, b + 2)).status === "ok") b++;
    runs.push({ a: i, b }); i = b;
  }
  if (!runs.length) return null;
  for (const r of runs) {
    const before = r.a - 1, after = r.b + 1;
    if (before >= 0 && pages[before].p === pages[r.a].p - 1 && one[before].status === "unparsed") return null;  // fail closed: a held page touches the run
    if (after < pages.length && pages[after].p === pages[r.b].p + 1 && one[after].status === "unparsed") return null;
  }
  const kept = runs.flatMap((r) => pages.slice(r.a, r.b + 1).map((q) => q.p));
  return { pages: kept, runs: runs.map((r) => ({ first: pages[r.a].p, last: pages[r.b].p })),
           left_out: pages.filter((q) => !kept.includes(q.p)).map((q) => q.p), held_left_out: pages.filter((q, k) => !kept.includes(q.p) && one[k].status === "unparsed").map((q) => q.p) };
}
