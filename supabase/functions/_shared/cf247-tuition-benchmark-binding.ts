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
// - benchmark_prompt_template / interpreter_prompt_template: the *exact
//   literal source text* of each caller's real prompt-building statement
//   (from its `const system =` / `const prompt = [` declaration through the
//   balanced end of the provider request-body call that consumes it),
//   extracted from the live .ts source — not a mirrored constant. Because the
//   extraction spans both the prompt/system construction AND the request
//   body in one literal, any change to the real benchmark `system` text or
//   the real interpreter `prompt` text changes this component by
//   construction; a source-substring assertion against unrelated prompt text
//   can never pass while the actual prompt text differs.
// - candidate_context_instruction: retained for backward-compatible shape,
//   populated from `shared_validator_source` (see below) rather than a
//   separate mirrored string literal, so the shared candidate-context
//   instruction is bound to the validator's real implementation, not a
//   disconnected copy of it.
// - benchmark_request_body_source / interpreter_request_body_source: the
//   *exact literal source text* of each caller's real `JSON.stringify({...})`
//   provider request body (extracted from the live .ts source, not a mirrored
//   constant). This is what actually carries each caller's real temperature,
//   seed, reasoning, max_tokens/profile fallback and response_format mode, so
//   a genuine divergence between the benchmark's and the interpreter's actual
//   request (e.g. json_schema vs json_object, or a changed token fallback)
//   changes the fingerprint by construction, because it changes this text.
// - shared_validator_source: the exact source text of the shared validator
//   module (implementation-bound, not merely its exported string identifiers).
//   This is also the sole source of the candidate-context instruction text
//   (tuitionValidationPromptContext's literal instruction string lives here),
//   so a change to that instruction is covered without a mirrored constant.
// - response_schema: the shared strict structured-output JSON schema object.
// - profile_response_schema: the stored profile schema; profile drift must
//   invalidate qualification even if the worker still uses the shared schema.
// - model_identifier / prompt_profile_version: identity of the model/prompt
//   version in effect.
// - deterministic_validators: the complete stored profile validator settings,
//   including allowed basis/currency and review threshold — never secrets.
// - inference_settings: the profile-derived, caller-shared determinism inputs
//   (max_input_tokens/max_output_tokens/timeout_ms/retry_ceiling) that are not literal in the
//   request-body source text. Per-caller settings that DO appear literally in
//   the request body (temperature/seed/reasoning/max_tokens fallback/
//   response_format) are intentionally NOT duplicated here as hardcoded
//   constants — they are covered, per caller, by *_request_body_source above,
//   so this module can never silently diverge from the real runtime request.
//
// Explicitly excluded: secret values (API keys), Evidence bytes, per-case
// candidate_value/candidate_context payloads, and volatile metrics (latency,
// cost, token counts, timestamps).

// Anchors used to locate each caller's real prompt-building statement — from
// the declaration of its effective system/prompt variable through to the
// balanced end of the provider request-body call that actually consumes it —
// within its own live source text. Anchoring here (rather than only at the
// request-body literal) means the extracted text includes the benchmark's
// real `system` template text and the interpreter's real `prompt` array,
// which are built OUTSIDE JSON.stringify(...) and therefore would otherwise
// be invisible to a binding anchored solely on the request-body object. Must
// stay in sync with the actual prompt-construction call sites; if either
// caller's source is refactored such that the anchor no longer precedes a
// balanced request-body call, extraction throws (fails closed) rather than
// silently binding to a stale/absent prompt.
export const CF247_BENCHMARK_PROMPT_BUILD_ANCHOR = "const system=";
export const CF247_INTERPRETER_PROMPT_BUILD_ANCHOR = "const prompt = [";

export type InferenceSettings = {
  max_input_tokens: number;
  max_output_tokens: number;
  timeout_ms: number;
  retry_ceiling: number;
};

export type BindingComponents = {
  benchmark_prompt_template: string;
  interpreter_prompt_template: string;
  candidate_context_instruction: string;
  benchmark_request_body_source: string;
  interpreter_request_body_source: string;
  shared_validator_source: string;
  response_schema: unknown;
  profile_response_schema: unknown;
  model_identifier: string;
  prompt_profile_version: string;
  prompt_profile_system: string;
  deterministic_validators: Record<string, unknown>;
  inference_settings: InferenceSettings;
};

