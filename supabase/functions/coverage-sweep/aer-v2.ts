// v0.79.0 (13 Nov 2026, CF-247 Decision 276, AER v2 step 1: shadow course-page reader; admin docs/platform/AER-DESIGN-V2-PROPOSAL.md v0.3 §3.3, §3.4,
// §3.9 and §9). SHADOW ONLY: nothing read here is admitted, no catalogue table is written and no Layer 4 item is raised.
//   prompt:   the versioned prompt is held in pipeline.aer_prompt_versions (one pinned model per version) and handed to the worker by
//             public.svc_aer_v2_shadow_next; the worker checks the text against its recorded sha-256 before any call (aerV2Sha256).
//   answer:   records, each with scope, applicant country (ISO alpha-2) or qualification (name as printed, plus the reference code when it is one
//             of ref.aer_qualifications), level and route as printed, the minimum exactly as printed, the scale, conditions and verbatim quotes;
//             plus "seen_not_mapped": requirement statements the model saw but could not record, with their quotes (completeness, §9 item 2).
//   verifier: small, strict and deterministic (§3.4). It does not interpret wording; it checks that every quote is on the stored page (the same
//             canonical flat comparison as course-entry.ts and entry.ts: letters and digits, case and spacing ignored), that the minimum is
//             printed in its own quote and any number given is printed in the minimum (values are never converted), that the applicant country
//             is an ISO code of ref.countries and that a qualification code exists in ref.aer_qualifications.
// Pure functions only (no network), so the contract spec can read them.

export const AER_V2_MODE = "aer_v2_shadow";
// v0.93.0 (14 Nov 2026, Platform Admin 14 Nov 2026 option 1): the AER v2 prompt v3 benchmark on the platform AI evaluation framework (svc_aer_v3_eval_next_v1 leases,
// svc_ai_eval_answer_record_v1 records, security.ai_eval_score_v1 scores). No job fires it; it answers only an opened run behind ai_eval.offline_runs_on,
// ai_eval.aer_v3_runs_on and the spend cap ai_eval.aer_v3_max_usd.
export const AER_V3_EVAL_MODE = "aer_v3_eval";

// the same canonical form as course-entry.ts and entry.ts (flat): letters and digits compared, case, accents and spacing ignored
export const aerFlat = (s: unknown) => String(s ?? "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");
const QUOTE_FLOOR = 4;  // fixed: the existing floor for a whole quote (course-entry.ts proveQuote)

export const AER_V2_SCALES = ["percentage", "gpa", "points", "rank", "letter", "aggregate", "none"] as const;
export const AER_V2_QUOTE_FOR = ["requirement", "min_grade", "applicant_country", "qualification", "study_level", "route", "conditions"] as const;

const strOrNull = { type: ["string", "null"] };
export const AER_V2_SCHEMA = {
  type: "object", additionalProperties: false, required: ["records", "seen_not_mapped"],
  properties: {
    records: { type: "array", items: { type: "object", additionalProperties: false,
      required: ["scope", "course_name", "audience", "applicant_country", "qualification", "qualification_code", "study_level", "route", "min_grade", "min_value", "grade_scale", "conditions", "quotes", "confidence"],
      properties: {
        scope: { type: "string", enum: ["course", "provider"] }, course_name: strOrNull,
        audience: { type: "string", enum: ["international", "domestic", "all"] },
        applicant_country: strOrNull, qualification: strOrNull, qualification_code: strOrNull, study_level: strOrNull, route: strOrNull,
        min_grade: strOrNull, min_value: { type: ["number", "null"] }, grade_scale: { type: "string", enum: AER_V2_SCALES }, conditions: strOrNull,
        quotes: { type: "array", items: { type: "object", additionalProperties: false, required: ["value", "text"],
          properties: { value: { type: "string", enum: AER_V2_QUOTE_FOR }, text: { type: "string" } } } },
        confidence: { type: "number" } } } },
    seen_not_mapped: { type: "array", items: { type: "object", additionalProperties: false, required: ["statement", "quote"],
      properties: { statement: { type: "string" }, quote: { type: "string" } } } } } };

export type AerV2Course = { title: string; provider: string; provider_country?: string | null; level?: string | null; url?: string | null };
export type AerV2Qualification = { code: string; name: string };

