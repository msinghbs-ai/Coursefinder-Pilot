// CF-247 Lean AI Input Phase 1b-3 (Platform Admin 14 Nov 2026 17:20, approving admin
// docs/platform/LEAN-AI-INPUT-PHASE1B-3-QUALIFICATION-PLAN-FEES-INTAKES.md with a hard US$2.00 ceiling): the qualification of the section
// selector's input for two readers, fees (service fee_reader) and intakes (service course_other_fields).
//
// Each labelled stored page is read twice on the reader's pinned route: once with today's input (baseline) and once with the selected
// [B# @offset] blocks (candidate). Both arms send the same instructions and the same context; the candidate adds one line saying the text
// comes as blocks. So the only difference between the arms is the input. Answers go to the qualification table only: nothing is
// admitted, published or proposed, and a pass switches nothing on (1b-4 is a separate setting the Platform Admin changes).
//
// Candidate prompt versions (recorded on every result, active nowhere): fee-reader+blocks-v1, course-intakes+blocks-v1.

import { feeAiRequest, type FeeItem } from "./fees.ts";
import { flatForm, unEntity } from "./lean-sections.ts";

export const LEAN_QUALIFY = "lean-qualify-v1";  // never edited in place once released
export const FEE_CANDIDATE_PROMPT = "fee-reader+blocks-v1";
export const INTAKE_BASELINE_PROMPT = "course-intakes-v1";
export const INTAKE_CANDIDATE_PROMPT = "course-intakes+blocks-v1";

// the one line the candidate adds: the text arrives as blocks, and a quote is words from one block, without its label
export const BLOCKS_LINE = "The page text below is given as blocks, one per line. Each line starts with its label, for example [B12 @3456] (block number and its place in the page). Quote only words that stand inside one block, and never include a label in a quote.";

// The intakes part of the live Enrich fields course-page prompt (index.ts, the course_fields read), sentence for sentence. The contract spec
// fails if any of these sentences is no longer in the live prompt, so the baseline cannot drift from what the reader is sent today.
export const INTAKE_PROMPT_SENTENCES = [
  "You read one university course page and report only what the page itself states for the course. For each field give the value and quote the exact words from the page that state it; give null when the page does not state it. ",
  "Page data fields at the top of the page text are the page's own labelled values (label: value); they are stated by the page: quote the value as written. ",
  "intakes: the months the course starts, as month names separated by commas, e.g. 'February, July', or the semesters, trimesters or terms it starts in as the page names them, e.g. 'Semester 1, Semester 2'; quote the words naming them; null when the page does not say when it starts. Never guess.",
] as const;

const strOrNull = { type: ["string", "null"] };
export const INTAKE_SCHEMA = { type: "object", additionalProperties: false, required: ["intakes"],
  properties: { intakes: { type: "object", additionalProperties: false, required: ["value", "quote"], properties: { value: strOrNull, quote: { type: "string" } } } } };

export function intakeRequest(model: string, provider: string, title: string, text: string, candidate: boolean, maxTokens: number) {
  const system = INTAKE_PROMPT_SENTENCES.join("") + (candidate ? " " + BLOCKS_LINE : "");
  return { model, temperature: 0, max_tokens: maxTokens, provider: { require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: "course_fields", strict: true, schema: INTAKE_SCHEMA } },
    messages: [{ role: "system", content: system }, { role: "user", content: `University: ${provider}\nCourse: ${title}\nFields: intakes\n\nPage text:\n${text}` }] };
}

// the fee reader's own request (fees.ts), with the blocks line added to the candidate's page text heading
export function feeRequest(model: string, it: FeeItem, text: string, candidate: boolean, maxTokens: number) {
  const req: any = feeAiRequest(model, it, text, maxTokens);
  if (candidate) req.messages[1].content = String(req.messages[1].content).replace("\n\nPage text:\n", `\n\n${BLOCKS_LINE}\n\nPage text:\n`);
  return req;
}

// a quote is held by the text the arm was sent, in the platform's flat form (letters and digits; labels in the candidate's text stay, so a
// quote that runs across two blocks is not held, as in the AER v3 quote check)
export const quoteHeld = (text: string, quote: string) => { const q = flatForm(unEntity(quote)); return q.length >= 3 && flatForm(text).includes(q) };

// intakes: the answer finds the label when every labelled month or term is named in its value
export function intakeFound(value: string | null, gold: string[]): boolean {
  if (!value) return false;
  const v = flatForm(value), g = gold.map((x) => flatForm(unEntity(x))).filter((x) => x.length >= 3);
  return g.length > 0 && g.every((x) => v.includes(x));
}

// fees: the answer finds the label when one proven row's amount (or range end) is the labelled yearly amount
export function feeFound(rows: any[], gold: string[]): boolean {
  const want = new Set(gold.map((x) => Math.round(Number(String(x).replace(/[^0-9.]/g, "")))).filter((n) => n > 0));
  return rows.some((r) => [r?.amount_min, r?.amount_max].some((a) => Number(a) > 0 && want.has(Math.round(Number(a)))));
}
