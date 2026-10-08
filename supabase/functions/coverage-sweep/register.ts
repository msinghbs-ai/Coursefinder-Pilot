// CF-247 Phase 2 (8 Oct 2026): register adapters. A register (CRICOS first) is described by a spec held in
// pipeline.register_adapters: where its files are in the archive, which file holds one record per course, the active
// rule, the joins and the field mapping. `adapterRecords` reads an archive using only the spec. `referenceRecords` is a
// verbatim copy of what Layer 1 does today (layer1-au-depth v1.7.0 courseFingerprints and scanCourses/scanInstitutions,
// layer1-au-cricos-facts v1.2.0 scanCsv), so a replay can compare the two row by row before anything is switched.
import { unzipSync } from "npm:fflate@0.8.2";

const clean = (v: unknown) => String(v ?? "").trim();
const nk = (v: unknown) => clean(v).replace(/^﻿/, "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
const numericText = (v: unknown) => clean(v).replace(/,/g, "");
async function sha(bytes: Uint8Array) { const d = await crypto.subtle.digest("SHA-256", bytes); return [...new Uint8Array(d)].map((x) => x.toString(16).padStart(2, "0")).join("") }

// Same CSV reader as Layer 1 (quotes, doubled quotes, BOM on the first header, blank rows skipped).
export function scanRows(text: string, onRow: (get: (name: string) => string, raw: string[]) => void) {
  let header: string[] | null = null, index: Record<string, number> = {}, row: string[] = [], field = "", quoted = false, rows = 0;
  const push = () => {
    row.push(field); field = "";
    if (!header) { header = row.map((x) => clean(x).replace(/^﻿/, "")); index = Object.fromEntries(header.map((h, i) => [nk(h), i])); row = []; return }
    if (!row.some((x) => clean(x))) { row = []; return }
    rows++; const current = row, get = (name: string) => clean(current[index[nk(name)]]); onRow(get, current); row = [];
  };
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) { if (c === '"') { if (text[i + 1] === '"') { field += '"'; i++ } else quoted = false } else field += c }
    else if (c === '"') quoted = true; else if (c === ",") { row.push(field); field = "" } else if (c === "\n") push(); else if (c !== "\r") field += c;
  }
  if (field.length || row.length) push();
  return { columns: header || [], rows };
}

function fieldParts(raw: string) { const s = clean(raw), m = s.match(/^\s*(\d{4})\b\s*(?:[-–—:]\s*)?(.*)$/); return m ? { code: m[1], name: clean(m[2]) || s.replace(/^\s*\d{4}\b\s*/, "") } : { code: "", name: s } }

export type FileRule = { name_regex: string; not_regex?: string };
export type FieldRule = string | { column?: string; columns?: string[]; from?: string; numeric_text?: boolean; split?: "asced4"; part?: "code" | "name"; prefix_https?: boolean };
export type RegisterSpec = {
  format: "zip_csv";
  files: Record<string, FileRule>;
  record: { file: string; key: string; active?: { column: string; active_if_empty_or: string } };
  joins: { as: string; file: string; on: [string, string][]; many?: boolean; then?: { file: string; on: [string, string][] } }[];
  fingerprint: { parts: string[]; field_sep: string; part_sep: string; pair_sep: string };
  fields: Record<string, FieldRule>;
};

function archiveTexts(zipBytes: Uint8Array, files: Record<string, FileRule>) {
  const zip = unzipSync(zipBytes), out: Record<string, string> = {}, dec = new TextDecoder();
  for (const [k, r] of Object.entries(files)) {
    const re = new RegExp(r.name_regex), not = r.not_regex ? new RegExp(r.not_regex) : null;
    const e = Object.entries(zip).find(([name]) => { const n = name.toLowerCase().replace(/[_-]+/g, " "); return re.test(n) && !(not && not.test(n)) });
    if (!e) throw new Error(`archive has no file for ${k}: ${Object.keys(zip).join(",")}`);
    out[k] = dec.decode(e[1]);
  }
  return out;
}

