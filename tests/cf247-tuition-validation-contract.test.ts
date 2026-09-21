import { strict as assert } from "node:assert";
import {
  CF247_TUITION_CANDIDATE_VALIDATOR_CONTRACT_ID,
  CF247_TUITION_RESPONSE_SCHEMA,
  CF247_TUITION_RESPONSE_SCHEMA_CONTRACT_ID,
  governedTuitionCandidates,
  tuitionValidationPromptContext,
  validateProviderCurrentTuitionCandidate,
} from "../supabase/functions/_shared/cf247-tuition-validation.ts";

const exactContext = {
  provider_current_tuition: { amount: 48160, currency: "AUD", basis: "indicative_annual", year: 2026, audience: "international" },
  fee_candidates: [
    { amount: 48160, currency: "AUD", basis: "indicative_annual", year: 2026, audience: "international" },
    { amount: 96320, currency: "AUD", basis: "total_course", year: 2026, audience: "international" },
  ],
  fee_ambiguous: true,
  identity_match: true,
};

assert.equal(governedTuitionCandidates(exactContext).length, 2, "deduplicates governed candidates");
const promptContext = JSON.parse(tuitionValidationPromptContext(exactContext));
assert.equal(promptContext.provider_current_tuition_target.amount, 48160, "prompt identifies the sole positive target");
assert.deepEqual(promptContext.competing_fee_candidates.map((candidate: { amount: number }) => candidate.amount), [96320], "prompt excludes the target duplicate and labels only alternative fees as competing context");
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 48160, currency_code: "AUD", basis: "indicative_annual", fee_year: 2026, audience: "international" }, exactContext).valid, true);
assert.equal(validateProviderCurrentTuitionCandidate(null, exactContext).valid, true, "null remains a safe rejection/no-candidate result");
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 48160, currency: "AUD", basis: "annual", year: 2026, audience: "international" }, exactContext).valid, false, "basis strengthening is rejected when Layer 2 basis is already resolved");
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 48160, currency: "USD", basis: "indicative_annual", year: 2026, audience: "international" }, exactContext).valid, false, "currency conversion is rejected");
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 24080, currency: "AUD", basis: "indicative_annual", year: 2026, audience: "international" }, exactContext).valid, false, "invented/derived amount is rejected");
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 48160, currency: "AUD", basis: "indicative_annual", year: 2025, audience: "international" }, exactContext).valid, false, "year mutation is rejected");
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 48160, currency: "AUD", basis: "indicative_annual", year: 2026, audience: "domestic" }, exactContext).valid, false, "audience mutation is rejected");
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 48160, currency: "AUD", basis: "indicative_annual", year: 2026, audience: "international" }, null).valid, false, "missing Layer 2 candidate context fails closed");

const runtimeAmbiguousContext = {
  provider_current_tuition: {
    amount: 40500,
    currency_code: "AUD",
    basis: "annual_or_indicative_requires_validation",
    audience: "international",
  },
  fee_candidates: [],
  fee_ambiguous: false,
  identity_match: true,
};
const indicative = validateProviderCurrentTuitionCandidate({ amount: 40500, currency_code: "AUD", basis: "indicative_annual", fee_year: null, audience: "international" }, runtimeAmbiguousContext);
assert.equal(indicative.valid, true, "explicit ambiguous Layer 2 basis may resolve to indicative_annual");
assert.equal(indicative.basis_resolution, true);
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 40500, currency_code: "AUD", basis: "annual", fee_year: null, audience: "international" }, runtimeAmbiguousContext).valid, true, "explicit ambiguous Layer 2 basis may resolve to annual when Evidence supports it");
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 40500, currency_code: "AUD", basis: "total_course", fee_year: null, audience: "international" }, runtimeAmbiguousContext).valid, false, "ambiguous annual/indicative basis cannot expand to total-course basis");
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 40501, currency_code: "AUD", basis: "indicative_annual", fee_year: null, audience: "international" }, runtimeAmbiguousContext).valid, false, "basis resolution cannot change deterministic amount");

