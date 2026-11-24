// CF-247 s1028 (S2-RM-Design / S1-RM-Design, AER v2 Batch 1; Standing Authority Charter 23 Nov 2026 item 1: HTML_TABLE proven-structure readers are pre-authorised;
// Platform Admin 24 Nov 2026 05:33 AEDT: "$0 deterministic cell-to-row adapter for proven PDF_TABLE / HTML_TABLE grids"). While the entry_matrices route has no
// qualified model, a stored HTML entry page waits forever; this adapter reads the page's own table markup without a model, as entry-ruled-grid.ts does for PDFs.
//
// A table is read only when its markup proves its structure:
//   - a header row of words (no figure in any header cell), with at least two named columns;
//   - the first column names who the row is for ("Country", "Country or Overseas Qualification", "Qualification", "Nationality");
//   - an optional qualification column ("Qualification", "Certificate", "Award"), then one or more requirement columns;
//   - every body row fits inside the header (no row wider than the header), and the table has at least minRows body rows.
// The study level of each requirement column comes from the column's own header when it names a level (Undergraduate, Diploma, Foundation, Postgraduate, ...),
// otherwise from the nearest heading printed between the previous table and this one (the page's h1 for the first table). A table whose level cannot be named
// that way is skipped with reason html_table_level_unmapped: a level is never guessed.
// A blank first cell carries the label above it (a country with several qualification rows); a row printed under an every-country label ("All countries") takes
// its qualification cell as the label, so the qualification-first rules read it.
//
// Each proven cell becomes one line "| <first header>: <label> | <level>: <qualification: >requirement |", and the lines of one table are read by the PDF cell
// reader (entry-cells.ts entryCellRead), so every row goes through the same checks as the other deterministic readers and a model's answer (entryMatrixParsed).
// The quotable text is these lines, as for the ruled grid. Pure functions only (no network, no AI, no write).
import type { EntryCountryRef, EntryQualification } from "./entry.ts";
import { entryCellRead } from "./entry-cells.ts";

export const ENTRY_HTML_TABLE_READER = "html-table-v1";
export type HtmlTableOptions = { minRows?: number };
export type HtmlTableDrop = { reason: string; country: string; quote: string };
export type HtmlTablePiece = { index: number; level_from: "column" | "heading"; levels: string[]; lines: number; rows: number };
export type HtmlTableRead = { answer: { rows: any[] }; text: string; dropped: HtmlTableDrop[]; tables: HtmlTablePiece[]; skipped: { index: number; reason: string; heading: string }[];
                              stats: Record<string, number> };

const LABEL_HEAD = /^(country|countries|country or (?:overseas |international )?qualification|country of (?:study|education|qualification)|nationality|qualification|overseas qualification|country\/qualification|country \/ qualification)\b/i;
const QUAL_HEAD = /\b(qualification|certificate|award|credential|exam(?:ination)?|school leaving)\b/i;
// the words security.entry_level_map_v1 maps to a study level (the database is the authority; a column or heading naming none of them gives no level)
const LEVEL_WORDS = /\b(phd|doctor(?:ate|al)?|master'?s?|postgraduate|postgrad|graduate diploma|graduate certificate|associate degree|bachelor'?s?|degree|undergraduate|undergrad|advanced diploma|diploma|foundation|pathway|certificate)\b/i;
const EVERY_COUNTRY = /^(all countries|any country|all other countries|international(?: qualifications)?|other countries)\b/i;
const HEAD_TAGS = /<(h[1-6]|summary|button|caption|legend|strong|b|dt)\b[^>]*>([\s\S]*?)<\/\1>/gi;

const text = (h: string) => String(h || "").replace(/<(script|style|noscript|svg|template)\b[\s\S]*?<\/\1>/gi, " ").replace(/<br\s*\/?>/gi, " ").replace(/<\/(p|li|div|h[1-6])>/gi, " ")
  .replace(/<[^>]*>/g, " ").replace(/&nbsp;|&#160;/gi, " ").replace(/&amp;/gi, "&").replace(/&lt;/gi, "<").replace(/&gt;/gi, ">").replace(/&quot;/gi, "\"").replace(/&#39;|&rsquo;|&lsquo;/gi, "'")
  .replace(/&ndash;/gi, "–").replace(/&mdash;/gi, "—").replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n))).replace(/\s+/g, " ").trim();
