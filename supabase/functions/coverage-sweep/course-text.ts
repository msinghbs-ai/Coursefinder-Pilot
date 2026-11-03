// v0.59.4 (3 Nov 2026, CF-247 Workstream C, Platform Admin direction 3 Nov 2026 09:32, acceptance report item 1): course description and
// application deadline are Enrich fields fields (security.enrich_fields_v1: description, deadline). The enrich_ai mode reads them from the
// course's STORED page (the bound page the database leases with the item; nothing is fetched here) in one call per course, with the same
// central model as the other course fields:
//   description: 1 to N sentences about this course only, each with the exact words of the page that support it (the provider description
//     rules: descriptionSentences in description.ts checks every quote against the page text). Nothing is cut here; the database holds a
//     description that is too long, has too many sentences or a fragment, and sends a provider's first descriptions to Layer 4.
//   deadline: each application deadline the page states, as an explicit date with its words, or rolling, or not stated, with the intake the
//     page ties it to in the page's own words. Never inferred; the database matches the intake and checks the date is in the quote.
// Pure functions only (no network), so the contract spec can read them.
import { callCost } from "./answer.ts";
import { descriptionPageText, descriptionSentences } from "./description.ts";

export const COURSE_TEXT_PROMPT_VERSION = "course-text-v1";
export const COURSE_TEXT_FIELDS = ["description", "deadline"] as const;
// the setting that limits the answer (pipeline toolset, returned by svc_worker_settings_v1 like every reading.answer_tokens.* limit)
export const COURSE_TEXT_ANSWER_KEY = "reading.answer_tokens.course_text";
export const COURSE_TEXT_ANSWER_DEFAULT = 1500;

const flatText = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");

export const COURSE_TEXT_SYSTEM =
  "You read one course page of a university or education provider and report only what this page states about this course. " +
  "description: 1 or more sentences that tell a prospective student what this course is (what it covers, how it is structured, who it is for). Each sentence is a plain, factual paraphrase of one passage of the page about this course, and for each sentence give that passage's exact words as its quote, copied character for character from the page text. " +
  "Never use text about the provider in general, other courses, news, events, rankings or marketing banners. Do not state rankings, ratings, awards, employment or graduate outcomes, salaries, accreditations or facilities unless the quoted words state them. Do not use superlatives or marketing words (best, leading, world-class, top, renowned, prestigious, excellent) unless they are inside the quote. " +
  "Write in Australian English, third person, present tense. Set about_course to false and give no sentences when the page does not describe this course. " +
  "deadlines: every application closing date the page states for this course. kind is date when the page prints a full date (day, month and year), rolling when the page says applications are open all year or assessed as received, not_stated otherwise. " +
  "date is that date as YYYY-MM-DD only when kind is date and the page prints the day, the month and the year; never work out a date from a start date or a term, and never assume a year. " +
  "intake is the intake, start or semester the page ties the deadline to, in the page's own words (for example 'February 2027 intake', 'Semester 1'), or null when the page gives one deadline for the course. quote is the exact words of the page that state the deadline. Give an empty list when the page states none.";

export type CourseTextLength = { min_sentences?: number; max_sentences?: number; min_chars?: number; max_chars?: number };

// the limits the database applies (settings enrich.course_description_*), stated to the model; never enforced by cutting here
export function courseTextLengthNote(l: CourseTextLength | null | undefined): string {
  const n = (x: unknown) => (Number.isFinite(Number(x)) && Number(x) > 0 ? Math.floor(Number(x)) : null);
  const s1 = n(l?.min_sentences), s2 = n(l?.max_sentences), c2 = n(l?.max_chars);
  if (!s2 && !c2) return "";
  return `Description length: ${s1 && s2 ? `${s1} to ${s2} sentences` : s2 ? `at most ${s2} sentences` : ""}${s2 && c2 ? ", " : ""}${c2 ? `at most ${c2} characters in all (the sentences, not the quotes)` : ""}.\n`;
}

// the limits from the worker's settings (svc_worker_settings_v1 returns every enrich.* key)
export function courseTextLength(ws: Record<string, unknown> | null | undefined): CourseTextLength {
  const g = (k: string) => Number((ws || {})[k]);
  return { min_sentences: g("enrich.course_description_min_sentences"), max_sentences: g("enrich.course_description_max_sentences"),
           min_chars: g("enrich.course_description_min_chars"), max_chars: g("enrich.course_description_max_chars") };
}

export function courseTextAnswerLimit(ws: Record<string, unknown> | null | undefined): number {
  const n = Number((ws || {})[COURSE_TEXT_ANSWER_KEY]);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : COURSE_TEXT_ANSWER_DEFAULT;
}

const strOrNull = { type: ["string", "null"] };
// only the fields asked are in the schema (strict: every property required)
export function courseTextSchema(want: string[]) {
  const props: Record<string, unknown> = {};
  if (want.includes("description")) props.description = { type: "object", additionalProperties: false, required: ["about_course", "sentences"], properties: {
    about_course: { type: "boolean" },
    sentences: { type: "array", items: { type: "object", additionalProperties: false, required: ["text", "quote"], properties: { text: { type: "string" }, quote: { type: "string" } } } } } };
  if (want.includes("deadline")) props.deadlines = { type: "array", items: { type: "object", additionalProperties: false, required: ["intake", "kind", "date", "quote"], properties: {
    intake: strOrNull, kind: { type: "string", enum: ["date", "rolling", "not_stated"] }, date: strOrNull, quote: { type: "string" } } } };
  return { type: "object", additionalProperties: false, required: Object.keys(props), properties: props };
}

