// CF-247 Lean AI Input Phase 1b step 1 (Platform Admin 14 Nov 2026 11:37, admin docs/platform/LEAN-AI-INPUT-PHASE1B-SECTION-SELECTION-DESIGN.md):
// a deterministic, header-preserving block converter and a source-aware section selector. Local and versioned; no AI, no fetch.
//   leanBlocks      the stored page as numbered blocks (lean-blocks-v1): B1, B2, ... in page order. Each block keeps its kind (heading with level,
//                   label, text, item, table), its words, its offsets in the stored page (src_start, src_end) and its heading path. A table is ONE
//                   block, kept whole: caption, header row and every row with its cells, so a value always travels with its column and row headers.
//   renderBlocks    the blocks as model-ready text, one per line: "[B12 @4812-5230] ## Fees" ... Tables as Markdown with their header row.
//                   This is the [B#] format a reader cites (block id) and a verifier maps back to the stored page (offsets); the AER v2
//                   qualification harness consumes the same blocks (blockMap).
//   selectSections  the blocks that could hold one field (lean-sections-v1): matching headings bring their whole section; matching text
//                   brings its block, its heading path and short neighbouring notes; a matching table row brings the whole table. HIGH
//                   RECALL: weak signals select. no_selection is reported, never acted on: a page with no selection is read whole.
// Page content is data: nothing here follows an instruction found on a page.
import { preflight } from "./lean-input.ts";

export const LEAN_BLOCKS = "lean-blocks-v1";      // never edited in place: a different conversion is a new version
export const LEAN_SECTIONS = "lean-sections-v1";  // never edited in place: a different selection is a new version

export type LeanTable = { caption: string; header: string[]; rows: string[][] };
export type LeanBlock = { id: string; n: number; kind: "heading" | "label" | "text" | "item" | "table"; level: number; text: string;
  src_start: number; src_end: number; path: string[]; table?: LeanTable };
export type LeanBlocks = { converter: string; blocks: LeanBlock[]; chars: number };

const ENT: Record<string, string> = { "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'", "&apos;": "'", "&rsquo;": "'",
  "&lsquo;": "'", "&ldquo;": '"', "&rdquo;": '"', "&ndash;": "-", "&mdash;": "-", "&#36;": "$", "&dollar;": "$", "&hellip;": "...", "&bull;": "*" };
