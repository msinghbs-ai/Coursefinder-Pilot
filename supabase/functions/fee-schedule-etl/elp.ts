// CF-247 Decision 162 step 4: provider English-language requirement tables (default plus named exceptions).
// Pure functions only (no I/O), so the parser is unit-tested against the real layout rules in the Pilot repo.
//
// UQ "English Language Proficiency Admission — Table 1" (higher-than-minimum ELP programs) is a two-column PDF:
// program names in the left column (wrapping over several lines), the ways to satisfy ELP in the right column.
// Each requirement block starts with an "IELTS:" line; one block can cover several programs. A program belongs to
// the lowest block on its page that starts no more than BLOCK_TOLERANCE points below the program's first line
// (requirement text can be vertically centred a little below the first program of its row).
// UQ "Table 3" gives the minimum entry scores applying to every program not listed in Table 1 (Procedure cl. 10-11).

export type Item = { p: number; x: number; y: number; s: string };
export type Components = Partial<Record<"listening" | "reading" | "writing" | "speaking", number>>;
export type Requirement = { test_code: string; overall_score: number; component_scores: Components };
export type Program = { name: string; section: "coursework" | "research"; page: number; requirements: Requirement[];
  other_tests: "table3_equivalents" | "not_accepted"; ielts_text: string };

const BLOCK_TOLERANCE = 6; // points
const WRAP_GAP = 12; // points between wrapped lines of one program name (programs are ~16 apart)
const SKILLS = ["listening", "reading", "writing", "speaking"] as const;
const clean = (s: string) => s.replace(/\s+/g, " ").replace(/\s*-\s*band/gi, "-band").replace(/sub\s*-\s*$/i, "sub-").trim();

function lines(items: Item[]) {
  const m = new Map<string, Item[]>();
  for (const it of items) {
    const k = `${it.p}|${it.y}`;
    if (!m.has(k)) m.set(k, []);
    m.get(k)!.push(it);
  }
  return [...m.values()].map((xs) => {
    xs.sort((a, b) => a.x - b.x);
    return { p: xs[0].p, y: xs[0].y, x: xs[0].x, s: xs.map((i) => i.s).join(" ").replace(/\s+/g, " ").trim() };
  }).sort((a, b) => a.p - b.p || b.y - a.y);
}

export function parseIelts(text: string): { overall: number; components: Components } | null {
  const t = clean(text);
  const o = t.match(/Overall Band Score\s*of\s*(\d+(?:\.\d)?)/i);
  if (!o) return null;
  const tail = t.slice(t.search(/\bAND\b/) >= 0 ? t.search(/\bAND\b/) : o.index! + o[0].length);
  const re = /(\d+(?:\.\d)?)\s+in\s+(?:each\s+sub-band\s+of\s+)?/gi;
  const hits = [...tail.matchAll(re)];
  const components: Components = {};
  for (let i = 0; i < hits.length; i++) {
    const span = tail.slice(hits[i].index! + hits[i][0].length, i + 1 < hits.length ? hits[i + 1].index : tail.length);
    const skills = [...span.matchAll(/\b(listening|reading|writing|speaking)\b/gi)].map((m) => m[1].toLowerCase() as typeof SKILLS[number]);
    for (const s of skills) {
      if (components[s] !== undefined) return null; // a skill stated twice: refuse rather than guess
      components[s] = Number(hits[i][1]);
    }
  }
  if (Object.keys(components).length === 0) return null;
  return { overall: Number(o[1]), components };
}

