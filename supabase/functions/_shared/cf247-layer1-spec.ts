// CF-247 Wave 2 (S2-Build, 17 Nov 2026): applies an AI-built Layer 1 parser spec to rows. Shared by layer1-ai-induction-mapper (sample check)
// and the Layer 1 declarative runner. A spec only names columns, fixed types and fixed transforms (security.layer1_parser_spec_validate_v1
// checks it first); nothing here evaluates code or builds SQL.

export type SpecField = { source: string; target: string; type: string; required?: boolean; transforms?: { op: string; arg?: unknown }[] };
export type Spec = {
  spec_version: number; record_type: string; target_table: string; format: string; source?: Record<string, unknown>;
  expected_headers?: string[]; fields: SpecField[]; unique_key: string[]; attribution_text: string; evidence?: { bind: string }; currency?: string;
};

const MONTHS: Record<string, number> = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12 };
const pad = (n: number) => String(n).padStart(2, "0");

function toIsoDate(v: string, pattern: string | null): string | null {
  const s = v.trim();
  let y = 0, m = 0, d = 0, x: RegExpMatchArray | null;
  const p = pattern || "YYYY-MM-DD";
  if (p === "YYYY-MM-DD" || p === "YYYY/MM/DD") { x = s.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})/); if (x) [y, m, d] = [+x[1], +x[2], +x[3]]; }
  else if (p === "DD/MM/YYYY" || p === "DD-MM-YYYY") { x = s.match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$/); if (x) [d, m, y] = [+x[1], +x[2], +x[3]]; }
  else if (p === "MM/DD/YYYY") { x = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/); if (x) [m, d, y] = [+x[1], +x[2], +x[3]]; }
  else if (p === "D MMM YYYY") { x = s.match(/^(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\s+(\d{4})$/); if (x && MONTHS[x[2].toLowerCase()]) [d, m, y] = [+x[1], MONTHS[x[2].toLowerCase()], +x[3]]; }
  if (!y || m < 1 || m > 12 || d < 1 || d > 31) return null;
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCMonth() !== m - 1) return null;
  return `${y}-${pad(m)}-${pad(d)}`;
}

export function transformValue(raw: unknown, field: SpecField): { value: string | number | boolean | null; error?: string } {
  let v: string | null = raw === null || raw === undefined ? null : String(raw);
  let datePattern: string | null = null;
  for (const t of field.transforms || []) {
    if (t.op === "trim" && v !== null) v = v.replace(/\s+/g, " ").trim();
    else if (t.op === "upper" && v !== null) v = v.toUpperCase();
    else if (t.op === "lower" && v !== null) v = v.toLowerCase();
    else if (t.op === "strip_currency" && v !== null) v = v.replace(/[^0-9.\-]/g, "");
    else if (t.op === "first_token" && v !== null) v = v.trim().split(/\s+/)[0] || "";
    else if (t.op === "default" && (v === null || v.trim() === "")) v = String(t.arg ?? "");
    else if (t.op === "map_values" && v !== null) { const m = (t.arg || {}) as Record<string, string>; if (Object.prototype.hasOwnProperty.call(m, v.trim())) v = m[v.trim()]; }
    else if (t.op === "date_format") datePattern = String(t.arg || "");
  }
  if (v !== null && v.trim() === "") v = null;
  if (v === null) return field.required ? { value: null, error: `${field.target} is empty` } : { value: null };
  switch (field.type) {
    case "integer": { const n = Number(v.replace(/,/g, "")); return Number.isInteger(n) ? { value: n } : { value: null, error: `${field.target} "${v}" is not a whole number` }; }
    case "numeric": case "currency_amount": { const n = Number(v.replace(/,/g, "").replace(/^\$/, "")); return Number.isFinite(n) ? { value: n } : { value: null, error: `${field.target} "${v}" is not a number` }; }
    case "date": { const d = toIsoDate(v, datePattern); return d ? { value: d } : { value: null, error: `${field.target} "${v}" is not a date${datePattern ? ` in ${datePattern}` : ""}` }; }
    case "boolean": { const s = v.trim().toLowerCase(); if (["true", "yes", "y", "1"].includes(s)) return { value: true }; if (["false", "no", "n", "0"].includes(s)) return { value: false }; return { value: null, error: `${field.target} "${v}" is not yes or no` }; }
    case "url": return /^https?:\/\/\S+$/i.test(v.trim()) ? { value: v.trim() } : { value: null, error: `${field.target} "${v}" is not a web address` };
    case "code": return { value: v.trim() };
    default: return { value: v };
  }
}

// Rows are objects keyed by source column (tabular) or key (JSON). Returns the canonical records and the problems found.
export function applySpec(spec: Spec, rows: Record<string, unknown>[], maxErrors = 20) {
  const records: Record<string, unknown>[] = [];
  const errors: string[] = [];
  rows.forEach((row, i) => {
    const rec: Record<string, unknown> = {};
    let bad = false;
    for (const f of spec.fields) {
      const r = transformValue(row[f.source], f);
      if (r.error) { bad = bad || !!f.required; if (errors.length < maxErrors) errors.push(`Row ${i + 1}: ${r.error}.`); }
      rec[f.target] = r.value;
    }
    if (spec.currency && !rec.currency_code && spec.fields.some((f) => f.type === "currency_amount")) rec.currency_code = spec.currency;
    if (!bad) records.push(rec);
  });
  return { records, errors };
}

// Layout drift: the expected headers that are missing from the file's headers.
export function missingHeaders(spec: Spec, headers: string[]) {
  const have = new Set(headers.map((h) => String(h).trim()));
  return (spec.expected_headers || []).filter((h) => !have.has(String(h).trim()));
}

// The row key and a stable hash of the canonical record (deterministic row-hash diffing).
export async function rowKeyAndHash(spec: Spec, rec: Record<string, unknown>) {
  const key = spec.unique_key.map((k) => String(rec[k] ?? "").trim().toUpperCase()).join("|");
  const canon = JSON.stringify(Object.keys(rec).sort().map((k) => [k, rec[k]]));
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canon));
  return { key, hash: [...new Uint8Array(d)].map((x) => x.toString(16).padStart(2, "0")).join("") };
}
