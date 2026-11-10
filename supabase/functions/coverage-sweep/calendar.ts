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
// calendar-v2.1 (Platform Admin final intake recovery mandate 5 Nov 2026 12:44, R1): a year not printed in the quote is taken only from
//    the section that encloses the quoted row (sectionYear): the nearest heading above it, an ancestor heading (a higher level, never a
//    sibling such as "changing in 2028"), the document title, or the calendar's year tabs matched to repeated section headings in order
//    (UNSW "2026 | 2027" then Term 1 … Term 3 twice). The heading or tab is kept as year_quote with year_basis. A year the reader claims that
//    the section does not give is rejected (year_from_wrong_section); a quote found in sections of different years is rejected
//    (year_ambiguous); no section year at all stays "academic year unproven" (year_not_printed). Period names lose their printed year.
// calendar-v2.2 (Decisions 270 and 270a, Platform Admin 10 Nov 2026): a start printed without a year may also take its year from
//    * its table column: the nearest row above it in the same table whose cell over the date's column is one year (basis "column");
//      the date's column is the one cell of the row whose first date is the start's day and month;
//    * a range heading over unlabelled columns ("Semester dates 2026–2028"): only when the date columns number the years of the range, in
//      order, and every column of the row gives a start on the same weekday that a one-year shift would break (basis "range_columns");
//    * the address: exactly one edition year (2025–2035) in the URL path, only when no section gives a year, no heading or title names
//      another year and every year printed on the page is within a year of it (basis "address").
//    Where the page prints a weekday against the date, it must agree with the resolved date (weekday_mismatch otherwise). A column year
//    that disagrees with the section year gives no start (year_ambiguous). A year is never guessed.
// calendar-v2.3 (11 Nov 2026, Decisions 270 and 270a, first live result): a teaching start resolved by its table column stands for its whole
//    row, so every other column of that row whose first date maps to one year by the same rule (and agrees with any printed weekday) is a
//    start too, with the same quote. gpt-4.1-mini reported only the 2026 column of Monash summary-dates under v2.2.
export const CALENDAR_READER = "calendar-v2.3";
export const CALENDAR_PARSER_DATES = "provider-policy-calendar-dates-v2";
const MONTHS = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"];
const flat = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");
const SCOPES = ["main_teaching", "offshore_campus", "college_or_residence", "study_abroad_inbound", "pathway_or_foundation", "research_only", "other"];
const MEANINGS = ["teaching_start", "orientation", "enrolment", "other"];
const APPLIES = ["international", "domestic", "all", "unstated"];

