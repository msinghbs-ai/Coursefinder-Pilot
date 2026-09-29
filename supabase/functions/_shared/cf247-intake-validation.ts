// CF-CHG-20260915-247 plan item A3: intake months for international students.
// Pure functions (no I/O), shared by the Layer 3 intake benchmark and any future
// intake interpreter, so a benchmark PASS describes exactly what production runs.
//
// The coverage sweep's deterministic Layer 2 intake reading is HELD (a hand check
// found money, visa and deadline windows read as intakes). Layer 3 reads the stored
// page text and returns the intake months, or "not_stated", with verbatim quotes.
// An answer is accepted only when every quote is in the page text and every month
// it reports is written in its quotes. Nothing here admits anything.

// v1.1.0: fields are answered in reading order (rationale, quotes, months, status). With status first (v1.0.0) the
// pinned model answered not_stated on every stated case even where its own rationale named the months (run r1).
export const INTAKE_VALIDATOR_VERSION = "cf247-intake-validation-v1.1.0";

export const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const MONTH_ABBR = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];

export const INTAKE_SYSTEM_PROMPT = `You read the plain text of an Australian education provider's official course page and report the months in which this course starts (its intakes) for international students. Return JSON only.
Rules:
1. Report a month only when the text explicitly says the course starts, commences or has an intake or entry in that month (a month name, a month abbreviation, or a full date).
2. Never treat these as intakes: application opening or closing dates, deadlines, census dates, fee or payment dates, visa dates, orientation, exams, results, holidays or breaks, open days, events, webinars, or page-updated dates.
3. Do not convert terms such as "Semester 1", "Trimester 2", "Term 3" or "Study Period 4" into months. If the page gives only such terms and no month, the answer is not_stated.
4. If the page separates domestic and international intakes, report only the international ones. If a month is stated as not available to international students, leave it out. If intakes are listed per campus, location or study mode, report every month listed for any option open to international students.
5. If no start month is stated for this course, return status "not_stated" with months [].
6. quotes: one to four short passages copied exactly, character for character, from the text, which together name every month you report. Use an empty list only for not_stated.
7. months: integers 1 to 12, ascending, no duplicates.
8. If the page says the course is suspended, closed, not accepting applications or enrolments, has no current or further intakes, or is not available to international students or student visa holders, return not_stated.
9. General explanations that are not about this course (for example a glossary saying most courses start in February) are not intakes of this course.
Answer the fields in order: rationale (what the page says about when this course starts), then quotes, then months, then status ("months" when you report at least one month, otherwise "not_stated").`;

export const INTAKE_RESPONSE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["rationale", "quotes", "months", "status"],
  properties: {
    rationale: { type: "string" },
    quotes: { type: "array", items: { type: "string" } },
    months: { type: "array", items: { type: "integer", minimum: 1, maximum: 12 } },
    status: { type: "string", enum: ["months", "not_stated"] },
  },
};

