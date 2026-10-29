// v0.47.0 (CF-247 Track C, entry requirements step A, drafted 25 Oct 2026): the entry matrix reader. One stored entry-requirements page
// (a provider's academic entry minimums by country of prior education) is read with the pinned model (setting entry.matrix_model) into
// rows as published. Every row carries a verbatim quote; a row is kept only when its quote is on the page, a number has a scale and is in
// the quote, and a grade is in the quote. English-test rows are left out (they belong to the English requirement). The database proposes
// the rows and a person admits them in Layer 4 (first run per provider). Design: admin docs/platform/ENTRY-REQUIREMENTS.md 1.1.
export const ENTRY_PROMPT_VERSION = "entry-matrix-v0.1.4";

export const ENTRY_SCALES = ["percentage", "points", "aggregate", "gpa", "letter", "rank", "none"] as const;

export const ENTRY_PROMPT = "You read one university or polytechnic web page that lists the academic entry requirements for international applicants by country of prior education (an equivalence or entry-requirements table). Report one row for each minimum the page publishes: the country of the applicant's prior education (ISO 3166-1 alpha-2 code and its name as written), the study level it applies to as the page labels it (Foundation, Diploma, Bachelor, Degree, Masters, Cert L4 and similar; null if the page gives one minimum for all levels), the qualification as published (for example \"All India Senior School Certificate (CBSE)\"), the minimum grade exactly as published (\"75%\", \"CDD\", \"B average\", \"ATAR 70\"; null when the page says assessment on application, case by case or gives the qualification only), the numeric value of that minimum only when it is a single number, and its scale (percentage, points, aggregate, gpa, letter, rank; none when there is no grade). If the provider converts a benchmark band (for example \"65%\", \"ATAR 60\", \"rank 70\", \"group 2\") instead of a level, give that band. If a row belongs to one named course, give the course name. Put subject minimums (\"minimum 60% in English\"), best-N rules (\"best four subjects\") and alternative routes into conditions. Give your confidence (0 to 1) that the row is read correctly. Each table row on the page is given as one line with its cells separated by \" | \" (a level named once for a group of rows is repeated on each row of the group). When a table has an \"Australian standard\" column (the Australian score each row is equivalent to, such as \"70%\"), that cell on the row is the row's benchmark band: give it exactly as printed, keep the level too, and give one row per band. Read every qualification column of such a table: one row for each cell that gives a minimum, and quote the cell's whole table line (it begins with the level), never the cell alone. When the message lists the published cells of a table, give exactly one row for each listed cell, in the listed order, and no row for any other cell of that table: that cell's column as the qualification, its level and band as listed, the cell as the grade, and the listed line as the quote; a value repeated from the row above is still its own row. For every row copy the exact sentence or the whole table line from the page that contains it, with the qualification and the grade (quote, at most 300 characters). Leave out English language test scores (IELTS, TOEFL, PTE and similar), fees, dates and domestic-only rows. Never infer a row from another page or from general knowledge; return an empty list if the page publishes no minimums. Also give the edition or intake year the page names, if any.";

const cond = {
  type: "object", additionalProperties: false, required: ["subject_minimums", "best_n", "alternatives"],
  properties: {
    subject_minimums: { type: "array", items: { type: "object", additionalProperties: false, required: ["subject", "min_grade"], properties: { subject: { type: "string" }, min_grade: { type: "string" } } } },
    best_n: { type: ["integer", "null"] },
    alternatives: { type: "array", items: { type: "object", additionalProperties: false, required: ["route", "min_grade"], properties: { route: { type: "string" }, min_grade: { type: ["string", "null"] } } } },
  },
};
export const ENTRY_SCHEMA = {
  type: "object", additionalProperties: false, required: ["rows", "edition", "intake_year"],
  properties: {
    edition: { type: ["string", "null"] },
    intake_year: { type: ["integer", "null"] },
    rows: { type: "array", items: { type: "object", additionalProperties: false,
      required: ["country_code", "country_name", "study_level", "qualification_name", "min_grade", "min_value", "grade_scale", "benchmark_band", "course_name", "conditions", "confidence", "quote"],
      properties: {
        country_code: { type: "string" }, country_name: { type: "string" }, study_level: { type: ["string", "null"] },
        qualification_name: { type: "string" }, min_grade: { type: ["string", "null"] }, min_value: { type: ["number", "null"] },
        grade_scale: { type: "string", enum: [...ENTRY_SCALES] }, benchmark_band: { type: ["string", "null"] }, course_name: { type: ["string", "null"] },
        conditions: cond, confidence: { type: "number" }, quote: { type: "string" },
      } } },
  },
};