// --- CF-247 candidate-contract regressions ---

// 1. fee_candidates are competing context only; a candidate matching an alternative
// fee_candidates entry (not the provider_current_tuition target) must never be accepted.
assert.equal(
  validateProviderCurrentTuitionCandidate({ amount: 96320, currency: "AUD", basis: "total_course", year: 2026, audience: "international" }, exactContext).valid,
  false,
  "an alternative fee_candidates entry must never be accepted as a substitute for the sole provider_current_tuition target",
);

// 2. Non-null results fail closed unless identity_match === true.
const exactContextIdentityFalse = { ...exactContext, identity_match: false };
assert.equal(
  validateProviderCurrentTuitionCandidate({ amount: 48160, currency_code: "AUD", basis: "indicative_annual", fee_year: 2026, audience: "international" }, exactContextIdentityFalse).valid,
  false,
  "identity_match: false must fail closed for a non-null candidate",
);
const exactContextIdentityMissing: Record<string, unknown> = { ...exactContext };
delete exactContextIdentityMissing.identity_match;
assert.equal(
  validateProviderCurrentTuitionCandidate({ amount: 48160, currency_code: "AUD", basis: "indicative_annual", fee_year: 2026, audience: "international" }, exactContextIdentityMissing).valid,
  false,
  "missing identity_match must fail closed for a non-null candidate",
);
assert.equal(
  validateProviderCurrentTuitionCandidate(null, exactContextIdentityFalse).valid,
  true,
  "null abstention remains valid even when identity_match is false",
);

// 3. Target audience missing/blank fails, even when the returned candidate matches otherwise.
const targetAudienceMissing = {
  provider_current_tuition: { amount: 48160, currency: "AUD", basis: "indicative_annual", year: 2026 },
  fee_candidates: [],
  identity_match: true,
};
assert.equal(
  validateProviderCurrentTuitionCandidate({ amount: 48160, currency_code: "AUD", basis: "indicative_annual", fee_year: 2026, audience: "international" }, targetAudienceMissing).valid,
  false,
  "missing target audience must fail",
);
const targetAudienceBlank = {
  provider_current_tuition: { amount: 48160, currency: "AUD", basis: "indicative_annual", year: 2026, audience: "  " },
  fee_candidates: [],
  identity_match: true,
};
assert.equal(
  validateProviderCurrentTuitionCandidate({ amount: 48160, currency_code: "AUD", basis: "indicative_annual", fee_year: 2026, audience: "international" }, targetAudienceBlank).valid,
  false,
  "blank target audience must fail",
);

// 4. Returned candidate audience missing/blank fails, even against a valid international target.
assert.equal(
  validateProviderCurrentTuitionCandidate({ amount: 48160, currency_code: "AUD", basis: "indicative_annual", fee_year: 2026 }, exactContext).valid,
  false,
  "missing returned audience must fail",
);
assert.equal(
  validateProviderCurrentTuitionCandidate({ amount: 48160, currency_code: "AUD", basis: "indicative_annual", fee_year: 2026, audience: " " }, exactContext).valid,
  false,
  "blank returned audience must fail",
);

// 5. Missing candidate_context (undefined/null/empty) fails closed for a non-null candidate.
assert.equal(
  validateProviderCurrentTuitionCandidate({ amount: 48160, currency_code: "AUD", basis: "indicative_annual", fee_year: 2026, audience: "international" }, undefined).valid,
  false,
  "undefined candidate_context fails closed",
);
assert.equal(
  validateProviderCurrentTuitionCandidate({ amount: 48160, currency_code: "AUD", basis: "indicative_annual", fee_year: 2026, audience: "international" }, {}).valid,
  false,
  "empty candidate_context fails closed",
);

