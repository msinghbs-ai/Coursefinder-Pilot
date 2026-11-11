// v0.72.0 (CF-247 F-AER.08 step 2; Platform Admin 11 Nov 2026 decision 1: "Every extracted minimum must map to exactly one course and one qualification ... Support IB,
// GCE A Levels, Gao Kao, Indian CBSE and other recognised qualifications using the approved qualification-first model. Reject ambiguous or conflicting mappings").
// A proven course-by-qualification grid (pdf-grid.ts) becomes requirement rows in the shape the model returns, so entryMatrixParsed runs every check on them:
//   - each column heading is classified once: a country (Spain), an education board naming one country (India AISSCE), an international qualification
//     (IB, GCE A Level), a course fact (CRICOS, fee, duration, intake, English test: not a requirement of a qualification), or unknown;
//     the governed heading list (reading.entry_grid_headings, "HKDSE=HK", "Gao Kao=CN", "EB=@EB", "CRICOS=fact") is read first, then the cell reader's rules;
//   - a heading naming two qualifications ("GCE AL or NCUK") gives one row for each; a heading that cannot be classified is never guessed: its cells are dropped
//     with reason grid_heading_unmapped (the read is then held by the D-R3 gate until the heading list names it);
//   - each cell gives one row per course: course_name is the printed course label (linked to the catalogue course later, step 3), the minimum exactly as printed,
//     its number only when the cell is one number, and its scale from the cell or the heading (%, GPA, ATAR rank, letter grade); "N/A" gives no row
//     (no_minimum_published, ignored by the gate setting);
//   - the quote is the cell line the grid gives ("| Course: B Science | IB: 29 |"); its page and coordinates are kept in conditions.
import type { EntryCountryRef, EntryQualification } from "./entry.ts";
import { entryCellCountryIndex, entryCellLabel } from "./entry-cells.ts";
import type { GridTable } from "./pdf-grid.ts";

export const ENTRY_GRID_READER = "pdf-grid-v1";

export type HeadingKind = { kind: "country" | "board" | "qualification" | "fact" | "unknown"; country: string | null; qualification: string | null; head: string };
const words = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, " ").trim();

// the governed list: "TOKEN=CC" a country, "TOKEN=@CODE" a qualification, "TOKEN=fact" a course fact; a token matches as whole words
export function entryGridHeadingList(list: unknown): { token: string; to: string }[] {
  return (Array.isArray(list) ? list : []).map((x) => String(x)).filter((x) => x.includes("=")).map((x) => ({ token: words(x.split("=")[0]), to: x.split("=").slice(1).join("=").trim() }))
    .filter((x) => x.token && x.to).sort((a, b) => b.token.length - a.token.length);
}

export function entryGridHeading(head: string, refs: EntryCountryRef[], quals: EntryQualification[], list: { token: string; to: string }[], aliases: Record<string, string> = {}): HeadingKind[] {
  const w = ` ${words(head)} `;
  const one = (part: string): HeadingKind => {
    const pw = ` ${words(part)} `;
    const hit = list.find((x) => pw.includes(` ${x.token} `));
    // course facts first (CRICOS, fee, English test); then the standard identity rules; the governed list fills only what those rules cannot name
    if (hit && hit.to.toLowerCase() === "fact") return { kind: "fact", country: null, qualification: null, head: part };
    const r = entryCellLabel(part, entryCellCountryIndex(refs, aliases), quals);
    if (r.kind !== "unknown") return { kind: r.kind, country: r.country, qualification: r.qualification, head: part };
    if (hit?.to.startsWith("@")) return { kind: "qualification", country: null, qualification: hit.to.slice(1).toUpperCase(), head: part };
    if (hit && /^[A-Z]{2}$/.test(hit.to)) return { kind: "board", country: hit.to, qualification: null, head: part };
    return { kind: "unknown", country: null, qualification: r.qualification, head: part };
  };
  // a heading naming two qualifications ("GCE AL or NCUK"): one row each, only when both parts are recognised; otherwise the whole heading is read as one
  // both parts must be named; one part unknown makes the whole heading unknown (never read as the other part alone)
  const parts = head.split(/\s+or\s+/i);
  if (parts.length === 2) {
    const a = one(parts[0]), b = one(parts[1]);
    if (a.kind === "unknown" || b.kind === "unknown") return [{ kind: "unknown", country: null, qualification: null, head }];
    if (a.kind !== "fact" && b.kind !== "fact") return [a, b];
  }
  void w;
  return [one(head)];
}