export const CALENDAR_PROMPT = [
  "You read one university page or document with academic dates (an academic calendar, key dates or principal dates).",
  "1. scope: which students this calendar is for: main_teaching (the university's main coursework teaching periods at its home campuses), offshore_campus (a campus in another country), college_or_residence (a residential or affiliated college), study_abroad_inbound (exchange or study abroad students), pathway_or_foundation (a foundation, diploma or English pathway provider), research_only, or other. Copy the sentence or heading that shows it (scope_quote).",
  "2. periods: every study period (Semester 1, Trimester 2, Term 3, Autumn session, Teaching period 1, Summer school and similar). For each, the date it starts, exactly as printed: year, month and day (null when not printed). Copy the exact row or sentence that gives that date (start_quote). If the year is not printed in that row, give the year of the section that encloses the row: the heading above it, the page title, or the year tab the section sits under (pages often show one block of identical headings per year, in the order of their year tabs); copy that heading or tab as year_quote. Never take a year from a neighbouring section, a note about future changes or another year's block; leave the year null if the enclosing section shows none. Give the period name without its year. Give start_meaning: teaching_start when classes or teaching begin, orientation for orientation or O-week, enrolment for enrolment or census, other otherwise. Give the end date the same way when printed (end_quote). In a table with one column per year, report the start once for each year column, each with that column's date, and copy the whole row as start_quote. In a table of teaching weeks, a period's teaching start is the date of its week 1 row under that period's section row (for example Semester one), not orientation.",
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
type Dated = { year: number | null; month: number; day: number | null; date: string | null; quote: string; year_quote?: string; year_basis?: string; applies_to?: string; meaning?: string; rolling?: false };
const iso = (y: number | null, m: number, d: number | null) => {
  if (!y || !d) return null;
  const t = new Date(Date.UTC(y, m - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d ? t.toISOString().slice(0, 10) : null;
};
const monthIn = (m: number, q: string) => { const l = String(q || "").toLowerCase(); return l.includes(MONTHS[m - 1].slice(0, 3)) || new RegExp(`\\b0?${m}[/.-]`).test(l) };
const dayIn = (d: number, q: string) => new RegExp(`(^|[^0-9])0?${d}(st|nd|rd|th)?([^0-9]|$)`).test(String(q || ""));
const yearIn = (y: number, q: string) => new RegExp(`\\b${y}\\b`).test(String(q || ""));

// R1: the year of the section that encloses a quoted row. Headings are markdown "#" lines; a bold-only first line is the document title.
type SectionYear = { year: number | null; basis: "heading" | "title" | "tabs" | null; quote: string; reason?: "year_ambiguous" | "year_not_printed" };
const HEAD = /^\s{0,3}(#{1,6})\s+(.*\S)\s*$/;
const yearsOf = (s: string) => [...new Set((String(s).match(/\b20\d\d\b/g) || []).map(Number))];
function lineYear(lines: string[], idx: number): SectionYear {
  // 1. nearest heading, then ancestors only (strictly higher level), then the title line
  let level = 7;
  for (let i = idx - 1; i >= 0; i--) {
    const h = lines[i].match(HEAD); if (!h || h[1].length >= level) continue;
    level = h[1].length; const ys = yearsOf(h[2]);
    if (ys.length === 1) return { year: ys[0], basis: "heading", quote: lines[i].trim().slice(0, 200) };
    if (ys.length > 1) return { year: null, basis: null, quote: lines[i].trim().slice(0, 200), reason: "year_ambiguous" };
    if (level === 1) break;
  }
  const first = lines.findIndex((l) => l.trim()); const title = first >= 0 && first < idx ? lines[first].trim() : "";
  if (/^\*\*[^*]+\*\*$/.test(title) && !HEAD.test(title)) {
    const ys = yearsOf(title); if (ys.length === 1) return { year: ys[0], basis: "title", quote: title.slice(0, 200) };
  }
  // 2. year tabs ("  - 2026", "  - 2027") above repeated identical section headings: the k-th block of a heading is the k-th tab year
  const tabLines: number[] = []; const tabs: number[] = [];
  lines.forEach((l, i) => { const t = l.match(/^\s*[-*]\s*(20\d\d)\s*$/); if (t && i < idx) { tabLines.push(i); if (tabs[tabs.length - 1] !== Number(t[1])) tabs.push(Number(t[1])) } });
  if (tabs.length >= 2 && new Set(tabs).size === tabs.length) {
    let hi = -1; for (let i = idx - 1; i > tabLines[tabLines.length - 1]; i--) if (HEAD.test(lines[i])) { hi = i; break }
    if (hi > 0) {
      const text = lines[hi].trim(), lvl = (lines[hi].match(HEAD) as RegExpMatchArray)[1].length;
      const at = lines.map((l, i) => (l.trim() === text && i > tabLines[tabLines.length - 1] ? i : -1)).filter((i) => i >= 0);
      const k = at.indexOf(hi);
      if (at.length === tabs.length && k >= 0) {
        const y = tabs[k];
        // the block's printed years must agree (the year itself, or the year before for a summer term that starts in December)
        let end = lines.length; for (let i = hi + 1; i < lines.length; i++) { const h = lines[i].match(HEAD); if (h && h[1].length <= lvl) { end = i; break } }
        const printed = yearsOf(lines.slice(hi + 1, end).join("\n"));
        if (printed.every((p) => p === y || p === y - 1))
          return { year: y, basis: "tabs", quote: `year tabs ${tabs.join(" | ")}: block ${k + 1} of "${text}" is ${y}`.slice(0, 200) };
      }
    }
  }
  return { year: null, basis: null, quote: "", reason: "year_not_printed" };
}
export function sectionYear(page: string, quote: string): SectionYear {
  const lines = String(page || "").split("\n"), fq = flat(quote);
  if (fq.length < 6) return { year: null, basis: null, quote: "", reason: "year_not_printed" };
  const at: number[] = [];
  // the quoted row; a quote across two lines counts from its second line when the first is a heading (the row sits under that heading)
  lines.forEach((l, i) => {
    if (flat(l).includes(fq)) at.push(i);
    else if (i + 1 < lines.length && !flat(lines[i + 1]).includes(fq) && flat(l + "\n" + lines[i + 1]).includes(fq)) at.push(HEAD.test(l) ? i + 1 : i);
  });
  if (!at.length) return { year: null, basis: null, quote: "", reason: "year_not_printed" };
  const ys = at.map((i) => lineYear(lines, i));
  const known = [...new Set(ys.map((y) => y.year))];
  if (known.length > 1) return { year: null, basis: null, quote: "", reason: "year_ambiguous" };
  return ys[0];
}
// calendar-v2.2 (Decisions 270, 270a): table columns, range headings over unlabelled columns, the address, and printed weekdays.
type EditionYear = { year: number | null; basis: "column" | "range_columns" | "address" | null; quote: string; reason?: string };
const EDITION = (y: number) => y >= 2025 && y <= 2035;  // fixed: the edition-year window of Decision 270
const WEEKDAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
const plain = (s: string) => String(s || "").replace(/<br\s*\/?>/gi, " ").replace(/[*_^\\]/g, " ").replace(/\s+/g, " ").trim();
const rowCells = (line: string) => line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map(plain);
const isRow = (line: string) => /^\s*\|.*\|\s*$/.test(line);
const isRule = (line: string) => /^\s*\|(\s*:?-{3,}:?\s*\|)+\s*$/.test(line);
const monthOf = (w: string) => { const l = w.toLowerCase().replace(/\.$/, ""); const i = l.length >= 3 ? MONTHS.findIndex((m) => m.startsWith(l)) : -1; return i + 1 };
// the first date printed in a cell, as day and month ("1 Mar – 25 Jun", "19–27 Feb", "Monday 4 January 2027")
function firstDate(cell: string): { d: number; m: number } | null {
  const t = cell.match(/(\d{1,2})(?:st|nd|rd|th)?(?:\s*[–-]\s*\d{1,2})?\s+([A-Za-z]{3,9}\.?)/);
  if (!t) return null;
  const m = monthOf(t[2]); return m ? { d: Number(t[1]), m } : null;
}
const weekday = (y: number, m: number, d: number) => new Date(Date.UTC(y, m - 1, d)).getUTCDay();
// the weekdays printed against one day and month in a text ("Monday 1 March", "Mon 4 Oct", "Tue, Sep 8")
export function printedWeekdays(text: string, m: number, d: number): number[] {
  const mon = MONTHS[m - 1].slice(0, 3), out: number[] = [];
  const res = [new RegExp(`\\b(sun|mon|tue|wed|thu|fri|sat)[a-z]*\\.?,?\\s+0?${d}(?:st|nd|rd|th)?\\s+${mon}`, "gi"),
    new RegExp(`\\b(sun|mon|tue|wed|thu|fri|sat)[a-z]*\\.?,?\\s+${mon}[a-z]*\\.?\\s+0?${d}(?![0-9])`, "gi")];
  for (const re of res) for (const x of plain(text).matchAll(re)) out.push(WEEKDAYS.indexOf(x[1].toLowerCase().slice(0, 3)));
  return [...new Set(out)];
}
export function columnYear(page: string, quote: string, m: number, d: number): EditionYear | null {
  const lines = String(page || "").split("\n"), fq = flat(quote);
  if (fq.length < 6) return null;
  const at = lines.map((l, i) => (isRow(l) && flat(l).includes(fq) ? i : -1)).filter((i) => i >= 0);
  if (!at.length) return null;
  const found: EditionYear[] = [];
  for (const i of at) {
    const cells = rowCells(lines[i]);
    const k = cells.map((c, j) => { const f = firstDate(c); return f && f.d === d && f.m === m ? j : -1 }).filter((j) => j >= 0);
    if (k.length !== 1) { found.push({ year: null, basis: null, quote: "", reason: k.length ? "year_ambiguous" : "column_not_found" }); continue }
    let t0 = i; while (t0 > 0 && isRow(lines[t0 - 1])) t0--;
    // 1. the nearest row above in the same table whose cell over the date's column is one edition year
    let col: EditionYear | null = null;
    for (let h = i - 1; h >= t0; h--) {
      if (isRule(lines[h])) continue;
      const hc = rowCells(lines[h]); if (hc.length !== cells.length) continue;
      const years = hc.map((c) => (/^(20\d\d)$/.test(c) ? Number(c) : 0));
      if (years.filter(Boolean).length < 2) continue;
      const y = years[k[0]];
      col = y && EDITION(y) ? { year: y, basis: "column", quote: lines[h].trim().slice(0, 200) } : { year: null, basis: null, quote: "", reason: "year_not_printed" };
      break;
    }
    if (col) { found.push(col); continue }
    // 2. Decision 270a: a range heading over unlabelled date columns, validated by weekday and academic period
    let head = ""; for (let h = t0 - 1; h >= 0; h--) { if (HEAD.test(lines[h])) { head = lines[h].trim(); break } if (isRow(lines[h])) break }
    const r = head.match(/\b(20\d\d)\s*[–-]\s*(20\d\d)\b/);
    if (!r) continue;
    const a = Number(r[1]), b = Number(r[2]), n = b - a + 1;
    if (!(n >= 2 && EDITION(a) && EDITION(b)) || cells.length - 1 !== n || k[0] < 1) { found.push({ year: null, basis: null, quote: "", reason: "range_columns_unproved" }); continue }
    const dates = cells.slice(1).map(firstDate);
    // weekday evidence: every column's start falls on the same weekday under this mapping (a one-year shift moves them all, so this alone
    // is not enough); academic-period evidence, at least one of: the starts are Mondays (a teaching period opens on a Monday), or another
    // row of the same table prints one year per column, rising by one across the columns in step with the mapping ("11–15 Jan (2027)")
    const wds = dates.every(Boolean) ? [...new Set(dates.map((x, j) => weekday(a + j, x!.m, x!.d)))] : [];
    let tEnd = i; while (tEnd + 1 < lines.length && isRow(lines[tEnd + 1])) tEnd++;
    const stepRow = lines.slice(t0, tEnd + 1).some((l, j) => {
      if (t0 + j === i) return false;
      const c = rowCells(l); if (c.length !== cells.length) return false;
      const ys = c.slice(1).map((x) => { const y = yearsOf(x); return y.length === 1 ? y[0] : 0 });
      return ys.every(Boolean) && ys.every((y, q) => y - q === ys[0]) && (ys[0] === a || ys[0] === a + 1);
    });
    const months = dates.filter(Boolean).map((x) => x!.m), spread = Math.max(...months) - Math.min(...months);
    if (wds.length === 1 && (wds[0] === 1 || stepRow) && spread <= 1) found.push({ year: a + k[0] - 1, basis: "range_columns", quote: `${head.slice(0, 120)}: column ${k[0]} of ${n}`.slice(0, 200) });
    else found.push({ year: null, basis: null, quote: "", reason: "range_columns_unproved" });
  }
  if (!found.length) return null;
  const years = [...new Set(found.map((f) => f.year))];
  if (years.length > 1) return { year: null, basis: null, quote: "", reason: "year_ambiguous" };
  return found[0];
}
// v2.3: a teaching start resolved by its column stands for its whole row: every other column of the same row whose first date maps to
// one year by the same rule is a start too (same quote). The model often reports only one column (Monash summary-dates, 11 Nov 2026).
export function columnSiblings(page: string, quote: string): Dated[] {
  const rows = String(page || "").split("\n").filter((l) => isRow(l) && flat(l).includes(flat(quote)));
  if (rows.length !== 1 || flat(quote).length < 6) return [];
  const out: Dated[] = [];
  for (const c of rowCells(rows[0]).slice(1)) {
    const f = firstDate(c); if (!f) continue;
    const cy = columnYear(page, quote, f.m, f.d);
    if (!cy || !cy.year || !(cy.basis === "column" || cy.basis === "range_columns")) continue;
    if (printedWeekdays(c, f.m, f.d).some((w) => w !== weekday(cy.year!, f.m, f.d))) continue;
    const date = iso(cy.year, f.m, f.d); if (!date) continue;
    out.push({ year: cy.year, month: f.m, day: f.d, date, quote: quote.slice(0, 300), year_quote: cy.quote, year_basis: cy.basis });
  }
  return out;
}
export function addressYear(url: string, page: string): EditionYear | null {
  let path = ""; try { path = new URL(url).pathname } catch { return null }
  const ys = yearsOf(path).filter(EDITION);
  if (ys.length !== 1) return null;
  const y = ys[0], lines = String(page || "").split("\n");
  const heads = lines.filter((l) => HEAD.test(l) || /^\*\*[^*]+\*\*$/.test(l.trim())).flatMap(yearsOf);
  if (heads.some((h) => h !== y)) return { year: null, basis: null, quote: "", reason: "year_ambiguous" };
  if (yearsOf(page).some((p) => Math.abs(p - y) > 1)) return { year: null, basis: null, quote: "", reason: "year_ambiguous" };
  return { year: y, basis: "address", quote: `address ${path}`.slice(0, 200) };
}

export const periodName = (s: string) => String(s || "").toLowerCase().replace(/\b(19|20)\d\d\b/g, " ").replace(/[()]/g, " ").replace(/\s+/g, " ").trim().slice(0, 60);

// one answer (or several slices' answers) in the shape the approval and calendar_dated_periods read, keeping only what the page proves
export function calendarAiParsed(answers: any[], page: string, parser: string, cut = false, address = "") {
  const P = flat(page), on = (q: string) => flat(q).length >= 6 && P.includes(flat(q));
  const findings: Finding[] = [];
  const found = (msg: Finding) => { if (findings.length < 40 && !findings.some((f) => f.code === msg.code && f.detail === msg.detail)) findings.push({ ...msg, example: msg.example?.slice(0, 300) }) };
  const periods: Record<string, { months: Set<number>; years: Set<number>; quotes: string[]; starts: Dated[]; deadlines: Dated[] }> = {};
  const scopes: Record<string, number> = {}; let scopeQuote = "";
  const check = (x: any, where: string, period: string, yearQuote: string, rawPeriod = ""): Dated | null => {
    if (!x) return null;
    const m = Number(x.month), q = String(x.quote || "");
    if (!(m >= 1 && m <= 12)) { found({ code: "no_month", detail: `${where} of ${period}`, example: q }); return null }
    if (!on(q)) { found({ code: "quote_not_on_page", detail: `${where} of ${period}`, example: q }); return null }
    if (!monthIn(m, q)) { found({ code: "month_not_in_quote", detail: `${where} of ${period}`, example: q }); return null }
    let day = Number.isInteger(x.day) ? x.day : null;
    if (day && !dayIn(day, q)) { found({ code: "day_not_in_quote", detail: `${where} of ${period}`, example: q }); day = null }
    // R1: a year printed in the quote stands; otherwise only the enclosing section's year, and the reader's claim must agree with it
    let year = Number.isInteger(x.year) ? x.year : null, yq = "", basis = "";
    // the reader's claim: its year, else (for a start) the one year in its year_quote or period name
    const one = (t: string) => (yearsOf(t).length === 1 ? yearsOf(t)[0] : null);
    const claimed = year || (where === "start" ? one(yearQuote) || one(rawPeriod) : null);
    if (!(year && yearIn(year, q)) && where === "deadline") {
      // a closing date often falls in the year before its section's year: it is a date only when its own row prints the year
      found({ code: "year_not_printed", detail: `${where} of ${period}`, example: q }); year = null;
    } else if (!(year && yearIn(year, q))) {
      // v2.2 (Decisions 270, 270a): the date's table column first, then the enclosing section, then the address; they must not disagree
      const sec = sectionYear(page, q);
      const col = day ? columnYear(page, q, m, day) : null;
      let sy: { year: number | null; basis: string | null; quote: string; reason?: string } = sec;
      if (col && col.year) sy = sec.year && sec.year !== col.year ? { year: null, basis: null, quote: "", reason: "year_ambiguous" } : col;
      else if (col && col.reason && col.reason !== "column_not_found" && !sec.year) sy = { ...col };
      if (!sy.year && sy.reason === "year_not_printed" && address) { const ad = addressYear(address, page); if (ad) sy = ad }
      if (sy.year && claimed && claimed !== sy.year) { found({ code: "year_from_wrong_section", detail: `${where} of ${period}: ${claimed} claimed, the section gives ${sy.year}`, example: q }); year = null }
      else if (sy.year) { year = sy.year; yq = sy.quote; basis = sy.basis || "" }
      else { found({ code: sy.reason || "year_not_printed", detail: `${where} of ${period}`, example: q }); year = null }
    } else {
      basis = "quote";
      // v2.2: in a row printing several years, the year must be in the date's own cell (2 March 2026 | 1 March 2027 | 28 February 2028)
      if (day && yearsOf(q).length > 1 && q.includes("|")) {
        const own = rowCells(q).filter((c) => { const f = firstDate(c); return f && f.d === day && f.m === m });
        if (own.length !== 1 || !yearIn(year as number, own[0])) { found({ code: "year_from_wrong_section", detail: `${where} of ${period}: ${year} is not in the date's own cell`, example: q }); year = null; basis = "" }
      }
    }
    // v2.2 (Decision 270): a weekday printed against the date must agree with the resolved date
    if (year && day) {
      const wd = printedWeekdays(q, m, day);
      if (wd.length && (wd.length > 1 || wd[0] !== weekday(year, m, day))) { found({ code: "weekday_mismatch", detail: `${where} of ${period}: ${year}`, example: q }); year = null; yq = ""; basis = "" }
    }
    return { year, month: m, day, date: iso(year, m, day), quote: q.slice(0, 300), ...(yq ? { year_quote: yq } : {}), ...(year && basis ? { year_basis: basis } : {}) };
  };
  for (const a of answers) {
    if (!a) continue;
    const sc = SCOPES.includes(a.scope) ? a.scope : "other";
    if (a.scope_quote && on(a.scope_quote)) { scopes[sc] = (scopes[sc] || 0) + 1; if (!scopeQuote) scopeQuote = String(a.scope_quote).slice(0, 300) }
    else scopes[sc] = (scopes[sc] || 0) + 0.5;
    for (const x of (a.periods || []) as any[]) {
      const raw = String(x?.period || ""), key = periodName(raw); if (!key) continue;
      const yq = String(x?.year_quote || "");
      const f = periods[key] ||= { months: new Set(), years: new Set(), quotes: [], starts: [], deadlines: [] };
      const st = check(x?.start, "start", key, yq, raw);
      if (st) {
        const meaning = MEANINGS.includes(x?.start_meaning) ? x.start_meaning : "other";
        if (meaning !== "teaching_start") found({ code: "not_a_teaching_start", detail: `${meaning} of ${key}`, example: st.quote });
        else {
          f.months.add(st.month); if (st.year) f.years.add(st.year); if (f.quotes.length < 3) f.quotes.push(st.quote);
          if (!f.starts.some((y) => y.date === st.date && y.month === st.month && y.year === st.year)) f.starts.push({ ...st, meaning });
          // v2.3: the other year columns of a column-resolved row are starts of the same period
          if (st.year_basis === "column" || st.year_basis === "range_columns")
            for (const sib of columnSiblings(page, st.quote))
              if (!f.starts.some((y) => y.date === sib.date)) { f.starts.push({ ...sib, meaning }); if (sib.year) f.years.add(sib.year) }
        }
      }
      for (const d of (x?.application_deadlines || []) as any[]) {
        const dl = check(d, "deadline", key, yq, raw); if (!dl) continue;
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
