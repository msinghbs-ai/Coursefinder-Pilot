// CF-247 S744 (19 Nov 2026, session S2-BOOST-AER; Platform Admin full-steam directive 19 Nov 2026 05:42 AEDT, item 3): the deterministic table row chunker for dense
// entry-requirement pages. Rounds 4 and 5 of the AER v2 qualification sent a whole multi-row international table in one model call: the models dropped rows (54 provider
// matrices held on the D-R3 completeness gate) or ran out of time. Before any model sees such a page, it is split here into one chunk per printed table row (or per labelled
// list line), each carrying the headings printed over it, the table's header line, its row label and its cells, with the row's quote exactly as it stands in the page text the
// checks read. A model then answers one small chunk at a time, and completeness is a count: every printed row is a chunk, so none can go missing unnoticed.
// AER v2 record source only (Decision 276): no AER v1 reader, prompt, word list or threshold is changed, and this module calls nothing that writes, fetches or asks a model.
// It reuses the page text and header forms of entryTables, the cell minimum parser and the row label classifier (entry-cells.ts). National qualifications (ATAR, Gaokao,
// CBSE, ISC, STPM, UEC, HKDSE and the like) are named by the alias list passed in (a setting at the caller), never by a word list here.
import { entryTables, type EntryQualification } from "./entry.ts";
import { entryCellMinimum, entryCellLabel, entryCellCountryIndex, type CellCountryIndex } from "./entry-cells.ts";
import type { EntryCountryRef } from "./entry.ts";

export type ChunkCell = { head: string; text: string; minimum: { grade: string; value: number | null; scale: string } | null; qualification: string | null };
export type EntryChunk = {
  n: number;                      // page order, from 1
  kind: "table_row" | "list_line" | "text_block";
  table: number | null;           // which table block of the page (from 0), or null outside tables
  context: string[];              // the headings printed over it, outermost first (page heading, section headings, the tab or accordion label)
  header: string | null;          // the table's header line, exactly as in the page text, when the table has one
  label: string;                  // the row label: the first cell of a table row, or the words before the colon of a list line
  quote: string;                  // the row exactly as it stands in the page text the checks read, never rebuilt
  cells: ChunkCell[];
  country: string | null;         // ISO code when the label names exactly one country
  qualification: string | null;   // an international qualification code (entryCellLabel) or a national one from the alias list
};
export type NationalQualification = { code: string; country: string | null; aliases: string[] };
export type ChunkOptions = { qualifications?: EntryQualification[]; national?: NationalQualification[]; countries?: EntryCountryRef[]; countryAliases?: Record<string, string>;
  textBlockChars?: number; notRows?: Set<string> };
export type EntryChunkSet = { text: string; chunks: EntryChunk[]; tables: number; tableRows: number; headerLines: number; listLines: number; textBlocks: number; notRows: Set<string> };

const TEXT_BLOCK_CHARS = 1500;  // fixed: shape of a prose chunk outside tables (a paragraph group under one heading), not an operational limit
const HEADING_WORDS = 12, HEADING_CHARS = 90;  // fixed: shape rule of a heading line (a label, not a sentence), as entry.ts treats a lead label
const words = (s: unknown) => String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, " ").trim();
const isRow = (l: string) => l.includes(" | ") || /^\|.*\|$/.test(l.trim());
const isHeading = (l: string) => { const t = l.trim(); return !!t && t.length <= HEADING_CHARS && t.split(/\s+/).length <= HEADING_WORDS && !/[.;,]$/.test(t) && !isRow(t) && /[A-Za-z]/.test(t) };
const LIST_LINE = /^([A-Z][^:|]{1,60}?)\s*:\s+(\S.*)$/;  // "Argentina: Bachillerato / Técnico de Nivel Medio" (a label, a colon, the requirement)

// a national qualification named in the text, as whole words (the longest alias wins)
export function chunkNationalQualification(text: string, list: NationalQualification[] = []): NationalQualification | null {
  const w = ` ${words(text)} `; let best: { q: NationalQualification; n: number } | null = null;
  for (const q of list) for (const a of q.aliases || []) { const aw = words(a); if (aw.length >= 2 && w.includes(` ${aw} `) && (!best || aw.length > best.n)) best = { q, n: aw.length } }
  return best?.q ?? null;
}

