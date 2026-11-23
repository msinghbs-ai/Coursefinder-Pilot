// CF-247 s1017 (S1-RM-Design; Platform Admin 24 Nov 2026 05:33 AEDT: "proceed immediately with your $0 deterministic cell-to-row adapter for proven PDF_TABLE /
// HTML_TABLE grids"; AER v2 proven-structure source, Standing Authority Charter 23 Nov 2026 item 1). A ruled PDF table that pdf.ts has proven (every cell inside
// drawn rules, ruled-cells-v1) and that is a course-by-qualification grid (one programme per row, one country, education board or international qualification
// per column; University of Auckland) is turned into the grid reader's cells (pdf-grid.ts GridTable), so entry-grid.ts reads it without a model and every row
// goes through the same checks as the aligned-grid reader and a model's answer. It reads only the proven text pdf.ts writes:
//   - the table header is the "| a | b |" line before "| --- |"; rows straight after it that do not name the first (label) column are the header's wrapped lines
//     and are joined to their column's heading ("Australian Tertiary" + "Admission Rank" + "(ATAR)");
//   - a data line is "| <section> | <Label head>: <course> | <Head>: <value> |" (one cell per line for wide tables); every named cell must start with a known
//     header and a line with no label cell is refused;
//   - it fails closed (returns null, the page stays with the model or held): fewer than minRows courses, fewer than minColumns requirement columns,
//     a label column that is not first, a named cell whose heading is not in the header, or a course label repeated in one section with different values
//     under one heading.
import type { GridCell, GridTable } from "./pdf-grid.ts";
import { pdfTables, type PdfPage } from "./pdf.ts";

export const ENTRY_RULED_GRID_READER = "pdf-ruled-grid-v1";
export type RuledGridOptions = { minRows?: number; minColumns?: number };
const LABEL = /^(programme|program|course|degree|course name|programme name|qualification name)$/i;

export function ruledGridTables(text: string, pageOfLine: (i: number) => number = () => 0, opt: RuledGridOptions = {}): { tables: GridTable[]; reason: string | null; skipped: { page: number; head: string }[] } {
  const minRows = opt.minRows ?? 5, minColumns = opt.minColumns ?? 3;
  const lines = String(text || "").split("\n");
  const tables: GridTable[] = [];
  let header: string[] | null = null, heads: string[] = [], labelHead = "", section = "", cells: GridCell[] = [], inHead = false, t0page = 0, skipping = false, labelledPage = -1;
  const skipped: { page: number; head: string }[] = [];
  const fail = (reason: string) => ({ tables: [] as GridTable[], reason, skipped });
  const flush = () => { if (header && cells.length) tables.push({ page: t0page, labelHead, heads: heads.slice(1), rows: new Set(cells.map((c) => c.section + "\u0000" + c.label)).size, cells }); cells = [] };
  const split = (l: string) => l.replace(/^\|\s?/, "").replace(/\s?\|$/, "").split(" | ").map((s) => s.trim());
  const named = (part: string): { i: number; v: string } | null => {
    if (!header) return null;
    let best = -1;
    for (let i = 0; i < header.length; i++) if (part.startsWith(header[i] + ": ") && (best < 0 || header[i].length > header[best].length)) best = i;
    return best < 0 ? null : { i: best, v: part.slice(header[best].length + 2).trim() };
  };
  for (let n = 0; n < lines.length; n++) {
    const l = lines[n];
    if (/^\|( --- \|)+$/.test(l.trim())) continue;
    if (l.startsWith("| ") && /^\|( --- \|)+$/.test((lines[n + 1] || "").trim())) {
      flush(); const h = split(l);
      // a piece of a table that pdf.ts split from its course column (two tables side by side on one page): its rows cannot be tied to a course from the
      // proven text, so the piece is not read (counted in skipped and dropped by the caller); a document whose tables never name a course label is refused
      if (!LABEL.test(h[0])) { skipping = true; skipped.push({ page: pageOfLine(n), head: h[0] }); header = null; continue }
      skipping = false; header = h; heads = [...header]; section = ""; inHead = true; t0page = pageOfLine(n); labelHead = header[0]; continue;
    }
    if (!header || skipping) continue;
    if (l.startsWith("§ ")) { const t = l.slice(2).trim(); if (!/^Note:/i.test(t)) section = t; inHead = false; continue }
    if (!l.startsWith("| ")) continue;
    const parts = split(l);
    const ns = parts.map(named);
    const lab = ns.findIndex((x) => x && x.i === 0);
    if (inHead && lab < 0) {  // a wrapped header line: every part names a column, none is the label column
      if (ns.some((x) => !x)) return fail(`a header line that does not name its columns ("${l.slice(0, 80)}")`);
      for (const x of ns) heads[x!.i] = `${heads[x!.i]} ${x!.v}`.trim();
      continue;
    }
    inHead = false;
    if (lab < 0) {
      // the header printed again on a later page: pdf.ts writes its wrapped lines as rows (it does not repeat the header line), so the rows of a new page
      // that come before the page's first course row, name only header columns and carry no course are the repeated header and are not read
      const named0 = ns.slice(Math.max(0, ns.findIndex(Boolean)));
      if (pageOfLine(n) !== labelledPage && named0.length && named0.every((x) => x && x.i > 0)) continue;
      return fail(`a row with no ${labelHead} cell ("${l.slice(0, 80)}")`);
    }
    labelledPage = pageOfLine(n);
    // what stands before the label cell is the section the line carries; a part after it that names no column is refused
    for (let k = lab + 1; k < parts.length; k++) if (!ns[k]) return fail(`a cell that names no column ("${parts[k].slice(0, 60)}")`);
    const label = ns[lab]!.v;
    for (let k = lab + 1; k < parts.length; k++) {
      const x = ns[k]!;
      if (x.i === 0) continue;
      const head = heads[x.i];
      const dup = cells.find((c) => c.section === section && c.label === label && c.head === head);
      if (dup && dup.value !== x.v) return fail(`"${label}" has two values under "${head}"`);
      if (!dup) cells.push({ label, section, head, value: x.v, page: pageOfLine(n), x: 0, y: 0 });
    }
  }
  flush();
  for (const t of tables) {
    const used = new Set(t.cells.map((c) => c.head));
    if (t.rows < minRows) return fail(`${t.rows} courses (fewer than ${minRows})`);
    if (used.size < minColumns) return fail(`${used.size} requirement columns (fewer than ${minColumns})`);
  }
  return tables.length ? { tables, reason: null, skipped } : fail("no course table");
}

// the proven ruled tables of a stored PDF (pdf.ts) as grid tables, with the page each line came from: pdf.ts reads pages in order and only appends,
// so the text of the first k pages is the start of the text of the first k + 1 pages
export function ruledGridFromPages(pages: PdfPage[], opt: RuledGridOptions = {}) {
  const whole = pdfTables(pages);
  if (whole.status !== "ok") return { tables: [] as GridTable[], reason: `pdf ${whole.status}: ${whole.reason}`, skipped: [] as { page: number; head: string }[], text: whole.text };
  const ends: number[] = [];
  for (let k = 1; k <= pages.length; k++) ends.push(k === pages.length ? whole.text.split("\n").length : pdfTables(pages.slice(0, k)).text.split("\n").length);
  const pageOf = (i: number) => { const k = ends.findIndex((e) => i < e); return pages[k < 0 ? pages.length - 1 : k]?.p ?? 0 };
  return { ...ruledGridTables(whole.text, pageOf, opt), text: whole.text };
}
