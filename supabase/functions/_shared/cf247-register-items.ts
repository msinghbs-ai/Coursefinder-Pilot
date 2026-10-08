// CF-247 Phase 2 (8 Oct 2026, Platform Admin: "Build 21, add raw capture to 11"): register adapters for catalogues published as one web
// page or one JSON document (most Canadian Layer 1 readers). The spec in pipeline.register_adapters says how the stored file is cut into
// items (split marker, repeated pattern, JSON array, JSON embedded in the page, or table rows), how each field is read from an item
// (pattern and group, JSON path, constant, table cell next to an anchor, any start month from this month on, membership of a second
// list), how text is cleaned (an ordered list of steps), which items are skipped, how repeated keys are settled and which fields go into
// the record. `itemsAdapterRecords` reads a stored file using only the spec. Read only.

export type Tx = "trim" | "upper" | "lower" | "strip_tags" | "collapse_ws" | ["replace", string, string, string?] | ["pad", number, string];
export type ItemRule = {
  group?: number;                    // a group of the item pattern
  regex?: string | string[];         // first pattern that matches the item (or the `from` field); `rgroup` picks the group (default 1)
  rgroup?: number; flags?: string;
  all?: string;                      // every match of this pattern, group 1, joined with `join` (default "")
  join?: string;
  json?: string;                     // dotted path on a JSON item
  json_any?: { path: string; key: string; equals: string };   // "true" when any element of the array has key == equals
  const?: string;
  from?: string;                     // read from another field instead of the item
  cell?: { anchor: string; offset: number };   // table rows: the cell `offset` places from the first cell containing the anchor field
  future_month?: string;             // pattern with (month name)(year): "true" when any is this month or later
  in_set?: string;                   // "true" when the value is in the named list
  same_as?: string;                  // "true" when the value equals this field's value
  cells_join?: string;               // table rows: all cells joined with this separator
  cell_match?: string;               // table rows: the first cell matching this pattern (case-insensitive)
  tx?: Tx[];
  map?: [string, string][];          // first pattern (on the value) that matches gives the value
  else?: string;                     // value when no map pattern matches
  null_if_empty?: boolean;
  only_if?: string;                  // left out of the record unless this field has a value
};
export type ItemsSpec = {
  format: "text_items";
  pre?: [string, string, string?][];
  sets?: Record<string, { json: string; key: string; tx?: Tx[] }>;
  items: { split?: string; regex?: string; flags?: string; json?: string; embedded_json?: { regex: string; path: string }; table_rows?: { row: string; cell: string; cell_tx?: Tx[]; min_cells: number } };
  fields: Record<string, ItemRule>;
  require?: string[];
  skip?: { field: string; regex: string; flags?: string; not?: boolean }[];
  key: string;
  dedupe: "first" | "last" | "last_unless_conflict" | "last_throw_conflict" | "throw_dup" | "group";
  compare?: string;                  // the field compared for a conflict (default course_title)
  group?: { first: string[]; collect: string[] };   // dedupe "group": first value kept for `first`, distinct values collected for `collect`
  out: string[];
};

const MONTHS: Record<string, number> = { january: 0, february: 1, march: 2, april: 3, may: 4, june: 5, july: 6, august: 7, september: 8, october: 9, november: 10, december: 11 };
function applyTx(v: string, tx: Tx[] = []) {
  for (const s of tx) {
    if (s === "trim") v = v.trim(); else if (s === "upper") v = v.toUpperCase(); else if (s === "lower") v = v.toLowerCase();
    else if (s === "strip_tags") v = v.replace(/<[^>]+>/g, ""); else if (s === "collapse_ws") v = v.replace(/\s+/g, " ");
    else if (Array.isArray(s) && s[0] === "replace") v = v.replace(new RegExp(s[1], s[3] ?? "g"), s[2]);
    else if (Array.isArray(s) && s[0] === "pad") v = v.padStart(s[1], s[2]);
  }
  return v;
}
const jget = (o: any, path: string) => path === "." ? o : path.split(".").reduce((a, k) => (a == null ? undefined : a[k]), o);
const str = (v: unknown) => String(v ?? "");