// Every key here is required for a well-formed binding descriptor. Missing or
// blank required components fail closed (buildTuitionBenchmarkBindingDescriptor
// throws rather than producing a partial/omitted-component fingerprint).
export const CF247_BINDING_REQUIRED_COMPONENT_KEYS: readonly (keyof BindingComponents)[] = [
  "benchmark_prompt_template",
  "interpreter_prompt_template",
  "candidate_context_instruction",
  "benchmark_request_body_source",
  "interpreter_request_body_source",
  "shared_validator_source",
  "response_schema",
  "profile_response_schema",
  "model_identifier",
  "prompt_profile_version",
  "prompt_profile_system",
  "deterministic_validators",
  "inference_settings",
];

// Extracts the exact literal source text of a `JSON.stringify({ ... })`
// provider request-body call that immediately follows `anchor` in `source`,
// by scanning forward from the first `{` after the anchor and returning the
// substring up to its balanced matching `}` (brace-depth counting, respecting
// both `'...'`/`"..."` quoted strings and `` `...` `` template literals so a
// stray `{`/`}` inside a string or interpolation never breaks the balance).
// This ties the binding to the caller's REAL runtime request body — the exact
// source text that determines temperature/seed/reasoning/max_tokens fallback/
// response_format — not to a mirrored/hardcoded description of it. Fails
// closed (throws) if the anchor or a balanced body cannot be found, so a
// caller whose request shape changed enough to break extraction cannot
// silently produce a stale/incomplete binding.
export function extractJsonRequestBodySource(source: string, anchor: string): string {
  const anchorIndex = source.indexOf(anchor);
  if (anchorIndex < 0) {
    throw new Error(`CF-247 tuition benchmark binding: request-body anchor not found in source: ${anchor}`);
  }
  const openIndex = source.indexOf("{", anchorIndex + anchor.length);
  if (openIndex < 0) {
    throw new Error(`CF-247 tuition benchmark binding: no request-body object found after anchor: ${anchor}`);
  }
  let depth = 0;
  let quote: '"' | "'" | "`" | null = null;
  for (let i = openIndex; i < source.length; i++) {
    const ch = source[i];
    const prev = source[i - 1];
    if (quote) {
      if (ch === quote && prev !== "\\") quote = null;
      continue;
    }
    if (ch === '"' || ch === "'" || ch === "`") { quote = ch; continue; }
    if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) return source.slice(openIndex, i + 1);
    }
  }
  throw new Error(`CF-247 tuition benchmark binding: unbalanced request-body object after anchor: ${anchor}`);
}

// Extracts the exact literal source text spanning `anchor` (a caller's real
// prompt/system-building declaration, e.g. `const system=`) through the
// balanced end of the first `JSON.stringify({ ... })` request-body call that
// follows it in `source`. This proves the binding actually covers the real
// prompt/system text — which is constructed OUTSIDE JSON.stringify(...) in
// both the benchmark and the interpreter — not merely the request body that
// consumes it. Uses the same brace-depth counting (respecting quoted strings
// and template literals) as extractJsonRequestBodySource. Fails closed
// (throws) if the anchor, the `JSON.stringify(` call after it, or a balanced
// body cannot be found.
export function extractPromptBuildSource(source: string, anchor: string): string {
  const anchorIndex = source.indexOf(anchor);
  if (anchorIndex < 0) {
    throw new Error(`CF-247 tuition benchmark binding: prompt-build anchor not found in source: ${anchor}`);
  }
  const stringifyMarker = "JSON.stringify(";
  const stringifyIndex = source.indexOf(stringifyMarker, anchorIndex + anchor.length);
  if (stringifyIndex < 0) {
    throw new Error(`CF-247 tuition benchmark binding: no JSON.stringify request-body call found after prompt-build anchor: ${anchor}`);
  }
  const openIndex = source.indexOf("{", stringifyIndex + stringifyMarker.length);
  if (openIndex < 0) {
    throw new Error(`CF-247 tuition benchmark binding: no request-body object found after prompt-build anchor: ${anchor}`);
  }
  let depth = 0;
  let quote: '"' | "'" | "`" | null = null;
  for (let i = openIndex; i < source.length; i++) {
    const ch = source[i];
    const prev = source[i - 1];
    if (quote) {
      if (ch === quote && prev !== "\\") quote = null;
      continue;
    }
    if (ch === '"' || ch === "'" || ch === "`") { quote = ch; continue; }
    if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) return source.slice(anchorIndex, i + 1);
    }
  }
  throw new Error(`CF-247 tuition benchmark binding: unbalanced request-body object after prompt-build anchor: ${anchor}`);
}

