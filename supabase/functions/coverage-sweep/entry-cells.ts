// v0.71.0 (11 Nov 2026, CF-247 F-AER.07 PDF cell reader; Platform Admin 11 Nov 2026 16:20 "build a reader for WSU based on the PDF ... reader need to recognise Country,
// qualification and minimum requirement in accordance with Country and their Education Boards", and 19:3x qualification-first decision item 5 "Update the PDF table reader
// to identify country, education board, qualification, academic level, grading scale and minimum requirement for every applicable row or cell"):
// a deterministic reader for a ruled PDF country table that pdfTables (pdf.ts, ruled-cells-v1) gives one line per cell:
//   | <first column>: <row label> | <level column>: <cell> |
// The row label is a country (Argentina), an education board that names its country (Indian School Certificate (ISC)) or an international qualification
// (International Baccalaureate Certificate (IB)); each level column is a study level (Undergraduate Degree). Each cell becomes one or more rows in the same shape the
// pinned model returns, so every existing check (quote on the page, grade and value in the quote, scale, qualification-first) runs on them unchanged
// (entry.ts entryMatrixParsed). Nothing is inferred that the cell does not print: a cell with several boards ("... (pre-2018) or Nepalese Education Board ...")
// gives one row per board that prints its own minimum; a cell that prints no minimum keeps its words as the requirement with no value; "Not applicable" gives no row.
// Pure functions only (no network, no AI): tests/uat/cf-247-f-aer-07-pdf-cell-reader-contract.spec.mjs runs them on the stored WSU table (fixture wsu.json.gz).
import type { EntryCountryRef, EntryQualification } from "./entry.ts";

export const ENTRY_CELL_READER = "pdf-cells-v1";

// common English names a table prints where the ISO short name differs (reference identity only; the country still has to be printed in the row label)
const COMMON: Record<string, string> = {
  "russia": "RU", "south korea": "KR", "korea": "KR", "republic of korea": "KR", "north korea": "KP", "iran": "IR", "taiwan": "TW", "vietnam": "VN", "viet nam": "VN",
  "laos": "LA", "syria": "SY", "tanzania": "TZ", "macau": "MO", "macao": "MO", "brunei": "BN", "turkey": "TR", "turkiye": "TR", "bolivia": "BO", "venezuela": "VE",
  "czech republic": "CZ", "czechia": "CZ", "moldova": "MD", "usa": "US", "united states of america": "US", "united states": "US", "uk": "GB", "great britain": "GB",
  "england": "GB", "scotland": "GB", "wales": "GB", "northern ireland": "GB", "uae": "AE", "the netherlands": "NL", "holland": "NL", "palestine": "PS",
  "ivory coast": "CI", "cote d ivoire": "CI", "swaziland": "SZ", "eswatini": "SZ", "burma": "MM", "east timor": "TL", "timor leste": "TL", "cape verde": "CV",
  "hong kong sar": "HK", "macau sar": "MO", "kyrgyz republic": "KG", "slovak republic": "SK", "micronesia": "FM", "congo dr": "CD", "dr congo": "CD",
};
// a country named by its adjective inside an education board's name ("Indian School Certificate"); only where the adjective names one country
const ADJECTIVE: Record<string, string> = {
  "indian": "IN", "all india": "IN", "chinese": "CN", "nepalese": "NP", "nepali": "NP", "sri lankan": "LK", "pakistani": "PK", "bangladeshi": "BD", "malaysian": "MY",
  "singaporean": "SG", "indonesian": "ID", "vietnamese": "VN", "thai": "TH", "japanese": "JP", "korean": "KR", "philippine": "PH", "filipino": "PH", "kenyan": "KE",
  "nigerian": "NG", "ghanaian": "GH", "german": "DE", "french": "FR", "italian": "IT", "spanish": "ES", "swedish": "SE", "norwegian": "NO", "danish": "DK",
  "finnish": "FI", "dutch": "NL", "polish": "PL", "greek": "GR", "turkish": "TR", "russian": "RU", "brazilian": "BR", "mexican": "MX", "argentinean": "AR",
  "argentine": "AR", "chilean": "CL", "colombian": "CO", "peruvian": "PE", "canadian": "CA", "irish": "IE", "scottish": "GB", "egyptian": "EG", "saudi": "SA",
  "omani": "OM", "kuwaiti": "KW", "qatari": "QA", "bahraini": "BH", "emirati": "AE", "jordanian": "JO", "lebanese": "LB", "iranian": "IR", "iraqi": "IQ",
  "mauritian": "MU", "fijian": "FJ", "bhutanese": "BT", "cambodian": "KH", "burmese": "MM", "taiwanese": "TW", "hong kong": "HK", "macanese": "MO",
};
const words = (s: unknown) => String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, " ").trim();

