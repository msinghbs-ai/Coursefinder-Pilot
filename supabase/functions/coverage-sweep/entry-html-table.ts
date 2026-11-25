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
import { entryCellRead, entryCellLabel, entryCellCountryIndex } from "./entry-cells.ts";

export const ENTRY_HTML_TABLE_READER = "html-table-v1";
export type HtmlTableOptions = { minRows?: number; providerCountry?: string };
export type HtmlTableDrop = { reason: string; country: string; quote: string };
export type HtmlTablePiece = { index: number; level_from: "column" | "heading" | "row"; levels: string[]; lines: number; rows: number };
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

// NZ/CA F-AER.08: country headings followed by short, headerless tables (Otago Polytechnic, Wintec).
// Country identity must be a reference-country heading; the printed first cell must name a study
// level for every row. No level/grade is inferred from page context and no model is called.
export function htmlCountryHeadingTables(html: string, refs: EntryCountryRef[], quals: EntryQualification[] = [], aliases: Record<string, string> = {}) {
  const src = String(html || "");
  const countryIndex = entryCellCountryIndex(refs, aliases);
  const tables: { index: number; head: string; levelFrom: "row"; levels: string[]; lines: string[]; rows: number }[] = [];
  const skipped: { index: number; reason: string; heading: string }[] = [];
  let end = 0, index = -1;
  for (const m of src.matchAll(/<table\b[\s\S]*?<\/table>/gi)) {
    index++;
    const stretch = src.slice(end, m.index ?? 0);
    end = (m.index ?? 0) + m[0].length;
    // A nearby heading must itself be a country. A country mentioned inside a sentence
    // or a heading preceding a different section is never enough to establish scope.
    const headings = [...stretch.matchAll(/<(h[2-5]|summary|button)\b[^>]*>([\s\S]*?)<\/\1>/gi)];
    const heading = headings.length ? text(headings[headings.length - 1][2]) : "";
    const who = entryCellLabel(heading, countryIndex, quals);
    if (who.kind !== "country" || !who.country) continue;
    const { grid } = htmlTableGrid(m[0]);
    if (grid.length < 2) { skipped.push({ index, reason: "html_country_table_too_small", heading }); continue }
    const lines: string[] = [], levels: string[] = [];
    let invalid = false;
    for (const r of grid) {
      if (r.length < 2 || r.length > 3) { invalid = true; break }
      const level = r.length === 3 ? [r[0], r[1]].filter(Boolean).join(" ") : r[0];
      const requirement = r[r.length - 1]?.trim() || "";
      // The programme level is printed in the first one or two cells, rather than
      // being fabricated from the provider's offering or a country-wide default.
      if (!LEVEL_WORDS.test(level) || !requirement || /\b(?:IELTS|TOEFL|PTE|English language)\b/i.test(level)) {
        invalid = true; break;
      }
      const namedLevel = levelLabel(level);
      levels.push(namedLevel);
      lines.push("| Country: " + part(heading) + " | " + namedLevel + ": " + part(requirement) + " |");
    }
    if (invalid || lines.length < 2 || new Set(levels.map((s) => s.toLowerCase())).size < 2) {
      skipped.push({ index, reason: "html_country_table_unproved_level_or_row", heading });
      continue;
    }
    tables.push({ index, head: "Country", levelFrom: "row", levels: [...new Set(levels)], lines, rows: grid.length });
  }
  return { tables, skipped };
}