// the user message: the trusted course record, the qualification reference list, then the page text (data, never instructions)
export function aerV2User(c: AerV2Course, quals: AerV2Qualification[], pageText: string): string {
  const q = quals.map((x) => `${x.code}: ${x.name}`).join("\n");
  return `Provider: ${c.provider}${c.provider_country ? ` (provider country ${c.provider_country})` : ""}\nCourse: ${c.title}\n` +
    (c.level ? `Study level in the catalogue: ${c.level}\n` : "") + (c.url ? `Page address: ${c.url}\n` : "") +
    `\nQUALIFICATIONS (code: name):\n${q}\n\nPage text:\n${pageText}`;
}

export function aerV2Request(model: string, system: string, user: string, maxTokens: number) {
  return { model, temperature: 0, max_tokens: maxTokens, usage: { include: true }, provider: { require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: "aer_v2_course_page", strict: true, schema: AER_V2_SCHEMA } },
    messages: [{ role: "system", content: system }, { role: "user", content: user }] };
}

// the sha-256 of the prompt text, hex (the database records encode(sha256(convert_to(system_text, 'UTF8')), 'hex'))
export async function aerV2Sha256(text: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// the answer as OpenRouter returns it: whole and readable, or failed with the reason named (a cut answer is never parsed)
export function aerV2Answer(d: any, model: string): { ok: true; a: any; cost: number } | { ok: false; error: string; cost: number } {
  const cost = Number(d?.usage?.cost || 0), ch = d?.choices?.[0] || {}, content = String(ch?.message?.content || "");
  if (d?.model && !String(d.model).startsWith(model)) return { ok: false, error: `returned model ${d.model}, not ${model}`, cost };  // pinned: no other model's answer is used
  if (ch?.finish_reason === "length") return { ok: false, error: "output_truncated: the answer reached reading.aer_v2_max_tokens", cost };
  if (!content.trim()) return { ok: false, error: `no_answer (${String(ch?.error?.message || d?.error?.message || ch?.finish_reason || "no choices").slice(0, 120)})`, cost };
  try { return { ok: true, a: JSON.parse(content), cost } } catch (e) { return { ok: false, error: `unreadable_answer (${e instanceof Error ? e.message : String(e)})`.slice(0, 300), cost } }
}

export type AerV2Refs = { countries: Set<string>; qualifications: Set<string> };
export const aerV2Refs = (countries: unknown, quals: unknown): AerV2Refs => ({
  countries: new Set((Array.isArray(countries) ? countries : []).map((x) => String(x).toUpperCase())),
  qualifications: new Set((Array.isArray(quals) ? quals : []).map((x: any) => String(x?.code ?? x))) });

export type AerV2Check = { quote_on_page: boolean; minimum_in_quote: boolean; country_known: boolean; qualification_known: boolean; quote_length_ok: boolean;
  has_minimum: boolean; has_target: boolean; pass: boolean; reasons: string[] };

// the numbers printed in a text ("75%" -> 75, "GPA 5.5/7" -> 5.5 and 7, "1,200" -> 1200)
export const aerNumbers = (s: unknown): number[] => [...String(s ?? "").matchAll(/\d+(?:,\d{3})*(?:\.\d+)?/g)].map((m) => Number(m[0].replace(/,/g, "")));

// one record checked against the stored page text (the text the model was given)
export function aerV2Check(r: any, flatPage: string, refs: AerV2Refs, quoteMax: number): AerV2Check {
  const reasons: string[] = [];
  const quotes: { value: string; text: string }[] = (Array.isArray(r?.quotes) ? r.quotes : []).map((q: any) => ({ value: String(q?.value || ""), text: String(q?.text || "") }));
  const onPage = (t: string) => { const f = aerFlat(t); return f.length >= QUOTE_FLOOR && flatPage.includes(f) };
  // every quote is on the stored page
  const quote_on_page = quotes.length > 0 && quotes.every((q) => onPage(q.text));
  if (!quotes.length) reasons.push("no_quote");
  else if (!quote_on_page) reasons.push("quote_not_on_page");
  const quote_length_ok = quotes.every((q) => q.text.trim().length <= quoteMax);
  if (!quote_length_ok) reasons.push("quote_too_long");
  // the minimum is printed in its own quote; a number is only the one printed in the minimum (never converted)
  const grade = r?.min_grade == null ? "" : String(r.min_grade), value = r?.min_value == null ? null : Number(r.min_value);
  const has_minimum = !!grade.trim() || value !== null;
  let minimum_in_quote = true;
  if (has_minimum) {
    const fg = aerFlat(grade);
    const own = quotes.filter((q) => q.value === "min_grade");
    if (!fg) { minimum_in_quote = false; reasons.push("value_without_printed_minimum") }
    else if (!own.length) { minimum_in_quote = false; reasons.push("minimum_has_no_quote") }
    else if (!own.some((q) => aerFlat(q.text).includes(fg) && onPage(q.text))) { minimum_in_quote = false; reasons.push("minimum_not_in_quote") }
    if (value !== null && fg && !(Number.isFinite(value) && aerNumbers(grade).some((n) => n === value))) { minimum_in_quote = false; reasons.push("value_not_printed_in_minimum") }
  }
  // the applicant country is an ISO code in reference data; a domestic-only route names no applicant country
  const cc = r?.applicant_country == null ? null : String(r.applicant_country).trim().toUpperCase();
  let country_known = cc === null || (/^[A-Z]{2}$/.test(cc) && refs.countries.has(cc));
  if (!country_known) reasons.push("country_not_in_reference");
  if (cc !== null && r?.audience === "domestic") { country_known = false; reasons.push("domestic_route_with_country") }
  // a qualification code exists in reference data (a qualification printed with no code is kept as printed)
  const qc = r?.qualification_code == null ? null : String(r.qualification_code).trim();
  const qualification_known = qc === null || (refs.qualifications.has(qc) && !!String(r?.qualification ?? "").trim());
  if (!qualification_known) reasons.push(refs.qualifications.has(qc ?? "") ? "qualification_code_without_name" : "qualification_not_in_reference");
  const has_target = cc !== null || !!String(r?.qualification ?? "").trim();
  const pass = quote_on_page && minimum_in_quote && country_known && qualification_known && quote_length_ok;
  return { quote_on_page, minimum_in_quote, country_known, qualification_known, quote_length_ok, has_minimum, has_target, pass, reasons };
}

export type AerV2Verified = { records: any[]; checks: AerV2Check[]; seen_not_mapped: { statement: string; quote: string; on_page: boolean }[]; passed: number; failed: number };

// the whole answer verified: records kept as the model gave them (shadow: nothing is changed or admitted), one check per record (same order)
export function aerV2Verify(a: any, pageText: string, refs: AerV2Refs, quoteMax: number): AerV2Verified {
  const P = aerFlat(pageText);
  const records: any[] = Array.isArray(a?.records) ? a.records : [];
  const checks = records.map((r) => aerV2Check(r, P, refs, quoteMax));
  const seen = (Array.isArray(a?.seen_not_mapped) ? a.seen_not_mapped : []).map((s: any) => {
    const q = String(s?.quote || ""), f = aerFlat(q);
    return { statement: String(s?.statement || "").slice(0, 500), quote: q.slice(0, quoteMax), on_page: f.length >= QUOTE_FLOOR && P.includes(f) };
  });
  const passed = checks.filter((c) => c.pass).length;
  return { records, checks, seen_not_mapped: seen, passed, failed: checks.length - passed };
}

// ---------------------------------------------------------------------------------------------------------------------------------------------
// v0.88.0 (14 Nov 2026, CF-247 AER v2 prompt v3, Platform Admin 14 Nov 2026 item 2): answer contract aer-v2-answer-v3 over input lean-blocks-v1.
//   input:    the WHOLE stored page (never cut, never section-selected) as the Lean AI Input lean-md blocks (lean-md-v2 from v0.93.0) (lean-input.ts; the block form Phase 1b
//             selects from), each on its own line as "[B<n> @<source_at>] <block>": headings kept as "## ...", list items as "- ...", every table row
//             with its column headers ("Header: cell | Header: cell"). Page data fields come first as "[B<n> @data] ...". <n> is the block's number
//             in this rendering (1, 2, 3 ... in page order); <source_at> is its offset in the stored page (Phase 1b's "[§n @source_at]", here
//             numbered B so the model can cite a block by its number).
//   answer:   each record cites ONE block for its exact_quote (the statement that prints the minimum, copied from that block only) and, when the
//             statement only makes sense after a list lead-in ("one of the following:", "Applicants must have:"), the lead-in separately as
//             lead_in_quote with its own block. The two are never joined into one quote (the v2 trial's commonest failure).
//   verifier: every quote is inside the block it cites (canonical flat form), the minimum is printed inside exact_quote, and the lead-in obeys the
//             ordered proximity rule: it comes before the exact quote (an earlier block, or earlier in the same block without overlap), at most
//             aer.v3_lead_in_max_blocks blocks before it, and no heading lies between them (the lead-in may itself be a heading). Country and
//             qualification checks are as in v2. Every passed record carries its blocks' source offsets (evidence back to the stored page).
// Pure functions only, as above.

export const AER_V3_CONTRACT = "aer-v2-answer-v3";
export const AER_V3_INPUT = "lean-blocks-v1";

export type AerBlock = { n: number; kind: string; text: string; source_at: number | null };
export type AerBlocks = { input: string; text: string; blocks: AerBlock[] };

// the whole page as numbered blocks (page data first); lean is leanText(html) from lean-input.ts, data is pageDataItems(html) (one field a line)
export function aerV3Blocks(lean: { converter: string; blocks: { kind: string; text: string; source_at: number }[] }, data?: string | null): AerBlocks {
  const blocks: AerBlock[] = [];
  for (const line of String(data || "").split("\n").map((s) => s.replace(/\s+/g, " ").trim()).filter(Boolean)) blocks.push({ n: blocks.length + 1, kind: "data", text: line, source_at: null });
  for (const b of lean.blocks) blocks.push({ n: blocks.length + 1, kind: b.kind, text: b.text, source_at: b.source_at });
  const show = (b: AerBlock) => `[B${b.n} @${b.source_at === null ? "data" : b.source_at}] ${b.kind === "heading" ? "## " : b.kind === "item" ? "- " : ""}${b.text}`;
  return { input: `${AER_V3_INPUT}/${lean.converter}`, text: blocks.map(show).join("\n"), blocks };
}

const quoteV3 = { type: "object", additionalProperties: false, required: ["value", "block", "text"],
  properties: { value: { type: "string", enum: ["applicant_country", "qualification", "study_level", "route", "conditions"] }, block: { type: "integer" }, text: { type: "string" } } };
export const AER_V3_SCHEMA = {
  type: "object", additionalProperties: false, required: ["records", "seen_not_mapped"],
  properties: {
    records: { type: "array", items: { type: "object", additionalProperties: false,
      required: ["scope", "course_name", "audience", "applicant_country", "qualification", "qualification_code", "study_level", "route", "min_grade", "min_value", "grade_scale",
                 "conditions", "exact_block", "exact_quote", "lead_in_block", "lead_in_quote", "support", "confidence"],
      properties: {
        scope: { type: "string", enum: ["course", "provider"] }, course_name: strOrNull,
        audience: { type: "string", enum: ["international", "domestic", "all"] },
        applicant_country: strOrNull, qualification: strOrNull, qualification_code: strOrNull, study_level: strOrNull, route: strOrNull,
        min_grade: strOrNull, min_value: { type: ["number", "null"] }, grade_scale: { type: "string", enum: AER_V2_SCALES }, conditions: strOrNull,
        exact_block: { type: "integer" }, exact_quote: { type: "string" },
        lead_in_block: { type: ["integer", "null"] }, lead_in_quote: strOrNull,
        support: { type: "array", items: quoteV3 },
        confidence: { type: "number" } } } },
    seen_not_mapped: { type: "array", items: { type: "object", additionalProperties: false, required: ["statement", "block", "quote"],
      properties: { statement: { type: "string" }, block: { type: "integer" }, quote: { type: "string" } } } } } };

// the user message: the trusted course record, the qualification reference list, then the page blocks (data, never instructions)
export function aerV3User(c: AerV2Course, quals: AerV2Qualification[], b: AerBlocks): string {
  const q = quals.map((x) => `${x.code}: ${x.name}`).join("\n");
  return `Provider: ${c.provider}${c.provider_country ? ` (provider country ${c.provider_country})` : ""}\nCourse: ${c.title}\n` +
    (c.level ? `Study level in the catalogue: ${c.level}\n` : "") + (c.url ? `Page address: ${c.url}\n` : "") +
    `\nQUALIFICATIONS (code: name):\n${q}\n\nPAGE BLOCKS (${b.blocks.length} blocks, the whole page, in page order):\n${b.text}`;
}

// routing is the version's pinned provider routing (pipeline.aer_prompt_versions.routing: order, allow_fallbacks false, quantizations);
// require_parameters is always set so no provider that ignores the strict schema is used; params are the version's extra request fields
// (for example reasoning off); neither may replace the model, the schema or the messages
export function aerV3Request(model: string, system: string, user: string, maxTokens: number, routing?: Record<string, unknown> | null, params?: Record<string, unknown> | null) {
  const extra: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(params || {})) if (!["model", "messages", "response_format", "provider", "max_tokens", "temperature"].includes(k)) extra[k] = v;
  return { ...extra, model, temperature: 0, max_tokens: maxTokens, usage: { include: true }, provider: { ...(routing || {}), require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: "aer_v2_course_page_v3", strict: true, schema: AER_V3_SCHEMA } },
    messages: [{ role: "system", content: system }, { role: "user", content: user }] };
}