export type CellCountryIndex = Map<string, string>;
export function entryCellCountryIndex(refs: EntryCountryRef[], aliases: Record<string, string> = {}): CellCountryIndex {
  const m: CellCountryIndex = new Map();
  for (const [k, v] of Object.entries(COMMON)) m.set(k, v);
  for (const r of refs || []) {
    const a2 = String((r as any)?.a2 || "").toUpperCase(); if (!/^[A-Z]{2}$/.test(a2)) continue;
    for (const n of [(r as any)?.name, (r as any)?.official, String((r as any)?.name || "").split(",")[0]]) { const w = words(n); if (w && !m.has(w)) m.set(w, a2) }
  }
  for (const [k, v] of Object.entries(aliases || {})) { const w = words(k); if (w && /^[A-Z]{2}$/.test(v) && w.length > 2) m.set(w, v) }
  return m;
}

// what a row label is: a country (exact name), an education board naming one country (by name or adjective, as whole words), an international qualification, or unknown
export type CellLabel = { kind: "country" | "board" | "qualification" | "unknown"; country: string | null; qualification: string | null; label: string };
export function entryCellLabel(label: string, idx: CellCountryIndex, quals: EntryQualification[] = []): CellLabel {
  const w = words(label), out = (kind: CellLabel["kind"], country: string | null, qualification: string | null): CellLabel => ({ kind, country, qualification, label });
  if (idx.has(w)) return out("country", idx.get(w)!, null);
  // an international qualification's alias, as whole words (the longest wins), before any country word ("Cambridge International" names no country)
  let qbest: { code: string; n: number } | null = null;
  for (const q of quals) for (const a of q.aliases || []) { const aw = words(a); if (aw.length >= 2 && ` ${w} `.includes(` ${aw} `) && (!qbest || aw.length > qbest.n)) qbest = { code: q.code, n: aw.length } }
  // a board naming exactly one country by name or adjective (whole words); two different countries named is unknown
  const found = new Set<string>();
  for (const [k, v] of [...idx.entries(), ...Object.entries(ADJECTIVE)]) if (k.length >= 4 && ` ${w} `.includes(` ${k} `)) found.add(v);
  if (qbest && found.size === 0) return out("qualification", null, qbest.code);
  if (found.size === 1) return out("board", [...found][0], null);
  return out("unknown", null, qbest?.code ?? null);
}

