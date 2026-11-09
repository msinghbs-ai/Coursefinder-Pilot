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
export function descriptionIdentityLabels(names: string[]): string[] {
  const institution = /\b(university|college|polytechnic|institute)\b/i;
  const out: string[] = [];
  for (const raw of names || []) {
    const name = String(raw || "").replace(/\s+/g, " ").trim();
    if (!name) continue;
    out.push(name);
    // 1 abbreviation-only parentheticals
    const bare = name.replace(/\s*\(([^()]*)\)/g, (whole, inner) => inOrder(String(inner), name.replace(/\([^()]*\)/g, "")) ? "" : whole).replace(/\s+/g, " ").replace(/\s+([,;])/g, "$1").trim();
    if (bare && bare !== name) out.push(bare);
    // 2 the first entity of a list
    for (const candidate of [name, bare]) {
      if (!/[;,]/.test(candidate)) continue;
      const first = candidate.split(/[;,]/)[0].trim();
      if (first.split(/\s+/).length >= 2 && institution.test(first)) out.push(first);
    }
  }
  return out;
}

export type DescriptionIdentity = { ok: boolean; rule: string; matched_name?: string; via?: string };
function strictSourceIdentity(html: string, page: string, names: string[]): DescriptionIdentity {
  const words = (s: string) => String(s || "").normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
    .replace(/&/g, " and ").replace(/[^a-z0-9]+/g, " ").replace(/^the\s+/, "").trim();
  const labels = [...new Set(descriptionIdentityLabels(names || []).map(words).filter((s) => s.split(" ").length > 1))];
  const contains = (text: string, label: string) => (` ${words(text)} `).includes(` ${label} `);
  const headings = Array.from(String(html || "").matchAll(/<(title|h1)\b[^>]*>([\s\S]*?)<\/\1>/gi), (m) => ({ tag: m[1].toLowerCase(), text: htmlToText(m[2]) }));
  const matched = labels.find((name) => contains(page, name) || headings.some((h) => contains(h.text, name)));
  if (!matched) return { ok: false, rule: "provider_name_not_proved" };
  const subunits = /\b(campus|campuses|faculty|faculties|school|schools)\b/g;
  if (headings.some((h) => h.tag === "h1" && (words(h.text).match(subunits) || []).some((unit) => !(` ${matched} `).includes(` ${unit} `)))) {
    return { ok: false, rule: "provider_subunit_source" };
  }
  // A heading identifying a different university or college is stronger evidence of a conflict
  // than a passing mention of the requested name in the body (partnerships, history, offshore sites).
  const institutionalHeadings = headings.filter((h) => /\b(university|college|polytechnic|institute)\b/.test(words(h.text))
    && words(h.text).replace(/\b(about|us|the|our|who|we|are|overview|profile|welcome|to|at|university|college|polytechnic|institute)\b/g, "").trim());
  const subjectHeadings = institutionalHeadings.some((h) => h.tag === "h1") ? institutionalHeadings.filter((h) => h.tag === "h1") : institutionalHeadings;
  if (subjectHeadings.length && !subjectHeadings.some((h) => labels.some((name) => contains(h.text, name)))) {
    return { ok: false, rule: "provider_name_conflict" };
  }
  // An offshore branch can include its parent's complete name ("X University Malaysia").
  // A named institutional h1 must identify this catalogue institution without an extra entity suffix.
  // When h1 is generic, the institutional title must provide that same exact identity proof.
  const namedH1 = headings.filter((h) => h.tag === "h1" && labels.some((name) => contains(h.text, name)));
  const framing = /\b(about|us|the|our|who|we|are|overview|profile|welcome|to|at|a|glance|facts|and|figures)\b/g;
  const proofHeadings = namedH1.length ? namedH1 : headings.filter((h) => h.tag === "title");
  if (!proofHeadings.some((h) => labels.some((name) => contains(h.text, name) && !words(h.text).replace(name, " ").replace(framing, " ").trim()))) {
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
const IDENTITY_OTHER = /\b(university|college|polytechnic|institute|campus|campuses|faculty|faculties|school|schools)\b/;
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
    const first = plain.split(/[;,]/)[0].trim();
    if (/\b(university|college|polytechnic|institute)\b/i.test(first)) {
      const letters = first.split(/\s+/).filter((w, i) => !(i === 0 && /^the$/i.test(w))).filter((w) => /^[A-Z]/.test(w)).map((w) => w[0]).join("");
      if (letters.length >= 3) add(letters);  // fixed: shorter initialisms (UC, CC) are shared by too many institutions
    }
  }
  return out;
}

