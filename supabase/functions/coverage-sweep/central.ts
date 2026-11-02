// v0.19.0 (11 Oct 2026, Platform Admin Feature 4): central pages found automatically. A Firecrawl map of the provider's own
// site lists its addresses; these fixed rules pick the likeliest key-dates, international-fee and English-requirements pages.
// They are only suggestions: a person attaches one, and an attached page waits for approval in Layer 4 › Attributes.
// v0.47.0 (CF-247 Track C, entry requirements step A): page type entry_requirements (a provider's academic entry minimums by country of
// prior education; Part 1 address and link-text patterns). It is suggested from the whole-site map only: no extra targeted map is asked for
// it (weakKinds leaves it out), so central_find spends no more credits. The entry matrix reader attaches the suggestions while it is on.
// v0.56.0 (CF-247 P1 provider descriptions, Platform Admin 2 Nov 2026 10:28): page type about_page (the provider's own About, Overview or
// institutional profile page), suggested from the whole-site map only (no extra targeted map, so no new central_find spend). The provider
// description reader takes the suggestions itself (public.svc_provider_description_next); they are not provider-facts sources.
export type CentralKind = "intake_calendar" | "fee_schedule" | "english_policy" | "entry_requirements" | "about_page";
export type CentralCandidate = { kind: CentralKind; url: string; title: string | null; score: number; why: string };

const RULES: Record<CentralKind, { strong: RegExp; weak?: RegExp; why: string }> = {
  intake_calendar: {
    strong: /(key|important|term|semester|trimester|intake|census)[-_ ]?dates?|academic[-_ ]?(calendar|year|dates)|study[-_ ]?periods?|teaching[-_ ]?periods?|course[-_ ]?dates|start[-_ ]?dates/,
    weak: /\bintakes?\b|calendar|when[-_ ]?to[-_ ]?start/,
    why: "key dates",
  },
  fee_schedule: {
    strong: /international[-_ ]?(student[-_ ]?)?(tuition[-_ ]?)?fees?|fees?[-_ ]?(for[-_ ]?)?international|tuition[-_ ]?fees?|fee[-_ ]?schedule|indicative[-_ ]?fees?|course[-_ ]?fees?|fees?[-_ ]?(and|&)[-_ ]?charges/,
    weak: /\bfees?\b|tuition|costs?/,
    why: "fees",
  },
  english_policy: {
    strong: /english[-_ ]?(language[-_ ]?)?(requirements?|proficiency|entry|test|admission)|\bielts\b|language[-_ ]?requirements?/,
    weak: /\benglish\b/,
    why: "English requirements",
  },
  entry_requirements: {
    strong: /country[-_ ]?equivalen|academic[-_ ]?(equivalen|entry[-_ ]?requirements?|requirements)|international[-_ ]?(and[-_ ]?overseas[-_ ]?)?qualifications|overseas[-_ ]?qualifications|qualifications?[-_ ]?(by[-_ ]?country|equivalen)|admission[-_ ]?by[-_ ]?country|entry[-_ ]?requirements?[-_ ]?(by[-_ ]?country|for[-_ ]?international)|international[-_ ]?(academic[-_ ]?)?entry[-_ ]?requirements?|minimum[-_ ]?entry[-_ ]?score/,
    weak: /entry[-_ ]?requirements?/,
    why: "entry requirements",
  },
  about_page: {
    strong: /^\/(about|about[-_ ]?us|about[-_ ]?(the[-_ ]?)?(university|uni|college|institute)|overview|our[-_ ]?(university|story)|the[-_ ]?university|who[-_ ]?we[-_ ]?are|(university|institutional)[-_ ]?profile|at[-_ ]?a[-_ ]?glance|facts[-_ ]?and[-_ ]?figures)(\/(overview|about[-_ ]?us|who[-_ ]?we[-_ ]?are)?)?$/,
    weak: /^about\b|\babout (us|the university)\b/,
    why: "about the provider",
  },
};
const NOISE = /\/(news|events?|blog|stories|media|staff|people|profiles?|search|login|signin|tags?|category|careers?|jobs|research|alumni|giving|donate|library|shop|cart|wp-admin|feed|residence|housing|accommodation|insurance|medical|parking|workshops?|pubs|publications)(\/|$)|refund|extension|request[-_ ]?form|meals?|events[-_ ]?calendar|\.(jpe?g|png|gif|svg|zip|docx?|xlsx?|pptx?)$|[?&](page|s|q)=/;
const INTERNATIONAL = /international|overseas|\bintl\b/;

