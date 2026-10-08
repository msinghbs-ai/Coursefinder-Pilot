// CF-247 Phase 2 (8 Oct 2026): register adapters for registers published as web pages (NZQA first). The spec in
// pipeline.register_adapters says which stored page holds what: provider identity on the details page, one record per row of
// the qualifications table, the row rules and the level mapping. `htmlAdapterRecords` reads a stored Layer 1 batch file using
// only the spec. `nzqaReferenceRecords` is a verbatim copy of what Layer 1 does today (layer1-nz-live v1.2.1: providerNumber,
// providerName, providerWebsite, parseQualifications, mapLevel and the record shape), so the replay can compare row by row.

const clean = (v: unknown) => String(v ?? "").replace(/&nbsp;/gi, " ").replace(/&amp;/gi, "&").replace(/&#39;/g, "'").replace(/&quot;/gi, '"').replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();

export type HtmlSpec = {
  format: "html_pages";
  provider: {
    code: { source: string; text_regex: string[] };
    name: { source: string; html_regex: string[]; fallback_field?: string; strip?: string[] };
    website: { source: string; html_regex: string[]; https_prefix?: boolean };
    copy: Record<string, string>;
  };
  records: {
    source: string; row: string; link: string; require?: string; status_value: string;
    level_from_title?: string; credits_cell?: { regex: string; min: number; max: number };
    level_map: [string, string][];
  };
};

type Rec = { k: string; x: Record<string, string> };
const keyOf = (r: Record<string, unknown>) => `${r.provider_code ?? ""}|${r.course_code ?? ""}`;
const asText = (r: Record<string, unknown>) => Object.fromEntries(Object.entries(r).map(([k, v]) => [k, v == null ? "" : String(v)]));

// The records exactly as the Layer 1 worker sends them to the apply functions (null where nothing was read).
export function htmlAdapterRecords(spec: HtmlSpec, batch: any[]): Rec[] {
  return htmlAdapterRows(spec, batch).map((r) => ({ k: keyOf(r), x: asText(r) }));
}

export function htmlAdapterRows(spec: HtmlSpec, batch: any[]): Record<string, unknown>[] {
  const out: Record<string, unknown>[] = [], P = spec.provider, R = spec.records;
  for (const p of batch || []) {
    const src = (name: string) => String(p?.[name] ?? "");
    const ctext = clean(src(P.code.source));
    let code = ""; for (const re of P.code.text_regex) { const m = ctext.match(new RegExp(re, "i")); if (m?.[1]) { code = m[1]; break } }
    const nh = src(P.name.source); let raw = ""; for (const re of P.name.html_regex) { const m = nh.match(new RegExp(re, "i")); if (m?.[1]) { raw = m[1]; break } }
    let name = clean(raw || (P.name.fallback_field ? String(p?.[P.name.fallback_field] ?? "") : ""));
    for (const s of P.name.strip || []) name = name.replace(new RegExp(s, "i"), "");
    name = name.trim();
    const wh = src(P.website.source); let web: string | null = null; for (const re of P.website.html_regex) { const m = wh.match(new RegExp(re, "i")); if (m?.[1]) { web = m[1]; break } }
    web = web ? (P.website.https_prefix ? web.trim().replace(/^(https?:\/\/)+/i, "https://") : web.trim()) : null;
    const base: Record<string, unknown> = { provider_code: code, provider_name: name, website: web };
    for (const [to, from] of Object.entries(P.copy)) base[to] = p?.[from] ?? null;
    const html = src(R.source), seen = new Set<string>(), quals: Record<string, unknown>[] = [];
    for (const m of html.matchAll(new RegExp(R.row, "gi"))) {
      const row = m[1], qm = row.match(new RegExp(R.link, "i")); if (!qm) continue;
      const qc = decodeURIComponent(qm[1]).trim().toUpperCase(), title = clean(qm[2]), text = clean(row);
      if (!qc || !title || seen.has(qc) || (R.require && !new RegExp(R.require, "i").test(text))) continue;
      seen.add(qc);
      const cells = [...row.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/gi)].map((x) => clean(x[1]));
      const level = R.level_from_title ? (title.match(new RegExp(R.level_from_title, "i"))?.[1] || null) : null;
      const cc = R.credits_cell, credits = cc ? (cells.find((x) => new RegExp(cc.regex).test(x) && Number(x) >= cc.min && Number(x) <= cc.max) || null) : null;
      const low = title.toLowerCase(), lv = (R.level_map.find(([re]) => new RegExp(re).test(low)) || [null, ""])[1];
      quals.push({ course_code: qc, course_name: title, course_level: lv, nzqf_level: level, credits, source_status: R.status_value });
    }
    if (!code || !name) throw new Error(`stable provider identity missing for ${String(p?.providerId ?? "a provider")}`);
    if (!quals.length) out.push(base);
    for (const q of quals) out.push({ ...base, ...q });
  }
  return out;
}