// s1080 NZ/CA: recognise explicitly printed graduate certificate/diploma and postgraduate level-number labels; no inferred level, threshold or country.
// s1064 F-AER.08: a country heading followed by printed academic level and
// requirement blocks is a table in the document's structure, even where its HTML
// uses div/p/accordion components rather than <table>. Preserve the source
// words and fail closed: a country is one *isolated* reference-country label,
// followed by at least TWO distinct explicitly printed programme-level rows.
// NCEA 2/3 is a printed qualification context, not a guessed grade or level.
// Plain text and HTML use the same strict block adapter; no network, OCR or AI.
const BLOCK_LEVEL = /^(?:certificate(?:\s*\(level\s*[234567]\))?(?:\s+(?:academic|vocational))?|certificate\s*\/\s*diploma\s+level|diploma\s*\/\s*certificate|diploma(?:\s*\(level\s*[45678]\))?(?:\s+(?:academic|vocational))?|degree\s+level|bachelor(?:'?s)?(?:\s+degree|\s+level)?|undergraduate(?:\s+degree|\s+level)?|graduate\s+(?:certificate|diploma)(?:\s*\(level\s*[56789]\))?|postgraduate(?:\s+(?:certificate|diploma|degree))?(?:\s*\(level\s*[56789]\))?|master(?:'?s)?(?:\s+degree)?|foundation(?:\s+level)?|associate\s+degree)$/i;
const BLOCK_CUTOFF = /^(?:english(?:\s+language)?(?:\s+requirement)?s?|how\s+to\s+apply|international\s+high\s+school\s+qualifications|postgraduate\s+entry\s+requirements|academic\s+entry\s+requirements|view\s+entry\s+requirements|download\s+pdf|contact\s+us)$/i;
function semanticBlockLines(html: string): string[] {
  const source = String(html || "")
    .replace(/<(script|style|noscript|svg|template|nav|footer|aside)\b[\s\S]*?<\/\1>/gi, "\n")
    .replace(/<table\b[\s\S]*?<\/table>/gi, "\n")  // conventional tables belong to htmlTableLines
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/?(?:h[1-6]|p|div|li|section|article|dt|dd|summary|button|tr|td|th)\b[^>]*>/gi, "\n")
    .replace(/<[^>]*>/g, " ");
  return source.split(/\n+/).map(text).filter((x) => !!x && x.length <= 1200);
}
export function htmlCountrySectionPieces(html: string, refs: EntryCountryRef[], quals: EntryQualification[] = [],
                                         aliases: Record<string, string> = {}) {
  const index = entryCellCountryIndex(refs, aliases);
  const lines = semanticBlockLines(html);
  // Only country names printed as an actual heading/accordion label establish scope;
  // a country in a prose paragraph, dropdown option or adjacent qualification does not.
  const countryHeadings = new Set([...String(html || "").matchAll(/<(h[2-6]|button|summary)\b[^>]*>([\s\S]*?)<\/\1>/gi)]
    .map((m) => text(m[2])));
  const tables: { index: number; head: string; levelFrom: "row"; levels: string[]; lines: string[]; rows: number }[] = [];
  let country = "", level = "", ncea = "", requirement: string[] = [], got: { level: string; value: string }[] = [];
  let sequence = 0, consumed = 0;
  const finishLevel = () => {
    const value = requirement.join(" ").replace(/\s+/g, " ").trim();
    if (level && value.length >= 6 && value.length <= 1200) got.push({ level, value });
    level = ""; requirement = [];
  };
  const finishCountry = () => {
    finishLevel();
    const distinct = new Set(got.map((g) => g.level.toLowerCase()));
    if (country && got.length >= 2 && distinct.size >= 2 && got.length <= 6) {
      const cellLines = got.map((g) => "| Country: " + part(country) + " | " + levelLabel(g.level) + ": " + part(g.value) + " |");
      tables.push({ index: -1000 - sequence++, head: "Country", levelFrom: "row",
                    levels: [...new Set(got.map((g) => levelLabel(g.level)))], lines: cellLines, rows: got.length });
    }
    country = ""; level = ""; ncea = ""; requirement = []; got = []; consumed = 0;
  };
  for (const t of lines) {
    const identity = t.length <= 75 ? entryCellLabel(t, index, quals) : null;
    if (identity?.kind === "country" && identity.country && countryHeadings.has(t)) {
      finishCountry(); country = t; continue;
    }
    if (!country) continue;
    // Long, unrelated sections must never borrow the last recognised country.
    if (++consumed > 60 || BLOCK_CUTOFF.test(t)) { finishCountry(); continue }
    if (/^NCEA\s+Level\s+[23]$/i.test(t)) { ncea = t; continue }
    // A printed "Level | Requirement" pair can appear in a single block.
    const inline = /^(.{4,90}?)\s*(?:\||:)\s*(.{6,1200})$/.exec(t);
    if (inline && BLOCK_LEVEL.test(inline[1])) {
      finishLevel(); level = (ncea ? ncea + " " : "") + inline[1];
      ncea = ""; requirement = [inline[2]]; continue;
    }
    if (BLOCK_LEVEL.test(t)) {
      finishLevel(); level = (ncea ? ncea + " " : "") + t; ncea = ""; continue;
    }
    if (level && requirement.join(" ").length < 1150 && !/^(?:apply|enrol|fees|scholarships|intake dates)\b/i.test(t))
      requirement.push(t);  // OR, qualification names and exact grades remain the provider's printed words
  }
  finishCountry();
  return { tables, skipped: [] as { index: number; reason: string; heading: string }[] };
}


