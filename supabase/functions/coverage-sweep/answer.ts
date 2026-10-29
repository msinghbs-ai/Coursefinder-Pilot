// v0.54.0 (29 Oct 2026, CF-247 decision W32: reader answer limits). Every AI read in the worker had its answer limit written into the code
// (2,000 tokens for the Enrich fields reads, 3,000 scholarship pages, 800 scholarship re-checks, 1,500 central pages, 300 course page
// matching, 4,000 then 8,000 adapter proposals, and no limit at all for fee pages). A read whose answer reached the limit was parsed as JSON
// ("Unterminated string in JSON at position 3,948 to 9,149" on seven Enrich fields items, 21 to 27 Oct 2026), retried at the same size, and
// the cost of the cut call was not recorded. W29 fixed the course entry-requirements read (course-entry.ts); W32 applies the same rules to
// every other read:
//   limit:     each read type's answer limit is a setting (pipeline toolset, key reading.answer_tokens.<read>), read through
//              svc_worker_settings_v1. The defaults are today's values, so nothing changes until a person changes a setting.
//   cut:       an answer that reached its limit (finish_reason length), or one that is not JSON while its output tokens reached the limit, is
//              output_truncated and the whole read is held (held_partial on the existing failure path; no new status). Nothing of a cut answer
//              is parsed, quoted or proposed.
//   cost:      the cost of every call made is recorded, also when the read fails or is held.
// Pure functions only (no network): tests/uat/cf-247-s173-reader-answer-limits-contract.spec.mjs runs them on recorded long answers.

// read type -> its setting and today's value (the value used only when the setting cannot be read)
export const READ_ANSWER_LIMITS = {
  course_fields:       { key: "reading.answer_tokens.course_fields",       def: 2000,  mode: "enrich_ai (course page fields: campus, duration, delivery, level, international, english, intakes)" },
  course_titles:       { key: "reading.answer_tokens.course_titles",       def: 2000,  mode: "enrich_ai (field of study and level from titles)" },
  campus_regions:      { key: "reading.answer_tokens.campus_regions",      def: 2000,  mode: "enrich_ai (region of each campus city)" },
  campus_lists:        { key: "reading.answer_tokens.campus_lists",        def: 2000,  mode: "enrich_ai (a university's campus list)" },
  provider_address:    { key: "reading.answer_tokens.provider_address",    def: 2000,  mode: "enrich_ai (provider street address)" },
  scholarship_page:    { key: "reading.answer_tokens.scholarship_page",    def: 3000,  mode: "scholarship_ai" },
  scholarship_recheck: { key: "reading.answer_tokens.scholarship_recheck", def: 800,   mode: "scholarship_recheck" },
  central_page:        { key: "reading.answer_tokens.central_page",        def: 1500,  mode: "central_ai" },
  fee_page:            { key: "reading.answer_tokens.fee_page",            def: 32000, mode: "fee_ai" },
  course_page_match:   { key: "reading.answer_tokens.course_page_match",   def: 300,   mode: "ai_match" },
  adapter_proposal:    { key: "reading.answer_tokens.adapter_proposal",    def: 4000,  mode: "adapter_propose (first ask)" },
  adapter_proposal_retry: { key: "reading.answer_tokens.adapter_proposal_retry", def: 8000, mode: "adapter_propose (asked again once when the first answer was cut)" },
} as const;
export type ReadType = keyof typeof READ_ANSWER_LIMITS;

// the answer limit of a read type from the worker's settings (a missing, unreadable or non-positive value gives today's value)
export function answerLimit(ws: Record<string, unknown> | null | undefined, read: ReadType): number {
  const n = Number((ws || {})[READ_ANSWER_LIMITS[read].key]);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : READ_ANSWER_LIMITS[read].def;
}

// the cost OpenRouter reports for one call (0 when it is not given)
export function callCost(d: any): number { const c = Number(d?.usage?.cost || 0); return Number.isFinite(c) && c > 0 ? c : 0 }

export type ReadAnswer = { ok: true; a: any; cost: number } | { ok: false; cut: boolean; error: string; cost: number };

// one answer as OpenRouter returns it: whole and readable, or failed with the reason named. A cut answer is never parsed.
// `where` names the read in the message, for example "course_fields" or "slice 2 of 3".
export function readAnswer(d: any, read: ReadType, maxTokens: number, where: string = read): ReadAnswer {
  const cost = callCost(d), key = READ_ANSWER_LIMITS[read].key;
  const ch = d?.choices?.[0] || {}, content = String(ch?.message?.content ?? "");
  const out = Number(d?.usage?.completion_tokens);
  const truncated = (why: string) => ({ ok: false as const, cut: true, cost, error: `held_partial: output_truncated: ${where} ${why} ${key} (${maxTokens})` });
  if (ch?.finish_reason === "length") return truncated("reached");
  if (!content.trim()) {
    const err = ch?.error?.message || d?.error?.message || (ch?.finish_reason ? `finish: ${ch.finish_reason}` : "no choices");
    return { ok: false, cut: false, cost, error: `no_answer: ${where} (${String(err).slice(0, 120)})` };
  }
  try { return { ok: true, a: JSON.parse(content), cost } }
  catch (e) {
    // a provider that does not report finish_reason length: an unreadable answer that used the whole limit is a cut answer
    if (Number.isFinite(out) && maxTokens > 0 && out >= maxTokens) return truncated("used all of");
    return { ok: false, cut: false, cost, error: `unreadable_answer: ${where} (${e instanceof Error ? e.message : String(e)})`.slice(0, 300) };
  }
}

// an Error carrying the cost of the call, so a catch records what was spent
export function readError(message: string, cost: number): Error & { cost: number } { return Object.assign(Error(message), { cost }) }
export function errorCost(e: unknown): number { const c = Number((e as any)?.cost || 0); return Number.isFinite(c) && c > 0 ? c : 0 }
