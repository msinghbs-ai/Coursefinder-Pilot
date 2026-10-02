import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { currencyFor, english, fee, h1Of, htmlToText, identity, intakeEvidence, intakes, keepUrl, robotsAllows, siteNameMatch, staleCalendarUrl, titleOf } from "./extract.ts";
import { calendarStarts, englishPolicy, POLICY_PARSER } from "./policy.ts";
import { PAGE_ID_CONTRACT, pageIdChecks, pageIdInput, pageIdRequest } from "./pageid.ts";
import { admissionCheck, awardScope, baseHost, keepScholarshipUrl, onSite, mainText, matchScholarshipPage, nameOnPage, normUrl, pageHeadings, providerTokens, scholarshipCriteria, scholarshipFacts } from "./scholarship.ts";
const SCH_VERSION = "scholarship-sweep-v0.5.4";
// v0.5.4 (2 Oct 2026, Decision 212 check): a listed value ("Residency Australian Citizen, New Zealand Citizen, International
// Student") includes international students.
// v0.5.3: "Overseas students are eligible to apply" includes international students.
// v0.5.2 (2 Oct 2026, second hand-check, 14 domestic-only readings): "... New Zealand citizen or International student" and
// "both domestic (...) and international students" include international students.
// v0.5.1 (2 Oct 2026, first 30 hand-checked): the eligibility section ends at the next part of the page (how to apply,
// related scholarships); "key details" lines only as label + values; international as a stated requirement, not a menu
// link; "not eligible ... if you: are an Australian citizen" read as an exclusion.
// v0.5.0 (2 Oct 2026, Decision 211): eligibility criteria (student type, study stage, full-time, ATAR/GPA/WAM minimum,
// gender, nationality, applying without an application) and award scope (one-off, first year, per year, per year for the
// course, whole course; what it pays for) are read from the eligibility and benefit wording.
// v0.4.6 (step-2 hand-check): amounts in another currency (Swinburne "$5,000 USD") or stated as a maximum ("up to
// A$7,496", "up to AUD$20,000") are not a single AUD value; the eligibility section is a heading-like "Eligibility"
// (not "eligible countries") and when it states no level the page start is used.
// v0.4.5 (step-2 hand-check): an admitted title must be a scholarship's own name - ending with the scholarship word or a
// qualifier; page furniture, student stories, recaps, application forms and generic plural titles are not admitted.
// v0.4.4 (step-2 hand-check): articles, information pages and faculty listings are not single scholarships; links held
// as escaped HTML count as listing links; a re-read of an admitted page checks the admission rules again (a page that
// no longer meets them is withdrawn by the database, never published).
// v0.4.3 (step-1 hand-check): conditions about other scholarships covering full tuition are not the value; "up to N%"
// is a maximum (not applied); "Value $N" is a stated amount; stipend amounts kept; one amount in the scholarship's name
// that the page states is the value; a discovered page must be about a scholarship (UWA research-project page) and a
// web-search match must be a scholarship address or title.
// v0.4.2 (hand-check of the first admitted pages): full tuition is a single value only when no other percentage is
// stated; levels ignore excluded levels ("excluding Master by Research or PhD") and earlier study ("completed an
// undergraduate degree").
// v0.4.1: listing pages counted from the page content only (menus and side panels removed); supporting pages
// (terms and conditions, FAQs, how to apply, recipients, news) are not scholarships.
// v0.4.0 (scholarship discovery): the reader confirms the page names the scholarship (title, og:title, <h1>, or the whole
// name in one of the first <h2>s) before anything is applied - otherwise read_status "name_mismatch"; Firecrawl for
// scholarship work is capped at 3,000 credits (purposes sch_map, sch_search, sch_scrape).
const SCH_FC_CAP = 3000;

// CF-247 complete coverage sweep (Platform Admin direction 29 Sep 2026). Nonce-only. Nothing is written to the
// catalogue: discovery lists a provider's course-like pages, reading keeps each bound course page as evidence and
// records tuition, English and intake candidates for a separately approved admission rule.
//   mode discover: Firecrawl map per provider website (1 credit per call), inside the monthly budget guard.
//   mode read:     direct fetch (robots.txt respected); Firecrawl scrape only when the site refuses or the page is
//                  script-only, inside the budget guard; identity = CRICOS course code on the page or exact title.
const VERSION = "coverage-sweep-v0.5.6"; // extractor version (unchanged by v0.6.0 worker modes)
const WORKER = "coverage-sweep-worker-v0.13.0";
// v0.10.1 (2 Oct 2026, 22:11 direction): modes openrouter_key, reference_capture (Hipo), site_hint_verify; univ.cc directory hints.
// v0.10.0 (2 Oct 2026): mode ai_match, the map-first link matcher (a pinned model picks a course's page from its stored site map).
// v0.9.5 (2 Oct 2026, Decision 227): English policy and academic calendar documents are read and parsed (policy.ts,
// deterministic) into proposals a Platform Admin approves; modes provider_facts_inspect and provider_facts_parse work on
// the stored copies (no Firecrawl credit).
// v0.9.4 / extractor v0.5.6 (2 Oct 2026, Decision 224): amounts that are not tuition (bursaries, scholarships, loan caps,
// health cover, salaries, deposits, payment limits, other fees) are left out; in a "Session fee / Course fee" table the
// first amount is one session and the second the whole course.
// v0.9.3 / extractor v0.5.5 (2 Oct 2026, Decision 223): a fee's audience follows the page's own domestic or international
// view marker before it ("This content is for domestic students", "Local Student Fee"); course totals ("Total Indicative
// Course Fees", "Estimated total course cost") are totals; re-extraction reads each page in its country's currency.
// v0.9.2 (2 Oct 2026, Decision 220): Canada. find_site finds a Canadian provider's own site by name (search in Canada),
// accepted only on a .ca site whose home page names the provider or prints its DLI number; course pages are read in CAD
// and stored under layer2/CA/. A provider with no code to check is never accepted on an empty pattern.
// v0.9.1 (2 Oct 2026, Decision 217): New Zealand pages are proven by a labelled NZQA number or by the NZQA title with the
// same level ("title_level"), their fees are read in NZD, and they are stored under layer2/NZ/.
// v0.9.0 (Decision 211): mode scholarship_reextract adds eligibility criteria and award scope to stored scholarship pages.
// v0.8.0: mode scholarship_discover (provider scholarship pages from site maps, Firecrawl map/search fallbacks, matching
// held Study Australia-only scholarships, reading unheld pages at Australian universities for admission as new
// unpublished scholarships; Firecrawl only for pages the site refuses, keeping 800 credits for step 1) and mode scholarship_inspect (read only: stored or live page headings and text for hand checks).
// v0.5.2: discovery drops requirement, scholarship and applying pages (pilot: RMIT inherent-requirements pages).
// v0.5.1: PTE/TOEFL only when stated as overall or directly after the test name.
// v0.5.0: English overall only when stated as overall or in a score table; minimum band after the overall; fee basis
// total/annual from the amount's own wording ("(2027 total)", "total indicative fee"); mode reextract re-runs the
// extractor over stored pages read by an older version (no fetch).
// v0.4.0: mode find_site - providers with no website: web search (Firecrawl, 2 credits), accepted only when the
// home page prints the provider's CRICOS provider code; directories and registers skipped.
// v0.3.2: a script-only page read directly while the Firecrawl reserve is reached is "needs_render" (retried after the
// budget resets), never an identity mismatch.
// v0.6.3 (1 Oct 2026, Decision 179 CRUD): an official page entered by hand is trusted as the course's page (identity "manual").
// v0.6.2 (1 Oct 2026, course link recipes): a priority page read directly that does not show the course's CRICOS code
// is rendered once through Firecrawl before it is called an identity mismatch (script-rendered handbooks).
// v0.6.1 (30 Sep 2026, Platform Admin: maximum data for top universities): the Firecrawl fallback also covers ambiguous
// pages of the 100 largest providers (read_next marks them priority); identity is still the CRICOS code on the page.
// v0.3.1: Firecrawl fallback only for bound pages; ambiguous pages are read directly only (low yield).
// v0.3.0: ambiguous course pages are read too and accepted only with the CRICOS course code on the page; month
// names in intakes must be capitalised.
// v0.2.0: discovery reads the site's own XML site maps first (free), from the final address after redirects; Firecrawl
// map runs when the site maps give fewer course pages than 60% of the provider's courses, and a second map focused on
// "course" only when still short (at most 2 credits per provider). Binding runs separately (cron coverage-bind).
const UA = "Mozilla/5.0 (compatible; CourseFinder-Pilot/coverage-0.1; +https://coursefinder-pilot.techm.workers.dev)";
// Map-first link matcher (v0.10.0): one pinned model, structured output; it chooses a page, it never admits a value.
export const AI_MATCH_MODEL = "qwen/qwen3-30b-a3b-instruct-2507";
// third-party directories that may be captured as hints (Platform Admin 2 Oct 2026: Hotcourses for Canada and NZ)
const DIRECTORY_HOSTS: Record<string, string> = { hotcourses: "www.hotcoursesabroad.com", univcc: "univ.cc" };
// reference lists read as a whole file (Platform Admin 2 Oct 2026, 22:11); MIT-licensed
const REFERENCE_FILES: Record<string, string> = { hipo: "https://raw.githubusercontent.com/Hipo/university-domains-list/master/world_universities_and_domains.json" };
// AI page-identity candidates (qualification only), each pinned to one named model
const PAGE_ID_MODELS = ["qwen/qwen3-30b-a3b-instruct-2507", "anthropic/claude-haiku-4.5", "xiaomi/mimo-v2.6-pro", "moonshotai/kimi-k2-0905"];
// identity rule version used by mode reidentify (extract.ts identity(); v0.5.7 = national code before the title)
const IDENTITY_RULE = "identity-v0.5.12";
const AI_MATCH_PROFILE ="openrouter-intake-l3c-qwen3-30b-a3b-2507-v1"; // credential source only; its contract is not used here
export const AI_MATCH_SYSTEM = `You match a course from a government register to its own page on the education provider's website. You get the course (title, level, code) and a numbered list of candidate pages from the provider's site (address, and page title when known).
Pick the one page that is this course's own page: the page for this exact qualification at this level.
Do not pick: a list, search or faculty page; a subject-area page; a page for a different level, major, specialisation, campus-only variant or double degree; a page about entry requirements, fees, careers, news, events, research or applying.
A closely named qualification is a different course (for example "Bachelor of X (Honours)" when the course is "Bachelor of X", or "Bachelor of X/Bachelor of Y" when the course is "Bachelor of X"). A register title may add "(International)" or a short code in brackets; the provider's page may leave these out.
If no candidate is clearly this course's own page, answer 0. Answer JSON only: reason first, then choice (the candidate number, or 0).`;
export function aiMatchRequest(it: { title: string; code: string | null; level: string | null; provider: string; candidates: { url: string; title: string }[] }) {
  const list = it.candidates.map((x, i) => `${i + 1}. ${x.url}${x.title ? ` | ${x.title}` : ""}`).join("\n");
  return {
    model: AI_MATCH_MODEL, temperature: 0, max_tokens: 300, usage: { include: true }, provider: { require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: "page_choice", strict: true, schema: { type: "object", additionalProperties: false, required: ["reason", "choice"],
      properties: { reason: { type: "string" }, choice: { type: "integer", minimum: 0, maximum: it.candidates.length } } } } },
    messages: [{ role: "system", content: AI_MATCH_SYSTEM },
      { role: "user", content: `Course: ${it.title}\nLevel: ${it.level || "not given"}\nCode: ${it.code || "none"}\nProvider: ${it.provider}\nCandidates:\n${list}` }],
  };
}
const BUDGET_MS = 110_000;
const j = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

async function sha256(b: Uint8Array) { return [...new Uint8Array(await crypto.subtle.digest("SHA-256", b))].map((x) => x.toString(16).padStart(2, "0")).join("") }
async function gzip(s: string) { const cs = new CompressionStream("gzip"); const w = cs.writable.getWriter(); w.write(new TextEncoder().encode(s)); w.close(); return new Uint8Array(await new Response(cs.readable).arrayBuffer()) }
async function pool<T>(items: T[], n: number, f: (x: T) => Promise<void>) { let i = 0; await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => { while (i < items.length) await f(items[i++]) })) }