export type ItemRec = { k: string; x: Record<string, unknown> };
export function itemsAdapterRows(spec: ItemsSpec, text: string, now = new Date()): ItemRec[] {
  for (const [re, rep, fl] of spec.pre || []) text = text.replace(new RegExp(re, fl ?? "g"), rep);
  const doc = spec.items.json || spec.sets ? (() => { try { return JSON.parse(text) } catch { return null } })() : null;
  const sets: Record<string, Set<string>> = {};
  for (const [name, s] of Object.entries(spec.sets || {})) sets[name] = new Set((jget(doc, s.json) || []).map((x: any) => applyTx(str(x?.[s.key]), s.tx)));
  type It = { text?: string; m?: RegExpMatchArray; obj?: any; cells?: string[] };
  let items: It[] = [];
  const I = spec.items;
  if (I.split != null) items = text.split(I.split).slice(1).map((t) => ({ text: t }));
  else if (I.regex) items = [...text.matchAll(new RegExp(I.regex, I.flags ?? "g"))].map((m) => ({ text: m[0], m }));
  else if (I.json) { const a = jget(doc, I.json); if (!Array.isArray(a)) throw new Error(`no list at ${I.json}`); items = a.map((o: any) => ({ obj: o })) }
  else if (I.embedded_json) { const m = text.match(new RegExp(I.embedded_json.regex)); if (!m) throw new Error("embedded JSON not found"); const a = jget(JSON.parse(m[1]), I.embedded_json.path); items = (Array.isArray(a) ? a : []).map((o: any) => ({ obj: o })) }
  else if (I.table_rows) {
    for (const row of text.match(new RegExp(I.table_rows.row, "gi")) || []) {
      const cells = [...row.matchAll(new RegExp(I.table_rows.cell, "gi"))].map((m) => applyTx(m[1], I.table_rows!.cell_tx));
      if (cells.length >= I.table_rows.min_cells) items.push({ text: row, cells });
    }
  }
  const floor = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1);
  // Fields are read in dependency order (a field read `from`, compared `same_as` or anchored on another comes after it): a spec stored as
  // jsonb does not keep its key order.
  const deps = (r: ItemRule) => [r.from, r.same_as, r.cell?.anchor].filter((d): d is string => !!d && d in spec.fields);
  const fieldOrder: string[] = [], placed = new Set<string>(), names = Object.keys(spec.fields).sort();
  while (fieldOrder.length < names.length) {
    const next = names.find((n) => !placed.has(n) && deps(spec.fields[n]).every((d) => placed.has(d)));
    if (!next) throw new Error("field rules depend on each other in a loop");
    fieldOrder.push(next); placed.add(next);
  }
  const out = new Map<string, Record<string, unknown>>(), order: string[] = [];
  for (const it of items) {
    const x: Record<string, unknown> = {}, omit = new Set<string>();
    for (const name of fieldOrder) {
      const r = spec.fields[name];
      const src = r.from != null ? str(x[r.from]) : str(it.text);
      let v = "";
      if (r.const != null) v = r.const;
      else if (r.group != null) v = str(it.m?.[r.group]);
      else if (r.json != null) v = str(jget(it.obj, r.json));
      else if (r.json_any) { const a = jget(it.obj, r.json_any.path); v = Array.isArray(a) && a.some((e: any) => e?.[r.json_any!.key] === r.json_any!.equals) ? "true" : "" }
      else if (r.all != null) v = [...src.matchAll(new RegExp(r.all, r.flags ?? "g"))].map((m) => m[1]).join(r.join ?? "");
      else if (r.cells_join != null) v = (it.cells || []).join(r.cells_join);
      else if (r.cell_match != null) v = (it.cells || []).find((c) => new RegExp(r.cell_match!, "i").test(c)) || "";
      else if (r.cell) { const a = str(x[r.cell.anchor]), cells = it.cells || [], q = cells.findIndex((c) => c.includes(a)); v = a && q + r.cell.offset >= 0 && q >= 0 ? str(cells[q + r.cell.offset]) : ""; if (r.cell.offset < 0 && q + r.cell.offset < 0) v = "" }
      else if (r.future_month != null) { let ok = false; for (const m of src.matchAll(new RegExp(r.future_month, "g"))) { const mo = MONTHS[m[1].toLowerCase()]; if (mo !== undefined && Date.UTC(Number(m[2]), mo, 1) >= floor) { ok = true; break } } v = ok ? "true" : "" }
      else if (r.regex != null) { for (const re of Array.isArray(r.regex) ? r.regex : [r.regex]) { const m = src.match(new RegExp(re, r.flags ?? "")); if (m) { v = str(m[r.rgroup ?? 1]); if (v) break } } }
      else if (r.from != null) v = src;
      if (r.in_set) v = sets[r.in_set]?.has(v) ? "true" : "";
      if (r.same_as != null) v = v === str(x[r.same_as]) ? "true" : "";
      v = applyTx(v, r.tx);
      if (r.map) { const hit = r.map.find(([re]) => new RegExp(re).test(v)); v = hit ? hit[1] : (r.else ?? v) } else if (r.else != null && !v) v = r.else;
      x[name] = r.null_if_empty && !v ? null : v;
      if (r.only_if && !str(x[r.only_if])) omit.add(name);
    }
    if ((spec.require || []).some((f) => !str(x[f]))) continue;
    if ((spec.skip || []).some((s) => { const hit = new RegExp(s.regex, s.flags ?? "").test(str(x[s.field])); return s.not ? !hit : hit })) continue;
    const key = str(x[spec.key]), cmp = spec.compare || "course_title", prior = out.get(key);
    const rec: Record<string, unknown> = {};
    for (const f of spec.out) if (!omit.has(f)) rec[f] = x[f];
    if (prior) {
      if (spec.dedupe === "first") continue;
      if (spec.dedupe === "throw_dup") throw new Error(`duplicate key ${key}`);
      if (spec.dedupe === "last_unless_conflict" && prior[cmp] !== rec[cmp]) continue;
      if (spec.dedupe === "last_throw_conflict" && prior[cmp] !== rec[cmp]) throw new Error(`conflicting key ${key}`);
      if (spec.dedupe === "group") {
        for (const f of spec.group?.collect || []) { const v = rec[f] as string; const a = prior[f] as string[]; if (v && !a.includes(v)) a.push(v) }
        continue;
      }
    } else order.push(key);
    if (spec.dedupe === "group") for (const f of spec.group?.collect || []) { const v = rec[f] as string; rec[f] = v ? [v] : [] }
    out.set(key, rec);
  }
  return order.map((k) => ({ k, x: out.get(k)! }));
}

const asText = (r: Record<string, unknown>) => Object.fromEntries(Object.entries(r).map(([k, v]) => [k, v == null ? "" : Array.isArray(v) ? v.join("\u001f") : String(v)]));
export function itemsAdapterRecords(spec: ItemsSpec, text: string, now = new Date()) {
  return itemsAdapterRows(spec, text, now).map((r) => ({ k: r.k, x: asText(r.x) }));
}
export const itemsText = asText;
