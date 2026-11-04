// CF-247 intake recovery (Platform Admin decision 5 Nov 2026 §1, §2, §7; design admin docs/platform/2026-11-05-intake-calendar-v2-design.md).
// calendar-v2: the existing central-page reader for academic calendars, extended (no second reader).
//  * The AI reports each study period's teaching start (year, month and day as printed, with the quote and, when the year is printed only in a
//    heading, that heading as year_quote), its end when printed, its application closing dates (with who they apply to), the meaning of each
//    date, and the calendar's scope (main teaching, offshore campus, college or residence, study abroad, pathway or foundation, research only).
//  * Every value must be on the page: the quote is on the page, the month (and the day and year when given) are in the quote, a year from a
//    heading needs that heading on the page. Anything else is dropped and becomes a finding (fed to the next read as notes).
//  * Long documents are read in slices (settings reading.calendar_slice_chars, reading.calendar_max_slices).
//  * calendarSafe: the dated parser's reading may stand without AI only when it gives a current or future dated teaching start and the
//    address is a trusted main teaching calendar (decision §2: AI only when deterministic extraction cannot interpret the source safely).
export const CALENDAR_READER = "calendar-v2";
export const CALENDAR_PARSER_DATES = "provider-policy-calendar-dates-v2";
const MONTHS = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"];
const flat = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");
const SCOPES = ["main_teaching", "offshore_campus", "college_or_residence", "study_abroad_inbound", "pathway_or_foundation", "research_only", "other"];
const MEANINGS = ["teaching_start", "orientation", "enrolment", "other"];
const APPLIES = ["international", "domestic", "all", "unstated"];

export const CALENDAR_PROMPT = [
  "You read one university page or document with academic dates (an academic calendar, key dates or principal dates).",
  "1. scope: which students this calendar is for: main_teaching (the university's main coursework teaching periods at its home campuses), offshore_campus (a campus in another country), college_or_residence (a residential or affiliated college), study_abroad_inbound (exchange or study abroad students), pathway_or_foundation (a foundation, diploma or English pathway provider), research_only, or other. Copy the sentence or heading that shows it (scope_quote).",
  "2. periods: every study period (Semester 1, Trimester 2, Term 3, Autumn session, Teaching period 1, Summer school and similar). For each, the date it starts, exactly as printed: year, month and day (null when not printed). Copy the exact row or sentence that gives that date (start_quote). If the year is printed only in a heading above the row, give that heading as year_quote; otherwise leave year_quote empty. Give start_meaning: teaching_start when classes or teaching begin, orientation for orientation or O-week, enrolment for enrolment or census, other otherwise. Give the end date the same way when printed (end_quote).",
  "3. application_deadlines: for each period, the closing dates for applications printed for it, with year, month, day, who they apply to (international, domestic, all, unstated) and the exact quote.",
  "Never infer, calculate or move a date to another year. Leave out exams, census dates, holidays, results and graduation. Return an empty periods list if the page gives no dates.",
].join("\n");

export function calendarAiRequest(model: string, p: { provider: string; url: string; text: string; notes?: string | null; slice?: string }, maxTokens = 3000) {
  const date = (extra: Record<string, unknown> = {}) => ({ type: "object", additionalProperties: false, required: ["year", "month", "day", "quote", ...Object.keys(extra)],
    properties: { year: { type: ["integer", "null"] }, month: { type: "integer" }, day: { type: ["integer", "null"] }, quote: { type: "string" }, ...extra } });
  const schema = { type: "object", additionalProperties: false, required: ["scope", "scope_quote", "periods"], properties: {
    scope: { type: "string", enum: SCOPES }, scope_quote: { type: "string" },
    periods: { type: "array", items: { type: "object", additionalProperties: false, required: ["period", "start", "start_meaning", "year_quote", "end", "application_deadlines"], properties: {
      period: { type: "string" }, start: { anyOf: [date(), { type: "null" }] }, start_meaning: { type: "string", enum: MEANINGS }, year_quote: { type: "string" },
      end: { anyOf: [date(), { type: "null" }] },
      application_deadlines: { type: "array", items: date({ applies_to: { type: "string", enum: APPLIES } }) } } } } } };
  const notes = p.notes ? `\n\nNotes from earlier reads of this university's calendars (check whether they apply here):\n${p.notes}` : "";
  return { model, temperature: 0, max_tokens: maxTokens, provider: { require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: "intake_calendar_v2", strict: true, schema } },
    messages: [{ role: "system", content: CALENDAR_PROMPT + notes },
               { role: "user", content: `University: ${p.provider}\nPage address: ${p.url}${p.slice ? `\nPart: ${p.slice}` : ""}\n\nPage text:\n${p.text}` }] };
}

