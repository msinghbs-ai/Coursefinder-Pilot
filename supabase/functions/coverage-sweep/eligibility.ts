// v0.75.0 (12 Nov 2026, CF-247 F-SCH.01 scholarship eligibility reader). 2,226 scholarship pages were refused only because the first read found no
// sentence saying international students may apply (1,870 of them had no eligibility text captured at all), and every one of them was handed to a
// person in Layer 4 (lane capped at 150) without a second read. The eligibility reader reads the stored page again with the narrow re-check
// question (who may apply, with the exact sentence; index.ts scholarshipRecheckRequest / judgeScholarshipRecheck) and, when the page itself is
// silent, at most `links_max` pages the scholarship page links to for its eligibility or terms on the same site. A sentence counts only when it
// is on the page it was read from and names international (or domestic) students in words. The database decides what to do with the answer
// (security.scholarship_eligibility_apply_v1: shadow until sch_elig.apply_on); nothing is admitted, published or decided here.
// Pure functions only (no network): tests/uat/cf-247-f-sch-01-eligibility-reader-contract.spec.mjs runs them.

// words that mark a link to a scholarship's eligibility or conditions (anchor text or address)
export const ELIGIBILITY_LINK_TEXT = /\b(eligib\w*|terms|conditions|criteria|who can apply|who may apply|how to apply|selection|rules)\b/i;
export const ELIGIBILITY_LINK_PATH = /(eligib|terms|condition|criteria|how-to-apply|who-can-apply|rules)/i;
// addresses never followed: files the reader does not read as pages, and actions
const SKIP_PATH = /\.(pdf|docx?|xlsx?|pptx?|zip|jpe?g|png|gif|svg|mp4)([?#].*)?$/i;
const SKIP_SCHEME = /^(mailto|tel|javascript|data):/i;
// second-level labels under which a site's own name is the third label from the right (unisa.edu.au, auckland.ac.nz, ox.ac.uk)
const SECOND_LEVEL = new Set(["com", "edu", "ac", "org", "net", "gov", "govt", "co", "school", "nz", "id", "asn"]);

// the registrable part of a host name: the site a page belongs to
export function siteOf(host: string) {
  const labels = String(host || "").toLowerCase().replace(/^www\./, "").split(".").filter(Boolean);
  if (labels.length <= 2) return labels.join(".");
  const n = SECOND_LEVEL.has(labels[labels.length - 2]) ? 3 : 2;
  return labels.slice(-n).join(".");
}

const decode = (s: string) => s.replace(/&amp;/g, "&").replace(/&#x2F;/gi, "/").replace(/&#47;/g, "/").replace(/&quot;/g, '"');
const textOf = (s: string) => decode(s.replace(/<[^>]+>/g, " ")).replace(/\s+/g, " ").trim();
const norm = (u: URL) => `${u.protocol}//${u.host.toLowerCase()}${u.pathname.replace(/\/+$/, "")}${u.search}`;

// The links of a scholarship page that point to its eligibility or conditions on the same site, best first: at most `max`, never the page itself,
// never a file or another site. Anchor words weigh more than address words; ties keep the page's order.
export function eligibilityLinks(html: string, pageUrl: string, max = 1): string[] {
  let base: URL;
  try { base = new URL(pageUrl) } catch { return [] }
  if (!(max > 0)) return [];
  const site = siteOf(base.hostname), self = norm(base);
  const seen = new Set<string>(), found: { url: string; score: number; at: number }[] = [];
  const re = /<a\b[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>([\s\S]*?)<\/a>/gi;
  let m: RegExpExecArray | null, at = 0;
  while ((m = re.exec(String(html || "")))) {
    const href = decode((m[1] ?? m[2] ?? m[3] ?? "").trim());
    if (!href || href.startsWith("#") || SKIP_SCHEME.test(href)) continue;
    let u: URL;
    try { u = new URL(href, base) } catch { continue }
    if (!/^https?:$/.test(u.protocol) || SKIP_PATH.test(u.pathname)) continue;
    if (siteOf(u.hostname) !== site) continue;
    u.hash = "";
    const key = norm(u);
    if (key === self || seen.has(key)) continue;
    const words = textOf(m[4] || "") + " " + textOf((m[0].match(/\b(?:title|aria-label)\s*=\s*"([^"]*)"/i) || [])[1] || "");
    const score = (ELIGIBILITY_LINK_TEXT.test(words) ? 2 : 0) + (ELIGIBILITY_LINK_PATH.test(u.pathname) ? 1 : 0);
    if (score === 0) continue;
    seen.add(key);
    found.push({ url: u.toString(), score, at: at++ });
  }
  return found.sort((a, b) => b.score - a.score || a.at - b.at).slice(0, max).map((x) => x.url);
}

// The re-check request asked of a linked page: the same question and schema, told which scholarship it is about and where the link came from,
// so a page about other scholarships answers not_stated.
export function linkedPageNote(req: any, scholarshipName: string, fromUrl: string) {
  const out = structuredClone(req);
  const msg = out?.messages?.[1];
  if (msg && typeof msg.content === "string") {
    msg.content = `This page is linked from the page of the scholarship "${scholarshipName || "(named on that page)"}" (${fromUrl}) as its eligibility or conditions. ` +
      `Answer only for that scholarship, or for all of the university's scholarships when the page says so. If the page is about other scholarships, answer "not_stated".\n\n` + msg.content;
  }
  return out;
}

// what the reader records for one scholarship page: proven (with where the sentence is), silent (no sentence on the page or the pages it links to),
// or unread (the page could not be read); the database acts on it
export type EligibilityOutcome = "proven" | "silent" | "unread";
export function eligibilityOutcome(first: any | null, linked: { url: string; status: string; judged?: any }[]): { outcome: EligibilityOutcome; source: "page" | "linked" | null; judged: any | null; source_url: string | null } {
  if (!first) return { outcome: "unread", source: null, judged: null, source_url: null };
  if (first.audience_proven) return { outcome: "proven", source: "page", judged: first, source_url: null };
  const hit = linked.find((l) => l.status === "read" && l.judged?.audience_proven);
  if (hit) return { outcome: "proven", source: "linked", judged: hit.judged, source_url: hit.url };
  return { outcome: "silent", source: null, judged: first, source_url: null };
}

// v0.76.0 (12 Nov 2026, F-SCH.01 shadow review): the re-check proof accepts any quote holding the word "international"; in the first 200 shadow reads 2 of
// 5 international proofs were a course name ("Master of International Business", "an international business honours program"). For acting on a reader
// answer, "international" must describe who may apply: international students or applicants, the "(international)" eligibility tag, domestic and
// international, overseas students, a student visa, non-residents. A domestic proof is unchanged.
export const INTL_APPLICANT = /\binternational\s+(?:students?|applicants?|candidates?|scholars?|offer[- ]holders?|learners?)\b|\(\s*international\s*\)|\b(?:domestic|local|australian|new zealand|canadian)\s+(?:students?\s+)?(?:and|or|&)\s+international\b|\boverseas\s+(?:students?|applicants?)\b|\bstudents?\s+from\s+overseas\b|\bstudent\s+visa\b|\bsubclass\s+500\b|\bnon[- ]?residents?\b/i;
// v0.78.0 (12 Nov 2026, F-SCH.01 post-activation review): the first live run acted on sentences that name international students without saying
// that THIS scholarship is open to them: a course title with "(International)" (UTS), the site-wide scholarship banner (Bond: "a broad offering
// for both domestic and international applicants, our scholarship program ..."), a fee or deposit instruction (UNBC, NZQA) and a navigation tag
// ("Prospective students (international)", on 75 Sydney pages). A proof now also needs, after course titles are taken out: an eligibility cue
// (eligible, open to, available to, must be, applicants, student type, citizenship ...), no programme-wide wording, no search control, and, for a sentence about paying
// or entering, an eligibility word. Fail closed: a sentence that does not meet these is "international not stated", never "domestic".
export const COURSE_TITLE_INTL = /\b(?:master|bachelor|doctor|graduate certificate|graduate diploma|diploma|advanced diploma|associate degree|certificate [ivx]+)\s+(?:of|in)\s+[^().;]{2,80}?\s*\(\s*international\s*\)/gi;
export const ELIGIBILITY_CUE = /\b(?:eligib\w*|open to|available (?:to|for)|must (?:be|hold|have)|applicants?|who (?:can|may) apply|may apply|can apply|student type|citizenship|residency|residents?|only for|is for|are for|offered to|awarded to|you are an?|be an?|be classified|commencing|applying|enrol(?:led|ling)? as|as an? (?:international|overseas))\b/i;
export const PROGRAMME_WIDE = /\b(?:our scholarships?(?: program(?:me)?)?|most scholarships|a broad offering|range of scholarships|all (?:of )?our scholarships|scholarships? (?:program|programme) rewards)\b/i;
const FORM_CONTROL = /(?:\*\s*)?\bselect\s*(?:\.\.\.|…)|\bplease select\b|\bfilter by\b/i;
const PAY_OR_ENTER = /\b(?:pay|paid|payment|deposit|to enter|entry)\b/i;
const PAY_ELIGIBILITY = /\b(?:eligib\w*|open to|available (?:to|for)|applicants?|may apply|can apply)\b/i;
export function eligibilityProof(judged: any) {
  if (!judged?.audience_proven || judged.audience === "domestic") return judged;
  const q = String(judged.audience_quote || "").replace(COURSE_TITLE_INTL, " ");
  const down = (proof: string, why: string) => ({ ...judged, audience_proven: false, recommendation: "audience_not_stated", proof, why });
  if (FORM_CONTROL.test(q)) return down("form_control", "The words are a search or filter control on the page, not who may apply.");
  if (!INTL_APPLICANT.test(q)) return down("international_not_applicant", "The sentence holds the word international but not as who may apply (for example a course name).");
  if (PROGRAMME_WIDE.test(q)) return down("programme_wide", "The sentence describes the provider's scholarship programme as a whole, not this scholarship.");
  if (PAY_OR_ENTER.test(q) && !PAY_ELIGIBILITY.test(q)) return down("payment_instruction", "The sentence is about paying or entering, not about who may apply.");
  if (!ELIGIBILITY_CUE.test(q)) return down("no_eligibility_cue", "The words name international students without saying who may apply (for example a menu item).");
  return judged;
}
