// v0.9.0 (s1327, Platform Admin 28 Nov 2026 06:54, scoped exception for UNE and TAFE Queensland): an official HTML schedule is read as its
// tables. Only a table whose header row matches the schedule's header rule is read (TAFE Queensland: the higher education table, "Cost (annual
// indicative)"; its vocational tables print whole-of-course totals and are never read). Each row becomes its cells' text joined with " | ",
// so parseRows applies unchanged. A footnote mark after an amount (35,472*) is dropped; a schedule that prints amounts without "$" (UNE)
// says so (bareAmounts) and only a cell that is wholly an amount gets the sign.
const ENT: Record<string, string> = { "&amp;": "&", "&nbsp;": " ", "&#39;": "'", "&rsquo;": "'", "&quot;": '"', "&lt;": "<", "&gt;": ">", "&ndash;": "-", "&#8211;": "-" };
const cellText = (h: string) => h.replace(/<br\s*\/?>/gi, " ").replace(/<[^>]+>/g, " ").replace(/&[a-z#0-9]+;/gi, (e) => ENT[e.toLowerCase()] ?? " ").replace(/\s+/g, " ").trim();
export function htmlRows(html: string, header: RegExp, bareAmounts: boolean) {
  const tables = [...html.matchAll(/<table\b[\s\S]*?<\/table>/gi)].map((m) => m[0]);
  const rows: string[] = []; let tablesRead = 0;
  for (const tb of tables) {
    const trs = [...tb.matchAll(/<tr\b[\s\S]*?<\/tr>/gi)].map((m) => m[0]);
    if (!trs.length) continue;
    const head = [...trs[0].matchAll(/<t[hd]\b[^>]*>([\s\S]*?)<\/t[hd]>/gi)].map((m) => cellText(m[1])).join(" | ");
    if (!header.test(head)) continue;
    tablesRead++;
    for (const tr of trs.slice(1)) {
      const cells = [...tr.matchAll(/<t[hd]\b[^>]*>([\s\S]*?)<\/t[hd]>/gi)].map((m) => cellText(m[1]))
        .map((c) => c.replace(/^((?:A|AU)?\$?\s?\d{1,3}(?:,\d{3})+)[*^#\u2020]+$/, "$1"))
        .map((c) => (bareAmounts && /^\d{1,3}(?:,\d{3})+$/.test(c) ? "$" + c : c));
      if (cells.length) rows.push(cells.join(" | "));
    }
  }
  return { tables: tables.length, tablesRead, rows };
}
