// v0.57.0 (2 Nov 2026, CF-247 missing-field enrichment Priority 1, Platform Admin 2 Nov 2026 10:28): the provider description reader.
// Mode provider_description: the database (public.svc_provider_description_next) gives each provider's verified website hosts, a stored
// About / Overview copy when one is held, the page-name patterns, the pinned model and the limits. The worker uses the stored copy first;
// otherwise it reads the provider's home page directly (robots.txt respected), picks the About / Overview link on the provider's own hosts and
// reads that page (directly; Firecrawl only when the site refuses a direct read, within the existing Firecrawl budget). The pinned model then
// writes 2 to 5 student-facing sentences, each with the exact words of the page that support it. Every sentence's quote is checked against the
// page here; the database repeats the remaining checks (host, length, superlatives, claims, support, duplicates) and proposes the description
// to Layer 4. Nothing here writes a description.
// Pure functions only (no network), so the contract spec can read them.
import { htmlToText } from "./extract.ts";
import { callCost } from "./answer.ts";

export const DESCRIPTION_PROMPT_VERSION = "provider-description-v2";  // v2 (v0.58.0): the length limits are stated to the model

const flatText = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");
const bare = (h: string) => String(h || "").toLowerCase().replace(/^www\./, "").replace(/\.$/, "");

// a host belongs to the provider when it is one of its hosts or a sub-domain of one
export function ownHost(hostname: string, hosts: string[]): boolean {
  const h = bare(hostname);
  return (hosts || []).map(bare).filter(Boolean).some((x) => h === x || h.endsWith("." + x));
}

// v0.58.0 (pilot 2 Nov 2026 16:16): the page rule, the same as security.provider_description_page_v1. The lists are settings sent by the lease
// (page_rule: pdesc.about_prefixes, pdesc.refused_path_words, pdesc.refused_host_labels, pdesc.about_max_segments).
export type PageRule = { about_prefixes?: string[]; refused_path_words?: string[]; refused_host_labels?: string[]; about_max_segments?: number };
export function aboutPageCheck(url: string, hosts: string[], patterns: string[], rule: PageRule = {}): { ok: boolean; rule: string; main: boolean } {
  let u: URL; try { u = new URL(url) } catch { return { ok: false, rule: "wrong_host", main: false } }
  const host = bare(u.hostname);
  if (!/^https?:$/.test(u.protocol) || !ownHost(host, hosts)) return { ok: false, rule: "wrong_host", main: false };
  const main = (hosts || []).map(bare).includes(host);
  const low = (xs?: string[]) => (xs || []).map((x) => String(x).toLowerCase()).filter(Boolean);
  if (!main && low(rule.refused_host_labels).includes(host.split(".")[0])) return { ok: false, rule: "refused_host", main };
  let segs = decodeURIComponent(u.pathname).toLowerCase().replace(/\/+$/, "").split("/").filter(Boolean);
  if (segs.length && /^[a-z]{2}(-[a-z]{2})?$/.test(segs[0])) segs = segs.slice(1);  // a language part (/en/) is not a path part
  const refused = low(rule.refused_path_words);
  if (segs.some((s) => refused.includes(s) || s.split(/[-_.]+/).some((t) => refused.includes(t)))) return { ok: false, rule: "refused_word", main };
  const first = segs[0] || "", max = Number(rule.about_max_segments) > 0 ? Number(rule.about_max_segments) : 2;
  const named = low(patterns).includes(first) || low(rule.about_prefixes).some((x) => first.startsWith(x) && first.length > x.length);
  if (!segs.length || segs.length > max || !named) return { ok: false, rule: "not_about_page", main };
  return { ok: true, rule: "about_page", main };
}

// About / Overview links on the provider's own hosts that pass the page rule, best first: the main site host first, then a link whose text
// names an About page, then the shorter address.
export function aboutLinks(html: string, baseUrl: string, hosts: string[], patterns: string[], rule: PageRule = {}): { url: string; text: string; score: number }[] {
  const res = new Map<string, { url: string; text: string; score: number }>();
  const pats = (patterns || []).map((p) => String(p).toLowerCase().replace(/[-_]/g, " ")).filter((p) => p.length >= 3);
  const re = /<a\b[^>]*href\s*=\s*["']([^"'#]+)["'][^>]*>([\s\S]*?)<\/a>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html || ""))) {
    let u: URL; try { u = new URL(m[1], baseUrl) } catch { continue }
    const key = u.origin.toLowerCase() + u.pathname.toLowerCase().replace(/\/+$/, "");
    const c = aboutPageCheck(key, hosts, patterns, rule);
    if (!c.ok) continue;
    const text = htmlToText(m[2]).toLowerCase().slice(0, 80);
    const score = (c.main ? 20 : 0) + (pats.some((p) => text === p || text.startsWith(p + " ") || text.startsWith("about")) ? 5 : 0) - key.length / 100;
    if (!res.has(key) || res.get(key)!.score < score) res.set(key, { url: key, text, score });
  }
  return [...res.values()].sort((a, b) => b.score - a.score || a.url.length - b.url.length);
}

// the page text the model reads: main text without navigation, header, footer and asides, at most pageChars characters
export function descriptionPageText(html: string, pageChars: number): string {
  let h = String(html || "");
  const main = h.match(/<main[\s\S]*?<\/main>/i);
  if (main && main[0].length > 1500) h = main[0];
  h = h.replace(/<(nav|header|footer|aside)\b[\s\S]*?<\/\1>/gi, " ");
  return htmlToText(h).slice(0, Math.max(1000, pageChars));
}

// the letters of an abbreviation occur in order in the name it abbreviates (UTS in University of Technology Sydney)
const inOrder = (abbr: string, name: string) => {
  const a = abbr.toLowerCase().replace(/[^a-z0-9]/g, ""), n = name.toLowerCase().replace(/[^a-z0-9]/g, "");
  if (a.length < 2) return false;  // fixed: a one-letter abbreviation proves nothing
  let at = 0;
  for (const ch of n) if (ch === a[at] && ++at === a.length) return true;
  return false;
};