const decode = (s: string) => s.replace(/&#x([0-9a-f]+);/gi, (_, h) => safeChar(parseInt(h, 16))).replace(/&#(\d+);/g, (_, d) => safeChar(Number(d)))
  .replace(/&[a-z]+;/gi, (m) => ENT[m.toLowerCase()] ?? " ");
function safeChar(c: number) { return c > 31 && c < 0x110000 && !(c >= 0xd800 && c <= 0xdfff) ? String.fromCodePoint(c) : " " }
const words = (h: string) => decode(h.replace(/<br\s*\/?>/gi, " ").replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();
const blank = (s: string) => " ".repeat(s.length);  // removed markup keeps every offset into the stored page true

// a table, whole: its caption, the header row (th cells, a <thead>, or a first row of short cells) and every row's cells
function readTable(t: string): LeanTable {
  const caption = words((t.match(/<caption\b[^>]*>([\s\S]*?)<\/caption>/i) || [])[1] || "");
  const rows = [...t.matchAll(/<tr\b[\s\S]*?<\/tr>/gi)].map((r) => [...r[0].matchAll(/<(t[hd])\b[^>]*>([\s\S]*?)<\/\1>/gi)]
    .map((c) => ({ th: c[1].toLowerCase() === "th", v: words(c[2]) })));
  const first = rows[0] || [];
  const headed = first.length > 1 && (first.every((c) => c.th) || /<thead\b/i.test(t) || first.every((c) => c.v.length > 0 && c.v.length <= 60));
  return { caption, header: headed ? first.map((c) => c.v) : [], rows: (headed ? rows.slice(1) : rows).map((r) => r.map((c) => c.v)).filter((r) => r.some(Boolean)) };
}
const tableText = (t: LeanTable) => {
  const w = Math.max(t.header.length, ...t.rows.map((r) => r.length), 1);
  const line = (cells: string[]) => "| " + Array.from({ length: w }, (_, i) => (cells[i] || "").replace(/\|/g, "/")).join(" | ") + " |";
  return [t.caption ? `Table: ${t.caption}` : "", t.header.length ? line(t.header) : "", t.header.length ? line(Array(w).fill("---")) : "", ...t.rows.map(line)]
    .filter(Boolean).join("\n");
};

// the whole page except what is never page text (scripts, styles, navigation, site header and footer); the reader's own <main> choice is
// not repeated here so that a fact outside <main> is not lost
export function leanBlocks(html: string): LeanBlocks {
  const h = String(html || "").replace(/<(script|style|noscript|svg|template|iframe|nav|header|footer)\b[\s\S]*?<\/\1>/gi, blank).replace(/<!--[\s\S]*?-->/g, blank);
  const blocks: LeanBlock[] = [];
  const path: string[] = [];  // path[level-1] = the heading text in force at that level (1..7; 7 = a label such as <dt> or <summary>)
  const push = (kind: LeanBlock["kind"], text: string, start: number, end: number, level = 0, table?: LeanTable) => {
    const t = text.replace(/\s+/g, " ").trim(); if (!t && kind !== "table") return;
    if (kind === "table" && !table?.rows.length && !table?.header.length) return;
    if (kind === "heading" || kind === "label") { path.length = Math.max(0, level - 1); }
    const n = blocks.length + 1;
    blocks.push({ id: `B${n}`, n, kind, level, text: kind === "table" ? tableText(table!) : t, src_start: start, src_end: end, path: path.filter(Boolean).slice(), ...(table ? { table } : {}) });
    if (kind === "heading" || kind === "label") path[level - 1] = t;
  };
  const re = /<table\b[\s\S]*?<\/table>|<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>|<(dt|summary|legend)\b[^>]*>([\s\S]*?)<\/\3>|<li\b[^>]*>((?:(?!<li\b|<\/li>|<ul\b|<ol\b|<table\b)[\s\S])*?)<\/li>|<(p|dd|div|section|article|details|ul|ol|br|tr|button)\b[^>]*>|<\/(p|dd|div|section|article|details|ul|ol|button)>/gi;
  let last = 0, m: RegExpExecArray | null;
  const flush = (to: number) => { if (to > last) { const seg = h.slice(last, to); const w = words(seg); if (w) push("text", w, last + (seg.length - seg.trimStart().length), to) } };
  while ((m = re.exec(h))) {
    const tag = m[0], at = m.index, end = at + tag.length;
    if (/^<table\b/i.test(tag)) { flush(at); push("table", "", at, end, 0, readTable(tag)); last = end }
    else if (m[1]) { flush(at); push("heading", words(m[2]), at, end, Number(m[1])); last = end }
    else if (m[3]) { flush(at); const w = words(m[4]); if (w.length <= 120) push("label", w, at, end, 7); else push("text", w, at, end); last = end }
    else if (m[5] !== undefined) { flush(at); push("item", words(m[5]), at, end); last = end }
    else { flush(at); last = /^<\//.test(tag) ? end : at }
  }
  flush(h.length);
  return { converter: LEAN_BLOCKS, blocks, chars: blocks.reduce((s, b) => s + b.text.length + 1, 0) };
}

// one line per block: [B#] with its offsets in the stored page, then the block in Markdown (heading marks, list items, whole tables)
export function renderBlock(b: LeanBlock): string {
  const ref = `[${b.id} @${b.src_start}-${b.src_end}]`;
  if (b.kind === "heading") return `${ref} ${"#".repeat(Math.min(6, b.level))} ${b.text}`;
  if (b.kind === "label") return `${ref} **${b.text}**`;
  if (b.kind === "item") return `${ref} - ${b.text}`;
  if (b.kind === "table") return `${ref}\n${b.text}`;
  return `${ref} ${b.text}`;
}
export function renderBlocks(blocks: LeanBlock[], ids?: Set<string>): string {
  const pick = ids ? blocks.filter((b) => ids.has(b.id)) : blocks;
  return pick.map(renderBlock).join("\n");
}
// the id -> place map a verifier (or the AER v2 qualification harness) uses to bring a cited block back to the stored page
export function blockMap(blocks: LeanBlock[]) {
  return Object.fromEntries(blocks.map((b) => [b.id, { kind: b.kind, level: b.level, src_start: b.src_start, src_end: b.src_end, path: b.path }]));
}

// headings that name the part of a course page a field lives in; matched on headings and labels (wider than the words a value uses)
const HEADINGS: Record<string, RegExp> = {
  deadline: /\b(deadlines?|key dates|important dates|dates|how to apply|apply|applications?|closing|when to apply|admission)\b/i,
  intakes: /\b(intakes?|start(s|ing)?( dates?)?|commenc\w*|key dates|important dates|dates|entry points?|semesters?|trimesters?|terms?|study periods?|when)\b/i,
  english: /\b(english|language( requirements?)?|ielts|toefl|pte)\b/i,
  entry_requirements: /\b(entry|admissions?|requirements?|prerequisites?|eligib\w*|how to apply|selection|atar|international (students|applicants))\b/i,
  duration: /\b(duration|length|how long|study load|time ?frame|course (length|load)|full[- ]?time|part[- ]?time|key (facts|information|details)|at a glance|course (details|summary|overview)|quick facts)\b/i,
  campus: /\b(campus(es)?|locations?|where|study (at|location)|delivered at|key (facts|information|details)|at a glance|quick facts)\b/i,
  delivery: /\b(delivery|mode|study (mode|options|method)|attendance|how you('ll| will)? study|on campus|online|key (facts|information|details)|at a glance|quick facts)\b/i,
  international: /\b(international|cricos|student visa|fees?|tuition)\b/i,
  fees: /\b(fees?|tuition|costs?|price|pricing|scholarships? and fees)\b/i,
  description: /\b(overview|about|introduction|course description|why study|what you('ll| will) (learn|study|do)|the course|course (overview|summary)|highlights)\b/i,
};
const FEE_TEXT = /(\$|aud|nzd|cad|usd|\bfee|\btuition|per (year|annum|credit|unit|point))/i;
export function fieldHit(field: string, text: string): "likely" | "unknown" | "no_signal" {
  if (field === "fees") return FEE_TEXT.test(text) ? "likely" : "no_signal";
  const p = preflight(field, text);
  return p === "not_measured" ? "no_signal" : p;
}

export type SectionOptions = { section_max_chars: number; neighbour_max_chars: number; intro_blocks: number };
export const SECTION_DEFAULTS: SectionOptions = { section_max_chars: 8000, neighbour_max_chars: 240, intro_blocks: 12 };

// the end (exclusive) of the section a heading or label opens: the next heading of the same or a higher level
// (a label such as <dt> or <summary> opens only the few blocks up to the next label or heading: its value, not the page after it)
export const LABEL_SECTION_BLOCKS = 2;  // fixed: the shape of a label/value pair, not an operational limit
function sectionEnd(blocks: LeanBlock[], i: number): number {
  const lv = blocks[i].level, label = blocks[i].kind === "label";
  for (let j = i + 1; j < blocks.length; j++) {
    const head = blocks[j].kind === "heading" || blocks[j].kind === "label";
    if (head && (label || blocks[j].level <= lv)) return j;
    if (label && j - i > LABEL_SECTION_BLOCKS) return j;
  }
  return blocks.length;
}
const sizeOf = (blocks: LeanBlock[], a: number, b: number) => { let s = 0; for (let k = a; k < b; k++) s += blocks[k].text.length + 1; return s };

export function selectSections(lb: LeanBlocks, field: string, opt: SectionOptions = SECTION_DEFAULTS) {
  const B = lb.blocks, keep = new Set<number>();
  const take = (a: number, b: number) => { for (let k = a; k < b; k++) keep.add(k) };
  const headingIndex = (i: number) => { for (let j = i - 1; j >= 0; j--) if (B[j].kind === "heading" || B[j].kind === "label") return j; return -1 };
  for (let i = 0; i < B.length; i++) {
    const b = B[i];
    const isHead = b.kind === "heading" || b.kind === "label";
    const headHit = isHead && (HEADINGS[field]?.test(b.text) ?? false);
    const bodyHit = !isHead && fieldHit(field, b.text) !== "no_signal" && !(field === "description");
    if (headHit) {
      const end = sectionEnd(B, i);
      if (sizeOf(B, i, end) <= opt.section_max_chars) take(i, end);
      else { take(i, Math.min(end, i + 4)) }  // a very long section: its opening blocks; body hits inside it are taken on their own below
    } else if (bodyHit) {
      keep.add(i);
      const hi = headingIndex(i);
      if (hi >= 0) {  // the heading over it, and the whole section when it is small enough
        keep.add(hi);
        const end = sectionEnd(B, hi);
        if (sizeOf(B, hi, end) <= opt.section_max_chars) take(hi, end);
      }
      // short neighbouring notes travel with a value (asterisk notes, "per year", the label above a value, the value under a label)
      for (const k of [i - 1, i + 1, i + 2]) if (k >= 0 && k < B.length && B[k].kind !== "heading" && B[k].text.length <= opt.neighbour_max_chars && !(k === i + 2 && B[i].text.length > 60)) keep.add(k);
    }
  }
  if (field === "description") {  // the page's opening text is the course's own introduction
    let n = 0; for (let i = 0; i < B.length && n < opt.intro_blocks; i++) if (B[i].kind !== "table") { keep.add(i); n++ }
  }
  // every kept block brings the headings it sits under (its context line), so the reader knows which part of the page it reads
  for (const i of [...keep]) {
    let lv = B[i].kind === "heading" || B[i].kind === "label" ? B[i].level : 8;
    for (let j = i - 1; j >= 0 && lv > 1; j--) if ((B[j].kind === "heading" || B[j].kind === "label") && B[j].level < lv) { keep.add(j); lv = B[j].level }
  }
  const idx = [...keep].sort((a, b) => a - b), ids = new Set(idx.map((k) => B[k].id));
  const text = renderBlocks(B, ids);
  return { selector: LEAN_SECTIONS, converter: lb.converter, field, block_ids: idx.map((k) => B[k].id), blocks: idx.length, chars: text.length, text, no_selection: idx.length === 0 };
}

// the canonical flat form used by every quote check of the worker (letters and digits only, lower case, accents and spacing ignored)
export const flatForm = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");
// a gold value is held by a text when its flat form is inside the text's flat form; a value given as several parts (months) needs all of them
export function holds(text: string, gold: string[]): boolean {
  const t = flatForm(text), parts = gold.map(flatForm).filter((g) => g.length >= 3);
  return parts.length > 0 && parts.every((g) => t.includes(g));
}