// a minimum printed in a stretch of cell text: its words (exactly as printed), the number and the scale. Null when the text prints none.
export type CellMinimum = { grade: string; value: number | null; scale: "percentage" | "points" | "aggregate" | "gpa" | "letter" | "rank"; start: number; end: number };
const MINIMUMS: { re: RegExp; scale: CellMinimum["scale"]; value: boolean }[] = [
  { re: /\bGPA\s*(?:of\s*)?(?:at least\s*)?(\d(?:\.\d{1,2})?)(?:\s*(?:out of|\/)\s*\d(?:\.\d)?)?/i, scale: "gpa", value: true },
  { re: /\b(\d{1,2}(?:\.\d{1,2})?)\s*GPA\b/i, scale: "gpa", value: true },
  { re: /\bATAR\s*(?:of\s*)?(\d{2,3}(?:\.\d{1,2})?)/i, scale: "rank", value: true },
  { re: /\b(?:(?:an?\s+)?(?:overall\s+|minimum\s+|average\s+|aggregate\s+|final\s+)*(?:grade|mark|pass|average|score|result|percentage)\s+(?:average\s+)?(?:of\s+)?)?(?:at least\s+)?(\d{1,3}(?:\.\d{1,2})?)\s?%(?:\s+(?:average|overall|aggregate))?/i, scale: "percentage", value: true },
  { re: /\b(?:(?:a\s+)?(?:minimum\s+|overall\s+|total\s+)*score\s+of\s+|(?:minimum\s+of\s+)?)(\d{1,2}(?:\.\d)?)\s+points?\b/i, scale: "points", value: true },
  { re: /\b(?:a\s+)?(?:minimum\s+|overall\s+|total\s+)*score\s+of\s+(\d{1,3}(?:\.\d{1,2})?)\b/i, scale: "points", value: true },
  { re: /\b(?:an?\s+)?(?:minimum\s+|overall\s+|average\s+|final\s+)*grade\s+(?:average\s+)?of\s+(\d{1,2}(?:\.\d{1,2})?)\b(?!\s?%)/i, scale: "aggregate", value: true },
  { re: /\b(?:an?\s+)?(?:minimum\s+|overall\s+)*average\s+(?:grade\s+)?of\s+(\d{1,2}(?:\.\d{1,2})?)\b(?!\s?%)/i, scale: "aggregate", value: true },
  { re: /\b(?:minimum\s+of\s+(?:a\s+)?|grade\s+(?:average\s+)?of\s+)?([A-E][+-]?)\s+(?:grade\s+)?average\b/, scale: "letter", value: false },
];
export function entryCellMinimum(text: string): CellMinimum | null {
  let best: CellMinimum | null = null;
  for (const m of MINIMUMS) {
    const x = m.re.exec(text); if (!x) continue;
    const n = m.value ? Number(x[1]) : null;
    // a printed range ("4.6 to 5.0", "between 70 and 79") is kept as words with no single value: the bound that applies is the provider's to state
    const after = text.slice(x.index + x[0].length, x.index + x[0].length + 24);
    const range = m.value ? /^\s*(?:to|-|–|and)\s*\d+(?:\.\d+)?%?/.exec(after) : null;
    // the direction a grade printed with it ("4.0 or less", "70% or above") is part of the minimum's words
    const dir = !range ? /^\s+or\s+(?:less|lower|better|above|higher|more|greater)\b/i.exec(after) : null;
    const len = x[0].length + (range?.[0].length || dir?.[0].length || 0);
    const grade = text.slice(x.index, x.index + len).trim();
    const cand: CellMinimum = { grade, value: range || n == null || !Number.isFinite(n) ? null : n, scale: m.scale, start: x.index, end: x.index + len };
    if (!best || cand.start < best.start) best = cand;
  }
  return best;
}

// the qualification a stretch of cell text names: the words after "completion of" up to " with" (or the stretch itself), as printed
export function entryCellQualification(text: string): string {
  let t = String(text || "").trim();
  t = t.replace(/^(?:or\s+)?(?:a\s+)?(?:successful\s+)?(?:completion\s+of\s+)?(?:any\s+of\s+the\s+following:\s*)?(?:the\s+)?/i, "");
  const cut = /\s+(?:with|from)\s+|,\s+(?:with|from)\s+/i.exec(t);
  return (cut ? t.slice(0, cut.index) : t).replace(/[\s,;:.]+$/, "").slice(0, 200);
}

