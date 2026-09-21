// CF-CHG-20260921-247-3B1
// CF-247 Slice 3B1: deterministic candidate-bound tuition benchmark BINDING
// descriptor/fingerprint, shared by the benchmark and the interpreter.
//
// Scope (3B1 only): this module computes a canonical, deterministic descriptor
// covering the components that must match between the benchmark run and the
// interpreter run for a benchmark PASS to be a meaningful basis for admission.
// It does NOT persist a PASS, does NOT alter any eligibility predicate, RPC or
// migration, and does NOT change candidate validation, benchmark controls, or
// any Evidence/identity/security boundary. Persistence/eligibility wiring is
// explicitly deferred to 3B2.
//
// Included components (all static/structural, never per-case or secret):
// - benchmark_prompt_template / interpreter_prompt_template: the effective,
//   non-case-specific instructional templates (candidate-context instructions
//   included via a fixed placeholder, never interpolated per-case values).
// - shared_validator_source: the exact source text of the shared validator
//   module (implementation-bound, not merely its exported string identifiers).
// - response_schema: the shared strict structured-output JSON schema object.
// - model_identifier / prompt_profile_version: identity of the model/prompt
//   version in effect.
// - deterministic_validators: the deterministic validator thresholds in effect
//   (e.g. confidence bounds, quote limits) — never secret values.
// - inference_settings: temperature, seed/reasoning, input/output limits,
//   timeout/retry — the settings that affect determinism/reproducibility.
//
// Explicitly excluded: secret values (API keys), Evidence bytes, per-case
// candidate_value/candidate_context payloads, and volatile metrics (latency,
// cost, token counts, timestamps).

// The benchmark's effective system-prompt template, fixed and non-case-specific.
// Mirrors supabase/functions/layer3-cf245-tuition-benchmark/index.ts `system`
// (candidate-bound header + profile.prompt_system), with profile.prompt_system
// represented as a fixed placeholder rather than its live value, since the
// live value is carried separately via BindingComponents.prompt_profile_system.
export const CF247_BENCHMARK_PROMPT_TEMPLATE =
  "CF-247 candidate-bound validation. This is validation of one immutable deterministic Layer 2 candidate, not extraction. Return JSON only. A positive answer MUST return the supplied candidate exactly unchanged; a negative/ambiguous answer MUST return candidate_value null. Never invent, annualise, convert currency, change year, strengthen basis, or select a different amount.\n{{profile.prompt_system}}";

// The benchmark's effective user-turn instructional template (case label and
// per-case candidate/evidence content replaced with fixed placeholders).
export const CF247_BENCHMARK_USER_TEMPLATE =
  "Benchmark case: {{label}}\nValidate ONLY the exact Layer 2 candidate against the retained first-party Evidence excerpt. If the Evidence explicitly supports the same amount, currency, international audience, basis and stated fee year (when non-null), return that candidate exactly unchanged with confidence >= 0.90 and short verbatim Evidence quotes. If any required attribute is unsupported, conflicting or ambiguous, return candidate_value null. Do not extract or substitute another value. indicative_annual is an allowed governed basis and must remain indicative_annual.\nLayer 2 candidate:\n{{candidateJson}}\nEvidence excerpt:\n{{evidenceExcerpt}}";

// The interpreter's effective prompt template (mirrors the `prompt` array
// joined in supabase/functions/layer3-work-interpret/index.ts, with per-case
// Evidence source/content and the candidate-context instructions carried via
// tuitionValidationPromptContext represented as a fixed placeholder — the
// candidate-bound *instructions* are covered by the shared validator source
// below, not by interpolating a specific candidate_context here).
export const CF247_INTERPRETER_PROMPT_TEMPLATE = [
  "Task class: provider_current_tuition_validation",
  "Governed Evidence source: {{evidence.source_url}}",
  "{{tuitionValidationPromptContext(candidateContext)}}",
  "Return exactly one JSON object with keys candidate_value, confidence, rationale, evidence_quotes. candidate_value must be null or one supplied tuition candidate with amount, currency_code, basis, fee_year and audience. Evidence must explicitly support any basis resolution; otherwise return null.",
  "Evidence:\n{{evidenceText}}",
].join("\n\n");

