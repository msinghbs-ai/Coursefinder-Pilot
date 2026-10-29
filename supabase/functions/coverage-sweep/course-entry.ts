// v0.53.0 (29 Oct 2026, CF-247 AER decision W29: course-level reading of long pages in bounded slices). The course entry-requirements read
// (worker mode enrich_ai, field entry_requirements, Layer 4 'course_entry_first_read') sent a course page of up to entry.course_page_chars
// characters in one call whose answer was limited to a fixed 2,000 tokens. Three Monash pages that publish a long per-country minimum list
// (M3008, M2019, S2000) answered past the limit; the cut answer was parsed as JSON ("Unterminated string in JSON at position 8,061 to
// 8,598"), was retried at the same size and failed, with the cost of the calls not recorded. The provider entry-matrix reader already reads
// long pages in slices (entrySlices, entry.matrix_slice_concurrency, entry.ts); the course read now does the same, with these rules:
//   coverage:     the page text is cut into contiguous slices of the stored text (each slice is the page's own characters, start and end
//                 recorded); together they cover the whole text with no gap. A page longer than entry.course_page_chars, or one needing more
//                 than enrich.course_entry_max_slices slices, is held before any AI call (never read in part).
//   every slice:  one call to the pinned entry model, answer limited by enrich.course_entry_max_tokens. An answer that reached the limit
//                 (finish_reason length), an empty answer or one that is not JSON fails that slice, named.
//   quotes:       a row is kept only when its quote is on its own slice (and so on the page), as before.
//   completeness: the read is complete only when every slice was read and answered whole. Anything else holds the whole read (no row is
//                 proposed from a partial read) with the slices that failed named.
//   merging:      rows are joined in page order; a row read twice (in the overlap of two slices, enrich.course_entry_slice_overlap_chars)
//                 is kept once (same kind, audience, quote, score, basis, band and grade).
// A one-slice page is asked exactly as before (same system prompt and user message); only the answer limit is now a setting.
export const COURSE_ENTRY_SLICE_BASIS = "course-slices-v1";
export const COURSE_ENTRY_PROMPT_VERSION = "course-entry-v1";  // the system prompt is unchanged; the slice label is recorded in coverage

export const COURSE_ENTRY_KINDS = ["minimum_grade", "subject_prerequisite", "portfolio_interview", "prior_qualification", "work_experience", "override", "general_note"];
export const COURSE_ENTRY_SYSTEM =
  "You read one university course page and list only the academic entry requirements the page itself publishes for this course. One row per requirement. kind is one of: " +
  "minimum_grade (a minimum entry score or rank the page prints for this course, for example an ATAR or a selection rank: min_entry_score is the number as printed and min_entry_score_basis the words the page prints with it, for example '2027 Guaranteed ATAR'); " +
  "subject_prerequisite (a subject applicants must have studied, with the level the page gives); portfolio_interview (a selection task: portfolio, interview, audition, test, folio, personal statement); " +
  "prior_qualification (a qualification applicants must hold); work_experience; override (only where the page states a rule that replaces the university's general entry requirements for this course); general_note (another academic entry condition the page states). " +
  "Do not list English language tests or English proficiency requirements. benchmark_band: only when the page prints a percentage band such as '65%' as this course's entry band; never derive a band from an ATAR, rank or score; otherwise null. " +
  "audience: international when the sentence names international or overseas applicants, domestic when it names Australian school-leaver routes (VCE, ATAR, VTAC, STAT), all otherwise. " +
  "quote: the exact words from the page that state the requirement (at most 300 characters). confidence: 0 to 1. Give no row the page does not state; give an empty list when the page states none. Never guess.";
const strOrNull = { type: ["string", "null"] };
export const COURSE_ENTRY_SCHEMA = { type: "object", additionalProperties: false, required: ["rows"], properties: { rows: { type: "array", items: { type: "object", additionalProperties: false,
  required: ["kind", "audience", "description", "min_entry_score", "min_entry_score_basis", "benchmark_band", "min_grade", "confidence", "quote"],
  properties: { kind: { type: "string", enum: COURSE_ENTRY_KINDS }, audience: { type: "string", enum: ["international", "domestic", "all"] }, description: { type: "string" },
    min_entry_score: { type: ["number", "null"] }, min_entry_score_basis: strOrNull, benchmark_band: strOrNull, min_grade: strOrNull, confidence: { type: "number" }, quote: { type: "string" } } } } } };

// letters and digits compared, case and spacing ignored (the same comparison as the worker's quote check)
const flat = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");