// the headings that identify the page's subject: the title, every h1, og:site_name, og:title and application-name
function identityHeadings(html: string): { tag: string; text: string }[] {
  const out = Array.from(String(html || "").matchAll(/<(title|h1)\b[^>]*>([\s\S]*?)<\/\1>/gi), (m) => ({ tag: m[1].toLowerCase(), text: htmlToText(m[2]) }));
  for (const m of String(html || "").matchAll(/<meta\b[^>]*>/gi)) {
    const key = (m[0].match(/\b(?:property|name)\s*=\s*["']([^"']+)["']/i) || [])[1]?.toLowerCase();
    if (key !== "og:site_name" && key !== "og:title" && key !== "application-name") continue;
    const c = m[0].match(/\bcontent\s*=\s*(?:"([^"]*)"|'([^']*)')/i);
    if (c) out.push({ tag: key, text: htmlToText(c[1] ?? c[2] ?? "") });
  }
  return out;
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

function registryEvidenceIdentity(html: string, names: string[]): DescriptionIdentity {
  const uniq = (xs: string[]) => [...new Set(xs.map(identityWords).filter(Boolean))];
  const labels = uniq(descriptionIdentityLabels(names || [])).filter((l) => l.split(" ").length > 1);
  const aliases = uniq(descriptionIdentityAliases(names || [])).filter((a) => !labels.includes(a));
  const phrases = [...labels, ...aliases].sort((a, b) => b.length - a.length);
  const has = (w: string, phrase: string) => (` ${w} `).includes(` ${phrase} `);
  const strip = (w: string, ps: string[]) => { let r = w; for (const p of ps) r = r.replace(new RegExp(`(?<=^| )${p}(?= |$)`, "g"), " "); return r.replace(/\s+/g, " ").trim() };
  const fail = (rule: string): DescriptionIdentity => ({ ok: false, rule });
  let proof: { name: string; via: string } | null = null, aboutHeading = false;
  for (const el of identityHeadings(html)) {
    for (const seg of el.text.split(/\s[-–—―]\s|[|:·•,;\/–—]/)) {
      const w = identityWords(seg);
      if (!w) continue;
      const label = labels.find((l) => has(w, l)), alias = aliases.find((a) => has(w, a));
      if (label || alias) {
        // the name or an abbreviation with extra words ("X University Malaysia", "UTS College") names something else
        const extra = strip(w, phrases).replace(IDENTITY_FRAMING, " ").replace(/\s+/g, " ").trim();
        if (extra) return fail(el.tag === "h1" && IDENTITY_SUBUNIT.test(extra) ? "provider_subunit_source" : "provider_name_conflict");
        if (label) { if (!proof || proof.via !== "registry_heading_name") proof = { name: label, via: "registry_heading_name" } }  // the whole name outranks an abbreviation
        else proof ||= { name: alias!, via: "registry_heading_abbreviation" };
        continue;
      }
      if (!w.replace(IDENTITY_FRAMING, " ").replace(IDENTITY_GENERIC, " ").trim()) { if (/\b(about|overview|profile|welcome|who)\b/.test(w)) aboutHeading = true; continue }  // a generic heading ("About us", "About the university")
      if (IDENTITY_OTHER.test(w)) return fail(el.tag === "h1" && IDENTITY_SUBUNIT.test(w) ? "provider_subunit_source" : "provider_name_conflict");  // another institution, college, faculty, school or campus
    }
  }
  if (proof) return { ok: true, rule: "current_provider_name", matched_name: proof.name, via: proof.via };
  // no heading names the provider and none names another, and a heading says this is an About page: the opening statement must begin with the whole catalogue name
  if (!aboutHeading) return fail("provider_name_not_proved");
  const para = openingParagraph(html), pw = identityWords(para);
  const label = labels.find((l) => pw === l || pw.startsWith(l + " "));
  if (label) {
    const sentence = para.split(/(?<=[.!?])\s/)[0];
    const elsewhere = /\b(?:[A-Z][\w'’-]*\s+){1,5}(?:University|College|Polytechnic|Institute|School)\b|\b(?:University|College|Institute|School)\s+of\s+[A-Z]/;
    const rest = sentence.replace(new RegExp(label.split(" ").join("[\\s\\W]+"), "ig"), " ");
    if (!elsewhere.test(rest) && !IDENTITY_SUBUNIT.test(identityWords(rest))) return { ok: true, rule: "current_provider_name", matched_name: label, via: "registry_opening_statement" };
  }
  return fail("provider_name_not_proved");
}

// The identity proof the reader applies. `evidence` is what the database gave the worker: the page's final address and the provider's own verified
// hosts. Without it, or when the page is not on one of those hosts, only the strict proof applies, exactly as before.
export function descriptionSourceIdentity(html: string, page: string, names: string[], evidence?: { url?: string; hosts?: string[] }): DescriptionIdentity {
  const strict = strictSourceIdentity(html, page, names);
  if (strict.ok || strict.rule === "provider_subunit_source" || !evidence) return strict;
  let host = "";
  try { host = new URL(String(evidence.url || "")).hostname } catch { return strict }
  if (!/^https?:$/.test(new URL(String(evidence.url)).protocol) || !ownHost(host, evidence.hosts || [])) return strict;
  const registry = registryEvidenceIdentity(html, names);
  return registry.ok || registry.rule === "provider_subunit_source" ? registry : strict;
}

// The lease protocol this worker follows: reserve a conservative price with svc_provider_description_reserve_v1 before every paid call.
export const DESCRIPTION_WORKER_PROTOCOL = "provider-description-reserve-v1";

// Worker-side check: only long copied official passages. Numbers and historic context are decided once, evidence-aware, by
// security.provider_description_validate_v1 (validation 5 Nov 2026, decision 20:03 §2: no keyword- or format-only rejection).
// Keep the whole answer and quotes; hold it rather than rewriting any sentence to make it pass.
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

export const DESCRIPTION_SYSTEM =
  "You write a short description of one university or education provider for prospective students, using only what the provider's own official page states. " +
  "Give 2 to 5 sentences. Each sentence is a plain, factual paraphrase of one passage of the page, and for each sentence you give that passage's exact words as its quote, copied character for character from the page text. " +
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

export type DescriptionLength = { min_sentences?: number; max_sentences?: number; min_chars?: number; max_chars?: number };
// the limits the database validation applies (settings pdesc.min_sentences, max_sentences, min_chars, max_chars), stated to the model
export function lengthNote(l: DescriptionLength | null | undefined): string {
  const n = (x: unknown) => (Number.isFinite(Number(x)) && Number(x) > 0 ? Math.floor(Number(x)) : null);
  const s1 = n(l?.min_sentences), s2 = n(l?.max_sentences), c1 = n(l?.min_chars), c2 = n(l?.max_chars);
  if (!s2 && !c2) return "";
  return `Length: ${s1 && s2 ? `${s1} to ${s2} sentences` : s2 ? `at most ${s2} sentences` : ""}${s2 && c2 ? ", " : ""}${c1 && c2 ? `${c1} to ${c2} characters in all (the sentences, not the quotes)` : c2 ? `at most ${c2} characters in all` : ""}.\n`;
}
export function descriptionRequest(model: string, provider: string, url: string, page: string, maxTokens: number, length?: DescriptionLength) {
  return {
    model, temperature: 0, max_tokens: maxTokens, provider: { require_parameters: true },  // pinned: one model, never a router
    response_format: { type: "json_schema", json_schema: { name: "provider_description", strict: true, schema: DESCRIPTION_SCHEMA } },
    messages: [{ role: "system", content: DESCRIPTION_SYSTEM }, { role: "user", content: `Provider: ${provider}\nPage: ${url}\n${lengthNote(length)}\nPage text:\n${page}` }],
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

// Provider descriptions only (provider-description-source-guard-v1): the quote must be on the page exactly.
// Only canonical Unicode form and layout whitespace may differ. Punctuation, decimal points,
// signs, percentages, words and case remain evidence: "1.2%" must never prove "12%".
export function providerDescriptionSentences(a: any, page: string, minQuoteChars = 20): { about_page: boolean; sentences: { text: string; quote: string; on_page: boolean }[] } {
  const sourceText = (value: string) => String(value || "").normalize("NFC").replace(/\s+/g, " ").trim();
  const fp = sourceText(page);
  const onPage = (quote: string) => {
    const needle = sourceText(quote), ends = Array.from(needle), first = ends[0] || "", last = ends[ends.length - 1] || "";
    const word = (c: string) => /[\p{L}\p{N}_]/u.test(c);
    const numeric = (c: string) => /[0-9.,+\-$€£%]/u.test(c);
    for (let at = fp.indexOf(needle); at >= 0 && needle; at = fp.indexOf(needle, at + 1)) {
      const before = Array.from(fp.slice(0, at)).at(-1) || "", after = Array.from(fp.slice(at + needle.length))[0] || "";
      if (word(first) && word(before) || word(last) && word(after)) continue;
      if (numeric(first) && numeric(before) || numeric(last) && numeric(after)) continue;
      return true;
    }
    return false;
  };
  // As descriptionSentences: nothing is cut; every sentence and its whole quote is passed on for the database checks.
  const sentences = (Array.isArray(a?.sentences) ? a.sentences : []).map((s: any) => {
    const text = String(s?.text || "").replace(/\s+/g, " ").trim(), quote = String(s?.quote || "");
    const fq = flatText(quote);
    return { text, quote, on_page: fq.length >= minQuoteChars && onPage(quote) };
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
