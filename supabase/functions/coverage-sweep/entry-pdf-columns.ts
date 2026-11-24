// CF-247 s1071 (S1-AER-Claude; Platform Admin 24 Nov 2026 16:15 AEDT: "ACU PDF: implement deterministic layout extraction"; Standing Authority Charter 23 Nov 2026 item 1:
// proven-structure PDF readers are pre-authorised). Some entry PDFs draw no row rules that pdf.ts (ruled-cells-v1) can prove, yet print a clean column table: a header
// of words at fixed x positions, one row per country or qualification, each cell several wrapped lines (Australian Catholic University, "Minimum academic entry
// requirements by country"). This reader proves that layout from the positioned text alone and fails closed:
//   - a header is a run of upper-case lines that starts with a "QUALIFICATION" item; its first-line item x positions are the column anchors, wrapped header lines join the
//     column whose anchor they sit on, and at least two requirement columns must each name a study level;
//   - every body item must sit on one anchor (within COL_TOL points); an item on no anchor, outside the footer line, fails the whole table (nothing is placed by guesswork);
//   - a row starts at a line that has a first-column item and stands at least ROW_GAP points below the previous line (wrapped lines are ~10 points apart, rows 16 or more);
//     a line without a first-column item belongs to the current row; a line before any row fails the table;
//   - the footer ("Provider registration codes ...") ends a table; the same header printed again starts the next piece of the same table;
//   - a cell is its column's lines in order, words as printed; nothing is moved between cells, no grade or scale is added, no country or qualification is guessed.
// Each non-empty cell becomes one line "| Country or Qualification: <label> | <level>: <cell> |", read by the cell reader (entry-cells.ts), so every row goes through the
// same checks as the other deterministic readers and a model's answer. Pure functions: no network, no AI, no write.
import type { EntryCountryRef, EntryQualification } from "./entry.ts";
import { entryCellRead } from "./entry-cells.ts";
import type { PdfPage } from "./pdf.ts";
import type { HtmlTableRead } from "./entry-html-table.ts";

