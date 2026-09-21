import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
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

// --- CF-247 Slice 3A2a: benchmark must import and use the shared response schema,
// with no duplicated local schema definition left behind. This is a deterministic
// source-text contract (no execution of the benchmark edge function itself), so it
// stays cheap and stable in PR CI.
const benchmarkSourcePath = fileURLToPath(
  new URL("../supabase/functions/layer3-cf245-tuition-benchmark/index.ts", import.meta.url),
);
const benchmarkSource = readFileSync(benchmarkSourcePath, "utf8");
const benchmarkImportMatch = benchmarkSource.match(
  /import\s*\{([^}]*)\}\s*from\s*["']\.\.\/_shared\/cf247-tuition-validation\.ts["']/,
);
assert.ok(
  benchmarkImportMatch,
  "benchmark must import from the shared validation module",
);
const benchmarkImportedNames = (benchmarkImportMatch?.[1] ?? "")
  .split(",")
  .map((name) => name.trim())
  .filter(Boolean);
assert.ok(
  benchmarkImportedNames.includes("CF247_TUITION_RESPONSE_SCHEMA"),
  "benchmark must import CF247_TUITION_RESPONSE_SCHEMA from the shared validation module",
);
assert.match(
  benchmarkSource,
  /schema\s*:\s*CF247_TUITION_RESPONSE_SCHEMA\b/,
  "benchmark must pass the imported CF247_TUITION_RESPONSE_SCHEMA into its response_format.json_schema",
);
assert.doesNotMatch(
  benchmarkSource,
  /\bconst\s+schema\s*=/,
  "benchmark must not keep a duplicated local schema definition",
);

// --- CF-247 Slice 3A2b: benchmark must delegate positive acceptance authority to the
// shared validateProviderCurrentTuitionCandidate validator, build an explicit immutable
// candidate_context (sole target provider_current_tuition + identity_match:true) for
// every provider and synthetic call(), and pass that same context to the model via
// tuitionValidationPromptContext. No local sameCandidate acceptance authority may remain.

// 9. The benchmark must import both validateProviderCurrentTuitionCandidate and
// tuitionValidationPromptContext from the shared module (same import statement as the
// schema, or otherwise — only presence in the module-scoped import list is asserted).
assert.ok(
  benchmarkImportedNames.includes("validateProviderCurrentTuitionCandidate"),
  "benchmark must import validateProviderCurrentTuitionCandidate from the shared validation module",
);
assert.ok(
  benchmarkImportedNames.includes("tuitionValidationPromptContext"),
  "benchmark must import tuitionValidationPromptContext from the shared validation module",
);