// v0.49.2 (29 Oct 2026, AER programme Wave H: two large pages cut off mid-answer): the answer's length limit comes from the setting
// entry.matrix_max_tokens (8000 when not given)
// v0.50.0 (Step B): a PDF table's lines name each cell by its column header; told so with the page (the prompt itself is unchanged)
export const PDF_NOTE = "This page is a PDF table rebuilt from its drawn cells. Each table row is one line; each cell is given as its column header, a colon and the cell (\"Header: cell\"); a line beginning with § is a heading (a country or group) for the lines below it, and a row that begins with that heading belongs to it. Read the study level or qualification from the column header the cell is named by, never from its position. Quote the whole line or the part of it that holds the cell with its header.";
// v0.50.2 (29 Oct 2026): why a model call answered with no text, as OpenRouter returns it (an upstream error can come with HTTP 200)
export function entryNoAnswerWhy(d: any, slice: number, slices: number): string {
  const ch = d?.choices?.[0] || {}, bits: string[] = [];
  const err = ch?.error?.message || ch?.error?.code || d?.error?.message || d?.error?.code;
  if (err) bits.push(`error: ${String(err).slice(0, 160)}`);
  if (d?.unreadable) bits.push(`reply unreadable: ${String(d.unreadable).slice(0, 120)}`);  // v0.51.0
  if (ch?.finish_reason) bits.push(`finish: ${ch.finish_reason}`);
  if (ch?.native_finish_reason && ch.native_finish_reason !== ch.finish_reason) bits.push(`native: ${ch.native_finish_reason}`);
  if (d?.provider) bits.push(`provider: ${d.provider}`);
  if (!d?.choices && !d?.unreadable) bits.push("no choices");
  if (slices > 1) bits.push(`slice ${slice} of ${slices}`);
  return bits.length ? ` (${bits.join("; ")})` : "";
}

export function entryMatrixRequest(model: string, p: { provider: string; url: string; text: string; slice?: string; cells?: string; note?: string }, maxTokens = 8000) {
  return { model, temperature: 0, max_tokens: maxTokens, provider: { require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: "entry_matrix", strict: true, schema: ENTRY_SCHEMA } },
    messages: [{ role: "system", content: ENTRY_PROMPT },
      { role: "user", content: `Provider: ${p.provider}\nPage address: ${p.url}${p.slice ? `\nPart of the page: ${p.slice}` : ""}${p.note ? `\n\n${p.note}` : ""}\n\nPage text:\n${p.text}${p.cells ? `\n\nPublished cells of the band table(s), in printed order (one row for each):\n${p.cells}` : ""}` }] };
}

// a large one-page table is read in slices of at most maxRows lines (and maxChars characters); a markdown table's header row is
// repeated at the top of each later slice so the columns keep their meaning
export function entrySlices(text: string, maxRows: number, maxChars = 24000): string[] {
  const lines = String(text || "").split("\n");
  const out: string[] = []; let cur: string[] = [], chars = 0, header: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (/^\s*\|/.test(l) && /^\s*\|?\s*:?-{3,}/.test(lines[i + 1] || "")) header = [l, lines[i + 1]];
    if (cur.length && (cur.length >= maxRows || chars + l.length + 1 > maxChars)) {
      out.push(cur.join("\n"));
      cur = /^\s*\|/.test(l) && header.length && header[0] !== l ? [...header] : []; chars = cur.join("\n").length;
    }
    cur.push(l); chars += l.length + 1;
  }
  if (cur.join("").trim()) out.push(cur.join("\n"));
  return out.length ? out : [""];
}

// v0.48.1 (26 Oct 2026, AER v1.1 first runs: RMIT band ladders dropped as quote_not_on_page): an equivalency table names its level once
// for a group of rows (a merged cell, rowspan, or the label left blank on the rows below). Read as plain text, the lower rows of the group
// have no level, so the model's whole-row quote ("Bachelor degrees 70% Not applicable Minimum CGPA of 4.2") is not on the page. Each table
// row is given as one line, cells joined by " | ", with a merged cell repeated on the rows it spans and a blank first cell taking the label
// above it inside the same table. Only the first column is carried down from a blank cell; other cells are given as published. The page
// outside tables is unchanged (htmlToText). Quotes are checked against this same text, so the model sees what the check sees.
export const ENTRY_TABLE_BASIS = "table-rows-v1";
export function entryPageText(html: string, toText: (h: string) => string): string { return entryTables(html, toText).text }

