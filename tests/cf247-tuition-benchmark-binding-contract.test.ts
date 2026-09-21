import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import {
  CF247_BINDING_REQUIRED_COMPONENT_KEYS,
  CF247_TUITION_BENCHMARK_BINDING_CONTRACT_ID,
  assertBindingComponentsComplete,
  buildTuitionBenchmarkBindingComponents,
  canonicalBindingDescriptor,
  canonicalJsonStringify,
  tuitionBenchmarkBindingFingerprint,
} from "../supabase/functions/_shared/cf247-tuition-benchmark-binding.ts";
import type { BindingComponents } from "../supabase/functions/_shared/cf247-tuition-benchmark-binding.ts";
import { CF247_TUITION_RESPONSE_SCHEMA } from "../supabase/functions/_shared/cf247-tuition-validation.ts";

const validatorSource = readFileSync(new URL("../supabase/functions/_shared/cf247-tuition-validation.ts", import.meta.url), "utf8");
const benchmarkSource = readFileSync(new URL("../supabase/functions/layer3-cf245-tuition-benchmark/index.ts", import.meta.url), "utf8");
const interpreterSource = readFileSync(new URL("../supabase/functions/layer3-work-interpret/index.ts", import.meta.url), "utf8");

const profile = {
  model_identifier: "openrouter/example-model-v1",
  prompt_profile_version: "cf247-tuition-prompt-v3",
  prompt_system: "Fixed governed system prompt text.",
  max_input_tokens: 12000,
  max_output_tokens: 900,
  timeout_ms: 30000,
  retry_ceiling: 1,
  validators: { confidence_min: 0, confidence_max: 1, max_quotes: 4, max_quote_chars: 600 },
};

function baseComponents(): BindingComponents {
  return buildTuitionBenchmarkBindingComponents(profile, CF247_TUITION_RESPONSE_SCHEMA, validatorSource);
}

// --- 1. Descriptor covers effective prompt templates, shared validator
// implementation, response schema, model identifier, prompt_profile_version,
// deterministic validators and inference settings — not merely static IDs. ---

assert.equal(CF247_TUITION_BENCHMARK_BINDING_CONTRACT_ID, "cf247-tuition-benchmark-binding-v1");
assert.deepEqual(
  [...CF247_BINDING_REQUIRED_COMPONENT_KEYS].sort(),
  [
    "benchmark_prompt_template",
    "candidate_context_instruction",
    "deterministic_validators",
    "inference_settings",
    "interpreter_prompt_template",
    "model_identifier",
    "prompt_profile_system",
    "prompt_profile_version",
    "response_schema",
    "shared_validator_source",
  ].sort(),
  "binding descriptor must cover effective prompt templates, shared validator implementation, response schema, model identifier, prompt_profile_version, deterministic validators and inference settings",
);

// The descriptor is bound to the *exact implementation* of the shared
// validator (its full source text), not merely a static contract-id literal.
const components = baseComponents();
assert.ok(components.shared_validator_source.length > 0, "shared_validator_source must be the validator's actual source text");
assert.ok(
  components.shared_validator_source.includes("export function validateProviderCurrentTuitionCandidate"),
  "shared_validator_source must contain the real validator implementation, not just an identifier",
);

// The benchmark's and interpreter's actual effective prompt templates are
// present verbatim (as literal text) in their respective source files, so the
// descriptor tracks their real, current instructional content.
assert.ok(benchmarkSource.includes("CF-247 candidate-bound validation. This is validation of one immutable deterministic Layer 2 candidate"), "benchmark source must still contain the templated system-prompt header this descriptor is bound to");
assert.ok(interpreterSource.includes("Task class: provider_current_tuition_validation"), "interpreter source must still contain the templated prompt lead-in this descriptor is bound to");

// --- 2. Canonical serialization / hash: deterministic given the same inputs. ---

const fingerprintA = await tuitionBenchmarkBindingFingerprint(baseComponents());
const fingerprintB = await tuitionBenchmarkBindingFingerprint(baseComponents());
assert.equal(fingerprintA, fingerprintB, "the same components must always produce the same fingerprint");
assert.match(fingerprintA, /^[0-9a-f]{64}$/, "fingerprint must be a SHA-256 hex digest");

// --- 3. Each covered component change invalidates the binding. ---

async function fingerprintWithChange(mutate: (c: BindingComponents) => void): Promise<string> {
  const mutated = baseComponents();
  mutate(mutated);
  return tuitionBenchmarkBindingFingerprint(mutated);
}

const mutations: Array<[string, (c: BindingComponents) => void]> = [
  ["benchmark_prompt_template", (c) => { c.benchmark_prompt_template += " changed"; }],
  ["interpreter_prompt_template", (c) => { c.interpreter_prompt_template += " changed"; }],
  ["candidate_context_instruction", (c) => { c.candidate_context_instruction += " changed"; }],
  ["shared_validator_source", (c) => { c.shared_validator_source += "\n// changed"; }],
  ["response_schema", (c) => { c.response_schema = { ...(c.response_schema as Record<string, unknown>), extra: true }; }],
  ["model_identifier", (c) => { c.model_identifier = "a-different-model"; }],
  ["prompt_profile_version", (c) => { c.prompt_profile_version = "a-different-version"; }],
  ["prompt_profile_system", (c) => { c.prompt_profile_system += " changed"; }],
  ["deterministic_validators", (c) => { c.deterministic_validators = { ...c.deterministic_validators, confidence_min: 0.5 }; }],
  ["inference_settings", (c) => { c.inference_settings = { ...c.inference_settings, temperature: 0.2 }; }],
];