export type CourseSlice = { index: number; start: number; end: number; text: string };
export type CourseSliceLimits = { pageChars: number; sliceChars: number; overlapChars: number; maxSlices: number };
export type CourseSlicePlan = { ok: true; page_chars: number; slices: CourseSlice[] } | { ok: false; page_chars: number; slices_needed: number; reason: string };

// the text in units that end after a line break; a line longer than a slice is cut at its last space within the slice (or at the limit)
function units(text: string, max: number): [number, number][] {
  const out: [number, number][] = [];
  let i = 0;
  while (i < text.length) {
    const nl = text.indexOf("\n", i), j = nl < 0 ? text.length : nl + 1;
    while (j - i > max) {
      const sp = text.lastIndexOf(" ", i + max - 1);
      const cut = sp > i ? sp + 1 : i + max;
      out.push([i, cut]); i = cut;
    }
    if (j > i) out.push([i, j]);
    i = j;
  }
  return out;
}

// contiguous slices of at most sliceChars characters, each starting at a line (or cut) boundary; a later slice begins with the last lines of
// the one before it, up to overlapChars characters, so a requirement printed across a boundary is read whole at least once
export function courseEntrySlices(text: string, sliceChars: number, overlapChars = 0): CourseSlice[] {
  const t = String(text || ""), max = Math.max(1, Math.floor(sliceChars)), ov = Math.max(0, Math.min(Math.floor(overlapChars), Math.floor(max / 2)));
  // the page text is mostly one long line (htmlToText joins blocks with spaces), so units are kept to half the overlap (cut at a space):
  // the overlap is then made of whole units and is at least half the setting
  const u = units(t, ov > 0 ? Math.max(1, Math.min(max, Math.floor(ov / 2))) : max);
  if (!u.length) return [{ index: 0, start: 0, end: 0, text: "" }];
  const out: CourseSlice[] = [];
  let a = 0;
  while (a < u.length) {
    let b = a;
    while (b + 1 < u.length && u[b + 1][1] - u[a][0] <= max) b++;
    out.push({ index: out.length, start: u[a][0], end: u[b][1], text: t.slice(u[a][0], u[b][1]) });
    if (b === u.length - 1) break;
    let n = b + 1;
    while (n - 1 > a && u[b][1] - u[n - 1][0] <= ov) n--;
    if (u[b + 1][1] - u[n][0] > max) n = b + 1;  // the overlap never stops the next slice reaching new text
    a = n;
  }
  return out;
}

// the slices cover the whole text: the first starts at 0, each starts no later than the one before ended, the last ends at the text's end
export function courseEntryCoverage(slices: { start: number; end: number }[], pageChars: number): { complete: boolean; gaps: [number, number][] } {
  const gaps: [number, number][] = [];
  let reached = 0;
  for (const s of [...slices].sort((x, y) => x.start - y.start)) {
    if (s.start > reached) gaps.push([reached, s.start]);
    reached = Math.max(reached, s.end);
  }
  if (reached < pageChars) gaps.push([reached, pageChars]);
  return { complete: gaps.length === 0, gaps };
}

// the read's plan, before any AI call: the page is read whole or held (named)
export function courseEntryPlan(text: string, o: CourseSliceLimits): CourseSlicePlan {
  const t = String(text || ""), len = t.length;
  if (len > o.pageChars) {
    return { ok: false, page_chars: len, slices_needed: Math.ceil(len / Math.max(1, o.sliceChars)),
      reason: `page text is ${len} characters, longer than entry.course_page_chars (${o.pageChars}); a cut page is never read as complete` };
  }
  const slices = courseEntrySlices(t, o.sliceChars, o.overlapChars);
  if (slices.length > o.maxSlices) return { ok: false, page_chars: len, slices_needed: slices.length, reason: `page text needs ${slices.length} slices of ${o.sliceChars} characters, more than enrich.course_entry_max_slices (${o.maxSlices})` };
  const cov = courseEntryCoverage(slices, len);
  if (!cov.complete) return { ok: false, page_chars: len, slices_needed: slices.length, reason: `slices leave ${cov.gaps.length} part(s) of the page unread` };
  return { ok: true, page_chars: len, slices };
}

// the user message: a one-slice page exactly as before v0.53.0; a slice says which part of the page it is
export function courseEntryUser(provider: string, title: string, slice: CourseSlice, slices: number, pageChars: number): string {
  const part = slices > 1 ? `Part of the page: ${slice.index + 1} of ${slices} (characters ${slice.start + 1} to ${slice.end} of ${pageChars}); list only the requirements this part states\n` : "";
  return `University: ${provider}\nCourse: ${title}\n${part}\nPage text:\n${slice.text}`;
}
export function courseEntryRequest(model: string, user: string, maxTokens: number) {
  return { model, temperature: 0, max_tokens: maxTokens, provider: { require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: "course_entry", strict: true, schema: COURSE_ENTRY_SCHEMA } },
    messages: [{ role: "system", content: COURSE_ENTRY_SYSTEM }, { role: "user", content: user }] };
}

