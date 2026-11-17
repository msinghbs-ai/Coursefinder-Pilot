// CF-247 Wave 2 (S2-Build, 17 Nov 2026): reads a Layer 1 source file into a header row and rows, for an AI-built parser spec. Shared by
// layer1-ai-induction-mapper (re-infer samples) and the Layer 1 declarative runner. Formats: csv, xlsx, json (rows by a simple path such as
// $.data[*]) and html_table (Track B, 18 Nov 2026: one table on a web page, by source.table_index and source.header_row; cf247-html-table.js). No code is evaluated; the size limit is the caller's setting (layer1.declarative_max_file_mb).
import * as XLSX from "npm:xlsx@0.18.5";
import { htmlTableRows } from "./cf247-html-table.js";

export type Table = { headers: string[]; rows: Record<string, unknown>[]; arrays: string[][]; bytes: Uint8Array };

export async function fetchBytes(url: string, maxBytes: number, timeoutMs = 60000): Promise<Uint8Array> {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs); // the caller passes its fixed API time-out
  try {
    const r = await fetch(url, { signal: ctl.signal, redirect: "follow", headers: { "user-agent": "coursefinder-layer1-declarative/1.0" } });
    if (!r.ok) throw new Error(`HTTP ${r.status} from ${url}`);
    const len = Number(r.headers.get("content-length") || 0);
    if (len && len > maxBytes) throw new Error(`the file is ${len} bytes, over the limit of ${maxBytes}`);
    const b = new Uint8Array(await r.arrayBuffer());
    if (b.length > maxBytes) throw new Error(`the file is ${b.length} bytes, over the limit of ${maxBytes}`);
    return b;
  } finally {
    clearTimeout(timer);
  }
}

// RFC 4180 CSV: quoted fields, doubled quotes, line breaks inside quotes
export function parseCsv(text: string, delimiter = ","): string[][] {
  const out: string[][] = [];
  let row: string[] = [], field = "", q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else q = false; }
      else field += c;
    } else if (c === '"') q = true;
    else if (c === delimiter) { row.push(field); field = ""; }
    else if (c === "\n" || c === "\r") { if (c === "\r" && text[i + 1] === "\n") i++; row.push(field); out.push(row); row = []; field = ""; }
    else field += c;
  }
  if (field !== "" || row.length) { row.push(field); out.push(row); }
  return out.filter((r) => r.some((v) => v.trim() !== ""));
}

function rowsAt(doc: unknown, path: string): unknown[] {
  // $.a.b[*] : names and [*] only (the spec check allows nothing else)
  let cur: unknown[] = [doc];
  for (const part of path.replace(/^\$\.?/, "").split(".").filter(Boolean)) {
    const m = part.match(/^([A-Za-z_][A-Za-z0-9_]*)(\[\*\])?$/);
    if (!m) throw new Error(`rows_path part "${part}" is not allowed`);
    cur = cur.flatMap((x) => {
      const v = x && typeof x === "object" ? (x as Record<string, unknown>)[m[1]] : undefined;
      return m[2] ? (Array.isArray(v) ? v : []) : (v === undefined ? [] : [v]);
    });
  }
  return cur.length === 1 && Array.isArray(cur[0]) ? (cur[0] as unknown[]) : cur;
}

export function readTable(bytes: Uint8Array, format: string, source: Record<string, unknown> = {}, maxRows = Infinity): Table {
  const headerRow = Math.max(1, Math.floor(Number(source.header_row) || 1));
  if (format === "csv") {
    const text = new TextDecoder("utf-8").decode(bytes).replace(/^﻿/, "");
    const grid = parseCsv(text, typeof source.delimiter === "string" ? source.delimiter : ",");
    const headers = (grid[headerRow - 1] || []).map((h) => h.trim());
    const arrays = grid.slice(headerRow, headerRow + (Number.isFinite(maxRows) ? maxRows : grid.length));
    return { headers, arrays, rows: arrays.map((r) => Object.fromEntries(headers.map((h, i) => [h, r[i] ?? null]))), bytes };
  }
  if (format === "xlsx") {
    const sheet = typeof source.sheet === "string" ? source.sheet : undefined;
    const wb = XLSX.read(bytes, { type: "array", ...(sheet ? { sheets: [sheet] } : {}) });
    const ws = wb.Sheets[sheet || wb.SheetNames[0]];
    if (!ws) throw new Error(`sheet "${sheet}" not found (sheets: ${wb.SheetNames.join(", ")})`);
    const grid = (XLSX.utils.sheet_to_json(ws, { header: 1, raw: false, defval: "" }) as unknown[][]).map((r) => r.map((v) => String(v ?? "")));
    const headers = (grid[headerRow - 1] || []).map((h) => h.trim());
    const arrays = grid.slice(headerRow).filter((r) => r.some((v) => v.trim() !== "")).slice(0, Number.isFinite(maxRows) ? maxRows : undefined);
    return { headers, arrays, rows: arrays.map((r) => Object.fromEntries(headers.map((h, i) => [h, r[i] ?? null]))), bytes };
  }
  if (format === "json") {
    const doc = JSON.parse(new TextDecoder("utf-8").decode(bytes));
    const items = rowsAt(doc, typeof source.rows_path === "string" ? source.rows_path : "$").filter((x) => x && typeof x === "object") as Record<string, unknown>[];
    const picked = items.slice(0, Number.isFinite(maxRows) ? maxRows : undefined);
    const headers = [...new Set(picked.slice(0, 50).flatMap((x) => Object.keys(x)))];
    const rows = picked.map((x) => Object.fromEntries(headers.map((h) => [h, x[h] === null || x[h] === undefined ? null : typeof x[h] === "object" ? JSON.stringify(x[h]) : x[h]])));
    return { headers, rows, arrays: rows.map((r) => headers.map((h) => String(r[h] ?? ""))), bytes };
  }
  if (format === "html_table") {
    const html = new TextDecoder("utf-8").decode(bytes);
    const t = htmlTableRows(html, source, Number.isFinite(maxRows) ? maxRows : Infinity);
    const headers = t.headers.map((h) => String(h).trim());
    const arrays = t.arrays.map((r) => headers.map((_, i) => String(r[i] ?? "")));
    return { headers, arrays, rows: arrays.map((r) => Object.fromEntries(headers.map((h, i) => [h, r[i] === "" ? null : r[i]]))), bytes };
  }
  throw new Error(`format ${format} is not read by the declarative reader (csv, xlsx, json and html_table are)`);
}
