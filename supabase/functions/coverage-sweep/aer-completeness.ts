// AER v2 step 0, independent table completeness (Decision 276 amendment 2, Platform Admin 12 Nov 2026: "Independently verify table completeness against the source
// document rather than relying on the AI reader to report what it missed"). Pure functions: nothing here reads, writes or admits.
// A country table's converted text (pdfTables, the HTML table converter, or an aligned grid) prints one row label per applicant country or board. This counts
// the countries the table's row labels name, from the stored page alone, and compares them with the countries of the records a reader returned:
//   printed  - countries a table row label names (a row is a line in the "| a | b |" form the converters write, or a grid cell's row label);
//   recorded - countries of the returned records;
//   missing  - printed but not recorded: the read is incomplete for them, whatever the reader said it dropped;
//   extra    - recorded but not printed in any row label (named in prose, or a heading): for a person to see, not an error by itself.
// The measure needs no model and no list setting: the country index is the reference countries (svc_entry_country_refs_v1) plus the governed aliases.
import type { EntryCountryRef } from "./entry.ts";
import { entryCellCountryIndex } from "./entry-cells.ts";

export const AER_COMPLETENESS_METHOD = "table-row-countries-v1";
const words = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, " ").trim();

// the first cell of each table row, as the converters write rows ("| Nepal | ... |"), or a whole short line that is only a label
export function tableRowLabels(text: string): string[] {
  const out: string[] = [];
  for (const raw of String(text || "").split("\n")) {
    const line = raw.trim();
    if (line.startsWith("|")) {
      const cell = line.split("|").map((c) => c.trim()).filter(Boolean)[0] || "";
      // "Head: label" cells (the cell reader's "| Country: Nepal | ... |") keep the label after the colon
      out.push(cell.includes(":") ? cell.slice(cell.indexOf(":") + 1).trim() : cell);
    }
  }
  return out;
}

// the one country a row label names: the label is the country's name or alias, or begins with it ("Nepal (NEB)", "India CBSE"); otherwise none (never guessed)
export function labelCountry(label: string, index: Map<string, string>): string | null {
  const w = words(label);
  if (!w) return null;
  if (index.has(w)) return index.get(w)!;
  const hits = new Set<string>();
  for (const [name, cc] of index) if (name.length > 3 && (w === name || w.startsWith(name + " "))) hits.add(cc);
  return hits.size === 1 ? [...hits][0] : null;
}

export type TableCompleteness = { method: string; printed: string[]; recorded: string[]; missing: string[]; extra: string[]; complete: boolean };
export function tableCompleteness(text: string, records: { country_code?: string | null }[], refs: EntryCountryRef[], aliases: Record<string, string> = {}): TableCompleteness {
  const index = entryCellCountryIndex(refs, aliases);
  const printed = [...new Set(tableRowLabels(text).map((l) => labelCountry(l, index)).filter((c): c is string => !!c))].sort();
  const recorded = [...new Set((records || []).map((r) => String(r?.country_code || "").toUpperCase()).filter((c) => /^[A-Z]{2}$/.test(c)))].sort();
  const missing = printed.filter((c) => !recorded.includes(c)), extra = recorded.filter((c) => !printed.includes(c));
  return { method: AER_COMPLETENESS_METHOD, printed, recorded, missing, extra, complete: missing.length === 0 };
}