// the chunks of one stored HTML page (the same page text the entry-matrix checks read: entryTables with structure forms)
export function entryChunks(html: string, toText: (h: string) => string, opt: ChunkOptions = {}): EntryChunkSet {
  const et = entryTables(html, toText, true);
  // a line the page prints outside its tables is never a table row, even when it holds " | " (a page title "China | Academic Entry Requirements")
  const outside = new Set(entryTables(String(html || "").replace(/<table\b[\s\S]*?<\/table>/gi, " "), toText, true).text.split("\n").map((l) => l.trim()).filter(Boolean));
  return entryChunksOfText(et.text, et.forms, et.heads, { ...opt, notRows: outside });
}

// the chunks of a page text whose tables are lines of cells separated by " | " (entryTables text, or a Markdown copy): exported so a Markdown copy is chunked the same way
export function entryChunksOfText(text: string, forms: string[] = [], heads: { line: string; cells: { h: string; c: string }[] }[] = [], opt: ChunkOptions = {}): EntryChunkSet {
  const idx: CellCountryIndex = entryCellCountryIndex(opt.countries || [], opt.countryAliases || {});
  // a header line is one entryTables paired with the line after it ("header\nrow" is one of its forms): a data row printing the same words as some table's header is still a row
  const formSet = new Set(forms.map((f) => f.split("\n").map((x) => x.trim()).join("\n")));
  const headOf = new Map(heads.map((h) => [h.line.trim(), h.cells]));
  const lines = String(text || "").split("\n").map((l) => l.replace(/\s+$/, ""));
  const notRows = opt.notRows || new Set<string>();
  const row = (l: string) => isRow(l) && !notRows.has(l);
  const chunks: EntryChunk[] = [];
  const ctx: string[] = [];  // the headings seen, innermost last; a table or list takes the nearest three
  let table = -1, inTable = false, header: string | null = null, label = "", textBuf: string[] = [], tableRows = 0, headerCount = 0, listLines = 0, textBlocks = 0;
  const textChars = Math.max(200, Number(opt.textBlockChars) || TEXT_BLOCK_CHARS);
  const flushText = () => {
    if (!textBuf.length) return;
    let cur: string[] = [];
    const out = () => { if (cur.length) { chunks.push(make("text_block", null, null, "", cur.join("\n"), [])); textBlocks++; cur = [] } };
    for (const t of textBuf) { if (cur.length && cur.join("\n").length + t.length + 1 > textChars) out(); cur.push(t) }
    out(); textBuf = [];
  };
  // the qualification a column header (or a cell) names: an international one first, then a national one of the alias list
  const qualOf = (t: string): string | null => {
    if (!t) return null;
    const c = entryCellLabel(t, idx, opt.qualifications || []);
    return c.qualification ?? chunkNationalQualification(t, opt.national)?.code ?? null;
  };
  // the country the headings name: the nearest heading naming exactly one country
  const ctxCountry = (): string | null => {
    for (let k = ctx.length - 1; k >= 0 && k >= ctx.length - 3; k--) {
      for (const part of ctx[k].split(/\s*\|\s*/)) { const c = entryCellLabel(part, idx, opt.qualifications || []); if (c.country && (c.kind === "country" || c.kind === "board")) return c.country }
    }
    return null;
  };
  const make = (kind: EntryChunk["kind"], tbl: number | null, hdr: string | null, lab: string, quote: string, cells: ChunkCell[]): EntryChunk => {
    const cl = lab ? entryCellLabel(lab, idx, opt.qualifications || []) : null;
    const nat = chunkNationalQualification(lab, opt.national);
    for (const c of cells) c.qualification = qualOf(c.head) ?? (c.text.length <= HEADING_CHARS ? qualOf(c.text) : null);
    return { n: chunks.length + 1, kind, table: tbl, context: ctx.slice(-3), header: hdr, label: lab, quote, cells,
      country: cl?.country ?? nat?.country ?? ctxCountry(), qualification: cl?.qualification ?? nat?.code ?? null };
  };
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i].trim(), next = (lines[i + 1] || "").trim();
    if (!l) { if (inTable) { inTable = false; header = null; label = "" } continue }
    if (row(l)) {
      flushText();
      if (!inTable) { inTable = true; table++; header = null; label = "" }
      // the header row names the columns; it is context, not a requirement. A header line met again inside a block starts the next table (tables printed back to back)
      // the same header printed again inside a table (RMIT foundation equivalencies, table 24) stays that table's header; a different one starts the next table
      if (formSet.has(`${l}\n${next}`)) { if (header !== null && header !== l) { table++; label = "" } header = l; headerCount++; continue }
      const parts = l.replace(/^\|\s*|\s*\|$/g, "").split(/\s*\|\s*/);
      const named = headOf.get(l);
      const hcells = header ? header.replace(/^\|\s*|\s*\|$/g, "").split(/\s*\|\s*/) : [];
      // a cell's column header by position on the header line (two cells may print the same words, "Not applicable"); the named form only where there is no header line
      const cells: ChunkCell[] = parts.map((c, j) => ({ head: hcells[j] ?? (hcells.length ? "" : named?.find((x) => x.c === c)?.h ?? ""), text: c, minimum: entryCellMinimum(c), qualification: null }));
      if (parts[0]) label = parts[0];
      chunks.push(make("table_row", table, header, label, l, cells)); tableRows++;
      continue;
    }
    if (inTable) { inTable = false; header = null; label = "" }
    const lm = LIST_LINE.exec(l);
    if (lm) {  // a labelled line is a requirement even when it is as short as a heading ("Brazil: Certificado de Ensino Medio")
      flushText();
      chunks.push(make("list_line", null, null, lm[1].trim(), l, [{ head: lm[1].trim(), text: lm[2].trim(), minimum: entryCellMinimum(lm[2]), qualification: null }])); listLines++;
      continue;
    }
    // a heading; a page title printed outside the tables may hold " | " ("China | Academic Entry Requirements") and is a heading all the same
    const titled = notRows.has(l) && l.length <= HEADING_CHARS * 2 && !/[.;,]$/.test(l);  // fixed: a title may join two headings
    if (isHeading(l) || titled) { flushText(); ctx.push(l); if (ctx.length > 12) ctx.shift(); continue }  // fixed: how far back headings are kept (only the nearest three are carried)
    textBuf.push(l);
  }
  flushText();
  return { text, chunks, tables: table + 1, tableRows, headerLines: headerCount, listLines, textBlocks, notRows };
}

