// CF-CHG-20260915-247 Layer 3 model routing (Platform Admin direction 29 Sep 2026 18:30 IST).
// Pure functions (no I/O) shared by the holdout qualification and the live worker of layer3-model-routing, so a
// qualification PASS describes exactly what production runs: the request body, the text the model sees, the
// deterministic validation and the admitted value are all built here, in one place, for each task class.
//
//  provider_intake_validation   intake months      (contract cf247-intake-validation-v1.2.0, unchanged)
//  provider_english_validation  IELTS/PTE/TOEFL    (contract cf247-english-validation-v1.0.0)
//  provider_current_tuition_validation              (the live interpreter's request and checks, replicated)
//
// Scoring outcomes (per case, against a hand-read gold answer):
//  exact              stated case, admitted value equals the gold value
//  exact_not_stated   nothing stated, nothing admitted
//  wrong_admitted     a value passed every check and would be admitted, but it is not the gold value
//  incomplete         admitted value is right but partial (a missing month, a missing IELTS band, a missing fee year)
//  not_stated_on_stated  the model said nothing is stated where the gold has a value (nothing admitted)
//  withheld           rejected by the validators, low confidence, or no answer (routes to Layer 4; nothing admitted)

import {
  applyIntakeSafetyRule, focusText, INTAKE_RESPONSE_SCHEMA, INTAKE_SAFETY_RULES, INTAKE_SYSTEM_PROMPT, INTAKE_VALIDATOR_VERSION,
  intakeSafetyBlockers, MAX_QUOTES, validateIntakeAnswer,
} from "./cf247-intake-validation.ts";
import { INTAKE_SYSTEM_PROMPT_V13, INTAKE_VALIDATOR_VERSION_V13, ROLLING_RE, monthsWrittenV13, quoteInTextV13, validateIntakeAnswerV13 } from "./cf247-intake-validation-v13.ts";
import {
  ENGLISH_RESPONSE_SCHEMA, ENGLISH_SYSTEM_PROMPT, ENGLISH_VALIDATOR_VERSION, englishFocusText, scoreEnglishCase, validateEnglishAnswer,
} from "./cf247-english-validation.ts";
import {
  quoteComparable as tuitionQuoteComparable, tuitionQuoteSupports, tuitionQuoteSupportsBasis, tuitionValidationPromptContext,
  validateProviderCurrentTuitionCandidate,
} from "./cf247-tuition-validation.ts";

export const ROUTING_VERSION = "cf247-l3-model-routing-v1.0.0";
export const TASKS = {
  intake: "provider_intake_validation",
  english: "provider_english_validation",
  tuition: "provider_current_tuition_validation",
} as const;
export type TaskKey = keyof typeof TASKS;
export const INTAKE_MAX_CHARS = 30000;
export const ENGLISH_MAX_CHARS = 24000;

export function isPinnedModel(model: string) {
  return !!model && !/(^|\/)auto$|openrouter\/auto|:auto\b|\/router\b/i.test(model) && /^[a-z0-9-]+\/[a-z0-9._:-]+$/i.test(model);
}

// ---------- request bodies (the binding hash covers these sources) ----------
// No seed: with require_parameters a seed would exclude providers that do not take one (for example Anthropic);
// temperature 0, a strict JSON schema and the deterministic validators carry the determinism instead.
export function intakeRequestBody(model: string, text: string, maxTokens: number) {
  return {
    model, temperature: 0, max_tokens: maxTokens,
    provider: { require_parameters: true }, usage: { include: true },
    response_format: { type: "json_schema", json_schema: { name: "cf247_intake_months", strict: true, schema: INTAKE_RESPONSE_SCHEMA } },
    messages: [
      { role: "system", content: INTAKE_SYSTEM_PROMPT },
      { role: "user", content: `Course page text:\n${focusText(text, INTAKE_MAX_CHARS)}` },
    ],
  };
}
export function englishRequestBody(model: string, text: string, maxTokens: number) {
  return {
    model, temperature: 0, max_tokens: maxTokens,
    provider: { require_parameters: true }, usage: { include: true },
    response_format: { type: "json_schema", json_schema: { name: "cf247_english_requirements", strict: true, schema: ENGLISH_RESPONSE_SCHEMA } },
    messages: [
      { role: "system", content: ENGLISH_SYSTEM_PROMPT },
      { role: "user", content: `Course page text:\n${englishFocusText(text, ENGLISH_MAX_CHARS)}` },
    ],
  };
}

