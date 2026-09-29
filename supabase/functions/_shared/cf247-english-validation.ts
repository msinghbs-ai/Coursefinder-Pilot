// CF-CHG-20260915-247 Layer 3 English requirement validation (task class provider_english_validation).
// Pure functions (no I/O), shared by the holdout qualification and the live worker in layer3-model-routing,
// so a qualification PASS describes exactly what production runs.
//
// The coverage sweep's deterministic Layer 2 English reading admits a score only when it is unambiguous; many pages
// give no value or an unclear one. Layer 3 reads the stored page text and reports the minimum IELTS Academic, PTE
// Academic and TOEFL iBT scores for international entry to this course, each with one verbatim quote. An answer is
// accepted only when every quote is in the page text and names its test and every number reported for it.
// Nothing here admits anything.

export const ENGLISH_VALIDATOR_VERSION = "cf247-english-validation-v1.0.0";
export const ENGLISH_TESTS = ["IELTS", "PTE", "TOEFL_IBT"] as const;
export type EnglishTest = typeof ENGLISH_TESTS[number];

export const ENGLISH_SYSTEM_PROMPT = `You read the plain text of an Australian education provider's official course page and report the minimum English language test scores that international students need for entry to this course. Return JSON only.
Rules:
1. Report only these tests: IELTS Academic ("IELTS"), PTE Academic ("PTE") and TOEFL iBT ("TOEFL_IBT"). Ignore every other test (Cambridge, OET, Duolingo, TOEFL Essentials, paper-based TOEFL and so on).
2. For each reported test give the overall score. For IELTS also give min_band, the lowest score allowed in each band (listening, reading, writing, speaking), only when the text states one; otherwise null. For PTE and TOEFL_IBT min_band is always null.
3. Report a score only when the text states it as the English requirement of this course, or of a group of courses that the text says this course belongs to. Scores for other courses, other levels, pathway or ELICOS programs, or scores given only as examples are not this course's requirement.
4. If the text gives different scores for this course (for example by major, campus, year or entry pathway) and does not say which applies, leave that test out.
5. Never convert between tests, never work out a score from a band table you have to interpret, and never use a score that is only in a linked document or another page.
6. quote: one short passage copied exactly, character for character, from the text, that names the test and contains every number you report for it.
7. If no score for these tests is stated for this course, return status "not_stated" with tests [].
Answer the fields in order: rationale (what the page says about English requirements), then tests, then status ("stated" when you report at least one test, otherwise "not_stated").`;

export const ENGLISH_RESPONSE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["rationale", "tests", "status"],
  properties: {
    rationale: { type: "string" },
    tests: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["test", "overall", "min_band", "quote"],
        properties: {
          test: { type: "string", enum: ["IELTS", "PTE", "TOEFL_IBT"] },
          overall: { type: "number" },
          min_band: { anyOf: [{ type: "number" }, { type: "null" }] },
          quote: { type: "string" },
        },
      },
    },
    status: { type: "string", enum: ["stated", "not_stated"] },
  },
};