// The official host alone does not prove which institution a page describes. Use the current
// catalogue names, never a shortened shared label such as "Monash" for Monash University.
// A missing proof is held before any paid AI call; it does not change the catalogue identity.
// v0.59.12 (CF-247 F-PDESC, Platform Admin data population mandate 9 Nov 2026 \u00a72): the catalogue holds some names with a trailing abbreviation or a list of
// entities ("University of Technology Sydney (UTS)", "The University of Newcastle (UoN), The University of Newcastle Language Centre, Sydney",
// "Torrens University Australia; Torrens University Language Centre; ..."). No official page prints those whole strings, so the whole-string label could
// never be proved. Two more labels are derived from the same catalogue name, never from the page and never from a shorter shared name:
//   1 the name without a parenthetical that is only an abbreviation of it (its letters occur in order in the name: UTS, UniMelb, UoN, Deakin, UTas, RMIT;
//     a parenthetical that qualifies the name, such as "(Belfast)", is kept, so "Queen's University (Belfast)" is not widened to "Queen's University");
//   2 the first entity of a ';' or ',' list, when it is still a full institution name (two or more words with university, college, polytechnic or institute).
// Every other check below is unchanged: the label must still be the whole of a title or h1 (plus framing words), a different institution's heading
// is still a conflict, and a sub-unit heading is still refused.
// v0.59.15 (CF-247 F-PDESC, 10 Nov 2026): the catalogue holds the registered company name of many private colleges ("Helix College Pty Ltd", "Thames International College
// Pty Ltd", "Imperial College of New Zealand Limited"). The company form is not part of the name an institution prints on its own page ("About Helix College", site name
// "Helix College"), so the whole-string label could never be proved (89 of the 159 live identity holds of the v2 reader, read 10 Nov 2026, carry such a form). The same catalogue name
// without its trailing company form (Pty Ltd, Pty Limited, Limited, Ltd, Inc, Incorporated, LLC, Limited Partnership) is one more derived label, treated exactly like the
// abbreviation-free and first-entity labels below: never taken from the page, still needs two or more words, still must be the whole of a title, h1 or site-name segment
// (plus framing words) on the provider's own verified host, and a segment with extra words, another institution or a sub-unit is still a conflict.
const COMPANY_FORM = /(?:[\s,]+(?:pty\.?\s+ltd\.?|pty\.?\s+limited|limited\s+partnership|limited|ltd\.?|inc\.?|incorporated|l\.?l\.?c\.?))+[\s.,]*$/i;
export function withoutCompanyForm(name: string): string {
  const s = String(name || "").replace(/\s+/g, " ").trim();
  if (s.length > 200) return s;  // fixed: the pattern backtracks on very long runs of separators; no real catalogue name is this long
  const r = s.replace(COMPANY_FORM, "").replace(/[\s,;]+$/, "").trim();
  return r && r !== s && r.split(/\s+/).length >= 2 ? r : s;
}

// v0.63.0 (CF-247 F-PDESC, Platform Admin 10 Nov 2026, Holmesglen "Holmesglen, Holmesglen Institute" held provider_name_not_proved: the page title is "About Us - Holmesglen Institute"):
// the catalogue lists the short name first and the full name second, and only the first entity of a list was ever a label. A LATER entity of the list is now a label only when it is the
// full name of the FIRST entity: the first is a bare short name (no university, college, polytechnic or institute word in it) and the later entity is that name and nothing else but
// institution words ("Holmesglen" -> "Holmesglen Institute"). Lists of different institutions are not touched: "Murdoch College, The University of Adelaide College, Kaplan International
// College Adelaide" or "Humber College; Humber Trading Institute" have no bare first entity or carry other words, so a page of one entity never proves the merged record, and a centre, school,
// campus, faculty or department is never a name here. The label keeps every safeguard of the first-entity label: it must still be the whole of a title, h1 or site-name segment plus framing
// words, on the provider's own verified host, with no extra word, no other institution and no sub-unit.
const ENTITY_GENERIC = new Set(["university", "college", "polytechnic", "institute", "the", "of"]);
const ENTITY_UNIT = /\b(campus|campuses|faculty|faculties|school|schools|centre|centres|center|centers|department|division|library)\b/i;
function fullNameOfShortEntity(first: string, later: string): boolean {
  const toks = (x: string) => String(x || "").normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);
  const f = toks(first), l = toks(later);
  if (!f.length || l.length < 2 || f.some((t) => ENTITY_GENERIC.has(t))) return false;      // the first entity is a bare short name
  if (!l.some((t) => t === "university" || t === "college" || t === "polytechnic" || t === "institute")) return false;
  if (ENTITY_UNIT.test(later)) return false;
  if (!f.every((t) => l.includes(t))) return false;                                           // it contains the first entity
  return l.every((t) => f.includes(t) || ENTITY_GENERIC.has(t));                              // and nothing else but institution words
}

// withForm=false keeps the strict (segment-free) proof exactly as it was before v0.59.15: the company-form-free label is for the segment proof only
export function descriptionIdentityLabels(names: string[], withForm = true): string[] {
  const institution = /\b(university|college|polytechnic|institute)\b/i;
  const out: string[] = [];
  for (const raw of names || []) {
    const full = String(raw || "").replace(/\s+/g, " ").trim();
    if (!full) continue;
    // the catalogue name as held, then (v0.59.15) the same name without its trailing company form; each goes through the same two derivations
    for (const name of [...new Set(withForm ? [full, withoutCompanyForm(full)] : [full])]) {
      out.push(name);
      // 1 abbreviation-only parentheticals
      const bare = name.replace(/\s*\(([^()]*)\)/g, (whole, inner) => inOrder(String(inner), name.replace(/\([^()]*\)/g, "")) ? "" : whole).replace(/\s+/g, " ").replace(/\s+([,;])/g, "$1").trim();
      if (bare && bare !== name) out.push(bare);
      // 2 the first entity of a list
      for (const candidate of [name, bare]) {
        if (!/[;,]/.test(candidate)) continue;
        const head = candidate.split(/[;,]/)[0].trim();
        for (const first of new Set(withForm ? [head, withoutCompanyForm(head)] : [head])) if (first.split(/\s+/).length >= 2 && institution.test(first)) out.push(first);
        // 3 (v0.63.0) a later entity of the list that is the full name of a bare short first entity ("Holmesglen, Holmesglen Institute")
        for (const later of candidate.split(/[;,]/).slice(1).map((x) => x.trim()).filter(Boolean)) {
          for (const e of new Set(withForm ? [later, withoutCompanyForm(later)] : [later])) if (fullNameOfShortEntity(head, e)) out.push(e);
        }
      }
    }
  }
  return out;
}

