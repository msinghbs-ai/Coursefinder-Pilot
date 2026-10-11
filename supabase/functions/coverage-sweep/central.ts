// v0.19.0 (11 Oct 2026, Platform Admin Feature 4): central pages found automatically. A Firecrawl map of the provider's own
// site lists its addresses; these fixed rules pick the likeliest key-dates, international-fee and English-requirements pages.
// They are only suggestions: a person attaches one, and an attached page waits for approval in Layer 4 › Attributes.
export type CentralKind = "intake_calendar" | "fee_schedule" | "english_policy";
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
};
const NOISE = /\/(news|events?|blog|stories|media|staff|people|profiles?|search|login|signin|tags?|category|careers?|jobs|research|alumni|giving|donate|library|shop|cart|wp-admin|feed)(\/|$)|\.(jpe?g|png|gif|svg|zip|docx?|xlsx?|pptx?)$|[?&](page|s|q)=/;
const INTERNATIONAL = /international|overseas|\bintl\b/;

function hostOk(u: URL, siteHost: string): boolean {
  const h = u.hostname.toLowerCase().replace(/^www\./, ""), s = siteHost.toLowerCase().replace(/^www\./, "");
  return h === s || h.endsWith("." + s) || s.endsWith("." + h);
}

export function centralCandidates(links: { url: string; title?: string | null }[], siteHost: string, perKind = 3): CentralCandidate[] {
  const best: Record<string, CentralCandidate[]> = { intake_calendar: [], fee_schedule: [], english_policy: [] };
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
      let score = r.strong.test(path) ? 6 : r.strong.test(title) ? 4 : (r.weak && (r.weak.test(path) || r.weak.test(title))) ? 1.5 : 0;
      if (!score) continue;
      if (kind !== "intake_calendar" && INTERNATIONAL.test(path + " " + title)) score += 2;
      if (/\.pdf$/.test(path)) score += kind === "fee_schedule" ? 1 : -0.5;
      score += Math.max(0, 5 - depth) * 0.2; // a short address is usually the main page for the topic
      best[kind].push({ kind, url: l.url, title: l.title ?? null, score: Math.round(score * 10) / 10, why: r.why });
    }
  }
  return (Object.keys(best) as CentralKind[]).flatMap((k) => best[k].sort((a, b) => b.score - a.score || a.url.length - b.url.length).slice(0, perKind));
}
