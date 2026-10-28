// CF-247 AER programme, Step B (28 Oct 2026; admin docs/platform/ENTRY-REQUIREMENTS-PROGRAMME-DECISION-2026-10-28.md section 3):
// PDF entry matrices. The stored PDF's text items keep their page, x and y, and the page's drawn table rules are kept too (unpdf, as the
// fee-schedule reader). This module rebuilds each table from the rules the PDF itself draws and proves column and row fidelity before
// anything is read by the model:
//   - a table is a set of ruled cells: its columns are the edges of its rule segments, its rows the rules across each column (a cell merged
//     over several rows has no rule between them, so it is repeated on each of those rows, as for HTML tables);
//   - every text item inside a table must sit wholly inside one column and between two rules of that column; an item that crosses a column
//     edge or a row rule fails the whole document closed (held_unparsed, with the page and the text). Nothing is placed by guesswork;
//   - a page that shows columns of text but draws no rules is held too: its rows cannot be proven;
//   - each cell is named by its column's header, so the model never works out which column a value came from; a table continued on the
//     next page keeps its header;
//   - text outside the tables is given as plain lines.
// No scale is added, no grade is moved between cells, and a partial table is never given. Pure functions, tested against the stored
// PDFs' positioned items and rules.
export const PDF_METHOD = "ruled-cells-v1";
// v0.51.0: from this many columns a table row is given cell by cell with its first cell (structure rule of the reader, not an operational value)
export const WIDE_COLUMNS = 5;

export type PdfItem = { x: number; y: number; w: number; h: number; s: string };
export type PdfRule = { o: "h" | "v"; y?: number; x?: number; a: number; b: number; box?: number };
export type PdfPage = { p: number; width: number; height: number; items: PdfItem[]; rules: PdfRule[] };
export type PdfTable = { page: number; header: string[]; rows: number; columns: number };
export type PdfResult = { status: "ok" | "unparsed" | "no_table"; reason: string; text: string; tables: PdfTable[]; method: string };

const median = (a: number[]) => { const s = [...a].sort((x, y) => x - y); return s.length ? s[s.length >> 1] : 0 };
const clean = (s: string) => String(s || "").replace(/\s+/g, " ").trim();
const flat = (s: string) => String(s || "").toLowerCase().replace(/[^a-z0-9]+/g, "");
const EDGE = 4;  // fixed: rule end points closer than this (points) are one edge