export type DescriptionIdentity = { ok: boolean; rule: string; matched_name?: string; via?: string };
// v0.63.0 (diagnostics only): what the proof used and where it refused, so a conflict names its own cause. Filled while the proof runs; nothing reads it back, no result depends on it.
export const IDENTITY_TRACE_TEXT_MAX = 160;      // fixed: the longest excerpt kept (a diagnostic excerpt, not an operating value)
export const IDENTITY_TRACE_HEADINGS_MAX = 12;   // fixed: the most headings listed (a diagnostic excerpt, not an operating value)
export type IdentityTrace = {
  labels?: string[]; aliases?: string[]; headings?: { tag: string; text: string }[];
  strict?: { rule: string; why: string; heading?: string };
  registry?: { reached: boolean; why?: string; rule?: string; tag?: string; heading?: string; segment?: string; extra?: string };
  returned?: string;
};
const cut = (x: unknown) => String(x ?? "").replace(/\s+/g, " ").trim().slice(0, IDENTITY_TRACE_TEXT_MAX);
function strictSourceIdentity(html: string, page: string, names: string[], trace?: IdentityTrace): DescriptionIdentity {
  const words = (s: string) => String(s || "").normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
    .replace(/&/g, " and ").replace(/[^a-z0-9]+/g, " ").replace(/^the\s+/, "").trim();
  const labels = [...new Set(descriptionIdentityLabels(names || [], false).map(words).filter((s) => s.split(" ").length > 1))];
  const contains = (text: string, label: string) => (` ${words(text)} `).includes(` ${label} `);
  const headings = Array.from(String(html || "").matchAll(/<(title|h1)\b[^>]*>([\s\S]*?)<\/\1>/gi), (m) => ({ tag: m[1].toLowerCase(), text: htmlToText(m[2]) }));
  const matched = labels.find((name) => contains(page, name) || headings.some((h) => contains(h.text, name)));
  if (trace) trace.labels = labels.map(cut).slice(0, IDENTITY_TRACE_HEADINGS_MAX);
  if (!matched) { if (trace) trace.strict = { rule: "provider_name_not_proved", why: "no label is in the page text or a title or h1" }; return { ok: false, rule: "provider_name_not_proved" } }
  const subunits = /\b(campus|campuses|faculty|faculties|school|schools)\b/g;
  if (headings.some((h) => h.tag === "h1" && (words(h.text).match(subunits) || []).some((unit) => !(` ${matched} `).includes(` ${unit} `)))) {
    if (trace) trace.strict = { rule: "provider_subunit_source", why: "an h1 names a campus, faculty or school", heading: cut(headings.find((h) => h.tag === "h1" && (words(h.text).match(subunits) || []).some((unit) => !(` ${matched} `).includes(` ${unit} `)))?.text) };
    return { ok: false, rule: "provider_subunit_source" };
  }
  // A heading identifying a different university or college is stronger evidence of a conflict
  // than a passing mention of the requested name in the body (partnerships, history, offshore sites).
  const institutionalHeadings = headings.filter((h) => /\b(university|college|polytechnic|institute)\b/.test(words(h.text))
    && words(h.text).replace(/\b(about|us|the|our|who|we|are|overview|profile|welcome|to|at|university|college|polytechnic|institute)\b/g, "").trim());
  const subjectHeadings = institutionalHeadings.some((h) => h.tag === "h1") ? institutionalHeadings.filter((h) => h.tag === "h1") : institutionalHeadings;
  if (subjectHeadings.length && !subjectHeadings.some((h) => labels.some((name) => contains(h.text, name)))) {
    if (trace) trace.strict = { rule: "provider_name_conflict", why: "a title or h1 names another institution and none names this one", heading: cut(subjectHeadings[0].text) };
    return { ok: false, rule: "provider_name_conflict" };
  }
  // An offshore branch can include its parent's complete name ("X University Malaysia").
  // A named institutional h1 must identify this catalogue institution without an extra entity suffix.
  // When h1 is generic, the institutional title must provide that same exact identity proof.
  const namedH1 = headings.filter((h) => h.tag === "h1" && labels.some((name) => contains(h.text, name)));
  const framing = /\b(about|us|the|our|who|we|are|overview|profile|welcome|to|at|a|glance|facts|and|figures)\b/g;
  const proofHeadings = namedH1.length ? namedH1 : headings.filter((h) => h.tag === "title");
  if (!proofHeadings.some((h) => labels.some((name) => contains(h.text, name) && !words(h.text).replace(name, " ").replace(framing, " ").trim()))) {
    if (trace) trace.strict = { rule: "provider_name_conflict", why: proofHeadings.length ? (namedH1.length ? "the h1 that names the provider carries other words" : "the name is in the page text but no h1 names the provider and the title is not the name alone") : "the name is in the page text but there is no title or h1 that is the name alone", heading: cut(proofHeadings[0]?.text) };
    return { ok: false, rule: "provider_name_conflict" };
  }
  return { ok: true, rule: "current_provider_name", matched_name: matched };
}

// v0.59.13 (CF-247 F-PDESC, Platform Admin Directive 3, Blocker B): registry-proved identity.
// The strict proof above needs the title or h1 to be the provider's whole catalogue name and nothing else. Official pages rarely print that: the
// title is "About UTS | University of Technology Sydney", the h1 is "About UC", the site name is repeated, or a tagline follows the name. About
// 65 of 115 live reads were held for that reason although the registry (security.provider_description_identity_v1) already proved the provider.
// When the strict proof fails (never when it passed, never on a sub-unit h1), the worker also holds the evidence the database gave it: the
// provider's own verified hosts (security.provider_hosts_v1) and the page's final address. The page is then accepted only when ALL agree:
//   1 the page address is on one of the provider's own verified hosts (ownHost, the same helper as the About-page rule);
//   2 a segment of the title, an h1, og:site_name or og:title (split at | : - dash , ; /) is exactly the catalogue name (or a label derived from it
//     by descriptionIdentityLabels) or exactly a registry abbreviation of it (descriptionIdentityAliases), plus framing words only; or, when no
//     heading names the provider, the page's opening statement begins with the full catalogue name;
//   3 no segment of those headings names anything else: a segment that contains the name or an abbreviation with extra words (an offshore branch
//     "X University Malaysia", "UTS College"), or another institution, college, faculty, school or campus, is a conflict.
// Nothing here relaxes the checks above, the About-page rule, the sub-unit rule, the manual locks or the database validation. No setting is needed:
// the hosts and names come from the lease, and the framing words are the same list as the strict proof.
const identityWords = (s: string) => String(s || "").normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase()
  .replace(/&/g, " and ").replace(/[^a-z0-9]+/g, " ").replace(/^the\s+/, "").trim();
const IDENTITY_FRAMING = /\b(about|us|the|our|who|we|are|overview|profile|welcome|to|at|a|glance|facts|and|figures)\b/g;
const IDENTITY_GENERIC = /\b(university|college|polytechnic|institute)\b/g;
const IDENTITY_OTHER_INSTITUTION = /\b(university|college|polytechnic|institute)\b/;
const IDENTITY_SUBUNIT = /\b(campus|campuses|faculty|faculties|school|schools)\b/;

// Registry abbreviations of a catalogue name, never taken from the page:
//   1 a parenthetical that abbreviates the name ("University of Technology Sydney (UTS)", "(UoN)"); a bare word of the name itself ("(Deakin)",
//     "(RMIT)") is not an abbreviation, it is the shared name that also belongs to a college of the same group;
//   2 the initialism of the capitalised words of the first entity of an institution name (University of Technology Sydney -> UTS), three letters
//     or more (a two-letter initialism such as UC or CC is shared by too many institutions).
export function descriptionIdentityAliases(names: string[]): string[] {
  const out: string[] = [], seen = new Set<string>();
  const add = (a: string) => { const w = identityWords(a); if (w && !seen.has(w)) { seen.add(w); out.push(a) } };
  for (const raw of names || []) {
    const name = String(raw || "").replace(/\s+/g, " ").trim();
    if (!name) continue;
    const plain = name.replace(/\s*\([^()]*\)/g, "").replace(/\s+/g, " ").trim();
    const own = identityWords(plain).split(" ");
    for (const m of name.matchAll(/\(([^()]*)\)/g)) {
      const inner = m[1].trim(), toks = identityWords(inner).split(" ").filter(Boolean);
      if (!toks.length || !inOrder(inner, plain) || toks.every((t) => own.includes(t))) continue;
      add(inner);
    }
    const first = withoutCompanyForm(plain.split(/[;,]/)[0].trim());  // v0.59.15: the company form is not a capitalised word of the name ("Engineering Institute of Technology Pty Ltd" is EIT, not EITPL)
    if (/\b(university|college|polytechnic|institute)\b/i.test(first)) {
      const letters = first.split(/\s+/).filter((w, i) => !(i === 0 && /^the$/i.test(w))).filter((w) => /^[A-Z]/.test(w)).map((w) => w[0]).join("");
      if (letters.length >= 3) add(letters);  // fixed: shorter initialisms (UC, CC) are shared by too many institutions
    }
  }
  return out;
}

