import { strict as assert } from "node:assert";
import { governedTuitionCandidates, validateProviderCurrentTuitionCandidate } from "../supabase/functions/_shared/cf247-tuition-validation.ts";

const context = {
  provider_current_tuition: { amount: 48160, currency: "AUD", basis: "indicative_annual", year: 2026 },
  fee_candidates: [
    { amount: 48160, currency: "AUD", basis: "indicative_annual", year: 2026 },
    { amount: 96320, currency: "AUD", basis: "total_course", year: 2026 },
  ],
  fee_ambiguous: true,
  identity_match: true,
};

assert.equal(governedTuitionCandidates(context).length, 2, "deduplicates governed candidates");
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 48160, currency: "AUD", basis: "indicative_annual", year: 2026 }, context).valid, true);
assert.equal(validateProviderCurrentTuitionCandidate(null, context).valid, true, "null remains a safe rejection/no-candidate result");
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 48160, currency: "AUD", basis: "annual", year: 2026 }, context).valid, false, "basis strengthening is rejected");
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 48160, currency: "USD", basis: "indicative_annual", year: 2026 }, context).valid, false, "currency conversion is rejected");
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 24080, currency: "AUD", basis: "indicative_annual", year: 2026 }, context).valid, false, "invented/derived amount is rejected");
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 48160, currency: "AUD", basis: "indicative_annual", year: 2025 }, context).valid, false, "year mutation is rejected");
assert.equal(validateProviderCurrentTuitionCandidate({ amount: 48160, currency: "AUD", basis: "indicative_annual", year: 2026 }, null).valid, false, "missing Layer 2 candidate context fails closed");

console.log("CF-247 candidate-bound tuition validation contract PASS");