export function calendarSlices(text: string, chars: number, max: number): { slices: string[]; cut: boolean } {
  const size = Math.max(1000, Math.floor(chars)), out: string[] = [];
  for (let i = 0; i < text.length && out.length < Math.max(1, Math.floor(max)); i += size) {
    // a slice ends at a line break when one is near, so a row is not cut in two
    let end = Math.min(text.length, i + size); const nl = text.lastIndexOf("\n", end);
    if (end < text.length && nl > i + size * 0.8) end = nl;
    out.push(text.slice(i, end)); if (end !== i + size) i = end - size;
  }
  const read = out.reduce((n, s) => n + s.length, 0);
  return { slices: out, cut: read < text.length };
}

type Finding = { code: string; detail: string; example?: string };
type Dated = { year: number | null; month: number; day: number | null; date: string | null; quote: string; year_quote?: string; applies_to?: string; meaning?: string; rolling?: false };
const iso = (y: number | null, m: number, d: number | null) => {
  if (!y || !d) return null;
  const t = new Date(Date.UTC(y, m - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d ? t.toISOString().slice(0, 10) : null;
};
const monthIn = (m: number, q: string) => { const l = String(q || "").toLowerCase(); return l.includes(MONTHS[m - 1].slice(0, 3)) || new RegExp(`\\b0?${m}[/.-]`).test(l) };
const dayIn = (d: number, q: string) => new RegExp(`(^|[^0-9])0?${d}(st|nd|rd|th)?([^0-9]|$)`).test(String(q || ""));
const yearIn = (y: number, q: string) => new RegExp(`\\b${y}\\b`).test(String(q || ""));

// one answer (or several slices' answers) in the shape the approval and calendar_dated_periods read, keeping only what the page proves
export function calendarAiParsed(answers: any[], page: string, parser: string, cut = false) {
  const P = flat(page), on = (q: string) => flat(q).length >= 6 && P.includes(flat(q));
  const findings: Finding[] = [];
  const found = (msg: Finding) => { if (findings.length < 40 && !findings.some((f) => f.code === msg.code && f.detail === msg.detail)) findings.push({ ...msg, example: msg.example?.slice(0, 300) }) };
  const periods: Record<string, { months: Set<number>; years: Set<number>; quotes: string[]; starts: Dated[]; deadlines: Dated[] }> = {};
  const scopes: Record<string, number> = {}; let scopeQuote = "";
  const check = (x: any, where: string, period: string, yearQuote: string): Dated | null => {
    if (!x) return null;
    const m = Number(x.month), q = String(x.quote || "");
    if (!(m >= 1 && m <= 12)) { found({ code: "no_month", detail: `${where} of ${period}`, example: q }); return null }
    if (!on(q)) { found({ code: "quote_not_on_page", detail: `${where} of ${period}`, example: q }); return null }
    if (!monthIn(m, q)) { found({ code: "month_not_in_quote", detail: `${where} of ${period}`, example: q }); return null }
    let day = Number.isInteger(x.day) ? x.day : null;
    if (day && !dayIn(day, q)) { found({ code: "day_not_in_quote", detail: `${where} of ${period}`, example: q }); day = null }
    let year = Number.isInteger(x.year) ? x.year : null, yq = "";
    if (year && !yearIn(year, q)) {
      if (yearQuote && on(yearQuote) && yearIn(year, yearQuote)) yq = yearQuote.slice(0, 200);
      else { found({ code: "year_not_printed", detail: `${where} of ${period}`, example: q }); year = null }
    }
    return { year, month: m, day, date: iso(year, m, day), quote: q.slice(0, 300), ...(yq ? { year_quote: yq } : {}) };
  };
  for (const a of answers) {
    if (!a) continue;
    const sc = SCOPES.includes(a.scope) ? a.scope : "other";
    if (a.scope_quote && on(a.scope_quote)) { scopes[sc] = (scopes[sc] || 0) + 1; if (!scopeQuote) scopeQuote = String(a.scope_quote).slice(0, 300) }
    else scopes[sc] = (scopes[sc] || 0) + 0.5;
    for (const x of (a.periods || []) as any[]) {
      const key = String(x?.period || "").toLowerCase().replace(/\s+/g, " ").trim().slice(0, 60); if (!key) continue;
      const yq = String(x?.year_quote || "");
      const f = periods[key] ||= { months: new Set(), years: new Set(), quotes: [], starts: [], deadlines: [] };
      const st = check(x?.start, "start", key, yq);
      if (st) {
        const meaning = MEANINGS.includes(x?.start_meaning) ? x.start_meaning : "other";
        if (meaning !== "teaching_start") found({ code: "not_a_teaching_start", detail: `${meaning} of ${key}`, example: st.quote });
        else {
          f.months.add(st.month); if (st.year) f.years.add(st.year); if (f.quotes.length < 3) f.quotes.push(st.quote);
          if (!f.starts.some((y) => y.date === st.date && y.month === st.month && y.year === st.year)) f.starts.push({ ...st, meaning });
        }
      }
      for (const d of (x?.application_deadlines || []) as any[]) {
        const dl = check(d, "deadline", key, yq); if (!dl) continue;
        const applies = APPLIES.includes(d?.applies_to) ? d.applies_to : "unstated";
        if (!f.deadlines.some((y) => y.date === dl.date && y.applies_to === applies)) f.deadlines.push({ ...dl, applies_to: applies, rolling: false });
      }
    }
  }
  // the scope most slices support with a quote on the page
  const scope = Object.entries(scopes).sort((a, b) => b[1] - a[1])[0]?.[0] || "other";
  const list = Object.entries(periods).filter(([, f]) => f.months.size > 0 || f.deadlines.length > 0).map(([period, f]) => ({
    period, months: [...f.months].sort((a, b) => a - b), years: [...f.years].sort(), quotes: f.quotes, starts: f.starts, deadlines: f.deadlines }));
  const now = new Date().getUTCFullYear();
  const startYears = list.flatMap((p) => p.starts.map((s) => s.year || 0));
  if (!list.some((p) => p.starts.length)) found({ code: "no_dated_start", detail: "no teaching start with its month on the page" });
  else if (!startYears.some((y) => y > now)) found({ code: "next_year_missing", detail: `no teaching start after ${now}: the next year's calendar is needed` });
  if (!list.some((p) => p.deadlines.length)) found({ code: "no_deadline", detail: "no application closing date on this calendar" });
  if (scope !== "main_teaching") found({ code: "not_main_calendar", detail: scope.replace(/_/g, " "), example: scopeQuote });
  if (cut) found({ code: "document_longer_than_read", detail: "the document is longer than the reader's slices" });
  return { parser, reader: CALENDAR_READER, scope, scope_quote: scopeQuote, periods: list, findings };
}

// the dated parser's reading stands without AI only when it gives a current or future dated start and the address is a trusted main calendar
export function calendarSafe(parsed: { periods?: { starts?: { year: number | null; date: string | null }[] }[] } | null, trustedAddress: boolean, today = new Date()) {
  if (!trustedAddress) return { safe: false, reason: "the address may not be the main teaching calendar" };
  const d = today.toISOString().slice(0, 10);
  const future = (parsed?.periods || []).flatMap((p) => p.starts || []).filter((s) => s.date && s.date >= d);
  if (!future.length) return { safe: false, reason: "the dated parser found no current or future dated teaching start" };
  return { safe: true, reason: `the dated parser found ${future.length} current or future dated teaching start(s)` };
}
