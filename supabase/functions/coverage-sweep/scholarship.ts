// CF-247 scholarship sweep (Decision 139 / 163): deterministic facts from a scholarship's own provider page.
// Nothing here decides publication; the database applies values only where the record has none, and links courses
// only by the levels and fields the page itself states.
import { clean, htmlToText } from "./extract.ts";

const MONTHS = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"];

// Main content only: prefer <main>, drop navigation, header, footer and side panels (menus list every level/field).
export function mainText(html: string) {
  let h = html;
  const m = h.match(/<main[\s\S]*?<\/main>/i);
  if (m && m[0].length > 1500) h = m[0];
  h = h.replace(/<(nav|header|footer|aside)\b[\s\S]*?<\/\1>/gi, " ");
  return htmlToText(h);
}

// v0.4.2: levels the text excludes ("excluding Master by Research or PhD") or that describe earlier study ("completed
// an undergraduate degree") are not levels of the scholarship.
export function levelText(body: string) {
  return body
    .replace(/\b(?:excluding|except(?: for)?|other than|not (?:available|eligible|open|applicable) (?:for|to)|does not apply to|cannot be used for|ineligible)\b[^.;:)\n]{0,140}/gi, " ")
    .replace(/\b(?:completed|completing|graduated (?:from|with)|graduates? of|holds?|holding|have finished|prior|previous(?:ly)?)\b[^.;:)\n]{0,80}?\b(?:degree|qualification|diploma|program(?:me)?|studies|course)s?\b/gi, " ");
}
function levelsIn(t: string) {
  const levels = new Set<string>();
  if (/\bundergraduate\b|\bbachelor/.test(t)) levels.add("undergraduate");
  const research = /\b(phd|doctor of philosophy|doctoral|higher degree by research|hdr|research degree|master(?:'s|s)? by research|research master|postgraduate research|graduate research)/.test(t);
  if (/postgraduate coursework|coursework (?:master|postgraduate)|master(?:'s|s)? (?:degree )?by coursework|graduate (?:certificate|diploma)/.test(t)) levels.add("postgraduate_coursework");
  else if (/\bpostgraduate\b|\bmaster(?:'s|s)?\b/.test(t) && !research) levels.add("postgraduate_coursework");
  if (research) levels.add("research");
  return levels;
}
// A level named in the scholarship's own title decides (v0.4.2: "RMIT Vietnam Alumni Postgraduate Scholarship" is
// postgraduate although its eligibility mentions the undergraduate degree already completed); otherwise the text.
export function scholarshipLevels(titleText: string, body: string) {
  const title = titleText.toLowerCase();
  let levels = levelsIn(title);
  if (!levels.size) levels = levelsIn(title + " " + levelText(body.slice(0, 3000)).toLowerCase());
  if (/\b(foundation|pathway|elicos)\b/.test(title)) levels.add("pathway");
  return [...levels].sort();
}

// Field restriction from the scholarship's own name only (page bodies mention many fields in passing).
const FIELDS: [RegExp, string][] = [
  [/\bengineer/i, "asced-03"], [/\b(information technology|computing|computer science|\bict\b|cyber|data science)/i, "asced-02"],
  [/\b(nursing|health|medicine|medical|pharmacy|dentist|midwi|physiotherap|psycholog)/i, "asced-06"],
  [/\b(business|commerce|accounting|management|\bmba\b|finance|economics)/i, "asced-08"], [/\blaw\b|\blegal\b/i, "asced-0909"],
  [/\b(education|teaching)\b/i, "asced-07"], [/\b(architecture|built environment|construction)\b/i, "asced-04"],
  [/\b(agricultur|environment|veterinar)/i, "asced-05"], [/\b(creative arts|music|design|fine art|film)\b/i, "asced-10"],
  [/\b(science)\b/i, "asced-01"], [/\b(arts|humanities|social science)\b/i, "asced-09"],
];
export function scholarshipFields(name: string) {
  const out = new Set<string>();
  for (const [re, code] of FIELDS) if (re.test(name)) out.add(code);
  return [...out].sort();
}

// A faculty or school named in the scholarship text ("Faculty of Law") restricts it to that field. Several different
// faculties, or one that cannot be matched to a field, mean the course links need a person (field_unmapped).
export function scholarshipFaculties(body: string) {
  const t = body.slice(0, 5000);
  const names = new Set<string>();
  for (const m of t.matchAll(/\b(?:Faculty|School|College) of ([A-Z][A-Za-z&,\- ]{2,70}?)(?=[.,;:()]|\s(?:at|is|in|for|to|with|students|scholarship|and\s+the)\b|$)/g)) names.add(clean(m[1]));
  const fields = new Set<string>(); let unmapped = false;
  for (const n of names) { const f = scholarshipFields(n); if (f.length) f.forEach((x) => fields.add(x)); else unmapped = true }
  return { faculties: [...names], fields: [...fields].sort(), unmapped };
}

// Award value: one clear percentage of tuition, one clear fixed amount, or full tuition. Tiers or mixed -> ambiguous.
// v0.4.3 (step-1 hand-check): "must not hold a scholarship that covers full tuition fees" is a condition, not the value
// (Macquarie "$10,000" and "$5,000" scholarships were given 100%); "up to N%" is a maximum, not the value; "Value
// $10,000" counts as a stated amount; stipend amounts are not dropped as living costs; one amount in the scholarship's own
// name ("ASEAN $10,000 Early Acceptance Scholarship") that the page also states is the value.
const FULL_TUITION = /\b(?:100\s?%|full)\s+(?:tuition|course)\s+fees?\b|\bfull[- ]tuition\b|\bfull fee (?:waiver|scholarship)\b/gi;
function fullTuitionStated(t: string) {
  for (const m of t.matchAll(FULL_TUITION)) {
    const before = t.slice(Math.max(0, (m.index || 0) - 70), m.index || 0);
    if (/\b(not|no|pay(?:s|ing)?|paid|recipients?|receiving|sponsor\w*|already|another|other|up to)\b[^.]{0,55}$/i.test(before)) continue;
    return true;
  }
  return false;
}
export function scholarshipValue(body: string, name = "") {
  const t = body.slice(0, 6000);
  const nameAmt = [...String(name).matchAll(/\$\s?(\d{1,3}(?:,\d{3})+|\d{3,6})\b/g)].map((m) => Number(m[1].replace(/,/g, "")));
  if (nameAmt.length === 1 && nameAmt[0] >= 500 && new RegExp(`\\$\\s?${nameAmt[0].toLocaleString("en-AU").replace(/,/g, ",?")}(?![\\d,])`).test(t))
    return { type: "fixed_amount", amount: nameAmt[0], currency: "AUD", basis: "scholarship_name", context: ctx(t, new RegExp(nameAmt[0].toLocaleString("en-AU").replace(/,/g, ",?"))) };
  // v0.4.2: full tuition only when no other percentage is stated (HonduFuturo: full tuition for PhD, 20% for coursework)
  const otherPct = [...t.matchAll(/(\d{1,3})\s?%/g)].map((m) => Number(m[1])).filter((v) => v >= 5 && v < 100);
  if (fullTuitionStated(t))
    return otherPct.length ? { type: "ambiguous", percentages: [...new Set([...otherPct, 100])].sort((a, b) => a - b), amounts: [] as number[] }
      : { type: "percentage", percentage: 100, applies_to: "tuition_fee", context: ctx(t, /full[- ]?(?:tuition|fee)|100\s?%/i) };
  const pct = new Set<number>(); let upTo = false;
  for (const m of t.matchAll(/(\d{1,3})\s?%\s+(?:off\s+|of\s+)?(?:(?:your|the|annual|first[- ]year|total)\s+)*(?:tuition|course)\s+fees?|(\d{1,3})\s?%\s+(?:tuition\s+)?(?:fee\s+)?(?:reduction|remission|discount|waiver|scholarship)/gi)) {
    const v = Number(m[1] || m[2]); if (v >= 5 && v <= 100) pct.add(v);
    if (/up to\s*$/i.test(t.slice(Math.max(0, (m.index || 0) - 12), m.index || 0))) upTo = true;
  }
  const amt = new Set<number>(); let foreign = false;
  const stipend = /\bstipend\b/i.test(t);
  for (const m of t.matchAll(/(?:A\$|AUD\s?\$?|US\$|USD\s?\$?|\$)\s?(\d{1,3}(?:,\d{3})+|\d{3,6})(?:\.\d{2})?(\s?(?:USD|US|NZD|CAD|GBP|EUR))?/g)) {
    const at = m.index || 0, around = t.slice(Math.max(0, at - 90), at + 90).toLowerCase();
    // v0.4.6: an amount in another currency, or a maximum ("up to A$7,496"), is not a single AUD value
    if (/^(?:US\$|USD)/i.test(m[0]) || m[2] || /\b(?:USD|US\$)\s*$/i.test(t.slice(Math.max(0, at - 8), at))) { foreign = true; continue }
    if (/up to\s*(?:a|au)?\s*$/i.test(t.slice(Math.max(0, at - 12), at))) upTo = true;
    if (!/(scholarship|award|valued?|worth|stipend|bursary|grant|per year|per annum|each year|one-off|one off|once-off)/.test(around)) continue;
    if (/(accommodation|application fee|cost of|visa|oshc|health cover)/.test(around) || (!stipend && /living/.test(around))) continue;
    const v = Number(m[1].replace(/,/g, "")); if (v >= 500 && v <= 200000) amt.add(v);
  }
  // any other percentage in the scholarship text (tiers by region, level or result) makes a single value unsafe
  const allPct = new Set<number>([...t.matchAll(/(\d{1,3})\s?%/g)].map((m) => Number(m[1])).filter((v) => v >= 5 && v <= 100))
  if (foreign) return { type: "ambiguous", foreign_currency: true, percentages: [...pct], amounts: [...amt] };
  if (upTo) return { type: "ambiguous", up_to: true, percentages: [...allPct].sort((a, b) => a - b), amounts: [...amt] };
  if (pct.size === 1 && allPct.size > 1) return { type: "ambiguous", percentages: [...allPct].sort((a, b) => a - b), amounts: [...amt] };
  if (pct.size === 1 && amt.size === 0) { const p = [...pct][0]; return { type: "percentage", percentage: p, applies_to: "tuition_fee", context: ctx(t, new RegExp(`${p}\\s?%`)) } }
  if (amt.size === 1 && pct.size === 0) { const a = [...amt][0]; return { type: "fixed_amount", amount: a, currency: "AUD", context: ctx(t, new RegExp(a.toLocaleString("en-AU").replace(/,/g, ",?"))) } }
  if (pct.size || amt.size) return { type: "ambiguous", percentages: [...pct].sort((a, b) => a - b), amounts: [...amt].sort((a, b) => a - b) };
  return null;
}

// Closing date: an explicit day, month and year beside "close/closing/deadline/due/apply by".
export function scholarshipDeadline(body: string) {
  const t = body.slice(0, 8000);
  const re = /(clos(?:e|es|ing)|deadline|due|apply by|applications? (?:close|due))[^.]{0,70}?(?:(\d{1,2})(?:st|nd|rd|th)?\s+(january|february|march|april|may|june|july|august|september|october|november|december)|(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2})(?:st|nd|rd|th)?,?)\s+(20\d\d)/gi;
  const dates = new Set<string>();
  for (const m of t.matchAll(re)) {
    const day = Number(m[2] || m[5]), mon = MONTHS.indexOf(String(m[3] || m[4]).toLowerCase()) + 1, yr = Number(m[6]);
    if (day >= 1 && day <= 31 && mon >= 1) dates.add(`${yr}-${String(mon).padStart(2, "0")}-${String(day).padStart(2, "0")}`);
  }
  const list = [...dates].sort();
  return list.length === 1 ? { date: list[0], context: ctx(t, re) } : list.length ? { dates: list, ambiguous: true } : null;
}

function ctx(t: string, re: RegExp) { const m = t.match(new RegExp(re.source, re.flags.replace("g", ""))); if (!m) return null; const at = m.index || 0; return clean(t.slice(Math.max(0, at - 120), at + 160)) }

export function scholarshipFacts(html: string, titleText: string, name: string) {
  const body = mainText(html);
  // levels from the eligibility section when the page has one (pages mention other levels elsewhere); else the page start
  // v0.4.6: the eligibility section is a heading-like "Eligibility" / "Who is eligible" (not "eligible countries"), and
  // when it states no level the page start is used
  const at = body.search(/\b(?:eligibility(?: criteria| requirements)?\b|who (?:is|can be) eligible|am i eligible|to be eligible)/i);
  const eligibility = at >= 0 ? body.slice(at, at + 1200) : null;
  const fromElig = eligibility ? scholarshipLevels(titleText + " " + name, eligibility) : [];
  return {
    levels: fromElig.length ? fromElig : scholarshipLevels(titleText + " " + name, body),
    levels_from: fromElig.length ? "eligibility" : "page",
    ...(() => { const n = scholarshipFields(name); const fac = scholarshipFaculties(body); return { fields: n.length ? n : fac.fields, faculties: fac.faculties, field_unmapped: !n.length && fac.unmapped } })(),
    value: scholarshipValue(body, name),
    deadline: scholarshipDeadline(body),
    international: /\binternational\b/i.test(titleText + " " + body.slice(0, 4000)),
    eligibility_excerpt: (() => { const at = body.search(/eligib/i); return at >= 0 ? clean(body.slice(at, at + 900)) : null })(),
    criteria: scholarshipCriteria(body),
    award_scope: awardScope(body),
    text_length: body.length,
  };
}

// ---------------------------------------------------------------------------------------------------------------
// v0.5.0 (CF-247 Decision 211, 2 Oct 2026): eligibility criteria and award scope, read from the page's own eligibility
// and "key details" text. Each criterion carries the words it came from. Only what the page states plainly is kept;
// anything mixed (e.g. "future or current student") is left out rather than guessed.

type Criterion = { type: string; operator: string; value_text?: string; value_number?: number; value_codes?: string[]; scale?: number; text: string };
const NEGATED = /\b(?:not|non|excluding|except|other than|nor|ineligible|cannot)\b[^.;]{0,85}$/i;
const snip = (t: string, at: number, len = 220) => clean(t.slice(Math.max(0, at - 40), at + len)).slice(0, 300);
// "... are not eligible", "... cannot apply" after the words also excludes them
const NEGATED_AFTER = /^[^.;:]{0,70}?\b(?:(?:are|is) (?:not|in)eligible|(?:are|is) not (?:eligible|able to apply)|cannot (?:apply|receive|be awarded)|(?:are|is) excluded)\b/i;
function firstPlain(t: string, re: RegExp) {
  for (const m of t.matchAll(re)) {
    const at = m.index || 0;
    if (!NEGATED.test(t.slice(Math.max(0, at - 100), at)) && !NEGATED_AFTER.test(t.slice(at + m[0].length, at + m[0].length + 90))) return m;
  }
  return null;
}
// The text that states who can apply: the eligibility section, plus short "key details" lines (Eligible citizenship,
// Student type, Residency) that many university pages put above it.
export function eligibilityText(body: string) {
  const t = body.slice(0, 12000), parts: string[] = [];
  const at = t.search(/\b(?:eligibility(?: criteria| requirements)?\b|who (?:is|can be|'s) eligible|am i eligible|to be eligible|you must:)/i);
  if (at >= 0) {
    // the section ends at the next part of the page (how to apply, related scholarships, page footer)
    let sec = t.slice(at, at + 2500);
    const end = sec.slice(80).search(/\b(?:how (?:do i |to )apply|when do applications|application process|more about scholarships|explore (?:similar|other|more) scholarships|(?:related|similar|other) scholarships|read more|contact us|terms and conditions)\b/i);
    if (end >= 0) sec = sec.slice(0, end + 80);
    parts.push(sec);
  }
  let n = 0;
  for (const m of t.matchAll(/\b(?:eligible (?:citizenship|student type|study stage)|student type|residency|citizenship)\b:?\s+/gi)) {
    const at = m.index || 0, after = t.slice(at + m[0].length, at + m[0].length + 140);
    // a label followed by its values ("Student type Domestic, International"), not a sentence ("citizenship from a country")
    if (!/^[A-Z]/.test(after)) continue;
    if (n++ >= 3) break;
    parts.push(t.slice(at, at + m[0].length) + after.split(/(?<=[a-z)])\.\s|\?\s/)[0]);
  }
  return parts.join(" \n ");
}

const COUNTRIES: [RegExp, string][] = [
  [/\bindia\b/i, "IN"], [/\bchina\b|\bchinese mainland\b/i, "CN"], [/\bvietnam\b|\bviet nam\b/i, "VN"], [/\bindonesia\b/i, "ID"], [/\bmalaysia\b/i, "MY"],
  [/\bthailand\b/i, "TH"], [/\bsingapore\b/i, "SG"], [/\bphilippines\b/i, "PH"], [/\bsri lanka\b/i, "LK"], [/\bnepal\b/i, "NP"], [/\bbangladesh\b/i, "BD"],
  [/\bpakistan\b/i, "PK"], [/\bcambodia\b/i, "KH"], [/\bmyanmar\b/i, "MM"], [/\blaos\b|\blao pdr\b/i, "LA"], [/\bmongolia\b/i, "MN"], [/\bjapan\b/i, "JP"],
  [/\bsouth korea\b|\brepublic of korea\b|\bkorea\b/i, "KR"], [/\btaiwan\b/i, "TW"], [/\bhong kong\b/i, "HK"], [/\bmacau\b|\bmacao\b/i, "MO"], [/\bbhutan\b/i, "BT"],
  [/\bfiji\b/i, "FJ"], [/\bpapua new guinea\b/i, "PG"], [/\bsamoa\b/i, "WS"], [/\btonga\b/i, "TO"], [/\bvanuatu\b/i, "VU"], [/\bsolomon islands\b/i, "SB"],
  [/\btimor[- ]leste\b|\beast timor\b/i, "TL"], [/\bkiribati\b/i, "KI"], [/\btuvalu\b/i, "TV"], [/\bnauru\b/i, "NR"],
  [/\bunited states\b|\busa\b/i, "US"], [/\bcanada\b/i, "CA"], [/\bmexico\b/i, "MX"], [/\bbrazil\b/i, "BR"], [/\bcolombia\b/i, "CO"], [/\bchile\b/i, "CL"],
  [/\bperu\b/i, "PE"], [/\bargentina\b/i, "AR"], [/\becuador\b/i, "EC"], [/\bhonduras\b/i, "HN"],
  [/\bunited kingdom\b/i, "GB"], [/\bireland\b/i, "IE"], [/\bgermany\b/i, "DE"], [/\bfrance\b/i, "FR"], [/\bitaly\b/i, "IT"], [/\bspain\b/i, "ES"], [/\bnorway\b/i, "NO"],
  [/\bsweden\b/i, "SE"], [/\bnetherlands\b/i, "NL"], [/\bturkey\b|\btürkiye\b/i, "TR"],
  [/\bsaudi arabia\b/i, "SA"], [/\bunited arab emirates\b|\buae\b/i, "AE"], [/\biran\b/i, "IR"], [/\biraq\b/i, "IQ"], [/\bjordan\b/i, "JO"], [/\begypt\b/i, "EG"],
  [/\bkenya\b/i, "KE"], [/\bnigeria\b/i, "NG"], [/\bghana\b/i, "GH"], [/\bsouth africa\b/i, "ZA"], [/\bethiopia\b/i, "ET"], [/\buganda\b/i, "UG"], [/\btanzania\b/i, "TZ"],
  [/\bzimbabwe\b/i, "ZW"], [/\brwanda\b/i, "RW"], [/\bkazakhstan\b/i, "KZ"], [/\buzbekistan\b/i, "UZ"],
];
const WORD_NUM: Record<string, number> = { one: 1, two: 2, three: 3, four: 4, five: 5, six: 6 };

export function scholarshipCriteria(body: string): Criterion[] {
  const t = eligibilityText(body);
  if (!t) return [];
  const out: Criterion[] = [];
  // student type: domestic (citizens, permanent residents), international, or both
  const dom = firstPlain(t, /\b(?:australian citizens?|permanent residents?(?: of australia)?|australian permanent residents?|domestic students?|new zealand citizens?|(?:permanent )?humanitarian visa(?: holders?)?|student type:? domestic|domestic(?=,| and| or))\b/gi);
  // stated as a requirement, not a menu link ("Applying to RMIT International students Parents")
  const intl = firstPlain(t, /\b(?:be|is|are|an?|or|and|new|commencing|current|continuing|offshore|onshore|eligible|open to|all) (?:an? )?international(?: students?| applicants?| candidates?|,)|\binternational (?:students?|applicants?|candidates?) (?:who|must|may|are|will|can|only|commencing|applying|from|studying|enrolling|holding|with|in|on)\b|\b(?:student type|domestic(?: and|,| or| \/)?|citizenship|residency)[ :,/a-z]{0,25}\binternational\b/gi);
  // a shortened list ("Australian citizen, Permanent resident +2 more") hides the rest: domestic-only is not certain
  const hidden = /\+\s?\d+ more\b/i.test(t);
  if (intl || (dom && !hidden)) {
    const codes = [...(dom ? ["domestic"] : []), ...(intl ? ["international"] : [])];
    const at = Math.min(dom?.index ?? Infinity, intl?.index ?? Infinity);
    out.push({ type: "student_type", operator: "in", value_codes: codes, text: snip(t, at) });
  }
  // study stage: commencing (new) or current (continuing) students; both named -> left out
  const comm = firstPlain(t, /\b(?:commencing|new students?|future study|intending to enrol|be enrolling|commence (?:study|studies|your)|first[- ]year (?:student|entry))\b/gi);
  const cur = firstPlain(t, /\b(?:current(?:ly enrolled)? students?|continuing students?|currently enrolled|in (?:your|their) (?:second|third|fourth|final|2nd|3rd|4th)(?: (?:or|and|,) (?:third|fourth|final|3rd|4th))? year|have completed at least)\b/gi);
  if (comm && !cur) out.push({ type: "study_stage", operator: "equals", value_text: "commencing", text: snip(t, comm.index || 0) });
  else if (cur && !comm) out.push({ type: "study_stage", operator: "equals", value_text: "current", text: snip(t, cur.index || 0) });
  // study load
  const ft = firstPlain(t, /\bfull[- ]time\b/gi);
  if (ft && !/\bpart[- ]time\b/i.test(t)) out.push({ type: "study_load", operator: "equals", value_text: "full_time", text: snip(t, ft.index || 0) });
  // academic minimum: ATAR, GPA or a weighted average (first stated of each)
  const atar = t.match(/\bATAR\b[^.;]{0,45}?(?:of|at least|minimum(?: of)?|above|or higher than)?\s*(\d{2}(?:\.\d{1,2})?)\b/i);
  if (atar && Number(atar[1]) >= 30 && Number(atar[1]) <= 99.95) out.push({ type: "academic_minimum", operator: ">=", value_text: "ATAR", value_number: Number(atar[1]), text: snip(t, atar.index || 0) });
  const gpa = t.match(/\b(?:GPA|grade point average)\b(?:\s*\([^)]{0,10}\))?[^.;]{0,45}?(?:of|at least|minimum(?: of)?|above)?\s*(\d(?:\.\d{1,2})?)(?:\s*(?:\/|out of)\s*(4|5|7))?(?![\d%])/i);
  if (gpa && Number(gpa[1]) > 0 && Number(gpa[1]) <= 7) out.push({ type: "academic_minimum", operator: ">=", value_text: "GPA", value_number: Number(gpa[1]), ...(gpa[2] ? { scale: Number(gpa[2]) } : {}), text: snip(t, gpa.index || 0) });
  const wam = t.match(/\b(?:WAM|weighted average mark|average mark|average (?:grade|score)|course average)\b[^.;]{0,40}?(?:of|at least|minimum(?: of)?|above)?\s*(\d{2})\s*%?/i);
  if (wam && Number(wam[1]) >= 40 && Number(wam[1]) <= 100) out.push({ type: "academic_minimum", operator: ">=", value_text: "WAM", value_number: Number(wam[1]), text: snip(t, wam.index || 0) });
  // gender, when the page restricts it
  const g = firstPlain(t, /\b(?:identify(?:ing)? as (?:a )?(woman|women|female|man|male)|(female|women|male) (?:students?|applicants?)|must be (?:a )?(woman|female|man|male))\b/gi);
  if (g) { const w = String(g[1] || g[2] || g[3]).toLowerCase(); out.push({ type: "gender", operator: "equals", value_text: /^(woman|women|female)$/.test(w) ? "women" : "men", text: snip(t, g.index || 0) }) }
  // nationality: countries named right after "citizens of", "nationals of", "born in", "from"
  const codes = new Set<string>(); let natAt = -1;
  for (const m of t.matchAll(/\b(?:citizens?(?:hip)? (?:of|from|in)|nationals? of|passport holders? (?:of|from)|born in|students from|applicants from|from one of the following(?: countries)?)\b/gi)) {
    const at = m.index || 0;
    if (NEGATED.test(t.slice(Math.max(0, at - 100), at))) continue;
    const win = t.slice(at, at + 320).split(/\b(?:and be|and have|must|you must|be enrolled|enrol)\b/i)[0];
    for (const [re, code] of COUNTRIES) if (re.test(win)) { codes.add(code); if (natAt < 0) natAt = at }
  }
  if (codes.size) out.push({ type: "nationality", operator: "in", value_codes: [...codes].sort(), text: snip(t, natAt, 320) });
  // applying: some scholarships are given without an application
  const auto = body.match(/\b(?:automatic(?:ally)? (?:consider|assess)\w*|open for automatic consideration|no (?:separate )?application (?:is )?(?:required|needed|necessary)|you do not need to apply|you don'?t need to apply)\b/i);
  if (auto) out.push({ type: "application_method", operator: "equals", value_text: "automatic", text: snip(body, auto.index || 0) });
  return out;
}

// Award scope: how long and what the award pays for, from the benefit wording ("$5,000 per year for up to three years",
// "one-off payment", "for the standard duration of your degree", "tuition fees").
export function benefitText(body: string) {
  const t = body.slice(0, 10000), parts: string[] = [];
  let n = 0;
  for (const m of t.matchAll(/\b(?:benefits?|value and duration|what you(?:'ll| will) (?:receive|get)|(?:this|the) (?:scholarship|award|bursary|grant) (?:provides|is valued|covers|offers|will provide|is worth|pays)|scholarship value|award value|benefit (?:amount|duration)|duration of (?:the |this )?(?:scholarship|award)|total value|value|worth)\b/gi)) {
    if (n++ >= 6) break;
    parts.push(t.slice(m.index || 0, (m.index || 0) + 260));
  }
  return parts.join(" \n ");
}
export function awardScope(body: string) {
  const t = benefitText(body);
  if (!t) return null;
  const annual = /\bper (?:academic )?(?:year|annum)\b|\bp\.\s?a\.|\beach (?:academic )?year\b|\bannually\b|\ba year\b|\byearly\b|\bper calendar year\b/i.test(t);
  const yrs = t.match(/\b(?:for )?up to (\d|one|two|three|four|five|six)(?:\.\d)? (?:years?|academic years?)\b|\bfor (\d|two|three|four|five|six) (?:years|academic years)\b/i);
  const program = /\b(?:normal|standard|minimum|full|remaining|entire|prescribed)?\s*duration of (?:your|the|their|a|an|his|her) (?:course|degree|program|programme|studies|study|candidature)\b|\bfor the (?:length|life) of (?:your|the) (?:course|degree|program)\b/i.test(t) || !!yrs;
  const oneOff = /\bone[- ]?off\b|\bonce[- ]off\b|\bone[- ]time\b|\bsingle (?:payment|instalment)\b|\bpaid once\b|\bone year only\b/i.test(t);
  const firstYear = /\bfirst[- ]year (?:of study )?only\b|\b(?:for|in) (?:the|your) first year(?: of (?:study|your (?:degree|course|program)))?\b(?! and)|\bfirst[- ]year tuition\b/i.test(t);
  const sem = /\bper semester\b|\beach semester\b/i.test(t);
  let duration: string | null = null;
  if (oneOff && !annual && !program) duration = "one_off";
  else if (firstYear && !program && !oneOff) duration = "first_year";
  else if (annual && program && !oneOff) duration = "annual_program_duration";
  else if (annual && !oneOff && !firstYear) duration = "annual";
  else if (program && !oneOff && !firstYear) duration = "program_duration";
  else if (sem && !annual && !oneOff) duration = "per_semester";
  const y = yrs ? (yrs[1] || yrs[2]) : null;
  const years = y ? (WORD_NUM[y.toLowerCase()] ?? Number(y)) : null;
  const appliesTo = [
    ...(/\btuition\b|\bcourse fees?\b|\bfee (?:reduction|remission|waiver|discount)\b/i.test(t) ? ["tuition_fee"] : []),
    ...(/\bstipend\b|\bliving (?:allowance|costs?)\b|\ballowance\b/i.test(t) ? ["living_allowance"] : []),
    ...(/\baccommodation\b/i.test(t) ? ["accommodation"] : []),
  ];
  if (!duration && !years && !appliesTo.length) return null;
  return { duration, years: years && years > 0 && years <= 8 ? years : null, applies_to: appliesTo, text: clean(t.slice(0, 400)) };
}

// ---------------------------------------------------------------------------------------------------------------
// v0.4.0 (CF-247 scholarship discovery): finding a scholarship's own provider page, confirming a page is the same
// scholarship before anything is applied, and deciding whether an unheld provider page is a new scholarship.

// Names: lower case, entities and apostrophes folded, "&" as "and", years and "the" dropped, simple plurals folded
// ("Scholarships" = "Scholarship", "Vice-Chancellor's" = "vice chancellors" = "vice chancellor").
export function nameTokens(s: string) {
  const t = String(s ?? "").replace(/&#0*39;|&#x0*27;|&#x2019;|&#8217;|&rsquo;|&lsquo;|[’‘`]/gi, "'").replace(/&amp;/gi, "&")
    .replace(/(\d),(\d{3})/g, "$1$2").toLowerCase().replace(/'/g, "").replace(/&/g, " and ").replace(/[^a-z0-9]+/g, " ").trim();
  return t ? t.split(" ").filter((w) => w !== "the" && !/^20\d\d$/.test(w)).map((w) => w.length > 3 && w.endsWith("ies") ? w.slice(0, -3) + "y" : w.length > 3 && w.endsWith("s") && !w.endsWith("ss") ? w.slice(0, -1) : w) : [];
}
const GENERIC = new Set(["scholarship", "international", "award", "grant", "bursary", "student", "program", "fee", "and", "of", "for", "university", "study", "in", "at", "to", "a"]);
const STOP_PROVIDER = new Set(["international", "college", "school", "institute", "australia", "australian", "of", "and", "the", "group", "limited", "ltd", "pty", "education", "grammar", "sydney", "melbourne"]);
function seqIn(a: string[], b: string[]) { // a contiguous in b
  if (!a.length || a.length > b.length) return false;
  outer: for (let i = 0; i + a.length <= b.length; i++) { for (let k = 0; k < a.length; k++) if (a[k] !== b[i + k]) continue outer; return true }
  return false;
}
// Provider words that may prefix a scholarship name ("UC - ...", "Macquarie University $5,000 ...", "UNSW ...").
export function providerTokens(names: string[]) {
  const out = new Set<string>(["university"]);
  for (const n of names.filter(Boolean)) {
    for (const w of nameTokens(n)) if (!STOP_PROVIDER.has(w)) out.add(w);
    for (const m of n.matchAll(/\(([A-Za-z]{2,8})\)/g)) out.add(m[1].toLowerCase());
    const acro = n.split(/[\s,;]+/).filter((w) => /^[A-Z]/.test(w) && !/^(of|and|the)$/i.test(w)).map((w) => w[0]).join("").toLowerCase();
    if (acro.length >= 2 && acro.length <= 5) out.add(acro);
  }
  return out;
}
function stripProvider(t: string[], prov: Set<string>) { let i = 0; while (i < t.length && prov.has(t[i])) i++; return t.slice(i) }

// The headings a page names itself by: <title> in <head> (an SVG <title> is not the page title), og/twitter title,
// every <h1>; secondary: the first two <h2>s (some sites keep a generic "Scholarships" <h1> above the scholarship's own
// name). A secondary heading confirms only when it contains the whole name.
export function pageHeadings(html: string) {
  const out: string[] = [], sec: string[] = [];
  const head = (html.match(/<head[\s\S]*?<\/head>/i) || [""])[0];
  const t = head.match(/<title[^>]*>([\s\S]*?)<\/title>/i); if (t) out.push(htmlToText(t[1]));
  for (const m of html.matchAll(/<meta[^>]+(?:property|name)=["'](?:og:title|twitter:title)["'][^>]*>/gi)) { const c = m[0].match(/content=["']([^"']*)["']/i); if (c) out.push(htmlToText(c[1])) }
  for (const m of html.matchAll(/<h1[^>]*>([\s\S]*?)<\/h1>/gi)) out.push(htmlToText(m[1]));
  let h2 = 0; for (const m of html.matchAll(/<h2[^>]*>([\s\S]*?)<\/h2>/gi)) { if (h2++ >= 2) break; sec.push(htmlToText(m[1])) }
  const tidy = (a: string[]) => [...new Set(a.map((x) => clean(x)).filter((x) => x && x.length <= 300))];
  return { primary: tidy(out), secondary: tidy(sec) };
}

// Same scholarship: the page names it. The whole name (or the name without a provider prefix) appears in one of the
// page's headings, or a heading of at least two words, not all generic, makes up at least 70% of the name.
export function nameOnPage(name: string, headings: string[], prov: Set<string> = new Set(), secondary: string[] = []) {
  const n = nameTokens(name), np = stripProvider(n, prov);
  for (const h of secondary) {
    const ht = nameTokens(h);
    if (seqIn(n, ht) || (np.length >= 2 && seqIn(np, ht))) return { ok: true, basis: "subheading_contains_name", heading: h };
  }
  for (const h of headings) {
    const ht = nameTokens(h);
    if (seqIn(n, ht)) return { ok: true, basis: "heading_contains_name", heading: h };
    if (np.length >= 2 && seqIn(np, ht)) return { ok: true, basis: "heading_contains_name_without_provider", heading: h };
    const hp = stripProvider(ht, prov);
    if (hp.length >= 2 && hp.some((w) => !GENERIC.has(w)) && seqIn(hp, n) && hp.length / n.length >= 0.7) return { ok: true, basis: "name_contains_heading", heading: h };
  }
  return { ok: false, basis: "name_mismatch", heading: headings[0] || null };
}

// Candidate scholarship pages on the provider's own site (and its subdomains).
const SCH_KEEP = /(scholarship|bursar|award|grant|fee-remission|fee-reduction|fee-waiver|tuition-discount|fee-discount)/i;
const SCH_DROP = /(\/sitecore\/|\/news|\/events?\/|\/stories|\/story\/|\/blog|\/media|\/staff|\/people\/|\/profile|login|\/search|\/apply(?:ing)?\b|\/how-to-apply|\/terms|\/conditions|\/faqs?\b|\/rules|\/recipients|\/awardees|\/donat|\/giving|\/alumni\/|teaching-award|staff-award|research-grants?\/|\/grants?-and-funding|\/tag\/|\/category\/|wp-content|\/feed|\.(pdf|jpe?g|png|gif|docx?|xlsx?|zip|mp4)(\?|$))/i;
const SCH_LISTING = /\/(scholarships?|international-scholarships?|scholarships-and-(?:fees|grants|awards|prizes)|find-a-scholarship|find-scholarship|scholarship-search|scholarships-search|awards?|grants?|bursar(?:y|ies)|international|undergraduate|postgraduate|research|domestic)\/?$/i;
export const baseHost = (h: string) => h.toLowerCase().replace(/^www\./, "").split(".").slice(-3).join(".");
// on the provider's own site: its website host or one of its other domains (e.g. monash.edu for monash.edu.au)
export function onSite(hostname: string, hosts: string | string[]) {
  const h = hostname.toLowerCase();
  return (Array.isArray(hosts) ? hosts : [hosts]).filter(Boolean).some((x) => baseHost(h) === baseHost(x) || h.endsWith("." + baseHost(x)));
}
export function keepScholarshipUrl(url: string, host: string | string[]) {
  try {
    const x = new URL(url);
    if (!/^https?:$/.test(x.protocol)) return false;
    if (!onSite(x.hostname, host)) return false;
    if (x.search && /[?&](q|query|search|page|f\.|collection|filter)/i.test(x.search)) return false;
    return SCH_KEEP.test(x.hostname + x.pathname) && !SCH_DROP.test(x.pathname) && !SCH_LISTING.test(x.pathname) && x.pathname.length > 1;
  } catch { return false }
}
export function normUrl(u: string) { try { const x = new URL(u); x.hash = ""; return (x.origin.toLowerCase() + x.pathname.replace(/\/+$/, "") + x.search).replace(/^http:/, "https:") } catch { return u } }

// The page address as a name: last path segment, file extension and a trailing reference number dropped
// (".../monash-thailand-award-6307" -> "monash thailand award").
export function slugTokens(url: string) {
  try {
    const segs = new URL(url).pathname.split("/").filter(Boolean);
    const s = decodeURIComponent(segs[segs.length - 1] || "").replace(/\.(html?|aspx?|php)$/i, "");
    const cut = s.replace(/[-_](?=[a-z]*\d)[a-z0-9]{1,8}$/i, "");
    return [...new Set([s, cut])].map((x) => nameTokens(x.replace(/[-_]+/g, " "))).filter((x) => x.length);
  } catch { return [] }
}
const eq = (a: string[], b: string[]) => a.length > 0 && a.length === b.length && a.every((x, i) => x === b[i]);
const titleHead = (t?: string) => nameTokens(String(t || "").split(/\s+[|:–-]\s+/)[0]);

// Strong match only: the page address or the page title names exactly the scholarship (provider prefix allowed on
// either side). Several different pages matching one name -> the one under an "international" path, else none.
export function matchScholarshipPage(name: string, candidates: { url: string; title?: string }[], prov: Set<string>) {
  const n = nameTokens(name), np = stripProvider(n, prov);
  if (!n.length || (np.length < 2 && n.length < 2)) return null;
  const hits: { url: string; basis: string }[] = [];
  for (const c of candidates) {
    const slugs = slugTokens(c.url), t = titleHead(c.title), tp = stripProvider(t, prov);
    const basis = slugs.some((s) => eq(s, n)) ? "url_slug"
      : slugs.some((s) => { const sp = stripProvider(s, prov); return (np.length >= 2 && (eq(sp, np) || eq(s, np))) || eq(sp, n) }) ? "url_slug_without_provider"
      : eq(t, n) || (np.length >= 2 && (eq(tp, np) || eq(t, np))) ? "page_title" : null;
    if (basis) hits.push({ url: c.url, basis });
  }
  const uniq = [...new Map(hits.map((h) => [normUrl(h.url), h])).values()];
  if (uniq.length === 1) return uniq[0];
  const intl = uniq.filter((h) => /international/i.test(new URL(h.url).pathname));
  if (intl.length === 1) return intl[0];
  return null;
}

// New scholarship from an unheld provider page: a single named scholarship detail page on the provider's own site,
// explicitly open to international students and currently offered. Anything else is not admitted.
const GENERIC_TITLE = /^(scholarships?|awards?|grants?|bursar(?:y|ies)|eligibility|faqs?|find a scholarship|search scholarships|scholarship search|international scholarships?|scholarships? for international students|international students? scholarships?|undergraduate scholarships?|postgraduate scholarships?|research scholarships?|scholarships? and (?:fees|awards|grants|prizes)|fees and scholarships|page not found|404.*|access denied|home)$/i;
// v0.4.1: supporting pages about scholarships are not scholarships (RMIT "... Scholarship Specific Terms and Conditions")
// v0.4.4 (step-2 hand-check): articles and information pages ("The impact of a scholarship", "Your introduction to UC's
// international scholarships", "Costs and scholarships") and faculty listings ("Architecture, design and planning
// international undergraduate scholarships") are not single scholarships.
const NOT_A_SCHOLARSHIP_TITLE = /(\brecap\b|\breceiving\b|\bstudying\b|\bmeet\b|congratulat|\bapplication$|\ba scholarships?\b|introduction to|impact of|\bcosts? and\b|and scholarships\b|scholarships and\b|how to\b|what is\b|\bwhy\b|\btips\b|\bguide\b|\bstor(?:y|ies)\b|\bexperience\b|\b(?:international|undergraduate|postgraduate|research|faculty|college|school|domestic)\b[^|]*\bscholarships$|terms and conditions|conditions of (?:award|scholarship)|\bfaqs?\b|frequently asked|how to apply|information for|guidelines|\bpolicy\b|\brules\b|recipients|winners|finalists|celebrating|announc|\bnews\b|contact us|apply now|application form|register|registration|sponsors?hip information|sponsored students)/i;
// v0.4.5 (step-2 hand-check): a scholarship's own title ends with the scholarship word, optionally followed by a
// qualifier ("(Graduate)", "- 2027", "for Excellence", "in Pharmacy"); page furniture ("--> Scholarships <!--",
// "International Scholarships | UniSC | ..."), student stories ("... Scholarship Shruti") and generic plural titles
// ("Global Curtin scholarships", "UNSW scholarships for international students", "Accommodation scholarships") are not.
const KEYWORD = "(?:scholarship|bursary|bursaries|award|grant|prize|fellowship|stipend|discount|remission|reduction|waiver)";
export function namedScholarshipTitle(t: string) {
  if (/[<>|{}]/.test(t)) return false;
  const m = t.match(new RegExp(`${KEYWORD}(s?)(\\s*\\(.*\\)|\\s*[-–:]\\s*.+|\\s+(?:for|in|of|to|at|from|with)\\s.+|\\s+20\\d\\d.*)?$`, "i"));
  if (!m) return false;
  const plural = /(?:scholarships|bursaries|awards|grants|prizes|fellowships)$/i.test(t.slice(0, (m.index || 0) + m[0].length - (m[2] || "").length).trim());
  if (plural && (!m[2] || /^\s+for\s+(?:all\s+|new\s+|current\s+|commencing\s+|future\s+)?(?:international\s+|domestic\s+)?students?\b/i.test(m[2]))) return false;
  return true;
}
export function scholarshipTitle(html: string) {
  const h1s = [...html.matchAll(/<h1[^>]*>([\s\S]*?)<\/h1>/gi)].map((m) => clean(htmlToText(m[1]))).filter(Boolean);
  const head = (html.match(/<head[\s\S]*?<\/head>/i) || [""])[0];
  const og = (head.match(/<meta[^>]+property=["']og:title["'][^>]*content=["']([^"']*)["']/i) || [])[1];
  const title = (head.match(/<title[^>]*>([\s\S]*?)<\/title>/i) || [])[1];
  const opts = [...h1s, og ? htmlToText(og).split(/\s+[|–]\s+|\s+-\s+/)[0] : "", title ? htmlToText(title).split(/\s+[|–]\s+|\s+-\s+/)[0] : ""].map(clean);
  return opts.find((t) => t.length >= 8 && t.length <= 160 && !GENERIC_TITLE.test(t) && !NOT_A_SCHOLARSHIP_TITLE.test(t) && namedScholarshipTitle(t)) || null;
}
export function internationalEligibility(text: string) {
  const t = text.slice(0, 12000);
  const excluded = /(not (?:open|available) to international|international students (?:are|will) not (?:be )?eligible|(?:only|solely) (?:open|available) to (?:domestic|australian)|domestic students only|must be an? (?:australian|new zealand) citizen|australian citizens?(?:,| or| and) (?:new zealand citizens?,? )?(?:or |and )?permanent residents? only)/i.test(t);
  const explicit = /(\binternational (?:students?|applicants?|candidates?|undergraduate|postgraduate|school leavers?|high school)|open to international|onshore (?:and|or) offshore|offshore students|student visa|overseas students?|full[- ]fee[- ]paying international)/i.test(t);
  return { explicit: explicit && !excluded, excluded };
}
export function currentlyOffered(text: string, today = new Date()) {
  const t = text.slice(0, 15000);
  if (/(no longer (?:be )?(?:offered|available|accepting)|(?:has been|is|was) discontinued|closed permanently|permanently closed|not (?:being )?offered in 20\d\d|this scholarship (?:is|has) (?:now )?closed|will not be offered)/i.test(t)) return { ok: false, reason: "not_offered" };
  const years = [...t.matchAll(/\b(20[1-3]\d)\b/g)].map((m) => Number(m[1])).filter((y) => y >= 2019 && y <= 2035);
  if (years.length && Math.max(...years) < today.getUTCFullYear()) return { ok: false, reason: "past_year_only" };
  return { ok: true, reason: null };
}
// Listing: many links to other scholarship pages inside the page's own content (menus, headers, footers and side
// panels removed first - v0.4.1: RMIT detail pages were counted as listings from their navigation), or a plural
// title ("... scholarships") over several such links.
export function listingLinks(html: string, url: string) {
  // links embedded as escaped HTML (Sydney keeps page content in JSON attributes) count too
  html = html.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&#34;|&quot;/g, '"').replace(/\\"/g, '"');
  const m = html.match(/<main[\s\S]*?<\/main>/i);
  const main = (m && m[0].length > 1500 ? m[0] : html).replace(/<(nav|header|footer|aside)\b[\s\S]*?<\/\1>/gi, " ")
    .replace(/<(div|ul|section)[^>]+(?:class|id)=["'][^"']*(?:menu|breadcrumb|navigation|sidebar|related|footer|header|megamenu)[^"']*["'][\s\S]*?<\/\1>/gi, " ");
  let self = ""; try { self = normUrl(url) } catch { /* */ }
  const links = new Set<string>();
  for (const m of main.matchAll(/<a[^>]+href=["']([^"'#]+)["']/gi)) {
    try { const u = new URL(m[1], url); if (SCH_KEEP.test(u.pathname) && !SCH_LISTING.test(u.pathname) && normUrl(u.href) !== self) links.add(normUrl(u.href)) } catch { /* */ }
  }
  return links.size;
}
export function isListingPage(html: string, url: string, title: string | null) {
  const n = listingLinks(html, url);
  return n >= 15 || (!!title && /\b(scholarships|awards|bursaries|grants)$/i.test(title.trim()) && n >= 5);
}
export function admissionCheck(html: string, finalUrl: string, providerHost: string | string[]) {
  const reasons: string[] = [];
  const text = mainText(html);
  const name = scholarshipTitle(html);
  if (!name) reasons.push("no_named_title");
  let host = ""; try { host = new URL(finalUrl).hostname } catch { /* */ }
  if (!host || !onSite(host, providerHost)) reasons.push("not_provider_domain");
  if (isListingPage(html, finalUrl, name)) reasons.push("listing_page");
  const intl = internationalEligibility(text);
  if (!intl.explicit) reasons.push(intl.excluded ? "domestic_only" : "international_not_stated");
  const off = currentlyOffered(text);
  if (!off.ok) reasons.push(off.reason!);
  if (text.length < 400) reasons.push("too_thin");
  if (name && /\b(award|grant)s?\b/i.test(name) && !/scholarship|bursary|fee/i.test(name) && !/(tuition|scholarship|stipend|bursary)/i.test(text.slice(0, 6000))) reasons.push("not_a_scholarship");
  return { admit: reasons.length === 0, name, reasons, international_explicit: intl.explicit, offered: off.ok, detail_page: !reasons.includes("listing_page") && !!name, listing_links: listingLinks(html, finalUrl) };
}
