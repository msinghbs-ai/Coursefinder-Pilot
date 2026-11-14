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

export const LEAN_CONVERTER = "lean-md-v1";  // never edited in place: a different conversion is a new version
export const OBSERVATION_CONTRACT = "lean-input-observation-v1";

type Block = { kind: "heading" | "table_row" | "item" | "text"; text: string; start: number; end: number; source_at: number };
export type LeanText = { converter: string; text: string; blocks: Block[]; tables: number; table_rows: number };

const ENT: Record<string, string> = { "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'", "&rsquo;": "'", "&lsquo;": "'",
  "&ldquo;": '"', "&rdquo;": '"', "&ndash;": "-", "&mdash;": "-", "&#36;": "$", "&dollar;": "$" };
const decode = (s: string) => s.replace(/&[a-z#0-9]+;/gi, (m) => ENT[m.toLowerCase()] ?? " ");
// the visible words of a piece of markup, on one line
const words = (h: string) => decode(h.replace(/<br\s*\/?>/gi, " ").replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();

// the region of the page a reader reads: <main> when it is a real body, without navigation, header, footer and side panels
function bodyOf(html: string): { h: string; base: number } {
  const m = html.match(/<main[\s\S]*?<\/main>/i);
  const useMain = !!m && m[0].length > 1500;
  return { h: useMain ? m![0] : html, base: useMain ? m!.index! : 0 };
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

export function leanText(html: string): LeanText {
  const { h: body, base } = bodyOf(String(html || ""));
  // remove what is never page text, keeping offsets (blanked, not cut)
  let h = body.replace(/<(script|style|noscript|svg|template|nav|header|footer|aside)\b[\s\S]*?<\/\1>/gi, blank).replace(/<!--[\s\S]*?-->/g, blank);
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
  return { converter: LEAN_CONVERTER, text, blocks, tables, table_rows: tableRowsN };
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
