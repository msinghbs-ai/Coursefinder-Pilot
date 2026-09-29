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

// v0.5.0 (level hand-check): study levels were read from site menus ("Undergraduate courses Postgraduate courses ...
// Research degrees" on RMIT pages, "Postgraduate Courses Higher Degrees by Research" on Avondale and CQU pages) and
// enquiry forms ("I am interested in: ... Research Degrees"). The level text is now the page content only: from the
// page's own <h1>, without menus, headers, footers, side panels, forms, menu/breadcrumb blocks and link-only lists.
export function contentText(html: string) {
  let h = html.replace(/<(script|style|noscript|svg|template)[\s\S]*?<\/\1>/gi, " ");
  const main = h.match(/<main[\s\S]*?<\/main>/i);
  if (main && main[0].length > 1500) h = main[0];
  const h1 = h.search(/<h1[\s>]/i);
  if (h1 > 0 && htmlToText(h.slice(h1)).length > 300) h = h.slice(h1);
  h = h.replace(/<(nav|header|footer|aside|form|select)\b[\s\S]*?<\/\1>/gi, " ")
    .replace(/<(div|ul|section)[^>]+(?:class|id)=["'][^"']*(?:menu|breadcrumb|navigation|navbar|sidebar|footer|megamenu|site-header)[^"']*["'][\s\S]*?<\/\1>/gi, " ")
    // link-only lists (at least four items, nearly all links): menus that are not marked as such
    .replace(/<ul\b[^>]*>([\s\S]*?)<\/ul>/gi, (all, inner: string) => {
      const items = inner.match(/<li\b[\s\S]*?(?=<li\b|$)/gi) || [];
      const links = items.filter((li) => /<a\b/i.test(li) && htmlToText(li.replace(/<a\b[\s\S]*?<\/a>/gi, "")).length < 4).length;
      return items.length >= 4 && links / items.length >= 0.75 ? " " : all;
    });
  return htmlToText(h);
}

// v0.4.2: levels the text excludes ("excluding Master by Research or PhD") or that describe earlier study ("completed
// an undergraduate degree") are not levels of the scholarship.
export function levelText(body: string) {
  return body
    .replace(/\b(?:excluding|except(?: for)?|other than|not (?:available|eligible|open|applicable) (?:for|to)|does not apply to|cannot be used for|ineligible)\b[^.;:)\n]{0,140}/gi, " ")
    .replace(/\b(?:completed|completing|graduated (?:from|with)|graduates? of|holds?|holding|have finished|prior|previous(?:ly)?|(?:students?|applicants?|those) with)\b[^.;:)\n]{0,80}?\b(?:degree|qualification|diploma|program(?:me)?|studies|course)s?\b/gi, " ");
}
function levelsIn(t: string) {
  const levels = new Set<string>();
  if (/\bundergraduate\b|\bbachelor/.test(t)) levels.add("undergraduate");
  const research = /\b(phd|doctor of philosophy|doctoral|higher degrees? by research|hdr|research degree|master(?:'s|s)? by research|research master|postgraduate research|graduate research|research (?:courses?|programs?|higher degrees?))/.test(t);
  // v0.5.0: "graduate coursework" (Melbourne) is postgraduate coursework; "postgraduate" beside research levels counts
  // when it is not itself "postgraduate research"
  if (/postgraduate coursework|graduate coursework|coursework (?:master|postgraduate)|master(?:'s|s)? (?:degree )?by coursework|graduate (?:certificate|diploma)/.test(t)) levels.add("postgraduate_coursework");
  else if (/\bpostgraduate\b(?!\s+(?:research|by research|\(research\)))|\bmaster(?:'s|s)?\b(?!\s+(?:by research|of philosophy|\(research\)))/.test(t) && (!research || /\bpostgraduate\b(?!\s+(?:research|by research))/.test(t))) levels.add("postgraduate_coursework");
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

// v0.5.0: a scholarship or bursary for an English language course (General English, IELTS preparation, ELICOS, EAP,
// Academic English, English programs) is linked to the provider's English language courses only, never to degrees.
const ENGLISH_COURSE = /\b(general english|ielts prep(?:aration)?|elicos|english for academic purposes|\beap\b|academic english|english (?:language )?(?:programs?|courses?)|english language (?:intensive )?course|english bursary)\b/i;
export function englishCourse(name: string, content = "") {
  // the scholarship's name, or the page's own "Course: General English" field
  const n = name.match(ENGLISH_COURSE);
  const c = content.slice(0, 1500).match(/\bCourse\s*:?\s*(General English|IELTS Preparation|RMIT UP Academic English|Academic English|ELICOS|English for Academic Purposes)\b/);
  const k = (n ? n[1] : c ? c[1] : "").toLowerCase();
  if (!k) return null;
  return { course: /ielts/.test(k) ? "ielts preparation" : /general english/.test(k) ? "general english" : /academic english|academic purposes|\beap\b/.test(k) ? "academic english" : "english" };
}
// v0.5.0: not currently offered - held by a recipient until a later year, not offered, no longer offered or available,
// closed permanently, discontinued. An annual round that has closed for this year is not this.
// v0.5.1: "no longer offered/available" only as a statement about the scholarship ("is no longer offered"), not a
// condition ("... will result in the scholarship being no longer available")
const NOT_OFFERED = /(held in tenure until|currently held in tenure|not currently (?:being )?(?:offered|available|open for applications|accepting applications)|(?:is|are|has been|have been)\s+no longer\s+(?:being\s+)?(?:offered|available|accepting applications)|applications? (?:have |are |is )?closed permanently|permanently closed|(?:has been|is|was) discontinued|will not be offered|not (?:being )?offered in 20\d\d)/i;
export function notOffered(text: string) {
  const m = text.slice(0, 15000).match(NOT_OFFERED);
  if (!m) return null;
  const at = m.index || 0;
  return clean(text.slice(Math.max(0, at - 100), at + 140));
}

export function scholarshipFacts(html: string, titleText: string, name: string) {
  const body = mainText(html);
  const content = contentText(html);
  // levels from the eligibility section when the page has one (pages mention other levels elsewhere); else the page start
  // v0.4.6: the eligibility section is a heading-like "Eligibility" / "Who is eligible" (not "eligible countries"), and
  // when it states no level the page start is used
  // v0.5.0: from the page content (menus and forms removed); the name's own level still decides first
  const at = content.search(/\b(?:eligibility(?: criteria| requirements)?\b|who (?:is|can be) eligible|am i eligible|to be eligible)/i);
  const eligibility = at >= 0 ? content.slice(at, at + 1200) : null;
  // v0.5.2: a page's own "Study level(s)" / "Eligible study level" field decides when present (Melbourne, UQ, ANU, QUT
  // key-details blocks: Ormond College Scholarships "Undergraduate, Honours, Graduate coursework, Graduate research")
  const field = content.match(/\b(?:eligible )?study levels?\s*:?\s+((?:(?:undergraduate|bachelor|honours|postgraduate|graduate|coursework|research|masters?|doctoral|phd|hdr|certificate|diploma|and|or|\/|,|\(|\)|-)\s*)+)/i);
  const fromField = field ? scholarshipLevels(titleText + " " + name, field[1]) : [];
  const fromElig = fromField.length ? fromField : eligibility ? scholarshipLevels(titleText + " " + name, eligibility) : [];
  const eng = englishCourse(name, content);
  const off = notOffered(content);
  return {
    levels: eng ? [] : fromElig.length ? fromElig : scholarshipLevels(titleText + " " + name, content),
    levels_from: eng ? "english_course" : fromField.length ? "study_level_field" : fromElig.length ? "eligibility" : "content",
    ...(eng ? { english_course: eng } : {}),
    not_offered: !!off, ...(off ? { not_offered_context: off } : {}),
    ...(() => { const n = scholarshipFields(name); const fac = scholarshipFaculties(body); return { fields: n.length ? n : fac.fields, faculties: fac.faculties, field_unmapped: !n.length && fac.unmapped } })(),
    value: scholarshipValue(body, name),
    deadline: scholarshipDeadline(body),
    international: /\binternational\b/i.test(titleText + " " + body.slice(0, 4000)),
    eligibility_excerpt: (() => { const at = body.search(/eligib/i); return at >= 0 ? clean(body.slice(at, at + 900)) : null })(),
    text_length: body.length,
  };
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
  if (NOT_OFFERED.test(t) || /this scholarship (?:is|has) (?:now )?closed permanently/i.test(t)) return { ok: false, reason: "not_offered" };
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