// Extracts the exact literal `instruction:` string from the shared
// validator's real `tuitionValidationPromptContext` source (the fixed
// candidate-context instruction text sent to both the benchmark and the
// interpreter), so `candidate_context_instruction` is derived from the
// validator's actual current implementation rather than a disconnected
// mirrored copy of it. Fails closed (throws) if the anchor or a
// terminating unescaped quote cannot be found.
const CANDIDATE_CONTEXT_INSTRUCTION_ANCHOR = "instruction:";
export function extractCandidateContextInstructionSource(validatorSource: string): string {
  const anchorIndex = validatorSource.indexOf(CANDIDATE_CONTEXT_INSTRUCTION_ANCHOR);
  if (anchorIndex < 0) {
    throw new Error("CF-247 tuition benchmark binding: candidate-context instruction anchor not found in shared validator source");
  }
  const searchFrom = anchorIndex + CANDIDATE_CONTEXT_INSTRUCTION_ANCHOR.length;
  let quoteIndex = -1;
  let quoteChar = "";
  for (let j = searchFrom; j < validatorSource.length; j++) {
    const ch = validatorSource[j];
    if (ch === '"' || ch === "'") { quoteIndex = j; quoteChar = ch; break; }
  }
  if (quoteIndex < 0) {
    throw new Error("CF-247 tuition benchmark binding: no candidate-context instruction string literal found after anchor");
  }
  let i = quoteIndex + 1;
  let value = "";
  for (; i < validatorSource.length; i++) {
    const ch = validatorSource[i];
    if (ch === "\\") { value += ch + (validatorSource[i + 1] ?? ""); i++; continue; }
    if (ch === quoteChar) return value;
    value += ch;
  }
  throw new Error("CF-247 tuition benchmark binding: unterminated candidate-context instruction string literal");
}

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

// Anchors used to locate each caller's real provider request-body literal
// within its own live source text. These must stay in sync with the actual
// `fetch(...)` call sites in layer3-cf245-tuition-benchmark/index.ts and
// layer3-work-interpret/index.ts; if either caller's source is refactored
// such that the anchor no longer immediately precedes the request-body
// object, extractJsonRequestBodySource throws (fails closed) rather than
// silently binding to a stale/absent request body.
export const CF247_BENCHMARK_REQUEST_BODY_ANCHOR = "body:JSON.stringify(";
export const CF247_INTERPRETER_REQUEST_BODY_ANCHOR = "body: JSON.stringify(";

export type TuitionProfileLike = {
  model_identifier?: unknown;
  prompt_profile_version?: unknown;
  prompt_system?: unknown;
  structured_output_schema?: unknown;
  max_input_tokens?: unknown;
  max_output_tokens?: unknown;
  timeout_ms?: unknown;
  retry_ceiling?: unknown;
  deterministic_validators?: Record<string, unknown> | null;
};

export type ResolvedTuitionProfileBindingInputs = {
  model_identifier: string;
  prompt_profile_version: string;
  prompt_profile_system: string;
  profile_response_schema: unknown;
  deterministic_validators: Record<string, unknown>;
  inference_settings: InferenceSettings;
};

// Validates and resolves the profile-derived binding inputs shared by both
// the full source-text descriptor (buildTuitionBenchmarkBindingComponents,
// CI/test-only — see below) and the runtime source-manifest descriptor
// (tuitionBenchmarkRuntimeBindingHash, safe to call from the deployed Deno
// worker). Kept as a single implementation so the two descriptors can never
// silently diverge in which profile fields they require or how they resolve
// the validators/schema key aliases. Fails closed: throws rather than
// substituting a default for any missing/invalid/ambiguous field.
export function resolveTuitionProfileBindingInputs(profile: TuitionProfileLike): ResolvedTuitionProfileBindingInputs {
  // The live profile RPC may expose deterministic_validators/structured_output_schema
  // or the validators/schema aliases. Reject profiles carrying both so alias
  // resolution can never mask a change made under only one key. Never substitute
  // a default: that would make a changed/malformed profile look last-qualified.
  const p = profile as any;
  if (p.deterministic_validators != null && p.validators != null) {
    throw new Error("CF-247 tuition benchmark binding: ambiguous validators (both keys present)");
  }
  if (p.structured_output_schema != null && p.schema != null) {
    throw new Error("CF-247 tuition benchmark binding: ambiguous schema (both keys present)");
  }
  const validators = p.deterministic_validators ?? p.validators;
  const schema = p.structured_output_schema ?? p.schema;
  if (!validators || !Object.keys(validators).length ||
      !schema || typeof schema !== "object") {
    throw new Error("CF-247 tuition benchmark binding: profile validator/schema settings missing");
  }
  for (const key of ["max_input_tokens", "max_output_tokens", "timeout_ms", "retry_ceiling"] as const) {
    if (profile[key] == null || !Number.isFinite(Number(profile[key]))) {
      throw new Error(`CF-247 tuition benchmark binding: profile ${key} missing or invalid`);
    }
  }
  return {
    model_identifier: String(profile?.model_identifier ?? ""),
    prompt_profile_version: String(profile?.prompt_profile_version ?? ""),
    prompt_profile_system: String(profile?.prompt_system ?? ""),
    profile_response_schema: schema,
    deterministic_validators: validators,
    inference_settings: {
      max_input_tokens: Number(profile.max_input_tokens),
      max_output_tokens: Number(profile.max_output_tokens),
      timeout_ms: Number(profile.timeout_ms),
      retry_ceiling: Number(profile.retry_ceiling),
    },
  };
}

