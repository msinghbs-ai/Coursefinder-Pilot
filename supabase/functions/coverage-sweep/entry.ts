// v0.47.0 (CF-247 Track C, entry requirements step A, drafted 25 Oct 2026): the entry matrix reader. One stored entry-requirements page
// (a provider's academic entry minimums by country of prior education) is read with the pinned model (setting entry.matrix_model) into
// rows as published. Every row carries a verbatim quote; a row is kept only when its quote is on the page, a number has a scale and is in
// the quote, and a grade is in the quote. English-test rows are left out (they belong to the English requirement). The database proposes
// the rows and a person admits them in Layer 4 (first run per provider). Design: admin docs/platform/ENTRY-REQUIREMENTS.md 1.1.
export const ENTRY_PROMPT_VERSION = "entry-matrix-v0.1.0";

export const ENTRY_SCALES = ["percentage", "points", "aggregate", "gpa", "letter", "rank", "none"] as const;

export const ENTRY_PROMPT = "You read one university or polytechnic web page that lists the academic entry requirements for international applicants by country of prior education (an equivalence or entry-requirements table). Report one row for each minimum the page publishes: the country of the applicant's prior education (ISO 3166-1 alpha-2 code and its name as written), the study level it applies to as the page labels it (Foundation, Diploma, Bachelor, Degree, Masters, Cert L4 and similar; null if the page gives one minimum for all levels), the qualification as published (for example \"All India Senior School Certificate (CBSE)\"), the minimum grade exactly as published (\"75%\", \"CDD\", \"B average\", \"ATAR 70\"; null when the page says assessment on application, case by case or gives the qualification only), the numeric value of that minimum only when it is a single number, and its scale (percentage, points, aggregate, gpa, letter, rank; none when there is no grade). If the provider converts a benchmark band (for example \"65%\", \"ATAR 60\", \"rank 70\", \"group 2\") instead of a level, give that band. If a row belongs to one named course, give the course name. Put subject minimums (\"minimum 60% in English\"), best-N rules (\"best four subjects\") and alternative routes into conditions. Give your confidence (0 to 1) that the row is read correctly. For every row copy the exact sentence or the whole table row from the page that contains it, with the qualification and the grade (quote, at most 300 characters). Leave out English language test scores (IELTS, TOEFL, PTE and similar), fees, dates and domestic-only rows. Never infer a row from another page or from general knowledge; return an empty list if the page publishes no minimums. Also give the edition or intake year the page names, if any.";

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

export function entryMatrixRequest(model: string, p: { provider: string; url: string; text: string; slice?: string }) {
  return { model, temperature: 0, max_tokens: 8000, provider: { require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: "entry_matrix", strict: true, schema: ENTRY_SCHEMA } },
    messages: [{ role: "system", content: ENTRY_PROMPT },
      { role: "user", content: `Provider: ${p.provider}\nPage address: ${p.url}${p.slice ? `\nPart of the page: ${p.slice}` : ""}\n\nPage text:\n${p.text}` }] };
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

// letters and digits compared, case and spacing ignored, so words split by markup ("S enior", NMIT 25 Oct byte-check) still match
const flat = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");
const ENGLISH_TEST = /\b(ielts|toefl|pte|duolingo|cambridge english|oet)\b/i;

export type EntryDrop = { reason: string; country?: string; quote?: string };
export function entryMatrixParsed(a: any, page: string) {
  const P = flat(page), on = (q: string) => flat(q).length >= 6 && P.includes(flat(q));
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
    rows.push({ country_code: cc, country_name: String(x?.country_name || ""), study_level: x?.study_level ?? null, qualification_name: String(x?.qualification_name || "").trim(),
      min_grade: grade, min_value: value, grade_scale: scale, benchmark_band: x?.benchmark_band ?? null, course_name: x?.course_name ?? null,
      conditions: x?.conditions ?? {}, confidence: Number(x?.confidence ?? 0), quote: quote.slice(0, 300) });
  }
  return { rows, dropped, edition: a?.edition ?? null, intake_year: Number.isInteger(a?.intake_year) ? a.intake_year : null };
}
