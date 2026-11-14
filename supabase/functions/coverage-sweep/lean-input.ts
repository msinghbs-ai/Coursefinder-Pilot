// CF-247 Lean AI Input, Phase 1 (Platform Admin 13 Nov 2026 22:51 "StudySearch — Lean AI Input and Evidence Optimisation"; admin
// docs/platform/SHARED-SOURCE-TO-PUBLISHED-ENRICHMENT-DESIGN.md §11, Phase 0 baseline docs/platform/LEAN-AI-INPUT-PHASE0-BASELINE-2026-11-13.md).
// Observe first, change nothing that admits: this module measures what each AI read is sent and what it is not sent. It never changes a
// request, never skips a read and never decides a value.
//   leanText      the stored page as structured text (lean-md-v1): headings kept as headings, every table row with its column headers,
//                 list items as items, each block with its offset in the text and in the stored page. Deterministic and local.
//   preflight     a HIGH-RECALL "could this text answer the field?" signal: likely / unknown / no_signal. Shadow only: recorded, never used
//                 to skip a read. "no_signal" is a candidate for measurement, not a finding that the page lacks the field.
//   observation   one row per read: how long the source text was, how much was sent, whether and where it was cut, the preflight on the
//                 text sent and on the whole page (a field signalled only beyond the cut is a possible false negative of the cut), the
//                 sent-input hash and the content/prompt/model/schema fingerprint for change-based re-reading.
// Page content is data: nothing here follows an instruction found on a page.

export const LEAN_CONVERTER = "lean-md-v2";  // never edited in place: a different conversion is a new version
// lean-md-v2 (14 Nov 2026, CF-247 S1-AER, Lean AI Phase 1b Run B recall audit: 20 of 51 entry requirement misses were score lines such as
// "70 Guaranteed ATAR or equivalent" lost in conversion). Changes from lean-md-v1, block line format unchanged:
//   1. the region is the page today's reader sends (the whole page without navigation, site header, footer and non-text), not <main> only and
//      not without <aside>: a course's key-facts panel (score, duration, campus) is often an <aside> or sits outside <main>;
//   2. numeric character references are decoded (&#8211; is a dash, not a space);
//   3. a short value-only line ("70", "80.0", "58.25 65.05") is kept with the score label printed next to it ("Guaranteed ATAR or equivalent"),
//      as one block: the label after it first, else the label before it; only a score label (ATAR, rank, score, GPA, IB, ...) is joined, so a
//      value never moves onto an unrelated line, and a value with no score label beside it stays a block of its own.
export const OBSERVATION_CONTRACT = "lean-input-observation-v1";

type Block = { kind: "heading" | "table_row" | "item" | "text"; text: string; start: number; end: number; source_at: number };
export type LeanText = { converter: string; text: string; blocks: Block[]; tables: number; table_rows: number };

const ENT: Record<string, string> = { "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'", "&rsquo;": "'", "&lsquo;": "'",
  "&ldquo;": '"', "&rdquo;": '"', "&ndash;": "-", "&mdash;": "-", "&#36;": "$", "&dollar;": "$" };
