// CF-247 Decision 227 (2 Oct 2026): parsers for institution-level documents read by mode provider_facts.
// Deterministic only (no model). Nothing here writes to the catalogue: the results become proposals that a
// Platform Admin approves.
//  * englishPolicy: the provider's default English requirement by study level (undergraduate, postgraduate
//    coursework) and the courses it names as exceptions. A default is taken only where the document says it applies
//    to all (or the standard) courses of that level; course-by-course pages, English bands and faculty tables are
//    reported, not turned into a default.
//  * calendarStarts: the months in which each semester or trimester starts, from an academic calendar.
export const POLICY_PARSER = "provider-policy-v0.2.2";

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
  const s = clean(text).replace(/\s;\s/g, " ").replace(/[–—]/g, "-");
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
  const all = s.match(new RegExp(`no (?:individual |single |other )?(?:band|section|sub-?test|sub-?score|skill|component|communicative skill|score)s?(?: score)?(?: (?:less|lower) than| below| under)\\s*(?:an? )?${NUM}`, "i"))
    || s.match(new RegExp(`${NUM}\\s*(?:or (?:above|higher|more|better)\\s*)?(?:in|for|on) (?:each|all|every)(?: of the)?(?: four)?(?: (?:band|section|sub-?test|skill|component|communicative skill|sub-?score)s?)?`, "i"))
    || s.match(new RegExp(`(?:each|all|every) (?:band|section|sub-?test|skill|component|communicative skill|sub-?score)s?(?: (?:of|at least|minimum|min\\.?))*\\s*[:\\-]?\\s*${NUM}`, "i"))
    || s.match(new RegExp(`(?:minimum|min\\.?) (?:band|section|sub-?test|skill|component|sub-?score)(?: score)?(?: of)?\\s*${NUM}`, "i"));
  if (all && okc(Number(all[1]))) for (const k of SKILLS) comps[k] = Number(all[1]);
  // named skills: "Writing: 6.0" first, then "6.0 Speaking" / "7.0 in writing & reading", then "Writing 27"
  for (const m of s.matchAll(new RegExp(`\\b(listening|reading|writing|speaking)\\s*:\\s*${NUM}(?!\\d)`, "gi"))) {
    const v = Number(m[2]); if (okc(v) && !(m[1].toLowerCase() in comps && !all)) comps[m[1].toLowerCase()] = v;
  }
  const named0 = new Set(Object.keys(comps).filter(() => !all));
  for (const m of s.matchAll(new RegExp(`${NUM}\\s*(?:in\\s+)?((?:(?:listening|reading|writing|speaking)(?!\\s*:)(?:\\s*(?:,|&|and|\\/)\\s*)?)+)`, "gi"))) {
    const v = Number(m[1]); if (!okc(v)) continue;
    for (const k of SKILLS) if (new RegExp(k, "i").test(m[2]) && !named0.has(k)) comps[k] = v;
  }
  for (const m of s.matchAll(new RegExp(`\\b(listening|reading|writing|speaking)\\s+${NUM}(?!\\d)`, "gi"))) {
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

// Text that is not about admission to a coursework award: pathways, study abroad, research, professional
// registration after graduating, visas, English courses themselves.
const NOT_ADMISSION = /\b(study abroad|exchange|foundation|pathway|ELICOS|english (?:language )?(?:course|program|programme|centre|bridging)|bridging|direct entry|EAP|English for Academic Purposes|higher degrees? by research|research degrees?|HDR|PhD|register(?:ed|ing)? with|registration (?:with|requirements?)|AHPRA|Nursing and Midwifery Board|visa|subclass|secondary school|high school|year 1[012]|school students?|under 18)\b/i;
// A sentence that describes some courses ("courses that require 6.5", "programs requiring", "equivalent to IELTS 6.5",
// "any course with an IELTS of 7.0") states no default.
const NOT_DEFAULT = /\b(?:that|which) (?:require|requires|need|needs|have)\b|\brequiring\b|\b(?:any|those|some|certain|selected|specific) (?:of (?:our|the) )?(?:courses?|programs?|programmes|degrees|disciplines|study areas)\b|\bequivalen(?:t|ce) (?:to|of)\b(?![^.]{0,60}\brequire)|\bif you\b/i;
const HIGHER_UNLISTED = /\b(?:some|certain|selected|many) (?:courses?|programs?|programmes|degrees|disciplines)(?: (?:may|will|do))? (?:have|require|need|set) (?:a )?higher\b|\bhigher (?:English )?(?:language )?(?:requirements?|scores?) (?:for|apply to) (?:some|certain|selected)\b|\bcheck (?:the |your |each )?(?:course|program)(?:'s)? (?:page|entry)/i;
const generic = (x: string) => x.replace(/\b(?:bachelor|master)(?:'?s)? (?:degrees?|programs?|programmes|courses?|level)\b/gi, "");
const EXCEPT = /\b(?:except(?: for)?|other than|excluding|with the exception of|unless otherwise)\b/i;

type Statement = { level: Level | "both" | null; isDefault: boolean; names: string[]; reqs: Req[]; except: boolean; exceptNames: string[] };

// Scores for every test mentioned in a sentence; a sentence naming both levels with different scores
// ("6.0 for undergraduate courses and 6.5 for postgraduate coursework") is split by level.
function sentenceReqs(text: string): { level: Level | null; req: Req }[] {
  const out: { level: Level | null; req: Req }[] = [];
  for (const t of TESTS) {
    for (const m of text.matchAll(new RegExp(t.re.source, "gi"))) {
      const at = m.index || 0;
      let win = text.slice(at + m[0].length, at + m[0].length + 220);
      const cut = win.search(OTHER_TEST); if (cut >= 0) win = win.slice(0, cut);
      // several scores for one test, each followed by its level
      const scored = [...win.matchAll(new RegExp(`${NUM}(?:\\s*\\([^)]{0,40}\\))?\\s*(?:overall\\s*)?(?:for|in) (?:all )?(?:our )?(under-?graduate|post-?graduate(?: coursework)?|bachelor|master)`, "gi"))];
      if (scored.length >= 2) {
        for (const sm of scored) {
          const p = parseScore(t.code, sm[1]); const lv = levelOf(sm[2]);
          if (p && (lv === "undergraduate" || lv === "postgraduate")) out.push({ level: lv, req: { test_code: t.code, overall_score: p.overall, component_scores: p.comps, quote: quoteOf(text.slice(Math.max(0, at - 80), at + 260)) } });
        }
        if (out.length) break;
      }
      const p = parseScore(t.code, win.replace(/^[^\d]{0,80}?(?=(?:overall|total|min|\d))/i, ""));
      if (p) { out.push({ level: null, req: { test_code: t.code, overall_score: p.overall, component_scores: p.comps, quote: quoteOf(text.slice(Math.max(0, at - 80), at + 220)) } }); break }
    }
  }
  return out;
}

function exceptNamesOf(text: string): string[] {
  const m = text.replace(/\s;\s/g, " ").match(/\b(?:except(?: for)?|other than|excluding|with the exception of)(?: the)?(?: following)?:?\s+([^.;]{3,200})/i);
  if (!m) return [];
  const tail = m[1].replace(/\s;\s/g, " ").replace(/[()]/g, " ").split(/,?\s+(?:where|which|that|who|as|require|requires|must|need)\b/i)[0];
  return tail.split(/\s*(?:,|\band\b|&|;)\s*/).map((x) => x.replace(/^(?:the|our)\s+/i, "").trim())
    .filter((x) => x.length >= 4 && x.length <= 100 && /^[A-Z(]/.test(x) && !/^(?:those|courses?|programs?|programmes|disciplines|where|specified|listed|below|above)\b/i.test(x));
}

export function englishPolicy(md: string) {
  const statements: Statement[] = [];
  const signals = new Set<string>();
  const flat = clean(md);
  if (COURSE_SPECIFIC.test(flat)) signals.add("course_specific");
  if (HIGHER_UNLISTED.test(flat)) signals.add("higher_unlisted");
  for (const b of blocks(md)) {
    if (NOT_ADMISSION.test(b.heading)) continue;
    if (b.kind === "table") {
      if (b.rows.length < 2) continue;
      const head = b.rows[0];
      const testCol = head.map((c) => TESTS.find((t) => t.re.test(c) && !/equivalen|comparable/i.test(c))?.code || null);
      const levelCol = head.map((c) => { const l = levelOf(c); return l === "undergraduate" || l === "postgraduate" || l === "both" ? l : null });
      const rows = b.rows.slice(1);
      if (testCol.slice(1).filter(Boolean).length >= 1 && levelCol.slice(1).filter(Boolean).length === 0) {
        // columns are tests; each row is a course group, labelled in the first column
        const labels = rows.map((r) => (testCol[0] ? "" : r[0] || "").trim());
        if (labels.filter((l) => BAND_LABEL.test(l)).length >= 2) { signals.add("bands"); continue }
        if (labels.filter((l) => /^\d(?:\.\d)?$/.test(l)).length >= 2) { signals.add("equivalence_table"); continue }
        rows.forEach((r, k) => {
          const label = labels[k];
          if (NOT_ADMISSION.test(label)) return;
          const reqs: Req[] = [];
          r.forEach((cell, i) => { const code = testCol[i]; if (!code) return; const p = parseScore(code, cell); if (p) reqs.push({ test_code: code, overall_score: p.overall, component_scores: p.comps, quote: quoteOf(`${label ? label + " | " : ""}${head[i]}: ${cell}`) }) });
          if (!reqs.length) return;
          const lv = levelOf(label) || levelOf(b.heading);
          const named = AWARD.test(generic(label).replace(EXCEPT, "|").split("|")[0]) || (!!label && !PLAIN_LEVEL.test(label) && !DEFAULT_CUE.test(label) && lv !== "both" && !levelOf(label));
          statements.push({ level: lv === "research" ? null : lv, isDefault: !named && (PLAIN_LEVEL.test(label) || DEFAULT_CUE.test(label) || label === ""), names: named ? namesFrom(label) : [], reqs, except: EXCEPT.test(label), exceptNames: exceptNamesOf(label) });
        });
        continue;
      }
      if (rows.length && rows.every((r) => TESTS.some((t) => t.re.test(r[0] || ""))) && levelCol.slice(1).filter(Boolean).length === 0) {
        // rows are tests ("IELTS | 6.5 | Reading: 6.0 ..."): one requirement under the heading
        const reqs: Req[] = [];
        for (const r of rows) { const code = TESTS.find((t) => t.re.test(r[0]))!.code; const p = parseScore(code, r.slice(1).join(" ")); if (p && !reqs.some((q) => q.test_code === code)) reqs.push({ test_code: code, overall_score: p.overall, component_scores: p.comps, quote: quoteOf(`${b.heading ? b.heading + " | " : ""}${r.join(" | ")}`) }) }
        if (!reqs.length) continue;
        const lv = levelOf(b.heading);
        const named = !!b.heading && AWARD.test(b.heading);
        statements.push({ level: lv === "research" ? null : lv, isDefault: !named && (!b.heading || PLAIN_LEVEL.test(b.heading) || DEFAULT_CUE.test(b.heading) || /english (?:language )?(?:requirements?|proficiency)/i.test(b.heading)), names: named ? namesFrom(b.heading) : [], reqs, except: false, exceptNames: [] });
        continue;
      }
      if (levelCol.slice(1).filter(Boolean).length >= 1) {
        // columns are levels; rows are tests (a default) or faculties (a default only if every faculty agrees)
        const rowTest = rows.map((r) => TESTS.find((t) => t.re.test(r[0] || ""))?.code || null);
        if (rowTest.every(Boolean)) {
          levelCol.forEach((lv, i) => {
            if (!lv || i === 0) return;
            const reqs: Req[] = [];
            rows.forEach((r, k) => { const p = parseScore(rowTest[k]!, r[i] || ""); if (p) reqs.push({ test_code: rowTest[k]!, overall_score: p.overall, component_scores: p.comps, quote: quoteOf(`${r[0]} | ${head[i]}: ${r[i]}`) }) });
            if (reqs.length) statements.push({ level: lv, isDefault: true, names: [], reqs, except: false, exceptNames: [] });
          });
        } else {
          signals.add("by_faculty");
          const code = TESTS.find((t) => t.re.test(b.heading))?.code || TESTS.find((t) => t.re.test(head[0]))?.code;
          if (!code) continue;
          levelCol.forEach((lv, i) => {
            if (!lv || i === 0) return;
            const cells = rows.map((r) => r[i] || "").filter(Boolean);
            const parsed = cells.map((c) => parseScore(code, c));
            if (parsed.length >= 2 && parsed[0] && new Set(parsed.map((p) => JSON.stringify(p))).size === 1)
              statements.push({ level: lv, isDefault: true, names: [], reqs: [{ test_code: code, overall_score: parsed[0].overall, component_scores: parsed[0].comps, quote: quoteOf(`${head[i]}: ${cells[0]} (every faculty)`) }], except: false, exceptNames: [] });
          });
        }
      }
      continue;
    }
    // text, one sentence at a time
    for (const text of b.text.split(/(?<=[.!?])\s+(?=[A-Z])/)) {
    if (!OTHER_TEST.test(text) || NOT_ADMISSION.test(text)) continue;
    const sr = sentenceReqs(text);
    if (!sr.length) continue;
    const head = text.replace(/^[A-Z]{1,4}\d{1,4}[A-Z]?\s*[-–—]\s*/, "").split(/\s*[–—]\s*|\s+-\s+|:\s/)[0];
    const awardLead = AWARD.test(head) && new RegExp(NAMED.source).test(head);
    if (awardLead) { statements.push({ level: levelOf(text) === "research" ? null : (levelOf(head) as Level | "both" | null), isDefault: false, names: namesFrom(head), reqs: sr.map((x) => x.req), except: false, exceptNames: [] }); continue }
    if (NOT_DEFAULT.test(text)) continue;
    const lv = levelOf(text) || levelOf(b.heading);
    const split = sr.filter((x) => x.level);
    if (split.length) { for (const x of split) statements.push({ level: x.level, isDefault: true, names: [], reqs: [x.req], except: EXCEPT.test(text), exceptNames: exceptNamesOf(text) }); continue }
    const awardInText = AWARD.test(text.replace(/\b(?:bachelor|master)(?:'?s)? (?:degrees?|programs?|courses?|level)\b/gi, "").replace(EXCEPT, "|").split("|")[0]);
    statements.push({ level: lv === "research" ? null : lv, isDefault: !awardInText, names: [], reqs: sr.map((x) => x.req), except: EXCEPT.test(text), exceptNames: exceptNamesOf(text) });
    }
  }

  // Resolve: the default for each level, from statements that apply to all (or the standard) courses of that level.
  const defaults: Record<Level, Map<TestCode, Req[]>> = { undergraduate: new Map(), postgraduate: new Map() };
  const caveats = new Set<string>();
  const put = (lv: Level | "both", r: Req) => { for (const l of (lv === "both" ? ["undergraduate", "postgraduate"] : [lv]) as Level[]) { const a = defaults[l].get(r.test_code) || []; a.push(r); defaults[l].set(r.test_code, a) } };
  const levelled = statements.filter((x) => x.isDefault && x.level);
  for (const x of levelled) x.reqs.forEach((r) => put(x.level!, r));
  if (!levelled.length) {
    // one requirement stated for the whole document with no level: offered for both levels, flagged
    const loose = statements.filter((x) => x.isDefault && !x.level);
    // every IELTS score anywhere in the document (named courses included) must be the same one
    const keys = new Set(statements.flatMap((x) => x.reqs.filter((r) => r.test_code === "IELTS").map((r) => r.overall_score)));
    if (loose.length && keys.size === 1 && !signals.has("bands") && !signals.has("by_faculty")) { loose.forEach((x) => x.reqs.forEach((r) => put("both", r))); caveats.add("level_not_stated") }
  }
  const usedDefault = statements.filter((x) => x.isDefault);
  if (usedDefault.some((x) => x.except) && !statements.some((x) => x.names.length) && !usedDefault.some((x) => x.exceptNames.length)) caveats.add("exceptions_unlisted");
  if (signals.has("higher_unlisted") || signals.has("course_specific")) caveats.add("higher_unlisted");
  if (signals.has("bands") || signals.has("by_faculty")) caveats.add("course_groups");
  const out: Partial<Record<Level, Req[]>> = {};
  const conflicts: string[] = [];
  for (const lv of ["undergraduate", "postgraduate"] as Level[]) {
    const reqs: Req[] = [];
    for (const [code, list] of defaults[lv]) {
      if (new Set(list.map((r) => r.overall_score)).size > 1) { conflicts.push(`${lv} ${code}: ${[...new Set(list.map((r) => r.overall_score))].join(" / ")}`); continue }
      // the same overall written twice, with and without band detail: keep the one with the band detail
      reqs.push(list.reduce((a, b) => Object.keys(b.component_scores).length > Object.keys(a.component_scores).length ? b : a));
    }
    if (reqs.some((r) => r.test_code === "IELTS") && !conflicts.some((c) => c.startsWith(`${lv} IELTS`))) out[lv] = reqs;
  }
  const exceptions = statements.filter((x) => x.names.length).flatMap((x) => x.names.map((name) => ({ name, level: x.level, reqs: x.reqs })))
    .concat(statements.flatMap((x) => x.exceptNames.map((name) => ({ name, level: x.level, reqs: [] as Req[] }))));
  const style = out.undergraduate || out.postgraduate ? "level_default"
    : signals.has("bands") ? "bands" : signals.has("by_faculty") ? "by_faculty" : signals.has("course_specific") ? "course_specific"
    : exceptions.length ? "named_courses" : "none";
  return { parser: POLICY_PARSER, style, defaults: out, exceptions: exceptions.slice(0, 300), named: namedCourses(md), caveats: [...caveats], signals: [...signals], conflicts };
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
  const keyOf = (p: RegExpMatchArray) => `${p[1].toLowerCase().replace(/ period$/, "_period")} ${words[p[2].toLowerCase()] || p[2]}`;
  const DATE = new RegExp(`(?:\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+${MON_RE}|${MON_RE}\\s+(\\d{1,2})(?:st|nd|rd|th)?)(?:,?\\s+(20\\d\\d))?`, "i");
  const startWords = /\b(start|starts|begin|begins|commence|commences|commencement|first day|week 1|teaching begins|classes begin|lectures begin)\b/i;
  for (const b of blocks(md)) {
    const rows = b.kind === "table" ? b.rows.map((r) => r.join(" | ")) : [b.text];
    // v0.2.2 (3 Oct 2026): a period named on its own — a table section row ("| Semester 1 |") or the block's heading —
    // applies to the "Start date | Monday 16 February" rows that follow it until the next period is named (Curtin's layout).
    const hp = b.heading.match(PERIOD); let section: string | null = hp ? keyOf(hp) : null;
    for (const row of rows) {
      const p = row.match(PERIOD);
      const d = row.match(DATE);
      if (p && !d && clean(row.replace(/\|/g, " ")).length <= 40) { section = keyOf(p); continue }
      const period = p ? keyOf(p) : section; if (!period) continue;
      if (!startWords.test(row) && !(b.kind === "table" && p && /start|commence|begin/i.test(b.rows[0]?.join(" ") || ""))) continue;
      if (/\b(census|exams?|examinations?|results|holidays?|break|recess|ends?|finish(?:es)?|last day|deadline|closing|closes?|orientation)\b/i.test(row) && !startWords.test(row)) continue;
      if (!d) continue;
      const mon = monthNo(d[2] || d[3]); if (mon < 1) continue;
      const yr = Number(d[5] || (row.match(/\b(20\d\d)\b/) || [])[1] || (b.heading.match(/\b(20\d\d)\b/) || [])[1] || 0) || null;
      add(period, mon, yr, row);
    }
  }
  const periods = Object.entries(found).map(([period, f]) => ({ period, months: [...f.months].sort((a, b) => a - b), years: [...f.years].sort(), quotes: f.quotes }));
  return { parser: POLICY_PARSER, periods };
}
