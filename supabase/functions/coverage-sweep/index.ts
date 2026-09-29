import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { english, fee, h1Of, htmlToText, identity, intakeEvidence, intakes, keepUrl, robotsAllows, titleOf } from "./extract.ts";

// CF-247 complete coverage sweep (Platform Admin direction 29 Sep 2026). Nonce-only. Nothing is written to the
// catalogue: discovery lists a provider's course-like pages, reading keeps each bound course page as evidence and
// records tuition, English and intake candidates for a separately approved admission rule.
//   mode discover: Firecrawl map per provider website (1 credit per call), inside the monthly budget guard.
//   mode read:     direct fetch (robots.txt respected); Firecrawl scrape only when the site refuses or the page is
//                  script-only, inside the budget guard; identity = CRICOS course code on the page or exact title.
const VERSION = "coverage-sweep-v0.5.4";
// v0.5.2: discovery drops requirement, scholarship and applying pages (pilot: RMIT inherent-requirements pages).
// v0.5.1: PTE/TOEFL only when stated as overall or directly after the test name.
// v0.5.0: English overall only when stated as overall or in a score table; minimum band after the overall; fee basis
// total/annual from the amount's own wording ("(2027 total)", "total indicative fee"); mode reextract re-runs the
// extractor over stored pages read by an older version (no fetch).
// v0.4.0: mode find_site - providers with no website: web search (Firecrawl, 2 credits), accepted only when the
// home page prints the provider's CRICOS provider code; directories and registers skipped.
// v0.3.2: a script-only page read directly while the Firecrawl reserve is reached is "needs_render" (retried after the
// budget resets), never an identity mismatch.
// v0.3.1: Firecrawl fallback only for bound pages; ambiguous pages are read directly only (low yield).
// v0.3.0: ambiguous course pages are read too and accepted only with the CRICOS course code on the page; month
// names in intakes must be capitalised.
// v0.2.0: discovery reads the site's own XML site maps first (free), from the final address after redirects; Firecrawl
// map runs when the site maps give fewer course pages than 60% of the provider's courses, and a second map focused on
// "course" only when still short (at most 2 credits per provider). Binding runs separately (cron coverage-bind).
const UA = "Mozilla/5.0 (compatible; CourseFinder-Pilot/coverage-0.1; +https://coursefinder-pilot.techm.workers.dev)";
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
async function siteMapUrls(origin: string, deadline: number) {
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
      const pri = (u: string) => /course|program|study|handbook|degree|qualification/i.test(u) ? 0 : /page|post/i.test(u) ? 1 : 2;
      queue.push(...locs.sort((a, b) => pri(a) - pri(b)));
    } else for (const l of locs) urls.add(l);
  }
  return { urls: [...urls], files };
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
    const useFc = async (purpose: string, providerId: string | null, url: string) => {
      if (!fc?.secret || fcRemaining < 1) return false;
      const units = purpose === "search" ? 2 : 1; if (fcRemaining < units) return false;
      fcRemaining -= units; await rpc("svc_coverage_usage", { p_units: units, p_purpose: purpose, p_provider_id: providerId, p_url: url }); return true;
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


    if (mode === "reextract") {
      const rows: { course_id: string; storage_path: string; title: string; code: string; status: string; url: string }[] = await rpc("svc_coverage_reextract_next", { p_limit: Math.min(Number(body.limit || 100), 200), p_version: VERSION });
      let done = 0, failed = 0;
      await pool(rows, 10, async (r) => {
        try {
          const { data, error } = await c.storage.from("evidence").download(r.storage_path);
          if (error || !data) throw Error(error?.message || "missing");
          const html = await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text();
          const text = htmlToText(html);
          const cand = { final_url: r.url, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), fee: fee(text), english: english(text), intakes: intakes(text), intake_context: intakeEvidence(text), extractor: VERSION };
          await rpc("svc_coverage_candidates_update", { p_course_id: r.course_id, p_candidates: cand }); done++;
        } catch { failed++ }
      });
      return j({ ok: true, mode, rows: rows.length, done, failed, ms: Date.now() - t0, workerVersion: VERSION });
    }
    if (mode === "find_site") {
      const provs: { provider_id: string; name: string; trading: string | null; cricos: string }[] = await rpc("svc_coverage_site_next", { p_limit: Math.min(Number(body.limit || 5), 10) });
      const out: unknown[] = [];
      const SKIP = /(cricos\.education\.gov\.au|education\.gov\.au|studyaustralia|studyinaustralia|hotcourses|idp\.com|studyin|linkedin|facebook|instagram|youtube|twitter|x\.com|yellowpages|abr\.business|asic\.gov|training\.gov\.au|myskills|seek\.com|indeed|glassdoor|wikipedia|google\.|bing\.|yelp|truelocal|hotfrog|startlocal|opencorporates|dnb\.com|zoominfo|asqa\.gov|teqsa\.gov|studiesinaustralia|educations\.com|coursefinder|topuniversities|timeshighereducation)/i;
      await pool(provs, 3, async (p) => {
        const code = String(p.cricos || "").toUpperCase();
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
    if (mode === "read") {
      const items: { course_id: string; provider_id: string; url: string; title: string; code: string; status: string }[] = await rpc("svc_coverage_read_next", { p_limit: Math.min(Number(body.limit || 24), 60) });
      const robots = new Map<string, Promise<string>>();
      const robotsFor = (u: URL) => { if (!robots.has(u.origin)) robots.set(u.origin, fetch(u.origin + "/robots.txt", { headers: { "user-agent": UA }, signal: AbortSignal.timeout(8000) }).then((r) => r.ok ? r.text() : "").catch(() => "")); return robots.get(u.origin)! };
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
            if ((!html || thin) && it.status === "bound" && (http === null || [401, 403, 406, 429, 503].includes(http) || thin) && await useFc("scrape", it.provider_id, it.url)) {
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
          const text = htmlToText(html);
          identityBasis = identity(html, text, it.title, it.code, it.status === "ambiguous");
          if (!identityBasis) status = "identity_mismatch";
          const gz = await gzip(html); sha = await sha256(new TextEncoder().encode(html));
          path = `layer2/AU/coverage/${it.provider_id}/${it.course_id}/${sha}.html.gz`;
          const up = await c.storage.from("evidence").upload(path, gz, { contentType: "application/gzip", upsert: true });
          if (up.error) { path = null; sha = null }
          candidates = identityBasis ? { final_url: finalUrl, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), fee: fee(text), english: english(text), intakes: intakes(text), intake_context: intakeEvidence(text), extractor: VERSION }
                                     : { final_url: finalUrl, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200) };
        }
        await rpc("svc_coverage_read_record", { p_course_id: it.course_id, p_read_status: status, p_http_status: http, p_fetched_via: via, p_identity_basis: identityBasis, p_storage_path: path, p_sha256: sha, p_candidates: candidates });
        tally[status] = (tally[status] || 0) + 1;
      });
      return j({ ok: true, mode, items: items.length, tally, firecrawlRemainingAboveReserve: fcRemaining, ms: Date.now() - t0, workerVersion: VERSION });
    }
    return j({ ok: false, error: "supported modes: discover, read, find_site, reextract", workerVersion: VERSION }, 422);
  } catch (e) {
    return j({ ok: false, error: e instanceof Error ? e.message : String(e), workerVersion: VERSION }, 500);
  }
});