const decode = (s: string) => s.replace(/&[a-z#0-9]+;/gi, (m) => {
  const n = /^&#x([0-9a-f]+);$/i.exec(m) ? parseInt(m.slice(3, -1), 16) : /^&#([0-9]+);$/.exec(m) ? parseInt(m.slice(2, -1), 10) : NaN;
  if (Number.isFinite(n) && n > 0 && n <= 0x10ffff) { const ch = String.fromCodePoint(n); return /[\u2000-\u200b\u00a0]/.test(ch) ? " " : ch }  // v2: numeric references decoded
  return ENT[m.toLowerCase()] ?? " ";
});
// the visible words of a piece of markup, on one line
const words = (h: string) => decode(h.replace(/<br\s*\/?>/gi, " ").replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();

// the region of the page a reader reads (v2): the whole page, as today's reader sends it; navigation, site header and footer are blanked below
function bodyOf(html: string): { h: string; base: number } {
  return { h: html, base: 0 };
}
const blank = (s: string) => " ".repeat(s.length);  // keeps every offset into the stored page true

// one table: each body row as "Header: cell | Header: cell"; a row with no header names keeps its cells joined by " | "
function tableRows(t: string): string[] {
  const rows = [...t.matchAll(/<tr\b[\s\S]*?<\/tr>/gi)].map((r) => [...r[0].matchAll(/<(t[hd])\b[^>]*>([\s\S]*?)<\/\1>/gi)].map((c) => ({ th: c[1].toLowerCase() === "th", v: words(c[2]) })));
  if (!rows.length) return [];
  const headerRow = rows[0].length > 1 && rows[0].every((c) => c.th || c.v.length <= 80) && (rows[0].some((c) => c.th) || /<thead\b/i.test(t)) ? rows[0].map((c) => c.v) : null;
  const out: string[] = [];
  for (const r of headerRow ? rows.slice(1) : rows) {
    const cells = r.map((c, i) => headerRow && headerRow[i] && c.v ? `${headerRow[i]}: ${c.v}` : c.v).filter(Boolean);
    if (cells.length) out.push(cells.join(" | "));
  }
  if (headerRow && !out.length) out.push(headerRow.join(" | "));
  return out;
}


// v2: a short line that is only a value (a number, a few letters at most) and the score label printed beside it are one statement
const VALUE_ONLY_MAX = 20, LABEL_MAX = 200;  // fixed: the shape of a key-facts value and its label, not an operational limit
const valueOnly = (t: string) => t.length <= VALUE_ONLY_MAX && /\d/.test(t) && (t.match(/[a-z]/gi) || []).length <= 3;
const SCORE_LABEL = /\b(atar|selection rank|rank|entry score|score|gpa|ib|minimum|guaranteed|lowest|threshold|points?|band|grade|ncea|percent|%)\b|%/i;
const labelFor = (b: Block | undefined) => !!b && (b.kind === "text" || b.kind === "item") && b.text.length <= LABEL_MAX && !valueOnly(b.text) && SCORE_LABEL.test(b.text);
function keepScoreLines(blocks: Block[]): Block[] {
  const out: Block[] = [];
  let labelText: string | null = null;  // the label words of the last block when values were added after it ("Lowest rank to receive an offer" + "58.25" + "65.05")
  for (let i = 0; i < blocks.length; i++) {
    const b = blocks[i];
    if (b.kind === "text" && valueOnly(b.text)) {
      const next = blocks[i + 1], prev = out[out.length - 1];
      if (labelFor(next)) { blocks[i + 1] = { ...next, text: `${b.text} ${next.text}`, source_at: b.source_at }; labelText = null; continue }  // "70" + "Guaranteed ATAR or equivalent"
      const label = labelText ?? prev?.text ?? "";
      if (prev && labelFor({ ...prev, text: label }) && !/\d/.test(label)) { out[out.length - 1] = { ...prev, text: `${prev.text} ${b.text}` }; labelText = label; continue }  // "Guaranteed ATAR" + "70"
    }
    out.push({ ...b }); labelText = null;
  }
  return out;
}

export function leanText(html: string): LeanText {
  const { h: body, base } = bodyOf(String(html || ""));
  // remove what is never page text, keeping offsets (blanked, not cut)
  let h = body.replace(/<(script|style|noscript|svg|template|nav|header|footer)\b[\s\S]*?<\/\1>/gi, blank).replace(/<!--[\s\S]*?-->/g, blank);  // v2: <aside> kept
  const blocks: Block[] = [];
  let text = "", tables = 0, tableRowsN = 0;
  const push = (kind: Block["kind"], t: string, at: number) => {
    const s = t.replace(/\s+/g, " ").trim(); if (!s) return;
    const line = kind === "heading" ? `## ${s}` : kind === "item" ? `- ${s}` : s;
    const start = text.length; text += (text ? "\n" : "") + line;
    blocks.push({ kind, text: s, start: start + (start ? 1 : 0), end: text.length, source_at: base + at });
  };
  // tables, headings, list items and paragraphs, in page order
  const re = /<table\b[\s\S]*?<\/table>|<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>|<li\b[^>]*>([\s\S]*?)<\/li>|<(p|dd|dt|div|section)\b[^>]*>/gi;
  let last = 0, m: RegExpExecArray | null;
  const flushText = (to: number) => { if (to > last) { const w = words(h.slice(last, to)); if (w) push("text", w, last) } };
  while ((m = re.exec(h))) {
    const tag = m[0];
    if (/^<table\b/i.test(tag)) {
      flushText(m.index); tables++;
      for (const row of tableRows(tag)) { push("table_row", row, m.index); tableRowsN++ }
      last = m.index + tag.length;
    } else if (m[1]) { flushText(m.index); push("heading", words(m[2]), m.index); last = m.index + tag.length }
    else if (m[3] !== undefined && !/<(ul|ol|li|table)\b/i.test(m[3])) { flushText(m.index); push("item", words(m[3]), m.index); last = m.index + tag.length }
    else if (/^<(p|dd|dt|div|section)\b/i.test(tag)) { flushText(m.index); last = m.index }
  }
  flushText(h.length);
  // v2: a value-only line is kept with the score label beside it, then the text is laid out again (offsets into the stored page unchanged)
  const kept = keepScoreLines(blocks);
  let out = "";
  for (const b of kept) {
    const line = b.kind === "heading" ? `## ${b.text}` : b.kind === "item" ? `- ${b.text}` : b.text;
    const start = out.length + (out ? 1 : 0); out += (out ? "\n" : "") + line; b.start = start; b.end = out.length;
  }
  return { converter: LEAN_CONVERTER, text: out, blocks: kept, tables, table_rows: tableRowsN };
}

// fc-md-v1 (worker v1.0.0, Platform Admin 15 Nov 2026 00:23): the same structured text built from Firecrawl's own markdown of the page, kept beside
// the stored HTML (<name>.md.gz) since worker v0.99.0. Same block kinds and line format as lean-md-v2 (headings "## ", items "- ", table rows
// "Header: cell | Header: cell"), the markdown syntax taken out so a quote is the page's own words: links keep their text, images go, emphasis
// and inline code marks go. source_at is the offset in the markdown. Used only when reading.markdown_input is on and the markdown file exists;
// otherwise lean-md-v2 converts the stored HTML, as before.
export const MD_CONVERTER = "fc-md-v1";  // never edited in place: a different conversion is a new version
export function mdPlain(s: string): string {
  return String(s || "")
    .replace(/!\[[^\]]*\]\([^)]*\)/g, " ")                    // images
    .replace(/\[([^\]]*)\]\((?:[^()]|\([^)]*\))*\)/g, "$1")      // links keep their text
    .replace(/<[^>]+>/g, " ")                                  // stray markup
    .replace(/(\*\*|__)(.+?)\1/g, "$2").replace(/(^|[\s(])[*_]([^*_\n]+)[*_](?=[\s).,;:!?]|$)/g, "$1$2")  // emphasis
    .replace(/`([^`]*)`/g, "$1").replace(/\\([\\`*_{}\[\]()#+\-.!|])/g, "$1")  // inline code, escapes
    .replace(/\s+/g, " ").trim();
}
const cells = (row: string) => row.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => mdPlain(c));
export function leanTextFromMarkdown(md: string): LeanText {
  const lines = String(md || "").split("\n");
  const blocks: Block[] = [];
  let tables = 0, tableRowsN = 0, at = 0, para: string[] = [], paraAt = 0;
  const push = (kind: Block["kind"], t: string, src: number) => { const s = mdPlain(t); if (s) blocks.push({ kind, text: s, start: 0, end: 0, source_at: src }) };
  const flush = () => { if (para.length) push("text", para.join(" "), paraAt); para = [] };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i], t = line.trim(), here = at; at += line.length + 1;
    if (!t || /^(-{3,}|\*{3,}|_{3,})$/.test(t) || /^```/.test(t)) { flush(); continue }
    let m: RegExpExecArray | null;
    if ((m = /^#{1,6}\s+(.*)$/.exec(t))) { flush(); push("heading", m[1].replace(/\s#+$/, ""), here); continue }
    if (/^\|.*\|$/.test(t)) {  // a table: header row, separator row, body rows
      flush(); tables++;
      const rows: { c: string[]; at: number }[] = [{ c: cells(t), at: here }];
      while (i + 1 < lines.length && /^\s*\|.*\|\s*$/.test(lines[i + 1])) { i++; rows.push({ c: cells(lines[i]), at }); at += lines[i].length + 1 }
      const sep = rows.length > 1 && rows[1].c.every((c) => /^:?-{2,}:?$/.test(c.replace(/\s/g, "")) || c === "");
      const head = sep ? rows[0].c : null, body = sep ? rows.slice(2) : rows;
      for (const r of body) {
        const out = r.c.map((c, k) => head && head[k] && c ? `${head[k]}: ${c}` : c).filter(Boolean);
        if (out.length) { push("table_row", out.join(" | "), r.at); tableRowsN++ }
      }
      if (head && !body.length) push("table_row", head.filter(Boolean).join(" | "), rows[0].at);
      continue;
    }
    if ((m = /^(?:[-*+]|\d+[.)])\s+(.*)$/.exec(t))) { flush(); push("item", m[1], here); continue }
    if (!para.length) paraAt = here;
    para.push(t.replace(/^>\s?/, ""));
  }
  flush();
  const kept = keepScoreLines(blocks);
  let out = "";
  for (const b of kept) {
    const line = b.kind === "heading" ? `## ${b.text}` : b.kind === "item" ? `- ${b.text}` : b.text;
    const start = out.length + (out ? 1 : 0); out += (out ? "\n" : "") + line; b.start = start; b.end = out.length;
  }
  return { converter: MD_CONVERTER, text: out, blocks: kept, tables, table_rows: tableRowsN };
}