// The live interpreter's Evidence text (layer3-work-interpret evidenceText), unchanged.
export function tuitionEvidenceText(bytes: Uint8Array, mime: string | null, maxChars: number) {
  const allowed = ["text/", "application/json", "application/xml", "application/xhtml+xml"];
  if (mime && !allowed.some((x) => mime.startsWith(x))) throw new Error(`evidence MIME type ${mime} is not supported`);
  let text = new TextDecoder("utf-8", { fatal: false }).decode(bytes);
  if (mime?.includes("html") || /<html|<body|<div|<p[ >]/i.test(text.slice(0, 1000)))
    text = text.replace(/<script[\s\S]*?<\/script>/gi, " ").replace(/<style[\s\S]*?<\/style>/gi, " ").replace(/<[^>]+>/g, " ").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&");
  return text.replace(/\s+/g, " ").trim().slice(0, maxChars);
}
// The live interpreter's request (layer3-work-interpret), unchanged: same prompt lines, json_object, profile settings.
export function tuitionRequestBody(profile: any, sourceUrl: string | null, context: any, text: string) {
  const prompt = [
    "Task class: provider_current_tuition_validation",
    `Governed Evidence source: ${sourceUrl || "retained Evidence"}`,
    tuitionValidationPromptContext(context),
    "Return exactly one JSON object with keys candidate_value, confidence, rationale, evidence_quotes. candidate_value must be null or one supplied tuition candidate with amount, currency_code, basis, fee_year and audience. Evidence must explicitly support any basis resolution; otherwise return null.",
    `Evidence:\n${text}`,
  ].join("\n\n");
  return {
    model: profile.model_identifier, temperature: 0, seed: 0,
    max_tokens: Number(profile.max_output_tokens || 1200),
    provider: { require_parameters: true },
    response_format: { type: "json_object" },
    messages: [{ role: "system", content: profile.prompt_system }, { role: "user", content: prompt }],
  };
}
export function tuitionMaxChars(profile: any) { return Math.min(Number(profile.max_input_tokens || 12000) * 4, 120000) }

export function parseModelJson(v: unknown): any {
  if (v && typeof v === "object") return v;
  if (typeof v !== "string") throw new Error("model response content is not JSON text");
  return JSON.parse(v.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, ""));
}

// ---------- validation to an admitted value ----------
export type Checked = { valid: boolean; errors: string[]; status: string | null; admitted: any | null; detail?: any };

