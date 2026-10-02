// CF-CHG-20260915-247 Decision 229 (2 Oct 2026): intake check v1.3.0, a NEW contract alongside v1.2.0.
// The qualified v1.2.0 contract (cf247-intake-validation.ts) is not changed: its functions and texts stay byte for
// byte as qualified, so every profile bound to it keeps its binding hash. A profile uses this contract only when its
// prompt_profile_version is INTAKE_VALIDATOR_VERSION_V13, after it is qualified on the frozen holdout l3r-intake-h1 and
// switched on by the Platform Admin.
//
// What v1.3.0 accepts that v1.2.0 rejected (reading of the waiting Layer 4 intake reviews, 2 Oct 2026):
//  1. Short quotes that are on the page as whole words: "JAN 12", "12/01", "April" (v1.2.0 needs 6 visible characters).
//  2. A heading quoted with one item of the list under it, when the page has the heading and the item in that order,
//     close together: "Intake Months each year February" for "Intake Months each year January February April ...",
//     "Commences January, July" for "Commences Scheduled ... Full Time January, July" (every word of the quote on the
//     page, in order, within 300 characters, no gap over 160 characters).
//  3. Day-first numeric dates name their month: 12/01 is January, 01-03-2027 is March (Australian pages write the day
//     first).
//  4. A course that starts every week, every month or on a rolling basis: all twelve months, when a quote says so.
// Unchanged: every month must be written in the quotes (or a rolling statement quoted), status not_stated has no
// months, at most 12 quotes, the safety rule, and terms such as "Semester 1" are never turned into months here (an
// approved calendar does that separately, Decision 228).
import { MAX_QUOTES, MONTHS, quoteComparable, quoteInText } from "./cf247-intake-validation.ts";

export const INTAKE_VALIDATOR_VERSION_V13 = "cf247-intake-validation-v1.3.0";

export const INTAKE_SYSTEM_PROMPT_V13 = `You read the plain text of an Australian education provider's official course page and report the months in which this course starts (its intakes) for international students. Return JSON only.
Rules:
1. Report a month only when the text explicitly says the course starts, commences or has an intake or entry in that month (a month name, a month abbreviation, or a full date). Dates written with numbers are day first: 12/01 is 12 January.
2. Never treat these as intakes: application opening or closing dates, deadlines, census dates, fee or payment dates, visa dates, orientation, exams, results, holidays or breaks, open days, events, webinars, or page-updated dates.
3. Do not convert terms such as "Semester 1", "Trimester 2", "Term 3" or "Study Period 4" into months. If the page gives only such terms and no month, the answer is not_stated.
4. If the page separates domestic and international intakes, report only the international ones. If a month is stated as not available to international students, leave it out. If intakes are listed per campus, location or study mode, report every month listed for any option open to international students.
5. If the page says the course starts every week, every month, or on a rolling basis (for example "Intakes every Monday"), report all twelve months and quote that statement.
6. If no start month is stated for this course, return status "not_stated" with months [].
7. quotes: one to twelve short passages copied exactly, character for character, from the text, which together name every month you report. Use an empty list only for not_stated.
8. months: integers 1 to 12, ascending, no duplicates.
Answer the fields in order: rationale (what the page says about when this course starts), then quotes, then months, then status ("months" when you report at least one month, otherwise "not_stated").`;

const WORD = /[\p{L}\p{N}]+/gu;
function tokens(s: string) {
  const out: { t: string; at: number; end: number }[] = [];
  for (const m of String(s ?? "").matchAll(WORD)) out.push({ t: m[0].toLowerCase(), at: m.index || 0, end: (m.index || 0) + m[0].length });
  return out;
}
const SPAN = 300, GAP = 160;
// v1.3.0 quote rule: v1.2.0's rule, or a short quote on the page as whole words, or every word of the quote on the page
// in the same order within a short stretch (a heading and an item of its list).
export function quoteInTextV13(quote: unknown, text: string, textTokens?: { t: string; at: number; end: number }[]): boolean {
  if (quoteInText(quote, text)) return true;
  const q = tokens(String(quote ?? ""));
  if (!q.length) return false;
  const visible = quoteComparable(quote).length;
  if (visible < 3) return false;
  const tt = textTokens ?? tokens(text);
  for (let i = 0; i < tt.length; i++) {
    if (tt[i].t !== q[0].t) continue;
    let k = 1, last = tt[i], ok = true;
    if (q.length === 1) return true; // a single whole word on the page (for example "April")
    for (let j = i + 1; j < tt.length && k < q.length; j++) {
      if (tt[j].at - last.end > GAP || tt[j].end - tt[i].at > SPAN) { ok = false; break }
      if (tt[j].t === q[k].t) {
        // a short quote (under 6 visible characters, such as "JAN 12") must be contiguous on the page
        if (visible < 6 && j !== tt.indexOf(last) + 1) { ok = false; break }
        last = tt[j]; k++;
      }
    }
    if (ok && k === q.length) return true;
  }
  return false;
}

const MONTH_ABBR = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
// Months written in a passage: v1.2.0's names and abbreviations, plus day-first numeric dates (12/01, 01-03-2027).
export function monthsWrittenV13(s: string): number[] {
  const out = new Set<number>();
  MONTHS.forEach((m, i) => { if (new RegExp(`\\b${m}\\b`, "i").test(s)) out.add(i + 1) });
  MONTH_ABBR.forEach((m, i) => { if (new RegExp(`\\b${m}\\b`, "i").test(s)) out.add(i + 1) });
  if (/\bsept\b/i.test(s)) out.add(9);
  if (!/\bMay\b|\bMAY\b/.test(s)) out.delete(5);
  for (const m of String(s).matchAll(/(?<![\d.\/-])(\d{1,2})[\/-](\d{1,2})(?:[\/-](\d{2}|\d{4}))?(?![\d\/-])/g)) {
    const d = Number(m[1]), mo = Number(m[2]);
    if (d >= 1 && d <= 31 && mo >= 1 && mo <= 12) out.add(mo);
  }
  return [...out].sort((a, b) => a - b);
}

export const ROLLING_RE = /\b(?:every|each) (?:monday|tuesday|wednesday|thursday|friday|week|fortnight|month)\b|\bweekly (?:intakes?|starts?|start dates?)\b|\bmonthly (?:intakes?|starts?|start dates?)\b|\brolling (?:intakes?|starts?|enrol?ments?|admissions?|basis)\b|\b(?:start|enrol|commence) (?:at )?any ?time\b|\bintakes? (?:every|each) (?:week|month)\b/i;

export function validateIntakeAnswerV13(r: any, text: string) {
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
    if (quotes.length > MAX_QUOTES) errors.push("too_many_quotes");
    const tt = tokens(text);
    for (const q of quotes) if (!quoteInTextV13(q, text, tt)) { errors.push("quote_not_in_page_text"); break }
    const joined = quotes.join(" \n ");
    const rolling = months.length === 12 && ROLLING_RE.test(joined);
    const quoted = new Set(monthsWrittenV13(joined));
    if (!rolling && months.some((m) => !quoted.has(m))) errors.push("month_not_in_quotes");
  }
  if (status === "not_stated" && months.length) errors.push("not_stated_with_months");
  const valid = errors.length === 0;
  return { valid, errors, status: valid ? status : null, months: valid && status === "months" ? months : [], quotes };
}