// 10. No local sameCandidate acceptance authority may remain — positive acceptance is
// delegated entirely to the shared validator.
assert.doesNotMatch(
  benchmarkSource,
  /\bfunction\s+sameCandidate\b/,
  "benchmark must not retain a local sameCandidate function",
);
assert.doesNotMatch(
  benchmarkSource,
  /\bsameCandidate\s*\(/,
  "benchmark must not call a local sameCandidate anywhere",
);

// 11. validatePositive must invoke the shared validator to decide acceptance.
assert.match(
  benchmarkSource,
  /validateProviderCurrentTuitionCandidate\s*\(/,
  "benchmark must invoke the shared validateProviderCurrentTuitionCandidate validator",
);

// 12. The model prompt must be built via the shared tuitionValidationPromptContext,
// not a raw JSON.stringify of the bare candidate.
assert.match(
  benchmarkSource,
  /tuitionValidationPromptContext\s*\(/,
  "benchmark must build the model prompt context via the shared tuitionValidationPromptContext",
);

// 13. Every provider and synthetic call() site must construct an explicit
// candidate_context whose sole positive target is provider_current_tuition, with
// identity_match:true, and any other fee only ever placed in fee_candidates.
const candidateContextSites = [
  ...benchmarkSource.matchAll(/candidateContext\s*=\s*Object\.freeze\(\{([^}]*)\}\)/g),
];
assert.equal(
  candidateContextSites.length,
  2,
  "exactly one provider-loop and one synthetic-loop candidate_context construction site is expected",
);
for (const [, body] of candidateContextSites) {
  assert.match(
    body,
    /provider_current_tuition\s*:/,
    "each candidate_context must set provider_current_tuition as the sole positive target",
  );
  assert.match(
    body,
    /fee_candidates\s*:/,
    "each candidate_context must carry fee_candidates as non-selectable context only",
  );
  assert.match(
    body,
    /identity_match\s*:\s*true\b/,
    "each candidate_context must assert identity_match:true",
  );
}

// 14. Both call() sites (provider loop and synthetic loop) must pass the same
// constructed candidateContext through as an explicit argument.
assert.match(
  benchmarkSource,
  /call\(profile,key,`governed-\$\{c\.provider_cricos\}-\$\{c\.course_cricos\}`,evidence,c\.candidate_payload,candidateContext\)/,
  "the provider-loop call() must be invoked with the explicit candidateContext",
);
assert.match(
  benchmarkSource,
  /call\(profile,key,c\.case,c\.text,c\.candidate,candidateContext\)/,
  "the synthetic-loop call() must be invoked with the explicit candidateContext",
);

// 15. Wrong-target and identity-false non-null results remain rejected by the shared
// validator even though the benchmark no longer holds any local acceptance authority.
const wrongTargetContext = {
  provider_current_tuition: { amount: 48160, currency_code: "AUD", basis: "annual", fee_year: 2026, audience: "international" },
  fee_candidates: [{ amount: 59000, currency_code: "AUD", basis: "annual", fee_year: 2026, audience: "international" }],
  identity_match: true,
};
assert.equal(
  validateProviderCurrentTuitionCandidate(
    { amount: 59000, currency_code: "AUD", basis: "annual", fee_year: 2026, audience: "international" },
    wrongTargetContext,
  ).valid,
  false,
  "a candidate matching only a competing fee_candidates entry (wrong target) must remain rejected",
);
assert.equal(
  validateProviderCurrentTuitionCandidate(
    { amount: 48160, currency_code: "AUD", basis: "annual", fee_year: 2026, audience: "international" },
    { ...wrongTargetContext, identity_match: false },
  ).valid,
  false,
  "a non-null result with identity_match:false must remain rejected even when it matches the sole target",
);

// --- CF-247 Slice 3A2c: the `ambiguous_multiple_equal_rank` synthetic null-control's
// Evidence must genuinely fail to support its own target (annual/2026 basis), so the
// null expected outcome is correct under single-target candidate-bound validation.
// A competing fee amount present in the same Evidence must never, on its own, be the
// reason an otherwise-supported target is expected to be null.

// 16. Extract the exact synthetic case entry and its Evidence text from source.
const ambiguousCaseMatch = benchmarkSource.match(
  /case:'ambiguous_multiple_equal_rank',candidate:(\{[^}]*\}),fee_candidates:(\[[^\]]*\]),text:'([^']*)'/,
);
assert.ok(ambiguousCaseMatch, "the ambiguous_multiple_equal_rank synthetic case must exist with candidate/fee_candidates/text fields");
const toObject = (jsLiteral: string) =>
  JSON.parse(jsLiteral.replace(/([{,])\s*([A-Za-z_][A-Za-z0-9_]*)\s*:/g, '$1"$2":').replace(/'/g, '"'));
const ambiguousTarget = toObject(ambiguousCaseMatch![1]);
const ambiguousFeeCandidates = toObject(ambiguousCaseMatch![2]);
const ambiguousEvidenceText = ambiguousCaseMatch![3];

// The target and competing fee retained as non-selectable context must be unchanged
// (exact amount/currency/basis/fee_year/audience), so only the Evidence text changed.
assert.deepEqual(
  ambiguousTarget,
  { amount: 56800, currency_code: "AUD", basis: "annual", fee_year: 2026, audience: "international" },
  "the ambiguous_multiple_equal_rank target must remain the exact AUD 56,800 annual/2026 candidate",
);
assert.deepEqual(
  ambiguousFeeCandidates,
  [{ amount: 59000, currency_code: "AUD", basis: "annual", fee_year: 2026, audience: "international" }],
  "the competing AUD 59,000 fee must be retained unchanged as non-selectable context",
);

// 17. The target's annual/2026 basis must be genuinely unsupported/conflicting in the
// Evidence text — i.e. the shared validator's own governed-target matching would not
// find explicit annual support for the target in this text (checked deterministically
// via the same signals evidenceDiagnostic uses: an annual-basis phrase must not appear
// adjacent to the target's own amount, or the target's stated year must not be the one
// the Evidence actually supports).
const ambiguousLower = ambiguousEvidenceText.toLowerCase();
const targetAmountIdx = ambiguousLower.indexOf("56,800");
assert.ok(targetAmountIdx >= 0, "the target amount must still appear in the Evidence text");
const targetWindow = ambiguousEvidenceText.slice(Math.max(0, targetAmountIdx - 200), targetAmountIdx + 200);
const annualBasisPhrase = /indicative\s+annual|annual\s+fee|per\s+year|per\s+annum|annual\s+tuition/i;
assert.ok(
  !annualBasisPhrase.test(targetWindow) || /per\s+semester/i.test(targetWindow),
  "the target's annual basis must be unsupported or conflicting near its own amount in the Evidence",
);
assert.match(
  ambiguousEvidenceText,
  /per\s+semester/i,
  "the Evidence must state a conflicting (non-annual) basis for the target amount",
);
assert.doesNotMatch(
  ambiguousEvidenceText,
  /56,800[^.]*\bper\s+year\b/i,
  "the target amount must not be explicitly stated as per year anywhere in the Evidence",
);

// 18. A competing fee amount being present must never, by itself, be why the target is
// expected null: prove that with Evidence genuinely supporting the target (annual/2026,
// no conflict) plus the same competing fee present, the shared validator still accepts
// the target — i.e. only the target's own unsupported/conflicting basis (not the mere
// presence of a competing fee) determines the null outcome.
const supportedContext = {
  provider_current_tuition: ambiguousTarget,
  fee_candidates: ambiguousFeeCandidates,
  identity_match: true,
};
assert.equal(
  validateProviderCurrentTuitionCandidate(ambiguousTarget, supportedContext).valid,
  true,
  "a competing fee_candidates entry must never invalidate an otherwise fully-supported, unchanged target",
);

// --- CF-247 Slice 3A2d: provider-corpus cases are independently admitted
// provider-current-tuition positive truth (layer3_cf245_tuition_benchmark_cases_service).
// The benchmark must score every provider case as a known positive with
// validatePositive against the shared candidate-bound validator/schema, and must
// never re-derive expected_outcome/validator choice from the evidenceDiagnostic
// keyword heuristic. Provider transport errors must be inconclusive/invalid, never
// scored valid:true, and must not be mislabeled as a semantic Layer 4 route.

// 19. The provider loop must not select between validatePositive/validateNull (or
// between 'resolve_candidate'/'safe_abstention_to_layer4') based on evidenceDiagnostic
// output. expectedOutcome for provider-corpus cases must be a fixed known-positive
// literal, not a ternary driven by the heuristic's support signals.
const providerLoopMatch = benchmarkSource.match(
  /const support=evidenceDiagnostic\(evidence,c\.candidate_payload\);([^]*?evidenceIds\.push\(String\(c\.evidence_id\)\)\})/,
);
assert.ok(providerLoopMatch, "the provider loop body must be present and match the expected shape");
const providerLoopBody = providerLoopMatch![1];
assert.doesNotMatch(
  providerLoopBody,
  /support\.amount_present/,
  "expected_outcome for provider-corpus cases must not branch on evidenceDiagnostic support signals",
);
assert.doesNotMatch(
  providerLoopBody,
  /safe_abstention_to_layer4/,
  "provider-corpus cases must never be routed to a null/abstention expected outcome",
);
assert.match(
  providerLoopBody,
  /expectedOutcome\s*=\s*['"]resolve_candidate['"]/,
  "provider-corpus cases must always expect resolve_candidate as independently admitted positive truth",
);

// 20. On a semantic (non-transport-error) result, the provider loop must call
// validatePositive with the parsed response, the candidateContext, and evidence —
// never validateNull — for provider-corpus cases.
assert.match(
  providerLoopBody,
  /validatePositive\(r\.parsed,candidateContext,evidence\)/,
  "provider-corpus cases must be scored with validatePositive(r.parsed,candidateContext,evidence)",
);
assert.doesNotMatch(
  providerLoopBody,
  /validateNull\(r\.parsed\)/,
  "provider-corpus cases must never be scored with validateNull",
);

// 21. evidenceDiagnostic may remain present as diagnostic metadata (evidence_support)
// but must not gate acceptance/validator choice for provider cases.
assert.match(
  providerLoopBody,
  /evidence_support\s*:\s*support/,
  "evidenceDiagnostic output may still be attached as diagnostic metadata",
);

// 22. Provider transport errors must never be scored valid:true, must be marked
// inconclusive, and must not be mislabeled as a semantic Layer 4 routing outcome
// (i.e. no 'technical_failure_to_layer4' expected_outcome literal for provider cases).
assert.doesNotMatch(
  providerLoopBody,
  /r\.error\s*\?\s*\{valid:true/,
  "a provider transport error must never be scored valid:true",
);
assert.doesNotMatch(
  providerLoopBody,
  /technical_failure_to_layer4/,
  "a provider transport error must not be mislabeled as a semantic Layer 4 route",
);
assert.match(
  providerLoopBody,
  /r\.error\s*\?\s*\{valid:false,inconclusive:true/,
  "a provider transport error must be scored valid:false with an explicit inconclusive flag",
);

// 23. Deterministic behavioral proof (no execution of the Deno edge function): given
// a known-positive candidate_context (mirroring a provider-corpus row), an unsupported
// or abstaining model response (candidate_value: null, or a materially different
// candidate) must fail validatePositive's contract-level gate — i.e. the shared
// validator must reject it — so a null-abstention against known-positive truth can
// never be accepted as a passing null control or as a positive.
const knownPositiveContext = {
  provider_current_tuition: { amount: 51200, currency_code: "AUD", basis: "annual", fee_year: 2026, audience: "international" },
  fee_candidates: [],
  identity_match: true,
};
assert.equal(
  validateProviderCurrentTuitionCandidate(null, knownPositiveContext).valid,
  true,
  "the shared validator alone treats null as a safe no-candidate result (defense in depth lives in validatePositive's positive_candidate_required gate, asserted below)",
);
// validatePositive (the benchmark's own gate, mirrored here since it is not exported)
// must require a non-null candidate_value; this is the same requirement enforced by
// the benchmark source (`if(!c||typeof c!=='object')e.push('positive_candidate_required')`).
assert.match(
  benchmarkSource,
  /if\(!c\|\|typeof c!=='object'\)e\.push\('positive_candidate_required'\)/,
  "validatePositive must require a non-null, object candidate_value — an abstaining/null response to a known-positive case must fail this gate",
);

// 24. A materially different (heuristic-missed-but-still-known-positive) Evidence
// phrasing must not itself change the correctness of the target candidate: the
// shared validator must still accept the exact unchanged target regardless of
// whether an annual-basis keyword happens to sit near the amount in the Evidence
// text (i.e. correctness is candidate-bound, not keyword-proximity-bound).
const heuristicMissedContext = {
  provider_current_tuition: { amount: 51200, currency_code: "AUD", basis: "annual", fee_year: 2026, audience: "international" },
  fee_candidates: [],
  identity_match: true,
};
assert.equal(
  validateProviderCurrentTuitionCandidate(
    { amount: 51200, currency_code: "AUD", basis: "annual", fee_year: 2026, audience: "international" },
    heuristicMissedContext,
  ).valid,
  true,
  "the exact unchanged known-positive target must validate regardless of Evidence keyword phrasing, since candidate-bound correctness does not depend on evidenceDiagnostic's keyword-proximity heuristic",
);

console.log("CF-247 candidate-bound tuition validation contract PASS");
