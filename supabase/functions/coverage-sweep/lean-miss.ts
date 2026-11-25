// CF-247 s1152 (S1-Build; Platform Admin 25 Nov 2026 15:40 AEDT: "Retain the existing v6 meaningful-content selector and correct the three demonstrated
// missed lines"). Where a labelled line on a stored page sits when the recall check (mode lean_sections_eval) finds it on the page but not in the
// selection: the lean block holding its opening words (kind, words, the selector's signal, the nearest heading, selected or not), how many of its
// words run on in the lean text, and the stored markup around it. Diagnostic only: it changes no selection, input, prompt or reader.
import { fieldHit, flatForm } from "./lean-sections.ts";

type Block = { n: number; kind: string; text: string; source_at: number | null };
const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

export function missDetail(raw: string, blocks: Block[], plain: string, selected: string[], gold: string[], field: string) {
  const sel = new Set(selected.map(String)), W = flatForm(plain);
  return gold.slice(0, 4).map((g) => {  // fixed: a diagnostic record's size
    const words = String(g).replace(/&[a-z#0-9]+;/gi, " ").split(/\s+/).filter(Boolean);
    let k = words.length;
    while (k > 0 && !W.includes(flatForm(words.slice(0, k).join(" ")))) k--;
    const head = flatForm(words.slice(0, Math.min(5, words.length)).join(" "));
    const bi = head.length >= 6 ? blocks.findIndex((b) => flatForm(b.text).includes(head)) : -1;
    let h = bi; while (h > 0 && blocks[h].kind !== "heading") h--;
    const b = bi >= 0 ? blocks[bi] : null;
    const m = words.length >= 2 ? new RegExp(words.slice(0, 4).map(esc).join("(?:\\s|<[^>]*>|&[#a-z0-9]+;)+"), "i").exec(raw) : null;
    return {
      gold: String(g).slice(0, 100), lean_words: k, of_words: words.length,
      block: b ? { n: b.n, kind: b.kind, chars: b.text.length, text: b.text.slice(0, 300), signal: fieldHit(field, b.text), selected: sel.has(`B${b.n}`),
                   heading: h >= 0 && blocks[h].kind === "heading" ? blocks[h].text.slice(0, 120) : null, next: blocks[bi + 1] ? blocks[bi + 1].text.slice(0, 160) : null } : null,
      raw: m ? raw.slice(Math.max(0, m.index - 600), m.index + 500) : null,  // fixed: the markup shown around the line
    };
  });
}