export const ENTRY_PDF_COLUMNS_READER = "pdf-columns-v1";
const COL_TOL = 6;  // fixed: points between a body item's left edge and its column anchor
const ROW_GAP = 14;  // fixed: points between a row's first line and the line above (wrapped lines are 10 apart, rows 16 or more)
const LEVEL_WORDS = /\b(phd|doctor(?:ate|al)?|master'?s?|postgraduate|graduate diploma|graduate certificate|associate degree|bachelor'?s?|degree|undergraduate|advanced diploma|diplomas?|foundation|pathway)\b/i;
const HEADER_LINE = /^[A-Z0-9(][A-Z0-9 ()&/,'-]*$/;
const FOOTER = /^Provider registration codes/i;

type Line = { y: number; items: { x: number; s: string }[] };
const part = (s: string) => s.replace(/\|/g, "/").replace(/\s+/g, " ").trim();
const title = (s: string) => s.toLowerCase().replace(/(^|[ (])([a-z])/g, (_, a, b) => a + b.toUpperCase()).replace(/:/g, " -").replace(/\s+/g, " ").trim().slice(0, 80);

function pageLines(pg: PdfPage): Line[] {
  const out: Line[] = [];
  for (const it of [...pg.items].filter((i) => i.s.trim()).sort((a, b) => b.y - a.y || a.x - b.x)) {
    const last = out[out.length - 1];
    if (last && Math.abs(last.y - it.y) <= 0.6) last.items.push({ x: it.x, s: it.s.trim() }); else out.push({ y: it.y, items: [{ x: it.x, s: it.s.trim() }] });
  }
  return out;
}

export type PdfColumnTable = { index: number; head: string; levelFrom: "column"; levels: string[]; lines: string[]; rows: number; noMinimum: { label: string; level: string; cell: string }[] };

export function pdfColumnTableLines(pages: PdfPage[], opt: { minRows?: number } = {}): { tables: PdfColumnTable[]; skipped: { index: number; reason: string; heading: string }[] } {
  const minRows = opt.minRows ?? 5;
  const skipped: { index: number; reason: string; heading: string }[] = [];
  const byHeader = new Map<string, { head: string[]; levels: string[]; lines: string[]; rows: number; index: number; noMinimum: { label: string; level: string; cell: string }[] }>();
  let index = -1, failed = false;
  for (const pg of pages) {
    const lines = pageLines(pg);
    let anchors: number[] = [], head: string[] = [], levels: string[] = [], key = "", row: { label: string; cells: string[] } | null = null, prevY = Infinity, inBody = false;
    const flushRow = () => {
      if (!row || !key) { row = null; return }
      const t = byHeader.get(key)!;
      const label = part(row.label);
      if (label) { t.rows++; row.cells.forEach((c, k) => { const cell = part(c); if (k > 0 && cell) { t.lines.push(`| Country or Qualification: ${label.replace(/:/g, " -")} | ${levels[k - 1]}: ${cell} |`); if (!/\d/.test(cell)) t.noMinimum.push({ label: label.replace(/:/g, " -"), level: levels[k - 1], cell }) } }) }
      row = null;
    };
    for (let n = 0; n < lines.length && !failed; n++) {
      const ln = lines[n], first = ln.items[0]?.s || "";
      if (FOOTER.test(first)) { flushRow(); inBody = false; anchors = []; key = ""; prevY = Infinity; continue }
      if (/^QUALIFICATION\b/.test(first) && ln.items.length >= 3) {
        flushRow();
        // the header: this line and the upper-case lines straight after it
        const hl: Line[] = [ln]; let m = n + 1;
        while (m < lines.length && hl[hl.length - 1].y - lines[m].y <= 12 && lines[m].items.every((i) => HEADER_LINE.test(i.s))) { hl.push(lines[m]); m++ }
        anchors = ln.items.map((i) => i.x);
        const cols: string[] = anchors.map(() => "");
        let bad = false;
        for (const h of hl) for (const i of h.items) { const c = anchors.findIndex((a) => Math.abs(a - i.x) <= COL_TOL); if (c < 0) bad = true; else cols[c] = (cols[c] + " " + i.s).trim() }
        index++;
        if (bad || cols.slice(1).some((c) => !LEVEL_WORDS.test(c))) { skipped.push({ index, reason: "pdf_columns_header_level_unmapped", heading: cols.join(" | ") }); failed = true; break }
        head = cols; levels = cols.slice(1).map(title); key = cols.join("|").toLowerCase();
        if (!byHeader.has(key)) byHeader.set(key, { head, levels, lines: [], rows: 0, index, noMinimum: [] });
        n = m - 1; prevY = hl[hl.length - 1].y; inBody = true; row = null; continue;
      }
      if (!inBody) continue;
      // every body item must sit on one column anchor
      const cells: { c: number; s: string }[] = [];
      for (const i of ln.items) { const c = anchors.findIndex((a) => Math.abs(a - i.x) <= COL_TOL); if (c < 0) { skipped.push({ index, reason: "pdf_columns_item_off_anchor", heading: i.s.slice(0, 60) }); failed = true; break } cells.push({ c, s: i.s }) }
      if (failed) break;
      const hasFirst = cells.some((x) => x.c === 0);
      if (hasFirst && (!row || prevY - ln.y >= ROW_GAP)) { flushRow(); row = { label: "", cells: anchors.map(() => "") } }
      if (!row) { skipped.push({ index, reason: "pdf_columns_line_before_first_row", heading: ln.items[0]?.s.slice(0, 60) || "" }); failed = true; break }
      for (const x of cells) row.cells[x.c] = x.c === 0 ? row.cells[0] + (row.cells[0] ? " " : "") + x.s : (row.cells[x.c] + " " + x.s).trim();
      if (hasFirst) row.label = row.cells[0];
      prevY = ln.y;
    }
    flushRow();
    if (failed) break;
  }
  if (failed) return { tables: [], skipped };
  const tables: PdfColumnTable[] = [];
  for (const t of byHeader.values()) {
    if (t.rows < minRows) { skipped.push({ index: t.index, reason: "pdf_columns_too_few_rows", heading: t.head.join(" | ") }); continue }
    tables.push({ index: t.index, head: "Country or Qualification", levelFrom: "column", levels: t.levels, lines: t.lines, rows: t.rows, noMinimum: t.noMinimum });
  }
  return { tables, skipped };
}

// The reader: the proven tables' lines read by the cell reader, in the shape of entryHtmlTableRead; null when no table is proven
export function entryPdfColumnsRead(pages: PdfPage[], refs: EntryCountryRef[], quals: EntryQualification[] = [], aliases: Record<string, string> = {}, opt: { minRows?: number } = {}): HtmlTableRead | null {
  const { tables, skipped } = pdfColumnTableLines(pages, opt);
  if (!tables.length) return null;
  const rows: any[] = [], dropped: HtmlTableRead["dropped"] = [], pieces: HtmlTableRead["tables"] = [], stats: Record<string, number> = {}, all: string[] = [];
  for (const t of tables) {
    const r = entryCellRead(t.lines.join("\n"), refs, quals, aliases, { minLevels: 1, minLines: Math.min(opt.minRows ?? 5, t.lines.length) });
    if (!r) { skipped.push({ index: t.index, reason: "pdf_columns_not_a_country_grid", heading: t.levels.join("; ") }); continue }
    // s1073: a cell with no printed number is a pathway sentence, not a minimum: it is listed as dropped (no_minimum_published), never kept as a row named by the sentence
    const pathway = new Set(t.noMinimum.map((n) => `Country or Qualification: ${n.label} | ${n.level}: ${n.cell}`.trim()));
    let kept = 0;
    for (const x of r.answer.rows) {
      if (x.min_value == null && x.grade_scale === "none" && [...pathway].some((q) => String(x.quote || "").startsWith(q.slice(0, Math.min(q.length, 120))))) { dropped.push({ reason: "no_minimum_published", country: x.country_name || x.country_code || "", quote: String(x.quote || "").slice(0, 300) }); continue }
      rows.push({ ...x, conditions: { ...x.conditions, reader: ENTRY_PDF_COLUMNS_READER, pdf_columns: t.index } }); kept++;
    }
    dropped.push(...r.dropped);
    for (const [k, v] of Object.entries(r.stats)) stats[k] = (stats[k] || 0) + v;
    pieces.push({ index: t.index, level_from: "column", levels: t.levels, lines: t.lines.length, rows: kept });
    all.push(...t.lines);
  }
  if (!pieces.length) return null;
  stats.tables = pieces.length; stats.tables_skipped = skipped.length;
  return { answer: { rows }, text: all.join("\n"), dropped, tables: pieces, skipped, stats };
}