// The fixed instructional wrapper produced by the shared prompt-context
// builder, independent of any specific candidate_context value. This captures
// the *instruction* text that governs candidate-bound behaviour identically
// for the benchmark and the interpreter (both call the same shared function).
export const CF247_CANDIDATE_CONTEXT_INSTRUCTION =
  "Validate only the supplied provider_current_tuition target against Evidence — it is the sole positive candidate. The listed competing_fee_candidates are other fees mentioned in context for awareness only; they must never be returned or substituted for the target, even if Evidence supports one of them instead. Keep amount, currency, fee_year and audience unchanged from the target. If the target's basis is annual_or_indicative_requires_validation, Evidence may resolve only to annual or indicative_annual; otherwise basis must remain unchanged. Both the target and any returned candidate must have audience explicitly \"international\"; missing, blank or other audience is invalid. A non-null result additionally requires identity_match to be true. Return null when Evidence does not explicitly support the target, when identity_match is not true, or when no positive target can be admitted — null is always a safe abstention. Never invent or annualise an amount, convert currency, infer a year, change audience, or select a different fee.";

export type InferenceSettings = {
  temperature: number;
  seed?: number | null;
  reasoning?: { effort: string; exclude: boolean } | null;
  max_input_tokens: number;
  max_output_tokens: number;
  timeout_ms: number;
  retry_ceiling: number;
};

export type DeterministicValidatorSettings = {
  confidence_min: number;
  confidence_max: number;
  max_quotes: number;
  max_quote_chars: number;
};

export type BindingComponents = {
  benchmark_prompt_template: string;
  interpreter_prompt_template: string;
  candidate_context_instruction: string;
  shared_validator_source: string;
  response_schema: unknown;
  model_identifier: string;
  prompt_profile_version: string;
  prompt_profile_system: string;
  deterministic_validators: DeterministicValidatorSettings;
  inference_settings: InferenceSettings;
};

// Every key here is required for a well-formed binding descriptor. Missing or
// blank required components fail closed (buildTuitionBenchmarkBindingDescriptor
// throws rather than producing a partial/omitted-component fingerprint).
export const CF247_BINDING_REQUIRED_COMPONENT_KEYS: readonly (keyof BindingComponents)[] = [
  "benchmark_prompt_template",
  "interpreter_prompt_template",
  "candidate_context_instruction",
  "shared_validator_source",
  "response_schema",
  "model_identifier",
  "prompt_profile_version",
  "prompt_profile_system",
  "deterministic_validators",
  "inference_settings",
];

export const CF247_TUITION_BENCHMARK_BINDING_CONTRACT_ID = "cf247-tuition-benchmark-binding-v1";

function isBlank(value: unknown): boolean {
  if (value == null) return true;
  if (typeof value === "string") return value.trim().length === 0;
  if (typeof value === "object" && !Array.isArray(value)) return Object.keys(value as Record<string, unknown>).length === 0;
  return false;
}

// Deterministic canonical JSON: object keys are sorted recursively so that
// key insertion order never affects the serialized form or the fingerprint.
// Arrays preserve order (order is semantically significant, e.g. quotes/ids).
export function canonicalJsonStringify(value: unknown): string {
  const canonicalise = (input: unknown): unknown => {
    if (Array.isArray(input)) return input.map(canonicalise);
    if (input && typeof input === "object") {
      const sortedKeys = Object.keys(input as Record<string, unknown>).sort();
      const out: Record<string, unknown> = {};
      for (const key of sortedKeys) out[key] = canonicalise((input as Record<string, unknown>)[key]);
      return out;
    }
    return input;
  };
  return JSON.stringify(canonicalise(value));
}

