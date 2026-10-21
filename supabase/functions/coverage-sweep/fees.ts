// CF-247 (21 Oct 2026, Platform Admin 20:02: "Build fee reader for nz unis and make sure its compatible to ca and upcoming countries. The
// logic has to be built by using ai model in the platform and collect and feed error to build and evolve data reader").
// Worker mode fee_ai: a stored fee page is read with the platform's pinned model into rows as published, each matched to one of the
// provider's own courses; the country's rules, the provider's reading notes and its open findings (past mistakes) go with every read.
// Every row needs a quote that is on the page. Pure functions here; the mode is in index.ts.

export type FeeItem = {
  provider: string; country: string; url: string; notes?: string | null;
  profile?: { currency_code?: string; usual_unit?: string; full_time_units_a_year?: number; unit_name?: string; terms_a_year?: number; notes?: string } | null;
  findings?: { kind: string; detail: unknown; times: number }[];
  courses: { id: string; title: string; level: string | null }[];
};

export const FEE_AI_PROMPT = `You read one tuition fee page of a tertiary education provider and return every fee row on it, exactly as published.
Rules:
- One row per fee shown: the qualification (e.g. "Bachelor of Science"), the subject or major if the fee is for one subject, the level if stated, the amount (amount_min; amount_max only when the page gives a range), the currency, the unit and the fee year.
- unit: per_year (a yearly or annual fee, a fee per EFTS or full-time year), per_credit, per_point (NZ points), per_term (semester, trimester or term), per_course (whole programme), or unknown.
- audience: international or domestic, from the page's heading or column. If the page is only for international students, every row is international.
- quote: copy the words of the row from the page exactly, including the amount, so it can be found on the page.
- course_id: the id of the one course in the given course list that this row's fee is for (same qualification; a subject row belongs to its qualification's course when the list has no separate course for the subject). Use null when no course in the list fits. match_confidence 0 to 1: how sure the match is.
- Do not invent rows, amounts or years. Leave out notes, deposits, levies, insurance and living costs.
- more_fee_pages: full addresses of other fee pages of this provider that this page links to (for example one page per faculty or division), only on the provider's own site.
- page_notes: two to four sentences on how this provider's fee pages are laid out and how rows map to courses, written for the next reader of this site (for example "fees are in one table per division; qualification rows with subject rows under them; the first column is the 2027 yearly fee").`;

const fees_schema = {
  type: "object", additionalProperties: false,
  required: ["rows", "more_fee_pages", "page_notes"],
  properties: {
    rows: { type: "array", items: { type: "object", additionalProperties: false,
      required: ["qualification", "subject", "level", "amount_min", "amount_max", "currency", "unit", "audience", "fee_year", "quote", "course_id", "match_confidence"],
      properties: {
        qualification: { type: "string" }, subject: { type: ["string", "null"] }, level: { type: ["string", "null"] },
        amount_min: { type: "number" }, amount_max: { type: ["number", "null"] }, currency: { type: "string" },
        unit: { type: "string", enum: ["per_year", "per_credit", "per_point", "per_term", "per_course", "unknown"] },
        audience: { type: "string", enum: ["international", "domestic"] }, fee_year: { type: ["integer", "null"] },
        quote: { type: "string" }, course_id: { type: ["string", "null"] }, match_confidence: { type: "number" } } } },
    more_fee_pages: { type: "array", items: { type: "string" } },
    page_notes: { type: "string" },
  },
};

export function feeAiRequest(model: string, it: FeeItem, text: string) {
  const p = it.profile || {};
  const country = `Country ${it.country}: currency ${p.currency_code || "?"}; fees are usually published ${String(p.usual_unit || "per_year").replace("_", " ")}`
    + (p.full_time_units_a_year ? `; a full-time year is ${p.full_time_units_a_year} ${p.unit_name || "units"}` : "") + (p.notes ? `. ${p.notes}` : "");
  const past = (it.findings || []).slice(0, 20).map((f) => `- ${f.kind} (${f.times}x): ${JSON.stringify(f.detail).slice(0, 220)}`).join("\n");
  const courses = it.courses.map((c) => `${c.id} | ${c.title} | ${c.level || ""}`).join("\n");
  const user = [
    `Provider: ${it.provider}`, `Page: ${it.url}`, country,
    it.notes ? `How this provider's fee pages were read before:\n${it.notes}` : "",
    past ? `Problems with earlier reads of this provider (avoid them):\n${past}` : "",
    `Courses of this provider (id | title | level):\n${courses}`,
    `Page text:\n${text}`,
  ].filter(Boolean).join("\n\n");
  return {
    model, temperature: 0, provider: { require_parameters: true },
    messages: [{ role: "system", content: FEE_AI_PROMPT }, { role: "user", content: user }],
    response_format: { type: "json_schema", json_schema: { name: "fee_rows", strict: true, schema: fees_schema } },
  };
}

// letters and digits only, so table bars, currency signs, thousands separators and spacing do not matter
export const squash = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]/g, "");

// 22 Oct 2026 (NZ enrichment review, fix 6): null characters in page text or answers made the database refuse the record
// ("unsupported Unicode escape sequence"); they are removed from everything recorded.
export function noNul<T>(v: T): T {
  if (typeof v === "string") return v.replace(/\u0000/g, "") as unknown as T;
  if (Array.isArray(v)) return v.map(noNul) as unknown as T;
  if (v && typeof v === "object") return Object.fromEntries(Object.entries(v as Record<string, unknown>).map(([k, x]) => [k, noNul(x)])) as T;
  return v;
}

// 22 Oct 2026 (fix 6): a page without a single money amount has no fee table; it is recorded as no rows without asking the AI
export const hasFeeAmount = (text: string) => /(?:[$£€]|\b(?:NZD|CAD|AUD|USD)\b)\s?\d{1,3}(?:[,\s]?\d{3})+(?:\.\d{2})?|\d{1,3}(?:,\d{3})+(?:\.\d{2})?\s?(?:NZD|CAD|AUD)\b/i.test(String(text || ""));

export function feeAiParsed(a: any, page: string, courseIds: Set<string>) {
  const on = squash(page);
  const rows: any[] = []; let quotes_missing = 0;
  for (const r of Array.isArray(a?.rows) ? a.rows : []) {
    const q = squash(r?.quote), amount = Number(r?.amount_min);
    if (!q || q.length < 6 || !on.includes(q) || !(amount > 0) || !on.includes(String(Math.trunc(amount)))) { quotes_missing++; continue }
    rows.push({ ...r, amount_min: amount, amount_max: Number(r?.amount_max) > 0 ? Number(r.amount_max) : null,
      course_id: r?.course_id && courseIds.has(String(r.course_id)) ? String(r.course_id) : null,
      match_confidence: Math.max(0, Math.min(1, Number(r?.match_confidence) || 0)) });
  }
  const more = (Array.isArray(a?.more_fee_pages) ? a.more_fee_pages : []).filter((u: unknown) => /^https?:\/\/\S+$/.test(String(u))).slice(0, 20);
  return noNul({ rows, quotes_missing, more_fee_pages: more, page_notes: String(a?.page_notes || "").slice(0, 1500) });
}