// v0.59.15 (CF-247 F-PDESC, Platform Admin directive 10 Nov 2026, University of Sydney and UTS held by the v2 reader): a heading is read the way a browser shows it.
// htmlToText decodes only a few entities, so the numeric ones that real titles use (UTS: "About UTS &#x2013; University of Technology Sydney", Auswide "&#038;",
// a curly apostrophe "&#8217;") reached the proof as stray words ("x2013") and made the UTS title look like it named something else. Only the identity proof
// decodes them (headings and meta content), and only to the characters the page shows; the page text the model reads is not changed.
const NAMED_ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", ndash: "–", mdash: "—", lsquo: "‘", rsquo: "’", ldquo: "“", rdquo: "”", hellip: "…", bull: "•", middot: "·", reg: "®", trade: "™", copy: "©" };
export function decodeHeadingEntities(s: string): string {
  return String(s || "").replace(/&(?:#(\d{1,7})|#[xX]([0-9a-fA-F]{1,6})|([a-zA-Z]{2,8}));/g, (whole, dec, hex, name) => {
    if (name) return NAMED_ENTITIES[String(name).toLowerCase()] ?? whole;
    const cp = dec !== undefined ? Number(dec) : parseInt(hex, 16);
    // fixed: Unicode limit; anything outside it is left as printed
    return Number.isInteger(cp) && cp > 0 && cp <= 0x10ffff && !(cp >= 0xd800 && cp <= 0xdfff) ? String.fromCodePoint(cp) : whole;
  });
}

// the headings that identify the page's subject: the title, every h1, og:site_name, og:title and application-name
function identityHeadings(html: string): { tag: string; text: string }[] {
  const out = Array.from(String(html || "").matchAll(/<(title|h1)\b[^>]*>([\s\S]*?)<\/\1>/gi), (m) => ({ tag: m[1].toLowerCase(), text: decodeHeadingEntities(htmlToText(m[2])) }));
  for (const m of String(html || "").matchAll(/<meta\b[^>]*>/gi)) {
    const key = (m[0].match(/\b(?:property|name)\s*=\s*["']([^"']+)["']/i) || [])[1]?.toLowerCase();
    if (key !== "og:site_name" && key !== "og:title" && key !== "application-name") continue;
    const c = m[0].match(/\bcontent\s*=\s*(?:"([^"]*)"|'([^']*)')/i);
    if (c) out.push({ tag: key, text: decodeHeadingEntities(htmlToText(c[1] ?? c[2] ?? "")) });
  }
  return out;
}