// ---- reference: layer1-nz-live v1.2.1 (copied, not changed) ----------------------------------------------------------
function mapLevel(t: string) { const s = t.toLowerCase(); if (/doctor|phd/.test(s)) return "doctorate"; if (/master/.test(s)) return "masters"; if (/graduate certificate/.test(s)) return "graduate_certificate"; if (/graduate diploma/.test(s)) return "graduate_diploma"; if (/bachelor/.test(s)) return "bachelor"; if (/associate/.test(s)) return "associate_degree"; if (/diploma/.test(s)) return "diploma"; if (/certificate/.test(s)) return "certificate"; if (/foundation/.test(s)) return "foundation"; return "" }
function providerNumber(html: string) { const text = clean(html); return text.match(/Education Organisation number\s+([0-9]{3,8})/i)?.[1] || text.match(/provider number\s+([0-9]{3,8})/i)?.[1] || "" }
function providerName(html: string, fallback: string) { let n = clean(html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i)?.[1] || html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] || fallback); n = n.replace(/^Organisations\s*>>\s*NZQA\s*-\s*/i, "").replace(/^Organisations\s*>>\s*/i, ""); return n.trim() }
function providerWebsite(html: string) { const text = html.match(/Website[\s\S]{0,400}?href=["']([^"']+)["']/i)?.[1] || ""; return text ? text.trim().replace(/^(https?:\/\/)+/i, "https://") : null }
function parseQualifications(html: string) { const rows: any[] = []; const seen = new Set<string>(); for (const m of html.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/gi)) { const row = m[1]; const qm = row.match(/viewQualification\.do\?selectedItemKey=([^&"']+)[^>]*>([\s\S]*?)<\/a>/i); if (!qm) continue; const code = decodeURIComponent(qm[1]).trim().toUpperCase(); const title = clean(qm[2]); const text = clean(row); if (!code || !title || seen.has(code) || !/(^|\s)Current(\s|$)/i.test(text)) continue; seen.add(code); const cells = [...row.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/gi)].map((x) => clean(x[1])); const level = (title.match(/\(Level\s+([1-9]|10)\)/i)?.[1]) || null; const credits = (cells.find((x: string) => /^[0-9]{2,4}$/.test(x) && Number(x) >= 20 && Number(x) <= 1000)) || null; rows.push({ code, title, status: "Current", level, credits }) } return rows }

export function nzqaReferenceRecords(batch: any[]): Rec[] {
  const out: Rec[] = [];
  for (const p0 of batch || []) {
    const details = String(p0?.detailsHtml ?? ""), qualsHtml = String(p0?.qualsHtml ?? "");
    const p = { ...p0, provider_code: providerNumber(details), provider_name: providerName(details, p0?.listingName || ""), website: providerWebsite(details), quals: parseQualifications(qualsHtml) };
    if (!p.quals.length) { const r = { provider_code: p.provider_code, provider_name: p.provider_name, website: p.website, city: p.city, provider_type: p.type }; out.push({ k: keyOf(r), x: asText(r) }) }
    for (const q of p.quals) { const r = { provider_code: p.provider_code, provider_name: p.provider_name, website: p.website, city: p.city, provider_type: p.type, course_code: q.code, course_name: q.title, course_level: mapLevel(q.title), nzqf_level: q.level, credits: q.credits, source_status: q.status }; out.push({ k: keyOf(r), x: asText(r) }) }
  }
  return out;
}