// Quotes are compared on visible characters: whitespace and formatting symbols ignored,
// characters otherwise matched exactly and in order (same rule as the tuition validator).
export function quoteComparable(value: unknown): string {
  return String(value ?? "")
    .replace(/\\[nrt]/g, " ")
    .replace(/[*_`#>|]/g, "")
    .replace(/\s+/g, "")
    .toLowerCase();
}
export function quoteInText(quote: unknown, text: string): boolean {
  const q = quoteComparable(quote);
  return q.length >= 6 && quoteComparable(text).includes(q);
}

// Months written in a passage (full names capitalised or not; three-letter abbreviations as whole words).
export function monthsWritten(s: string): number[] {
  const out = new Set<number>();
  MONTHS.forEach((m, i) => { if (new RegExp(`\\b${m}\\b`, "i").test(s)) out.add(i + 1) });
  MONTH_ABBR.forEach((m, i) => { if (new RegExp(`\\b${m}\\b`, "i").test(s)) out.add(i + 1) });
  if (/\bsept\b/i.test(s)) out.add(9);
  // "may" the verb is never a month unless capitalised
  if (!/\bMay\b/.test(s)) out.delete(5);
  return [...out].sort((a, b) => a - b);
}

export function monthNamesToNumbers(names: unknown): number[] {
  const arr = Array.isArray(names) ? names : [];
  return [...new Set(arr.map((n) => MONTHS.findIndex((m) => m.toLowerCase() === String(n).toLowerCase()) + 1).filter((n) => n > 0))].sort((a, b) => a - b);
}

// Focused evidence: when the page text is long, only windows around intake wording and month names are sent.
const LEAD = /(intakes?|commenc\w*|start(?:s|ing)?|start dates?|entry|begin\w*|semester|trimester|study period|term\s?\d|available|January|February|March|April|May|June|July|August|September|October|November|December)/g;
export function focusText(text: string, maxChars = 30000, radius = 400): string {
  if (text.length <= maxChars) return text;
  const spans: [number, number][] = [];
  for (const m of text.matchAll(LEAD)) {
    const at = m.index || 0;
    spans.push([Math.max(0, at - radius), Math.min(text.length, at + m[0].length + radius)]);
  }
  spans.sort((a, b) => a[0] - b[0]);
  const merged: [number, number][] = [];
  for (const s of spans) {
    const last = merged[merged.length - 1];
    if (last && s[0] <= last[1]) last[1] = Math.max(last[1], s[1]); else merged.push([s[0], s[1]]);
  }
  let out = "";
  for (const [a, b] of merged) {
    const piece = text.slice(a, b);
    if (out.length + piece.length + 5 > maxChars) break;
    out += (out ? "\n...\n" : "") + piece;
  }
  return out || text.slice(0, maxChars);
}

export type IntakeAnswer = { status: "months" | "not_stated"; months: number[]; quotes: string[]; rationale?: string };

// Deterministic acceptance of a Layer 3 answer against the full page text.
export function validateIntakeAnswer(r: any, text: string) {
  const errors: string[] = [];
  const status = r?.status;
  if (status !== "months" && status !== "not_stated") errors.push("status_invalid");
  const monthsRaw = Array.isArray(r?.months) ? r.months : null;
  if (!monthsRaw) errors.push("months_array_required");
  const months = [...new Set((monthsRaw || []).map((m: any) => Number(m)))].sort((a: number, b: number) => a - b) as number[];
  if (months.some((m) => !Number.isInteger(m) || m < 1 || m > 12)) errors.push("month_out_of_range");
  const quotes: string[] = Array.isArray(r?.quotes) ? r.quotes.map((q: any) => String(q)) : [];
  if (!Array.isArray(r?.quotes)) errors.push("quotes_array_required");
  if (status === "months") {
    if (!months.length) errors.push("months_required_for_status_months");
    if (!quotes.length) errors.push("quote_required");
    if (quotes.length > 4) errors.push("too_many_quotes");
    for (const q of quotes) if (!quoteInText(q, text)) { errors.push("quote_not_in_page_text"); break }
    const quoted = new Set(monthsWritten(quotes.join(" \n ")));
    if (months.some((m) => !quoted.has(m))) errors.push("month_not_in_quotes");
  }
  if (status === "not_stated" && months.length) errors.push("not_stated_with_months");
  const valid = errors.length === 0;
  return { valid, errors, status: valid ? status : null, months: valid && status === "months" ? months : [], quotes };
}

// Case scoring against the gold answer. A rejected answer counts as an abstention (nothing admitted).
export function scoreCase(gold: { status: string; months: number[] }, predicted: { status: string | null; months: number[] }) {
  const g = new Set(gold.status === "months" ? gold.months : []);
  const p = new Set(predicted.status === "months" ? predicted.months : []);
  const invented = [...p].filter((m) => !g.has(m)).sort((a, b) => a - b);
  const missed = [...g].filter((m) => !p.has(m)).sort((a, b) => a - b);
  const abstained = predicted.status === null;
  const exact = gold.status === "months"
    ? predicted.status === "months" && invented.length === 0 && missed.length === 0
    : predicted.status === "not_stated";
  // for a not_stated case, a rejected answer still admits nothing: safe but not an exact answer
  const safe_on_not_stated = gold.status === "not_stated" ? p.size === 0 : null;
  return { exact, invented, missed, abstained, safe_on_not_stated };
}

export function summarise(rows: { gold: { status: string; months: number[] }; predicted: { status: string | null; months: number[] } }[]) {
  let stated = 0, statedExact = 0, notStated = 0, notStatedExact = 0, notStatedInvented = 0, output = 0, outputExact = 0, invented = 0, missed = 0, abstained = 0;
  for (const r of rows) {
    const s = scoreCase(r.gold, r.predicted);
    if (r.gold.status === "months") { stated++; if (s.exact) statedExact++ } else { notStated++; if (s.exact) notStatedExact++; if (!s.safe_on_not_stated) notStatedInvented++ }
    if (r.predicted.status === "months" && r.predicted.months.length) { output++; if (s.exact) outputExact++ }
    invented += s.invented.length; missed += s.missed.length; if (s.abstained) abstained++;
  }
  const ratio = (a: number, b: number) => b ? Math.round((a / b) * 10000) / 10000 : null;
  return {
    cases: rows.length, stated_cases: stated, stated_exact: statedExact, stated_exact_rate: ratio(statedExact, stated),
    not_stated_cases: notStated, not_stated_exact: notStatedExact, not_stated_with_invented_intakes: notStatedInvented,
    // case-level precision: of the cases where months were output, how many were exactly right
    precision: ratio(outputExact, output), recall: ratio(statedExact, stated),
    overall_exact: statedExact + notStatedExact, overall_exact_rate: ratio(statedExact + notStatedExact, rows.length),
    false_intake_months: invented, missed_months: missed, rejected_or_failed_answers: abstained,
  };
}

// Qualification bar (A3): at least 95% exact on stated cases and zero invented intakes on not-stated cases.
export function passesBar(s: ReturnType<typeof summarise>) {
  return (s.stated_exact_rate ?? 0) >= 0.95 && s.not_stated_with_invented_intakes === 0 && s.stated_cases > 0 && s.not_stated_cases > 0;
}