export function checkIntake(answer: any, text: string, blockers: { code: string; quote: string }[]): Checked {
  const v = applyIntakeSafetyRule(validateIntakeAnswer(answer, text), blockers);
  return { valid: v.valid, errors: v.errors, status: v.status, admitted: v.valid && v.status === "months" ? { months: v.months } : null, detail: { quotes: v.quotes } };
}
export function checkEnglish(answer: any, text: string): Checked {
  const v = validateEnglishAnswer(answer, text);
  return { valid: v.valid, errors: v.errors, status: v.status, admitted: v.valid && v.status === "stated" ? { tests: v.tests.map((t) => ({ test: t.test, overall: t.overall, min_band: t.min_band })) } : null, detail: { tests: v.tests } };
}
// The interpreter's checks followed by the admission gates of security.layer3_tuition_admit_validated_v1.
export function checkTuition(parsed: any, text: string, context: any, profile: any, cost: number): Checked {
  const validators = profile.deterministic_validators ?? profile.validators ?? {};
  const errors: string[] = [];
  const confidence = Number(parsed?.confidence);
  const min = Number(validators?.confidence_min ?? 0), max = Number(validators?.confidence_max ?? 1);
  if (!Number.isFinite(confidence) || confidence < min || confidence > max) errors.push("confidence outside allowed range");
  if (typeof parsed?.rationale !== "string" || !parsed.rationale.trim()) errors.push("rationale is required");
  const quotes = Array.isArray(parsed?.evidence_quotes) ? parsed.evidence_quotes : [];
  if (!Array.isArray(parsed?.evidence_quotes)) errors.push("evidence_quotes must be an array");
  if (quotes.length > Number(validators?.max_quotes ?? 4)) errors.push("too many evidence quotes");
  const haystack = tuitionQuoteComparable(text);
  for (const quote of quotes) {
    if (typeof quote !== "string" || quote.length > Number(validators?.max_quote_chars ?? 600)) errors.push("invalid evidence quote");
    else if (quote.trim() && !haystack.includes(tuitionQuoteComparable(quote))) errors.push("evidence quote not present in governed Evidence");
  }
  const tuition = validateProviderCurrentTuitionCandidate(parsed?.candidate_value ?? null, context);
  errors.push(...tuition.errors);
  if (tuition.basis_resolution && parsed?.candidate_value && !tuitionQuoteSupportsBasis(quotes, parsed.candidate_value.amount, parsed.candidate_value.basis))
    errors.push("Evidence quote does not explicitly support the resolved tuition basis");
  if (tuition.year_resolution && parsed?.candidate_value && !tuitionQuoteSupports(quotes, parsed.candidate_value.amount, parsed.candidate_value.fee_year))
    errors.push("Evidence quote does not state the resolved fee year together with the amount");
  if (Number(profile.cost_ceiling_usd) >= 0 && cost > Number(profile.cost_ceiling_usd)) errors.push("response exceeded configured cost ceiling");
  const valid = errors.length === 0;
  const cand = parsed?.candidate_value ?? null;
  if (!valid) return { valid, errors, status: "rejected_validation", admitted: null };
  if (cand == null) return { valid, errors, status: "no_candidate", admitted: null };
  const threshold = Number(validators?.review_confidence_min ?? 0);
  if (confidence < threshold) return { valid, errors: ["low_confidence"], status: "low_confidence", admitted: null };
  // admission gates (security.layer3_tuition_admit_validated_v1)
  const basis = (tuition as any)?.provider_rule_basis && tuition.matched_candidate ? String((tuition.matched_candidate as any).basis) : String(cand.basis ?? "");
  const cur = String(cand.currency_code ?? cand.currency ?? "").trim().toUpperCase();
  const amount = Number(cand.amount);
  const hold: string[] = [];
  if (!(amount > 0)) hold.push("amount_not_positive");
  if (String(cand.audience ?? "").trim().toLowerCase() !== "international") hold.push("audience_not_international");
  if (Array.isArray(validators?.allowed_currencies) && !validators.allowed_currencies.includes(cur)) hold.push("currency_not_allowed");
  if (Array.isArray(validators?.allowed_basis) && !validators.allowed_basis.includes(basis)) hold.push("basis_not_allowed");
  if (validators?.amount_max != null && amount > Number(validators.amount_max)) hold.push("amount_above_ceiling");
  if (hold.length) return { valid, errors: hold, status: "admission_hold", admitted: null };
  const year = cand.fee_year == null || String(cand.fee_year).trim() === "" ? null : Number(cand.fee_year);
  return { valid, errors, status: "validated", admitted: { amount, currency_code: cur, basis, fee_year: year } };
}

