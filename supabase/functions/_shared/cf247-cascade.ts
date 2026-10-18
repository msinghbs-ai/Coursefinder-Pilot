// CF-CHG-20260915-247 Layer 3 cost-first cascade helpers (no model call, no I/O).
// Cost-first cascade (Platform Admin direction 29 Sep 2026 21:08 IST): a "not stated" answer moves up a tier only when
// the page shows a clear signal; 5% of answers accepted below the final tier are re-asked to the final tier.
const MONTH = "January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept?|Oct|Nov|Dec";
const INTAKE_WORD = "intakes?|start|starts|starting|commenc\\w*|entry|semester|trimester|term";
const SIGNAL: Record<"intake" | "english", RegExp> = {
  intake: new RegExp(`\\b(?:${MONTH})\\b[^.\\n]{0,80}?\\b(?:${INTAKE_WORD})\\b|\\b(?:${INTAKE_WORD})\\b[^.\\n]{0,80}?\\b(?:${MONTH})\\b`, "i"),
  english: /\b(?:IELTS|PTE|TOEFL|Cambridge|Duolingo)\b[^.\n]{0,60}?\b\d{1,3}(?:\.\d)?\b/i,
};
export function cascadeSignal(task: "intake" | "english", text: string) { return SIGNAL[task].test(text) }
export const AUDIT_RATE = 0.05;
export const CASCADE_VERSION = "cf247-l3-cascade-v1.1.0";  // v1.1.0: pinned model from Layer 4
export const sameAnswer = (task: "intake" | "english", a: any, b: any) => {
  if (!a || !b) return false;
  if (task === "intake") return JSON.stringify([...(a.months || [])].map(Number).sort((x, y) => x - y)) === JSON.stringify([...(b.months || [])].map(Number).sort((x, y) => x - y));
  const k = (t: any[]) => JSON.stringify((t || []).map((x) => `${x.test}:${Number(x.overall)}`).sort());
  return k(a.tests) === k(b.tests);
};