// Validates that every required binding component is present and non-blank.
// Fails closed: throws (does not silently substitute a default or omit the
// missing component from the fingerprint) when any required component is
// missing, undefined, null, or blank.
export function assertBindingComponentsComplete(components: Partial<BindingComponents>): BindingComponents {
  const missing: string[] = [];
  for (const key of CF247_BINDING_REQUIRED_COMPONENT_KEYS) {
    if (!(key in components) || isBlank((components as Record<string, unknown>)[key])) missing.push(key);
  }
  if (missing.length) {
    throw new Error(`CF-247 tuition benchmark binding descriptor missing required component(s): ${missing.join(", ")}`);
  }
  return components as BindingComponents;
}

// Canonical serialization of the binding descriptor: contract id, explicit
// component list (sorted keys via canonicalJsonStringify), independent of
// object-key insertion order at any nesting level.
export function canonicalBindingDescriptor(components: BindingComponents): string {
  const complete = assertBindingComponentsComplete(components);
  return canonicalJsonStringify({
    binding_contract_id: CF247_TUITION_BENCHMARK_BINDING_CONTRACT_ID,
    components: complete,
  });
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Deterministic candidate-bound tuition benchmark binding fingerprint: the
// SHA-256 hex digest of the canonical descriptor. Any change to any required
// component changes the fingerprint; object-key order never does; a missing
// required component fails closed (throws, via assertBindingComponentsComplete)
// rather than producing a fingerprint over an incomplete descriptor.
export async function tuitionBenchmarkBindingFingerprint(components: BindingComponents): Promise<string> {
  return sha256Hex(canonicalBindingDescriptor(components));
}

// Assembles the BindingComponents shared by the benchmark and the interpreter
// from a model/prompt profile record (the same `profile` shape both the
// benchmark and the interpreter already receive), plus the shared validator
// module's source text. Callers are responsible for supplying `validatorSource`
// (the shared cf247-tuition-validation.ts source text) so this module has no
// filesystem/runtime dependency of its own.
export function buildTuitionBenchmarkBindingComponents(
  profile: {
    model_identifier?: unknown;
    prompt_profile_version?: unknown;
    prompt_system?: unknown;
    max_input_tokens?: unknown;
    max_output_tokens?: unknown;
    timeout_ms?: unknown;
    retry_ceiling?: unknown;
    validators?: { confidence_min?: unknown; confidence_max?: unknown; max_quotes?: unknown; max_quote_chars?: unknown } | null;
  },
  responseSchema: unknown,
  validatorSource: string,
): BindingComponents {
  return {
    benchmark_prompt_template: CF247_BENCHMARK_PROMPT_TEMPLATE,
    interpreter_prompt_template: CF247_INTERPRETER_PROMPT_TEMPLATE,
    candidate_context_instruction: CF247_CANDIDATE_CONTEXT_INSTRUCTION,
    shared_validator_source: validatorSource,
    response_schema: responseSchema,
    model_identifier: String(profile?.model_identifier ?? ""),
    prompt_profile_version: String(profile?.prompt_profile_version ?? ""),
    prompt_profile_system: String(profile?.prompt_system ?? ""),
    deterministic_validators: {
      confidence_min: Number(profile?.validators?.confidence_min ?? 0),
      confidence_max: Number(profile?.validators?.confidence_max ?? 1),
      max_quotes: Number(profile?.validators?.max_quotes ?? 4),
      max_quote_chars: Number(profile?.validators?.max_quote_chars ?? 600),
    },
    inference_settings: {
      temperature: 0,
      seed: 0,
      reasoning: { effort: "none", exclude: true },
      max_input_tokens: Number(profile?.max_input_tokens ?? 12000),
      max_output_tokens: Number(profile?.max_output_tokens ?? 900),
      timeout_ms: Number(profile?.timeout_ms ?? 30000),
      retry_ceiling: Number(profile?.retry_ceiling ?? 0),
    },
  };
}