// Quotes are compared on visible characters: whitespace and formatting symbols ignored, characters otherwise matched
// exactly and in order (same rule as the tuition and intake validators).
export function quoteComparable(value: unknown): string {
  return String(value ?? "").replace(/\\[nrt]/g, " ").replace(/[*_`#>|]/g, "").replace(/\s+/g, "").toLowerCase();
}
export function quoteInText(quote: unknown, text: string): boolean {
  const q = quoteComparable(quote);
  return q.length >= 6 && quoteComparable(text).includes(q);
}

const TEST_NAME: Record<EnglishTest, RegExp> = {
  IELTS: /\bIELTS\b/i,
  PTE: /\bPTE\b|Pearson Test of English/i,
  TOEFL_IBT: /\bTOEFL\b/i,
};
// A number is "written" in a quote when it appears as a whole number token ("6.5", "6.0" for 6, "79").
export function numberWritten(quote: string, n: number): boolean {
  const forms = new Set([String(n)]);
  if (Number.isInteger(n)) forms.add(n.toFixed(1));
  return [...forms].some((f) => new RegExp(`(^|[^\\d.])${f.replace(".", "\\.")}(?![\\d]|\\.\\d)`).test(quote));
}
function inRange(test: EnglishTest, v: number) {
  if (test === "IELTS") return v >= 4 && v <= 9 && Math.round(v * 2) === v * 2;
  if (test === "PTE") return Number.isInteger(v) && v >= 30 && v <= 90;
  return Number.isInteger(v) && v >= 40 && v <= 120;
}

// Focused evidence: when the page text is long, only windows around English wording are sent.
const LEAD = /(IELTS|PTE|Pearson|TOEFL|English language|English requirement|language requirement|English proficiency|band score|overall score)/gi;
export function englishFocusText(text: string, maxChars = 24000, radius = 700): string {
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

export type EnglishValue = { test: EnglishTest; overall: number; min_band: number | null; quote: string };

// Deterministic acceptance of a Layer 3 answer against the full page text.
export function validateEnglishAnswer(r: any, text: string) {
  const errors: string[] = [];
  const status = r?.status;
  if (status !== "stated" && status !== "not_stated") errors.push("status_invalid");
  const raw = Array.isArray(r?.tests) ? r.tests : null;
  if (!raw) errors.push("tests_array_required");
  const tests: EnglishValue[] = [];
  const seen = new Set<string>();
  for (const t of raw || []) {
    const test = String(t?.test || "") as EnglishTest;
    if (!ENGLISH_TESTS.includes(test)) { errors.push("test_unknown"); continue }
    if (seen.has(test)) { errors.push("test_duplicated"); continue }
    seen.add(test);
    const overall = Number(t?.overall);
    const minBand = t?.min_band == null ? null : Number(t.min_band);
    const quote = String(t?.quote ?? "");
    if (!Number.isFinite(overall) || !inRange(test, overall)) errors.push(`${test}:overall_out_of_range`);
    if (minBand !== null && (test !== "IELTS" || !Number.isFinite(minBand) || !inRange("IELTS", minBand) || minBand > overall)) errors.push(`${test}:min_band_invalid`);
    if (!quoteInText(quote, text)) errors.push(`${test}:quote_not_in_page_text`);
    else {
      if (!TEST_NAME[test].test(quote)) errors.push(`${test}:quote_does_not_name_test`);
      if (!numberWritten(quote, overall)) errors.push(`${test}:overall_not_in_quote`);
      if (minBand !== null && !numberWritten(quote, minBand)) errors.push(`${test}:min_band_not_in_quote`);
    }
    tests.push({ test, overall, min_band: minBand, quote });
  }
  if (status === "stated" && !tests.length) errors.push("tests_required_for_status_stated");
  if (status === "not_stated" && tests.length) errors.push("not_stated_with_tests");
  const valid = errors.length === 0;
  return { valid, errors, status: valid ? status : null, tests: valid ? tests : [] as EnglishValue[] };
}

export type EnglishGold = { status: "stated" | "not_stated"; tests: { test: EnglishTest; overall: number; min_band: number | null }[] };

// Case scoring. wrong_values: reported values that are not the gold value (a test the gold does not have, a different
// overall, or a different or invented min_band). A withheld case (rejected or no answer) admits nothing.
export function scoreEnglishCase(gold: EnglishGold, predicted: { status: string | null; tests: { test: string; overall: number; min_band: number | null }[] }) {
  const g = new Map(gold.tests.map((t) => [t.test, t]));
  const p = predicted.status === "stated" ? predicted.tests : [];
  const wrong: string[] = [], missed: string[] = [];
  for (const t of p) {
    const x = g.get(t.test as EnglishTest);
    if (!x) wrong.push(`${t.test}:not_in_gold`);
    else {
      if (x.overall !== t.overall) wrong.push(`${t.test}:overall ${t.overall}<>${x.overall}`);
      if ((t.min_band ?? null) !== null && t.min_band !== x.min_band) wrong.push(`${t.test}:min_band ${t.min_band}<>${x.min_band}`);
      if ((t.min_band ?? null) === null && x.min_band !== null) missed.push(`${t.test}:min_band`);
    }
  }
  for (const t of gold.tests) if (!p.some((q) => q.test === t.test)) missed.push(t.test);
  const withheld = predicted.status === null;
  const exact = gold.status === "stated" ? predicted.status === "stated" && !wrong.length && !missed.length : predicted.status === "not_stated";
  return { exact, wrong, missed, withheld };
}