// the boards one cell prints: split at " or " only where both sides print a minimum of their own; otherwise one stretch
export function entryCellAlternatives(cell: string): { text: string; offset: number }[] {
  const parts: { text: string; offset: number }[] = [];
  const re = /,?\s+or\s+/gi; let from = 0, x: RegExpExecArray | null;
  while ((x = re.exec(cell))) {
    const left = cell.slice(from, x.index), right = cell.slice(x.index + x[0].length);
    if (entryCellMinimum(left) && entryCellMinimum(right)) { parts.push({ text: left, offset: from }); from = x.index + x[0].length }
  }
  parts.push({ text: cell.slice(from), offset: from });
  return parts;
}

// one cell line of a ruled PDF table
export type CellLine = { line: string; head: string; label: string; level: string; cell: string };
const LINE = /^\| ([^|:]{2,60}): ([^|]+?) \| ([^|:]{2,80}): (.*?) \|$/;
export function entryCellLines(page: string): { lines: CellLine[]; heads: string[]; levels: string[] } {
  const all: CellLine[] = [];
  for (const raw of String(page || "").split("\n")) {
    const m = LINE.exec(raw.trim()); if (!m) continue;
    all.push({ line: raw.trim(), head: m[1].trim(), label: m[2].trim(), level: m[3].trim(), cell: m[4].trim() });
  }
  // the first column is the header most lines start with; levels are the column headers that follow it
  const count = new Map<string, number>(); for (const l of all) count.set(l.head, (count.get(l.head) || 0) + 1);
  const head = [...count.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  const lines = all.filter((l) => l.head === head);
  const levels = [...new Set(lines.map((l) => l.level))];
  return { lines, heads: head ? [head] : [], levels };
}

// The reader: a page is read by cells only when its proven PDF table is this shape (one first column, at least minLevels level columns, at least minLines cell
// lines, and every row label giving a cell for most levels); otherwise null and the page goes to the pinned model as before.
export type CellRead = { answer: { rows: any[] }; dropped: { reason: string; country: string; quote: string }[]; stats: Record<string, number>; levels: string[] };
export function entryCellRead(page: string, refs: EntryCountryRef[], quals: EntryQualification[] = [], aliases: Record<string, string> = {},
                              opt: { minLevels?: number; minLines?: number } = {}): CellRead | null {
  const { lines, levels } = entryCellLines(page);
  const minLevels = opt.minLevels ?? 4, minLines = opt.minLines ?? 20;
  if (levels.length < minLevels || lines.length < minLines) return null;
  const perLabel = new Map<string, Set<string>>(); for (const l of lines) { if (!perLabel.has(l.label)) perLabel.set(l.label, new Set()); perLabel.get(l.label)!.add(l.level) }
  const full = [...perLabel.values()].filter((s) => s.size >= Math.ceil(levels.length * 0.75)).length;
  if (full < Math.ceil(perLabel.size * 0.9)) return null;  // not a country-by-level grid
  const idx = entryCellCountryIndex(refs, aliases);
  const rows: any[] = [], dropped: CellRead["dropped"] = [], stats: Record<string, number> = { cells: lines.length, labels: perLabel.size };
  const bump = (k: string) => { stats[k] = (stats[k] || 0) + 1 };
  for (const l of lines) {
    const who = entryCellLabel(l.label, idx, quals);
    const prefix = `${l.head}: ${l.label} | ${l.level}: `;
    if (/^(?:not applicable|n\/a|-|–|—)$/i.test(l.cell)) { dropped.push({ reason: "no_minimum_published", country: who.country || l.label, quote: (prefix + l.cell).slice(0, 120) }); bump("not_applicable"); continue }
    if (who.kind === "unknown") { dropped.push({ reason: "unknown_country", country: l.label, quote: (prefix + l.cell).slice(0, 120) }); bump("unknown_label"); continue }
    const alts = entryCellAlternatives(l.cell);
    let prevQual = "";
    alts.forEach((a, i) => {
      const min = entryCellMinimum(a.text);
      // the quote is the printed text from the row label up to this board's minimum (the board's own words when that is over 300 characters), at most 300
      const endInCell = a.offset + (min ? min.end : a.text.length);
      let quote = prefix + l.cell.slice(0, endInCell);
      if (quote.length > 300) quote = l.cell.slice(a.offset, endInCell);
      if (quote.length > 300) quote = l.cell.slice(Math.max(a.offset, endInCell - 300), endInCell);
      quote = quote.trim().replace(/[\s,;]+$/, "");
      // the board's words without its minimum ("SMA3 50%" is SMA3); a stretch that is only a minimum ("or 5.0 GPA") is the board before it
      let own = entryCellQualification(min ? a.text.slice(0, min.start) + a.text.slice(min.end) : a.text).replace(/\s{2,}/g, " ").replace(/[\s,;:.]+$/, "").trim()
        .replace(/^(?:on|in|at|with)\s+/i, "").replace(/(?:[\s,]+(?:with|from|of|in|on|at|and|an?|the|minimum|overall))+$/i, "").trim();
      // a stretch that is only a further minimum for the same qualification ("SMA3 50% or 5.0 GPA") is one requirement printed two ways: it stays on the row
      // before it as an equivalent minimum, never a second row with the same identity (the D-R3 gate holds two rows of one identity)
      if (!/[A-Za-z]{2}/.test(own) && prevQual && rows.length && min) {
        const prev = rows[rows.length - 1];
        prev.conditions.equivalent_minimums = [...(prev.conditions.equivalent_minimums || []), { min_grade: min.grade, min_value: min.value, grade_scale: min.scale }];
        bump("equivalent_minimums"); return;
      }
      prevQual = own;
      // a board row's qualification is the board, unless the cell names a different award (a degree for postgraduate entry), which it then is
      const degree = /\b(bachelor|degree|diploma of|university studies|aqf)\b/i.test(own);
      const qualName = who.kind === "board" ? (degree ? own : alts.length > 1 ? `${l.label}: ${own}` : l.label)
                     : who.kind === "qualification" ? l.label : own;
      const others = alts.filter((_, j) => j !== i).map((b) => b.text.trim().slice(0, 200));
      // words after the minimum that the alternative still prints (a further pathway with no minimum of its own) are kept as conditions, as printed
      const rest = min ? a.text.slice(min.end).replace(/^[\s,;)]+/, "").trim() : "";
      // the same requirement printed for several boards of one country (India's postgraduate cell under each board) is one row: the boards are listed on it
      const same = rows.find((r) => r.country_code === (who.country || "") && r.study_level === l.level && r.qualification_name === qualName
                                   && r.min_grade === (min ? min.grade : null) && r.conditions.reader === ENTRY_CELL_READER);
      if (same) {
        if (who.kind === "board") same.conditions.education_boards = [...new Set([...(same.conditions.education_boards || [same.conditions.education_board].filter(Boolean)), l.label])];
        bump("same_requirement_boards"); return;
      }
      rows.push({
        country_code: who.country || "", country_name: who.kind === "country" ? l.label : who.kind === "board" ? who.country : l.label,
        study_level: l.level, qualification_name: qualName,
        min_grade: min ? min.grade : null, min_value: min ? min.value : null, grade_scale: min ? (min.value == null && min.scale !== "letter" ? "none" : min.scale) : "none",
        benchmark_band: null, course_name: null,
        conditions: { best_n: null, alternatives: others, subject_minimums: [], reader: ENTRY_CELL_READER, ...(who.kind === "board" ? { education_board: l.label } : {}),
                      ...(rest && /\b(or|and|plus)\b/i.test(rest) ? { also_printed: rest.slice(0, 300) } : {}), ...(!min ? { no_printed_minimum: true } : {}) },
        confidence: 1, quote,
      });
      bump(min ? "rows_with_minimum" : "rows_without_minimum"); if (alts.length > 1) bump("board_rows");
    });
  }
  return { answer: { rows }, dropped, stats, levels };
}