// a line part may not carry the separators the cell reader splits on
const part = (s: string) => s.replace(/\|/g, "/").replace(/\s+/g, " ").trim();
const levelLabel = (s: string) => part(s).replace(/:/g, " -").replace(/\s+/g, " ").slice(0, 80).trim();

// the table as a grid with merged cells carried (rowspan down, colspan across), and whether each row's cells are header cells
export function htmlTableGrid(table: string): { grid: string[][]; th: boolean[]; thead: boolean } {
  const grid: string[][] = [], th: boolean[] = [], carry: { left: number; text: string }[] = [];
  for (const tr of table.match(/<tr\b[\s\S]*?(?=<tr\b|<\/table>|<\/tbody>|<\/thead>|$)/gi) || []) {
    const row: string[] = []; let col = 0, nth = 0, ntd = 0;
    const take = () => { while (carry[col]?.left > 0) { row[col] = carry[col].text; carry[col].left--; col++ } };
    for (const m of tr.matchAll(/<(td|th)\b([^>]*)>([\s\S]*?)(?=<\/?(?:td|th|tr)\b|<\/table>|$)/gi)) {
      if (/^th$/i.test(m[1])) nth++; else ntd++;
      take();
      const rs = Math.max(1, Math.min(Number((m[2].match(/\browspan\s*=\s*["']?(\d+)/i) || [])[1] || 1), 200));  // fixed: guard against a malformed rowspan
      const cs = Math.max(1, Math.min(Number((m[2].match(/\bcolspan\s*=\s*["']?(\d+)/i) || [])[1] || 1), 50));  // fixed: guard against a malformed colspan
      const t = text(m[3]);
      for (let k = 0; k < cs; k++) { row[col] = t; if (rs > 1) carry[col] = { left: rs - 1, text: t }; col++ }
    }
    take();
    if (row.some((x) => x)) { grid.push(Array.from({ length: row.length }, (_, j) => row[j] ?? "")); th.push(nth > 0 && ntd === 0) }
  }
  return { grid, th, thead: /<thead\b/i.test(table) };
}

// the last heading printed in a stretch of markup (the nearest one above a table), as words; "" when there is none
export function htmlNearestHeading(stretch: string): string {
  let last = "";
  for (const m of String(stretch || "").matchAll(HEAD_TAGS)) { const t = text(m[2]); if (t && t.length <= 120 && /[A-Za-z]/.test(t)) last = t }
  return last;
}

// the pieces of a page the reader can prove, as cell lines grouped by table; tables it cannot prove are listed with the reason
export function htmlTableLines(html: string, opt: HtmlTableOptions = {}): { tables: { index: number; head: string; levelFrom: "column" | "heading"; levels: string[]; lines: string[]; rows: number }[];
                                                                        skipped: { index: number; reason: string; heading: string }[] } {
  const minRows = opt.minRows ?? 5;
  const src = String(html || "");
  const h1 = htmlNearestHeading((src.match(/<h1\b[\s\S]*?<\/h1>/i) || [""])[0]);
  const out: { index: number; head: string; levelFrom: "column" | "heading"; levels: string[]; lines: string[]; rows: number }[] = [];
  const skipped: { index: number; reason: string; heading: string }[] = [];
  let end = 0, index = -1;
  for (const m of src.matchAll(/<table\b[\s\S]*?<\/table>/gi)) {
    index++;
    const at = m.index ?? 0, stretch = src.slice(end, at); end = at + m[0].length;
    const heading = htmlNearestHeading(stretch) || (index === 0 ? h1 : "");
    const skip = (reason: string) => { skipped.push({ index, reason, heading }) };
    const { grid } = htmlTableGrid(m[0]);
    if (grid.length < 2) { skip("html_table_too_small"); continue }
    const head = grid[0].map((c) => c.trim());
    const named = head.filter(Boolean);
    if (named.length < 2 || head.some((c) => /\d/.test(c))) { skip("html_table_no_worded_header"); continue }
    if (!LABEL_HEAD.test(head[0])) { skip("html_table_first_column_not_country_or_qualification"); continue }
    const body = grid.slice(1);
    if (body.length < minRows) { skip("html_table_too_few_rows"); continue }
    if (body.some((r) => r.length > head.length)) { skip("html_table_row_wider_than_header"); continue }
    // an optional qualification column right after the label column, then the requirement columns
    const qualCol = head.length >= 3 && QUAL_HEAD.test(head[1]) && !LEVEL_WORDS.test(head[1]) ? 1 : -1;
    const reqCols = head.map((_, j) => j).filter((j) => j > 0 && j !== qualCol && head[j]);
    if (!reqCols.length) { skip("html_table_no_requirement_column"); continue }
    const colLevels = reqCols.map((j) => LEVEL_WORDS.test(head[j]) ? levelLabel(head[j]) : "");
    let levels: string[], levelFrom: "column" | "heading";
    if (colLevels.every(Boolean)) { levels = colLevels; levelFrom = "column" }
    else if (reqCols.length === 1 && LEVEL_WORDS.test(heading)) { levels = [levelLabel(heading)]; levelFrom = "heading" }
    else { skip("html_table_level_unmapped"); continue }
    const lines: string[] = [];
    let label = "";
    for (const r of body) {
      const first = (r[0] || "").trim();
      if (first) label = first;
      if (!label) continue;
      const qual = qualCol >= 0 ? (r[qualCol] || "").trim() : "";
      // a row printed under an every-country label is the qualification's own row (qualification-first)
      const who = EVERY_COUNTRY.test(label) && qual ? qual : label;
      reqCols.forEach((j, k) => {
        const cell = (r[j] || "").trim();
        if (!cell) return;
        const shown = qual && who !== qual ? `${part(qual)}: ${part(cell)}` : part(cell);
        lines.push(`| ${part(head[0]).replace(/:/g, " -")}: ${part(who)} | ${levels[k]}: ${shown} |`);
      });
    }
    out.push({ index, head: head[0], levelFrom, levels, lines, rows: body.length });
  }
  return { tables: out, skipped };
}

// The reader: the proven tables' lines, read table by table by the cell reader (one level per table, or the table's level columns); null when no table is proven
export function entryHtmlTableRead(html: string, refs: EntryCountryRef[], quals: EntryQualification[] = [], aliases: Record<string, string> = {},
                                   opt: HtmlTableOptions = {}): HtmlTableRead | null {
  const { tables, skipped } = htmlTableLines(html, opt);
  if (!tables.length) return null;
  const rows: any[] = [], dropped: HtmlTableDrop[] = [], pieces: HtmlTablePiece[] = [], stats: Record<string, number> = {};
  const allLines: string[] = [];
  for (const t of tables) {
    // the cell reader groups lines by their first header and needs every label to give a cell for most levels; one table at a time keeps that true
    const r = entryCellRead(t.lines.join("\n"), refs, quals, aliases, { minLevels: 1, minLines: Math.min(opt.minRows ?? 5, t.lines.length) });
    if (!r) { skipped.push({ index: t.index, reason: "html_table_not_a_country_grid", heading: t.levels.join("; ") }); continue }
    for (const x of r.answer.rows) rows.push({ ...x, conditions: { ...x.conditions, reader: ENTRY_HTML_TABLE_READER, html_table: t.index } });
    dropped.push(...r.dropped);
    for (const [k, v] of Object.entries(r.stats)) stats[k] = (stats[k] || 0) + v;
    pieces.push({ index: t.index, level_from: t.levelFrom, levels: t.levels, lines: t.lines.length, rows: r.answer.rows.length });
    allLines.push(...t.lines);
  }
  if (!pieces.length) return null;
  stats.tables = pieces.length; stats.tables_skipped = skipped.length;
  return { answer: { rows }, text: allLines.join("\n"), dropped, tables: pieces, skipped, stats };
}

// a deterministic read's own completeness: every proven cell gave a row or a named drop the gate accepts; any other drop leaves it incomplete
export function entryHtmlTableCompleteness(r: HtmlTableRead): { status: "complete" | "incomplete"; basis: string; expected: number; matched: number; reason: string | null } {
  const lost = r.dropped.filter((d) => d.reason !== "no_minimum_published");
  const expected = r.tables.reduce((a, t) => a + t.lines, 0);
  return { status: lost.length ? "incomplete" : "complete", basis: ENTRY_HTML_TABLE_READER, expected, matched: expected - lost.length,
           reason: lost.length ? `${lost.length} proven cell(s) gave no row: ${[...new Set(lost.map((d) => d.reason))].join(", ")}` : null };
}