// High-recall signals per field. A word list can miss a page (tables, aliases, implicit headings), so the verdict is three-way and only
// "likely" is a positive claim; "no_signal" means no signal was seen, never "the page does not state it".
const MONTH = "jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|june?|july?|aug(ust)?|sep(t(ember)?)?|oct(ober)?|nov(ember)?|dec(ember)?";
const SIGNALS: Record<string, { strong: RegExp; weak?: RegExp; always?: boolean }> = {
  deadline: { strong: /\b(deadlines?|closing dates?|closes?|closed|apply by|applications? (are )?(open|close|due)|due dates?|last date|cut-?off|rolling (admissions?|basis|intake)|key dates|important dates|round \d)\b/i,
    weak: new RegExp(`\\b\\d{1,2}(st|nd|rd|th)?\\s+(${MONTH})\\b|\\b(${MONTH})\\s+\\d{1,2}\\b|\\b\\d{1,2}[/.-]\\d{1,2}[/.-]\\d{2,4}\\b|\\bapplications?\\b|\\bapply\\b`, "i") },
  intakes: { strong: new RegExp(`\\b(intakes?|start dates?|commenc\\w*|starting|starts? (in|from)|semester\\s*(\\d|one|two)|trimester\\s*(\\d|one|two|three)|term\\s*\\d|study period)\\b`, "i"),
    weak: new RegExp(`\\b(${MONTH})\\b|\\bstart\\b`, "i") },
  english: { strong: /\b(ielts|toefl|pte|duolingo|cambridge (english|c1|c2)|oet|celpip|english language (requirements?|proficiency)|english proficiency)\b/i, weak: /\benglish\b/i },
  entry_requirements: { strong: /\b(entry requirements?|admission requirements?|prerequisites?|atar|gpa|selection rank|minimum (entry|score|grade)|academic requirements?|eligibility)\b/i,
    weak: /\b(requirements?|qualifications?|admission|entry|equivalent)\b/i },
  duration: { strong: /\b\d+(\.\d+)?\s*(years?|yrs?|months?|weeks?|semesters?|trimesters?)\b|\b(one|two|three|four|five|six)\s+(years?|months?|semesters?|trimesters?)\b/i, weak: /\b(full-?time|part-?time|duration|length)\b/i },
  campus: { strong: /\b(campus(es)?|location|study at|taught at|delivered at)\b/i, weak: /\b(city|online|centre|center)\b/i },
  delivery: { strong: /\b(online|on campus|on-campus|face[- ]to[- ]face|blended|in person|distance|delivery mode|mode of (study|delivery)|study mode)\b/i, weak: /\b(delivery|mode|attendance)\b/i },
  international: { strong: /\binternational (students?|applicants?|fees?|tuition)\b|\bcricos\b|\bstudent visa\b/i, weak: /\binternational\b/i },
  description: { strong: /\S/, always: true },
  level: { strong: /\S/, always: true },
  field_of_study: { strong: /\S/, always: true },
};
export type Preflight = "likely" | "unknown" | "no_signal" | "not_measured";
export function preflight(field: string, text: string): Preflight {
  const s = SIGNALS[field]; if (!s) return "not_measured";
  const t = String(text || "");
  if (s.always) return t.trim().length >= 200 ? "likely" : "unknown";
  if (s.strong.test(t)) return "likely";
  if (s.weak && s.weak.test(t)) return "unknown";
  return "no_signal";
}

