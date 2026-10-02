// CF-247 Decision 227 (2 Oct 2026): parsers for institution-level documents read by mode provider_facts.
// Deterministic only (no model). Nothing here writes to the catalogue: the results become proposals that a
// Platform Admin approves.
//  * englishPolicy: the provider's default English requirement by study level (undergraduate, postgraduate
//    coursework) and the courses it names as exceptions. A default is taken only where the document says it applies
//    to all (or the standard) courses of that level; course-by-course pages, English bands and faculty tables are
//    reported, not turned into a default.
//  * calendarStarts: the months in which each semester or trimester starts, from an academic calendar.
export const POLICY_PARSER = "provider-policy-v0.1.0";

export type TestCode = "IELTS" | "PTE" | "TOEFL_IBT" | "CAE";
export type Req = { test_code: TestCode; overall_score: number; component_scores: Record<string, number>; quote: string };
type Level = "undergraduate" | "postgraduate";

const clean = (s: string) => String(s ?? "").replace(/<br\s*\/?>/gi, " ").replace(/\*\*|__|`/g, "").replace(/\\([*_|])/g, "$1").replace(/\[([^\]]*)\]\([^)]*\)/g, "$1").replace(/\s+/g, " ").trim();

const TESTS: { code: TestCode; re: RegExp; range: [number, number]; comp: [number, number]; decimals: boolean }[] = [
  { code: "IELTS", re: /\bIELTS\b/i, range: [4, 9], comp: [4, 9], decimals: true },
  { code: "PTE", re: /\bPTE\b|Pearson/i, range: [30, 90], comp: [30, 90], decimals: false },
  { code: "TOEFL_IBT", re: /TOEFL/i, range: [32, 120], comp: [1, 30], decimals: false },
  { code: "CAE", re: /Cambridge|C1 Advanced|\bCAE\b|C2 Proficiency/i, range: [140, 230], comp: [140, 230], decimals: false },
];
const OTHER_TEST = /\b(IELTS|PTE|Pearson|TOEFL|Cambridge|C1 Advanced|CAE|C2 Proficiency|Duolingo|DET|OET|Occupational English|LanguageCert|Michigan|MET)\b/i;
const SKILLS = ["listening", "reading", "writing", "speaking"];
const NUM = "(\\d{1,3}(?:\\.\\d)?)";

function inRange(v: number, r: [number, number], decimals: boolean) {
  if (!(v >= r[0] && v <= r[1])) return false;
  return decimals ? Math.abs(v * 2 - Math.round(v * 2)) < 1e-9 : Number.isInteger(v);
}

// One test's score from a short text (a table cell, or the words after the test name).
export function parseScore(code: TestCode, text: string): { overall: number; comps: Record<string, number> } | null {
  const t = TESTS.find((x) => x.code === code)!;
  const s = clean(text).replace(/[–—]/g, "-");
  if (/not accepted|not applicable|^n\/?a$|^-$/i.test(s)) return null;
  const ok = (v: number) => inRange(v, t.range, t.decimals);
  const okc = (v: number) => inRange(v, t.comp, t.decimals);
  let overall: number | null = null;
  for (const re of [new RegExp(`(?:overall|total)(?: band)?(?: score)?(?: of| minimum| min\\.?| at least| is|:)*\\s*[:=\\-]?\\s*${NUM}(?!\\d)`, "i"),
                    new RegExp(`${NUM}\\s*(?:\\(|,)?\\s*(?:or (?:above|higher|better|more)\\s*)?(?:overall|total)`, "i"),
                    new RegExp(`^\\s*(?:min(?:imum)?\\.?\\s*(?:of\\s*)?)?${NUM}(?!\\d|\\s*(?:in|for|on) (?:each|all|every|listening|reading|writing|speaking)|\\s*-\\s*\\d)`, "i")]) {
    const m = s.match(re);
    if (m && ok(Number(m[1]))) { overall = Number(m[1]); break }
  }
  if (overall == null) return null;
  const comps: Record<string, number> = {};
  const all = s.match(new RegExp(`no (?:individual |single |other )?(?:band|section|sub-?test|sub-?score|skill|component|communicative skill|score)s?(?: score)?(?: (?:less|lower) than| below| under)\\s*${NUM}`, "i"))
    || s.match(new RegExp(`${NUM}\\s*(?:or (?:above|higher|more|better)\\s*)?(?:in|for|on) (?:each|all|every)(?: of the)?(?: four)?(?: (?:band|section|sub-?test|skill|component|communicative skill|sub-?score)s?)?`, "i"))
    || s.match(new RegExp(`(?:each|all|every) (?:band|section|sub-?test|skill|component|communicative skill|sub-?score)s?(?: (?:of|at least|minimum|min\\.?))*\\s*[:\\-]?\\s*${NUM}`, "i"))
    || s.match(new RegExp(`(?:minimum|min\\.?) (?:band|section|sub-?test|skill|component|sub-?score)(?: score)?(?: of)?\\s*${NUM}`, "i"));
  if (all && okc(Number(all[1]))) for (const k of SKILLS) comps[k] = Number(all[1]);
  // named skills: "6.0 Speaking", "7.0 in writing & reading", "Writing 27", "Writing: 6.0"
  for (const m of s.matchAll(new RegExp(`${NUM}\\s*(?:in\\s+)?((?:(?:listening|reading|writing|speaking)(?:\\s*(?:,|&|and|\\/)\\s*)?)+)`, "gi"))) {
    const v = Number(m[1]); if (!okc(v)) continue;
    for (const k of SKILLS) if (new RegExp(k, "i").test(m[2])) comps[k] = v;
  }
  for (const m of s.matchAll(new RegExp(`\\b(listening|reading|writing|speaking)\\s*[:\\-]?\\s*${NUM}(?!\\d)`, "gi"))) {
    const v = Number(m[2]); if (okc(v) && !(m[1].toLowerCase() in comps)) comps[m[1].toLowerCase()] = v;
  }
  const other = s.match(new RegExp(`${NUM}\\s*(?:in|for) (?:the )?(?:other|remaining) (?:band|section|sub-?test|skill|component)s?`, "i"));
  if (other && okc(Number(other[1]))) for (const k of SKILLS) if (!(k in comps)) comps[k] = Number(other[1]);
  return { overall, comps };
}

export function levelOf(s: string): Level | "both" | "research" | null {
  const x = clean(s);
  if (/\b(higher degrees? by research|research degrees?|research programs?|HDR|PhD|doctor of philosophy|masters? (?:by|of) research|postgraduate research)\b/i.test(x)
      && !/coursework/i.test(x)) return "research";
  const pg = /\b(post-?graduate|graduate (?:certificate|diploma)s?|master(?:'?s)?|coursework|PG)\b/i.test(x);
  const ug = /\b(under-?graduate|bachelor(?:'?s)?|associate degrees?|UG)\b/i.test(x);
  if (pg && ug) return "both";
  if (pg) return "postgraduate";
  if (ug) return "undergraduate";
  if (/\ball (?:(?:of )?(?:our|the|other|remaining) )?(?:coursework )?(?:courses|programs?|programmes|degrees)\b/i.test(x)) return "both";
  return null;
}

const DEFAULT_CUE = /\b(all|standard|general|minimum|most|default|other|remaining|unless (?:otherwise )?(?:stated|specified|listed|noted)|except(?: for)?(?: those)?(?: (?:listed|specified|shown))?|applicable to all|majority)\b/i;
const AWARD = /\b(Bachelor|Master|Graduate Certificate|Graduate Diploma|Doctor|Diploma|Associate Degree|Juris Doctor|Certificate (?:I|II|III|IV))\b/;
const PLAIN_LEVEL = /^(?:(?:all|our|standard|general|minimum)\s+)?(?:under-?graduate|post-?graduate(?: coursework)?|coursework|(?:under|post)graduate and (?:under|post)graduate(?: coursework)?)(?: (?:courses|programs?|programmes|degrees|study|entry|admission))?(?: requirements?)?\s*:?$/i;
const COURSE_SPECIFIC = /\b(?:listed|shown|found|stated|specified|published|available|detailed) (?:on|in) (?:the |each |your |individual |relevant )*(?:course|program|programme|degree)(?:'s)? (?:page|entry|details|listing|information|handbook)|minimum (?:required )?scores? for each (?:course|program)|(?:check|see|refer to) (?:the |each |your |individual )*(?:course|program)(?:'s)? (?:page|entry requirements|details)/i;
const BAND_LABEL = /^(?:english )?(?:language )?(?:band|level|category|group|tier|standard)\s*[A-E1-9]\b|^[A-E1-9]$|^(?:band|level) \d/i;

function namesFrom(label: string): string[] {
  const x = clean(label).replace(/^(?:exceptions?|except|the following (?:courses|programs?) require[^:]*):?\s*/i, "");
  // split before each award word; a discipline list ("Exercise Science, Human Nutrition") is kept as phrases
  const parts = AWARD.test(x) ? x.split(/(?=\b(?:Bachelor|Master|Graduate Certificate|Graduate Diploma|Doctor|Diploma|Associate Degree|Juris Doctor)\b)/) : x.split(/\s*(?:,|;|•|\s{2,})\s*/);
  return parts.map((p) => p.replace(/[:;,.\s]+$/, "").replace(/\s*\((?:including|incl\.?)[^)]*\)\s*$/i, "").trim()).filter((p) => p.length >= 4 && p.length <= 160 && !/^(and|or|the|all|other)$/i.test(p));
}

type Block = { kind: "table"; heading: string; rows: string[][] } | { kind: "text"; heading: string; text: string };
function blocks(md: string): Block[] {
  const out: Block[] = [];
  let heading = "", table: string[][] | null = null;
  const lines = md.replace(/\r/g, "").split("\n");
  for (const raw of lines) {
    const line = raw.trim();
    if (line.startsWith("|")) {
      const cells = line.replace(/^\||\|$/g, "").split("|").map((c) => clean(c.replace(/<br\s*\/?>/gi, " ; ")));
      if (cells.every((c) => /^:?-{2,}:?$/.test(c) || c === "")) continue;
      if (!table) { table = []; out.push({ kind: "table", heading, rows: table }) }
      table.push(cells);
      continue;
    }
    table = null;
    if (!line) continue;
    const h = line.match(/^#{1,6}\s+(.*)$/) || line.match(/^\*\*([^*]{2,120})\*\*:?$/);
    if (h) { heading = clean(h[1]); continue }
    out.push({ kind: "text", heading, text: clean(line.replace(/^[-*+]\s+/, "")) });
  }
  return out;
}

const quoteOf = (s: string) => clean(s).slice(0, 300);

// Every course the document names ("Bachelor of Nursing", "Master of Teaching (Secondary)"): a course the policy names
// is never given the level default, because the policy may set a different requirement for it.
const NAMED = /\b(Bachelor|Master|Graduate Certificate|Graduate Diploma|Doctor|Advanced Diploma|Diploma|Associate Degree|Juris Doctor)(?:'?s)? (?:of|in) [A-Z(][^.;:|\n]{2,90}/g;
export function namedCourses(md: string): string[] {
  const out = new Set<string>();
  for (const m of clean(md.replace(/<br\s*\/?>/gi, " ; ").replace(/\|/g, " ; ")).matchAll(NAMED)) {
    const n = m[0].split(/\s+(?:-|–|—)\s+|\s+(?:IELTS|TOEFL|PTE|Pearson|Cambridge|requires?|must|will|is|are|has|have|need|with|overall|minimum|min\.?|and (?:a|an|the)\b)\b|\s+\d/i)[0]
      .replace(/[\s,(]+$/, "").replace(/\s*\((?:including|incl\.?)[^)]*$/i, "").trim();
    if (n.split(" ").length >= 3 && n.length <= 100) out.add(n);
    if (out.size >= 300) break;
  }
  return [...out];
}

export function englishPolicy(md: string) {
  const defaults: Record<Level, Map<TestCode, Req[]>> = { undergraduate: new Map(), postgraduate: new Map() };
  const exceptions: { name: string; level: Level | "both" | null; reqs: Req[] }[] = [];
  const signals = new Set<string>();
  const addDefault = (lv: Level | "both", r: Req) => {
    for (const l of (lv === "both" ? ["undergraduate", "postgraduate"] : [lv]) as Level[]) {
      const list = defaults[l].get(r.test_code) || []; list.push(r); defaults[l].set(r.test_code, list);
    }
  };
  if (COURSE_SPECIFIC.test(clean(md))) signals.add("course_specific");
  for (const b of blocks(md)) {
    if (b.kind === "table") {
      if (b.rows.length < 2) continue;
      const head = b.rows[0];
      const testCol = head.map((c) => TESTS.find((t) => t.re.test(c) && !/equivalen/i.test(c))?.code || null);
      const levelCol = head.map((c) => { const l = levelOf(c); return l === "undergraduate" || l === "postgraduate" || l === "both" ? l : null });
      if (testCol.filter(Boolean).length >= 1 && levelCol.slice(1).filter(Boolean).length === 0) {
        // columns are tests; each row is a course group
        const labels = b.rows.slice(1).map((r) => r.filter((_, i) => !testCol[i]).join(" ").trim());
        if (labels.filter((l) => BAND_LABEL.test(l)).length >= 2) { signals.add("bands"); continue }
        // an IELTS-to-other-test conversion table (first column is an IELTS score) is not a requirement
        if (labels.filter((l) => /^\d(?:\.\d)?$/.test(l)).length >= 2) { signals.add("equivalence_table"); continue }
        b.rows.slice(1).forEach((r, k) => {
          const label = labels[k];
          const lv = levelOf(label) || levelOf(b.heading);
          if (!lv || lv === "research") return;
          const reqs: Req[] = [];
          r.forEach((cell, i) => { const code = testCol[i]; if (!code) return; const p = parseScore(code, cell); if (p) reqs.push({ test_code: code, overall_score: p.overall, component_scores: p.comps, quote: quoteOf(`${label} | ${head[i]}: ${cell}`) }) });
          if (!reqs.length) return;
          const isDefault = PLAIN_LEVEL.test(label) || label === "" ? true : (DEFAULT_CUE.test(label) && !AWARD.test(label.replace(/^.*?\b(?:except|unless)\b/i, "")) ) || (DEFAULT_CUE.test(label) && /\bexcept\b/i.test(label));
          if (isDefault) reqs.forEach((q) => addDefault(lv, q));
          else for (const n of namesFrom(label)) exceptions.push({ name: n, level: lv, reqs });
        });
        continue;
      }
      if (levelCol.filter(Boolean).length >= 1) {
        // columns are levels; rows are tests (a default) or faculties (not a default unless every row agrees)
        const rows = b.rows.slice(1);
        const rowTest = rows.map((r) => TESTS.find((t) => t.re.test(r[0]))?.code || null);
        if (rowTest.filter(Boolean).length === rows.length) {
          rows.forEach((r, k) => r.forEach((cell, i) => { const lv = levelCol[i]; if (!lv || i === 0) return; const p = parseScore(rowTest[k]!, cell); if (p) addDefault(lv, { test_code: rowTest[k]!, overall_score: p.overall, component_scores: p.comps, quote: quoteOf(`${r[0]} | ${head[i]}: ${cell}`) }) }));
        } else {
          signals.add("by_faculty");
          const code = TESTS.find((t) => t.re.test(b.heading))?.code || (TESTS.find((t) => t.re.test(head[0]))?.code ?? null);
          if (!code) continue;
          levelCol.forEach((lv, i) => {
            if (!lv) return;
            const cells = rows.map((r) => r[i] || "").filter(Boolean);
            const parsed = cells.map((c) => parseScore(code, c));
            const keys = new Set(parsed.map((p) => JSON.stringify(p)));
            if (parsed.length >= 2 && keys.size === 1 && parsed[0]) addDefault(lv, { test_code: code, overall_score: parsed[0].overall, component_scores: parsed[0].comps, quote: quoteOf(`${head[i]}: ${cells[0]} (every faculty)`) });
          });
        }
      }
      continue;
    }
    // text: "Undergraduate: IELTS 6.5 overall with no band below 6.0"
    const text = b.text;
    if (!OTHER_TEST.test(text)) continue;
    const lv = levelOf(text) || levelOf(b.heading);
    if (!lv || lv === "research") continue;
    const awardInText = AWARD.test(text.replace(/\b(?:bachelor|master)(?:'?s)? (?:degrees?|programs?|courses?|level)\b/gi, ""));
    const isDefault = !awardInText && (DEFAULT_CUE.test(text) || PLAIN_LEVEL.test(b.heading) || /\b(?:under|post)-?graduate\b/i.test(text));
    if (!isDefault) continue;
    for (const t of TESTS) {
      for (const m of text.matchAll(new RegExp(t.re.source, "gi"))) {
        const at = m.index || 0;
        let win = text.slice(at, at + 200);
        const cut = win.slice(m[0].length).search(OTHER_TEST); if (cut >= 0) win = win.slice(0, cut + m[0].length);
        const p = parseScore(t.code, win.slice(m[0].length).replace(/^[^\d]{0,60}?(?=(?:overall|total|min|\d))/i, ""));
        if (p) { addDefault(lv, { test_code: t.code, overall_score: p.overall, component_scores: p.comps, quote: quoteOf(text.slice(Math.max(0, at - 80), at + 200)) }); break }
      }
    }
  }
  const out: Partial<Record<Level, Req[]>> = {};
  const conflicts: string[] = [];
  for (const lv of ["undergraduate", "postgraduate"] as Level[]) {
    const reqs: Req[] = [];
    for (const [code, list] of defaults[lv]) {
      const keys = new Set(list.map((r) => `${r.overall_score}|${JSON.stringify(r.component_scores)}`));
      const overalls = new Set(list.map((r) => r.overall_score));
      if (overalls.size > 1) { conflicts.push(`${lv} ${code}`); continue }
      // same overall written twice with and without band detail: keep the one with the band detail
      reqs.push(keys.size > 1 ? list.reduce((a, b) => Object.keys(b.component_scores).length > Object.keys(a.component_scores).length ? b : a) : list[0]);
    }
    if (reqs.some((r) => r.test_code === "IELTS")) out[lv] = reqs;
    else if (reqs.length) conflicts.push(`${lv}: no IELTS`);
  }
  const style = out.undergraduate || out.postgraduate ? "level_default"
    : signals.has("bands") ? "bands" : signals.has("by_faculty") ? "by_faculty" : signals.has("course_specific") ? "course_specific" : "none";
  return { parser: POLICY_PARSER, style, defaults: out, exceptions: exceptions.slice(0, 200), named: namedCourses(md), signals: [...signals], conflicts };
}

// Academic calendar: the month each Semester/Trimester/Term N starts (first date in the row or sentence that names it
// with "start"/"commence"/"begin" or as the first teaching week). Only months with a stated year are kept.
const MONTH = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"];
const MON_RE = "(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)";
const monthNo = (s: string) => MONTH.findIndex((m) => m.startsWith(s.toLowerCase().slice(0, 3))) + 1;
export function calendarStarts(md: string) {
  const found: Record<string, { months: Set<number>; quotes: string[]; years: Set<number> }> = {};
  const add = (period: string, month: number, year: number | null, quote: string) => {
    const f = found[period] ||= { months: new Set(), quotes: [], years: new Set() };
    f.months.add(month); if (year) f.years.add(year); if (f.quotes.length < 3) f.quotes.push(quoteOf(quote));
  };
  const PERIOD = /\b(semester|trimester|term|study period|teaching period|session)\s*([1-6]|one|two|three|four|I{1,3})\b/i;
  const words: Record<string, string> = { one: "1", two: "2", three: "3", four: "4", i: "1", ii: "2", iii: "3" };
  for (const b of blocks(md)) {
    const rows = b.kind === "table" ? b.rows.map((r) => r.join(" | ")) : [b.text];
    for (const row of rows) {
      const p = row.match(PERIOD); if (!p) continue;
      const startWords = /\b(start|starts|begin|begins|commence|commences|commencement|first day|week 1|teaching begins|classes begin|lectures begin)\b/i;
      if (!startWords.test(row) && !(b.kind === "table" && /start|commence|begin/i.test(b.rows[0]?.join(" ") || ""))) continue;
      if (/\b(census|exams?|examinations?|results|holidays?|break|recess|ends?|finish(?:es)?|last day|deadline|closing|closes?|orientation)\b/i.test(row) && !startWords.test(row)) continue;
      const d = row.match(new RegExp(`(?:\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+${MON_RE}|${MON_RE}\\s+(\\d{1,2})(?:st|nd|rd|th)?)(?:,?\\s+(20\\d\\d))?`, "i"));
      if (!d) continue;
      const mon = monthNo(d[2] || d[3]); if (mon < 1) continue;
      const yr = Number(d[5] || (row.match(/\b(20\d\d)\b/) || [])[1] || (b.heading.match(/\b(20\d\d)\b/) || [])[1] || 0) || null;
      const n = words[p[2].toLowerCase()] || p[2];
      add(`${p[1].toLowerCase().replace(/ period$/, "_period")} ${n}`, mon, yr, row);
    }
  }
  const periods = Object.entries(found).map(([period, f]) => ({ period, months: [...f.months].sort((a, b) => a - b), years: [...f.years].sort(), quotes: f.quotes }));
  return { parser: POLICY_PARSER, periods };
}