export function courseTextUser(provider: string, title: string, want: string[], page: string, length?: CourseTextLength): string {
  const asked = want.map((f) => (f === "deadline" ? "deadlines" : f));
  return `Provider: ${provider}\nCourse: ${title}\nFields: ${asked.join(", ")}\n${want.includes("description") ? courseTextLengthNote(length) : ""}\nPage text:\n${page}`;
}

export function courseTextRequest(model: string, user: string, want: string[], maxTokens: number) {
  return {
    model, temperature: 0, max_tokens: maxTokens, provider: { require_parameters: true },  // pinned: the central model, never a router
    response_format: { type: "json_schema", json_schema: { name: "course_text", strict: true, schema: courseTextSchema(want) } },
    messages: [{ role: "system", content: COURSE_TEXT_SYSTEM }, { role: "user", content: user }],
  };
}

// the page text the model reads: the stored page's main text without navigation, header, footer and asides (the provider description rule)
export function courseTextPage(html: string, pageChars: number): string { return descriptionPageText(html, pageChars) }

// one answer as OpenRouter returns it (the W32 rules): a cut answer is never parsed and is held, an empty or unreadable answer fails, named;
// the cost is always kept
export function courseTextAnswer(d: any, maxTokens: number): { ok: true; a: any; cost: number } | { ok: false; error: string; cost: number } {
  const cost = callCost(d), ch = d?.choices?.[0] || {}, content = String(ch?.message?.content ?? ""), out = Number(d?.usage?.completion_tokens);
  const cut = (why: string) => ({ ok: false as const, cost, error: `held_partial: output_truncated: course_text ${why} ${COURSE_TEXT_ANSWER_KEY} (${maxTokens})` });
  if (ch?.finish_reason === "length") return cut("reached");
  if (!content.trim()) return { ok: false, cost, error: `no_answer: course_text (${String(ch?.error?.message || d?.error?.message || ch?.finish_reason || "no choices").slice(0, 120)})` };
  try { return { ok: true, a: JSON.parse(content), cost } }
  catch (e) {
    if (Number.isFinite(out) && maxTokens > 0 && out >= maxTokens) return cut("used all of");
    return { ok: false, cost, error: `unreadable_answer: course_text (${e instanceof Error ? e.message : String(e)})`.slice(0, 300) };
  }
}

// the deadlines with whether each quote is on the page; a date that is not YYYY-MM-DD is dropped to null (the database never infers one)
export function courseTextDeadlines(a: any, page: string, minQuoteChars = 8): { intake: string | null; kind: string; date: string | null; quote: string; on_page: boolean }[] {
  const fp = flatText(page);
  return ((a?.deadlines || []) as any[]).map((x) => {
    const quote = String(x?.quote || "").replace(/\s+/g, " ").trim(), fq = flatText(quote);
    const kind = ["date", "rolling", "not_stated"].includes(String(x?.kind)) ? String(x.kind) : "not_stated";
    const date = kind === "date" && /^\d{4}-\d{2}-\d{2}$/.test(String(x?.date || "")) ? String(x.date) : null;
    const intake = x?.intake == null ? null : String(x.intake).replace(/\s+/g, " ").trim().slice(0, 120) || null;
    return { intake, kind, date, quote: quote.slice(0, 300), on_page: fq.length >= minQuoteChars && fp.includes(fq) };
  }).filter((x) => x.quote || x.kind !== "not_stated");
}

// the results recorded for the course's items (svc_enrich_ai_record -> security.enrich_course_text_record_v1)
export function courseTextResults(a: any, page: string, items: { item_id: number; field: string }[], meta: { model: string; worker: string; cost: number; minQuoteChars?: number }) {
  const share = meta.cost / Math.max(1, items.length), out: any[] = [];
  for (const x of items) {
    const base = { item_id: Number(x.item_id), model: meta.model, worker: meta.worker, prompt_version: COURSE_TEXT_PROMPT_VERSION, cost: share };
    if (x.field === "description") {
      const d = descriptionSentences({ about_page: a?.description?.about_course === true, sentences: a?.description?.sentences || [] }, page, meta.minQuoteChars ?? 20);
      const off = d.sentences.filter((s) => !s.on_page).length;
      out.push({ ...base, value: { about_course: d.about_page, sentences: d.sentences }, quote: d.sentences[0]?.quote?.slice(0, 300) ?? null,
        reason: !d.about_page || !d.sentences.length ? "the page does not state it" : off ? "a sentence's quote is not on the page" : null });
    } else {
      const dl = courseTextDeadlines(a, page);
      out.push({ ...base, value: { deadlines: dl }, quote: dl.find((y) => y.kind === "date" && y.on_page)?.quote ?? dl[0]?.quote ?? null,
        reason: dl.length ? null : "the page does not state it" });
    }
  }
  return out;
}
