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

export function scholarshipLevels(titleText: string, body: string) {
  const t = (titleText + " " + body.slice(0, 3000)).toLowerCase();
  const levels = new Set<string>();
  if (/\bundergraduate\b|\bbachelor/.test(t)) levels.add("undergraduate");
  if (/postgraduate coursework|coursework (?:master|postgraduate)|master(?:'s|s)? (?:degree )?by coursework|graduate (?:certificate|diploma)/.test(t)) levels.add("postgraduate_coursework");
  else if (/\bpostgraduate\b|\bmaster(?:'s|s)?\b/.test(t) && !/\b(phd|doctor of philosophy|higher degree by research)\b/.test(t)) levels.add("postgraduate_coursework");
  if (/\b(phd|doctor of philosophy|higher degree by research|hdr|research degree|master(?:'s|s)? by research|research master)/.test(t)) levels.add("research");
  if (/\b(foundation|pathway|elicos)\b/.test(titleText.toLowerCase())) levels.add("pathway");
  return [...levels].sort();
}

// Field restriction from the scholarship's own name only (page bodies mention many fields in passing).
const FIELDS: [RegExp, string][] = [
  [/\bengineer/i, "asced-03"], [/\b(information technology|computing|computer science|\bict\b|cyber|data science)/i, "asced-02"],
  [/\b(nursing|health|medicine|medical|pharmacy|dentist|midwi|physiotherap|psycholog)/i, "asced-06"],
  [/\b(business|commerce|accounting|management|\bmba\b|finance|economics)/i, "asced-08"], [/\blaw\b|\blegal\b/i, "asced-09"],
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
export function scholarshipValue(body: string) {
  const t = body.slice(0, 6000);
  if (/\b(?:100\s?%|full)\s+(?:tuition|course)\s+fees?\b|\bfull[- ]tuition\b|\bfull fee (?:waiver|scholarship)\b/i.test(t))
    return { type: "percentage", percentage: 100, applies_to: "tuition_fee", context: ctx(t, /full[- ]?(?:tuition|fee)|100\s?%/i) };
  const pct = new Set<number>();
  for (const m of t.matchAll(/(\d{1,3})\s?%\s+(?:off\s+|of\s+)?(?:(?:your|the|annual|first[- ]year|total)\s+)*(?:tuition|course)\s+fees?|(\d{1,3})\s?%\s+(?:tuition\s+)?(?:fee\s+)?(?:reduction|remission|discount|waiver|scholarship)/gi)) {
    const v = Number(m[1] || m[2]); if (v >= 5 && v <= 100) pct.add(v);
  }
  const amt = new Set<number>();
  for (const m of t.matchAll(/(?:A\$|AUD\s?\$?|\$)\s?(\d{1,3}(?:,\d{3})+|\d{3,6})(?:\.\d{2})?/g)) {
    const at = m.index || 0, around = t.slice(Math.max(0, at - 90), at + 90).toLowerCase();
    if (!/(scholarship|award|valued|worth|stipend|bursary|grant|per year|per annum|each year|one-off|one off)/.test(around)) continue;
    if (/(living|accommodation|application fee|cost of|visa|oshc|health cover)/.test(around)) continue;
    const v = Number(m[1].replace(/,/g, "")); if (v >= 500 && v <= 200000) amt.add(v);
  }
  // any other percentage in the scholarship text (tiers by region, level or result) makes a single value unsafe
  const allPct = new Set<number>([...t.matchAll(/(\d{1,3})\s?%/g)].map((m) => Number(m[1])).filter((v) => v >= 5 && v <= 100))
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
  return {
    levels: scholarshipLevels(titleText + " " + name, body),
    ...(() => { const n = scholarshipFields(name); const fac = scholarshipFaculties(body); return { fields: n.length ? n : fac.fields, faculties: fac.faculties, field_unmapped: !n.length && fac.unmapped } })(),
    value: scholarshipValue(body),
    deadline: scholarshipDeadline(body),
    international: /\binternational\b/i.test(titleText + " " + body.slice(0, 4000)),
    eligibility_excerpt: (() => { const at = body.search(/eligib/i); return at >= 0 ? clean(body.slice(at, at + 900)) : null })(),
    text_length: body.length,
  };
}
