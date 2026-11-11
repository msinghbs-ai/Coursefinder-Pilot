// v0.72.0 (CF-247 F-AER.08 aligned grid proof; Platform Admin 11 Nov 2026 23:2x, decision 1 "Aligned proof, fail closed": "Accept tables without drawn row boundaries
// where column alignment and course-row identity are reliably proven. Every extracted minimum must map to exactly one course and one qualification. Preserve the
// qualification heading, course label, score, exact quote, source page and extraction coordinates ... Reject ambiguous or conflicting mappings").
// A course-by-qualification PDF table (UNSW, Sydney, UQ: one row per course, one column per qualification) whose rows have no drawn rules is rebuilt from the
// alignment of its values instead of from rules (pdf.ts ruled-cells-v1 holds these documents). The proof, which fails closed for the whole page:
//   - a data line is a line with at least minValues printed values (scores, N/A, codes); its row label is the text left of its first value;
//   - the value columns are the x positions that values share on at least half of the data lines; every value on every data line must sit in exactly one
//     column, and no column may hold two values of one line;
//   - every column has a heading: the text printed over (or, rotated, beside) it in the band just above the first data line, inside that column's span;
//   - a label printed on lines of its own belongs to the data line beside it only when that data line prints no label; otherwise it is a section heading.
// Each value becomes a cell line "| <label heading>: <row label> | <column heading>: <value> |" (the same shape the cell reader takes), and its page and
// coordinates are kept. Pure functions, tested against the stored PDFs' positioned items (tests/fixtures/entry-matrix/pdf).
import type { PdfItem, PdfPage } from "./pdf.ts";

export const PDF_GRID_METHOD = "aligned-grid-v1";

// a printed value of a grid cell: a score, a band, a code or "not applicable"; never a word
export const GRID_VALUE = /^(?:N\/A|n\/a|NA|-|–|—|\d{1,4}(?:\.\d{1,3})?%?\*{0,2}|\d{1,2}\/\d{1,2}|\d+(?:\.\s?\d+)?\s?\(\d+(?:\.\d+)?(?:\/\d+)?\)\*{0,2}|[A-E][0-9]?\*{0,2}|[A-E]\*?[A-E]{1,3}|\$?\d{1,3}(?:,\d{3})+|\d{6}[A-Z]|\d\+\d|\d(?:\.\d)?–\d(?:\.\d)?|\d(?:,\s?\d)+|\d[\d.]*\d|\d+(?:\.\d+)?\/[A-E][+-]?|(?:Feb|Mar|Jul|Aug|Sep|Nov)(?:\/(?:Feb|Mar|Jul|Aug|Sep|Nov))*)$/;

const median = (a: number[]) => { const s = [...a].sort((x, y) => x - y); return s.length ? s[s.length >> 1] : 0 };
// private-use glyphs (icons a PDF draws with a symbol font) are not text
const clean = (s: string) => String(s || "").replace(/[\uE000-\uF8FF]/g, "").replace(/\s+/g, " ").trim();

export type GridCell = { label: string; section: string; head: string; value: string; page: number; x: number; y: number };
export type GridTable = { page: number; labelHead: string; heads: string[]; rows: number; cells: GridCell[] };
export type GridResult = { status: "ok" | "unparsed" | "no_table"; reason: string; method: string; tables: GridTable[]; text: string };

type Line = { y: number; items: PdfItem[] };
function lines(its: PdfItem[], H: number): Line[] {
  const out: Line[] = [];
  for (const it of [...its].sort((a, b) => b.y - a.y || a.x - b.x)) {
    const l = out[out.length - 1];
    if (l && Math.abs(l.y - it.y) <= 0.35 * H) l.items.push(it); else out.push({ y: it.y, items: [it] });
  }
  for (const l of out) l.items.sort((a, b) => a.x - b.x);
  return out;
}

