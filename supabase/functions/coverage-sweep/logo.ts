// Logo finder (CF-247, 15 Oct 2026, Platform Admin: "make it background Job to find and attached"). Reads a provider's own home page and
// picks the site's logo: an image in the page header that is named a logo, the logo the page declares (schema.org), an SVG icon, then the
// large touch icon. Pure functions only: the worker fetches, stores and records.

export type LogoCandidate = { url: string; method: string; score: number };

const attr = (tag: string, name: string) => {
  const m = tag.match(new RegExp(`\\s${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`, "i"));
  return m ? (m[1] ?? m[2] ?? m[3] ?? "").trim() : "";
};
const decode = (s: string) => s.replace(/&amp;/g, "&").replace(/&#x2F;/gi, "/").replace(/&#47;/g, "/").replace(/&quot;/g, '"');
// images that sit next to the provider's logo but are someone else's: regulators, rankings, awards, partners, social networks
const NOT_OURS = /cricos|teqsa|asqa|nzqa|qs[-_ ]?(star|rank)|times[-_ ]?higher|ranking|award|accredit|partner|sponsor|member|badge|flag|facebook|twitter|linkedin|instagram|youtube|tiktok|wechat|weibo|whatsapp|google|apple[-_]?store|app[-_]?store|play[-_]?store|payment|visa|mastercard|cookie|chat|avatar|banner|hero|slide|campus[-_ ]?photo|placeholder|spinner|loading|icon-?(search|menu|close)/i;

function resolve(raw: string, base: string): string | null {
  const v = decode(raw).trim();
  if (!v || v.startsWith("data:") || v.startsWith("javascript:")) return null;
  try { const u = new URL(v, base); return u.protocol === "https:" || u.protocol === "http:" ? u.href.replace(/^http:/, "https:") : null } catch { return null }
}

export function logoCandidates(html: string, base: string, name = ""): LogoCandidate[] {
  const out = new Map<string, LogoCandidate>();
  const add = (raw: string, method: string, score: number) => {
    const u = resolve(raw, base); if (!u) return;
    if (NOT_OURS.test(u.replace(/^https:\/\/[^/]+/, ""))) return;
    const prev = out.get(u); if (!prev || prev.score < score) out.set(u, { url: u, method, score });
  };
  const head = html.slice(0, Math.max(html.search(/<\/header>/i), 0) || Math.floor(html.length * 0.3));
  const nameWords = name.toLowerCase().split(/[^a-z]+/).filter((w) => w.length > 3 && !/university|college|institute|school|technology|limited|australia|canada|zealand/.test(w));
  // 1. images named a logo: in the header first
  for (const m of html.matchAll(/<img\b[^>]*>/gi)) {
    const tag = m[0], idx = m.index ?? 0;
    const src = attr(tag, "src") || attr(tag, "data-src") || (attr(tag, "srcset").split(",").pop() || "").trim().split(/\s+/)[0];
    if (!src) continue;
    const label = `${attr(tag, "alt")} ${attr(tag, "class")} ${attr(tag, "id")} ${attr(tag, "title")}`;
    // the element around the image (its link or wrapper) often carries the "logo" name
    const before = html.slice(Math.max(0, idx - 300), idx);
    const wrapper = (before.match(/<(a|div|span|figure|picture)\b[^>]*>[^<]*$/i)?.[0] || before.slice(-200));
    // v0.25.1: the file name (not its folder: "/new-brand/homepage/campus.jpeg" is a photo) or the image's own label says logo
    const file = (src.split(/[?#]/)[0].split("/").pop() || "").toLowerCase();
    const isLogo = /logo|wordmark|crest|emblem/.test(file) || /logo|brand|crest|wordmark/i.test(label) || /class\s*=\s*["'][^"']*(logo|brand)/i.test(wrapper);
    if (!isLogo || NOT_OURS.test(label) || NOT_OURS.test(file)) continue;
    const inHeader = idx < head.length;
    const named = nameWords.some((w) => (label + " " + src).toLowerCase().includes(w));
    const svg = /\.svg$/.test(file);
    const photo = /\.jpe?g$/.test(file) || /photo|campus|student|homepage/.test(file);  // logos are rarely JPEG; photos often are
    const knockout = /white|reverse|inverse|negative|knockout|light/.test(file);         // drawn for dark backgrounds: invisible on white
    add(src, inHeader ? "header_logo" : "page_logo", (inHeader ? 60 : 30) + (named ? 15 : 0) + (svg ? 5 : 0) + (/footer/i.test(label) ? -20 : 0) + (photo ? -45 : 0) + (knockout ? -50 : 0));
  }
  // inline SVG logos have no address: skipped (the next candidates usually exist)
  // 2. the logo the page declares (schema.org Organization, CollegeOrUniversity)
  for (const m of html.matchAll(/<script\b[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    for (const l of m[1].matchAll(/"logo"\s*:\s*(?:"([^"]+)"|\{[^}]*?"(?:url|contentUrl)"\s*:\s*"([^"]+)")/g)) add(l[1] || l[2], "declared_logo", 55);
  }
  for (const m of html.matchAll(/<meta\b[^>]*>/gi)) {
    const p = (attr(m[0], "property") || attr(m[0], "itemprop") || attr(m[0], "name")).toLowerCase();
    if (p === "og:logo" || p === "logo") add(attr(m[0], "content"), "declared_logo", 55);
  }
  // 3. icons: an SVG icon, then the large touch icon (square crests and marks)
  for (const m of html.matchAll(/<link\b[^>]*>/gi)) {
    const rel = attr(m[0], "rel").toLowerCase(), href = attr(m[0], "href"), sizes = attr(m[0], "sizes"), type = attr(m[0], "type");
    if (!href) continue;
    if (/(^|\s)icon(\s|$)/.test(rel) && (/svg/i.test(type) || /\.svg(\?|$)/i.test(href))) add(href, "svg_icon", 25);
    else if (/mask-icon/.test(rel)) add(href, "mask_icon", 8);  // v0.25.1: a one-colour silhouette, used only when nothing else is there
    else if (/apple-touch-icon/.test(rel)) add(href, "touch_icon", 20);
    else if (/(^|\s)icon(\s|$)/.test(rel) && Number((sizes.match(/(\d+)x\d+/) || [])[1] || 0) >= 128) add(href, "large_icon", 18);
  }
  return [...out.values()].filter((c) => c.score > 0).sort((a, b) => b.score - a.score);
}

// width and height of a PNG, JPEG or WebP; null when the bytes do not say
export function imageSize(b: Uint8Array, mime: string): { width: number; height: number } | null {
  const u32 = (o: number) => (b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3]) >>> 0;
  if (mime === "image/png" && b.length > 24 && b[12] === 0x49 && b[13] === 0x48) return { width: u32(16), height: u32(20) };
  if (mime === "image/jpeg") {
    let i = 2;
    while (i + 9 < b.length) {
      if (b[i] !== 0xff) { i++; continue }
      const mk = b[i + 1], len = b[i + 2] << 8 | b[i + 3];
      if (mk >= 0xc0 && mk <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(mk)) return { height: b[i + 5] << 8 | b[i + 6], width: b[i + 7] << 8 | b[i + 8] };
      i += 2 + len;
    }
    return null;
  }
  if (mime === "image/webp" && b.length > 30) {
    const kind = String.fromCharCode(b[12], b[13], b[14], b[15]);
    if (kind === "VP8 ") return { width: (b[26] | b[27] << 8) & 0x3fff, height: (b[28] | b[29] << 8) & 0x3fff };
    if (kind === "VP8L") { const v = b[21] | b[22] << 8 | b[23] << 16 | b[24] << 24; return { width: (v & 0x3fff) + 1, height: (v >> 14 & 0x3fff) + 1 } }
    if (kind === "VP8X") return { width: 1 + (b[24] | b[25] << 8 | b[26] << 16), height: 1 + (b[27] | b[28] << 8 | b[29] << 16) };
  }
  return null;
}

// an SVG is stored only when it is a plain drawing: no scripts, event handlers, embedded pages or outside references
export function svgSafe(text: string): boolean {
  if (!/<svg[\s>]/i.test(text)) return false;
  return !/<script|<foreignObject|\son[a-z]+\s*=|javascript:|<iframe|<embed|<object|xlink:href\s*=\s*["']https?:|href\s*=\s*["']https?:|<!ENTITY/i.test(text);
}

// the type the bytes are, whatever the server said
export function sniffMime(b: Uint8Array, declared: string): string | null {
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  if (b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 && b[8] === 0x57 && b[9] === 0x45) return "image/webp";
  const head = new TextDecoder().decode(b.slice(0, 512)).trimStart().toLowerCase();
  if (head.startsWith("<svg") || (head.startsWith("<?xml") && head.includes("<svg")) || (/svg/.test(declared) && head.includes("<svg"))) return "image/svg+xml";
  return null;
}