for (const [label, mutate] of mutations) {
  const mutatedFingerprint = await fingerprintWithChange(mutate);
  assert.notEqual(mutatedFingerprint, fingerprintA, `changing ${label} must invalidate the binding fingerprint`);
}

// --- 4. Object-key order does not affect the fingerprint. ---

const reorderedComponents = baseComponents();
const reorderedKeysDescriptor: Record<string, unknown> = {};
for (const key of [...Object.keys(reorderedComponents)].reverse()) {
  (reorderedKeysDescriptor as Record<string, unknown>)[key] = (reorderedComponents as unknown as Record<string, unknown>)[key];
}
const fingerprintReorderedTopLevel = await tuitionBenchmarkBindingFingerprint(reorderedKeysDescriptor as BindingComponents);
assert.equal(fingerprintReorderedTopLevel, fingerprintA, "top-level component key order must not affect the fingerprint");

const nestedReordered = baseComponents();
nestedReordered.inference_settings = {
  retry_ceiling: nestedReordered.inference_settings.retry_ceiling,
  timeout_ms: nestedReordered.inference_settings.timeout_ms,
  max_output_tokens: nestedReordered.inference_settings.max_output_tokens,
  max_input_tokens: nestedReordered.inference_settings.max_input_tokens,
  reasoning: nestedReordered.inference_settings.reasoning,
  seed: nestedReordered.inference_settings.seed,
  temperature: nestedReordered.inference_settings.temperature,
};
const fingerprintNestedReordered = await tuitionBenchmarkBindingFingerprint(nestedReordered);
assert.equal(fingerprintNestedReordered, fingerprintA, "nested object key order must not affect the fingerprint");

assert.equal(
  canonicalJsonStringify({ b: 1, a: 2 }),
  canonicalJsonStringify({ a: 2, b: 1 }),
  "canonicalJsonStringify must be independent of object key insertion order",
);
assert.notEqual(
  canonicalJsonStringify(["b", "a"]),
  canonicalJsonStringify(["a", "b"]),
  "canonicalJsonStringify must preserve array element order (order is semantically significant there)",
);

// --- 5. Missing required components fail closed. ---

for (const key of CF247_BINDING_REQUIRED_COMPONENT_KEYS) {
  const incomplete = baseComponents() as Partial<BindingComponents>;
  delete incomplete[key];
  assert.throws(
    () => assertBindingComponentsComplete(incomplete),
    /missing required component/,
    `missing ${key} must fail closed (throw), not silently produce a fingerprint`,
  );
  await assert.rejects(
    tuitionBenchmarkBindingFingerprint(incomplete as BindingComponents),
    /missing required component/,
    `computing a fingerprint over components missing ${key} must fail closed`,
  );
}

// Blank string / empty object components must also fail closed, not merely
// absent keys.
const blankString = baseComponents();
blankString.model_identifier = "   ";
assert.throws(() => assertBindingComponentsComplete(blankString), /missing required component/, "a blank model_identifier must fail closed");

const emptyValidators = baseComponents();
emptyValidators.deterministic_validators = {} as unknown as BindingComponents["deterministic_validators"];
assert.throws(() => assertBindingComponentsComplete(emptyValidators), /missing required component/, "an empty deterministic_validators object must fail closed");

// A complete descriptor never throws.
assert.doesNotThrow(() => assertBindingComponentsComplete(baseComponents()), "a fully-populated descriptor must not throw");

// --- 6. Canonical descriptor excludes secret values, Evidence bytes, per-case
// candidate values, and volatile metrics by construction (component shape). ---

const descriptor = JSON.parse(canonicalBindingDescriptor(baseComponents())) as { components: Record<string, unknown> };
const topLevelComponentKeys = Object.keys(descriptor.components);
for (const forbidden of ["secret_env_key", "evidence_id", "storage_path", "latency_ms", "cost_usd", "input_tokens", "output_tokens", "timestamp"]) {
  assert.ok(!topLevelComponentKeys.includes(forbidden), `canonical descriptor components must never include a ${forbidden} field`);
}
// The descriptor's response_schema component legitimately mentions the field
// name "candidate_value" (it is part of the shared JSON schema shape), but no
// component may carry an actual per-case candidate value/payload.
assert.ok(
  !("provider_current_tuition" in descriptor.components) && !("fee_candidates" in descriptor.components) && !("candidate_context" in descriptor.components),
  "canonical descriptor must never carry a per-case candidate_context/candidate payload",
);

console.log("CF-247 tuition benchmark binding contract PASS");