// ---------- scoring ----------
export function scoreIntake(gold: { status: string; months: number[] }, chk: Checked) {
  if (!chk.valid) return { outcome: "withheld", wrong: [] as number[] };
  const g = new Set(gold.status === "months" ? gold.months.map(Number) : []);
  const p: number[] = chk.admitted?.months ?? [];
  const wrong = p.filter((m) => !g.has(m));
  if (wrong.length) return { outcome: "wrong_admitted", wrong };
  if (gold.status !== "months") return { outcome: "exact_not_stated", wrong };
  if (!p.length) return { outcome: "not_stated_on_stated", wrong };
  return { outcome: p.length === g.size ? "exact" : "incomplete", wrong };
}
export function scoreEnglish(gold: any, chk: Checked) {
  if (!chk.valid) return { outcome: "withheld", wrong: [] as string[] };
  const s = scoreEnglishCase(gold, { status: chk.status, tests: chk.admitted?.tests ?? [] });
  if (s.wrong.length) return { outcome: "wrong_admitted", wrong: s.wrong };
  if (gold.status !== "stated") return { outcome: "exact_not_stated", wrong: [] };
  if (!chk.admitted) return { outcome: "not_stated_on_stated", wrong: [] };
  return { outcome: s.exact ? "exact" : "incomplete", wrong: [], missed: s.missed };
}
export function scoreTuition(gold: { status: string; amount?: number; fee_year?: number | null }, chk: Checked) {
  const a = chk.admitted;
  if (!a) {
    if (gold.status !== "admit") return { outcome: chk.status === "no_candidate" ? "exact_not_stated" : "withheld", wrong: [] as string[] };
    return { outcome: chk.status === "no_candidate" ? "not_stated_on_stated" : "withheld", wrong: [] as string[] };
  }
  if (gold.status !== "admit") return { outcome: "wrong_admitted", wrong: ["admitted where gold has no admissible annual fee"] };
  const wrong: string[] = [];
  if (Number(a.amount) !== Number(gold.amount)) wrong.push(`amount ${a.amount}<>${gold.amount}`);
  const gy = gold.fee_year ?? null;
  if (a.fee_year != null && a.fee_year !== gy) wrong.push(`fee_year ${a.fee_year}<>${gy}`);
  if (wrong.length) return { outcome: "wrong_admitted", wrong };
  if (a.fee_year == null && gy != null) return { outcome: "incomplete", wrong };
  return { outcome: "exact", wrong };
}

// ---------- contract fingerprints (frozen before any holdout case is read) ----------
export function contractComponents(task: TaskKey): Record<string, unknown> {
  if (task === "intake") return {
    version: INTAKE_VALIDATOR_VERSION, prompt: INTAKE_SYSTEM_PROMPT, schema: INTAKE_RESPONSE_SCHEMA, max_quotes: MAX_QUOTES, max_chars: INTAKE_MAX_CHARS,
    safety_rules: INTAKE_SAFETY_RULES.map((r) => ({ code: r.code, re: String(r.re) })), validate: validateIntakeAnswer.toString(),
    safety_blockers: intakeSafetyBlockers.toString(), safety_apply: applyIntakeSafetyRule.toString(), focus: focusText.toString(),
    request_body: intakeRequestBody.toString(), check: checkIntake.toString(), score: scoreIntake.toString(),
  };
  if (task === "english") return {
    version: ENGLISH_VALIDATOR_VERSION, prompt: ENGLISH_SYSTEM_PROMPT, schema: ENGLISH_RESPONSE_SCHEMA, max_chars: ENGLISH_MAX_CHARS,
    validate: validateEnglishAnswer.toString(), focus: englishFocusText.toString(), request_body: englishRequestBody.toString(),
    check: checkEnglish.toString(), score: scoreEnglish.toString(), score_case: scoreEnglishCase.toString(),
  };
  return {
    version: "cf247-provider-current-tuition-validation-v2 (live interpreter)", request_body: tuitionRequestBody.toString(),
    evidence_text: tuitionEvidenceText.toString(), prompt_context: tuitionValidationPromptContext.toString(),
    validate: validateProviderCurrentTuitionCandidate.toString(), check: checkTuition.toString(), score: scoreTuition.toString(),
  };
}
export function contractVersion(task: TaskKey) {
  return task === "intake" ? INTAKE_VALIDATOR_VERSION : task === "english" ? ENGLISH_VALIDATOR_VERSION : "cf247-provider-current-tuition-validation-v2";
}
// Profile-bound binding descriptor for intake and English (tuition uses the live interpreter's runtime binding hash).
export function factBindingDescriptor(task: TaskKey, profile: any) {
  return JSON.stringify({
    routing: ROUTING_VERSION, task: TASKS[task], contract: contractComponentsFor(task, profile), model: profile.model_identifier,
    max_output_tokens: Number(profile.max_output_tokens), timeout_ms: Number(profile.timeout_ms), prompt_profile_version: profile.prompt_profile_version,
  });
}