// v0.48.2 (26 Oct 2026, AER v1.1 RMIT re-read: 59 rows, benchmark band empty on all, rows collapsed onto shared identities): a table whose
// header names an "Australian standard" column (RMIT's band ladder) publishes a benchmark band on each row. Each table line keeps the band
// printed in that column on that row (blank and "Not applicable" are no band), so the reader's band can be checked against the page.
export type EntryBandLine = { line: string; band: string | null };
export const ENTRY_BAND_HEADER = /\baustralian standard\b/i;
export const NA_BAND = /^(not applicable|n\/a|na|-|–|—)$/i;  // the page's own words for "no band" in a band column
// v0.50.1 (29 Oct 2026, AER programme Wave H: ANU and UWA rows dropped as quote_too_short / quote_not_on_page): a table whose data cells
// are all bare numbers (a rank-to-score or score-to-ATAR conversion) gives each data cell named by its column header ("Program Required
// Entrance Rank: 80 | Indicative score required: 14.0"), so a row's own line says what its numbers are and can be quoted whole. Tables
// with any worded cell are unchanged. Structure-driven: no provider or country is named. Off for a provider under the completeness guard
// (its manifest compares quotes with the plain table lines) and wherever the caller does not ask for it.
const BARE_NUMBER = /^[<>≥≤~]?\s*\d+(?:[.,]\d+)?\s*%?(?:\s*[-–]\s*\d+(?:[.,]\d+)?\s*%?)?$/;
export const NAMED_NOTE = "Some tables of numbers give each cell as its column header, a colon and the value (\"Header: value\"); quote the whole line, which names what each number is.";
// v0.52.0 (29 Oct 2026, AER reader corrections, Platform Admin mandate 28 Oct 23:22 and decision 29 Oct 09:57): the structure a table line
// carries, kept beside the page text so the quote gate can recognise printed cells quoted with the structure that names them. Nothing here
// is added to what the model reads except a table's lead label (below); every value still has to be printed in the quote.
//   forms: quotable structural line forms. (a) A table with a structural header row (a <thead>, a first row of header cells, a table of
//          named numbers, or a matrix whose top-left cell is empty): the header line followed by one of its data lines (the model quotes the
//          header with the row: "NCUK | ATAR equivalent NCUK: 8 | ATAR equivalent: 75.00"). (b) A PDF row named cell by cell: the row's first
//          cell with one other named cell of the same row ("COUNTRY: Albania | Undergraduate Entry: Case-by-case basis").
//   heads: each data line of a table with a structural header row, with every cell and the header of its column, so a band given with
//          words of its column header ("ATAR 70" for the cell 70 under "ATAR equivalent") is resolved to the printed cell, and only then.
export type EntryHeadRow = { line: string; cells: { h: string; c: string }[] };
export type EntryLineSet = EntryBandLine[] & { forms?: string[]; heads?: EntryHeadRow[] };
// a table's lead label: the last piece of text the markup prints before a table with no header row (the country named on the button or
// heading above its table), when it is a label and not a sentence, carried onto each of the table's lines as the PDF reader carries a
// section ("Argentina | NCEA Level 2 Certificate/Diploma Level | Titulo de Bachiller")
const LEAD_WORDS = 6, LEAD_CHARS = 60;  // fixed: structure rule of the reader (a label, not a sentence), as pdf.ts treats a section heading
const leadLabel = (s: string) => { const t = String(s || "").replace(/\s+/g, " ").trim(); return t && t.length <= LEAD_CHARS && t.split(" ").length <= LEAD_WORDS && !/[.;:,]$/.test(t) && /[A-Za-z]/.test(t) ? t : "" };
const lastText = (html: string, toText: (h: string) => string) => {
  const parts = String(html || "").replace(/<(script|style|noscript|svg|template)\b[\s\S]*?<\/\1>/gi, " ").replace(/<!--[\s\S]*?-->/g, " ").split(/<[^>]*>/);
  for (let i = parts.length - 1; i > 0; i--) { const t = toText(parts[i]).replace(/\s+/g, " ").trim(); if (t) return t }  // parts[0] may begin inside a tag
  return "";
};
export function entryTables(html: string, toText: (h: string) => string, nameNumbers = false): { text: string; lines: EntryLineSet; grids: string[][][]; covered: boolean[][]; named: number; forms: string[]; heads: EntryHeadRow[]; labelled: number } {
  // covered (v0.48.6, D5): per table and row, whether a merged cell from an earlier row still spans a column past the end of this row
  // (the carry stops at the first gap), so a short row there is not simply a row whose trailing cells were left out
  const all: EntryBandLine[] = [], grids: string[][][] = [], covered: boolean[][] = [];
  let named = 0, labelled = 0;
  const cellText = (h: string) => toText(h).replace(/\s*\n\s*/g, " ").replace(/\s+/g, " ").trim();
  const tables: string[] = [], built: { lines: string[]; head: boolean; heads: EntryHeadRow[]; lead: string }[] = [];
  let end = 0;  // where the previous table ended in the markup
  const marked = String(html || "").replace(/<table\b[\s\S]*?<\/table>/gi, (table, at: number, whole: string) => {
    const from = end; end = at + table.length;
    const grid: string[][] = [], carry: { left: number; text: string }[] = [], cov: boolean[] = [], ths: boolean[] = [];
    for (const tr of table.match(/<tr\b[\s\S]*?(?=<tr\b|<\/table>)/gi) || []) {
      const row: string[] = []; let col = 0, th = 0, td = 0;
      const take = () => { while (carry[col]?.left > 0) { row[col] = carry[col].text; carry[col].left--; col++ } };
      for (const m of tr.matchAll(/<(td|th)\b([^>]*)>([\s\S]*?)(?=<\/?(?:td|th|tr)\b|<\/table>|$)/gi)) {
        if (/^th$/i.test(m[1])) th++; else td++;
        take();
        const span = Math.max(1, Math.min(Number((m[2].match(/\browspan\s*=\s*["']?(\d+)/i) || [])[1] || 1), 200));  // fixed: guard against a malformed rowspan
        const cs = Math.max(1, Math.min(Number((m[2].match(/\bcolspan\s*=\s*["']?(\d+)/i) || [])[1] || 1), 50));  // fixed: guard against a malformed colspan
        const t = cellText(m[3]);
        for (let k = 0; k < cs; k++) { row[col] = t; if (span > 1) carry[col] = { left: span - 1, text: t }; col++ }
      }
      take();
      const beyond = carry.some((x, j) => j >= row.length && x?.left > 0);
      if (row.some((x) => x)) { grid.push(row); cov.push(beyond); ths.push(th > 0 && td === 0) }
    }
    if (!grid.length) return table;
    let label = "", bandCol = -1;
    const carried: string[][] = [];
    const head = grid[0], body = grid.slice(1);
    const numeric = nameNumbers && head.filter((c) => c).length >= 2 && head.every((c) => !c || !BARE_NUMBER.test(c)) && body.length >= 2
      && body.every((r) => r.length <= head.length && r.every((c) => !c || BARE_NUMBER.test(c)) && r.some((c) => c));
    if (numeric) named++;
    const lines = grid.map((r, i) => {
      const cells = Array.from({ length: r.length }, (_, j) => r[j] ?? "");
      if (cells[0]) label = cells[0]; else if (i > 0 && label && cells.slice(1).some((x) => x)) cells[0] = label;
      carried.push(cells);
      const line = numeric && i > 0 ? cells.map((c, j) => c ? `${head[j] || `Column ${j + 1}`}: ${c}` : "").filter(Boolean).join(" | ") : cells.join(" | ");
      const h = cells.findIndex((c) => ENTRY_BAND_HEADER.test(c));
      if (bandCol < 0 && h > 0) { bandCol = h; all.push({ line, band: null }); return line }  // the header row names the band column
      const b = bandCol > 0 ? String(cells[bandCol] || "").trim() : "";
      all.push({ line, band: b && !/^(not applicable|n\/a|-|–)$/i.test(b) ? b : null });
      return line;
    });
    // v0.52.0: a structural header row (only where the caller asks for structure forms): a <thead>, a first row of header cells only, a
    // table of named numbers, a matrix whose top-left cell is empty above worded column headings, or a row of worded headings (no figure in
    // any of them) above rows that each print a figure ("GCE A-LEVEL GRADES | GCE A-LEVEL POINTS | ATAR EQUIVALENT" above "CDD | 7 | 70")
    const worded = (r: string[]) => r.filter(Boolean).length >= 2 && r.every((c) => !c || !/\d/.test(c));
    const hasHead = nameNumbers && grid.length > 1 && (numeric || /<thead\b/i.test(table) || ths[0]
      || (!head0(grid[0][0]) && grid[0].slice(1).filter(Boolean).length >= 2 && grid[0].slice(1).every((c) => c && !BARE_NUMBER.test(c)))
      || (worded(grid[0]) && body.every((r) => r.some((c) => BARE_NUMBER.test(c) || /^\d+(?:[.,]\d+)?\s*%?\s+to\s+\d/.test(c)))));
    const heads: EntryHeadRow[] = hasHead ? carried.slice(1).map((cells, k) => ({ line: lines[k + 1], cells: cells.map((c, j) => ({ h: String(grid[0][j] || ""), c: String(c || "") })).filter((x) => x.c && x.h) })) : [];
    const lead = nameNumbers && !hasHead ? leadLabel(lastText(whole.slice(from, at), toText)) : "";
    tables.push(lines.join("\n")); grids.push(carried); covered.push(cov); built.push({ lines, head: hasHead, heads, lead });
    return `<p>ZZENTRYTABLE${tables.length - 1}ZZ</p>`;  // a placeholder the page text keeps; the rows replace it after
  });
  const plain = toText(marked);
  const forms: string[] = [], heads: EntryHeadRow[] = [];
  if (!nameNumbers) return { text: plain.replace(/ZZENTRYTABLE(\d+)ZZ/g, (_, n) => `\n${tables[Number(n)]}\n`), lines: all, grids, covered, named, forms, heads, labelled };
  // v0.52.0: a table with no header row carries its lead label on each of its lines; a table with a header row gives its structure forms.
  // The text is otherwise the same as before.
  const text = plain.replace(/ZZENTRYTABLE(\d+)ZZ/g, (_, n) => {
    const b = built[Number(n)];
    if (b.lead) labelled++;
    const lines = b.lead ? b.lines.map((x) => `${b.lead} | ${x}`) : b.lines;
    if (b.head) { for (const x of lines.slice(1)) forms.push(`${lines[0]}\n${x}`); heads.push(...b.heads) }
    return `\n${lines.join("\n")}\n`;
  });
  // the band lines carry the structure to the gate (entryMatrixParsed reads lines.forms and lines.heads)
  return { text, lines: Object.assign(all, { forms, heads }), grids, covered, named, forms, heads, labelled };
}
const head0 = (c: string | undefined) => String(c || "").trim();

// letters and digits compared, case and spacing ignored, so words split by markup ("S enior", NMIT 25 Oct byte-check) still match
const flat = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");
const ENGLISH_TEST = /\b(ielts|toefl|pte|duolingo|cambridge english|oet)\b/i;

export type EntryDrop = { reason: string; country?: string; quote?: string };
// v0.48.2: bandLines (from entryTables) are the page's table lines with the band each publishes. A row whose quote is such a line and shows
// its band must give that band (band_missing otherwise); a band given must be in the quote (band_not_in_quote) and be the one the line
// publishes (band_mismatch); lines that match the quote with different bands leave it unproven (band_ambiguous). The band kept is the one
// printed on the page, never inferred.
// v0.52.0: bandLines may carry the page's structure (EntryLineSet: forms and heads from entryTables, forms from pdfTables). A quote is on
// the page when it is in the page text or in one structural form; each form is printed text of one table row with the structure that
// names it, so a value must still be printed in the quote. A band given with words of its column header is the printed cell only when the
// whole row is quoted, the cell is in that column and the other words are that column's header words (headerBand).
export function entryMatrixParsed(a: any, page: string, bandLines: EntryLineSet = []) {
  const F = (bandLines.forms || []).map(flat);
  const P = flat(page), on = (q: string) => flat(q).length >= 6 && (P.includes(flat(q)) || F.some((f) => f.includes(flat(q))));
  const numIn = (n: number, q: string) => [String(n), String(n).replace(/\.0$/, ""), n.toFixed(1), n.toFixed(2)].some((d) => String(q || "").includes(d));
  const rows: any[] = [], dropped: EntryDrop[] = [];
  for (const x of (Array.isArray(a?.rows) ? a.rows : []) as any[]) {
    const quote = String(x?.quote || "").trim(), cc = String(x?.country_code || "").toUpperCase().trim();
    const d = (reason: string) => dropped.push({ reason, country: cc || String(x?.country_name || ""), quote: quote.slice(0, 120) });
    if (!/^[A-Z]{2}$/.test(cc)) { d("unknown_country"); continue }
    if (flat(quote).length < 6) { d("quote_too_short"); continue }  // a bare cell ("70 10.5") proves nothing: the whole row is quoted
    if (!on(quote)) { d("quote_not_on_page"); continue }
    if (ENGLISH_TEST.test(quote) && ENGLISH_TEST.test(String(x?.qualification_name || ""))) { d("english_test_row"); continue }
    const scale = ENTRY_SCALES.includes(x?.grade_scale) ? x.grade_scale : "none";
    const value = typeof x?.min_value === "number" && Number.isFinite(x.min_value) ? x.min_value : null;
    if (value != null && scale === "none") { d("value_without_scale"); continue }
    if (value != null && !numIn(value, quote)) { d("value_not_in_quote"); continue }
    const grade = x?.min_grade == null ? null : String(x.min_grade).trim() || null;
    if (grade && !flat(quote).includes(flat(grade))) { d("grade_not_in_quote"); continue }
    const Q = flat(quote), given0 = x?.benchmark_band == null ? null : String(x.benchmark_band).trim() || null;
    const given = given0 && !Q.includes(flat(given0)) && !NA_BAND.test(given0) ? (headerBand(given0, Q, bandLines.heads || []) ?? given0) : given0;
    const published = [...new Set(bandLines.filter((l) => l.band && flat(l.band) && Q.includes(flat(l.band)) && (flat(l.line).includes(Q) || Q.includes(flat(l.line))))
      .map((l) => String(l.band)))];
    if (published.length > 1) { d("band_ambiguous"); continue }
    // v0.48.4 (D1, 27 Oct 2026): a band given as the page's own "Not applicable" (or a dash) is no band when the quoted line prints none in
    // its band column; on a line that prints a band it is a missing band. The quote keeps the source text either way.
    const givenNA = !!given && NA_BAND.test(given);
    if (published.length === 1 && (!given || givenNA)) { d("band_missing"); continue }
    if (given && !givenNA && !Q.includes(flat(given))) { d("band_not_in_quote"); continue }
    if (given && !givenNA && published.length === 1 && flat(given) !== flat(published[0])) { d("band_mismatch"); continue }
    const band = published.length === 1 ? published[0] : (givenNA ? null : given);
    rows.push({ country_code: cc, country_name: String(x?.country_name || ""), study_level: x?.study_level ?? null, qualification_name: String(x?.qualification_name || "").trim(),
      min_grade: grade, min_value: value, grade_scale: scale, benchmark_band: band, course_name: x?.course_name ?? null,
      conditions: x?.conditions ?? {}, confidence: Number(x?.confidence ?? 0), quote: quote.slice(0, 300) });
  }
  return { rows, dropped, edition: a?.edition ?? null, intake_year: Number.isInteger(a?.intake_year) ? a.intake_year : null };
}
// v0.52.0: "ATAR 70" quoted with the row "French Baccalaureat Points: 10 | ATAR equivalent: 70" is the printed cell "70" of the column
// "ATAR equivalent": one word of the band is exactly the cell, every other word is a word of that column's header, the whole row line is in
// the quote, and every row the quote holds gives the same cell. Anything else gives null (the band stays as given and the gate decides).
export function headerBand(given: string, Q: string, heads: EntryHeadRow[]): string | null {
  const toks = String(given || "").split(/\s+/).map(flat).filter(Boolean);
  if (toks.length < 2) return null;
  const found = new Set<string>();
  for (const r of heads) {
    if (!flat(r.line) || !Q.includes(flat(r.line))) continue;
    for (const { h, c } of r.cells) {
      const v = flat(c); if (!v) continue;
      const k = toks.indexOf(v); if (k < 0) continue;
      const hw = allWords(h), rest = toks.filter((_, i) => i !== k);
      if (rest.length && rest.every((t) => hw.has(t))) found.add(c.trim());
    }
  }
  return found.size === 1 ? [...found][0] : null;
}

// v0.48.3 (26 Oct 2026, Platform Admin 23:16 "source-anchored completeness guard"): a read of 13 of 22 China rows (the whole Gao Kao column
// left out) was proposed with nothing dropped. The stored page is the source of truth: entryManifest lists every minimum an equivalency
// table publishes (each row of a table with an "Australian standard" column, for each qualification column, the cell the row carries after
// merged cells and carried-down level labels; "Not applicable" and blank cells publish nothing; a grading or calculation row is a footnote,
// not a minimum). entryCompleteness matches each row the reader kept to exactly one manifest entry: its quote must be the entry's table line
// (so it shows the level, and the band when the line has one), its grade must be in the entry's own cell, its level and band must be the
// line's, and its qualification must name the entry's column. The read is complete only when every entry is matched once and every kept
// row is explained; otherwise it is held whole (never proposed in part). A page whose tables cannot be read this way is "unparsed".
export type EntryManifestEntry = { line: string; level: string; band: string | null; col: number; header: string; cell: string };
export type EntryManifest = { status: "ok" | "none" | "unparsed"; reason: string | null; heading: string; entries: EntryManifestEntry[]; columns: string[]; footnotes: string[] };
const NA = /^(not applicable|n\/a|-|–|—)$/i;
const FOOTNOTE_ROW = /^(grading|calculation|note|notes|\*)|\b(grading|calculation system)\b/i;
const allWords = (s: string) => new Set(String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, " ").split(" ").filter(Boolean));
const words = (s: string) => new Set(String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, " ").split(" ").filter((w) => w.length > 1 && !/^(of|the|and|or|in|at|a)$/.test(w)));
export function entryManifest(html: string, toText: (h: string) => string): EntryManifest { return entryManifestDetail(html, toText).manifest }
// v0.48.7 (D4): the manifest plus the band tables' data lines that publish no minimum (every qualification cell blank or "Not applicable"),
// kept apart so the manifest itself (and its recorded fingerprints) is unchanged
export function entryManifestDetail(html: string, toText: (h: string) => string): { manifest: EntryManifest; emptyLines: string[] } {
  const emptyLines: string[] = [];
  const manifest = ((): EntryManifest => {
  const h1 = (String(html || "").match(/<h1[^>]*>([\s\S]*?)<\/h1>/i) || [])[1], title = (String(html || "").match(/<title[^>]*>([\s\S]*?)<\/title>/i) || [])[1];
  const heading = [h1, title].filter(Boolean).map((x) => toText(String(x)).replace(/\s+/g, " ").trim()).join(" | ");
  const { grids, covered } = entryTables(html, toText);
  const entries: EntryManifestEntry[] = [], columns: string[] = [], footnotes: string[] = [];
  let found = 0;
  for (const [gi, g] of grids.entries()) {
    const hi = g.findIndex((r) => r.some((c, j) => j > 0 && ENTRY_BAND_HEADER.test(c)));
    if (hi < 0) continue;
    found++;
    const header = g[hi], bandCol = header.findIndex((c, j) => j > 0 && ENTRY_BAND_HEADER.test(c));
    const qual = header.map((c, j) => ({ j, c })).filter(({ j, c }) => j > 0 && j !== bandCol && c.trim());
    if (!qual.length) return { status: "unparsed", reason: "a band table has no qualification column", heading, entries: [], columns: [], footnotes: [] };
    const body = g.slice(hi + 1);
    if (!body.length) return { status: "unparsed", reason: "a band table has no rows", heading, entries: [], columns: [], footnotes: [] };
    for (const [bi, r0] of body.entries()) {
      const line = r0.join(" | ");
      // v0.48.8 (PR A, P2, 27 Oct 2026): the table's header row printed again inside the body (Singapore: "Level of study | Australian
      // standard | Completion of Secondary School ... |") is a header, not a row of minimums: every non-blank cell is its column's heading
      if (ENTRY_BAND_HEADER.test(String(r0[bandCol] || "")) && r0.every((c, j) => !String(c || "").trim() || flat(c) === flat(header[j] || ""))) continue;
      // v0.48.6 (D5, 27 Oct 2026): a grading or calculation row is a footnote whatever its width (Kuwait: one cell spans the columns,
      // colspan 3 under a three-column header); it publishes no minimum
      if (r0[0] && FOOTNOTE_ROW.test(r0[0])) { footnotes.push(line); continue }
      if (r0.length > header.length) return { status: "unparsed", reason: `a row has ${r0.length} cells, the header ${header.length}: ${line.slice(0, 80)}`, heading, entries: [], columns: [], footnotes: [] };
      // a data row whose trailing cells were left out of the markup (Mexico 80%: the other rows carry an empty cell there) is read with
      // those cells blank, which publish nothing; when a merged cell from an earlier row still spans one of them, the row is not
      // understood and the table stays unparsed (padding there would drop a published minimum)
      if (r0.length < header.length && covered[gi]?.[hi + 1 + bi]) return { status: "unparsed", reason: `a short row under a merged cell: ${line.slice(0, 80)}`, heading, entries: [], columns: [], footnotes: [] };
      const r = r0.length < header.length ? [...r0, ...Array(header.length - r0.length).fill("")] : r0;
      // a browser shows a short row's cells from the left, so a cell missing in the middle shifts the others: a padded row whose band
      // cell is not blank, "Not applicable" or the same shape as the band cells of the table's full rows ("80%") is not understood
      if (r0.length < header.length) {
        const shape = (x: string) => String(x || "").trim().replace(/\d+(?:\.\d+)?/g, "9");
        const b = String(r[bandCol] || "").trim(), full = new Set(body.filter((x) => x.length === header.length && x[bandCol] && !NA.test(String(x[bandCol]).trim())).map((x) => shape(x[bandCol])));
        if (b && !NA.test(b) && !full.has(shape(b))) return { status: "unparsed", reason: `a short row whose band cell does not read as a band: ${line.slice(0, 80)}`, heading, entries: [], columns: [], footnotes: [] };
      }
      if (!r[0]) return { status: "unparsed", reason: `a row has no level label: ${line.slice(0, 80)}`, heading, entries: [], columns: [], footnotes: [] };
      const b = String(r[bandCol] || "").trim(), band = b && !NA.test(b) ? b : null;
      if (qual.every(({ j }) => { const x = String(r[j] || "").trim(); return !x || NA.test(x) })) emptyLines.push(line);
      for (const { j, c } of qual) {
        const cell = String(r[j] || "").trim();
        if (!cell || NA.test(cell)) continue;
        // a table repeated on the page (a second copy for small screens) publishes the same minimum once
        if (entries.some((e) => e.line === line && e.header === c)) continue;
        entries.push({ line, level: r[0], band, col: j, header: c, cell });
      }
    }
    for (const { c } of qual) if (!columns.includes(c)) columns.push(c);
  }
  if (!found) return { status: "none", reason: "no table with an Australian standard column", heading, entries, columns, footnotes };
  if (!entries.length) return { status: "unparsed", reason: "the band tables publish no minimum", heading, entries, columns, footnotes };
  return { status: "ok", reason: null, heading, entries, columns, footnotes };
  })();
  return { manifest, emptyLines: manifest.status === "ok" ? emptyLines : [] };
}

// v0.48.4 (D2, 27 Oct 2026, Platform Admin 04:58 "hold them as non-country/unreadable sources without further automatic retries"): an
// equivalency page under the guard must be one country's table. Two shapes are not: a table whose columns are requirement types (English
// requirement, academic requirement, prerequisites: RMIT "Foundation equivalencies"), and a page whose heading names a qualification, not a
// country (RMIT "International Baccalaureate", "Global Assessment Certificate"). The page's heading (h1 and title) must name a country of
// the reference list: its name, official name, the name before a comma ("Korea" of "Korea, Republic of") or its alpha-3 code as a word.
export type EntryCountryRef = { a2: string; a3: string; name: string; official: string | null };
const REQUIREMENT_COLUMN = /\b(english|prerequisites?|academic requirement|requirement \d|entry requirement)\b/i;
export function entryPageCountry(heading: string, countries: EntryCountryRef[]): string | null {
  // the longest name the heading contains wins ("Nigeria" over "Niger"); an alpha-3 code must stand as its own word ("USA")
  const H = flat(heading), W = new Set(String(heading || "").split(/[^A-Za-z]+/).filter(Boolean));
  let best: string | null = null, len = 0;
  for (const c of countries || []) {
    const names = [c.name, c.official || "", String(c.name || "").split(",")[0]].map(flat).filter((n) => n.length >= 4 && H.includes(n));
    const l = Math.max(0, ...names.map((n) => n.length), c.a3 && W.has(String(c.a3).toUpperCase()) ? 3 : 0);
    if (l > len) { best = c.a2; len = l }
  }
  return best;
}
export function entryNonCountryShape(man: EntryManifest, countries: EntryCountryRef[]): string | null {
  const req = man.columns.filter((c) => REQUIREMENT_COLUMN.test(c));
  if (req.length) return `requirement-type columns, not qualifications (${req.join("; ")})`.slice(0, 300);
  if (!entryPageCountry(man.heading, countries)) return `no country named in the page heading ("${man.heading.slice(0, 120)}")`;
  return null;
}

// v0.48.8 (PR A, R2, 27 Oct 2026, Platform Admin 14:35 "preserve the printed numeric scale so bare numbers are not admitted without scale"):
// a qualification column whose every published cell is a bare number ("1", "2.0" ... "5.0": Norway) has no scale unless the page prints one
// (a "scale", "out of", "maximum" or "/n" in the page heading, the column heading, a cell or a grading/calculation row). Such a column cannot be
// admitted as numbers, and its numbers mean nothing as text without the scale, so the page is held as a source hold before any AI read.
const SCALE_PRINTED = /\b(scale|out of|maximum|max\.?)\b|\/\s*\d/i;
export function entryUnscaledColumns(man: EntryManifest): string[] {
  if (man.status !== "ok") return [];
  if (SCALE_PRINTED.test(man.heading) || man.footnotes.some((f) => SCALE_PRINTED.test(f))) return [];
  return man.columns.filter((c) => {
    const cells = man.entries.filter((e) => e.header === c).map((e) => e.cell.trim());
    return cells.length > 0 && !SCALE_PRINTED.test(c) && cells.every((x) => /^\d+(?:[.,]\d+)?$/.test(x));
  });
}

export type EntryCompleteness = { status: "complete" | "incomplete" | "unparsed" | "not_applicable"; basis: string; heading?: string; expected: number; matched: number;
  omitted_columns: string[]; omitted: { level: string; band: string | null; column: string; cell: string }[]; unexplained: { reason: string; quote: string; country: string }[]; reason: string | null };
export const ENTRY_COMPLETENESS_BASIS = "manifest-v1";
export function entryCompleteness(man: EntryManifest, rows: any[]): EntryCompleteness {
  const base = { basis: ENTRY_COMPLETENESS_BASIS, heading: man.heading.slice(0, 200), expected: man.entries.length, matched: 0, omitted_columns: [] as string[], omitted: [] as any[], unexplained: [] as any[], reason: man.reason };
  if (man.status === "none") return { ...base, status: "not_applicable" };
  if (man.status === "unparsed") return { ...base, status: "unparsed" };
  const taken = new Map<number, number>(), unexplained: { reason: string; quote: string; country: string }[] = [];
  const H = flat(man.heading);
  rows.forEach((x, ri) => {
    const quote = String(x?.quote || ""), Q = flat(quote), u = (reason: string) => unexplained.push({ reason, quote: quote.slice(0, 120), country: String(x?.country_code || "") });
    const cn = flat(x?.country_name || "");
    if (!cn || !(H.includes(cn) || (cn.length >= 4 && [...words(x?.country_name)].some((w) => w.length >= 4 && H.includes(flat(w)))))) return u("country_not_evidenced");
    const onLine = man.entries.map((e, i) => ({ e, i })).filter(({ e }) => flat(e.line).includes(Q));
    if (!onLine.length) return u("not_a_table_row");
    const withLevel = onLine.filter(({ e }) => Q.includes(flat(e.level)) && (!e.band || Q.includes(flat(e.band))));
    if (!withLevel.length) return u("level_not_evidenced");  // a cell-only quote does not prove its level (or band)
    const grade = x?.min_grade == null ? "" : flat(x.min_grade);
    const inCell = withLevel.filter(({ e }) => (grade ? flat(e.cell).includes(grade) : true) && Q.includes(flat(e.cell)));
    if (!inCell.length) return u("grade_not_in_cell");
    // the qualification must name one column of the table better than every other column, and that column must hold the grade
    const qw = words(x?.qualification_name), score = (h: string) => { const hw = words(h); let n = 0; for (const w of qw) if (hw.has(w)) n++; return n / Math.max(1, new Set([...qw, ...hw]).size) };
    let cols = [...new Set(man.entries.filter((e) => e.line === inCell[0].e.line || inCell.some((c) => c.e.line === e.line)).map((e) => e.header))].map((h) => ({ h, s: score(h) })).sort((a, b) => b.s - a.s);
    // v0.48.8 (PR A, G1, 27 Oct 2026): two columns that differ only by a one-character word ("Sri Lanka O Levels" / "A Levels", "Matayom 5" /
    // "6", Scottish Higher "(3 subjects)" / "(4 subjects)") tie on the word score; the tie is broken by the same score over every word, single
    // characters included, and only when that gives one column strictly the best. A tie that remains is still not resolved.
    if (cols.length > 1 && cols[0].s && cols[1].s === cols[0].s) {
      const tw = allWords(x?.qualification_name), score2 = (h: string) => { const hw = allWords(h); let n = 0; for (const w of tw) if (hw.has(w)) n++; return n / Math.max(1, new Set([...tw, ...hw]).size) };
      const tied = cols.filter((c) => c.s === cols[0].s).map((c) => ({ h: c.h, s: score2(c.h) })).sort((a, b) => b.s - a.s);
      if (!(tied[0].s > 0 && tied[0].s > tied[1].s)) return u("qualification_not_resolved");
      cols = [{ h: tied[0].h, s: 1 }];  // resolved by the tie-break: the one column strictly best over every word
    }
    if (!cols.length || !cols[0].s || (cols[1] && cols[1].s === cols[0].s)) return u("qualification_not_resolved");
    const best = inCell.filter((c) => c.e.header === cols[0].h);
    if (!best.length) return u("wrong_column");  // the named column does not hold this grade on this line
    if (new Set(best.map((c) => c.e.line)).size > 1) return u("line_ambiguous");
    const e = best[0].e, idx = best[0].i;
    if (flat(x?.study_level || "") !== flat(e.level)) return u("wrong_level");
    if (flat(x?.benchmark_band || "") !== flat(e.band || "")) return u("wrong_band");
    if (taken.has(idx)) return u("duplicate_row");
    taken.set(idx, ri);
  });
  const omittedIdx = man.entries.map((_, i) => i).filter((i) => !taken.has(i));
  const omitted = omittedIdx.map((i) => ({ level: man.entries[i].level, band: man.entries[i].band, column: man.entries[i].header, cell: man.entries[i].cell }));
  const omitted_columns = man.columns.filter((c) => man.entries.some((e) => e.header === c) && man.entries.every((e, i) => e.header !== c || !taken.has(i)));
  const complete = !omitted.length && !unexplained.length;
  return { ...base, status: complete ? "complete" : "incomplete", matched: taken.size, omitted, omitted_columns, unexplained,
    reason: complete ? null : [omitted_columns.length ? `column left out: ${omitted_columns.join("; ")}` : "", omitted.length ? `${omitted.length} of ${man.entries.length} published minimums not read` : "", unexplained.length ? `${unexplained.length} rows not explained (${[...new Set(unexplained.map((x) => x.reason))].join(", ")})` : ""].filter(Boolean).join("; ") };
}

// v0.48.7 (D4, 27 Oct 2026, Platform Admin 05:46: "Drive behaviour from table structure and source evidence"): the reader is given the band
// tables' published cells, taken from the manifest in printed order, so it reads every cell once (a value repeated in the row above, a
// merged case-by-case cell, the right printed column) and none that publishes nothing. The guard still checks the read independently.
export function entryCellList(man: EntryManifest): string {
  if (man.status !== "ok" || !man.entries.length) return "";
  return man.entries.map((e, i) => `[${i + 1}] level: ${e.level} | band: ${e.band ?? "none"} | column: ${e.header} | cell: ${e.cell}\n    line: ${e.line}`).join("\n");
}
// a row whose quoted table line publishes no minimum (every qualification cell blank or "Not applicable") is not a minimum: dropped before
// the guard (Pakistan, Philippines: Bachelor lines that are all "Not applicable")
export function entryDropNoMinimum(man: EntryManifest, emptyLines: string[], rows: any[]): { rows: any[]; dropped: EntryDrop[] } {
  if (man.status !== "ok" || !emptyLines.length) return { rows, dropped: [] };
  const E = emptyLines.map(flat), P = man.entries.map((e) => flat(e.line)), keep: any[] = [], dropped: EntryDrop[] = [];
  for (const x of rows) {
    const Q = flat(x?.quote || "");
    const onEmpty = E.some((l) => l.includes(Q) || (Q.length >= l.length && Q.includes(l)));
    const onPublished = P.some((l) => l.includes(Q) || (Q.length >= l.length && Q.includes(l)));
    if (Q && onEmpty && !onPublished) dropped.push({ reason: "no_minimum_published", country: String(x?.country_code || ""), quote: String(x?.quote || "").slice(0, 120) });
    else keep.push(x);
  }
  return { rows: keep, dropped };
}