// Assembles the BindingComponents shared by the benchmark and the interpreter
// from a model/prompt profile record (the same `profile` shape both the
// benchmark and the interpreter already receive), the shared validator
// module's source text, and each caller's own live edge-function source text.
// Callers are responsible for supplying `validatorSource`, `benchmarkSource`
// and `interpreterSource` (read from the real .ts files) so this module has
// no filesystem/runtime dependency of its own, while still binding to the
// actual runtime request bodies rather than a mirrored description of them.
// CI/TEST USE ONLY: raw-source-text extraction is not available inside the
// deployed Deno worker (there is no readable copy of these .ts files at edge
// runtime). The worker computes its own binding hash via
// tuitionBenchmarkRuntimeBindingHash below instead.
export function buildTuitionBenchmarkBindingComponents(
  profile: TuitionProfileLike,
  responseSchema: unknown,
  validatorSource: string,
  benchmarkSource: string,
  interpreterSource: string,
): BindingComponents {
  const resolved = resolveTuitionProfileBindingInputs(profile);
  return {
    benchmark_prompt_template: extractPromptBuildSource(benchmarkSource, CF247_BENCHMARK_PROMPT_BUILD_ANCHOR),
    interpreter_prompt_template: extractPromptBuildSource(interpreterSource, CF247_INTERPRETER_PROMPT_BUILD_ANCHOR),
    candidate_context_instruction: extractCandidateContextInstructionSource(validatorSource),
    benchmark_request_body_source: extractJsonRequestBodySource(benchmarkSource, CF247_BENCHMARK_REQUEST_BODY_ANCHOR),
    interpreter_request_body_source: extractJsonRequestBodySource(interpreterSource, CF247_INTERPRETER_REQUEST_BODY_ANCHOR),
    shared_validator_source: validatorSource,
    response_schema: responseSchema,
    profile_response_schema: resolved.profile_response_schema,
    model_identifier: resolved.model_identifier,
    prompt_profile_version: resolved.prompt_profile_version,
    prompt_profile_system: resolved.prompt_profile_system,
    deterministic_validators: resolved.deterministic_validators,
    inference_settings: resolved.inference_settings,
  };
}

// Runtime-safe binding hash: the SHA-256 hex digest of a canonical descriptor
// combining the checked-in, CI-verified source manifest (proof that the
// checked-in component hashes match the actual deployed source, established
// by the mandatory binding contract test recomputing them from real source on
// every PR) with the live profile's binding-relevant settings. Deliberately
// does NOT re-derive from raw .ts source text at runtime — see the CI/TEST
// USE ONLY note above. Changing any manifest component (a real source change,
// caught by the binding contract test if the manifest isn't regenerated to
// match) or any resolved profile input changes this hash. Fails closed via
// resolveTuitionProfileBindingInputs. Format matches the recorder migration's
// binding_hash CHECK constraint (^[0-9a-f]{64}$).
export async function tuitionBenchmarkRuntimeBindingHash(
  manifest: Record<string, string>,
  profile: TuitionProfileLike,
): Promise<string> {
  const resolved = resolveTuitionProfileBindingInputs(profile);
  const descriptor = canonicalJsonStringify({
    binding_contract_id: CF247_TUITION_BENCHMARK_BINDING_CONTRACT_ID,
    source_manifest: manifest,
    model_identifier: resolved.model_identifier,
    prompt_profile_version: resolved.prompt_profile_version,
    prompt_profile_system: resolved.prompt_profile_system,
    profile_response_schema: resolved.profile_response_schema,
    deterministic_validators: resolved.deterministic_validators,
    inference_settings: resolved.inference_settings,
  });
  return sha256Hex(descriptor);
}