// the minimum a cell prints: its words, its number when the cell is one number, and its scale
export function entryGridValue(value: string, head: string): { grade: string | null; value: number | null; scale: string } | null {
  const v = String(value || "").replace(/\*+$/, "").trim();
  if (!v || /^(?:N\/A|n\/a|NA|-|–|—)$/.test(v)) return null;
  const h = head.toLowerCase();
  const num = /^(\d{1,4}(?:\.\d{1,3})?)(%?)$/.exec(v.replace(/,/g, ""));
  if (num) {
    const n = Number(num[1]);
    const scale = num[2] ? "percentage" : /\bgpa\b/.test(h) ? "gpa" : /\batar\b|tertiary admission rank|\brank\b/.test(h) ? "rank" : "points";
    return { grade: value.trim(), value: Number.isFinite(n) ? n : null, scale };
  }
  if (/^[A-E][0-9]?$|^[A-E]\*?[A-E]{1,3}$/.test(v)) return { grade: value.trim(), value: null, scale: "letter" };
  // a pair ("14/14"), a grade with a note ("7.3/C+"), a misprint ("3..6"): kept as printed with no single number
  return { grade: value.trim(), value: null, scale: "none" };
}

export type GridRead = { answer: { rows: any[] }; qualification_rows_hint: number; dropped: { reason: string; country: string; quote: string }[];
                         columns: { head: string; kind: string; country: string | null; qualification: string | null }[]; stats: Record<string, number> };
export function entryGridRead(tables: GridTable[], refs: EntryCountryRef[], quals: EntryQualification[], list: { token: string; to: string }[],
                              aliases: Record<string, string> = {}): GridRead {
  const rows: any[] = [], dropped: GridRead["dropped"] = [], stats: Record<string, number> = {};
  const bump = (k: string) => { stats[k] = (stats[k] || 0) + 1 };
  const columns: GridRead["columns"] = [];
  let qhint = 0;
  for (const t of tables) {
    const kinds = new Map<string, HeadingKind[]>(t.heads.map((h) => [h, entryGridHeading(h, refs, quals, list, aliases)]));
    for (const [h, ks] of kinds) for (const k of ks) if (!columns.some((c) => c.head === h && c.kind === k.kind && c.country === k.country && c.qualification === k.qualification))
      columns.push({ head: h, kind: k.kind, country: k.country, qualification: k.qualification });
    // the course's CRICOS code where the table prints one on the course's row (decision 2 step 1: the code links the course; kept beside the row, never a minimum)
    const cricos = new Map<string, string>();
    for (const c of t.cells) if (/\bcricos\b/i.test(c.head) && /^[0-9]{6}[0-9A-Z]$/.test(String(c.value || "").trim().toUpperCase())) cricos.set(c.label, String(c.value).trim().toUpperCase());
    for (const c of t.cells) {
      const quote = `| ${t.labelHead}: ${c.label} | ${c.head}: ${c.value} |`;
      for (const k of kinds.get(c.head) || []) {
        if (k.kind === "fact") { bump("fact_cells"); continue }
        if (k.kind === "unknown") { dropped.push({ reason: "grid_heading_unmapped", country: c.head, quote: quote.slice(0, 120) }); bump("unmapped_cells"); continue }
        const min = entryGridValue(c.value, c.head);
        if (!min) { dropped.push({ reason: "no_minimum_published", country: k.country || k.qualification || c.head, quote: quote.slice(0, 120) }); bump("not_applicable"); continue }
        if (k.kind === "qualification") qhint++;
        rows.push({
          country_code: k.kind === "qualification" ? "" : k.country,
          country_name: k.kind === "qualification" ? (quals.find((q) => q.code === k.qualification)?.aliases?.[0] || k.head) : k.country,
          study_level: /^(B|Bachelor)\b/.test(c.label) ? "Bachelor" : /^(M|Master)\b/.test(c.label) ? "Master" : /^(D|Doctor)\b/.test(c.label) ? "Doctor" : null,
          qualification_name: k.head, min_grade: min.grade, min_value: min.value, grade_scale: min.scale, benchmark_band: null, course_name: c.label,
          conditions: { best_n: null, alternatives: [], subject_minimums: [], reader: ENTRY_GRID_READER, section: c.section || null, ...(cricos.has(c.label) ? { cricos_code: cricos.get(c.label) } : {}),
                        place: { page: c.page, x: Math.round(c.x * 10) / 10, y: Math.round(c.y * 10) / 10 }, ...(min.value == null ? { printed_without_single_number: true } : {}) },
          confidence: 1, quote: quote.slice(0, 300),
        });
        bump("rows");
      }
    }
  }
  return { answer: { rows }, qualification_rows_hint: qhint, dropped, columns, stats };
}