type Row = { get: (n: string) => string; raw: string[] };
// Reads the archive using only the spec: one record per active row of the record file, joined rows, fingerprint and fields.
export async function adapterRecords(spec: RegisterSpec, zipBytes: Uint8Array, from = 0, to = Infinity) {
  const texts = archiveTexts(zipBytes, spec.files), sep = spec.fingerprint;
  const J = (a: string[]) => a.map((x) => clean(x)).join(sep.field_sep);
  const index: Record<string, Map<string, Row[]>> = {};
  const keyOf = (get: (n: string) => string, cols: string[]) => cols.map((c) => get(c)).join("|");
  const needed = new Map<string, string[]>();
  for (const j of spec.joins) { needed.set(j.file, j.on.map((p) => p[1])); if (j.then) needed.set(j.then.file, j.then.on.map((p) => p[1])) }
  for (const [file, cols] of needed) {
    const m = new Map<string, Row[]>();
    scanRows(texts[file], (get, raw) => { const k = keyOf(get, cols); if (cols.some((c) => !get(c))) return; const a = m.get(k) || []; a.push({ get, raw: [...raw] }); m.set(k, a) });
    index[file] = m;
  }
  const act = spec.record.active, activeRe = act ? new RegExp(act.active_if_empty_or, "i") : null;
  const out: { k: string; f: string; x: Record<string, string> }[] = [], enc = new TextEncoder();
  const recs: { key: string; text: string; x: Record<string, string> }[] = [];
  scanRows(texts[spec.record.file], (get, raw) => {
    if (act) { const v = get(act.column); if (v && !activeRe!.test(v)) return }
    const key = get(spec.record.key); if (!key) return;
    const joined: Record<string, Row | Row[] | undefined> = {}, parts: string[] = [];
    for (const j of spec.joins) {
      const rows = index[j.file].get(keyOf(get, j.on.map((p) => p[0]))) || [];
      if (j.many) {
        const list: string[] = [];
        for (const r of rows) {
          const subs = j.then ? (index[j.then.file].get(keyOf(r.get, j.then.on.map((p) => p[0]))) || []) : [], sub = subs[subs.length - 1]; // last row wins, as Layer 1's Map.set does
          list.push(J(r.raw) + sep.pair_sep + (sub ? J(sub.raw) : ""));
        }
        joined[j.as] = rows; (joined as any)["__fp_" + j.as] = list.sort();
      } else {
        // last row wins, as Layer 1's Map.set does
        joined[j.as] = rows[rows.length - 1];
      }
    }
    for (const p of spec.fingerprint.parts) {
      if (p === "record") parts.push(J(raw));
      else if (p.startsWith("join:")) { const r = joined[p.slice(5)] as Row | undefined; parts.push(r ? J(r.raw) : "") }
      else if (p.startsWith("many:")) parts.push(...((joined as any)["__fp_" + p.slice(5)] as string[] || []));
    }
    const x: Record<string, string> = {};
    for (const [name, rule] of Object.entries(spec.fields)) {
      if (typeof rule === "string") { x[name] = get(rule); continue }
      const src: ((n: string) => string) | null = rule.from ? ((joined[rule.from] as Row | undefined)?.get || null) : get;
      if (!src) { x[name] = ""; continue }
      let v = rule.columns ? (rule.columns.map((c) => src(c)).find((s) => s) || "") : src(rule.column || "");
      if (rule.numeric_text) v = numericText(v);
      if (rule.split === "asced4") { const fp = fieldParts(v); v = rule.part === "code" ? fp.code : fp.name }
      if (rule.prefix_https && v && !/^https?:\/\//i.test(v)) v = "https://" + v;
      x[name] = v;
    }
    recs.push({ key, text: parts.join(sep.part_sep), x });
  });
  for (const r of recs.slice(from, to)) out.push({ k: r.key, f: await sha(enc.encode(r.text)), x: r.x });
  return { total: recs.length, recs: out };
}

// ---- reference: what Layer 1 does today (copied, not changed) --------------------------------------------------------
function archiveEntry(zip: Record<string, Uint8Array>, kind: "i" | "c" | "l" | "cl") { const e = Object.entries(zip).find(([name]) => { const n = name.toLowerCase().replace(/[_-]+/g, " "); if (kind === "i") return /institutions.*\.csv$/.test(n); if (kind === "c") return /courses.*\.csv$/.test(n) && !/course locations/.test(n); if (kind === "l") return /locations.*\.csv$/.test(n) && !/course locations/.test(n); return /course locations.*\.csv$/.test(n) }); if (!e) throw new Error(`archive missing ${kind}`); return { name: e[0], bytes: e[1] } }

export async function referenceRecords(zipBytes: Uint8Array, from = 0, to = Infinity) {
  const zip = unzipSync(zipBytes), parts = { institutions: archiveEntry(zip, "i"), courses: archiveEntry(zip, "c"), locations: archiveEntry(zip, "l"), courseLocations: archiveEntry(zip, "cl") };
  // layer1-au-depth v1.7.0 courseFingerprints
  const texts = new Map<Uint8Array, string>(), dec = (b: Uint8Array) => { let t = texts.get(b); if (t === undefined) { t = new TextDecoder().decode(b); texts.set(b, t) } return t }, J = (a: string[]) => a.map((x) => clean(x)).join("\u001f");
  const inst = new Map<string, string>(), loc = new Map<string, string>(), cl = new Map<string, string[]>(), rows: [string, string][] = [];
  scanRows(dec(parts.institutions.bytes), (get, raw) => { const pc = get("CRICOS Provider Code"); if (pc) inst.set(pc, J(raw)) });
  scanRows(dec(parts.locations.bytes), (get, raw) => { const pc = get("CRICOS Provider Code"), n = get("Location Name"); if (pc && n) loc.set(`${pc}|${n}`, J(raw)) });
  scanRows(dec(parts.courseLocations.bytes), (get, raw) => { const cc = get("CRICOS Course Code"); if (!cc) return; const a = cl.get(cc) || []; a.push(J(raw) + "\u001e" + (loc.get(`${get("CRICOS Provider Code")}|${get("Location Name")}`) || "")); cl.set(cc, a) });
  scanRows(dec(parts.courses.bytes), (get, raw) => { const ex = get("Expired"); if (ex && !/^(no|false|n|0)$/i.test(ex)) return; const cc = get("CRICOS Course Code"); if (!cc) return; rows.push([cc, [J(raw), inst.get(get("CRICOS Provider Code")) || "", ...(cl.get(cc) || []).sort()].join("\u001d")]) });
  // layer1-au-depth scanCourses + scanInstitutions, layer1-au-cricos-facts scanCsv (the fields they send to the apply functions)
  const prov = new Map<string, any>();
  scanRows(dec(parts.institutions.bytes), (get) => { const pc = get("CRICOS Provider Code"); if (!pc) return; let website = get("Website"); if (website && !/^https?:\/\//i.test(website)) website = "https://" + website; prov.set(pc, { provider_name: get("Trading Name") || get("Institution Name"), provider_website: website || "" }) });
  const fields = new Map<string, Record<string, string>>();
  scanRows(dec(parts.courses.bytes), (get) => {
    const ex = get("Expired"); if (ex && !/^(no|false|n|0)$/i.test(ex)) return; const cc = get("CRICOS Course Code"); if (!cc) return;
    const f1 = fieldParts(get("Field of Education 1 Narrow Field")), f2 = get("Field of Education 2 Narrow Field"), m = f2.match(/^\s*(\d{4})\b\s*(?:[-–—:]\s*)?(.*)$/);
    const p = prov.get(get("CRICOS Provider Code")) || { provider_name: "", provider_website: "" };
    fields.set(cc, {
      provider_code: get("CRICOS Provider Code"), course_code: cc, course_name: get("Course Name"), course_level_raw: get("Course Level"), duration_weeks: get("Duration (Weeks)"),
      field_code: f1.code, field_name: f1.name, vet_national_code: get("VET National Code"), dual_qualification: get("Dual Qualification"),
      secondary_field_code: m?.[1] || "", secondary_field_name: m ? (clean(m[2]) || f2.replace(/^\s*\d{4}\b\s*/, "")) : f2, foundation_studies: get("Foundation Studies"),
      work_component: get("Work Component"), work_component_hours_per_week: numericText(get("Work Component Hours/Week")), work_component_weeks: numericText(get("Work Component Weeks")),
      work_component_total_hours: numericText(get("Work Component Total Hours")), course_language: get("Course Language"), tuition_fee: get("Tuition Fee"),
      non_tuition_fee: get("Non Tuition Fee"), estimated_total_course_cost: get("Estimated Total Course Cost"), provider_name: p.provider_name, provider_website: p.provider_website,
    });
  });
  const enc = new TextEncoder(), out: { k: string; f: string; x: Record<string, string> }[] = [];
  for (const [k, t] of rows.slice(from, to)) out.push({ k, f: await sha(enc.encode(t)), x: fields.get(k) || {} });
  return { total: rows.length, recs: out };
}