export type AerV3Check = { exact_in_block: boolean; lead_in_ok: boolean; minimum_in_quote: boolean; country_known: boolean; qualification_known: boolean;
  quote_length_ok: boolean; support_ok: boolean; has_minimum: boolean; has_target: boolean; exact_source_at: number | null; lead_in_source_at: number | null;
  pass: boolean; reasons: string[] };

// one record checked against the blocks the model was given; gapMax is aer.v3_lead_in_max_blocks
export function aerV3Check(r: any, b: AerBlocks, refs: AerV2Refs, quoteMax: number, gapMax: number): AerV3Check {
  const reasons: string[] = [];
  const blockOf = (n: unknown) => (Number.isInteger(n) ? b.blocks[(n as number) - 1] : undefined);
  const fb = (blk: AerBlock | undefined) => (blk ? aerFlat(blk.text) : "");
  // the exact quote: one block, copied from it
  const ex = blockOf(r?.exact_block), exq = String(r?.exact_quote ?? ""), fex = aerFlat(exq), exAt = ex ? fb(ex).indexOf(fex) : -1;
  let exact_in_block = false;
  if (fex.length < QUOTE_FLOOR) reasons.push("no_exact_quote");
  else if (!ex) reasons.push("exact_block_unknown");
  else if (exAt < 0) reasons.push("exact_quote_not_in_block");
  else exact_in_block = true;
  let quote_length_ok = exq.trim().length <= quoteMax;
  if (!quote_length_ok) reasons.push("exact_quote_too_long");
  // the lead-in: its own block, before the exact quote, close to it, no heading between (ordered proximity)
  const liq = r?.lead_in_quote == null ? "" : String(r.lead_in_quote), fli = aerFlat(liq);
  let lead_in_ok = true, lead_in_source_at: number | null = null;
  if (fli) {
    const li = blockOf(r?.lead_in_block), liAt = li ? fb(li).indexOf(fli) : -1;
    if (liq.trim().length > quoteMax) { quote_length_ok = false; reasons.push("lead_in_too_long") }
    if (!li) { lead_in_ok = false; reasons.push("lead_in_block_unknown") }
    else if (liAt < 0) { lead_in_ok = false; reasons.push("lead_in_not_in_block") }
    else if (ex && exact_in_block) {
      const same = li.n === ex.n;
      if (li.n > ex.n || (same && liAt + fli.length > exAt)) { lead_in_ok = false; reasons.push("lead_in_not_before_exact") }
      else if (ex.n - li.n > gapMax) { lead_in_ok = false; reasons.push("lead_in_too_far") }
      else if (b.blocks.slice(li.n, ex.n - 1).some((x) => x.kind === "heading")) { lead_in_ok = false; reasons.push("lead_in_crosses_heading") }
      if (fex.includes(fli)) { lead_in_ok = false; reasons.push("lead_in_repeated_in_exact") }
    }
    if (lead_in_ok) lead_in_source_at = li!.source_at;
  } else if (r?.lead_in_block != null) { lead_in_ok = false; reasons.push("lead_in_block_without_quote") }
  // supporting quotes: each inside the block it cites
  const support: any[] = Array.isArray(r?.support) ? r.support : [];
  let support_ok = true;
  for (const s of support) {
    const blk = blockOf(s?.block), f = aerFlat(s?.text);
    if (String(s?.text ?? "").trim().length > quoteMax) { quote_length_ok = false; if (!reasons.includes("support_too_long")) reasons.push("support_too_long") }
    if (f.length < QUOTE_FLOOR || !blk || !fb(blk).includes(f)) { support_ok = false; if (!reasons.includes("support_not_in_block")) reasons.push("support_not_in_block") }
  }
  // the minimum is printed inside the exact quote; a number only the one printed in the minimum (never converted)
  const grade = r?.min_grade == null ? "" : String(r.min_grade), value = r?.min_value == null ? null : Number(r.min_value), fg = aerFlat(grade);
  const has_minimum = !!grade.trim() || value !== null;
  let minimum_in_quote = true;
  if (has_minimum) {
    if (!fg) { minimum_in_quote = false; reasons.push("value_without_printed_minimum") }
    else if (!fex.includes(fg)) { minimum_in_quote = false; reasons.push("minimum_not_in_exact_quote") }
    if (value !== null && fg && !(Number.isFinite(value) && aerNumbers(grade).some((n) => n === value))) { minimum_in_quote = false; reasons.push("value_not_printed_in_minimum") }
  }
  // country and qualification, as in v2
  const cc = r?.applicant_country == null ? null : String(r.applicant_country).trim().toUpperCase();
  let country_known = cc === null || (/^[A-Z]{2}$/.test(cc) && refs.countries.has(cc));
  if (!country_known) reasons.push("country_not_in_reference");
  if (cc !== null && r?.audience === "domestic") { country_known = false; reasons.push("domestic_route_with_country") }
  const qc = r?.qualification_code == null ? null : String(r.qualification_code).trim();
  const qualification_known = qc === null || (refs.qualifications.has(qc) && !!String(r?.qualification ?? "").trim());
  if (!qualification_known) reasons.push(refs.qualifications.has(qc ?? "") ? "qualification_code_without_name" : "qualification_not_in_reference");
  const has_target = cc !== null || !!String(r?.qualification ?? "").trim();
  const pass = exact_in_block && lead_in_ok && minimum_in_quote && country_known && qualification_known && quote_length_ok && support_ok;
  return { exact_in_block, lead_in_ok, minimum_in_quote, country_known, qualification_known, quote_length_ok, support_ok, has_minimum, has_target,
    exact_source_at: exact_in_block ? ex!.source_at : null, lead_in_source_at, pass, reasons };
}

export type AerV3Verified = { records: any[]; checks: AerV3Check[]; seen_not_mapped: { statement: string; block: number | null; quote: string; on_page: boolean }[]; passed: number; failed: number };

// the whole answer verified: records kept as the model gave them (nothing changed or admitted), one check per record (same order)
export function aerV3Verify(a: any, b: AerBlocks, refs: AerV2Refs, quoteMax: number, gapMax: number): AerV3Verified {
  const records: any[] = Array.isArray(a?.records) ? a.records : [];
  const checks = records.map((r) => aerV3Check(r, b, refs, quoteMax, gapMax));
  const seen = (Array.isArray(a?.seen_not_mapped) ? a.seen_not_mapped : []).map((s: any) => {
    const q = String(s?.quote || ""), f = aerFlat(q), n = Number.isInteger(s?.block) ? s.block : null, blk = n ? b.blocks[n - 1] : undefined;
    return { statement: String(s?.statement || "").slice(0, 500), block: n, quote: q.slice(0, quoteMax), on_page: f.length >= QUOTE_FLOOR && !!blk && aerFlat(blk.text).includes(f) };
  });
  const passed = checks.filter((c) => c.pass).length;
  return { records, checks, seen_not_mapped: seen, passed, failed: checks.length - passed };
}