export async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
// change-based re-reading key: the same text, field, prompt, model and answer shape give the same fingerprint
export async function fingerprint(p: { input_sha256: string; field: string; prompt_key: string; model: string; schema_key: string }): Promise<string> {
  return sha256Hex([OBSERVATION_CONTRACT, p.input_sha256, p.field, p.prompt_key, p.model, p.schema_key].join("␟"));
}

export type ObservationInput = { read: string; field: string; item_id: number; course_id?: string | null; storage_path?: string | null;
  source_text: string; sent_text: string; limit_chars: number | null; lean: LeanText; prompt_key: string; model: string; schema_key: string; worker: string };
export async function observation(o: ObservationInput, sourceSha: string) {
  const src = String(o.source_text || ""), sent = String(o.sent_text || "");
  const cut = sent.length < src.length;
  const inputSha = await sha256Hex(sent);
  return {
    contract: OBSERVATION_CONTRACT, worker: o.worker.slice(0, 60), read: o.read, field: o.field, item_id: o.item_id, course_id: o.course_id ?? null,
    storage_path: o.storage_path ?? null, source_sha256: sourceSha, converter: o.lean.converter,
    source_chars: src.length, sent_chars: sent.length, limit_chars: o.limit_chars, cut, cut_at: cut ? sent.length : null,
    lean_chars: o.lean.text.length, lean_tables: o.lean.tables, lean_table_rows: o.lean.table_rows,
    preflight_sent: preflight(o.field, sent), preflight_full: preflight(o.field, o.lean.text + "\n" + src),
    prompt_key: o.prompt_key.slice(0, 120), model: o.model.slice(0, 120), schema_key: o.schema_key.slice(0, 120),
    input_sha256: inputSha, fingerprint: await fingerprint({ input_sha256: inputSha, field: o.field, prompt_key: o.prompt_key, model: o.model, schema_key: o.schema_key }),
  };
}
