// CF-247 Phase 3 (Platform Admin 9 Oct 2026): the merged reading step's input for one field. The adapter's own place for
// the field comes first (its JSON path, then its heading section); with neither, the whole page, as Layer 3 reads it.
import { htmlToText } from "../coverage-sweep/extract.ts";
import { jsonAt, jsonText, pageJson, sectionText } from "../coverage-sweep/adapters.ts";

export function shadowInput(a: any, html: string, task: "intake" | "english" | "tuition"): { basis: string; text: string } {
  const field = task === "intake" ? "intakes" : task === "tuition" ? "fee" : "english";
  const full = htmlToText(html);
  const path = a?.json_paths?.[field];
  if (path) { const data = pageJson(html, a?.json_source); const t = data ? jsonText(jsonAt(data, path)) : ""; if (t && t.trim().length >= 3) return { basis: "adapter_json", text: t } }
  const sec = a?.sections?.[field] ? sectionText(full, a.sections[field], Number(a?.section_chars || 2000)) : null;
  if (sec) return { basis: "adapter_section", text: sec };
  return { basis: "page", text: full };
}