// 6. candidate_value: null remains a valid safe abstention, including when no positive
// target can be admitted (e.g. missing context, identity false, or blank target audience).
assert.equal(validateProviderCurrentTuitionCandidate(null, undefined).valid, true, "null abstention is valid with no context at all");
assert.equal(validateProviderCurrentTuitionCandidate(null, targetAudienceMissing).valid, true, "null abstention is valid when the target audience is missing");
assert.equal(validateProviderCurrentTuitionCandidate(null, targetAudienceBlank).valid, true, "null abstention is valid when the target audience is blank");

// --- CF-247 Slice 3A1: shared contract export regressions ---

// 7. The exported identifiers are nonblank, stable expected literals — callers must
// be able to assert they are using the same shared contract by exact value.
assert.equal(
  CF247_TUITION_CANDIDATE_VALIDATOR_CONTRACT_ID,
  "cf247-tuition-candidate-validator-v1",
  "candidate validator contract identifier must be the stable expected literal",
);
assert.equal(
  CF247_TUITION_RESPONSE_SCHEMA_CONTRACT_ID,
  "cf247-tuition-response-schema-v1",
  "response schema contract identifier must be the stable expected literal",
);
assert.ok(CF247_TUITION_CANDIDATE_VALIDATOR_CONTRACT_ID.trim().length > 0, "candidate validator contract identifier must be nonblank");
assert.ok(CF247_TUITION_RESPONSE_SCHEMA_CONTRACT_ID.trim().length > 0, "response schema contract identifier must be nonblank");

// 8. The exported response schema is strict: object, additionalProperties false,
// exactly the four required top-level fields, and candidate_value is null or the
// exact five-field tuition object (also additionalProperties false).
assert.equal(CF247_TUITION_RESPONSE_SCHEMA.type, "object", "response schema root must be an object");
assert.equal(CF247_TUITION_RESPONSE_SCHEMA.additionalProperties, false, "response schema must be strict (additionalProperties false)");
assert.deepEqual(
  [...CF247_TUITION_RESPONSE_SCHEMA.required].sort(),
  ["candidate_value", "confidence", "evidence_quotes", "rationale"].sort(),
  "response schema must require exactly candidate_value/confidence/rationale/evidence_quotes",
);

const candidateValueSchema = CF247_TUITION_RESPONSE_SCHEMA.properties.candidate_value;
assert.equal(candidateValueSchema.anyOf.length, 2, "candidate_value must accept exactly null or the tuition object shape");
assert.deepEqual(candidateValueSchema.anyOf[0], { type: "null" }, "candidate_value must allow null");
const candidateObjectSchema = candidateValueSchema.anyOf[1];
assert.equal(candidateObjectSchema.type, "object", "candidate_value object branch must be an object");
assert.equal(candidateObjectSchema.additionalProperties, false, "candidate_value object branch must be strict (additionalProperties false)");
assert.deepEqual(
  [...candidateObjectSchema.required].sort(),
  ["amount", "audience", "basis", "currency_code", "fee_year"].sort(),
  "candidate_value object branch must require exactly the five governed tuition fields",
);
assert.deepEqual(
  Object.keys(candidateObjectSchema.properties).sort(),
  ["amount", "audience", "basis", "currency_code", "fee_year"].sort(),
  "candidate_value object branch must expose exactly the five governed tuition fields",
);

const confidenceSchema = CF247_TUITION_RESPONSE_SCHEMA.properties.confidence;
assert.equal(confidenceSchema.type, "number", "confidence must be a number");
assert.equal(confidenceSchema.minimum, 0, "confidence must be bounded at minimum 0");
assert.equal(confidenceSchema.maximum, 1, "confidence must be bounded at maximum 1");

assert.equal(CF247_TUITION_RESPONSE_SCHEMA.properties.rationale.type, "string", "rationale must be a string");

const evidenceQuotesSchema = CF247_TUITION_RESPONSE_SCHEMA.properties.evidence_quotes;
assert.equal(evidenceQuotesSchema.type, "array", "evidence_quotes must be an array");
assert.equal(evidenceQuotesSchema.items.type, "string", "evidence_quotes items must be strings");

console.log("CF-247 candidate-bound tuition validation contract PASS");
