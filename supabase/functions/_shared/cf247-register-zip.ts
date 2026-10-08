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
export type FieldRule = string | { column?: string; columns?: string[]; join_columns?: string[][]; sep?: string; from?: string; numeric_text?: boolean; split?: "asced4"; part?: "code" | "name"; prefix_https?: boolean; fallback?: "record_provider" };
// v2 (8 Oct 2026): further row sets read from the archive for the records selected (CRICOS: campus locations of their providers and the
// locations of each course), so a Layer 1 worker can take everything it applies from the adapter.
export type SetSpec = { file: string; prefix: string; filter: { column: string; in: "record_providers" | "record_keys" }; fields: Record<string, FieldRule>;
  constants?: Record<string, string>; require?: string[]; dedupe?: string[]; key: string[] };
export type RegisterSpec = {
  format: "zip_csv";
  files: Record<string, FileRule>;
  record: { file: string; key: string; active?: { column: string; active_if_empty_or: string } };
  joins: { as: string; file: string; on: [string, string][]; many?: boolean; then?: { file: string; on: [string, string][] } }[];
  fingerprint: { parts: string[]; field_sep: string; part_sep: string; pair_sep: string };
  fields: Record<string, FieldRule>;
  record_provider?: string;   // the record column holding its provider code (for set filters and fallbacks)
  sets?: Record<string, SetSpec>;
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

// One field value from its rule. `src` reads the row itself; `joinedGet` reads a joined row (null when there is none).
function evalRule(rule: FieldRule, get: (n: string) => string, joinedGet: (from: string) => ((n: string) => string) | null, fallback?: (name: string) => string): string {
  if (typeof rule === "string") return get(rule);
  const src = rule.from ? joinedGet(rule.from) : get;
  if (!src) return "";
  let v = rule.join_columns ? rule.join_columns.map((cols) => cols.map((c) => src(c)).find((x) => x) || "").filter(Boolean).join(rule.sep ?? ", ")
    : rule.columns ? (rule.columns.map((c) => src(c)).find((x) => x) || "") : src(rule.column || "");
  if (!v && rule.fallback && fallback) v = fallback(rule.fallback);
  if (rule.numeric_text) v = numericText(v);
  if (rule.split === "asced4") { const fp = fieldParts(v); v = rule.part === "code" ? fp.code : fp.name }
  if (rule.prefix_https && v && !/^https?:\/\//i.test(v)) v = "https://" + v;
  return v;
}
function evalFields(fields: Record<string, FieldRule>, get: (n: string) => string, joinedGet: (from: string) => ((n: string) => string) | null, fallback?: (name: string) => string) {
  const x: Record<string, string> = {};
  for (const [name, rule] of Object.entries(fields)) x[name] = evalRule(rule, get, joinedGet, fallback);
  return x;
}

type Row = { get: (n: string) => string; raw: string[] };
// Reads the archive using only the spec: one record per active row of the record file, joined rows, fingerprint and fields.
// v2 replays: positions past the last record each read one row set (in name order), in a call of its own, so no call reads the records
// and the sets together. `next` and `done` say where the replay continues.
export const setNames = (spec: { sets?: Record<string, unknown> }) => Object.keys(spec.sets || {}).sort();
export async function adapterRecords(spec: RegisterSpec, zipBytes: Uint8Array, from = 0, to = Infinity) {
  const texts = archiveTexts(zipBytes, spec.files), sep = spec.fingerprint;
  if (spec.sets) {
    const act0 = spec.record.active, re0 = act0 ? new RegExp(act0.active_if_empty_or, "i") : null, all0: { key: string; prov: string }[] = [];
    scanRows(texts[spec.record.file], (get) => { if (act0) { const v = get(act0.column); if (v && !re0!.test(v)) return } const key = get(spec.record.key); if (key) all0.push({ key, prov: spec.record_provider ? get(spec.record_provider) : "" }) });
    if (from >= all0.length) {
      const names = setNames(spec), name = names[from - all0.length], out0: { k: string; f: string; x: Record<string, string> }[] = [];
      if (name) { const one = adapterSets({ ...spec, sets: { [name]: spec.sets[name] } }, texts, all0); for (const x of one[name] || []) out0.push({ k: setKey(spec.sets[name], x), f: "set", x }) }
      return { total: all0.length, recs: out0, next: from + 1, done: from - all0.length + 1 >= names.length };
    }
  }
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
  // v2: only the records of this slice are joined and read (the others are only counted, with their key and provider for the sets)
  const recs: { key: string; text: string; x: Record<string, string>; prov: string }[] = [], all: { key: string; prov: string }[] = [];
  scanRows(texts[spec.record.file], (get, raw) => {
    if (act) { const v = get(act.column); if (v && !activeRe!.test(v)) return }
    const key = get(spec.record.key); if (!key) return;
    const at = all.length; all.push({ key, prov: spec.record_provider ? get(spec.record_provider) : "" });
    if (at < from || at >= to) return;
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
    const x = evalFields(spec.fields, get, (from) => (joined[from] as Row | undefined)?.get || null);
    recs.push({ key, text: parts.join(sep.part_sep), x, prov: spec.record_provider ? get(spec.record_provider) : "" });
  });
  for (const r of recs) out.push({ k: r.key, f: await sha(enc.encode(r.text)), x: r.x });
  // v2: the further row sets, for every record, with the last slice (keyed "<prefix>|<key fields>")
  return { total: all.length, recs: out, next: Math.min(to, all.length), done: !spec.sets && to >= all.length };
}

export const setKey = (s: SetSpec, x: Record<string, string>) => [s.prefix, ...s.key.map((k) => x[k] ?? "")].join("|");

// The further row sets for the given records: rows of the set's file whose filter column is one of the records' providers (or keys),
// read with the set's field rules; rows missing a required field are skipped and duplicates (by `dedupe`) kept once, as Layer 1 does.
export function adapterSets(spec: RegisterSpec, texts: Record<string, string>, records: { key: string; prov: string }[], counts: Record<string, number> = {}) {
  const out: Record<string, Record<string, string>[]> = {};
  const provs = new Set(records.map((r) => r.prov).filter(Boolean)), keys = new Set(records.map((r) => r.key)), provOf = new Map(records.map((r) => [r.key, r.prov]));
  for (const [name, set] of Object.entries(spec.sets || {})) {
    const rows: Record<string, string>[] = [], seen = new Set<string>(), wanted = set.filter.in === "record_providers" ? provs : keys;
    counts[set.file] = scanRows(texts[set.file], (get) => {
      const fv = get(set.filter.column); if (!fv || !wanted.has(fv)) return;
      const x = evalFields(set.fields, get, () => null, (fb) => fb === "record_provider" ? (provOf.get(fv) || "") : "");
      for (const [k, v] of Object.entries(set.constants || {})) x[k] = v;
      if ((set.require || []).some((k) => !x[k])) return;
      if (set.dedupe) { const d = set.dedupe.map((k) => x[k]).join("|"); if (seen.has(d)) return; seen.add(d) }
      rows.push(x);
    }).rows;
    out[name] = rows;
  }
  return out;
}

// For a Layer 1 worker: the archive's files, the active and expired counts, the selected records (by code, or by position) with all their
// fields, and the further row sets for them. Read only.
export function adapterTexts(spec: RegisterSpec, zipBytes: Uint8Array) { return archiveTexts(zipBytes, spec.files) }
export function adapterSelect(spec: RegisterSpec, texts: Record<string, string>, sel: { codes?: Set<string> | null; offset?: number; limit?: number }, opts: { joins?: boolean; sets?: boolean } = {}) {
  const useJoins = opts.joins !== false, index: Record<string, Map<string, { get: (n: string) => string }>> = {}, counts: Record<string, number> = {};
  if (useJoins) for (const j of spec.joins.filter((j) => !j.many)) {
    const m = new Map<string, { get: (n: string) => string }>(), cols = j.on.map((p) => p[1]);
    counts[j.file] = scanRows(texts[j.file], (get) => { if (cols.some((c) => !get(c))) return; m.set(cols.map((c) => get(c)).join("|"), { get }) }).rows; // last row wins, as Layer 1's Map.set does
    index[j.as] = m;
  }
  const act = spec.record.active, activeRe = act ? new RegExp(act.active_if_empty_or, "i") : null;
  let active = 0, expired = 0; const selected: { key: string; prov: string; x: Record<string, string>; joined: Record<string, boolean> }[] = [];
  const offset = sel.offset || 0, limit = sel.limit ?? Infinity;
  const scan = scanRows(texts[spec.record.file], (get) => {
    if (act) { const v = get(act.column); if (v && !activeRe!.test(v)) { expired++; return } }
    const ai = active++;
    const key = get(spec.record.key);
    if (sel.codes ? !sel.codes.has(key) : (ai < offset || selected.length >= limit)) return;
    const joined: Record<string, boolean> = {};
    const x = evalFields(spec.fields, get, (from) => {
      if (!useJoins) return null;
      const j = spec.joins.find((jj) => jj.as === from); if (!j || j.many) return null;
      const r = index[from]?.get(j.on.map((p) => get(p[0])).join("|")); joined[from] = !!r; return r ? r.get : null;
    });
    selected.push({ key, prov: spec.record_provider ? get(spec.record_provider) : "", x, joined });
  });
  counts[spec.record.file] = scan.rows;
  const sets = opts.sets === false ? {} : adapterSets(spec, texts, selected, counts);
  const columns = Object.fromEntries(Object.entries(texts).map(([k, t]) => [k, headerOf(t)]));
  return { active, expired, rows: scan.rows, counts, columns, selected, sets };
}
function headerOf(text: string) { const end = text.indexOf("\n"); return scanRows(end < 0 ? text + "\n" : text.slice(0, end + 1), () => {}).columns }

// For the plan step: one fingerprint per active record, without building fields (the whole archive in one call).
export async function adapterFingerprints(spec: RegisterSpec, texts: Record<string, string>) {
  const sep = spec.fingerprint, J = (a: string[]) => a.map((x) => clean(x)).join(sep.field_sep);
  const single: Record<string, Map<string, string>> = {}, many: Record<string, Map<string, string[]>> = {};
  for (const j of spec.joins) {
    if (!j.many) { const m = new Map<string, string>(), cols = j.on.map((p) => p[1]); scanRows(texts[j.file], (get, raw) => { if (cols.some((c) => !get(c))) return; m.set(cols.map((c) => get(c)).join("|"), J(raw)) }); single[j.as] = m; continue }
    const sub = new Map<string, string>();
    if (j.then) { const tc = j.then.on.map((p) => p[1]); scanRows(texts[j.then.file], (get, raw) => { if (tc.some((c) => !get(c))) return; sub.set(tc.map((c) => get(c)).join("|"), J(raw)) }) }
    const m = new Map<string, string[]>(), cols = j.on.map((p) => p[1]), thenFrom = j.then ? j.then.on.map((p) => p[0]) : [];
    scanRows(texts[j.file], (get, raw) => { if (cols.some((c) => !get(c))) return; const k = cols.map((c) => get(c)).join("|"), a = m.get(k) || [];
      a.push(J(raw) + sep.pair_sep + (j.then ? (sub.get(thenFrom.map((c) => get(c)).join("|")) || "") : "")); m.set(k, a) });
    many[j.as] = m;
  }
  const act = spec.record.active, activeRe = act ? new RegExp(act.active_if_empty_or, "i") : null, texts2: [string, string][] = [];
  scanRows(texts[spec.record.file], (get, raw) => {
    if (act) { const v = get(act.column); if (v && !activeRe!.test(v)) return }
    const key = get(spec.record.key); if (!key) return;
    const parts: string[] = [];
    for (const p of sep.parts) {
      if (p === "record") parts.push(J(raw));
      else if (p.startsWith("join:")) { const j = spec.joins.find((jj) => jj.as === p.slice(5))!; parts.push(single[j.as].get(j.on.map((q) => get(q[0])).join("|")) || "") }
      else if (p.startsWith("many:")) { const j = spec.joins.find((jj) => jj.as === p.slice(5))!; parts.push(...[...(many[j.as].get(j.on.map((q) => get(q[0])).join("|")) || [])].sort()) }
    }
    texts2.push([key, parts.join(sep.part_sep)]);
  });
  const enc = new TextEncoder(), out: [string, string][] = [];
  for (const [k, t] of texts2) out.push([k, await sha(enc.encode(t))]);
  return out;
}

// ---- reference: what Layer 1 does today (copied, not changed) --------------------------------------------------------
function archiveEntry(zip: Record<string, Uint8Array>, kind: "i" | "c" | "l" | "cl") { const e = Object.entries(zip).find(([name]) => { const n = name.toLowerCase().replace(/[_-]+/g, " "); if (kind === "i") return /institutions.*\.csv$/.test(n); if (kind === "c") return /courses.*\.csv$/.test(n) && !/course locations/.test(n); if (kind === "l") return /locations.*\.csv$/.test(n) && !/course locations/.test(n); return /course locations.*\.csv$/.test(n) }); if (!e) throw new Error(`archive missing ${kind}`); return { name: e[0], bytes: e[1] } }

function scanLocations(text:string,wanted:Set<string>){const selected:any[]=[];const s=scanRows(text,get=>{const pc=get("CRICOS Provider Code"),name=get("Location Name");if(!pc||!name||!wanted.has(pc))return;selected.push({provider_code:pc,location_code:name,location_name:name,address_line1:get("Address Line 1"),address_line2:[get("Address Line 2"),get("Address Line 3"),get("Address Line 4")].filter(Boolean).join(", "),city:get("City"),state:get("State"),postcode:get("Postcode")});});return{...s,selected};}
function scanCourseLocations(text:string,wanted:Set<string>,courseProviderMap:Map<string,string>){const selected:any[]=[],seen=new Set<string>();const s=scanRows(text,get=>{const cc=get("CRICOS Course Code");if(!cc||!wanted.has(cc))return;const pc=get("CRICOS Provider Code")||courseProviderMap.get(cc)||"",name=get("Location Name");if(!pc||!name)return;const key=`${pc}|${cc}|${name}`;if(seen.has(key))return;seen.add(key);selected.push({provider_code:pc,course_code:cc,location_code:name,delivery_mode:"on_campus"});});return{...s,selected};}

// withAddress (v2 replays): also the provider address fields and the location sets, as the extended adapter reads them.
export async function referenceRecords(zipBytes: Uint8Array, from = 0, to = Infinity, withAddress = false) {
  const extra = new Map<string, Record<string, string>>();
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
  scanRows(dec(parts.institutions.bytes), (get) => { const pc = get("CRICOS Provider Code"); if (!pc) return; let website = get("Website"); if (website && !/^https?:\/\//i.test(website)) website = "https://" + website; prov.set(pc, { provider_name: get("Trading Name") || get("Institution Name"), provider_website: website || "",
    // v2: the address fields exactly as layer1-au-depth v1.7.0 scanInstitutions reads them (null shown as empty)
    provider_city: get("Postal Address City") || get("Postal City") || null, provider_state: get("Postal Address State") || get("Postal State") || get("State") || null,
    provider_address_line1: get("Postal Address Line 1") || get("Postal Address 1") || null,
    provider_address_line2: [get("Postal Address Line 2") || get("Postal Address 2"), get("Postal Address Line 3") || get("Postal Address 3"), get("Postal Address Line 4") || get("Postal Address 4")].filter(Boolean).join(", ") || null,
    provider_postcode: get("Postal Address Postcode") || get("Postal Postcode") || get("Postcode") || null }) });
  const fields = new Map<string, Record<string, string>>();
  scanRows(dec(parts.courses.bytes), (get) => {
    const ex = get("Expired"); if (ex && !/^(no|false|n|0)$/i.test(ex)) return; const cc = get("CRICOS Course Code"); if (!cc) return;
    const f1 = fieldParts(get("Field of Education 1 Narrow Field")), f2 = get("Field of Education 2 Narrow Field"), m = f2.match(/^\s*(\d{4})\b\s*(?:[-–—:]\s*)?(.*)$/);
    const p = prov.get(get("CRICOS Provider Code")) || { provider_name: "", provider_website: "" };
    if (withAddress) for (const k of ["provider_city", "provider_state", "provider_address_line1", "provider_address_line2", "provider_postcode"]) extra.set(get("CRICOS Course Code"), { ...(extra.get(get("CRICOS Course Code")) || {}), [k]: (p as any)[k] ?? "" });
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
  for (const [k, t] of rows.slice(from, to)) out.push({ k, f: await sha(enc.encode(t)), x: { ...(fields.get(k) || {}), ...(extra.get(k) || {}) } });
  // v2: layer1-au-depth v1.7.0 scanLocations and scanCourseLocations (copied, not changed) for every active course, one set a call after
  // the last record (course_locations, then locations), as the adapter does
  if (withAddress && from >= rows.length) {
    out.length = 0;
    const which = ["course_locations", "locations"][from - rows.length];
    const active: { provider_code: string; course_code: string }[] = [];
    scanRows(dec(parts.courses.bytes), (get) => { const ex = get("Expired"); if (ex && !/^(no|false|n|0)$/i.test(ex)) return; const cc = get("CRICOS Course Code"); if (!cc) return; active.push({ provider_code: get("CRICOS Provider Code"), course_code: cc }) });
    const selectedProviders = new Set<string>(active.map((x) => x.provider_code)), selectedCodes = new Set<string>(active.map((x) => x.course_code));
    const courseProviderMap = new Map<string, string>(active.map((x) => [x.course_code, x.provider_code]));
    const T = (r: Record<string, unknown>) => Object.fromEntries(Object.entries(r).map(([k, v]) => [k, v == null ? "" : String(v)]));
    if (which === "locations") for (const r of scanLocations(dec(parts.locations.bytes), selectedProviders).selected) out.push({ k: `loc|${r.provider_code}|${r.location_code}`, f: "set", x: T(r) });
    if (which === "course_locations") for (const r of scanCourseLocations(dec(parts.courseLocations.bytes), selectedCodes, courseProviderMap).selected) out.push({ k: `cl|${r.provider_code}|${r.course_code}|${r.location_code}`, f: "set", x: T(r) });
    return { total: rows.length, recs: out, next: from + 1, done: from - rows.length + 1 >= 2 };
  }
  return { total: rows.length, recs: out, next: Math.min(to, rows.length), done: !withAddress && to >= rows.length };
}