// the rows of the page text that a chunk set must cover: every line of a table block that is not its header line. A chunk set is complete when each such line is the quote
// of exactly one table_row chunk (the S745 regression suite checks this on every stored page it carries).
export function entryChunkCoverage(set: EntryChunkSet, forms: string[] = [], notRows: Set<string> = set.notRows): { expected: number; covered: number; missing: string[]; doubled: string[] } {
  const formSet = new Set(forms.map((f) => f.split("\n").map((x) => x.trim()).join("\n")));
  const expected: string[] = [];
  let header: string | null = null, inTable = false;
  const all = set.text.split("\n");
  for (let i = 0; i < all.length; i++) {
    const l = all[i].trim(), next = (all[i + 1] || "").trim();
    if (!l || !isRow(l) || notRows.has(l)) { inTable = false; header = null; continue }
    if (!inTable) { inTable = true; header = null }
    if (formSet.has(`${l}\n${next}`)) { header = l; continue }
    expected.push(l);
  }
  const seen = new Map<string, number>();
  for (const c of set.chunks) if (c.kind === "table_row") seen.set(c.quote, (seen.get(c.quote) || 0) + 1);
  const want = new Map<string, number>(); for (const e of expected) want.set(e, (want.get(e) || 0) + 1);
  const missing = [...want.entries()].filter(([k, n]) => (seen.get(k) || 0) < n).map(([k]) => k);
  const doubled = [...seen.entries()].filter(([k, n]) => n > (want.get(k) || 0)).map(([k]) => k);
  return { expected: expected.length, covered: expected.length - missing.reduce((a, k) => a + (want.get(k)! - (seen.get(k) || 0)), 0), missing, doubled };
}

// the user message for one chunk (or a few chunks of one table): the headings, the header line and the rows, each with its number, so the model answers row by row and
// quotes within a row. The prompt and the pinned model are the caller's (AER v2 evaluation framework); this only lays the rows out.
export function entryChunkUser(provider: string, url: string, group: EntryChunk[]): string {
  if (!group.length) return "";
  const first = group[0];
  const lines = [`Provider: ${provider}`, `Page: ${url}`];
  if (first.context.length) lines.push(`Headings over these rows: ${first.context.join(" > ")}`);
  if (first.header) lines.push(`Table header: ${first.header}`);
  lines.push(`Rows (${group.length}); answer every row, quoting only within it:`);
  for (const c of group) lines.push(`[R${c.n}] ${c.quote}`);
  return lines.join("\n");
}

// chunks grouped for model calls: consecutive rows of one table (same headings and header), at most `per` rows in a group; a list line or text block is its own group
export function entryChunkGroups(chunks: EntryChunk[], per: number): EntryChunk[][] {
  const out: EntryChunk[][] = []; const n = Math.max(1, Math.floor(per) || 1);
  for (const c of chunks) {
    const g = out[out.length - 1];
    if (g && c.kind === "table_row" && g[0].kind === "table_row" && g[0].table === c.table && g.length < n) g.push(c); else out.push([c]);
  }
  return out;
}
