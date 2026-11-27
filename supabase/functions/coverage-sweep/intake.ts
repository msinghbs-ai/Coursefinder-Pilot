// CF-247 s1321 (S1-Build; SS-Programme-Control 27 Nov 2026 21:08 AEDT, approved scoped exception 1: structured data intake).
// Quote proof for structured candidates (pipeline.structured_intake_items): a submitted quote counts only when it is printed on the platform's own
// stored copy of the page it names. The comparison is exact on the characters: only white space is left out (a stored page and a submitter's
// extraction break lines differently) and typographic forms of the same character are folded (curly quotes, dashes, non-breaking and zero-width
// spaces). Letter case, digits and words are compared as they are. Pure functions, no fetch, no model; the worker mode intake_verify reads the
// stored copies and the database decides (security.structured_intake_record_v1). The same contract serves any later processing worker.
export const INTAKE_VERIFY = "intake-quote-v1";

const FOLD: [RegExp, string][] = [
  [/[‘’‚‛′]/g, "'"], [/[“”„‟″]/g, '"'],
  [/[‐‑‒–—―−]/g, "-"], [/…/g, "..."],
];

export function foldText(s: string): string {
  let t = String(s || "").normalize("NFKC");
  for (const [re, to] of FOLD) t = t.replace(re, to);
  return t.replace(/[\s ​‌‍⁠﻿]+/g, "");
}

export type QuoteProof = { found: boolean; reason: string };

export function quoteOnPage(foldedPage: string, quote: string, minChars = 8): QuoteProof {
  const q = foldText(quote);
  if (q.length < minChars) return { found: false, reason: "quote_too_short" };
  if (!foldedPage) return { found: false, reason: "stored_copy_empty" };
  return foldedPage.includes(q) ? { found: true, reason: "on_stored_copy" } : { found: false, reason: "quote_not_on_stored_copy" };
}

// the text of a stored PDF, page by page (unpdf document proxy passed in, so this module stays free of the PDF library)
export async function pdfPlainText(doc: any, maxPages: number): Promise<string> {
  const out: string[] = [];
  for (let p = 1; p <= Math.min(doc.numPages, maxPages); p++) {
    const tc = await (await doc.getPage(p)).getTextContent();
    out.push((tc.items as any[]).map((i) => (typeof i.str === "string" ? i.str : "")).join(" "));
  }
  return out.join("\n");
}