// one slice's answer as OpenRouter returns it: whole and readable, or failed with the reason named (never parsed when it was cut)
export function courseEntryAnswer(d: any, index: number, slices: number): { ok: true; a: any } | { ok: false; error: string } {
  const where = slices > 1 ? `slice ${index + 1} of ${slices}` : "the page";
  const ch = d?.choices?.[0] || {}, content = String(ch?.message?.content || "");
  if (ch?.finish_reason === "length") return { ok: false, error: `output_truncated: ${where} reached enrich.course_entry_max_tokens` };
  if (!content.trim()) {
    const err = ch?.error?.message || d?.error?.message || (ch?.finish_reason ? `finish: ${ch.finish_reason}` : "no choices");
    return { ok: false, error: `no_answer: ${where} (${String(err).slice(0, 120)})` };
  }
  try { return { ok: true, a: JSON.parse(content) } } catch (e) { return { ok: false, error: `unreadable_answer: ${where} (${e instanceof Error ? e.message : String(e)})`.slice(0, 300) } }
}

// one slice's rows: a row is kept only when its quote is on that slice (so on the page)
export function courseEntrySliceRows(a: any, sliceText: string): { rows: any[]; dropped: any[] } {
  const P = flat(sliceText), rows: any[] = [], dropped: any[] = [];
  for (const r of (Array.isArray(a?.rows) ? a.rows : []) as any[]) {
    const q = String(r?.quote || ""), fq = flat(q);
    if (!(fq.length >= 4 && P.includes(fq))) { dropped.push({ reason: "quote_not_on_page", kind: r?.kind, quote: q.slice(0, 300) }); continue }
    rows.push({ ...r, quote: q.slice(0, 300), description: String(r?.description || "").slice(0, 500) });
  }
  return { rows, dropped };
}

export type CourseSliceOutcome = { index: number; ok: true; rows: any[]; dropped: any[]; cost: number } | { index: number; ok: false; error: string; cost: number };
const rowKey = (r: any) => [r?.kind, r?.audience, flat(r?.quote), r?.min_entry_score ?? "", flat(r?.min_entry_score_basis), flat(r?.benchmark_band), flat(r?.min_grade)].join("|");

// the slices' answers joined: complete only when every planned slice was read and answered whole; rows in page order, a repeated row once
export function courseEntryMerge(slices: CourseSlice[], outcomes: (CourseSliceOutcome | undefined)[], pageChars: number) {
  const n = slices.length, cost = outcomes.reduce((x, o) => x + Number(o?.cost || 0), 0);
  const failed: string[] = [];
  for (const s of slices) {
    const o = outcomes[s.index];
    if (!o) failed.push(`slice ${s.index + 1} of ${n} not read`);
    else if (!o.ok) failed.push(o.error);
  }
  const ranges = slices.map((s) => [s.start, s.end] as [number, number]);
  const cov = courseEntryCoverage(slices, pageChars);
  if (!cov.complete) failed.push(`slices leave ${cov.gaps.length} part(s) of the page unread`);
  const coverage = { basis: COURSE_ENTRY_SLICE_BASIS, page_chars: pageChars, slices: n, ranges, answered: outcomes.filter((o) => o?.ok).length, duplicates: 0, complete: failed.length === 0 };
  if (failed.length) return { complete: false as const, reason: `${failed.length} of ${n} slice(s) not read whole: ${failed.join("; ")}`.slice(0, 300), rows: [] as any[], dropped: [] as any[], coverage, cost };
  const rows: any[] = [], dropped: any[] = [], seen = new Set<string>(), seenDrop = new Set<string>();
  for (const s of slices) {
    const o = outcomes[s.index] as Extract<CourseSliceOutcome, { ok: true }>;
    for (const r of o.rows) { const k = rowKey(r); if (seen.has(k)) { coverage.duplicates++; continue } seen.add(k); rows.push(r) }
    for (const d of o.dropped) { const k = `${d.reason}|${d.kind}|${flat(d.quote)}`; if (seenDrop.has(k)) continue; seenDrop.add(k); dropped.push(d) }
  }
  return { complete: true as const, reason: null, rows, dropped, coverage, cost };
}