function hostOk(u: URL, siteHost: string): boolean {
  const h = u.hostname.toLowerCase().replace(/^www\./, ""), s = siteHost.toLowerCase().replace(/^www\./, "");
  return h === s || h.endsWith("." + s) || s.endsWith("." + h);
}

export function centralCandidates(links: { url: string; title?: string | null }[], siteHost: string, perKind = 3): CentralCandidate[] {
  const best: Record<string, CentralCandidate[]> = { intake_calendar: [], fee_schedule: [], english_policy: [], entry_requirements: [], about_page: [] };
  const seen = new Set<string>();
  for (const l of links) {
    let u: URL; try { u = new URL(l.url) } catch { continue }
    if (!/^https?:$/.test(u.protocol) || !hostOk(u, siteHost)) continue;
    const key = (u.hostname.replace(/^www\./, "") + u.pathname).toLowerCase().replace(/\/$/, "");
    if (seen.has(key)) continue; seen.add(key);
    const path = decodeURIComponent(u.pathname).toLowerCase(), title = String(l.title || "").toLowerCase();
    if (NOISE.test(path + u.search.toLowerCase())) continue;
    const depth = path.split("/").filter(Boolean).length;
    for (const kind of Object.keys(RULES) as CentralKind[]) {
      const r = RULES[kind];
      // an English language course (General English, ELICOS, IELTS preparation) is not the English requirements page
      if (kind === "english_policy" && /\/(courses?|programs?)\/|general[-_ ]?english|elicos|tesol|ielts[-_ ]?prep|english[-_ ]?(course|class|learning)/.test(path)) continue;
      // an English-language requirements page is the English rule, not the academic entry matrix
      if (kind === "entry_requirements" && /english|ielts|language[-_ ]?requirements?/.test(path + " " + title)) continue;
      let score = r.strong.test(path) ? 6 : r.strong.test(title) ? 4 : (r.weak && (r.weak.test(path) || r.weak.test(title))) ? 1.5 : 0;
      // a top-level fees or tuition page (slc.edu.au/fees, provider.edu.au/tuition-fees) is the fee schedule of a small provider
      if (kind === "fee_schedule" && depth <= 2 && /^\/(fees?|tuition)([-_][a-z-]+)?(\/|$)/.test(path)) score = Math.max(score, 4.5);
      if (!score) continue;
      if (kind !== "intake_calendar" && kind !== "about_page" && INTERNATIONAL.test(path + " " + title)) score += 2;
      if (/\.pdf$/.test(path)) score += kind === "fee_schedule" ? 1 : -0.5;
      score += Math.max(0, 5 - depth) * 0.2; // a short address is usually the main page for the topic
      best[kind].push({ kind, url: l.url, title: l.title ?? null, score: Math.round(score * 10) / 10, why: r.why });
    }
  }
  // weak matches (a word in passing) are not suggested
  return (Object.keys(best) as CentralKind[]).flatMap((k) => best[k].filter((c) => c.score >= 3).sort((a, b) => b.score - a.score || a.url.length - b.url.length).slice(0, perKind));
}

// What to ask a targeted map for when the whole-site map found no strong page of a kind (large sites list only part of themselves).
export const CENTRAL_SEARCH: Record<CentralKind, string> = { intake_calendar: "key dates academic calendar", fee_schedule: "international student tuition fees", english_policy: "english language requirements", entry_requirements: "international entry requirements by country", about_page: "about the university" };
export function weakKinds(found: CentralCandidate[]): CentralKind[] {
  return (Object.keys(RULES) as CentralKind[]).filter((k) => k !== "about_page").filter((k) => k !== "entry_requirements" && !found.some((c) => c.kind === k && c.score >= 5));
}
