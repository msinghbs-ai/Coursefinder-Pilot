import { strict as assert } from "node:assert";
import { governedTuitionCandidates, validateProviderCurrentTuitionCandidate } from "../supabase/functions/_shared/cf247-tuition-validation.ts";

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

console.log("CF-247 candidate-bound tuition validation contract PASS");