export type GridOptions = { minValues?: number; minRows?: number; support?: number };
// one page's grid, or null when the page has none; throws (held) when a grid is there but cannot be proven
export function pdfGridPage(pg: PdfPage, opt: GridOptions = {}): GridTable | null {
  const minValues = opt.minValues ?? 6, minRows = opt.minRows ?? 5, support = opt.support ?? 0.2;
  const raw = pg.items.map((i) => ({ ...i, s: clean(i.s) })).filter((i) => i.s);
  const H = median(raw.map((i) => i.h).filter((h) => h > 0)) || 8;
  // pieces of one word drawn touching on one baseline ("13" "6" "0" for 1360) are one item, as pdf.ts lineText joins them
  const its: PdfItem[] = [];
  for (const it of [...raw].sort((a, b) => b.y - a.y || a.x - b.x)) {
    const p = its[its.length - 1];
    if (p && Math.abs(p.y - it.y) <= 0.1 * H && it.x - (p.x + p.w) >= -0.5 && it.x - (p.x + p.w) < 0.12 * H) { p.s += it.s; p.w = it.x + it.w - p.x }
    else its.push({ ...it });
  }
  const ls = lines(its, H);
  const isVal = (it: PdfItem) => GRID_VALUE.test(it.s);
  const data = ls.filter((l) => l.items.filter(isVal).length >= minValues);
  if (data.length < minRows) return null;
  // the first value of a data line marks where its values start; text left of it is the row label
  const firstVal = (l: Line) => l.items.find((it, i) => isVal(it) && l.items.slice(i).filter(isVal).length >= minValues - 1)!;
  const startX = median(data.map((l) => firstVal(l).x));
  // value columns: x positions shared by values on at least `support` of the data lines (a value may sit a little left or right of its column's others)
  const tol = Math.max(4, 0.7 * H);
  // grouped by their centres: values in one column may be set left, centred or right ("Feb" and "Feb/Aug" start apart but share a centre)
  const vs = data.flatMap((l) => l.items.filter((it) => isVal(it) && it.x >= startX - tol)).sort((a, b) => (a.x + a.w / 2) - (b.x + b.w / 2));
  const groups: PdfItem[][] = [];
  for (const it of vs) { const g = groups[groups.length - 1]; const c = it.x + it.w / 2; if (g && c - (g[g.length - 1].x + g[g.length - 1].w / 2) <= tol) g.push(it); else groups.push([it]) }
  const cols = groups.filter((g) => g.length >= support * data.length)
    .map((g) => ({ a: Math.min(...g.map((i) => i.x)), b: Math.max(...g.map((i) => i.x + i.w)), c: median(g.map((i) => i.x + i.w / 2)) }));
  if (cols.length < minValues) throw Error(`page ${pg.p}: fewer than ${minValues} value columns are shared by half the rows`);
  // a column's span runs to the next column's start
  const span = cols.map((c, i) => ({ ...c, lo: i ? Math.min(c.a - 1, (cols[i - 1].c + c.c) / 2) : c.a - tol, hi: i + 1 < cols.length ? Math.max(c.b + 1, (c.c + cols[i + 1].c) / 2) : c.b + 6 * H }));
  for (let i = 1; i < span.length; i++) if (span[i].lo < span[i - 1].hi) span[i].lo = span[i - 1].hi;  // spans never overlap
  // an item belongs to the column whose span holds its centre
  const colOf = (x: number, w = 0) => span.findIndex((s) => x + w / 2 >= s.lo && x + w / 2 < s.hi);
  // proof per data line: every printed item right of the label sits in exactly one column; the items of one column make its cell (a score and its
  // printed note, "7.0 (6.0)" or "6.2/C"); two value-shaped items of one column apart by more than a word gap mean two columns collided: the page is held
  const cellOf = new Map<Line, Map<number, PdfItem[]>>();
  for (const l of data) {
    const m = new Map<number, PdfItem[]>();
    for (const it of l.items) {
      if (it.x < startX - tol) continue;
      const k = colOf(it.x, it.w);
      if (k < 0) throw Error(`page ${pg.p}: "${it.s.slice(0, 50)}" lies outside every value column`);
      const prev = m.get(k) || [];
      // a cell's words that are not a value (a printed note) must sit over the column's own values; text off-centre in a column is a column that was not
      // found (its values are not value-shaped): the page is held rather than folding that column into its neighbour
      if (!isVal(it) && Math.abs(it.x + it.w / 2 - cols[k].c) > Math.max(it.w / 2 + 0.5 * tol, 0.6 * (span[k].hi - span[k].lo)))
        throw Error(`page ${pg.p}: "${it.s.slice(0, 50)}" is not over the values of its column`);
      // one value per cell, set over its column: a second value in a cell, or a value whose centre is off its column's centre by more than its own half
      // width and half the column's tolerance, is a misplaced value (two columns run together, or a column not found): the page is held
      const lastVal = prev.find(isVal);
      if (lastVal && isVal(it)) throw Error(`page ${pg.p}: two values of one row in one column ("${lastVal.s}", "${it.s}")`);
      if (isVal(it) && Math.abs(it.x + it.w / 2 - cols[k].c) > it.w / 2 + tol) throw Error(`page ${pg.p}: "${it.s}" is not over the values of its column`);
      prev.push(it); m.set(k, prev);
    }
    if ([...m.values()].every((v) => !v.some(isVal))) throw Error(`page ${pg.p}: a row whose cells print no value`);
    cellOf.set(l, m);
  }
  // headings: the text above the first data line (or rotated beside it), up to the nearest gap of more than four lines, inside each column's span
  const top = Math.max(...data.map((l) => l.y)), bottom = Math.min(...data.map((l) => l.y));
  // headings: the text in the band above the first data line. A heading set across its column is matched by its centre to the nearest column centre; a
  // heading longer than twice its column's width (set rotated, along the column) by where it starts, inside the column's span. A column with no heading,
  // or a heading between two columns, holds the page.
  const above = its.filter((it) => it.y > top + 0.35 * H && it.y <= top + 14 * H && !isVal(it));
  const ctr = span.map((s) => median(data.flatMap((l) => l.items.filter((it) => isVal(it) && it.x >= s.lo && it.x < s.hi).map((it) => it.x + it.w / 2))));
  const width = span.map((s, i) => Math.max(2 * H, (i + 1 < ctr.length ? ctr[i + 1] - ctr[i] : s.hi - s.lo)));
  const byCol: PdfItem[][] = span.map(() => []); const labelItems: PdfItem[] = [];
  const over = above.filter((it) => it.x + it.w >= startX - tol && it.w <= 5 * median(width) && it.h <= 1.5 * H);
  // headings set rotated (reading up the page): most of them start on one baseline and run longer than their column is wide; each is in the column
  // whose span holds where it starts, its lines left to right. Headings set across their columns are matched by their centres.
  const base = median(over.map((i) => i.y));
  const rotated = over.length >= 3 && over.filter((i) => Math.abs(i.y - base) <= 0.5).length >= 0.7 * over.length
                  && over.filter((i) => i.w > 1.5 * median(width)).length >= 0.3 * over.length;
  const rot: PdfItem[] = [];
  for (const it of above) {
    if (it.x + it.w < startX - tol) { labelItems.push(it); continue }
    if (!over.includes(it)) continue;  // paragraph text (longer than five columns) and title type (taller than one and a half lines) are not headings
    let k: number;
    if (rotated) {
      if (Math.abs(it.y - base) <= 0.5) { rot.push(it); continue }
      // not on the headings' baseline: the wrapped end of a cell in the first row ("105 (27-L/S," over its TOEFL cell) joins that cell; anything else holds
      const k0 = colOf(it.x, it.w), first = data.reduce((a, b) => (b.y > a.y ? b : a));
      if (k0 >= 0 && it.y - first.y <= 2.5 * H) { const m = cellOf.get(first)!; m.set(k0, [it, ...(m.get(k0) || [])]); continue }
      throw Error(`page ${pg.p}: "${it.s.slice(0, 50)}" is above the table but neither a heading nor part of its first row`);
    }
    else {
      const c = it.x + it.w / 2;
      k = ctr.reduce((best, v, i) => Math.abs(v - c) < Math.abs(ctr[best] - c) ? i : best, 0);
      if (Math.abs(ctr[k] - c) > 0.75 * width[k]) k = -1;  // between two columns: not placed (the column is then without a heading and the page held)
    }
    if (k >= 0) byCol[k].push(it);
  }
  if (rotated) {
    // rotated headings in reading order: the lines of one heading are a line apart, two headings a column apart. One heading per column, in order;
    // any other count holds the page (a heading cannot be placed without guessing)
    const xs2 = [...rot].sort((a, b) => a.x - b.x), groups2: PdfItem[][] = [];
    const split = Math.max(1.4 * H, 0.45 * Math.min(...width));
    for (const it of xs2) { const g = groups2[groups2.length - 1]; if (g && it.x - g[g.length - 1].x <= split) g.push(it); else groups2.push([it]) }
    if (groups2.length !== span.length) throw Error(`page ${pg.p}: ${groups2.length} rotated headings for ${span.length} value columns`);
    groups2.forEach((g, i) => byCol[i].push(...g));
  }
  const heads = byCol.map((items) => clean((rotated ? [...items].sort((a, b) => a.x - b.x).map((i) => i.s) : lines(items, H).map((l) => l.items.map((i) => i.s).join(" "))).join(" ")));
  const missing = heads.map((h, i) => h ? -1 : i).filter((i) => i >= 0);
  if (missing.length) throw Error(`page ${pg.p}: ${missing.length} value column(s) have no heading (first at x ${Math.round(cols[missing[0]].c)})`);
  // the label column's heading: label-side text on the heading band's lines only (a page title higher up is not the heading)
  const hy = byCol.flat().map((i) => i.y);
  const labelHead = clean(lines(labelItems.filter((it) => it.y >= Math.min(...hy) - 0.35 * H && it.y <= Math.max(...hy) + 0.35 * H), H).map((l) => l.items.map((i) => i.s).join(" ")).join(" ")) || "Row";
  const onLine = (d: Line, it: PdfItem) => Math.abs(it.y - d.y) <= 0.6 * H;
  // row labels: a data line's own label, or label lines beside it when it prints none; label lines beside a labelled line are section headings
  const inBody = its.filter((it) => it.y <= top + 0.35 * H && it.y >= bottom - 2 * H && it.x < startX - tol && !isVal(it));
  const labelLines = lines(inBody.filter((it) => !data.some((d) => onLine(d, it))), H);
  const gap = median(data.slice(1).map((d, i) => data[i].y - d.y)) || 2 * H;
  const own = new Map<Line, string>(data.map((d) => [d, clean(its.filter((it) => it.x < startX - tol && !isVal(it) && onLine(d, it)).sort((a, b) => a.x - b.x).map((i) => i.s).join(" "))]));
  // the left-most label column (a faculty printed beside the first course of its group) is a section, not part of the label
  const labelX = median(data.flatMap((d) => d.items.filter((it) => it.x < startX - tol).map((it) => it.x)).filter((x) => x > 0));
  const sectionAt = new Map<Line, string>();
  for (const d of data) {
    const left = d.items.filter((it) => it.x < labelX - 2 * H);
    if (left.length) { sectionAt.set(d, clean(left.map((i) => i.s).join(" "))); own.set(d, clean(d.items.filter((it) => it.x >= labelX - 2 * H && it.x < startX - tol).map((i) => i.s).join(" "))) }
  }
  const extra = new Map<Line, Line[]>();
  const sections: { y: number; text: string }[] = [];
  for (const l of labelLines) {
    const near = data.filter((d) => Math.abs(d.y - l.y) <= 0.8 * gap).sort((a, b) => Math.abs(a.y - l.y) - Math.abs(b.y - l.y));
    const host = near.find((d) => !own.get(d));
    if (host) { if (!extra.has(host)) extra.set(host, []); extra.get(host)!.push(l) }
    else if (l.items.every((it) => it.x < labelX - 2 * H) || near.length === 0 || near.every((d) => own.get(d))) sections.push({ y: l.y, text: clean(l.items.map((i) => i.s).join(" ")) });
  }
  for (const [d, xs2] of extra) own.set(d, clean([...xs2, d].sort((a, b) => b.y - a.y).map((l) => l === d ? own.get(d) : l.items.map((i) => i.s).join(" ")).join(" ")));
  // the wrapped parts of a cell (printed on lines between rows): each joins the cell of the row it is nearest to; equally near two rows holds the page
  const dataItems = new Set(data.flatMap((d) => d.items));
  for (const it of its) {
    if (dataItems.has(it) || it.x < startX - tol || it.y > top + 2.5 * H || it.y < bottom - 2.5 * H) continue;
    if (data.some((d) => [...cellOf.get(d)!.values()].some((v) => v.includes(it)))) continue;
    const near = [...data].sort((a, b) => Math.abs(a.y - it.y) - Math.abs(b.y - it.y));
    const d1 = Math.abs(near[0].y - it.y), d2 = near[1] ? Math.abs(near[1].y - it.y) : Infinity;
    if (d1 > 0.75 * gap) continue;  // not part of a row (a footnote or a heading)
    if (d2 - d1 < 0.2 * gap) throw Error(`page ${pg.p}: "${it.s.slice(0, 50)}" is as near one row as the next`);
    const k = colOf(it.x, it.w);
    if (k < 0) throw Error(`page ${pg.p}: "${it.s.slice(0, 50)}" lies outside every value column`);
    const m = cellOf.get(near[0])!; const cell = m.get(k) || [];
    cell.push(it); cell.sort((a, b) => b.y - a.y || a.x - b.x); m.set(k, cell);
  }
  const unlabelled = data.filter((d) => !own.get(d));
  if (unlabelled.length) throw Error(`page ${pg.p}: ${unlabelled.length} row(s) with values but no label (first at y ${Math.round(unlabelled[0].y)})`);
  // cells, top to bottom; a section heading applies to the rows below it until the next one
  const cells: GridCell[] = [];
  let section = "";
  const marks = [...sections, ...[...sectionAt.entries()].map(([d, t]) => ({ y: d.y + 0.01, text: t }))].sort((a, b) => b.y - a.y);
  for (const d of [...data].sort((a, b) => b.y - a.y)) {
    for (const m of marks) if (m.y > d.y && (!marks.some((n) => n.y > d.y && n.y < m.y))) section = m.text;
    for (const [k, items] of [...cellOf.get(d)!.entries()].sort((a, b) => a[0] - b[0])) {
      cells.push({ label: own.get(d)!, section, head: heads[k], value: clean(items.map((i) => i.s).join(" ")), page: pg.p, x: items[0].x, y: items[0].y });
    }
  }
  return { page: pg.p, labelHead, heads, rows: data.length, cells };
}

export function pdfGrids2(pages: PdfPage[], opt: GridOptions = {}): GridResult {
  const tables: GridTable[] = [];
  try { for (const pg of pages) { const t = pdfGridPage(pg, opt); if (t) tables.push(t) } }
  catch (e) { return { status: "unparsed", reason: (e instanceof Error ? e.message : String(e)).slice(0, 300), method: PDF_GRID_METHOD, tables: [], text: "" } }
  if (!tables.length) return { status: "no_table", reason: "no aligned grid", method: PDF_GRID_METHOD, tables, text: "" };
  const text = tables.flatMap((t) => t.cells.map((c) => `| ${t.labelHead}: ${c.label} | ${c.head}: ${c.value} |`)).join("\n");
  return { status: "ok", reason: "", method: PDF_GRID_METHOD, tables, text };
}