// ---------- Decision 229: intake check v1.3.0, a separate contract chosen per profile ----------
// A profile is on v1.3.0 only when its prompt_profile_version says so; every other profile (all qualified profiles
// today) keeps v1.2.0 and the same binding descriptor, byte for byte.
export function isIntakeV13(task: TaskKey, profile: any) {
  return task === "intake" && String(profile?.prompt_profile_version || "") === INTAKE_VALIDATOR_VERSION_V13;
}
export function intakeRequestBodyV13(model: string, text: string, maxTokens: number) {
  return {
    model, temperature: 0, max_tokens: maxTokens,
    provider: { require_parameters: true }, usage: { include: true },
    response_format: { type: "json_schema", json_schema: { name: "cf247_intake_months", strict: true, schema: INTAKE_RESPONSE_SCHEMA } },
    messages: [
      { role: "system", content: INTAKE_SYSTEM_PROMPT_V13 },
      { role: "user", content: `Course page text:\n${focusText(text, INTAKE_MAX_CHARS)}` },
    ],
  };
}
export function checkIntakeV13(answer: any, text: string, blockers: { code: string; quote: string }[]): Checked {
  const v = applyIntakeSafetyRule(validateIntakeAnswerV13(answer, text), blockers);
  return { valid: v.valid, errors: v.errors, status: v.status, admitted: v.valid && v.status === "months" ? { months: v.months } : null, detail: { quotes: v.quotes } };
}
export function contractComponentsFor(task: TaskKey, profile: any): Record<string, unknown> {
  if (!isIntakeV13(task, profile)) return contractComponents(task);
  return {
    version: INTAKE_VALIDATOR_VERSION_V13, prompt: INTAKE_SYSTEM_PROMPT_V13, schema: INTAKE_RESPONSE_SCHEMA, max_quotes: MAX_QUOTES, max_chars: INTAKE_MAX_CHARS,
    safety_rules: INTAKE_SAFETY_RULES.map((r) => ({ code: r.code, re: String(r.re) })), validate: validateIntakeAnswerV13.toString(),
    quote_rule: quoteInTextV13.toString(), months_rule: monthsWrittenV13.toString(), rolling: String(ROLLING_RE),
    safety_blockers: intakeSafetyBlockers.toString(), safety_apply: applyIntakeSafetyRule.toString(), focus: focusText.toString(),
    request_body: intakeRequestBodyV13.toString(), check: checkIntakeV13.toString(), score: scoreIntake.toString(),
  };
}
export function contractVersionFor(task: TaskKey, profile: any) {
  return isIntakeV13(task, profile) ? INTAKE_VALIDATOR_VERSION_V13 : contractVersion(task);
}
// the request body and checks a profile runs (v1.3.0 profiles: the v1.3.0 contract; all others unchanged)
export function intakeBodyFor(profile: any, model: string, text: string, maxTokens: number) {
  return isIntakeV13("intake", profile) ? intakeRequestBodyV13(model, text, maxTokens) : intakeRequestBody(model, text, maxTokens);
}
export function intakeCheckFor(profile: any, answer: any, text: string, blockers: { code: string; quote: string }[]) {
  return isIntakeV13("intake", profile) ? checkIntakeV13(answer, text, blockers) : checkIntake(answer, text, blockers);
}