async function fetchText(url: string, ms = 15000) {
  const r = await fetch(url, { headers: { "user-agent": UA, accept: "application/xml,text/xml,text/plain,*/*" }, redirect: "follow", signal: AbortSignal.timeout(ms) });
  if (!r.ok) return "";
  if (/\.gz($|\?)/i.test(url) || /gzip/i.test(r.headers.get("content-type") || "")) {
    try { return await new Response(r.body!.pipeThrough(new DecompressionStream("gzip"))).text() } catch { return "" }
  }
  return await r.text();
}
const coursePri = (u: string) => /course|program|study|handbook|degree|qualification/i.test(u) ? 0 : /page|post/i.test(u) ? 1 : 2;
const scholarshipPri = (u: string) => /scholar|award|bursar|grant/i.test(u) ? 0 : /study|international|page|content/i.test(u) ? 1 : 2;
async function siteMapUrls(origin: string, deadline: number, pri: (u: string) => number = coursePri) {
  const robots = await fetchText(origin + "/robots.txt", 8000).catch(() => "");
  const queue = [...robots.matchAll(/^\s*sitemap:\s*(\S+)/gim)].map((m) => m[1]);
  if (!queue.length) queue.push(origin + "/sitemap.xml", origin + "/sitemap_index.xml");
  const seen = new Set<string>(), urls = new Set<string>();
  let files = 0;
  while (queue.length && files < 60 && urls.size < 60000 && Date.now() < deadline) {
    const sm = queue.shift()!; if (seen.has(sm)) continue; seen.add(sm); files++;
    const xml = await fetchText(sm).catch(() => "");
    const locs = [...xml.matchAll(/<loc>\s*(?:<!\[CDATA\[)?\s*([^<\]\s]+)/gi)].map((m) => m[1].replace(/&amp;/g, "&"));
    if (/<sitemapindex/i.test(xml)) {
      queue.push(...locs.sort((a, b) => pri(a) - pri(b)));
      queue.sort((a, b) => pri(a) - pri(b));
    } else for (const l of locs) urls.add(l);
  }
  return { urls: [...urls], files };
}

// 1 Oct 2026 (Decision 205): fee schedules. A fee row is kept only when the same row carries exactly one course code
// in CRICOS form (6 digits and a check character) and an amount; the basis comes from the column heading (or the line's
// own wording outside tables). Nothing is inferred across rows. The document year is the fee year most often named.
const FEE_CODE = /\b(\d{6}[0-9A-Z])\b/g;
const FEE_HEAD = /fee|tuition|cost|price|aud|\$/i;
const FEE_MONEY = /\$\s?(\d{1,3}(?:,\d{3})+|\d{4,6})(?:\.\d{2})?/g;
function feeBasis(label: string) {
  const l = label.toLowerCase();
  if (/total|whole|full course|entire|course fee \(total\)/.test(l)) return "total_indicative";
  if (/semester/.test(l)) return "per_semester";
  if (/trimester/.test(l)) return "per_trimester";
  if (/annual|per year|yearly|p\.a\.|per annum|eftsl|full[- ]time|1st year|first year|\b20\d\d\b/.test(l)) return "annual";
  return "";
}
function feeDocYear(text: string) {
  const n = new Map<number, number>();
  for (const m of text.matchAll(/\b(202[5-9])\b/g)) n.set(+m[1], (n.get(+m[1]) || 0) + 1);
  return [...n.entries()].sort((a, b) => b[1] - a[1] || b[0] - a[0])[0]?.[0] ?? null;
}
// Fee schedule documents linked from a fee page (usually PDFs): links on the provider's own site whose text or address
// mentions fees or tuition. Newest year first, at most 4.
export function feeLinks(md: string, pageUrl: string) {
  let base: URL; try { base = new URL(pageUrl) } catch { return [] }
  const root = base.hostname.replace(/^www\./, "").split(".").slice(-3).join(".");
  const out = new Map<string, number>();
  for (const m of md.matchAll(/\[([^\]]{0,200})\]\((\S+?)(?:\s+"[^"]*")?\)/g)) {
    let u: URL; try { u = new URL(m[2], base) } catch { continue }
    if (!/^https?:$/.test(u.protocol) || !(u.hostname === root || u.hostname.endsWith("." + root))) continue;
    const text = `${m[1]} ${decodeURIComponent(u.pathname)}`;
    if (!/\.pdf$/i.test(u.pathname) || !/fee|tuition/i.test(text) || /domestic|csp|commonwealth|refund|policy|procedure|form/i.test(text)) continue;
    u.hash = "";
    const y = Math.max(0, ...[...text.matchAll(/\b(202[5-9])\b/g)].map((x) => +x[1]));
    out.set(u.toString(), Math.max(out.get(u.toString()) ?? 0, y));
  }
  return [...out.entries()].sort((a, b) => b[1] - a[1]).slice(0, 4).map(([url, year]) => ({ url, year: year || null }));
}
export function parseFeeRows(md: string) {
  const year = feeDocYear(md);
  const out: { course_code: string; amount: number; basis: string; fee_year: number | null; column_label: string; row_text: string }[] = [];
  // lastFee: the last heading row that named a fee basis. A schedule split across pages (PDFs) continues in tables whose
  // first row is a course row, not a heading; such a table takes lastFee when it has the same number of columns.
  let header: string[] = [], lastFee: string[] = [], tableRows = 0;
  for (const raw of md.split("\n")) {
    const line = raw.trim();
    if (!line) { header = []; continue }
    const codes = [...new Set([...line.matchAll(FEE_CODE)].map((m) => m[1]))];
    if (line.startsWith("|")) {
      const cells = line.split("|").slice(1, -1).map((x) => x.trim());
      if (cells.every((x) => /^:?-{2,}:?$/.test(x) || x === "")) continue;
      const money = cells.map((x) => [...x.matchAll(FEE_MONEY)].map((m) => Number(m[1].replace(/,/g, ""))));
      if (!codes.length && money.every((m) => !m.length)) {
        // a section row inside a table ("| FACULTY OF HEALTH |  |  |") does not replace a heading row that named fees
        if (!header.some((x) => FEE_HEAD.test(x))) header = cells;
        if (cells.some((x) => feeBasis(x))) lastFee = cells;
        continue;
      }
      tableRows++;
      if (codes.length !== 1) continue;
      const head = header.some((x) => FEE_HEAD.test(x)) ? header : (lastFee.length === cells.length ? lastFee : []);
      money.forEach((ms, i) => {
        if (ms.length !== 1) return;
        const label = head[i] || "";
        const basis = feeBasis(label);
        if (!basis) return;
        out.push({ course_code: codes[0], amount: ms[0], basis, fee_year: (label.match(/\b(202[5-9])\b/) ? +label.match(/\b(202[5-9])\b/)![1] : year), column_label: label.slice(0, 120), row_text: line.slice(0, 500) });
      });
    } else if (codes.length === 1) {
      const ms = [...line.matchAll(FEE_MONEY)].map((m) => Number(m[1].replace(/,/g, "")));
      const basis = feeBasis(line);
      if (ms.length === 1 && basis) out.push({ course_code: codes[0], amount: ms[0], basis, fee_year: year, column_label: "", row_text: line.slice(0, 500) });
    }
  }
  const seen = new Set<string>();
  const rows = out.filter((r) => r.amount >= 1000 && r.amount <= 200000 && !seen.has(`${r.course_code}|${r.amount}|${r.basis}`) && (seen.add(`${r.course_code}|${r.amount}|${r.basis}`), true));
  return { rows, summary: { fee_year: year, table_rows: tableRows, codes_seen: new Set([...md.matchAll(FEE_CODE)].map((m) => m[1])).size, rows: rows.length } };
}

Deno.serve(async (req) => {
  const t0 = Date.now();
  if (req.method !== "POST") return j({ error: "POST required", workerVersion: VERSION }, 405);
  const c = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const rpc = async (fn: string, args: Record<string, unknown>) => { const { data, error } = await c.rpc(fn, args); if (error) throw Error(`${fn}: ${error.message}`); return data };
  try {
    const nonce = (req.headers.get("x-cf-run-nonce") || "").trim();
    const { data: ok } = nonce ? await c.rpc("svc_pilot_consume_nonce", { p_function: "coverage-sweep", p_nonce: nonce }) : { data: false };
    if (!ok) return j({ error: "valid one-time Pilot nonce required", workerVersion: VERSION }, 401);
    const body = await req.json().catch(() => ({}));
    const mode = String(body.mode || "");
    const fc = await rpc("svc_coverage_firecrawl", {});
    let fcRemaining = fc?.budget_status?.allowed === false ? 0 : Math.max(0, Number(fc?.budget_status?.remaining_units ?? 0) - Number(fc?.budget_status?.stop_at_remaining_units ?? 0));
    const fcHeaders = { authorization: `Bearer ${fc?.secret}`, "content-type": "application/json" };
    // scholarship work (purposes sch_*) also stays inside its own 3,000-credit cap
    let schLeft = mode.startsWith("scholarship") ? Math.max(0, SCH_FC_CAP - Number(await rpc("svc_scholarship_fc_used", {}) ?? SCH_FC_CAP)) : 0;
    const useFc = async (purpose: string, providerId: string | null, url: string) => {
      if (!fc?.secret || fcRemaining < 1) return false;
      const units = /search$/.test(purpose) ? 2 : /^fcx_/.test(purpose) ? 5 : 1; if (fcRemaining < units) return false; // v0.13.0: a JSON-format scrape costs 5 credits
      if (purpose.startsWith("sch_")) { if (schLeft < units) return false; schLeft -= units }
      fcRemaining -= units; await rpc("svc_coverage_usage", { p_units: units, p_purpose: purpose, p_provider_id: providerId, p_url: url }); return true;
    };
    const robots = new Map<string, Promise<string>>();
    const robotsFor = (u: URL) => { if (!robots.has(u.origin)) robots.set(u.origin, fetch(u.origin + "/robots.txt", { headers: { "user-agent": UA }, signal: AbortSignal.timeout(8000) }).then((r) => r.ok ? r.text() : "").catch(() => "")); return robots.get(u.origin)! };
    // direct page read (robots.txt respected); no Firecrawl
    const readDirect = async (url: string) => {
      let status = "fetch_failed", http: number | null = null, html = "", finalUrl = url;
      try {
        const u = new URL(url);
        if (!robotsAllows(await robotsFor(u), u.pathname + u.search)) return { status: "robots_disallowed", http, html, finalUrl };
        const r = await fetch(u, { headers: { "user-agent": UA, accept: "text/html,application/xhtml+xml" }, redirect: "follow", signal: AbortSignal.timeout(20000) });
        http = r.status; finalUrl = r.url || url;
        if (r.ok && /html/i.test(r.headers.get("content-type") || "html")) html = await r.text(); else await r.body?.cancel();
        status = html && mainText(html).length >= 300 ? "read" : html ? "too_thin" : http === 404 || http === 410 ? "gone" : [401, 403, 406, 429].includes(http) ? "blocked" : r.ok ? "not_html" : "fetch_failed";
      } catch { status = "fetch_failed" }
      return { status, http, html, finalUrl };
    };

    if (mode === "discover") {
      const want = Math.min(Number(body.limit || 4), 8);
      const providers: { provider_id: string; website: string }[] = await rpc("svc_coverage_discovery_next", { p_limit: want });
      const out: unknown[] = [];
      await pool(providers as any[], 4, async (p: { provider_id: string; website: string; courses: number }) => {
        let site: URL;
        try { site = new URL(/^https?:/i.test(p.website) ? p.website : "https://" + p.website) } catch { await rpc("svc_coverage_discovery_record", { p_provider_id: p.provider_id, p_status: "failed", p_method: "map", p_url_count: 0, p_urls: [], p_error: "invalid website" }); return }
        try {
          // final address after redirects (monash.edu.au -> monash.edu)
          try { const r = await fetch(site, { headers: { "user-agent": UA }, redirect: "follow", signal: AbortSignal.timeout(15000) }); if (r.url) site = new URL(r.url); await r.body?.cancel() } catch { /* keep the recorded address */ }
          const found = new Map<string, { url: string; title?: string }>();
          const methods: string[] = [];
          const sm = await siteMapUrls(site.origin, Date.now() + 40000).catch(() => ({ urls: [] as string[], files: 0 }));
          if (sm.urls.length) methods.push(`sitemap(${sm.files})`);
          let total = sm.urls.length;
          for (const u of sm.urls) if (keepUrl({ url: u }, site.hostname)) found.set(u, { url: u });
          const target = Math.max(5, Math.ceil(Number(p.courses || 0) * 0.6));
          for (const search of [null, "course"]) {
            if (found.size >= target) break;
            if (!(await useFc("map", p.provider_id, site.origin))) { methods.push("map:budget"); break }
            const r = await fetch("https://api.firecrawl.dev/v2/map", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: site.origin, limit: 30000, sitemap: "include", includeSubdomains: true, ...(search ? { search } : {}) }), signal: AbortSignal.timeout(60000) });
            const d = await r.json().catch(() => ({}));
            if (!r.ok || d?.success === false) { methods.push(`map:${r.status}`); break }
            const links = (d.links || d.data?.links || []).map((x: any) => typeof x === "string" ? { url: x } : { url: x.url, title: x.title });
            methods.push(search ? `map_search(${links.length})` : `map(${links.length})`); total += links.length;
            for (const u of links) if (u.url && keepUrl(u, site.hostname) && (!found.has(u.url) || u.title)) found.set(u.url, u);
          }
          const kept = [...found.values()].slice(0, 12000);
          const status = kept.length ? "mapped" : "failed";
          const rec = await rpc("svc_coverage_discovery_record", { p_provider_id: p.provider_id, p_status: status, p_method: methods.join("+") || "none", p_url_count: total, p_urls: kept, p_error: kept.length ? null : "no course-like pages found" });
          out.push({ provider_id: p.provider_id, status, methods, total, kept: rec?.kept });
        } catch (e) {
          await rpc("svc_coverage_discovery_record", { p_provider_id: p.provider_id, p_status: "failed", p_method: "discover", p_url_count: 0, p_urls: [], p_error: e instanceof Error ? e.message : String(e) });
          out.push({ provider_id: p.provider_id, status: "failed", error: e instanceof Error ? e.message : String(e) });
        }
      });
      return j({ ok: true, mode, providers: out, firecrawlRemainingAboveReserve: fcRemaining, ms: Date.now() - t0, workerVersion: VERSION });
    }


    // v0.10.0 (2 Oct 2026, Platform Admin 21:18): third-party directory capture, hints only. Only allow-listed directory
    // hosts; robots.txt respected; each page fetched through Firecrawl (scrape, html + links), stored gzipped in the
    // evidence bucket under thirdparty/<site>/<country>/ and recorded with its links. Nothing from a directory is
    // admitted; names, website links and course counts become hints that our own rules verify.
    if (mode === "directory_capture") {
      const site = String(body.site || "");
      const host = DIRECTORY_HOSTS[site];
      if (!host) return j({ ok: false, mode, error: "unknown directory site", workerVersion: VERSION }, 422);
      const country = String(body.country || "").toUpperCase();
      const urls: string[] = (Array.isArray(body.urls) ? body.urls : []).map(String).filter((u: string) => { try { return new URL(u).hostname === host } catch { return false } }).slice(0, 25);
      // v0.10.2: robots.txt per RFC 9309. A file with rules is followed. A site that answers 404 or 410 has no
      // robots.txt, which means no rules. A site that refuses or fails our direct request is asked through Firecrawl;
      // if it still cannot be read, nothing is captured.
      let robotsTxt = "", robotsState = "unreadable";
      const direct = await fetch(`https://${host}/robots.txt`, { headers: { "user-agent": UA }, signal: AbortSignal.timeout(8000) }).catch(() => null);
      const directText = direct?.ok ? await direct.text().catch(() => "") : "";
      if (/user-agent/i.test(directText)) { robotsTxt = directText; robotsState = "read" }
      // a file served successfully but holding no rule groups restricts nothing (RFC 9309 §2.2; Google reads it the same way)
      else if (direct?.ok) robotsState = "no_rules";
      else if (direct && (direct.status === 404 || direct.status === 410)) robotsState = "none";
      else if (await useFc("directory_scrape", null, `https://${host}/robots.txt`)) {
        const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: `https://${host}/robots.txt`, formats: ["rawHtml"] }), signal: AbortSignal.timeout(45000) }).catch(() => null);
        const d = r ? await r.json().catch(() => ({})) : {};
        const raw = String(d?.data?.rawHtml || "");
        const sc = Number(d?.data?.metadata?.statusCode || 0);
        if (/user-agent/i.test(raw)) { robotsTxt = raw.replace(/<[^>]+>/g, ""); robotsState = "read_via_firecrawl" }
        else if (sc === 404 || sc === 410) robotsState = "none";
      }
      if (robotsState === "unreadable") return j({ ok: false, mode, error: "robots.txt could not be read; nothing captured", robotsHttp: direct?.status ?? null, workerVersion: VERSION }, 409);
      const out: unknown[] = [];
      await pool(urls, 4, async (u) => {
        const url = new URL(u);
        if (robotsTxt && !robotsAllows(robotsTxt, url.pathname + url.search)) { out.push({ url: u, status: "robots_disallowed" }); return }
        if (!(await useFc("directory_scrape", null, u))) { out.push({ url: u, status: "credit_budget" }); return }
        try {
          const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: u, formats: ["html", "links"], onlyMainContent: false, ...(body.wait_ms ? { waitFor: Math.min(Number(body.wait_ms), 8000) } : {}) }), signal: AbortSignal.timeout(90000) });
          const d = await r.json().catch(() => ({}));
          const html = String(d?.data?.html || "");
          if (!r.ok || !html) { out.push({ url: u, status: "failed", http: r.status, error: String(d?.error || "").slice(0, 160) }); return }
          const sha = await sha256(new TextEncoder().encode(html));
          const path = `thirdparty/${site}/${country || "XX"}/${sha}.html.gz`;
          const up = await c.storage.from("evidence").upload(path, await gzip(html), { contentType: "application/gzip", upsert: true });
          const links: string[] = Array.isArray(d?.data?.links) ? d.data.links.map(String) : [];
          const rec = await rpc("svc_directory_page_record", { p_site: site, p_country: country || null, p_url: u, p_final_url: d?.data?.metadata?.sourceURL || u, p_http: d?.data?.metadata?.statusCode ?? 200,
            p_storage_path: up.error ? null : path, p_sha256: up.error ? null : sha, p_title: titleOf(html).slice(0, 300), p_links: links.slice(0, 5000), p_text: htmlToText(html).slice(0, 20000) });
          // univ.cc lists each institution as a link to its own website: link text = name, address = website hint
          let hints: unknown = null;
          if (site === "univcc" && country) {
            const anchors = [...html.matchAll(/<a\b[^>]*href\s*=\s*["'](https?:\/\/[^"']+)["'][^>]*>([\s\S]{1,300}?)<\/a>/gi)]
              .map((m) => ({ href: m[1], text: htmlToText(m[2]) })).filter((a) => { try { return !new URL(a.href).hostname.endsWith("univ.cc") } catch { return false } });
            hints = await rpc("svc_directory_anchor_hints", { p_site: site, p_country: country, p_page_id: rec, p_page_url: u, p_anchors: anchors });
          }
          out.push({ url: u, status: "stored", links: links.length, page_id: rec, hints });
        } catch (e) { out.push({ url: u, status: "failed", error: e instanceof Error ? e.message : String(e) }) }
      });
      return j({ ok: true, mode, site, country, robots: robotsState, pages: out, firecrawlRemainingAboveReserve: fcRemaining, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    // v0.10.0: AI page-identity check, qualification only (contract cf247-page-identity-v1.0.0). Runs one pinned model on
    // the frozen holdout and records each answer with the deterministic checks. Nothing is admitted or switched on.
    if (mode === "id_qualify") {
      const model = String(body.model || "");
      if (!PAGE_ID_MODELS.includes(model)) return j({ ok: false, mode, error: "model is not a pinned candidate", workerVersion: VERSION }, 422);
      const runLabel = String(body.run_label || "");
      if (!/^q-pid-[a-z0-9.-]{3,60}$/.test(runLabel)) return j({ ok: false, mode, error: "run_label q-pid-... required", workerVersion: VERSION }, 422);
      const goldSet = String(body.gold_set || "pid-h1");
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) { const prof = await rpc("layer3_routing_profile_service", { p_code: AI_MATCH_PROFILE }); const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof?.id }); key = typeof data === "string" ? data : "" }
      if (!key) return j({ ok: false, mode, error: "OpenRouter credential unavailable", workerVersion: VERSION }, 503);
      const cases: { case_no: number; storage_path: string; gold: boolean; title: string; code: string; level: string | null; provider: string }[] =
        await rpc("svc_coverage_identity_cases", { p_gold_set: goldSet, p_offset: Number(body.offset || 0), p_limit: Math.min(Number(body.limit || 60), 120) });
      const tally: Record<string, number> = {}; let cost = 0;
      await pool(cases, Math.min(Number(body.concurrency || 8), 12), async (k) => {
        if (Date.now() - t0 > BUDGET_MS) { tally.time = (tally.time || 0) + 1; return }
        let answer: any = null, checks: any = null, accepted: boolean | null = null, returned: string | null = null, c1 = 0;
        try {
          const { data, error } = await c.storage.from("evidence").download(k.storage_path);
          if (error || !data) throw Error(error?.message || "missing page");
          const html = await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text();
          // a wrong pairing whose own code is printed on the page is not a wrong pairing (one page for two courses)
          if (!k.gold && k.code && new RegExp(`\\b${String(k.code).replace(/[^0-9A-Z]/gi, "")}\\b`, "i").test(htmlToText(html))) { checks = { excluded: "asked course's code is on the page" } }
          else {
            const page = pageIdInput(html, mainText);
            const r = await fetch("https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" }, body: JSON.stringify(pageIdRequest(model, k, page)), signal: AbortSignal.timeout(60000) });
            const d = await r.json().catch(() => ({}));
            if (!r.ok) throw Error(`HTTP ${r.status}: ${JSON.stringify(d?.error || d).slice(0, 160)}`);
            returned = d?.model || null; c1 = Number(d?.usage?.cost || 0);
            answer = JSON.parse(String(d?.choices?.[0]?.message?.content || "{}"));
            checks = pageIdChecks(k.title, answer, page.fullText);
            accepted = returned === model ? checks.accepted : false;
            if (returned !== model) checks.returned_model_mismatch = returned;
          }
        } catch (e) { checks = { ...(checks || {}), error: e instanceof Error ? e.message : String(e) } }
        cost += c1;
        await rpc("svc_coverage_identity_result", { p_run_label: runLabel, p_gold_set: goldSet, p_case_no: k.case_no, p_model: model, p_returned: returned, p_answer: answer, p_checks: checks, p_accepted: accepted, p_cost: c1 });
        const o = checks?.excluded ? "excluded" : accepted === null ? "error" : accepted === k.gold ? "right" : k.gold ? "missed" : "WRONG_ACCEPTED";
        tally[o] = (tally[o] || 0) + 1;
      });
      return j({ ok: true, mode, run_label: runLabel, model, contract: PAGE_ID_CONTRACT, cases: cases.length, tally, cost_usd: cost, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    // v0.10.1: the OpenRouter key's own limits (weekly, daily, total), read with the governed credential; the key is
    // never returned.
    // v0.13.0 (3 Oct 2026, Platform Admin "Yes, qualify now"): Firecrawl's own AI extraction (JSON format) as a CANDIDATE
    // route for intakes and English. Qualification only: each frozen holdout case is fetched and rendered by Firecrawl,
    // which returns fields against a fixed schema; the answer is scored against the gold value and recorded
    // (svc_fc_extract_result). Nothing is admitted and no cascade changes. Firecrawl does not name its model, so a pass
    // admits it only as a provider-level route (re-tested weekly, paused on a failure), never a model-cascade step.
    if (mode === "fc_extract_qualify") {
      const task = String(body.task_class || "");
      if (!["provider_intake_validation", "provider_english_validation"].includes(task)) return j({ ok: false, mode, error: "task_class must be provider_intake_validation or provider_english_validation", workerVersion: VERSION }, 422);
      const runLabel = String(body.run_label || "");
      if (!/^q-fcx-[a-z0-9.-]{3,60}$/.test(runLabel)) return j({ ok: false, mode, error: "run_label q-fcx-... required", workerVersion: VERSION }, 422);
      if (!fc?.secret) return j({ ok: false, mode, error: "Firecrawl credential unavailable", workerVersion: VERSION }, 503);
      const intake = task === "provider_intake_validation";
      const schema = intake
        ? { type: "object", properties: { status: { type: "string", enum: ["months", "not_stated"] }, months: { type: "array", items: { type: "integer", minimum: 1, maximum: 12 } }, quote: { type: "string" } }, required: ["status", "months", "quote"] }
        : { type: "object", properties: { status: { type: "string", enum: ["stated", "not_stated"] }, tests: { type: "array", items: { type: "object", properties: { test: { type: "string", enum: ["IELTS", "PTE", "TOEFL_IBT", "CAE"] }, overall: { type: "number" }, min_band: { type: ["number", "null"] } }, required: ["test", "overall"] } }, quote: { type: "string" } }, required: ["status", "tests", "quote"] };
      const prompt = intake
        ? "This is one course's page. Give the months of the year in which this course starts (intakes) for new students, ONLY where the page states them as month names or full dates for this course. Semester, trimester or term names without a month are NOT months: then status is not_stated and months is empty. Do not infer. quote = the exact words from the page that state the months."
        : "This is one course's page. Give the English language test scores this course requires of international applicants, ONLY where the page states them for this course: IELTS, PTE, TOEFL_IBT or CAE with the overall score and the minimum band if stated. A statement that English is required without a score, or a link to a policy, is not_stated. Do not infer. quote = the exact words from the page that state the scores.";
      const cases: { case_id: string; task_class: string; url: string; gold: any }[] = await rpc("svc_fc_extract_cases", { p_task_class: task, p_offset: Number(body.offset || 0), p_limit: Math.min(Number(body.limit || 50), 100) });
      const tally: Record<string, number> = {}; let credits = 0;
      const norm = (s: string) => String(s || "").toLowerCase().replace(/\s+/g, " ").trim();
      const sameSet = (a: unknown[], b: unknown[]) => { const x = [...new Set(a.map(String))].sort().join(","), y = [...new Set(b.map(String))].sort().join(","); return x === y };
      await pool(cases, Math.min(Number(body.concurrency || 4), 6), async (k) => {
        if (Date.now() - t0 > BUDGET_MS) { tally.time = (tally.time || 0) + 1; return }
        let answer: any = null, outcome = "error", quoteIn: boolean | null = null, http: number | null = null, err: string | null = null, c1 = 0;
        try {
          if (!(await useFc("fcx_qualify", null, k.url))) throw Error("credit budget");
          const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: k.url, formats: ["markdown", { type: "json", schema, prompt }], onlyMainContent: false }), signal: AbortSignal.timeout(90000) });
          http = r.status; const d = await r.json().catch(() => ({}));
          if (!r.ok || !d?.data) throw Error(`HTTP ${r.status}: ${JSON.stringify(d?.error || "").slice(0, 160)}`);
          c1 = Number(d?.data?.metadata?.creditsUsed || 5); credits += c1;
          answer = d.data.json || null; const md = String(d.data.markdown || "");
          const q = norm(answer?.quote || ""); quoteIn = q.length >= 8 ? norm(md).includes(q) : false;
          const g = k.gold || {};
          if (intake) {
            const gm = Array.isArray(g.months) ? g.months : [], am = Array.isArray(answer?.months) ? answer.months : [];
            const gStated = g.status === "months" && gm.length > 0, aStated = answer?.status === "months" && am.length > 0 && quoteIn === true;
            outcome = !gStated && !aStated ? "exact_not_stated" : gStated && aStated && sameSet(gm, am) ? "exact" : aStated ? "wrong_admitted" : "missed";
          } else {
            const key = (t: any) => `${String(t?.test || "").toUpperCase()}:${Number(t?.overall)}`;
            const gt = Array.isArray(g.tests) ? g.tests.map(key) : [], at = Array.isArray(answer?.tests) ? answer.tests.map(key) : [];
            const gStated = g.status === "stated" && gt.length > 0, aStated = answer?.status === "stated" && at.length > 0 && quoteIn === true;
            // right = every test the answer gives is in the gold with the same overall score, and the gold's tests are all given
            outcome = !gStated && !aStated ? "exact_not_stated" : gStated && aStated && sameSet(gt, at) ? "exact" : aStated ? "wrong_admitted" : "missed";
          }
        } catch (e) { err = e instanceof Error ? e.message : String(e); outcome = "error" }
        await rpc("svc_fc_extract_result", { p_run_label: runLabel, p_case_id: k.case_id, p_task_class: task, p_answer: answer, p_outcome: outcome, p_quote_in_page: quoteIn, p_credits: c1, p_http: http, p_error: err });
        tally[outcome] = (tally[outcome] || 0) + 1;
      });
      return j({ ok: true, mode, run_label: runLabel, task_class: task, cases: cases.length, tally, credits, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    if (mode === "openrouter_key") {
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) { const prof = await rpc("layer3_routing_profile_service", { p_code: AI_MATCH_PROFILE }); const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof?.id }); key = typeof data === "string" ? data : "" }
      if (!key) return j({ ok: false, mode, error: "OpenRouter credential unavailable", workerVersion: VERSION }, 503);
      const r = await fetch("https://openrouter.ai/api/v1/key", { headers: { authorization: `Bearer ${key}` }, signal: AbortSignal.timeout(15000) });
      const d = (await r.json().catch(() => ({})))?.data || {};
      const pick = ["label", "limit", "limit_remaining", "limit_reset", "include_byok_in_limit", "usage", "usage_daily", "usage_weekly", "usage_monthly", "is_free_tier"];
      return j({ ok: r.ok, mode, http: r.status, key: Object.fromEntries(pick.filter((k) => k in d).map((k) => [k, d[k]])), workerVersion: VERSION, worker: WORKER });
    }
    // v0.10.1: reference lists read as a whole file (Hipo university-domains-list, MIT), stored as evidence, loaded as
    // website hints (Decision 232). Only allow-listed files.
    if (mode === "reference_capture") {
      const src = String(body.source || ""), url = REFERENCE_FILES[src];
      if (!url) return j({ ok: false, mode, error: "unknown reference source", workerVersion: VERSION }, 422);
      const r = await fetch(url, { headers: { "user-agent": UA }, signal: AbortSignal.timeout(60000) });
      const txt = r.ok ? await r.text() : "";
      let rows: unknown[] = []; try { rows = JSON.parse(txt) } catch { /* not JSON */ }
      if (!Array.isArray(rows) || !rows.length) return j({ ok: false, mode, error: `could not read ${src} (HTTP ${r.status})`, workerVersion: VERSION }, 502);
      const sha = await sha256(new TextEncoder().encode(txt));
      const path = `reference/${src}/${sha}.json.gz`;
      const up = await c.storage.from("evidence").upload(path, await gzip(txt), { contentType: "application/gzip", upsert: true });
      const res = await rpc("svc_reference_institutions_load", { p_source: src, p_rows: rows, p_storage_path: up.error ? null : path });
      return j({ ok: true, mode, source: src, rows: rows.length, stored: up.error ? null : path, result: res, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    // v0.10.1: website hints (reference lists, directories) are accepted only when our own website rule passes on the
    // home page: AU the CRICOS provider code on the page; CA a .ca site naming the provider or printing its DLI number;
    // NZ a .nz site naming the provider.
    if (mode === "site_hint_verify") {
      const items: { provider_id: string; name: string; country: string; cricos: string | null; dli: string | null; urls: { url: string; via: string }[] }[] =
        await rpc("svc_site_hint_next", { p_limit: Math.min(Number(body.limit || 20), 60) });
      const tally: Record<string, number> = {};
      await pool(items, 6, async (it) => {
        let done = false;
        for (const h of it.urls.slice(0, 4)) {
          if (Date.now() - t0 > BUDGET_MS) return;
          let accepted = false, basis: string | null = null, ev: Record<string, unknown> = { hint: h.url, via: h.via, worker: WORKER };
          try {
            const u = new URL(/^https?:/i.test(h.url) ? h.url : "https://" + h.url);
            const resp = await fetch(u.origin + "/", { headers: { "user-agent": UA }, redirect: "follow", signal: AbortSignal.timeout(15000) }).catch(() => null);
            let html = resp?.ok ? await resp.text() : "";
            let finalUrl = resp?.url || u.origin + "/";
            ev = { ...ev, final: finalUrl, http: resp?.status ?? null };
            const check = (page: string, at: string) => {
              const host = new URL(at).hostname.toLowerCase();
              if (it.country === "AU") {
                const code = String(it.cricos || "").toUpperCase();
                if (code.length >= 5 && new RegExp("(^|[^0-9A-Z])" + code.split("").join("\\s?") + "([^0-9A-Z]|$)", "i").test(htmlToText(page))) { accepted = true; basis = "cricos_code" }
              } else if ((it.country === "CA" && host.endsWith(".ca")) || (it.country === "NZ" && host.endsWith(".nz"))) {
                const b = siteNameMatch(page, htmlToText(page), it.name, it.dli || "", host);
                if (b) { accepted = true; basis = String(b) }
              }
            };
            if (!done && html) check(html, finalUrl);
            // v0.10.2: a home page that refuses our direct request, or does not prove itself as fetched (often a page
            // drawn by script), is read once through Firecrawl (rendered). robots.txt is respected; the same rule decides.
            if (!done && !accepted && robotsAllows(await robotsFor(new URL(u.origin)), "/") && await useFc("site_hint", it.provider_id, u.origin + "/")) {
              const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: u.origin + "/", formats: ["html"], onlyMainContent: false }), signal: AbortSignal.timeout(60000) }).catch(() => null);
              const d = r ? await r.json().catch(() => ({})) : {};
              const fh = String(d?.data?.html || "");
              if (fh) { html = fh; finalUrl = String(d?.data?.metadata?.url || d?.data?.metadata?.sourceURL || finalUrl); ev = { ...ev, via_firecrawl: true, final: finalUrl, http_firecrawl: d?.data?.metadata?.statusCode ?? null }; check(html, finalUrl) }
            }
            const site = accepted ? new URL(finalUrl).origin : h.url;
            const st = await rpc("svc_site_hint_record", { p_provider_id: it.provider_id, p_url: accepted ? site : h.url, p_accepted: accepted, p_basis: basis, p_evidence: ev });
            if (accepted && site !== h.url) await rpc("svc_site_hint_record", { p_provider_id: it.provider_id, p_url: h.url, p_accepted: false, p_basis: "redirected", p_evidence: { ...ev, accepted_as: site } });
            tally[st] = (tally[st] || 0) + 1;
            if (accepted) { done = true; break }
          } catch (e) {
            await rpc("svc_site_hint_record", { p_provider_id: it.provider_id, p_url: h.url, p_accepted: false, p_basis: "fetch_failed", p_evidence: { ...ev, error: e instanceof Error ? e.message : String(e) } });
            tally.failed = (tally.failed || 0) + 1;
          }
        }
      });
      return j({ ok: true, mode, providers: items.length, tally, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    // v0.10.0: pages stored as identity mismatches are checked again with the current identity rule from their stored
    // copy (no fetch). A page that now passes is set back to read; the usual admission runs on it.
    if (mode === "reidentify") {
      const rule = IDENTITY_RULE;
      const rows: { course_id: string; evidence_id: string; storage_path: string; url: string; title: string; code: string; country?: string }[] =
        await rpc("svc_coverage_reidentify_next", { p_limit: Math.min(Number(body.limit || 100), 400), p_rule: rule });
      const tally: Record<string, number> = {};
      await pool(rows, 10, async (r) => {
        let basis: string | null = null, cand: unknown = null;
        try {
          if (Date.now() - t0 > BUDGET_MS) return;
          const { data, error } = await c.storage.from("evidence").download(r.storage_path);
          if (error || !data) throw Error(error?.message || "missing");
          const html = await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text();
          const text = htmlToText(html);
          basis = identity(html, text, r.title, r.code, false, r.country || "");
          if (basis === "field_award" && staleCalendarUrl(r.url)) basis = null;
          if (basis) cand = { final_url: r.url, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), fee: fee(text, currencyFor(r.country)), english: english(text), intakes: intakes(text), intake_context: intakeEvidence(text), extractor: VERSION };
          const st = await rpc("svc_coverage_reidentify_record", { p_course_id: r.course_id, p_evidence_id: r.evidence_id, p_rule: rule, p_identity_basis: basis, p_candidates: cand });
          tally[st] = (tally[st] || 0) + 1;
        } catch { tally.failed = (tally.failed || 0) + 1 }
      });
      return j({ ok: true, mode, rule, rows: rows.length, tally, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    if (mode === "reextract") {
      const rows: { course_id: string; storage_path: string; title: string; code: string; status: string; url: string; country?: string }[] = await rpc("svc_coverage_reextract_next", { p_limit: Math.min(Number(body.limit || 100), 200), p_version: VERSION });
      let done = 0, failed = 0;
      await pool(rows, 10, async (r) => {
        try {
          const { data, error } = await c.storage.from("evidence").download(r.storage_path);
          if (error || !data) throw Error(error?.message || "missing");
          const html = await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text();
          const text = htmlToText(html);
          const cand = { final_url: r.url, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), fee: fee(text, currencyFor(r.country)), english: english(text), intakes: intakes(text), intake_context: intakeEvidence(text), extractor: VERSION };
          await rpc("svc_coverage_candidates_update", { p_course_id: r.course_id, p_candidates: cand }); done++;
        } catch { failed++ }
      });
      return j({ ok: true, mode, rows: rows.length, done, failed, ms: Date.now() - t0, workerVersion: VERSION });
    }
    // v0.6.0 (Decision 163, Option A): tuition found on CRICOS-code pages goes to the qualified Layer 3 model.
    // The stored page is turned into plain text (the qualified interpreter reads text evidence only), saved as its
    // own evidence, and recorded as a Layer 2 run item with a Layer 3 work item. Nothing is admitted here.
    if (mode === "tuition_handoff") {
      const rows: { course_id: string; storage_path: string; url: string }[] = await rpc("svc_coverage_tuition_handoff_next", { p_limit: Math.min(Number(body.limit || 50), 100) });
      let done = 0, failed = 0; const errors: string[] = [];
      await pool(rows, 8, async (r) => {
        try {
          const { data, error } = await c.storage.from("evidence").download(r.storage_path);
          if (error || !data) throw Error(error?.message || "missing");
          const html = await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text();
          const text = htmlToText(html);
          if (text.length < 200) throw Error("page text too short");
          const bytes = new TextEncoder().encode(text), hash = await sha256(bytes);
          const path = `coverage-text/${r.course_id}/${hash.slice(0, 32)}.txt`;
          const up = await c.storage.from("evidence").upload(path, bytes, { contentType: "text/plain", upsert: true });
          if (up.error) throw Error("upload: " + up.error.message);
          const res = await rpc("svc_coverage_tuition_handoff_record", { p_course_id: r.course_id, p_storage_path: path, p_content_hash: hash, p_bytes: bytes.length });
          if (res?.queued) done++; else failed++;
        } catch (e) { failed++; if (errors.length < 3) errors.push(e instanceof Error ? e.message : String(e)) }
      });
      return j({ ok: true, mode, rows: rows.length, done, failed, errors, ms: Date.now() - t0, workerVersion: VERSION });
    }
    if (mode === "find_site") {
      const provs: { provider_id: string; name: string; trading: string | null; cricos: string; country?: string; dli?: string }[] = await rpc("svc_coverage_site_next", { p_limit: Math.min(Number(body.limit || 5), 10) });
      const out: unknown[] = [];
      // v0.6.4: sites that are never a university's own website come from Reference sources (use not_provider_site),
      // managed in the admin, instead of a fixed pattern here. No list means no search (fail closed).
      const skipDomains: string[] = await rpc("svc_reference_domains", { p_use: "not_provider_site" });
      if (!Array.isArray(skipDomains) || skipDomains.length === 0) return j({ ok: false, mode, error: "reference sources list is empty or unavailable" }, 503);
      const SKIP = { test: (host: string) => { const h = host.toLowerCase(); return skipDomains.some((d) => d.includes(".") ? (h === d || h.endsWith("." + d)) : new RegExp("(^|\\.)" + d.replace(/[^a-z0-9-]/g, "")).test(h)); } };
      // Decision 220: a Canadian provider's site, found by name. Accepted only on a .ca host (not a directory or
      // register) whose home page names the provider or prints its IRCC DLI number.
      const findCanadianSite = async (p: { provider_id: string; name: string; dli?: string }) => {
        const query = `${p.name} official website`;
        if (!(await useFc("search", p.provider_id, p.name))) { await rpc("svc_coverage_site_record", { p_provider_id: p.provider_id, p_website: null, p_evidence: { note: "Firecrawl budget reserve reached" } }); return { provider_id: p.provider_id, status: "budget" } }
        let accepted: string | null = null, basis: string | null = null; const tried: unknown[] = [];
        try {
          const r = await fetch("https://api.firecrawl.dev/v2/search", { method: "POST", headers: fcHeaders, body: JSON.stringify({ query, limit: 8, country: "CA" }), signal: AbortSignal.timeout(45000) });
          const d = await r.json().catch(() => ({}));
          const results = (d?.data?.web || d?.data || []).map((x: any) => ({ url: x.url })).filter((x: any) => typeof x.url === "string");
          const seenHosts = new Set<string>();
          for (const res of results) {
            let u: URL; try { u = new URL(res.url) } catch { continue }
            const host = u.hostname.toLowerCase();
            if (!host.endsWith(".ca") || SKIP.test(host) || seenHosts.has(host)) { tried.push({ page: res.url, skipped: true }); continue }
            seenHosts.add(host);
            try {
              const h = await fetch(u.origin + "/", { headers: { "user-agent": UA }, redirect: "follow", signal: AbortSignal.timeout(15000) });
              const html = h.ok ? await h.text() : "";
              let finalHost = host; try { finalHost = new URL(h.url || u.origin).hostname.toLowerCase() } catch { /* keep */ }
              const b = finalHost.endsWith(".ca") ? siteNameMatch(html, htmlToText(html), p.name, p.dli || "", finalHost) : null;
              tried.push({ page: u.origin + "/", http: h.status, basis: b });
              if (b) { accepted = new URL(h.url || u.origin).origin; basis = b; break }
            } catch { tried.push({ page: u.origin + "/", error: true }) }
            if (seenHosts.size >= 4) break;
          }
        } catch (e) { tried.push({ error: e instanceof Error ? e.message : String(e) }) }
        await rpc("svc_coverage_site_record", { p_provider_id: p.provider_id, p_website: accepted, p_evidence: { query, country: "CA", tried, accepted, basis, worker: WORKER } });
        return { provider_id: p.provider_id, status: accepted ? "found" : "not_found", website: accepted, basis };
      };
      await pool(provs, 3, async (p) => {
        if ((p.country || "AU") === "CA") { out.push(await findCanadianSite(p)); return }
        const code = String(p.cricos || "").toUpperCase();
        if (code.length < 5) { await rpc("svc_coverage_site_record", { p_provider_id: p.provider_id, p_website: null, p_evidence: { note: "no CRICOS provider code to check a site against", worker: WORKER } }); out.push({ provider_id: p.provider_id, status: "no_code" }); return }
        const codeRe = new RegExp("(^|[^0-9A-Z])" + code.split("").join("\\s?") + "([^0-9A-Z]|$)", "i");
        if (!(await useFc("search", p.provider_id, p.name))) { out.push({ provider_id: p.provider_id, status: "budget" }); await rpc("svc_coverage_site_record", { p_provider_id: p.provider_id, p_website: null, p_evidence: { note: "Firecrawl budget reserve reached" } }); return }
        let accepted: string | null = null; const tried: unknown[] = [];
        try {
          const r = await fetch("https://api.firecrawl.dev/v2/search", { method: "POST", headers: fcHeaders, body: JSON.stringify({ query: `${p.name} CRICOS ${code}`, limit: 8, country: "AU" }), signal: AbortSignal.timeout(45000) });
          const d = await r.json().catch(() => ({}));
          const results = (d?.data?.web || d?.data || []).map((x: any) => ({ url: x.url, title: x.title })).filter((x: any) => typeof x.url === "string");
          const seenHosts = new Set<string>();
          for (const res of results) {
            let u: URL; try { u = new URL(res.url) } catch { continue }
            if (SKIP.test(u.hostname) || seenHosts.has(u.hostname)) continue; seenHosts.add(u.hostname);
            for (const page of [u.origin + "/", res.url]) {
              try {
                const h = await fetch(page, { headers: { "user-agent": UA }, redirect: "follow", signal: AbortSignal.timeout(15000) });
                const html = h.ok ? await h.text() : "";
                const ok = codeRe.test(htmlToText(html));
                tried.push({ page, http: h.status, code_found: ok });
                if (ok) { accepted = new URL(h.url || page).origin; break }
              } catch { tried.push({ page, error: true }) }
            }
            if (accepted || seenHosts.size >= 4) break;
          }
        } catch (e) { tried.push({ error: e instanceof Error ? e.message : String(e) }) }
        await rpc("svc_coverage_site_record", { p_provider_id: p.provider_id, p_website: accepted, p_evidence: { query: `${p.name} CRICOS ${code}`, tried, accepted, worker: VERSION } });
        out.push({ provider_id: p.provider_id, status: accepted ? "found" : "not_found", website: accepted });
      });
      return j({ ok: true, mode, providers: out, firecrawlRemainingAboveReserve: fcRemaining, ms: Date.now() - t0, workerVersion: VERSION });
    }
    // v0.7.0: scholarship sweep. Each active scholarship's own provider page is read (robots.txt respected; Firecrawl
    // only when a direct read is refused or script-only), kept as gzipped evidence, and deterministic facts are recorded.
    if (mode === "scholarship_read") {
      const items: { scholarship_id: string; url: string; name: string; provider_id: string; url_source?: string; names?: string[] }[] = await rpc("svc_scholarship_read_next", { p_limit: Math.min(Number(body.limit || 20), 40) });
      const tally: Record<string, number> = {}; const applied: unknown[] = [];
      await pool(items, 6, async (it) => {
        let status = "fetch_failed", http: number | null = null, via: string | null = null, html = "", finalUrl = it.url;
        try {
          const u = new URL(it.url);
          if (!robotsAllows(await robotsFor(u), u.pathname + u.search)) status = "robots_disallowed";
          else {
            try {
              const r = await fetch(u, { headers: { "user-agent": UA, accept: "text/html,application/xhtml+xml" }, redirect: "follow", signal: AbortSignal.timeout(20000) });
              http = r.status; finalUrl = r.url || it.url;
              if (r.ok && /html/i.test(r.headers.get("content-type") || "html")) { html = await r.text(); via = "direct" }
            } catch { http = null }
            const thin = html && mainText(html).length < 800;
            if ((!html || thin) && (http === null || [401, 403, 406, 429, 503].includes(http) || thin) && await useFc("sch_scrape", it.provider_id, it.url)) {
              const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: it.url, formats: ["html"], onlyMainContent: false }), signal: AbortSignal.timeout(60000) });
              const d = await r.json().catch(() => ({}));
              if (r.ok && d?.data?.html) { html = d.data.html; via = "firecrawl"; http = d.data?.metadata?.statusCode ?? 200; finalUrl = d.data?.metadata?.sourceURL || it.url }
            }
            if (html && mainText(html).length >= 300) status = "read";
            else if (html) status = "too_thin";
            else if (http === 404 || http === 410) status = "gone";
            else if (http && [401, 403, 406, 429].includes(http)) status = "blocked";
          }
        } catch { status = "fetch_failed" }
        let path: string | null = null, sha: string | null = null, facts: unknown = null;
        // v0.4.0: the page must name the scholarship before anything from it is used
        const hd = status === "read" ? pageHeadings(html) : null;
        const nc = hd ? { ...nameOnPage(it.name, hd.primary, providerTokens(it.names || []), hd.secondary), headings: hd, extractor: SCH_VERSION } : null;
        if (status === "read" && !nc!.ok) { status = "name_mismatch"; facts = { name_check: nc, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), final_url: finalUrl } }
        // a discovered page must be about a scholarship (a research-project page can carry the same title)
        if (status === "read" && it.url_source === "discovered" && !/(scholarship|stipend|bursary|tuition|\baward|\bgrant|\bprize|fee (?:reduction|remission|discount|waiver))/i.test(mainText(html).slice(0, 8000))) {
          status = "name_mismatch"; facts = { name_check: { ...nc, ok: false, basis: "not_a_scholarship_page" }, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), final_url: finalUrl };
        }
        if (status === "read") {
          const t = titleOf(html) + " " + h1Of(html);
          facts = { ...scholarshipFacts(html, t, it.name), page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), final_url: finalUrl, extractor: SCH_VERSION, name_check: nc };
          if (it.url_source === "admitted") { let h = ""; try { h = new URL(it.url).hostname } catch { /* */ } (facts as any).admission = admissionCheck(html, finalUrl, [h, new URL(finalUrl).hostname]) }
          const gz = await gzip(html); sha = await sha256(new TextEncoder().encode(html));
          path = `layer2/AU/scholarships/${it.provider_id}/${it.scholarship_id}/${sha}.html.gz`;
          const up = await c.storage.from("evidence").upload(path, gz, { contentType: "application/gzip", upsert: true });
          if (up.error) { path = null; sha = null }
        }
        const res = await rpc("svc_scholarship_read_record", { p_scholarship_id: it.scholarship_id, p_read_status: status, p_http_status: http, p_fetched_via: via, p_final_url: finalUrl, p_storage_path: path, p_sha256: sha, p_facts: facts });
        if (res?.changes?.length) applied.push({ scholarship_id: it.scholarship_id, changes: res.changes });
        tally[status] = (tally[status] || 0) + 1;
      });
      return j({ ok: true, mode, items: items.length, tally, applied, firecrawlRemainingAboveReserve: fcRemaining, scholarshipFirecrawlLeft: schLeft, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER, scholarshipExtractor: SCH_VERSION });
    }
    // 1 Oct 2026 (Decision 204): course-link search runs here, a bounded number at a time, instead of through the
    // database's outbound queue (pg_net), which sends in rounds of 200 and waits for the slowest call. Each result is
    // recorded through public.svc_course_link_search_record (same pick, bind and title-search rules as before).
    if (mode === "link_search") {
      const items: { course_id: string; provider_id: string; stage: string; query: string }[] =
        await rpc("svc_course_link_search_next", { p_limit: Math.min(Number(body.limit || 40), 120) });
      let searched = 0, found = 0, failed = 0;
      await pool(items, Math.min(Number(body.concurrency || 6), 10), async (it) => {
        if (Date.now() - t0 > BUDGET_MS) { await rpc("svc_course_link_search_record", { p_course_id: it.course_id, p_http: 0, p_urls: [], p_error: "time budget" }); return }
        if (!(await useFc("course_link_search", it.provider_id, it.query))) { await rpc("svc_course_link_search_record", { p_course_id: it.course_id, p_http: 0, p_urls: [], p_error: "credit budget" }); return }
        let http = 0, urls: string[] = [], err: string | null = null;
        try {
          const r = await fetch("https://api.firecrawl.dev/v1/search", { method: "POST", headers: fcHeaders, body: JSON.stringify({ query: it.query, limit: 5 }), signal: AbortSignal.timeout(45000) });
          http = r.status;
          const d = await r.json().catch(() => ({}));
          urls = Array.isArray(d?.data) ? d.data.map((x: { url?: string }) => String(x?.url || "")).filter(Boolean) : [];
          if (!r.ok) err = String(d?.error || `HTTP ${r.status}`);
        } catch (e) { err = e instanceof Error ? e.message : String(e) }
        searched++; if (err) failed++;
        if (await rpc("svc_course_link_search_record", { p_course_id: it.course_id, p_http: http, p_urls: urls, p_error: err }) === "found") found++;
      });
      return j({ ok: true, mode, workerVersion: VERSION, picked: items.length, searched, found, failed, ms: Date.now() - t0 });
    }

    // 1 Oct 2026 (Decision 205): institution-level sources. Search each provider's site for its international fee schedule,
    // English language policy and academic calendar; read each document (PDFs included) as evidence; parse fee rows.
    // Nothing is written to the catalogue here: parsed rows become a proposal a person approves.
    // Decision 227: stored provider documents, parsed again without reading the site (no Firecrawl credit).
    // provider_facts_inspect returns the stored text (or the lines that match "lines") and what the parser makes of it;
    // provider_facts_parse records the parser's proposal for each document.
    if (mode === "provider_facts_inspect" || mode === "provider_facts_parse") {
      const docs: { id: string; provider: string; kind: string; url: string; storage_path: string }[] = await rpc("svc_provider_facts_docs", { p_ids: body.ids || null, p_kind: body.kind || null, p_limit: Math.min(Number(body.limit || 5), 400) });
      const chars = Math.min(Number(body.chars || 6000), 60000), from = Math.max(0, Number(body.offset || 0));
      const out: unknown[] = []; const tally: Record<string, number> = {};
      await pool(docs, 6, async (d) => {
        try {
          const { data, error } = await c.storage.from("evidence").download(d.storage_path); if (error || !data) throw Error(error?.message || "missing");
          const md = await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text();
          const parsed = d.kind === "english_policy" ? englishPolicy(md) : d.kind === "intake_calendar" ? calendarStarts(md) : null;
          if (mode === "provider_facts_parse") {
            if (!parsed) return;
            const r = await rpc("svc_provider_policy_record", { p_source_id: d.id, p_parsed: parsed });
            tally[String(r?.status || "recorded")] = (tally[String(r?.status || "recorded")] || 0) + 1;
            if (body.summary) out.push({ id: d.id, provider: d.provider, kind: d.kind, status: r?.status, style: (parsed as { style?: string }).style, defaults: (parsed as { defaults?: unknown }).defaults, periods: (parsed as { periods?: unknown }).periods });
            return;
          }
          const lines = body.lines ? md.split("\n").filter((l) => new RegExp(String(body.lines), "i").test(l)).map((l) => l.slice(0, Number(body.line_chars || 400))).slice(0, Number(body.max_lines || 120)) : null;
          out.push({ id: d.id, provider: d.provider, kind: d.kind, url: d.url, chars: md.length, ...(lines ? { lines } : { text: md.slice(from, from + chars) }), ...(body.no_parse ? {} : { parsed }) });
        } catch (e) { tally.failed = (tally.failed || 0) + 1; out.push({ id: d.id, url: d.url, error: e instanceof Error ? e.message : String(e) }) }
      });
      return j({ ok: true, mode, workerVersion: WORKER, parser: POLICY_PARSER, docs: docs.length, tally, out });
    }

    if (mode === "provider_facts") {
      const searches: { provider_id: string; kind: string; query: string }[] = await rpc("svc_provider_facts_search_next", { p_limit: Math.min(Number(body.search_limit || 12), 40) });
      let found = 0;
      await pool(searches, 6, async (it) => {
        if (Date.now() - t0 > BUDGET_MS / 2 || !(await useFc("provider_facts_search", it.provider_id, it.query))) { await rpc("svc_provider_facts_search_record", { p_provider_id: it.provider_id, p_kind: it.kind, p_http: 0, p_results: [], p_error: "budget" }); return }
        let http = 0, results: { url: string; title: string }[] = [];
        try {
          const r = await fetch("https://api.firecrawl.dev/v1/search", { method: "POST", headers: fcHeaders, body: JSON.stringify({ query: it.query, limit: 6 }), signal: AbortSignal.timeout(45000) });
          http = r.status; const d = await r.json().catch(() => ({}));
          results = Array.isArray(d?.data) ? d.data.map((x: { url?: string; title?: string }) => ({ url: String(x?.url || ""), title: String(x?.title || "") })).filter((x: { url: string }) => x.url) : [];
        } catch { http = 0 }
        found += Number(await rpc("svc_provider_facts_search_record", { p_provider_id: it.provider_id, p_kind: it.kind, p_http: http, p_results: results, p_error: null }) || 0);
      });
      const docs: { id: string; provider_id: string; kind: string; url: string; country: string; currency: string }[] = await rpc("svc_provider_facts_read_next", { p_limit: Math.min(Number(body.read_limit || 6), 20) });
      const tally: Record<string, number> = {};
      await pool(docs, 4, async (it) => {
        if (Date.now() - t0 > BUDGET_MS || !(await useFc("provider_facts_scrape", it.provider_id, it.url))) {
          await rpc("svc_provider_facts_read_record", { p_id: it.id, p_status: "failed", p_http: null, p_storage_path: null, p_sha256: null, p_mime: null, p_rows: [], p_summary: { error: "budget" } }); return
        }
        try {
          const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: it.url, formats: ["markdown"], onlyMainContent: true }), signal: AbortSignal.timeout(90000) });
          const d = await r.json().catch(() => ({}));
          const md: string = d?.data?.markdown || "";
          const http = Number(d?.data?.metadata?.statusCode ?? r.status);
          const extra = Math.max(0, Number(d?.data?.metadata?.creditsUsed ?? d?.creditsUsed ?? 1) - 1);
          if (extra > 0) await rpc("svc_coverage_usage", { p_units: extra, p_purpose: "provider_facts_scrape", p_provider_id: it.provider_id, p_url: it.url });
          if (!r.ok || md.length < 200) { await rpc("svc_provider_facts_read_record", { p_id: it.id, p_status: "failed", p_http: http, p_storage_path: null, p_sha256: null, p_mime: null, p_rows: [], p_summary: { error: d?.error || "no content", chars: md.length } }); tally.failed = (tally.failed || 0) + 1; return }
          const sha = await sha256(new TextEncoder().encode(md));
          let path: string | null = `layer2/${it.country || "XX"}/provider-facts/${it.provider_id}/${it.id}/${sha}.md.gz`;
          const up = await c.storage.from("evidence").upload(path, await gzip(md), { contentType: "application/gzip", upsert: true });
          if (up.error) path = null;
          const parsed = it.kind === "fee_schedule" ? parseFeeRows(md) : { rows: [], summary: { chars: md.length } };
          const links = it.kind === "fee_schedule" ? feeLinks(md, it.url) : [];
          const res = await rpc("svc_provider_facts_read_record_v2", { p_id: it.id, p_status: "read", p_http: http, p_storage_path: path, p_sha256: path ? sha : null, p_mime: "text/markdown", p_rows: parsed.rows, p_summary: { ...parsed.summary, chars: md.length, title: String(d?.data?.metadata?.title || "").slice(0, 200) }, p_links: links });
          // Decision 227: English policy and academic calendar documents are parsed into a proposal (approved by a person)
          if (it.kind === "english_policy" || it.kind === "intake_calendar") {
            try { await rpc("svc_provider_policy_record", { p_source_id: it.id, p_parsed: it.kind === "english_policy" ? englishPolicy(md) : calendarStarts(md) }); tally.proposals = (tally.proposals || 0) + 1 }
            catch { tally.proposal_failed = (tally.proposal_failed || 0) + 1 }
          }
          tally.linked = (tally.linked || 0) + Number(res?.linked || 0);
          tally[it.kind] = (tally[it.kind] || 0) + 1; tally.fee_rows = (tally.fee_rows || 0) + Number(res?.fee_rows || 0);
        } catch (e) {
          await rpc("svc_provider_facts_read_record", { p_id: it.id, p_status: "failed", p_http: null, p_storage_path: null, p_sha256: null, p_mime: null, p_rows: [], p_summary: { error: e instanceof Error ? e.message : String(e) } });
          tally.failed = (tally.failed || 0) + 1;
        }
      });
      return j({ ok: true, mode, workerVersion: VERSION, searched: searches.length, sources_found: found, read: docs.length, tally, ms: Date.now() - t0 });
    }

    // v0.8.0: scholarship discovery. Phase discover: a provider's own scholarship pages from its site maps (and a
    // scholarships.<domain> subdomain's), one Firecrawl map with search "scholarship" only when the site maps give none;
    // held Study Australia-only scholarships are matched to a page by exact name (address or title). Phase search: one
    // Firecrawl web search per held scholarship still without a page. Phase candidates: unheld pages at Australian
    // universities are read directly and offered to security.scholarship_admit_from_provider_page_v1.
    if (mode === "scholarship_discover") {
      const phase = String(body.phase || "all"), deadline = t0 + 105_000;
      const out: Record<string, unknown> = {};
      if (phase === "all" || phase === "discover") {
        const provs: { provider_id: string; website: string; reason: string; hosts?: string[]; names: string[]; held: { scholarship_id: string; name: string }[] }[] = await rpc("svc_scholarship_discover_next", { p_limit: Math.min(Number(body.limit || 3), 6) });
        const done: unknown[] = [];
        await pool(provs, 3, async (p) => {
          let site: URL;
          try { site = new URL(/^https?:/i.test(p.website) ? p.website : "https://" + p.website) } catch { await rpc("svc_scholarship_discover_record", { p_provider_id: p.provider_id, p_status: "failed", p_site_origin: null, p_method: "none", p_url_count: 0, p_candidates: [], p_matches: [], p_error: "invalid website" }); return }
          try {
            try { const r = await fetch(site, { headers: { "user-agent": UA }, redirect: "follow", signal: AbortSignal.timeout(15000) }); if (r.url) site = new URL(r.url); await r.body?.cancel() } catch { /* keep */ }
            const found = new Map<string, { url: string; title?: string; source: string }>();
            const methods: string[] = []; let total = 0;
            const origins = [site.origin, `https://scholarships.${baseHost(site.hostname)}`, ...(p.hosts || []).map((h) => `https://www.${baseHost(h)}`)].filter((o, i, a) => a.indexOf(o) === i);
            for (const o of origins) {
              if (Date.now() > deadline - 20000) break;
              const sm = await siteMapUrls(o, Math.min(deadline - 15000, Date.now() + (o === site.origin ? 40000 : 12000)), scholarshipPri).catch(() => ({ urls: [] as string[], files: 0 }));
              if (sm.urls.length) methods.push(`sitemap${o === site.origin ? "" : ":" + new URL(o).hostname}(${sm.files})`);
              total += sm.urls.length;
              for (const u of sm.urls) if (keepScholarshipUrl(u, [site.hostname, ...(p.hosts || [])])) found.set(normUrl(u), { url: u, source: "sitemap" });
            }
            if (!found.size) {
              if (await useFc("sch_map", p.provider_id, site.origin)) {
                const r = await fetch("https://api.firecrawl.dev/v2/map", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: site.origin, search: "scholarship", limit: 5000, sitemap: "include", includeSubdomains: true }), signal: AbortSignal.timeout(60000) });
                const d = await r.json().catch(() => ({}));
                if (!r.ok || d?.success === false) methods.push(`map:${r.status}`);
                else {
                  const links = (d.links || d.data?.links || []).map((x: any) => typeof x === "string" ? { url: x } : { url: x.url, title: x.title });
                  methods.push(`map_search(${links.length})`); total += links.length;
                  for (const u of links) if (u.url && keepScholarshipUrl(u.url, [site.hostname, ...(p.hosts || [])])) found.set(normUrl(u.url), { url: u.url, title: u.title, source: "map" });
                }
              } else methods.push("map:budget");
            }
            const cands = [...found.values()].slice(0, 6000);
            const prov = providerTokens(p.names || []);
            const matches = (p.held || []).map((h) => ({ h, m: matchScholarshipPage(h.name, cands, prov) })).filter((x) => x.m);
            // one page for two held scholarships is not a strong match for either
            const byUrl = new Map<string, number>(); for (const x of matches) byUrl.set(normUrl(x.m!.url), (byUrl.get(normUrl(x.m!.url)) || 0) + 1);
            const pm = matches.filter((x) => byUrl.get(normUrl(x.m!.url)) === 1).map((x) => ({ scholarship_id: x.h.scholarship_id, url: x.m!.url, basis: x.m!.basis }));
            const rec = await rpc("svc_scholarship_discover_record", { p_provider_id: p.provider_id, p_status: cands.length ? "mapped" : "empty", p_site_origin: site.origin, p_method: methods.join("+") || "none", p_url_count: total, p_candidates: cands, p_matches: pm, p_error: null });
            done.push({ provider_id: p.provider_id, methods, total, kept: rec?.kept, held: (p.held || []).length, matched: rec?.matched });
          } catch (e) {
            await rpc("svc_scholarship_discover_record", { p_provider_id: p.provider_id, p_status: "failed", p_site_origin: site.origin, p_method: "discover", p_url_count: 0, p_candidates: [], p_matches: [], p_error: e instanceof Error ? e.message : String(e) });
            done.push({ provider_id: p.provider_id, status: "failed", error: e instanceof Error ? e.message : String(e) });
          }
        });
        out.discover = done;
      }
      if ((phase === "all" || phase === "search") && Date.now() < deadline - 45000) {
        const items: { scholarship_id: string; name: string; provider_id: string; site: string; hosts?: string[]; names: string[] }[] = await rpc("svc_scholarship_search_next", { p_limit: Math.min(Number(body.search_limit || 4), 20) });
        const done: unknown[] = [];
        await pool(items, 4, async (it) => {
          let host = ""; try { host = (it.hosts || [])[0] || new URL(/^https?:/i.test(it.site) ? it.site : "https://" + it.site).hostname } catch { /* */ }
          const hosts = [host, it.site, ...(it.hosts || [])].filter(Boolean).map((h) => { try { return new URL(/^https?:/i.test(h) ? h : "https://" + h).hostname } catch { return h } });
          const q = `"${it.name.replace(/"/g, "")}" site:${baseHost(host)}`;
          if (!host || !(await useFc("sch_search", it.provider_id, q))) { await rpc("svc_scholarship_search_record", { p_scholarship_id: it.scholarship_id, p_query: q, p_status: "budget", p_results: [], p_match: {} }); done.push({ scholarship_id: it.scholarship_id, status: "budget" }); return }
          try {
            const r = await fetch("https://api.firecrawl.dev/v2/search", { method: "POST", headers: fcHeaders, body: JSON.stringify({ query: q, limit: 5 }), signal: AbortSignal.timeout(45000) });
            const d = await r.json().catch(() => ({}));
            const res = (d?.data?.web || (Array.isArray(d?.data) ? d.data : [])).map((x: any) => ({ url: String(x.url || ""), title: String(x.title || "") })).filter((x: any) => /^https?:/i.test(x.url));
            const prov = providerTokens(it.names || []);
            const kept = res.map((x: any) => { let ok = false; try { const u = new URL(x.url); ok = onSite(u.hostname, hosts) && !/\.(pdf|docx?|xlsx?)(\?|$)|\/news|\/events?\//i.test(u.pathname) } catch { /* */ } return { ...x, kept: ok } });
            const pool2 = kept.filter((x: any) => x.kept);
            // v0.4.3: only scholarship addresses or scholarship titles (a research-project page can carry the same name)
            const schPool = pool2.filter((x: any) => keepScholarshipUrl(x.url, hosts) || /scholarship|bursary|award|grant|prize|stipend/i.test(x.title || ""));
            let m: { url: string; basis: string } | null = matchScholarshipPage(it.name, schPool, prov);
            if (!m) { const byTitle = schPool.filter((x: any) => nameOnPage(it.name, [x.title], prov).ok && keepScholarshipUrl(x.url, hosts)); if (byTitle.length === 1) m = { url: byTitle[0].url, basis: "search_title" } }
            const rec = await rpc("svc_scholarship_search_record", { p_scholarship_id: it.scholarship_id, p_query: q, p_status: r.ok ? (m ? "matched" : "no_match") : `http_${r.status}`, p_results: kept, p_match: m || {} });
            done.push({ scholarship_id: it.scholarship_id, results: res.length, match: m, matched: rec?.matched ?? false });
          } catch (e) {
            await rpc("svc_scholarship_search_record", { p_scholarship_id: it.scholarship_id, p_query: q, p_status: "failed", p_results: [], p_match: {} });
            done.push({ scholarship_id: it.scholarship_id, status: "failed", error: e instanceof Error ? e.message : String(e) });
          }
        });
        out.search = done;
      }
      if ((phase === "all" || phase === "candidates") && Date.now() < deadline - 30000) {
        const items: { candidate_id: number; url: string; provider_id: string; site: string; hosts?: string[] }[] = await rpc("svc_scholarship_candidate_next", { p_limit: Math.min(Number(body.read_limit || 30), 60) });
        const tally: Record<string, number> = {}; const admitted: unknown[] = [];
        await pool(items, 6, async (it) => {
          if (Date.now() > deadline) { await rpc("svc_scholarship_candidate_record", { p_candidate_id: it.candidate_id, p_read_status: "deferred", p_http_status: null, p_fetched_via: null, p_final_url: null, p_storage_path: null, p_sha256: null, p_facts: null }); return }
          const pg = await readDirect(it.url);
          let via = pg.status === "read" ? "direct" : null;
          // many university sites refuse direct reads (403); Firecrawl then, inside the scholarship cap, keeping a
          // reserve of 800 credits for step 1 (provider pages of held scholarships)
          if (["blocked", "fetch_failed", "too_thin"].includes(pg.status) && schLeft > 800 && await useFc("sch_scrape", it.provider_id, it.url)) {
            try {
              const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: it.url, formats: ["html"], onlyMainContent: false }), signal: AbortSignal.timeout(60000) });
              const d = await r.json().catch(() => ({}));
              if (r.ok && d?.data?.html && mainText(d.data.html).length >= 300) { pg.html = d.data.html; pg.status = "read"; pg.http = d.data?.metadata?.statusCode ?? 200; pg.finalUrl = d.data?.metadata?.sourceURL || it.url; via = "firecrawl" }
            } catch { /* keep the direct result */ }
          }
          let facts: Record<string, unknown> | null = null, path: string | null = null, sha: string | null = null;
          if (pg.status === "read") {
            let host = ""; try { host = new URL(/^https?:/i.test(it.site) ? it.site : "https://" + it.site).hostname } catch { /* */ }
            const adm = admissionCheck(pg.html, pg.finalUrl, [host, ...(it.hosts || [])]);
            facts = { ...scholarshipFacts(pg.html, titleOf(pg.html) + " " + h1Of(pg.html), adm.name || ""), page_title: titleOf(pg.html).slice(0, 200), h1: h1Of(pg.html).slice(0, 200), final_url: pg.finalUrl, extractor: SCH_VERSION, admission: adm };
            if (adm.admit) {
              const gz = await gzip(pg.html); sha = await sha256(new TextEncoder().encode(pg.html));
              path = `layer2/AU/scholarships/${it.provider_id}/candidates/${it.candidate_id}/${sha}.html.gz`;
              const up = await c.storage.from("evidence").upload(path, gz, { contentType: "application/gzip", upsert: true });
              if (up.error) { path = null; sha = null; (facts.admission as any).admit = false; (facts.admission as any).reasons = ["evidence_upload_failed"] }
            }
          }
          const res = await rpc("svc_scholarship_candidate_record", { p_candidate_id: it.candidate_id, p_read_status: pg.status, p_http_status: pg.http, p_fetched_via: via, p_final_url: pg.finalUrl, p_storage_path: path, p_sha256: sha, p_facts: facts });
          const k = res?.admitted ? "admitted" : pg.status === "read" ? (res?.reason ? "read:" + res.reason : "read:rejected") : pg.status;
          tally[k] = (tally[k] || 0) + 1;
          if (res?.admitted) admitted.push({ candidate_id: it.candidate_id, scholarship_id: res.scholarship_id, apply: res.apply?.changes });
        });
        out.candidates = { items: items.length, tally, admitted };
      }
      return j({ ok: true, mode, phase, ...out, firecrawlRemainingAboveReserve: fcRemaining, scholarshipFirecrawlLeft: schLeft, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER, scholarshipExtractor: SCH_VERSION });
    }
    // read only: headings, name check, admission rules and page text of stored evidence (or a live page) for hand checks
    // v0.9.0 (Decision 211): eligibility criteria and award scope from stored scholarship pages (no fetch). Only the
    // two new facts are added; the page's other facts and course links stay as they are.
    if (mode === "scholarship_reextract") {
      const rows: { scholarship_id: string; storage_path: string }[] = await rpc("svc_scholarship_reextract_next", { p_limit: Math.min(Number(body.limit || 100), 300), p_version: SCH_VERSION });
      let done = 0, failed = 0; const changes: Record<string, number> = {};
      await pool(rows, 10, async (r) => {
        try {
          const { data, error } = await c.storage.from("evidence").download(r.storage_path);
          if (error || !data) throw Error(error?.message || "missing");
          const html = await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text();
          const text = mainText(html);
          const res = await rpc("svc_scholarship_reextract_record", { p_scholarship_id: r.scholarship_id, p_facts: { criteria: scholarshipCriteria(text), award_scope: awardScope(text), criteria_extractor: SCH_VERSION } });
          for (const k of (res?.changes || []) as string[]) changes[k] = (changes[k] || 0) + 1;
          done++;
        } catch { failed++ }
      });
      return j({ ok: true, mode, rows: rows.length, done, failed, changes, ms: Date.now() - t0, workerVersion: VERSION, scholarshipExtractor: SCH_VERSION });
    }
    if (mode === "scholarship_inspect") {
      const chars = Math.min(Number(body.chars || 2500), 8000);
      const paths = await rpc("svc_scholarship_inspect_paths", { p_scholarship_ids: body.scholarship_ids || [], p_candidate_ids: body.candidate_ids || [] });
      const rows: any[] = [...(paths?.scholarships || []), ...(paths?.candidates || []), ...((body.urls || []) as string[]).map((u) => ({ url: u, live: true, name: body.name || "" }))];
      const out: unknown[] = [];
      await pool(rows, 4, async (r) => {
        try {
          let html = "";
          if (r.live) { const pg = await readDirect(r.url); html = pg.html; r.status = pg.status; r.url = pg.finalUrl }
          else if (r.storage_path) { const { data, error } = await c.storage.from("evidence").download(r.storage_path); if (error || !data) throw Error(error?.message || "missing"); html = await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text() }
          if (!html) { out.push({ ...r, error: "no page" }); return }
          const hd = pageHeadings(html), text = mainText(html);
          let host = ""; try { host = new URL(r.url).hostname } catch { /* */ }
          out.push({ scholarship_id: r.scholarship_id, candidate_id: r.candidate_id, url: r.url, name: r.name, headings: hd,
            name_check: r.name ? nameOnPage(r.name, hd.primary, providerTokens(r.names || []), hd.secondary) : null,
            admission: admissionCheck(html, r.url, host), facts: scholarshipFacts(html, titleOf(html) + " " + h1Of(html), r.name || ""), text: text.slice(0, chars) });
        } catch (e) { out.push({ ...r, error: e instanceof Error ? e.message : String(e) }) }
      });
      return j({ ok: true, mode, pages: out, ms: Date.now() - t0, workerVersion: VERSION, scholarshipExtractor: SCH_VERSION });
    }
    // v0.10.0 (2 Oct 2026, map-first link matcher): for a course with no verified page, one pinned model picks the
    // course's own page from the 25 closest addresses in its university's stored site map, or none. The choice must be
    // one of those addresses (checked again in the database); the page is then read by mode read and accepted only under
    // the identity rule. Nothing is admitted here. No Firecrawl credit is used.
    if (mode === "ai_match") {
      // the account key: the Edge secret when set, otherwise the governed OpenRouter credential (vault) of the pinned
      // model's own Layer 3 profile, as layer3-model-routing resolves it
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) {
        const prof = await rpc("layer3_routing_profile_service", { p_code: AI_MATCH_PROFILE });
        if (prof?.model_identifier !== AI_MATCH_MODEL) return j({ ok: false, mode, error: "pinned model profile not found", workerVersion: VERSION }, 503);
        const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof.id });
        key = typeof data === "string" ? data : "";
      }
      if (!key) return j({ ok: false, mode, error: "OpenRouter credential unavailable", workerVersion: VERSION }, 503);
      const items: { id: number; title: string; code: string | null; level: string | null; provider: string; country: string; candidates: { url: string; title: string }[] }[] =
        await rpc("svc_coverage_ai_match_next", { p_limit: Math.min(Number(body.limit || 40), 80) });
      const tally: Record<string, number> = {}; let cost = 0;
      await pool(items, Math.min(Number(body.concurrency || 8), 12), async (it) => {
        if (Date.now() - t0 > BUDGET_MS) { await rpc("svc_coverage_ai_match_record", { p_id: it.id, p_url: null, p_answer: null, p_model: AI_MATCH_MODEL, p_cost: 0, p_error: "time budget" }); return }
        let url: string | null = null, answer: unknown = null, err: string | null = null, c1 = 0;
        try {
          const r = await fetch("https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
            body: JSON.stringify(aiMatchRequest(it)), signal: AbortSignal.timeout(45000) });
          const d = await r.json().catch(() => ({}));
          if (!r.ok) throw Error(`HTTP ${r.status}: ${JSON.stringify(d?.error || d).slice(0, 160)}`);
          if (d?.model && d.model !== AI_MATCH_MODEL) throw Error(`returned model ${d.model}`);
          c1 = Number(d?.usage?.cost || 0);
          const a = JSON.parse(String(d?.choices?.[0]?.message?.content || "{}"));
          const n = Number(a?.choice);
          answer = { choice: n, reason: String(a?.reason || "").slice(0, 400) };
          if (Number.isInteger(n) && n >= 1 && n <= it.candidates.length) url = it.candidates[n - 1].url;
        } catch (e) { err = e instanceof Error ? e.message : String(e) }
        cost += c1;
        const st = await rpc("svc_coverage_ai_match_record", { p_id: it.id, p_url: url, p_answer: answer, p_model: AI_MATCH_MODEL, p_cost: c1, p_error: err });
        tally[st] = (tally[st] || 0) + 1;
      });
      return j({ ok: true, mode, items: items.length, tally, cost_usd: cost, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    if (mode === "read") {
      const items: { course_id: string; provider_id: string; url: string; title: string; code: string; status: string; priority?: boolean; manual?: boolean; country?: string }[] = await rpc("svc_coverage_read_next", { p_limit: Math.min(Number(body.limit || 24), 60) });
      const tally: Record<string, number> = {};
      await pool(items, 8, async (it) => {
        if (Date.now() - t0 > BUDGET_MS) { await rpc("svc_coverage_read_record", { p_course_id: it.course_id, p_read_status: "deferred", p_http_status: null, p_fetched_via: null, p_identity_basis: null, p_storage_path: null, p_sha256: null, p_candidates: null }); return }
        let status = "fetch_failed", http: number | null = null, via: string | null = null, html = "", finalUrl = it.url;
        try {
          const u = new URL(it.url);
          if (!robotsAllows(await robotsFor(u), u.pathname + u.search)) status = "robots_disallowed";
          else {
            try {
              const r = await fetch(u, { headers: { "user-agent": UA, accept: "text/html,application/xhtml+xml" }, redirect: "follow", signal: AbortSignal.timeout(20000) });
              http = r.status; finalUrl = r.url || it.url;
              if (r.ok && /html/i.test(r.headers.get("content-type") || "html")) { html = await r.text(); via = "direct" }
            } catch { http = null }
            const thin = html && htmlToText(html).length < 1500;
            if ((!html || thin) && (it.status === "bound" || it.priority === true) && (http === null || [401, 403, 406, 429, 503].includes(http) || thin) && await useFc("scrape", it.provider_id, it.url)) {
              const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: it.url, formats: ["html"], onlyMainContent: false }), signal: AbortSignal.timeout(60000) });
              const d = await r.json().catch(() => ({}));
              if (r.ok && d?.data?.html) { html = d.data.html; via = "firecrawl"; http = d.data?.metadata?.statusCode ?? 200; finalUrl = d.data?.metadata?.sourceURL || it.url }
            }
            if (html && via === "direct" && htmlToText(html).length < 1500) status = "needs_render";
            else if (html) status = "read";
            else if (http && [401, 403, 406, 429].includes(http)) status = "blocked";
          }
        } catch { status = "fetch_failed" }
        let identityBasis: string | null = null, path: string | null = null, sha: string | null = null, candidates: unknown = null;
        if (status === "read") {
          let text = htmlToText(html);
          // v0.6.3: a page a person entered on the course page is the course's page (Decision 179).
          identityBasis = identity(html, text, it.title, it.code, it.status === "ambiguous", it.country || "") || (it.manual === true ? "manual" : null);
          // v0.6.2: a priority page read directly without the code may be a script-rendered handbook (UNSW, Melbourne):
          // render it once through Firecrawl before calling it a mismatch.
          if (!identityBasis && via === "direct" && it.priority === true && await useFc("scrape", it.provider_id, it.url)) {
            const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: it.url, formats: ["html"], onlyMainContent: false }), signal: AbortSignal.timeout(60000) }).catch(() => null);
            const d = r ? await r.json().catch(() => ({})) : {};
            if (r?.ok && d?.data?.html) {
              html = d.data.html; via = "firecrawl"; http = d.data?.metadata?.statusCode ?? http; finalUrl = d.data?.metadata?.sourceURL || finalUrl;
              text = htmlToText(html); identityBasis = identity(html, text, it.title, it.code, it.status === "ambiguous", it.country || "");
            }
          }
          // Decision 235: a field + award match on an archived calendar page (a year in the address more than a year old) is not used
          if (identityBasis === "field_award" && staleCalendarUrl(finalUrl)) identityBasis = null;
          if (!identityBasis) status = "identity_mismatch";
          const gz = await gzip(html); sha = await sha256(new TextEncoder().encode(html));
          path = `layer2/${["NZ", "CA"].includes(it.country) ? it.country : "AU"}/coverage/${it.provider_id}/${it.course_id}/${sha}.html.gz`;
          const up = await c.storage.from("evidence").upload(path, gz, { contentType: "application/gzip", upsert: true });
          if (up.error) { path = null; sha = null }
          candidates = identityBasis ? { final_url: finalUrl, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), fee: fee(text, currencyFor(it.country)), english: english(text), intakes: intakes(text), intake_context: intakeEvidence(text), extractor: VERSION }
                                     : { final_url: finalUrl, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200) };
        }
        await rpc("svc_coverage_read_record", { p_course_id: it.course_id, p_read_status: status, p_http_status: http, p_fetched_via: via, p_identity_basis: identityBasis, p_storage_path: path, p_sha256: sha, p_candidates: candidates });
        tally[status] = (tally[status] || 0) + 1;
      });
      return j({ ok: true, mode, items: items.length, tally, firecrawlRemainingAboveReserve: fcRemaining, ms: Date.now() - t0, workerVersion: VERSION });
    }
    return j({ ok: false, error: "supported modes: discover, read, ai_match, reidentify, directory_capture, id_qualify, openrouter_key, reference_capture, site_hint_verify, find_site, reextract, tuition_handoff, link_search, provider_facts, provider_facts_inspect, provider_facts_parse, scholarship_read, scholarship_discover, scholarship_reextract, scholarship_inspect", workerVersion: VERSION }, 422);
  } catch (e) {
    return j({ ok: false, error: e instanceof Error ? e.message : String(e), workerVersion: VERSION }, 500);
  }
});