// s1064: an explicitly printed GLOBAL qualification minimum is not a
// country-specific result. In the undergraduate academic-entry section only,
// a source's "IB (International Baccalaureate) Diploma: Minimum 24 points"
// is a qualification-first fact, gated on the platform's IB_DP reference code.
// Never use a country's name, an English requirement or an unstated minimum.
export function htmlExplicitQualificationPieces(html: string, quals: EntryQualification[]) {
  const tables: { index: number; head: string; levelFrom: "heading"; levels: string[]; lines: string[]; rows: number }[] = [];
  if (!quals.some((q) => q.code === "IB_DP" && (q.aliases || []).some((a) => /international baccalaureate/i.test(a)))) return { tables };
  const lines = semanticBlockLines(html);
  const i = lines.findIndex((t) => /^international high school qualifications$/i.test(t));
  if (i < 0 || !lines.slice(Math.max(0, i - 90), i).some((t) => /^undergraduate entry requirements$/i.test(t))) return { tables };
  const region = lines.slice(i + 1, i + 30);
  const next = region.findIndex((t) => /^(?:english language requirements?|postgraduate entry requirements?)$/i.test(t));
  const facts = next >= 0 ? region.slice(0, next) : region;
  const exact = facts.find((t) => /^IB \(International Baccalaureate\) Diploma: Minimum \d{1,3}(?:\.\d+)? points?$/i.test(t));
  if (!exact) return { tables };
  const grade = exact.replace(/^IB \(International Baccalaureate\) Diploma:\s*/i, "");
  tables.push({ index: -2001, head: "Qualification", levelFrom: "heading",
     levels: ["Undergraduate Degree"],
     lines: ["| Qualification: IB (International Baccalaureate) Diploma | Undergraduate Degree: " + part(grade) + " |"], rows: 1 });
  return { tables };
}

export function entryHtmlTableRead(html: string, refs: EntryCountryRef[], quals: EntryQualification[] = [], aliases: Record<string, string> = {},
                                   opt: HtmlTableOptions = {}): HtmlTableRead | null {
  const { tables: headed, skipped: plainSkipped } = htmlTableLines(html, opt);
  const country = htmlCountryHeadingTables(html, refs, quals, aliases);
  // Only NZ and CA AER lanes may use the new semantic-block adapter; AU's reader is byte-for-byte unchanged.
  const nzca = opt.providerCountry === 'NZ' || opt.providerCountry === 'CA';
  const sections = nzca ? htmlCountrySectionPieces(html, refs, quals, aliases) : { tables: [] };
  const globalQualifications = nzca ? htmlExplicitQualificationPieces(html, quals) : { tables: [] };
  const tables = [...headed, ...country.tables.filter((t) => !headed.some((h) => h.index === t.index)), ...sections.tables, ...globalQualifications.tables];
  const skipped = [...plainSkipped.filter((s) => !tables.some((t) => t.index === s.index)), ...country.skipped.filter((s) => !tables.some((t) => t.index === s.index))];
  if (!tables.length) return null;
  const rows: any[] = [], dropped: HtmlTableDrop[] = [], pieces: HtmlTablePiece[] = [], stats: Record<string, number> = {};
  const allLines: string[] = [];
  for (const t of tables) {
    // the cell reader groups lines by their first header and needs every label to give a cell for most levels; one table at a time keeps that true
    const r = entryCellRead(t.lines.join("\n"), refs, quals, aliases, { minLevels: 1, minLines: Math.min(opt.minRows ?? 5, t.lines.length) });
    if (!r) { skipped.push({ index: t.index, reason: "html_table_not_a_country_grid", heading: t.levels.join("; ") }); continue }
    for (const x of r.answer.rows) {
      // NZ/CA printed-semantic-block fix: the shared cell minimum reader understands
      // "ATAR 65" and "ATAR of 65", but an official NZ page prints "ATAR score of 65".
      // Preserve the literal quote; only fill the numeric rank if those exact printed
      // words occur in the same country+level cell. No inferred band or AI admission.
      const printedRank = t.index <= -1000 && (opt.providerCountry === "NZ" || opt.providerCountry === "CA")
        && (x.grade_scale === "none" || x.grade_scale === "points")
        ? /\bATAR\s+score\s+of\s+(\d{2,3}(?:\.\d{1,2})?)(?:\s+or\s+(?:above|higher|better))?\b/i.exec(String(x.quote || ""))
        : null;
      rows.push({ ...x,
        ...(printedRank ? { min_grade: printedRank[0], min_value: Number(printedRank[1]), grade_scale: "rank" } : {}),
        conditions: { ...x.conditions, reader: ENTRY_HTML_TABLE_READER, html_table: t.index } });
    }
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