export function parseUqTable1(items: Item[]) {
  const issues: string[] = [];
  const header = items.filter((i) => /^Programs$/.test(i.s.trim()));
  const reqHeader = items.filter((i) => /^Ways to satisfy/i.test(i.s.trim()));
  if (!header.length || !reqHeader.length) return { programs: [] as Program[], unassigned: [] as string[], issues: ["table headers not found"] };
  const progX = header[0].x, colX = reqHeader[0].x - 5;
  const headerY = new Map(header.map((h) => [h.p, h.y]));
  const body = items.filter((i) => headerY.has(i.p) && i.y < headerY.get(i.p)! - 1 && !/^Last approved/i.test(i.s.trim()));
  const left = lines(body.filter((i) => i.x < colX));
  const right = lines(body.filter((i) => i.x >= colX));

  // left column: program lines start at the Programs column; section headers switch coursework/research
  type P = { p: number; y: number; lastY: number; name: string; section: "coursework" | "research" };
  const progs: P[] = [];
  let section: "coursework" | "research" = "coursework";
  for (const l of left) {
    if (/^HIGHER\b/i.test(l.s)) { section = /RESEARCH/i.test(l.s) ? "research" : "coursework"; continue; }
    if (Math.abs(l.x - progX) > 3 || /^Note\b/i.test(l.s)) continue;
    const prev = progs[progs.length - 1];
    if (prev && prev.p === l.p && prev.lastY - l.y < WRAP_GAP && prev.section === section) { prev.name += " " + l.s; prev.lastY = l.y; }
    else progs.push({ p: l.p, y: l.y, lastY: l.y, name: l.s, section });
  }

  // right column: blocks start at an "IELTS:" line
  type B = { p: number; y: number; lines: string[] };
  const blocks: B[] = [];
  for (const r of right) {
    if (/^IELTS\s*:/i.test(r.s)) blocks.push({ p: r.p, y: r.y, lines: [r.s] });
    else if (blocks.length && blocks[blocks.length - 1].p === r.p) blocks[blocks.length - 1].lines.push(r.s);
  }

  const programs: Program[] = [];
  const unassigned: string[] = [];
  const used = new Set<B>();
  for (const pr of progs) {
    const name = pr.name.replace(/\s+/g, " ").trim();
    const cands = blocks.filter((b) => b.p === pr.p && b.y + BLOCK_TOLERANCE >= pr.y);
    const b = cands.sort((a, c) => a.y - c.y)[0];
    if (!b) { unassigned.push(name); continue; }
    used.add(b);
    // IELTS paragraph: the IELTS line plus continuation lines until the next test/clause line
    const para: string[] = [b.lines[0]];
    for (const l of b.lines.slice(1)) {
      if (/^(BE\b|Other tests|TOEFL|PTE|CES|OET|Occupational|Clause|Note|Incoming)/i.test(l)) break;
      para.push(l);
    }
    const ieltsText = clean(para.join(" "));
    const ielts = parseIelts(ieltsText);
    if (!ielts) { issues.push(`IELTS requirement not parsed for ${name}: ${ieltsText}`); continue; }
    const reqs: Requirement[] = [{ test_code: "IELTS", overall_score: ielts.overall, component_scores: ielts.components }];
    const all = b.lines.join(" ");
    const toefl = all.match(/TOEFL iBT[^:]*:\s*Overall\s+(\d+),\s*listening\s+(\d+),\s*reading\s+(\d+),\s*writing\s+(\d+),\s*speaking\s+(\d+)/i);
    if (toefl) reqs.push({ test_code: "TOEFL_IBT", overall_score: +toefl[1], component_scores: { listening: +toefl[2], reading: +toefl[3], writing: +toefl[4], speaking: +toefl[5] } });
    const pte = all.match(/PTE Academic\s*:\s*Overall\s+(\d+),\s*all sub bands minimum\s+(\d+)/i);
    if (pte) reqs.push({ test_code: "PTE", overall_score: +pte[1], component_scores: { listening: +pte[2], reading: +pte[2], writing: +pte[2], speaking: +pte[2] } });
    programs.push({ name, section: pr.section, page: pr.p, requirements: reqs,
      other_tests: /other tests (?:and [^.]*?)?are not accepted/i.test(all) ? "not_accepted" : "table3_equivalents", ielts_text: ieltsText });
  }
  const orphanBlocks = blocks.filter((b) => !used.has(b)).map((b) => `p${b.p} y${b.y}: ${b.lines[0]}`);
  if (orphanBlocks.length) issues.push(...orphanBlocks.map((o) => "requirement block with no program: " + o));
  return { programs, unassigned, issues };
}

// Table 3 "UQ minimum entry": rows between "UQ minimum entry" and "higher than minimum"; columns Overall, L, R, W, S.
export function parseUqTable3Minimum(rows: string[]) {
  const start = rows.findIndex((r) => /UQ minimum entry/i.test(r));
  const end = rows.findIndex((r, i) => i > start && /higher than minimum/i.test(r));
  if (start < 0 || end < 0) return { requirements: [] as Requirement[], issues: ["minimum entry section not found"] };
  const reqs: Requirement[] = [];
  const issues: string[] = [];
  const pick = (re: RegExp, code: string) => {
    const r = rows.slice(start, end).find((x) => re.test(x));
    const n = r ? (r.match(/\d+(?:\.\d+)?/g) || []).map(Number) : [];
    if (n.length < 5) { issues.push(`${code} minimum row not found`); return; }
    const [o, l, rd, w, s] = n.slice(-5);
    reqs.push({ test_code: code, overall_score: o, component_scores: { listening: l, reading: rd, writing: w, speaking: s } });
  };
  pick(/^IELTS/i, "IELTS");
  pick(/^TOEFL iBT/i, "TOEFL_IBT");
  pick(/^PTE Academic/i, "PTE");
  return { requirements: reqs, issues };
}
