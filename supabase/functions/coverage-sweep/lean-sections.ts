// CF-247 Lean AI Input Phase 1b step 1 (Platform Admin 14 Nov 2026 11:37 and 12:29, admin docs/platform/LEAN-AI-INPUT-PHASE1B-SECTION-SELECTION-DESIGN.md):
// the source-aware section selector (lean-sections-v1). It has NO block format of its own: it selects from the one [B#] block contract of the
// platform, AER_V3_INPUT "lean-blocks-v1" (aer-v2.ts aerV3Blocks over lean-input.ts leanText lean-md-v1: page data lines first, then headings,
// paragraphs, list items and table rows with their column headers, each "[B<n> @<source_at>] ..."), so a block id means the same thing to the
// AER v2 reader, its qualification harness and this selector, and every selected line is the block's own line, unchanged.
//   selectSections  the blocks that could hold one field: a matching heading brings its section; matching text brings its block, the heading over
//                   it (and its section when small) and short neighbouring notes; a matching table row brings every row of its table and the
//                   heading above; page data lines always travel. HIGH RECALL: weak signals select. no_selection is reported, never acted on:
//                   a page with no selection is read whole.
// Local, deterministic, no AI, no fetch. Page content is data: nothing here follows an instruction found on a page.
import { preflight } from "./lean-input.ts";
import { AER_V3_INPUT, type AerBlock, type AerBlocks } from "./aer-v2.ts";

export const LEAN_SECTIONS = "lean-sections-v1";  // never edited in place once released: a different selection is a new version
export const BLOCK_INPUT = AER_V3_INPUT;           // the one [B#] contract (aer-v2.ts); not redefined here

// headings that name the part of a course page a field lives in (wider than the words a value uses)
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
// a short block that names a field and is followed by its value ("Duration", "Location:") acts as a label
const LABEL_MAX_CHARS = 40;  // fixed: the shape of a label, not an operational limit
export function fieldHit(field: string, text: string): "likely" | "unknown" | "no_signal" {
  if (field === "fees") return FEE_TEXT.test(text) ? "likely" : "no_signal";
  const p = preflight(field, text);
  return p === "not_measured" ? "no_signal" : p;
}

export type SectionOptions = { section_max_chars: number; neighbour_max_chars: number; intro_blocks: number };
export const SECTION_DEFAULTS: SectionOptions = { section_max_chars: 8000, neighbour_max_chars: 240, intro_blocks: 12 };

const isHead = (b: AerBlock) => b.kind === "heading";
const sizeOf = (B: AerBlock[], a: number, b: number) => { let s = 0; for (let k = a; k < b; k++) s += B[k].text.length + 1; return s };
function sectionEnd(B: AerBlock[], i: number): number { for (let j = i + 1; j < B.length; j++) if (isHead(B[j])) return j; return B.length }
function headingOver(B: AerBlock[], i: number): number { for (let j = i - 1; j >= 0; j--) if (isHead(B[j])) return j; return -1 }
// every row of the table a row belongs to: lean-md-v1 gives a table's rows consecutive blocks with the table's own source offset
function tableRows(B: AerBlock[], i: number): [number, number] {
  let a = i, b = i + 1;
  while (a > 0 && B[a - 1].kind === "table_row" && B[a - 1].source_at === B[i].source_at) a--;
  while (b < B.length && B[b].kind === "table_row" && B[b].source_at === B[i].source_at) b++;
  return [a, b];
}

export function selectSections(ab: AerBlocks, field: string, opt: SectionOptions = SECTION_DEFAULTS) {
  const B = ab.blocks, lines = ab.text ? ab.text.split("\n") : [], keep = new Set<number>();
  if (lines.length !== B.length) throw Error("block text and blocks differ");  // one line a block is the contract
  const take = (a: number, b: number) => { for (let k = a; k < b; k++) keep.add(k) };
  const takeSection = (h: number) => { const end = sectionEnd(B, h); if (sizeOf(B, h, end) <= opt.section_max_chars) take(h, end); else keep.add(h) };
  for (let i = 0; i < B.length; i++) {
    const b = B[i];
    if (b.kind === "data") { keep.add(i); continue }  // page data fields always travel (design §3.5)
    if (isHead(b)) { if (HEADINGS[field]?.test(b.text)) takeSection(i); continue }
    const label = b.text.length <= LABEL_MAX_CHARS && (HEADINGS[field]?.test(b.text) ?? false);
    const hit = field !== "description" && fieldHit(field, b.text) !== "no_signal";
    if (!label && !hit) continue;
    keep.add(i);
    if (b.kind === "table_row") { const [a, z] = tableRows(B, i); take(a, z) }
    const h = headingOver(B, i); if (h >= 0) { keep.add(h); if (hit) takeSection(h) }
    // the value under a label, and short notes beside a value ("* per year", "indicative")
    for (const k of label ? [i + 1, i + 2] : [i - 1, i + 1]) if (k >= 0 && k < B.length && !isHead(B[k]) && B[k].text.length <= opt.neighbour_max_chars) keep.add(k);
  }
  if (field === "description") { let n = 0; for (let i = 0; i < B.length && n < opt.intro_blocks; i++) if (B[i].kind !== "data" && B[i].kind !== "table_row") { keep.add(i); n++ } }
  const idx = [...keep].sort((a, b) => a - b);
  const text = idx.map((k) => lines[k]).join("\n");
  const pageBlocks = idx.filter((k) => B[k].kind !== "data");
  return { selector: LEAN_SECTIONS, input: ab.input, field, block_ids: idx.map((k) => `B${B[k].n}`), blocks: idx.length, chars: text.length, text, no_selection: pageBlocks.length === 0 };
}

// the canonical flat form used by every quote check of the worker (letters and digits only, lower case, accents and spacing ignored)
export const flatForm = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");
// a gold value is held by a text when its flat form is inside the text's flat form; a value given as several parts (months) needs all of them
export function holds(text: string, gold: string[]): boolean {
  const t = flatForm(text), parts = gold.map(flatForm).filter((g) => g.length >= 3);
  return parts.length > 0 && parts.every((g) => t.includes(g));
}