// v0.59.15: does a heading segment NAME another institution, as opposed to merely using the word "university" or "college"?
// The University of Sydney's About page has the h1 "We get behind a range of activities ... in our university." That sentence names nobody, but the v2 reader
// treated the bare word as another institution and refused the page although the title ("About us - The University of Sydney") and the site name proved the provider.
// A segment names an institution when an institution word (university, college, polytechnic, institute) follows a capitalised word that is not a plain
// word of English ("Western Sydney University", "Murdoch College") or is followed by "of" and a capitalised word ("University of Melbourne", "College of Arts").
// When the segment carries no case to read (all capitals or all lower case) the old rule stands: the bare word is a conflict. The sub-unit words
// (campus, faculty, school) are NOT part of this relaxation and are still refused wherever they occur.
const PLAIN_WORDS = new Set(["the", "our", "a", "an", "this", "that", "your", "my", "its", "their", "every", "each", "any", "one", "of", "to", "at", "in", "for", "with", "from", "and", "or", "about", "us", "welcome", "who", "we", "are", "is", "as", "by", "on", "into", "all", "study", "join"]);
const INSTITUTION_WORD = /^(university|college|polytechnic|institute)$/i;
export function namesAnotherInstitution(segment: string): boolean {
  const seg = String(segment || "");
  const letters = seg.replace(/[^\p{L}]/gu, "");
  const upper = /\p{Lu}/u.test(letters), lower = /\p{Ll}/u.test(letters);
  if (!upper || !lower) return IDENTITY_OTHER_INSTITUTION.test(identityWords(seg));
  // a possessive is not part of the name and a hyphen or other punctuation separates words ("Monash University’s story", "Griffith-University news")
  const toks = seg.replace(/[\u2019']s\b/g, "").split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  const cap = (t?: string) => !!t && /^\p{Lu}/u.test(t);
  for (let i = 0; i < toks.length; i++) {
    if (!INSTITUTION_WORD.test(toks[i])) continue;
    if (cap(toks[i - 1]) && !PLAIN_WORDS.has(toks[i - 1].toLowerCase())) return true;
    if (/^of$/i.test(toks[i + 1] || "")) {
      const j = /^the$/i.test(toks[i + 2] || "") ? i + 3 : i + 2;  // "University of the Sunshine Coast"
      if (cap(toks[j])) return true;
    }
  }
  return false;
}

// the opening statement: the first paragraph of the main text (navigation, header, footer and asides removed)
function openingParagraph(html: string): string {
  let h = String(html || "");
  const main = h.match(/<main[\s\S]*?<\/main>/i);
  if (main) h = main[0];
  h = h.replace(/<(nav|header|footer|aside|script|style)\b[\s\S]*?<\/\1>/gi, " ");
  for (const m of h.matchAll(/<p\b[^>]*>([\s\S]*?)<\/p>/gi)) { const t = htmlToText(m[1]).replace(/\s+/g, " ").trim(); if (identityWords(t)) return t }
  return "";
}

function registryEvidenceIdentity(html: string, names: string[], trace?: IdentityTrace): DescriptionIdentity {
  const uniq = (xs: string[]) => [...new Set(xs.map(identityWords).filter(Boolean))];
  const labels = uniq(descriptionIdentityLabels(names || [])).filter((l) => l.split(" ").length > 1);
  const aliases = uniq(descriptionIdentityAliases(names || [])).filter((a) => !labels.includes(a));
  const phrases = [...labels, ...aliases].sort((a, b) => b.length - a.length);
  const has = (w: string, phrase: string) => (` ${w} `).includes(` ${phrase} `);
  const strip = (w: string, ps: string[]) => { let r = w; for (const p of ps) r = r.replace(new RegExp(`(?<=^| )${p}(?= |$)`, "g"), " "); return r.replace(/\s+/g, " ").trim() };
  const fail = (rule: string, at?: { tag: string; heading: string; segment: string; extra?: string }): DescriptionIdentity => {
    if (trace) trace.registry = { reached: true, rule, ...(at ? { tag: at.tag, heading: cut(at.heading), segment: cut(at.segment), ...(at.extra ? { extra: cut(at.extra) } : {}) } : {}) };
    return { ok: false, rule };
  };
  let proof: { name: string; via: string } | null = null, aboutHeading = false;
  const heads = identityHeadings(html);
  if (trace) { trace.labels = labels.map(cut).slice(0, IDENTITY_TRACE_HEADINGS_MAX); trace.aliases = aliases.map(cut).slice(0, IDENTITY_TRACE_HEADINGS_MAX); trace.headings = heads.slice(0, IDENTITY_TRACE_HEADINGS_MAX).map((h) => ({ tag: h.tag, text: cut(h.text) })) }
  for (const el of heads) {
    for (const seg of el.text.split(/\s[-–—―]\s|[|:·•,;\/–—]/)) {
      const w = identityWords(seg);
      if (!w) continue;
      const label = labels.find((l) => has(w, l)), alias = aliases.find((a) => has(w, a));
      if (label || alias) {
        // the name or an abbreviation with extra words ("X University Malaysia", "UTS College") names something else
        const extra = strip(w, phrases).replace(IDENTITY_FRAMING, " ").replace(/\s+/g, " ").trim();
        if (extra) return fail(el.tag === "h1" && IDENTITY_SUBUNIT.test(extra) ? "provider_subunit_source" : "provider_name_conflict", { tag: el.tag, heading: el.text, segment: seg, extra });
        if (label) { if (!proof || proof.via !== "registry_heading_name") proof = { name: label, via: "registry_heading_name" } }  // the whole name outranks an abbreviation
        else proof ||= { name: alias!, via: "registry_heading_abbreviation" };
        continue;
      }
      if (!w.replace(IDENTITY_FRAMING, " ").replace(IDENTITY_GENERIC, " ").trim()) { if (/\b(about|overview|profile|welcome|who)\b/.test(w)) aboutHeading = true; continue }  // a generic heading ("About us", "About the university")
      // another institution, college, faculty, school or campus; v0.59.15: a bare institution word in a sentence is not a name (namesAnotherInstitution), a sub-unit word still is
      if (IDENTITY_SUBUNIT.test(w) || namesAnotherInstitution(seg)) return fail(el.tag === "h1" && IDENTITY_SUBUNIT.test(w) ? "provider_subunit_source" : "provider_name_conflict", { tag: el.tag, heading: el.text, segment: seg, extra: IDENTITY_SUBUNIT.test(w) ? "a sub-unit word" : "another institution" });
    }
  }
  if (proof) { if (trace) trace.registry = { reached: true }; return { ok: true, rule: "current_provider_name", matched_name: proof.name, via: proof.via } }
  // no heading names the provider and none names another, and a heading says this is an About page: the opening statement must begin with the whole catalogue name
  if (!aboutHeading) { const r = fail("provider_name_not_proved"); if (trace) trace.registry!.extra = "no heading names the provider and none says About"; return r }
  const para = openingParagraph(html), pw = identityWords(para);
  const label = labels.find((l) => pw === l || pw.startsWith(l + " "));
  if (label) {
    const sentence = para.split(/(?<=[.!?])\s/)[0];
    const elsewhere = /\b(?:[A-Z][\w'’-]*\s+){1,5}(?:University|College|Polytechnic|Institute|School)\b|\b(?:University|College|Institute|School)\s+of\s+[A-Z]/;
    const rest = sentence.replace(new RegExp(label.split(" ").join("[\\s\\W]+"), "ig"), " ");
    if (!elsewhere.test(rest) && !IDENTITY_SUBUNIT.test(identityWords(rest))) { if (trace) trace.registry = { reached: true }; return { ok: true, rule: "current_provider_name", matched_name: label, via: "registry_opening_statement" } }
  }
  const last = fail("provider_name_not_proved");
  if (trace) trace.registry!.extra = "no heading names the provider; the opening statement does not begin with its name";
  return last;
}

// v0.62.0 (CF-247 F-PDESC, Platform Admin 10 Nov 2026): what the identity proof was given, kept when it FAILS (observability only; no page passes or fails differently).
// 199 reads were held provider_name_not_proved (Swinburne, Collarts, Alphacrucis, Ara, Whitecliffe, Auckland Institute of Studies among them) and the database could not
// say why: a page drawn in the browser (a script shell with no title or h1 in the raw HTML), a title with extra words, the short name only. This is the evidence for that
// decision: the first <title>, up to three <h1>, og:site_name (each as the proof reads it, entities decoded, white space collapsed), the size of the raw HTML and of the
// visible text, and whether the page looks like a script shell. It is stored by svc_provider_description_record inside checks.identity.seen.
export const IDENTITY_SEEN_TEXT_MAX = 160;        // fixed: the longest heading excerpt kept (a diagnostic excerpt, not an operating value)
export const IDENTITY_SEEN_H1_MAX = 3;            // fixed: the most h1 headings kept (a diagnostic excerpt, not an operating value)
export const IDENTITY_SHELL_TEXT_MAX = 200;       // fixed: below this many visible characters a page with script tags is a shell drawn in the browser (a diagnostic label, not an operating value)
export type DescriptionIdentitySeen = { title: string; h1: string[]; og_site_name: string; html_chars: number; text_chars: number; has_script_shell: boolean };
export function descriptionIdentitySeen(html: string): DescriptionIdentitySeen {
  const raw = String(html || "");
  const read = (inner: string) => decodeHeadingEntities(htmlToText(inner)).replace(/\s+/g, " ").trim().slice(0, IDENTITY_SEEN_TEXT_MAX);
  const title = raw.match(/<title\b[^>]*>([\s\S]*?)<\/title>/i);
  const h1: string[] = [];
  for (const m of raw.matchAll(/<h1\b[^>]*>([\s\S]*?)<\/h1>/gi)) { const t = read(m[1]); if (t) h1.push(t); if (h1.length >= IDENTITY_SEEN_H1_MAX) break }
  let site = "";
  for (const m of raw.matchAll(/<meta\b[^>]*>/gi)) {
    if ((m[0].match(/\b(?:property|name)\s*=\s*["']([^"']+)["']/i) || [])[1]?.toLowerCase() !== "og:site_name") continue;
    const c = m[0].match(/\bcontent\s*=\s*(?:"([^"]*)"|'([^']*)')/i);
    if (c) { site = read(c[1] ?? c[2] ?? ""); break }
  }
  // the visible text of the whole page (no cap at the model's page length): the same reader as the page text, with the navigation left in
  const text_chars = htmlToText(raw).replace(/\s+/g, " ").trim().length;
  return { title: title ? read(title[1]) : "", h1, og_site_name: site, html_chars: raw.length, text_chars, has_script_shell: text_chars < IDENTITY_SHELL_TEXT_MAX && /<script\b/i.test(raw) };
}

// The identity proof the reader applies. `evidence` is what the database gave the worker: the page's final address and the provider's own verified
// hosts. Without it, or when the page is not on one of those hosts, only the strict proof applies, exactly as before.
export function descriptionSourceIdentity(html: string, page: string, names: string[], evidence?: { url?: string; hosts?: string[] }, trace?: IdentityTrace): DescriptionIdentity {
  const strict = strictSourceIdentity(html, page, names, trace);
  const done = (r: DescriptionIdentity, from: string, why?: string) => { if (trace) { trace.returned = from; if (why && !trace.registry) trace.registry = { reached: false, why } } return r };
  if (strict.ok) return done(strict, "strict", "strict proof passed");
  if (strict.rule === "provider_subunit_source") return done(strict, "strict", "strict proof refused on a sub-unit");
  if (!evidence) return done(strict, "strict", "no registry evidence given");
  let host = "";
  try { host = new URL(String(evidence.url || "")).hostname } catch { return done(strict, "strict", "the page address cannot be read") }
  if (!/^https?:$/.test(new URL(String(evidence.url)).protocol) || !ownHost(host, evidence.hosts || [])) return done(strict, "strict", "the page is not on one of the provider's verified hosts");
  const registry = registryEvidenceIdentity(html, names, trace);
  return registry.ok || registry.rule === "provider_subunit_source" ? done(registry, "registry") : done(strict, "strict");
}

// The lease protocol this worker follows: reserve a conservative price with svc_provider_description_reserve_v1 before every paid call.
export const DESCRIPTION_WORKER_PROTOCOL = "provider-description-reserve-v1";

// Worker-side check: only long copied official passages. Numbers and historic context are decided once, evidence-aware, by
// security.provider_description_validate_v1 (validation 5 Nov 2026, decision 20:03 §2: no keyword- or format-only rejection).
// Keep the whole answer and quotes; hold it rather than rewriting any sentence to make it pass.
// v0.60.0: the worker no longer holds the whole answer for a copied sentence (rule verbatim_passage). The same test is made per sentence by
// security.provider_description_validate_v1, which leaves out a sentence that copies its quote and keeps the sentences that pass every rule.
export function descriptionClaimCheck(answer: any, maxVerbatimChars?: number): { ok: boolean; rule?: string; reason?: string } {
  if (!Array.isArray(answer?.sentences)) return { ok: false, rule: "invalid_answer", reason: "The answer has no sentence array." };
  if (maxVerbatimChars !== undefined && (!Number.isInteger(maxVerbatimChars) || maxVerbatimChars < 1)) return { ok: false, rule: "invalid_verbatim_limit", reason: "The governed quotation-copy limit is unavailable." };
  for (const s of answer.sentences) {
    if (maxVerbatimChars !== undefined) {
      const normalized = (value: unknown) => String(value || "").replace(/\s+/g, " ").trim().toLowerCase();
      const text = Array.from(normalized(s?.text)), quote = normalized(s?.quote), span = maxVerbatimChars;
      for (let i = 0; i + span <= text.length; i++) {
        if (quote.includes(text.slice(i, i + span).join(""))) return { ok: false, rule: "verbatim_passage", reason: "A long official passage was copied; a concise source-grounded paraphrase is required." };
      }
    }
  }
  return { ok: true };
}

// OpenRouter's model catalogue quotes USD per token/request. A UTF-8 byte per prompt token
// bounds the byte-token vocabulary, including the JSON schema; the extra envelope covers
// provider message framing. Missing or unfamiliar charge components fail closed.
export function descriptionCostQuote(request: any, catalogue: any): { ok: false; reason: string } | { ok: true; model: string; max_cost_usd: number; input_tokens_bound: number; output_tokens_bound: number; pricing: Record<string, number>; provider_max_price: { prompt: number; completion: number; request: number } } {
  const model = String(request?.model || ""), output = Number(request?.max_tokens);
  if (!model || !Number.isInteger(output) || output <= 0 || !Array.isArray(catalogue?.data)) return { ok: false, reason: "model_pricing_unavailable" };
  const entry = catalogue.data.find((m: any) => m?.id === model), price = entry?.pricing;
  if (!price || typeof price !== "object") return { ok: false, reason: "model_pricing_unavailable" };
  const allowed = new Set(["prompt", "completion", "request", "image", "web_search", "internal_reasoning", "input_cache_read", "input_cache_write", "audio", "audio_output"]);
  const rates: Record<string, number> = {};
  for (const [key, value] of Object.entries(price)) {
    if ((typeof value !== "string" && typeof value !== "number") || String(value).trim() === "" || !Number.isFinite(Number(value)) || Number(value) < 0) return { ok: false, reason: "invalid_model_pricing" };
    if (!allowed.has(key) && Number(value) !== 0) return { ok: false, reason: "unrecognised_pricing_component" };
    rates[key] = Number(value);
  }
  if (rates.prompt == null || rates.completion == null) return { ok: false, reason: "model_pricing_unavailable" };
  // The catalogue may quote the cheapest provider. OpenRouter's enforced max_price filter
  // prevents same-model provider routing from charging above the rates used to reserve.
  // API contract: https://openrouter.ai/docs/guides/routing/provider-selection#max-price
  const precision = 1e9; // fixed: round price caps and USD reservations upwards to nanodollar precision.
  const maxPrice = { prompt: Math.ceil(rates.prompt * 1e6 * precision) / precision, completion: Math.ceil(rates.completion * 1e6 * precision) / precision, request: rates.request || 0 }; // fixed: API uses USD per million tokens.
  const pricedRequest = { ...request, provider: { ...request.provider, max_price: maxPrice } };
  const envelope = 4096; // fixed: conservative technical allowance for provider/schema/message framing, not a spending setting.
  const input = new TextEncoder().encode(JSON.stringify(pricedRequest)).length + envelope;
  const maximum = input * (maxPrice.prompt / 1e6 + (rates.input_cache_read || 0) + (rates.input_cache_write || 0))
    + output * (maxPrice.completion / 1e6 + (rates.internal_reasoning || 0)) + maxPrice.request;
  if (!Number.isFinite(maximum) || maximum < 0) return { ok: false, reason: "invalid_model_pricing" };
  return { ok: true, model, max_cost_usd: Math.ceil(maximum * precision) / precision, input_tokens_bound: input, output_tokens_bound: output, pricing: rates, provider_max_price: maxPrice };
}

// v0.60.0 (10 Nov 2026, CF-247 F-PDESC delivery): 94 reads, 2 admitted. The model copied its quote into the sentence (verbatim_passage, 51 holds) or added a point the quote does not state
// (unsupported_sentence, unsupported_claim, 17 holds), and one such sentence held a proposal whose other sentences were fully supported. The prompt now asks for one short paraphrase per
// quote, in the quote's own key words, with nothing added; the database (security.provider_description_validate_v1, drop_failing) leaves a sentence out that still fails and keeps the rest.
export const DESCRIPTION_SYSTEM =
  "You write a short description of one university or education provider for prospective students, using only what the provider's own official page states. " +
  "Give 2 to 5 sentences. Each sentence is one short, plain, factual paraphrase of one passage of the page, and for each sentence you give that passage's exact words as its quote, copied character for character from the page text. " +
  "The quote is the shortest exact passage (one clause or one sentence) that states the point, and one quote supports one sentence only: never join two passages in one sentence. " +
  "Write the sentence in your own words and make it shorter than its quote: keep the quote's key nouns and verbs, leave out its extra clauses, and never copy a long run of the quote word for word. " +
  "Say only what the quote states. Add no aim, mission, motive, value or benefit that is not in it (for example dedicated to, committed to, aims to, so that students thrive). If a point needs more than the quote says, leave the point out: fewer sentences that the quotes fully support are better than one sentence that goes beyond its quote. " +
  "Do not state rankings, ratings, awards, facilities, employment or graduate outcomes, accreditations, student or staff numbers, or comparisons with other institutions unless the quoted words state them. " +
  "Do not use superlatives or marketing words (best, leading, world-class, top, renowned, prestigious, excellent) unless they are inside the quote. " +
  "Do not use anything you know about the provider from elsewhere. Write in Australian English, third person, present tense. " +
  "Set about_page to false and give no sentences when the page does not describe the institution itself (what it is, where it is, what it teaches, its history).";

export const DESCRIPTION_SCHEMA = {
  type: "object", additionalProperties: false, required: ["about_page", "sentences"],
  properties: {
    about_page: { type: "boolean" },
    sentences: { type: "array", items: { type: "object", additionalProperties: false, required: ["text", "quote"], properties: { text: { type: "string" }, quote: { type: "string" } } } },
  },
} as const;

// v0.69.0 (11 Nov 2026, CF-247 F-PDESC, Platform Admin 14:51/14:57: "prompt based ... easily modified rather than stringent rules"): the prompt is
// kept in the database (pipeline.provider_description_prompts, edited on Models & services › AI & OpenRouter) and handed over by the lease as
// w.prompt { version, system }. A sentence may draw on several passages of the page; every passage must stand on the page. The database
// (security.provider_description_validate_v1, prompt profile) keeps the checks a machine applies reliably. Without w.prompt the built-in
// prompt v2 below is used, exactly as before.
export const PROMPT_SCHEMA = {
  type: "object", additionalProperties: false, required: ["sentences", "reason"],
  properties: {
    sentences: { type: "array", items: { type: "object", additionalProperties: false, required: ["text", "sources"], properties: { text: { type: "string" }, sources: { type: "array", items: { type: "string" } } } } },
    reason: { type: "string" },
  },
} as const;
export function promptRequest(model: string, system: string, provider: string, url: string, page: string, maxTokens: number, length?: DescriptionLength) {
  return {
    model, temperature: 0, max_tokens: maxTokens, provider: { require_parameters: true },  // pinned: one model, never a router
    response_format: { type: "json_schema", json_schema: { name: "provider_description_prompt", strict: true, schema: PROMPT_SCHEMA } },
    messages: [{ role: "system", content: system }, { role: "user", content: `Provider: ${provider}\nPage: ${url}\n${lengthNote(length)}\nPage text:\n${page}` }],
  };
}
// each sentence keeps its passages joined (" … ") as its quote; on_page only when every passage stands on the page (each proven on its own)
// v0.69.1 (11 Nov 2026, CF-247 F-PDESC, first hour of prompt-based reads: about one AI answer in ten held as quote_not_on_page with a
// passage the page does carry): the page text is built by turning every tag into a space, so a link or bold word inside a sentence reads
// "IT , engineering" or "( CHT )" here while the model copies "IT, engineering"; pages also mix curly and straight quotes and dash shapes.
// For the prompt's passages only, both sides are compared in one canonical form: compatibility Unicode (NFKC), curly quotes as straight,
// dashes as "-", no space before , . ; : ! ? ) % or after ( $, and single spaces. Letters, digits, decimal points, signs and percentages
// stay evidence exactly as before: "1.2%" never proves "12%". The built-in prompt v2 path (providerDescriptionSentences) is unchanged.
export const passageCanonical = (s: string): string => String(s || "").normalize("NFKC")
  .replace(/[\u2018\u2019\u201A\u201B\u2032\u00B4`]/g, "'").replace(/[\u201C\u201D\u201E\u201F\u2033]/g, '"')
  .replace(/[\u2010-\u2015\u2212]/g, "-").replace(/\s+/g, " ")
  .replace(/ ([,.;:!?)\]%])/g, "$1").replace(/([(\[$]) /g, "$1").trim();
export function promptSentences(a: any, page: string, minQuoteChars = 20): { about_page: boolean; reason: string; sentences: { text: string; quote: string; on_page: boolean; sources: number }[] } {
  const cp = passageCanonical(page);
  const out = (Array.isArray(a?.sentences) ? a.sentences : []).map((s: any) => {
    const sources: string[] = (Array.isArray(s?.sources) ? s.sources : []).map((x: unknown) => String(x || "").trim()).filter(Boolean);
    const proven = sources.length > 0 && sources.every((q) => { const cq = passageCanonical(q); return providerDescriptionSentences({ about_page: true, sentences: [{ text: cq, quote: cq }] }, cp, minQuoteChars).sentences[0]?.on_page === true });
    return { text: String(s?.text || "").trim(), quote: sources.join(" … "), on_page: proven, sources: sources.length };
  }).filter((s: any) => s.text);
  return { about_page: out.length > 0, reason: String(a?.reason || "").slice(0, 300), sentences: out };
}

export type DescriptionLength = { min_sentences?: number; max_sentences?: number; min_chars?: number; max_chars?: number };
// the limits the database validation applies (settings pdesc.min_sentences, max_sentences, min_chars, max_chars), stated to the model
export function lengthNote(l: DescriptionLength | null | undefined): string {
  const n = (x: unknown) => (Number.isFinite(Number(x)) && Number(x) > 0 ? Math.floor(Number(x)) : null);
  const s1 = n(l?.min_sentences), s2 = n(l?.max_sentences), c1 = n(l?.min_chars), c2 = n(l?.max_chars);
  if (!s2 && !c2) return "";
  return `Length: ${s1 && s2 ? `${s1} to ${s2} sentences` : s2 ? `at most ${s2} sentences` : ""}${s2 && c2 ? ", " : ""}${c1 && c2 ? `${c1} to ${c2} characters in all (the sentences, not the quotes)` : c2 ? `at most ${c2} characters in all` : ""}.\n`;
}
// the copy limit the database applies (setting pdesc.verbatim_span_max_chars, sent by the lease as verbatim_span_max_chars), stated to the model
export function copyNote(maxVerbatimChars: number | null | undefined): string {
  const n = Number.isInteger(Number(maxVerbatimChars)) && Number(maxVerbatimChars) > 0 ? Number(maxVerbatimChars) : null;
  return n ? `Copy limit: keep each sentence short (under ${n} characters) and never repeat ${n} or more characters in a row from its quote.\n` : "";
}
export function descriptionRequest(model: string, provider: string, url: string, page: string, maxTokens: number, length?: DescriptionLength, maxVerbatimChars?: number) {
  return {
    model, temperature: 0, max_tokens: maxTokens, provider: { require_parameters: true },  // pinned: one model, never a router
    response_format: { type: "json_schema", json_schema: { name: "provider_description", strict: true, schema: DESCRIPTION_SCHEMA } },
    messages: [{ role: "system", content: DESCRIPTION_SYSTEM }, { role: "user", content: `Provider: ${provider}\nPage: ${url}\n${lengthNote(length)}${copyNote(maxVerbatimChars)}\nPage text:\n${page}` }],
  };
}

// every sentence keeps its quote and whether the quote is on the page (at least minQuoteChars letters and digits, found in the page text)
// Shared with the course-description reader (course-text.ts); its matching is unchanged by the provider-description source guard.
export function descriptionSentences(a: any, page: string, minQuoteChars = 20): { about_page: boolean; sentences: { text: string; quote: string; on_page: boolean }[] } {
  const fp = flatText(page);
  // v0.58.0 (Platform Admin 2 Nov 2026 23:24, "avoid cutting essential conditions or publishing fragments"): nothing is cut here. Every
  // sentence and quote is kept whole and every sentence the model gave is passed on; the database holds a description that is too long,
  // has too many sentences or a sentence that is not complete (rules length, sentence_count, incomplete_sentence). It was cut at 600
  // characters and 12 sentences.
  const sentences = ((a?.sentences || []) as any[]).map((s) => {
    const text = String(s?.text || "").replace(/\s+/g, " ").trim(), quote = String(s?.quote || "").replace(/\s+/g, " ").trim();
    const fq = flatText(quote);
    return { text, quote, on_page: fq.length >= minQuoteChars && fp.includes(fq) };
  }).filter((s) => s.text);
  return { about_page: a?.about_page === true, sentences };
}

// v0.59.14 (9 Nov 2026, CF-247 F-PDESC, Platform Admin Directive 3): a quote the model joined from separate passages of the page with an
// ellipsis ("..", "..." or the single character) is proven fragment by fragment, but only when the switch reading.provider_quote_fragments_on
// is on (ships off) and the whole quote is not on the page. Each fragment must be on the page exactly as the whole quote is (same boundary
// rule, same canonical form), be at least pdesc.min_quote_chars letters and digits long, and follow the one before it in the page's order;
// at least two fragments are required. One fragment missing, too short, out of order or only partly a word fails the whole quote
// (quote_not_on_page, as before). The quote is passed on whole, with the ellipsis; the database checks are unchanged.
const QUOTE_ELLIPSIS = /\s*(?:\.{2,}|\u2026)\s*/;
export const providerQuoteFragments = (q: string): string[] => String(q || "").split(QUOTE_ELLIPSIS).map((x) => x.trim()).filter((x) => flatText(x).length > 0);

// Provider descriptions only (provider-description-source-guard-v1): the quote must be on the page exactly.
// Only canonical Unicode form and layout whitespace may differ. Punctuation, decimal points,
// signs, percentages, words and case remain evidence: "1.2%" must never prove "12%".
export function providerDescriptionSentences(a: any, page: string, minQuoteChars = 20, opts: { fragments?: boolean } = {}): { about_page: boolean; sentences: { text: string; quote: string; on_page: boolean; fragments?: number }[] } {
  const sourceText = (value: string) => String(value || "").normalize("NFC").replace(/\s+/g, " ").trim();
  const fp = sourceText(page);
  // the end of the first place the quote stands on the page at or after `from` (-1: nowhere); the boundary rules are those of the whole quote
  const placeOnPage = (quote: string, from = 0): number => {
    const needle = sourceText(quote), ends = Array.from(needle), first = ends[0] || "", last = ends[ends.length - 1] || "";
    const word = (c: string) => /[\p{L}\p{N}_]/u.test(c);
    const numeric = (c: string) => /[0-9.,+\-$€£%]/u.test(c);
    for (let at = fp.indexOf(needle, from); at >= 0 && needle; at = fp.indexOf(needle, at + 1)) {
      const before = Array.from(fp.slice(0, at)).at(-1) || "", after = Array.from(fp.slice(at + needle.length))[0] || "";
      if (word(first) && word(before) || word(last) && word(after)) continue;
      if (numeric(first) && numeric(before) || numeric(last) && numeric(after)) continue;
      return at + needle.length;
    }
    return -1;
  };
  const onPage = (quote: string) => placeOnPage(quote) >= 0;
  // the number of fragments proven in the page's order (0: not proven)
  const provedFragments = (quote: string): number => {
    const frags = providerQuoteFragments(quote);
    if (frags.length < 2) return 0;  // fixed: a joined quote has at least two passages, by definition
    let from = 0;
    for (const f of frags) {
      if (flatText(f).length < minQuoteChars) return 0;
      const end = placeOnPage(f, from);
      if (end < 0) return 0;
      from = end;
    }
    return frags.length;
  };
  // As descriptionSentences: nothing is cut; every sentence and its whole quote is passed on for the database checks.
  const sentences = (Array.isArray(a?.sentences) ? a.sentences : []).map((s: any) => {
    const text = String(s?.text || "").replace(/\s+/g, " ").trim(), quote = String(s?.quote || "");
    const fq = flatText(quote);
    if (fq.length >= minQuoteChars && onPage(quote)) return { text, quote, on_page: true };
    const n = opts.fragments === true && fq.length >= minQuoteChars ? provedFragments(quote) : 0;
    return n > 1 ? { text, quote, on_page: true, fragments: n } : { text, quote, on_page: false };
  }).filter((s: any) => s.text);
  return { about_page: a?.about_page === true, sentences };
}

// the setting that limits the answer (pipeline toolset, read through svc_worker_settings_v1 like every reading.answer_tokens.* limit)
export const DESCRIPTION_ANSWER_KEY = "reading.answer_tokens.provider_description";

// one answer as OpenRouter returns it, read by the same rules as answer.ts readAnswer (W32): a cut answer is never parsed and is held
// (held_partial: output_truncated), an empty or unreadable answer fails, named; the cost is always kept
export function descriptionAnswer(d: any, maxTokens: number): { ok: true; a: any; cost: number } | { ok: false; error: string; cost: number } {
  const cost = callCost(d), ch = d?.choices?.[0] || {}, content = String(ch?.message?.content ?? ""), out = Number(d?.usage?.completion_tokens);
  const cut = (why: string) => ({ ok: false as const, cost, error: `held_partial: output_truncated: provider_description ${why} ${DESCRIPTION_ANSWER_KEY} (${maxTokens})` });
  if (ch?.finish_reason === "length") return cut("reached");
  if (!content.trim()) return { ok: false, cost, error: `no_answer: provider_description (${String(ch?.error?.message || d?.error?.message || ch?.finish_reason || "no choices").slice(0, 120)})` };
  try { return { ok: true, a: JSON.parse(content), cost } }
  catch (e) {
    if (Number.isFinite(out) && maxTokens > 0 && out >= maxTokens) return cut("used all of");
    return { ok: false, cost, error: `unreadable_answer: provider_description (${e instanceof Error ? e.message : String(e)})`.slice(0, 300) };
  }
}