// footnote and superscript markers ("60% 5", "score of 5#"): short and much smaller than the body text
const isMarker = (it: PdfItem, H: number) => it.h > 0 && it.h < 0.75 * H && /^[\s\d*#†‡a-z,]{1,3}$/i.test(it.s.trim());

// items on one line (same baseline within a third of the text height), left to right, joined with a space where they are apart
function lineText(its: PdfItem[], H: number): string {
  let out = "", end = -Infinity;
  for (const it of [...its].sort((a, b) => a.x - b.x)) { out += (out && it.x - end > 0.12 * H && !/\s$/.test(out) ? " " : "") + it.s; end = Math.max(end, it.x + it.w) }
  return clean(out);
}
function linesOf(its: PdfItem[], H: number): { y: number; items: PdfItem[] }[] {
  const out: { y: number; items: PdfItem[] }[] = [];
  for (const it of [...its].sort((a, b) => b.y - a.y || a.x - b.x)) {
    const l = out[out.length - 1];
    if (l && Math.abs(l.y - it.y) <= 0.35 * H) l.items.push(it); else out.push({ y: it.y, items: [it] });
  }
  return out;
}
const textOf = (its: PdfItem[], H: number) => clean(linesOf(its, H).map((l) => lineText(l.items, H)).join(" "));

type Seg = { y: number; a: number; b: number; full?: boolean };
type Grid = { top: number; bottom: number; edges: number[]; segs: Seg[] };

// the page's tables: runs of horizontal rules that share column edges. A filled box counts only when it runs across the whole table (a
// section bar); boxes inside cells (shading behind a word) are not rules.
function grids(pg: PdfPage, H: number): Grid[] {
  // a line drawn just under a word (a link's underline) is not a rule
  const under = (r: PdfRule) => pg.items.some((it) => it.y - r.y! >= -1 && it.y - r.y! <= 0.6 * H && r.a >= it.x - 2 && r.b <= it.x + it.w + 2);
  const thin = (pg.rules || []).filter((r) => r.o === "h" && !r.box && r.b - r.a >= 2 * H && !under(r)).map((r) => ({ y: r.y!, a: r.a, b: r.b }));
  const boxes = (pg.rules || []).filter((r) => r.o === "h" && r.box).map((r) => ({ y: r.y!, a: r.a, b: r.b }));
  if (thin.length < 3) return [];
  const ys = [...new Set(thin.map((s) => Math.round(s.y * 2) / 2))].sort((p, q) => q - p);
  const edgesOf = (segs: Seg[]) => { const e: number[] = []; for (const v of segs.flatMap((s) => [s.a, s.b]).sort((p, q) => p - q)) if (!e.length || v - e[e.length - 1] > EDGE) e.push(v); return e };
  const finish = (c: { ys: number[]; segs: Seg[] }): Grid => {
    // a stray short rule above or below the table (under a logo, beside a title) is not one of its rows
    const span = (y: number) => c.segs.filter((s) => Math.abs(s.y - y) <= 0.5).reduce((t, s) => t + s.b - s.a, 0);
    const w0 = (() => { const e = edgesOf(c.segs); return e[e.length - 1] - e[0] })();
    while (c.ys.length > 1 && span(c.ys[0]) < 0.5 * w0) { const y = c.ys.shift()!; c.segs = c.segs.filter((s) => Math.abs(s.y - y) > 0.5) }
    while (c.ys.length > 1 && span(c.ys[c.ys.length - 1]) < 0.5 * w0) { const y = c.ys.pop()!; c.segs = c.segs.filter((s) => Math.abs(s.y - y) > 0.5) }
    const edges = edgesOf(c.segs), top = c.ys[0], bottom = c.ys[c.ys.length - 1];
    const width = edges[edges.length - 1] - edges[0];
    for (const s of c.segs) if (s.b - s.a >= 0.9 * width) s.full = true;
    // filled boxes that are rules too: a bar across the whole table (a section heading), or a cell's shading that sits exactly on the
    // table's column edges (a shaded header cell above the first drawn rule)
    const onEdge = (v: number) => edges.some((e) => Math.abs(e - v) <= EDGE);
    const fit = boxes.filter((s) => s.b - s.a >= 0.9 * width || (onEdge(s.a) && onEdge(s.b))).map((s) => ({ ...s, full: s.b - s.a >= 0.9 * width }));
    // boxes inside the table, and those chained above or below it no further apart than its tallest row (a shaded header, a section bar)
    const step = Math.max(4 * H, ...c.ys.slice(1).map((y, i) => c.ys[i] - y));
    let hi = top, lo = bottom; const bars: Seg[] = fit.filter((s) => s.y <= top + 0.5 && s.y >= bottom - 0.5);
    // ... but never across text that runs over a column edge (a title between two tables)
    const across = (y0: number, y1: number) => pg.items.some((it) => it.y > y0 + 0.5 && it.y < y1 - 0.5 && edges.some((e) => it.x < e - EDGE && it.x + it.w > e + EDGE));
    for (const s of [...fit].filter((s) => s.y > top + 0.5).sort((p, q) => p.y - q.y)) { if (s.y - hi > step || across(hi, s.y)) break; bars.push(s); hi = Math.max(hi, s.y) }
    for (const s of [...fit].filter((s) => s.y < bottom - 0.5).sort((p, q) => q.y - p.y)) { if (lo - s.y > step || across(s.y, lo)) break; bars.push(s); lo = Math.min(lo, s.y) }
    const segs = [...c.segs, ...bars];
    // a last row the page leaves open (a column with no rule under its last row, the table running on to the next page): the row runs
    // down over the lines just below, each within one column, until a gap or a line across the columns; a closing rule is set there
    const covered = (s: Seg, a: number, b: number) => s.a <= a + EDGE && s.b >= b - EDGE;
    const open = edges.slice(0, -1).some((a, i) => !segs.some((s) => Math.abs(s.y - lo) <= 0.5 && covered(s, a, edges[i + 1])));
    const below = linesOf(pg.items.filter((it) => it.y < lo - 0.5 && it.x >= edges[0] - EDGE && it.x < edges[edges.length - 1]), H);
    // ... or a last row printed under the last rule: the next line is just below and has text in two or more columns
    const colAt = (x: number) => edges.findIndex((e, i) => i + 1 < edges.length && x >= e - 1 && x < edges[i + 1]);
    const rowLike = below.length > 0 && lo - below[0].y <= 2.2 * H && new Set(below[0].items.map((it) => colAt(it.x))).size >= 2;
    if (open || rowLike) {
      let last = lo;
      for (const l of below) {
        if (last - l.y > 2.2 * H || l.items.some((it) => edges.some((e) => it.x < e - EDGE && it.x + it.w > e + EDGE))) break;
        last = l.y;
      }
      if (last < lo) { const y = last - 0.5 * H; segs.push({ y, a: edges[0], b: edges[edges.length - 1], full: true }); lo = y }
    }
    return { top: hi, bottom: lo, edges, segs };
  };
  const out: Grid[] = [];
  let cur: { ys: number[]; segs: Seg[] } | null = null;
  for (const y of ys) {
    const at = thin.filter((s) => Math.abs(s.y - y) <= 0.5);
    const lo = Math.min(...at.map((s) => s.a)), hi = Math.max(...at.map((s) => s.b));
    if (cur) {
      const e = edgesOf(cur.segs), elo = e[0], ehi = e[e.length - 1];
      // the same table: overlapping extent; every end point on a known edge, or widening the table (a column added at a side), or (below
      // a single first rule, which may span merged header cells) inside it; and no more than a third of the page between two rules
      const known = (v: number) => e.some((x) => Math.abs(x - v) <= EDGE);
      const fits = lo < ehi && hi > elo && at.every((s) => [s.a, s.b].every((v) => known(v) || v < elo || v > ehi || cur!.ys.length === 1))
                   && at.some((s) => known(s.a) || known(s.b)) && cur.ys[cur.ys.length - 1] - y < pg.height / 3;
      if (fits) { cur.ys.push(y); cur.segs.push(...at); continue }
      out.push(finish(cur));
    }
    cur = { ys: [y], segs: [...at] };
  }
  if (cur) out.push(finish(cur));
  return out.filter((g) => g.edges.length >= 3 && g.top - g.bottom > H);
}

type Row = string[];
const SPAN = "\u0000";  // a row that is one cell across the table

// one table's rows, or a fidelity error
function gridRows(pg: PdfPage, g: Grid, items: PdfItem[], H: number): Row[] {
  const cols = g.edges.slice(0, -1).map((a, i) => ({ a, b: g.edges[i + 1] }));
  // a column's rules: the segments that run across it
  const bounds = cols.map((c) => [...new Set(g.segs.filter((s) => s.a <= c.a + EDGE && s.b >= c.b - EDGE).map((s) => Math.round(s.y * 2) / 2))].sort((p, q) => q - p));
  const cells = new Map<string, PdfItem[]>();
  // a band between two rules across the whole table with no rule inside it for any column is one cell across the table (a heading bar)
  const fulls = [...new Set(g.segs.filter((s) => s.full).map((s) => Math.round(s.y * 2) / 2))].sort((p, q) => q - p);
  const spans: { hi: number; lo: number; items: PdfItem[] }[] = [];
  for (let j = 0; j + 1 < fulls.length; j++) {
    const hi = fulls[j], lo = fulls[j + 1];
    if (!bounds.some((bs) => bs.some((y) => y < hi - 0.5 && y > lo + 0.5))) spans.push({ hi, lo, items: [] });
  }
  for (const it of items) {
    const sp = spans.find((x) => it.y <= x.hi + 0.5 && it.y >= x.lo - 0.5);
    if (sp) { if (it.y + 0.7 * it.h > sp.hi + 1) throw Error(`page ${pg.p}: "${clean(it.s).slice(0, 60)}" crosses a row rule`); sp.items.push(it); continue }
    const k = cols.findIndex((c) => it.x >= c.a - 1 && it.x < c.b);
    if (k < 0) throw Error(`page ${pg.p}: "${clean(it.s).slice(0, 60)}" lies inside the table but outside its columns`);
    if (it.x + it.w > cols[k].b + 1) throw Error(`page ${pg.p}: "${clean(it.s).slice(0, 60)}" crosses a column edge`);
    const bs = bounds[k];
    if (bs.length < 2) throw Error(`page ${pg.p}: "${clean(it.s).slice(0, 60)}" is in a column without row rules`);
    const i = bs.findIndex((b, j) => j + 1 < bs.length && it.y >= bs[j + 1] - 0.5 && it.y <= b + 0.5);
    if (i < 0) throw Error(`page ${pg.p}: "${clean(it.s).slice(0, 60)}" is outside the rules of its column`);
    if (it.y + 0.7 * it.h > bs[i] + 1) throw Error(`page ${pg.p}: "${clean(it.s).slice(0, 60)}" crosses a row rule`);
    const key = `${k}:${i}`; if (!cells.has(key)) cells.set(key, []); cells.get(key)!.push(it);
  }
  // rows: the bands between all the table's rules; a cell is in every band it covers (merged over rows it is repeated); a band becomes a
  // row only when it has a cell of its own with text
  const all = [...new Set([...bounds.flat(), ...fulls])].sort((p, q) => q - p);
  const rows: Row[] = [];
  for (let j = 0; j + 1 < all.length; j++) {
    const hi = all[j], lo = all[j + 1];
    const sp = spans.find((x) => Math.abs(x.hi - hi) <= 0.5 && Math.abs(x.lo - lo) <= 0.5);
    if (sp) { const t = textOf(sp.items, H); if (t) rows.push([SPAN + t]); continue }
    let own = false;
    const row = cols.map((_, k) => {
      const bs = bounds[k], i = bs.findIndex((b, m) => m + 1 < bs.length && b >= hi - 0.5 && bs[m + 1] <= lo + 0.5);
      if (i < 0) return "";
      const t = textOf(cells.get(`${k}:${i}`) || [], H);
      if (t && Math.abs(bs[i] - hi) <= 0.5 && Math.abs(bs[i + 1] - lo) <= 0.5) own = true;
      return t;
    });
    if (own) rows.push(row);
  }
  return rows;
}

export function pdfTables(pages: PdfPage[]): PdfResult {
  const res = (status: PdfResult["status"], reason: string, text = "", tables: PdfTable[] = []): PdfResult => ({ status, reason, text, tables, method: PDF_METHOD });
  const out: string[] = []; const tables: PdfTable[] = [];
  let header: string[] = [], section = "";
  try {
    for (const pg of pages) {
      const its = pg.items.filter((i) => clean(i.s)).map((i) => ({ ...i, s: i.s.replace(/\s+/g, " ") }));
      const H = median(its.map((i) => i.h).filter((h) => h > 0)) || 8;
      const body = its.filter((i) => !isMarker(i, H));
      const gs = grids(pg, H);
      const inGrid = (it: PdfItem, g: Grid) => it.y <= g.top + 0.5 && it.y >= g.bottom - 0.5;
      // text outside every table, with each table placed where it stands on the page
      const freeLines = linesOf(body.filter((it) => !gs.some((g) => inGrid(it, g))), H);
      // runs of text on a line, apart by more than a word space
      const runsOf = (l: { items: PdfItem[] }) => { const r: PdfItem[][] = []; let end = -Infinity; for (const it of l.items) { if (it.x - end >= 1.5 * H || !r.length) r.push([]); r[r.length - 1].push(it); end = Math.max(end, it.x + it.w) } return r };
      // short cells side by side with no drawn rules (a table whose rows cannot be proven): the document is held
      const loose = freeLines.filter((l) => runsOf(l).length >= 3);
      const cellLen = median(loose.flatMap((l) => runsOf(l).map((r) => lineText(r, H).length)));
      if (loose.length >= 3 && cellLen <= 20) throw Error(`page ${pg.p}: columns of text with no drawn rules ("${lineText(loose[0].items, H).slice(0, 60)}")`);
      // notes set in text columns (long lines side by side) are read column by column, not across
      const parts: { y: number; text: string[] }[] = [];
      if (loose.length >= 3) {
        const starts: number[] = []; for (const x of loose.flatMap((l) => runsOf(l).map((r) => r[0].x)).sort((p, q) => p - q)) if (!starts.length || x - starts[starts.length - 1] > 2 * H) starts.push(x);
        const colOf = (x: number) => { let k = 0; for (let i = 0; i < starts.length; i++) if (x >= starts[i] - H) k = i; return k };
        const y0 = freeLines.length ? freeLines[0].y : 0;
        parts.push({ y: y0, text: starts.map((_, k) => textOf(freeLines.flatMap((l) => runsOf(l).filter((r) => colOf(r[0].x) === k).flat()), H)).filter(Boolean) });
      } else parts.push(...freeLines.map((l) => ({ y: l.y, text: [lineText(l.items, H)] })));
      for (const g0 of gs) {
       const all = gridRows(pg, g0, body.filter((it) => inGrid(it, g0)), H);
       // two tables side by side in one ruled grid: split at a column that is empty on every row
       const width = Math.max(0, ...all.filter((r) => !r[0]?.startsWith(SPAN)).map((r) => r.length));
       const gaps = [...Array(width).keys()].filter((k) => k > 0 && k < width - 1 && all.every((r) => r[0]?.startsWith(SPAN) || !r[k]));
       const pieces = gaps.length ? [-1, ...gaps, width].slice(0, -1).map((a, i, arr) => [a + 1, i + 1 < arr.length ? arr[i + 1] : width]) : [[0, width]];
       for (const [c0, c1] of pieces) {
        const g = g0;
        const rows = all.map((r) => r[0]?.startsWith(SPAN) ? r : r.slice(c0, c1)).filter((r) => r[0]?.startsWith(SPAN) || r.some(Boolean));
        const lines: string[] = [];
        while (rows.length && rows[0][0]?.startsWith(SPAN)) lines.push(`§ ${rows.shift()![0].slice(1)}`);  // a title bar above the header
        let first = 0;
        const top = rows[0] || [];
        const repeat = header.length === top.length && flat(top.join(" ")) === flat(header.join(" "));
        if (!header.length || (header.length !== top.length && !repeat)) {
          if (top.filter(Boolean).length < 2) throw Error(`page ${pg.p}: a table whose first row is not a header (${top.filter(Boolean).length} cell)`);
          header = top; first = 1; section = "";
          lines.push("| " + header.map((h, i) => h || `Column ${i + 1}`).join(" | ") + " |", "| " + header.map(() => "---").join(" | ") + " |");
        } else if (repeat) first = 1;
        let carry = "", n = 0;
        for (const r of rows.slice(first)) {
          if (r[0]?.startsWith(SPAN)) { const t = r[0].slice(1); if (t.split(" ").length <= 8) { section = t; carry = "" } lines.push(`§ ${t}`); continue }
          const filled = r.filter(Boolean).length;
          // a row with only its first cell, a short one, is a section heading (a country above its rows)
          if (filled === 1 && r[0] && r[0].split(" ").length <= 6 && r.length > 2) { section = r[0]; carry = ""; lines.push(`§ ${section}`); continue }
          const cells = [...r];
          if (!cells[0] && carry) cells[0] = carry; else if (cells[0]) carry = cells[0];
          const named = cells.map((c, i) => c ? `${header[i] || `Column ${i + 1}`}: ${c}` : "").filter(Boolean);
          if (!named.length) continue;
          // v0.51.0: a wide table (WIDE_COLUMNS or more columns, a requirement per column, e.g. one column per study level) gives each data
          // cell on its own line with its row's first cell, so a requirement can be quoted whole (Western Sydney: 65 of 78 rows were dropped
          // as quote_not_on_page when the model quoted the row label with one level's cell); the cells are the same proven cells
          if (header.length >= WIDE_COLUMNS && cells[0] && named.length > 2) { for (const c of named.slice(1)) lines.push("| " + (section ? `${section} | ` : "") + named[0] + " | " + c + " |"); n++; continue }
          lines.push("| " + (section ? `${section} | ` : "") + named.join(" | ") + " |"); n++;
        }
        parts.push({ y: g.top + 0.25 - c0 * 1e-3, text: lines });
        tables.push({ page: pg.p, header, rows: n, columns: header.length });
       }
      }
      for (const p of parts.sort((a, b) => b.y - a.y)) out.push(...p.text);
    }
  } catch (e) { return res("unparsed", (e instanceof Error ? e.message : String(e)).slice(0, 300)) }
  if (!tables.length) return res("no_table", "no ruled table", out.join("\n"));
  return res("ok", "", out.join("\n"), tables);
}

// for the fixture tests: the tables a page's rules describe
export function pdfGrids(pg: PdfPage) {
  const H = median(pg.items.map((i) => i.h).filter((h) => h > 0)) || 8;
  return grids(pg, H).map((g) => ({ top: g.top, bottom: g.bottom, edges: g.edges.map((e) => Math.round(e)), rules: [...new Set(g.segs.map((s) => Math.round(s.y)))].length }));
}

// the worker's extraction (and the fixtures'): text items with their position and size, and the horizontal and vertical lines the page
// draws (filled thin rectangles, stroked lines, and the edges of filled boxes), in page coordinates. `doc` is an unpdf document proxy and
// `OPS` its operator list codes (both passed in, so this module stays free of the PDF library and runs in the tests as it runs live).
export async function pdfPages(doc: any, OPS: any, maxPages: number): Promise<PdfPage[]> {
  const r1 = (v: number) => Math.round(v * 10) / 10;
  const mul = (m: number[], n: number[]) => [m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1], m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3], m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5]];
  const ap = (m: number[], x: number, y: number) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
  const paint = [OPS.fill, OPS.eoFill, OPS.stroke, OPS.closeStroke, OPS.fillStroke, OPS.eoFillStroke, OPS.closeFillStroke, OPS.closeEOFillStroke];
  const pages: PdfPage[] = [];
  for (let p = 1; p <= Math.min(doc.numPages, maxPages); p++) {
    const pg = await doc.getPage(p); const vp = pg.getViewport({ scale: 1 });
    const tc = await pg.getTextContent();
    const items: PdfItem[] = (tc.items as any[]).filter((i) => typeof i.str === "string" && i.str.trim())
      .map((i) => ({ x: r1(i.transform[4]), y: r1(i.transform[5]), w: r1(i.width || 0), h: r1(i.height || Math.abs(i.transform[3]) || 0), s: i.str }));
    const ol = await pg.getOperatorList(); const rules: PdfRule[] = [];
    let ctm = [1, 0, 0, 1, 0, 0]; const stack: number[][] = []; let pend: number[][] = [];
    for (let i = 0; i < ol.fnArray.length; i++) {
      const f = ol.fnArray[i], a = ol.argsArray[i];
      if (f === OPS.save) stack.push(ctm); else if (f === OPS.restore) ctm = stack.pop() || ctm;
      else if (f === OPS.transform) ctm = mul(ctm, a);
      else if (f === OPS.constructPath) {
        const [ops, args] = a; let k = 0; pend = []; let cur: number[] | null = null;
        for (const o of ops) {
          if (o === OPS.rectangle) { const [x, y, w, h] = args.slice(k, k + 4); k += 4; const [x0, y0] = ap(ctm, x, y), [x1, y1] = ap(ctm, x + w, y + h); pend.push([Math.min(x0, x1), Math.min(y0, y1), Math.max(x0, x1), Math.max(y0, y1), 0]) }
          else if (o === OPS.moveTo) { cur = ap(ctm, args[k], args[k + 1]); k += 2 }
          else if (o === OPS.lineTo) { const n = ap(ctm, args[k], args[k + 1]); k += 2; if (cur) pend.push([Math.min(cur[0], n[0]), Math.min(cur[1], n[1]), Math.max(cur[0], n[0]), Math.max(cur[1], n[1]), 1]); cur = n }
          else if (o === OPS.curveTo) k += 6; else if (o === OPS.curveTo2 || o === OPS.curveTo3) k += 4;
        }
      } else if (paint.includes(f)) {
        for (const r of pend) {
          const w = r[2] - r[0], h = r[3] - r[1];
          if (h <= 2 && w >= 20) rules.push({ o: "h", y: r1((r[1] + r[3]) / 2), a: r1(r[0]), b: r1(r[2]) });
          else if (w <= 2 && h >= 8) rules.push({ o: "v", x: r1((r[0] + r[2]) / 2), a: r1(r[1]), b: r1(r[3]) });
          else if (!r[4] && w >= 20 && h >= 8) rules.push({ o: "h", y: r1(r[1]), a: r1(r[0]), b: r1(r[2]), box: 1 }, { o: "h", y: r1(r[3]), a: r1(r[0]), b: r1(r[2]), box: 1 });
        }
        pend = [];
      } else if (f === OPS.endPath) pend = [];
    }
    pages.push({ p, width: r1(vp.width), height: r1(vp.height), items, rules });
  }
  return pages;
}
